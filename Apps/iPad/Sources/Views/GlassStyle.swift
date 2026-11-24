import SwiftUI

/// Liquid Glass panel styling with a material fallback.
///
/// Uses the real `glassEffect` API on iOS 26+, and falls back to
/// `ultraThinMaterial` on earlier systems so the app looks coherent
/// everywhere. Applied sparingly (command bar, toolbar chips, cards)
/// to keep contrast high and the layout uncluttered.
struct GlassPanelModifier: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(.secondary.opacity(0.35), lineWidth: 1))
        }
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 14) -> some View {
        modifier(GlassPanelModifier(cornerRadius: cornerRadius))
    }

    /// iOS text-entry hygiene for command / file-name / numeric
    /// fields (no autocapitalisation). A no-op on macOS, which has
    /// no such modifier — Mac text fields never autocapitalise.
    /// (v0.3.1: lets the shared views compile for both apps from one
    /// source instead of scattering #if os(iOS) through every form.)
    @ViewBuilder
    func noAutocapitalization() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never)
        #else
        self
        #endif
    }

    /// Numeric keypad hint on iOS; a no-op on macOS (no on-screen
    /// keyboard to hint at).
    @ViewBuilder
    func numericKeyboard() -> some View {
        #if os(iOS)
        self.keyboardType(.numbersAndPunctuation)
        #else
        self
        #endif
    }
}

extension ToolbarItemPlacement {
    /// The trailing toolbar placement: `.topBarTrailing` on iOS;
    /// macOS has no top bar, so the primary-action area instead
    /// (v0.3.1 — one spelling for every toolbar in the shared UI).
    static var trailing: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }
}

/// Small pill button used in toolbars and the viewport overlay.
struct GlassChipButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.callout)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .glassPanel(cornerRadius: 20)
        .accessibilityLabel(title)
    }
}
