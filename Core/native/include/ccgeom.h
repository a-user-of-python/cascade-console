// ============================================================================
// ccgeom — Layer-1 geometry interface for the Cascade Console session
// interpreter (Layer 2). This is the interpreter's ONLY view of geometry.
//
// It mirrors, one-for-one, the mc_* functions of the cascade-port façade
// (Facade/occt_facade.h, "CascadeKit", OCCT 8.0.1) that the prototype's
// command set needs — same conventions: mm units, inputs never consumed,
// every operation returns a NEW owned handle, failures are error codes,
// never exceptions across the boundary.
//
// Three implementations exist:
//   src/ccgeom_occt.cpp — direct OCCT C++ (host proof; also usable on
//                         device if OCCT is ever linked without CascadeKit)
//   src/ccgeom_mc.cpp   — adapter over the cascade-port mc_* façade
//                         (the DEVICE build: CascadeKit does the geometry)
//   src/ccgeom_mock.cpp — analytic test double (host logic tests only;
//                         NEVER shipped — see its header comment)
//
// Two mc_* functions the interpreter needs do NOT exist in cascade-port
// today and are specified in src/mc_additions.h (same style, thin
// pass-throughs) for the mc backend:
//   mc_clone_shape — new owned handle for the same immutable shape
//                    (copy/duplicate + undo snapshots)
//   mc_export_stl  — StlAPI_Writer wrap (TKDESTL is already staged)
//
// Error codes (ccgeom layer only; the interpreter translates them):
// ============================================================================
#pragma once

#ifdef __cplusplus
extern "C" {
#endif

typedef struct CCGeomShape CCGeomShape;  // opaque, owned by caller

enum {
  CCGEOM_OK = 0,
  CCGEOM_ERR_INVALID_ARG = 1,  // bad parameter (mirrors MC_ERR_INVALID_ARG)
  CCGEOM_ERR_OCCT = 2,         // backend raised / operation did not finish
  CCGEOM_ERR_EMPTY = 3,        // operation produced a null shape
  CCGEOM_ERR_EDGE_INDEX = 4    // fillet/chamfer edge index out of range
};

/// Message for the most recent failure (backend-owned storage).
const char* ccgeom_last_error(void);

// ---- ownership -------------------------------------------------------------
CCGeomShape* ccgeom_clone(CCGeomShape* s);          // NULL on failure
void         ccgeom_free(CCGeomShape* s);           // NULL-safe
void         ccgeom_free_buffer(void* p);           // frees tessellation buffers

// ---- primitives (BRepPrimAPI_Make*) -----------------------------------------
CCGeomShape* ccgeom_box(double w, double d, double h, int* err);
CCGeomShape* ccgeom_cylinder(double r, double h, int* err);
CCGeomShape* ccgeom_sphere(double r, int* err);
CCGeomShape* ccgeom_cone(double r1, double r2, double h, int* err);
CCGeomShape* ccgeom_torus(double ringR, double tubeR, int* err);

// ---- profile extrude (polygon prism along +Z) --------------------------------
/// xy: n (x,y) pairs of a closed polygon (closed automatically).
CCGeomShape* ccgeom_prism(const double* xy, int n, double dist, int* err);

// ---- booleans (BRepAlgoAPI_Fuse / Cut / Common) -------------------------------
CCGeomShape* ccgeom_unite(CCGeomShape* a, CCGeomShape* b, int* err);
CCGeomShape* ccgeom_subtract(CCGeomShape* a, CCGeomShape* b, int* err);
CCGeomShape* ccgeom_intersect(CCGeomShape* a, CCGeomShape* b, int* err);

// ---- finishing ------------------------------------------------------------------
/// edgeIndices == NULL (or count <= 0) = all edges; indices are 0-based
/// in the shared census space (TopExp traversal order).
CCGeomShape* ccgeom_fillet(CCGeomShape* s, double radius,
                           const int* edgeIndices, int edgeCount, int* err);
CCGeomShape* ccgeom_chamfer(CCGeomShape* s, double dist,
                            const int* edgeIndices, int edgeCount, int* err);

// ---- transform --------------------------------------------------------------------
/// Row-major 3x4: [r00 r01 r02 tx, r10 r11 r12 ty, r20 r21 r22 tz].
CCGeomShape* ccgeom_transform(CCGeomShape* s, const double m[12], int* err);

// ---- queries ------------------------------------------------------------------------
double ccgeom_volume(CCGeomShape* s, int* err);
double ccgeom_area(CCGeomShape* s, int* err);
int    ccgeom_bbox(CCGeomShape* s, double out[6], int* err);
int    ccgeom_counts(CCGeomShape* s, int* faces, int* edges, int* err);

// ---- tessellation ---------------------------------------------------------------------
/// Flat-shading layout identical to the prototype's view JSON: vertices
/// duplicated per face, 0-based indices, triangles only. Buffers are
/// heap-allocated; free with ccgeom_free_buffer().
int ccgeom_tessellate(CCGeomShape* s, double deflectionMM,
                      float** outVertices, int* outVertexCount,
                      int** outIndices, int* outIndexCount, int* err);

// ---- export -----------------------------------------------------------------------------
int ccgeom_export_step(CCGeomShape* s, const char* path, int* err);
int ccgeom_export_stl(CCGeomShape* s, const char* path, int* err);

#ifdef __cplusplus
}
#endif
// (appended declaration — see cc_interpreter.cpp cc_borrow_shape)
#ifdef __cplusplus
extern "C" {
#endif
/// Backend native handle for cc_borrow_shape: the mc backend returns the
/// MCFacadeShape*; direct-OCCT and mock backends return NULL (their
/// native handle type is not an MCFacadeShape).
void* ccgeom_native_handle(CCGeomShape* s);
#ifdef __cplusplus
}
#endif
