import Foundation

/// Canales de Inicio (docs/producto/inicio-benchmark/): cada serie que eliges es un canal que siempre está pasando un
/// episodio al azar, como la tele. Qué episodio va y en qué minuto sale de la hora y del id de la serie, con una cuenta
/// fija (sin servidor): el iPhone, el iPad y la Mac ven lo mismo al mismo tiempo, y al tocar el canal entras donde va.
/// Límite conocido: el orden depende de cuántos episodios hay. El día que sale uno nuevo el horario de esa serie se rehace,
/// y dos aparatos con la ficha de Cinemeta de días distintos (guardada en disco) pueden pasar capítulos distintos ese día.
public enum ChannelSchedule {
    /// Un episodio que puede salir al aire.
    public struct Episode: Codable, Sendable, Equatable {
        public var season: Int, episode: Int
        public var name: String
        /// La imagen de ese capítulo (no el arte de la serie); vacía si Cinemeta no la tiene.
        public var still: String
        public var videoID: String
        public init(season: Int, episode: Int, name: String, still: String, videoID: String) {
            self.season = season; self.episode = episode; self.name = name; self.still = still; self.videoID = videoID
        }
    }

    /// Lo que está al aire en un canal: el episodio, cuánto lleva y cuál sigue.
    public struct OnAir: Sendable, Equatable {
        public var episode: Episode
        /// Segundos desde que empezó.
        public var elapsed: TimeInterval
        public var length: TimeInterval
        public var next: Episode
        public var progress: Double { length > 0 ? min(1, max(0, elapsed / length)) : 0 }
        /// Minutos que le quedan (al menos 1 mientras siga al aire).
        public var minutesLeft: Int { max(1, Int(((length - elapsed) / 60).rounded(.up))) }
    }

    /// Desde cuándo cuentan los turnos (cualquier fecha fija sirve; cambiarla movería todos los canales).
    public static let epoch = Date(timeIntervalSince1970: 1_767_225_600)   // 1 ene 2026, 00:00 UTC

    /// Qué pasa en el canal de `seriesID` a la hora `now`. Cada turno dura lo que un episodio (`length`, en segundos); el
    /// episodio de cada turno se elige al azar pero siempre igual para la misma serie y el mismo turno. Nunca repite el
    /// episodio del turno anterior (si hay más de uno). Nil si la serie no tiene episodios.
    public static func onAir(seriesID: String, episodes: [Episode], length: TimeInterval, now: Date) -> OnAir? {
        guard !episodes.isEmpty, length > 0 else { return nil }
        let since = max(0, now.timeIntervalSince(epoch))
        let slot = Int(since / length)
        let elapsed = since - Double(slot) * length
        return OnAir(episode: episodes[index(seriesID, slot: slot, count: episodes.count)], elapsed: elapsed, length: length,
                     next: episodes[index(seriesID, slot: slot + 1, count: episodes.count)])
    }

    /// El episodio de un turno. Los turnos van en vueltas de `count`: en cada vuelta pasan todos los episodios una vez, en
    /// un orden al azar fijo para esa serie y esa vuelta (como una lista revuelta). Entre una vuelta y la siguiente nunca se
    /// repite el mismo episodio seguido.
    static func index(_ seriesID: String, slot: Int, count: Int) -> Int {
        guard count > 1 else { return 0 }
        if count == 2 { return (slot + Int(fnv(seriesID) % 2)) % 2 }   // con dos, se alternan
        let lap = Int((Double(slot) / Double(count)).rounded(.down)), position = slot - lap * count
        return order(seriesID, lap: lap, count: count)[position]
    }

    /// El orden revuelto de una vuelta; si empezaría con el mismo episodio con el que terminó la anterior, se cambian los dos
    /// primeros (la anterior se calcula sin ese ajuste: su último lugar no lo toca).
    static func order(_ seriesID: String, lap: Int, count: Int) -> [Int] {
        var here = shuffled(seriesID, lap: lap, count: count)
        if here[0] == shuffled(seriesID, lap: lap - 1, count: count)[count - 1] { here.swapAt(0, 1) }
        return here
    }

    static func shuffled(_ seriesID: String, lap: Int, count: Int) -> [Int] {
        var state = fnv("\(seriesID)#\(lap)")
        func next() -> UInt64 {   // SplitMix64: un azar estable a partir de la semilla
            state &+= 0x9e37_79b9_7f4a_7c15
            var z = state
            z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
            z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
            return z ^ (z >> 31)
        }
        var out = Array(0..<count)
        for i in stride(from: count - 1, to: 0, by: -1) { out.swapAt(i, Int(next() % UInt64(i + 1))) }
        return out
    }

    static func fnv(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 }
        return hash
    }
}
