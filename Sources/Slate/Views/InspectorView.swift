import SwiftUI

/// Right-hand inspector: Outline (headings of the current note) and Backlinks
/// (notes that link to the current note).
struct InspectorView: View {
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var ui: UIState

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $ui.inspectorTab) {
                ForEach(InspectorTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)
            Divider()
            switch ui.inspectorTab {
            case .outline:   outline
            case .backlinks: backlinks
            }
        }
        .frame(minWidth: 220)
    }

    @ViewBuilder
    private var outline: some View {
        if vault.outline.isEmpty {
            ContentUnavailableView("No headings", systemImage: "list.bullet.indent")
        } else {
            List(vault.outline) { item in
                Button { vault.scrollRequest = item.charIndex } label: {
                    Text(item.title)
                        .lineLimit(1)
                        .padding(.leading, CGFloat(item.level - 1) * 12)
                        .font(item.level <= 1 ? .body.weight(.semibold) : .body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var backlinks: some View {
        if vault.selection == nil {
            ContentUnavailableView("No note open", systemImage: "link")
        } else if vault.backlinks.isEmpty {
            ContentUnavailableView("No backlinks", systemImage: "link",
                description: Text("No other notes link here yet."))
        } else {
            List(vault.backlinks) { link in
                Button { vault.select(link.source) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(link.sourceName).font(.body.weight(.medium)).lineLimit(1)
                        Text(link.context).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
