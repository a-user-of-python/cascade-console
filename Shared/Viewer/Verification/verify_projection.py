#!/usr/bin/env python3
"""Projection-matrix guard for the Cascade Console viewer.

WHY THIS EXISTS (v0.2.2): the v0.2.1 device verdict was "the geometry
is inverted so I can't see it". The mesh data was proven innocent
(signed-volume / outward-normal invariants in the engine tests, both
backends); the defect was in Shared/Viewer/Swift/Camera.swift — its
perspective matrix was LEFT-handed (clip w = +z_view, NDC z decreasing
with distance) while the view matrix, the model data and Metal's
defaults are all RIGHT-handed. Every point in front of the camera had
negative clip w (which inverts the rasterizer's front/back facing
test, so near faces were culled and the inside of the far side
showed), and depth ordering was inverted under the renderer's
less-than depth test. The orthographic matrix had the same inverted
depth slope.

Swift cannot be compiled on the host, so this script replicates the
matrix formulas from Camera.swift EXACTLY (keep them in step — the
Swift file points here) and asserts the invariants a right-handed
Metal pipeline requires:

  1. clip w > 0 for every point in front of the camera;
  2. NDC z in [0, 1] and strictly INCREASING with distance
     (near surfaces must win the less-than depth test);
  3. a triangle whose geometric normal faces the camera classifies
     as FRONT (positive homogeneous signed area), and one facing
     away classifies as BACK;
  4. the orthographic matrix keeps near < far under the same test.

Exit status 0 iff every check passes.
"""
import math
import sys

import numpy as np

FAIL = []


def check(ok, what):
    print(("  [PASS] " if ok else "  [FAIL] ") + what)
    if not ok:
        FAIL.append(what)


# --- Camera.swift, replicated formula for formula (column-major) ---

def look_at(eye, centre, up):
    z = eye - centre
    z = z / np.linalg.norm(z)                    # backward
    x = np.cross(up, z)
    x = x / np.linalg.norm(x)                    # right
    y = np.cross(z, x)                           # true up
    M = np.zeros((4, 4))
    M[:, 0] = [x[0], y[0], z[0], 0]
    M[:, 1] = [x[1], y[1], z[1], 0]
    M[:, 2] = [x[2], y[2], z[2], 0]
    M[:, 3] = [-np.dot(x, eye), -np.dot(y, eye), -np.dot(z, eye), 1]
    return M


def perspective(fov_deg, aspect, near, far):
    # float4x4(perspectiveFovDegrees:aspect:near:far:) in Camera.swift
    y_scale = 1 / math.tan(math.radians(fov_deg) / 2)
    x_scale = y_scale / aspect
    z_scale = far / (near - far)                 # negative (RH form)
    M = np.zeros((4, 4))
    M[:, 0] = [x_scale, 0, 0, 0]
    M[:, 1] = [0, y_scale, 0, 0]
    M[:, 2] = [0, 0, z_scale, -1]
    M[:, 3] = [0, 0, near * z_scale, 0]
    return M


def orthographic(l, r, b, t, n, f):
    # float4x4(orthographicLeft:right:bottom:top:near:far:)
    M = np.zeros((4, 4))
    M[:, 0] = [2 / (r - l), 0, 0, 0]
    M[:, 1] = [0, 2 / (t - b), 0, 0]
    M[:, 2] = [0, 0, -1 / (f - n), 0]
    M[:, 3] = [-(r + l) / (r - l), -(t + b) / (t - b), f / (f - n), 1]
    return M


def main():
    print("Cascade Console projection guard (Camera.swift mirror)")
    # Default OrbitCamera: azimuth pi/4, elevation pi/6, looking at the
    # origin; distance 30 (a fitted 10 mm box sits well inside).
    az, el, dist = math.pi / 4, math.pi / 6, 30.0
    eye = np.array([math.sin(az) * math.cos(el),
                    math.cos(az) * math.cos(el),
                    math.sin(el)]) * dist
    up = np.array([-math.sin(az) * math.sin(el),
                   -math.cos(az) * math.sin(el),
                   math.cos(el)])
    V = look_at(eye, np.zeros(3), up)
    near = max(dist / 1000, 0.001)               # projectionMatrix()
    far = dist * 100 + 1000
    P = perspective(45.0, 1.3, near, far)

    # 1 + 2: w and depth along the view direction.
    forward = -eye / np.linalg.norm(eye)
    ws, zs = [], []
    for d in (10.0, 20.0, 40.0, 80.0):
        clip = P @ (V @ np.array([*(eye + forward * d), 1.0]))
        ws.append(clip[3])
        zs.append(clip[2] / clip[3])
    check(all(w > 0 for w in ws),
          "perspective: clip w > 0 for points in front of the camera")
    check(all(0.0 <= z <= 1.0 for z in zs) and
          all(zs[i] < zs[i + 1] for i in range(len(zs) - 1)),
          "perspective: NDC z in [0,1] and increasing with distance")

    # 3: facing classification of a box's faces (outward CCW winding,
    # as the engine tessellation delivers — proven in the C++ tests).
    c = 5.0
    faces = {
        "+X": [(c, -c, -c), (c, c, -c), (c, c, c), (c, -c, c)],
        "-X": [(-c, -c, c), (-c, c, c), (-c, c, -c), (-c, -c, -c)],
        "+Y": [(-c, c, -c), (c, c, -c), (c, c, c), (-c, c, c)],
        "-Y": [(-c, -c, c), (c, -c, c), (c, -c, -c), (-c, -c, -c)],
        "+Z": [(-c, -c, c), (c, -c, c), (c, c, c), (-c, c, c)],
        "-Z": [(-c, c, -c), (-c, -c, -c), (c, -c, -c), (c, c, -c)],
    }
    facing_ok = True
    for name, q in faces.items():
        for tri in ((q[0], q[1], q[2]), (q[0], q[2], q[3])):
            clips = [P @ (V @ np.array([*p, 1.0])) for p in tri]
            # Homogeneous signed area (what the rasterizer's facing
            # test reduces to): front iff > 0 for CCW-front pipelines.
            (x0, y0, w0), (x1, y1, w1), (x2, y2, w2) = [
                (cl[0], cl[1], cl[3]) for cl in clips]
            area = (x0 * (y1 * w2 - y2 * w1)
                    + x1 * (y2 * w0 - y0 * w2)
                    + x2 * (y0 * w1 - y1 * w0))
            n = np.cross(np.array(tri[1]) - tri[0], np.array(tri[2]) - tri[0])
            cen = (np.array(tri[0]) + tri[1] + tri[2]) / 3
            toward = np.dot(n, eye - cen) > 0
            if (area > 0) != toward:
                facing_ok = False
                print(f"    face {name}: toward={toward} but classified "
                      f"{'FRONT' if area > 0 else 'BACK'}")
    check(facing_ok,
          "perspective: camera-facing faces classify FRONT, away faces BACK")

    # 4: orthographic depth slope with the caller's symmetric slab.
    D = dist * 10 + 1000
    O = orthographic(-40, 40, -30, 30, -D, D)
    zn = (O @ np.array([0, 0, -5.0, 1.0]))[2]
    zf = (O @ np.array([0, 0, -50.0, 1.0]))[2]
    check(zn < zf, "orthographic: nearer view point has smaller NDC z")

    print(f"RESULT: {'FAIL: ' + '; '.join(FAIL) if FAIL else 'all checks pass'}")
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
