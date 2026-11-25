// ============================================================================
// mc_additions.cpp — implementations for mc_additions.h, against OCCT
// directly (to be compiled INTO the CascadeKit façade TU set on device;
// on the host it is compiled against system/conda OCCT for proof only).
// The handle struct is façade-private in cascade-port (its _impl points
// to a TopoDS_Shape); this file therefore CANNOT be built standalone
// against the shipped occt_facade.cpp without access to that private
// definition — it is delivered as the exact code to add inside
// occt_facade.cpp, where _impl is visible. The two functions are marked
// with the section banner used there.
// ============================================================================
// ---- BEGIN: paste into Facade/occt_facade.cpp (after section 10) ----
//
// MCFacadeShape* mc_clone_shape(MCFacadeShape* s, int* err) {
//   if (!s || !s->_impl) { if (err) *err = MC_ERR_INVALID_ARG;
//     setError("mc_clone_shape: null shape"); return NULL; }
//   if (err) *err = MC_OK;
//   MCFacadeShape* out = new MCFacadeShape;
//   out->_impl = new TopoDS_Shape(*reinterpret_cast<TopoDS_Shape*>(s->_impl));
//   return out;
// }
//
// int mc_export_stl(MCFacadeShape* s, const char* path, int* err) {
//   if (!s || !s->_impl || !path) { if (err) *err = MC_ERR_INVALID_ARG;
//     setError("mc_export_stl: null argument"); return MC_ERR_INVALID_ARG; }
//   try {
//     const TopoDS_Shape& shape = *reinterpret_cast<TopoDS_Shape*>(s->_impl);
//     // v0.4.2: size-aware policy, same formula as ccgeom_mc.cpp's
//     // tessellationPolicy (bbox diagonal -> linear deflection,
//     // angular deflection 0.20 rad) — no longer the fixed 0.5 mm.
//     Bnd_Box bb; BRepBndLib::Add(shape, bb);
//     double x0 = 0, y0 = 0, z0 = 0, x1 = 0, y1 = 0, z1 = 0;
//     bb.Get(x0, y0, z0, x1, y1, z1);
//     const double diag = std::sqrt((x1 - x0) * (x1 - x0) +
//                                   (y1 - y0) * (y1 - y0) +
//                                   (z1 - z0) * (z1 - z0));
//     double lin = 0.004 * diag;
//     if (lin < 0.02) lin = 0.02;
//     if (lin > 0.5) lin = 0.5;
//     BRepMesh_IncrementalMesh mesher(shape, lin, Standard_False,
//                                     0.20, Standard_True);
//     (void)mesher;
//     StlAPI_Writer writer;
//     if (!writer.Write(shape, path)) {
//       if (err) *err = MC_ERR_OCCT;
//       setError("mc_export_stl: writer did not complete");
//       return MC_ERR_OCCT;
//     }
//   } catch (const std::exception& e) {
//     if (err) *err = MC_ERR_OCCT; setError(e.what()); return MC_ERR_OCCT;
//   }
//   if (err) *err = MC_OK;
//   return MC_OK;
// }
// ---- END paste block ----
// NOTE: setError() above stands for whatever the façade's internal
// last-error setter is named in occt_facade.cpp (mc_last_error()'s
// backing store). That name is internal to that TU and was not assumed
// beyond this note — the integrator renames the three call sites to the
// façade's actual helper when pasting. Everything else (types, writer
// calls, error codes) is literal.
//
// v0.4.2 adds a third function, mc_tessellate_ex, which is NOT
// reproduced in this paste block: its body is the pinned
// mc_tessellate body verbatim apart from the signature, the mesher's
// angle argument and the error labels, so the operative text lives
// in Core/native/ci/patch_cascade_port.py (which injects all three
// functions into the CI checkout). The declaration is in
// mc_additions.h.
