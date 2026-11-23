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

This repository is the **integrated scaffold**: UI shells for both
platforms, the shared Metal viewer, a host-proven Python reference
implementation of the command interpreter (47/47 tests passing over
real OCCT), and the C façade design the native session layer will
implement. The native C++ session interpreter and the expanded OCCT
device build are **not yet built** — see `INTEGRATION-NOTES.md` for
exactly what remains before a device build can succeed. Do not expect
the downloads below to produce a working CAD app until that work
lands; the workflows exist so the build is exercised from day one.

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
