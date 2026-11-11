import Foundation

/// Fichas en el idioma de la app: Cinemeta solo habla inglés; TMDB pone título, sinopsis, géneros y episodios.
/// En inglés no se toca nada. Lo que TMDB no tiene traducido se queda como venía de Cinemeta.
public actor Localizer {
    public static let cacheSeconds: TimeInterval = 24 * 3600
    public static let retrySeconds: TimeInterval = 600
    static let regions = ["es": "es-MX", "pt": "pt-BR"]  // el español de México, no el de España
    /// Sin traducción, TMDB llama al episodio «Episodio 3»: mejor el título original de Cinemeta.
    static let genericEpisode = try! NSRegularExpression(pattern: #"^(episodio|episode|épisode|episódio|folge|episodio n\.?)\s*\d+$"#, options: [.caseInsensitive])

    /// «es» → «es-MX»; nil si no hay que traducir (inglés, o nada).
    public static func tmdbLanguage(_ language: String?) -> String? {
        let lang = (language ?? "").trimmingCharacters(in: .whitespaces)
        if lang.isEmpty || lang.lowercased().hasPrefix("en") { return nil }
        return regions[lang.lowercased()] ?? lang
    }

    private let tmdb: Tmdb
    private let language: @Sendable () -> String?
    private let clock: @Sendable () -> Date
    private var cache: [String: (expires: Date, value: Translation?)] = [:]
    /// Lo que ya se está pidiendo: dos listas con el mismo título (Seguir viendo y Mi lista) comparten la petición.
    private var inflight: [String: Task<Translation?, Never>] = [:]
    /// Título, sinopsis y géneros en disco (sin episodios): al abrir la app ya salen en tu idioma, sin esperar a TMDB.
    private let store: KeyValueStore?
    private var disk: [String: Saved]?
    private var saveScheduled = false
    private struct Saved: Codable { var t: String; var o: String; var g: [String]; var d: Double; var n: Bool?; var p: String? }
    /// `-v2` (3 nov): lo guardado antes traía en inglés las películas hechas en español; se vuelve a pedir una vez.
    static let diskKey = "tmdb-translations-v2", diskSeconds: TimeInterval = 7 * 24 * 3600, diskLimit = 3000
    /// Cuántas traducciones a la vez (antes, cientos juntas: TMDB contestaba 429 y se quedaban en inglés).
    static let concurrency = 8

    public init(tmdb: Tmdb, language: @escaping @Sendable () -> String?, clock: @escaping @Sendable () -> Date = { Date() }, store: KeyValueStore? = nil) {
        self.tmdb = tmdb; self.language = language; self.clock = clock; self.store = store
    }

    private func saved(_ key: String) -> Translation? {
        if disk == nil { disk = store?.data(Self.diskKey).flatMap { try? JSONDecoder().decode([String: Saved].self, from: $0) } ?? [:] }
        guard let s = disk?[key], clock().timeIntervalSince1970 - s.d < Self.diskSeconds else { return nil }
        return Translation(title: s.t, overview: s.o, genres: s.g, native: s.n ?? false, poster: s.p ?? "")
    }

    private func remember(_ key: String, _ t: Translation) {
        guard store != nil else { return }
        if disk == nil { _ = saved(key) }
        disk?[key] = Saved(t: t.title, o: t.overview, g: t.genres, d: clock().timeIntervalSince1970, n: t.native ? true : nil, p: t.poster.isEmpty ? nil : t.poster)
        if let count = disk?.count, count > Self.diskLimit, let oldest = disk?.sorted(by: { $0.value.d < $1.value.d }).prefix(count - Self.diskLimit).map(\.key) {
            for k in oldest { disk?[k] = nil }
        }
        guard !saveScheduled else { return }
        saveScheduled = true
        Task { [weak self] in try? await Task.sleep(nanoseconds: 2_000_000_000); await self?.flush() }   // ds-exception: se juntan las escrituras a disco
    }

    private func flush() {
        saveScheduled = false
        if let disk, let data = try? JSONEncoder().encode(disk) { store?.set(Self.diskKey, data: data) }
    }

    /// En la ficha traducida: el título está hecho en tu idioma (su logo de metahub, en inglés, no le queda).
    public static let nativeKey = "orbital_native_title"
    /// El póster de TMDB, de reserva (`Translation.poster`).
    public static let posterKey = "orbital_tmdb_poster"

    public var active: String? { tmdb.configured ? Localizer.tmdbLanguage(language()) : nil }

    private func translation(kind: String, imdb: String, lang: String, episodes: Bool) async -> Translation? {
        let key = "\(lang)|\(imdb)|\(kind)|\(episodes)"
        if let hit = cache[key], clock() < hit.expires { return hit.value }
        if !episodes, let hit = saved(key) { cache[key] = (clock().addingTimeInterval(Localizer.cacheSeconds), hit); return hit }
        if let running = inflight[key] { return await running.value }
        let tmdb = tmdb
        let task = Task<Translation?, Never> {
            do {
                guard let id = try await tmdb.findID(imdb: imdb, kind: kind) else { return Translation() }
                return try await tmdb.translation(kind: kind, tmdbID: id, language: lang, episodes: episodes)
            } catch { return nil }
        }
        inflight[key] = task
        let result = await task.value
        inflight[key] = nil
        // nil: falló (sin red, 429): se reintenta pronto. Vacío: TMDB no lo tiene; eso sí se recuerda.
        let value = result.flatMap { $0.isEmpty ? nil : $0 }
        if cache.count >= 500 { for k in cache.sorted(by: { $0.value.expires < $1.value.expires }).prefix(125).map(\.key) { cache[k] = nil } }
        cache[key] = (clock().addingTimeInterval(result == nil ? Localizer.retrySeconds : Localizer.cacheSeconds), value)
        if !episodes, let value { remember(key, value) }
        return value
    }

    /// Los nombres en tu idioma que ya se tienen (memoria o disco), sin pedir nada: así una búsqueda se ve traducida desde
    /// el primer momento en lo ya conocido, en vez de salir en inglés y cambiar al rato.
    public func knownTitles(kind: String, ids: [String]) -> [String: String] {
        guard let lang = active else { return [:] }
        var names: [String: String] = [:]
        for id in ids {
            let key = "\(lang)|\(id)|\(kind)|false"
            let found = cache[key].flatMap { clock() < $0.expires ? $0.value : nil } ?? saved(key)
            if let title = found?.title, !title.isEmpty { names[id] = title }
        }
        return names
    }

    /// Todos los nombres en tu idioma que ya se tienen (memoria y disco), por id de IMDb: `TitleNames` arranca con ellos para
    /// que lo ya conocido salga traducido desde el primer pintado.
    public func allKnownTitles() -> [String: String] {
        guard let lang = active else { return [:] }
        if disk == nil { _ = saved("") }
        var names: [String: String] = [:]
        let now = clock()
        let prefix = "\(lang)|"
        for (key, s) in disk ?? [:] where key.hasPrefix(prefix) && key.hasSuffix("|false") && !s.t.isEmpty && now.timeIntervalSince1970 - s.d < Self.diskSeconds {
            names[String(key.dropFirst(prefix.count).prefix { $0 != "|" })] = s.t
        }
        for (key, hit) in cache where key.hasPrefix(prefix) && key.hasSuffix("|false") && now < hit.expires {
            if let title = hit.value?.title, !title.isEmpty { names[String(key.dropFirst(prefix.count).prefix { $0 != "|" })] = title }
        }
        return names
    }

    /// El nombre de un título en tu idioma (lo pide a TMDB si no se tiene); nil si no hay que traducir o TMDB no lo tiene.
    public func title(kind: String, imdb: String) async -> String? {
        guard let lang = active, kind == "movie" || kind == "series", imdb.hasPrefix("tt") else { return nil }
        let found = await translation(kind: kind, imdb: imdb, lang: lang, episodes: false)
        return found.flatMap { $0.title.isEmpty ? nil : $0.title }
    }

    /// La ficha en tu idioma (una copia; la original no se toca). En una serie, los títulos y sinopsis de episodio que se
    /// quedan como venían de Cinemeta (en inglés: TMDB no los tiene en tu idioma, o no hay clave) llevan su idioma
    /// (`markUntranslated`), para que la app diga «En inglés» en vez de colarlos como si fueran tuyos.
    public func meta(kind: String, meta: JSON) async -> JSON {
        let imdb = meta["imdb_id"]?.string ?? meta["id"]?.string
        var out = meta
        if let lang = active, kind == "movie" || kind == "series", let imdb, imdb.hasPrefix("tt"),
           let found = await translation(kind: kind, imdb: imdb, lang: lang, episodes: kind == "series"), !found.isEmpty {
            out = Localizer.apply(meta, found)
        }
        guard kind == "series", Localizer.tmdbLanguage(language()) != nil else { return out }
        return Localizer.markUntranslated(original: meta, localized: out)
    }

    /// De qué idioma es lo que trae Cinemeta (siempre inglés).
    public static let sourceLanguage = "en"
    /// En cada episodio de `videos`: el idioma de su nombre y de su sinopsis cuando no están en el de la app.
    public static let nameLanguageKey = "orbital_name_lang", overviewLanguageKey = "orbital_overview_lang"

    /// Marca los episodios cuyo nombre o sinopsis siguen iguales que en Cinemeta (no se tradujeron): llevan
    /// `nameLanguageKey` / `overviewLanguageKey` con `sourceLanguage`. Un nombre de relleno («Episode 3») no se marca: la app
    /// lo dice en tu idioma («Episodio 3»).
    public static func markUntranslated(original: JSON, localized: JSON) -> JSON {
        guard var out = localized.object, let videos = localized["videos"]?.array else { return localized }
        var before: [String: JSON] = [:]
        for v in original["videos"]?.array ?? [] { if let id = v["id"]?.string { before[id] = v } }
        func text(_ v: JSON?, _ a: String, _ b: String) -> String {
            let first = (v?[a]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return first.isEmpty ? (v?[b]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines) : first
        }
        out["videos"] = .array(videos.map { video in
            guard var v = video.object, let id = video["id"]?.string, let old = before[id] else { return video }
            let name = text(video, "name", "title")
            if !name.isEmpty, name == text(old, "name", "title"), !CinemetaParsing.isPlaceholderEpisodeName(name) {
                v[nameLanguageKey] = .string(sourceLanguage)
            }
            let overview = text(video, "overview", "description")
            if !overview.isEmpty, overview == text(old, "overview", "description") { v[overviewLanguageKey] = .string(sourceLanguage) }
            return .object(v)
        })
        return .object(out)
    }

    /// Título y sinopsis de una fila (sin episodios: una consulta por título). Unas cuantas a la vez; al terminar una, entra
    /// la siguiente. Sin funciones anidadas que toquen el grupo: así, en la versión optimizada, la lista que regresaba salía
    /// dañada y la app se cerraba al abrir Inicio.
    public func catalog(kind: String, metas: [JSON]) async -> [JSON] {
        guard let lang = active else { return metas }
        return await withTaskGroup(of: (Int, JSON).self, returning: [JSON].self) { group in
            var out = metas
            var next = 0
            while next < min(Localizer.concurrency, metas.count) {
                let i = next, meta = metas[i]
                group.addTask { (i, await self.localized(meta, kind: kind, lang: lang)) }
                next += 1
            }
            while let (i, meta) = await group.next() {
                out[i] = meta
                if next < metas.count {
                    let j = next, more = metas[j]
                    group.addTask { (j, await self.localized(more, kind: kind, lang: lang)) }
                    next += 1
                }
            }
            return out
        }
    }

    /// Una ficha de una fila con su título y sinopsis traducidos (si TMDB los tiene).
    private func localized(_ meta: JSON, kind: String, lang: String) async -> JSON {
        guard let imdb = meta["id"]?.string, imdb.hasPrefix("tt"),
              let found = await translation(kind: kind, imdb: imdb, lang: lang, episodes: false), !found.isEmpty else { return meta }
        return Localizer.apply(meta, found)
    }

    /// La ficha de Cinemeta con lo que TMDB tiene traducido; lo vacío se queda como estaba.
    public static func apply(_ meta: JSON, _ found: Translation) -> JSON {
        guard var out = meta.object else { return meta }
        if !found.title.isEmpty { out["name"] = .string(found.title) }
        if found.native { out[Localizer.nativeKey] = .bool(true) }
        if !found.poster.isEmpty { out[Localizer.posterKey] = .string(found.poster) }
        if !found.overview.isEmpty { out["description"] = .string(found.overview) }
        if !found.genres.isEmpty { out["genres"] = .array(found.genres.map(JSON.string)) }
        if !found.episodes.isEmpty, let videos = meta["videos"]?.array {
            out["videos"] = .array(videos.map { video in
                guard var v = video.object, let season = video["season"]?.intValue, let episode = video["episode"]?.intValue,
                      let ep = found.episodes[.init(season: season, episode: episode)] else { return video }
                let generic = genericEpisode.firstMatch(in: ep.name, range: NSRange(ep.name.startIndex..., in: ep.name)) != nil
                if !ep.name.isEmpty && !generic { v["name"] = .string(ep.name); v["title"] = nil }
                if !ep.overview.isEmpty { v["overview"] = .string(ep.overview); v["description"] = nil }
                return .object(v)
            })
        }
        return .object(out)
    }
}
