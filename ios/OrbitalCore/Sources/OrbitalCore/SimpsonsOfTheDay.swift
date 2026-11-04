import Foundation

/// «Los Simpson en la tele» (el widget): la tele cambia de episodio cada media hora (Fernando, 4 nov 2026: «que el episodio
/// que se muestra en los widgets de los Simpson cambie cada X tiempo»). La app arma la tanda del día (unos cuantos episodios,
/// con la imagen de cada uno ya reducida junto al archivo) y el widget la recorre en orden, uno por turno; si la app no se abre,
/// la sigue recorriendo con la del último día que armó.
public struct SimpsonsOfTheDay: Codable, Equatable, Sendable {
    public struct Episode: Codable, Equatable, Sendable, Identifiable {
        public var season: Int
        public var episode: Int
        /// El nombre del episodio (vacío si Cinemeta no lo trae).
        public var title: String
        /// El id del video («tt0096697:6:12»): tocar el widget lo reproduce.
        public var videoID: String
        /// La imagen del episodio (remota) y la reducida, junto al archivo.
        public var still: String
        public var imageFile: String?
        public var id: String { videoID }

        public init(season: Int, episode: Int, title: String, videoID: String, still: String, imageFile: String? = nil) {
            self.season = season; self.episode = episode; self.title = title; self.videoID = videoID
            self.still = still; self.imageFile = imageFile
        }

        /// Reproducir ese episodio en la app.
        public var link: URL? { WidgetLink.play(kind: "series", id: SimpsonsOfTheDay.seriesID, video: videoID) }
    }

    public static let seriesID = "tt0096697"
    /// La tanda, en el orden en que pasan por la tele.
    public var episodes: [Episode]
    /// El día (a medianoche, en la hora de aquí) para el que se armó: al día siguiente la app arma otra.
    public var day: Date
    /// Las temporadas de Ajustes con que se armó (si cambian, se arma de nuevo).
    public var seasons: [Int]
    public init(episodes: [Episode], day: Date, seasons: [Int]) { self.episodes = episodes; self.day = day; self.seasons = seasons }

    /// El turno de `date`: cuántos turnos de `minutes` minutos van desde 1970 en la hora de aquí (cambian a la hora y a la
    /// media, como la programación de la tele).
    public static func turn(for date: Date, minutes: Double, calendar: Calendar = .current) -> Int {
        let local = date.timeIntervalSince1970 + Double(calendar.timeZone.secondsFromGMT(for: date))
        return Int((local / (minutes * 60)).rounded(.down))
    }

    /// Cuándo empieza el turno `turn` (lo inverso de `turn(for:)`).
    public static func start(ofTurn turn: Int, minutes: Double, calendar: Calendar = .current) -> Date {
        let local = Double(turn) * minutes * 60
        let guess = Date(timeIntervalSince1970: local)
        return Date(timeIntervalSince1970: local - Double(calendar.timeZone.secondsFromGMT(for: guess)))
    }

    /// El episodio en la tele en `date` con turnos de `minutes`: recorre la tanda en orden y vuelve a empezar.
    public func episode(at date: Date, minutes: Double, calendar: Calendar = .current) -> Episode? {
        guard !episodes.isEmpty else { return nil }
        let turn = Self.turn(for: date, minutes: minutes, calendar: calendar)
        return episodes[((turn % episodes.count) + episodes.count) % episodes.count]
    }

    /// Cuáles `take` de `count` episodios forman la tanda del día `date`: salta por la lista con un paso grande y primo con
    /// `count`, así dos seguidos no son vecinos, no se repite uno dentro de la tanda y, día tras día, no vuelve uno hasta
    /// recorrerlos todos.
    public static func indices(for date: Date, count: Int, take: Int, calendar: Calendar = .current) -> [Int] {
        guard count > 0 else { return [] }
        let take = min(take, count)
        let start = calendar.startOfDay(for: date)
        let day = Int((start.timeIntervalSince1970 + Double(calendar.timeZone.secondsFromGMT(for: start))) / 86_400)
        // Un paso de ±1 dejaría vecinos seguidos (con 240 episodios, 7919 % 240 = 239): se busca otro entre 2 y count − 2.
        // Con muy pocos (6: solo 1 y 5 son primos con él) no hay otro y se queda en 1.
        let first = count > 4 ? min(max(7919 % count, 2), count - 2) : 1
        let candidates = count > 4 ? Array(first...(count - 2)) + Array(2..<first) : []
        let step = candidates.first { gcd($0, count) == 1 } ?? 1
        return (0..<take).map { k in (((day * take + k) % count) * step + 13) % count }
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
