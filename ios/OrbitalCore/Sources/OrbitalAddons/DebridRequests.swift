import Foundation

/// Un pedido a Real-Debrid (R12): qué torrent, para qué título y episodio, en qué idioma, desde qué aparato y cómo va. Real-
/// Debrid solo sabe el nombre del archivo; lo demás lo sabe esta libreta.
///
/// Su forma es la que acordó la TV (A6/A7 de la revisión adversarial, `orbital/rd_requests.py`): una entrada por torrent
/// (la clave es su huella), con `video_ids`, `meta_id`, `title`, `episode`, `by` (el aparato), `hash`, `rd_id`, `rd_status`,
/// `percent`, `seeders`, `since` y los seis estados de R13. Así S2/S4 la pueden juntar con la de la TV sin traducirla
/// (`GET/POST /api/realdebrid/requests`, ver `DebridRequestSync`). Se lee con tolerancia: lo que falta toma su valor de siempre.
public struct DebridRequest: Codable, Equatable, Sendable, Identifiable {
    /// Los seis estados de R13, en palabras en `DebridRequestWords`.
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

        /// Sigue en camino (se le pregunta a Real-Debrid cuánto lleva).
        public var isActive: Bool { self == .queued || self == .downloading || self == .noPeers }
    }

    /// La huella del torrent (minúsculas): la clave del pedido, en los dos aparatos.
    public var hash: String
    /// El archivo dentro del torrent (el de Torrentio, desde 0), si se sabe.
    public var fileIdx: Int?
    /// Su id en tu Real-Debrid (nil si lo pidió Torrentio al abrirlo y todavía no se encuentra en tu cuenta).
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
    /// Quién lo pidió: el nombre del aparato («iPhone de Fernando», la TV).
    public var device: String
    public var createdAt: Date
    public var updatedAt: Date
    /// Lo que dice Real-Debrid tal cual (`downloading`, `magnet_error`…).
    public var rdStatus: String?
    public var percent: Int
    public var seeders: Int?
    public var state: State
    /// La última vez que avanzó (para «sigue sin bajar» a las 24 h).
    public var progressAt: Date
    /// Ya se avisó que está listo (R10) / que sigue atorado (R13).
    public var notified: Bool
    public var nudged: Bool

    public var id: String { hash }

    public init(hash: String, fileIdx: Int? = nil, rdID: String? = nil, title: String, kind: String, metaID: String, videoIDs: [String],
                season: Int? = nil, episode: Int? = nil, language: String? = nil, release: String? = nil, device: String, createdAt: Date,
                rdStatus: String? = nil, percent: Int = 0, seeders: Int? = nil, state: State = .queued) {
        self.hash = hash.lowercased(); self.fileIdx = fileIdx; self.rdID = rdID; self.title = title; self.kind = kind; self.metaID = metaID
        self.videoIDs = videoIDs; self.season = season; self.episode = episode; self.language = language; self.release = release
        self.device = device; self.createdAt = createdAt; self.updatedAt = createdAt; self.rdStatus = rdStatus; self.percent = percent
        self.seeders = seeders; self.state = state; self.progressAt = createdAt; self.notified = false; self.nudged = false
    }

    enum CodingKeys: String, CodingKey {
        case hash, fileIdx = "file_idx", rdID = "rd_id", title, kind, metaID = "meta_id", videoIDs = "video_ids", season, episode, language,
             release, device = "by", createdAt = "since", updatedAt = "updated", rdStatus = "rd_status", percent, seeders, state,
             progressAt = "progress_at", notified, nudged
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hash = try c.decode(String.self, forKey: .hash).lowercased()
        fileIdx = try c.decodeIfPresent(Int.self, forKey: .fileIdx)
        rdID = try c.decodeIfPresent(String.self, forKey: .rdID)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "movie"
        metaID = try c.decodeIfPresent(String.self, forKey: .metaID) ?? ""
        videoIDs = try c.decodeIfPresent([String].self, forKey: .videoIDs) ?? []
        season = try c.decodeIfPresent(Int.self, forKey: .season)
        episode = try c.decodeIfPresent(Int.self, forKey: .episode)
        language = try c.decodeIfPresent(String.self, forKey: .language)
        release = try c.decodeIfPresent(String.self, forKey: .release)
        device = try c.decodeIfPresent(String.self, forKey: .device) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        rdStatus = try c.decodeIfPresent(String.self, forKey: .rdStatus)
        percent = try c.decodeIfPresent(Int.self, forKey: .percent) ?? 0
        seeders = try c.decodeIfPresent(Int.self, forKey: .seeders)
        // Un estado que esta versión no conoce (uno nuevo de la TV) se lee como «En cola»: se vuelve a preguntar.
        state = (try? c.decodeIfPresent(State.self, forKey: .state)) ?? .queued
        progressAt = try c.decodeIfPresent(Date.self, forKey: .progressAt) ?? updatedAt
        notified = try c.decodeIfPresent(Bool.self, forKey: .notified) ?? false
        nudged = try c.decodeIfPresent(Bool.self, forKey: .nudged) ?? false
    }

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
}

/// La libreta de pedidos de este aparato (R12): sobrevive a reiniciar la app y nunca olvida uno que sigue en camino. Los
/// terminados (listos o rechazados) se olvidan a la semana, como en la TV. Se guarda en los ajustes de la app (no lleva
/// claves ni enlaces de Real-Debrid: los enlaces van atados a quien los pidió).
public final class DebridRequestBook: @unchecked Sendable {
    public static let key = "debrid-requests"
    public static let forgetFinishedAfter: TimeInterval = 7 * 24 * 3600
    private let vault: AddonVault
    private let lock = NSLock()
    private var cached: [DebridRequest]?

    public init(vault: AddonVault) { self.vault = vault }

    /// Todos, el más reciente primero.
    public var all: [DebridRequest] { lock.withLock { load() }.sorted { $0.createdAt > $1.createdAt } }
    public var active: [DebridRequest] { all.filter { $0.state.isActive } }

    public func find(hash: String) -> DebridRequest? { lock.withLock { load().first { $0.hash == hash.lowercased() } } }

    /// El pedido de un video (el más reciente que no fue rechazado; si todos lo fueron, el último).
    public func find(metaID: String, videoID: String?) -> DebridRequest? {
        let mine = all.filter { $0.covers(metaID: metaID, videoID: videoID) }
        return mine.first { $0.state != .refused } ?? mine.first
    }

    /// Anota o reemplaza (por huella).
    public func put(_ request: DebridRequest) {
        lock.withLock {
            var list = load()
            if let i = list.firstIndex(where: { $0.hash == request.hash }) { list[i] = request } else { list.append(request) }
            save(list)
        }
    }

    public func update(hash: String, _ change: (inout DebridRequest) -> Void) {
        lock.withLock {
            var list = load()
            guard let i = list.firstIndex(where: { $0.hash == hash.lowercased() }) else { return }
            change(&list[i])
            save(list)
        }
    }

    public func remove(hash: String) { lock.withLock { save(load().filter { $0.hash != hash.lowercased() }) } }

    /// Olvida los terminados de hace más de una semana (los que siguen en camino, nunca).
    public func prune(now: Date) {
        lock.withLock {
            let list = load()
            let kept = list.filter { $0.state.isActive || now.timeIntervalSince($0.updatedAt) < Self.forgetFinishedAfter }
            if kept.count != list.count { save(kept) }
        }
    }

    private func load() -> [DebridRequest] {
        if let cached { return cached }
        let list = vault.data(Self.key).flatMap { try? Self.decoder.decode([DebridRequest].self, from: $0) } ?? []
        cached = list
        return list
    }
    private func save(_ list: [DebridRequest]) {
        cached = list
        vault.setData(Self.key, try? Self.encoder.encode(list))
    }

    static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970; e.outputFormatting = [.sortedKeys]; return e }()
    static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970; return d }()
}

/// Por donde la libreta se juntará con la de la TV (S2/S4): `GET /api/realdebrid/requests` para leer los suyos y `POST
/// /api/realdebrid/requests {hash, video_ids, title, by}` para anotar los de este aparato (la TV no le vuelve a pedir nada a
/// Real-Debrid; es idempotente por huella). La TV los agrega en su S2: hasta entonces la app usa `NoDebridRequestSync` y
/// nunca llama a esas rutas.
public protocol DebridRequestSync: Sendable {
    /// Los pedidos que tiene la TV (vacío si no hay TV o no contesta).
    func pull() async -> [DebridRequest]
    /// Anota en la TV un pedido de este aparato.
    func push(_ request: DebridRequest) async
}

public struct NoDebridRequestSync: DebridRequestSync {
    public init() {}
    public func pull() async -> [DebridRequest] { [] }
    public func push(_ request: DebridRequest) async {}
}

/// Lo que se quiere pedir: un torrent que existe (de tu Torrentio sin Real-Debrid, R4) para un título.
public struct DebridWish: Equatable, Sendable {
    public var hash: String
    public var fileIdx: Int?
    public var title: String
    public var kind: String
    public var metaID: String
    public var videoID: String
    public var season: Int?
    public var episode: Int?
    public var language: String?
    public var release: String?
    public init(hash: String, fileIdx: Int?, title: String, kind: String, metaID: String, videoID: String, season: Int? = nil, episode: Int? = nil,
                language: String? = nil, release: String? = nil) {
        self.hash = hash.lowercased(); self.fileIdx = fileIdx; self.title = title; self.kind = kind; self.metaID = metaID; self.videoID = videoID
        self.season = season; self.episode = episode; self.language = language; self.release = release
    }
}

/// Pide a Real-Debrid y sigue cada pedido (R12, R13): agrega el torrent una sola vez (si ya está en tu cuenta, lo toma),
/// elige el archivo, pregunta cuánto llevan todos con una sola consulta y cancela. Lo que cambia se anota en la libreta.
public actor DebridRequester {
    public nonisolated let book: DebridRequestBook
    private let api: RealDebridTorrents
    private let token: @Sendable () -> String?
    private let device: @Sendable () -> String
    private let clock: @Sendable () -> Date
    private let sync: DebridRequestSync

    public init(book: DebridRequestBook, api: RealDebridTorrents, token: @escaping @Sendable () -> String?, device: @escaping @Sendable () -> String,
                clock: @escaping @Sendable () -> Date = { Date() }, sync: DebridRequestSync = NoDebridRequestSync()) {
        self.book = book; self.api = api; self.token = token; self.device = device; self.clock = clock; self.sync = sync
    }

    private func key() throws -> String {
        guard let token = token(), !token.isEmpty else { throw RDRequestError.noKey }
        return token
    }

    /// «Pedirlo y avisarme»: lo agrega a tu Real-Debrid y elige su archivo. Si ya estaba pedido (aquí o porque Torrentio lo
    /// pidió al abrirlo), no se pide otra vez: se devuelve ese. Si Real-Debrid dice que no por el archivo (derechos, límite),
    /// queda anotado con ese estado; si es por tu cuenta o la red, lanza `RDRequestError`.
    public func request(_ wish: DebridWish) async throws -> DebridRequest {
        if var known = book.find(hash: wish.hash), known.state != .refused {
            if !known.videoIDs.contains(wish.videoID) { known.videoIDs.append(wish.videoID); book.put(known) }
            return known
        }
        let token = try key()
        let now = clock()
        var entry = DebridRequest(hash: wish.hash, fileIdx: wish.fileIdx, title: wish.title, kind: wish.kind, metaID: wish.metaID, videoIDs: [wish.videoID],
                                  season: wish.season, episode: wish.episode, language: wish.language, release: wish.release, device: device(), createdAt: now)
        do {
            // Ya en tu cuenta (Torrentio lo agregó al abrirlo, o lo pediste en real-debrid.com): se toma ese, no se agrega otro.
            if let existing = try await api.list(limit: 100, token: token).first(where: { $0.hash == entry.hash }) {
                entry.apply(existing, now: now)
            } else {
                let id = try await api.addMagnet(hash: entry.hash, token: token)
                entry.rdID = id
                book.put(entry)   // anotado ya: aunque falle lo que sigue, no se vuelve a agregar
                try await selectFiles(id: id, fileIdx: wish.fileIdx, token: token)
                if let fresh = try? await api.info(id: id, token: token) { entry.apply(fresh, now: clock()) }
            }
        } catch let error as RDRequestError {
            guard let state = DebridRequest.state(after: error) else {
                if entry.rdID == nil { book.remove(hash: entry.hash) }
                throw error
            }
            entry.state = state; entry.updatedAt = clock()
        }
        book.put(entry)
        await sync.push(entry)
        return entry
    }

    /// El archivo del episodio (`fileIdx` + 1, como lo cuenta Real-Debrid) o, si no se sabe o no está, todos los videos.
    private func selectFiles(id: String, fileIdx: Int?, token: String) async throws {
        let info = try? await api.info(id: id, token: token)
        let files = info?.files ?? []
        var wanted: [Int] = []
        if let fileIdx, files.contains(where: { $0.id == fileIdx + 1 }) { wanted = [fileIdx + 1] }
        if wanted.isEmpty { wanted = files.filter(\.isVideo).map(\.id) }
        try await api.selectFiles(id: id, files: wanted, token: token)
    }

    /// Torrentio ya se lo pidió a Real-Debrid al abrir una versión «por bajar» (R5/R6): se anota para seguirlo y no pedirlo
    /// otra vez. Su id se encuentra en la siguiente revisión, por su huella.
    public func noteOpened(_ wish: DebridWish) {
        guard book.find(hash: wish.hash) == nil else { return }
        let entry = DebridRequest(hash: wish.hash, fileIdx: wish.fileIdx, title: wish.title, kind: wish.kind, metaID: wish.metaID, videoIDs: [wish.videoID],
                                  season: wish.season, episode: wish.episode, language: wish.language, release: wish.release, device: device(), createdAt: clock())
        book.put(entry)
    }

    /// Cuánto lleva cada pedido en camino, con una sola consulta a `GET /torrents`. Devuelve los que cambiaron (para avisar
    /// los que quedaron listos). Sin pedidos en camino no le pregunta nada a Real-Debrid.
    @discardableResult
    public func refresh() async -> [DebridRequest] {
        let now = clock()
        book.prune(now: now)
        let active = book.active
        guard !active.isEmpty, let token = try? key() else { return [] }
        let torrents: [RDTorrent]
        do { torrents = try await api.list(limit: 100, token: token) } catch { return [] }
        var changed: [DebridRequest] = []
        for request in active {
            var updated = request
            let match = torrents.first { $0.id == request.rdID } ?? torrents.first { $0.hash == request.hash }
            if let match {
                if match.status == "waiting_files_selection" { try? await selectFiles(id: match.id, fileIdx: request.fileIdx, token: token) }
                guard updated.apply(match, now: now) else { continue }
            } else if let id = request.rdID {
                // Más viejo que los 100 de la lista: se le pregunta por él. Si ya no está, lo borraste en real-debrid.com.
                do { let info = try await api.info(id: id, token: token); guard updated.apply(info, now: now) else { continue } }
                catch RDRequestError.notFound { book.remove(hash: request.hash); continue }
                catch { continue }
            } else {
                continue   // lo pidió Torrentio y todavía no sale en tu cuenta
            }
            book.put(updated)
            changed.append(updated)
        }
        return changed
    }

    /// «Cancelar pedido»: se quita de tu Real-Debrid y de la libreta.
    public func cancel(hash: String) async throws {
        guard let entry = book.find(hash: hash) else { return }
        if let id = entry.rdID { try await api.delete(id: id, token: try key()) }
        book.remove(hash: hash)
    }

    /// Cuántas descargas tienes a la vez y tu máximo (D3); nil si no contestó.
    public func activeCount() async -> (active: Int, limit: Int)? {
        guard let token = try? key() else { return nil }
        return try? await api.activeCount(token: token)
    }

    /// Ya se avisó que está listo / que sigue atorado.
    public func markNotified(hash: String) { book.update(hash: hash) { $0.notified = true } }
    public func markNudged(hash: String) { book.update(hash: hash) { $0.nudged = true } }
}
