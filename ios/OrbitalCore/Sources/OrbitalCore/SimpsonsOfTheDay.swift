import Foundation

/// «Un Simpson del día» (el widget): un episodio distinto cada día, el mismo todo el día en cualquier aparato. La app arma la
/// semana (con la imagen de cada episodio ya reducida junto al archivo) y el widget solo la lee.
public struct SimpsonsOfTheDay: Codable, Equatable, Sendable {
    public struct Day: Codable, Equatable, Sendable, Identifiable {
        /// El día (a medianoche, en la hora de aquí).
        public var day: Date
        public var season: Int
        public var episode: Int
        /// El nombre del episodio (vacío si Cinemeta no lo trae).
        public var title: String
        /// El id del video en Stremio («tt0096697:6:12»): tocar el widget lo reproduce.
        public var videoID: String
        /// La imagen del episodio (remota) y la reducida, junto al archivo.
        public var still: String
        public var imageFile: String?
        public var id: Date { day }

        public init(day: Date, season: Int, episode: Int, title: String, videoID: String, still: String, imageFile: String? = nil) {
            self.day = day; self.season = season; self.episode = episode; self.title = title; self.videoID = videoID
            self.still = still; self.imageFile = imageFile
        }

        /// Reproducir ese episodio en la app.
        public var link: URL? { WidgetLink.play(kind: "series", id: SimpsonsOfTheDay.seriesID, video: videoID) }
    }

    public static let seriesID = "tt0096697"
    public var days: [Day]
    /// Las temporadas de Ajustes con que se armó (si cambian, se arma de nuevo).
    public var seasons: [Int]
    public init(days: [Day], seasons: [Int]) { self.days = days; self.seasons = seasons }

    /// El de `date` (o, si la app no ha armado ese día, el último que haya).
    public func day(for date: Date, calendar: Calendar = .current) -> Day? {
        days.first { calendar.isDate($0.day, inSameDayAs: date) } ?? days.last { $0.day <= date }
    }

    /// Cuál de `count` episodios toca el día `date`: salta por la lista con un paso grande y primo con `count`, así dos días
    /// seguidos no caen en episodios vecinos y no se repite uno hasta recorrerlos todos.
    public static func index(for date: Date, count: Int, calendar: Calendar = .current) -> Int {
        guard count > 0 else { return 0 }
        let start = calendar.startOfDay(for: date)
        let day = Int((start.timeIntervalSince1970 + Double(calendar.timeZone.secondsFromGMT(for: start))) / 86_400)
        var step = 7919 % count
        if step == 0 { step = 1 }
        while gcd(step, count) != 1 { step += 1 }
        return ((day % count) * step + 13) % count
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) -> SimpsonsOfTheDay? {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SimpsonsOfTheDay.self, from: data)
    }
}
