import SwiftUI
import UIKit

// MARK: - Colour

/// Colours are declared in code as dynamic `UIColor`s rather than in an asset
/// catalog. An `.xcassets` bundle is one more generated-project moving part that
/// can only be verified by a full CI round trip; a dynamic provider cannot fail
/// to resolve and reacts to light/dark instantly.
enum Palette {

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(rgb: dark)
                : UIColor(rgb: light)
        })
    }

    // Surfaces
    static let background = dynamic(light: 0xF5F4FA, dark: 0x0B0A11)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x17161F)
    static let surfaceRaised = dynamic(light: 0xFFFFFF, dark: 0x21202C)
    static let surfaceSunken = dynamic(light: 0xECEAF4, dark: 0x121118)

    // Text
    static let textPrimary = dynamic(light: 0x14121C, dark: 0xF5F4F9)
    static let textSecondary = dynamic(light: 0x676480, dark: 0x9B98AC)
    static let textTertiary = dynamic(light: 0x8F8CA3, dark: 0x6E6B7F)

    // Lines
    static let separator = dynamic(light: 0xE4E1EE, dark: 0x2B2937)

    // Semantics. Every use is paired with an icon or text — colour is never the
    // only thing carrying the meaning.
    static let success = dynamic(light: 0x14855A, dark: 0x34D399)
    static let danger = dynamic(light: 0xC7374A, dark: 0xFB7185)
    static let warning = dynamic(light: 0xB45309, dark: 0xFBBF24)
    static let accent = dynamic(light: 0x4F46E5, dark: 0x818CF8)

    static let successSoft = dynamic(light: 0xE3F5EC, dark: 0x14312A)
    static let dangerSoft = dynamic(light: 0xFCE9EC, dark: 0x36181F)
    static let warningSoft = dynamic(light: 0xFDF2E0, dark: 0x342612)
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Book accents

extension BookTheme {
    /// Start/end colours of the book's signature gradient.
    ///
    /// The light-mode pair is deliberately deep: white text and glyphs sit on
    /// these gradients, and the lighter mid-tones that look nice on a dark
    /// background fail contrast on a white one.
    var gradientColors: [Color] {
        switch self {
        case .indigo:
            return [
                Palette.dynamic(light: 0x4F46E5, dark: 0x6366F1),
                Palette.dynamic(light: 0x7C3AED, dark: 0xA855F7),
            ]
        case .teal:
            return [
                Palette.dynamic(light: 0x0F766E, dark: 0x14B8A6),
                Palette.dynamic(light: 0x0E7490, dark: 0x22D3EE),
            ]
        case .amber:
            return [
                Palette.dynamic(light: 0xB45309, dark: 0xF59E0B),
                Palette.dynamic(light: 0xC2410C, dark: 0xFB923C),
            ]
        case .rose:
            return [
                Palette.dynamic(light: 0xBE123C, dark: 0xF43F5E),
                Palette.dynamic(light: 0xA21CAF, dark: 0xE879F9),
            ]
        }
    }

    var gradient: LinearGradient {
        LinearGradient(
            colors: gradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Flat colour for small text and icons, where the gradient would hurt
    /// legibility.
    var solid: Color { gradientColors[0] }

    /// Very low-opacity wash for card backgrounds.
    var wash: Color { gradientColors[0].opacity(0.12) }
}

// MARK: - Typography

/// All text styles are built from `Font.system(_ textStyle:design:)`, which
/// means every one of them scales with Dynamic Type automatically. Fixed point
/// sizes are avoided on purpose — they are the single most common reason an
/// otherwise well-built iOS app is unusable at large accessibility sizes.
enum AppFont {
    /// The word under test. Serif, because it reads as "dictionary" and gives
    /// the practice screen its one moment of personality.
    static let word = Font.system(.largeTitle, design: .serif).weight(.bold)
    static let screenTitle = Font.system(.largeTitle, design: .rounded).weight(.bold)
    static let title = Font.system(.title2, design: .rounded).weight(.bold)
    static let cardTitle = Font.system(.headline, design: .rounded)
    static let sectionHeader = Font.system(.subheadline, design: .rounded).weight(.semibold)
    static let body = Font.system(.body)
    static let definition = Font.system(.title3, design: .serif)
    static let caption = Font.system(.caption, design: .rounded).weight(.medium)
    static let metricValue = Font.system(.title, design: .rounded).weight(.bold).monospacedDigit()
    static let metricValueSmall = Font.system(.title3, design: .rounded).weight(.bold).monospacedDigit()
    static let badge = Font.system(.caption2, design: .rounded).weight(.bold)
}

// MARK: - Metrics

enum Metrics {
    static let cardRadius: CGFloat = 22
    static let controlRadius: CGFloat = 16
    static let chipRadius: CGFloat = 10

    static let screenPadding: CGFloat = 20
    static let cardPadding: CGFloat = 18
    static let stackSpacing: CGFloat = 16
    static let tightSpacing: CGFloat = 8

    /// Apple's minimum comfortable hit target.
    static let minimumTapTarget: CGFloat = 44
}

// MARK: - Shared modifiers

private struct CardModifier: ViewModifier {
    var padding: CGFloat
    var background: Color

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(Palette.separator, lineWidth: 1)
            )
    }
}

extension View {
    func card(
        padding: CGFloat = Metrics.cardPadding,
        background: Color = Palette.surface
    ) -> some View {
        modifier(CardModifier(padding: padding, background: background))
    }

    /// Standard screen background, applied behind scrollable content.
    func screenBackground() -> some View {
        background(Palette.background.ignoresSafeArea())
    }
}
