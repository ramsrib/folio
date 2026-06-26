import SwiftUI

/// ⌘/ — a read-only cheat sheet of every keyboard shortcut, shown as a floating
/// rounded palette matching the Quick Switcher / Command Palette chrome.
struct ShortcutsView: View {
    @EnvironmentObject private var ui: UIState
    @FocusState private var focused: Bool

    private struct Item: Identifiable {
        let id = UUID()
        let keys: String
        let label: String
    }
    private struct Group: Identifiable {
        let id = UUID()
        let title: String
        let items: [Item]
    }

    private let groups: [Group] = [
        Group(title: "Notes", items: [
            Item(keys: "⌘N", label: "New note"),
            Item(keys: "⌘W", label: "Close tab"),
            Item(keys: "⇧⌘T", label: "Reopen closed tab"),
        ]),
        Group(title: "Navigation", items: [
            Item(keys: "⌘K", label: "Search files"),
            Item(keys: "⌘P", label: "Command palette"),
            Item(keys: "⇧⌘Y", label: "Browse tags"),
            Item(keys: "⌃⇥", label: "Next tab"),
            Item(keys: "⌃⇧⇥", label: "Previous tab"),
        ]),
        Group(title: "View", items: [
            Item(keys: "⌘E", label: "Toggle reading / writing mode"),
        ]),
        Group(title: "Vault", items: [
            Item(keys: "⇧⌘O", label: "Open vault"),
            Item(keys: "⇧⌘R", label: "Reload vault"),
        ]),
        Group(title: "Help", items: [
            Item(keys: "⌘/", label: "Keyboard shortcuts"),
        ]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "keyboard").foregroundStyle(.secondary)
                Text("Keyboard Shortcuts").font(.title3.weight(.semibold))
                Spacer()
                Button { ui.showShortcuts = false } label: {
                    Image(systemName: "xmark.circle.fill").font(.title3)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel("Close")
            }
            .padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(group.title.uppercased())
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(group.items) { item in
                                HStack {
                                    Text(item.label)
                                    Spacer()
                                    Text(item.keys)
                                        .font(.callout.monospaced())
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(.primary.opacity(0.06),
                                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                }
                            }
                        }
                    }
                }
                .padding(18)
            }
        }
        .frame(width: 460, height: 520)
        .paletteSurface()
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onExitCommand { ui.showShortcuts = false }
    }
}
