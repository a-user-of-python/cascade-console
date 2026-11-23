# ENGINE agent report — Cascade Console native Layer-2 engine

Date: 2026-11-23. Workdir: `~/workspace/cascade-console/enginework/`
(nothing pushed; the main agent reviews and pushes). No user name
appears in any delivered file (verified by grep).

## 1. What was delivered

- `NativeEngine/` — the native engine (see its README for layout):
  a C++17 Layer-2 session interpreter implementing the full
  `cc_facade.h` API (`cc_session_create/destroy`, `cc_execute`,
  `cc_execute_script`, `cc_last_error_code/name/message/line`,
  `cc_object_count/name/stats`, `cc_borrow_shape`, `cc_view_data` +
  `cc_free_view_data`, `cc_undo/cc_redo/cc_history_count`,
  `cc_free_string`), written as a line-by-line port of the Python
  reference interpreter — same grammar (compact AND catalog `as`
  forms), same aliases, same numeric error codes, same result
  strings, same undo rule (snapshot before mutation; failed commands
  leave no undo step; snapshots hold cloned handles).
- A Layer-1 backend interface (`ccgeom.h`, shaped exactly like the
  cascade-port `mc_*` calls the command set needs) with three
  implementations:
  - `ccgeom_occt.cpp` — direct OCCT C++, thin pass-through in the
    façade's style, version-guarded for OCCT 7.6 / 7.8 / 8.0.1
    (indexed-map type, chamfer Add form, `AddOptimal` bbox — the
    last one is cascade-port's own documented fix for `Add`'s
    inflated boxes, found by a failing bbox assertion here).
  - `ccgeom_mc.cpp` — the DEVICE backend: a pure adapter over the
    existing cascade-port `mc_*` functions. Every needed `mc_*`
    already exists except two, below.
  - `ccgeom_mock.cpp` — analytic test double for host logic tests.
    Exact for primitives, polygon extrudes, transforms, box-box
    booleans and all-edges box fillet/chamfer (closed forms); fails
    loudly with a "mock limitation" error outside that, and its
    tessellation is a documented bounding-box placeholder. It is
    never in a device target.
- `mc_additions.h/.cpp` — the two Layer-1 functions that DO NOT exist
  in cascade-port and had to be written in its style:
  1. `mc_clone_shape` — a second owned handle for an immutable shape
     (registry copy/duplicate + undo snapshots). Trivial
     representation-only wrap.
  2. `mc_export_stl` — `StlAPI_Writer` wrap (TKDESTL is already in
     the staged 35-toolkit tree; no façade wrap existed).
  Caveat, stated in the file: `mc_additions.cpp` is delivered as the
  exact code block to paste INTO `occt_facade.cpp`, because the
  handle's `_impl` is façade-private — it cannot compile standalone
  against the shipped header, and its internal last-error setter is
  named there as a placeholder the integrator renames (3 call sites).
  Everything else in it is literal.
- `repo-copy/` — my copy of the repo with the Swift wiring applied:
  - `Shared/Engine/NativeEngine.swift` — `NativeEngine` (serial
    console queue, `cc_execute` per command, structured error surface
    `E<code> / <NAME>`, `objectNames()` and `viewData()` helpers for
    AppState mirroring) plus `EngineFactory.makeEngine()`, the single
    switch point: NativeEngine when the build defines
    `CASCADE_NATIVE_ENGINE`, StubEngine otherwise (still honest
    E5002). StubEngine itself is untouched and remains the fallback.
  - `Apps/iPad/.../project.pbxproj` — NativeEngine.swift added to the
    target (file ref + build file + group + Sources phase, md5-style
    UUIDs like the rest of the file); the header TODO rewritten to
    state exactly what CI must add before the flag can be defined.
  - `Apps/Mac/Package.swift` — appended a precise, commented plan.
    The Mac target does NOT get the native target in this pass, for
    the structural reason the repo itself records: the Mac target
    carries its own per-app EngineProtocol/StubConsoleEngine types
    and the Shared adaptation pass (INTEGRATION-NOTES resolution (f))
    has not landed; adding NativeEngine now would duplicate types in
    one module and break the build.
  - `Core/native/` — the engine sources in-repo (same tree as
    `NativeEngine/` here).
  - `.github/workflows/build-native-engine.yml` — new workflow,
    standard free runners only: an ubuntu job that installs distro
    OCCT and runs the full host suite, and a macos-26 job that
    compile-checks `ccgeom_mc.cpp` against the real cascade-port
    façade header fetched from `a-user-of-python/cascade-ios`.

## 2. Command-by-command status vs the 24-command target

All 24 prototype-implemented catalog commands are implemented in the
C++ interpreter and exercised by the host harness on real OCCT:

| Catalog command | Status | Host evidence |
|---|---|---|
| set | implemented | variables/expressions test |
| show-vars | implemented | output format matches prototype |
| rename (+ compact form) | implemented | copy/rename/delete test |
| list | implemented | via scripts/inspection paths |
| delete | implemented | E1005 after delete |
| duplicate (`as` form) | implemented | catalog-form test block |
| undo / redo | implemented | incl. variables restore, failed-command rule, cc_undo/cc_redo API |
| box / cylinder / cone / sphere / torus | implemented | analytic volumes to ≥3 dp on real OCCT |
| extrude (with profile) | implemented | 40×20×10 → 8000 |
| fuse (alias union) | implemented | 9000 on overlapping boxes, both grammars |
| cut (incl. `minus` form) | implemented | 3000 |
| common (alias intersect) | implemented | 3000 |
| fillet | implemented | 5949.8348 == prototype value; E2005 on bad edge |
| chamfer | implemented | 5885.3333 == prototype value |
| translate / rotate | implemented | bbox/volume assertions; zero-axis E2001 |
| measure-volume (alias volume) | implemented | output string match |
| export-step / export-stl | implemented | STEP carries ISO-10303-21 header; STL non-trivial |
| shape-history | NOT_IMPLEMENTED by design | returns E5002, exactly as the prototype and the task specify |

Also implemented (prototype surface beyond the catalog-24, needed for
the apps to be coherent): help, echo, clear, copy, info, volume,
history (the command log — resolution (a)), export step|stl compact
form, view (view-JSON file, the file form of cc_view_data), run.

NOT implemented (unchanged from the prototype; they answer E1002
unknown-command from the interpreter, same as the Python reference —
212 façade-ready catalog commands still need their own Layer-2
dispatch, one command family at a time): everything else in the
catalog. This pass deliberately ported the proven 24, it did not
widen the set with unproven commands.

## 3. Host test results (real numbers, this machine)

`NativeEngine/build_host.sh`, run three times (conda OCCT 8.0.1,
system OCCT 7.6.3, and from the repo-copy layout):

- Mock backend: **84 pass, 0 fail, 2 skip** (skips are the two
  documented mock-export placeholders).
- Real OCCT backend: **90 pass, 0 fail, 0 skip** — on BOTH
  OCCT 8.0.1 (conda-forge build, the device's version) and
  OCCT 7.6.3 (Debian system). Included in the 90:
  - analytic primitive volumes (box 6000, cylinder π·5²·10, sphere,
    cone, torus) and boolean volumes 9000 / 3000 / 3000 with inputs
    provably unchanged;
  - fillet 5949.8348 and chamfer 5885.3333 — byte-for-byte the
    Python prototype's measured values (TEST_REPORT.md);
  - the full demo script (`Core/scripts/demo.ccs`) runs clean and
    `part3` volume = **30937.339 mm³**, matching the prototype's
    measured result to 0.01;
  - error codes E1002–E1007, E2001, E2005, E3001, E3004 (+ failing
    line number) each asserted;
  - `cc_view_data` returns tessellation for all objects;
    `cc_object_stats` bbox/faces/edges exact.
- Device adapter: `ccgeom_mc.cpp` **compiles** (object only) against
  the real cascade-port `occt_facade.h`. It was NOT linked — no
  CascadeKit library exists for this Linux host in a form this
  project owns (cascade-port's own Linux proof built one in its
  project, but reusing that artifact here was out of scope), so the
  mc-backend path is compile-proven, not run-proven. The interpreter
  logic it drives is run-proven through the other two backends,
  which share the identical interpreter binary code.

What could NOT be proven here, honestly:
- No Swift compilation (no swiftc/Xcode on this host): NativeEngine
  .swift is syntax-reviewed only. Two known-risk spots for the first
  CI compile: the incomplete-struct `CCSession` handle surfaces as
  `OpaquePointer` (handled in the code), and C array fields
  (`CCViewData.bbox`) import as tuples (handled explicitly).
- No device or CI link of CascadeKit + Layer 2 yet (next section).
- OCCT 8.0.1 was the conda-forge build, not cascade-port's staged
  source build; the wrapped APIs are the same ones cascade-port's
  MANIFEST proves against its 8.0.1 tree, but the staged-tree build
  itself was not re-run here.

## 4. How OCCT gets into this repo's build — decision

**CI fetch of the cascade-port repo (a-user-of-python/cascade-ios)
at a pinned commit, built there as CascadeKit — NOT vendoring, NOT a
submodule.** Justification: vendoring copies ~91 MB / 9,836 files of
OCCT sources into a second repo that must then be kept in sync with
cascade-port's prunes and proofs (they would drift; cascade-port is
the single source of truth and its MANIFEST is the proof record). A
submodule pins the same fetch but adds checkout friction to every
consumer (including the user's web-UI downloads) for no benefit over
an explicit checkout step. The new workflow's second job already
demonstrates the fetch pattern for the header; the link step extends
it: checkout cascade-ios at the pinned commit, run its
`gen_project.py`, `xcodebuild` the CascadeKit target once, cache the
result keyed by that commit, then build the apps against it.

## 5. What the next CI run should do / remaining path to a working device build

1. Run the new `build-native-engine.yml` (both jobs should pass as
   written; the ubuntu job reproduces this report's host numbers
   against distro OCCT 7.6.3).
2. Add the CascadeKit link step to `build-ipa.yml` / `build-mac.yml`
   per §4: fetch cascade-ios (pin the current HEAD; record the SHA
   in the workflow), build CascadeKit, compile
   `Core/native/src/cc_interpreter.cpp` + `ccgeom_mc.cpp` +
   the `mc_additions` block (pasted into the façade TU set in the
   cascade-ios checkout, or built as its own TU once the façade
   exposes its error setter) into a `libCascadeConsoleEngine.a`,
   link both libraries, add the module map to the target, define
   `CASCADE_NATIVE_ENGINE`, and switch the app entry point from
   `StubEngine()` to `EngineFactory.makeEngine()`.
3. First CI compile of NativeEngine.swift will likely need small
   fixes at the two risk spots named in §3 — budget one fix
   iteration, as v0.1 needed three.
4. Device verdict (the user's iPad, via Signulous) is the final
   gate: run the welcome script, check `info`/`volume` numbers
   against §3's values, and confirm `view` tessellation renders.
   Nothing in this report claims that step has happened.

Until step 2 lands, the shipped apps remain exactly as honest as
v0.1: StubEngine, E5002 for modelling commands. What changed is that
the engine those commands need now exists, is ported from the proven
prototype, and passes the prototype's own assertions on real OCCT —
the remaining work is link plumbing, not geometry.
