# Cascade Console — CorePrototype (Agent 2)

Working, host-verified core prototype for the text-command OCCT CAD
app: a command interpreter over real Open CASCADE geometry, plus the
façade API design the Mac/iPad Swift apps will call.

## Layout

| Path | What |
|---|---|
| `DESIGN.md` | Interpreter design, language, undo model, errors, catalog alignment table, open questions |
| `python/cc/geometry.py` | Thin OCCT backend (cadquery-ocp / OCCT 7.8) — primitives, booleans, fillet/chamfer, transforms, queries, tessellation, STEP/STL |
| `python/cc/interpreter.py` | Tokenizer/parser, named objects, $variables + expressions, profiles, undo/redo, scripts, log, all commands |
| `python/cc/errors.py` | Structured error codes (E1001–E5001) + plain-language messages |
| `python/cascade_console.py` | CLI: interactive, script-file, and `-c` modes |
| `facade/cc_facade.h` | Layer-2 session façade sketch for Swift (syntax-checked C11 + C++17) |
| `facade/FACADE.md` | How the two façade layers fit; command → `mc_*` mapping; cascade-port lessons |
| `scripts/demo.ccs` | Demo script (flanged plate with bore) — runs clean |
| `tests/test_core.py` | 47 automated tests, all passing |
| `TEST_REPORT.md` | Real measured numbers, export sizes, what's not verified |
| `output/` | Sample exports from the report run (STEP/STL/view JSON) |

## Run it

```sh
cd ~/workspace/cascade-console/CorePrototype
~/workspace/stl2step-venv/bin/python python/cascade_console.py            # interactive
~/workspace/stl2step-venv/bin/python python/cascade_console.py scripts/demo.ccs
~/workspace/stl2step-venv/bin/python -m unittest discover -s tests        # tests
```

## Commands (prototype subset; full 251-command target is Agent 1's catalog)

`set`, `box`, `cylinder`, `sphere`, `cone`, `torus`, `profile`,
`extrude`, `union`/`fuse`, `cut`, `intersect`/`common`, `fillet`,
`chamfer`, `translate`, `rotate`, `copy`, `duplicate`, `rename`,
`delete`, `clear`, `list`, `info`, `volume`/`measure-volume`,
`show-vars`, `undo`, `redo`, `history`, `export step|stl`, `view`,
`run`, `echo`, `help`. Both name forms work:
`box b 10 20 30` and `box 10 20 30 as b`.

Licence note: OCCT is LGPL 2.1 + the Open CASCADE exception; the
device build must ship the licence texts from the cascade-port tree
unmodified, exactly as that project does.
