import Foundation

/// Pide fuentes a los complementos que las dan (en paralelo) y las recuerda unos minutos.
/// Los enlaces de Real-Debrid caducan: una caché vieja no se usa para reproducir.
public actor StreamFinder {
    public static let cacheSeconds: TimeInterval = 600
    public static let retryFailed: TimeInterval = 15
    static let cacheMax = 200
    /// Cuánto se espera a los complementos lentos cuando otro ya dio fuentes (segundos).
    static let budget: Double = 5
    private enum Arrival: Sendable { case addon(Int, [JSON]?), budget }

    private let http: HTTPClient
    private let registry: AddonRegistry
    private let clock: @Sendable () -> Date
    private var cache: [String: (expires: Date, sources: [Source])] = [:]

    public init(http: HTTPClient, registry: AddonRegistry, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.http = http; self.registry = registry; self.clock = clock
    }

    private func fetch(_ addon: Addon, kind: String, videoID: String) async -> [JSON]? {
        // nil si la red falló (para no recordar «no hay» 10 minutos)
        guard let url = URL(string: "\(addon.base)/stream/\(kind)/\(uriComponent(videoID)).json") else { return nil }
        do {
            let streams = try await http.getJSON(url, timeout: 15)?["streams"]?.array ?? []
            return streams.filter { $0.object != nil && ($0["url"]?.nonEmptyString != nil || $0["infoHash"]?.nonEmptyString != nil) }
        } catch { return nil }
    }

    /// Todas las fuentes ordenadas. `onlyPlayable`: en iOS solo sirven las de URL http(s) (Real-Debrid).
    /// `fresh`: se salta la caché (para pedir un enlace nuevo cuando el que se tenía caducó).
    public func find(kind: String, videoID: String, prefs: Preferences, purpose: Purpose = .watch, onlyPlayable: Bool = true, fresh: Bool = false) async throws -> [Source] {
        let key = "\(kind):\(videoID):\(prefs.audio):\(prefs.quality):\(purpose):\(onlyPlayable)"
        if !fresh, let hit = cache[key], clock() < hit.expires { return hit.sources }
        let serving = try await registry.serving("stream", kind: kind, itemID: videoID)
        // Un complemento lento no detiene a los demás: pasado `budget`, si alguno ya dio fuentes, no se le espera (cuenta como
        // fallido: se vuelve a preguntar pronto).
        let budget = Self.budget
        let results = await withTaskGroup(of: Arrival.self) { group in
            for (i, addon) in serving.enumerated() { group.addTask { .addon(i, await self.fetch(addon, kind: kind, videoID: videoID)) } }
            group.addTask { try? await Task.sleep(nanoseconds: UInt64(budget * 1_000_000_000)); return .budget }
            var out = [[JSON]?](repeating: nil, count: serving.count)
            var pending = serving.count, overBudget = false
            while pending > 0, let next = await group.next() {
                switch next {
                case .addon(let i, let streams): out[i] = streams; pending -= 1
                case .budget: overBudget = true
                }
                if overBudget, out.contains(where: { !($0 ?? []).isEmpty }) { break }
            }
            group.cancelAll()
            return out
        }
        let failed = results.contains { $0 == nil }
        var sources: [Source] = [], seen = Set<Int>()
        for (addon, streams) in zip(serving, results) {
            for stream in streams ?? [] {
                var index = Streams.stableIndex(addonURL: addon.url, stream: stream)
                while seen.contains(index) { index = (index + 1) % (1 << 31) }  // el mismo enlace dos veces: la segunda, el número siguiente
                let source = Streams.parse(stream, addon: addon.name, transportURL: addon.url, index: index)
                if onlyPlayable && source.playbackURL == nil { continue }
                // Una lista HLS o DASH no es un archivo: se ve, pero no se puede guardar en el teléfono.
                if purpose == .download, let ext = source.playbackURL?.pathExtension.lowercased(), ["m3u8", "mpd"].contains(ext) { continue }
                sources.append(source); seen.insert(index)
            }
        }
        let ranked = Streams.rank(sources, prefs: prefs, kind: kind, purpose: purpose)
        if failed && ranked.isEmpty { return ranked }  // la red falló y no hay nada: no se recuerda
        if cache.count >= Self.cacheMax { for k in cache.sorted(by: { $0.value.expires < $1.value.expires }).prefix(Self.cacheMax / 2).map(\.key) { cache[k] = nil } }
        cache[key] = (clock().addingTimeInterval(failed ? Self.retryFailed : Self.cacheSeconds), ranked)
        return ranked
    }

    /// La fuente recomendada; en una serie, mejor la del mismo grupo que el episodio anterior (misma calidad
    /// e idioma: así lo hace Stremio con bingeGroup). `skip`: fuentes que ya fallaron.
    public func best(kind: String, videoID: String, prefs: Preferences, binge: String? = nil, skip: Set<Int> = [], purpose: Purpose = .watch) async throws -> Source? {
        let found = try await find(kind: kind, videoID: videoID, prefs: prefs, purpose: purpose).filter { !skip.contains($0.index) }
        guard let first = found.first else { return nil }
        if let binge, let same = found.first(where: { $0.binge == binge && $0.score > first.score - 700 }) { return same }
        return first
    }

    /// URLs de subtítulos en tu idioma de tus complementos (OpenSubtitles…), por si el video no trae.
    public func subtitles(kind: String, videoID: String, language: String) async -> [URL] {
        let codes: Set<String> = [language, Streams.languageCodes[language] ?? language]
        let serving = (try? await registry.serving("subtitles", kind: kind, itemID: videoID)) ?? []
        var urls: [URL] = []
        for addon in serving {
            guard let url = URL(string: "\(addon.base)/subtitles/\(kind)/\(uriComponent(videoID)).json"),
                  let subs = (try? await http.getJSON(url, timeout: 15))?["subtitles"]?.array else { continue }
            for sub in subs {
                guard let text = sub["url"]?.string, let u = URL(string: text), ["http", "https"].contains(u.scheme?.lowercased() ?? ""),
                      let lang = sub["lang"]?.string, codes.contains(lang) else { continue }
                urls.append(u)
            }
        }
        return urls
    }
}
