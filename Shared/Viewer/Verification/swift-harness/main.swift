//
//  main.swift — Swift viewer harness (v0.2.3)
//
//  The first CI gate that EXECUTES the production Swift viewer-feed
//  code. Until v0.2.3 every gate stopped at the C++ boundary: the
//  engine's cc_view_data was proven good while the Swift side —
//  EngineMeshAdapter, MeshBufferLoader, and the vertex-layout
//  contract the Metal renderer describes to the GPU — had never run
//  anywhere but the user's iPad. It shipped broken twice (v0.2:
//  nothing rendered; v0.2.2: a fan of slivers, because the vertex
//  descriptor declared the packed CCM1 file stride 24 while the
//  uploaded [MeshVertex] buffer's real memory stride is 32).
//
//  This harness is compiled by the mc-backend-matrix CI job from the
//  PRODUCTION sources (MeshBuffer.swift, EngineMeshAdapter.swift,
//  EngineProtocol.swift, SharedModels.swift, SceneHelpers.swift,
//  ViewCommands.swift, ViewerBridge.swift, Camera.swift,
//  SceneStore.swift) plus this file, and run against a CCFX fixture
//  produced in the same job by the real engine
//  (Core/native/tests/dump_view_fixture.cpp, mc backend):
//  a 10x2x10 box and a cylinder, as cc_view_data returned them.
//
//  Checks:
//   * adapter + loader round-trip: counts, names, bbox, face groups
//   * signed volume of the parsed mesh > 0 and matching the solid
//     (box exactly 200 mm^3; cylinder within tessellation tolerance)
//   * the GPU read contract: the parsed vertices are re-read from
//     their raw array memory using MeshVertex.bufferStride /
//     bufferNormalOffset — the exact values the renderer's vertex
//     descriptor declares — and must come back identical, with the
//     re-read mesh's signed volume still correct. This is the check
//     whose absence let the v0.2.2 fan ship.
//   * v0.2.4: census edges round-trip (CCFX v2 -> EngineViewObject ->
//     CCM1 v2 -> MeshObject.edges): count, 0-based census sequence,
//     and the box's endpoint set == its 12 geometric edges.
//   * v0.2.4: the LINE path — the one whose absence let the v0.2.3
//     fan ship. The production SceneLineBuilder grid + axis-arrow
//     builders run here on the default scene (box 10x2x10 at the
//     origin); the built [LineVertex] array is re-read through
//     LineVertex.bufferStride / bufferColorOffset (the values the
//     line descriptor declares) and every vertex must come back
//     exact — position AND colour. Arrow length == 20% of the scene
//     diagonal; the mesh edge-overlay builder runs on the parsed box.
//   * v0.2.4: view commands — production ViewCommandParser output for
//     `view rotate` (absolute + by), `view labels edges`, and the
//     production OrbitCamera application of the parsed angles.
//
//  Exit code 0 iff every check passes.
//

import Foundation
import simd

var passCount = 0
var failCount = 0
func check(_ condition: Bool, _ label: String) {
    if condition { passCount += 1; print("PASS: \(label)") }
    else { failCount += 1; print("FAIL: \(label)") }
}
func approx(_ a: Double, _ b: Double, _ tol: Double) -> Bool { abs(a - b) <= tol }

// MARK: - CCFX fixture reader (fixture plumbing, not production code)

struct FixtureObject {
    var name: String
    var vertices: [Float]
    var indices: [Int32]
    var volume: Double
    var bbox: [Double]
    var faceRanges: [EngineViewObject.FaceRange]
    var edges: [EngineViewObject.Edge]
}

struct FixtureReader {
    let data: Data
    var offset = 0
    mutating func bytes(_ n: Int) -> Data {
        defer { offset += n }
        return data.subdata(in: offset..<(offset + n))
    }
    mutating func i32() -> Int32 { bytes(4).withUnsafeBytes { $0.loadUnaligned(as: Int32.self) } }
    mutating func f32() -> Float { Float(bitPattern: UInt32(bitPattern: i32())) }
    mutating func f64() -> Double { bytes(8).withUnsafeBytes { $0.loadUnaligned(as: Double.self) } }
}

func loadFixture(_ path: String) -> [FixtureObject] {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
        print("FAIL: cannot read fixture at \(path)")
        exit(2)
    }
    var r = FixtureReader(data: data)
    let magic = r.bytes(4)
    guard magic == Data("CCFX".utf8) else { print("FAIL: bad fixture magic"); exit(2) }
    let version = r.i32()
    let count = Int(r.i32())
    var out: [FixtureObject] = []
    for _ in 0..<count {
        let nameLen = Int(r.i32())
        let name = String(data: r.bytes(nameLen), encoding: .utf8) ?? ""
        let vc = Int(r.i32())
        let tc = Int(r.i32())
        var verts: [Float] = []
        for _ in 0..<(3 * vc) { verts.append(r.f32()) }
        var idx: [Int32] = []
        for _ in 0..<(3 * tc) { idx.append(r.i32()) }
        let vol = r.f64()
        var bbox: [Double] = []
        for _ in 0..<6 { bbox.append(r.f64()) }
        let frc = Int(r.i32())
        var ranges: [EngineViewObject.FaceRange] = []
        for _ in 0..<frc {
            ranges.append(EngineViewObject.FaceRange(faceIndex: r.i32(),
                                                     indexStart: r.i32(),
                                                     indexCount: r.i32()))
        }
        var edges: [EngineViewObject.Edge] = []
        if version >= 2 {
            let ec = Int(r.i32())
            for _ in 0..<ec {
                let edgeIndex = r.i32()
                let start = [r.f64(), r.f64(), r.f64()]
                let end = [r.f64(), r.f64(), r.f64()]
                edges.append(EngineViewObject.Edge(edgeIndex: edgeIndex,
                                                   start: start, end: end))
            }
        }
        out.append(FixtureObject(name: name, vertices: verts, indices: idx,
                                 volume: vol, bbox: bbox, faceRanges: ranges,
                                 edges: edges))
    }
    return out
}

// MARK: - Geometry helpers over parsed MeshObjects

func signedVolume(_ mesh: MeshObject) -> Double {
    var v = 0.0
    var i = 0
    while i + 2 < mesh.indices.count {
        let a = mesh.vertices[Int(mesh.indices[i])].position
        let b = mesh.vertices[Int(mesh.indices[i + 1])].position
        let c = mesh.vertices[Int(mesh.indices[i + 2])].position
        let cr = simd_cross(b, c)
        v += Double(a.x * cr.x + a.y * cr.y + a.z * cr.z) / 6.0
        i += 3
    }
    return v
}

func derivedBBox(_ mesh: MeshObject) -> (SIMD3<Float>, SIMD3<Float>) {
    var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
    var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
    for vtx in mesh.vertices {
        lo = simd_min(lo, vtx.position)
        hi = simd_max(hi, vtx.position)
    }
    return (lo, hi)
}

// MARK: - Run

guard CommandLine.arguments.count > 1 else {
    print("usage: swift_viewer_harness <fixture.ccfx>")
    exit(2)
}
let fixture = loadFixture(CommandLine.arguments[1])
check(fixture.count == 2, "fixture holds 2 objects (got \(fixture.count))")

let engineObjects = fixture.map {
    EngineViewObject(name: $0.name, vertices: $0.vertices, indices: $0.indices,
                     volume: $0.volume, bbox: $0.bbox, faceRanges: $0.faceRanges,
                     edges: $0.edges)
}

let meshes: [MeshObject]
do {
    meshes = try EngineMeshAdapter.meshObjects(from: engineObjects)
    check(true, "EngineMeshAdapter.meshObjects + MeshBufferLoader parse the fixture")
} catch {
    check(false, "EngineMeshAdapter.meshObjects threw: \(error)")
    print("RESULT: \(passCount) pass, \(failCount) fail (swift viewer harness)")
    exit(1)
}
check(meshes.count == fixture.count, "parsed object count == \(fixture.count) (got \(meshes.count))")

for (fx, mesh) in zip(fixture, meshes) {
    let triCount = fx.indices.count / 3
    check(mesh.id == fx.name, "\(fx.name): name survives the round trip")
    check(mesh.vertices.count == 3 * triCount && mesh.indices.count == 3 * triCount,
          "\(fx.name): unwelded counts vertices == indices == \(3 * triCount) (got \(mesh.vertices.count)/\(mesh.indices.count))")
    let vol = signedVolume(mesh)
    check(vol > 0, "\(fx.name): signed volume > 0 (got \(vol))")
    let (lo, hi) = derivedBBox(mesh)
    // The parsed vertices must stay inside the engine's bbox and
    // (within the tessellation deflection) reach it.
    let inside = lo.x >= Float(fx.bbox[0]) - 1e-3 && lo.y >= Float(fx.bbox[1]) - 1e-3 &&
                 lo.z >= Float(fx.bbox[2]) - 1e-3 && hi.x <= Float(fx.bbox[3]) + 1e-3 &&
                 hi.y <= Float(fx.bbox[4]) + 1e-3 && hi.z <= Float(fx.bbox[5]) + 1e-3
    check(inside, "\(fx.name): parsed vertices inside engine bbox")

    if fx.name == "test" {
        check(approx(vol, 200.0, 0.01), "test: signed volume == 200 (got \(vol))")
        let exact = approx(Double(lo.x), 0, 1e-4) && approx(Double(lo.y), 0, 1e-4) &&
                    approx(Double(lo.z), 0, 1e-4) && approx(Double(hi.x), 10, 1e-4) &&
                    approx(Double(hi.y), 2, 1e-4) && approx(Double(hi.z), 10, 1e-4)
        check(exact, "test: derived bbox == [0 0 0 .. 10 2 10] (got [\(lo) .. \(hi)])")
        check(mesh.faceGroups.count == 6, "test: 6 face groups (got \(mesh.faceGroups.count))")
        var partition = mesh.faceGroups.count == 6
        var cursor: UInt32 = 0
        for (i, g) in mesh.faceGroups.enumerated() {
            if g.sourceFaceIndex != UInt32(i) || g.indexStart != cursor ||
               g.vertexStart != g.indexStart || g.vertexCount != g.indexCount {
                partition = false
            }
            cursor += g.indexCount
        }
        if cursor != UInt32(mesh.indices.count) { partition = false }
        check(partition, "test: face groups are census-ordered and partition the index buffer")
    }
    if fx.name == "cyl" {
        let analytic = Double.pi * 9.0 * 12.0
        check(vol > 0.95 * analytic && vol < 1.001 * analytic,
              "cyl: signed volume within tessellation tolerance of \(analytic) (got \(vol))")
        let reach = Double(hi.x - lo.x) > 5.4 && Double(hi.y - lo.y) > 5.4 &&
                    approx(Double(hi.z - lo.z), 12.0, 1e-3)
        check(reach, "cyl: derived bbox reaches the engine bbox (size \(hi - lo))")
    }

    // Census edges (v0.2.4): the fixture's cc_view_data edges must
    // survive EngineViewObject -> CCM1 v2 -> MeshObject.edges with
    // indices and endpoints intact — these are the numbers the
    // viewer's edge labels print and `fillet ... edges i` accepts
    // (the backend-side census proof lives in the C++ suites).
    check(mesh.edges.count == fx.edges.count,
          "\(fx.name): edge count survives the round trip (\(mesh.edges.count) vs \(fx.edges.count))")
    var edgeSeq = mesh.edges.count == fx.edges.count
    for (j, e) in mesh.edges.enumerated() {
        if e.edgeIndex != UInt32(j) || e.edgeIndex != UInt32(fx.edges[j].edgeIndex) { edgeSeq = false }
        if !approx(Double(e.start.x), fx.edges[j].start[0], 1e-4) ||
           !approx(Double(e.start.y), fx.edges[j].start[1], 1e-4) ||
           !approx(Double(e.start.z), fx.edges[j].start[2], 1e-4) ||
           !approx(Double(e.end.x), fx.edges[j].end[0], 1e-4) ||
           !approx(Double(e.end.y), fx.edges[j].end[1], 1e-4) ||
           !approx(Double(e.end.z), fx.edges[j].end[2], 1e-4) { edgeSeq = false }
    }
    check(edgeSeq, "\(fx.name): edge indices are the census sequence and endpoints are intact")
    if fx.name == "test" {
        check(mesh.edges.count == 12, "test: box carries 12 census edges (got \(mesh.edges.count))")
        func key(_ p: SIMD3<Float>) -> String {
            String(format: "%.3f,%.3f,%.3f", Double(p.x), Double(p.y), Double(p.z))
        }
        let corners: [SIMD3<Float>] = [
            SIMD3(0, 0, 0), SIMD3(10, 0, 0), SIMD3(10, 2, 0), SIMD3(0, 2, 0),
            SIMD3(0, 0, 10), SIMD3(10, 0, 10), SIMD3(10, 2, 10), SIMD3(0, 2, 10)]
        let pairs = [(0, 1), (1, 2), (2, 3), (3, 0), (4, 5), (5, 6),
                     (6, 7), (7, 4), (0, 4), (1, 5), (2, 6), (3, 7)]
        var want = Set<String>()
        for (a, b) in pairs {
            let ka = key(corners[a]), kb = key(corners[b])
            want.insert(ka < kb ? "\(ka)|\(kb)" : "\(kb)|\(ka)")
        }
        var got = Set<String>()
        for e in mesh.edges {
            let ka = key(e.start), kb = key(e.end)
            got.insert(ka < kb ? "\(ka)|\(kb)" : "\(kb)|\(ka)")
        }
        check(got == want, "test: edge endpoint set == the box's 12 geometric edges")
    }

    // The GPU read contract — the v0.2.2 regression check. The
    // renderer uploads [MeshVertex] verbatim and the vertex
    // descriptor fetches position at (i * bufferStride) and normal
    // at (i * bufferStride + bufferNormalOffset). Re-read the raw
    // array memory with exactly those parameters: every vertex must
    // come back identical, and the re-read mesh must keep its
    // signed volume. With the shipped v0.2.2 constants (24/12) this
    // check fails on 32 of 36 box vertices and the volume is wrong.
    let rawCount = mesh.vertices.withUnsafeBytes { $0.count }
    check(rawCount == mesh.vertices.count * MeshVertex.bufferStride,
          "\(fx.name): vertex array byte count == count * bufferStride (\(rawCount) vs \(mesh.vertices.count * MeshVertex.bufferStride))")
    var rereadOK = true
    var rereadVolume = 0.0
    mesh.vertices.withUnsafeBytes { raw in
        guard let base = raw.baseAddress else { rereadOK = false; return }
        func f3(_ byteOffset: Int) -> SIMD3<Float> {
            SIMD3<Float>(base.loadUnaligned(fromByteOffset: byteOffset, as: Float.self),
                         base.loadUnaligned(fromByteOffset: byteOffset + 4, as: Float.self),
                         base.loadUnaligned(fromByteOffset: byteOffset + 8, as: Float.self))
        }
        var positions: [SIMD3<Float>] = []
        for i in mesh.vertices.indices {
            let p = f3(i * MeshVertex.bufferStride)
            let n = f3(i * MeshVertex.bufferStride + MeshVertex.bufferNormalOffset)
            if p != mesh.vertices[i].position || n != mesh.vertices[i].normal { rereadOK = false }
            positions.append(p)
        }
        var i = 0
        while i + 2 < mesh.indices.count {
            let a = positions[Int(mesh.indices[i])]
            let b = positions[Int(mesh.indices[i + 1])]
            let c = positions[Int(mesh.indices[i + 2])]
            let cr = simd_cross(b, c)
            rereadVolume += Double(a.x * cr.x + a.y * cr.y + a.z * cr.z) / 6.0
            i += 3
        }
    }
    check(rereadOK, "\(fx.name): GPU-layout re-read (stride \(MeshVertex.bufferStride), normal offset \(MeshVertex.bufferNormalOffset)) reproduces every vertex")
    check(approx(rereadVolume, vol, 0.01) && rereadVolume > 0,
          "\(fx.name): GPU-layout re-read keeps signed volume (got \(rereadVolume))")
}

// MARK: - Line path (v0.2.4) — the fan regression gate
//
// The v0.2.3 device verdict: the box rendered solid but a fan of thin
// coloured lines radiated from its origin corner. Root cause (proven
// numerically, FIXLOG v0.2.4): LineVertex's real layout is stride 48
// / colour offset 32, while the line descriptor declared 32/16 and
// every line buffer copy truncated to count*32 bytes — 0 of the
// default scene's 53 segments survived the GPU read. This section
// executes the PRODUCTION builders for the exact default scene and
// re-reads the built array through the descriptor's declared layout.

func rereadLines(_ lines: [LineVertex]) -> [LineVertex] {
    var out: [LineVertex] = []
    lines.withUnsafeBytes { raw in
        guard let base = raw.baseAddress else { return }
        func f(_ off: Int) -> Float { base.loadUnaligned(fromByteOffset: off, as: Float.self) }
        for i in lines.indices {
            let b = i * LineVertex.bufferStride
            let p = SIMD3<Float>(f(b), f(b + 4), f(b + 8))
            let co = LineVertex.bufferColorOffset
            let c = SIMD4<Float>(f(b + co), f(b + co + 4), f(b + co + 8), f(b + co + 12))
            out.append(LineVertex(p, c))
        }
    }
    return out
}

check(LineVertex.bufferStride == 48 && LineVertex.bufferColorOffset == 32,
      "LineVertex memory layout is stride 48 / colour offset 32 (got \(LineVertex.bufferStride)/\(LineVertex.bufferColorOffset))")

let sceneLo = SIMD3<Float>(0, 0, 0)
let sceneHi = SIMD3<Float>(10, 2, 10)
let sceneCentre = SIMD3<Float>(5, 1, 5)
let grid = SceneLineBuilder.gridLines(lo: sceneLo, hi: sceneHi, centre: sceneCentre)
check(grid.count == 100, "grid builder: default scene grid has 100 vertices (got \(grid.count))")
let diagonal = SceneLineBuilder.sceneDiagonal(lo: sceneLo, hi: sceneHi)
let arrows = SceneLineBuilder.axisArrowLines(diagonal: diagonal)
check(arrows.count == 54, "arrow builder: 3 arrows x 18 vertices (got \(arrows.count))")
let defaultLines = grid + arrows
check(rereadLines(defaultLines) == defaultLines,
      "line GPU read: all \(defaultLines.count) default-scene line vertices (grid + arrows) re-read exact through stride \(LineVertex.bufferStride)/offset \(LineVertex.bufferColorOffset)")
let defaultRaw = defaultLines.withUnsafeBytes { $0.count }
check(defaultRaw == defaultLines.count * LineVertex.bufferStride,
      "line array byte count == count * bufferStride (\(defaultRaw))")

let arrowLen = SceneLineBuilder.axisArrowLength(diagonal: diagonal)
check(approx(Double(arrowLen), 0.2 * Double(diagonal), 1e-4),
      "arrow length == 20% of scene diagonal (\(arrowLen) vs \(0.2 * diagonal))")
check(SceneLineBuilder.axisArrowLength(diagonal: 1.0) == SceneLineBuilder.axisArrowMinimum,
      "arrow length floors at the minimum on tiny scenes")
var arrowsBounded = true
for v in arrows where simd_length(v.position) > arrowLen + 1e-4 { arrowsBounded = false }
check(arrowsBounded, "no arrow vertex reaches beyond the arrow length from the origin")
let tips = SceneLineBuilder.axisArrowTips(diagonal: diagonal)
check(tips.count == 3 && tips[0].label == "X" && tips[1].label == "Y" && tips[2].label == "Z" &&
      tips[0].tip == SIMD3<Float>(arrowLen, 0, 0) && tips[1].tip == SIMD3<Float>(0, arrowLen, 0) &&
      tips[2].tip == SIMD3<Float>(0, 0, arrowLen),
      "arrow tips sit at (L,0,0), (0,L,0), (0,0,L) with X/Y/Z labels")

// Edge-overlay builder on the parsed box mesh (production input: the
// unwelded MeshObject the renderer holds).
if let boxMesh = meshes.first(where: { $0.id == "test" }) {
    let overlay = SceneLineBuilder.meshEdgeLines(vertices: boxMesh.vertices,
                                                 indices: boxMesh.indices)
    check(overlay.count == 72,
          "edge overlay builder: unwelded box yields 36 segments (got \(overlay.count / 2))")
    func key(_ p: SIMD3<Float>) -> String {
        String(format: "%.3f,%.3f,%.3f", Double(p.x), Double(p.y), Double(p.z))
    }
    let corners: [SIMD3<Float>] = [
        SIMD3(0, 0, 0), SIMD3(10, 0, 0), SIMD3(10, 2, 0), SIMD3(0, 2, 0),
        SIMD3(0, 0, 10), SIMD3(10, 0, 10), SIMD3(10, 2, 10), SIMD3(0, 2, 10)]
    let pairs = [(0, 1), (1, 2), (2, 3), (3, 0), (4, 5), (5, 6),
                 (6, 7), (7, 4), (0, 4), (1, 5), (2, 6), (3, 7)]
    var want = Set<String>()
    for (a, b) in pairs {
        let ka = key(corners[a]), kb = key(corners[b])
        want.insert(ka < kb ? "\(ka)|\(kb)" : "\(kb)|\(ka)")
    }
    var got = Set<String>()
    var overlayColorsOK = true
    var i = 0
    while i + 1 < overlay.count {
        let ka = key(overlay[i].position), kb = key(overlay[i + 1].position)
        got.insert(ka < kb ? "\(ka)|\(kb)" : "\(kb)|\(ka)")
        if overlay[i].color != SceneLineBuilder.edgeOverlayColor ||
           overlay[i + 1].color != SceneLineBuilder.edgeOverlayColor { overlayColorsOK = false }
        i += 2
    }
    // The overlay is built from the UNWELDED mesh (one vertex per
    // triangle corner), so its distinct position pairs are the 12
    // geometric edges PLUS one triangulation diagonal per face —
    // 18 pairs, not 12. (The census edges in MeshObject.edges are
    // the backend's true 12; the overlay is a triangle-soup view.)
    let quads = [(0, 1, 2, 3), (4, 5, 6, 7), (0, 1, 5, 4),
                 (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    var allowed = want
    for q in quads {
        for (a, b) in [(q.0, q.2), (q.1, q.3)] {
            let ka = key(corners[a]), kb = key(corners[b])
            allowed.insert(ka < kb ? "\(ka)|\(kb)" : "\(kb)|\(ka)")
        }
    }
    check(got.count == 18 && want.isSubset(of: got) && got.isSubset(of: allowed),
          "edge overlay: distinct segment pairs == 12 geometric edges + 6 face diagonals (got \(got.count))")
    check(overlayColorsOK, "edge overlay: every vertex carries the overlay colour")
    check(rereadLines(overlay) == overlay,
          "edge overlay: vertices re-read exact through the line layout")
}

// MARK: - View commands (v0.2.4): rotate + labels edges
//
// Production parser output, then the production OrbitCamera
// application of the parsed angles (the same calls Renderer.apply
// makes), driven through a SceneStore holding the parsed box.

func parsed(_ line: String) -> ViewerCommand? {
    if case .success(let cmd) = ViewCommandParser.parse(line) { return cmd }
    return nil
}
check(parsed("view rotate 45 30") == .setCameraRotation(azimuthDegrees: 45, elevationDegrees: 30),
      "parse: view rotate 45 30 -> setCameraRotation(45, 30)")
check(parsed("view rotate by 10 -5") == .rotateCameraBy(azimuthDegrees: 10, elevationDegrees: -5),
      "parse: view rotate by 10 -5 -> rotateCameraBy(10, -5)")
check(parsed("view labels edges on") == .setEdgeLabelsEnabled(true),
      "parse: view labels edges on -> setEdgeLabelsEnabled(true)")
check(parsed("view labels edges off") == .setEdgeLabelsEnabled(false),
      "parse: view labels edges off -> setEdgeLabelsEnabled(false)")
check(parsed("view labels faces on") == .setFaceLabelsEnabled(true),
      "parse: view labels faces on still -> setFaceLabelsEnabled(true)")
check(parsed("view rotate 45") == nil && parsed("view rotate by 10") == nil &&
      parsed("view labels edges") == nil && parsed("view labels bogus on") == nil,
      "parse: malformed rotate/labels forms are rejected")

let store = SceneStore()
if let boxMesh = meshes.first(where: { $0.id == "test" }) {
    _ = store.load(boxMesh, props: ObjectDisplayProps())
}
if case .setCameraRotation(let az, let el) = parsed("view rotate 45 30") {
    store.camera.setRotation(azimuthDegrees: az, elevationDegrees: el)
}
check(approx(Double(store.camera.azimuth), Double.pi / 4, 1e-5) &&
      approx(Double(store.camera.elevation), Double.pi / 6, 1e-5),
      "camera: after view rotate 45 30, azimuth == 45 deg, elevation == 30 deg (got \(store.camera.azimuth), \(store.camera.elevation))")
if case .rotateCameraBy(let dAz, let dEl) = parsed("view rotate by 45 -30") {
    store.camera.rotateBy(azimuthDegrees: dAz, elevationDegrees: dEl)
}
check(approx(Double(store.camera.azimuth), Double.pi / 2, 1e-5) &&
      approx(Double(store.camera.elevation), 0, 1e-5),
      "camera: after view rotate by 45 -30, azimuth == 90 deg, elevation == 0 (got \(store.camera.azimuth), \(store.camera.elevation))")
var clampedCam = OrbitCamera()
clampedCam.setRotation(azimuthDegrees: 0, elevationDegrees: 120)
check(approx(Double(clampedCam.elevation), 89.9 * Double.pi / 180, 1e-5),
      "camera: view rotate elevation clamps at 89.9 deg (got \(clampedCam.elevation))")

// Pin the ABI facts the descriptor relies on: if a future toolchain
// changed the SIMD layout, the MemoryLayout-derived constants would
// move with it and stay correct — this check exists to force a
// human look at that moment, not to freeze the ABI.
check(MeshVertex.bufferStride == 32 && MeshVertex.bufferNormalOffset == 16,
      "MeshVertex memory layout is stride 32 / normal offset 16 (got \(MeshVertex.bufferStride)/\(MeshVertex.bufferNormalOffset))")
check(MeshVertex.stride == 24, "CCM1 file stride stays 24 (packed file format)")

print("RESULT: \(passCount) pass, \(failCount) fail (swift viewer harness)")
exit(failCount == 0 ? 0 : 1)
