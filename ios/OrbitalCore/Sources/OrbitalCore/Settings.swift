import Foundation

/// Almacén de pares clave–valor para ajustes y cachés pequeñas (en la app, `UserDefaults`).
public protocol KeyValueStore: Sendable {
    func data(_ key: String) -> Data?
    func set(_ key: String, data: Data?)
}

public final class InMemoryKeyValueStore: KeyValueStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    public init() {}
    public func data(_ key: String) -> Data? { lock.withLock { values[key] } }
    public func set(_ key: String, data: Data?) { lock.withLock { values[key] = data } }
}

public final class UserDefaultsKeyValueStore: KeyValueStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let prefix: String
    public init(defaults: UserDefaults = .standard, prefix: String = "orbital.") { self.defaults = defaults; self.prefix = prefix }
    public func data(_ key: String) -> Data? { defaults.data(forKey: prefix + key) }
    public func set(_ key: String, data: Data?) { defaults.set(data, forKey: prefix + key) }
}

/// Lo que eliges en Ajustes. El idioma de la app, el del audio y el de los subtítulos son tres cosas distintas.
public struct AppSettings: Codable, Equatable, Sendable {
    public var uiLanguage = "es"               // idioma de la app y de las fichas: «es» | «en»
    public var audio = "es"                    // idioma de audio preferido de las fuentes
    public var subtitles = "es"                // idioma de subtítulos («» = sin subtítulos)
    public var onlyForcedSubtitles = false
    public var quality = "1080p"               // calidad al ver: «4K», «1080p», «720p»
    public var cellularQuality = "1080p"       // calidad máxima con datos móviles
    public var wifiOnlyDownloads = true
    public var autoNextDownload = true         // reponer el siguiente episodio al terminar de bajar uno
    public var deleteWhenWatched = false
    public var warnCellularOverGB = 5.0
    public var region = "MX"                   // para «lo más popular en Netflix» (TMDB)
    public var preferInfuse = false            // reproducir en Infuse en vez del reproductor propio
    public var traktClientID = ""            // el identificador no es secreto; el secreto de la aplicación va en el Keychain
    public var subtitleSize = "medium"         // «small» | «medium» | «large»: el tamaño de la letra de los subtítulos
    public var orbitalAddress = ""             // tu Orbital por el túnel («orbital.midominio.com»); el token va en el Keychain
    public var appearance = "system"           // «system» | «light» | «dark»: el modo de la app (por omisión, el del iPhone)
    public var homeDeck = "coverflow"          // el carrusel de Inicio: «coverflow» | «fan» (abanico)
    public var homeTime = "pill"               // cuánto falta en la tarjeta: «pill» | «edge» | «fill» | «arc»
    public var avatar = "planet"               // tu avatar (Assets › Avatars)

    public init() {}

    /// Tolerante: un ajuste nuevo (o uno que falte en lo guardado antes) toma su valor por omisión; no se pierde todo.
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: Keys.self)
        uiLanguage = try c.decodeIfPresent(String.self, forKey: .uiLanguage) ?? uiLanguage
        audio = try c.decodeIfPresent(String.self, forKey: .audio) ?? audio
        subtitles = try c.decodeIfPresent(String.self, forKey: .subtitles) ?? subtitles
        onlyForcedSubtitles = try c.decodeIfPresent(Bool.self, forKey: .onlyForcedSubtitles) ?? onlyForcedSubtitles
        quality = try c.decodeIfPresent(String.self, forKey: .quality) ?? quality
        cellularQuality = try c.decodeIfPresent(String.self, forKey: .cellularQuality) ?? cellularQuality
        wifiOnlyDownloads = try c.decodeIfPresent(Bool.self, forKey: .wifiOnlyDownloads) ?? wifiOnlyDownloads
        autoNextDownload = try c.decodeIfPresent(Bool.self, forKey: .autoNextDownload) ?? autoNextDownload
        deleteWhenWatched = try c.decodeIfPresent(Bool.self, forKey: .deleteWhenWatched) ?? deleteWhenWatched
        warnCellularOverGB = try c.decodeIfPresent(Double.self, forKey: .warnCellularOverGB) ?? warnCellularOverGB
        region = try c.decodeIfPresent(String.self, forKey: .region) ?? region
        preferInfuse = try c.decodeIfPresent(Bool.self, forKey: .preferInfuse) ?? preferInfuse
        traktClientID = try c.decodeIfPresent(String.self, forKey: .traktClientID) ?? traktClientID
        subtitleSize = try c.decodeIfPresent(String.self, forKey: .subtitleSize) ?? subtitleSize
        orbitalAddress = try c.decodeIfPresent(String.self, forKey: .orbitalAddress) ?? orbitalAddress
        appearance = try c.decodeIfPresent(String.self, forKey: .appearance) ?? appearance
        homeDeck = try c.decodeIfPresent(String.self, forKey: .homeDeck) ?? homeDeck
        homeTime = try c.decodeIfPresent(String.self, forKey: .homeTime) ?? homeTime
        avatar = try c.decodeIfPresent(String.self, forKey: .avatar) ?? avatar
    }

    enum Keys: String, CodingKey {
        case uiLanguage, audio, subtitles, onlyForcedSubtitles, quality, cellularQuality, wifiOnlyDownloads, autoNextDownload
        case deleteWhenWatched, warnCellularOverGB, region, preferInfuse, traktClientID, subtitleSize, orbitalAddress, appearance
        case homeDeck, homeTime, avatar
    }
    public var traktEnabled: Bool { !traktClientID.isEmpty }

    /// Alto de la letra de los subtítulos como fracción del alto del video (lo que usan los reproductores de TV).
    public var subtitleHeightFraction: Double { ["small": 0.042, "large": 0.068][subtitleSize] ?? 0.054 }

    /// Preferencias de fuentes para ver (en datos móviles se limita la calidad).
    public func preferences(onCellular: Bool = false) -> Preferences {
        var q = quality
        if onCellular, let want = ["4K", "1080p", "720p", "480p"].firstIndex(of: cellularQuality), let have = ["4K", "1080p", "720p", "480p"].firstIndex(of: q), have < want { q = cellularQuality }
        return Preferences(audio: audio, quality: q)
    }
}

public final class SettingsStore: @unchecked Sendable {
    static let key = "settings"
    private let kv: KeyValueStore
    private let lock = NSLock()
    private var current: AppSettings

    public init(_ kv: KeyValueStore) {
        self.kv = kv
        current = kv.data(Self.key).flatMap { try? JSONDecoder().decode(AppSettings.self, from: $0) } ?? AppSettings()
    }

    public var value: AppSettings { lock.withLock { current } }

    public func update(_ change: (inout AppSettings) -> Void) {
        lock.withLock {
            change(&current)
            kv.set(Self.key, data: try? JSONEncoder().encode(current))
        }
    }
}

/// Cada serie o película recuerda el audio y los subtítulos que elegiste viéndola (como en Orbital).
public final class TitlePreferences: @unchecked Sendable {
    struct Saved: Codable { var audio: String?; var subtitles: String? }
    static let key = "title-prefs"
    private let kv: KeyValueStore
    private let lock = NSLock()
    private var all: [String: Saved]

    public init(_ kv: KeyValueStore) {
        self.kv = kv
        all = kv.data(Self.key).flatMap { try? JSONDecoder().decode([String: Saved].self, from: $0) } ?? [:]
    }

    /// Idioma de audio y subtítulos para un título: el que elegiste viéndolo o, si nunca cambiaste, el de Ajustes.
    public func languages(for metaID: String, settings: AppSettings, onCellular: Bool = false) -> (prefs: Preferences, subtitles: String) {
        let saved = lock.withLock { all[metaID] }
        var prefs = settings.preferences(onCellular: onCellular)
        if let audio = saved?.audio, !audio.isEmpty { prefs.audio = audio }
        return (prefs, saved?.subtitles ?? settings.subtitles)
    }

    /// Cambiaste el audio o los subtítulos en el reproductor: ese título lo recuerda. `code` es el de la pista.
    public func remember(metaID: String, audioTrack: String? = nil, subtitleTrack: String? = nil) {
        lock.withLock {
            var saved = all[metaID] ?? Saved()
            if let audioTrack, let lang = PlaybackRules.languageCode(audioTrack), !lang.isEmpty { saved.audio = lang }
            if let subtitleTrack, let lang = PlaybackRules.languageCode(subtitleTrack) { saved.subtitles = lang }
            all[metaID] = saved
            kv.set(Self.key, data: try? JSONEncoder().encode(all))
        }
    }
}
