import Foundation

/// Ningún complemento contestó (sin internet, o tus complementos caídos): no es lo mismo que «no hay fuentes».
public enum StreamFinderError: Error, Sendable, CustomStringConvertible {
    case unreachable
    public var description: String { "Sin conexión: no pude buscar dónde verlo. Revisa tu internet." }
}

/// Lo que va pasando al pedir fuentes: a qué complementos se les pregunta y lo que contesta cada uno (las versiones con
/// enlace que trajo; 0 si no tiene ese video, nil si no contestó a tiempo).
public enum SearchEvent: Sendable, Equatable {
    case asking([String])
    case answered(addon: String, found: Int?)
}

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
    /// Quien quiere ver la búsqueda mientras pasa (la órbita de «Buscando la mejor versión»), por video.
    private var watchers: [String: [UUID: AsyncStream<SearchEvent>.Continuation]] = [:]
    /// Lo que ya pasó en una búsqueda en curso: quien llega tarde (el reproductor, si la ficha ya había preguntado) lo recibe
    /// primero.
    private var happened: [String: [SearchEvent]] = [:]

    public init(http: HTTPClient, registry: AddonRegistry, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.http = http; self.registry = registry; self.clock = clock
    }

    /// De dónde es un título (su idioma original y país), para el audio de lo que no lo dice; y lo comprobado al ver una
    /// versión (sus pistas reales, por su huella `Source.key`).
    private var origin: @Sendable (_ kind: String, _ metaID: String) async -> TitleOrigin? = { _, _ in nil }
    private var checked: @Sendable (_ key: String) -> [AudioLanguage]? = { _ in nil }
    public func configure(origin: @escaping @Sendable (_ kind: String, _ metaID: String) async -> TitleOrigin?,
                          checked: @escaping @Sendable (_ key: String) -> [AudioLanguage]?) {
        self.origin = origin; self.checked = checked
        cache = [:]
    }
    /// Se comprobó el audio de una versión: lo que estaba ordenado con lo que se suponía ya no vale.
    public func forgetSorted() { cache = [:] }

    private func fetch(_ addon: Addon, kind: String, videoID: String) async -> [JSON]? {
        // nil si la red falló (para no recordar «no hay» 10 minutos)
        guard let url = URL(string: "\(addon.base)/stream/\(kind)/\(uriComponent(videoID)).json") else { return nil }
        do {
            let streams = try await http.getJSON(url, timeout: 15)?["streams"]?.array ?? []
            return streams.filter { $0.object != nil && ($0["url"]?.nonEmptyString != nil || $0["infoHash"]?.nonEmptyString != nil) }
        } catch let error as NetworkError where error.description.hasPrefix("HTTP 4") {
            return []   // contestó (no tiene ese video): eso es «no hay», no un fallo de red
        } catch { return nil }
    }

    /// Todas las fuentes ordenadas. `onlyPlayable`: en iOS solo sirven las de URL http(s) (Real-Debrid).
    /// `fresh`: se salta la caché (para pedir un enlace nuevo cuando el que se tenía caducó).
    public func find(kind: String, videoID: String, prefs: Preferences, purpose: Purpose = .watch, onlyPlayable: Bool = true, fresh: Bool = false) async throws -> [Source] {
        let key = "\(kind):\(videoID):\(prefs.wanted):\(prefs.quality):\(purpose):\(onlyPlayable)"
        if !fresh, let hit = cache[key], clock() < hit.expires { return hit.sources }
        // De dónde es el título, a la vez que se pregunta a los complementos (no después: no se espera de más).
        let metaID = String(videoID.split(separator: ":").first ?? Substring(videoID))
        let lookup = origin
        let originTask = Task { await lookup(kind, metaID) }
        let (serving, results) = try await ask(kind: kind, videoID: videoID, fresh: fresh)
        let failed = results.contains { $0 == nil }
        let titleOrigin = await originTask.value
        var sources: [Source] = [], seen = Set<Int>()
        for (addon, streams) in zip(serving, results) {
            for stream in streams ?? [] {
                var index = Streams.stableIndex(addonURL: addon.url, stream: stream)
                while seen.contains(index) { index = (index + 1) % (1 << 31) }  // el mismo enlace dos veces: la segunda, el número siguiente
                var source = Streams.parse(stream, addon: addon.name, transportURL: addon.url, index: index, origin: titleOrigin)
                source.otherTitle = !Streams.mentionsTitle(titleOrigin?.titles ?? [], "\(source.release) \(stream["behaviorHints"]?["filename"]?.string ?? "")")
                if let real = checked(source.key) { source.setAudio(real) }
                if onlyPlayable && source.playbackURL == nil { continue }
                // Una lista HLS o DASH no es un archivo: se ve, pero no se puede guardar en el teléfono.
                if purpose == .download, let ext = source.playbackURL?.pathExtension.lowercased(), ["m3u8", "mpd"].contains(ext) { continue }
                sources.append(source); seen.insert(index)
            }
        }
        let ranked = Streams.rank(sources, prefs: prefs, kind: kind, purpose: purpose)
        // Nadie contestó: es la red, no que no haya fuentes (antes se decía «No hay fuentes» sin internet).
        if !results.isEmpty, results.allSatisfy({ $0 == nil }), ranked.isEmpty { throw StreamFinderError.unreachable }
        if failed && ranked.isEmpty { return ranked }  // la red falló y no hay nada: no se recuerda
        if cache.count >= Self.cacheMax { for k in cache.sorted(by: { $0.value.expires < $1.value.expires }).prefix(Self.cacheMax / 2).map(\.key) { cache[k] = nil } }
        cache[key] = (clock().addingTimeInterval(failed ? Self.retryFailed : Self.cacheSeconds), ranked)
        return ranked
    }

    /// La búsqueda de un video mientras pasa. Si las fuentes ya estaban guardadas no llega nada (no hubo que preguntar).
    public func events(kind: String, videoID: String) -> AsyncStream<SearchEvent> {
        let key = "\(kind):\(videoID)", id = UUID()
        let (stream, continuation) = AsyncStream<SearchEvent>.makeStream()
        watchers[key, default: [:]][id] = continuation
        for event in happened[key] ?? [] { continuation.yield(event) }
        continuation.onTermination = { [weak self] _ in Task { await self?.stopWatching(key, id) } }
        return stream
    }
    private func stopWatching(_ key: String, _ id: UUID) {
        watchers[key]?[id] = nil
        if watchers[key]?.isEmpty == true { watchers[key] = nil }
    }
    private func emit(_ key: String, _ event: SearchEvent) {
        if case .asking = event { happened[key] = [event] } else { happened[key, default: []].append(event) }
        watchers[key]?.values.forEach { $0.yield(event) }
    }

    /// Pregunta ya a los complementos por ese video (sin ordenar nada): el `find` que venga después se une o lo encuentra guardado.
    public func warm(kind: String, videoID: String) async { _ = try? await ask(kind: kind, videoID: videoID, fresh: false) }
    /// Pide ya la lista de complementos (`addonCollectionGet`, o la de disco y la nueva aparte) para que las fuentes no la esperen.
    public func warmAddons() async { _ = try? await registry.addons() }

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
        let key = "\(kind):\(videoID)"
        emit(key, .asking(serving.map(\.name)))
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
                case .addon(let i, let streams):
                    out[i] = streams; pending -= 1
                    emit(key, .answered(addon: serving[i].name, found: streams?.filter { $0["url"]?.nonEmptyString != nil }.count))
                case .budget: overBudget = true
                }
                if overBudget, out.contains(where: { !($0 ?? []).isEmpty }) { break }
            }
            group.cancelAll()
            return out
        }
        happened[key] = nil
        return (serving, results)
    }

    /// La fuente recomendada; en una serie, mejor la del mismo grupo que el episodio anterior (misma calidad
    /// e idioma: así lo hace Stremio con bingeGroup). `skip`: fuentes que ya fallaron.
    /// La huella de un video en línea (para pedir subtítulos de esa copia exacta).
    public func fingerprint(of url: URL) async -> FileFingerprint? { await FileFingerprint.ofRemote(url, http: http) }

    public func best(kind: String, videoID: String, prefs: Preferences, binge: String? = nil, skip: Set<Int> = [], purpose: Purpose = .watch) async throws -> Source? {
        let found = try await find(kind: kind, videoID: videoID, prefs: prefs, purpose: purpose).filter { !skip.contains($0.index) }
        guard let first = found.first else { return nil }
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
        await subtitleSearch(kind: kind, videoID: videoID, file: file) ?? []
    }

    /// Lo mismo, pero nil si nadie contestó (sin red): así «no hay subtítulos» y «sin conexión» no se confunden.
    public func subtitleSearch(kind: String, videoID: String, file: FileFingerprint? = nil) async -> [SubtitleOption]? {
        var bases = ((try? await registry.serving("subtitles", kind: kind, itemID: videoID)) ?? []).map(\.base)
        if !bases.contains(where: { $0.contains("opensubtitles") }) { bases.append(Self.builtInSubtitles) }
        let extra = file.map { "/videoHash=\($0.hash)&videoSize=\($0.size)" } ?? ""
        var out: [SubtitleOption] = []
        var answered = false
        await withTaskGroup(of: [SubtitleOption]?.self) { group in
            for base in bases {
                group.addTask { [http] in
                    guard let url = URL(string: "\(base)/subtitles/\(kind)/\(uriComponent(videoID))\(extra).json") else { return [] }
                    let json: JSON?
                    do { json = try await http.getJSON(url, timeout: 15) }
                    catch let error as NetworkError where error.description.hasPrefix("HTTP") { return [] }   // contestó: no es falta de red
                    catch { return nil }
                    guard let subs = json?["subtitles"]?.array else { return [] }
                    let source = base.contains("opensubtitles") ? "OpenSubtitles" : URL(string: base)?.host
                    return subs.compactMap { sub in
                        guard let text = sub["url"]?.string, let u = URL(string: text), ["http", "https"].contains(u.scheme?.lowercased() ?? ""),
                              let lang = sub["lang"]?.string else { return nil }
                        // Lo que algunos complementos cuentan de más (OpenSubtitles por su API): la copia, las descargas, si es para sordos o forzado.
                        let release = sub["release"]?.string ?? sub["releaseName"]?.string ?? sub["release_name"]?.string ?? sub["title"]?.string
                        let downloads = sub["downloads"]?.intValue ?? sub["download_count"]?.intValue
                        let hi = sub["hearing_impaired"]?.bool ?? sub["hearingImpaired"]?.bool ?? false
                        let forced = sub["foreign_parts_only"]?.bool ?? sub["forced"]?.bool ?? false
                        let fileID = sub["id"]?.string ?? sub["id"]?.intValue.map(String.init)
                        return SubtitleOption(url: u, language: lang, release: release, downloads: downloads, hearingImpaired: hi, foreignOnly: forced,
                                              source: source, fileID: fileID)
                    }
                }
            }
            for await found in group { if let found { answered = true; out += found } }
        }
        guard answered else { return nil }
        var seen = Set<URL>()
        return out.filter { seen.insert($0.url).inserted }
    }
}

/// Un subtítulo que se puede sumar al video: de dónde bajarlo y en qué idioma (código de OpenSubtitles: «spa», «eng»).
public struct SubtitleOption: Sendable, Equatable, Identifiable {
    public var url: URL
    public var language: String
    public var release: String?          // el nombre de la copia para la que se hizo («…WEB-DL-NTb»)
    public var downloads: Int?
    public var hearingImpaired = false   // SDH/CC
    public var foreignOnly = false       // forzado: solo carteles o partes en otro idioma
    /// De dónde salió («OpenSubtitles» o el servidor del complemento) y su id de archivo allá (para no guardarlo dos veces).
    public var source: String?
    public var fileID: String?
    public var id: URL { url }
    public init(url: URL, language: String, release: String? = nil, downloads: Int? = nil, hearingImpaired: Bool = false, foreignOnly: Bool = false,
                source: String? = nil, fileID: String? = nil) {
        self.url = url; self.language = language; self.release = release; self.downloads = downloads
        self.hearingImpaired = hearingImpaired; self.foreignOnly = foreignOnly; self.source = source; self.fileID = fileID
    }
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

    /// La misma huella (la de OpenSubtitles) de un video en línea, con dos pedidos de 64 KB (el principio y el final): así
    /// también lo que ves sin bajar encuentra los subtítulos hechos para esa copia exacta.
    public static func compute(head: Data, tail: Data, size: Int64) -> FileFingerprint? {
        guard head.count == 65_536, tail.count == 65_536, size >= 65_536 else { return nil }
        var sum = UInt64(size)
        for data in [head, tail] {
            data.withUnsafeBytes { raw in
                for i in stride(from: 0, to: raw.count - 7, by: 8) { sum = sum &+ raw.loadUnaligned(fromByteOffset: i, as: UInt64.self).littleEndian }
            }
        }
        return FileFingerprint(hash: String(format: "%016llx", sum), size: size)
    }

    public static func ofRemote(_ url: URL, http: HTTPClient) async -> FileFingerprint? {
        let chunk: Int64 = 65_536
        guard let first = try? await http.send(HTTPRequest(url: url, headers: ["Range": "bytes=0-\(chunk - 1)"], timeout: 10)), first.status == 206,
              let total = first.headers["content-range"]?.split(separator: "/").last.flatMap({ Int64($0) }), total >= chunk,
              let last = try? await http.send(HTTPRequest(url: url, headers: ["Range": "bytes=\(total - chunk)-\(total - 1)"], timeout: 10)), last.status == 206
        else { return nil }
        return compute(head: first.data, tail: last.data, size: total)
    }
}

