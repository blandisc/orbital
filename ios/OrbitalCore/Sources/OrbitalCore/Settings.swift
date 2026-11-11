import Foundation

/// Lo que eliges en Ajustes. El idioma de la app, el del audio y el de los subtítulos son tres cosas distintas.
public struct AppSettings: Codable, Equatable, Sendable {
    public var uiLanguage = "es"               // idioma de la app y de las fichas: «es» | «en»
    public var audio = "es"                    // idioma de audio preferido de las fuentes
    public var subtitles = "es"                // idioma de subtítulos («» = sin subtítulos)
    public var onlyForcedSubtitles = false
    /// Audio en español latino (no de España) cuando un video trae los dos.
    public var latinSpanish = false
    /// Español de España (castellano) antes que el latino; con `latinSpanish` en falso y este también, cualquiera.
    public var castilianSpanish = false
    /// «Tus idiomas» (N4-A, Fernando, 4 nov): tu orden entero, el primero es el que quieres («es-419», «original», «en»,
    /// «es-ES»…). Es la única fuente: la puntuación de las versiones, el plan B del reproductor y los «Idiomas primero» de
    /// Torrentio salen de aquí. nil: todavía no se migra (vale `yourLanguages`, lo de antes). Se cambia con `setLanguages`.
    public var languages: [String]?
    public var quality = "1080p"               // calidad al ver: «4K», «1080p», «720p»
    public var cellularQuality = "1080p"       // calidad máxima con datos móviles
    public var wifiOnlyDownloads = true
    public var autoNextDownload = true         // reponer el siguiente episodio al terminar de bajar uno
    public var deleteWhenWatched = false
    public var warnCellularOverGB = 5.0
    /// Tu país para lo popular en plataformas (Top 10 de Netflix y JustWatch) y «dónde verla»: el del iPhone hasta que elijas
    /// otro en Ajustes (antes era México para todos).
    public var region = AppSettings.phoneRegion
    /// Ya hay país: lo elegiste en Ajustes o se trajo una vez de tu Orbital. Conectarla después ya no lo cambia.
    public var regionChosen = false
    /// El país del iPhone (Ajustes › General › Idioma y región), o México si no lo dice.
    public static var phoneRegion: String {
        let code = Locale.current.region?.identifier ?? ""
        return code.count == 2 && code.allSatisfy(\.isLetter) ? code.uppercased() : "MX"
    }
    public var preferInfuse = false            // reproducir en Infuse en vez del reproductor propio
    public var traktClientID = ""            // el identificador no es secreto; el secreto de la aplicación va en el Keychain
    public var subtitleSize = "medium"         // «small» | «medium» | «large» | «xlarge»: el tamaño de la letra de los subtítulos
    public var subtitleBackground = "outline"  // «outline» (contorno) | «box» (caja oscura) | «translucent»
    public var subtitlePosition = "normal"     // «normal» | «raised» (más arriba)
    public var subtitlesOnSkipBack = true      // al regresar 10 s con subtítulos apagados, se ven un momento
    public var forcedForForeignAudio = true    // audio en otro idioma (ni el tuyo ni inglés): los carteles en tu idioma
    public var subtitleSystemStyle = false     // «Usar el estilo del iPhone» (Accesibilidad › Subtítulos): su color, fondo y tamaño
    public var orbitalAddress = ""             // tu Orbital por el túnel («orbital.midominio.com»); el token va en el Keychain
    /// Ajustes › «Usar con tu Orbital»: la app es de una sola pieza y todo lo de la consola (Ver en la TV, el control, la voz,
    /// «Desde la TV») sale solo con esto prendido. Lo guardado de antes con una consola ya emparejada llega prendido.
    public var orbitalEnabled = false
    public var appearance = "system"           // «system» | «light» | «dark»: el modo de la app (por omisión, el del iPhone)
    public var releaseAlerts = false           // avisar cuando un episodio de lo que sigues ya se puede ver («Ya está para ver»)
    public var becauseStyle = "posters"        // «Porque viste» (Para ti): «posters» (mini pósters) | «deck» (mazo de cartas)
    public var avatar = "planet"               // tu avatar (Assets › Avatars)
    public var displayName = ""                // cómo te saluda Inicio («Hola, Fer»); vacío: el de tu Trakt
    public var oneDriveClientID = ""           // el «ID de la aplicación» de Microsoft Entra (no es secreto; la sesión va en el Keychain)
    public var oneDriveFolder = ""             // la carpeta de OneDrive con tus películas y series («Videos/Películas»)
    public var videoZoom = VideoZoom.fit.rawValue   // cómo llena la pantalla el video del reproductor (`VideoZoom`); se recuerda
    public var simpsonsSeasons = Array(5...15)     // de qué temporadas sale «Un Simpson al azar» (por omisión, las clásicas)
    /// «Pedir solo el siguiente episodio» (R8, R9-B): si Real-Debrid aún no tiene el que sigue, se le pide 3 min antes del
    /// final del que ves. Prendido por omisión, igual que la TV (`rd_auto_request`).
    public var autoRequestNextEpisode = true
    /// Buscar subtítulos en internet (OpenSubtitles) cuando el video no trae en tu idioma. Viene con Orbital: ya no es un
    /// complemento de la lista (Fernando, 3 nov 2026).
    public var internetSubtitles = true

    public init() {}

    /// Tolerante: un ajuste nuevo (o uno que falte en lo guardado antes) toma su valor por omisión; no se pierde todo.
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: Keys.self)
        uiLanguage = try c.decodeIfPresent(String.self, forKey: .uiLanguage) ?? uiLanguage
        audio = try c.decodeIfPresent(String.self, forKey: .audio) ?? audio
        subtitles = try c.decodeIfPresent(String.self, forKey: .subtitles) ?? subtitles
        onlyForcedSubtitles = try c.decodeIfPresent(Bool.self, forKey: .onlyForcedSubtitles) ?? onlyForcedSubtitles
        latinSpanish = try c.decodeIfPresent(Bool.self, forKey: .latinSpanish) ?? latinSpanish
        castilianSpanish = try c.decodeIfPresent(Bool.self, forKey: .castilianSpanish) ?? castilianSpanish
        languages = try c.decodeIfPresent([String].self, forKey: .languages)
        quality = try c.decodeIfPresent(String.self, forKey: .quality) ?? quality
        cellularQuality = try c.decodeIfPresent(String.self, forKey: .cellularQuality) ?? cellularQuality
        wifiOnlyDownloads = try c.decodeIfPresent(Bool.self, forKey: .wifiOnlyDownloads) ?? wifiOnlyDownloads
        autoNextDownload = try c.decodeIfPresent(Bool.self, forKey: .autoNextDownload) ?? autoNextDownload
        deleteWhenWatched = try c.decodeIfPresent(Bool.self, forKey: .deleteWhenWatched) ?? deleteWhenWatched
        warnCellularOverGB = try c.decodeIfPresent(Double.self, forKey: .warnCellularOverGB) ?? warnCellularOverGB
        region = try c.decodeIfPresent(String.self, forKey: .region) ?? region
        regionChosen = try c.decodeIfPresent(Bool.self, forKey: .regionChosen) ?? regionChosen
        preferInfuse = try c.decodeIfPresent(Bool.self, forKey: .preferInfuse) ?? preferInfuse
        traktClientID = try c.decodeIfPresent(String.self, forKey: .traktClientID) ?? traktClientID
        subtitleSize = try c.decodeIfPresent(String.self, forKey: .subtitleSize) ?? subtitleSize
        subtitleBackground = try c.decodeIfPresent(String.self, forKey: .subtitleBackground) ?? subtitleBackground
        subtitlePosition = try c.decodeIfPresent(String.self, forKey: .subtitlePosition) ?? subtitlePosition
        subtitlesOnSkipBack = try c.decodeIfPresent(Bool.self, forKey: .subtitlesOnSkipBack) ?? subtitlesOnSkipBack
        forcedForForeignAudio = try c.decodeIfPresent(Bool.self, forKey: .forcedForForeignAudio) ?? forcedForForeignAudio
        subtitleSystemStyle = try c.decodeIfPresent(Bool.self, forKey: .subtitleSystemStyle) ?? subtitleSystemStyle
        orbitalAddress = try c.decodeIfPresent(String.self, forKey: .orbitalAddress) ?? orbitalAddress
        appearance = try c.decodeIfPresent(String.self, forKey: .appearance) ?? appearance
        becauseStyle = try c.decodeIfPresent(String.self, forKey: .becauseStyle) ?? becauseStyle
        releaseAlerts = try c.decodeIfPresent(Bool.self, forKey: .releaseAlerts) ?? releaseAlerts
        avatar = try c.decodeIfPresent(String.self, forKey: .avatar) ?? avatar
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? displayName
        oneDriveClientID = try c.decodeIfPresent(String.self, forKey: .oneDriveClientID) ?? oneDriveClientID
        oneDriveFolder = try c.decodeIfPresent(String.self, forKey: .oneDriveFolder) ?? oneDriveFolder
        videoZoom = try c.decodeIfPresent(String.self, forKey: .videoZoom) ?? videoZoom
        simpsonsSeasons = try c.decodeIfPresent([Int].self, forKey: .simpsonsSeasons) ?? simpsonsSeasons
        autoRequestNextEpisode = try c.decodeIfPresent(Bool.self, forKey: .autoRequestNextEpisode) ?? autoRequestNextEpisode
        internetSubtitles = try c.decodeIfPresent(Bool.self, forKey: .internetSubtitles) ?? internetSubtitles
        orbitalEnabled = try c.decodeIfPresent(Bool.self, forKey: .orbitalEnabled) ?? !orbitalAddress.isEmpty
    }

    enum Keys: String, CodingKey {
        case uiLanguage, audio, subtitles, onlyForcedSubtitles, quality, cellularQuality, wifiOnlyDownloads, autoNextDownload
        case deleteWhenWatched, warnCellularOverGB, region, regionChosen, preferInfuse, traktClientID, subtitleSize, orbitalAddress, appearance
        case avatar, displayName, latinSpanish, castilianSpanish, becauseStyle, releaseAlerts, oneDriveClientID, oneDriveFolder, videoZoom, simpsonsSeasons
        case subtitleBackground, subtitlePosition, subtitlesOnSkipBack, forcedForForeignAudio, subtitleSystemStyle, orbitalEnabled
        case autoRequestNextEpisode, internetSubtitles, languages
    }

    /// Alto de la letra de los subtítulos como fracción del alto del video (lo que usan los reproductores de TV).
    /// Cuatro medidas, como la TV (Pequeño ×0,85 · Normal · Grande ×1,25 · Muy grande ×1,5; Fernando, 4 nov 2026, PT19).
    public var subtitleHeightFraction: Double { ["small": 0.046, "large": 0.068, "xlarge": 0.081][subtitleSize] ?? 0.054 }

    /// Las medidas de la letra de los subtítulos, de chica a grande (los nombres: «Pequeño», «Normal», «Grande», «Muy grande»).
    public static let subtitleSizes = ["small", "medium", "large", "xlarge"]

    /// Preferencias de fuentes para ver (en datos móviles se limita la calidad).
    public func preferences(onCellular: Bool = false) -> Preferences {
        var q = quality
        if onCellular, let want = ["4K", "1080p", "720p", "480p"].firstIndex(of: cellularQuality), let have = ["4K", "1080p", "720p", "480p"].firstIndex(of: q), have < want { q = cellularQuality }
        var prefs = Preferences(audio: audio, quality: q, spanish: spanishVariant)
        prefs.languages = languages
        return prefs
    }

    /// «Tus idiomas» como se ven en Ajustes: lo guardado o, sin migrar, lo de antes (tu audio y, con latino o sin variante
    /// elegida, el orden de Fernando del 3 nov: latino → original → inglés → castellano).
    public var yourLanguages: [String] {
        if let languages, !languages.isEmpty { return languages }
        // Sin variante elegida (lo de fábrica), el orden de Fernando para es-MX: Latino, Idioma original, Inglés, Castellano.
        let first = audio == "es" ? (latinSpanish ? "es-419" : castilianSpanish ? "es-ES" : "es-419") : audio
        return [first] + (first == "es-419" ? Preferences.latinOrder : [])
    }

    /// Cambia «Tus idiomas» y, de ahí, tu audio de siempre: el primero que no es «original» manda (Ajustes no deja subir
    /// «original» hasta arriba: el primero es tu idioma). Una lista vacía o solo con «original» no se guarda.
    public mutating func setLanguages(_ list: [String]) {
        var clean: [String] = []
        for code in list where !code.isEmpty && !clean.contains(code) { clean.append(code) }
        guard let first = clean.first(where: { $0 != "original" }) else { return }
        languages = clean
        audio = first.hasPrefix("es") ? "es" : first
        latinSpanish = first == "es-419"
        castilianSpanish = first == "es-ES"
    }

    /// La variante de español que prefieres: «es-419» (latino), «es-ES» (castellano) o "" (cualquiera).
    /// Sale de «Tus idiomas» (lo que ves en Ajustes), no de una casilla aparte: sin variante marcada, la lista de fábrica pone
    /// latino primero y el reproductor tomaba «cualquiera» (la primera pista en español, casi siempre la de España; Fernando,
    /// 6 nov: «me la puso en castellano y sí había latino»).
    /// Tu español aunque tu audio de siempre sea otro (un título que pusiste en español).
    public static func spanishOf(_ s: AppSettings) -> String {
        s.latinSpanish ? "es-419" : s.castilianSpanish ? "es-ES" : s.yourLanguages.first { $0 == "es-419" || $0 == "es-ES" } ?? ""
    }

    public var spanishVariant: String {
        guard audio == "es" else { return "" }
        if latinSpanish { return "es-419" }
        if castilianSpanish { return "es-ES" }
        return yourLanguages.first { $0 == "es-419" || $0 == "es-ES" } ?? ""
    }
}

/// Cómo se ve el video: dos modos y nada más (Fernando, 3 nov 2026: antes los cuatro de Infuse, «Normal», «Ajuste de aspecto»,
/// «Recortar» y «Estirar»). Pellizcar va de uno a otro (abrir los dedos llena la pantalla, cerrarlos vuelve a la imagen
/// completa) y el botón del «⋯» cambia al otro.
public enum VideoZoom: String, CaseIterable, Sendable {
    case fit    // «Completa»: toda la imagen, lejos de la isla y de las esquinas redondeadas
    case fill   // «Llenar pantalla»: sin franjas negras; puede recortar las orillas

    /// Lo guardado en ajustes. Los modos que ya no existen caen en el más parecido: «Ajuste de aspecto» en «Completa» y
    /// «Estirar» en «Llenar pantalla»; uno desconocido, en «Completa».
    public init(stored: String) {
        switch stored {
        case "fill", "stretch": self = .fill
        default: self = .fit
        }
    }

    /// El otro modo (el botón del «⋯»).
    public var next: VideoZoom { self == .fit ? .fill : .fit }

    /// Pellizcar: abrir los dedos (más de un 20 %) llena la pantalla, cerrarlos (a menos de 80 %) vuelve a la imagen completa.
    /// Entre medio no cambia nada: dos dedos que se mueven un poco (pausar con dos dedos, sujetar el teléfono al girar) no son
    /// un pellizco.
    public static func pinched(magnification: Double) -> VideoZoom? {
        if magnification > 1.2 { return .fill }
        if magnification < 0.8 { return .fit }
        return nil
    }

    /// El nombre que dice el aviso y VoiceOver (la clave de `Localizable.xcstrings`).
    public var title: String { self == .fit ? "Completa" : "Llenar pantalla" }
    /// Qué hace, en una línea (el aviso al cambiar).
    public var explanation: String { self == .fit ? "Ves toda la imagen" : "Sin franjas negras · puede recortar las orillas" }
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

/// Con qué dejaste un video: la huella de la fuente y la pista exacta de audio y de subtítulos (Latinoamérica y no España,
/// los forzados…). `subtitle` nil = no se sabe; con `off`, los apagaste.
public struct ResumeChoice: Codable, Equatable, Sendable {
    public struct Track: Codable, Equatable, Sendable {
        public var off = false
        public var language: String?
        public var title: String?
        /// Subtítulos de un complemento (OpenSubtitles…) que traía la TV: si este archivo no los tiene, se cargan de ahí.
        public var url: String?
        public init(off: Bool = false, language: String? = nil, title: String? = nil, url: String? = nil) {
            self.off = off; self.language = language; self.title = title; self.url = url
        }

        /// Como la manda la TV ({"off", "lang", "title", "url"}); nil si no es una pista.
        public static func parse(_ json: JSON?) -> Track? {
            guard let json, case .object = json else { return nil }
            return Track(off: json["off"]?.bool ?? false, language: json["lang"]?.nonEmptyString, title: json["title"]?.nonEmptyString,
                         url: json["url"]?.nonEmptyString)
        }

        /// Para la TV (`/api/stremio/play`): el mismo formato.
        public var json: JSON {
            .object(["off": .bool(off), "lang": .string(language ?? ""), "title": .string(title ?? ""), "url": .string(url ?? "")])
        }
    }
    public var videoID: String
    public var source: String?
    public var audio: Track?
    public var subtitle: Track?
    /// La «familia» de la versión (`bingeGroup`: mismo grupo, calidad e idioma en cada episodio): con ella el siguiente
    /// episodio sigue en la misma versión, no solo en el mismo idioma.
    public var binge: String?
    /// Cuándo lo viste así (segundos desde 1970): en «Continuar» gana lo último, en este aparato o en otro (vía tu Orbital).
    public var at: Double?
    public init(videoID: String, source: String? = nil, audio: Track? = nil, subtitle: Track? = nil, binge: String? = nil, at: Double? = nil) {
        self.videoID = videoID; self.source = source; self.audio = audio; self.subtitle = subtitle; self.binge = binge; self.at = at
    }

    /// Lo mismo sin la hora (para saber si cambió algo).
    var unstamped: ResumeChoice { var copy = self; copy.at = nil; return copy }
}

/// Cada serie o película recuerda el audio y los subtítulos que elegiste viéndola (como en Orbital).
public final class TitlePreferences: @unchecked Sendable {
    struct Saved: Codable { var audio: String?; var subtitles: String?
        /// El español de ese título («es-419» latino, «es-ES» castellano), si lo elegiste viéndolo: así «los siguientes
        /// episodios, en latino» es cierto aunque en Ajustes no tengas la variante.
        var spanish: String? }
    static let key = "title-prefs"
    private let kv: KeyValueStore
    private let lock = NSLock()
    /// N5-A: lo que se ve bien en este aparato (las pruebas de los escenarios comunes ponen el del escenario).
    public var device: PlaybackDevice {
        get { lock.withLock { storedDevice } }
        set { lock.withLock { storedDevice = newValue } }
    }
    private var storedDevice = PlaybackDevice.apple

    /// Lo que se sincroniza con tu Orbital (el audio, la variante y los subtítulos de cada título valen en los dos lados).
    struct SyncState: Codable {
        /// La última revisión de tu Orbital que se vio (0: nunca se sincronizó: la primera vez solo suma).
        var rev = 0
        var synced = false
        /// La revisión de cada título que conoce el iPhone (la base de lo que manda).
        var revs: [String: Int] = [:]
        /// Lo que se eligió aquí y tu Orbital aún no sabe (sobrevive sin conexión).
        var pending: [String: OrbitalRemote.ChoiceChange] = [:]
        /// Cuántas veces seguidas rechazó la TV el cambio pendiente de cada título, y cuál (otro cambio cuenta desde cero).
        /// Opcional: lo guardado antes no lo trae.
        var refusals: [String: Refused]?
        /// Lo que la TV rechazó `maxRefusals` veces: ya no se reenvía; queda aquí para diagnóstico (y en la bitácora).
        var setAside: [String: OrbitalRemote.ChoiceChange]?
    }
    struct Refused: Codable { var change: OrbitalRemote.ChoiceChange; var count: Int }
    /// Tras cuántos rechazos de la TV un cambio deja de reenviarse (se aparta y queda en la bitácora).
    static let maxRefusals = 3
    static let syncKey = "choices-sync"
    private var sync: SyncState
    private var syncing = false
    /// Algo nuevo para mandar a tu Orbital (la app sincroniza al rato).
    public var onPendingChoice: (@Sendable () -> Void)?
    private var all: [String: Saved]

    static let resumeKey = "resume-choices"
    private var resumes: [String: ResumeChoice]
    /// Lo que se vio aquí y tu Orbital aún no sabe (para «Continuar» en otro aparato).
    static let resumePendingKey = "resume-pending"
    private var resumePending: Set<String>
    /// Habla con tu Orbital: manda lo de aquí y trae lo que recuerda de `want` (nil sin conexión o con una de antes).
    public var exchangeResume: (@Sendable (_ changes: [String: ResumeChoice], _ want: [String]) async -> [String: ResumeChoice]?)?

    /// «Comprobado»: las pistas de audio reales de cada versión que ya viste (por su huella `Source.key`, la misma de la TV).
    static let checkedKey = "checked-audio", checkedLimit = 2000
    private var checked: [String: [AudioLanguage]]

    public init(_ kv: KeyValueStore) {
        self.kv = kv
        all = kv.data(Self.key).flatMap { try? JSONDecoder().decode([String: Saved].self, from: $0) } ?? [:]
        resumes = kv.data(Self.resumeKey).flatMap { try? JSONDecoder().decode([String: ResumeChoice].self, from: $0) } ?? [:]
        resumePending = kv.data(Self.resumePendingKey).flatMap { try? JSONDecoder().decode(Set<String>.self, from: $0) } ?? []
        checked = kv.data(Self.checkedKey).flatMap { try? JSONDecoder().decode([String: [AudioLanguage]].self, from: $0) } ?? [:]
        sync = kv.data(Self.syncKey).flatMap { try? JSONDecoder().decode(SyncState.self, from: $0) } ?? SyncState()
    }

    public static func familyKey(_ family: String) -> String { "family:" + family }

    /// El audio comprobado de una versión, si ya la viste.
    public func checkedAudio(_ key: String) -> [AudioLanguage]? { lock.withLock { checked[key] } }

    /// Se abrió una versión: se anotan sus pistas de audio reales. true si cambió algo (lo ordenado ya no vale).
    @discardableResult public func rememberChecked(key: String, tracks: [MediaTrack]) -> Bool {
        var codes: [String] = []
        for track in tracks where track.kind == .audio {
            if let code = TrackChooser.audioCode(track), !codes.contains(code) { codes.append(code) }
        }
        return rememberChecked(key: key, codes: codes)
    }

    /// Lo mismo con los idiomas ya resueltos («es-419» si el nombre lo decía y la pista solo dice «spa»). Con `family` (el
    /// `bingeGroup`: la misma versión en cada episodio), también para los demás episodios de esa versión (Fernando, 6 nov:
    /// decía un idioma y al abrirla traía más).
    @discardableResult public func rememberChecked(key: String, codes: [String], family: String? = nil) -> Bool {
        if let family, !family.isEmpty { rememberChecked(key: Self.familyKey(family), codes: codes) }
        guard !codes.isEmpty, !key.isEmpty else { return false }
        let value = codes.map { AudioLanguage($0, .checked) }
        return lock.withLock {
            guard checked[key] != value else { return false }
            if checked.count >= Self.checkedLimit, let any = checked.keys.first { checked[any] = nil }
            checked[key] = value
            kv.set(Self.checkedKey, data: try? JSONEncoder().encode(checked))
            return true
        }
    }

    /// Idioma de audio y subtítulos para un título: el que elegiste viéndolo o, si nunca cambiaste, el de Ajustes.
    public func languages(for metaID: String, settings: AppSettings, onCellular: Bool = false) -> (prefs: Preferences, subtitles: String) {
        let saved = lock.withLock { all[metaID] }
        var prefs = settings.preferences(onCellular: onCellular)
        prefs.device = device
        if let audio = saved?.audio, !audio.isEmpty { prefs.audio = audio }
        if prefs.audio == "es", let variant = saved?.spanish, !variant.isEmpty { prefs.spanish = variant }
        // Este título lo pusiste en español aunque tu audio de siempre sea otro: la variante que elegiste en Ajustes vale igual.
        if prefs.audio == "es", prefs.spanish.isEmpty { prefs.spanish = AppSettings.spanishOf(settings) }
        return (prefs, saved?.subtitles ?? settings.subtitles)
    }

    /// «Continuar»: con qué fuente y qué pistas dejaste ese video (la regla de la TV), o nil si es otro video.
    public func resumeChoice(metaID: String, videoID: String) -> ResumeChoice? {
        let saved = lock.withLock { resumes[metaID] }
        return saved?.videoID == videoID ? saved : nil
    }

    /// Las pistas con que dejaste el título (cualquier episodio): para el siguiente se usan las mismas.
    public func lastChoice(metaID: String) -> ResumeChoice? { lock.withLock { resumes[metaID] } }

    /// Con qué lo estás viendo. Lleva la hora (si no trae una) y, si `share`, tu Orbital se entera: «Continuar» en la TV,
    /// el iPad o la Mac sigue igual. La hora se renueva aunque no cambie nada (a lo más una vez por minuto).
    public func remember(metaID: String, choice: ResumeChoice, share: Bool = true, now: Date = Date()) {
        var stamped = choice
        if stamped.at == nil { stamped.at = now.timeIntervalSince1970 }
        let queued: Bool = lock.withLock {
            let old = resumes[metaID]
            guard old?.unstamped != stamped.unstamped || (old?.at ?? 0) < (stamped.at ?? 0) - 50 else { return false }
            resumes[metaID] = stamped
            kv.set(Self.resumeKey, data: try? JSONEncoder().encode(resumes))
            guard share else { return false }
            resumePending.insert(metaID)
            kv.set(Self.resumePendingKey, data: try? JSONEncoder().encode(resumePending))
            return true
        }
        if queued { onPendingChoice?() }
    }

    /// Manda lo pendiente a tu Orbital y trae lo que recuerda de `want`: si allá es más reciente (lo viste después en la TV
    /// u otro aparato), se queda eso. A lo más `timeout` segundos: sin respuesta, se sigue con lo de aquí.
    public func syncResume(want: [String] = [], timeout: Double = 8) async {
        guard let exchange = exchangeResume else { return }
        let sent = lock.withLock { Dictionary(uniqueKeysWithValues: resumePending.compactMap { id in resumes[id].map { (id, $0) } }) }
        guard !sent.isEmpty || !want.isEmpty else { return }
        let reply: [String: ResumeChoice]? = await withTaskGroup(of: [String: ResumeChoice]??.self) { group in
            group.addTask { await exchange(sent, want) }
            group.addTask { try? await Task.sleep(for: .seconds(timeout)); return .some(nil) }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? nil
        }
        guard let reply else { return }
        lock.withLock {
            for (id, choice) in sent where resumes[id] == choice { resumePending.remove(id) }   // lo que cambió mientras, va la próxima
            for (id, theirs) in reply where (theirs.at ?? 0) > (resumes[id]?.at ?? 0) {
                resumes[id] = theirs
                resumePending.remove(id)
            }
            kv.set(Self.resumeKey, data: try? JSONEncoder().encode(resumes))
            kv.set(Self.resumePendingKey, data: try? JSONEncoder().encode(resumePending))
        }
    }

    /// Cambiaste el audio o los subtítulos en el reproductor: ese título lo recuerda. `code` es el de la pista.
    public func remember(metaID: String, audioTrack: String? = nil, subtitleTrack: String? = nil) {
        lock.withLock {
            var saved = all[metaID] ?? Saved()
            if let audioTrack, let lang = PlaybackRules.languageCode(audioTrack), !lang.isEmpty {
                saved.audio = lang
                if audioTrack == "es-419" || audioTrack == "es-ES" { saved.spanish = audioTrack } else if lang != "es" { saved.spanish = nil }
            }
            // Cualquier idioma (antes solo español e inglés: elegir francés no se recordaba). "" = apagados.
            if let subtitleTrack { saved.subtitles = subtitleTrack.isEmpty ? "" : (SubtitleLanguage.code(subtitleTrack) ?? PlaybackRules.languageCode(subtitleTrack) ?? subtitleTrack) }
            let before = all[metaID]
            all[metaID] = saved
            kv.set(Self.key, data: try? JSONEncoder().encode(all))
            queue(metaID, from: before, to: saved)
        }
        onPendingChoice?()
    }

    /// «Lo que recuerda cada título» › Olvidar: vuelve a lo de Ajustes, aquí y en tu Orbital.
    public func forget(metaID: String) {
        lock.withLock {
            guard all[metaID] != nil else { return }
            all[metaID] = nil
            kv.set(Self.key, data: try? JSONEncoder().encode(all))
            var change = sync.pending[metaID] ?? OrbitalRemote.ChoiceChange(base: sync.revs[metaID] ?? 0)
            change.audio = nil; change.spanish = nil; change.subtitles = nil
            change.forget = ["audio", "spanish", "subtitles"]
            sync.pending[metaID] = change
            saveSync()
        }
        onPendingChoice?()
    }

    /// Lo que recuerda cada título (para Ajustes): {id: (audio, variante, subtítulos)}.
    public func remembered() -> [String: (audio: String?, spanish: String?, subtitles: String?)] {
        lock.withLock { all.mapValues { ($0.audio, $0.spanish, $0.subtitles) }.filter { $0.value.audio != nil || $0.value.subtitles != nil } }
    }

    // MARK: sincronizar con tu Orbital

    private func queue(_ metaID: String, from before: Saved?, to saved: Saved) {
        var change = sync.pending[metaID] ?? OrbitalRemote.ChoiceChange(base: sync.revs[metaID] ?? 0)
        if saved.audio != before?.audio, let v = saved.audio { change.audio = v; change.forget.removeAll { $0 == "audio" } }
        if saved.spanish != before?.spanish, let v = saved.spanish { change.spanish = v; change.forget.removeAll { $0 == "spanish" } }
        if saved.subtitles != before?.subtitles, let v = saved.subtitles { change.subtitles = v; change.forget.removeAll { $0 == "subtitles" } }
        guard change != OrbitalRemote.ChoiceChange(base: change.base) else { return }
        sync.pending[metaID] = change
        saveSync()
    }

    private func saveSync() { kv.set(Self.syncKey, data: try? JSONEncoder().encode(sync)) }

    /// Un intento de sincronizar: manda lo pendiente y aplica lo que cambió en la TV. La primera vez solo suma: lo que un
    /// lado tiene y el otro no, pasa; si los dos eligieron distinto para el mismo título, gana la TV. Sin conexión o con
    /// una Orbital de antes, nada se pierde (lo pendiente espera).
    public func syncChoices(with remote: OrbitalRemote) async {
        guard lock.withLock({ syncing ? false : { syncing = true; return true }() }) else { return }   // uno a la vez
        defer { lock.withLock { syncing = false } }
        if !(lock.withLock { sync.synced }) {
            guard let first = try? await remote.syncChoices(since: 0, changes: [:]) else { return }
            lock.withLock {
                for (id, theirs) in first.changed {
                    var mine = all[id] ?? Saved()
                    var missing = OrbitalRemote.ChoiceChange(base: theirs.rev)
                    if let v = theirs.audio { mine.audio = v } else if let v = mine.audio { missing.audio = v }
                    if let v = theirs.spanish { mine.spanish = v } else if let v = mine.spanish { missing.spanish = v }
                    if let v = theirs.subtitles { mine.subtitles = v } else if let v = mine.subtitles { missing.subtitles = v }
                    all[id] = mine
                    sync.revs[id] = theirs.rev
                    if missing != OrbitalRemote.ChoiceChange(base: theirs.rev) { sync.pending[id] = missing }
                }
                for (id, mine) in all where first.changed[id] == nil && (mine.audio != nil || mine.subtitles != nil) {
                    sync.pending[id] = OrbitalRemote.ChoiceChange(audio: mine.audio, spanish: mine.spanish, subtitles: mine.subtitles, base: 0)
                }
                sync.rev = first.rev
                sync.synced = true
                kv.set(Self.key, data: try? JSONEncoder().encode(all))
                saveSync()
            }
        }
        // De a lo más `syncBatch` títulos por vuelta: la TV no acepta más de 100 cambios ni más de 16 KB por petición, y todo
        // junto se rechazaba entero sin que nadie se enterara (A10, 10 nov 2026). Sin nada pendiente va una vuelta vacía (para
        // traer lo de la TV).
        var batches = Self.batches(lock.withLock { sync.pending })[...]
        while let batch = batches.popFirst() {
            let since = lock.withLock { sync.rev }
            let reply: OrbitalRemote.ChoicesReply?
            do { reply = try await remote.syncChoices(since: since, changes: batch) }
            catch OrbitalRemote.Failure.refused(let why) {
                // La TV no quiso este lote (413 o 422: muy grande o un valor que no entiende): se dice en la bitácora y los demás
                // lotes siguen. Un lote de varios se vuelve a mandar título por título, para dar con el que no quiere; ese, tras
                // `maxRefusals` rechazos, se aparta (antes se reenviaba para siempre).
                Log.network.error("La TV rechazó \(batch.count, privacy: .public) idiomas por título: \(why, privacy: .public)")
                if batch.count > 1 { batches = ArraySlice(batch.sorted { $0.key < $1.key }.map { [$0.key: $0.value] } + batches) }
                else { giveUpAfterRefusals(batch, why: why) }
                continue
            } catch {
                return   // sin conexión: lo pendiente espera
            }
            guard let reply else { return }   // una Orbital de antes
            lock.withLock {
                for (id, change) in batch where sync.pending[id] == change { sync.pending[id] = nil; sync.refusals?[id] = nil }   // lo que cambió mientras, se manda la próxima
                for (id, theirs) in reply.changed {
                    sync.revs[id] = theirs.rev
                    if sync.pending[id] != nil { continue }   // aquí hay algo más nuevo: va en la siguiente
                    let value = Saved(audio: theirs.audio, subtitles: theirs.subtitles, spanish: theirs.spanish)
                    all[id] = value.audio == nil && value.subtitles == nil && value.spanish == nil ? nil : value
                }
                sync.rev = reply.rev
                kv.set(Self.key, data: try? JSONEncoder().encode(all))
                saveSync()
            }
        }
    }

    /// Cuántos títulos van por petición: el tope de la TV (`ChoicesSync.changes`, `max_length=100` en `orbital/server.py`).
    static let syncBatch = 100

    /// Lo pendiente en lotes de `syncBatch`, en orden fijo; sin nada pendiente, un lote vacío.
    static func batches(_ pending: [String: OrbitalRemote.ChoiceChange]) -> [[String: OrbitalRemote.ChoiceChange]] {
        guard !pending.isEmpty else { return [[:]] }
        let ids = pending.keys.sorted()
        return stride(from: 0, to: ids.count, by: syncBatch).map { start in
            Dictionary(uniqueKeysWithValues: ids[start..<min(start + syncBatch, ids.count)].map { ($0, pending[$0]!) })
        }
    }

    /// Un lote que la TV no quiso: cada título suma un rechazo; al llegar a `maxRefusals` su cambio se aparta (ya no se reenvía
    /// para siempre) y se registra. Si mientras tanto elegiste otra cosa para ese título, ese cambio nuevo cuenta desde cero.
    private func giveUpAfterRefusals(_ batch: [String: OrbitalRemote.ChoiceChange], why: String) {
        lock.withLock {
            var counts = sync.refusals ?? [:]
            var aside = sync.setAside ?? [:]
            for (id, change) in batch where sync.pending[id] == change {
                let count = (counts[id]?.change == change ? counts[id]!.count : 0) + 1
                counts[id] = Refused(change: change, count: count)
                guard count >= Self.maxRefusals else { continue }
                sync.pending[id] = nil; counts[id] = nil; aside[id] = change
                Log.network.error("La TV rechazó \(Self.maxRefusals, privacy: .public) veces los idiomas de \(id, privacy: .public): se dejan de mandar (\(why, privacy: .public))")
            }
            sync.refusals = counts.isEmpty ? nil : counts
            sync.setAside = aside.isEmpty ? nil : aside
            saveSync()
        }
    }

    /// Lo que la TV rechazó tantas veces que ya no se manda (pruebas y diagnóstico).
    public var setAsideChoices: [String: OrbitalRemote.ChoiceChange] { lock.withLock { sync.setAside ?? [:] } }

    /// Lo que falta mandar (pruebas y diagnóstico).
    public var pendingChoices: [String: OrbitalRemote.ChoiceChange] { lock.withLock { sync.pending } }
}
