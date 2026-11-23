import Foundation

/// Direct access to the app's Documents folder. This is the picker-free
/// file path: it works in sideloaded builds where the system document
/// picker is broken by the signing certificate. All methods are
/// do/catch based and return Result — nothing here can crash on a
/// missing folder or file.
final class FileStore: ObservableObject {

    struct FileItem: Identifiable, Equatable {
        let url: URL
        var id: URL { url }
        var name: String { url.lastPathComponent }
        var kind: CascadeFileKind {
            CascadeFileKind.kind(forExtension: url.pathExtension)
        }
        var modified: Date?
    }

    @Published private(set) var items: [FileItem] = []
    @Published var lastError: String?

    /// Documents directory, falling back to the temporary directory if
    /// the documents URL is somehow unavailable (never force-unwrapped).
    var documentsURL: URL {
        if let url = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask).first {
            return url
        }
        return FileManager.default.temporaryDirectory
    }

    func refresh() {
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: documentsURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles])
            let mapped: [FileItem] = urls.map { url in
                let values = try? url.resourceValues(
                    forKeys: [.contentModificationDateKey])
                return FileItem(url: url, modified: values?.contentModificationDate)
            }
            items = mapped.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            lastError = nil
        } catch {
            items = []
            lastError = "Could not list Documents: \(error.localizedDescription)"
        }
    }

    func readText(_ item: FileItem) -> Result<String, Error> {
        do {
            let text = try String(contentsOf: item.url, encoding: .utf8)
            return .success(text)
        } catch {
            return .failure(error)
        }
    }

    @discardableResult
    func writeText(_ text: String, fileName: String) -> Result<URL, Error> {
        let safeName = fileName.isEmpty ? "untitled.cascade" : fileName
        let url = documentsURL.appendingPathComponent(safeName)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            refresh()
            return .success(url)
        } catch {
            return .failure(error)
        }
    }

    /// Copy an externally picked file into Documents so it remains
    /// reachable through the in-app browser afterwards.
    @discardableResult
    func importCopy(of source: URL) -> Result<URL, Error> {
        let destination = documentsURL.appendingPathComponent(source.lastPathComponent)
        do {
            let scoped = source.startAccessingSecurityScopedResource()
            defer {
                if scoped { source.stopAccessingSecurityScopedResource() }
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
            refresh()
            return .success(destination)
        } catch {
            return .failure(error)
        }
    }

    func delete(_ item: FileItem) -> Result<Void, Error> {
        do {
            try FileManager.default.removeItem(at: item.url)
            refresh()
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    /// Seed a starter file only if it does not already exist.
    func seedIfMissing(fileName: String, contents: String) {
        let url = documentsURL.appendingPathComponent(fileName)
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            lastError = "Could not seed \(fileName): \(error.localizedDescription)"
        }
    }
}
