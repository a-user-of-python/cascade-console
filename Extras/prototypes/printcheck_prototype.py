#!/usr/bin/env python3
"""
Cascade Console - Extras prototype P3: 3D-print export checks.
PROTOTYPE (host, trimesh) - shipped app does the same queries in OCCT
(BRepCheck_Analyzer + shell census for watertight; BRepExtrema surface-to-
surface sampling for wall thickness). Checks:
  1. Watertight: closed box mesh -> True; same mesh with 2 faces removed -> False
  2. Wall thickness estimate: hollow box, outer 20 mm, inner cavity 18 mm
     (true wall 1.0 mm). Estimator: sample outer-surface face centres,
     nearest distance to the inner surface; report min/median.
"""
import json
import numpy as np, trimesh

out = {}
box = trimesh.creation.box(extents=[20,20,20])
out["watertight_closed_box"] = bool(box.is_watertight)
faces = np.arange(len(box.faces)); keep = faces[2:]
open_mesh = trimesh.Trimesh(vertices=box.vertices.copy(), faces=box.faces[keep].copy(), process=False)
out["watertight_open_box_2_faces_removed"] = bool(open_mesh.is_watertight)
out["volume_closed_box_mm3"] = float(box.volume)

outer = trimesh.creation.box(extents=[20,20,20])
inner = trimesh.creation.box(extents=[18,18,18])
centres = outer.triangles_center
# exclude centres whose nearest inner point is a corner artefact by using
# face centres only (they sit mid-face, 1.0 mm from the cavity wall)
_, dist, _ = trimesh.proximity.closest_point(inner, centres)
out["wall_thickness_hollow_box"] = {
    "true_wall_mm": 1.0,
    "estimated_min_mm": float(dist.min()),
    "estimated_median_mm": float(np.median(dist)),
    "samples": int(len(centres))}
print(json.dumps(out, indent=2))
json.dump(out, open("../results/printcheck_results.json","w"), indent=2)
