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
//  EngineProtocol.swift, SharedModels.swift) plus this file, and run
//  against a CCFX fixture produced in the same job by the real
//  engine (Core/native/tests/dump_view_fixture.cpp, mc backend):
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
    _ = r.i32() // version
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
        out.append(FixtureObject(name: name, vertices: verts, indices: idx,
                                 volume: vol, bbox: bbox, faceRanges: ranges))
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
                     volume: $0.volume, bbox: $0.bbox, faceRanges: $0.faceRanges)
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

// Pin the ABI facts the descriptor relies on: if a future toolchain
// changed the SIMD layout, the MemoryLayout-derived constants would
// move with it and stay correct — this check exists to force a
// human look at that moment, not to freeze the ABI.
check(MeshVertex.bufferStride == 32 && MeshVertex.bufferNormalOffset == 16,
      "MeshVertex memory layout is stride 32 / normal offset 16 (got \(MeshVertex.bufferStride)/\(MeshVertex.bufferNormalOffset))")
check(MeshVertex.stride == 24, "CCM1 file stride stays 24 (packed file format)")

print("RESULT: \(passCount) pass, \(failCount) fail (swift viewer harness)")
exit(failCount == 0 ? 0 : 1)
