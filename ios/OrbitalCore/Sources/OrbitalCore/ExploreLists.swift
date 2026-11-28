import Foundation

/// «Esta semana» en Explorar (Fernando, 23 nov 2026: ED-B y ED-C de docs/producto/explorar-listas-2026-11-23/): una tabla en
/// el repositorio (`listas/explorar.json`) que la app lee una vez al día. Las listas con fechas (los especiales de Halloween de
/// Los Simpson, lo de Navidad) salen en su temporada y van primero; las demás (listas famosas de MDBList o Trakt) rotan cada
/// semana. Cambiar la tabla en `main` cambia Explorar sin instalar nada. La TV lee la misma tabla (`orbital/foryou/weekly.py`).
public struct ExploreList: Sendable, Equatable, Codable, Identifiable {
    /// Un título escrito en la tabla: un id de IMDb o un capítulo («tt0096697:2:3», serie:temporada:episodio).
    public struct Entry: Sendable, Equatable, Codable {
        public var id: String, kind: String, title: String
        public var year: Int?
        public init(id: String, kind: String, title: String, year: Int? = nil) { self.id = id; self.kind = kind; self.title = title; self.year = year }
    }
    public var id: String
    /// El nombre corto (la tarjeta), el completo (su pantalla) y de qué se trata.
    public var title: String, full: String, about: String
    /// «MM-DD»: desde y hasta cuándo sale (puede cruzar el año: «12-01» a «01-06»). Sin fechas, rota.
    public var from: String?, to: String?
    /// De dónde sale: MDBList («usuario/lista»), Trakt («usuario/lista») o escrita en la tabla.
    public var mdblist: String?, trakt: String?
    public var items: [Entry]?
    /// Su ícono y su color en la tarjeta: uno de los de Temporadas y Géneros («halloween», «navidad», «drama»…). Sin él, uno
    /// fijo según su id, para que ninguna tarjeta quede gris.
    public var art: String?
    /// El nombre, el completo y de qué se trata en inglés, para quien usa la app en inglés (24 nov 2026: «los nombres de las
    /// listas… deberían de cambiar de idioma»). Sin él, en español.
    public var en: Words?
    public struct Words: Sendable, Equatable, Codable {
        public var title: String, full: String, about: String
        public init(title: String, full: String, about: String) { self.title = title; self.full = full; self.about = about }
    }

    /// Sus palabras en el idioma de la app.
    public func words(_ ui: String) -> Words {
        if ui == "en", let en { return en }
        return Words(title: title, full: full, about: about)
    }

    public init(id: String, title: String, full: String? = nil, about: String = "", from: String? = nil, to: String? = nil,
                mdblist: String? = nil, trakt: String? = nil, items: [Entry]? = nil, art: String? = nil) {
        self.id = id; self.title = title; self.full = full ?? title; self.about = about; self.from = from; self.to = to
        self.mdblist = mdblist; self.trakt = trakt; self.items = items; self.art = art
    }

    public var dated: Bool { from != nil && to != nil }

    /// ¿Sale este día? (las de fecha, solo en su temporada; las demás, siempre que les toque).
    public func inSeason(_ day: MonthDay) -> Bool {
        guard let start = from.flatMap(Self.monthDay), let end = to.flatMap(Self.monthDay) else { return false }
        return start <= end ? (start <= day && day <= end) : (day >= start || day <= end)
    }

    static func monthDay(_ s: String) -> MonthDay? {
        let parts = s.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2, (1...12).contains(parts[0]), (1...31).contains(parts[1]) else { return nil }
        return MonthDay(parts[0], parts[1])
    }

    /// Los títulos escritos en la tabla, ya como objetos de una colección (con su lugar).
    public var written: [CanonCollection.Item]? {
        items?.enumerated().map { i, e in .init(imdb: e.id, kind: e.kind, title: e.title, year: e.year, rank: i + 1) }
    }
}

/// Una receta de «Hoy» (LD-C, Fernando, 25 nov 2026): un nombre con gracia y un filtro de TMDB (género, época, calificación,
/// duración…). Cada día salen `daily` distintas; la app esconde lo que ya viste. Como Netflix con sus filas temáticas.
public struct ExploreRecipe: Sendable, Equatable, Codable, Identifiable {
    public var id: String
    public var title: String, full: String?, about: String
    public var art: String?
    public var en: ExploreList.Words?
    public var filter: AdvancedFilter
    public init(id: String, title: String, about: String, art: String? = nil, filter: AdvancedFilter) {
        self.id = id; self.title = title; self.about = about; self.art = art; self.filter = filter
    }
    /// Como lista de Explorar (su tarjeta y su pantalla usan lo mismo que las listas famosas). Su id lleva «hoy-».
    public var list: ExploreList {
        var l = ExploreList(id: "hoy-\(id)", title: title, full: full ?? title, about: about, art: art)
        l.en = en
        return l
    }
}

public struct ExploreTable: Sendable, Equatable, Codable {
    /// Cuántas de las que rotan salen a la vez.
    public var rotate: Int
    public var lists: [ExploreList]
    /// Las recetas de «Hoy» y cuántas salen cada día (sin el campo, 2).
    public var recipes: [ExploreRecipe]?
    public var daily: Int?
    public init(rotate: Int, lists: [ExploreList], recipes: [ExploreRecipe]? = nil, daily: Int? = nil) {
        self.rotate = rotate; self.lists = lists; self.recipes = recipes; self.daily = daily
    }

    /// Las recetas de hoy: cada día (a medianoche UTC, igual en la TV) avanza la rueda `daily` lugares; ninguna se repite
    /// antes de que pasen todas.
    /// Cada día, primero una por ánimo («animo-…»: «Para cuando andas triste», Fernando, 26 nov 2026) y luego las demás, cada
    /// grupo en su propia rueda (todas pasan antes de repetirse).
    public func recipesToday(_ date: Date) -> [ExploreRecipe] {
        let all = recipes ?? [], n = max(0, daily ?? 2)
        guard !all.isEmpty, n > 0 else { return [] }
        let day = Int(floor(date.timeIntervalSince1970 / 86400))   // día UTC a propósito: el mismo que la TV
        func wheel(_ pool: [ExploreRecipe], _ k: Int) -> [ExploreRecipe] {
            guard !pool.isEmpty, k > 0 else { return [] }
            if pool.count <= k { return pool }
            let start = ((day * k) % pool.count + pool.count) % pool.count
            return (0..<k).map { pool[(start + $0) % pool.count] }
        }
        let moods = all.filter { $0.id.hasPrefix(Self.moodPrefix) }, rest = all.filter { !$0.id.hasPrefix(Self.moodPrefix) }
        let mood = wheel(moods, 1)
        return mood + wheel(rest, n - mood.count)
    }
    /// Las recetas por ánimo llevan este id al principio.
    public static let moodPrefix = "animo-"

    public static func parse(_ data: Data) -> ExploreTable? { try? JSONDecoder().decode(ExploreTable.self, from: data) }

    /// Las de esta semana: primero las de temporada que van hoy, luego `rotate` de las demás. Cada lunes (semana UTC) avanza la
    /// rueda; todas pasan antes de que se repita una.
    public func thisWeek(_ date: Date, calendar: Calendar = .current) -> [ExploreList] {
        let parts = calendar.dateComponents([.month, .day], from: date)
        let today = MonthDay(parts.month ?? 1, parts.day ?? 1)
        let seasonal = lists.filter { $0.dated && $0.inSeason(today) }
        let wheel = lists.filter { !$0.dated }
        guard !wheel.isEmpty, rotate > 0 else { return seasonal }
        if wheel.count <= rotate { return seasonal + wheel }
        // Semanas desde el lunes 5 ene 1970 (el 1 fue jueves): así la rueda cambia el lunes y no a media semana.
        let week = Int(floor((date.timeIntervalSince1970 - 4 * 86400) / (7 * 86400)))
        let start = ((week * rotate) % wheel.count + wheel.count) % wheel.count
        return seasonal + (0..<rotate).map { wheel[(start + $0) % wheel.count] }
    }

    /// La tabla de verdad: en `main`, en GitHub (el repositorio es público).
    public static let url = URL(string: "https://raw.githubusercontent.com/blandisc/orbital/main/listas/explorar.json")!
}

extension CanonCollection.Item {
    /// Un capítulo («serie:temporada:episodio»): la serie y el video que se abre.
    public var episode: (show: String, video: String)? {
        let parts = imdb.split(separator: ":")
        guard parts.count == 3 else { return nil }
        return (String(parts[0]), imdb)
    }
}
