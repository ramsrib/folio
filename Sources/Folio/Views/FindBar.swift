import SwiftUI

/// The one find-in-page bar, shared by Reading and Writing modes. Wide and
/// prominent — find is a primary action in Folio — bound entirely to `FindModel`.
/// It's docked into the note layout (above the title) by its host, not floated
/// over content.
struct FindBar: View {
    @ObservedObject var find: FindModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.system(size: 15)).foregroundStyle(.secondary)

            // PaletteTextField, not TextField: same first-responder reliability
            // fix as the palettes — SwiftUI focus requests lost the race with the
            // editor/window, leaving ⌘F with an unfocused field. This one takes
            // focus on creation and re-takes it on every focusRequest bump.
            PaletteTextField(text: $find.query, placeholder: "Find in page", fontSize: 16,
                             onSubmit: { $0.contains(.shift) ? find.prev() : find.next() },
                             focusToken: find.focusRequest,
                             onEscape: { find.close() })
                .frame(height: 21)
                .frame(maxWidth: .infinity)

            if !find.query.isEmpty {
                Text(find.total == 0 ? "No results" : "\(find.current + 1) of \(find.total)")
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }

            Button { find.caseSensitive.toggle() } label: { Text("Aa").font(.system(size: 14, weight: .semibold)) }
                .foregroundStyle(find.caseSensitive ? settings.selectionTint : .secondary)
                .help("Case sensitive")

            Divider().frame(height: 20)

            Button { find.prev() } label: { Image(systemName: "chevron.up") }
                .disabled(find.total == 0).help("Previous match (⌘⇧G)")
            Button { find.next() } label: { Image(systemName: "chevron.down") }
                .disabled(find.total == 0).help("Next match (↩ / ⌘G)")
            Button { find.close() } label: { Image(systemName: "xmark") }
                .help("Close (esc)").accessibilityLabel("Close find")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 15))
        .padding(.horizontal, 16).padding(.vertical, 11)
        // Same themed surface as the palettes (Paper → cream, else material) so the
        // finder matches the app's chrome instead of a gray material box.
        .background(settings.surfaceStyle, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator.opacity(0.5)))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
        .onExitCommand { find.close() }
    }
}
