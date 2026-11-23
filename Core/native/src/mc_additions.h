// ============================================================================
// mc_additions.h — two Layer-1 functions the Cascade Console session
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
//                    Direct wrap of StlAPI_Writer after
//                    BRepMesh_IncrementalMesh at 0.5 mm deflection
//                    (the prototype's StlAPI default path).
// ============================================================================
#pragma once

#include "occt_facade.h"

#ifdef __cplusplus
extern "C" {
#endif

/// New owned handle wrapping the same (immutable) shape as `s`.
/// Release with mc_free_shape(). NULL on failure (*err set).
MCFacadeShape* mc_clone_shape(MCFacadeShape* s, int* err);

/// Write `s` to a binary STL file at `path` (UTF-8), tessellating at
/// 0.5 mm linear deflection first. Returns MC_OK on success.
int mc_export_stl(MCFacadeShape* s, const char* path, int* err);

#ifdef __cplusplus
}
#endif
