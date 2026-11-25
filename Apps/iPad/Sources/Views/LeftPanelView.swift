import SwiftUI

/// The LEFT panel (v0.3.0): segmented sections —
///  * Parts: the part tree (folders + name directories),
///  * History: the parametric step list,
///  * Properties: the inspector, moved here from the right side,
///  * View: every view control (grid/axes/labels/display mode/
///    camera rotation/measure) — added in v0.3.2; in v0.3.0 these
///    existed only as console `view ...` commands.
/// The command UI lives on the RIGHT now (CommandPanelView); the
/// viewport stays centre.
struct LeftPanelView: View {
    @State private var tab: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("Panel", selection: $tab) {
                Text("Parts").tag(0)
                Text("History").tag(1)
                // "Properties" truncated to "Properti…" in the
                // 300 pt panel's four-way segmented control
                // (v0.4.2, same device screenshot as the title
                // fix) — the short label fits without truncation.
                Text("Props").tag(2)
                Text("View").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(8)
            Divider()
            switch tab {
            case 0: PartTreeView()
            case 1: HistoryView()
            case 3: ViewPanelView()
            default: PropertiesView()
            }
        }
    }
}
