import Foundation
import OrbitalCore

public struct EpisodeRow: Equatable, Identifiable {
    public var id: String                  // el video id
    public var season: Int
    public var number: Int
    public var title: String               // en tu idioma
    public var hasTitle: Bool
    public var overview: String
    public var thumbnail: String?
    public var watched: Bool
    public var progress: Double?           // a medias
    public var timeLeft: String
    public var leftMinutes: Int
    public var download: DownloadState?
    /// Todavía no sale: cuándo (nil = ya salió o no se sabe). Se ve con su fecha y no se puede reproducir ni bajar.
    public var airs: Date? = nil
}

/// Lo que se sabe de las fuentes del video de «Ver» antes de abrir el reproductor.
public enum SourceCheck: Equatable, Sendable { case unknown, available, none, offline }

/// La ficha de una película o serie: datos en tu idioma, temporadas y episodios con su estado (visto, a medias,
/// descargado), Mi lista (Stremio), watchlist (Trakt) y las acciones de ver y descargar.
@MainActor
public final class TitleModel: ObservableModel {
    public private(set) var kind: String
    public private(set) var metaID: String
    public private(set) var title = "" { didSet { changed() } }
    public private(set) var originalTitle = "" { didSet { changed() } }
    public private(set) var info = MetaInfo(year: "", rating: "", genres: [], description: "", logo: nil, runtime: "") { didSet { changed() } }
    public private(set) var credits = Credits(cast: [], directors: [], writers: [], released: "", awards: "", country: "") { didSet { changed() } }
    public private(set) var poster: String? { didSet { changed() } }
    public private(set) var background: String? { didSet { changed() } }
    public private(set) var seasons: [Season] = [] { didSet { changed() } }
    public private(set) var selectedSeason = 1 { didSet { changed() } }
    public private(set) var rows: [EpisodeRow] = [] { didSet { changed() } }
    public private(set) var inLibrary = false { didSet { changed() } }
    public private(set) var inWatchlist = false { didSet { changed() } }
    /// Tus listas de Trakt y si este título está en cada una («Guardar en…»); `nil` mientras no se han pedido.
    public private(set) var lists: [SavedList]? { didSet { changed() } }
    public private(set) var loadingLists = false { didSet { changed() } }
    /// ¿Está guardado en algún lado? (Mi lista, tu watchlist o una de tus listas): el botón dice «Guardado».
    public var isSaved: Bool { inLibrary || inWatchlist || (lists.map { $0.contains(where: \.contains) } ?? inSomeList) }
    /// Está en alguna de tus listas de Trakt (sin abrir «Guardar en…»; al abrirla manda lo que diga cada lista).
    public private(set) var inSomeList = false { didSet { changed() } }
    public private(set) var traktAvailable = false { didSet { changed() } }
    public private(set) var isLoading = false { didSet { changed() } }
    public private(set) var error: String? { didSet { changed() } }
    public private(set) var message: String? { didSet { changed() } }
    /// La sinopsis que dio tu Orbital (en español cuando puede) y si su logo es oscuro (se pinta blanco); nil si no hay consola.
    public private(set) var consoleOverview: String? { didSet { changed() } }
    public private(set) var logoIsDark = false { didSet { changed() } }
    /// La ficha rica de TMDB (elenco con foto, saga, tráiler…); nil sin clave de TMDB o mientras llega.
    public private(set) var extras: TitleExtras? { didSet { changed() } }
    /// «Lo mejor disponible» entre las fuentes del episodio o película que toca (como el encabezado de Infuse).
    /// Lo mejor que hay (para «Disponible: 4K · Dolby Vision» en los detalles).
    public private(set) var bestSource: Source? { didSet { changed() } }
    /// La que va a sonar al tocar «Ver»: la recomendada (idioma, calidad y tamaño; la primera de «Elegir la fuente»). Su
    /// calidad es la que dice el botón (antes decía la mejor, 4K, y luego sonaba la recomendada en 1080p).
    public private(set) var recommendedSource: Source? { didSet { changed() } }
    /// Si ya se sabe que no hay fuentes (o no hay red), «Ver» lo dice en vez de abrir un reproductor que va a fallar.
    public private(set) var sourceCheck: SourceCheck = .unknown { didSet { changed() } }
    /// La calificación de Trakt (0–10), si alguien votó.
    public private(set) var traktRating: Double? { didSet { changed() } }

    private let services: Services
    private var meta: JSON?                // la ficha ORIGINAL
    private var localized: JSON?
    private var raw: JSON?
    private var watched = Set<String>()
    private var downloadStates: [String: DownloadState] = [:]
    private var downloadProgress: [String: Double] = [:]
    /// Cómo va la descarga de un video de este título (nil: no se ha pedido).
    public func downloadState(_ videoID: String?) -> DownloadState? { videoID.flatMap { downloadStates[$0] } }
    /// Cuánto lleva (0…1) una descarga en curso de este título.
    public func downloadFraction(_ videoID: String?) -> Double? { videoID.flatMap { downloadProgress[$0] } }

    /// Mientras la ficha está abierta: cada cambio de las descargas (avance, terminó, falló) se ve al momento.
    public func followDownloads() async {
        for await items in services.downloads.makeUpdates() { applyDownloads(items) }
    }

    private func applyDownloads(_ items: [DownloadItem]) {
        // Puede haber dos versiones del mismo video («Bajar también esta»): por video se enseña la que más importa (la que
        // está bajando antes que la terminada). Antes se armaba con claves únicas y con dos versiones la app se cerraba.
        var chosen: [String: DownloadItem] = [:]
        for item in items where item.metaID == metaID {
            if let current = chosen[item.videoID], Self.rank(current.state) <= Self.rank(item.state) { continue }
            chosen[item.videoID] = item
        }
        let states = chosen.mapValues(\.state)
        let progress = chosen.compactMapValues(\.progress)
        guard states != downloadStates || progress != downloadProgress else { return }
        let stateChanged = states != downloadStates
        downloadStates = states; downloadProgress = progress
        if stateChanged { buildRows() } else { changed() }
    }

    /// Qué versión de un video se enseña en la ficha: la que bajando, luego en cola, en pausa, lista y, al final, la fallida.
    static func rank(_ state: DownloadState) -> Int {
        switch state {
        case .downloading: 0
        case .queued: 1
        case .paused: 2
        case .done: 3
        case .failed: 4
        }
    }

    public init(_ services: Services, kind: String, metaID: String, hint: (title: String, poster: String?)? = nil) {
        self.services = services; self.kind = kind; self.metaID = metaID
        super.init()
        // El título que se muestra puede venir traducido: el ORIGINAL (lo que se guarda en Stremio) solo sale de Cinemeta, al cargar.
        if let hint { title = hint.title; poster = hint.poster }
        // El fondo de metahub se conoce por el id: el arte empieza a bajar al abrir, no después de Cinemeta y la traducción
        // (3 a 5 viajes de red en una serie). Si Cinemeta trae otro, se cambia al llegar.
        if metaID.hasPrefix("tt") { background = String(format: ForYou.metahubBackground, metaID) }
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        // Lo tuyo en Stremio (avance, vistos) se pide a la vez que la ficha: no espera a Cinemeta ni a la traducción.
        let watch = services.watch, id = metaID
        let state = Task { await watch.rawItem(metaID: id) }
        do {
            let original = try await services.cinemeta.meta(kind: kind, id: metaID)
            meta = original
            // Arte y póster en cuanto llega Cinemeta; el texto traducido llega después.
            poster = CinemetaParsing.medium(original["poster"]?.string) ?? poster
            // Si Cinemeta no trae fondo, tampoco hay en metahub: se cae al póster (no a un hueco).
            if let art = original["background"]?.string, !art.isEmpty { background = art } else { background = nil }
            let local = await services.localizer.meta(kind: kind, meta: original)
            localized = local
            title = local["name"]?.string ?? original["name"]?.string ?? title
            originalTitle = original["name"]?.string ?? title
            info = CinemetaParsing.describe(local)
            credits = CinemetaParsing.credits(local)
            seasons = CinemetaParsing.seasons(local)
            error = nil
        } catch where !Task.isCancelled { self.error = "No pude cargar la ficha. Revisa tu conexión." } catch {}   // cancelado al salir: sin error falso
        await refreshState(prefetched: await state.value)
    }

    /// La sinopsis de la ficha: la de tu Orbital si contestó (viene en español), si no la de Cinemeta de siempre.
    public var overview: String { consoleOverview ?? info.description }

    /// Pide a tu Orbital la sinopsis y el tipo de logo (`/api/foryou/details`). Sin consola o sin respuesta no cambia nada.
    /// Lo de la ficha rica: TMDB (elenco, saga, tráiler, dónde verlo…) y la calificación de Trakt, a la vez.
    public func loadExtras() async {
        guard metaID.hasPrefix("tt") else { return }
        let tmdb = services.tmdb, trakt = services.trakt, kind = kind, metaID = metaID, region = services.appSettings.region
        async let rating = try? trakt?.rating(kind: kind, imdb: metaID)
        if tmdb.configured, let id = try? await tmdb.findID(imdb: metaID, kind: kind) {
            extras = try? await tmdb.extras(kind: kind, tmdbID: id, region: region)
        }
        traktRating = await rating?.rating
    }

    /// Busca las fuentes del video que toca (el mismo pedido que «Elegir fuente», así luego sale de la caché) y se queda con
    /// la mejor para el encabezado. Sin fuentes o sin red, no se enseña nada.
    public func loadBestSource(onCellular: Bool = false) async {
        guard let videoID = continueVideoID else { return }
        let prefs = services.titlePrefs.languages(for: metaID, settings: services.appSettings, onCellular: onCellular).prefs
        do {
            let found = try await services.finder.find(kind: kind, videoID: videoID, prefs: prefs, purpose: .watch)
            guard !Task.isCancelled else { return }
            bestSource = Source.best(found)
            recommendedSource = found.first
            sourceCheck = found.isEmpty ? .none : .available
        } catch {
            if !Task.isCancelled { sourceCheck = error is StreamFinderError ? .offline : .unknown }
        }
    }

    /// Un título de TMDB (recomendación, saga, filmografía) → su id de IMDb, para abrir su ficha.
    public static func imdbID(of title: TmdbTitle, services: Services) async -> String? {
        try? await services.tmdb.details(kind: title.kind, tmdbID: title.tmdbID).imdb
    }

    /// Marca como vistos los episodios de la temporada elegida que te faltan (como «Marcar como visto» en cada uno).
    public func markSeasonWatched() async {
        for row in rows where !row.watched { await markWatched(row.id) }
    }

    /// «4 de 10 vistos» de la temporada elegida.
    public var seasonProgress: (watched: Int, total: Int) { (rows.filter(\.watched).count, rows.count) }

    public func loadConsoleDetails() async {
        let remote = services.orbital
        guard remote.isConfigured, metaID.hasPrefix("tt") else { return }
        guard let json = try? await remote.foryouDetails(key: "video:\(metaID)", kind: kind) else { return }
        if let text = json["overview"]?.nonEmptyString?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty { consoleOverview = text }
        logoIsDark = json["logo_dark"]?.bool ?? false
    }

    /// Lo que cambia viendo, descargando o marcando: lo tuyo en Stremio, Trakt y las descargas.
    public func refreshState() async { await refreshState(prefetched: nil) }

    /// Lo tuyo en Stremio, Trakt y las descargas: las cuatro consultas a la vez.
    private func refreshState(prefetched: JSON??) async {
        let forYou = services.forYou, downloads = services.downloads, watch = services.watch, id = metaID
        async let linked = forYou.traktLinked
        async let keys = forYou.watchlistKeys()
        async let listed = forYou.listKeys()
        async let queue = downloads.all
        if let prefetched { raw = prefetched } else { raw = await watch.rawItem(metaID: id) }
        let ids = meta.map(CinemetaParsing.seasonVideoIDs) ?? []
        watched = StremioLibrary.parseWatched(raw?["state"]?["watched"]?.string, videoIDs: ids)
        inLibrary = StremioLibrary.isInLibrary(raw)
        traktAvailable = await linked
        inWatchlist = await keys.contains(metaID)
        inSomeList = await listed.contains(metaID)
        applyDownloads(await queue)
        if let state = StremioLibrary.state(of: raw)["video_id"]?.string, kind == "series", let season = seasons.first(where: { $0.episodes.contains { $0.id == state } }) { selectedSeason = season.season }
        else if !seasons.contains(where: { $0.season == selectedSeason }) { selectedSeason = seasons.first { !$0.isSpecials }?.season ?? seasons.first?.season ?? 1 }
        buildRows()
    }

    public func select(season: Int) { selectedSeason = season; buildRows() }

    private func buildRows() {
        let state = StremioLibrary.state(of: raw)
        let current = state["video_id"]?.string
        let offset = asInt(state["timeOffset"]), duration = asInt(state["duration"])
        rows = (seasons.first { $0.season == selectedSeason }?.episodes ?? []).map { ep in
            let ongoing = ep.id == current && offset > 1 && duration > 0
            let seasonNumber = selectedSeason
            return EpisodeRow(id: ep.id, season: seasonNumber, number: ep.episode, title: ep.title, hasTitle: ep.hasTitle, overview: ep.overview, thumbnail: ep.thumbnail,
                              watched: watched.contains(ep.id), progress: ongoing ? min(1, Double(offset) / Double(duration)) : nil,
                              timeLeft: ongoing ? PlaybackRules.timeLeft(Double(duration - offset) / 1000) : "",
                              leftMinutes: ongoing ? PlaybackRules.minutesLeft(Double(duration - offset) / 1000) : 0, download: downloadStates[ep.id],
                              airs: Self.airDate(ep.released))
        }
    }

    // MARK: ver
    /// El video con el que sigue el botón principal: donde ibas, o el primer episodio.
    public var continueVideoID: String? {
        let state = StremioLibrary.state(of: raw)
        if let video = state["video_id"]?.nonEmptyString, asInt(state["timeOffset"]) > 0 || kind == "series" { return video }
        if kind == "movie" { return metaID }
        return seasons.first { !$0.isSpecials }?.episodes.first?.id
    }

    /// «Continuar T2 E5» / «Reproducir» / «Reproducir T1 E1».
    public var continueLabel: (isResume: Bool, season: Int?, episode: Int?) {
        guard let video = continueVideoID else { return (false, nil, nil) }
        let state = StremioLibrary.state(of: raw)
        let resume = state["video_id"]?.string == video && asInt(state["timeOffset"]) > 1
        if kind == "series" {
            let numbers = StremioLibrary.episodeNumbers(videoID: video, metaID: metaID)
            if let s = numbers.season, let e = numbers.episode { return (resume, s, e) }
        }
        return (resume, nil, nil)
    }

    /// Minutos para acabar lo que pone el botón principal: lo que falta si vas a medias, si no la duración (de la película o
    /// del episodio típico de la serie). nil si no se sabe. Con esto la ficha dice «terminas a las 23:21».
    public var minutesToFinish: Int? {
        guard continueVideoID != nil else { return nil }
        let state = StremioLibrary.state(of: raw)
        let duration = asInt(state["duration"]), offset = asInt(state["timeOffset"])
        if continueLabel.isResume, duration > offset, offset > 0 { return max(1, PlaybackRules.minutesLeft(Double(duration - offset) / 1000)) }
        let runtime = Int(CinemetaParsing.runtimeSeconds(info.runtime) / 60)
        return runtime > 0 ? runtime : nil
    }

    /// Cuánto llevas visto de lo que pone el botón principal (0…1); nil si no ibas a medias.
    public var resumeFraction: Double? {
        guard continueLabel.isResume else { return nil }
        let state = StremioLibrary.state(of: raw)
        let duration = asInt(state["duration"]), offset = asInt(state["timeOffset"])
        guard duration > 0, offset > 0 else { return nil }
        return min(1, Double(offset) / Double(duration))
    }

    public func playRequest(videoID: String? = nil, fromStart: Bool = false) -> PlayRequest? {
        guard let video = videoID ?? continueVideoID else { return nil }
        var label = ""
        if kind == "series", let found = episode(video) { label = services.episodeLabel(found.0, found.1.episode) + (found.1.hasTitle ? " · \(found.1.title)" : "") }
        return PlayRequest(kind: kind, metaID: metaID, videoID: video, originalTitle: originalTitle, displayTitle: title, episodeLabel: label,
                           poster: poster, year: info.year, meta: meta, fromStart: fromStart)
    }

    /// La fecha de estreno si todavía no llega («2026-10-23T02:00:00.000Z»).
    static func airDate(_ released: String?, now: Date = Date()) -> Date? {
        guard let released else { return nil }
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        guard let date = iso.date(from: released) ?? plain.date(from: released), date > now else { return nil }
        return date
    }

    /// El video de «Ver» todavía no sale: cuándo.
    public var continueAirs: Date? { continueVideoID.flatMap { episode($0)?.1.released }.flatMap { Self.airDate($0) } }

    private func episode(_ id: String) -> (Int, Episode)? {
        for season in seasons { if let ep = season.episodes.first(where: { $0.id == id }) { return (season.season, ep) } }
        return nil
    }

    // MARK: Mi lista y watchlist
    public func toggleLibrary() async {
        let target = !inLibrary
        inLibrary = target
        do { try await services.watch.setInLibrary(kind: kind, metaID: metaID, title: originalTitle, poster: poster, add: target) }
        catch { inLibrary = !target; message = "No pude cambiar tu lista de Stremio: \(error)" }
    }

    public func toggleWatchlist() async {
        guard let trakt = services.trakt, trakt.linked, metaID.hasPrefix("tt") else { return }
        let want = !inWatchlist
        inWatchlist = want
        do {
            try await trakt.setWatchlist(imdb: metaID, series: kind == "series", add: want)
            await services.forYou.clearCache()
        } catch { inWatchlist = !want; message = "No pude cambiar tu watchlist de Trakt: \(error)" }
    }

    // MARK: tus listas de Trakt
    /// Tus listas y en cuáles está este título (una consulta por lista: suelen ser pocas).
    public func loadLists() async {
        guard let trakt = services.trakt, trakt.linked, metaID.hasPrefix("tt") else { lists = []; return }
        loadingLists = true
        defer { loadingLists = false }
        let all = (try? await trakt.lists()) ?? []
        let id = metaID
        lists = await withTaskGroup(of: (Int, SavedList).self) { group in
            for (i, l) in all.enumerated() {
                group.addTask { (i, SavedList(id: l.id, name: l.name, contains: ((try? await trakt.listMembers(l.id)) ?? []).contains(id))) }
            }
            var out: [(Int, SavedList)] = []
            for await r in group { out.append(r) }
            return out.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    public func toggleList(_ listID: String) async {
        guard let trakt = services.trakt, var all = lists, let i = all.firstIndex(where: { $0.id == listID }) else { return }
        let want = !all[i].contains
        all[i].contains = want
        lists = all
        do {
            try await trakt.setListItem(listID: listID, imdb: metaID, series: kind == "series", add: want)
            await services.forYou.clearCache()
        } catch {
            if var back = lists, let j = back.firstIndex(where: { $0.id == listID }) { back[j].contains = !want; lists = back }
            message = "No pude cambiar tu lista de Trakt: \(error)"
        }
    }

    /// Una lista nueva en Trakt, ya con este título.
    public func createList(named name: String) async {
        guard let trakt = services.trakt, trakt.linked else { return }
        do {
            let made = try await trakt.createList(name: name)
            lists = (lists ?? []) + [SavedList(id: made.id, name: made.name, contains: false)]
            await toggleList(made.id)
        } catch { message = "No pude crear la lista: \(error)" }
    }

    /// Marca un episodio (o la película) como visto en Stremio y en Trakt. Se relee el item antes de escribir: lo que
    /// hayas hecho en otro dispositivo no se pisa, y marcar un episodio anterior no mueve tu punto de «Seguir viendo».
    public func markWatched(_ videoID: String) async {
        do { try await services.watch.markWatched(kind: kind, metaID: metaID, videoID: videoID) } catch { message = "No pude marcarlo: \(error)"; return }
        if let trakt = services.trakt, trakt.linked, let target = TraktTarget(videoID: videoID, kind: kind) { _ = try? await trakt.addToHistory(target, watchedAt: Date()) }
        await refreshState()
    }

    // MARK: descargar
    public enum DownloadOutcome: Equatable { case queued(Int), noSources, notEnoughSpace(String), already, failed(String) }

    /// Descarga uno o varios episodios con la fuente que mejor sirve para guardar (1080p, moderada).
    @discardableResult
    public func download(_ videoIDs: [String], source: Source? = nil, replace: Bool = false, keepBoth: Bool = false) async -> DownloadOutcome {
        var queued = 0
        for video in videoIDs {
            var label = ""
            if let found = episode(video) { label = services.episodeLabel(found.0, found.1.episode) + (found.1.hasTitle ? " · \(found.1.title)" : "") }
            switch await services.queueDownload(kind: kind, metaID: metaID, videoID: video, title: title, originalTitle: originalTitle, subtitle: label, poster: poster, source: source, replace: replace, keepBoth: keepBoth) {
            case .queued: queued += 1
            case .noSources: if queued == 0 { return .noSources } else { continue }
            case .already: if videoIDs.count == 1 { return .already } else { continue }
            case .notEnoughSpace(let message): return .notEnoughSpace(message)
            case .failed(let message): return .failed(message)
            }
        }
        await refreshState()
        return queued > 0 ? .queued(queued) : .noSources
    }

    /// «Descargar los siguientes N episodios».
    public func downloadNext(_ count: Int) async -> DownloadOutcome {
        let from = continueVideoID
        let ids = seasons.filter { !$0.isSpecials }.flatMap { $0.episodes.map(\.id) }
        guard let from, let i = ids.firstIndex(of: from) else { return .noSources }
        return await download(Array(ids.dropFirst(i).prefix(count)))
    }

    /// Seguir una descarga en pausa o que falló (donde iba, con la misma fuente), en vez de empezarla de cero.
    public func resumeDownload(_ videoID: String) async {
        await services.downloads.resume(DownloadItem.makeID(metaID: metaID, videoID: videoID))
        await refreshState()
    }

    /// Pausar o cancelar (borrar lo bajado) una descarga de este título.
    public func pauseDownload(_ videoID: String) async {
        await services.downloads.pause(DownloadItem.makeID(metaID: metaID, videoID: videoID))
        await refreshState()
    }

    public func cancelDownload(_ videoID: String) async {
        await services.downloads.remove(DownloadItem.makeID(metaID: metaID, videoID: videoID))
        await refreshState()
    }

    /// «T2 E5» de un episodio de esta serie; nil en una película.
    public func episodeLabel(_ videoID: String) -> String? {
        guard kind == "series", let found = episode(videoID) else { return nil }
        return services.episodeLabel(found.0, found.1.episode)
    }

    /// El video que bajaría «Descargar» de un toque: la película, o el episodio que sigue en una serie.
    public var downloadTarget: String? { kind == "movie" ? metaID : continueVideoID }

    /// La copia que ya tienes (o se está bajando) de este video, para preguntar antes de cambiarla por otra fuente.
    public func existingDownload(_ videoID: String) async -> DownloadItem? { await services.downloads.item(DownloadItem.makeID(metaID: metaID, videoID: videoID)) }

    public func clearMessage() { message = nil }
}

/// Una de tus listas de Trakt, con si el título que ves está en ella.
public struct SavedList: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public var contains: Bool
}
