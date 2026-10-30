import Foundation

/// Colecciones (docs/producto/muvy-busqueda-premios/prototipo-repisa.html): el canon que «hay que ver». Dos familias, nada
/// más: premios (los ganadores que ya trae la app, `Awards`) y listas famosas (Criterion y el Top 250 de IMDb, listas
/// públicas de MDBList, sin clave). Lo que viste las va pintando.
public struct CanonCollection: Sendable, Equatable, Identifiable {
    public enum Family: String, Sendable { case award, list }
    /// Cómo se agrupa en su repisa: por década del premio, por década de estreno o de diez en diez por lugar.
    public enum Grouping: Sendable { case awardDecade, releaseDecade, rank }
    public struct Item: Sendable, Equatable, Identifiable {
        public var imdb: String, kind: String, title: String
        /// El año que se muestra: el de la ceremonia (premios) o el de estreno (listas). Una serie que ganó varios años, el
        /// primero y el último («2008–11»).
        public var year: Int?, lastYear: Int?
        public var rank: Int?
        public var id: String { imdb }
        public var poster: String { String(format: ForYou.metahubPoster, imdb) }
        public init(imdb: String, kind: String, title: String, year: Int?, lastYear: Int? = nil, rank: Int? = nil) {
            self.imdb = imdb; self.kind = kind; self.title = title; self.year = year; self.lastYear = lastYear; self.rank = rank
        }
    }

    public var id: String
    public var family: Family
    public var grouping: Grouping
    public var items: [Item]
    /// Cuántos tiene de verdad (las listas largas se cargan completas; si no llegaron, se sabe el total igual).
    public var total: Int

    public init(id: String, family: Family, grouping: Grouping, items: [Item], total: Int? = nil) {
        self.id = id; self.family = family; self.grouping = grouping; self.items = items; self.total = total ?? items.count
    }

    public func seen(_ watched: Set<String>) -> Int { items.filter { watched.contains($0.imdb) }.count }

    /// Los grupos de su repisa, en orden (lo más reciente primero, salvo el lugar: del 1 en adelante).
    public func groups(newestFirst: Bool = true) -> [(title: String, items: [Item])] {
        switch grouping {
        case .rank:
            let sorted = items.sorted { ($0.rank ?? .max) < ($1.rank ?? .max) }
            return stride(from: 0, to: sorted.count, by: 10).map { i in ("\(i + 1) – \(min(i + 10, sorted.count))", Array(sorted[i..<min(i + 10, sorted.count)])) }
        case .awardDecade, .releaseDecade:
            let byDecade = Dictionary(grouping: items) { ($0.year ?? 0) / 10 * 10 }
            let decades = byDecade.keys.sorted(by: newestFirst ? (>) : (<))
            return decades.map { d in
                let inside = (byDecade[d] ?? []).sorted { newestFirst ? ($0.year ?? 0) > ($1.year ?? 0) : ($0.year ?? 0) < ($1.year ?? 0) }
                return (Canon.decadeName(d), inside)
            }
        }
    }

    /// La que conviene ver ahora: la más reciente que te falta (premios), la de mejor lugar (Top 250) o la más clásica
    /// (Criterion).
    public func next(_ watched: Set<String>) -> Item? {
        let missing = items.filter { !watched.contains($0.imdb) }
        switch grouping {
        case .awardDecade: return missing.max { ($0.year ?? 0) < ($1.year ?? 0) }
        case .rank: return missing.min { ($0.rank ?? .max) < ($1.rank ?? .max) }
        case .releaseDecade: return missing.min { ($0.year ?? .max) < ($1.year ?? .max) }
        }
    }
}

public enum Canon {
    /// Las dos listas famosas (MDBList, públicas): usuario, lista y cuántos títulos tiene.
    public static let lists: [(id: String, user: String, slug: String, total: Int, grouping: CanonCollection.Grouping)] = [
        ("criterion", "pizzadeath", "the-criterion-collection", 1000, .releaseDecade),
        ("top250", "georgenilas", "imdb-top-250", 250, .rank),
    ]

    /// El orden de los premios en la repisa (y en Para ti, para que no se contradigan).
    public static let awardOrder = ["oscar", "palm", "ariel", "globe", "bafta", "emmy"]

    /// «Los 2020», «Los 90», «Los 2000».
    public static func decadeName(_ d: Int) -> String { d >= 2000 ? "Los \(d)" : "Los \(String(format: "%02d", d % 100))" }

    /// Los premios que ya trae la app como colecciones (una serie que ganó varios años va una vez, con sus años).
    public static func awards(_ all: [AwardCollection] = Awards.all) -> [CanonCollection] {
        // El orden de la repisa: Óscar, Palma y Ariel al frente (como en la maqueta); luego los demás.
        let order = awardOrder
        let sorted = all.sorted { (order.firstIndex(of: $0.id) ?? order.count) < (order.firstIndex(of: $1.id) ?? order.count) }
        return sorted.map { award in
            var order: [String] = []
            var byID: [String: CanonCollection.Item] = [:]
            for w in award.winners {
                if var have = byID[w.imdb] {
                    let first = have.year ?? w.awardYear, last = have.lastYear ?? first
                    have.year = min(first, w.awardYear)
                    have.lastYear = max(last, w.awardYear)
                    byID[w.imdb] = have
                } else {
                    order.append(w.imdb)
                    byID[w.imdb] = .init(imdb: w.imdb, kind: award.kind, title: w.title, year: w.awardYear)
                }
            }
            return CanonCollection(id: award.id, family: .award, grouping: .awardDecade, items: order.compactMap { byID[$0] })
        }
    }

    /// Una lista pública de MDBList → sus títulos con IMDb (y su lugar, si lo trae).
    public static func list(http: HTTPClient, user: String, slug: String) async throws -> [CanonCollection.Item] {
        guard let url = URL(string: "https://mdblist.com/lists/\(user)/\(slug)/json") else { return [] }
        let response = try await http.send(HTTPRequest(url: url, headers: ["User-Agent": "Orbital"], timeout: 15))
        guard response.status == 200, let json = JSON.parse(response.data) else { throw NetworkError("MDBList no contestó") }
        let rows = json.array ?? ((json["movies"]?.array ?? []) + (json["shows"]?.array ?? []))
        var seen = Set<String>()
        return rows.enumerated().compactMap { i, r in
            guard let imdb = r["imdb_id"]?.string, imdb.hasPrefix("tt"), seen.insert(imdb).inserted else { return nil }
            return .init(imdb: imdb, kind: r["mediatype"]?.string == "show" ? "series" : "movie", title: r["title"]?.string ?? "",
                         year: r["release_year"]?.intValue, rank: i + 1)
        }
    }
}
