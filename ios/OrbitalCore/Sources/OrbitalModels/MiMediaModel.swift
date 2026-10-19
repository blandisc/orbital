import Foundation
import OrbitalCore

/// Descargas › Mi media: tu carpeta de OneDrive como biblioteca (como Infuse). Lo más reciente primero, filtros, sagas,
/// lo que no se reconoció (para corregirlo) y lo que ya bajaste al iPhone.
@MainActor
public final class MiMediaModel: ObservableModel {
    public enum Filter: String, CaseIterable, Sendable { case all, movies, series, unwatched }
    public enum Sort: String, CaseIterable, Sendable { case added, name }

    /// Una saga con al menos dos de tus películas («Dune: colección»).
    public struct Saga: Sendable, Equatable, Identifiable {
        public var id: Int
        public var name: String
        public var titles: [OneDriveLibrary.Title]
    }

    public private(set) var all: [OneDriveLibrary.Title] = [] { didSet { changed() } }
    public private(set) var unmatched: [OneDriveFile] = [] { didSet { changed() } }
    public private(set) var scannedAt: Date? { didSet { changed() } }
    public private(set) var scanning = false { didSet { changed() } }
    public private(set) var error: String? { didSet { changed() } }
    public private(set) var watched: Set<String> = [] { didSet { changed() } }
    /// Los videos que ya están (o se están bajando) en el iPhone: videoID → avance (1 = listo).
    public private(set) var onPhone: [String: Double] = [:] { didSet { changed() } }
    public private(set) var sagas: [Saga] = [] { didSet { changed() } }
    public var filter: Filter = .all { didSet { changed() } }
    public var sort: Sort = .added { didSet { changed() } }

    /// Cuánto tiempo algo cuenta como «Nuevo».
    public static let newFor: TimeInterval = 14 * 86_400
    static let sagasKey = "onedrive-sagas"

    private let services: Services
    public init(_ services: Services) {
        self.services = services
        super.init()
        reload()
    }

    public var ready: Bool { services.oneDriveLibrary.ready }
    public var folder: String { services.appSettings.oneDriveFolder }
    public var movies: Int { all.filter { $0.kind == "movie" }.count }
    public var series: Int { all.filter { $0.kind == "series" }.count }

    /// Lo que se ve con el filtro y el orden elegidos.
    public var shown: [OneDriveLibrary.Title] {
        let filtered = all.filter { t in
            switch filter {
            case .all: return true
            case .movies: return t.kind == "movie"
            case .series: return t.kind == "series"
            case .unwatched: return !watched.contains(t.imdb)
            }
        }
        switch sort {
        case .added: return filtered
        case .name: return filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    /// «Recién agregado»: lo de las últimas dos semanas (hasta 12).
    public var recent: [OneDriveLibrary.Title] {
        let now = services.now()
        return Array(all.filter { ($0.added.map { now.timeIntervalSince($0) < Self.newFor }) ?? false }.prefix(12))
    }

    public func isNew(_ title: OneDriveLibrary.Title) -> Bool {
        title.added.map { services.now().timeIntervalSince($0) < Self.newFor } ?? false
    }

    /// Cuántos de sus videos ya están en el iPhone (película: 1 si alguna versión; serie: episodios).
    public func onPhoneCount(_ title: OneDriveLibrary.Title) -> Int {
        Set(title.entries.map(\.videoID)).filter { (onPhone[$0] ?? 0) >= 1 }.count
    }

    public func reload() {
        let library = services.oneDriveLibrary
        all = library.titles()
        unmatched = library.saved?.unmatchedFiles ?? []
        scannedAt = library.saved?.scannedAt
    }

    /// Al abrir: lo guardado al instante; luego lo que esté viejo se revisa, lo visto (Trakt) y lo que ya está en el iPhone.
    public func load() async {
        reload()
        if await services.oneDriveLibrary.refreshIfStale() { reload() }
        await refreshPhone()
        if let trakt = services.trakt, trakt.linked, let ids = try? await trakt.watchedIDs() { watched = ids }
        await loadSagas()
    }

    public func refreshPhone() async {
        var found: [String: Double] = [:]
        for item in await services.downloads.all where item.addon == OneDriveLibrary.addonName || all.contains(where: { $0.imdb == item.metaID }) {
            found[item.videoID] = item.state == .done ? 1 : (item.progress ?? 0)
        }
        onPhone = found
    }

    public func rescan() async {
        guard ready else { return }
        scanning = true; error = nil
        defer { scanning = false }
        do { _ = try await services.oneDriveLibrary.scan(); reload(); await loadSagas() }
        catch let e as OneDriveError { error = e.description }
        catch { self.error = "\(error)" }
    }

    /// Sagas (TMDB): cada película se pregunta una vez y se recuerda; solo salen las que tienen dos o más tuyas.
    func loadSagas() async {
        let tmdb = services.tmdb
        guard tmdb.configured else { return }
        var known = services.kv.data(Self.sagasKey).flatMap { try? JSONDecoder().decode([String: SagaRef].self, from: $0) } ?? [:]
        var asked = false
        for t in all where t.kind == "movie" && known[t.imdb] == nil {
            let found: (id: Int, name: String)?
            do { found = try await tmdb.collection(imdb: t.imdb) } catch { continue }   // sin red: se vuelve a preguntar después
            known[t.imdb] = SagaRef(id: found?.id ?? 0, name: found?.name ?? "")
            asked = true
        }
        if asked { services.kv.set(Self.sagasKey, data: try? JSONEncoder().encode(known)) }
        var groups: [Int: Saga] = [:]
        for t in all where t.kind == "movie" {
            guard let ref = known[t.imdb], ref.id > 0 else { continue }
            groups[ref.id, default: Saga(id: ref.id, name: ref.name, titles: [])].titles.append(t)
        }
        sagas = groups.values.filter { $0.titles.count >= 2 }.sorted { $0.name < $1.name }
    }

    struct SagaRef: Codable { var id: Int; var name: String }

    // MARK: un título
    /// Las temporadas de una serie con lo que tienes y lo que falta (los episodios ya estrenados que no están en tu carpeta).
    public struct EpisodeRow: Sendable, Equatable, Identifiable {
        public var episode: Episode
        public var season: Int
        public var versions: [OneDriveLibrary.Entry]
        public var id: String { episode.id }
        public var missing: Bool { versions.isEmpty }
    }

    public func episodes(_ title: OneDriveLibrary.Title) async -> [(season: Int, rows: [EpisodeRow])] {
        let have = Dictionary(grouping: title.entries, by: \.videoID)
        guard let meta = try? await services.cinemeta.meta(kind: "series", id: title.imdb) else {
            // Sin la ficha: solo lo que tienes, por temporada.
            let bySeason = Dictionary(grouping: title.entries) { $0.file.info.season ?? 0 }
            return bySeason.keys.sorted().map { s in
                (s, (bySeason[s] ?? []).sorted { ($0.file.info.episode ?? 0) < ($1.file.info.episode ?? 0) }.map { e in
                    EpisodeRow(episode: Episode(id: e.videoID, episode: e.file.info.episode ?? 0, title: "", thumbnail: nil, overview: "", released: nil, hasTitle: false),
                               season: s, versions: have[e.videoID] ?? [])
                })
            }
        }
        let now = services.now()
        let seasons = CinemetaParsing.seasons(meta).filter { !$0.isSpecials }
        // Solo las temporadas de las que tienes algo (una serie de 20 temporadas con una sola tuya no se llena de faltantes).
        let mine = Set(title.entries.compactMap(\.file.info.season))
        return seasons.filter { mine.contains($0.season) }.map { season in
            (season.season, season.episodes.compactMap { ep in
                let versions = (have[ep.id] ?? []).sorted(by: OneDriveLibrary.better)
                if versions.isEmpty, let released = ep.released.flatMap(Self.date), released > now { return nil }   // aún no sale
                return EpisodeRow(episode: ep, season: season.season, versions: versions)
            })
        }
    }

    static func date(_ text: String) -> Date? { ISO8601DateFormatter().date(from: text) ?? ISO8601DateFormatter().date(from: text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)) }

    /// Para ver: el pedido del reproductor con tu copia primero (también para el siguiente episodio).
    public func playRequest(_ title: OneDriveLibrary.Title, videoID: String, version: OneDriveLibrary.Entry? = nil, fromStart: Bool = false) async -> PlayRequest {
        let meta = try? await services.cinemeta.meta(kind: title.kind, id: title.imdb)
        var label = ""
        if title.kind == "series", let meta { label = DownloadsModel.episodeLabel(videoID, meta: meta, services: services) }
        var request = PlayRequest(kind: title.kind, metaID: title.imdb, videoID: videoID, originalTitle: title.name, displayTitle: title.name,
                                  episodeLabel: label, poster: title.poster, year: title.year, meta: meta, fromStart: fromStart)
        request.ownCopy = true
        request.sourceIndex = version?.details.index
        return request
    }

    /// Bajar al iPhone: la versión que mejor sirve para el teléfono (1080p), o la que elegiste.
    public func download(_ title: OneDriveLibrary.Title, videoID: String, entry: OneDriveLibrary.Entry? = nil) async -> TitleModel.DownloadOutcome {
        let library = services.oneDriveLibrary
        guard let pick = entry ?? library.pick(videoID, purpose: .download) else { return .noSources }
        guard let source = try? await library.source(pick) else { return .failed("No pude pedir el archivo a OneDrive.") }
        var subtitle = ""
        if title.kind == "series", let meta = try? await services.cinemeta.meta(kind: "series", id: title.imdb) {
            subtitle = DownloadsModel.episodeLabel(videoID, meta: meta, services: services)
        }
        let outcome = await services.queueDownload(kind: title.kind, metaID: title.imdb, videoID: videoID, title: title.name, originalTitle: title.name,
                                                   subtitle: subtitle, poster: title.poster, source: source)
        await refreshPhone()
        return outcome
    }

    /// «Corregir ficha»: buscar por nombre (del mismo tipo) y elegir.
    public func search(_ query: String, kind: String) async -> [SearchResult] {
        ((try? await services.cinemeta.searchAll(query, limit: 20)) ?? []).filter { $0.kind == kind && $0.metaID.hasPrefix("tt") }
    }

    public func fix(_ info: OneDriveName, to result: SearchResult) async {
        await services.oneDriveLibrary.fix(info, to: OneDriveLibrary.Fix(imdb: result.metaID, name: result.title, poster: result.poster, year: result.year))
        reload()
        await loadSagas()
    }

    /// La vista de carpetas.
    public func listing(_ path: String) async throws -> (folders: [OneDriveFolder], videos: [OneDriveFile]) {
        try await services.oneDriveLibrary.listing(path.isEmpty ? folder : path)
    }

    /// Un video de la vista de carpetas, tal cual (aunque no tenga ficha).
    public func playRequest(file: OneDriveFile) async throws -> PlayRequest {
        let url = try await services.oneDriveLibrary.url(of: file)
        return PlayRequest(kind: "movie", metaID: "file:\(file.id)", videoID: "file:\(file.id)", originalTitle: file.info.title, displayTitle: file.info.title, localFile: url)
    }
}
