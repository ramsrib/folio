import SwiftUI
import AppKit

/// Shared chrome for the floating palettes (Quick Switcher, Command Palette,
/// Tags, Shortcuts): rounded surface tinted to the theme (Paper → cream, else
/// material), hairline border, and shadow. Presented as an in-window overlay
/// (see ContentView.paletteOverlay), so there's no sheet window to flash white.
private struct PaletteSurface: ViewModifier {
    @EnvironmentObject private var settings: AppSettings

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return content
            .background(settings.surfaceStyle, in: shape)
            .overlay(shape.strokeBorder(.separator.opacity(0.5)))
            .clipShape(shape)
            .shadow(color: .black.opacity(0.25), radius: 30, y: 12)
    }
}

extension View {
    /// Apply the themed floating-palette chrome.
    func paletteSurface() -> some View { modifier(PaletteSurface()) }
}
