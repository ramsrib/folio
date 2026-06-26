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

    private static let paper = NSColor(red: 0.98, green: 0.96, blue: 0.90, alpha: 1)
}
