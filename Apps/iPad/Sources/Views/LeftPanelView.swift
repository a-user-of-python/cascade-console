import SwiftUI

/// The LEFT panel (v0.3.0): three segmented sections —
///  * Parts: the part tree (folders + name directories),
///  * History: the parametric step list,
///  * Properties: the inspector, moved here from the right side.
/// The command UI lives on the RIGHT now (CommandPanelView); the
/// viewport stays centre.
struct LeftPanelView: View {
    @State private var tab: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("Panel", selection: $tab) {
                Text("Parts").tag(0)
                Text("History").tag(1)
                Text("Properties").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(8)
            Divider()
            switch tab {
            case 0: PartTreeView()
            case 1: HistoryView()
            default: PropertiesView()
            }
        }
    }
}
