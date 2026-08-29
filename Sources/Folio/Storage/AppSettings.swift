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

/// How a single newline inside a paragraph is treated.
enum LineBreakMode: String, CaseIterable, Identifiable {
    /// Decide per paragraph. Text wrapped at a column reflows; deliberate short
    /// breaks are kept. Right far more often than either fixed choice, because
    /// this is a property of the document, not of the reader.
    case auto
    /// Obsidian's behavior: every newline is a line break.
    case preserve
    /// CommonMark/GitHub: lines join with a space.
    case reflow

    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto:     return "Auto"
        case .preserve: return "Preserve"
        case .reflow:   return "Reflow"
        }
    }
    var help: String {
        switch self {
        case .auto:     return "Reflow hard-wrapped paragraphs, keep deliberate breaks"
        case .preserve: return "Every line break is a line break (Obsidian)"
        case .reflow:   return "Lines join into a paragraph (CommonMark)"
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
    @Published var lineBreaks: LineBreakMode { didSet { d.set(lineBreaks.rawValue, forKey: kLineBreakMode) } }
    /// Let the note fill the pane instead of sitting in a measured column. A wide
    /// window trades reading measure for less scrolling — worth having as a choice
    /// rather than a fixed answer.
    @Published var fullWidth: Bool { didSet { d.set(fullWidth, forKey: kFullWidth) } }

    /// Width the note should occupy, or `.infinity` for full width — every
    /// consumer clamps this against its own bounds, so "unbounded" reads as "as
    /// wide as there is room for", and the infinity is also how the text views
    /// know to switch to the roomier full-width margin.
    var columnWidth: Double { fullWidth ? .infinity : readableWidth }

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
    private let kLineBreaks = "folio.preserveLineBreaks"      // pre-Auto, migrated below
    private let kLineBreakMode = "folio.lineBreaks"
    private let kFullWidth = "folio.fullWidth"

    init() {
        theme = AppTheme(rawValue: d.string(forKey: kTheme) ?? "") ?? .system
        readingFont = ReadingFont(rawValue: d.string(forKey: kFont) ?? "") ?? .system
        bodyFontSize = d.object(forKey: kSize) as? Double ?? 17
        // ~660pt at 17pt body ≈ 70–75 characters per line — the long-form
        // sweet spot (60–75); the old 720 default ran ~85 and read wide.
        readableWidth = d.object(forKey: kWidth) as? Double ?? 660
        showInlineTitle = d.object(forKey: kInlineTitle) as? Bool ?? true
        // Migration from the old Bool, which defaulted to true. Only `false` is
        // evidence of an actual choice — `true` is indistinguishable from the
        // default, and the key gets written back as a side effect of merely
        // opening Settings, so treating it as intent would pin people to
        // .preserve and Auto would never run for anyone.
        if let mode = d.string(forKey: kLineBreakMode) {
            lineBreaks = LineBreakMode(rawValue: mode) ?? .auto
        } else if d.object(forKey: kLineBreaks) as? Bool == false {
            lineBreaks = .reflow
        } else {
            lineBreaks = .auto
        }
        fullWidth = d.object(forKey: kFullWidth) as? Bool ?? false
        fontSmoothing = FontSmoothing(rawValue: d.string(forKey: kSmoothing) ?? "") ?? .system
    }

    // ⌘= / ⌘- / ⌘0 (browser/reader convention), mirrored in the View menu and
    // command palette. Bounds match the settings slider.
    func biggerText()  { bodyFontSize = min(24, bodyFontSize + 1) }
    func smallerText() { bodyFontSize = max(13, bodyFontSize - 1) }
    func resetTextSize() { bodyFontSize = 17 }

    var colorScheme: ColorScheme? {
        switch theme {
        // Frosted glass and Paper both have a light and a dark side, so they
        // follow the system rather than pinning an appearance.
        case .system, .frosted, .paper: return nil
        case .light:                    return .light
        case .dark:                     return .dark
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
        theme == .paper ? AnyShapeStyle(Color(platform: Self.paperSurface))
                        : AnyShapeStyle(.regularMaterial)
    }

    /// Tint for selection highlights across lists/palettes (sidebar, command palette,
    /// quick switcher, tags). Paper uses a warm tint so selections match the ground
    /// instead of a system-blue pop; other themes use the system accent.
    var selectionTint: Color { theme == .paper ? Color(platform: Self.paperSelection) : .accentColor }
    /// Background fill for a selected row, and the wash behind selected text —
    /// one color for both, so a selected row and a run of selected text can't drift.
    var selectionFill: Color {
        theme == .paper ? Color(platform: Self.paperSelectionFill) : Color.accentColor.opacity(0.20)
    }
    /// Body and dimmed text. Every theme but Paper's dark side resolves to the
    /// system label colors, so this is a no-op everywhere else.
    var nsTextColor: PlatformColor { theme == .paper ? Self.paperText : .pLabel }
    var nsSecondaryTextColor: PlatformColor {
        theme == .paper ? Self.paperSecondaryText : .pSecondaryLabel
    }
    /// The caret, at full tint strength — the system's is derived from the accent
    /// color, which is the same blue the selection used to be. nil = system.
    var nsCaretColor: PlatformColor? { theme == .paper ? Self.paperSelection : nil }
    /// Selecting text inside a note, in the same tint the sidebar uses — the
    /// system blue read as a foreign object on the cream. nil = system selection
    /// color, which already matches every other theme's chrome.
    var nsSelectionHighlight: PlatformColor? {
        theme == .paper ? Self.paperSelectionFill : nil
    }

    // MARK: Paper palette
    //
    // One hue (~91° in OKLCh) at two lightnesses. The dark side is built fresh
    // rather than inverted: inverting the cream lands on a navy, because warmth
    // doesn't survive the flip.
    //
    // Counter-intuitively the dark side needs MORE absolute chroma than the light
    // one, not less — the eye loses chroma sensitivity as luminance falls, so the
    // first attempt at half the light side's chroma (C 0.010 vs 0.021) read as
    // plain charcoal on screen. These sit near C 0.030.

    private static let paper = PlatformColor.dynamic(
        light: rgb(250, 245, 230),      // cream
        dark:  rgb(40, 34, 17))
    /// Chrome sits *under* the page in both modes — that relationship, not the
    /// absolute lightness, is what makes the page read as a page on a desk. The
    /// dark step is twice the light one (OKLab ΔL 0.048 vs 0.024): the same
    /// separation costs more lightness when there is less of it to spend.
    private static let paperSidebar = PlatformColor.dynamic(
        light: rgb(245, 237, 214),
        dark:  rgb(28, 23, 8))
    /// Floating palettes and floaters. On the light side they can reuse the page
    /// (it is the lightest surface there is); on the dark side they have to lift
    /// off it, or a floater dissolves into the page behind it.
    private static let paperSurface = PlatformColor.dynamic(
        light: rgb(250, 245, 230),
        dark:  rgb(52, 45, 25))
    /// Body and dimmed text. The type carries most of a warm theme's temperature
    /// — it is the largest high-contrast area after the ground — so leaving it at
    /// system white is what made the first dark Paper read as merely tinted.
    /// The light side stays on the system labels, which track Increase Contrast.
    private static let paperText = PlatformColor.dynamic(
        light: .pLabel,
        dark:  rgb(229, 223, 207))      // 11.9:1 on the page
    private static let paperSecondaryText = PlatformColor.dynamic(
        light: .pSecondaryLabel,
        dark:  rgb(163, 158, 145))      // 5.9:1 on the page
    /// Selection tint at full strength (selected labels, match highlighting).
    private static let paperSelection = PlatformColor.dynamic(
        light: rgb(140, 102, 51),       // sepia
        dark:  rgb(224, 188, 122))      // lifted amber, same OKLCh chroma
    /// The same tint as a wash. Alpha is baked in per side rather than applied at
    /// the call site: a light ground takes a selection tinted *down* toward the
    /// hue and a dark ground one tinted *up*, and no single opacity serves both.
    ///
    /// The dark alpha is a deliberate compromise. Since the wash only sets a
    /// background and leaves each run's own color alone, anything light enough to
    /// see against the page also eats contrast from the light foregrounds sitting
    /// on it — a search over the warm hues found no colour that satisfies both.
    /// This is why AppKit's own dark selection overrides the foreground instead.
    /// 0.22 keeps body text (nearly all selected content) at 7.2:1 and the wash at
    /// 1.66:1 against the page — more visible than the light side's 1.44:1, to
    /// offset how much harder lightness steps are to see down here. Links are the
    /// one weak case at 2.6:1; at the 0.38 this started as they were 1.75:1.
    private static let paperSelectionFill = PlatformColor.dynamic(
        light: rgb(140, 102, 51, 0.28),
        dark:  rgb(224, 188, 122, 0.22))

    private static func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> PlatformColor {
        PlatformColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a)
    }
}
