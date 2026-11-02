import Foundation

/// Letterboxd sin API (Fernando, 1 nov 2026: solo leer; la API oficial no). Todo sale de lo público de tu perfil:
///
///     GET https://letterboxd.com/{usuario}/rss/              tu diario: las últimas ~50, con estrellas, ♥ y reseña
///     GET https://letterboxd.com/{usuario}/lists/            tus listas (nombre, cuántas películas)
///     GET https://letterboxd.com/{usuario}/list/{lista}/     las películas de una lista (de 100 en 100: /page/2/)
///     GET https://letterboxd.com/film/{película}/            su código de TMDB e IMDb (se recuerda para siempre)
///
/// Y, una vez, el archivo de exportación (`LetterboxdArchive`). Orbital nunca escribe en Letterboxd.
public struct Letterboxd: Sendable {
    public static let site = "https://letterboxd.com"
    /// Un navegador cualquiera: con otro nombre, Letterboxd contesta con la pantalla de «comprobando que eres humano».
    static let agent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
    /// Cuántas páginas de una lista se leen (100 por página): las listas larguísimas se quedan en 500.
    static let maxListPages = 5, maxListsPages = 3

    let http: HTTPClient
    let kv: KeyValueStore

    public init(http: HTTPClient, kv: KeyValueStore) { self.http = http; self.kv = kv }

    /// Un usuario de Letterboxd: letras, números y «_» (lo que se escriba con @ o espacios se limpia).
    public static func cleanUser(_ raw: String) -> String? {
        let user = raw.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "@/"))
            .replacingOccurrences(of: "https://letterboxd.com/", with: "").split(separator: "/").first.map(String.init)?.lowercased() ?? ""
        guard !user.isEmpty, user.range(of: #"^[a-z0-9_]{2,40}$"#, options: .regularExpression) != nil else { return nil }
        return user
    }

    private func page(_ path: String) async throws -> String {
        guard let url = URL(string: Self.site + path) else { throw NetworkError("Dirección inválida") }
        let response = try await http.send(HTTPRequest(url: url, headers: ["User-Agent": Self.agent, "Accept-Language": "en"], timeout: 15))
        if response.status == 404 { throw LetterboxdError.notFound }
        guard response.status == 200 else { throw NetworkError("Letterboxd no contestó (\(response.status))") }
        return String(decoding: response.data, as: UTF8.self)
    }

    // MARK: el diario

    /// Tu diario reciente (lo más nuevo primero). Un usuario que no existe: `LetterboxdError.notFound`.
    public func diary(user: String) async throws -> [LetterboxdEntry] {
        Self.parseDiary(try await page("/\(user)/rss/"))
    }

    static func parseDiary(_ xml: String) -> [LetterboxdEntry] {
        xml.components(separatedBy: "<item>").dropFirst().compactMap { raw in
            let item = raw.components(separatedBy: "</item>").first ?? raw
            guard let title = tag("letterboxd:filmTitle", in: item).map(decodeEntities), !title.isEmpty else { return nil }   // lo que no es una película (una lista nueva)
            let link = tag("link", in: item) ?? ""
            let slug = link.range(of: #"/film/[^/]+"#, options: .regularExpression).map { String(link[$0].dropFirst("/film/".count)) }
            var entry = LetterboxdEntry(title: title, year: tag("letterboxd:filmYear", in: item).flatMap { Int($0) }, slug: slug)
            entry.tmdbID = tag("tmdb:movieId", in: item).flatMap { Int($0) }
            entry.watched = tag("letterboxd:watchedDate", in: item).flatMap(LetterboxdEntry.day)
            entry.rating = tag("letterboxd:memberRating", in: item).flatMap { Double($0) }
            entry.liked = tag("letterboxd:memberLike", in: item) == "Yes"
            entry.rewatch = tag("letterboxd:rewatch", in: item) == "Yes"
            entry.review = review(fromDescription: tag("description", in: item) ?? "")
            entry.id = tag("guid", in: item) ?? entry.id
            return entry
        }
    }

    /// La reseña de una entrada: los párrafos que no son el póster, «Watched on…» ni el aviso de spoilers.
    static func review(fromDescription raw: String) -> String? {
        let html = raw.replacingOccurrences(of: "<![CDATA[", with: "").replacingOccurrences(of: "]]>", with: "")
        let paragraphs = html.components(separatedBy: "<p>").dropFirst().map { $0.components(separatedBy: "</p>").first ?? "" }
            .filter { !$0.contains("<img") }
            .map { decodeEntities($0.replacingOccurrences(of: "<br />", with: "\n").replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("Watched on ") && !$0.hasPrefix("This review may contain spoilers") }
        return paragraphs.isEmpty ? nil : paragraphs.joined(separator: "\n\n")
    }

    // MARK: tus listas

    /// Tus listas públicas, como las tienes ordenadas en Letterboxd.
    public func lists(user: String) async throws -> [LetterboxdList] {
        var out: [LetterboxdList] = []
        for n in 1...Self.maxListsPages {
            let found = Self.parseLists(try await page("/\(user)/lists/" + (n > 1 ? "page/\(n)/" : "")), user: user)
            out += found.filter { list in !out.contains { $0.slug == list.slug } }
            if found.count < 12 { break }   // Letterboxd enseña 12 por página
        }
        return out
    }

    static func parseLists(_ html: String, user: String) -> [LetterboxdList] {
        html.components(separatedBy: "<article class=\"list-summary").dropFirst().compactMap { block in
            let pattern = #"<h2 class="name[^"]*">\s*<a href="/[^/]+/list/([^/"]+)/">([^<]+)</a>"#
            guard let m = firstMatch(pattern, in: block), m.count == 3 else { return nil }
            let count = firstMatch(#"<span class="value">([\d,]+)&nbsp;film"#, in: block)?.last.flatMap { Int($0.replacingOccurrences(of: ",", with: "")) }
            return LetterboxdList(slug: m[1], name: decodeEntities(m[2]).trimmingCharacters(in: .whitespacesAndNewlines), count: count)
        }
    }

    /// Las películas de una lista, en su orden (título, año y su nombre en Letterboxd).
    public func listFilms(user: String, slug: String) async throws -> [LetterboxdFilm] {
        var out: [LetterboxdFilm] = []
        for n in 1...Self.maxListPages {
            let found = Self.parseFilms(try await page("/\(user)/list/\(slug)/" + (n > 1 ? "page/\(n)/" : "")))
            out += found.filter { f in !out.contains { $0.slug == f.slug } }
            if found.count < 100 { break }
        }
        return out
    }

    static func parseFilms(_ html: String) -> [LetterboxdFilm] {
        // Solo la cuadrícula de la lista: al lado vienen otras listas tuyas (con sus pósters encimados), que no son de esta.
        let grid = html.components(separatedBy: "poster-list-overlapped").first ?? html
        var seen = Set<String>(), out: [LetterboxdFilm] = []
        for m in allMatches(#"data-item-name="([^"]+)"[^>]*?data-item-slug="([^"]+)""#, in: grid) where m.count == 3 && seen.insert(m[2]).inserted {
            let full = decodeEntities(m[1])
            // «The Testament of Ann Lee (2025)» → el título y el año.
            if let y = firstMatch(#"^(.*) \((\d{4})\)$"#, in: full), y.count == 3 { out.append(LetterboxdFilm(slug: m[2], title: y[1], year: Int(y[2]))) }
            else { out.append(LetterboxdFilm(slug: m[2], title: full, year: nil)) }
        }
        return out
    }

    // MARK: de película a IMDb

    /// El IMDb (y si es película o serie) de una película de Letterboxd, de su página; se recuerda para siempre.
    public func resolve(slug: String) async -> LetterboxdMatch? {
        let key = "lb-film.\(slug)"
        if let saved = kv.data(key), let match = try? JSONDecoder().decode(LetterboxdMatch.self, from: saved) { return match }
        guard let html = try? await page("/film/\(slug)/"), let match = Self.parseFilmPage(html) else { return nil }
        kv.set(key, data: try? JSONEncoder().encode(match))
        return match
    }

    static func parseFilmPage(_ html: String) -> LetterboxdMatch? {
        guard let imdb = firstMatch(#"imdb\.com/title/(tt\d+)"#, in: html)?.last else { return nil }
        let tmdb = firstMatch(#"data-tmdb-id="(\d+)""#, in: html)?.last.flatMap { Int($0) }
        let kind = firstMatch(#"data-tmdb-type="(\w+)""#, in: html)?.last == "tv" ? "series" : "movie"
        return LetterboxdMatch(imdb: imdb, kind: kind, tmdbID: tmdb)
    }

    // MARK: lo que dice Letterboxd de una película (su promedio y sus reseñas populares)

    /// Cuánto se recuerda lo de una película (su promedio cambia poco).
    public static let infoTTL: TimeInterval = 3 * 24 * 3600

    /// El promedio de Letterboxd (0.5–5) y sus reseñas populares de una película, por su IMDb (Letterboxd tiene una
    /// dirección que lleva de IMDb a su página). nil si Letterboxd no la tiene (casi todas las series) o no contestó.
    public func info(imdb: String, now: Date = Date()) async -> LetterboxdFilmInfo? {
        guard imdb.range(of: #"^tt\d+$"#, options: .regularExpression) != nil else { return nil }
        let key = "lb-info.\(imdb)"
        if let saved = kv.data(key), let info = try? JSONDecoder().decode(LetterboxdFilmInfo.self, from: saved), now.timeIntervalSince(info.fetchedAt) < Self.infoTTL {
            return info.missing ? nil : info
        }
        do {
            let html = try await page("/imdb/\(imdb)/")
            // Solo se recuerda que no la tiene si Letterboxd lo dice («IMDb ID Not found», que llega con 200). Una página que no se
            // puede leer (la verificación de Cloudflare, o un cambio de su HTML) no se guarda: antes la película desaparecía de los
            // filtros y de sus reseñas por tres días.
            guard var info = Self.parseFilmInfo(html) ?? (Self.saysNotFound(html) ? LetterboxdFilmInfo(missing: true) : nil) else { return nil }
            info.fetchedAt = now
            kv.set(key, data: try? JSONEncoder().encode(info))
            return info.missing ? nil : info
        } catch LetterboxdError.notFound {
            kv.set(key, data: try? JSONEncoder().encode(LetterboxdFilmInfo(missing: true, fetchedAt: now)))   // que no la tiene, también se recuerda
            return nil
        } catch { return nil }
    }

    /// El promedio de muchas películas a la vez (para ordenar o filtrar), de pocas en pocas.
    public func averages(_ imdbs: [String], concurrency: Int = 4) async -> [String: Double] {
        let wanted = Array(Set(imdbs))
        return await withTaskGroup(of: (String, Double?).self) { group in
            var next = 0, out: [String: Double] = [:]
            func add() { guard next < wanted.count, !Task.isCancelled else { return }; let id = wanted[next]; next += 1; group.addTask { (id, await self.info(imdb: id)?.average) } }
            for _ in 0..<concurrency { add() }
            for await (id, avg) in group { if let avg { out[id] = avg }; add() }
            return out
        }
    }

    /// La página de Letterboxd que dice que no tiene esa película («IMDb ID Not found»).
    static func saysNotFound(_ html: String) -> Bool { html.range(of: "not found", options: .caseInsensitive) != nil && !html.contains("data-tmdb-id") }

    static func parseFilmInfo(_ html: String) -> LetterboxdFilmInfo? {
        guard html.contains("data-tmdb-id") || html.contains("twitter:data2") else { return nil }
        var info = LetterboxdFilmInfo()
        info.slug = firstMatch(#"<meta property="og:url" content="https://letterboxd\.com/film/([^/"]+)/""#, in: html)?.last
        info.average = firstMatch(#"name="twitter:data2" content="([\d.]+) out of 5""#, in: html)?.last.flatMap { Double($0) }
        info.reviews = html.components(separatedBy: "<article class=\"production-viewing").dropFirst().prefix(8).compactMap { raw in
            let block = raw.components(separatedBy: "</article>").first ?? raw
            guard let author = firstMatch(#"<strong class="displayname">([^<]+)</strong>"#, in: block)?.last.map(decodeEntities) else { return nil }
            let body = block.components(separatedBy: "js-review-body").dropFirst().first ?? ""
            let text = allMatches(#"<p>(.*?)</p>"#, in: body.components(separatedBy: "viewing-actions").first ?? body).map {
                decodeEntities($0[1].replacingOccurrences(of: "<br />", with: "\n").replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }.joined(separator: "\n\n")
            guard !text.isEmpty else { return nil }
            let stars = firstMatch(#"aria-label="([★½]+)""#, in: block)?.last
            let rating = stars.map { Double($0.filter { $0 == "★" }.count) + ($0.contains("½") ? 0.5 : 0) }
            let likes = firstMatch(#"data-count="(\d+)""#, in: block)?.last.flatMap { Int($0) }
            return LetterboxdPublicReview(author: author.trimmingCharacters(in: .whitespaces), rating: rating, text: text,
                                          likes: likes, spoiler: block.contains("This review may contain spoilers"))
        }
        return info
    }

    // MARK: texto

    static func tag(_ name: String, in text: String) -> String? {
        guard let start = text.range(of: "<\(name)>"), let end = text.range(of: "</\(name)>", range: start.upperBound..<text.endIndex) else { return nil }
        return String(text[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeEntities(_ s: String) -> String {
        var out = s
        for (k, v) in [("&amp;", "&"), ("&quot;", "\""), ("&#039;", "'"), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "),
                       ("&rsquo;", "’"), ("&lsquo;", "‘"), ("&ldquo;", "“"), ("&rdquo;", "”"), ("&hellip;", "…"), ("&ndash;", "–"), ("&mdash;", "—")] {
            out = out.replacingOccurrences(of: k, with: v)
        }
        // Las letras con acento por su nombre: «&oacute;» → «ó», «&ntilde;» → «ñ», «&uuml;» → «ü».
        let marks: [String: String] = ["acute": "\u{301}", "grave": "\u{300}", "tilde": "\u{303}", "uml": "\u{308}", "circ": "\u{302}", "cedil": "\u{327}"]
        while let r = out.range(of: #"&([A-Za-z])(acute|grave|tilde|uml|circ|cedil);"#, options: .regularExpression) {
            let name = out[r].dropFirst().dropLast()
            out.replaceSubrange(r, with: (String(name.prefix(1)) + (marks[String(name.dropFirst())] ?? "")).precomposedStringWithCanonicalMapping)
        }
        // «&#233;» → «é»
        while let r = out.range(of: #"&#(\d+);"#, options: .regularExpression) {
            let code = out[r].dropFirst(2).dropLast()
            out.replaceSubrange(r, with: UInt32(code).flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? "")
        }
        return out
    }

    static func firstMatch(_ pattern: String, in text: String) -> [String]? { allMatches(pattern, in: text, limit: 1).first }

    static func allMatches(_ pattern: String, in text: String, limit: Int = .max) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).prefix(limit).map { m in
            (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
        }
    }
}

public enum LetterboxdError: Error, Sendable, CustomStringConvertible {
    case notFound
    public var description: String { "No encontré ese usuario en Letterboxd" }
}

/// Una entrada de tu diario (o de tus calificaciones, si viene del archivo): la película, cuándo la viste, tus estrellas
/// (0.5–5), si le diste ♥, si fue otra vez y tu reseña. `imdb` se llena al cruzarla con TMDB.
public struct LetterboxdEntry: Sendable, Codable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var year: Int?
    public var slug: String?
    public var tmdbID: Int?
    public var imdb: String?
    public var kind = "movie"
    public var watched: Date?
    public var rating: Double?
    public var liked = false
    public var rewatch = false
    public var review: String?

    public init(title: String, year: Int?, slug: String? = nil) {
        self.title = title; self.year = year; self.slug = slug
        id = "\(slug ?? title)|\(year ?? 0)"
    }

    /// Las estrellas en la escala de Trakt (1–10): ★★★★ = 8.
    public var traktRating: Int? { rating.map { max(1, min(10, Int(($0 * 2).rounded()))) } }

    /// La misma película vista el mismo día (para no repetir lo del diario y lo del archivo).
    public var sameWatchKey: String { "\(imdb ?? "\(title.lowercased())|\(year ?? 0)")|\(watched.map { Int($0.timeIntervalSince1970 / 86400) } ?? -1)" }

    static func day(_ text: String) -> Date? {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(text.prefix(10)))
    }
}

public struct LetterboxdList: Sendable, Codable, Equatable, Identifiable {
    public var slug: String, name: String, count: Int?
    public var id: String { slug }
    public init(slug: String, name: String, count: Int?) { self.slug = slug; self.name = name; self.count = count }
}

public struct LetterboxdFilm: Sendable, Codable, Equatable {
    public var slug: String, title: String, year: Int?
    public init(slug: String, title: String, year: Int?) { self.slug = slug; self.title = title; self.year = year }
}

public struct LetterboxdMatch: Sendable, Codable, Equatable {
    public var imdb: String, kind: String, tmdbID: Int?
    public init(imdb: String, kind: String, tmdbID: Int?) { self.imdb = imdb; self.kind = kind; self.tmdbID = tmdbID }
}

/// Lo que dice Letterboxd de una película: su promedio (0.5–5) y sus reseñas populares. `missing`: Letterboxd no la tiene.
public struct LetterboxdFilmInfo: Sendable, Codable, Equatable {
    public var slug: String?
    public var average: Double?
    public var reviews: [LetterboxdPublicReview] = []
    public var missing = false
    public var fetchedAt = Date.distantPast
    public init(slug: String? = nil, average: Double? = nil, reviews: [LetterboxdPublicReview] = [], missing: Bool = false, fetchedAt: Date = .distantPast) {
        self.slug = slug; self.average = average; self.reviews = reviews; self.missing = missing; self.fetchedAt = fetchedAt
    }
}

/// Una reseña popular de alguien en Letterboxd.
public struct LetterboxdPublicReview: Sendable, Codable, Equatable, Identifiable {
    public var author: String, rating: Double?, text: String, likes: Int?, spoiler: Bool
    public var id: String { author + String(text.prefix(24)) }
    public init(author: String, rating: Double?, text: String, likes: Int?, spoiler: Bool) {
        self.author = author; self.rating = rating; self.text = text; self.likes = likes; self.spoiler = spoiler
    }
}
