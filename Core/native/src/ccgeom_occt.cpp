// ============================================================================
// ccgeom_occt.cpp — Layer-1 backend: direct OCCT C++ implementation of
// ccgeom.h, in the cascade-port façade style (thin pass-through: translate
// arguments, call OCCT, translate back, catch every exception at the
// boundary; no geometry logic of its own).
//
// Version handling: written against APIs stable across OCCT 7.6 / 7.8 /
// 8.0.1. The two version-sensitive spots are guarded by OCC_VERSION_HEX:
//   * sub-shape maps: TopTools_IndexedMapOfShape (<= 7.x) vs
//     NCollection_IndexedMap<TopoDS_Shape, TopTools_ShapeMapHasher> (8.x)
//   * chamfer single-distance Add(dist, edge) exists in both.
//
// Host proof in this project links the system OCCT 7.6.3 (Debian
// libocct-*-dev). The device target is OCCT 8.0.1 via CascadeKit — see
// ccgeom_mc.cpp. No OCCT source is modified (LGPL 2.1 + exception).
// ============================================================================
#include "ccgeom.h"
#include <BRepAdaptor_Surface.hxx>
#include <BRepBuilderAPI_MakeVertex.hxx>
#include <BRepClass3d_SolidClassifier.hxx>
#include <BRepExtrema_DistShapeShape.hxx>
#include <BRepTools.hxx>
#include <TopExp_Explorer.hxx>
#include "ccsim_backend.h"


#include <cmath>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include <Standard_Version.hxx>
#include <Bnd_Box.hxx>
#include <BRepAlgoAPI_Common.hxx>
#include <BRepAlgoAPI_Cut.hxx>
#include <BRepAlgoAPI_Fuse.hxx>
#include <BRepBndLib.hxx>
#include <BRepBuilderAPI_MakeFace.hxx>
#include <BRepBuilderAPI_MakePolygon.hxx>
#include <BRepBuilderAPI_Transform.hxx>
#include <BRepFilletAPI_MakeChamfer.hxx>
#include <BRepFilletAPI_MakeFillet.hxx>
#include <BRepGProp.hxx>
#include <BRepMesh_IncrementalMesh.hxx>
#include <BRepOffsetAPI_MakePipe.hxx>
#include <BRepOffsetAPI_MakeThickSolid.hxx>
#include <BRepOffsetAPI_ThruSections.hxx>
#include <BRepPrimAPI_MakeBox.hxx>
#include <BRepPrimAPI_MakeCone.hxx>
#include <BRepPrimAPI_MakeCylinder.hxx>
#include <BRepPrimAPI_MakePrism.hxx>
#include <BRepPrimAPI_MakeRevol.hxx>
#include <BRepPrimAPI_MakeSphere.hxx>
#include <BRepPrimAPI_MakeTorus.hxx>
#include <NCollection_List.hxx>
#include <Precision.hxx>
#include <gp_Ax1.hxx>
#include <BRep_Tool.hxx>
#include <GProp_GProps.hxx>
#include <Poly_Triangulation.hxx>
#include <STEPControl_Writer.hxx>
#include <StlAPI_Writer.hxx>
#include <TopAbs_ShapeEnum.hxx>
#include <TopExp.hxx>
#include <TopLoc_Location.hxx>
#include <TopoDS.hxx>
#include <TopoDS_Shape.hxx>
#include <gp_Pnt.hxx>
#include <gp_Trsf.hxx>
#include <gp_Vec.hxx>

#if OCC_VERSION_HEX >= 0x080000
#include <NCollection_IndexedMap.hxx>
#include <TopTools_ShapeMapHasher.hxx>
typedef NCollection_IndexedMap<TopoDS_Shape, TopTools_ShapeMapHasher> CCIndexMap;
#else
#include <TopTools_IndexedMapOfShape.hxx>
typedef TopTools_IndexedMapOfShape CCIndexMap;
#endif

struct CCGeomShape {
  TopoDS_Shape shape;
};

static thread_local std::string g_lastError;

static int setErr(int* err, int code, const std::string& msg) {
  g_lastError = msg;
  if (err) *err = code;
  return code;
}

const char* ccgeom_last_error(void) { return g_lastError.c_str(); }

static CCGeomShape* wrap(const TopoDS_Shape& s, const char* op, int* err) {
  if (s.IsNull()) {
    setErr(err, CCGEOM_ERR_EMPTY, std::string(op) + " produced a null shape");
    return nullptr;
  }
  if (err) *err = CCGEOM_OK;
  return new CCGeomShape{s};
}

template <typename F>
static CCGeomShape* run(const char* op, int* err, F&& fn) {
  try {
    return wrap(fn(), op, err);
  } catch (const std::exception& e) {
    setErr(err, CCGEOM_ERR_OCCT, std::string(op) + ": " + e.what());
  } catch (...) {
    setErr(err, CCGEOM_ERR_OCCT, std::string(op) + ": unknown OCCT failure");
  }
  return nullptr;
}

CCGeomShape* ccgeom_clone(CCGeomShape* s) {
  if (!s) return nullptr;
  return new CCGeomShape{s->shape};  // TopoDS_Shape is a handle; shapes immutable
}
void ccgeom_free(CCGeomShape* s) { delete s; }
void ccgeom_free_buffer(void* p) { std::free(p); }

// ---------------------------------------------------------------- primitives
CCGeomShape* ccgeom_box(double w, double d, double h, int* err) {
  return run("box", err, [&] { return BRepPrimAPI_MakeBox(w, d, h).Shape(); });
}
CCGeomShape* ccgeom_cylinder(double r, double h, int* err) {
  return run("cylinder", err, [&] { return BRepPrimAPI_MakeCylinder(r, h).Shape(); });
}
CCGeomShape* ccgeom_sphere(double r, int* err) {
  return run("sphere", err, [&] { return BRepPrimAPI_MakeSphere(r).Shape(); });
}
CCGeomShape* ccgeom_cone(double r1, double r2, double h, int* err) {
  return run("cone", err, [&] { return BRepPrimAPI_MakeCone(r1, r2, h).Shape(); });
}
CCGeomShape* ccgeom_torus(double ringR, double tubeR, int* err) {
  return run("torus", err, [&] { return BRepPrimAPI_MakeTorus(ringR, tubeR).Shape(); });
}

CCGeomShape* ccgeom_prism(const double* xy, int n, double dist, int* err) {
  if (!xy || n < 3) { setErr(err, CCGEOM_ERR_INVALID_ARG, "prism: profile needs >= 3 points"); return nullptr; }
  return run("extrude", err, [&] {
    BRepBuilderAPI_MakePolygon poly;
    for (int i = 0; i < n; ++i) poly.Add(gp_Pnt(xy[2 * i], xy[2 * i + 1], 0.0));
    poly.Close();
    if (!poly.IsDone()) throw std::runtime_error("polygon builder did not finish");
    TopoDS_Face face = BRepBuilderAPI_MakeFace(poly.Wire()).Face();
    return BRepPrimAPI_MakePrism(face, gp_Vec(0.0, 0.0, dist)).Shape();
  });
}

// ---- v0.4.0: revolve / loft / sweep / shell (host OCCT backend) --------------
// These mirror the cascade-port façade's mc_revolve / mc_loft /
// mc_sweep / mc_shell semantics exactly (same OCCT builders, same
// conventions), so a command proven here means the same thing on
// the device backend; the per-command matrix proves it there too.
static TopoDS_Face polygonFaceAt(const double* xy, int n, double z) {
  BRepBuilderAPI_MakePolygon poly;
  for (int i = 0; i < n; ++i) poly.Add(gp_Pnt(xy[2 * i], xy[2 * i + 1], z));
  poly.Close();
  if (!poly.IsDone()) throw std::runtime_error("polygon builder did not finish");
  return BRepBuilderAPI_MakeFace(poly.Wire()).Face();
}

CCGeomShape* ccgeom_revolve(const double* xy, int n, double angleDeg, int* err) {
  if (!xy || n < 3) { setErr(err, CCGEOM_ERR_INVALID_ARG, "revolve: profile needs >= 3 points"); return nullptr; }
  if (!(angleDeg > 0.0) || angleDeg > 360.0) { setErr(err, CCGEOM_ERR_INVALID_ARG, "revolve: angle must be in (0, 360]"); return nullptr; }
  return run("revolve", err, [&] {
    TopoDS_Face face = polygonFaceAt(xy, n, 0.0);
    gp_Ax1 axis(gp_Pnt(0.0, 0.0, 0.0), gp_Dir(0.0, 1.0, 0.0));
    BRepPrimAPI_MakeRevol revol(face, axis, angleDeg * M_PI / 180.0, Standard_True);
    revol.Build();
    if (!revol.IsDone()) throw std::runtime_error("revolve builder did not finish");
    return revol.Shape();
  });
}

CCGeomShape* ccgeom_loft(const double* const* profiles, const int* counts,
                         const double* heights, int profileCount,
                         int ruled, int* err) {
  if (!profiles || !counts || !heights || profileCount < 2) {
    setErr(err, CCGEOM_ERR_INVALID_ARG, "loft: needs >= 2 profiles"); return nullptr;
  }
  for (int i = 0; i < profileCount; ++i)
    if (!profiles[i] || counts[i] < 3) { setErr(err, CCGEOM_ERR_INVALID_ARG, "loft: every profile needs >= 3 points"); return nullptr; }
  return run("loft", err, [&] {
    BRepOffsetAPI_ThruSections maker(Standard_True,
                                     ruled ? Standard_True : Standard_False,
                                     Precision::Confusion());
    for (int i = 0; i < profileCount; ++i) {
      BRepBuilderAPI_MakePolygon poly;
      for (int j = 0; j < counts[i]; ++j)
        poly.Add(gp_Pnt(profiles[i][2 * j], profiles[i][2 * j + 1], heights[i]));
      poly.Close();
      if (!poly.IsDone()) throw std::runtime_error("polygon builder did not finish");
      maker.AddWire(poly.Wire());
    }
    maker.Build();
    if (!maker.IsDone()) throw std::runtime_error("loft builder did not finish");
    return maker.Shape();
  });
}

CCGeomShape* ccgeom_sweep(const double* xy, int n,
                          const double* pathPts, int pathCount, int* err) {
  if (!xy || n < 3) { setErr(err, CCGEOM_ERR_INVALID_ARG, "sweep: profile needs >= 3 points"); return nullptr; }
  if (!pathPts || pathCount < 2) { setErr(err, CCGEOM_ERR_INVALID_ARG, "sweep: path needs >= 2 points"); return nullptr; }
  return run("sweep", err, [&] {
    TopoDS_Face face = polygonFaceAt(xy, n, 0.0);
    BRepBuilderAPI_MakePolygon spine;
    for (int i = 0; i < pathCount; ++i)
      spine.Add(gp_Pnt(pathPts[3 * i], pathPts[3 * i + 1], pathPts[3 * i + 2]));
    if (!spine.IsDone()) throw std::runtime_error("spine builder did not finish");
    BRepOffsetAPI_MakePipe pipe(spine.Wire(), face);
    pipe.Build();
    if (!pipe.IsDone()) throw std::runtime_error("sweep builder did not finish");
    return pipe.Shape();
  });
}

CCGeomShape* ccgeom_shell(CCGeomShape* s, double thickness, int* err) {
  if (!s) { setErr(err, CCGEOM_ERR_INVALID_ARG, "shell: null shape"); return nullptr; }
  if (!(thickness > 0.0)) { setErr(err, CCGEOM_ERR_INVALID_ARG, "shell: thickness must be > 0"); return nullptr; }
  return run("shell", err, [&]() -> TopoDS_Shape {
    // Identical composition to the façade's mc_shell: the bare
    // inward offset is NOT the hollow part — the hollow part is
    // the offset solid cut from the original.
    BRepOffsetAPI_MakeThickSolid mk;
    NCollection_List<TopoDS_Shape> noOpenings;
    mk.MakeThickSolidByJoin(s->shape, noOpenings, -thickness,
                            Precision::Confusion());
    mk.Build();
    if (!mk.IsDone()) throw std::runtime_error("shell offset builder did not finish");
    BRepAlgoAPI_Cut cut(s->shape, mk.Shape());
    cut.Build();
    if (!cut.IsDone()) throw std::runtime_error("shell cut did not finish");
    return cut.Shape();
  });
}

// ---------------------------------------------------------------- booleans
static CCGeomShape* booleanOp(const char* op, CCGeomShape* a, CCGeomShape* b, int* err, int which) {
  if (!a || !b) { setErr(err, CCGEOM_ERR_INVALID_ARG, std::string(op) + ": null operand"); return nullptr; }
  return run(op, err, [&]() -> TopoDS_Shape {
    BRepAlgoAPI_BooleanOperation* builder = nullptr;
    BRepAlgoAPI_Fuse fuse(a->shape, b->shape);
    BRepAlgoAPI_Cut cut(a->shape, b->shape);
    BRepAlgoAPI_Common common(a->shape, b->shape);
    builder = (which == 0) ? static_cast<BRepAlgoAPI_BooleanOperation*>(&fuse)
              : (which == 1) ? static_cast<BRepAlgoAPI_BooleanOperation*>(&cut)
                             : static_cast<BRepAlgoAPI_BooleanOperation*>(&common);
    builder->Build();
    if (!builder->IsDone()) throw std::runtime_error("boolean builder did not finish");
    return builder->Shape();
  });
}
CCGeomShape* ccgeom_unite(CCGeomShape* a, CCGeomShape* b, int* err) { return booleanOp("union", a, b, err, 0); }
CCGeomShape* ccgeom_subtract(CCGeomShape* a, CCGeomShape* b, int* err) { return booleanOp("cut", a, b, err, 1); }
CCGeomShape* ccgeom_intersect(CCGeomShape* a, CCGeomShape* b, int* err) { return booleanOp("intersect", a, b, err, 2); }

// ---------------------------------------------------------------- finishing
static std::vector<TopoDS_Edge> pickEdges(const TopoDS_Shape& shape,
                                          const int* indices, int count,
                                          int* err, const char* op) {
  CCIndexMap map;
  TopExp::MapShapes(shape, TopAbs_EDGE, map);
  std::vector<TopoDS_Edge> out;
  if (!indices || count <= 0) {
    for (int i = 1; i <= map.Extent(); ++i) out.push_back(TopoDS::Edge(map.FindKey(i)));
    return out;
  }
  for (int i = 0; i < count; ++i) {
    int idx = indices[i];
    if (idx < 0 || idx >= map.Extent()) {
      setErr(err, CCGEOM_ERR_EDGE_INDEX,
             std::string(op) + ": edge index out of range");
      return {};
    }
    out.push_back(TopoDS::Edge(map.FindKey(idx + 1)));
  }
  return out;
}

CCGeomShape* ccgeom_fillet(CCGeomShape* s, double radius, const int* idx, int n, int* err) {
  if (!s) { setErr(err, CCGEOM_ERR_INVALID_ARG, "fillet: null shape"); return nullptr; }
  auto edges = pickEdges(s->shape, idx, n, err, "fillet");
  if (err && *err == CCGEOM_ERR_EDGE_INDEX) return nullptr;
  return run("fillet", err, [&] {
    BRepFilletAPI_MakeFillet maker(s->shape);
    for (auto& e : edges) maker.Add(radius, e);
    return maker.Shape();
  });
}
CCGeomShape* ccgeom_chamfer(CCGeomShape* s, double dist, const int* idx, int n, int* err) {
  if (!s) { setErr(err, CCGEOM_ERR_INVALID_ARG, "chamfer: null shape"); return nullptr; }
  auto edges = pickEdges(s->shape, idx, n, err, "chamfer");
  if (err && *err == CCGEOM_ERR_EDGE_INDEX) return nullptr;
  return run("chamfer", err, [&] {
    BRepFilletAPI_MakeChamfer maker(s->shape);
    for (auto& e : edges) maker.Add(dist, e);
    return maker.Shape();
  });
}

// ---------------------------------------------------------------- transform
CCGeomShape* ccgeom_transform(CCGeomShape* s, const double m[12], int* err) {
  if (!s || !m) { setErr(err, CCGEOM_ERR_INVALID_ARG, "transform: null argument"); return nullptr; }
  return run("transform", err, [&] {
    gp_Trsf t;
    t.SetValues(m[0], m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8], m[9], m[10], m[11]);
    return BRepBuilderAPI_Transform(s->shape, t, Standard_True).Shape();
  });
}

// ---------------------------------------------------------------- queries
double ccgeom_volume(CCGeomShape* s, int* err) {
  if (!s) { setErr(err, CCGEOM_ERR_INVALID_ARG, "volume: null shape"); return 0.0; }
  try {
    GProp_GProps props;
    BRepGProp::VolumeProperties(s->shape, props);
    if (err) *err = CCGEOM_OK;
    return props.Mass();
  } catch (const std::exception& e) { setErr(err, CCGEOM_ERR_OCCT, std::string("volume: ") + e.what()); return 0.0; }
}
double ccgeom_area(CCGeomShape* s, int* err) {
  if (!s) { setErr(err, CCGEOM_ERR_INVALID_ARG, "area: null shape"); return 0.0; }
  try {
    GProp_GProps props;
    BRepGProp::SurfaceProperties(s->shape, props);
    if (err) *err = CCGEOM_OK;
    return props.Mass();
  } catch (const std::exception& e) { setErr(err, CCGEOM_ERR_OCCT, std::string("area: ") + e.what()); return 0.0; }
}
int ccgeom_bbox(CCGeomShape* s, double out[6], int* err) {
  if (!s || !out) return setErr(err, CCGEOM_ERR_INVALID_ARG, "bbox: null argument");
  try {
    Bnd_Box box;
    BRepBndLib::AddOptimal(s->shape, box, Standard_False, Standard_False);
    box.Get(out[0], out[1], out[2], out[3], out[4], out[5]);
    if (err) *err = CCGEOM_OK;
    return CCGEOM_OK;
  } catch (const std::exception& e) { return setErr(err, CCGEOM_ERR_OCCT, std::string("bbox: ") + e.what()); }
}
int ccgeom_counts(CCGeomShape* s, int* faces, int* edges, int* err) {
  if (!s) return setErr(err, CCGEOM_ERR_INVALID_ARG, "counts: null shape");
  try {
    CCIndexMap fm, em;
    TopExp::MapShapes(s->shape, TopAbs_FACE, fm);
    TopExp::MapShapes(s->shape, TopAbs_EDGE, em);
    if (faces) *faces = fm.Extent();
    if (edges) *edges = em.Extent();
    if (err) *err = CCGEOM_OK;
    return CCGEOM_OK;
  } catch (const std::exception& e) { return setErr(err, CCGEOM_ERR_OCCT, std::string("counts: ") + e.what()); }
}

// ---------------------------------------------------------------- tessellation
int ccgeom_tessellate(CCGeomShape* s, double deflectionMM,
                      float** outVertices, int* outVertexCount,
                      int** outIndices, int* outIndexCount, int* err) {
  if (!s || !outVertices || !outIndices) return setErr(err, CCGEOM_ERR_INVALID_ARG, "tessellate: null argument");
  try {
    BRepMesh_IncrementalMesh mesher(s->shape, deflectionMM);
    (void)mesher;
    std::vector<float> verts;
    std::vector<int> idx;
    CCIndexMap fm;
    TopExp::MapShapes(s->shape, TopAbs_FACE, fm);
    for (int fi = 1; fi <= fm.Extent(); ++fi) {
      TopoDS_Face face = TopoDS::Face(fm.FindKey(fi));
      TopLoc_Location loc;
      Handle(Poly_Triangulation) tri = BRep_Tool::Triangulation(face, loc);
      if (tri.IsNull()) continue;
      gp_Trsf trsf = loc.Transformation();
      int base = (int)(verts.size() / 3);
#if OCC_VERSION_HEX >= 0x070600
      for (int i = 1; i <= tri->NbNodes(); ++i) {
        gp_Pnt p = tri->Node(i).Transformed(trsf);
        verts.push_back((float)p.X()); verts.push_back((float)p.Y()); verts.push_back((float)p.Z());
      }
      bool reversed = (face.Orientation() == TopAbs_REVERSED);
      for (int i = 1; i <= tri->NbTriangles(); ++i) {
        int a, b, c;
        tri->Triangle(i).Get(a, b, c);
        if (reversed) { idx.push_back(base + a - 1); idx.push_back(base + c - 1); idx.push_back(base + b - 1); }
        else { idx.push_back(base + a - 1); idx.push_back(base + b - 1); idx.push_back(base + c - 1); }
      }
#else
#error "OCCT >= 7.6 required"
#endif
    }
    float* vbuf = (float*)std::malloc((verts.empty() ? 1 : verts.size()) * sizeof(float));
    int* ibuf = (int*)std::malloc((idx.empty() ? 1 : idx.size()) * sizeof(int));
    if (!vbuf || !ibuf) { std::free(vbuf); std::free(ibuf); return setErr(err, CCGEOM_ERR_OCCT, "tessellate: out of memory"); }
    std::memcpy(vbuf, verts.data(), verts.size() * sizeof(float));
    std::memcpy(ibuf, idx.data(), idx.size() * sizeof(int));
    *outVertices = vbuf; *outIndices = ibuf;
    if (outVertexCount) *outVertexCount = (int)(verts.size() / 3);
    if (outIndexCount) *outIndexCount = (int)idx.size();
    if (err) *err = CCGEOM_OK;
    return CCGEOM_OK;
  } catch (const std::exception& e) { return setErr(err, CCGEOM_ERR_OCCT, std::string("tessellate: ") + e.what()); }
}

// ---------------------------------------------------------------- export
int ccgeom_export_step(CCGeomShape* s, const char* path, int* err) {
  if (!s || !path) return setErr(err, CCGEOM_ERR_INVALID_ARG, "export-step: null argument");
  try {
    STEPControl_Writer writer;
    writer.Transfer(s->shape, STEPControl_AsIs);
    IFSelect_ReturnStatus st = writer.Write(path);
    if (st != IFSelect_RetDone) return setErr(err, CCGEOM_ERR_OCCT, "export-step: writer did not complete");
    if (err) *err = CCGEOM_OK;
    return CCGEOM_OK;
  } catch (const std::exception& e) { return setErr(err, CCGEOM_ERR_OCCT, std::string("export-step: ") + e.what()); }
}
int ccgeom_export_stl(CCGeomShape* s, const char* path, int* err) {
  if (!s || !path) return setErr(err, CCGEOM_ERR_INVALID_ARG, "export-stl: null argument");
  try {
    BRepMesh_IncrementalMesh mesher(s->shape, 0.5);
    (void)mesher;
    StlAPI_Writer writer;
    if (!writer.Write(s->shape, path)) return setErr(err, CCGEOM_ERR_OCCT, "export-stl: writer did not complete");
    if (err) *err = CCGEOM_OK;
    return CCGEOM_OK;
  } catch (const std::exception& e) { return setErr(err, CCGEOM_ERR_OCCT, std::string("export-stl: ") + e.what()); }
}

void* ccgeom_native_handle(CCGeomShape*) { return nullptr; }  // TopoDS_Shape is not an MCFacadeShape

// ---- ccsim backend extension (merged from ccsim_backend_occt.cpp at
// v0.2 integration, per docs/SIM-INTEGRATION.md: same TU as CCGeomShape
// so the sim layer shares ccgeom_last_error() storage) ----

// (merged: the sim functions below use this TU's own setErr /
// ccgeom_last_error() channel — the standalone file's shim is gone.)

bool faceByIndex(CCGeomShape* s, int faceIndex, TopoDS_Face& out) {
  CCIndexMap map;
  TopExp::MapShapes(s->shape, TopAbs_FACE, map);
  if (faceIndex < 0 || faceIndex >= map.Extent()) return false;
  out = TopoDS::Face(map.FindKey(faceIndex + 1));
  return true;
}

int ccgeom_point_inside(CCGeomShape* s, double x, double y, double z,
                        int* err) {
  if (!s) return setErr(err, CCGEOM_ERR_INVALID_ARG, "point_inside: null shape");
  try {
    TopoDS_Solid solid;
    if (s->shape.ShapeType() == TopAbs_SOLID) {
      solid = TopoDS::Solid(s->shape);
    } else {
      TopExp_Explorer ex(s->shape, TopAbs_SOLID);
      if (!ex.More())
        return setErr(err, CCGEOM_ERR_EMPTY, "point_inside: shape has no solid");
      solid = TopoDS::Solid(ex.Current());
    }
    BRepClass3d_SolidClassifier cls(solid);
    cls.Perform(gp_Pnt(x, y, z), 1e-7);
    TopAbs_State st = cls.State();
    if (err) *err = CCGEOM_OK;
    return (st == TopAbs_IN || st == TopAbs_ON) ? 1 : 0;
  } catch (const std::exception& e) {
    return setErr(err, CCGEOM_ERR_OCCT, std::string("point_inside: ") + e.what());
  }
}

double ccgeom_point_face_distance(CCGeomShape* s, int faceIndex,
                                  double x, double y, double z, int* err) {
  if (!s) { setErr(err, CCGEOM_ERR_INVALID_ARG, "face distance: null shape"); return -1; }
  try {
    TopoDS_Face face;
    if (!faceByIndex(s, faceIndex, face)) {
      setErr(err, CCGEOM_ERR_INVALID_ARG, "face distance: face index out of range");
      return -1;
    }
    TopoDS_Vertex v = BRepBuilderAPI_MakeVertex(gp_Pnt(x, y, z)).Vertex();
    BRepExtrema_DistShapeShape dist(face, v);
    dist.Perform();
    if (!dist.IsDone()) {
      setErr(err, CCGEOM_ERR_OCCT, "face distance: BRepExtrema did not finish");
      return -1;
    }
    if (err) *err = CCGEOM_OK;
    return dist.Value();
  } catch (const std::exception& e) {
    setErr(err, CCGEOM_ERR_OCCT, std::string("face distance: ") + e.what());
    return -1;
  }
}

double ccgeom_face_area(CCGeomShape* s, int faceIndex, int* err) {
  if (!s) { setErr(err, CCGEOM_ERR_INVALID_ARG, "face area: null shape"); return -1; }
  try {
    TopoDS_Face face;
    if (!faceByIndex(s, faceIndex, face)) {
      setErr(err, CCGEOM_ERR_INVALID_ARG, "face area: face index out of range");
      return -1;
    }
    GProp_GProps props;
    BRepGProp::SurfaceProperties(face, props);
    if (err) *err = CCGEOM_OK;
    return props.Mass();
  } catch (const std::exception& e) {
    setErr(err, CCGEOM_ERR_OCCT, std::string("face area: ") + e.what());
    return -1;
  }
}

int ccgeom_face_point_normal(CCGeomShape* s, int faceIndex,
                             double pointOut[3], double normalOut[3],
                             int* err) {
  if (!s || !pointOut || !normalOut)
    return setErr(err, CCGEOM_ERR_INVALID_ARG, "face normal: null argument");
  try {
    TopoDS_Face face;
    if (!faceByIndex(s, faceIndex, face))
      return setErr(err, CCGEOM_ERR_INVALID_ARG, "face normal: face index out of range");
    BRepAdaptor_Surface ad(face);
    double u0, u1, v0, v1;
    BRepTools::UVBounds(face, u0, u1, v0, v1);
    gp_Pnt P;
    gp_Vec DU, DV;
    ad.D1((u0 + u1) / 2.0, (v0 + v1) / 2.0, P, DU, DV);
    gp_Vec N = DU.Crossed(DV);
    if (N.Magnitude() < 1e-12)
      return setErr(err, CCGEOM_ERR_OCCT, "face normal: degenerate surface point");
    N.Normalize();
    if (face.Orientation() == TopAbs_REVERSED) N.Reverse();
    pointOut[0] = P.X(); pointOut[1] = P.Y(); pointOut[2] = P.Z();
    normalOut[0] = N.X(); normalOut[1] = N.Y(); normalOut[2] = N.Z();
    if (err) *err = CCGEOM_OK;
    return CCGEOM_OK;
  } catch (const std::exception& e) {
    return setErr(err, CCGEOM_ERR_OCCT, std::string("face normal: ") + e.what());
  }
}

// ---- face ranges (v0.2 labels): same face iteration as tessellate ----
// Re-runs the identical TopExp face-map walk ccgeom_tessellate uses, so
// range f is exactly the slice tessellate appended for census face f.
int ccgeom_face_ranges(CCGeomShape* s, double deflectionMM,
                       CCGeomFaceRange** outRanges, int* outCount, int* err) {
  if (!s || !outRanges || !outCount) return setErr(err, CCGEOM_ERR_INVALID_ARG, "face_ranges: null argument");
  try {
    BRepMesh_IncrementalMesh mesher(s->shape, deflectionMM);
    (void)mesher;
    CCIndexMap fm;
    TopExp::MapShapes(s->shape, TopAbs_FACE, fm);
    std::vector<CCGeomFaceRange> ranges;
    int indexCursor = 0;
    for (int fi = 1; fi <= fm.Extent(); ++fi) {
      TopoDS_Face face = TopoDS::Face(fm.FindKey(fi));
      TopLoc_Location loc;
      Handle(Poly_Triangulation) tri = BRep_Tool::Triangulation(face, loc);
      int count = tri.IsNull() ? 0 : tri->NbTriangles() * 3;
      ranges.push_back(CCGeomFaceRange{fi - 1, indexCursor, count});
      indexCursor += count;
    }
    CCGeomFaceRange* buf = (CCGeomFaceRange*)std::malloc((ranges.empty() ? 1 : ranges.size()) * sizeof(CCGeomFaceRange));
    if (!buf) return setErr(err, CCGEOM_ERR_OCCT, "face_ranges: out of memory");
    std::memcpy(buf, ranges.data(), ranges.size() * sizeof(CCGeomFaceRange));
    *outRanges = buf; *outCount = (int)ranges.size();
    if (err) *err = CCGEOM_OK;
    return CCGEOM_OK;
  } catch (const std::exception& e) { return setErr(err, CCGEOM_ERR_OCCT, std::string("face_ranges: ") + e.what()); }
}

// Census edges in the SAME TopExp::MapShapes(TopAbs_EDGE) order
// pickEdges() selects from for fillet/chamfer — census index i is
// FindKey(i+1) here exactly as there, so the viewer's edge labels
// number the edges the `edges i,j,...` selector accepts.
int ccgeom_edge_list(CCGeomShape* s, CCGeomEdge** outEdges, int* outCount, int* err) {
  if (!s || !outEdges || !outCount) return setErr(err, CCGEOM_ERR_INVALID_ARG, "edge_list: null argument");
  try {
    CCIndexMap em;
    TopExp::MapShapes(s->shape, TopAbs_EDGE, em);
    std::vector<CCGeomEdge> edges;
    for (int i = 1; i <= em.Extent(); ++i) {
      TopoDS_Edge edge = TopoDS::Edge(em.FindKey(i));
      gp_Pnt a = BRep_Tool::Pnt(TopExp::FirstVertex(edge));
      gp_Pnt b = BRep_Tool::Pnt(TopExp::LastVertex(edge));
      CCGeomEdge e;
      e.edgeIndex = i - 1;
      e.start[0] = a.X(); e.start[1] = a.Y(); e.start[2] = a.Z();
      e.end[0] = b.X(); e.end[1] = b.Y(); e.end[2] = b.Z();
      edges.push_back(e);
    }
    CCGeomEdge* buf = (CCGeomEdge*)std::malloc((edges.empty() ? 1 : edges.size()) * sizeof(CCGeomEdge));
    if (!buf) return setErr(err, CCGEOM_ERR_OCCT, "edge_list: out of memory");
    std::memcpy(buf, edges.data(), edges.size() * sizeof(CCGeomEdge));
    *outEdges = buf; *outCount = (int)edges.size();
    if (err) *err = CCGEOM_OK;
    return CCGEOM_OK;
  } catch (const std::exception& e) { return setErr(err, CCGEOM_ERR_OCCT, std::string("edge_list: ") + e.what()); }
}
