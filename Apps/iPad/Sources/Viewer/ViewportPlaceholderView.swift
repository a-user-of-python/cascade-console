import SwiftUI

/// Placeholder 3D viewport. Agent 5's Metal viewer replaces this view;
/// the bridge wiring (display / fit / wireframe) is already live so the
/// swap is a one-file change in ContentView.
struct ViewportPlaceholderView: View {
    @ObservedObject var bridge: PlaceholderViewerBridge
    @AppStorage(SettingsKeys.highContrast) private var highContrast = false

    var body: some View {
        ZStack {
            gridBackdrop
            VStack(spacing: 10) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text("3D View")
                    .font(.headline)
                Text(bridge.displayedNames.isEmpty
                     ? "Nothing displayed yet. Create an object, then run: view"
                     : "Showing: \(bridge.displayedNames.joined(separator: ", "))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Text("The Metal viewer (Shared/Viewer) plugs in here via the ViewerBridge protocol.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            VStack {
                Spacer()
                HStack(spacing: 10) {
                    GlassChipButton(title: "Fit", systemImage: "arrow.up.left.and.arrow.down.right") {
                        bridge.fitAll()
                    }
                    GlassChipButton(
                        title: bridge.isWireframe ? "Shaded" : "Wireframe",
                        systemImage: "grid") {
                        bridge.setWireframe(!bridge.isWireframe)
                    }
                    Spacer()
                    Text("\(bridge.displayedNames.count) object(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
            }
        }
        .accessibilityLabel("3D viewport placeholder")
    }

    private var gridBackdrop: some View {
        Canvas { context, size in
            let step: CGFloat = 28
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            context.stroke(
                path,
                with: .color(.secondary.opacity(highContrast ? 0.35 : 0.18)),
                lineWidth: 1)
        }
        .background(Color(.secondarySystemBackground))
    }
}
