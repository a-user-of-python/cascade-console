# Cascade Console — QA & Launch-Stability Plan

Agent 6 deliverable, 2026-11-23. Goal stated by the commission: "minimal
errors on launch" and a full-fledged app on Mac + iPad. This plan defines
what "launches clean" means, how errors are coded and logged, what is
tested where, and the gates a build must pass before it is handed over.
Standing rules baked in: every line double-checked including workflow
text; gates must prove the invariant **in the shipped binary**, not file
presence; a build that fails the full audit is **not** handed over;
public repos + standard free GitHub runners only, never larger/paid.

---

## 1. Error-code & logging scheme

Two layers, coordinated with the existing proven façade and with Agent 1's
command catalog rule ("OCCT exceptions caught at the façade boundary,
reported with the OCCT error string plus a distinct app error code per
command — never a crash, never a silent empty shape").

### 1.1 Kernel layer (façade) — EXISTS, do not renumber

From `cascade-port/Facade/occt_facade.h`, carried into Cascade Console's
core unchanged:

| Code | Meaning |
|---|---|
| `MC_OK = 0` | success |
| `MC_ERR_INVALID_ARG = 1` | null handle / bad parameter |
| `MC_ERR_OCCT = 2` | OCCT exception or failed operation (`mc_last_error()` carries the words) |
| `MC_ERR_EMPTY_RESULT = 3` | operation produced a null shape |
| `MC_ERR_FEM_SINGULAR = 4` | FEM: under-constrained / singular stiffness |
| `MC_ERR_FEM_NO_CONVERGE = 5` | FEM: PCG hit iteration cap |

### 1.2 App layer (console) — `CC-<domain><nnn>`

Every user-visible failure prints exactly one line of the form:

```
ERROR CC-SIM-003  sim run: stiffness is singular - the model is not fixed
enough (add a `sim fix` on at least one face).  [kernel MC_ERR_FEM_SINGULAR]
```

i.e. code + plain-words cause + the actionable next step + the kernel code
in brackets when there is one. Domains:

| Domain | Covers | Examples |
|---|---|---|
| `CC-PARSE-nnn` | command syntax | 001 unknown command (with "did you mean" from the catalog), 002 bad number/unit, 003 wrong argument count |
| `CC-NAME-nnn` | object/face/material lookup | 001 no such object, 002 no such face index, 003 name already exists |
| `CC-GEOM-nnn` | modeling operation failed | wraps MC_ERR_OCCT / EMPTY_RESULT with the command name attached |
| `CC-IO-nnn` | files | 001 file not found, 002 format not recognised, 003 import produced no solid, 004 export write failed, 005 project file corrupt (with the journal-recovery offer) |
| `CC-SIM-nnn` | simulation | 001 no material assigned, 002 no fixity, 003 singular (→ MC 4), 004 no convergence (→ MC 5), 005 mesh volume drift > 10 % warning (not an error — printed as WARN with both volumes), 006 tet engine requested before it ships (`NOT_IMPLEMENTED` class) |
| `CC-VIEW-nnn` | viewer/render | 001 tessellation failed for object (object still listed, view shows placeholder + this code — never a blank app), 002 screenshot write failed |
| `CC-SYS-nnn` | app lifecycle | 001 recovery journal found (informational), 002 low memory — mesh cache purged, 003 OCCT version mismatch between project file and app (project opens read-only with the two version strings printed) |

Rules: codes are **never reused** once shipped; a code's wording may
improve, its meaning may not change. `CC-*-000` in any domain =
`NOT_IMPLEMENTED`, used by reserved commands (tet meshing until it lands,
turntable video, transient thermal…) so scripts fail loudly instead of
silently doing nothing. Warnings use the same codes with `WARN` instead of
`ERROR` and never abort a script unless `--strict` is set.

### 1.3 Logging

- One log per launch: `Logs/cascade-console-<YYYYMMDD-HHMMSS>.log` in the
  app's Documents (iPad: visible in the in-app file browser; Mac: also in
  the project folder when a project is open). Plain text, one event per
  line: timestamp, level (INFO/WARN/ERROR), CC/MC code if any, the exact
  command line as typed, and the result summary (object created, volume,
  timing ms).
- Every command is logged *as typed* before execution — a crash therefore
  always leaves the offending command as the last line, which is also
  exactly what crash recovery replays (§EXTRAS 3).
- OCCT exceptions are caught at the façade boundary; the log records the
  OCCT exception string verbatim. No `catch(...)` may swallow without a
  log line + error code (CI lint gate, §4).
- Log rotation: keep last 20 launches, delete older — stated in Settings.
- No network, no analytics, no crash-report upload: logs leave the device
  only if the user exports them from the file browser. True by
  construction and verified by the binary gate (§5).

---

## 2. First-launch checklist

Run on a **fresh install** (no prior app data) — an upgrade-path launch
does not count. Every item is pass/fail with the build's md5 recorded.

### 2.1 Both platforms

1. App opens to the console with the welcome script executed: a demo box
   exists, `measure` on it prints volume 8000 mm³-class numbers, no ERROR
   lines in the first-launch log.
2. `view` opens the 3D view; the demo object is visible and orbit/zoom
   responds; returning to console loses no state.
3. Typing a deliberately bad command (`boxx 1 2`) yields `CC-PARSE-001`
   with a suggestion — not a crash, not silence.
4. Typing a geometrically impossible command (negative radius, boolean of
   a nonexistent object) yields the right CC code and the model is
   unchanged.
5. Create → save project → force-quit mid-session → relaunch: recovery
   offer appears, Recover reproduces the model (volume matches the log),
   Discard path also tested.
6. File browser (in-app, both platforms — on iPad this is mandatory
   because the user's signing certificate breaks the system document
   picker, so the system picker is a secondary path, never the only one)
   lists Documents, opens the saved project, exports a STEP and an STL.
7. Import the exported STEP back: volume/area match the original to
   1e-9 relative (round-trip gate).
8. Settings screen opens; every control changes its setting and the
   change survives relaunch; reduce-transparency + high-contrast modes
   render legibly (screenshot-reviewed).
9. `sim` smoke: assign steel, fix a face, load a face, `sim run` on the
   demo cantilever reproduces the reference numbers within tolerance
   (§3) — on device, not only on host.
10. About screen shows: app version, OCCT version string from the linked
    library (`mc_occt_version()` equivalent), and the LGPL licence texts
    bundled and openable.

### 2.2 Mac-specific

11. Runs on the user's 2019 Intel MacBook Pro (x86_64) **and** on the CI
    Apple-silicon build — the Mac build must be universal or ship the
    correct slice per machine; launching the wrong-arch build is a
    release-blocking defect, tested by installing the actual delivered
    artifact on the Intel machine.
12. Menu bar, keyboard shortcuts, window resize, and full-screen behave;
    console accepts pasted multi-line scripts.
13. No Homebrew / no admin / no network required at any point — install
    is drag-to-Applications (or the documented sideload route).

### 2.3 iPad-specific

14. Installs via the user's normal sideload flow (Signulous); first
    launch happens in airplane mode — everything above must pass
    offline.
15. Layout at the settled panel size (1180×820 pt) in both orientations;
    console, viewer, file browser and settings all usable by touch;
    external keyboard works in the console.
16. Backgrounding during a long boolean / sim run: the journal is intact
    on return; the run either completes or fails with a CC code — never
    a half-written project.

---

## 3. Test matrix

| Layer | What | Where | Gate |
|---|---|---|---|
| Unit (kernel) | Façade ops vs. closed-form: box/cylinder/cone volume, area, CoG, inertia; boolean volumes; section area; draft angle (the P2 prototype cases become permanent tests) | host + CI | exact to 1e-9 relative |
| Unit (solver) | Cantilever suite from prototype P1: tip deflection ≤ 2 % of Euler–Bernoulli at reference mesh, thermal midpoint exact to 1e-9, f1 ≤ 2 %, under-constrained model → MC_ERR_FEM_SINGULAR | host + CI | numbers in `ExtrasQA/results/` are the reference set |
| Convergence | P1b: halving voxel must not increase deflection error (3.51 % → 0.88 % reference) | host + CI (nightly-class job is fine on free runners) | monotone |
| Console | Every catalog command: golden-script tests — run the script, compare the full text output + resulting volumes; every reserved command returns its `*-000` code | host + CI | zero diffs |
| Replay determinism | Save project → replay its script into a scratch doc → BRep volume/area equal to 1e-9 | host + CI | exact |
| Round-trip | STEP/STL/BRep export→import per §2.1.7 | host + CI | 1e-9 (STEP/BRep); STL mesh-volume within tessellation tolerance, printed |
| UI smoke | Launch, welcome script, view open, settings open, file browser list — scripted where the platform allows; otherwise the §2 checklist by hand on device | device | checklist signed off |
| Recovery | Kill -9 during a scripted 50-command session at 5 random points; recovery must reproduce the journal exactly | host (Mac build) + device spot check | 5/5 |
| Perf sanity | Reference project (defined in CI fixtures) opens < 2 s and `sim run` at reference mesh < 30 s on the iPad Air M3 — measured on device, reported as device numbers; CI numbers are labelled host-only and never quoted as device perf | device | within budget or the regression is reported, not hidden |

Reference numbers must be medians of ≥ 3 runs, same session, when
comparing versions — best-of reporting is not accepted (standing rule).

## 4. GitHub Actions plan (free tier only)

- Repo public; workflows run on **standard** runners only:
  `macos-26` (Apple silicon) for Mac + iOS builds, `ubuntu-latest` for
  the Linux host kernel/solver tests. **Never** `larger`, never paid
  runners — a workflow file containing a paid-runner label fails the
  pre-push review checklist, and the workflow itself is double-checked
  line by line like code (standing rule).
- Jobs: (1) `host-tests` (ubuntu): build OCCT-fa
...[truncated 3074 chars]