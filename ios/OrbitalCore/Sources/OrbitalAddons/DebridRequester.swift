import Foundation

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
/// elige sus archivos (todos los videos si es un paquete), pregunta cuánto llevan todos con una sola consulta y cancela. Lo
/// que cambia se anota en la libreta y se le manda a la TV (`DebridRequestSync`).
public actor DebridRequester {
    public nonisolated let book: DebridRequestBook
    private let api: RealDebridTorrents
    private let token: @Sendable () -> String?
    private let device: @Sendable () -> String
    private let account: @Sendable () async -> String?
    private let clock: @Sendable () -> Date
    private let sync: DebridRequestSync
    private nonisolated let lastAccount = AccountMemo()

    /// - account: el id de usuario de tu Real-Debrid (`GET /user`, guardado), nunca la clave; nil si no se sabe.
    /// - knownAccount: el que ya se sabía al abrir la app (para decir sin esperar qué es de otra cuenta).
    public init(book: DebridRequestBook, api: RealDebridTorrents, token: @escaping @Sendable () -> String?, device: @escaping @Sendable () -> String,
                account: @escaping @Sendable () async -> String? = { nil }, knownAccount: String? = nil,
                clock: @escaping @Sendable () -> Date = { Date() }, sync: DebridRequestSync = NoDebridRequestSync()) {
        self.book = book; self.api = api; self.token = token; self.device = device; self.account = account; self.clock = clock; self.sync = sync
        lastAccount.value = knownAccount
    }

    /// El nombre de este aparato en lo que anota (`by`).
    public nonisolated var deviceName: String { device() }
    /// La cuenta de Real-Debrid de este aparato, la última que se supo (sin preguntar).
    public nonisolated var knownAccount: String? { lastAccount.value }

    private func currentAccount() async -> String? {
        if let fresh = await account(), !fresh.isEmpty { lastAccount.value = fresh; return fresh }
        return lastAccount.value
    }

    private func key() throws -> String {
        guard let token = token(), !token.isEmpty else { throw RDRequestError.noKey }
        return token
    }

    /// «Pedirlo y avisarme»: lo agrega a tu Real-Debrid y elige sus archivos. Si ya estaba pedido (aquí, en la TV con tu
    /// cuenta o porque Torrentio lo pidió al abrirlo), no se pide otra vez: se devuelve ese. Otro episodio de un paquete ya
    /// pedido solo une su video (sin preguntarle a Real-Debrid); de un paquete viejo pedido con un solo archivo, se pide como
    /// torrent nuevo. Si Real-Debrid dice que no por el archivo (derechos, límite), queda anotado con ese estado; si es por tu
    /// cuenta o la red, lanza `RDRequestError`.
    ///
    /// Dos toques seguidos (o la ficha y el reproductor a la vez) no agregan el torrent dos veces: el segundo espera al
    /// primero y luego toma lo que quedó anotado (el actor se puede reentrar en cada `await`).
    /// `auto` (N3-A): es el reintento solo de «Muchas descargas activas»; si vuelve a pasar, ya no se reintenta.
    public func request(_ wish: DebridWish, auto: Bool = false) async throws -> DebridRequest {
        while let running = inFlight[wish.hash] {
            _ = try? await running.value
            if inFlight[wish.hash] == running { inFlight[wish.hash] = nil }   // ya terminó: sin esto se quedaría dando vueltas
        }
        let task = Task { try await self.place(wish, auto: auto) }
        inFlight[wish.hash] = task
        defer { if inFlight[wish.hash] == task { inFlight[wish.hash] = nil } }
        return try await task.value
    }

    /// Los pedidos que van a medio camino, por huella.
    private var inFlight: [String: Task<DebridRequest, Error>] = [:]

    private func place(_ wish: DebridWish, auto: Bool) async throws -> DebridRequest {
        let mine = await currentAccount()
        var replacing: DebridRequest?
        if var known = book.find(hash: wish.hash), !known.isOther(account: mine), ![.refused, .tooMany, .gone].contains(known.state) {
            if known.videoIDs.contains(wish.videoID) { return known }
            if known.coversWholeTorrent {
                known.videoIDs.append(wish.videoID)
                if let idx = wish.fileIdx { known.files[wish.videoID] = idx }
                known.pending = true
                book.put(known)
                await push(known)
                return book.find(hash: known.hash) ?? known
            }
            replacing = known   // un solo archivo elegido: ese episodio no viene, se pide otra vez
        } else if let known = book.find(hash: wish.hash), !known.isOther(account: mine) {
            replacing = known   // rechazado, demasiadas descargas o cancelado: un pedido nuevo
        }
        let token = try key()
        let now = clock()
        var entry = DebridRequest(hash: wish.hash, files: wish.fileIdx.map { [wish.videoID: $0] } ?? [:], account: mine, title: wish.title, kind: wish.kind,
                                  metaID: wish.metaID, videoIDs: [wish.videoID], season: wish.season, episode: wish.episode, language: wish.language,
                                  release: wish.release, device: device(), createdAt: now)
        entry.retried = auto
        if let replacing {
            entry.videoIDs = replacing.videoIDs + entry.videoIDs.filter { !replacing.videoIDs.contains($0) }
            entry.files = replacing.files.merging(entry.files) { _, new in new }
        }
        do {
            // Ya en tu cuenta (Torrentio lo agregó al abrirlo, o lo pediste en real-debrid.com): se toma ese, no se agrega
            // otro. El que ya se conocía con un solo archivo no sirve: se agrega uno nuevo.
            if let existing = try await api.list(limit: 100, token: token).first(where: { $0.hash == entry.hash && $0.id != replacing?.rdID }) {
                entry.apply(existing, now: now)
                if existing.status == "waiting_files_selection", let pack = try? await selectFiles(id: existing.id, fileIdx: wish.fileIdx, token: token) { entry.pack = pack }
            } else {
                let id = try await api.addMagnet(hash: entry.hash, token: token)
                entry.rdID = id
                book.put(entry)   // anotado ya: aunque falle lo que sigue, no se vuelve a agregar
                entry.pack = try await selectFiles(id: id, fileIdx: wish.fileIdx, token: token)
                if let fresh = try? await api.info(id: id, token: token) { entry.apply(fresh, now: clock()) }
            }
        } catch let error as RDRequestError {
            guard let state = DebridRequest.state(after: error) else {
                if entry.rdID == nil {
                    if let replacing { book.put(replacing) } else { book.remove(hash: entry.hash) }
                }
                throw error
            }
            entry.state = state; entry.updatedAt = clock()
        }
        entry.pending = true
        book.put(entry)
        await push(entry)
        return book.find(hash: entry.hash) ?? entry
    }

    /// Elige los archivos (sus ids en Real-Debrid son el `fileIdx` de Torrentio + 1). Un paquete (más de un video) se pide
    /// con todos sus videos, como hace Torrentio: Real-Debrid solo deja elegir una vez. Con un solo video, ese archivo (o, si
    /// no se sabe, los videos). Devuelve true si se eligieron todos los videos de un paquete.
    private func selectFiles(id: String, fileIdx: Int?, token: String) async throws -> Bool {
        let info = try? await api.info(id: id, token: token)
        let files = info?.files ?? []
        let videos = files.filter(\.isVideo).map(\.id)
        var wanted: [Int] = []
        if videos.count > 1 {
            wanted = videos
            if let fileIdx, files.contains(where: { $0.id == fileIdx + 1 }), !wanted.contains(fileIdx + 1) { wanted = (wanted + [fileIdx + 1]).sorted() }
        } else if let fileIdx, files.contains(where: { $0.id == fileIdx + 1 }) {
            wanted = [fileIdx + 1]
        }
        if wanted.isEmpty { wanted = videos }
        try await api.selectFiles(id: id, files: wanted, token: token)
        return videos.count > 1
    }

    /// Torrentio ya se lo pidió a Real-Debrid al abrir una versión «por bajar» (R5/R6): se anota para seguirlo y no pedirlo
    /// otra vez. Su id se encuentra en la siguiente revisión, por su huella.
    public func noteOpened(_ wish: DebridWish) async {
        let mine = await currentAccount()
        if let known = book.find(hash: wish.hash), known.state != .gone, !known.isOther(account: mine) { return }
        let entry = DebridRequest(hash: wish.hash, files: wish.fileIdx.map { [wish.videoID: $0] } ?? [:], account: mine, title: wish.title, kind: wish.kind,
                                  metaID: wish.metaID, videoIDs: [wish.videoID], season: wish.season, episode: wish.episode, language: wish.language,
                                  release: wish.release, device: device(), createdAt: clock())
        book.put(entry)
        await push(entry)
    }

    /// Cuánto lleva cada pedido en camino de tu cuenta, con una sola consulta a `GET /torrents`. Devuelve los que cambiaron
    /// (para avisar los que quedaron listos). Sin pedidos en camino no le pregunta nada a Real-Debrid. Lo que ya no está en tu
    /// cuenta queda como lápida (`gone`), no se borra: así la TV tampoco lo vuelve a anotar.
    @discardableResult
    public func refresh() async -> [DebridRequest] {
        let now = clock()
        let mine = await currentAccount()
        book.prune(now: now, account: mine)
        let active = book.active(account: mine)
        guard !active.isEmpty, let token = try? key() else { return [] }
        let torrents: [RDTorrent]
        do { torrents = try await api.list(limit: 100, token: token) } catch { return [] }
        var changed: [DebridRequest] = []
        for request in active {
            var updated = request
            var touched = false
            if updated.account == nil, let mine { updated.account = mine; touched = true }
            let match = torrents.first { $0.id == request.rdID } ?? torrents.first { $0.hash == request.hash }
            if let match {
                if match.status == "waiting_files_selection", let pack = try? await selectFiles(id: match.id, fileIdx: request.fileIdx, token: token),
                   pack != updated.pack { updated.pack = pack; touched = true }
                guard updated.apply(match, now: now) || touched else { continue }
            } else if let id = request.rdID {
                // Más viejo que los 100 de la lista: se le pregunta por él. Si ya no está, lo borraste (aquí, en la TV o en
                // real-debrid.com): lápida.
                do { let info = try await api.info(id: id, token: token); guard updated.apply(info, now: now) || touched else { continue } }
                catch RDRequestError.notFound { updated.state = .gone; updated.updatedAt = now }
                catch { continue }
            } else {
                continue   // lo pidió Torrentio y todavía no sale en tu cuenta
            }
            updated.pending = true
            book.put(updated)
            changed.append(updated)
        }
        for request in changed { await push(request) }
        return changed.map { book.find(hash: $0.hash) ?? $0 }
    }

    /// «Cancelar pedido»: se quita de tu Real-Debrid (si ya no estaba, también cuenta) y queda como lápida, que se le manda a
    /// la TV. Lo de otra cuenta no se cancela desde aquí.
    public func cancel(hash: String) async throws {
        guard var entry = book.find(hash: hash), entry.state != .gone else { return }
        guard !entry.isOther(account: await currentAccount()) else { return }
        if let id = entry.rdID {
            do { try await api.delete(id: id, token: try key()) } catch RDRequestError.notFound {}
        }
        entry.state = .gone; entry.updatedAt = clock(); entry.pending = true
        book.put(entry)
        await push(entry)
    }

    /// Se junta con la libreta de la TV: primero manda lo que cambió aquí y la TV todavía no tiene; luego lee la suya y la
    /// junta entrada por entrada. Lo que llega de la TV no avisa aquí, salvo `watchReady` (R14-B, el iPhone: lo que la TV
    /// pidió con tu cuenta avisa al quedar listo). Sin TV (o con `NoDebridRequestSync`), nada.
    public func syncWithTV(watchReady: Bool = false) async {
        for entry in book.stored where entry.pending {
            guard await push(entry) else { return }   // la TV no contesta: lo demás, en el siguiente vistazo
        }
        guard let pulled = await sync.pull() else { return }
        for var remote in pulled.requests {
            if remote.account == nil { remote.account = pulled.account }   // sin `account`: la de quien la guarda
            book.absorb(remote, watchReady: watchReady)
        }
        book.prune(now: clock(), account: await currentAccount())
    }

    /// Le manda la entrada a la TV y junta lo que la TV guardó. true si la TV la recibió.
    @discardableResult
    private func push(_ entry: DebridRequest) async -> Bool {
        guard let saved = await sync.push(entry) else { return false }
        book.update(hash: entry.hash) { stored in
            stored = DebridRequest.merge(stored, saved)
            stored.pending = false
        }
        return true
    }

    /// N3-A · lo de este aparato que quedó en «Muchas descargas activas» y todavía no se reintenta solo.
    public nonisolated func waitingForSlot(account mine: String?) -> [DebridRequest] {
        book.all.filter { $0.retriesWhenFree && $0.device == device() && !$0.isOther(account: mine) }
    }

    /// N3-A · si ya hay lugar (`active < limit`, lo que se leyó de tu cuenta), se vuelve a pedir solo, una vez, cada uno que
    /// quedó en «Muchas descargas activas»; si otra vez no hay lugar, queda «Pedir a la nube» a mano. Devuelve los que se pidieron.
    @discardableResult
    public func retryWhenFree(slots: (active: Int, limit: Int)) async -> [DebridRequest] {
        var free = slots.limit - slots.active
        var out: [DebridRequest] = []
        for entry in waitingForSlot(account: knownAccount) where free > 0 {
            let wish = DebridWish(hash: entry.hash, fileIdx: entry.fileIdx, title: entry.title, kind: entry.kind, metaID: entry.metaID,
                                  videoID: entry.videoIDs.first ?? entry.metaID, season: entry.season, episode: entry.episode,
                                  language: entry.language, release: entry.release)
            if let made = try? await request(wish, auto: true) { out.append(made); if made.state.isActive { free -= 1 } }
            else { book.update(hash: entry.hash) { $0.retried = true } }   // la red o tu cuenta: tampoco se insiste
        }
        return out
    }

    /// Cuántas descargas tienes a la vez y tu máximo (D3); nil si no contestó.
    public func activeCount() async -> (active: Int, limit: Int)? {
        guard let token = try? key() else { return nil }
        return try? await api.activeCount(token: token)
    }

    /// Los pedidos de tu cuenta que Real-Debrid ya terminó y traen ese video (Fernando, 3 nov, con «El viento tiene miedo»:
    /// «ya está» y al abrirlo «no llega a ningún lado»). Torrentio puede seguir diciendo «[RD download]» de ellos: la lista
    /// de versiones los marca «Al instante · la pediste» con esto.
    ///
    /// Un paquete (todos sus videos) trae también los demás episodios de ese título aunque no se hayan pedido uno por uno: el
    /// siguiente episodio sale «Al instante · la pediste» sin pedirlo otra vez (análisis de fondo con la TV, 3 nov).
    public nonisolated func ready(kind: String, videoID: String) -> [DebridRequest] {
        let mine = knownAccount
        return book.all.filter { r in
            r.state == .ready && r.kind == kind && !r.isOther(account: mine)
                && (r.videoIDs.contains(videoID) || (r.coversWholeTorrent && videoID.hasPrefix(r.metaID + ":")))
        }
    }

    /// Las huellas que Real-Debrid no dejó bajar en tu cuenta (rechazadas: error 35, derechos…) para ese título: «Real-Debrid no
    /// lo dejó bajar» en «Versión», nunca la recomendada ni la ofrecida (FQ2-A, Fernando, 3 nov).
    public nonisolated func refused(metaID: String) -> Set<String> {
        let mine = knownAccount
        return Set(book.all.filter { $0.state == .refused && $0.metaID == metaID && !$0.isOther(account: mine) }.map(\.hash))
    }

    /// El enlace para ver ese video de un pedido listo, sin pasar por Torrentio (que puede ni listarlo, con «solo lo que ya
    /// está»): `torrents/info` → el enlace de su archivo → `unrestrict/link`. nil si no se puede.
    public func streamLink(hash: String, videoID: String) async -> URL? {
        // El archivo de ESE video: de un paquete sin saber cuál, nada (el más grande sería otro episodio).
        guard let request = book.find(hash: hash), request.state == .ready, let id = request.rdID, let token = try? key() else { return nil }
        let file = request.files[videoID] ?? (request.videoIDs == [videoID] && !request.coversWholeTorrent ? request.fileIdx : nil)
        guard file != nil || (request.videoIDs == [videoID] && !request.coversWholeTorrent),
              let info = try? await api.info(id: id, token: token), info.status == "downloaded", let link = info.link(fileIdx: file) else { return nil }
        return try? await api.unrestrict(link: link, token: token)
    }

    /// Ya se avisó que está listo / que sigue atorado.
    public func markNotified(hash: String) { book.update(hash: hash) { $0.notified = true } }
    public func markNudged(hash: String) { book.update(hash: hash) { $0.nudged = true } }
}

/// La última cuenta de Real-Debrid que se supo (para decir sin esperar si un pedido es de otra cuenta).
final class AccountMemo: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?
    var value: String? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
