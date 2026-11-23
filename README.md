# Cascade Console

A text-command 3D modelling app for **Mac and iPad**, powered by
**Open CASCADE Technology (OCCT)**. You type bare modelling commands
in a console —

```
box 40 30 20 as plate
cylinder 10 50 as shaft
fuse plate shaft as part
fillet part 2 as part
view part
export-step part bracket.step
```

— and a separate command opens the model in a Metal 3D view. The
command set is the full OCCT catalog: **251 commands** in
`docs/catalog/` (machine-readable: `docs/catalog/catalog.json`, also
bundled with the apps as their command source), each naming the real
OCCT class and toolkit that implements it. Commands whose toolkit is
not in a given build answer `NOT_IMPLEMENTED` — nothing is faked.
Per-command status: `COMMAND-COVERAGE.md`.

Modern-CAD extras around the modelling — simulation (linear statics,
thermal, modal, on an own solver over OCCT geometry; OCCT itself has
no FEM solver), materials, interference/clearance checks, print
checks, project files with a replayable command history — are
specified in `docs/EXTRAS.md`, with host-prototype numbers in
`Extras/results/`. Launch-stability gates are in `docs/QA.md`.

## Honest status

**v0.2 (2026-11-23): the native engine is linked into the iPad
build.** The C++ Layer-2 session interpreter (`Core/native/`, a port
of the host-proven Python reference — 90/90 host tests on real OCCT
8.0.1 and 7.6.3) is compiled in CI against CascadeKit (the
cascade-port `mc_*` façade over OCCT 8.0.1, fetched at a pinned
commit), and the iPad app is built with `CASCADE_NATIVE_ENGINE`
defined so `EngineFactory` returns the native engine. The CI gate
proves it from the shipped binary itself (native symbols must be
present in the executable). The 24 prototype-proven commands
(primitives, booleans, fillet/chamfer, transforms, measure, STEP/STL
export, undo/redo, sessions) run on device; the remaining catalog
commands still answer honestly (E1002/E5002) until their Layer-2
dispatch lands. **Simulation is included**: the `sim` command family
(voxel hex8 linear statics + steady-state thermal on the project's
own solver over OCCT geometry — 35/35 host checks) is registered in
the same interpreter. **Face-number labels**: `view labels faces on`
shows each face's census index (the number `@face <n>` accepts) as a
high-contrast chip at the face's centroid in the 3D view. After every successful command the app pulls the
session tessellation (`cc_view_data`) through the CCM1 contract into
the real Metal viewer. The **Mac app remains on the stub engine**
for now: its target still carries its own per-app engine types and
the Shared adaptation pass (INTEGRATION-NOTES resolution (f)) has
not landed — the exact remaining steps are recorded in
`Apps/Mac/Package.swift`. Device verdict (install + run on a real
iPad) is still the user's to give; see `docs/ENGINE-REPORT.md` and
`FIXLOG.md` for the full v0.2 record.

## Repository layout

| Path | What |
|---|---|
| `Apps/Mac/` | SwiftUI macOS app (SwiftPM, macOS 14+; Liquid Glass on macOS 26 with material fallback) |
| `Apps/iPad/` | SwiftUI iPad app (system picker **and** an in-app Documents browser — the in-app browser is the supported path when sideloading) |
| `Shared/` | One shared core for both apps: unified models, settings keys, engine protocol, command history, the Metal viewer (included once), and `Resources/catalog.json` |
| `Core/` | Command interpreter: Python reference prototype (`python/`, 47 tests), Layer-2 session façade design (`facade/cc_facade.h`) over the existing cascade-port Layer-1 `mc_*` OCCT façade |
| `docs/catalog/` | The 251-command OCCT catalog (Markdown + JSON) |
| `docs/ERROR-CODES.md` | The one unified error-code table |
| `docs/BUILD-PLAN-OCCT-TOOLKITS.md` | How the remaining OCCT toolkits get added to the build |
| `docs/QA.md`, `docs/EXTRAS.md` | Launch gates G1–G8; extras spec |
| `Extras/` | Simulation/analysis prototypes + their measured results |
| `UserGuide/` | User guide (Markdown + PDF + `build_pdf.py`) |
| `Licenses/` | OCCT licence texts (see Licensing) |
| `COMMAND-COVERAGE.md` | Every command → its implementation status |
| `INTEGRATION-NOTES.md` | How the seven workstreams were merged; every conflict and its resolution |

## Download & build

Builds are **unsigned** and run on GitHub's standard free runners
(`macos-26`) via GitHub Actions. There are no paid runners and no
subscriptions involved anywhere in this project.

### Mac

1. Open the repo's **Actions** tab → **Build Mac app** → **Run
   workflow**. (Pushes to the default branch also trigger it.)
2. When it finishes, download the `CascadeConsoleMac-unsigned`
   artifact and unzip it.
3. Run the app from the unzipped folder, or drag it to Applications.
   Because it is unsigned, the first launch needs a right-click →
   **Open** (Gatekeeper) — or build it yourself:
   `cd Apps/Mac && swift build` with Xcode 26 installed.
4. The Mac build must be the correct architecture for your machine;
   the CI artifact is Apple-silicon. On an Intel Mac, build from
   source with the command above (the code is architecture-neutral).

### iPad

1. Open the repo's **Actions** tab → **Build iPad IPA** → **Run
   workflow**.
2. Download the `CascadeConsole-unsigned-ipa` artifact and unzip it
   to get `CascadeConsole-unsigned.ipa`.
3. **Sideloading note:** the IPA is unsigned — install it with your
   usual sideloading tool (e.g. Signulous, AltStore, SideStore),
   which re-signs it with your own certificate. It cannot be
   installed directly from Files.
4. Because some sideloading certificates break the system document
   picker, the app ships its own **in-app file browser** over its
   Documents folder — use that for opening/saving/import/export when
   sideloaded; the system picker is a secondary path.

## Licensing

- **App code** (everything in this repo except `Licenses/` and the
  OCCT sources it builds against): © the author, **all rights
  reserved — viewing only**. No use, copying, modification, or
  redistribution without written permission. See `LICENSE`.
- **Open CASCADE Technology** is **LGPL 2.1 + the Open CASCADE
  exception**, © Open Cascade SAS. The licence texts ship in
  `Licenses/OCCT-LGPL-2.1.txt` and
  `Licenses/OCCT-LGPL-EXCEPTION.txt` and inside the apps. OCCT
  sources are used **unmodified**; if that ever changes, the modified
  files must stay LGPL and the change must be disclosed here.
- The OCCT build itself lives in the companion **cascade-port**
  project (OCCT 8.0.1 staged tree + Layer-1 façade); this app builds
  against it per `docs/BUILD-PLAN-OCCT-TOOLKITS.md`.
