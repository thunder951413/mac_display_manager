import Foundation

struct SavedDisplaySettings: Codable, Equatable {
    var modeWidth: Int?
    var modeHeight: Int?
    var refreshRate: Double?
    var brightness: Double = 1
    var contrast: Double = 1
    var warmth: Double = 0
}

final class DisplaySettingsStore {
    static let shared = DisplaySettingsStore()
    private let defaults = UserDefaults.standard
    private let prefix = "displayProfile."

    func savedSettings(for key: String) -> SavedDisplaySettings? {
        guard let data = defaults.data(forKey: prefix + key) else { return nil }
        return try? JSONDecoder().decode(SavedDisplaySettings.self, from: data)
    }

    func settings(for key: String) -> SavedDisplaySettings {
        savedSettings(for: key) ?? SavedDisplaySettings()
    }

    func save(_ settings: SavedDisplaySettings, for key: String) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: prefix + key)
    }
}
