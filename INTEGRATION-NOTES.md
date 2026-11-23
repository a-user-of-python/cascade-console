# Integration Notes — how the seven workstreams became one repo

Integration performed 2026-11-23. The original workstream folders
(`docs/catalog/`, `CorePrototype/`, `MacApp/`, `iOSApp/`, `Viewer/`,
`ExtrasQA/`, `UserGuide/` in the parent workspace) are untouched;
everything here is a copy, organised as:

```
repo/
  Apps/Mac/            <- MacApp/        Apps/iPad/   <- iOSApp/
  Shared/              <- unified core (new) + Viewer/ (included once)
  Core/                <- CorePrototype/
  docs/catalog/        <- docs/catalog/  docs/EXTRAS.md, docs/QA.md <- ExtrasQA/
  Extras/              <- ExtrasQA/prototypes + results
  UserGuide/           <- UserGuide/ (Markdown edited, PDF rebuilt)
  Licenses/            <- OCCT texts from the cascade-port OCCT tree
```

## Conflict resolutions

### (a) `history` name collision — RESOLVED

- **Canonical:** bare `history` = the **session command log**
  (numbered list of executed lines; `history run <n>`,
  `history save <file>`). This is what the user guide teaches, what
  the prototype implements (`cmd_history`), and what the façade's
  `cc_history_count()` counts (header comment amended to say so).
- The OCCT `BRepTools_History` query is renamed **`shape-history
  <name>`** everywhere: catalog Markdown + `catalog.json` (the entry
  formerly named `history`), this repo's coverage table, the core
  DESIGN.md alignment table, and a distinguishing note added to the
  user guide §3.2.
- The prototype gains `cmd_shape_history`, which answers
  **E5002 NOT_IMPLEMENTED** — the prototype records no
  BRepTools_History, so it fails loudly instead of pretending.
  In the C++ session it is facade-ready (TKTopAlgo is staged).

### (b) Export grammar — RESOLVED

- **Canonical:** the catalog forms — `export-step <shape> <file>`,
  `export-iges`, `export-brep`, `export-stl`, `export-obj`,
  `export-gltf`, `export-vrml`, `export-ply`, and the matching
  `import-*` forms. Argument order is shape-then-file.
- The prototype's compact forms (`export step <path> [name]`,
  leading-name primitives like `box b 10 20 30`, `union u a b`) are
  **aliases**: accepted, never taught. The prototype now also
  implements the canonical `cmd_export_step` / `cmd_export_stl`
  (shape-then-file) alongside the compact form.
- The user guide was the third spelling (`export step <name> <file>`)
  — all its export/import rows and examples were rewritten to the
  canonical hyphenated forms (see "User guide changes" below).

### (c) `view <name>` — RESOLVED

- **Canonical:** `view <name>` is an **app-layer** command: the app
  calls `cc_view_data(session, name, deflection)` on the core,
  converts the buffers to the viewer's CCM1/`MeshObject` form, and
  hands them to the Metal viewer (`Shared/Viewer/`). Bare `view`
  shows everything; `view-all`, `hide`, `show` are the catalog's
  app-layer companions.
- The prototype's `view <path.json> [name]` (write tessellation JSON
  to a file) is a **host-only debug variant**, documented as such in
  Core/DESIGN.md — it is not the app command.
- Viewer sub-commands (`view fit/top/iso/shaded/wireframe/edges/
  section/opacity/color/…`) are parsed by Agent 5's
  `ViewCommands.swift` — that parser is normative for sub-command
  spelling, and the user guide's view table was aligned to it
  (`view clip` → `view section`, `view colour` → `view color`,
  `view transparent` → `view opacity`, `view shade/wire` →
  `view shaded`/`view wireframe`/`view edges`).

### (d) Error codes — RESOLVED (one table)

Merged into **`docs/ERROR-CODES.md`**. Every failure prints the pair
`E#### / CC-<DOMAIN>-###`:

- Agent 2's numeric E-codes (1xxx language, 2xxx geometry, 3xxx
  files, 5xxx internal) are the machine-stable codes returned by
  `cc_execute()`.
- Agent 6's `CC-<domain>-###` codes name the domain for the user/log.
- Layer-1 `MC_*` codes stay internal and are translated at the
  Layer-2 boundary (MC_ERR_OCCT → E2002, MC_ERR_FEM_SINGULAR →
  E4003, …).
- **New at integration:** the E4xxx simulation range (E4001–E4004)
  for Agent 6's CC-SIM-001…004, which had no E-numbers; and
  **E5002 NOT_IMPLEMENTED** (= any `CC-*-000`), the mandatory answer
  for toolkit-missing commands. E5002 was added to the repo copy of
  `Core/python/cc/errors.py` and to the shared Swift stub engine.
- The user guide's CC-E001…E012 are documented as plain-language
  summaries mapped onto the table, not a fourth scheme (guide CC-E006
  is the boolean case of E2002; CC-E011 is not a distinct code).

### (e) ViewerBridge protocols — RESOLVED (Agent 5's wins)

- **Normative:** `Shared/Viewer/Swift/ViewerBridge.swift` — protocol
  `ViewerBridge` + `ViewerBridgeDelegate`, implemented by
  `CascadeRenderer`, exactly as Agent 5 specified. The viewer Swift
  + shaders are included **once**, under `Shared/Viewer/`.
- **Mac adapter:** `Apps/Mac/CascadeConsoleMac/ViewerBridge.swift`
  no longer defines a protocol named `ViewerBridge` (that was a
  direct name collision with Agent 5's). It keeps only
  `PlaceholderViewerBridge` (original call surface) and the
  placeholder view, with a TODO header.
- **iPad adapter:** `Apps/iPad/Sources/Viewer/ViewerBridge.swift`
  likewise drops its `CascadeViewerBridging` protocol definition and
  keeps `PlaceholderViewerBridge` with its original call surface.
- **Remaining adaptation (TODO, first device build):** Mac
  `AppState.swift` still types its viewer as the old protocol
  (`let viewer: ViewerBridge` + `PlaceholderViewerBridge()` default)
  — repoint it at `CascadeRenderer`; both apps' ContentViews still
  embed the placeholder views — replace with
  `CascadeViewerRepresentable(renderer:)`; iPad pick handling moves
  from `onObjectPicked` to `ViewerBridgeDelegate`. These are
  enumerated in the adapter files themselves. A full rewrite was not
  attempted here because neither scaffold has ever compiled — doing
  the swap blind, in the same pass as a first compile, would mix two
  unverifiable changes.

### (f) Shared Swift core unification — DONE (layout), adaptation TODOs noted

New canonical files under `Shared/`:

- `Shared/Models/SharedModels.swift` — unified `SceneObjectItem`
  (carries BOTH the Mac's kind/colorHex and the iPad's shapeID),
  `ConsoleLogEntry` (merges Mac `LogEntry` + iPad `LogEntry`),
  `CommandResult`, `CascadeFileKind`.
- `Shared/Settings/SettingsKeys.swift` — **one key scheme for both
  apps: the Mac `cc.*` strings**, extended with the iPad-only keys
  (showTimestamps, confirmBeforeClear, welcomeSeeded/Shown) and a
  default-export-format key. Neither app has shipped, so the iPad's
  `settings.*` strings are abandoned with no migration needed. The
  iPad's relative console-font *step* folds into the Mac's absolute
  `cc.consoleFontSize` points value (iPad Settings view converts on
  adaptation — TODO).
- `Shared/Engine/EngineProtocol.swift` — unified engine protocol:
  the iPad's **async** `CascadeEngine` form wins (the real session
  runs on a serial console queue; the Mac's sync form would block the
  main thread). `knownCommands` is sourced from
  `Shared/Resources/catalog.json`. The Mac form's `objects:`
  parameter is dropped — duplicate-name detection is the core's
  E1006, not the UI's. Includes the honest `StubEngine` (E5002 for
  unlinked commands).
- `Shared/Console/CommandHistory.swift` — the shared Up/Down +
  numbered-log implementation behind `history` (resolution (a)).
- `Shared/Resources/catalog.json` — the catalog, bundled as the
  apps' command source (byte-identical to `docs/catalog/catalog.json`).

The per-app model/engine/settings files are **kept** (the scaffolds'
internal references still compile against them in principle) but each
carries an INTEGRATION header marking it superseded by the Shared
counterpart. First device build adapts each AppState to the Shared
types and deletes the per-app copies — listed under "What remains".

## Toolkit gap — corrected at integration

Agent 1's gap list (TKFeat, TKHLR, TKDEIGES, TKDESTL, TKDEGLTF,
TKDEOBJ, TKDEVRML, TKDEPLY, TKRWMesh, TKExpress, TKBin/TKXml/TKStd)
was written against the pre-2026-10-29 cascade-port closure. The
staged tree actually holds **35 toolkits** (FreeCAD extension), so
most of the list is already satisfied. Genuinely missing:
**TKDEOBJ, TKDEVRML, TKDEPLY, TKXml branch** → only **7 commands**
are toolkit-missing. Full plan: `docs/BUILD-PLAN-OCCT-TOOLKITS.md`;
per-command truth: `COMMAND-COVERAGE.md`
(**24 implemented-in-prototype · 212 facade-ready · 7
toolkit-missing · 9 app-layer**, of 252 rows = 251 catalog +
`history`).

## User guide changes (Markdown edited, PDF rebuilt)

In `UserGuide/` (repo copy only): all `export step/iges/brep/stl/obj`
→ canonical `export-step/…`; the import row → `import-step` family;
§3.2 gained the `history` vs `shape-history` distinction; the view
table aligned to catalog + ViewCommands spellings (`view-all`,
`hide`/`show`, `view section`, `view color`, `view opacity`,
`view shaded`/`view wireframe`/`view edges`); §3.7 gained the
unified-code-pair + NOT_IMPLEMENTED note; `export-obj` notes its
TKDEOBJ dependency. PDF rebuilt with `build_pdf.py`:
**25 pages** (same as before), 53,821 bytes.

## Verification performed at integration

- Core prototype tests re-run against the **repo copy**: see the
  integration report (47 tests + the new alias/shape-history paths).
- Viewer tessellation verification re-run from the repo copy
  (`Shared/Viewer/Verification/verify_tessellation.py`).
- `catalog.json` JSON-validated (251 commands) in both locations,
  byte-identical.
- Whole `repo/` tree grepped for the user's real name: **zero**
  (public text uses "user" only). No paid GitHub runner labels
  anywhere (only `macos-26` and `ubuntu-latest`).

## What remains before a real device build can succeed (honest list)

1. **The C++ Layer-2 session interpreter does not exist yet.**
   `Core/facade/cc_facade.h` is a syntax-checked design sketch; the
   Python prototype is the executable reference. Porting it is the
   single biggest remaining work item.
2. **No Xcode project for the iPad app** (and no app-bundle target
   for the Mac — SwiftPM executable only). `build-ipa.yml` therefore
   fails at its xcodebuild step until a project is generated
   (cascade-port's `gen_project.py` pattern is the model).
   `build-mac.yml` (SwiftPM) and `host-tests.yml` are runnable today.
3. **The OCCT device build is cascade-port's**, not this repo's: the
   apps must link cascade-port's staged 35-toolkit tree + Layer-1
   façade, and the 4 missing toolkits (plan in
   `docs/BUILD-PLAN-OCCT-TOOLKITS.md`) must be staged there — with
   its host compile proof re-run — before `import-obj`,
   `export-obj`, `import-vrml`, `export-vrml`, `import-ply`,
   `export-ply`, `save-xml` can be anything but NOT_IMPLEMENTED.
4. **AppState adaptation to Shared types** (resolution (f)) and the
   **viewer swap** (resolution (e) TODOs) in both apps.
5. **Neither Swift scaffold has ever compiled.** First CI runs will
   surface SwiftUI nits (the workstream READMEs list the known risk
   areas: Liquid Glass SDK guards, fileExporter plumbing, layout
   APIs). QA gates G1–G8 (`docs/QA.md`) apply from the first green
   build; a build that fails the audit is not handed over.
6. **Simulation commands** (`sim …` in `docs/EXTRAS.md`) have
   host prototypes with true numbers but no Layer-2 commands yet;
   E4001–E4004 are reserved for them. Tet meshing remains
   NOT_IMPLEMENTED until TetGen (AGPL) is adopted or an own mesher
   lands.
7. **Intel Mac:** CI's `macos-26` runner is Apple-silicon; the user's
   2019 Intel Mac needs a source build (or a universal binary) —
   noted in the README download instructions.

## Decisions needed

- **Publishing:** the main agent publishes after review — nothing
  was pushed from integration. Repo name/visibility are the user's
  call (the tree is name-scrubbed and licence-ready either way).
- **TKXml branch scope:** stage TKXml alone or its full EXTERNLIB
  closure incl. TKStd/TKStdL — the closure computation at staging
  time decides; no user input needed unless XML persistence is to be
  dropped entirely (then `save-xml` stays NOT_IMPLEMENTED by design).
- **TetGen (AGPL v3)** for the tet simulation path: adopting it
  changes the app's licence surface (must ship AGPL text + label in
  About). Needs the user's explicit go-ahead, as in the FEBio
  project.
