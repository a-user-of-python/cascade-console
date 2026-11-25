// ============================================================================
// mc_additions.h — three Layer-1 functions the Cascade Console session
// interpreter needs that cascade-port's occt_facade.h does NOT have yet.
// Written in the façade's own style (thin pass-through, trailing int* err,
// caller owns returned handles, no geometry logic) so they can be dropped
// into Facade/occt_facade.h / occt_facade.cpp unchanged in spirit.
//
//   mc_clone_shape — the interpreter's registry, copy/duplicate and its
//                    snapshot undo all need a second OWNED handle for a
//                    shape that stays immutable. TopoDS_Shape is itself a
//                    handle, so this is representation only.
//   mc_export_stl  — export-stl is a prototype command; TKDESTL is
//                    already in the staged 35-toolkit tree (MANIFEST,
//                    FreeCAD extension) but no façade wrap exists.
//                    Direct wrap of StlAPI_Writer after a
//                    BRepMesh_IncrementalMesh tessellation. v0.4.2:
//                    the mesh uses the same size-aware policy as the
//                    viewer (linear deflection =
//                    clamp(0.004 * bbox diagonal, 0.02, 0.5) mm,
//                    angular deflection 0.20 rad) instead of the
//                    prototype's fixed 0.5 mm.
//   mc_tessellate_ex — (v0.4.2) mc_tessellate with a caller-chosen
//                    ANGULAR deflection. The pinned mc_tessellate
//                    hardcodes 0.5 rad, which leaves small curved
//                    faces (a 1 mm fillet) faceted no matter how fine
//                    the linear deflection is. The injected body is
//                    the pinned mc_tessellate body verbatim apart
//                    from the angle argument (see
//                    Core/native/ci/patch_cascade_port.py).
// ============================================================================
#pragma once

#include "occt_facade.h"

#ifdef __cplusplus
extern "C" {
#endif

/// New owned handle wrapping the same (immutable) shape as `s`.
/// Release with mc_free_shape(). NULL on failure (*err set).
MCFacadeShape* mc_clone_shape(MCFacadeShape* s, int* err);

/// Write `s` to a binary STL file at `path` (UTF-8), tessellating
/// with the size-aware viewer policy first (v0.4.2: linear
/// deflection clamp(0.004 * bbox diagonal, 0.02, 0.5) mm, angular
/// deflection 0.20 rad). Returns MC_OK on success.
int mc_export_stl(MCFacadeShape* s, const char* path, int* err);

/// mc_tessellate with a caller-chosen angular deflection (radians).
/// The pinned mc_tessellate hardcodes 0.5 rad, which facets small
/// curved faces (fillets) regardless of the linear deflection.
int mc_tessellate_ex(MCFacadeShape* s, double deflectionMM,
                     double angleRad, MCFacadeMesh* out, int* err);

#ifdef __cplusplus
}
#endif
