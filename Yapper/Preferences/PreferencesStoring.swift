@MainActor
protocol PreferencesStoring: AnyObject {
    func load() -> AppPreferences?
    func save(_ preferences: AppPreferences)
}
