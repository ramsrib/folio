import SwiftUI

/// Browse all tags (inline `#tags` + frontmatter `tags:`); pick one to see its
/// notes. Styled to match the Quick Switcher / Command Palette.
struct TagsView: View {
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var ui: UIState
    @State private var query = ""
    @State private var selected = 0
    @State private var selectedTag: String?
    @FocusState private var focused: Bool

    private var tags: [(tag: String, count: Int)] {
        let q = query.lowercased()
        return vault.allTags.filter { q.isEmpty || $0.tag.lowercased().contains(q) }
    }
    private var notes: [MarkdownFile] {
        guard let t = selectedTag else { return [] }
        let q = query.lowercased()
        return vault.notes(forTag: t).filter { q.isEmpty || $0.name.lowercased().contains(q) }
    }
    private var rowCount: Int { selectedTag == nil ? tags.count : notes.count }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollViewReader { proxy in
                List {
                    if selectedTag == nil { tagRows } else { noteRows }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 30)
                .animation(.easeOut(duration: 0.12), value: selected)
                .onChange(of: selected) { proxy.scrollTo(selected, anchor: .center) }
            }
        }
        .frame(width: 560, height: 440)
        .paletteSurface()
        .onAppear { focused = true }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.return) { activate(); return .handled }
        .onExitCommand { back() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if selectedTag != nil {
                Button { back() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityLabel("Back to tags")
            }
            Image(systemName: selectedTag == nil ? "number" : "tag").foregroundStyle(.secondary)
            TextField(selectedTag == nil ? "Filter tags…" : "Filter #\(selectedTag!)…", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($focused)
                .onChange(of: query) { selected = 0 }
                .onSubmit(activate)
        }
        .padding(14)
    }

    private var tagRows: some View {
        ForEach(Array(tags.enumerated()), id: \.element.tag) { idx, item in
            HStack {
                Text("#\(item.tag)")
                Spacer()
                Text("\(item.count)").font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .id(idx)
            .listRowSeparator(.hidden)
            .listRowBackground(rowBackground(idx))
            .onTapGesture { selected = idx; activate() }
        }
    }

    private var noteRows: some View {
        ForEach(Array(notes.enumerated()), id: \.element.id) { idx, file in
            HStack(spacing: 8) {
                Image(systemName: "doc.text").foregroundStyle(.secondary)
                Text(file.name).lineLimit(1)
                Spacer()
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .id(idx)
            .listRowSeparator(.hidden)
            .listRowBackground(rowBackground(idx))
            .onTapGesture { selected = idx; activate() }
        }
        .overlay(alignment: .center) {
            if notes.isEmpty {
                ContentUnavailableView("No notes", systemImage: "doc.text")
            }
        }
    }

    private func rowBackground(_ idx: Int) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(idx == selected ? Color.accentColor.opacity(0.22) : .clear)
    }

    private func move(_ delta: Int) {
        guard rowCount > 0 else { return }
        selected = min(max(selected + delta, 0), rowCount - 1)
    }

    private func activate() {
        if selectedTag == nil {
            guard tags.indices.contains(selected) else { return }
            selectedTag = tags[selected].tag
            query = ""; selected = 0
        } else {
            guard notes.indices.contains(selected) else { return }
            vault.select(notes[selected].id)
            ui.showTags = false
        }
    }

    private func back() {
        if selectedTag != nil { selectedTag = nil; query = ""; selected = 0 }
        else { ui.showTags = false }
    }
}
