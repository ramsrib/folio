import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark, paper, frosted
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system:  return "System"
        case .light:   return "Light"
        case .dark:    return "Dark"
        case .paper:   return "Paper (warm)"
        case .frosted: return "Frosted (glass)"
        }
    }
}

enum ReadingFont: String, CaseIterable, Identifiable {
    case system, serif, mono
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System"
        case .serif:  return "Serif"
        case .mono:   return "Monospace"
        }
    }
    var design: Font.Design {
        switch self {
        case .system: return .default
        case .serif:  return .serif
        case .mono:   return .monospaced
        }
    }
}

enum FontSmoothing: String, CaseIterable, Identifiable {
    case system, smooth, smoother
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system:   return "Crisp (system)"
        case .smooth:   return "Smooth"
        case .smoother: return "Smoother"
        }
    }
    /// Core Text's stem-darkening level (`AppleFontSmoothing`): nil = leave the
    /// system default; 2/3 = medium/strong darkening — the fuller, softer look
    /// browsers (and so Obsidian/Notion) apply to text by default.
    var appleFontSmoothing: Int? {
        switch self {
        case .system: return nil
        case .smooth: return 2
        case .smoother: return 3
        }
    }
}

/// User-facing appearance settings, persisted to UserDefaults and applied live.
@MainActor
final class AppSettings: ObservableObject {
    @Published var theme: AppTheme { didSet { d.set(theme.rawValue, forKey: kTheme) } }
    @Published var readingFont: ReadingFont { didSet { d.set(readingFont.rawValue, forKey: kFont) } }
    @Published var bodyFontSize: Double { didSet { d.set(bodyFontSize, forKey: kSize) } }
    @Published var readableWidth: Double { didSet { d.set(readableWidth, forKey: kWidth) } }
    /// The big Notion-style page title at the top of a note. Redundant if you're
    /// happy reading the name in the tab — but it's also the rename-in-place
    /// affordance, so it's a toggle (like Obsidian's "Show inline title"), not gone.
    @Published var showInlineTitle: Bool { didSet { d.set(showInlineTitle, forKey: kInlineTitle) } }
    /// Core Text reads `AppleFontSmoothing` from the app's defaults domain at
    /// launch, so changes take effect on next launch (the settings row says so).
    @Published var fontSmoothing: FontSmoothing {
        didSet {
            d.set(fontSmoothing.rawValue, forKey: kSmoothing)
            if let level = fontSmoothing.appleFontSmoothing {
                d.set(level, forKey: "AppleFontSmoothing")
            } else {
                d.removeObject(forKey: "AppleFontSmoothing")
            }
        }
    }

    private let d = UserDefaults.standard
    private let kTheme = "folio.theme", kFont = "folio.readingFont"
    private let kSize = "folio.bodyFontSize", kWidth = "folio.readableWidth"
    private let kInlineTitle = "folio.showInlineTitle"
    private let kSmoothing = "folio.fontSmoothing"

    init() {
        theme = AppTheme(rawValue: d.string(forKey: kTheme) ?? "") ?? .system
        readingFont = ReadingFont(rawValue: d.string(forKey: kFont) ?? "") ?? .system
        bodyFontSize = d.object(forKey: kSize) as? Double ?? 17
        readableWidth = d.object(forKey: kWidth) as? Double ?? 720
        showInlineTitle = d.object(forKey: kInlineTitle) as? Bool ?? true
        fontSmoothing = FontSmoothing(rawValue: d.string(forKey: kSmoothing) ?? "") ?? .system
    }

    var colorScheme: ColorScheme? {
        switch theme {
        case .system, .frosted: return nil    // frosted glass adapts to light/dark
        case .light, .paper:    return .light
        case .dark:             return .dark
        }
    }

    /// Frosted theme: a translucent vibrancy sidebar over a see-through window.
    var usesVibrantSidebar: Bool { theme == .frosted }
    var windowIsTranslucent: Bool { theme == .frosted }
    var paneBackground: Color? { theme == .paper ? Color(platform: Self.paper) : nil }
    var nsPaneBackground: PlatformColor { theme == .paper ? Self.paper : .pTextBackground }
    /// Top-bar (title-bar) tint; falls back to the standard window chrome color.
    var topBarBackground: Color { theme == .paper ? Color(platform: Self.paper) : Color(platform: .pWindowBackground) }
    var nsWindowBackground: PlatformColor? { theme == .paper ? Self.paper : nil }
    /// Sidebar tint — slightly darker than the page for separation. nil = native sidebar material.
    var sidebarBackground: Color? { theme == .paper ? Color(platform: Self.paperSidebar) : nil }
    /// Background for floating surfaces (palettes, outline, backlinks): theme tint or material.
    var surfaceStyle: AnyShapeStyle {
        if let paper = paneBackground { return AnyShapeStyle(paper) }
        return AnyShapeStyle(.regularMaterial)
    }

    /// Tint for selection highlights across lists/palettes (sidebar, command palette,
    /// quick switcher, tags). Paper uses a warm sepia so selections match the cream
    /// instead of a system-blue pop; other themes use the system accent.
    var selectionTint: Color { theme == .paper ? Color(platform: Self.paperSelection) : .accentColor }
    /// Background fill for a selected row (the tint at a theme-tuned opacity).
    var selectionFill: Color {
        theme == .paper ? Color(platform: Self.paperSelection).opacity(0.28) : Color.accentColor.opacity(0.20)
    }

    private static let paper = PlatformColor(red: 0.98, green: 0.96, blue: 0.90, alpha: 1)
    private static let paperSidebar = PlatformColor(red: 0.96, green: 0.93, blue: 0.84, alpha: 1)
    private static let paperSelection = PlatformColor(red: 0.55, green: 0.40, blue: 0.20, alpha: 1)
}
