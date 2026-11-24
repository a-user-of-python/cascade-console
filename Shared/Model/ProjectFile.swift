import Foundation

// MARK: - Project persistence (v0.3.0)
//
// The .cascadeproj file is the durable form of a project: the step
// list (history), the folder tree + object->folder assignments, and
// a viewer snapshot. Reopening replays the steps into a fresh
// session, so history, tree and model are restored exactly — the
// file never stores mesh data.
//
// Migration: a pre-v0.3.0 .cascade script still loads. It becomes a
// project with ONE step — an "Imported script" step holding the
// script text verbatim — which replays through the script runner.
// Its individual commands are not reverse-engineered into parametric
// steps; that is stated in FIXLOG, not hidden.

public struct ViewerStateSnapshot: Codable, Equatable {
    public var grid: Bool = true
    public var axes: Bool = true
    public var faceLabels: Bool = false
    public var edgeLabels: Bool = false
    /// CascadeDisplayMode raw value ("shaded", "wireframe", ...).
    public var displayMode: String = "shaded"
    public var cameraAzimuthDegrees: Double? = nil
    public var cameraElevationDegrees: Double? = nil

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case grid, axes, faceLabels, edgeLabels, displayMode
        case cameraAzimuthDegrees, cameraElevationDegrees
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        grid = try c.decodeIfPresent(Bool.self, forKey: .grid) ?? true
        axes = try c.decodeIfPresent(Bool.self, forKey: .axes) ?? true
        faceLabels = try c.decodeIfPresent(Bool.self, forKey: .faceLabels) ?? false
        edgeLabels = try c.decodeIfPresent(Bool.self, forKey: .edgeLabels) ?? false
        displayMode = try c.decodeIfPresent(String.self, forKey: .displayMode) ?? "shaded"
        cameraAzimuthDegrees = try c.decodeIfPresent(Double.self, forKey: .cameraAzimuthDegrees)
        cameraElevationDegrees = try c.decodeIfPresent(Double.self, forKey: .cameraElevationDegrees)
    }
}

/// One user folder in the part tree. Folders are organisational only
/// (stored in the project file); they nest, and objects keep their
/// folder assignment by qualified name so renames-by-replay (which
/// preserve qualified names) preserve the tree layout too.
public struct PartFolder: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var parentID: UUID?

    public init(id: UUID = UUID(), name: String, parentID: UUID? = nil) {
        self.id = id
        self.name = name
        self.parentID = parentID
    }
}

public struct ProjectFile: Codable, Equatable {
    public static let formatTag = "cascade-console-project"
    public static let currentVersion = 1

    public var format: String = ProjectFile.formatTag
    public var version: Int = ProjectFile.currentVersion
    public var steps: [ModelStep] = []
    public var folders: [PartFolder] = []
    /// qualified name -> folder id (UUID string). Absent = root.
    public var objectFolders: [String: String] = [:]
    public var viewer = ViewerStateSnapshot()

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case format, version, steps, folders, objectFolders, viewer
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decodeIfPresent(String.self, forKey: .format) ?? ""
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 0
        steps = try c.decodeIfPresent([ModelStep].self, forKey: .steps) ?? []
        folders = try c.decodeIfPresent([PartFolder].self, forKey: .folders) ?? []
        objectFolders = try c.decodeIfPresent([String: String].self, forKey: .objectFolders) ?? [:]
        viewer = try c.decodeIfPresent(ViewerStateSnapshot.self, forKey: .viewer) ?? ViewerStateSnapshot()
    }

    public var isValidFormat: Bool { format == ProjectFile.formatTag }

    public func encoded() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(self)
    }

    public static func decoded(from data: Data) throws -> ProjectFile {
        let file = try JSONDecoder().decode(ProjectFile.self, from: data)
        guard file.isValidFormat else {
            throw NSError(domain: "CascadeProject", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Not a Cascade Console project file."])
        }
        return file
    }

    /// Legacy migration: a .cascade script becomes a one-step project
    /// whose single step replays the script verbatim.
    public static func migrateLegacyScript(_ text: String) -> ProjectFile {
        var file = ProjectFile()
        file.steps = [ModelStep(command: "script", scriptText: text)]
        return file
    }

    // MARK: Folder operations (pure; exercised by the CI harness)

    public func childFolders(of parentID: UUID?) -> [PartFolder] {
        folders.filter { $0.parentID == parentID }
    }

    public func folder(id: UUID) -> PartFolder? {
        folders.first { $0.id == id }
    }

    @discardableResult
    public mutating func addFolder(name: String, parentID: UUID?) -> PartFolder {
        let folder = PartFolder(name: name, parentID: parentID)
        folders.append(folder)
        return folder
    }

    public mutating func renameFolder(id: UUID, name: String) {
        guard let idx = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[idx].name = name
    }

    /// Deleting a folder moves its child folders and its objects to
    /// the deleted folder's parent (root when it had none) — nothing
    /// is ever silently unfiled into the void or lost.
    public mutating func deleteFolder(id: UUID) {
        guard let target = folder(id: id) else { return }
        for idx in folders.indices where folders[idx].parentID == id {
            folders[idx].parentID = target.parentID
        }
        let idString = id.uuidString
        for (object, folderID) in objectFolders where folderID == idString {
            if let parent = target.parentID {
                objectFolders[object] = parent.uuidString
            } else {
                objectFolders.removeValue(forKey: object)
            }
        }
        folders.removeAll { $0.id == id }
    }

    public mutating func moveObject(_ qualifiedName: String, toFolder folderID: UUID?) {
        if let folderID {
            objectFolders[qualifiedName] = folderID.uuidString
        } else {
            objectFolders.removeValue(forKey: qualifiedName)
        }
    }

    public func folderID(forObject qualifiedName: String) -> UUID? {
        objectFolders[qualifiedName].flatMap { UUID(uuidString: $0) }
    }

    /// All descendant folder ids (cycle-safe).
    public func descendantFolderIDs(of id: UUID) -> Set<UUID> {
        var result: Set<UUID> = []
        var stack = [id]
        while let current = stack.popLast() {
            for child in childFolders(of: current) where !result.contains(child.id) {
                result.insert(child.id)
                stack.append(child.id)
            }
        }
        return result
    }
}
