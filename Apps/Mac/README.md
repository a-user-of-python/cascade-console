# Cascade Console — Mac app (macOS half)

The macOS app. Since **v0.3.1** this is the real app, not a
scaffold: the native Open CASCADE engine, the Metal viewer and the
v0.3 UI, built **universal (arm64 + x86_64)** — it runs natively on
Intel Macs (the original target machine: a 2019 16" Intel MacBook
Pro) and on Apple-silicon Macs.

## How it is built

There is exactly **one app codebase**. `CascadeConsoleMac.xcodeproj`
compiles the same sources as the iPad target:

- `Apps/iPad/Sources/**` — the app (AppState, the v0.3 views:
  left Parts/History/Properties panel, centre viewport, right
  command panel with sliders/inputs, console sheet, files,
  settings),
- `Shared/**` — models, the parametric model layer
  (`Shared/Model/`), settings keys, the engine protocol +
  NativeEngine, and the Metal viewer (`Shared/Viewer/`).

Platform differences live behind `#if os(...)` in those shared
files (CascadeMetalView has full mouse input + an
NSViewRepresentable on macOS; ContentView always takes the regular
three-panel layout; the renderer's label chips were ported in
v0.3.1 — see FIXLOG). The old standalone SwiftPM scaffold that
lived here through v0.3.0 (its own stub engine and per-app types)
is **retired**: this project replaces it, per INTEGRATION-NOTES
resolution (f).

## The native engine on Mac

Exactly the iPad arrangement (see `.github/workflows/build-mac.yml`):

1. CI fetches the cascade-port (OCCT 8.0.1 subset + `mc_*` façade)
   at a pinned commit and injects the two `mc_additions` functions
   into the *checkout* (upstream + OCCT sources unmodified — LGPL).
2. CascadeKit is compiled with direct clang for **both**
   architectures (`arm64-apple-macos14.0`, `x86_64-apple-macos14.0`)
   and lipo'd into one universal `libCascadeKit.a`; the Layer-2
   interpreter (`cc_interpreter` + `ccgeom_mc` + sim) likewise.
3. The app is built with `CASCADE_NATIVE_ENGINE` defined, so
   `EngineFactory.makeEngine()` returns the native engine.
4. **Gate:** the shipped executable must contain both architectures
   and the native symbols (`_cc_execute`, `_cc_session_create`,
   `_mc_clone_shape`, `_mc_export_stl`) in **both** slices, plus
   `catalog.json`, `default.metallib` and both OCCT licence texts
   in the bundle. A build that silently fell back to the stub fails.
5. The x86_64 engine is **executed**, not just linked: a CI job
   builds the per-command matrix + view-data smoke for x86_64 and
   runs them under Rosetta 2, and a second job runs the same matrix
   natively on an Intel runner (`macos-15-intel`).

A plain local build of the project (no CI libraries) compiles the
stub configuration instead — `EngineFactory` returns StubEngine and
modelling commands answer E5002. That is the honest fallback for
source builds without the engine libraries; the shipped artifact
is always the CI build above.

## Install (for the user)

See `INSTALL.txt` (also shipped inside the download zip): drag to
Applications, first launch via right-click → **Open** (the build is
ad-hoc signed, not notarized; on macOS 15+ use System Settings →
Privacy & Security → **Open Anyway** if the dialog offers no Open
button). Files live in the app's Documents folder, via the in-app
Files panel.

## Notes / adaptations vs iPad

- Settings is the same toolbar sheet as on iPad (no separate
  macOS Settings scene yet).
- The app is not sandboxed (ad-hoc local build); it reads/writes
  its Documents folder directly. macOS may prompt for Documents
  access on first save/export — allow it.
- Minimum system: macOS 14. Liquid Glass styling engages on
  macOS 26 (`#available(iOS 26.0, macOS 26.0, *)` in the shared
  GlassStyle), with the material fallback below that.
