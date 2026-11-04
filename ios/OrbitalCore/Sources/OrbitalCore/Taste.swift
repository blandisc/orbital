import Foundation

/// Lo que dijiste en la guía (H1, Fernando, 3 nov 2026): los títulos que te gustan y tus plataformas. Son gustos, no vistos:
/// nunca van a tu historial de Trakt. Sirven mientras Trakt no sabe nada de ti: «Porque viste» los usa como semillas y
/// «Nuevo en tus plataformas» solo enseña las tuyas.
public enum Taste {
    public struct Like: Codable, Sendable, Equatable, Hashable {
        public var kind: String, imdb: String, title: String, year: Int?
        public init(kind: String, imdb: String, title: String, year: Int?) { self.kind = kind; self.imdb = imdb; self.title = title; self.year = year }
    }

    static let likesKey = "taste-likes"
    static let platformsKey = "taste-platforms"

    public static func likes(_ kv: KeyValueStore) -> [Like] {
        kv.data(likesKey).flatMap { try? JSONDecoder().decode([Like].self, from: $0) } ?? []
    }

    public static func setLikes(_ likes: [Like], _ kv: KeyValueStore) {
        kv.set(likesKey, data: likes.isEmpty ? nil : try? JSONEncoder().encode(likes))
    }

    /// Las marcas de tus plataformas («netflix», «disney»…). Vacío: no dijiste, se enseñan todas las de tu país.
    public static func platforms(_ kv: KeyValueStore) -> [String] {
        kv.data(platformsKey).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
    }

    public static func setPlatforms(_ brands: [String], _ kv: KeyValueStore) {
        kv.set(platformsKey, data: brands.isEmpty ? nil : try? JSONEncoder().encode(brands))
    }

    /// Tus gustos como semillas de «Porque viste» (cuando Trakt aún no tiene historial).
    public static func seeds(_ kv: KeyValueStore) -> [TraktEntry] {
        likes(kv).map { TraktEntry(kind: $0.kind, imdb: $0.imdb, title: $0.title, year: $0.year, runtime: nil, episodes: nil, overview: "", traktID: nil, next: nil) }
    }
}
