import SwiftUI

/// Part tree (v0.3.0, replacing the flat object list).
///
/// Two organisations, one tree:
///  * USER FOLDERS: organisational folders stored in the project
///    file; they nest, and every object/profile can be filed into
///    one via its row menu. Deleting a folder moves its contents to
///    the folder's parent — nothing is lost.
///  * NAME DIRECTORIES: everything not in a folder, grouped under
///    the directory of the command that created it (box/, cut/,
///    ...). Rows show DISPLAY names — a box "part" and a cut "part"
///    are different rows in different groups, which is the whole
///    point of the directories.
///
/// Tapping a row selects the object and, when a history step
/// produced it, that step — the right panel then edits the step.
struct PartTreeView: View {
    @EnvironmentObject private var state: AppState

    @State private var showingNewFolder = false
    @State private var newFolderParent: PartFolder?
    @State private var newFolderName = ""
    @State private var renamingFolder: PartFolder?
    @State private var renameText = ""

    /// All qualified names in the tree: objects + profiles.
    private var allNames: [String] {
        state.objects.map { $0.shapeID } + state.profiles
    }

    private var unfiledNames: [String] {
        allNames.filter { state.project.folderID(forObject: $0) == nil }
    }

    /// Folders flattened in display order (parents before children).
    private var flatFolders: [(folder: PartFolder, depth: Int)] {
        var out: [(folder: PartFolder, depth: Int)] = []
        func walk(_ parent: UUID?, _ depth: Int) {
            for folder in state.project.childFolders(of: parent) {
                out.append((folder: folder, depth: depth))
                walk(folder.id, depth + 1)
            }
        }
        walk(nil, 0)
        return out
    }

    var body: some View {
        Group {
            if allNames.isEmpty && state.project.folders.isEmpty {
                ContentUnavailableView(
                    "No Parts Yet",
                    systemImage: "cube",
                    description: Text("Pick a command in the Build panel to create your first part. Parts, their folders and the command directories appear here."))
            } else {
                List {
                    ForEach(flatFolders, id: \.folder.id) { entry in
                        Section {
                            let filed = allNames.filter {
                                state.project.folderID(forObject: $0)
                                    == entry.folder.id
                            }
                            ForEach(filed.sorted(), id: \.self) { name in
                                entryRow(name)
                            }
                        } header: {
                            folderHeader(entry.folder, depth: entry.depth)
                        }
                    }
                    ForEach(Array(CascadeNames.grouped(unfiledNames)
                                    .enumerated()),
                            id: \.offset) { _, group in
                        Section {
                            ForEach(group.names, id: \.self) { name in
                                entryRow(name)
                            }
                        } header: {
                            Text("Unfiled · \(group.directory)/")
                                .font(.caption.bold())
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newFolderParent = nil
                    newFolderName = ""
                    showingNewFolder = true
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
            }
        }
        .alert("New Folder", isPresented: $showingNewFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") {
                let name = newFolderName.trimmingCharacters(in: .whitespaces)
                state.project.addFolder(
                    name: name.isEmpty ? "Folder" : name,
                    parentID: newFolderParent?.id)
            }
            Button("Cancel", role: .cancel) { }
        }
        .alert("Rename Folder", isPresented: Binding(
            get: { renamingFolder != nil },
            set: { if !$0 { renamingFolder = nil } })) {
            TextField("Folder name", text: $renameText)
            Button("Rename") {
                if let folder = renamingFolder {
                    state.project.renameFolder(
                        id: folder.id,
                        name: renameText.trimmingCharacters(in: .whitespaces))
                }
                renamingFolder = nil
            }
            Button("Cancel", role: .cancel) { renamingFolder = nil }
        }
    }

    // MARK: - Folder header

    private func folderHeader(_ folder: PartFolder, depth: Int) -> some View {
        HStack {
            Image(systemName: "folder")
            Text(folder.name)
            Spacer()
            Menu {
                Button("Rename") {
                    renameText = folder.name
                    renamingFolder = folder
                }
                Button("Add Subfolder") {
                    newFolderParent = folder
                    newFolderName = ""
                    showingNewFolder = true
                }
                Button("Delete Folder", role: .destructive) {
                    state.project.deleteFolder(id: folder.id)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Folder actions for \(folder.name)")
        }
        .padding(.leading, CGFloat(depth) * 12)
    }

    // MARK: - Entries

    private func entryRow(_ qualified: String) -> some View {
        let isProfile = CascadeNames.directory(of: qualified) == "profile"
        let item = state.objects.first { $0.shapeID == qualified }
        let stepSelected = state.selectedStepID != nil &&
            state.project.steps.first(where: {
                $0.id == state.selectedStepID
            })?.assignedName == qualified
        let isSelected = stepSelected ||
            (item != nil && state.selectedObjectID == item?.id)
        return HStack(spacing: 8) {
            Image(systemName: isProfile ? "square.dashed"
                             : (item?.isVisible ?? true ? "cube.fill" : "cube"))
                .foregroundStyle(.secondary)
            Text(CascadeNames.display(of: qualified))
                .foregroundStyle(.primary)
            Spacer()
            if !isProfile, let item {
                Button {
                    state.toggleVisibility(item)
                } label: {
                    Image(systemName: item.isVisible ? "eye" : "eye.slash")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.isVisible ? "Hide" : "Show")
            }
            Menu {
                Button("Move to Top Level") {
                    state.project.moveObject(qualified, toFolder: nil)
                }
                ForEach(state.project.folders) { folder in
                    Button("Move to \(folder.name)") {
                        state.project.moveObject(qualified, toFolder: folder.id)
                    }
                }
                Divider()
                Button("Delete", role: .destructive) {
                    state.deleteTreeEntry(qualifiedName: qualified)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Actions for \(CascadeNames.display(of: qualified))")
        }
        .contentShape(Rectangle())
        .onTapGesture { state.selectTreeEntry(qualifiedName: qualified) }
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.15) : nil)
    }
}
