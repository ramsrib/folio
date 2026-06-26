import SwiftUI

/// Browse all tags in the vault (inline `#tags` + frontmatter `tags:`); pick one
/// to see the notes that use it. Styled as a floating rounded palette.
struct TagsView: View {
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var ui: UIState
    @State private var query = ""
    @State private var selectedTag: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let tag = selectedTag {
                noteList(for: tag)
            } else {
                tagList
            }
        }
        .frame(width: 520, height: 440)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.separator.opacity(0.5)))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 30, y: 12)
        .presentationBackground(.clear)
        .onExitCommand { if selectedTag != nil { selectedTag = nil } else { ui.showTags = false } }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if selectedTag != nil {
                Button { selectedTag = nil } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back to tags")
            } else {
                Image(systemName: "number").foregroundStyle(.secondary)
            }
            Text(selectedTag.map { "#\($0)" } ?? "Tags").font(.title3)
            Spacer()
            if selectedTag == nil {
                TextField("Filter…", text: $query).textFieldStyle(.plain).frame(width: 160)
            }
        }
        .padding(12)
    }

    private var tagList: some View {
        let q = query.lowercased()
        let tags = vault.allTags.filter { q.isEmpty || $0.tag.lowercased().contains(q) }
        return List(tags, id: \.tag) { item in
            HStack {
                Text("#\(item.tag)")
                Spacer()
                Text("\(item.count)").foregroundStyle(.secondary).monospacedDigit()
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .onTapGesture { selectedTag = item.tag }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if tags.isEmpty {
                ContentUnavailableView("No tags", systemImage: "number",
                    description: Text("Add #tags or a frontmatter tags: list to your notes."))
            }
        }
    }

    private func noteList(for tag: String) -> some View {
        List(vault.notes(forTag: tag)) { file in
            HStack(spacing: 8) {
                Image(systemName: "doc.text").foregroundStyle(.secondary)
                Text(file.name)
                Spacer()
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .onTapGesture { vault.select(file.id); ui.showTags = false }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}
