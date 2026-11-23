import AppKit
import UniformTypeIdentifiers

// MARK: - File picking and plain file IO
//
// All panels are the standard NSOpenPanel / NSSavePanel. Every function
// returns nil on user cancellation (not an error) and throws a
// `FileServiceError` with plain-language text on real failures, which the
// caller turns into a console log line with an error code.

enum FileServiceError: Error, CustomStringConvertible {
    case unreadable(String)
    case unwritable(String)

    var description: String {
        switch self {
        case .unreadable(let name):
            return "Could not read \"\(name)\". The file may be damaged or in a format this app cannot open."
        case .unwritable(let name):
            return "Could not save \"\(name)\". Check that the location is writable and try again."
        }
    }
}

enum FileService {

    // MARK: File types

    static var scriptTypes: [UTType] {
        var types: [UTType] = [.plainText]
        if let txt = UTType(filenameExtension: "txt") { types.append(txt) }
        if let cc = UTType(filenameExtension: "ccs") { types.append(cc) }
        return types
    }

    static var modelTypes: [UTType] {
        var types: [UTType] = []
        for ext in ["step", "stp", "iges", "igs", "stl", "brep"] {
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }
        return types.isEmpty ? [.data] : types
    }

    static var exportTypes: [UTType] {
        modelTypes
    }

    // MARK: Panels (main-actor: panels are UI)

    @MainActor
    static func pickOpenFile(title: String, allowedTypes: [UTType]) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.allowedContentTypes = allowedTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    static func pickSaveFile(title: String,
                             defaultName: String,
                             allowedTypes: [UTType]) -> URL? {
        let panel = NSSavePanel()
        panel.title = title
        panel.nameFieldStringValue = defaultName
        panel.allowedContentTypes = allowedTypes
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    // MARK: IO

    static func readText(at url: URL) throws -> String {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw FileServiceError.unreadable(url.lastPathComponent)
        }
    }

    static func writeText(_ text: String, to url: URL) throws {
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw FileServiceError.unwritable(url.lastPathComponent)
        }
    }
}
