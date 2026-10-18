import Foundation

/// Tu carpeta de OneDrive ya reconocida: cada video con su ficha (IMDb), para ofrecerlo como fuente de esa película o
/// episodio. Se guarda en el teléfono y se vuelve a revisar cada `staleAfter` (o cuando lo pides en Ajustes).
public actor OneDriveLibrary {
    public static let staleAfter: TimeInterval = 6 * 3600
    static let key = "onedrive-index"
    /// El nombre de la fuente en la lista de fuentes (como el de un complemento).
    public static let addonName = "OneDrive"
    /// Cómo se nombra en pantalla (como la TV).
    public static let displayName = "Tu OneDrive"

    public struct Entry: Sendable, Equatable, Codable {
        public var file: OneDriveFile
        public var imdb: String
        public var kind: String
        /// El id del video como lo pide Stremio: «tt123» (película) o «tt123:1:3» (episodio).
        public var videoID: String { file.info.kind == "series" ? "\(imdb):\(file.info.season ?? 0):\(file.info.episode ?? 0)" : imdb }
    }

    public struct Index: Sendable, Equatable, Codable {
        public var folder: String
        public var scannedAt: Date
        public var entries: [Entry]
        /// Videos que no se pudieron emparejar con una ficha (por su nombre).
        public var unmatched: Int
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

    /// Revisa la carpeta y empareja cada video con su ficha. Una sola revisión a la vez.
    @discardableResult
    public func scan() async throws -> Index {
        if let scanning { return try await scanning.value }
        let task = Task<Index, Error> {
            let path = folder()
            let files = try await drive.videos(path)
            var ids: [String: String?] = [:]   // «kind|título|año» → imdb (cada título se busca una vez, no por episodio)
            var entries: [Entry] = [], unmatched = 0
            for file in files {
                let key = "\(file.info.kind)|\(file.info.title.lowercased())|\(file.info.year.map(String.init) ?? "")"
                if ids[key] == nil { ids[key] = .some(await match(file.info)) }
                if let imdb = ids[key] ?? nil { entries.append(Entry(file: file, imdb: imdb, kind: file.info.kind)) } else { unmatched += 1 }
            }
            let index = Index(folder: path, scannedAt: clock(), entries: entries, unmatched: unmatched)
            kv.set(Self.key, data: try? JSONEncoder().encode(index))
            return index
        }
        scanning = task
        defer { scanning = nil }
        return try await task.value
    }

    /// La ficha de un nombre (como la TV): en Cinemeta, del tipo que dice el nombre. Con año, solo una de ese año (±1: los
    /// estrenos cambian de año según el país); si no hay, sin ficha. Sin año, la primera.
    func match(_ info: OneDriveName) async -> String? {
        guard let metas = try? await cinemeta.search(info.kind, query: info.title) else { return nil }
        let candidates = metas.filter { ($0["id"]?.string ?? "").hasPrefix("tt") }
        guard let year = info.year else { return candidates.first?["id"]?.string }
        return candidates.first { meta in
            let release = meta["releaseInfo"]?.string ?? meta["year"]?.string ?? (meta["year"]?.intValue.map(String.init) ?? "")
            guard let found = Int(release.prefix(4)) else { return false }
            return abs(found - year) <= 1
        }?["id"]?.string
    }

    /// Lo guardado; si ya es viejo (o es de otra carpeta), se revisa de nuevo sin hacerte esperar.
    private func current() async -> Index? {
        let index = saved
        let stale = index.map { $0.folder != folder() || clock().timeIntervalSince($0.scannedAt) > Self.staleAfter } ?? true
        guard stale, ready else { return index }
        if index == nil || index?.folder != folder() { return try? await scan() }   // la primera vez sí se espera
        Task { _ = try? await self.scan() }
        return index
    }

    /// Revisa la carpeta si lo guardado ya es viejo (o no hay): para «En tu OneDrive» al abrir Para ti.
    @discardableResult
    public func refreshIfStale() async -> Bool {
        guard ready else { return false }
        let index = saved
        guard index == nil || index?.folder != folder() || clock().timeIntervalSince(index!.scannedAt) > Self.staleAfter else { return false }
        return (try? await scan()) != nil
    }

    /// Las copias de ese video en tu OneDrive, como fuentes (con su dirección temporal).
    public func sources(kind: String, videoID: String) async -> [Source] {
        guard ready, let index = await current() else { return [] }
        let found = index.entries.filter { $0.videoID == videoID && ($0.kind == kind || kind.isEmpty) }
        var out: [Source] = []
        for entry in found {
            guard let url = try? await drive.streamURL(entry.file.id) else { continue }
            out.append(Self.source(entry.file, url: url))
        }
        return out
    }

    /// Una fuente como las de los complementos: el nombre del archivo da la calidad, el HDR y el idioma; es tuya, así que
    /// arranca al instante (`cached`).
    public static func source(_ file: OneDriveFile, url: URL) -> Source {
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
        if !src.tags.contains(addonName) { src.tags.insert(addonName, at: 0) }
        return src
    }
}
