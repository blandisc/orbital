import Foundation

/// La calificación de Trakt de un título, la misma en toda la app (revisión del 11 nov: 79 % en el destacado de Inicio y
/// 84 % en la ficha de la misma película). Trakt la manda en dos lugares: dentro de cada lista (tendencias, recomendadas)
/// y en `/movies/{id}/ratings`, y cada una puede venir de otro momento. Regla: la primera que se conoce en la sesión es la
/// que se enseña en todos lados; la ficha solo pregunta si no hay ninguna. Y se escribe siempre igual: «84 %».
public enum TraktRatings {
    private final class Book: @unchecked Sendable {
        let lock = NSLock()
        var known: [String: Double] = [:]
        func withLock<T>(_ body: (inout [String: Double]) -> T) -> T { lock.lock(); defer { lock.unlock() }; return body(&known) }
    }
    private static let book = Book()

    /// Anota la de una lista o de la ficha (de 0 a 10) si todavía no había una; devuelve la que manda.
    @discardableResult
    public static func note(_ imdb: String, _ rating: Double?) -> Double? {
        guard !imdb.isEmpty else { return rating.flatMap { $0 > 0 ? $0 : nil } }
        return book.withLock { known in
            if let had = known[imdb] { return had }
            guard let rating, rating > 0 else { return nil }
            known[imdb] = rating
            return rating
        }
    }

    /// La que manda para ese título (nil si nadie la ha dicho).
    public static func known(_ imdb: String) -> Double? { book.withLock { $0[imdb] } }

    /// La que se enseña: la conocida y, si no hay, la que trae quien pregunta (que queda anotada).
    public static func shown(_ imdb: String, fallback: Double?) -> Double? { note(imdb, fallback) }

    /// «84 %»: de 0 a 10 a porcentaje entero, el mismo redondeo en toda la app.
    public static func percent(_ rating: Double) -> Int { Int((rating * 10).rounded()) }

    /// Solo para pruebas.
    static func forget() { book.withLock { $0 = [:] } }
}
