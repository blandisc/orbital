import Foundation
import OrbitalCore
import OrbitalAddons

/// Tus pedidos a Real-Debrid en la app (R12, R13, D3): la libreta de este aparato, pedir lo que todavía no tiene, cuánto
/// lleva cada uno y avisar cuando queda listo. La ficha, «Seguir viendo», el reproductor y Ajustes leen de aquí.
@MainActor
public final class DebridRequestsModel: ObservableModel {
    /// Todos los de la libreta, el más reciente primero.
    public private(set) var requests: [DebridRequest] = [] { didSet { if oldValue != requests { changed() } } }
    /// Cuántas descargas tienes a la vez y tu máximo (D3), si se preguntó.
    public private(set) var activeCount: (active: Int, limit: Int)? { didSet { changed() } }

    public let requester: DebridRequester
    private let lookup: TorrentLookup
    private let addonList: AddonList
    private let finder: @MainActor () -> StreamFinder
    private let hasKey: @MainActor () -> Bool
    private let clock: @Sendable () -> Date
    /// Un pedido quedó listo (R10: el aviso «Ya está…»). Lo pone la app.
    public var onReady: (@MainActor (DebridRequest) -> Void)?
    /// Un pedido lleva 24 h sin avanzar (R13: «Sigue sin bajar · ¿probar otra versión?»). Lo pone la app.
    public var onStalled: (@MainActor (DebridRequest) -> Void)?

    init(requester: DebridRequester, lookup: TorrentLookup, addonList: AddonList, finder: @escaping @MainActor () -> StreamFinder,
         hasKey: @escaping @MainActor () -> Bool, clock: @escaping @Sendable () -> Date) {
        self.requester = requester; self.lookup = lookup; self.addonList = addonList; self.finder = finder; self.hasKey = hasKey; self.clock = clock
        super.init()
        requests = requester.book.all
    }

    public var active: [DebridRequest] { requests.filter { $0.state.isActive } }

    /// El pedido de ese video (película o episodio), si hay.
    public func request(metaID: String, videoID: String?) -> DebridRequest? {
        let mine = requests.filter { $0.covers(metaID: metaID, videoID: videoID) }
        return mine.first { $0.state != .refused } ?? mine.first
    }

    /// Tu Torrentio sin Real-Debrid (R4): la base para ver qué torrents existen. nil sin clave o sin Torrentio prendido.
    public var keylessBase: String? {
        guard hasKey() else { return nil }
        let torrentio = addonList.installed.filter { $0.enabled && $0.resources.contains("stream") }
            .compactMap(addonList.resolvedURL).compactMap(AddonCatalog.torrentioWithoutDebrid).first
        // Sin tu lista armada (aún con los de Stremio), el de fábrica con las opciones de siempre.
        return torrentio ?? (addonList.isConfigured ? nil : AddonCatalog.torrentioWithoutDebrid(AddonCatalog.torrentioBase + "/manifest.json"))
    }

    /// Se puede pedir algo a Real-Debrid desde esta app (hay clave y un Torrentio que diga qué torrents existen).
    public var canRequest: Bool { keylessBase != nil }

    /// Los torrents que existen de ese video (R4), del mejor al peor; nil si no se pudo preguntar.
    public func torrents(kind: String, videoID: String, prefs: Preferences) async -> [Source]? {
        guard let base = keylessBase else { return nil }
        return await lookup.torrents(base: base, kind: kind, videoID: videoID, prefs: prefs)
    }

    public enum Outcome: Equatable, Sendable {
        /// Real-Debrid lo aceptó (o ya estaba pedido): este es el pedido, con su estado.
        case requested(DebridRequest)
        /// No se pudo: la causa (tu cuenta, el archivo) o, si no es una causa, el error en palabras.
        case failed(UnavailableCause?, RDRequestError)
        /// No hay ningún torrent de ese video (causa 11).
        case nobodyHasIt
    }

    /// «Pedirlo y avisarme»: el torrent que se sabe (`preferred`, la versión «por bajar» de la lista) o el mejor que exista
    /// en tu idioma. Nunca pide dos veces el mismo.
    public func request(kind: String, metaID: String, videoID: String, title: String, season: Int? = nil, episode: Int? = nil, prefs: Preferences,
                        preferred: TorrentID? = nil, language: String? = nil, release: String? = nil) async -> Outcome {
        if let known = request(metaID: metaID, videoID: videoID), known.state.isActive { return .requested(known) }
        var pick = preferred.map { (torrent: $0, language: language, release: release) }
        if pick == nil {
            guard let found = await torrents(kind: kind, videoID: videoID, prefs: prefs) else { return .failed(nil, .network) }
            guard let best = found.first, let torrent = best.torrent else { return .nobodyHasIt }
            pick = (torrent, Streams.playingLanguage(best, prefs)?.code, best.release.isEmpty ? nil : best.release)
        }
        guard let pick else { return .nobodyHasIt }
        let wish = DebridWish(hash: pick.torrent.hash, fileIdx: pick.torrent.fileIdx, title: title, kind: kind, metaID: metaID, videoID: videoID,
                              season: season, episode: episode, language: pick.language, release: pick.release)
        do {
            let made = try await requester.request(wish)
            reload()
            await finder().forget(kind: kind, videoID: videoID)
            return .requested(made)
        } catch let error as RDRequestError {
            return .failed(UnavailableCause.from(error), error)
        } catch {
            return .failed(nil, .unexpected)
        }
    }

    /// El reproductor abrió una versión «por bajar»: Torrentio ya se la pidió a Real-Debrid. Se anota para seguirla (R5, R6).
    public func noteOpened(_ source: Source, kind: String, metaID: String, videoID: String, title: String, season: Int?, episode: Int?, language: String?) async {
        guard let torrent = source.torrent else { return }
        await requester.noteOpened(DebridWish(hash: torrent.hash, fileIdx: torrent.fileIdx, title: title, kind: kind, metaID: metaID, videoID: videoID,
                                              season: season, episode: episode, language: language, release: source.release.isEmpty ? nil : source.release))
        reload()
    }

    /// Cuánto lleva cada uno (una sola consulta). Los que quedan listos salen «Al instante» y se avisan; los atorados 24 h,
    /// también (una vez).
    public func refresh() async {
        let changed = await requester.refresh()
        reload()
        for request in changed where request.state == .ready && !request.notified {
            for video in request.videoIDs { await finder().forget(kind: request.kind, videoID: video) }
            await requester.markNotified(hash: request.hash)
            onReady?(request)
        }
        let now = clock()
        for request in active where request.isStalled(now: now) && !request.nudged {
            await requester.markNudged(hash: request.hash)
            onStalled?(request)
        }
        reload()
    }

    /// «Cancelar pedido». false si Real-Debrid no contestó.
    @discardableResult
    public func cancel(_ request: DebridRequest) async -> Bool {
        do { try await requester.cancel(hash: request.hash) } catch { return false }
        reload()
        for video in request.videoIDs { await finder().forget(kind: request.kind, videoID: video) }
        return true
    }

    /// D3: cuántos van de tu límite.
    public func loadActiveCount() async { activeCount = await requester.activeCount() }

    /// Mientras la app está abierta y algo baja, pregunta cada `every` segundos (R10). Termina al cancelar la tarea.
    public func follow(every: TimeInterval = 20) async {
        while !Task.isCancelled {
            if !active.isEmpty { await refresh() }
            try? await Task.sleep(nanoseconds: UInt64(every * 1_000_000_000))
        }
    }

    func reload() { requests = requester.book.all }
    /// La demostración llenó la libreta (`-demo-rd-request`).
    public func reloadForDemo() { reload() }
}
