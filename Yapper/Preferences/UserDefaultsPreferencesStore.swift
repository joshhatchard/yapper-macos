import Foundation

@MainActor
final class UserDefaultsPreferencesStore: PreferencesStoring {
    static let key = "preferences"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Returns nil when nothing is stored or the stored data is unreadable (callers fall back to defaults).
    func load() -> AppPreferences? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(AppPreferences.self, from: data)
    }

    func save(_ preferences: AppPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
