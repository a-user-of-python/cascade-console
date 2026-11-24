//
//  EngineMeshAdapter.swift
//  Cascade Console - Viewer
//
//  The last mile of the v0.2 viewer feed: EngineViewObject (the native
//  session's cc_view_data result — positions + indices only) -> CCM1
//  bytes -> MeshBufferLoader -> MeshObject -> ViewerBridge.loadMesh.
//
//  Going through the actual CCM1 bytes (instead of hand-building a
//  MeshObject) means the shipped app exercises exactly the contract
//  that Shared/Viewer/Verification/verify_tessellation.py proves
//  against live OCCT tessellation: same magic, same layout, same
//  loader-side validation (unit normals, index ranges).
//
//  cc_view_data carries no normals and no per-face groups, so the
//  writer derives FLAT normals (one per triangle, from the positions)
//  and unwelds vertices per triangle corner, and emits a single face
//  group per object. Flat shading is the honest consequence of the
//  Layer-2 C API's shape; smooth normals require a facade tessellation
//  call (mc_tessellate) and are a documented later upgrade, not faked
//  here.
//

import Foundation
import simd

public enum EngineMeshAdapter {

    /// Serialise engine objects to a CCM1 payload (format documented
    /// in MeshBuffer.swift). Objects with no triangles are skipped.
    public static func ccm1Data(from objects: [EngineViewObject]) -> Data {
        var data = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func u64(_ v: UInt64) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func f32(_ v: Float) { u32(v.bitPattern) }

        let usable = objects.filter { $0.indices.count >= 3 && $0.vertices.count >= 9 }
        data.append(Data("CCM1".utf8))
        u32(2)                          // version (v2: census-edge section, v0.2.4)
        u32(UInt32(usable.count))      // objectCount
        u32(0)                          // reserved

        for obj in usable {
            let nameBytes = Data(obj.name.utf8)
            u32(UInt32(nameBytes.count))
            data.append(nameBytes)
            u64(geometryVersion(for: obj))

            // Unweld: one vertex per index corner, flat face normals.
            var positions: [SIMD3<Float>] = []
            var normals: [SIMD3<Float>] = []
            positions.reserveCapacity(obj.indices.count)
            normals.reserveCapacity(obj.indices.count)
            let triCount = obj.indices.count / 3
            for t in 0..<triCount {
                let ia = Int(obj.indices[t * 3])
                let ib = Int(obj.indices[t * 3 + 1])
                let ic = Int(obj.indices[t * 3 + 2])
                func p(_ i: Int) -> SIMD3<Float> {
                    SIMD3<Float>(obj.vertices[i * 3], obj.vertices[i * 3 + 1], obj.vertices[i * 3 + 2])
                }
                let a = p(ia), b = p(ib), c = p(ic)
                var n = simd_cross(b - a, c - a)
                let len = simd_length(n)
                n = len > 1e-12 ? n / len : SIMD3<Float>(0, 0, 1)
                positions.append(contentsOf: [a, b, c])
                normals.append(contentsOf: [n, n, n])
            }

            // Face groups from the backend's census ranges (v0.2
            // labels): sourceFaceIndex is the true @face index. In
            // the unwelded layout vertex i == index-corner i, so each
            // group's vertex range equals its index range. Objects
            // whose backend gave no ranges fall back to one group.
            let groups = obj.faceRanges.isEmpty
                ? [EngineViewObject.FaceRange(faceIndex: 0, indexStart: 0,
                                              indexCount: Int32(positions.count))]
                : obj.faceRanges
            u32(UInt32(groups.count))
            for g in groups {
                u32(UInt32(g.faceIndex))                 // sourceFaceIndex
                u32(UInt32(g.indexStart))                // vertexStart (unwelded)
                u32(UInt32(g.indexCount))                // vertexCount
                u32(UInt32(g.indexStart))                // indexStart
                u32(UInt32(g.indexCount))                // indexCount
            }

            u32(UInt32(positions.count))
            u32(UInt32(positions.count))
            for i in positions.indices {
                f32(positions[i].x); f32(positions[i].y); f32(positions[i].z)
                f32(normals[i].x); f32(normals[i].y); f32(normals[i].z)
            }
            for i in positions.indices { u32(UInt32(i)) }

            let bb = obj.bbox.count == 6 ? obj.bbox : [0, 0, 0, 0, 0, 0]
            for v in bb { f32(Float(v)) }
            f32(Float((bb[0] + bb[3]) / 2))
            f32(Float((bb[1] + bb[4]) / 2))
            f32(Float((bb[2] + bb[5]) / 2))

            // Census edges (CCM1 v2): the backend's own enumeration
            // from ccgeom_edge_list, carried verbatim — edgeIndex is
            // the number `fillet/chamfer ... edges i,j,...` accepts.
            u32(UInt32(obj.edges.count))
            for e in obj.edges {
                u32(UInt32(e.edgeIndex))
                for v in e.start { f32(Float(v)) }
                for v in e.end { f32(Float(v)) }
            }
        }
        return data
    }

    /// Full conversion: engine objects -> validated MeshObjects via
    /// the CCM1 loader. Throws MeshBufferError on any contract breach.
    public static func meshObjects(from objects: [EngineViewObject]) throws -> [MeshObject] {
        try MeshBufferLoader.load(data: ccm1Data(from: objects))
    }

    /// Cache key for SceneStore: changes whenever the tessellation
    /// could have changed (counts + volume), stable for identical data.
    static func geometryVersion(for obj: EngineViewObject) -> UInt64 {
        var hash: UInt64 = 1469598103934665603   // FNV-1a offset basis
        func mix(_ v: UInt64) {
            var x = v
            for _ in 0..<8 {
                hash ^= x & 0xFF
                hash &*= 1099511628211
                x >>= 8
            }
        }
        mix(UInt64(obj.vertices.count))
        mix(UInt64(obj.indices.count))
        mix(obj.volume.bitPattern)
        return hash
    }
}
