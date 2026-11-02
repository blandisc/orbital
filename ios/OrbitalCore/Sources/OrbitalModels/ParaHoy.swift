import Foundation
import OrbitalCore

/// «Para hoy»: lo que elegiste ver hoy desde «¿Qué vemos hoy?» (hacia arriba o la ★). Solo vale el día en que lo marcaste:
/// Inicio lo pone primero en Mi lista ese día y al siguiente vuelve a su lugar.
public enum ParaHoy {
    static let key = "para-hoy"
    private struct Mark: Codable { var imdb: String; var day: String }

    private static func day(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
    private static func all(_ kv: KeyValueStore) -> [Mark] { kv.data(key).flatMap { try? JSONDecoder().decode([Mark].self, from: $0) } ?? [] }

    /// Lo de hoy, lo último que marcaste primero.
    public static func ids(kv: KeyValueStore, now: Date) -> [String] {
        let today = day(now)
        return all(kv).filter { $0.day == today }.map(\.imdb)
    }

    public static func mark(_ imdb: String, kv: KeyValueStore, now: Date) {
        let today = day(now)
        let kept = all(kv).filter { $0.day == today && $0.imdb != imdb }   // lo de otros días ya no sirve
        kv.set(key, data: try? JSONEncoder().encode([Mark(imdb: imdb, day: today)] + kept))
    }

    public static func unmark(_ imdb: String, kv: KeyValueStore) {
        kv.set(key, data: try? JSONEncoder().encode(all(kv).filter { $0.imdb != imdb }))
    }

    /// La lista con lo de «Para hoy» primero (en el orden en que lo marcaste) y lo demás como venía.
    public static func first(_ items: [Suggestion], kv: KeyValueStore, now: Date) -> [Suggestion] {
        let tonight = ids(kv: kv, now: now)
        guard !tonight.isEmpty else { return items }
        let picked = tonight.compactMap { id in items.first { $0.imdb == id } }
        return picked + items.filter { !tonight.contains($0.imdb) }
    }
}
