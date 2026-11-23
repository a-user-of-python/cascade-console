# Cascade Console — core design (Agent 2: interpreter + façade)

## 1. Shape of the system

```
  Mac app (SwiftUI)            iPad app (SwiftUI)
        \                            /
         \   one line in,           /
          \  result/error out      /
           v                      v
        ┌───────────────────────────────────┐
        │  Layer 2 — console session (C++)  │  cc_facade.h
        │  parser, named objects, $vars,    │
        │  undo/redo, scripts, log, errors  │
        └──────────────┬────────────────────┘
                       │ shapes by name -> handles
        ┌──────────────▼────────────────────┐
        │  Layer 1 — geometry (C++, EXISTS) │  occt_facade.h (cascade-port)
        │  thin mc_* pass-through, no CAD   │
        │  logic of its own                 │
        └──────────────┬────────────────────┘
        ┌──────────────▼────────────────────┐
        │  Open CASCADE 8.0.1 toolkits      │
        └───────────────────────────────────┘
```

The Python package in `python/cc/` is the **executable reference** for
Layer 2: it implements the identical semantics against the OCCT 7.8
Python bindings (`cadquery-ocp`) so the design is host-proven today,
before the C++ port exists. Port algorithms, not Python.

Why the interpreter lives in C++ (Layer 2) and not in Swift: Mac and
iPad must behave *identically* — same parse, same error codes, same
undo rules. One C++ implementation behind a C ABI guarantees that;
two Swift reimplementations would drift. Swift owns only UI.

## 2. Language design

- One command per line; `#` comment; blank lines ignored; quoted
  strings are single tokens (shlex rules).
- **Names** are identifiers. Every shape-producing command names its
  result. Two dialects are accepted (see §5):
  compact `box b 10 20 30` and Agent 1 catalog form
  `box 10 20 30 as b`.
- **Numbers** are expressions: literals, `$var`, `pi`, `e`, and
  spaceless arithmetic (`2*$w+1`, `$h/2`, `(3+4)*2`). Evaluation is a
  whitelist AST walk (no `eval`), so a script file can never execute
  arbitrary code — important because scripts are user-shared files.
- **Points** are comma tuples: `x,y` (profiles) and `x,y,z`
  (placements, rotation centres).
- **Objects are immutable.** Every operation returns a new shape;
  inputs are never modified (true of OCCT builders and of the
  cascade-port façade). This single rule makes copy cheap (share the
  handle) and undo trivial (§3).
- **No silent overwrite.** Creating an existing name is E1006. The
  one exception is the catalog in-place idiom where `as <name>`
  reuses an *operand's* name (`fuse body boss as body`) — the result
  is computed from the old shapes first, then replaces the name.

## 3. Undo / redo

Snapshot semantics: before each mutating command, push a shallow
snapshot (object dict, profile dict, variable dict — shapes are
immutable handles, so a snapshot is three dict copies, O(names)).
`undo` moves the current state to the redo stack and restores the
top snapshot; `redo` is symmetric. A **failed command leaves no undo
step** (the snapshot is popped again in the error path) — this is
tested. `run` is not itself a step: each line inside a script is its
own undo step, matching what the user would expect from typing them.

On device, the same semantics sit on top of layer 1 handles; the
cascade-port project also has OCAF transactions available, but the
snapshot model is simpler and already proven — recommended.

## 4. Errors and logging

Every failure is a `CCError`: numeric code + stable name + plain
message (see `python/cc/errors.py` for the full table; ranges
1xxx language, 2xxx geometry, 3xxx files, 5xxx internal). OCCT
exceptions are caught at the geometry boundary and become E2002 with
the OCCT message preserved in the text. Script failures wrap the
inner error as E3004 and carry file + line number.

The `Log` records every executed line (info) and every failure
(error + code), as JSON-lines to a file when `CC_LOG` is set, else
in memory. The apps surface this as the console log panel; the codes
let support/bug reports be precise ("E2005" not "fillet broke").

## 5. Coordination with Agent 1's catalog (251 commands)

The prototype implements the **core subset** end-to-end (26 command
words incl. aliases); the catalog is the full target list. Alignment
done in this prototype:

| Catalog | Prototype | Status |
|---|---|---|
| `box 40 30 20 as plate` | both `as` form and `box plate 40 30 20` | ✅ both parse |
| `set wall = 2.5` | identical | ✅ |
| `fuse a b as a` / `common a b as x` | aliases `fuse`, `common`; operand-name reuse allowed | ✅ |
| `cut a minus b as x` | `minus` keyword accepted | ✅ |
| `fillet body radius… as body` | simplified: `fillet <src> <r> [edges i,j] as <name>` (numeric edge indices in the shared census space, not `edge(n)` selectors yet) | ⚠️ partial |
| `duplicate a as b`, `rename a as b` | ✅ catalog forms | ✅ |
| `show-vars`, `measure-volume` | ✅ aliases | ✅ |
| `translate/rotate <shape> …` (in place, optional copy) | prototype makes a named copy (`… as <name>` or leading name); in-place form not implemented | ⚠️ differs |
| `extrude prof1 along 0 0 1 distance 12 as pad` | simplified: `extrude <profile> <dist> as <name>`, XY profiles, +Z only | ⚠️ subset |
| `export-step <shape> <file>`, `export-stl …` | prototype: `export step <path> [name]` (verb-noun order differs) | ✅ RESOLVED at integration (b): catalog form is canonical and now implemented in the prototype (`cmd_export_step`/`cmd_export_stl`); compact form stays as an alias. |
| `view <name>` (opens viewer) | prototype: `view <path.json> [name]` writes the tessellation JSON the viewer consumes | ✅ RESOLVED at integration (c): app-side `view <name>` is canonical — it calls `cc_view_data` and hands buffers to the Metal viewer; the prototype's file-writing form is a host-only debug variant, not the app command. |
| `shape-history <name>` (BRepTools_History) | prototype `history` = command history | ✅ RESOLVED at integration (repo INTEGRATION-NOTES (a)): bare `history` = command log on both layers; the OCCT query is renamed `shape-history <name>` in the catalog. Prototype answers `shape-history` with E5002 NOT_IMPLEMENTED (it records no BRepTools_History). |
| remaining ~225 catalog commands | not in prototype | ⬜ Layer-1 `mc_*` functions already exist for most (prism/revolve/loft/sweep, shell, draft, chamfer2, thread, FEM, STEP XDE); the rest need the toolkit build gaps Agent 1 listed |

Recommendation: the C++ interpreter adopts the catalog grammar as
canonical; the compact leading-name form can stay as an accepted
shorthand since both are already proven unambiguous here.

## 6. Scripts

`.ccs`/`.txt`, one command per line, `#` comments. `run <file>` from
the console, or pass the file as the CLI argument. Execution stops
at the first failing line (no partial silent state — earlier lines
stand and are individually undoable), and the error names the line.

## 7. View data

`view` tessellates with OCCT's `BRepMesh_IncrementalMesh`
(deflection parameter, default 0.5 mm) and writes
`{format, version, units, objects:[{name, vertices, indices,
triangleCount, volume, bbox}]}` — flat arrays, vertices duplicated
per face for flat shading, every vertex verified inside its object's
bbox by test. This is exactly the buffer layout `cc_view_data` in
the façade sketch returns in memory for the Metal viewer agent.

## 8. Open design questions (for the parent / user)

1. ~~Canonical grammar: catalog-verbose vs compact~~ — RESOLVED at
   integration: catalog grammar is canonical, compact forms are
   aliases; the user guide teaches the catalog forms.
2. ~~`history` name collision (§5)~~ — RESOLVED at integration:
   `history` = command log, `shape-history <name>` = BRepTools_History.
3. Multi-body STEP export: prototype writes one file per object
   (`<base>_<name>.step`) when no name is given; layer 1 already has
   `mc_export_step_bodies`/XDE for a single multi-body file —
   prefer that on device.
4. Profiles are XY-polygons only in the prototype; the catalog's
   sketch entities (lines/circles/arcs on arbitrary planes) exist in
   layer 1 as `mc_face_from_sketch` — the C++ interpreter should
   expose them as `sketch` commands rather than extending `profile`.
