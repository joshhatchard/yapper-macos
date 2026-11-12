import Foundation
import Testing

@testable import Yapper

@MainActor
@Suite("UserDefaultsPreferencesStore")
struct UserDefaultsPreferencesStoreTests {
    let defaults = InMemoryDefaults()

    @Test("nothing saved loads nil")
    func emptyLoadsNil() {
        #expect(UserDefaultsPreferencesStore(defaults: defaults).load() == nil)
    }

    @Test("saved preferences load back")
    func roundTrip() {
        let preferences = AppPreferences(localeIdentifier: "en_AU")

        UserDefaultsPreferencesStore(defaults: defaults).save(preferences)

        #expect(UserDefaultsPreferencesStore(defaults: defaults).load() == preferences)
    }

    @Test("the transcript mode is saved and loads back")
    func modeRoundTrip() {
        let preferences = AppPreferences(localeIdentifier: "en_AU", transcriptMode: .notes)

        UserDefaultsPreferencesStore(defaults: defaults).save(preferences)

        #expect(UserDefaultsPreferencesStore(defaults: defaults).load()?.transcriptMode == .notes)
    }

    @Test("preferences saved before modes existed load in Default mode")
    func missingModeIsDefault() {
        defaults.set(Data(#"{"localeIdentifier":"en_GB"}"#.utf8), forKey: UserDefaultsPreferencesStore.key)

        #expect(UserDefaultsPreferencesStore(defaults: defaults).load()?.transcriptMode == .standard)
    }

    @Test("an unknown stored mode falls back to Default instead of losing the locale")
    func unknownModeIsDefault() {
        defaults.set(
            Data(#"{"localeIdentifier":"en_GB","transcriptMode":"poetry"}"#.utf8),
            forKey: UserDefaultsPreferencesStore.key)

        #expect(
            UserDefaultsPreferencesStore(defaults: defaults).load()
                == AppPreferences(localeIdentifier: "en_GB", transcriptMode: .standard))
    }

    @Test("unreadable stored data loads nil instead of crashing")
    func corruptDataLoadsNil() {
        defaults.set(Data("not json".utf8), forKey: UserDefaultsPreferencesStore.key)

        #expect(UserDefaultsPreferencesStore(defaults: defaults).load() == nil)
    }
}

extension UserDefaultsPreferencesStoreTests {
    /// PLAN.md documents this JSON for overriding the locale with `defaults write` (no settings UI yet).
    @Test("loads the JSON format documented for manual overrides")
    func loadsDocumentedOverrideFormat() {
        defaults.set(Data(#"{"localeIdentifier":"en_GB"}"#.utf8), forKey: UserDefaultsPreferencesStore.key)

        #expect(UserDefaultsPreferencesStore(defaults: defaults).load() == AppPreferences(localeIdentifier: "en_GB"))
    }

    @Test("preferences saved with the old Carbon shortcut still load their locale")
    func loadsLegacyShortcutPreferences() {
        let json = #"{"shortcut":{"keyCode":49,"modifiers":6},"localeIdentifier":"en_AU"}"#
        defaults.set(Data(json.utf8), forKey: UserDefaultsPreferencesStore.key)

        #expect(UserDefaultsPreferencesStore(defaults: defaults).load() == AppPreferences(localeIdentifier: "en_AU"))
    }
}

@Suite("AppPreferences")
struct AppPreferencesTests {
    @Test("defaults dictate in the given locale")
    func defaultsUseLocale() {
        #expect(
            AppPreferences.defaults(locale: Locale(identifier: "en_AU")) == AppPreferences(localeIdentifier: "en_AU"))
    }
}

/// `UserDefaults` that never reaches cfprefsd or disk (a real suite leaves a plist in ~/Library/Preferences).
final class InMemoryDefaults: UserDefaults {
    private var values: [String: Any] = [:]

    init() {
        super.init(suiteName: nil)!
    }

    override func object(forKey defaultName: String) -> Any? { values[defaultName] }
    override func data(forKey defaultName: String) -> Data? { values[defaultName] as? Data }
    override func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
    override func removeObject(forKey defaultName: String) { values[defaultName] = nil }
}
