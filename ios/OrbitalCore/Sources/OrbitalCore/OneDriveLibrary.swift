import Foundation

/// Mi media: tu carpeta de OneDrive ya reconocida. Cada video con su ficha (IMDb), agrupado por título y con sus
/// versiones (4K para la TV, 1080p para bajar), como en Infuse. Se guarda en el teléfono y se vuelve a revisar cada
/// `staleAfter` (o cuando lo pides). Lo que no se reconoce se corrige a mano («Corregir ficha») y se recuerda.
public actor OneDriveLibrary {
    public static let staleAfter: TimeInterval = 6 * 3600
    static let key = "onedrive-index"
    static let fixesKey = "onedrive-fixes"
    /// El nombre de la fuente (en las descargas, de dónde vino).
    public static let addonName = "OneDrive"

    public struct Entry: Sendable, Equatable, Codable {
        public var file: OneDriveFile
        public var imdb: String
        public var kind: String
        /// El nombre y el póster de su ficha (Cinemeta), para no pedirlos otra vez.
        public var name: String?
        public var poster: String?
        public var year: String?
        /// El id del video como lo pide Stremio: «tt123» (película) o «tt123:1:3» (episodio).
        public var videoID: String { kind == "series" ? "\(imdb):\(file.info.season ?? 0):\(file.info.episode ?? 0)" : imdb }
        /// Lo que dice el nombre del archivo: resolución, HDR, sonido, idioma (como las fuentes de los complementos).
        public var details: Source { OneDriveLibrary.describe(file) }
    }

    public struct Index: Sendable, Equatable, Codable {
        public var folder: String
        public var scannedAt: Date
        public var entries: [Entry]
        /// Videos que no se pudieron emparejar con una ficha (por su nombre).
        public var unmatched: Int
        public var unmatchedFiles: [OneDriveFile]?
    }

    /// Una ficha elegida a mano para un nombre («Corregir ficha»): vale para todos los archivos con ese nombre (una serie entera).
    public struct Fix: Sendable, Equatable, Codable {
        public var imdb: String, name: String, poster: String?, year: String?
        public init(imdb: String, name: String, poster: String?, year: String?) { self.imdb = imdb; self.name = name; self.poster = poster; self.year = year }
    }

    /// Un título de Mi media: sus archivos (versiones de una película o episodios de una serie).
    public struct Title: Sendable, Equatable, Identifiable {
        public var imdb: String
        public var kind: String
        public var name: String
        public var year: String?
        public var poster: String
        public var added: Date?
        public var entries: [Entry]
        public var id: String { "\(kind):\(imdb)" }
        /// La mejor calidad que tienes («4K», «1080p»).
        public var bestResolution: String { entries.map(\.details.resolution).min { OneDriveLibrary.rank($0) < OneDriveLibrary.rank($1) } ?? "" }
        public var bytes: Int { entries.reduce(0) { $0 + $1.file.size } }
    }

    private let drive: OneDrive
    private let cinemeta: Cinemeta
    private let kv: KeyValueStore
    private let folder: @Sendable () -> String
    private let clock: @Sendable () -> Date
    private var scanning: Task<Index, Error>?

    public init(drive: OneDrive, cinemeta: Cinemeta, kv: KeyValueStore, folder: @escaping @Sendable () -> String, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.drive = drive; self.cinemeta = cinemeta; self.kv = kv; self.folder = folder; self.clock = clock
    }

    public nonisolated var ready: Bool { drive.linked && !folder().isEmpty }

    public nonisolated var saved: Index? {
        kv.data(Self.key).flatMap { try? JSONDecoder().decode(Index.self, from: $0) }
    }

    public nonisolated func forget() { kv.set(Self.key, data: nil) }

    nonisolated var fixes: [String: Fix] {
        kv.data(Self.fixesKey).flatMap { try? JSONDecoder().decode([String: Fix].self, from: $0) } ?? [:]
    }

    /// La llave de un nombre: «kind|título|año». Un mismo título en varios archivos se busca (y se corrige) una vez.
    public nonisolated static func key(_ info: OneDriveName) -> String {
        "\(info.kind)|\(info.title.lowercased())|\(info.year.map(String.init) ?? "")"
    }

    /// Revisa la carpeta y empareja cada video con su ficha. Una sola revisión a la vez.
    @discardableResult
    public func scan() async throws -> Index {
        if let scanning { return try await scanning.value }
        let task = Task<Index, Error> {
            let path = folder()
            let files = try await drive.videos(path)
            let fixes = self.fixes
            var found: [String: Fix?] = [:]
            var entries: [Entry] = [], unmatched: [OneDriveFile] = []
            for file in files {
                let key = Self.key(file.info)
                if found[key] == nil {
                    if let fixed = fixes[key] { found[key] = .some(fixed) } else { found[key] = .some(await match(file.info)) }
                }
                if let fix = found[key] ?? nil { entries.append(Entry(file: file, imdb: fix.imdb, kind: file.info.kind, name: fix.name, poster: fix.poster, year: fix.year)) }
                else { unmatched.append(file) }
            }
            let index = Index(folder: path, scannedAt: clock(), entries: entries, unmatched: unmatched.count, unmatchedFiles: unmatched)
            save(index)
            return index
        }
        scanning = task
        defer { scanning = nil }
        return try await task.value
    }

    private nonisolated func save(_ index: Index) { kv.set(Self.key, data: try? JSONEncoder().encode(index)) }

    /// La ficha de un nombre (como la TV): en Cinemeta, del tipo que dice el nombre. Con año, solo una de ese año (±1: los
    /// estrenos cambian de año según el país); si no hay, sin ficha. Sin año, la primera.
    func match(_ info: OneDriveName) async -> Fix? {
        guard let metas = try? await cinemeta.search(info.kind, query: info.title) else { return nil }
        let candidates = metas.filter { ($0["id"]?.string ?? "").hasPrefix("tt") }
        let pick: JSON?
        if let year = info.year {
            pick = candidates.first { meta in
                guard let found = Int(Self.release(meta).prefix(4)) else { return false }
                return abs(found - year) <= 1
            }
        } else { pick = candidates.first }
        guard let pick, let id = pick["id"]?.string else { return nil }
        return Fix(imdb: id, name: pick["name"]?.string ?? info.title, poster: pick["poster"]?.string, year: Self.release(pick))
    }

    static func release(_ meta: JSON) -> String {
        meta["releaseInfo"]?.string ?? meta["year"]?.string ?? (meta["year"]?.intValue.map(String.init) ?? "")
    }

    /// «Corregir ficha»: ese nombre (y todos los archivos que lo comparten) pasa a la ficha que elegiste, ahora y en las
    /// siguientes revisiones. No hace falta volver a leer la carpeta.
    public func fix(_ info: OneDriveName, to fix: Fix) {
        let key = Self.key(info)
        var all = fixes; all[key] = fix
        kv.set(Self.fixesKey, data: try? JSONEncoder().encode(all))
        guard var index = saved else { return }
        index.entries = index.entries.map { e in
            guard Self.key(e.file.info) == key else { return e }
            return Entry(file: e.file, imdb: fix.imdb, kind: e.kind, name: fix.name, poster: fix.poster, year: fix.year)
        }
        let now = (index.unmatchedFiles ?? []).filter { Self.key($0.info) == key }
        index.entries += now.map { Entry(file: $0, imdb: fix.imdb, kind: $0.info.kind, name: fix.name, poster: fix.poster, year: fix.year) }
        index.unmatchedFiles = (index.unmatchedFiles ?? []).filter { Self.key($0.info) != key }
        index.unmatched = index.unmatchedFiles?.count ?? 0
        save(index)
    }

    /// Lo guardado; si ya es viejo (o es de otra carpeta), se revisa de nuevo.
    @discardableResult
    public func refreshIfStale() async -> Bool {
        guard ready else { return false }
        let index = saved
        guard index == nil || index?.folder != folder() || clock().timeIntervalSince(index!.scannedAt) > Self.staleAfter else { return false }
        return (try? await scan()) != nil
    }

    // MARK: lo que se ve en Mi media
    /// Tus títulos, lo más reciente primero: cada película con sus versiones, cada serie con sus episodios.
    public nonisolated func titles() -> [Title] {
        guard let index = saved else { return [] }
        var order: [String] = [], groups: [String: [Entry]] = [:]
        for e in index.entries {
            let id = "\(e.kind):\(e.imdb)"
            if groups[id] == nil { order.append(id) }
            groups[id, default: []].append(e)
        }
        return order.compactMap { id -> Title? in
            guard let entries = groups[id], let first = entries.first else { return nil }
            let added = entries.compactMap(\.file.added).max()
            return Title(imdb: first.imdb, kind: first.kind, name: first.name ?? first.file.info.title, year: first.year,
                         poster: first.poster ?? String(format: ForYou.metahubPoster, first.imdb), added: added,
                         entries: entries.sorted(by: Self.better))
        }
        .sorted { ($0.added ?? .distantPast) > ($1.added ?? .distantPast) }
    }

    /// Las copias de un video (una película o un episodio), la mejor primero.
    public nonisolated func versions(_ videoID: String) -> [Entry] {
        (saved?.entries ?? []).filter { $0.videoID == videoID }.sorted(by: Self.better)
    }

    /// Cuál usar: para ver, la mejor; para bajar al iPhone, la de 1080p (o la que más se le acerque sin pasarse de 4K).
    public nonisolated func pick(_ videoID: String, purpose: Purpose) -> Entry? {
        let all = versions(videoID)
        guard purpose == .download else { return all.first }
        return all.first { $0.details.resolution == "1080p" } ?? all.first { Self.rank($0.details.resolution) > Self.rank("1080p") } ?? all.last
    }

    /// Una copia como fuente (con su dirección temporal, ~1 h): para el reproductor o la cola de descargas.
    public func source(_ entry: Entry) async throws -> Source {
        Self.source(entry.file, url: try await drive.streamURL(entry.file.id))
    }

    /// `preferring`: la versión elegida (su número de fuente); si no está, la que toca para ese propósito.
    public func source(_ videoID: String, purpose: Purpose, preferring index: Int? = nil) async -> Source? {
        let chosen = index.flatMap { i in versions(videoID).first { $0.details.index == i } }
        guard let entry = chosen ?? pick(videoID, purpose: purpose) else { return nil }
        return try? await source(entry)
    }

    /// Un enlace nuevo para una descarga de Mi media cuyo enlace caducó (se busca por el nombre del archivo).
    public func refreshURL(release: String) async -> URL? {
        guard let entry = saved?.entries.first(where: { $0.file.name == release }) else { return nil }
        return try? await drive.streamURL(entry.file.id)
    }

    /// Un archivo cualquiera de la carpeta (la vista de carpetas): su dirección temporal.
    public func url(of file: OneDriveFile) async throws -> URL { try await drive.streamURL(file.id) }

    /// La vista de carpetas: lo que hay en una carpeta, tal cual.
    public func listing(_ path: String) async throws -> (folders: [OneDriveFolder], videos: [OneDriveFile]) { try await drive.listing(path) }

    // MARK: calidad
    static let order = ["4K": 0, "1440p": 1, "1080p": 2, "720p": 3, "480p": 4]
    nonisolated static func rank(_ resolution: String) -> Int { order[resolution] ?? 5 }
    public nonisolated static func better(_ a: Entry, _ b: Entry) -> Bool {
        let ra = rank(a.details.resolution), rb = rank(b.details.resolution)
        return ra != rb ? ra < rb : a.file.size > b.file.size
    }

    /// Lo que dice el nombre del archivo (sin dirección: para mostrar).
    public nonisolated static func describe(_ file: OneDriveFile) -> Source {
        source(file, url: URL(string: "https://onedrive.invalid/\(file.id)")!)
    }

    /// Una fuente como las de los complementos: el nombre del archivo da la calidad, el HDR y el idioma; es tuya, así que
    /// arranca al instante (`cached`).
    public nonisolated static func source(_ file: OneDriveFile, url: URL) -> Source {
        let gb = Double(file.size) / 1_073_741_824
        let stream: JSON = .object([
            "name": .string(addonName),
            "title": .string("\(file.name)\n💾 \(String(format: "%.2f", gb)) GB"),
            "url": .string(url.absoluteString),
            "behaviorHints": .object(["filename": .string(file.name)]),
        ])
        let index = Streams.stableIndex(addonURL: "onedrive", stream: .object(["url": .string("onedrive:\(file.id)")]))
        var src = Streams.parse(stream, addon: addonName, transportURL: "onedrive", index: index)
        src.cached = true
        src.size = file.size
        src.release = file.name
        return src
    }
}
