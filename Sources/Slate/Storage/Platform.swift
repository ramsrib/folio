import SwiftUI

#if canImport(UIKit)
import UIKit
typealias PlatformColor = UIColor
typealias PlatformFont = UIFont
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformColor = NSColor
typealias PlatformFont = NSFont
typealias PlatformImage = NSImage
#endif

/// Cross-platform aliases for the handful of system colors the shared code uses,
/// so the reader/data layer compiles for both macOS (AppKit) and iOS (UIKit).
extension PlatformColor {
    static var pLabel: PlatformColor {
        #if canImport(UIKit) && !targetEnvironment(macCatalyst)
        return .label
        #else
        return .labelColor
        #endif
    }
    static var pSecondaryLabel: PlatformColor {
        #if canImport(UIKit) && !targetEnvironment(macCatalyst)
        return .secondaryLabel
        #else
        return .secondaryLabelColor
        #endif
    }
    static var pTextBackground: PlatformColor {
        #if canImport(UIKit) && !targetEnvironment(macCatalyst)
        return .systemBackground
        #else
        return .textBackgroundColor
        #endif
    }
    static var pWindowBackground: PlatformColor {
        #if canImport(UIKit) && !targetEnvironment(macCatalyst)
        return .systemGroupedBackground
        #else
        return .windowBackgroundColor
        #endif
    }
}

extension Color {
    /// Build a SwiftUI Color from the platform color type.
    init(platform color: PlatformColor) {
        #if canImport(UIKit) && !targetEnvironment(macCatalyst)
        self.init(uiColor: color)
        #else
        self.init(nsColor: color)
        #endif
    }
}

extension Image {
    /// Build a SwiftUI Image from the platform image type.
    init(platform image: PlatformImage) {
        #if canImport(UIKit) && !targetEnvironment(macCatalyst)
        self.init(uiImage: image)
        #else
        self.init(nsImage: image)
        #endif
    }
}

extension PlatformImage {
    /// Load an image from a file URL (NSImage(contentsOf:) vs UIImage(contentsOfFile:)).
    static func load(contentsOf url: URL) -> PlatformImage? {
        #if canImport(UIKit) && !targetEnvironment(macCatalyst)
        return UIImage(contentsOfFile: url.path)
        #else
        return NSImage(contentsOf: url)
        #endif
    }
}
