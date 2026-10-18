import Foundation

/// Pide fuentes a los complementos que las dan (en paralelo) y las recuerda unos minutos.
/// Los enlaces de Real-Debrid caducan: una caché vieja no se usa para reproducir.
public actor StreamFinder {
    public static let cacheSeconds: TimeInterval = 600
    public static let retryFailed: TimeInterval = 15
    static let cacheMax = 200
    /// Cuánto se espera a los complementos lentos cuando otro ya dio fuentes (segundos).
    static let budget: Double = 3
    private enum Arrival: Sendable { case addon(Int, [JSON]?), budget }

    private let http: HTTPClient
    private let registry: AddonRegistry
    private let clock: @Sendable () -> Date
    private var cache: [String: (expires: Date, sources: [Source])] = [:]
    /// Lo que contestó cada complemento para un video, una sola vez: Ver, Descargar y la hoja de Fuente solo lo ordenan
    /// distinto (antes cada una volvía a preguntar a todos y esperaba al más lento). Y lo que ya se está pidiendo se comparte.
    private typealias Answers = (serving: [Addon], results: [[JSON]?])
    private var answers: [String: (expires: Date, answers: Answers, failed: Bool)] = [:]
    private var asking: [String: Task<Answers, Error>] = [:]

    /// Tus copias propias (OneDrive): van antes que las de los complementos, son tuyas y arrancan al instante.
    public typealias LocalSources = @Sendable (_ kind: String, _ videoID: String) async -> [Source]
    private let local: LocalSources?

    public init(http: HTTPClient, registry: AddonRegistry, clock: @escaping @Sendable () -> Date = { Date() }, local: LocalSources? = nil) {
        self.http = http; self.registry = registry; self.clock = clock; self.local = local
    }

    /// Cambió tu carpeta o tu cuenta de OneDrive: lo recordado ya no vale.
    public func forget() { cache = [:] }

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
        async let mine = local?(kind, videoID) ?? []
        let asked: Answers
        do { asked = try await ask(kind: kind, videoID: videoID, fresh: fresh) }
        catch {
            // Sin complementos (o sin red para ellos), tus copias igual sirven.
            let own = await mine
            if own.isEmpty { throw error }
            return Streams.rank(own, prefs: prefs, kind: kind, purpose: purpose)
        }
        let (serving, results) = asked
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
        var ranked = Streams.rank(sources, prefs: prefs, kind: kind, purpose: purpose)
        let own = await mine
        if !own.isEmpty {
            let top = ranked.first?.score ?? 0
            ranked = Streams.rank(own, prefs: prefs, kind: kind, purpose: purpose).map { var s = $0; s.score = max(s.score, top + 1); return s } + ranked
        }
        if failed && ranked.isEmpty { return ranked }  // la red falló y no hay nada: no se recuerda
        if cache.count >= Self.cacheMax { for k in cache.sorted(by: { $0.value.expires < $1.value.expires }).prefix(Self.cacheMax / 2).map(\.key) { cache[k] = nil } }
        cache[key] = (clock().addingTimeInterval(failed ? Self.retryFailed : Self.cacheSeconds), ranked)
        return ranked
    }

    /// Lo que contestaron los complementos para un video: de lo guardado (si no ha caducado y no se pide `fresh`), de una
    /// petición que ya va en camino, o se pregunta a todos a la vez.
    private func ask(kind: String, videoID: String, fresh: Bool) async throws -> Answers {
        let key = "\(kind):\(videoID)"
        if !fresh, let hit = answers[key], clock() < hit.expires { return hit.answers }
        if !fresh, let running = asking[key] { return try await running.value }
        let task = Task { try await self.askAll(kind: kind, videoID: videoID) }
        asking[key] = task
        defer { asking[key] = nil }
        let found = try await task.value
        let failed = found.results.contains { $0 == nil }
        if answers.count >= Self.cacheMax { for k in answers.sorted(by: { $0.value.expires < $1.value.expires }).prefix(Self.cacheMax / 2).map(\.key) { answers[k] = nil } }
        answers[key] = (clock().addingTimeInterval(failed ? Self.retryFailed : Self.cacheSeconds), found, failed)
        return found
    }

    private func askAll(kind: String, videoID: String) async throws -> Answers {
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
        return (serving, results)
    }

    /// La fuente recomendada; en una serie, mejor la del mismo grupo que el episodio anterior (misma calidad
    /// e idioma: así lo hace Stremio con bingeGroup). `skip`: fuentes que ya fallaron.
    public func best(kind: String, videoID: String, prefs: Preferences, binge: String? = nil, skip: Set<Int> = [], purpose: Purpose = .watch) async throws -> Source? {
        let found = try await find(kind: kind, videoID: videoID, prefs: prefs, purpose: purpose).filter { !skip.contains($0.index) }
        guard let first = found.first else { return nil }
        if first.addon == OneDriveLibrary.addonName { return first }   // tu copia siempre gana
        if let binge, let same = found.first(where: { $0.binge == binge && $0.score > first.score - 700 }) { return same }
        return first
    }

    /// URLs de subtítulos en tu idioma de tus complementos (OpenSubtitles…), por si el video no trae.
    public func subtitles(kind: String, videoID: String, language: String, file: FileFingerprint? = nil) async -> [URL] {
        let codes: Set<String> = [language, Streams.languageCodes[language] ?? language]
        return await subtitleOptions(kind: kind, videoID: videoID, file: file).filter { codes.contains($0.language) }.map(\.url)
    }

    /// OpenSubtitles (su complemento público de Stremio), siempre: los subtítulos no dependen de que tengas uno instalado.
    public static let builtInSubtitles = "https://opensubtitles-v3.strem.io"

    /// Todos los subtítulos que hay para un video, de tus complementos y de OpenSubtitles; con la huella del archivo (una
    /// descarga), los que van sincronizados con esa copia exacta salen primero.
    public func subtitleOptions(kind: String, videoID: String, file: FileFingerprint? = nil) async -> [SubtitleOption] {
        var bases = ((try? await registry.serving("subtitles", kind: kind, itemID: videoID)) ?? []).map(\.base)
        if !bases.contains(where: { $0.contains("opensubtitles") }) { bases.append(Self.builtInSubtitles) }
        let extra = file.map { "/videoHash=\($0.hash)&videoSize=\($0.size)" } ?? ""
        var out: [SubtitleOption] = []
        await withTaskGroup(of: [SubtitleOption].self) { group in
            for base in bases {
                group.addTask { [http] in
                    guard let url = URL(string: "\(base)/subtitles/\(kind)/\(uriComponent(videoID))\(extra).json"),
                          let subs = (try? await http.getJSON(url, timeout: 15))?["subtitles"]?.array else { return [] }
                    return subs.compactMap { sub in
                        guard let text = sub["url"]?.string, let u = URL(string: text), ["http", "https"].contains(u.scheme?.lowercased() ?? ""),
                              let lang = sub["lang"]?.string else { return nil }
                        return SubtitleOption(url: u, language: lang)
                    }
                }
            }
            for await found in group { out += found }
        }
        var seen = Set<URL>()
        return out.filter { seen.insert($0.url).inserted }
    }
}

/// Un subtítulo que se puede sumar al video: de dónde bajarlo y en qué idioma (código de OpenSubtitles: «spa», «eng»).
public struct SubtitleOption: Sendable, Equatable, Identifiable {
    public var url: URL
    public var language: String
    public var id: URL { url }
    public init(url: URL, language: String) { self.url = url; self.language = language }
}

/// La huella de OpenSubtitles de un archivo (su tamaño más la suma de los primeros y últimos 64 KB): encuentra los
/// subtítulos hechos para esa copia exacta, que van a tiempo.
public struct FileFingerprint: Sendable, Equatable {
    public var hash: String
    public var size: Int64

    public static func of(_ url: URL) -> FileFingerprint? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd(), end >= 65_536 else { return nil }
        let chunk = 65_536
        var sum = UInt64(end)
        func add(_ data: Data) {
            data.withUnsafeBytes { raw in
                for i in stride(from: 0, to: raw.count - 7, by: 8) { sum = sum &+ raw.loadUnaligned(fromByteOffset: i, as: UInt64.self).littleEndian }
            }
        }
        try? handle.seek(toOffset: 0)
        guard let head = try? handle.read(upToCount: chunk) else { return nil }
        add(head)
        try? handle.seek(toOffset: end - UInt64(chunk))
        guard let tail = try? handle.read(upToCount: chunk) else { return nil }
        add(tail)
        return FileFingerprint(hash: String(format: "%016llx", sum), size: Int64(end))
    }
}

