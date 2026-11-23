import SwiftUI

/// The command console: scrolling output log on top, one input line below.
/// - Return runs the command.
/// - Up / Down arrows walk the command history.
/// - When the typed prefix matches known commands, tappable completions
///   appear above the input line, plus a Help button that runs `help`.
struct ConsoleView: View {
    @EnvironmentObject private var state: AppState
    @AppStorage(SettingsKey.consoleFontSize) private var consoleFontSize = 13.0
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            logView
            Divider()
            suggestionRow
            inputRow
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: Output log

    private var logView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(state.log) { entry in
                        logRow(entry)
                            .id(entry.id)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: state.log.count) { _, _ in
                if let last = state.log.last {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func logRow(_ entry: LogEntry) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: entry.level.symbolName)
                .foregroundStyle(entry.level.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.text)
                    .font(.system(size: consoleFontSize, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                if let code = entry.code {
                    Text("Error code \(code) — look this code up in the user guide for what went wrong and how to fix it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Autocomplete suggestions

    @ViewBuilder
    private var suggestionRow: some View {
        let suggestions = state.suggestions
        if !suggestions.isEmpty {
            HStack(spacing: 6) {
                Text("Did you mean:")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ForEach(suggestions, id: \.self) { suggestion in
                    Button(suggestion) {
                        state.applySuggestion(suggestion)
                        inputFocused = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
    }

    // MARK: Input line

    private var inputRow: some View {
        HStack(spacing: 8) {
            Text(">")
                .font(.system(size: consoleFontSize, design: .monospaced))
                .foregroundStyle(.secondary)
            TextField("Type a command — try \"help\"", text: $state.input)
                .textFieldStyle(.plain)
                .font(.system(size: consoleFontSize, design: .monospaced))
                .focused($inputFocused)
                .onSubmit {
                    state.submitInput()
                    inputFocused = true
                }
                .onKeyPress(.upArrow) {
                    state.historyBack()
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    state.historyForward()
                    return .handled
                }
                .accessibilityLabel("Command input")
            Button {
                state.runCommand("help")
                inputFocused = true
            } label: {
                Label("Help", systemImage: "questionmark.circle")
            }
            .buttonStyle(.bordered)
            .help("Show the command list (runs the help command)")
            Button {
                state.submitInput()
                inputFocused = true
            } label: {
                Label("Run", systemImage: "return")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [])
            .help("Run the typed command")
        }
        .padding(10)
        .onAppear {
            inputFocused = true
        }
    }
}
