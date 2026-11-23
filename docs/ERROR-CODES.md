# Cascade Console — Unified Error Codes (INTEGRATION, resolution (d))

Three schemes arrived from the workstreams and are merged here into
ONE table. Every user-visible failure prints **both** forms:

```
ERROR E2002 / CC-GEOM-001  fillet failed inside Open CASCADE: <OCCT words>
```

- **E####** — the numeric code from Agent 2's prototype
  (`Core/python/cc/errors.py`), returned by `cc_execute()` in
  `Core/facade/cc_facade.h`. This is the machine-stable code scripts
  and tests compare against.
- **CC-&lt;DOMAIN&gt;-###** — Agent 6's app-layer code
  (`docs/QA.md` §1.2), which names the *domain* for the user and for
  the console log panel.
- **MC_** — the Layer-1 façade codes from cascade-port
  (`occt_facade.h`). Internal: they never reach the user alone; the
  Layer-2 boundary translates them (MC_ERR_OCCT → E2002, etc.) and the
  CC line may append the MC code in brackets, per QA §1.2.

Rules (from QA §1.2, unchanged): codes are never reused once shipped;
wording may improve, meaning may not; `CC-*-000` / E5002 =
NOT_IMPLEMENTED, used by any command whose OCCT toolkit is not in the
current build (see COMMAND-COVERAGE.md) so scripts fail loudly instead
of silently doing nothing. The user guide's CC-E001…CC-E012 table is a
plain-language *summary* of the common cases, not a fourth scheme —
each guide row maps to a row here (mapping in the last column).

## The one table

| E-code | Name | CC code | MC source | Meaning | Guide |
|---|---|---|---|---|---|
| E1001 | PARSE | CC-PARSE-002 | — | Line could not be tokenised / malformed syntax | CC-E002 class |
| E1002 | UNKNOWN_COMMAND | CC-PARSE-001 | — | Command word not in the catalog (print "did you mean" from catalog.json) | CC-E001 |
| E1003 | ARITY | CC-PARSE-003 | — | Wrong number of arguments / missing keyword | CC-E002 |
| E1004 | BAD_EXPRESSION | CC-PARSE-002 | — | Numeric expression / `$var` failed to evaluate | CC-E004 |
| E1005 | UNDEFINED_NAME | CC-NAME-001 | — | Referenced object / profile / variable does not exist | CC-E003 |
| E1006 | DUPLICATE_NAME | CC-NAME-003 | — | Create target name already exists | CC-E003 class |
| E1007 | NOTHING_TO_UNDO | CC-NAME-— (session) | — | `undo` with an empty undo stack | — |
| E1008 | NOTHING_TO_REDO | CC-NAME-— (session) | — | `redo` with an empty redo stack | — |
| E1009 | BAD_NAME | CC-PARSE-003 | — | Object name is not a valid identifier | CC-E002 class |
| E2001 | INVALID_PARAM | CC-GEOM-001 | MC_ERR_INVALID_ARG (1) | Parameter out of range (radius ≤ 0, zero axis, …) | CC-E005 class |
| E2002 | GEOMETRY_FAILED | CC-GEOM-001 | MC_ERR_OCCT (2) | OCCT raised / builder `IsDone()==false`; OCCT string preserved verbatim. Boolean failures are this code with the command name attached (guide CC-E006 is the boolean case of E2002, not a separate code) | CC-E005 / CC-E006 |
| E2003 | EMPTY_RESULT | CC-GEOM-002 | MC_ERR_EMPTY_RESULT (3) | Operation produced a null / zero-volume shape; also "result is not a solid" for solid-only commands | CC-E007 |
| E2004 | BAD_PROFILE | CC-GEOM-003 | — | Profile has < 3 points or is self-intersecting | CC-E005 class |
| E2005 | BAD_EDGE_INDEX | CC-NAME-002 | — | Fillet/chamfer edge index outside the shared census space | CC-E003 class |
| E3001 | FILE_NOT_FOUND | CC-IO-001 | — | Script / import path does not exist | CC-E008 |
| E3002 | FILE_READ | CC-IO-002 | — | File could not be read / decoded, or format not recognised | CC-E009 |
| E3003 | EXPORT_FAILED | CC-IO-004 | — | STEP/STL/view writer failed (incl. screenshot write, CC-VIEW-002) | CC-E009 class |
| E3004 | SCRIPT_FAILED | CC-IO-005 | — | A line inside a script failed; wraps the inner E-code and carries file + line number | CC-E012 |
| E4001* | SIM_NO_MATERIAL | CC-SIM-001 | — | `sim run` with no material assigned | CC-E010 |
| E4002* | SIM_NO_FIXITY | CC-SIM-002 | — | `sim run` with no fixed face | CC-E010 |
| E4003* | SIM_SINGULAR | CC-SIM-003 | MC_ERR_FEM_SINGULAR (4) | Stiffness singular — model not fixed enough | CC-E010 class |
| E4004* | SIM_NO_CONVERGE | CC-SIM-004 | MC_ERR_FEM_NO_CONVERGE (5) | PCG hit the iteration cap | CC-E010 class |
| E5001 | INTERNAL | CC-SYS-001 | — | Unexpected exception in app/session code (a bug, not user error) | — |
| E5002 | NOT_IMPLEMENTED | CC-*-000 (any domain; default CC-SYS-000) | — | Command or toolkit not in this build. Mandatory answer for every `toolkit-missing` row in COMMAND-COVERAGE.md and for reserved extras (tet meshing, transient thermal, …) | — |
| — | (warning only) | CC-SIM-005 | — | Mesh volume drift > 10 % — printed as WARN with both volumes, never an error | — |
| — | (warning/info) | CC-VIEW-001 | — | Tessellation failed for one object: object stays listed, viewer shows a placeholder + this code, never a blank app | — |
| — | (info) | CC-SYS-001/002/003 | — | Recovery journal found / low memory (mesh cache purged) / OCCT version mismatch (project opens read-only) | — |
| — | (guide only) | — | — | Guide CC-E011 "out of memory" is not a distinct code: the app prints CC-SYS-002 as WARN when it purges caches, and the failing command then returns its own E-code (usually E5001/E2002) | CC-E011 |

\* The E4xxx simulation range is **new at integration**: Agent 6
specified the CC-SIM codes and Agent 2's table had no 4xxx range.
E4001–E4004 are assigned here for the first time and must be added to
`Core/python/cc/errors.py` when the sim commands are ported (the
prototype has no sim commands yet, so nothing existing is renumbered).

## Logging

Per QA §1.3, unchanged: one log per launch in Documents, every command
logged as typed before execution, OCCT exception strings verbatim, no
network/analytics. The log line carries the E-code and the CC code.
