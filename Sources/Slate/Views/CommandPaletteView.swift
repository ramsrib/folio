import SwiftUI
import AppKit

struct AppCommand: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let run: () -> Void
}

/// ⌘P — fuzzy command palette, styled as a floating rounded palette.
struct CommandPaletteView: View {
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var ui: UIState
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool

    private var commands: [AppCommand] {
        var c: [AppCommand] = [
            AppCommand(title: "New Note", subtitle: "⌘N") { vault.newNote() },
            AppCommand(title: "Open Vault…", subtitle: "⇧⌘O") { vault.pickVault() },
            AppCommand(title: "Reload Vault", subtitle: "⇧⌘R") { vault.refresh() },
            AppCommand(title: "Search Files…", subtitle: "⌘K") { ui.showQuickSwitcher = true },
            AppCommand(title: ui.mode == .read ? "Edit Mode" : "Reading Mode", subtitle: "⌘E") {
                ui.mode = ui.mode == .read ? .edit : .read },
        ]
        if let sel = vault.selection {
            c.append(AppCommand(title: "Reveal in Finder", subtitle: nil) {
                NSWorkspace.shared.activateFileViewerSelecting([sel]) })
            c.append(AppCommand(title: "Move Note to Trash", subtitle: nil) { vault.delete(sel) })
        }
        return c
    }

    private var results: [AppCommand] {
        let q = query.lowercased()
        return q.isEmpty ? commands : commands.filter { $0.title.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "command").foregroundStyle(.secondary)
                TextField("Run a command…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onChange(of: query) { selected = 0 }
                    .onSubmit(runSelected)
            }
            .padding(14)
            Divider()
            List {
                ForEach(Array(results.enumerated()), id: \.element.id) { idx, cmd in
                    HStack {
                        Text(cmd.title)
                        Spacer()
                        if let s = cmd.subtitle {
                            Text(s).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                    .onTapGesture { run(cmd) }
                    .listRowSeparator(.hidden)
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(idx == selected ? Color.accentColor.opacity(0.22) : .clear)
                    )
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .animation(.easeOut(duration: 0.12), value: selected)
        }
        .frame(width: 560, height: 400)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.separator.opacity(0.5)))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 30, y: 12)
        .presentationBackground(.clear)
        .onAppear { focused = true }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.return) { runSelected(); return .handled }
        .onExitCommand { ui.showCommandPalette = false }
    }

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selected = min(max(selected + delta, 0), results.count - 1)
    }

    private func runSelected() {
        guard results.indices.contains(selected) else { return }
        run(results[selected])
    }

    private func run(_ cmd: AppCommand) {
        ui.showCommandPalette = false
        cmd.run()
    }
}
