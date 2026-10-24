import Foundation
import OrbitalCore

// BOCETO (exp/explorar-genero-temporada): «Por temporada» y «Lo mejor del género» en Buscar.
// Ver docs/bocetos/explorar-genero-temporada.md. La lógica de fechas es pura y tiene prueba (SeasonsTests);
// las listas de títulos de cada temporada son DATOS DE EJEMPLO curados a mano, no vienen de ninguna API.

/// Un día del año sin año (mes y día): las temporadas se repiten cada año.
public struct MonthDay: Hashable, Comparable, Sendable {
    public var month: Int, day: Int
    public init(_ month: Int, _ day: Int) { self.month = month; self.day = day }
    var ordinal: Int { month * 100 + day }
    public static func < (a: MonthDay, b: MonthDay) -> Bool { a.ordinal < b.ordinal }
}

/// Una colección de temporada: cuándo va (de `start` a `end`, ambos incluidos; puede cruzar el año nuevo) y qué títulos lleva.
public struct SeasonalCollection: Identifiable, Hashable, Sendable {
    public struct Pick: Hashable, Sendable {
        public var kind: String, metaID: String, title: String
        public var poster: String { String(format: ForYou.metahubPoster, metaID) }
    }
    /// `halloween`, `muertos`, `navidad`, `sanvalentin`, `verano` (el de `-demo-season`).
    public var id: String
    /// El nombre en español (la pantalla lo traduce como texto de la app).
    public var title: String
    /// La línea de arriba del encabezado.
    public var blurb: String
    public var symbol: String
    public var start: MonthDay, end: MonthDay
    /// DATOS DE EJEMPLO: IMDb de títulos conocidos de esa temporada (los pósters salen de metahub, como el resto de la app).
    public var picks: [Pick]

    /// ¿Cae `day` dentro de la temporada? (Navidad va del 25 de noviembre al 6 de enero: cruza el año).
    public func contains(_ day: MonthDay) -> Bool {
        start <= end ? (start <= day && day <= end) : (day >= start || day <= end)
    }

    /// Cuántos días faltan para que empiece, contando desde `day` (0 si ya va).
    func daysUntilStart(from day: MonthDay) -> Int {
        if contains(day) { return 0 }
        let from = Seasons.dayOfYear(day), to = Seasons.dayOfYear(start)
        return to >= from ? to - from : to + 365 - from
    }
}

public enum Seasons {
    /// Día del año en uno no bisiesto (el 29 de febrero cuenta como 28: no hay temporada que dependa de él).
    static func dayOfYear(_ d: MonthDay) -> Int {
        let before = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
        return before[max(0, min(11, d.month - 1))] + min(d.day, d.month == 2 ? 28 : 31)
    }

    public static func monthDay(_ date: Date, calendar: Calendar = .current) -> MonthDay {
        let c = calendar.dateComponents([.month, .day], from: date)
        return MonthDay(c.month ?? 1, c.day ?? 1)
    }

    /// Las temporadas en orden: la que va hoy primero (o, entre temporadas, la siguiente en llegar) y luego las demás
    /// según lo que falta para cada una. `forced` (`-demo-season`) pone esa primero.
    public static func ordered(on date: Date, calendar: Calendar = .current, forced: String? = nil,
                               from all: [SeasonalCollection] = Seasons.all) -> [SeasonalCollection] {
        let today = monthDay(date, calendar: calendar)
        var out = all.enumerated().sorted { a, b in
            let da = a.element.daysUntilStart(from: today), db = b.element.daysUntilStart(from: today)
            return da != db ? da < db : a.offset < b.offset
        }.map(\.element)
        if let forced, let i = out.firstIndex(where: { $0.id == forced }) { out.insert(out.remove(at: i), at: 0) }
        return out
    }

    /// La temporada que va hoy (nil entre temporadas).
    public static func current(on date: Date, calendar: Calendar = .current, from all: [SeasonalCollection] = Seasons.all) -> SeasonalCollection? {
        let today = monthDay(date, calendar: calendar)
        return all.first { $0.contains(today) }
    }

    private static func m(_ id: String, _ title: String) -> SeasonalCollection.Pick { .init(kind: "movie", metaID: id, title: title) }
    private static func s(_ id: String, _ title: String) -> SeasonalCollection.Pick { .init(kind: "series", metaID: id, title: title) }

    /// DATOS DE EJEMPLO (boceto): las colecciones y sus títulos, escritos a mano. Las fechas no se enciman.
    public static let all: [SeasonalCollection] = [
        SeasonalCollection(id: "halloween", title: "Halloween", blurb: "Sustos, brujas y calabazas", symbol: "moon.stars.fill",
                           start: MonthDay(9, 25), end: MonthDay(10, 31), picks: [
            m("tt0077651", "Halloween"), m("tt0107120", "Hocus Pocus"), s("tt13443470", "Wednesday"), m("tt0862856", "Trick 'r Treat"),
            m("tt0094721", "Beetlejuice"), s("tt4574334", "Stranger Things"), m("tt0081505", "The Shining"), m("tt0327597", "Coraline"),
            s("tt6763664", "The Haunting of Hill House"), m("tt0117571", "Scream"), m("tt1457767", "The Conjuring"),
        ]),
        SeasonalCollection(id: "muertos", title: "Día de Muertos", blurb: "Para recordar a los que se fueron", symbol: "sparkles",
                           start: MonthDay(11, 1), end: MonthDay(11, 10), picks: [
            m("tt2380307", "Coco"), m("tt2262227", "The Book of Life"), m("tt0121164", "Corpse Bride"), m("tt2379713", "Spectre"),
        ]),
        SeasonalCollection(id: "navidad", title: "Navidad", blurb: "Para ver en familia con chocolate caliente", symbol: "snowflake",
                           start: MonthDay(11, 25), end: MonthDay(1, 6), picks: [
            m("tt0099785", "Home Alone"), m("tt0319343", "Elf"), m("tt4729430", "Klaus"), m("tt0314331", "Love Actually"),
            m("tt0170016", "How the Grinch Stole Christmas"), m("tt0338348", "The Polar Express"), m("tt0095016", "Die Hard"),
            m("tt0457939", "The Holiday"), m("tt0038650", "It's a Wonderful Life"), m("tt0107688", "The Nightmare Before Christmas"),
        ]),
        SeasonalCollection(id: "sanvalentin", title: "San Valentín", blurb: "Romance para ver en pareja", symbol: "heart.fill",
                           start: MonthDay(1, 25), end: MonthDay(2, 14), picks: [
            m("tt0332280", "The Notebook"), m("tt0414387", "Pride & Prejudice"), m("tt3783958", "La La Land"), s("tt8740790", "Bridgerton"),
            m("tt0098635", "When Harry Met Sally..."), m("tt0125439", "Notting Hill"), m("tt0112471", "Before Sunrise"), m("tt0120338", "Titanic"),
        ]),
        SeasonalCollection(id: "verano", title: "Verano", blurb: "Sol, playa y vacaciones", symbol: "sun.max.fill",
                           start: MonthDay(6, 1), end: MonthDay(8, 31), picks: [
            m("tt0073195", "Jaws"), m("tt12801262", "Luca"), m("tt0795421", "Mamma Mia!"), s("tt13406094", "The White Lotus"),
            m("tt5726616", "Call Me by Your Name"), m("tt0077631", "Grease"), m("tt0108037", "The Sandlot"), s("tt10293938", "Outer Banks"),
        ]),
    ]
}

/// «Lo mejor del género»: los mejor calificados (IMDb) de un género, películas y series juntas.
public enum GenreTop {
    /// Cuántos van en la fila con puesto.
    public static let count = 10

    /// Ordena por calificación de IMDb (mayor primero); sin calificación, al final. Empates: como venían.
    /// Un título repetido (mismo id) cuenta una vez.
    public static func rank(_ items: [(item: CatalogItem, rating: Double?)], limit: Int = count) -> [CatalogItem] {
        var seen = Set<String>()
        return items.enumerated()
            .filter { seen.insert($0.element.item.id).inserted }
            .sorted { a, b in
                let ra = a.element.rating ?? -1, rb = b.element.rating ?? -1
                return ra != rb ? ra > rb : a.offset < b.offset
            }
            .prefix(limit).map(\.element.item)
    }
}
