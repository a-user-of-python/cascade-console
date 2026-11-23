import SwiftUI

/// Command console: scrolling output log, command field with history,
/// Run / Clear controls. Hardware keyboard: Return runs, Up/Down walk
/// history. Apple Pencil scribble works in the text field natively.
struct ConsoleView: View {
    @EnvironmentObject private var state: AppState
    @AppStorage(SettingsKeys.showTimestamps) private var showTimestamps = false
    @AppStorage(SettingsKeys.consoleFontSizeStep) private var fontStep = 0
    @AppStorage(SettingsKeys.confirmBeforeClear) private var confirmBeforeClear = true

    @State private var draft: String = ""
    @State private var showingClearConfirm = false
    @FocusState private var inputFocused: Bool

    private var logFont: Font {
        // Relative step only — the base size follows the device text-size
        // setting; we never hard-code a large fixed size.
        switch fontStep {
        case ..<0: return .caption.monospaced()
        case 0: return .callout.monospaced()
        default: return .body.monospaced()
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            logView
            Divider()
            inputBar
        }
        .confirmationDialog(
            "Clear the console log?",
            isPresented: $showingClearConfirm,
            titleVisibility: .visible) {
            Button("Clear Log", role: .destructive) { state.clearLog() }
            Button("Cancel", role: .cancel) { }
        }
    }

    private var logView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(state.log) { entry in
                        Text(displayText(for: entry))
                            .font(logFont)
                            .foregroundStyle(color(for: entry.kind))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(entry.id)
                    }
                }
                .padding(10)
            }
            .onChange(of: state.log.count) {
                if let last = state.log.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            Button {
                draft = state.historyPrevious(current: draft)
            } label: {
                Image(systemName: "chevron.up")
            }
            .accessibilityLabel("Previous command")

            Button {
                draft = state.historyNext(current: draft)
            } label: {
                Image(systemName: "chevron.down")
            }
            .accessibilityLabel("Next command")

            TextField("Command — try: help", text: $draft)
                .font(.callout.monospaced())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .focused($inputFocused)
                .onSubmit { submit() }
                .accessibilityLabel("Command input")

            Button {
                if confirmBeforeClear {
                    showingClearConfirm = true
                } else {
                    state.clearLog()
                }
            } label: {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Clear console log")

            Button(action: submit) {
                Label("Run", systemImage: "play.fill")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.plain)
            .glassPanel(cornerRadius: 18)
            .disabled(state.isRunning || draft.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel("Run command")
        }
        .padding(10)
        .glassPanel(cornerRadius: 0)
    }

    private func submit() {
        let command = draft
        draft = ""
        state.run(command: command)
    }

    private func displayText(for entry: LogEntry) -> String {
        if showTimestamps {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            return "[\(formatter.string(from: entry.date))] \(entry.text)"
        }
        return entry.text
    }

    private func color(for kind: LogEntry.Kind) -> Color {
        switch kind {
        case .input: return .primary
        case .output: return .secondary
        case .error: return .red
        case .info: return .blue
        }
    }
}
