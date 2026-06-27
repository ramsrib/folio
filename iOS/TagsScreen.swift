import SwiftUI

/// Browse tags (inline #tags + frontmatter), drill into a tag's notes, tap to open.
struct TagsScreen: View {
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss
    /// Called with a note to open; the parent dismisses this sheet and navigates.
    let onOpen: (MarkdownFile) -> Void
    @State private var selectedTag: String?

    var body: some View {
        NavigationStack {
            List {
                if let tag = selectedTag {
                    ForEach(vault.notes(forTag: tag), id: \.id) { file in
                        Button { onOpen(file) } label: {
                            Label(file.name, systemImage: "doc.text").foregroundStyle(.primary)
                        }
                    }
                } else if vault.allTags.isEmpty {
                    ContentUnavailableView("No tags", systemImage: "number",
                        description: Text("Add #tags to your notes to see them here."))
                } else {
                    ForEach(vault.allTags, id: \.tag) { item in
                        Button { selectedTag = item.tag } label: {
                            HStack {
                                Text("#\(item.tag)").foregroundStyle(.primary)
                                Spacer()
                                Text("\(item.count)").foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle(selectedTag.map { "#\($0)" } ?? "Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if selectedTag != nil {
                        Button { selectedTag = nil } label: { Label("Tags", systemImage: "chevron.left") }
                    } else {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
    }
}
