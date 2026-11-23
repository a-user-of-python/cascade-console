"""Geometry backend: a thin wrapper over the OCCT 7.8 Python bindings
(``cadquery-ocp``), mirroring exactly the role the C++ façade plays on
Mac/iOS — this module translates calls and buffers, OCCT does the geometry.

Shapes are ``TopoDS_Shape`` handles treated as immutable: every operation
returns a NEW shape and never mutates its inputs, which is what makes the
interpreter's snapshot-based undo sound.
"""

import math

from .errors import (CCError, Codes, bad_expression, empty_result,
                     geometry_failed, invalid_param)

try:
    from OCP.Bnd import Bnd_Box
    from OCP.BRep import BRep_Tool
    from OCP.BRepAlgoAPI import (BRepAlgoAPI_Common, BRepAlgoAPI_Cut,
                                 BRepAlgoAPI_Fuse)
    from OCP.BRepBndLib import BRepBndLib
    from OCP.BRepBuilderAPI import (BRepBuilderAPI_MakeFace,
                                    BRepBuilderAPI_MakePolygon,
                                    BRepBuilderAPI_Transform)
    from OCP.BRepFilletAPI import (BRepFilletAPI_MakeChamfer,
                                   BRepFilletAPI_MakeFillet)
    from OCP.BRepGProp import BRepGProp
    from OCP.BRepMesh import BRepMesh_IncrementalMesh
    from OCP.BRepPrimAPI import (BRepPrimAPI_MakeBox, BRepPrimAPI_MakeCone,
                                 BRepPrimAPI_MakeCylinder,
                                 BRepPrimAPI_MakePrism, BRepPrimAPI_MakeSphere,
                                 BRepPrimAPI_MakeTorus)
    from OCP.GProp import GProp_GProps
    from OCP.STEPControl import STEPControl_AsIs, STEPControl_Writer
    from OCP.StlAPI import StlAPI_Writer
    from OCP.TopAbs import TopAbs_EDGE, TopAbs_FACE
    from OCP.TopExp import TopExp
    from OCP.TopLoc import TopLoc_Location
    from OCP.TopTools import TopTools_IndexedMapOfShape
    from OCP.TopoDS import TopoDS
    from OCP.gp import gp_Ax1, gp_Dir, gp_Pnt, gp_Trsf, gp_Vec
except ImportError as exc:  # pragma: no cover - environment problem
    raise CCError(Codes.INTERNAL, "INTERNAL",
                  f"Open CASCADE bindings (cadquery-ocp) not importable: {exc}")


def _check_positive(what, value):
    if not (value > 0):
        raise invalid_param(f"{what} must be greater than zero (got {value}).")


def _run(op, fn):
    """Run an OCCT builder, converting any failure into a structured error."""
    try:
        shape = fn()
    except CCError:
        raise
    except Exception as exc:  # OCCT raises generic RuntimeError subclasses
        raise geometry_failed(op, str(exc) or exc.__class__.__name__)
    if shape is None or shape.IsNull():
        raise empty_result(op)
    return shape


def _unique_subshapes(shape, kind):
    m = TopTools_IndexedMapOfShape()
    TopExp.MapShapes_s(shape, kind, m)
    return [m.FindKey(i) for i in range(1, m.Extent() + 1)]


class Geometry:
    """Stateless OCCT operations. All units are millimetres, angles degrees."""

    # -- primitives ---------------------------------------------------------
    def box(self, w, d, h):
        _check_positive("width", w); _check_positive("depth", d); _check_positive("height", h)
        return _run("box", lambda: BRepPrimAPI_MakeBox(w, d, h).Shape())

    def cylinder(self, r, h):
        _check_positive("radius", r); _check_positive("height", h)
        return _run("cylinder", lambda: BRepPrimAPI_MakeCylinder(r, h).Shape())

    def sphere(self, r):
        _check_positive("radius", r)
        return _run("sphere", lambda: BRepPrimAPI_MakeSphere(r).Shape())

    def cone(self, r1, r2, h):
        _check_positive("base radius", r1); _check_positive("height", h)
        if r2 < 0:
            raise invalid_param(f"top radius must be zero or greater (got {r2}).")
        if r1 == r2:
            raise invalid_param("cone with equal radii is a cylinder — use 'cylinder'.")
        return _run("cone", lambda: BRepPrimAPI_MakeCone(r1, r2, h).Shape())

    def torus(self, ring_r, tube_r):
        _check_positive("ring radius", ring_r); _check_positive("tube radius", tube_r)
        return _run("torus", lambda: BRepPrimAPI_MakeTorus(ring_r, tube_r).Shape())

    # -- profile / extrude ----------------------------------------------------
    def extrude(self, points, dist):
        """Extrude a closed XY polygon profile along +Z by ``dist``."""
        if len(points) < 3:
            raise CCError(Codes.BAD_PROFILE, "BAD_PROFILE",
                          "A profile needs at least 3 points.")
        _check_positive("extrude distance", dist)

        def build():
            poly = BRepBuilderAPI_MakePolygon()
            for x, y in points:
                poly.Add(gp_Pnt(x, y, 0.0))
            poly.Close()
            if not poly.IsDone():
                raise geometry_failed("profile", "polygon builder did not finish")
            face = BRepBuilderAPI_MakeFace(poly.Wire()).Face()
            return BRepPrimAPI_MakePrism(face, gp_Vec(0.0, 0.0, dist)).Shape()

        return _run("extrude", build)

    # -- booleans -------------------------------------------------------------
    def _boolean(self, op_name, builder_cls, a, b):
        def build():
            op = builder_cls(a, b)
            op.Build()
            if not op.IsDone():
                raise geometry_failed(op_name, "boolean builder did not finish")
            return op.Shape()
        shape = _run(op_name, build)
        if self.volume(shape) <= 1e-9 and op_name != "intersect":
            raise empty_result(op_name)
        return shape

    def union(self, a, b):
        return self._boolean("union", BRepAlgoAPI_Fuse, a, b)

    def cut(self, a, b):
        return self._boolean("cut", BRepAlgoAPI_Cut, a, b)

    def intersect(self, a, b):
        return self._boolean("intersect", BRepAlgoAPI_Common, a, b)

    # -- finishing ------------------------------------------------------------
    def _edges(self, shape, indices):
        edges = _unique_subshapes(shape, TopAbs_EDGE)
        if indices is None:
            return [TopoDS.Edge_s(e) for e in edges], len(edges)
        picked = []
        for idx in indices:
            if idx < 0 or idx >= len(edges):
                raise CCError(Codes.BAD_EDGE_INDEX, "BAD_EDGE_INDEX",
                              f"Edge index {idx} is out of range — the shape has "
                              f"{len(edges)} edges (0..{len(edges) - 1}).")
            picked.append(TopoDS.Edge_s(edges[idx]))
        return picked, len(edges)

    def fillet(self, shape, radius, indices=None):
        _check_positive("fillet radius", radius)
        edges, _ = self._edges(shape, indices)

        def build():
            maker = BRepFilletAPI_MakeFillet(shape)
            for e in edges:
                maker.Add(radius, e)
            return maker.Shape()
        return _run("fillet", build)

    def chamfer(self, shape, dist, indices=None):
        _check_positive("chamfer distance", dist)
        edges, _ = self._edges(shape, indices)

        def build():
            maker = BRepFilletAPI_MakeChamfer(shape)
            for e in edges:
                maker.Add(dist, e)
            return maker.Shape()
        return _run("chamfer", build)

    # -- transforms -------------------------------------------------------------
    def translate(self, shape, dx, dy, dz):
        trsf = gp_Trsf()
        trsf.SetTranslation(gp_Vec(dx, dy, dz))
        return _run("translate",
                    lambda: BRepBuilderAPI_Transform(shape, trsf, True).Shape())

    def rotate(self, shape, axis, angle_deg, centre=(0.0, 0.0, 0.0)):
        ax_len = math.sqrt(sum(c * c for c in axis))
        if ax_len < 1e-12:
            raise invalid_param("Rotation axis must not be the zero vector.")
        trsf = gp_Trsf()
        trsf.SetRotation(
            gp_Ax1(gp_Pnt(*centre), gp_Dir(axis[0], axis[1], axis[2])),
            math.radians(angle_deg))
        return _run("rotate",
                    lambda: BRepBuilderAPI_Transform(shape, trsf, True).Shape())

    # -- queries ---------------------------------------------------------------
    def volume(self, shape):
        props = GProp_GProps()
        BRepGProp.VolumeProperties_s(shape, props)
        return props.Mass()

    def area(self, shape):
        props = GProp_GProps()
        BRepGProp.SurfaceProperties_s(shape, props)
        return props.Mass()

    def bbox(self, shape):
        box = Bnd_Box()
        BRepBndLib.Add_s(shape, box)
        xmin, ymin, zmin, xmax, ymax, zmax = box.Get()
        return (xmin, ymin, zmin, xmax, ymax, zmax)

    def counts(self, shape):
        faces = _unique_subshapes(shape, TopAbs_FACE)
        edges = _unique_subshapes(shape, TopAbs_EDGE)
        return len(faces), len(edges)

    # -- view data (tessellation) ----------------------------------------------
    def tessellate(self, shape, deflection=0.5):
        """Return (vertices, indices) — flat float/int lists, triangles only.

        Vertices are duplicated per face (flat-shading friendly), matching
        what the Metal viewer wants: one draw call per object, positions in
        millimetres, indices 0-based into this object's vertex list.
        """
        _check_positive("tessellation deflection", deflection)
        BRepMesh_IncrementalMesh(shape, deflection)
        vertices, indices = [], []
        for face_shape in _unique_subshapes(shape, TopAbs_FACE):
            face = TopoDS.Face_s(face_shape)
            loc = TopLoc_Location()
            tri = BRep_Tool.Triangulation_s(face, loc)
            if tri is None:
                continue
            trsf = loc.Transformation()
            base = len(vertices) // 3
            for i in range(1, tri.NbNodes() + 1):
                p = tri.Node(i).Transformed(trsf)
                vertices.extend([p.X(), p.Y(), p.Z()])
            reversed_face = face.Orientation() == 1  # TopAbs_REVERSED == 1
            for i in range(1, tri.NbTriangles() + 1):
                a, b, c = tri.Triangle(i).Get()
                if reversed_face:
                    indices.extend([base + a - 1, base + c - 1, base + b - 1])
                else:
                    indices.extend([base + a - 1, base + b - 1, base + c - 1])
        return vertices, indices

    # -- export ------------------------------------------------------------------
    def export_step(self, shape, path):
        try:
            writer = STEPControl_Writer()
            writer.Transfer(shape, STEPControl_AsIs)
            status = writer.Write(path)
        except Exception as exc:
            raise CCError(Codes.EXPORT_FAILED, "EXPORT_FAILED",
                          f"STEP export to '{path}' failed: {exc}")
        if int(status) != 1:  # IFSelect_RetDone == 1
            raise CCError(Codes.EXPORT_FAILED, "EXPORT_FAILED",
                          f"STEP export to '{path}' did not complete (status {status}).")

    def export_stl(self, shape, path, deflection=0.5):
        try:
            BRepMesh_IncrementalMesh(shape, deflection)
            ok = StlAPI_Writer().Write(shape, path)
        except Exception as exc:
            raise CCError(Codes.EXPORT_FAILED, "EXPORT_FAILED",
                          f"STL export to '{path}' failed: {exc}")
        if not ok:
            raise CCError(Codes.EXPORT_FAILED, "EXPORT_FAILED",
                          f"STL export to '{path}' did not complete.")
