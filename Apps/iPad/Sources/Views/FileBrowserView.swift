import SwiftUI
import UniformTypeIdentifiers

/// A document the app can export through the system exporter / share.
struct TextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            text = String(decoding: data, as: UTF8.self)
        } else {
            text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// Files screen. Two paths, both first-class:
///
/// 1. IN-APP BROWSER (primary, sideload-safe): lists the app's Documents
///    folder directly via FileStore. Open a script into the buffer, run
///    it, save the buffer, delete files — no system picker involved.
/// 2. SYSTEM PICKER: import/export via fileImporter / fileExporter for
///    builds where the picker works. Imported files are copied into
///    Documents so they show up in path 1 afterwards.
///
/// A visible note explains this, because on this user's sideloaded
/// installs the picker is expected to fail (certificate limitation).
struct FileBrowserView: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var store: FileStore

    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var showingSaveAs = false
    @State private var saveAsName: String = ""
    @State private var pendingDelete: FileStore.FileItem?
    @State private var message: String?

    private var exportDocument: TextDocument {
        TextDocument(text: state.scriptBuffer)
    }

    var body: some View {
        VStack(spacing: 0) {
            noteBanner
            if store.items.isEmpty {
                ContentUnavailableView(
                    "Documents is Empty",
                    systemImage: "folder",
                    description: Text("Scripts and models saved by the app will appear here. The welcome script is seeded on first launch."))
            } else {
                List {
                    ForEach(store.items) { item in
                        fileRow(item)
                    }
                }
                .listStyle(.plain)
            }
            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
            actionBar
        }
        .onAppear { store.refresh() }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.plainText, .data],
            allowsMultipleSelection: false) { result in
            handleImport(result)
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .plainText,
            defaultFilename: state.currentFileName) { result in
            switch result {
            case .success:
                message = "Exported \(state.currentFileName)."
            case .failure(let error):
                message = "Export failed: \(error.localizedDescription)"
            }
        }
        .alert("Save Script As", isPresented: $showingSaveAs) {
            TextField("File name", text: $saveAsName)
            Button("Save") {
                state.currentFileName = saveAsName.isEmpty
                    ? state.currentFileName : saveAsName
                state.saveBuffer()
            }
            Button("Cancel", role: .cancel) { }
        }
        .confirmationDialog(
            "Delete this file?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let item = pendingDelete {
                    _ = store.delete(item)
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
    }

    private var noteBanner: some View {
        Text("In-app browser reads the app's Documents folder directly — this works even when the system file picker does not (known sideloading limitation).")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fileRow(_ item: FileStore.FileItem) -> some View {
        HStack {
            Image(systemName: iconName(for: item.kind))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                Text(item.name)
                if let modified = item.modified {
                    Text(modified, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if item.kind == .project {
                Button("Open") { state.openProject(item: item) }
                    .buttonStyle(.bordered)
            }
            if item.kind == .script {
                Button("Open") { openScript(item) }
                    .buttonStyle(.bordered)
                Button("Run") {
                    openScript(item)
                    state.runScript(state.scriptBuffer)
                }
                .buttonStyle(.bordered)
                Button("Import") { state.importScriptAsProject(item: item) }
                    .buttonStyle(.bordered)
            }
            Button(role: .destructive) {
                pendingDelete = item
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(item.name)")
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            GlassChipButton(title: "Import", systemImage: "square.and.arrow.down") {
                showingImporter = true
            }
            GlassChipButton(title: "Export Script", systemImage: "square.and.arrow.up") {
                showingExporter = true
            }
            GlassChipButton(title: "Save", systemImage: "square.and.arrow.down.on.square") {
                state.saveBuffer()
            }
            GlassChipButton(title: "Save As", systemImage: "doc.badge.plus") {
                saveAsName = state.currentFileName
                showingSaveAs = true
            }
            Spacer()
            GlassChipButton(title: "Refresh", systemImage: "arrow.clockwise") {
                store.refresh()
            }
        }
        .padding(10)
    }

    private func iconName(for kind: CascadeFileKind) -> String {
        switch kind {
        case .script: return "doc.text"
        case .project: return "square.stack.3d.up"
        case .model: return "cube"
        case .other: return "doc"
        }
    }

    private func openScript(_ item: FileStore.FileItem) {
        switch store.readText(item) {
        case .success(let text):
            state.scriptBuffer = text
            state.currentFileName = item.name
            message = "Opened \(item.name)."
        case .failure(let error):
            message = "Could not open \(item.name): \(error.localizedDescription)"
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            switch store.importCopy(of: url) {
            case .success(let copied):
                message = "Imported \(copied.lastPathComponent) into Documents."
            case .failure(let error):
                message = "Import failed: \(error.localizedDescription)"
            }
        case .failure(let error):
            message = "Picker failed: \(error.localizedDescription). You can still use the in-app browser above."
        }
    }
}
