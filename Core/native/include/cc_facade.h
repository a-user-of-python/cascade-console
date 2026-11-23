// ============================================================================
// Cascade Console — session façade (DESIGN SKETCH, v0.1 prototype)
// ============================================================================
//
// Two layers, deliberately:
//
//   Layer 1 — GEOMETRY (already built, reused unchanged):
//   `occt_facade.h` from the cascade-port project (CascadeKit) — the
//   thin `mc_*` pass-through over Open CASCADE 8.0.1: mc_box,
//   mc_cylinder, mc_sphere, mc_cone, mc_torus, mc_prism / mc_revolve /
//   mc_loft / mc_sweep, mc_face_from_sketch + mc_prism_face, mc_unite /
//   mc_subtract / mc_intersect, mc_fillet / mc_chamfer / mc_chamfer2 /
//   mc_shell / mc_draft, mc_transform, mc_volume / mc_face_area /
//   mc_bbox / mc_contains, the section-8 census, mc_tessellate,
//   mc_import_step / mc_export_step (+ bodies / XDE variants), the
//   section-11 FEM calls and mc_thread.  Swift drives; OCCT does the
//   geometry; no C++ CAD logic.  Cascade Console changes NOTHING there.
//
//   Layer 2 — CONSOLE SESSION (this header, new):
//   The command interpreter itself, implemented ONCE in C++ so the
//   Mac and iPad apps share identical language behaviour instead of
//   drifting Swift ports.  A session owns: the named-shape registry
//   (name -> MCFacadeShape*), profiles, $variables, undo/redo
//   snapshot stacks, the structured log.  Swift owns only UI: it
//   sends one line in, renders one result / one error out, and asks
//   for view data when the user runs the view command.
//
//   The Python prototype in ../python/cc/ is the executable reference
//   for this layer's semantics: same grammar, same command names,
//   same error codes, same undo rule (snapshot before mutation, no
//   undo step for a failed command).  Port the algorithms, not the
//   Python.
//
// CONVENTIONS
// - Units millimetres, angles degrees at this layer (the mc_* layer
//   is radians where noted there — the interpreter converts).
// - Error codes are the SAME numbers as the prototype's cc/errors.py
//   (1xxx language, 2xxx geometry, 3xxx files, 5xxx internal;
//   5002 = NOT_IMPLEMENTED for commands whose toolkit is not in the
//   build — see repo docs/ERROR-CODES.md), plus
//   the mc_* layer's MCFacadeError stays internal to layer 1 and is
//   translated to 2002 GEOMETRY_FAILED at this boundary.
// - Ownership: strings returned via out-params are heap copies the
//   CALLER frees with cc_free_string().  View-data buffers are freed
//   with cc_free_view_data().  Shape handles never cross this layer —
//   Swift refers to shapes by NAME only.
// - Threading: a session is NOT thread-safe.  Apps call it from one
//   serial queue (the "console queue") and hop to the main actor for
//   UI.  Geometry calls can take seconds; never call from the main
//   thread.
// ============================================================================
#pragma once

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct CCSession CCSession;  // opaque

// ---- lifecycle -------------------------------------------------------------
CCSession* cc_session_create(void);
void       cc_session_destroy(CCSession* s);          // NULL-safe

// ---- execution ---------------------------------------------------------------
// Execute one command line.  On success returns 0 and (if outResult
// is non-NULL) stores a heap string with the human-readable result
// ("" for a blank/comment line).  On failure returns the numeric
// error code; cc_last_error_* describe it.
int  cc_execute(CCSession* s, const char* line, char** outResult);

// Execute a whole script file (.txt/.ccs).  Stops at the first
// failing line; cc_last_error_line() then gives its 1-based number.
int  cc_execute_script(CCSession* s, const char* path, char** outResult);

// ---- last error ----------------------------------------------------------------
int         cc_last_error_code(CCSession* s);       // e.g. 1006
const char* cc_last_error_name(CCSession* s);       // e.g. "DUPLICATE_NAME"
const char* cc_last_error_message(CCSession* s);    // plain language
int         cc_last_error_line(CCSession* s);       // script line, 0 if n/a

// ---- model inspection (for UI lists / inspector panels) -------------------------
int         cc_object_count(CCSession* s);
const char* cc_object_name(CCSession* s, int index);  // session-owned, do not free
int         cc_object_stats(CCSession* s, const char* name,
                            double* volume, double* area,
                            double bboxOut[6], int* faces, int* edges);

// Borrow the layer-1 handle for a named object, e.g. to hand to an
// mc_* function the interpreter does not wrap yet (the "every OCCT
// feature" escape hatch).  Borrowed: do NOT mc_free_shape() it, and
// it is invalidated by any mutating command.
struct MCFacadeShape;
struct MCFacadeShape* cc_borrow_shape(CCSession* s, const char* name);

// ---- view data ---------------------------------------------------------------------
// Tessellation for the 3D viewer, per object: positions are mm,
// indices 0-based, triangles only, vertices duplicated per face
// (flat shading).  Mirrors the prototype's `view` JSON exactly.
/// One face's slice of a CCViewData tessellation. faceIndex is the
/// 0-based census face index — the same number @face <n> references
/// in fillet / sim commands — and [indexStart, indexStart+indexCount)
/// is that face's slice of CCViewData.indices (element units, not
/// triangles). Every census face has a range (indexCount may be 0).
typedef struct CCFaceRange {
  int faceIndex;
  int indexStart;
  int indexCount;
} CCFaceRange;

typedef struct CCViewData {
  char*   name;          // heap copy
  float*  vertices;      // 3 * vertexCount
  int     vertexCount;
  int*    indices;       // 3 * triangleCount
  int     triangleCount;
  double  volume;
  double  bbox[6];
  CCFaceRange* faceRanges;  // heap array, faceRangeCount entries
  int     faceRangeCount;
} CCViewData;

int  cc_view_data(CCSession* s, const char* nameOrNull, double deflectionMM,
                  CCViewData** outObjects, int* outCount);
void cc_free_view_data(CCViewData* objects, int count);

// ---- history (SESSION COMMAND LOG — integration resolution (a)) ---------------------------
// cc_history_count counts executed command lines (the `history`
// command). The OCCT BRepTools_History query is a different command,
// `shape-history <name>`, served by cc_execute, not by these calls.
int cc_undo(CCSession* s);   // 0 ok, 1007 if nothing to undo
int cc_redo(CCSession* s);   // 0 ok, 1008 if nothing to redo
int cc_history_count(CCSession* s);

// ---- memory ----------------------------------------------------------------------------
void cc_free_string(char* p);  // NULL-safe

#ifdef __cplusplus
}
#endif
