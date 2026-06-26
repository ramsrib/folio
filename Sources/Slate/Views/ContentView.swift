import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var ui: UIState
    @EnvironmentObject private var settings: AppSettings
    @State private var renameTarget: URL?
    @State private var renameText = ""
    @State private var expandedDirs: Set<URL> = []
    @State private var showSidebar = true
    @State private var sidebarWidth: CGFloat = 280
    @State private var dragStartWidth: CGFloat?

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            HStack(spacing: 0) {
                if showSidebar {
                    sidebar.frame(width: sidebarWidth)
                    resizeDivider
                }
                EditorPane()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ignoresSafeArea(.container, edges: .top)   // let the title-bar row reach the traffic-light line
        .background(WindowConfigurator(background: settings.nsWindowBackground))
        .onChange(of: vault.selection) {
            ui.mode = vault.openInEditMode ? .edit : .read
            vault.openInEditMode = false
        }
        .sheet(isPresented: $ui.showQuickSwitcher) { QuickSwitcherView() }
        .sheet(isPresented: $ui.showCommandPalette) { CommandPaletteView() }
        .sheet(isPresented: $ui.showTags) { TagsView() }
        .alert("Rename Note", isPresented: renamePresented) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Rename") {
                if let t = renameTarget { vault.rename(t, to: renameText) }
                renameTarget = nil
            }
        }
    }

    // MARK: Title bar — a plain content row that fills the title-bar strip
    // (via fullSizeContentView). Tabs live in a ScrollView so they scroll with
    // many tabs and can never collapse into a ">>" overflow menu.

    private var titleBar: some View {
        HStack(spacing: 8) {
            Button { withAnimation(.smooth(duration: 0.2)) { showSidebar.toggle() } } label: {
                Image(systemName: "sidebar.leading")
            }
            .buttonStyle(.borderless).help("Toggle sidebar").accessibilityLabel("Toggle sidebar")

            Text(vault.vaultURL?.lastPathComponent ?? "Slate")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                .lineLimit(1).fixedSize()

            if vault.openTabs.isEmpty {
                Spacer()
            } else {
                Divider().frame(height: 16)
                TabBarView().frame(maxWidth: .infinity, alignment: .leading)
            }

            actionButtons
        }
        .padding(.leading, 80)   // clear the traffic lights
        .padding(.trailing, 12)
        .frame(height: 42)
        .background(settings.topBarBackground)
    }

    private var actionButtons: some View {
        HStack(spacing: 6) {
            Button { ui.showTags = true } label: { Image(systemName: "number") }
                .help("Browse tags").accessibilityLabel("Browse tags").disabled(vault.vaultURL == nil)
            Button { vault.newNote() } label: { Image(systemName: "square.and.pencil") }
                .help("New note").accessibilityLabel("New note").disabled(vault.vaultURL == nil)
            Button { vault.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .help("Reload vault").accessibilityLabel("Reload vault").disabled(vault.vaultURL == nil)
            Button {
                withAnimation(.smooth(duration: 0.2)) { ui.mode = ui.mode == .read ? .edit : .read }
            } label: { Image(systemName: ui.mode == .read ? "pencil" : "eye") }
                .help(ui.mode == .read ? "Edit" : "Reading mode")
                .accessibilityLabel(ui.mode == .read ? "Switch to editing" : "Switch to reading")
                .disabled(vault.selection == nil)
        }
        .buttonStyle(.borderless)
        .imageScale(.large)
    }

    private var resizeDivider: some View {
        Divider()
            .overlay(
                Color.clear.frame(width: 8).contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(DragGesture()
                        .onChanged { v in
                            if dragStartWidth == nil { dragStartWidth = sidebarWidth }
                            sidebarWidth = min(max((dragStartWidth ?? sidebarWidth) + v.translation.width, 200), 480)
                        }
                        .onEnded { _ in dragStartWidth = nil })
            )
    }

    // MARK: Sidebar

    @ViewBuilder
    private var sidebar: some View {
        if vault.vaultURL == nil {
            ContentUnavailableView {
                Label("No vault open", systemImage: "folder.badge.questionmark")
            } description: {
                Text("Open a folder of Markdown notes to get started.")
            } actions: {
                Button("Open Vault…") { vault.pickVault() }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            List(selection: Binding(get: { vault.selection }, set: { vault.select($0) })) {
                ForEach(vault.tree) { node in
                    FileTreeRow(node: node, expanded: $expandedDirs, startRename: startRename)
                }
            }
            .listStyle(.sidebar)
            .onChange(of: vault.vaultURL) { expandedDirs.removeAll() }
            .overlay {
                if vault.tree.isEmpty {
                    ContentUnavailableView("No notes", systemImage: "doc.text",
                        description: Text("No Markdown files found in this folder."))
                }
            }
        }
    }

    // MARK: Rename

    private var renamePresented: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }

    private func startRename(_ url: URL) {
        renameText = url.lastPathComponent
        renameTarget = url
    }
}
