import SwiftUI
import AppKit

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark, paper
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        case .paper:  return "Paper (warm)"
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

/// User-facing appearance settings, persisted to UserDefaults and applied live.
@MainActor
final class AppSettings: ObservableObject {
    @Published var theme: AppTheme { didSet { d.set(theme.rawValue, forKey: kTheme) } }
    @Published var readingFont: ReadingFont { didSet { d.set(readingFont.rawValue, forKey: kFont) } }
    @Published var bodyFontSize: Double { didSet { d.set(bodyFontSize, forKey: kSize) } }
    @Published var readableWidth: Double { didSet { d.set(readableWidth, forKey: kWidth) } }

    private let d = UserDefaults.standard
    private let kTheme = "slate.theme", kFont = "slate.readingFont"
    private let kSize = "slate.bodyFontSize", kWidth = "slate.readableWidth"

    init() {
        theme = AppTheme(rawValue: d.string(forKey: kTheme) ?? "") ?? .system
        readingFont = ReadingFont(rawValue: d.string(forKey: kFont) ?? "") ?? .system
        bodyFontSize = d.object(forKey: kSize) as? Double ?? 17
        readableWidth = d.object(forKey: kWidth) as? Double ?? 720
    }

    var colorScheme: ColorScheme? {
        switch theme {
        case .system:         return nil
        case .light, .paper:  return .light
        case .dark:           return .dark
        }
    }
    var paneBackground: Color? { theme == .paper ? Color(nsColor: Self.paper) : nil }
    var nsPaneBackground: NSColor { theme == .paper ? Self.paper : .textBackgroundColor }
    /// Top-bar (title-bar) tint; falls back to the standard window chrome color.
    var topBarBackground: Color { theme == .paper ? Color(nsColor: Self.paper) : Color(nsColor: .windowBackgroundColor) }
    var nsWindowBackground: NSColor? { theme == .paper ? Self.paper : nil }
    /// Sidebar tint — slightly darker than the page for separation. nil = native sidebar material.
    var sidebarBackground: Color? { theme == .paper ? Color(nsColor: Self.paperSidebar) : nil }
    /// Background for floating surfaces (palettes, outline, backlinks): theme tint or material.
    var surfaceStyle: AnyShapeStyle {
        if let paper = paneBackground { return AnyShapeStyle(paper) }
        return AnyShapeStyle(.regularMaterial)
    }

    private static let paper = NSColor(red: 0.98, green: 0.96, blue: 0.90, alpha: 1)
    private static let paperSidebar = NSColor(red: 0.96, green: 0.93, blue: 0.84, alpha: 1)
}
