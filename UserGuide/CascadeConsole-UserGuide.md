# Cascade Console — User Guide

Version 1.0 — for Cascade Console 1.x

This guide is the complete manual for Cascade Console. It covers installing
the app, your first part in ten commands, the console itself, the full
command reference, the 3D viewer, files, settings, simulation and analysis,
troubleshooting, keyboard shortcuts, and licences.

**How to read this guide**

- Text in `code style` is something you type, exactly as shown.
- Shape names in examples (like `plate`) are names you choose. Pick your own.
- All measurements are in the current working unit. The default unit is the
  millimetre (mm). See Settings to change it.
- Nothing in this guide needs the internet. The app works fully offline.

---

# 1. What Cascade Console is

Cascade Console is a 3D CAD app with no toolbar full of drawing tools.
Instead, you **type commands** — the bare modelling commands of the
Open CASCADE (OCCT) geometry kernel — into a console, and the app builds
real, exact solid geometry from them.

- Type `box plate 100 60 10` and you get a real solid plate, 100 × 60 × 10.
- Type `view` and the 3D view opens (or updates) showing your model.
- Type `export-step plate bracket.step` and you get a STEP file any other
  CAD program can open.

Because the commands go straight to the OCCT kernel, this is not a small
demo set. The command set covers the whole modelling surface of
Open CASCADE: primitives, Booleans, fillets and chamfers, sweeps and lofts,
surface work, healing, measurement, and file exchange. Chapter 4 is the
full reference, and the in-app `help` command prints the same reference
on your device.

**What Cascade Console is not**

- It is not a sketch-and-drag modeller. There is no mouse-driven sketch
  constraint solver, because Open CASCADE does not contain one. Curves and
  profiles are defined by coordinates and numbers, which is what makes
  every model in this app exactly reproducible: the same commands always
  build the same part.
- The simulation tools (Chapter 8) are the app's own solver working on
  OCCT geometry. They are not an OCCT feature — OCCT has no finite-element
  solver. Results shown are the solver's true computed results, never
  scaled, clipped, or dressed up.

**The two screens**

- **Console** — where you type. It keeps your full history, your variables,
  and a plain-language explanation of every error.
- **3D view** — where you look. Open it with the `view` command, the View
  button, or the keyboard shortcut. On iPad it sits beside or over the
  console; on Mac it can be its own window.

## 1.1 Install on Mac

> **Repository link (placeholder — replace before publishing):**
> `https://github.com/PLACEHOLDER/cascade-console`
> Download instructions below refer to that project's Releases page and
> GitHub Actions artifacts.

1. Open the project's **Releases** page and download the Mac build
   (`CascadeConsole-Mac.zip`), or open the latest successful **Actions**
   run and download the `CascadeConsole-Mac` artifact.
2. Unzip it. Drag **Cascade Console** into your **Applications** folder.
3. First launch: the app is built with a free developer signature, so
   macOS may warn you the first time. Right-click the app, choose **Open**,
   then **Open** again in the dialog. You only do this once.
4. The app needs no account, no licence key, and no internet connection.

Requires: macOS 14 or later, Intel or Apple silicon.

## 1.2 Install on iPad

1. Open the project's **Releases** page (link in §1.1) and download the
   iPad build (`CascadeConsole-iPad.ipa`), or download the
   `CascadeConsole-iPad` artifact from the latest successful Actions run.
2. Install the `.ipa` with your usual signing service or sideloading tool.
3. Launch **Cascade Console** from the Home Screen.
4. Important: on sideloaded installs, the system document picker can fail
   to open (a known issue with some signing certificates — see §9.2).
   Cascade Console therefore has its **own built-in file browser** for the
   app's Documents folder. Everything in this guide works through that
   browser; you never need the system picker.

Requires: iPadOS 17 or later.

## 1.3 Your first launch

On first launch the app creates a starter project called `Untitled` with
an empty console and one line of text: the welcome message and the hint
`Type help to see every command.` There are no accounts, no setup wizard,
and no sample clutter. You can start typing immediately.

---

# 2. Quick start — a real part in ten commands

This tutorial builds a **mounting bracket**: a flat plate, a round boss
standing on it, a hole through both, rounded edges, and a STEP export.
Type each line and press Return (Mac / external keyboard) or the Run
button (on-screen keyboard).

```
1  box plate 100 60 10
2  view
3  cylinder boss 14 20
4  move boss 50 30 10
5  fuse body plate boss
6  cylinder drill 6 40
7  move drill 50 30 -5
8  cut body body drill
9  fillet body 2
10 export-step body bracket.step
```

**What each command did**

| # | Command | Result |
|---|---------|--------|
| 1 | `box plate 100 60 10` | A solid box named `plate`, 100 long (X), 60 wide (Y), 10 thick (Z), corner at the origin. |
| 2 | `view` | Opens the 3D view and fits the model on screen. From now on the view updates after every command. |
| 3 | `cylinder boss 14 20` | A solid cylinder named `boss`, radius 14, height 20, standing on the XY plane at the origin. |
| 4 | `move boss 50 30 10` | Moves `boss` to x=50, y=30, z=10 — centred on the plate, sitting on its top face. |
| 5 | `fuse body plate boss` | Joins plate and boss into one solid named `body`. |
| 6 | `cylinder drill 6 40` | A long thin cylinder named `drill`, radius 6 — this is a cutting tool, not part of the design. |
| 7 | `move drill 50 30 -5` | Centres the drill on the boss and drops it 5 below the plate, so it passes clean through. |
| 8 | `cut body body drill` | Subtracts the drill from `body`. Now there is a clean Ø12 hole through boss and plate. |
| 9 | `fillet body 2` | Rounds every edge of `body` with a 2 mm radius, where geometry allows. |
| 10 | `export-step body bracket.step` | Writes `bracket.step` to the project folder — a standard file Fusion 360, FreeCAD, Shapr3D and slicers' CAD tools can open. |

**Check your work**

- `measure volume body` prints the volume in cubic units.
- `check body` verifies the solid is valid (closed, no broken faces).
- `list` shows every shape currently in the project: `body` and the
  leftover `drill` tool. `delete drill` tidies up.

**The one rule of the console:** most modelling commands follow the pattern

```
operation  new-name  inputs...  numbers...
```

The result is always a **new** named shape. Your inputs are not destroyed
unless a command says so — which is why `cut body body drill` reads as
"cut, store the answer in `body`, taking `body` minus `drill`."

---

# 3. The console

## 3.1 Typing and running

- Type a command, press **Return / Run**. The command, its output, and any
  measurements it prints appear in the console log, colour-coded: commands
  in white, results in green, warnings in amber, errors in red.
- **One line can hold several commands** separated by `;`
  (example: `box a 10 10 10; view a`).
- **Comments** start with `#`. Everything after `#` on a line is ignored.
- Command names are not case-sensitive. Shape names are.

## 3.2 History

- Press the **Up / Down arrows** (or swipe the history button on iPad) to
  walk back through everything you have typed in this project.
- `history` prints the numbered history. `history run 12` runs line 12
  again. `history save build.txt` writes the whole session to a script
  file — this is the easiest way to save a design as text.
- Not to be confused with `shape-history <name>`, a different command:
  it shows what a boolean or feature did to a shape's faces and edges
  (generated / modified / deleted), recorded by the kernel.

## 3.3 Scripts

A script is a plain text file of commands, one per line.

- `script run bracket.txt` runs a script file from the project folder.
- Scripts stop at the first error and tell you the line number.
- A project file (`.ccproj`, see §6.3) stores its full command history,
  so reopening a project and pressing **Rebuild** replays every command
  and recreates the model exactly.

## 3.4 Variables and expressions

- `set $r = 14` stores a number. Use it anywhere a number is expected:
  `cylinder boss $r 20`.
- Simple arithmetic works inline: `box plate 100/2 60 10`,
  `move boss $r+36 30 10`. Supported: `+ - * / ( )` and `sqrt()`.
- `set` with no arguments lists all variables. `unset $r` removes one.

## 3.5 Undo and redo

- `undo` steps back one modelling command; `redo` steps forward.
- Undo restores shapes, variables, and the view. It does not un-export a
  file you already wrote to disk.
- The undo depth is set in Settings (default 100 steps).

## 3.6 Help

- `help` — the full command list, grouped.
- `help fillet` — the exact syntax, arguments, and an example for one
  command. **This is the fastest way to unstuck yourself.**
- `help search round` — finds commands whose description mentions a word.

## 3.7 Error codes, in plain language

Every error has a code and a plain sentence. The code is for searching
this guide and for bug reports; the sentence tells you what to do.

| Code | Means | What to do |
|------|-------|-----------|
| CC-E001 | Unknown command | Check spelling, or `help search` the idea. |
| CC-E002 | Wrong number of arguments | Run `help <command>` for the exact pattern. |
| CC-E003 | A shape with that name does not exist | `list` shows the names you actually have. |
| CC-E004 | A number could not be read | Check for letters in numbers, or an unset `$variable`. |
| CC-E005 | The kernel could not build that shape | The numbers describe something impossible (e.g. a fillet bigger than the part). Make the number smaller or the part bigger. |
| CC-E006 | Boolean failed | The two shapes may only touch at a face or not overlap at all. Move one so they truly overlap, then retry. |
| CC-E007 | Result is not a solid | You asked a solid-only command for a face or wire. Check with `whatis <name>`. |
| CC-E008 | File not found | Check the name in the file browser (§6.2). Paths are relative to the project folder. |
| CC-E009 | File format not supported for that direction | See the import/export table (§6.4) — e.g. STL can be exported but a mesh STL imports as a mesh, not a solid. |
| CC-E010 | Simulation input missing | A `solve` needs a material, at least one `fix`, and at least one `load` first (§8). |
| CC-E011 | Out of memory during a heavy operation | Reduce tessellation detail in Settings, or split the operation into smaller steps. |
| CC-E012 | Script stopped | The message names the script line that failed; fix that line and run again. |

> The codes above are the plain-language short forms. On screen, every
> error also prints its full unified code pair — a number like `E2002`
> plus a domain code like `CC-GEOM-001` — which is what to quote in a
> bug report. One more code matters: **NOT_IMPLEMENTED** (E5002) means
> the command exists but its part of the kernel is not in this build;
> the app says so plainly instead of pretending to run it.

---

# 4. Command reference

This reference matches the in-app `help` output. Commands are grouped the
way the kernel groups them. In syntax lines, `<name>` is a shape name you
choose, numbers are in the current unit, and angles are in degrees unless
a command says radians.

## 4.1 Primitives — make basic solids

Backed by OCCT's primitive makers (`BRepPrimAPI`).

| Command | Syntax | Makes |
|---------|--------|-------|
| box | `box <name> <dx> <dy> <dz>` | Box from the origin corner. Add a point first with `box <name> <x> <y> <z> <dx> <dy> <dz>` to place the corner. |
| cylinder | `cylinder <name> <radius> <height>` | Cylinder standing on XY at the origin, growing in +Z. |
| cone | `cone <name> <r1> <r2> <height>` | Cone/frustum from radius r1 to r2. |
| sphere | `sphere <name> <radius>` | Sphere centred on the origin. |
| torus | `torus <name> <ring-radius> <tube-radius>` | Full torus around the Z axis. |
| wedge | `wedge <name> <dx> <dy> <dz> <top-dx>` | Box with a sloped top. |
| prism | `prism <name> <face> <dx> <dy> <dz>` | Sweeps a face straight — the classic extrude. |
| revolve | `revolve <name> <face> <ax> <ay> <az> <angle>` | Rotates a face around an axis through the origin. |
| pipe | `pipe <name> <profile-face> <spine-wire>` | Sweeps a profile along a path. |
| loft | `loft <name> <face1> <face2> [more faces...]` | Smooth solid through a series of profiles. `loft <name> solid <faces...>` closes the ends. |
| helix | `helix <name> <radius> <pitch> <height>` | A helical wire — the spine for threads and springs. |

## 4.2 Curves, wires, faces — build profiles

Backed by OCCT edge/wire/face builders (`BRepBuilderAPI`, `GC`).

| Command | Syntax | Makes |
|---------|--------|-------|
| point | `point <name> <x> <y> <z>` | A vertex. |
| line | `line <name> <x1> <y1> <z1> <x2> <y2> <z2>` | A straight edge between two points. |
| circle | `circle <name> <cx> <cy> <cz> <radius>` | A circular edge in the XY plane at that centre. |
| arc | `arc <name> <x1> <y1> <z1> <x2> <y2> <z2> <x3> <y3> <z3>` | Circular arc through three points. |
| spline | `spline <name> <x y z>...` | Smooth B-spline through the listed points (give at least 2 groups). |
| bezier | `bezier <name> <x y z>...` | Bézier curve through control points. |
| wire | `wire <name> <edge1> [edge2...]` | Joins connected edges into a wire. Order does not matter; ends must meet. |
| face | `face <name> <wire>` | A flat face filling a closed wire. |
| planeface | `planeface <name> <dx> <dy>` | A rectangular face on XY — a quick profile for `prism`. |
| polygon | `polygon <name> <x y>... ` | Closed flat face from 2D points on XY. |
| shell | `shell <name> <face1> [face2...]` | Sews faces into a shell. |
| solid | `solid <name> <shell>` | Turns a closed shell into a solid. Fails (CC-E007) if the shell is open. |
| sew | `sew <name> <shape> <tolerance>` | Stitches free edges of a shape together within a tolerance. |

## 4.3 Booleans — combine solids

Backed by OCCT Boolean operations (`BRepAlgoAPI`).

| Command | Syntax | Result |
|---------|--------|--------|
| fuse | `fuse <name> <a> <b> [more...]` | Union: everything in any input. |
| cut | `cut <name> <a> <b> [more tools...]` | `a` minus everything after it. |
| common | `common <name> <a> <b>` | Only the volume shared by both. |
| section | `section <name> <a> <b>` | The edge(s) where the surfaces cross. |
| split | `split <name> <a> <b>` | `a` divided into pieces by `b`, kept as one compound. |
| glue | `glue on` / `glue off` | Faster Booleans for shapes sharing exact faces. Use when parts were built to touch exactly. |

Boolean tips: inputs must genuinely overlap (touching at exactly one
face can fail — nudge by 0.001). Results are exact solids, not meshes.

## 4.4 Transforms — move shapes

| Command | Syntax | Effect |
|---------|--------|--------|
| move | `move <name> <x> <y> <z>` | Moves the shape so its local origin sits at that point. |
| translate | `translate <name> <dx> <dy> <dz>` | Moves by a relative amount. |
| rotate | `rotate <name> <ax> <ay> <az> <angle>` | Rotates around an axis through the shape's origin. |
| mirror | `mirror <name> <plane>` | Mirrors across `xy`, `xz`, or `yz`. The result replaces the shape under the same name if you reuse it. |
| scale | `scale <name> <factor>` | Uniform scale about the shape's origin. |
| copy | `copy <new> <name>` | Duplicates a shape under a new name. |
| rename | `rename <old> <new>` | Renames a shape. |
| delete | `delete <name>` | Removes a shape from the project. Undo brings it back. |

## 4.5 Features — fillets, chamfers, shells

Backed by OCCT local operations (`BRepFilletAPI`, `BRepOffsetAPI`).

| Command | Syntax | Effect |
|---------|--------|--------|
| fillet | `fillet <name> <radius>` | Rounds all edges that can take that radius. Use `fillet <name> <radius> <edge-shape>` to round only the edges of a helper section shape. |
| chamfer | `chamfer <name> <distance>` | 45° chamfer on all edges. `chamfer <name> <d1> <d2>` makes an asymmetric chamfer. |
| draft | `draft <name> <angle> <plane>` | Tapers faces for moulding, relative to a neutral plane (`xy`, `xz`, `yz`). |
| thickness | `thickness <name> <wall>` | Hollows a solid into a shell of the given wall thickness, opening the top face. |
| offset | `offset <name> <distance>` | Grows (positive) or shrinks (negative) a solid's skin. |
| defeature | `defeature <name> <tool>` | Removes the features overlapped by the tool shape (fills holes and pockets back in). |

If a fillet fails with CC-E005, the radius is too big for the smallest
edge or face. Halve it and retry — the kernel's message is honest, the
geometry really cannot take it.

## 4.6 Checking, healing, measuring

Backed by OCCT analysis and healing (`BRepCheck`, `ShapeFix`,
`ShapeUpgrade`, `BRepExtrema`, `BRepGProp`).

| Command | Syntax | Prints / does |
|---------|--------|---------------|
| check | `check <name>` | Whether the shape is a valid, closed, correctly sewn solid. |
| heal | `heal <name>` | Repairs common import damage: tiny gaps, flipped faces, bad tolerances. |
| unify | `unify <name>` | Merges coplanar faces and same-line edges — the clean-up that turns a triangle-soup-looking import into clean faces where faces are truly flat. |
| whatis | `whatis <name>` | The shape's type: solid, shell, face, wire, edge, vertex, or compound, and its counts. |
| bbox | `bbox <name>` | The bounding box: min, max, and size in X/Y/Z. |
| measure volume | `measure volume <name>` | Exact volume from the solid geometry. |
| measure area | `measure area <name>` | Total surface area. |
| measure centre | `measure centre <name>` | Centre of mass. |
| measure dist | `measure dist <a> <b>` | Minimum distance between two shapes. |
| interference | `interference <a> <b>` | Whether two solids overlap, and by how much volume. |
| list | `list` | All shapes in the project with their types. |

## 4.7 View commands

See Chapter 5 for the viewer itself.

| Command | Effect |
|---------|--------|
| `view` | Open/update the 3D view, fit everything. |
| `view <name>` | Show only that shape, fitted. |
| `view-all` | Show every shape. |
| `hide <name>` / `show <name>` | Hide or show one shape. |
| `view top` / `front` / `right` / `iso` | Jump to that camera. |
| `view fit` | Refit the camera to what's visible. |
| `view shaded` / `view wireframe` / `view edges` | Shaded, wireframe, or shaded-with-edges display. |
| `view opacity <name> 0.5` | Set a shape's opacity (0–1). |
| `view color <name> RRGGBB` | Colour a shape (hex colour, e.g. `FF0000`). |
| `view section z 12` | Clip everything above z=12 — a live section view. `view section off` removes it. |
| `view close` | Close the 3D view. Your model is untouched. |

## 4.8 Files

| Command | Effect |
|---------|--------|
| `import-step <file>` (also `import-iges`, `import-brep`, `import-stl`, `import-obj`) | Load a model file from the project folder as new shape(s). |
| `export-step <name> <file>` | Write a shape as STEP (.step/.stp). |
| `export-iges <name> <file>` | Write as IGES (.iges/.igs). |
| `export-brep <name> <file>` | Write in OCCT's native BREP text format — the most faithful save of a single shape. |
| `export-stl <name> <file>` | Write a triangulated STL mesh for printing. Tessellation detail is a Setting (§7). |
| `export-obj <name> <file>` | Write a Wavefront OBJ mesh. (Needs the TKDEOBJ toolkit — in a build without it this answers NOT_IMPLEMENTED instead of writing a file.) |
| `save <file>` | Save the whole project (shapes + history) as `.ccproj`. |
| `open <file>` | Open a `.ccproj` project. |
| `new` | Start a fresh, empty project (asks first if you have unsaved work). |

## 4.9 Simulation commands

Full explanation in Chapter 8.

| Command | Effect |
|---------|--------|
| `material <name> <preset>` | Assign a material preset (`pla`, `abs`, `petg`, `aluminium`, `steel`, `brass`, `wood`) to a shape, or `material <name> custom <E-MPa> <poisson> <density>` for your own numbers. |
| `fix <shape> <face-selector>` | Fix a face (e.g. `fix body bottom`, `fix body zmin`). |
| `load force <shape> <face-selector> <newtons> <direction>` | Apply a force, e.g. `load force body top 100 down`. |
| `load pressure <shape> <face-selector> <MPa>` | Apply uniform pressure to a face. |
| `sim mesh <shape> <size>` | Generate the solver mesh at an element size; prints node/element counts. |
| `sim solve static` | Run a static stress solve. |
| `sim solve modal` | Run a natural-frequency (vibration) solve. |
| `sim results` | Print peak von Mises stress, peak displacement, and (modal) the first frequencies — the solver's true numbers. |
| `sim view vonmises` / `sim view displacement` | Show the result field in the 3D view, coloured with the genuine min–max range. |

---

# 5. The 3D viewer

The viewer shows exact OCCT geometry, tessellated for display. It never
changes your model — display detail is a Setting, model precision is not
affected by it.

**Moving around**

- **Mac:** drag to orbit, right-drag (or two-finger drag) to pan, scroll
  to zoom. 
- **iPad:** one finger orbits, two fingers pan and pinch-zoom.
- Buttons (Liquid Glass, bottom of the view): Fit, Top, Front, Right,
  Iso, Shade/Wireframe toggle, Section (clip) toggle.

**Reading the view**

- The triad in the corner shows the axes: X red, Y green, Z blue.
- A shape selected in the console (`view <name>`) is highlighted.
- Hidden shapes stay hidden until `show <name>` or `view-all`.
- The section clip (`view section`) is display-only: exports and
  measurements always use the full, unclipped solid.

**Performance**

- Large imports are tessellated once and cached. If orbiting feels heavy,
  lower **Tessellation detail** in Settings and run `view` again — your
  geometry is unchanged, only the display triangles get coarser.

---

# 6. Files

## 6.1 The file picker

Buttons with a folder icon open the picker. On Mac this is the standard
macOS open/save panel. On iPad it is the system document picker **when it
works on your install** — and the app's own browser when it doesn't
(§6.2). You can force the built-in browser always: Settings →
Files → **Always use in-app file browser**.

## 6.2 The in-app file browser

A simple, high-contrast list of the app's Documents folder and your
project folders: name, size, date. Tap to open, long-press (or
right-click on Mac) to rename, duplicate, delete, or share/export a copy.
This browser exists because sideload signing certificates can break the
system picker on iPad — with the browser, file access never depends on
the picker working.

## 6.3 Project format

- A project is a single file: `name.ccproj`.
- Inside, it stores: every shape (as BREP), the **full command history**
  that built them, variables, materials and simulation setup, and view
  state.
- Because history is stored, **Rebuild** can regenerate the model from
  commands alone — and the history doubles as documentation of how the
  part was made.
- Projects open identically on Mac and iPad. Copy the file by any means
  (AirDrop, Files, email) — there is no cloud account involved.

## 6.4 Import / export table

| Format | Import | Export | Notes |
|--------|--------|--------|-------|
| STEP (.step, .stp) | Yes — solids | Yes | The best exchange format. Preserves exact solids, names, colours. |
| IGES (.iges, .igs) | Yes — surfaces/solids | Yes | Older standard; surfaces may need `heal` + `sew` after import. |
| BREP (.brep) | Yes | Yes | OCCT native. Perfect fidelity, but only OCCT-based tools read it. |
| STL (.stl) | Yes — as a **mesh** | Yes | Meshes have no exact faces. An imported STL can be viewed, measured approximately, and printed, but Boolean/fillet commands need a solid — converting a mesh to a solid is lossy and the app will say so when you try. |
| OBJ (.obj) | Yes — as a mesh | Yes | Same mesh rules as STL. |

After importing a STEP or IGES file, run `check` on it. If it reports
problems, `heal` then `check` again fixes most real-world files.

---

# 7. Settings explained

Open Settings from the gear button or `Cmd-,` (Mac) / Settings in the
menu (iPad). Settings apply immediately and are remembered.

**Units and precision**

- **Working unit** — mm (default), cm, m, inch. Changing units rescales
  the numbers you type and read; it does not rescale existing shapes.
- **Kernel precision** — the OCCT confusion tolerance. Leave at default
  (0.0001) unless a Boolean on a very large or very small part misbehaves.

**Console**

- **Font size** — console text size. The app also follows your system
  text-size setting.
- **Undo depth** — how many commands `undo` remembers (10–1000).
- **Echo results** — print measurements automatically after each command.

**3D view**

- **Tessellation detail** — how finely curved faces are triangulated for
  display and for STL/OBJ export. Finer = smoother + slower + bigger STL
  files. Does not change the exact geometry.
- **Background** — dark, light, or follow system.
- **Glass intensity** — how translucent the Liquid Glass buttons and
  panels are. Turn it down for maximum contrast.

**Files**

- **Always use in-app file browser** — skip the system picker entirely
  (recommended on sideloaded iPad installs).
- **Default export format** — STEP (default), IGES, BREP, STL, or OBJ.
- **Autosave** — save the project automatically every few minutes, and on
  close. Autosaves go to `Autosaves` in the project folder.

**Simulation**

- **Solver threads** — how many CPU threads the solver may use.
- **Default mesh size** — starting element size for `sim mesh`.

**About**

- App version, OCCT version, and the licence/attribution page (Chapter 11
  of this guide).

---

# 8. Simulation and analysis

## 8.1 What this is — honestly

Open CASCADE provides the **geometry**: exact solids, faces you can point
loads at, volumes and centres of mass. It does **not** contain a
finite-element solver. Cascade Console's simulation is the app's **own
solver** built on top of that geometry:

1. `sim mesh` tetrahedralises your solid.
2. The solver assembles stiffness from the material numbers **you**
   assigned and solves for displacement under the fixtures and loads
   **you** defined.
3. Stress (von Mises) and displacement are computed from that solution.

The numbers printed by `sim results` and the colours in `sim view` are
that solution's true values. The colour scale always spans the result's
genuine minimum to maximum — it is never narrowed, clipped, or adjusted
to look more dramatic. If a result looks boring, boring is what the
physics gave.

**Limits you should know**

- Linear, static, small-deflection theory. Big bending, contact between
  parts, buckling, and plastic (permanent) deformation are outside what
  this solver claims. If peak stress exceeds the material's yield, the
  app warns you the linear answer is no longer trustworthy — it still
  shows you the number, labelled.
- Accuracy depends on mesh size. Halve the element size and re-solve: if
  the peak stress moves a lot, keep refining. This is normal engineering
  practice, not an app defect.
- Modal results are the first natural frequencies of the part as fixtured.

## 8.2 A worked example

Continuing the Chapter 2 bracket, fixed by its base, 200 N pressing on
the boss top:

```
material body aluminium
fix body zmin
load force body zmax 200 down
sim mesh body 4
sim solve static
sim results
sim view vonmises
```

`sim results` prints peak von Mises stress (MPa), peak displacement
(mm), and where each peak occurs. `view` commands work as usual
afterwards; `sim view off` returns to the normal model display.

## 8.3 Analysis without simulation

For many questions you don't need the solver at all — OCCT's exact
analysis is faster and exact:

- Will it fit? `bbox`, `measure dist`.
- Will these two parts clash when assembled? `interference`.
- How heavy? `measure volume` × your material density (the console
  prints mass directly once a `material` is assigned).
- Is this import safe to build on? `check` and `heal`.

---

# 9. Troubleshooting

## 9.1 The app won't launch, or launches to a blank window

- **Mac:** if macOS blocked the first open, right-click the app →
  **Open** (§1.1). If the window is blank for more than a few seconds,
  quit and relaunch — the kernel loads once at startup and a first-launch
  block by Gatekeeper can interrupt it. Still stuck: delete the app,
  re-download, and drag a fresh copy to Applications.
- **iPad:** if the icon is greyed or the app closes instantly, the
  signing on the install has expired or been revoked — reinstall the
  `.ipa` with your signing service. Your projects are in the app's
  Documents folder and survive a reinstall done as an update (same app
  ID); they do not survive deleting the app first.
- **Both:** a project that was open at last quit reopens automatically.
  If a damaged project is suspected, hold **Shift** while launching to
  start with an empty project instead.

## 9.2 The file picker does nothing on iPad

Known issue: some sideload signing certificates break the system
document picker, so tapping a folder button appears to do nothing.
**Workaround (built into the app):** use the in-app file browser —
**Files button → Browse in app**, or turn on Settings → Files →
**Always use in-app file browser**. Every open/save/import/export in
this guide works through the browser. This is a certificate limitation,
not a fault in your files.

## 9.3 Common command problems

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| CC-E001 on a command you're sure exists | Typo, or the command needs its argument pattern | `help search <word>` |
| Boolean fails (CC-E006) | Shapes touch at exactly one face/point, or don't overlap | Nudge one shape by a small amount so volumes truly overlap |
| Fillet fails (CC-E005) | Radius larger than a face/edge can take | Halve the radius; fillet big faces first, small ones after |
| Imported STEP looks faceted with many tiny faces | The exporter wrote it that way | `unify <name>` merges truly-flat neighbours into clean faces |
| Imported IGES is faces, not a solid | IGES often carries loose surfaces | `heal`, then `sew`, then `solid` (§4.2) |
| `view` shows nothing | Everything is hidden, or the model is far from origin | `view-all`, then `view fit` |
| Solve refuses to start (CC-E010) | Missing material, fixture, or load | §8.2 shows the minimum set |
| Peak stress changes every mesh | Mesh too coarse near the peak | Halve `sim mesh` size and re-solve until it settles |
| STL export is huge | Tessellation detail set very fine | Lower it in Settings — display/export only, geometry unaffected |

## 9.4 Reporting a problem

Note the **error code**, the **exact command line** you typed, and the
app + OCCT versions from Settings → About. With those three things, most
problems can be reproduced exactly — one advantage of a command-driven
app.

---

# 10. Keyboard shortcuts

On iPad these work with an external keyboard (Smart Keyboard, Magic
Keyboard, or any Bluetooth keyboard).

| Action | Mac | iPad keyboard |
|--------|-----|---------------|
| Run the current command line | Return | Return |
| Run and keep text for editing | Cmd-Return | Cmd-Return |
| Previous / next command in history | Up / Down arrows | Up / Down arrows |
| Open or refresh the 3D view | Cmd-V | Cmd-V |
| Fit view | F | F |
| Undo / Redo (modelling) | Cmd-Z / Cmd-Shift-Z | Cmd-Z / Cmd-Shift-Z |
| Save project | Cmd-S | Cmd-S |
| Open project | Cmd-O | Cmd-O |
| Export (default format) | Cmd-E | Cmd-E |
| Clear console log | Cmd-K | Cmd-K |
| Help for the word at the cursor | Cmd-H | Cmd-H |
| Settings | Cmd-, (comma) | Cmd-, (comma) |
| Close 3D view | Cmd-W | Cmd-W |

---

# 11. Licences and attribution

**Open CASCADE Technology (OCCT)**

Cascade Console's geometry kernel is Open CASCADE Technology.

> Open CASCADE Technology is Copyright © Open CASCADE SAS.
> It is licensed under the GNU Lesser General Public License (LGPL)
> version 2.1, with the additional Open CASCADE exception.
> The full LGPL 2.1 text and the exception text ship inside the app
> (Settings → About → Licences) and with the source code.
> Open CASCADE sources are used unmodified. Project home:
> https://www.opencascade.org / https://dev.opencascade.org

Under the LGPL you may obtain the OCCT source, and you may relink the
app against a modified OCCT; the licence texts in the app explain your
rights in full. Nothing in the app's own licence (below) limits your
LGPL rights in OCCT itself.

**Cascade Console (the app)**

> Cascade Console is © the user (the author). All rights reserved.
> The app and its source are published for viewing only. No use,
> copying, modification, or redistribution is permitted without prior
> written permission from the author, except for your rights in
> Open CASCADE Technology under the LGPL 2.1 + exception terms above,
> which are unaffected.

**Trademarks**

Open CASCADE is a trademark of Open CASCADE SAS. Mac, iPad, macOS, and
iPadOS are trademarks of Apple Inc. This guide is an independent
publication and is not endorsed by Open CASCADE SAS or Apple Inc.

---

*End of guide — Cascade Console User Guide v1.0.*
