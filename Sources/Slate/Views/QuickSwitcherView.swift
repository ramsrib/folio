import SwiftUI

/// ⌘O — fuzzy "open note by name" overlay.
struct QuickSwitcherView: View {
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var ui: UIState
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool

    private var results: [MarkdownFile] {
        let q = query.lowercased()
        let matches = q.isEmpty ? vault.files : vault.files.filter {
            $0.name.lowercased().contains(q) || $0.relativePath.lowercased().contains(q)
        }
        return Array(matches.prefix(50))
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search notes…", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(12)
                .focused($focused)
                .onChange(of: query) { selected = 0 }
                .onSubmit(openSelected)
            Divider()
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(results.enumerated()), id: \.element.id) { idx, file in
                        HStack {
                            Image(systemName: "doc.text").foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(file.name).lineLimit(1)
                                if file.relativePath != "\(file.name).md" {
                                    Text(file.relativePath).font(.caption)
                                        .foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                        .listRowBackground(idx == selected ? Color.accentColor.opacity(0.25) : Color.clear)
                        .id(idx)
                        .onTapGesture { open(file) }
                    }
                }
                .onChange(of: selected) { proxy.scrollTo(selected, anchor: .center) }
            }
        }
        .frame(width: 620, height: 440)
        .onAppear { focused = true }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.return) { openSelected(); return .handled }
        .onExitCommand { ui.showQuickSwitcher = false }
    }

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selected = min(max(selected + delta, 0), results.count - 1)
    }

    private func openSelected() {
        guard results.indices.contains(selected) else { return }
        open(results[selected])
    }

    private func open(_ file: MarkdownFile) {
        vault.select(file.id)
        ui.showQuickSwitcher = false
    }
}
