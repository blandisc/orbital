import Foundation
import OrbitalAddons

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

/// Un pedido tuyo a Real-Debrid que ya terminó, de un video: su torrent y su archivo (la libreta de pedidos).
public struct ReadyTorrent: Sendable, Equatable {
    public var hash: String
    public var fileIdx: Int?
    /// El nombre de la versión que se pidió, si se sabe.
    public var release: String?
    public init(hash: String, fileIdx: Int?, release: String? = nil) { self.hash = hash.lowercased(); self.fileIdx = fileIdx; self.release = release }

    /// ¿Es esta versión? La misma huella y, si los dos lo dicen, el mismo archivo.
    func matches(_ source: Source) -> Bool {
        guard let torrent = source.torrent, torrent.hash == hash else { return false }
        guard let mine = fileIdx, let theirs = torrent.fileIdx else { return true }
        return mine == theirs
    }
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

    /// Lo más que se espera a un complemento (C8): pasado esto se salta y se dice su nombre.
    public static let slowAfter: TimeInterval = 8
    private let http: HTTPClient
    private let registry: AddonRegistry
    private let clock: @Sendable () -> Date
    /// Cómo le va a cada complemento (C2): el que no contesta dos veces seguidas ya no se espera hasta su próximo intento.
    private let health: AddonHealth?
    private var cache: [String: (expires: Date, sources: [Source])] = [:]
    /// Los avisos de Torrentio que llegaron en lugar de versiones en la última búsqueda de cada video (R5): no se ofrecen,
    /// pero dicen por qué no hay.
    private var noticesSeen: [String: [StreamNotice]] = [:]
    /// C8: los complementos que no contestaron a tiempo (o se saltaron por no contestar antes) en la última búsqueda de cada
    /// video, por su nombre: la lista de versiones lo dice («Comet no contestó a tiempo»).
    private var quietSeen: [String: [String]] = [:]
    private var skippedByHealth: [String: [String]] = [:]
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

    /// M5: «kitsu:» y «tmdb:» al de IMDb, para preguntarle también a los que solo saben de IMDb.
    private let bridge: IDBridge?

    public init(http: HTTPClient, registry: AddonRegistry, health: AddonHealth? = nil, bridge: IDBridge? = nil, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.http = http; self.registry = registry; self.health = health; self.bridge = bridge; self.clock = clock
    }

    /// De dónde es un título (su idioma original y país), para el audio de lo que no lo dice; y lo comprobado al ver una
    /// versión (sus pistas reales, por su huella `Source.key`).
    private var origin: @Sendable (_ kind: String, _ metaID: String) async -> TitleOrigin? = StreamFinder.noOrigin
    /// Una función con nombre (no un cierre asíncrono en la línea): ver `AsyncDefaults`.
    @Sendable static func noOrigin(_ kind: String, _ metaID: String) async -> TitleOrigin? { nil }
    private var checked: @Sendable (_ key: String) -> [AudioLanguage]? = { _ in nil }
    /// Tu plan B de idiomas (T2): los «Idiomas primero» de tu Torrentio, como códigos.
    private var fallback: @Sendable () -> [String] = { [] }
    /// Lo que pediste y Real-Debrid ya terminó, por video (la libreta), y cómo verlo sin Torrentio si no lo lista.
    private var ready: @Sendable (_ kind: String, _ videoID: String) -> [ReadyTorrent] = { _, _ in [] }
    private var readyLink: @Sendable (_ hash: String, _ videoID: String) async -> URL? = StreamFinder.noLink
    @Sendable static func noLink(_ hash: String, _ videoID: String) async -> URL? { nil }
    /// Fernando, 3 nov, con «El viento tiene miedo»: llegó «Ya está» y la versión seguía «Real-Debrid aún no la tiene» (Torrentio
    /// no se entera de lo que bajó tu cuenta). Con esto, lo que pediste y ya está sale «Al instante · la pediste» y se recomienda.
    public func configureReady(_ ready: @escaping @Sendable (_ kind: String, _ videoID: String) -> [ReadyTorrent],
                               link: @escaping @Sendable (_ hash: String, _ videoID: String) async -> URL?) {
        self.ready = ready; self.readyLink = link
        cache = [:]
    }
    /// De dónde es un título (lo mismo con que se ordenan las versiones): para leer igual lo que existe sin Real-Debrid.
    public func origin(kind: String, metaID: String) async -> TitleOrigin? { await origin(kind, metaID) }

    public func configure(origin: @escaping @Sendable (_ kind: String, _ metaID: String) async -> TitleOrigin?,
                          checked: @escaping @Sendable (_ key: String) -> [AudioLanguage]?,
                          fallback: @escaping @Sendable () -> [String] = { [] }) {
        self.origin = origin; self.checked = checked; self.fallback = fallback
        cache = [:]
    }
    /// Se comprobó el audio de una versión: lo que estaba ordenado con lo que se suponía ya no vale.
    public func forgetSorted() { cache = [:] }
    /// Cambiaron tus complementos o sus opciones (T1): nada de lo que contestaron antes vale.
    public func forgetAll() { cache = [:]; answers = [:]; noticesSeen = [:]; quietSeen = [:] }
    /// Real-Debrid terminó de bajar un pedido (o lo empezó): lo guardado de ese video ya no vale; la versión pedida sale
    /// «Al instante» en la siguiente búsqueda.
    public func forget(kind: String, videoID: String) {
        let prefix = "\(kind):\(videoID):"
        cache = cache.filter { !$0.key.hasPrefix(prefix) }
        answers["\(kind):\(videoID)"] = nil
    }

    private func fetch(_ addon: Addon, kind: String, videoID: String) async -> [JSON]? {
        // nil si la red falló (para no recordar «no hay» 10 minutos)
        guard let url = URL(string: "\(addon.base)/stream/\(kind)/\(uriComponent(videoID)).json") else { return nil }
        let start = Date()
        do {
            let streams = try await http.getJSON(url, timeout: Self.slowAfter)?["streams"]?.array ?? []
            health?.ok(addon.url, seconds: Date().timeIntervalSince(start))
            let found = streams.filter { $0.object != nil && ($0["url"]?.nonEmptyString != nil || $0["infoHash"]?.nonEmptyString != nil) }
            // M6: si solo da torrents, el iPhone no puede reproducir nada de él (la TV sí).
            if !found.isEmpty { health?.answered(addon.url, onlyTorrents: AddonTorrents.onlyTorrents(found.map { ($0["url"]?.string, $0["infoHash"]?.string) })) }
            return found
        } catch let error as NetworkError where error.description.hasPrefix("HTTP 4") {
            health?.ok(addon.url, seconds: Date().timeIntervalSince(start))
            return []   // contestó (no tiene ese video): eso es «no hay», no un fallo de red
        } catch {
            if !Task.isCancelled { health?.fail(addon.url) }   // no esperarlo porque otro ya contestó no es un fallo
            return nil
        }
    }

    /// Todas las fuentes ordenadas. `onlyPlayable`: en iOS solo sirven las de URL http(s) (Real-Debrid).
    /// `fresh`: se salta la caché (para pedir un enlace nuevo cuando el que se tenía caducó).
    public func find(kind: String, videoID: String, prefs: Preferences, purpose: Purpose = .watch, onlyPlayable: Bool = true, fresh: Bool = false) async throws -> [Source] {
        var prefs = prefs
        if prefs.fallback.isEmpty { prefs.fallback = fallback() }
        // Lo que quedó listo entra en la llave: un pedido que termina no se queda con la lista de antes (10 min).
        let readyNow = ready(kind, videoID)
        let key = "\(kind):\(videoID):\(prefs.wanted):\(prefs.quality):\(prefs.fallback.joined(separator: ",")):\(purpose):\(onlyPlayable):"
            + readyNow.map(\.hash).sorted().joined(separator: ",")
        if !fresh, let hit = cache[key], clock() < hit.expires { return hit.sources }
        // De dónde es el título, a la vez que se pregunta a los complementos (no después: no se espera de más).
        let metaID = String(videoID.split(separator: ":").first ?? Substring(videoID))
        let lookup = origin
        let originTask = Task { await lookup(kind, metaID) }
        let (serving, results) = try await ask(kind: kind, videoID: videoID, fresh: fresh)
        let failed = results.contains { $0 == nil }
        let titleOrigin = await originTask.value
        var sources: [Source] = [], seen = Set<Int>(), notices: [StreamNotice] = []
        for (addon, streams) in zip(serving, results) {
            for stream in streams ?? [] {
                var index = Streams.stableIndex(addonURL: addon.url, stream: stream)
                while seen.contains(index) { index = (index + 1) % (1 << 31) }  // el mismo enlace dos veces: la segunda, el número siguiente
                var source = Streams.parse(stream, addon: addon.name, transportURL: addon.url, index: index, origin: titleOrigin)
                source.otherTitle = !Streams.mentionsTitle(titleOrigin?.titles ?? [], "\(source.release) \(stream["behaviorHints"]?["filename"]?.string ?? "")")
                if let notice = source.notice { notices.append(notice); continue }   // el aviso de Torrentio nunca es una versión
                if let real = checked(source.key) { source.setAudio(real) }
                if onlyPlayable && source.playbackURL == nil { continue }
                if let url = source.playbackURL { PlaybackHeaders.remember(source.requestHeaders, for: url) }   // M3
                // Una lista HLS o DASH no es un archivo: se ve, pero no se puede guardar en el teléfono.
                if purpose == .download, let ext = source.playbackURL?.pathExtension.lowercased(), ["m3u8", "mpd"].contains(ext) { continue }
                sources.append(source); seen.insert(index)
            }
        }
        for missing in Self.markReady(&sources, readyNow) {
            // Torrentio no la lista (con «solo lo que ya está» o por su límite): se ve con el enlace de tu Real-Debrid.
            guard let url = await readyLink(missing.hash, videoID) else { continue }
            var source = Self.readySource(missing, url: url, origin: titleOrigin)
            while seen.contains(source.index) { source.index = (source.index + 1) % (1 << 31) }
            sources.append(source); seen.insert(source.index)
        }
        let ranked = Streams.rank(sources, prefs: prefs, kind: kind, purpose: purpose)
        noticesSeen["\(kind):\(videoID)"] = notices
        quietSeen["\(kind):\(videoID)"] = (skippedByHealth["\(kind):\(videoID)"] ?? []) + zip(serving, results).filter { $0.1 == nil }.map(\.0.name)
        // Nadie contestó: es la red, no que no haya fuentes (antes se decía «No hay fuentes» sin internet).
        if !results.isEmpty, results.allSatisfy({ $0 == nil }), ranked.isEmpty { throw StreamFinderError.unreachable }
        if failed && ranked.isEmpty { return ranked }  // la red falló y no hay nada: no se recuerda
        if cache.count >= Self.cacheMax { for k in cache.sorted(by: { $0.value.expires < $1.value.expires }).prefix(Self.cacheMax / 2).map(\.key) { cache[k] = nil } }
        cache[key] = (clock().addingTimeInterval(failed ? Self.retryFailed : Self.cacheSeconds), ranked)
        return ranked
    }

    /// Marca «Al instante · la pediste» las versiones de pedidos listos. Devuelve los pedidos que ninguna versión trae.
    static func markReady(_ sources: inout [Source], _ ready: [ReadyTorrent]) -> [ReadyTorrent] {
        var missing: [ReadyTorrent] = []
        for torrent in ready {
            var found = false
            for i in sources.indices where torrent.matches(sources[i]) { sources[i].cached = true; sources[i].requested = true; found = true }
            if !found { missing.append(torrent) }
        }
        return missing
    }

    /// Una versión hecha con el enlace de tu Real-Debrid para un pedido listo que Torrentio no lista.
    static func readySource(_ torrent: ReadyTorrent, url: URL, origin: TitleOrigin?) -> Source {
        var stream: [String: JSON] = ["name": .string("[RD+] Real-Debrid"), "title": .string(torrent.release ?? ""), "url": .string(url.absoluteString),
                                      "infoHash": .string(torrent.hash)]
        if let idx = torrent.fileIdx { stream["fileIdx"] = .int(idx) }
        let json = JSON.object(stream)
        // Su número sale de la huella, no del enlace (que cambia cada vez que se pide).
        let index = Streams.stableIndex(addonURL: "realdebrid:ready", stream: .object(stream.filter { $0.key != "url" }))
        var source = Streams.parse(json, addon: "Real-Debrid", transportURL: "", index: index, origin: origin)
        source.cached = true; source.debrid = true; source.requested = true
        return source
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
        var all = try await registry.serving("stream", kind: kind, itemID: videoID)
        var ids = [String: String]()   // M5: a los que solo saben de IMDb, con el id traducido
        if IDBridge.isForeign(videoID), let bridge, let imdb = await bridge.videoID(videoID, kind: kind) {
            let known = Set(all.map(\.url))
            for addon in try await registry.serving("stream", kind: kind, itemID: imdb) where !known.contains(addon.url) {
                all.append(addon); ids[addon.url] = imdb
            }
        }
        // Los que no contestan se saltan (C2); si son todos, se les pregunta igual: nunca te quedas sin preguntar.
        let awake = all.filter { health?.skip($0.url) != true }
        let serving = awake.isEmpty ? all : awake
        let key = "\(kind):\(videoID)"
        skippedByHealth[key] = awake.isEmpty ? [] : all.filter { health?.skip($0.url) == true }.map(\.name)
        emit(key, .asking(serving.map(\.name)))
        // Un complemento lento no detiene a los demás: pasado `budget`, si alguno ya dio fuentes, no se le espera (cuenta como
        // fallido: se vuelve a preguntar pronto).
        let budget = Self.budget
        let results = await withTaskGroup(of: Arrival.self) { group in
            for (i, addon) in serving.enumerated() {
                let id = ids[addon.url] ?? videoID
                group.addTask { .addon(i, await self.fetch(addon, kind: kind, videoID: id)) }
            }
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

    /// Los avisos de Torrentio de la última búsqueda de ese video (vacío si no hubo).
    public func notices(kind: String, videoID: String) -> [StreamNotice] { noticesSeen["\(kind):\(videoID)"] ?? [] }

    /// C8: quién no contestó a tiempo (o se saltó) en la última búsqueda de ese video, por su nombre y sin repetir.
    public func quiet(kind: String, videoID: String) -> [String] {
        var seen = Set<String>()
        return (quietSeen["\(kind):\(videoID)"] ?? []).filter { seen.insert($0).inserted }
    }

    /// `instantOnly`: solo las que arrancan al instante (un reintento nunca le pide a Real-Debrid otra descarga, R6).
    public func best(kind: String, videoID: String, prefs: Preferences, binge: String? = nil, skip: Set<Int> = [], instantOnly: Bool = false,
                     purpose: Purpose = .watch) async throws -> Source? {
        let found = try await find(kind: kind, videoID: videoID, prefs: prefs, purpose: purpose).filter { !skip.contains($0.index) && (!instantOnly || $0.instant) }
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

