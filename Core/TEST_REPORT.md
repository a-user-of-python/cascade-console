# Test report — Cascade Console core prototype

Environment: Linux host, Python 3.12 venv `~/workspace/stl2step-venv`,
`cadquery-ocp` (OCCT 7.8 bindings). All numbers below are real output
captured 2026-11-23 from the code in this folder.

## Automated tests

```
~/workspace/stl2step-venv/bin/python -m unittest discover -s tests
Ran 47 tests in 0.299s — OK
```

Coverage by class: PrimitiveTests (8), BooleanTests (5),
FinishAndTransformTests (7), ProfileTests (2), LanguageTests (11),
ScriptAndExportTests (6), CatalogFormTests (9 — Agent 1 `as`-form
grammar + aliases). Notable assertions:

- Analytic volumes: box 6000, cylinder π·5²·10, sphere 4/3π·5³,
  cone π·h/3·(R²+Rr+r²), torus 2π²·R·r² — all to ≥3 decimal places.
- Booleans on two 10×20×30 boxes offset by 5 in x: union 9000,
  cut 3000, intersect 3000; inputs provably unchanged afterwards.
- STEP round-trip: exported cylinder re-imported with a fresh
  `STEPControl_Reader` reads back π·5²·10 to 3 places.
- Undo: failed commands leave no undo step; undo restores variables
  as well as objects.
- View JSON: every tessellation vertex lies inside its object's
  bounding box; index count == 3 × triangle count.
- Error codes asserted individually: E1002, E1003, E1004, E1005,
  E1006, E1007, E2001, E2005, E3001, E3004 (+ failing line number).

Two test failures during development were the *tests'* arithmetic
(500 vs 5000 for a half-overlap of 10³ boxes), not the code — fixed
and re-run green. One API correction was needed while prototyping:
chamfer's single-distance form is `Add(dist, edge)` in OCP, and
tessellation requires casting explorer shapes to `TopoDS_Face`.

## Measured geometry table (deflection 0.5 mm for view data)

| object | volume mm³ | area mm² | faces | edges | view tris |
|---|---:|---:|---:|---:|---:|
| box 10×20×30 | 6000.0000 | 2200.000 | 6 | 12 | 12 |
| cylinder r5 h10 | 785.3982 | 471.239 | 3 | 3 | 100 |
| sphere r5 | 523.5988 | 314.159 | 1 | 3 | 306 |
| cone 6/3/9 | 593.7610 | 409.606 | 3 | 3 | 152 |
| torus 10/3 | 1776.5288 | 1184.353 | 1 | 2 | 1352 |
| union (overlap) | 9000.0000 | 2700.000 | 14 | 28 | 28 |
| cut | 3000.0000 | 1700.000 | 6 | 12 | 12 |
| intersect | 3000.0000 | 1700.000 | 6 | 12 | 12 |
| fillet r1 (all edges) | 5949.8348 | 2095.858 | 26 | 56 | 628 |
| chamfer d1 (all edges) | 5885.3333 | 2056.398 | 26 | 48 | 44 |
| extrude 40×20 ×10 | 8000.0000 | 2800.000 | 6 | 12 | 12 |
| translate / rotate of box | 6000.0000 | 2200.000 | 6 | 12 | 12 |

## Demo script (`scripts/demo.ccs`, runs clean, exit 0)

Flanged plate: profile-extruded base 60×40×10, boss cylinder,
through bore, fillet 1.5 on all edges. Final `part3`:
**volume 30937.339 mm³, area 8344.335 mm², 33 faces, 70 edges,
bbox (0,0,0)..(60,40,24)**.

## Exports (union solid `u`)

- STEP: `output/demo_u.step` — 33,693 bytes, header `ISO-10303-21`.
- STL: `output/demo_u.stl` — 7,100 bytes.
- View JSON (all 14 demo-session objects): `output/demo_view.json`
  — 138,797 bytes.

## CLI checks

- `-c "box b 10 20 30" "volume b"` → `b volume = 6000.000000 mm^3`.
- Unknown command → `[E1002 UNKNOWN_COMMAND] …`, process exit 234
  (1002 mod 256), as documented in the CLI header.

## Façade header check

`cc_facade.h` passes `cc -std=c11 -Wall -Wextra -fsyntax-only` and
the same as C++17 (one C-compatibility fix was needed during the
check: `struct MCFacadeShape*` in the borrow signature).

## Not verified

- Nothing on Mac/iPad (no device build exists yet — this is the
  host prototype the app agents build against).
- OCCT 8.0.1 numeric parity (host bindings are 7.8; see FACADE.md).
- Performance on large shapes; tessellation deflection is a single
  linear parameter (no angular deflection control yet).
