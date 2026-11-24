import SwiftUI

/// Root layout (v0.3.0 — the UI-first redesign).
/// - Regular width (iPad): LEFT panel = Parts tree / History /
///   Properties (segmented), CENTRE = the 3D viewport, RIGHT sidebar
///   = the command UI (command list + parameter forms). The text
///   console is no longer the home screen: it survives as a toolbar
///   sheet here, because scripts, exports and the sim commands still
///   live there — but building a model is a UI task now.
/// - Compact width: tabs (Model / Build / Library / Console / Files).
/// Settings and the script editor are reached from the toolbar in both.
struct ContentView: View {
    @EnvironmentObject private var state: AppState
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @Environment(\.scenePhase) private var scenePhase

    /// macOS has no size classes: a Mac window always gets the
    /// regular three-panel layout (v0.3.1 — the Mac app compiles
    /// these same sources).
    private var isRegularWidth: Bool {
        #if os(iOS)
        sizeClass == .regular
        #else
        true
        #endif
    }

    /// `.topBarTrailing` does not exist on macOS; the toolbar group
    /// goes in the primary-action area there instead.
    private var trailingToolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }
    @AppStorage(SettingsKeys.welcomeShown) private var welcomeShown = false
    @AppStorage(SettingsKeys.autosave) private var autosave = true

    @State private var showingSettings = false
    @State private var showingFiles = false
    @State private var showingWelcome = false
    @State private var showingScriptEditor = false
    @State private var showingConsole = false
    @State private var confirmingNewProject = false
    @State private var showingSaveProjectAs = false
    @State private var saveProjectName = ""

    var body: some View {
        Group {
            if isRegularWidth {
                regularLayout
            } else {
                compactLayout
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack { SettingsView() }
        }
        .sheet(isPresented: $showingFiles) {
            NavigationStack {
                FileBrowserView(store: state.fileStore)
                    .navigationTitle("Files")
            }
        }
        .sheet(isPresented: $showingScriptEditor) {
            scriptEditorSheet
        }
        .sheet(isPresented: $showingConsole) {
            NavigationStack {
                ConsoleView()
                    .navigationTitle("Console")
                    .toolbar {
                        ToolbarItem(placement: trailingToolbarPlacement) {
                            Button("Done") { showingConsole = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingWelcome) {
            WelcomeView()
        }
        .alert("Save Project As", isPresented: $showingSaveProjectAs) {
            TextField("Project file name", text: $saveProjectName)
            Button("Save") {
                if !saveProjectName.isEmpty {
                    state.currentProjectName = saveProjectName
                        .hasSuffix(".cascadeproj")
                        ? saveProjectName : saveProjectName + ".cascadeproj"
                }
                state.saveProject()
            }
            Button("Cancel", role: .cancel) { }
        }
        .confirmationDialog(
            "Start a new project?",
            isPresented: $confirmingNewProject,
            titleVisibility: .visible) {
            Button("New Project", role: .destructive) {
                state.newProject()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The current step history and model are cleared. Save the project first if you want to keep them.")
        }
        .onAppear {
            if !welcomeShown {
                showingWelcome = true
                welcomeShown = true
            }
            // Feed the viewport on appearance too, so objects created
            // before the view attached (e.g. by a script run from the
            // Files tab) still render without another command.
            Task { await state.refreshScene(fit: false) }
        }
        .onChange(of: scenePhase) {
            // Autosave (Settings) = save the script buffer whenever the
            // app leaves the foreground, as before. Project saving is
            // explicit (Save Project in the toolbar) so a half-edited
            // history is never silently persisted.
            if scenePhase == .background && autosave {
                state.saveBuffer()
            }
        }
    }

    // MARK: - iPad layout

    private var regularLayout: some View {
        NavigationStack {
            HStack(spacing: 0) {
                LeftPanelView()
                    .frame(width: 300)
                Divider()
                ViewportView(renderer: state.renderer,
                             objectCount: state.viewerObjectCount)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                CommandPanelView()
                    .frame(width: 320)
            }
            .navigationTitle("Cascade Console")
            .toolbar { detailToolbar }
        }
    }

    // MARK: - Compact layout

    private var compactLayout: some View {
        TabView {
            NavigationStack {
                ViewportView(renderer: state.renderer,
                             objectCount: state.viewerObjectCount)
                    .navigationTitle("Model")
                    .toolbar { detailToolbar }
            }
            .tabItem { Label("Model", systemImage: "cube") }

            NavigationStack {
                CommandPanelView()
                    .navigationTitle("Build")
            }
            .tabItem { Label("Build", systemImage: "plus.square") }

            NavigationStack {
                LeftPanelView()
                    .navigationTitle("Library")
            }
            .tabItem { Label("Library", systemImage: "list.bullet") }

            NavigationStack {
                ConsoleView()
                    .navigationTitle("Console")
            }
            .tabItem { Label("Console", systemImage: "terminal") }

            NavigationStack {
                FileBrowserView(store: state.fileStore)
                    .navigationTitle("Files")
            }
            .tabItem { Label("Files", systemImage: "folder") }
        }
    }

    // MARK: - Shared pieces

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: trailingToolbarPlacement) {
            Button {
                confirmingNewProject = true
            } label: {
                Label("New Project", systemImage: "doc.badge.plus")
            }
            Button {
                state.saveProject()
            } label: {
                Label("Save Project", systemImage: "square.and.arrow.down")
            }
            Button {
                saveProjectName = state.currentProjectName
                showingSaveProjectAs = true
            } label: {
                Label("Save Project As", systemImage: "square.and.arrow.down.on.square")
            }
            Button {
                showingConsole = true
            } label: {
                Label("Console", systemImage: "terminal")
            }
            Button {
                showingScriptEditor = true
            } label: {
                Label("Script Editor", systemImage: "doc.text")
            }
            Button {
                showingFiles = true
            } label: {
                Label("Files", systemImage: "folder")
            }
            Button {
                showingSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }

    private var scriptEditorSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField("File name", text: $state.currentFileName)
                    .noAutocapitalization()
                    .autocorrectionDisabled(true)
                    .padding(10)
                Divider()
                TextEditor(text: $state.scriptBuffer)
                    .font(.callout.monospaced())
                    .padding(6)
                HStack(spacing: 10) {
                    GlassChipButton(title: "Save", systemImage: "square.and.arrow.down.on.square") {
                        state.saveBuffer()
                    }
                    GlassChipButton(title: "Run Script", systemImage: "play.fill") {
                        state.runScript(state.scriptBuffer)
                        showingScriptEditor = false
                    }
                    Spacer()
                }
                .padding(10)
            }
            .navigationTitle("Script")
            .toolbar {
                ToolbarItem(placement: trailingToolbarPlacement) {
                    Button("Done") { showingScriptEditor = false }
                }
            }
        }
    }
}
