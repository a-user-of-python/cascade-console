import SwiftUI

// MARK: - Liquid Glass styling, with a graceful fallback
//
// macOS 26 introduces Liquid Glass (`glassEffect`, `GlassEffectContainer`).
// The user's Mac is a 2019 Intel MacBook Pro running macOS 26, so the glass
// path is the expected one — but every glass surface in this app goes
// through the two helpers below, which fall back to a standard material on
// older macOS instead of failing or looking broken. Never call
// `glassEffect` directly from a view; use these.

/// A glass (or fallback material) rounded panel background for toolbars
/// and floating control groups.
struct GlassPanelModifier: ViewModifier {
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        styled(content)
    }

    @ViewBuilder
    private func styled(_ content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            content
                .background(.ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(.separator, lineWidth: 1)
                )
        }
    }
}

/// A single glass (or fallback) toolbar button.
struct GlassButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        styled(content)
    }

    @ViewBuilder
    private func styled(_ content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content
                .background(.thinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.separator, lineWidth: 1))
        }
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 12) -> some View {
        modifier(GlassPanelModifier(cornerRadius: cornerRadius))
    }

    func glassButton() -> some View {
        modifier(GlassButtonModifier())
    }
}

/// Wraps a row of toolbar controls in a GlassEffectContainer on macOS 26
/// (so adjacent glass buttons blend correctly) and in a plain HStack with
/// the panel fallback everywhere else.
struct GlassToolbarGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    content()
                }
            }
        } else {
            HStack(spacing: 8) {
                content()
            }
            .padding(6)
            .glassPanel()
        }
    }
}
