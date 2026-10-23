import Foundation
import OrbitalCore

/// Lo descargado de un mismo título (una película, o los episodios de una serie): un renglón en Descargas.
public struct DownloadGroup: Identifiable, Equatable, Sendable {
    public var id: String { metaID }
    public var metaID: String, kind: String, title: String, poster: String?
    public var items: [DownloadItem]
    public var bytes: Int64 { items.reduce(0) { $0 + $1.writtenBytes } }

    /// Agrupa por título en el orden en que llegaron (lo más reciente primero dentro de cada grupo se respeta tal cual).
    public static func group(_ items: [DownloadItem]) -> [DownloadGroup] {
        var order: [String] = [], groups: [String: DownloadGroup] = [:]
        for item in items {
            if groups[item.metaID] == nil {
                order.append(item.metaID)
                groups[item.metaID] = DownloadGroup(metaID: item.metaID, kind: item.kind, title: item.title, poster: item.poster, items: [])
            }
            groups[item.metaID]?.items.append(item)
        }
        // Los episodios de una serie en orden (T1 E1, T1 E2…), no en el orden en que se bajaron.
        return order.compactMap { id in
            groups[id].map { g in
                var sorted = g
                sorted.items.sort { episodeKey($0.videoID) < episodeKey($1.videoID) }
                return sorted
            }
        }
    }

    /// Una serie por temporadas (en orden). Una película, o episodios sin temporada, quedan en la temporada 0.
    public var seasons: [DownloadSeason] {
        var order: [Int] = [], bySeason: [Int: [DownloadItem]] = [:]
        for item in items {
            let season = Self.episodeKey(item.videoID).0
            if bySeason[season] == nil { order.append(season) }
            bySeason[season, default: []].append(item)
        }
        return order.sorted().map { DownloadSeason(metaID: metaID, number: $0, items: bySeason[$0] ?? []) }
    }

    /// «tt0386676:2:5» → (2, 5); una película o un id sin temporada va primero.
    static func episodeKey(_ videoID: String) -> (Int, Int) {
        let parts = videoID.split(separator: ":")
        guard parts.count >= 3, let s = Int(parts[parts.count - 2]), let e = Int(parts[parts.count - 1]) else { return (0, 0) }
        return (s, e)
    }
}

/// Una temporada descargada de una serie: sus episodios en orden y cuánto ocupan.
public struct DownloadSeason: Identifiable, Equatable, Sendable {
    public var id: String { "\(metaID):\(number)" }
    public var metaID: String
    public var number: Int
    public var items: [DownloadItem]
    public var bytes: Int64 { items.reduce(0) { $0 + $1.writtenBytes } }
}

@MainActor
public final class DownloadsModel: ObservableModel {
    public private(set) var items: [DownloadItem] = [] { didSet { changed() } }
    public private(set) var freeBytes: Int64 = 0 { didSet { changed() } }
    /// Bytes por segundo de cada descarga que está bajando (promedio suave de los últimos segundos).
    public private(set) var speeds: [String: Double] = [:]
    private var samples: [String: (bytes: Int64, at: Date)] = [:]
    private let services: Services
    private let freeSpace: @Sendable () -> Int64

    public init(_ services: Services, freeSpace: @escaping @Sendable () -> Int64) {
        self.services = services; self.freeSpace = freeSpace
        super.init()
    }

    /// Escucha los cambios de la cola (la pantalla lo lanza en una tarea mientras está abierta).
    public func run() async {
        items = await services.downloads.all
        freeBytes = freeSpace()
        // El avance llega muchas veces por segundo: se pinta como mucho cada `progressInterval`; un cambio de verdad (una
        // descarga nueva, en pausa, terminada o borrada) se pinta en el acto.
        var lastPaint = Date.distantPast
        for await snapshot in services.downloads.makeUpdates() {
            let now = Date()
            let snapshot = snapshot.filter { !deleting.contains($0.id) }
            if Self.shape(snapshot) == Self.shape(items), now.timeIntervalSince(lastPaint) < Self.progressInterval { continue }
            measure(snapshot, at: now)
            items = snapshot; freeBytes = freeSpace(); lastPaint = now
        }
    }

    /// La velocidad: lo bajado entre dos muestras de al menos un segundo, suavizado (no brinca con cada avance).
    func measure(_ snapshot: [DownloadItem], at now: Date) {
        var next: [String: Double] = [:]
        for item in snapshot where item.state == .downloading && !item.waitingForNetwork {
            guard let last = samples[item.id] else { samples[item.id] = (item.writtenBytes, now); continue }
            let elapsed = now.timeIntervalSince(last.at)
            guard elapsed >= Self.speedWindow else { if let old = speeds[item.id] { next[item.id] = old }; continue }
            let rate = max(0, Double(item.writtenBytes - last.bytes) / elapsed)
            next[item.id] = speeds[item.id].map { $0 * (1 - Self.speedSmoothing) + rate * Self.speedSmoothing } ?? rate
            samples[item.id] = (item.writtenBytes, now)
        }
        samples = samples.filter { id, _ in snapshot.contains { $0.id == id && $0.state == .downloading } }
        speeds = next
    }

    static let speedWindow = 1.0, speedSmoothing = 0.4

    /// Cuánto falta (segundos) a la velocidad de ahora.
    public func secondsLeft(_ item: DownloadItem) -> Double? {
        guard let speed = speeds[item.id], speed > 0, let expected = item.expectedBytes, expected > item.writtenBytes else { return nil }
        return Double(expected - item.writtenBytes) / speed
    }

    /// Cada cuánto se pinta el avance (segundos).
    static let progressInterval = 0.5
    private static func shape(_ items: [DownloadItem]) -> [String] { items.map { "\($0.id)|\($0.state)" } }

    public var active: [DownloadItem] { items.filter { $0.state != .done } }
    public var ready: [DownloadItem] { items.filter { $0.state == .done } }
    /// Lo listo para ver, agrupado por título (los episodios de una serie en un solo renglón).
    public var readyGroups: [DownloadGroup] { DownloadGroup.group(ready) }
    /// Lo listo, separado: series (cada una, una fila; dentro, sus temporadas) y películas.
    public var readySeries: [DownloadGroup] { readyGroups.filter { $0.kind == "series" } }
    public var readyMovies: [DownloadGroup] { readyGroups.filter { $0.kind != "series" } }
    public var usedBytes: Int64 { items.reduce(0) { $0 + $1.writtenBytes } }

    public func pause(_ id: String) async { await services.downloads.pause(id) }
    public func resume(_ id: String) async { await services.downloads.resume(id) }
    public func remove(_ id: String) async { await services.downloads.remove(id); Self.clearShared() }

    /// Borrar desde la lista: el renglón se quita en el acto (el «Borrar» de deslizar lo anima al momento y la lista truena si
    /// el dato sigue ahí o regresa con el siguiente avance) y el archivo se borra después.
    public func delete(_ ids: [String]) {
        let ids = Set(ids)
        guard !ids.isEmpty else { return }
        deleting.formUnion(ids)
        items.removeAll { ids.contains($0.id) }
        Task {
            for id in ids { await remove(id) }
            deleting.subtract(ids)
        }
    }
    private var deleting: Set<String> = []

    /// «Buscar subtítulos» de una descarga: lo que hay en OpenSubtitles y tus complementos, con la huella del archivo (los de
    /// esa copia exacta primero).
    public func subtitleOptions(_ item: DownloadItem) async -> [SubtitleOption] {
        let file = await services.downloads.fileURL(item)
        return await services.finder.subtitleOptions(kind: item.kind, videoID: item.videoID, file: FileFingerprint.of(file))
    }

    /// Baja ese subtítulo y lo guarda con la descarga (sin conexión también sale). Nombre «es-2.srt»: el reproductor elige por
    /// el idioma del principio del nombre.
    public func saveSubtitle(_ item: DownloadItem, _ option: SubtitleOption) async -> Bool {
        guard let response = try? await services.http.send(HTTPRequest(url: option.url, timeout: 20)), response.status == 200, !response.data.isEmpty else { return false }
        let two = Streams.languageCodes.first { $0.value == option.language }?.key ?? option.language
        let count = item.subtitleFiles.filter { ($0 as NSString).lastPathComponent.hasPrefix(two) }.count
        return await services.downloads.addSubtitle(id: item.id, name: "\(two)-\(count + 1).srt", data: response.data)
    }

    /// Donde se ponen los enlaces para compartir. Se vacía al borrar una descarga y al abrir la app: un enlace olvidado
    /// mantenía ocupados los gigas del archivo borrado.
    public static let sharedFolder = FileManager.default.temporaryDirectory.appendingPathComponent("Compartir", isDirectory: true)
    public static func clearShared() { try? FileManager.default.removeItem(at: sharedFolder) }

    /// El archivo para compartir (AirDrop, Archivos, otra app) con un nombre que se entiende («Dune (1080p).mkv»): un enlace
    /// duro en la carpeta temporal, sin copiar los gigas.
    public func exportURL(_ item: DownloadItem) async -> URL? {
        let file = await services.downloads.fileURL(item)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let base = [item.title, item.subtitle.isEmpty ? nil : item.subtitle].compactMap { $0 }.joined(separator: " · ")
        let name = (item.quality.map { "\(base) (\($0))" } ?? base).replacingOccurrences(of: "/", with: "-")
        let folder = Self.sharedFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let link = folder.appendingPathComponent(name).appendingPathExtension(file.pathExtension)
        try? FileManager.default.removeItem(at: link)
        do { try FileManager.default.linkItem(at: file, to: link); return link } catch { return file }
    }

    /// Para ver una descarga sin conexión.
    public func playRequest(_ item: DownloadItem) async -> PlayRequest { await Self.playRequest(item, services: services) }

    /// Lo mismo, para quien no tiene la pantalla de Descargas a mano (Mi media: lo que ya está en el iPhone se ve de ahí).
    public static func playRequest(_ item: DownloadItem, services: Services) async -> PlayRequest {
        let file = await services.downloads.fileURL(item)
        let subs = item.subtitleFiles.map { file.deletingLastPathComponent().appendingPathComponent($0) }
        // La ficha (para el siguiente episodio y los datos) es opcional: sin red o con una que no contesta (Wi‑Fi del avión),
        // no se espera más de unos segundos para ver lo que ya está en el teléfono.
        let cinemeta = services.cinemeta, kind = item.kind, id = item.metaID
        let meta = await withTaskGroup(of: JSON?.self) { group -> JSON? in
            group.addTask { try? await cinemeta.meta(kind: kind, id: id) }
            group.addTask { try? await Task.sleep(nanoseconds: UInt64(Self.offlineMetaWait * 1_000_000_000)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        return PlayRequest(kind: item.kind, metaID: item.metaID, videoID: item.videoID, originalTitle: item.originalTitle, displayTitle: item.title,
                           episodeLabel: item.subtitle, poster: item.poster, meta: meta, localFile: file, localSubtitles: subs,
                           savedSubtitles: item.allSavedSubtitles)
    }
    /// Cuánto se espera la ficha antes de ver una descarga sin ella (segundos).
    static let offlineMetaWait = 3.0

    /// «T2 · E6 · Halloween» para una descarga (sin esto, varios episodios de la misma serie se ven iguales en la lista).
    static func episodeLabel(_ videoID: String, meta: JSON, services: Services) -> String {
        for season in CinemetaParsing.seasons(meta) {
            if let episode = season.episodes.first(where: { $0.id == videoID }) {
                return services.episodeLabel(season.season, episode.episode) + (episode.hasTitle ? " · \(episode.title)" : "")
            }
        }
        return ""
    }

    /// Al terminar de ver un episodio descargado: se baja el siguiente si lo pediste, y se borra lo visto si lo pediste.
    public func afterWatching(_ item: DownloadItem) async {
        let settings = services.appSettings
        if settings.autoNextDownload, item.kind == "series", let meta = try? await services.cinemeta.meta(kind: item.kind, id: item.metaID) {
            for next in await services.downloads.nextToDownload(metaID: item.metaID, meta: meta) {
                let langs = services.titlePrefs.languages(for: item.metaID, settings: settings)
                // De Mi media: el siguiente también de tu OneDrive (si lo tienes); si no, de Real-Debrid.
                let own = item.addon == OneDriveLibrary.addonName ? await services.oneDriveLibrary.source(next, purpose: .download) : nil
                var found = own
                if found == nil { found = try? await services.finder.best(kind: item.kind, videoID: next, prefs: langs.prefs, purpose: .download) }
                guard let source = found, let url = source.playbackURL else { continue }
                let download = DownloadItem(id: DownloadItem.makeID(metaID: item.metaID, videoID: next), kind: item.kind, metaID: item.metaID, videoID: next, title: item.title,
                                            originalTitle: item.originalTitle, subtitle: Self.episodeLabel(next, meta: meta, services: services), poster: item.poster, addon: source.addon, release: source.release, sourceIndex: source.index,
                                            expectedBytes: source.size > 0 ? Int64(source.size) : nil,
                                            relativePath: DownloadFiles.relativePath(metaID: item.metaID, videoID: next, ext: DownloadFiles.fileExtension(for: url)),
                                            createdAt: Date().timeIntervalSince1970)
                try? await services.downloads.enqueue(download, url: url)
            }
        }
        if settings.deleteWhenWatched { await services.downloads.remove(item.id) }
    }
}
