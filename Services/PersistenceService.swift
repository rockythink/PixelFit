import Foundation

struct PersistentSnapshot: Codable {
    var language: AppLanguage
    var presets: [DisplayPreset]
    var showsDockIcon: Bool
    var mediaKeysEnabled: Bool
    /// Per-display brightness mode and software level, keyed by "vendor-product-serial".
    var brightness: [String: DisplayBrightnessSetting]
    /// Legacy (one build): software-dimmed displays with their level. Read for migration, never written.
    var softwareDimming: [String: Double]?

    init(language: AppLanguage = .system, presets: [DisplayPreset] = [], showsDockIcon: Bool = true, mediaKeysEnabled: Bool = true,
         brightness: [String: DisplayBrightnessSetting] = [:]) {
        self.language = language
        self.presets = presets
        self.showsDockIcon = showsDockIcon
        self.mediaKeysEnabled = mediaKeysEnabled
        self.brightness = brightness
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
        presets = try container.decodeIfPresent([DisplayPreset].self, forKey: .presets) ?? []
        showsDockIcon = try container.decodeIfPresent(Bool.self, forKey: .showsDockIcon) ?? true
        mediaKeysEnabled = try container.decodeIfPresent(Bool.self, forKey: .mediaKeysEnabled) ?? true
        brightness = try container.decodeIfPresent([String: DisplayBrightnessSetting].self, forKey: .brightness) ?? [:]
        if let legacy = try container.decodeIfPresent([String: Double].self, forKey: .softwareDimming) {
            for (key, level) in legacy where brightness[key] == nil {
                brightness[key] = DisplayBrightnessSetting(mode: .software, softwareLevel: level)
            }
        }
    }
}

struct PersistenceService {
    private var fileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appending(path: "HiDPIBuddy/state.json")
    }

    func load() -> PersistentSnapshot {
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(PersistentSnapshot.self, from: data)
        } catch {
            return PersistentSnapshot()
        }
    }

    func save(_ snapshot: PersistentSnapshot) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder.pretty.encode(snapshot)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            NSLog("Failed to save PixelFit state: \(error.localizedDescription)")
        }
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
