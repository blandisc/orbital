import Foundation

/// Un susto de una película: en qué segundo, qué pasa y si es de los fuertes.
public struct JumpScare: Sendable, Equatable, Codable {
    public var time: Double
    public var text: String
    public var major: Bool
    public init(time: Double, text: String, major: Bool) { self.time = time; self.text = text; self.major = major }
}

/// El mapa de sustos de una película (Where's The Jump, hecho a mano por su comunidad: cada susto con su minuto y los fuertes
/// en negritas). Se busca por nombre en inglés y año, y se confirma con el id de IMDb que trae la página.
public struct JumpScares: Sendable {
    public static let site = "https://wheresthejump.com"
    let http: HTTPClient
    public init(http: HTTPClient) { self.http = http }

    /// Los sustos de una película; [] si la página existe pero no tiene, nil si no hay página (o no es esa película).
    public func scares(title: String, year: Int?, imdb: String?) async -> [JumpScare]? {
        // 1) La página directa (nombre y año); el año de Cinemeta a veces es uno más o menos que el del sitio.
        for y in [year, year.map { $0 - 1 }, year.map { $0 + 1 }].compactMap({ $0 }) {
            if let url = Self.pageURL(title: title, year: y), let html = await page(url), let scares = Self.checked(html, imdb: imdb) { return scares }
        }
        // 2) La búsqueda del sitio: los primeros resultados, hasta el que sea esa película (su id de IMDb).
        guard let search = Self.searchURL(title: title), let html = await page(search) else { return nil }
        for link in Self.searchResults(html, year: year).prefix(Self.maxCandidates) {
            if let found = await page(link), let scares = Self.checked(found, imdb: imdb) { return scares }
        }
        return nil
    }

    static let maxCandidates = 4

    private func page(_ url: URL) async -> String? {
        guard let response = try? await http.send(HTTPRequest(url: url, headers: ["User-Agent": "Mozilla/5.0 Orbital"], timeout: 10)),
              response.status == 200 else { return nil }
        return String(data: response.data, encoding: .utf8)
    }

    /// La página es de esa película (su id de IMDb aparece) y trae su lista.
    static func checked(_ html: String, imdb: String?) -> [JumpScare]? {
        if let imdb, !html.contains("title/\(imdb)") { return nil }
        return parse(html)
    }

    /// «jump-scares-in-insidious-2010».
    static func pageURL(title: String, year: Int?) -> URL? {
        let slug = slugify(title) + (year.map { "-\($0)" } ?? "")
        return URL(string: "\(site)/jump-scares-in-\(slug)/")
    }

    static func searchURL(title: String) -> URL? {
        var c = URLComponents(string: site + "/")!
        c.queryItems = [URLQueryItem(name: "s", value: title)]
        return c.url
    }

    /// Los resultados de la búsqueda, los de ese año (o uno cerca) primero.
    static func searchResults(_ html: String, year: Int?) -> [URL] {
        var seen = Set<String>()
        let links = matches(#"https://wheresthejump\.com/jump-scares-in-[a-z0-9-]+/"#, in: html).filter { seen.insert($0).inserted }
        func close(_ link: String) -> Int {
            guard let year, let y = link.split(separator: "-").last.flatMap({ Int($0.dropLast()) }) else { return 9 }
            return abs(y - year)
        }
        return links.sorted { close($0) < close($1) }.compactMap(URL.init(string:))
    }

    static func slugify(_ text: String) -> String {
        let plain = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en")).lowercased()
            .replacingOccurrences(of: "&", with: "and").replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "")
        let parts = plain.split { !$0.isLetter && !$0.isNumber }
        return parts.joined(separator: "-")
    }

    /// «00:13:35 – A ladder cracks…», un renglón por susto; los que van en `<strong>` son los fuertes.
    static func parse(_ html: String) -> [JumpScare] {
        let cleaned = html.replacingOccurrences(of: #"<(script|style)[\s\S]*?</\1>"#, with: " ", options: .regularExpression)
        // En la página: «<p><strong>01:30:29 <span class="spoilerdescription">– A hand…</span></strong></p>».
        let pattern = #"(<strong>|<b>)?\s*(\d{1,2}):(\d{2}):(\d{2})\s*(?:<[^>]+>\s*)*(?:–|&#8211;|-|&ndash;)\s*([^<]{3,220})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = cleaned as NSString
        var out: [JumpScare] = []
        for m in regex.matches(in: cleaned, range: NSRange(location: 0, length: ns.length)) {
            func group(_ i: Int) -> String? { m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i)) }
            guard let h = group(2).flatMap(Double.init), let mi = group(3).flatMap(Double.init), let s = group(4).flatMap(Double.init),
                  let text = group(5) else { continue }
            let time = h * 3600 + mi * 60 + s
            guard !out.contains(where: { $0.time == time }) else { continue }
            out.append(JumpScare(time: time, text: decode(text).trimmingCharacters(in: .whitespacesAndNewlines), major: group(1) != nil))
        }
        return out.sorted { $0.time < $1.time }
    }

    static func decode(_ text: String) -> String {
        var s = text
        for (entity, char) in [("&#8217;", "’"), ("&#8216;", "‘"), ("&#8220;", "“"), ("&#8221;", "”"), ("&amp;", "&"), ("&quot;", "\""), ("&#039;", "'"), ("&nbsp;", " ")] {
            s = s.replacingOccurrences(of: entity, with: char)
        }
        return s
    }

    static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }
}
