import Foundation

/// Un pedido a Real-Debrid (R12): qué torrent, para qué título y episodios, en qué idioma, desde qué aparato y cómo va.
/// Real-Debrid solo sabe el nombre del archivo; lo demás lo sabe esta libreta.
///
/// Su forma es la del contrato con la TV (`design/addons-contract.json` › `requests`, acuerdo S2 del iPhone y corte S2 de
/// la TV, RQ-1 a RQ-12): una entrada por torrent (la clave es su huella), con `account` (el id de usuario de Real-Debrid,
/// nunca la clave), `files` (el archivo de cada video), los seis estados más la lápida `gone`, y lo que nunca viaja
/// (`notified`, `nudged`) aparte. Se lee con tolerancia: lo que falta toma su valor de siempre.
public struct DebridRequest: Codable, Equatable, Sendable, Identifiable {
    /// Los seis estados de R13 (en palabras en `DebridRequestWords`) y la lápida `gone`.
    public enum State: String, Codable, Sendable, CaseIterable {
        /// «En cola»: Real-Debrid lo recibió y espera turno (o está leyendo el torrent).
        case queued
        /// «Bajando · 42 %».
        case downloading
        /// «Sin gente que lo comparta»: baja, pero nadie lo está compartiendo (puede tardar días).
        case noPeers = "no_peers"
        /// «Real-Debrid no lo dejó bajar»: derechos reclamados (error 35), virus, torrent muerto o roto.
        case refused
        /// «Muchas descargas activas»: tu cuenta llegó a su máximo a la vez (error 21).
        case tooMany = "too_many"
        /// «Listo»: ya arranca al instante.
        case ready
        /// Lápida: ya no está en tu Real-Debrid (lo cancelaste aquí, en el otro aparato o en real-debrid.com). No se enseña ni
        /// se sigue; se guarda 7 días para que el otro lado no lo vuelva a anotar.
        case gone

        /// Sigue en camino (se le pregunta a Real-Debrid cuánto lleva).
        public var isActive: Bool { self == .queued || self == .downloading || self == .noPeers }

        /// Al juntar dos entradas gana el de mayor precedencia (contrato › merge › state): gone > ready > refused > no_peers >
        /// downloading > queued > too_many (too_many se reintenta más tarde: cualquier otro le gana).
        public var precedence: Int {
            switch self {
            case .gone: 6
            case .ready: 5
            case .refused: 4
            case .noPeers: 3
            case .downloading: 2
            case .queued: 1
            case .tooMany: 0
            }
        }

        /// Lo que se lee: «failed» (la TV de antes) es `refused`; un estado que esta versión no conoce, «En cola» (se le
        /// vuelve a preguntar a Real-Debrid y, si ya no está en tu cuenta, queda `gone`).
        public static func read(_ raw: String?) -> State {
            guard let raw else { return .queued }
            if raw == "failed" { return .refused }
            return State(rawValue: raw) ?? .queued
        }
    }

    /// La huella del torrent (minúsculas): la clave del pedido, en los dos aparatos.
    public var hash: String
    /// El archivo de cada video dentro del torrent (`{video_id: file_idx}`, desde 0, como lo da Torrentio).
    public var files: [String: Int]
    /// El id de usuario de Real-Debrid de quien lo pidió (nunca la clave). nil = de la misma cuenta (lo de antes).
    public var account: String?
    /// Su id en esa cuenta (nil si lo pidió Torrentio al abrirlo y todavía no se encuentra).
    public var rdID: String?
    public var title: String
    public var kind: String
    public var metaID: String
    /// Los videos que trae (un paquete de temporada trae varios).
    public var videoIDs: [String]
    public var season: Int?
    public var episode: Int?
    /// El idioma de la versión pedida («es-419»), si se sabe.
    public var language: String?
    /// El nombre de la versión (el del archivo).
    public var release: String?
    /// Quién lo pidió: el nombre del aparato, el de su renglón en Cuentas de la TV («iPhone de Fernando», «TV»).
    public var device: String
    public var createdAt: Date
    /// Lo pone la TV al guardar; aquí, cuando cambió en este aparato. Para olvidar, nunca para decidir al juntar.
    public var updatedAt: Date
    /// Lo que dice Real-Debrid tal cual (`downloading`, `magnet_error`…).
    public var rdStatus: String?
    public var percent: Int
    public var seeders: Int?
    public var state: State
    /// La última vez que avanzó (para «sigue sin bajar» a las 24 h).
    public var progressAt: Date

    // Solo de este aparato (contrato › local_only y lo que esta libreta necesita): nunca viajan a la TV.
    /// Ya se avisó que está listo (R10) / que sigue atorado (R13). Un pedido que llega de la TV entra con los dos en true.
    public var notified: Bool
    public var nudged: Bool
    /// Se eligieron todos sus videos (un paquete): pedir otro episodio solo une su video, sin preguntarle a Real-Debrid.
    public var pack: Bool
    /// Cambió aquí y la TV todavía no lo tiene (se manda en el siguiente vistazo).
    public var pending: Bool
    /// N3-A: «Muchas descargas activas» ya se volvió a pedir solo una vez (en el siguiente vistazo con lugar libre). Con
    /// esto en true ya no se reintenta solo: queda «Pedir a la nube» a mano.
    public var retried = false

    public var id: String { hash }

    public init(hash: String, fileIdx: Int? = nil, files: [String: Int]? = nil, account: String? = nil, rdID: String? = nil, title: String, kind: String,
                metaID: String, videoIDs: [String], season: Int? = nil, episode: Int? = nil, language: String? = nil, release: String? = nil,
                device: String, createdAt: Date, rdStatus: String? = nil, percent: Int = 0, seeders: Int? = nil, state: State = .queued) {
        self.hash = hash.lowercased(); self.rdID = rdID; self.title = title; self.kind = kind; self.metaID = metaID; self.account = account
        self.files = files ?? (fileIdx.flatMap { idx in videoIDs.first.map { [$0: idx] } } ?? [:])
        self.videoIDs = videoIDs; self.season = season; self.episode = episode; self.language = language; self.release = release
        self.device = device; self.createdAt = createdAt; self.updatedAt = createdAt; self.rdStatus = rdStatus; self.percent = percent
        self.seeders = seeders; self.state = state; self.progressAt = createdAt; self.notified = false; self.nudged = false
        self.pack = false; self.pending = true
    }

    /// El archivo del primer video (el que se pidió primero).
    public var fileIdx: Int? { videoIDs.lazy.compactMap { self.files[$0] }.first ?? files.values.min() }

    /// Se eligieron todos los videos del torrent: cualquier episodio que traiga ya viene. Un paquete viejo pedido con un
    /// solo archivo no cuenta: ese otro episodio se pide como torrent nuevo.
    public var coversWholeTorrent: Bool { pack || files.count > 1 }

    /// Es de otra cuenta de Real-Debrid (las dos se saben y no son la misma): se enseña, pero no se sigue, no se cancela y
    /// no sale como versión (ese enlace no existe en tu cuenta).
    public func isOther(account mine: String?) -> Bool {
        guard let account, !account.isEmpty, let mine, !mine.isEmpty else { return false }
        return account != mine
    }

    enum CodingKeys: String, CodingKey {
        case hash, files, account, legacyFileIdx = "file_idx", rdID = "rd_id", title, kind, metaID = "meta_id", videoIDs = "video_ids", season,
             episode, language, release, device = "by", createdAt = "since", updatedAt = "updated", rdStatus = "rd_status", percent, seeders,
             state, progressAt = "progress_at", notified, nudged, pack = "all_files", legacyPack = "pack", pending, retried
    }

    /// Con `true` en el `userInfo` del codificador se escribe todo (la libreta de este aparato); sin él, solo lo que viaja a
    /// la TV (sin `updated` ni lo de este aparato, con los topes del contrato).
    public static let localKey = CodingUserInfoKey(rawValue: "orbital.debrid-requests.local")!

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hash = try c.decode(String.self, forKey: .hash).lowercased()
        guard !hash.isEmpty else { throw DecodingError.dataCorruptedError(forKey: .hash, in: c, debugDescription: "sin huella") }
        rdID = (try? c.decodeIfPresent(String.self, forKey: .rdID)).flatMap { $0.isEmpty ? nil : $0 }
        account = (try? c.decodeIfPresent(String.self, forKey: .account)) ?? nil
        if account == nil, let number = try? c.decodeIfPresent(Int.self, forKey: .account) { account = String(number) }
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "movie"
        metaID = try c.decodeIfPresent(String.self, forKey: .metaID) ?? ""
        videoIDs = try c.decodeIfPresent([String].self, forKey: .videoIDs) ?? []
        files = (try? c.decodeIfPresent([String: Int].self, forKey: .files)) ?? [:]
        // La libreta de antes guardaba un solo `file_idx`: es el del primer video.
        if files.isEmpty, let idx = try? c.decodeIfPresent(Int.self, forKey: .legacyFileIdx), let first = videoIDs.first { files = [first: idx] }
        season = try? c.decodeIfPresent(Int.self, forKey: .season)
        episode = try? c.decodeIfPresent(Int.self, forKey: .episode)
        language = (try? c.decodeIfPresent(String.self, forKey: .language)).flatMap { $0.isEmpty ? nil : $0 }
        release = (try? c.decodeIfPresent(String.self, forKey: .release)).flatMap { $0.isEmpty ? nil : $0 }
        device = try c.decodeIfPresent(String.self, forKey: .device) ?? ""
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date(timeIntervalSince1970: 0)
        updatedAt = (try? c.decodeIfPresent(Date.self, forKey: .updatedAt)) ?? createdAt
        rdStatus = try? c.decodeIfPresent(String.self, forKey: .rdStatus)
        percent = min(100, max(0, (try? c.decodeIfPresent(Int.self, forKey: .percent)) ?? 0))
        seeders = try? c.decodeIfPresent(Int.self, forKey: .seeders)
        state = State.read(try? c.decodeIfPresent(String.self, forKey: .state))
        progressAt = (try? c.decodeIfPresent(Date.self, forKey: .progressAt)) ?? updatedAt
        notified = (try? c.decodeIfPresent(Bool.self, forKey: .notified)) ?? false
        nudged = (try? c.decodeIfPresent(Bool.self, forKey: .nudged)) ?? false
        pack = ((try? c.decodeIfPresent(Bool.self, forKey: .pack)) ?? nil ?? (try? c.decodeIfPresent(Bool.self, forKey: .legacyPack)) ?? nil) ?? false
        pending = (try? c.decodeIfPresent(Bool.self, forKey: .pending)) ?? false
        retried = (try? c.decodeIfPresent(Bool.self, forKey: .retried)) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let local = encoder.userInfo[Self.localKey] as? Bool == true
        let videos = local ? videoIDs : Array(videoIDs.prefix(Self.maxVideos))
        try c.encode(hash, forKey: .hash)
        try c.encode(account, forKey: .account)
        try c.encode(rdID, forKey: .rdID)
        try c.encode(local ? title : String(title.prefix(Self.maxTitle)), forKey: .title)
        try c.encode(kind, forKey: .kind)
        try c.encode(metaID, forKey: .metaID)
        try c.encode(videos, forKey: .videoIDs)
        try c.encode(local ? files : files.filter { videos.contains($0.key) }, forKey: .files)
        try c.encode(season, forKey: .season)
        try c.encode(episode, forKey: .episode)
        try c.encode(language ?? "", forKey: .language)
        try c.encode(release ?? "", forKey: .release)
        try c.encode(local ? device : String(device.prefix(Self.maxBy)), forKey: .device)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(rdStatus ?? "", forKey: .rdStatus)
        try c.encode(percent, forKey: .percent)
        try c.encode(seeders, forKey: .seeders)
        try c.encode(progressAt, forKey: .progressAt)
        try c.encode(state.rawValue, forKey: .state)
        try c.encode(pack, forKey: .pack)   // `all_files`: se eligieron todos sus videos (contrato)
        guard local else { return }
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(notified, forKey: .notified)
        try c.encode(nudged, forKey: .nudged)
        try c.encode(pending, forKey: .pending)
        try c.encode(retried, forKey: .retried)
    }

    /// Los topes del contrato (`entry`).
    public static let maxTitle = 120, maxBy = 60, maxVideos = 50

    /// Lo que dice Real-Debrid de un torrent, como uno de los seis estados (la máquina de estados de R13).
    public static func state(rdStatus: String, progress: Int, seeders: Int?) -> State {
        switch rdStatus {
        case "downloaded": return .ready
        case "magnet_error", "error", "virus", "dead": return .refused
        case "downloading", "compressing", "uploading":
            // Bajando sin nadie que lo comparta: se queda en su porcentaje (puede tardar días).
            if rdStatus == "downloading", seeders == 0, progress < 100 { return .noPeers }
            return .downloading
        default: return .queued   // queued, magnet_conversion, waiting_files_selection y lo que salga
        }
    }

    /// El estado cuando Real-Debrid dijo que no al pedirlo (nil: no es del pedido sino de tu cuenta o de la red).
    public static func state(after error: RDRequestError) -> State? {
        switch error {
        case .refused: .refused
        case .tooManyActive: .tooMany
        default: nil
        }
    }

    /// Lo que se espera antes de decir «Sigue sin bajar · ¿probar otra versión?» (R13).
    public static let stallAfter: TimeInterval = 24 * 3600

    /// N3-A: «Muchas descargas activas» que se vuelve a pedir solo, una vez, cuando se libere un lugar.
    public var retriesWhenFree: Bool { state == .tooMany && !retried }

    /// Lleva `stallAfter` sin avanzar.
    public func isStalled(now: Date) -> Bool { state.isActive && now.timeIntervalSince(progressAt) >= Self.stallAfter }

    /// Es de ese video (la película, o un episodio que trae).
    public func covers(metaID: String, videoID: String?) -> Bool {
        self.metaID == metaID && (videoID.map { videoIDs.contains($0) } ?? true)
    }

    /// Le pone lo que dijo Real-Debrid ahora. Devuelve true si algo cambió.
    @discardableResult
    public mutating func apply(_ torrent: RDTorrent, now: Date) -> Bool {
        let before = self
        rdID = torrent.id
        rdStatus = torrent.status
        if torrent.progress > percent { progressAt = now }
        percent = torrent.status == "downloaded" ? 100 : torrent.progress
        seeders = torrent.seeders
        state = Self.state(rdStatus: torrent.status, progress: torrent.progress, seeders: torrent.seeders)
        if state == .ready && before.state != .ready { progressAt = now }
        guard self != before else { return false }
        updatedAt = now
        return true
    }

    /// Junta lo guardado con lo que llega (de la TV, o la respuesta de la TV a lo que se le mandó) por campo, como dice el
    /// contrato (`requests` › `merge`). Los relojes nunca deciden. Lo de este aparato (avisos, paquete) se queda como estaba.
    /// - Un `rd_id` que llega no vacío y distinto del guardado es un pedido nuevo (volver a pedir siempre da otro): reemplaza
    ///   la entrada, con los videos y archivos unidos. Así una lápida o un rechazo no atoran un pedido nuevo.
    /// - Si no: videos y archivos unidos, el mayor avance, el estado de mayor precedencia, el primer `rd_id` no vacío, el
    ///   título, quién y cuándo de quien lo anotó primero, y lo que dice Real-Debrid de la que lleva más avance.
    public static func merge(_ stored: DebridRequest, _ incoming: DebridRequest) -> DebridRequest {
        let videos = stored.videoIDs + incoming.videoIDs.filter { !stored.videoIDs.contains($0) }
        let files = stored.files.merging(incoming.files) { mine, _ in mine }
        var out: DebridRequest
        if let new = incoming.rdID, !new.isEmpty, let old = stored.rdID, !old.isEmpty, new != old {
            out = incoming
        } else {
            out = stored
            let ahead = incoming.percent > stored.percent ? incoming : stored
            out.percent = ahead.percent
            out.rdStatus = ahead.rdStatus
            out.seeders = ahead.seeders
            out.progressAt = max(stored.progressAt, incoming.progressAt)
            out.state = incoming.state.precedence > stored.state.precedence ? incoming.state : stored.state
            out.rdID = stored.rdID ?? incoming.rdID
            out.account = stored.account ?? incoming.account
            if out.title.isEmpty { out.title = incoming.title }
            if out.device.isEmpty { out.device = incoming.device }
            if out.metaID.isEmpty { out.metaID = incoming.metaID; out.kind = incoming.kind }
            out.season = out.season ?? incoming.season
            out.episode = out.episode ?? incoming.episode
            out.language = out.language ?? incoming.language
            out.release = out.release ?? incoming.release
            out.pack = stored.pack || incoming.pack
        }
        out.videoIDs = videos
        out.files = files
        out.updatedAt = max(stored.updatedAt, incoming.updatedAt)
        out.notified = stored.notified; out.nudged = stored.nudged; out.pending = stored.pending; out.retried = stored.retried
        return out
    }
}
