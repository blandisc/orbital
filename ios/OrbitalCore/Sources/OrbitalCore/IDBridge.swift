import Foundation

/// M5: los ids de anime y de otras bases («kitsu:», «tmdb:») al de IMDb, que es el que entienden Trakt y casi todos los
/// complementos. Un título de una lista de anime ya se puede abrir (su complemento da la ficha); lo que faltaba era buscar
/// sus versiones en los complementos que solo saben de IMDb y avisarle a Trakt.
///
/// - «tmdb:603» (película) → «tt0133093»; «tmdb:1399:1:2» (episodio) → «tt0944947:1:2». Con TMDB (la clave de la app).
/// - «kitsu:1376» → el de IMDb que da arm.haglund.dev (la tabla pública de ids de anime), o el de TMDB y de ahí IMDb.
///   Un episodio de anime («kitsu:1376:5») va numerado de corrido, sin temporada: ese no se traduce (Torrentio ya lo entiende
///   tal cual; Trakt no).
///
/// Lo traducido se recuerda (también en disco) y queda a la mano sin esperar (`known`): así Trakt lo usa al marcar o al ver.
public final class IDBridge: @unchecked Sendable {
    public static let armBase = "https://arm.haglund.dev/api/v2/ids"
    static let storeKey = "id-bridge"
    /// Lo ya traducido en esta instalación: «kitsu:1376» → «tt0213338».
    public static let memo = Memo()

    public final class Memo: @unchecked Sendable {
        private let lock = NSLock()
        private var map: [String: String] = [:]
        private var store: KeyValueStore?
        public func attach(_ store: KeyValueStore) {
            let saved = store.data(IDBridge.storeKey).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
            lock.withLock { self.store = store; map.merge(saved) { mine, _ in mine } }
        }
        func get(_ meta: String) -> String? { lock.withLock { map[meta] } }
        func set(_ meta: String, _ imdb: String) {
            let (store, data): (KeyValueStore?, Data?) = lock.withLock {
                map[meta] = imdb
                return (self.store, try? JSONEncoder().encode(map))
            }
            store?.set(IDBridge.storeKey, data: data)
        }
    }

    private let http: HTTPClient
    private let tmdb: @Sendable () -> Tmdb?
    public init(http: HTTPClient, tmdb: @escaping @Sendable () -> Tmdb?) { self.http = http; self.tmdb = tmdb }

    /// Un id que no es de IMDb pero se puede traducir.
    public static func isForeign(_ id: String) -> Bool { id.hasPrefix("kitsu:") || id.hasPrefix("tmdb:") }

    /// El id de un video con el de IMDb, con lo ya traducido (sin red). nil si no se sabe o no se puede.
    public static func known(videoID: String, kind: String) -> String? {
        guard let parts = split(videoID), let imdb = memo.get(parts.meta) else { return nil }
        return build(imdb, parts: parts, kind: kind)
    }

    /// El id de un video con el de IMDb; pregunta si hace falta. nil si no se puede (sin red, sin clave, un episodio de anime).
    public func videoID(_ videoID: String, kind: String) async -> String? {
        guard let parts = Self.split(videoID) else { return nil }
        if parts.prefix == "kitsu", kind == "series", parts.rest.count > 0 { return nil }   // de corrido: sin temporada
        if let done = Self.known(videoID: videoID, kind: kind) { return done }
        guard let imdb = await imdb(parts, kind: kind) else { return nil }
        Self.memo.set(parts.meta, imdb)
        return Self.build(imdb, parts: parts, kind: kind)
    }

    struct Parts { var prefix: String; var number: String; var rest: [String]; var meta: String { "\(prefix):\(number)" } }

    static func split(_ id: String) -> Parts? {
        let parts = id.split(separator: ":").map(String.init)
        guard parts.count >= 2, ["kitsu", "tmdb"].contains(parts[0]), Int(parts[1]) != nil else { return nil }
        return Parts(prefix: parts[0], number: parts[1], rest: Array(parts.dropFirst(2)))
    }

    static func build(_ imdb: String, parts: Parts, kind: String) -> String? {
        if parts.rest.isEmpty { return imdb }
        guard parts.prefix == "tmdb", kind == "series", parts.rest.count == 2, parts.rest.allSatisfy({ Int($0) != nil }) else { return nil }
        return ([imdb] + parts.rest).joined(separator: ":")
    }

    private func imdb(_ parts: Parts, kind: String) async -> String? {
        guard let number = Int(parts.number) else { return nil }
        if parts.prefix == "tmdb" { return await fromTMDB(number, kind: kind) }
        guard let url = URL(string: "\(Self.armBase)?source=kitsu&id=\(number)"),
              let json = try? await http.getJSON(url, timeout: 8) else { return nil }
        if let imdb = json["imdb"]?.string, imdb.hasPrefix("tt") { return imdb }
        if let tmdbID = json["themoviedb"]?.intValue { return await fromTMDB(tmdbID, kind: kind) }
        return nil
    }

    private func fromTMDB(_ id: Int, kind: String) async -> String? {
        guard let tmdb = tmdb(), tmdb.configured else { return nil }
        return try? await tmdb.details(kind: kind, tmdbID: id).imdb
    }
}
