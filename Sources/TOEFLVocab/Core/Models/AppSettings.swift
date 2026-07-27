import SwiftUI

// MARK: - Theme

enum AppTheme: String, Codable, CaseIterable, Identifiable, Hashable {
    case system
    case light
    case dark

    var id: String { rawValue }

    /// nil means "follow the device".
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var titleKey: StringKey {
        switch self {
        case .system: return .themeSystem
        case .light: return .themeLight
        case .dark: return .themeDark
        }
    }

    var symbolName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.stars.fill"
        }
    }
}

// MARK: - Pronunciation

/// Accent is chosen by picking a different system voice, so no audio files are
/// bundled and nothing is downloaded — `AVSpeechSynthesizer` already ships with
/// all three of these.
enum SpeechAccent: String, Codable, CaseIterable, Identifiable, Hashable {
    case american
    case british
    case australian

    var id: String { rawValue }

    var localeIdentifier: String {
        switch self {
        case .american: return "en-US"
        case .british: return "en-GB"
        case .australian: return "en-AU"
        }
    }

    /// Two-letter badge shown on the pronunciation control.
    var badge: String {
        switch self {
        case .american: return "US"
        case .british: return "UK"
        case .australian: return "AU"
        }
    }

    var titleKey: StringKey {
        switch self {
        case .american: return .accentAmerican
        case .british: return .accentBritish
        case .australian: return .accentAustralian
        }
    }
}

// MARK: - Extra practice scope

/// How wide the Reports drill casts its net.
enum ExtraPracticeScope: String, Codable, CaseIterable, Identifiable, Hashable {
    case weakest25
    case weakest50
    case everything

    var id: String { rawValue }

    /// nil means no cap — every word in the library.
    var limit: Int? {
        switch self {
        case .weakest25: return 25
        case .weakest50: return 50
        case .everything: return nil
        }
    }

    var titleKey: StringKey {
        switch self {
        case .weakest25: return .scopeWeakest25
        case .weakest50: return .scopeWeakest50
        case .everything: return .scopeEverything
        }
    }
}

// MARK: - Settings

struct AppSettings: Codable, Equatable {
    /// `AVSpeechUtteranceDefaultSpeechRate` is 0.5. Below ~0.3 the synthesiser
    /// starts to sound slurred rather than slow, above ~0.62 it is hard to
    /// follow for a learner, so the slider is clamped to a usable band.
    static let minimumSpeechRate: Double = 0.30
    static let maximumSpeechRate: Double = 0.62
    static let defaultSpeechRate: Double = 0.46

    var theme: AppTheme
    var language: AppLanguage
    var accent: SpeechAccent
    var speechRate: Double
    var autoSpeak: Bool
    var haptics: Bool
    var extraPracticeScope: ExtraPracticeScope

    init(
        theme: AppTheme = .system,
        language: AppLanguage = .system,
        accent: SpeechAccent = .american,
        speechRate: Double = AppSettings.defaultSpeechRate,
        autoSpeak: Bool = false,
        haptics: Bool = true,
        extraPracticeScope: ExtraPracticeScope = .weakest25
    ) {
        self.theme = theme
        self.language = language
        self.accent = accent
        self.speechRate = speechRate.clamped(
            to: AppSettings.minimumSpeechRate...AppSettings.maximumSpeechRate
        )
        self.autoSpeak = autoSpeak
        self.haptics = haptics
        self.extraPracticeScope = extraPracticeScope
    }

    /// Slow / Normal / Fast label for the current slider position.
    var speedLabelKey: StringKey {
        if speechRate < 0.40 { return .speedSlow }
        if speechRate > 0.53 { return .speedFast }
        return .speedNormal
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case theme, language, accent, speechRate, autoSpeak, haptics, extraPracticeScope
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            theme: try container.decodeIfPresent(AppTheme.self, forKey: .theme) ?? .system,
            language: try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system,
            accent: try container.decodeIfPresent(SpeechAccent.self, forKey: .accent) ?? .american,
            speechRate: try container.decodeIfPresent(Double.self, forKey: .speechRate)
                ?? AppSettings.defaultSpeechRate,
            autoSpeak: try container.decodeIfPresent(Bool.self, forKey: .autoSpeak) ?? false,
            haptics: try container.decodeIfPresent(Bool.self, forKey: .haptics) ?? true,
            extraPracticeScope: try container.decodeIfPresent(
                ExtraPracticeScope.self, forKey: .extraPracticeScope
            ) ?? .weakest25
        )
    }
}

// MARK: - Helpers

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
