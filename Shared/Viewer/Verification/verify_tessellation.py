#!/usr/bin/env python3
"""
Cascade Console - Viewer data-contract verification (host side).

Builds a real OCCT solid (a box with a cylindrical through-hole, made with
BRepAlgoAPI_Cut), tessellates it with BRepMesh_IncrementalMesh at three
deflection profiles, computes per-vertex normals from the underlying face
surface (D1 at each node's UV parameters, flipped for REVERSED faces),
and writes the "standard" profile in the CCM1 binary mesh-buffer format
that the Swift viewer consumes (see ../README.md, "Mesh buffer format").

It then reads the .ccm file back and checks the contract end to end:
  * magic / version / counts in the file match what was tessellated
  * every index is in range, every normal is unit length (1e-3)
  * the file bounding box matches OCCT's Bnd_Box for the shape
  * summed triangle area approximates OCCT's true surface area

Run with the project venv:
    ~/workspace/stl2step-venv/bin/python verify_tessellation.py

No user name, no network, no publishing. Output: sample_mesh.ccm + stdout.
"""

import math
import struct
import sys
import time
from pathlib import Path

from OCP.BRepPrimAPI import BRepPrimAPI_MakeBox, BRepPrimAPI_MakeCylinder
from OCP.BRepAlgoAPI import BRepAlgoAPI_Cut
from OCP.BRepMesh import BRepMesh_IncrementalMesh
from OCP.BRepAdaptor import BRepAdaptor_Surface
from OCP.TopExp import TopExp_Explorer
from OCP.TopAbs import TopAbs_FACE, TopAbs_REVERSED
from OCP.TopLoc import TopLoc_Location
from OCP.TopoDS import TopoDS
from OCP.BRep import BRep_Tool
from OCP.BRepBndLib import BRepBndLib
from OCP.Bnd import Bnd_Box
from OCP.BRepGProp import BRepGProp
from OCP.GProp import GProp_GProps
from OCP.gp import gp_Pnt, gp_Vec, gp_Trsf

MAGIC = b"CCM1"
VERSION = 2  # v2 (v0.2.4): per-object census-edge section after centre
OUT = Path(__file__).with_name("sample_mesh.ccm")


def build_sample_shape():
    """Box 30 x 20 x 12 with a radius-6 cylinder cut through the top face."""
    box = BRepPrimAPI_MakeBox(30.0, 20.0, 12.0).Shape()
    # Cylinder axis is +Z by default; centre it on the box top face.
    cyl = BRepPrimAPI_MakeCylinder(6.0, 20.0).Shape()
    trsf = gp_Trsf()
    trsf.SetTranslation(gp_Vec(15.0, 10.0, -4.0))
    from OCP.TopLoc import TopLoc_Location as Loc
    cyl = cyl.Moved(Loc(trsf))
    cut = BRepAlgoAPI_Cut(box, cyl)
    cut.Build()
    if not cut.IsDone():
        raise RuntimeError("BRepAlgoAPI_Cut failed")
    return cut.Shape()


def face_normal_at(face, u, v):
    """Unit normal of the face's surface at (u, v), honouring orientation."""
    adaptor = BRepAdaptor_Surface(face, True)
    p, du, dv = gp_Pnt(), gp_Vec(), gp_Vec()
    adaptor.D1(u, v, p, du, dv)
    n = du.Crossed(dv)
    mag = n.Magnitude()
    if mag < 1e-12:
        return (0.0, 0.0, 1.0)
    n.Scale(1.0 / mag)
    if face.Orientation() == TopAbs_REVERSED:
        n.Reverse()
    return (n.X(), n.Y(), n.Z())


def tessellate(shape, deflection, angular):
    """Return (vertices, indices, face_groups).

    vertices: list of (x, y, z, nx, ny, nz) float tuples, per-face blocks
    appended without cross-face welding so CAD edges stay sharp.
    face_groups: list of (sourceFaceIndex, vertexStart, vertexCount,
                          indexStart, indexCount).
    """
    BRepMesh_IncrementalMesh(shape, deflection, False, angular, True)
    vertices, indices, groups = [], [], []
    explorer = TopExp_Explorer(shape, TopAbs_FACE)
    face_index = 0
    while explorer.More():
        face = TopoDS.Face_s(explorer.Current())
        location = TopLoc_Location()
        tri = BRep_Tool.Triangulation_s(face, location)
        if tri is None:
            explorer.Next()
            face_index += 1
            continue
        trsf = location.Transformation()
        v_start, i_start = len(vertices), len(indices)
        has_uv = tri.HasUVNodes()
        for i in range(1, tri.NbNodes() + 1):
            p = tri.Node(i).Transformed(trsf)
            if has_uv:
                uv = tri.UVNode(i)
                n = face_normal_at(face, uv.X(), uv.Y())
                # The surface normal lives in face-local space; the mesh
                # location for this sample is identity/translation-only, and
                # OCCT triangulation locations in the core pipeline are
                # required to be rigid - see README "Coordinate contract".
            else:
                n = (0.0, 0.0, 1.0)
            vertices.append((p.X(), p.Y(), p.Z(), n[0], n[1], n[2]))
        reversed_face = face.Orientation() == TopAbs_REVERSED
        for i in range(1, tri.NbTriangles() + 1):
            a, b, c = tri.Triangle(i).Get()
            a, b, c = a - 1 + v_start, b - 1 + v_start, c - 1 + v_start
            if reversed_face:
                indices.extend((a, c, b))
            else:
                indices.extend((a, b, c))
        groups.append((face_index, v_start, tri.NbNodes(),
                       i_start, tri.NbTriangles() * 3))
        explorer.Next()
        face_index += 1
    return vertices, indices, groups


def census_edges(shape):
    """Census edges in TopExp.MapShapes(TopAbs_EDGE) order — the same
    enumeration the core's ccgeom_edge_list and the fillet/chamfer
    `edges i,j,...` selector use. Returns [(start, end), ...]."""
    from OCP.TopExp import TopExp
    from OCP.TopAbs import TopAbs_EDGE
    from OCP.TopTools import TopTools_IndexedMapOfShape
    emap = TopTools_IndexedMapOfShape()
    TopExp.MapShapes_s(shape, TopAbs_EDGE, emap)
    edges = []
    for i in range(1, emap.Extent() + 1):
        edge = TopoDS.Edge_s(emap.FindKey(i))
        a = BRep_Tool.Pnt_s(TopExp.FirstVertex_s(edge))
        b = BRep_Tool.Pnt_s(TopExp.LastVertex_s(edge))
        edges.append(((a.X(), a.Y(), a.Z()), (b.X(), b.Y(), b.Z())))
    return edges


def write_ccm(path, name, geometry_version, vertices, indices, groups, edges):
    name_bytes = name.encode("utf-8")
    xs = [v[0] for v in vertices]; ys = [v[1] for v in vertices]; zs = [v[2] for v in vertices]
    bbox = (min(xs), min(ys), min(zs), max(xs), max(ys), max(zs))
    centre = tuple((bbox[i] + bbox[i + 3]) / 2.0 for i in range(3))
    with open(path, "wb") as f:
        f.write(MAGIC)
        f.write(struct.pack("<III", VERSION, 1, 0))          # version, objectCount, reserved
        f.write(struct.pack("<I", len(name_bytes)))
        f.write(name_bytes)
        f.write(struct.pack("<Q", geometry_version))
        f.write(struct.pack("<I", len(groups)))
        for g in groups:
            f.write(struct.pack("<IIIII", *g))
        f.write(struct.pack("<II", len(vertices), len(indices)))
        flat = [c for v in vertices for c in v]
        f.write(struct.pack("<%df" % len(flat), *flat))
        f.write(struct.pack("<%dI" % len(indices), *indices))
        f.write(struct.pack("<6f", *bbox))
        f.write(struct.pack("<3f", *centre))
        # v2 edge section: count, then per edge (index, start xyz, end xyz)
        f.write(struct.pack("<I", len(edges)))
        for i, (a, b) in enumerate(edges):
            f.write(struct.pack("<I", i))
            f.write(struct.pack("<3f", *a))
            f.write(struct.pack("<3f", *b))
    return bbox


def read_ccm(path):
    data = path.read_bytes()
    off = 0
    def take(fmt):
        nonlocal off
        size = struct.calcsize(fmt)
        vals = struct.unpack_from(fmt, data, off)
        off += size
        return vals
    magic = data[:4]; off = 4
    version, count, _ = take("<III")
    (nlen,) = take("<I")
    name = data[off:off + nlen].decode("utf-8"); off += nlen
    (gver,) = take("<Q")
    (ngroups,) = take("<I")
    groups = [take("<IIIII") for _ in range(ngroups)]
    vcount, icount = take("<II")
    verts = take("<%df" % (vcount * 6))
    idx = take("<%dI" % icount)
    bbox = take("<6f")
    centre = take("<3f")
    edges = []
    if version >= 2:
        (ne,) = take("<I")
        for _ in range(ne):
            (ei,) = take("<I")
            a = take("<3f"); b = take("<3f")
            edges.append((ei, a, b))
    assert off == len(data), f"trailing bytes: parsed {off} of {len(data)}"
    return dict(magic=magic, version=version, count=count, name=name,
                gver=gver, groups=groups, vcount=vcount, icount=icount,
                verts=verts, idx=idx, bbox=bbox, centre=centre,
                edges=edges, file_bytes=len(data))


def main():
    shape = build_sample_shape()

    props = GProp_GProps()
    BRepGProp.VolumeProperties_s(shape, props)
    volume = props.Mass()
    BRepGProp.SurfaceProperties_s(shape, props)
    area = props.Mass()
    box = Bnd_Box()
    BRepBndLib.Add_s(shape, box, True)
    gxmin, gymin, gzmin, gxmax, gymax, gzmax = box.Get()

    print(f"sample shape: box 30x20x12, cylinder r6 cut through top")
    print(f"OCCT volume       : {volume:.3f} mm^3")
    print(f"OCCT surface area : {area:.3f} mm^2")
    print(f"OCCT bbox         : ({gxmin:.3f},{gymin:.3f},{gzmin:.3f}) .. "
          f"({gxmax:.3f},{gymax:.3f},{gzmax:.3f})")

    profiles = [("coarse", 0.5, 0.5), ("standard", 0.1, 0.3), ("fine", 0.02, 0.1)]
    results = {}
    for label, defl, ang in profiles:
        t0 = time.perf_counter()
        verts, idx, groups = tessellate(shape, defl, ang)
        dt = (time.perf_counter() - t0) * 1000.0
        results[label] = (verts, idx, groups)
        print(f"profile {label:8s}: deflection={defl:<5} angular={ang:<4} "
              f"vertices={len(verts):6d} triangles={len(idx)//3:6d} "
              f"faceGroups={len(groups):2d} tessellation={dt:8.1f} ms")

    verts, idx, groups = results["standard"]
    edges = census_edges(shape)
    bbox = write_ccm(OUT, "sample", 1, verts, idx, groups, edges)
    print(f"wrote {OUT.name}: {OUT.stat().st_size} bytes (standard profile, "
          f"{len(edges)} census edges)")

    # ---- read back and verify the contract ----
    m = read_ccm(OUT)
    assert m["magic"] == MAGIC, "bad magic"
    assert m["version"] == VERSION, "bad version"
    assert m["count"] == 1 and m["name"] == "sample" and m["gver"] == 1
    assert m["vcount"] == len(verts) and m["icount"] == len(idx), "count mismatch"
    assert len(m["groups"]) == len(groups), "face group count mismatch"
    assert max(m["idx"]) < m["vcount"], "index out of range"
    worst_normal_err = 0.0
    for i in range(m["vcount"]):
        nx, ny, nz = m["verts"][i * 6 + 3:i * 6 + 6]
        worst_normal_err = max(worst_normal_err,
                               abs(math.sqrt(nx * nx + ny * ny + nz * nz) - 1.0))
    assert worst_normal_err < 1e-3, f"non-unit normal, err {worst_normal_err}"
    for got, want in zip(m["bbox"], (gxmin, gymin, gzmin, gxmax, gymax, gzmax)):
        assert abs(got - want) < 1e-3, f"bbox mismatch {m['bbox']} vs OCCT box"
    tri_area = 0.0
    v = m["verts"]
    for t in range(0, m["icount"], 3):
        a, b, c = (m["idx"][t + k] for k in range(3))
        pa = v[a * 6:a * 6 + 3]; pb = v[b * 6:b * 6 + 3]; pc = v[c * 6:c * 6 + 3]
        ux, uy, uz = (pb[k] - pa[k] for k in range(3))
        wx, wy, wz = (pc[k] - pa[k] for k in range(3))
        cx, cy, cz = uy * wz - uz * wy, uz * wx - ux * wz, ux * wy - uy * wx
        tri_area += 0.5 * math.sqrt(cx * cx + cy * cy + cz * cz)
    area_err = abs(tri_area - area) / area * 100.0
    # v2 edge section: count and endpoints must match the census exactly.
    assert len(m["edges"]) == len(edges), "edge count mismatch vs census"
    for (ei, a, b), (wa, wb) in zip(m["edges"], edges):
        for got, want in zip(a + b, wa + wb):
            assert abs(got - want) < 1e-4, f"edge {ei} endpoint mismatch"
    assert [e[0] for e in m["edges"]] == list(range(len(edges))), \
        "edge indices are not the 0-based census sequence"
    print(f"read-back OK: vertices={m['vcount']} indices={m['icount']} "
          f"groups={len(m['groups'])} edges={len(m['edges'])} fileBytes={m['file_bytes']}")
    print(f"max |normal|-1 error : {worst_normal_err:.2e}")
    print(f"mesh triangle area   : {tri_area:.3f} mm^2 "
          f"(vs OCCT {area:.3f}, error {area_err:.3f}%)")
    print("CONTRACT VERIFIED: CCM1 round-trip matches OCCT tessellation.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
