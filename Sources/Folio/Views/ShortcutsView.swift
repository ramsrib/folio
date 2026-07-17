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
        Group(title: "Search & Navigation", items: [
            Item(keys: "⌘O / ⌘K", label: "Quick switcher (open note)"),
            Item(keys: "⇧⌘F", label: "Search in vault (content)"),
            Item(keys: "⌘P", label: "Command palette"),
            Item(keys: "⇧⌘Y", label: "Browse tags"),
            Item(keys: "⌘[ / ⌘⌥←", label: "Back"),
            Item(keys: "⌘] / ⌘⌥→", label: "Forward"),
        ]),
        Group(title: "Tabs", items: [
            Item(keys: "⌃⇥", label: "Next tab"),
            Item(keys: "⌃⇧⇥", label: "Previous tab"),
            Item(keys: "⌘1…⌘8", label: "Go to tab N"),
            Item(keys: "⌘9", label: "Go to last tab"),
        ]),
        Group(title: "Quick Switcher", items: [
            Item(keys: "↩", label: "Open selection"),
            Item(keys: "⌘↩", label: "Open in new tab"),
            Item(keys: "⇧↩", label: "Create note from query"),
            Item(keys: "#", label: "Jump to heading in note"),
        ]),
        Group(title: "View", items: [
            Item(keys: "⌘E", label: "Toggle reading / writing mode"),
            Item(keys: "esc", label: "Writing → reading (closes find bar first)"),
            Item(keys: "⌃⌘S", label: "Toggle sidebar"),
        ]),
        Group(title: "Reading Mode (Vim)", items: [
            Item(keys: "j / k", label: "Scroll down / up"),
            Item(keys: "h / l", label: "Scroll left / right"),
            Item(keys: "d / u", label: "Half-page down / up"),
            Item(keys: "⌃F / Space", label: "Page down"),
            Item(keys: "⌃B / ⇧Space", label: "Page up"),
            Item(keys: "gg", label: "Jump to top"),
            Item(keys: "G", label: "Jump to bottom"),
        ]),
        Group(title: "Find in Page", items: [
            Item(keys: "⌘F", label: "Find in page (reading & writing)"),
            Item(keys: "↩ / ⌘G", label: "Next match"),
            Item(keys: "⌘⇧G", label: "Previous match"),
            Item(keys: "esc", label: "Close find"),
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
