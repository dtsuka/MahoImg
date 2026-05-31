import Foundation

struct SettingsStorage {
    let load: () -> ConversionSettings
    let save: (ConversionSettings) -> Void

    static func ephemeral(initialSettings: ConversionSettings = ConversionSettings()) -> SettingsStorage {
        SettingsStorage(
            load: { initialSettings },
            save: { _ in }
        )
    }
}

enum SettingsStore {
    private static let key = "MahoImg.ConversionSettings"

    static func load() -> ConversionSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(ConversionSettings.self, from: data) else {
            return ConversionSettings()
        }
        return settings
    }

    static func save(_ settings: ConversionSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
