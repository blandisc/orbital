import Foundation

/// Tu Orbital (la consola de la TV) desde el iPhone: «Ver en la TV». Entra por el puerto público de Orbital (el del túnel
/// de Alexa), siempre con su token. Orbital pone la fuente recomendada y retoma donde ibas: el avance vive en Stremio.
public struct OrbitalRemote: Sendable {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case notConfigured, badToken, unreachable, refused(String)
        /// La consola no tiene esa ruta (versión anterior): el iPhone esconde lo que la usa.
        case outdated
        public var description: String {
            switch self {
            case .notConfigured: "Conecta tu Orbital en Ajustes (la dirección y el token)."
            case .badToken: "Tu Orbital no aceptó el token. Revísalo en Ajustes."
            case .unreachable: "Tu Orbital no contesta. ¿Está prendida la consola?"
            case .refused(let message): message
            case .outdated: "Actualiza tu Orbital para usar el control completo."
            }
        }
    }

    private let http: HTTPClient
    public let base: URL?
    private let token: String

    /// `orbital-ios://pair?u=<dirección>&t=<token>` (el QR de «Conectar iPhone» en la TV).
    public static func pairing(_ url: URL) -> (address: String, token: String)? {
        guard url.scheme == "orbital-ios", url.host == "pair", let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let address = items.first(where: { $0.name == "u" })?.value, normalize(address) != nil,
              let token = items.first(where: { $0.name == "t" })?.value, !token.isEmpty else { return nil }
        return (address, token)
    }

    public init(http: HTTPClient, address: String, token: String) {
        self.http = http; self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        self.base = Self.normalize(address)
    }

    public var isConfigured: Bool { base != nil && !token.isEmpty }

    /// «orbital.midominio.com», «https://orbital.midominio.com/» o con ruta: siempre https y sin la barra final.
    public static func normalize(_ address: String) -> URL? {
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http", url.host != nil else { return nil }
        return url
    }

    /// ¿Contesta y acepta el token?
    public func check() async throws {
        _ = try await send("api/ping", method: "GET", body: nil)
    }

    /// Lo de «Para ti» que ya está en tu Orbital (para no escribirlo otra vez en el iPhone).
    public struct Keys: Sendable, Equatable {
        public var tmdbKey: String, traktClientID: String, region: String
        /// La sesión de Trakt de la consola (nil si allá no está conectado).
        public var traktSession: BorrowedSession?
    }

    public func keys() async throws -> Keys {
        let json = try await send("api/companion", method: "GET", body: nil)
        func text(_ key: String) -> String { json?[key]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        var session: BorrowedSession?
        if let raw = json?["trakt_session"], let access = raw["access_token"]?.nonEmptyString {
            let expires: Double = { switch raw["expires_at"] { case .int(let i)?: Double(i); case .double(let d)?: d; default: 0 } }()
            session = BorrowedSession(accessToken: access, expiresAt: expires)
        }
        return Keys(tmdbKey: text("tmdb_key"), traktClientID: text("trakt_client_id"), region: text("region"), traktSession: session)
    }

    /// Pone en la TV un título de Stremio (película o el episodio `videoID`), desde donde ibas.
    /// Desde el reproductor del iPhone («Ver en la TV»): `position` es el segundo exacto y `choice`, la fuente, el audio y los
    /// subtítulos que tenías; la TV sigue igual (lo que no encuentre, con su regla de siempre).
    public func play(kind: String, metaID: String, videoID: String?, title: String, position: Double? = nil,
                     choice: ResumeChoice? = nil) async throws {
        var body: [String: JSON] = ["kind": .string(kind), "id": .string(metaID), "title": .string(title)]
        if let videoID { body["video_id"] = .string(videoID) }
        if let position, position > 0 { body["position"] = .double(position) }
        if let source = choice?.source { body["source_key"] = .string(source) }
        if let audio = choice?.audio, !audio.off { body["audio"] = audio.json }
        if let subtitle = choice?.subtitle { body["subtitle"] = subtitle.json }
        _ = try await send("api/stremio/play", method: "POST", body: JSON.object(body).serialized())
    }

    // MARK: «Para ti» (RemoteForYou la usa cuando el iPhone está conectado a la consola)
    /// La consola arma «Para ti» antes de contestar (Trakt, el Top 10 de Netflix, JustWatch…): con la caché fría tarda más
    /// que un botón del control remoto. Con 12 s el iPhone se rendía y caía a sus listas propias, sin Top 10 ni plataformas.
    public static let forYouTimeout: TimeInterval = 45

    public func foryouOverview() async throws -> JSON? {
        try await send("api/foryou", method: "GET", body: nil, timeout: Self.forYouTimeout)
    }

    public func foryouList(id: String, kind: String?) async throws -> JSON? {
        var query = [URLQueryItem(name: "id", value: id)]
        if let kind { query.append(URLQueryItem(name: "kind", value: kind)) }
        return try await send("api/foryou/list", method: "GET", query: query, body: nil, timeout: Self.forYouTimeout)
    }

    public func foryouDetails(key: String, kind: String?) async throws -> JSON? {
        var query = [URLQueryItem(name: "key", value: key)]
        if let kind { query.append(URLQueryItem(name: "kind", value: kind)) }
        return try await send("api/foryou/details", method: "GET", query: query, body: nil)
    }

    public func foryouDismiss(key: String) async throws {
        _ = try await send("api/foryou/dismiss", method: "POST", body: JSON.object(["key": .string(key)]).serialized())
    }

    /// Lo que se ve ahora en la TV, para la tarjeta «Viendo en la TV». nil si no hay nada abierto.
    public struct NowPlaying: Sendable, Equatable {
        public var kind: String, live: Bool
        public var metaID: String?, videoID: String?
        public var title: String, episodeLabel: String
        /// Temporada y episodio en números (0 = especiales); nil en películas, TV en vivo o consolas viejas (queda `episodeLabel`).
        public var season: Int?, episode: Int?
        public var poster: String?
        public var position: Double, duration: Double, paused: Bool
        public var channel: String?, number: Int?, category: String?, muted: Bool
        /// El logotipo del canal en vivo (o de la serie de un canal de Orbital 24/7), si la TV lo manda.
        public var logo: String?
        /// Lo que se pinta: en vivo, el logotipo del canal (si no hay, el póster); si no, el póster.
        public var art: String? { live ? (logo ?? poster) : poster }
        /// Las pistas de audio y subtítulos del reproductor (versiones de la consola que las mandan); vacío: no se sabe.
        public var audioTracks: [Track] = [], subtitleTracks: [Track] = []

        public struct Track: Sendable, Equatable, Identifiable {
            public var id: String, label: String, selected: Bool
            public init(id: String, label: String, selected: Bool) { self.id = id; self.label = label; self.selected = selected }
            static func parse(_ json: JSON) -> Track? {
                guard let id = json["id"].flatMap({ $0.string ?? $0.intValue.map(String.init) }) else { return nil }
                return Track(id: id, label: json["label"]?.nonEmptyString ?? json["lang"]?.nonEmptyString ?? id, selected: json["selected"]?.bool ?? false)
            }
        }

        public init(kind: String, live: Bool, metaID: String? = nil, videoID: String? = nil, title: String,
                    episodeLabel: String = "", poster: String? = nil, position: Double = 0, duration: Double = 0,
                    paused: Bool = false, channel: String? = nil, number: Int? = nil, category: String? = nil, muted: Bool = false,
                    season: Int? = nil, episode: Int? = nil) {
            self.kind = kind; self.live = live; self.metaID = metaID; self.videoID = videoID; self.title = title
            self.season = season; self.episode = episode
            self.episodeLabel = episodeLabel; self.poster = poster; self.position = position; self.duration = duration
            self.paused = paused; self.channel = channel; self.number = number; self.category = category; self.muted = muted
        }

        static func parse(_ json: JSON) -> NowPlaying? {
            guard let title = json["title"]?.string else { return nil }
            func number(_ key: String) -> Double {
                switch json[key] { case .int(let i)?: Double(i); case .double(let d)?: d; default: 0 }
            }
            var now = NowPlaying(kind: json["kind"]?.string ?? "movie", live: json["live"]?.bool ?? false,
                              metaID: json["meta_id"]?.string, videoID: json["video_id"]?.string, title: title,
                              episodeLabel: json["episode_label"]?.string ?? "", poster: json["poster"]?.string,
                              position: number("position"), duration: number("duration"), paused: json["paused"]?.bool ?? false,
                              channel: json["channel"]?.string, number: json["number"]?.intValue, category: json["category"]?.string,
                              muted: json["muted"]?.bool ?? false, season: json["season"]?.intValue, episode: json["episode"]?.intValue)
            now.logo = json["logo"]?.nonEmptyString
            now.audioTracks = (json["tracks"]?["audio"]?.array ?? []).compactMap(Track.parse)
            now.subtitleTracks = (json["tracks"]?["subtitles"]?.array ?? []).compactMap(Track.parse)
            return now
        }
    }

    /// Algo que la TV le dejó al iPhone («Enviar al iPhone» o «Descargar en el iPhone»), a la espera de que la app actúe.
    public struct InboxItem: Sendable, Equatable, Codable, Identifiable {
        public enum Action: String, Sendable, Codable { case open, download, played }
        public var id: String
        public var kind: String
        public var metaID: String
        public var videoID: String?
        public var title: String
        public var episodeLabel: String
        /// Temporada y episodio en números (0 = especiales); nil si es película o la consola es de antes (queda `episodeLabel`).
        public var season: Int?, episode: Int?
        public var poster: String?
        public var action: Action
        public var at: Double
        /// «Seguir en el iPhone»: el segundo exacto donde iba en la TV (nil con «Enviar al iPhone»).
        public var position: Double?
        /// …y con qué lo venía viendo: la huella de la fuente (la misma en los dos: `Source.key`), el audio y los subtítulos.
        public var choice: ResumeChoice?
        /// `played` (se cerró un juego): cuánto jugaste esta vez y en total, si se cerró solo o por falta de memoria, y las capturas.
        public var played: Session?

        public struct Session: Sendable, Equatable, Codable {
            public var seconds: Double, totalSeconds: Double?
            public var crashed: Bool, lowMemory: Bool
            public var captures: Int
            /// El arte del juego en tu Orbital (su portada ancha), ya con la dirección completa.
            public var art: String?
            public init(seconds: Double, totalSeconds: Double? = nil, crashed: Bool = false, lowMemory: Bool = false, captures: Int = 0, art: String? = nil) {
                self.seconds = seconds; self.totalSeconds = totalSeconds; self.crashed = crashed; self.lowMemory = lowMemory; self.captures = captures; self.art = art
            }
        }

        public init(id: String, kind: String, metaID: String, videoID: String? = nil, title: String, episodeLabel: String = "",
                    poster: String? = nil, action: Action, at: Double = 0, season: Int? = nil, episode: Int? = nil, position: Double? = nil) {
            self.id = id; self.kind = kind; self.metaID = metaID; self.videoID = videoID; self.title = title; self.position = position
            self.season = season; self.episode = episode
            self.episodeLabel = episodeLabel; self.poster = poster; self.action = action; self.at = at
        }

        static func parse(_ json: JSON) -> InboxItem? {
            guard let id = json["id"]?.nonEmptyString, let metaID = json["meta_id"]?.nonEmptyString,
                  let raw = json["action"]?.string, let action = Action(rawValue: raw) else { return nil }
            let at: Double = { switch json["at"] { case .int(let i)?: Double(i); case .double(let d)?: d; default: 0 } }()
            return InboxItem(id: id, kind: json["kind"]?.string ?? "movie", metaID: metaID, videoID: json["video_id"]?.nonEmptyString,
                             title: json["title"]?.string ?? "", episodeLabel: json["episode_label"]?.string ?? "",
                             poster: json["poster"]?.nonEmptyString, action: action, at: at,
                             season: json["season"]?.intValue, episode: json["episode"]?.intValue,
                             position: json["position"]?.doubleValue.flatMap { $0 > 0 ? $0 : nil })
                .with(choice: choice(json))
                .with(played: action == .played ? Session(seconds: json["seconds"]?.doubleValue ?? 0, totalSeconds: json["total_seconds"]?.doubleValue,
                                                          crashed: json["crashed"]?.bool ?? false, lowMemory: json["low_memory"]?.bool ?? false,
                                                          captures: json["captures"]?.intValue ?? json["captures"]?.array?.count ?? 0,
                                                          art: "/api/art/\(uriComponent(metaID))?kind=hero") : nil)
        }

        func with(played: Session?) -> InboxItem { var copy = self; copy.played = played; return copy }
        func with(choice: ResumeChoice?) -> InboxItem { var copy = self; copy.choice = choice; return copy }

        /// La fuente y las pistas que mandó la TV con «Seguir en el iPhone» (nil si no mandó ninguna).
        static func choice(_ json: JSON) -> ResumeChoice? {
            let source = json["source"]?.nonEmptyString, audio = ResumeChoice.Track.parse(json["audio"])
            let subtitle = ResumeChoice.Track.parse(json["subtitle"])
            guard source != nil || audio != nil || subtitle != nil else { return nil }
            let videoID = json["video_id"]?.nonEmptyString ?? json["meta_id"]?.nonEmptyString ?? ""
            return ResumeChoice(videoID: videoID, source: source, audio: audio, subtitle: subtitle)
        }

        /// «The Office T2 · E5» (o solo el título, si es una película).
        public var displayName: String { episodeLabel.isEmpty ? title : "\(title) \(episodeLabel)" }
    }

    /// Lo que contesta la consola en cada sondeo: lo que se ve ahora y lo que la TV le dejó al iPhone.
    /// El volumen de la TV (el de Windows): 0–100 y si está en silencio.
    public struct Volume: Sendable, Equatable {
        public var level: Int, muted: Bool
        public init(level: Int, muted: Bool) { self.level = level; self.muted = muted }
        static func parse(_ json: JSON?) -> Volume? {
            guard let level = json?["level"]?.intValue else { return nil }
            return Volume(level: max(0, min(100, level)), muted: json?["muted"]?.bool ?? false)
        }
    }

    /// El juego que corre en la consola (modo acompañante). nil si no hay juego o la consola es de antes.
    public struct Game: Sendable, Equatable {
        public var id: String, title: String
        /// steam | gamecube | switch | ps2 | … | geforcenow
        public var system: String
        public var runner: String?
        public var cover: String?, hero: String?, logo: String?
        public var started: Date?
        /// Congelado al ir al Inicio de Orbital.
        public var paused: Bool
        /// Cuándo se cerraría solo por inactividad (para avisar antes).
        public var closesAt: Date?

        public init(id: String, title: String, system: String, runner: String? = nil, cover: String? = nil, hero: String? = nil, logo: String? = nil,
                    started: Date? = nil, paused: Bool = false, closesAt: Date? = nil) {
            self.id = id; self.title = title; self.system = system; self.runner = runner; self.cover = cover; self.hero = hero; self.logo = logo
            self.started = started; self.paused = paused; self.closesAt = closesAt
        }

        static func parse(_ json: JSON?) -> Game? {
            guard let json, !json.isNull, let id = json["id"]?.nonEmptyString, let title = json["title"]?.nonEmptyString else { return nil }
            func date(_ key: String) -> Date? { json[key]?.doubleValue.map { Date(timeIntervalSince1970: $0) } }
            return Game(id: id, title: title, system: json["system"]?.string ?? "", runner: json["runner"]?.nonEmptyString,
                        cover: json["art"]?["cover"]?.nonEmptyString, hero: json["art"]?["hero"]?.nonEmptyString, logo: json["art"]?["logo"]?.nonEmptyString,
                        started: date("started"), paused: json["paused"]?.bool ?? false, closesAt: date("closes_at"))
        }
    }

    /// Cómo está la consola mientras juegas: batería, controles, Wi‑Fi, memoria y modo de energía.
    public struct ConsoleState: Sendable, Equatable {
        public struct Controller: Sendable, Equatable { public var kind: String, battery: String }
        public struct App: Sendable, Equatable { public var name: String, gb: Double, closable: Bool }
        public var batteryPercent: Int?, plugged: Bool, minutesLeft: Int?
        public var powerMode: String?, brightness: Int?
        public var wifiSSID: String?, wifiSignal: Int?
        public var controllers: [Controller]
        public var freeGB: Double?
        public var apps: [App]

        public init(batteryPercent: Int? = nil, plugged: Bool = false, minutesLeft: Int? = nil, powerMode: String? = nil, brightness: Int? = nil,
                    wifiSSID: String? = nil, wifiSignal: Int? = nil, controllers: [Controller] = [], freeGB: Double? = nil, apps: [App] = []) {
            self.batteryPercent = batteryPercent; self.plugged = plugged; self.minutesLeft = minutesLeft; self.powerMode = powerMode
            self.brightness = brightness; self.wifiSSID = wifiSSID; self.wifiSignal = wifiSignal; self.controllers = controllers
            self.freeGB = freeGB; self.apps = apps
        }

        static func parse(_ json: JSON?) -> ConsoleState? {
            guard let json, json.object != nil else { return nil }
            let battery = json["battery"]
            return ConsoleState(
                batteryPercent: battery?["percent"]?.intValue, plugged: battery?["plugged"]?.bool ?? false, minutesLeft: battery?["minutes_left"]?.intValue,
                powerMode: json["power_mode"]?.nonEmptyString, brightness: json["brightness"]?.intValue,
                wifiSSID: json["wifi"]?["ssid"]?.nonEmptyString, wifiSignal: json["wifi"]?["signal"]?.intValue,
                controllers: (json["controllers"]?.array ?? []).compactMap { c in c["kind"]?.string.map { Controller(kind: $0, battery: c["battery"]?.string ?? "") } },
                freeGB: json["memory"]?["free_gb"]?.doubleValue,
                apps: (json["memory"]?["apps"]?.array ?? []).compactMap { a in
                    a["name"]?.nonEmptyString.map { App(name: $0, gb: a["gb"]?.doubleValue ?? 0, closable: a["closable"]?.bool ?? false) }
                })
        }
    }

    public struct Snapshot: Sendable, Equatable {
        /// El juego que corre (modo acompañante), si la consola lo dice.
        public var game: Game?
        /// El volumen de la TV, si la consola lo dice (versiones nuevas).
        public var volume: Volume?
        public var playing: NowPlaying?
        public var inbox: [InboxItem]
        /// Hay un campo de texto con foco en la TV (el control completo enseña «Escribir»). nil: la consola no lo dice.
        public var textField: Bool?
        /// Lo que hace cada botón en la pantalla de la TV ahora (la leyenda del pie: «alt» → «Mi lista»…). Vacío: no lo dice.
        public var legend: [String: String]
        /// La sección de la TV al frente («Inicio», «Juegos», «Películas y series», «Apps»).
        public var section: String?
        /// La pantalla al frente: «search», «login», «menu», «title», «sources», «player», «live» o la sección («home»…).
        public var screen: String?

        public init(playing: NowPlaying?, inbox: [InboxItem], textField: Bool? = nil, legend: [String: String] = [:], section: String? = nil) {
            self.playing = playing; self.inbox = inbox; self.textField = textField; self.legend = legend; self.section = section
        }
    }

    /// Qué se ve ahora en la TV y qué le dejó la TV al iPhone, en una sola petición.
    public func snapshot() async throws -> Snapshot {
        let json = try await send("api/companion/now", method: "GET", body: nil)
        var playing: NowPlaying?
        if let raw = json?["playing"], !raw.isNull { playing = NowPlaying.parse(raw).map(absolute) }
        var snapshot = Snapshot(playing: playing, inbox: (json?["inbox"]?.array ?? []).compactMap(InboxItem.parse).map(absolute),
                                textField: json?["ui"]?["text_field"]?.bool,
                                legend: (json?["ui"]?["legend"]?.object ?? [:]).compactMapValues { $0.nonEmptyString },
                                section: json?["ui"]?["section"]?.nonEmptyString)
        snapshot.screen = json?["ui"]?["screen"]?.nonEmptyString
        snapshot.volume = Volume.parse(json?["ui"]?["volume"] ?? json?["volume"])
        snapshot.game = Game.parse(json?["game"]).map(absolute)
        return snapshot
    }

    /// Cómo está la consola (modo acompañante). nil: la consola es de antes.
    public func console() async throws -> ConsoleState? {
        do { return ConsoleState.parse(try await send("api/companion/console", method: "GET", body: nil)) }
        catch Failure.refused { return nil }
    }

    /// Volver al juego, ir al Inicio de Orbital (lo congela) o cerrarlo. Devuelve el juego como quedó.
    @discardableResult
    public func game(action: String) async throws -> Game? {
        let json = try await send("api/companion/game", method: "POST", body: JSON.object(["action": .string(action)]).serialized())
        return Game.parse(json?["game"] ?? json).map(absolute)
    }

    /// El modo de energía (efficiency · balanced · performance) o cerrar una app que gasta memoria (nunca el juego).
    public func console(powerMode: String? = nil, closeApp: String? = nil) async throws {
        var body: [String: JSON] = [:]
        if let powerMode { body["power_mode"] = .string(powerMode) }
        if let closeApp { body["close_app"] = .string(closeApp) }
        _ = try await send("api/companion/console", method: "POST", body: JSON.object(body).serialized())
    }

    private func absolute(_ game: Game) -> Game {
        var g = game
        func fix(_ s: String?) -> String? {
            guard let s, s.hasPrefix("/"), let base else { return s }
            return URL(string: s, relativeTo: base)?.absoluteString ?? s
        }
        g.cover = fix(g.cover); g.hero = fix(g.hero); g.logo = fix(g.logo)
        return g
    }

    /// Qué se ve ahora en la TV (para la tarjeta del iPhone). nil si no hay nada abierto.
    public func now() async throws -> NowPlaying? {
        try await snapshot().playing
    }

    /// El iPhone ya actuó sobre esos pendientes: la consola los quita de la bandeja.
    /// Lo que se eligió para un título (audio, «es-419» / «es-ES», subtítulos) y su revisión en tu Orbital.
    public struct TitleChoice: Sendable, Equatable, Codable {
        public var audio: String?
        public var spanish: String?
        public var subtitles: String?
        public var rev: Int
        public init(audio: String? = nil, spanish: String? = nil, subtitles: String? = nil, rev: Int = 0) {
            self.audio = audio; self.spanish = spanish; self.subtitles = subtitles; self.rev = rev
        }
    }

    /// Lo que eligió el iPhone y aún no sabe tu Orbital: solo los campos que cambiaron, lo que hay que olvidar y la
    /// última revisión de ese título que vio el iPhone (si la TV lo cambió después, gana la TV).
    public struct ChoiceChange: Sendable, Equatable, Codable {
        public var audio: String?
        public var spanish: String?
        public var subtitles: String?
        public var forget: [String]
        public var base: Int
        public init(audio: String? = nil, spanish: String? = nil, subtitles: String? = nil, forget: [String] = [], base: Int = 0) {
            self.audio = audio; self.spanish = spanish; self.subtitles = subtitles; self.forget = forget; self.base = base
        }
    }

    public struct ChoicesReply: Sendable, Equatable {
        public var rev: Int
        public var changed: [String: TitleChoice]
        public var rejected: [String]
    }

    /// Manda lo que cambió aquí y trae lo que cambió en la TV desde `since`. nil: tu Orbital es de antes (no sincroniza).
    public func syncChoices(since: Int, changes: [String: ChoiceChange]) async throws -> ChoicesReply? {
        var body: [String: JSON] = [:]
        for (id, c) in changes {
            var fields: [String: JSON] = ["base_rev": .int(c.base)]
            if let v = c.audio { fields["audio"] = .string(v) }
            if let v = c.spanish { fields["spanish"] = .string(v) }
            if let v = c.subtitles { fields["subtitles"] = .string(v) }
            if !c.forget.isEmpty { fields["forget"] = .array(c.forget.map { .string($0) }) }
            body[id] = .object(fields)
        }
        let json: JSON?
        do { json = try await send("api/companion/choices", method: "POST", body: JSON.object(["since": .int(since), "changes": .object(body)]).serialized()) }
        catch Failure.refused(let why) where why.contains("versión anterior") { return nil }
        guard let json, let rev = json["rev"]?.intValue else { return nil }
        var changed: [String: TitleChoice] = [:]
        for (id, raw) in json["changed"]?.object ?? [:] {
            changed[id] = TitleChoice(audio: raw["audio"]?.string, spanish: raw["spanish"]?.string, subtitles: raw["subtitles"]?.string,
                                      rev: raw["rev"]?.intValue ?? 0)
        }
        return ChoicesReply(rev: rev, changed: changed, rejected: (json["rejected"]?.array ?? []).compactMap(\.string))
    }

    public func ack(ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        _ = try await send("api/companion/inbox/ack", method: "POST", body: JSON.object(["ids": .array(ids.map { .string($0) })]).serialized())
    }

    /// Lo que contestó tu Orbital a una orden de voz: si la hizo y qué decir en voz alta («Poniendo The Office…»).
    public struct VoiceReply: Sendable, Equatable {
        public var ok: Bool
        public var speech: String
        /// Lo que se entendió («pon The Office», ya limpio), para enseñarlo bajo la respuesta. Vacío si la consola no lo manda.
        public var heard: String
        /// Varias con el mismo nombre (Dune de 1984 y de 2021): se enseñan para tocar la que es.
        public var choices: [VoiceChoice]
        public init(ok: Bool, speech: String, heard: String = "", choices: [VoiceChoice] = []) {
            self.ok = ok; self.speech = speech; self.heard = heard; self.choices = choices
        }
    }

    /// Una de las opciones que manda la consola cuando no sabe cuál: `kind` es movie o series.
    public struct VoiceChoice: Sendable, Equatable, Identifiable {
        public var id: String
        public var title: String
        public var subtitle: String
        public var kind: String
        public var metaID: String
        public var image: String?
        public init(id: String, title: String, subtitle: String, kind: String, metaID: String, image: String? = nil) {
            self.id = id; self.title = title; self.subtitle = subtitle; self.kind = kind; self.metaID = metaID; self.image = image
        }

        init?(_ json: JSON) {
            guard let title = json["title"]?.string, let metaID = json["meta_id"]?.string, !metaID.isEmpty else { return nil }
            self.init(id: json["id"]?.string ?? metaID, title: title, subtitle: json["subtitle"]?.string ?? "",
                      kind: json["kind"]?.string ?? "movie", metaID: metaID, image: json["image"]?.string)
        }
    }

    /// Una orden en texto libre, como a Alexa («pon The Office temporada 2», «pausa», «abre Zelda»): la consola la entiende
    /// con la misma lógica (`voice.py`). Sirve para Siri y para el micrófono de la app.
    public func voice(_ text: String) async throws -> VoiceReply {
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        let json = try await send("api/voice", method: "POST", body: JSON.object(["text": .string(trimmed), "source": "iphone"]).serialized(), timeout: 20)   // no cuenta como «Alexa se usó»
        let choices = (json?["choices"]?.array ?? []).compactMap(VoiceChoice.init)
        return VoiceReply(ok: json?["ok"]?.bool ?? true, speech: json?["speech"]?.string ?? "", heard: json?["heard"]?.string ?? "",
                          choices: choices)
    }

    /// Las acciones del mando de la TV (como `input.js`): el control completo del iPhone las manda como si fueran del mando.
    public enum InputAction: String, Sendable, CaseIterable {
        case up, down, left, right, select, back, home, menu, search, options, pageleft, pageright
        /// X del mando; LB y RB (cambiar de sección); F5 (recargar).
        case alt, prevsection, nextsection, refresh
    }

    /// Una tecla del mando, a la interfaz de la TV.
    public func input(_ action: InputAction) async throws {
        _ = try await send("api/companion/input", method: "POST", body: JSON.object(["action": .string(action.rawValue)]).serialized(), timeout: 5)
    }

    /// Texto al campo con foco de la TV (buscar); con `submit`, además lo envía.
    /// `replace`: el texto reemplaza el campo entero (consolas nuevas); sin él, se agrega letra por letra.
    public func type(_ text: String, submit: Bool, replace: Bool = false) async throws {
        var body: [String: JSON] = ["text": .string(text), "submit": .bool(submit)]
        if replace { body["replace"] = .bool(true) }
        _ = try await send("api/companion/text", method: "POST", body: JSON.object(body).serialized(), timeout: 8)
    }

    /// Un botón de la tarjeta: `toggle · pause · play · skip (con delta en segundos) · next · previous · stop · mute`.
    /// Devuelve lo que quedó viendo (nil si se detuvo).
    @discardableResult
    public func control(action: String, delta: Double? = nil, track: String? = nil) async throws -> NowPlaying? {
        var body: [String: JSON] = ["action": .string(action)]
        if let delta { body["delta"] = .double(delta) }
        if let track { body["track"] = .string(track) }
        let json = try await send("api/companion/player", method: "POST", body: JSON.object(body).serialized())
        guard let playing = json?["playing"], !playing.isNull else { return nil }
        return NowPlaying.parse(playing).map(absolute)
    }

    /// Una imagen que la consola sirve ella misma («/api/img?…») se pide a su dirección.
    private func absolute(_ item: InboxItem) -> InboxItem {
        guard var session = item.played, let art = session.art, art.hasPrefix("/"), let base else { return item }
        session.art = URL(string: art, relativeTo: base)?.absoluteString
        return item.with(played: session)
    }

    private func absolute(_ now: NowPlaying) -> NowPlaying {
        var n = now
        func fix(_ s: String?) -> String? {
            guard let s, s.hasPrefix("/"), let base else { return s }
            return URL(string: s, relativeTo: base)?.absoluteString ?? s
        }
        n.poster = fix(n.poster); n.logo = fix(n.logo)
        return n
    }

    private func send(_ path: String, method: String, query: [URLQueryItem] = [], body: Data?, timeout: TimeInterval = 12) async throws -> JSON? {
        guard let base, !token.isEmpty else { throw Failure.notConfigured }
        var headers = ["Authorization": "Bearer \(token)"]
        if body != nil { headers["Content-Type"] = "application/json" }
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw Failure.unreachable }
        let response: HTTPResponse
        do { response = try await http.send(HTTPRequest(url: url, method: method, headers: headers, body: body, timeout: timeout)) }
        catch { if Task.isCancelled { throw CancellationError() }; throw Failure.unreachable }   // cancelar no es «la consola no contesta»
        switch response.status {
        case 200..<300: return JSON.parse(response.data)
        case 401, 403: throw Failure.badToken
        case 429: throw Failure.refused("Tu Orbital pidió esperar un poco: demasiados intentos.")
        case 404 where path == "api/companion/input" || path == "api/companion/text":
            throw Failure.outdated
        case 404 where path.hasPrefix("api/stremio") || path.hasPrefix("api/companion"):
            throw Failure.refused("Tu Orbital es de una versión anterior: actualízala para «Ver en la TV».")
        default:
            let detail = JSON.parse(response.data)?["detail"]?.string
            throw Failure.refused(detail ?? "Tu Orbital contestó con un error (\(response.status)).")
        }
    }
}

/// «Escribir en la TV»: la tele agrega cada letra que recibe al campo con foco (y «\u{8}» borra una). Mandar el texto completo
/// en cada cambio lo repetía («hola» → «holahola mundo»): se manda solo la diferencia con lo ya enviado.
public enum RemoteTyping {
    /// Borrados («\u{8}») hasta lo que tienen en común y luego lo nuevo.
    public static func delta(from sent: String, to text: String) -> String {
        let common = zip(sent, text).prefix { $0 == $1 }.count
        return String(repeating: "\u{8}", count: sent.count - common) + String(text.dropFirst(common))
    }
}

