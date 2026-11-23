import SwiftUI

/// Root layout.
/// - Regular width (iPad): split view — sidebar objects, detail is the
///   viewport over the console.
/// - Compact width: tabs (Console / 3D View / Objects / Files).
/// Settings and the script editor are reached from the toolbar in both.
struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKeys.welcomeShown) private var welcomeShown = false
    @AppStorage(SettingsKeys.autosave) private var autosave = true

    @State private var showingSettings = false
    @State private var showingFiles = false
    @State private var showingWelcome = false
    @State private var showingScriptEditor = false

    var body: some View {
        Group {
            if sizeClass == .regular {
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
        .sheet(isPresented: $showingWelcome) {
            WelcomeView()
        }
        .onAppear {
            if !welcomeShown {
                showingWelcome = true
                welcomeShown = true
            }
        }
        .onChange(of: scenePhase) {
            // Autosave (Settings) = save the script buffer whenever the
            // app leaves the foreground. The interval setting is kept
            // for a future timer-based refinement.
            if scenePhase == .background && autosave {
                state.saveBuffer()
            }
        }
    }

    // MARK: - iPad layout

    private var regularLayout: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                ObjectListView()
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick files")
                        .font(.headline)
                    Button {
                        showingFiles = true
                    } label: {
                        Label("Browse Documents", systemImage: "folder")
                    }
                    Button {
                        showingScriptEditor = true
                    } label: {
                        Label("Script Editor", systemImage: "doc.text")
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Objects")
        } detail: {
            VStack(spacing: 0) {
                ViewportView(renderer: state.renderer)
                    .frame(maxHeight: .infinity)
                Divider()
                ConsoleView()
                    .frame(maxHeight: .infinity)
            }
            .navigationTitle("Cascade Console")
            .toolbar { detailToolbar }
        }
    }

    // MARK: - Compact layout

    private var compactLayout: some View {
        TabView {
            NavigationStack {
                ConsoleView()
                    .navigationTitle("Console")
                    .toolbar { detailToolbar }
            }
            .tabItem { Label("Console", systemImage: "terminal") }

            NavigationStack {
                ViewportView(renderer: state.renderer)
                    .navigationTitle("3D View")
            }
            .tabItem { Label("3D View", systemImage: "cube") }

            NavigationStack {
                ObjectListView()
                    .navigationTitle("Objects")
            }
            .tabItem { Label("Objects", systemImage: "list.bullet") }

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
        ToolbarItemGroup(placement: .topBarTrailing) {
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
                    .textInputAutocapitalization(.never)
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showingScriptEditor = false }
                }
            }
        }
    }
}
