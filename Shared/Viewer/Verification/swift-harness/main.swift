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
//  a 10x2x10 box and a cylinder, as cc_view_data returned them
//  (v0.3.0: under their qualified names box:test / cylinder:cyl).
//
//  v0.3.0 extends the same principle to the MODEL layer: the harness
//  also compiles Shared/Model (CascadeNames, CommandSpecs, ModelStep,
//  ProjectFile) and runs it against a second fixture from the same
//  tool — a 10-step UI scenario the mc backend executed, with the
//  engine-assigned qualified names and volumes — asserting the
//  production ReplayBuilder reproduces the engine's lines, names,
//  suffix behaviour and directory grouping exactly, plus the project
//  file's Codable round-trip, legacy migration and folder rules.
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
    print("usage: swift_viewer_harness <fixture.ccfx> [fixture_ns.txt]")
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

    if fx.name == "box:test" {
        check(approx(vol, 200.0, 0.01), "box:test: signed volume == 200 (got \(vol))")
        let exact = approx(Double(lo.x), 0, 1e-4) && approx(Double(lo.y), 0, 1e-4) &&
                    approx(Double(lo.z), 0, 1e-4) && approx(Double(hi.x), 10, 1e-4) &&
                    approx(Double(hi.y), 2, 1e-4) && approx(Double(hi.z), 10, 1e-4)
        check(exact, "box:test: derived bbox == [0 0 0 .. 10 2 10] (got [\(lo) .. \(hi)])")
        check(mesh.faceGroups.count == 6, "box:test: 6 face groups (got \(mesh.faceGroups.count))")
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
        check(partition, "box:test: face groups are census-ordered and partition the index buffer")
    }
    if fx.name == "cylinder:cyl" {
        let analytic = Double.pi * 9.0 * 12.0
        check(vol > 0.95 * analytic && vol < 1.001 * analytic,
              "cylinder:cyl: signed volume within tessellation tolerance of \(analytic) (got \(vol))")
        let reach = Double(hi.x - lo.x) > 5.4 && Double(hi.y - lo.y) > 5.4 &&
                    approx(Double(hi.z - lo.z), 12.0, 1e-3)
        check(reach, "cylinder:cyl: derived bbox reaches the engine bbox (size \(hi - lo))")
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
    if fx.name == "box:test" {
        check(mesh.edges.count == 12, "box:test: box carries 12 census edges (got \(mesh.edges.count))")
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
        check(got == want, "box:test: edge endpoint set == the box's 12 geometric edges")
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
if let boxMesh = meshes.first(where: { $0.id == "box:test" }) {
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
if let boxMesh = meshes.first(where: { $0.id == "box:test" }) {
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

// MARK: - Model layer (v0.3.0): names, specs, replay, project file
//
// The second fixture (fixture_ns.txt) was produced in the same CI
// job by dump_view_fixture running a 10-step UI scenario on the REAL
// mc backend: every step's engine-assigned qualified name and volume
// was verified there against analytic values, the final object name
// set recorded, and a fresh-session replay of the same lines proven
// to reproduce it. Below, the PRODUCTION Swift model layer rebuilds
// the identical steps and must agree with the engine exactly —
// lines, auto-names, suffixes, directory grouping — and the project
// file machinery (round-trip, legacy migration, folder rules) runs
// its own checks. This is the v0.2.2/v0.2.3/v0.2.4 lesson applied to
// the new layer: a production Swift path CI never executes is where
// the next device bug lives.

if CommandLine.arguments.count > 2 {
    let nsPath = CommandLine.arguments[2]
    let nsText = (try? String(contentsOfFile: nsPath, encoding: .utf8)) ?? ""
    check(!nsText.isEmpty, "ns fixture: readable at \(nsPath)")
    struct NSRow {
        var command: String; var name: String; var params: [String: String]
        var line: String; var assigned: String; var volume: Double
    }
    var nsRows: [NSRow] = []
    var nsNames: [String] = []
    var nsReplayOK = false
    for rawLine in nsText.split(separator: "\n") {
        let fields = rawLine.split(separator: "\t", omittingEmptySubsequences: false)
            .map(String.init)
        guard let kind = fields.first else { continue }
        if kind == "step", fields.count == 7 {
            var params: [String: String] = [:]
            for pair in fields[3].split(separator: ";", omittingEmptySubsequences: false) {
                let kv = pair.split(separator: "=", maxSplits: 1,
                                    omittingEmptySubsequences: false).map(String.init)
                if kv.count == 2 { params[kv[0]] = kv[1] }
                else if kv.count == 1 { params[kv[0]] = "" }
            }
            nsRows.append(NSRow(command: fields[1], name: fields[2], params: params,
                                line: fields[4], assigned: fields[5],
                                volume: Double(fields[6]) ?? .nan))
        } else if kind == "names", fields.count == 2 {
            nsNames = fields[1].split(separator: ",").map(String.init)
        } else if kind == "replay" {
            nsReplayOK = fields.count == 2 && fields[1] == "ok"
        }
    }
    check(nsRows.count == 10, "ns fixture: 10 scenario steps (got \(nsRows.count))")
    check(nsReplayOK, "ns fixture: the engine-side fresh-session replay reproduced the model")

    // The engine-verified volumes for the analytic steps (the dump
    // tool asserted them against the backend; restated here so a
    // fixture mix-up can't pass silently).
    let analyticVolumes: [String: Double] = [
        "box:part": 1000, "box:part2": 1000, "cylinder:cylinder1": 785.3981634,
        "cut:part": 803.6504592, "translate:moved": 1000, "extrude:plate": 500,
        "box:part3": 1000, "box:box1": 1,
    ]
    for row in nsRows {
        if let want = analyticVolumes[row.assigned] {
            check(approx(row.volume, want, 0.01),
                  "ns fixture: \(row.assigned) volume == \(want) (got \(row.volume))")
        }
    }

    // ReplayBuilder parity: the production builder, fed the same
    // steps, must produce the engine's lines and predicted names.
    let nsSteps = nsRows.map { ModelStep(command: $0.command, params: $0.params, name: $0.name) }
    let built = ReplayBuilder.build(steps: nsSteps)
    check(built.count == nsRows.count, "replay builder: one built step per scenario step")
    for (b, row) in zip(built, nsRows) {
        check(b.buildError == nil && b.line == row.line,
              "replay builder: \(row.command) '\(row.name)' line == \"\(row.line)\" (got \"\(b.line ?? "nil")\")")
        check(b.predictedName == row.assigned,
              "replay builder: \(row.command) '\(row.name)' predicted name == \(row.assigned) (got \(b.predictedName ?? "nil"))")
    }
    let predictedObjects = built.compactMap { $0.predictedName }
        .filter { CascadeNames.directory(of: $0) != "profile" }
    check(Set(predictedObjects) == Set(nsNames),
          "replay builder: final object name set == the engine's (\(nsNames.count) names)")

    // Directory grouping of the final set (the part tree's shape).
    let groups = CascadeNames.grouped(nsNames + ["profile:prof"])
    check(groups.map { $0.directory } == ["box", "cylinder", "profile", "extrude", "cut", "fillet", "translate"],
          "grouping: directories in canonical order (got \(groups.map { $0.directory }))")
    check(groups.first { $0.directory == "box" }?.names ==
          ["box:box1", "box:part", "box:part2", "box:part3"],
          "grouping: box/ holds its four objects sorted, cut:part separate from box:part")

    // CascadeNames unit parity with the engine's claim rule.
    check(CascadeNames.uniqueName(directory: "box", requested: "part",
                                  existing: ["box:part"]) == "part2",
          "names: same-directory duplicate suffixes (part -> part2)")
    check(CascadeNames.uniqueName(directory: "box", requested: "part2",
                                  existing: ["box:part2"]) == "part3",
          "names: trailing number increments (part2 -> part3)")
    check(CascadeNames.uniqueName(directory: "box", requested: "x",
                                  existing: ["cut:x"]) == "x",
          "names: another directory's name never forces a suffix")
    check(CascadeNames.autoName(directory: "box",
                                existing: ["box:box1", "box:box3"]) == "box2",
          "names: auto-name takes the lowest free number")
    check(CascadeNames.autoName(directory: "cut", existing: []) == "cut1",
          "names: auto-name in an empty directory is <command>1")
    check(CascadeNames.directory(of: "cut:part") == "cut" &&
          CascadeNames.display(of: "cut:part") == "part" &&
          CascadeNames.qualify(directory: "cut", display: "part") == "cut:part",
          "names: qualified/display split + join round-trips")

    // CommandSpecs sanity: the UI list is exactly the implemented
    // step commands, every one in a known directory + group.
    check(CommandCatalog.all.count == 21,
          "specs: 21 UI step commands (got \(CommandCatalog.all.count))")
    check(CommandCatalog.all.allSatisfy { CascadeNames.directoryOrder.contains($0.directory) },
          "specs: every command's directory is a known name directory")
    check(CommandCatalog.all.allSatisfy { CommandCatalog.groupOrder.contains($0.group) },
          "specs: every command sits in a displayed group")
    check(CommandCatalog.all.allSatisfy { spec in
        spec.defaultParams.count == spec.params.count &&
        Set(spec.params.map { $0.key }).count == spec.params.count
    }, "specs: defaults cover every parameter exactly once")
    check(CommandCatalog.spec(for: "extrude")?.param("profile")?.type == .profileRef &&
          CommandCatalog.spec(for: "cut")?.param("b")?.type == .objectRef &&
          CommandCatalog.spec(for: "fillet")?.param("edges")?.defaultValue == "",
          "specs: reference parameters are picker-fed, fillet edges default to all")

    // StepLineBuilder rendering details the fixture doesn't cover.
    check(StepLineBuilder.formatNumber("10") == "10" &&
          StepLineBuilder.formatNumber("2.5") == "2.5" &&
          StepLineBuilder.formatNumber(" -3 ") == "-3" &&
          StepLineBuilder.formatNumber("abc") == nil,
          "line builder: canonical number rendering")
    let atStep = ModelStep(command: "box",
                           params: ["width": "1", "depth": "1", "height": "1",
                                    "atX": "5", "atY": "0", "atZ": "0"], name: "b")
    check(StepLineBuilder.line(for: atStep, resultDisplayName: "b") == "box b 1 1 1 at 5,0,0",
          "line builder: non-zero origin emits the at clause")
    let rotStep = ModelStep(command: "rotate",
                            params: ["source": "box:b", "axisX": "0", "axisY": "0",
                                     "axisZ": "1", "angle": "45",
                                     "aboutX": "1", "aboutY": "0", "aboutZ": "0"], name: "r")
    check(StepLineBuilder.line(for: rotStep, resultDisplayName: "r") ==
          "rotate r box:b 0 0 1 45 about 1,0,0",
          "line builder: rotate emits the about clause only when non-zero")
    let badStep = ModelStep(command: "box",
                            params: ["width": "wide", "depth": "1", "height": "1",
                                     "atX": "0", "atY": "0", "atZ": "0"], name: "b")
    check(StepLineBuilder.line(for: badStep, resultDisplayName: "b") == nil,
          "line builder: a non-numeric parameter fails the build instead of emitting a bad line")

    // v0.4.0 command expansion: StepLineBuilder emission for the
    // six new step commands + catalog presence + ReplayBuilder
    // naming in the new directories.
    let profStep = ModelStep(command: "profile",
                             params: ["points": "10,0 14,0 14,6 10,6"], name: "tube")
    let revStep = ModelStep(command: "revolve",
                            params: ["profile": "profile:tube", "angle": "360"], name: "rv")
    check(StepLineBuilder.line(for: revStep, resultDisplayName: "rv") ==
          "revolve rv profile:tube 360",
          "line builder: revolve emits profile + angle")
    let loftStep = ModelStep(command: "loft",
                             params: ["profileA": "profile:a", "zA": "0",
                                      "profileB": "profile:b", "zB": "10",
                                      "profileC": "", "zC": "20", "style": "ruled"], name: "lf")
    check(StepLineBuilder.line(for: loftStep, resultDisplayName: "lf") ==
          "loft lf profile:a@0 profile:b@10 ruled",
          "line builder: loft emits sections@heights, optional C omitted, ruled kept")
    let loftStepC = ModelStep(command: "loft",
                              params: ["profileA": "profile:a", "zA": "0",
                                       "profileB": "profile:b", "zB": "10",
                                       "profileC": "profile:c", "zC": "25", "style": "smooth"], name: "lf")
    check(StepLineBuilder.line(for: loftStepC, resultDisplayName: "lf") ==
          "loft lf profile:a@0 profile:b@10 profile:c@25",
          "line builder: loft with a third section, smooth emits no style token")
    let sweepStep = ModelStep(command: "sweep",
                              params: ["profile": "profile:sq", "path": "0,0,0  0,0,30"], name: "sw")
    check(StepLineBuilder.line(for: sweepStep, resultDisplayName: "sw") ==
          "sweep sw profile:sq 0,0,0 0,0,30",
          "line builder: sweep normalises the path point list")
    let shellStep = ModelStep(command: "shell",
                              params: ["source": "box:b", "thickness": "2"], name: "sh")
    check(StepLineBuilder.line(for: shellStep, resultDisplayName: "sh") ==
          "shell sh box:b 2",
          "line builder: shell emits source + thickness")
    let mirrorStep = ModelStep(command: "mirror",
                               params: ["source": "box:b", "plane": "YZ", "offset": "0"], name: "mi")
    check(StepLineBuilder.line(for: mirrorStep, resultDisplayName: "mi") ==
          "mirror mi box:b yz 0",
          "line builder: mirror lowercases the plane token")
    let badMirror = ModelStep(command: "mirror",
                              params: ["source": "box:b", "plane": "ab", "offset": "0"], name: "mi")
    check(StepLineBuilder.line(for: badMirror, resultDisplayName: "mi") == nil,
          "line builder: mirror with an unknown plane fails the build")
    let patLin = ModelStep(command: "pattern",
                           params: ["source": "box:b", "kind": "linear", "count": "3",
                                    "dx": "15", "dy": "0", "dz": "0",
                                    "angle": "360", "axis": "z"], name: "pt")
    check(StepLineBuilder.line(for: patLin, resultDisplayName: "pt") ==
          "pattern pt box:b linear 3 15 0 0",
          "line builder: linear pattern emits count + step vector")
    let patCirc = ModelStep(command: "pattern",
                            params: ["source": "box:b", "kind": "circular", "count": "4",
                                     "dx": "15", "dy": "0", "dz": "0",
                                     "angle": "360", "axis": "z"], name: "pt")
    check(StepLineBuilder.line(for: patCirc, resultDisplayName: "pt") ==
          "pattern pt box:b circular 4 360 z",
          "line builder: circular pattern emits count + total angle + axis")
    check(CommandCatalog.spec(for: "revolve") != nil &&
          CommandCatalog.spec(for: "loft") != nil &&
          CommandCatalog.spec(for: "sweep") != nil &&
          CommandCatalog.spec(for: "shell") != nil &&
          CommandCatalog.spec(for: "mirror") != nil &&
          CommandCatalog.spec(for: "pattern") != nil &&
          CommandCatalog.all.count == 21,
          "specs: the six v0.4.0 commands are in the panel catalog (21 total)")
    let v4Built = ReplayBuilder.build(steps: [profStep, revStep])
    check(v4Built.count == 2 && v4Built[1].predictedName == "revolve:rv" &&
          v4Built[1].line == "revolve rv profile:tube 360",
          "replay builder: revolve step predicts revolve:rv with the emitted line")

    // v0.4.1 audit regressions: the consumed-source set the app
    // uses to hide a step's sources in the viewer (a fillet's box,
    // a cut's target + tool), and the edge-list whitespace
    // normalisation in the line builder.
    let filletStep = ModelStep(command: "fillet",
                               params: ["source": "box:b", "radius": "1", "edges": ""],
                               name: "f")
    check(filletStep.consumedObjectNames == ["box:b"],
          "consumed sources: fillet consumes its source object")
    let cutStep = ModelStep(command: "cut",
                            params: ["a": "box:t", "b": "box:c"], name: "r")
    check(cutStep.consumedObjectNames == ["box:t", "box:c"],
          "consumed sources: cut consumes target AND tool")
    let extrudeStep = ModelStep(command: "extrude",
                                params: ["profile": "profile:sq", "distance": "10"],
                                name: "e")
    check(extrudeStep.consumedObjectNames.isEmpty,
          "consumed sources: extrude consumes no OBJECT (profileRefs are not scene objects)")
    let spacedEdges = ModelStep(command: "fillet",
                                params: ["source": "box:b", "radius": "1",
                                         "edges": "0, 1, 2"], name: "f")
    check(StepLineBuilder.line(for: spacedEdges, resultDisplayName: "f") ==
          "fillet f box:b 1 edges 0,1,2",
          "line builder: edge list typed with spaces is normalised to one token")

    // ProjectFile: Codable round-trip with steps, folders, viewer.
    var project = ProjectFile()
    project.steps = nsSteps
    let asm = project.addFolder(name: "Assembly", parentID: nil)
    let sub = project.addFolder(name: "Fasteners", parentID: asm.id)
    project.moveObject("box:part", toFolder: sub.id)
    project.viewer.grid = false
    project.viewer.displayMode = "shadedEdges"
    project.viewer.cameraAzimuthDegrees = 45
    do {
        let data = try project.encoded()
        let back = try ProjectFile.decoded(from: data)
        check(back == project, "project file: encode/decode round-trips steps, folders, assignments, viewer")
        check(back.steps.count == 10 && back.folderID(forObject: "box:part") == sub.id,
              "project file: step list and object->folder assignment survive")
    } catch {
        check(false, "project file: round-trip threw \(error)")
    }
    check((try? ProjectFile.decoded(from: Data("{\"format\":\"nope\"}".utf8))) == nil,
          "project file: a foreign format tag is rejected")

    // Folder rules: delete reparents children + objects upward.
    var folderCase = project
    folderCase.deleteFolder(id: sub.id)
    check(folderCase.folderID(forObject: "box:part") == asm.id &&
          folderCase.childFolders(of: asm.id).isEmpty,
          "folders: deleting a folder moves its objects to the parent")
    folderCase.deleteFolder(id: asm.id)
    check(folderCase.folderID(forObject: "box:part") == nil && folderCase.folders.isEmpty,
          "folders: deleting the parent then files objects at the root")
    check(project.descendantFolderIDs(of: asm.id) == [sub.id],
          "folders: descendant walk finds the nested folder")

    // Legacy migration: one verbatim script step, replay-safe.
    let legacy = ProjectFile.migrateLegacyScript("box a 1 1 1\nview a\n")
    check(legacy.steps.count == 1 && legacy.steps[0].isScript &&
          legacy.steps[0].scriptText == "box a 1 1 1\nview a\n",
          "migration: a legacy script becomes exactly one verbatim script step")
    let legacyBuilt = ReplayBuilder.build(steps: legacy.steps)
    check(legacyBuilt.count == 1 && legacyBuilt[0].line == nil &&
          legacyBuilt[0].predictedName == nil,
          "migration: a script step builds to no parametric line (runs via the script runner)")
}

// MARK: - View panel state (v0.3.2)
//
// The View panel's production path, executed end to end:
// ViewStateChange -> the ViewerCommand the console parser
// produces for the equivalent `view ...` line -> SceneStore.apply
// (the implementation CascadeRenderer.apply delegates to) -> the
// store state the renderer reads. The renderer's own label flags
// are the one piece the store does not own; the split is pinned
// by the `apply(...) == false` checks below.
do {
    // Mapping pins: each panel change IS the console's command.
    check(ViewStateChange.setGrid(false).viewerCommand == .setGridVisible(false),
          "view panel: grid toggle maps to view grid's command")
    check(ViewStateChange.setAxes(true).viewerCommand == .setAxesVisible(true),
          "view panel: axes toggle maps to view axes' command")
    check(ViewStateChange.setFaceLabels(true).viewerCommand == .setFaceLabelsEnabled(true),
          "view panel: face labels map to view labels faces' command")
    check(ViewStateChange.setEdgeLabels(true).viewerCommand == .setEdgeLabelsEnabled(true),
          "view panel: edge labels map to view labels edges' command")
    check(ViewStateChange.setDisplayMode(.xray).viewerCommand == .displayMode(.xray),
          "view panel: display mode maps to the view mode command")
    check(ViewStateChange.setMeasure(true).viewerCommand == .setMeasureEnabled(true),
          "view panel: measure toggle maps to view measure's command")
    check(ViewStateChange.clearMeasure.viewerCommand == .clearMeasure,
          "view panel: clear measure maps to view measure clear's command")
    check(ViewStateChange.setRotation(azimuthDegrees: 30, elevationDegrees: 60).viewerCommand
            == .setCameraRotation(azimuthDegrees: 30, elevationDegrees: 60),
          "view panel: rotation sliders map to view rotate's command")
    check(ViewStateChange.fit.viewerCommand == .fit
            && ViewStateChange.resetCamera.viewerCommand == .resetCamera
            && ViewStateChange.standardView(.iso).viewerCommand == .standardView(.iso),
          "view panel: fit/reset/standard-view map to their console commands")

    // Execution against a real store, through the production
    // SceneStore.apply the renderer itself now delegates to.
    let store = SceneStore()
    check(store.gridVisible && store.axesVisible && !store.measureEnabled
            && store.displayMode == .shaded,
          "view panel: a fresh store matches the panel's default mirror")
    store.apply(ViewStateChange.setGrid(false).viewerCommand)
    check(!store.gridVisible, "view panel: grid toggle flips the flag the renderer reads")
    store.apply(ViewStateChange.setAxes(false).viewerCommand)
    check(!store.axesVisible, "view panel: axes toggle flips the flag the renderer reads")
    for mode in DisplayMode.allCases {
        store.apply(ViewStateChange.setDisplayMode(mode).viewerCommand)
        check(store.displayMode == mode,
              "view panel: display mode \(mode.rawValue) lands in the store")
    }
    store.apply(ViewStateChange.setRotation(azimuthDegrees: 30,
                                            elevationDegrees: 60).viewerCommand)
    check(abs(store.camera.azimuth - 30 * .pi / 180) < 1e-5
            && abs(store.camera.elevation - 60 * .pi / 180) < 1e-5,
          "view panel: rotation sliders land the camera at the requested angles")
    store.apply(ViewStateChange.setRotation(azimuthDegrees: 0,
                                            elevationDegrees: 120).viewerCommand)
    check(abs(store.camera.elevation - 89.9 * .pi / 180) < 1e-5,
          "view panel: elevation clamps at the same 89.9-degree pole limit as the console")
    store.apply(ViewStateChange.setMeasure(true).viewerCommand)
    store.addMeasurePoint(SIMD3<Float>(0, 0, 0))
    store.addMeasurePoint(SIMD3<Float>(3, 4, 0))
    check(store.measureEnabled && store.measureDistance == 5,
          "view panel: measure on + two picks gives the store's distance")
    store.apply(ViewStateChange.setMeasure(false).viewerCommand)
    check(!store.measureEnabled && store.measurePoints.isEmpty,
          "view panel: measure off clears the picked points (renderer semantics)")
    check(store.apply(.setFaceLabelsEnabled(true)) == false
            && store.apply(.setEdgeLabelsEnabled(true)) == false
            && store.apply(.screenshot(path: "x", width: 1, height: 1)) == false,
          "view panel: labels + screenshot stay renderer-owned (store.apply declines them)")
    store.apply(ViewStateChange.resetCamera.viewerCommand)
    check(abs(store.camera.azimuth - .pi / 4) < 1e-5,
          "view panel: reset restores the default camera")

    // The mirror reads back exactly what execution left behind.
    store.apply(ViewStateChange.setGrid(true).viewerCommand)
    store.apply(ViewStateChange.setDisplayMode(.wireframe).viewerCommand)
    let snap = ViewState(store: store, faceLabels: true, edgeLabels: false)
    check(snap.gridVisible && !snap.axesVisible && snap.faceLabelsEnabled
            && !snap.edgeLabelsEnabled && snap.displayMode == .wireframe
            && abs(snap.azimuthDegrees - 45) < 0.01,
          "view panel: the ViewState mirror reads the store back faithfully")
}

// MARK: - Simulation form (v0.3.2)
//
// SimScriptBuilder generates the existing `sim ...` commands
// verbatim; the lines below are the exact strings the form sends
// for its default state and its pressure variant, and invalid
// fields produce NO lines (a half-valid setup is never sent).
// The material list is pinned against the engine in the sim
// suite (test_sim asserts each name appears in `sim material
// list` on both backends).
do {
    check(SimFormState.materials == ["steel", "stainless-304",
            "aluminium-6061", "aluminium-7075", "titanium-6al4v",
            "brass", "copper", "pla", "abs", "petg"],
          "sim form: the material picker lists the engine library, in order")
    var form = SimFormState()
    check(SimScriptBuilder.setupLines(object: "box:part", form: form) == [
        "sim material box:part steel",
        "sim fix box:part @face 0",
        "sim load box:part @face 1 force 0 0 -100",
        "sim mesh size 2.5",
        "sim static",
    ], "sim form: the default statics setup generates the exact console commands")
    form.loadKind = .pressure
    form.pressureMPa = "0.5"
    form.fixedFace = "2"
    check(SimScriptBuilder.setupLines(object: "box:part", form: form)?[2]
            == "sim load box:part @face 1 pressure 0.5",
          "sim form: the pressure variant generates its load line")
    check(SimScriptBuilder.setupLines(object: "box:part", form: form)?[1]
            == "sim fix box:part @face 2",
          "sim form: the fixed face follows the form")
    form.fixedFace = "x"
    check(SimScriptBuilder.setupLines(object: "box:part", form: form) == nil,
          "sim form: a non-numeric face produces no setup lines")
    form.fixedFace = "0"
    form.meshSize = "0"
    check(SimScriptBuilder.setupLines(object: "box:part", form: form) == nil,
          "sim form: a zero mesh size produces no setup lines")
    form.meshSize = "2.5"
    form.material = "unobtainium"
    check(SimScriptBuilder.setupLines(object: "box:part", form: form) == nil,
          "sim form: a material outside the library produces no setup lines")
    check(SimScriptBuilder.runLine(object: "box:part") == "sim run box:part"
            && SimScriptBuilder.clearLine(object: "box:part") == "sim clear box:part",
          "sim form: run/clear lines are the console commands verbatim")
}

// MARK: - AppState sequences (v0.4.2): delete / re-add through the
// production AppState object
//
// The C++ sequence matrix (Core/native/tests/test_sequences_mc.cpp)
// drives cc_execute the way AppState drives it. This section removes
// the "the way" from that sentence: it runs the PRODUCTION AppState
// — the exact object the app's views drive — against a real
// NativeEngine on the mc backend, through the v0.4.1 device report's
// sequence (add a box, fillet one edge, DELETE the fillet step, add
// the same fillet again) plus cut delete/re-add, save/reload/replay,
// and an edit after a delete. The renderer is nil (CI has no Metal
// device to hand it), so refreshScene returns early and assertions
// read the session back through the production engine's own
// EngineViewDataProviding queries — the same reads refreshScene
// itself makes. If the failure lives in AppState's bookkeeping
// (name claims, consumed-source sets, replay adoption), it fails
// here, in CI, not on a device.

@MainActor
func waitIdle(_ state: AppState, _ what: String) async -> Bool {
    for _ in 0..<600 {  // ~30 s at 50 ms
        if !state.isRunning { return true }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
    check(false, "appstate: timed out waiting for \(what)")
    return false
}

@MainActor
func appStateSequences() async {
    let state = AppState(engine: NativeEngine(), viewer: nil,
                         fileStore: FileStore())
    let provider = state.engine as? EngineViewDataProviding
    check(provider != nil, "appstate: the harness engine provides view data")
    guard let provider else { return }

    func names() async -> [String] { await provider.objectNames() }
    func volume(of name: String) async -> Double {
        let feed = await provider.viewData(name: name)
        return feed.objects.first?.volume ?? -1
    }
    func specParams(_ id: String, _ overrides: [String: String]) -> [String: String] {
        var p = CommandCatalog.spec(for: id)?.defaultParams ?? [:]
        for (k, v) in overrides { p[k] = v }
        return p
    }

    // -- the lead repro: box -> fillet -> delete -> fillet again ----
    state.addStepFromUI(command: "box",
                        params: specParams("box", ["width": "10", "depth": "10", "height": "10"]),
                        name: "")
    _ = await waitIdle(state, "box add")
    check(state.project.steps.count == 1, "appstate: box step recorded")
    check(await names() == ["box:box1"], "appstate: session holds box:box1")
    check(state.lastReplayError == nil, "appstate: no error after box add")

    let filletParams = specParams("fillet", ["source": "box:box1", "radius": "1", "edges": "3"])
    state.addStepFromUI(command: "fillet", params: filletParams, name: "")
    _ = await waitIdle(state, "fillet add")
    check(state.project.steps.count == 2, "appstate: fillet step recorded")
    check(await names().contains("fillet:fillet1"), "appstate: session holds fillet:fillet1")
    let filletVolume = await volume(of: "fillet:fillet1")
    check(approx(filletVolume, 997.854, 0.01),
          "appstate: fillet volume == 997.854 (one edge, r=1; got \(filletVolume))")
    check(state.autoHiddenSources == ["box:box1"],
          "appstate: the fillet consumed (hid) its source box")

    // Save here so the reload below replays exactly [box, fillet].
    state.currentProjectName = "harness-sequences.cascadeproj"
    state.saveProject()

    guard let filletStep = state.project.steps.first(where: { $0.command == "fillet" }) else {
        check(false, "appstate: fillet step present for deletion")
        return
    }
    state.deleteStep(id: filletStep.id)
    _ = await waitIdle(state, "fillet delete replay")
    check(state.lastReplayError == nil,
          "appstate: deleting the fillet step replays clean (got \(state.lastReplayError ?? "nil"))")
    check(state.project.steps.count == 1, "appstate: fillet step removed from history")
    check(await names() == ["box:box1"], "appstate: session back to the bare box")
    check(state.autoHiddenSources.isEmpty,
          "appstate: consumed-source set recomputed empty after the delete")

    state.addStepFromUI(command: "fillet", params: filletParams, name: "")
    _ = await waitIdle(state, "fillet re-add")
    check(state.project.steps.count == 2, "appstate: re-added fillet step recorded")
    check(await names().contains("fillet:fillet1"),
          "appstate: THE REPRO — the same fillet on the same edge succeeds after the delete")
    check(approx(await volume(of: "fillet:fillet1"), filletVolume, 0.01),
          "appstate: re-added fillet geometry identical to the first")

    // -- save -> delete -> re-add -> reload -> replay ----------------
    state.fileStore.refresh()
    if let item = state.fileStore.items.first(
        where: { $0.name == "harness-sequences.cascadeproj" }) {
        state.openProject(item: item)
    } else {
        check(false, "appstate: saved project visible in the file store")
    }
    _ = await waitIdle(state, "project reload replay")
    check(state.lastReplayError == nil, "appstate: saved project replays clean on reload")
    check(state.project.steps.count == 2, "appstate: reloaded project has box + fillet steps")
    check(approx(await volume(of: "fillet:fillet1"), filletVolume, 0.01),
          "appstate: reloaded fillet geometry identical")

    // -- cut: delete + re-add ----------------------------------------
    state.addStepFromUI(command: "box",
                        params: specParams("box", ["width": "4", "depth": "4", "height": "4",
                                                   "atX": "3", "atY": "3", "atZ": "3"]),
                        name: "")
    _ = await waitIdle(state, "tool box add")
    let cutParams = specParams("cut", ["a": "box:box1", "b": "box:box2"])
    state.addStepFromUI(command: "cut", params: cutParams, name: "")
    _ = await waitIdle(state, "cut add")
    check(approx(await volume(of: "cut:cut1"), 936.0, 0.01),
          "appstate: cut volume == 936 (tool fully inside the target)")
    if let cutStep = state.project.steps.first(where: { $0.command == "cut" }) {
        state.deleteStep(id: cutStep.id)
        _ = await waitIdle(state, "cut delete replay")
        check(!(await names()).contains("cut:cut1"), "appstate: cut gone after its step is deleted")
        state.addStepFromUI(command: "cut", params: cutParams, name: "")
        _ = await waitIdle(state, "cut re-add")
        check(approx(await volume(of: "cut:cut1"), 936.0, 0.01),
              "appstate: re-added cut geometry identical")
    } else {
        check(false, "appstate: cut step present for deletion")
    }

    // -- edit after delete --------------------------------------------
    if let fillet = state.project.steps.first(where: { $0.command == "fillet" }) {
        state.deleteStep(id: fillet.id)
        _ = await waitIdle(state, "fillet delete before edit")
    }
    if let boxStep = state.project.steps.first(where: { $0.command == "box" && $0.assignedName == "box:box1" }) {
        var edited = boxStep.params
        edited["width"] = "20"
        state.applyStepEdit(id: boxStep.id, params: edited, name: boxStep.name)
        _ = await waitIdle(state, "box edit replay")
        check(state.lastReplayError == nil,
              "appstate: editing the box after deleting the fillet replays clean")
        check(approx(await volume(of: "cut:cut1"), 1936.0, 0.01),
              "appstate: edited model rebuilt (cut == 2000 - 64 == 1936)")
    } else {
        check(false, "appstate: box step present for the edit")
    }
}

// Drive the @MainActor section by SPINNING the main runloop: the
// main actor's executor is the main dispatch queue, which only the
// main thread can service. Blocking this thread on a semaphore
// instead deadlocks the harness — the task can never start, the
// semaphore never signals (v0.4.2's first CI run hung exactly here
// until cancelled). The spin has a hard deadline so a wedged
// sequence fails the gate in minutes instead of hanging the job.
var appStateDone = false
Task { @MainActor in
    await appStateSequences()
    appStateDone = true
}
let appStateDeadline = Date(timeIntervalSinceNow: 300)
while !appStateDone {
    if Date() > appStateDeadline {
        print("FAIL appstate: sequence section exceeded its 300 s deadline")
        print("RESULT: \(passCount) pass, \(failCount + 1) fail (swift viewer harness)")
        exit(1)
    }
    RunLoop.main.run(mode: .default,
                     before: Date(timeIntervalSinceNow: 0.05))
}

print("RESULT: \(passCount) pass, \(failCount) fail (swift viewer harness)")
exit(failCount == 0 ? 0 : 1)
