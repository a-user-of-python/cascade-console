//
//  MeshBuffer.swift
//  Cascade Console - Viewer
//
//  The geometry data contract between the OCCT core and the viewer.
//  The core tessellates BRep shapes with BRepMesh and hands the viewer
//  plain triangle buffers - the viewer never sees OCCT types.
//
//  Binary interchange format "CCM1" (all integers/floats little-endian):
//    header : char[4] magic "CCM1", UInt32 version (=1),
//             UInt32 objectCount, UInt32 reserved (=0)
//    per object:
//             UInt32 nameByteCount, name UTF-8 bytes
//             UInt64 geometryVersion        (cache key, see SceneStore)
//             UInt32 faceGroupCount
//             faceGroup[ ]: UInt32 sourceFaceIndex, UInt32 vertexStart,
//                           UInt32 vertexCount, UInt32 indexStart,
//                           UInt32 indexCount
//             UInt32 vertexCount, UInt32 indexCount
//             vertex[ ]: Float32 x, y, z, nx, ny, nz   (stride 24 bytes)
//             index[ ] : UInt32 (triangle list, CCW, outward normals)
//             Float32 bbox[6]  (minX, minY, minZ, maxX, maxY, maxZ)
//             Float32 centre[3] (bbox centre; explode pivot reference)
//
//  Vertices are NOT welded across faces: each BRep face contributes its
//  own vertex block so face normals stay sharp at CAD edges. Normals are
//  the true surface normals (surface D1 at the node's UV), unit length,
//  flipped for REVERSED faces - computed on the core side, never in the
//  viewer. Coordinates are OCCT model units (mm by convention), Z-up,
//  right-handed - identical to the core, no conversion anywhere.
//
//  Verified end-to-end by Verification/verify_tessellation.py, which
//  writes and re-reads exactly this format from a live OCCT tessellation.
//

import Foundation
import simd

public struct MeshVertex: Equatable {
    public var position: SIMD3<Float>
    public var normal: SIMD3<Float>
    public init(position: SIMD3<Float>, normal: SIMD3<Float>) {
        self.position = position
        self.normal = normal
    }
    /// Byte stride in both the CCM1 file and the Metal vertex buffer.
    public static let stride = 24
}

public struct MeshFaceGroup: Equatable {
    public var sourceFaceIndex: UInt32
    public var vertexStart: UInt32
    public var vertexCount: UInt32
    public var indexStart: UInt32
    public var indexCount: UInt32
}

public struct MeshObject: Identifiable, Equatable {
    public let id: String                       // stable scene name
    public var geometryVersion: UInt64          // bump on any core rebuild
    public var vertices: [MeshVertex]
    public var indices: [UInt32]
    public var faceGroups: [MeshFaceGroup]
    public var boundingBoxMin: SIMD3<Float>
    public var boundingBoxMax: SIMD3<Float>
    public var centre: SIMD3<Float>

    public var triangleCount: Int { indices.count / 3 }
    public var boundingBoxSize: SIMD3<Float> { boundingBoxMax - boundingBoxMin }

    public init(id: String, geometryVersion: UInt64,
                vertices: [MeshVertex], indices: [UInt32],
                faceGroups: [MeshFaceGroup],
                boundingBoxMin: SIMD3<Float>, boundingBoxMax: SIMD3<Float>,
                centre: SIMD3<Float>) {
        self.id = id
        self.geometryVersion = geometryVersion
        self.vertices = vertices
        self.indices = indices
        self.faceGroups = faceGroups
        self.boundingBoxMin = boundingBoxMin
        self.boundingBoxMax = boundingBoxMax
        self.centre = centre
    }
}

public enum MeshBufferError: Error, Equatable {
    case badMagic
    case unsupportedVersion(UInt32)
    case truncated(needed: Int, available: Int)
    case indexOutOfRange(index: UInt32, vertexCount: Int)
    case nonUnitNormal(vertex: Int, length: Float)
    case invalidUTF8Name
}

/// Minimal little-endian cursor reader; hosts are little-endian (Apple
/// silicon and Intel both are), and the format is defined little-endian.
private struct CCMReader {
    let data: Data
    var offset: Int = 0
    var remaining: Int { data.count - offset }

    mutating func bytes(_ count: Int) throws -> Data {
        guard remaining >= count else {
            throw MeshBufferError.truncated(needed: count, available: remaining)
        }
        defer { offset += count }
        return data.subdata(in: offset..<(offset + count))
    }

    mutating func u32() throws -> UInt32 {
        let b = try bytes(4)
        return b.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
    }

    mutating func u64() throws -> UInt64 {
        let b = try bytes(8)
        return b.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }
    }

    mutating func f32() throws -> Float {
        Float(bitPattern: try u32())
    }

    mutating func vec3() throws -> SIMD3<Float> {
        SIMD3<Float>(try f32(), try f32(), try f32())
    }
}

public enum MeshBufferLoader {
    /// Parses a CCM1 payload (one or more objects) exactly as written by
    /// the core and by Verification/verify_tessellation.py.
    public static func load(data: Data) throws -> [MeshObject] {
        var r = CCMReader(data: data)
        let magic = try r.bytes(4)
        guard magic == Data("CCM1".utf8) else { throw MeshBufferError.badMagic }
        let version = try r.u32()
        guard version == 1 else { throw MeshBufferError.unsupportedVersion(version) }
        let objectCount = try r.u32()
        _ = try r.u32() // reserved
        var objects: [MeshObject] = []
        objects.reserveCapacity(Int(objectCount))
        for _ in 0..<objectCount {
            let nameLen = Int(try r.u32())
            let nameData = try r.bytes(nameLen)
            guard let name = String(data: nameData, encoding: .utf8) else {
                throw MeshBufferError.invalidUTF8Name
            }
            let geometryVersion = try r.u64()
            let groupCount = Int(try r.u32())
            var groups: [MeshFaceGroup] = []
            groups.reserveCapacity(groupCount)
            for _ in 0..<groupCount {
                groups.append(MeshFaceGroup(sourceFaceIndex: try r.u32(),
                                            vertexStart: try r.u32(),
                                            vertexCount: try r.u32(),
                                            indexStart: try r.u32(),
                                            indexCount: try r.u32()))
            }
            let vertexCount = Int(try r.u32())
            let indexCount = Int(try r.u32())
            var vertices: [MeshVertex] = []
            vertices.reserveCapacity(vertexCount)
            for i in 0..<vertexCount {
                let p = try r.vec3()
                let n = try r.vec3()
                let len = simd_length(n)
                guard abs(len - 1.0) < 1e-2 else {
                    throw MeshBufferError.nonUnitNormal(vertex: i, length: len)
                }
                vertices.append(MeshVertex(position: p, normal: n))
            }
            var indices: [UInt32] = []
            indices.reserveCapacity(indexCount)
            for _ in 0..<indexCount {
                let idx = try r.u32()
                guard Int(idx) < vertexCount else {
                    throw MeshBufferError.indexOutOfRange(index: idx,
                                                          vertexCount: vertexCount)
                }
                indices.append(idx)
            }
            let bbMin = try r.vec3()
            let bbMax = try r.vec3()
            let centre = try r.vec3()
            objects.append(MeshObject(id: name, geometryVersion: geometryVersion,
                                      vertices: vertices, indices: indices,
                                      faceGroups: groups,
                                      boundingBoxMin: bbMin, boundingBoxMax: bbMax,
                                      centre: centre))
        }
        return objects
    }
}
