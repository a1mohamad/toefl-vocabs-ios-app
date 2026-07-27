import Foundation

/// User preferences, persisted to `UserDefaults` as a single encoded blob.
///
/// One blob rather than a key per field so adding a setting never needs a
/// migration — `AppSettings` decodes field-by-field with defaults.
@MainActor
final class SettingsStore: ObservableObject {

    @Published var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            persist()
        }
    }

    private let defaults: UserDefaults
    private let storageKey: String

    init(defaults: UserDefaults = .standard, storageKey: String = "settings.v1") {
        self.defaults = defaults
        self.storageKey = storageKey

        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = AppSettings()
        }
    }

    /// Resolved copy of the string table for the currently selected language.
    var strings: Strings { Strings(language: settings.language) }

    func resetToDefaults() {
        settings = AppSettings()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
