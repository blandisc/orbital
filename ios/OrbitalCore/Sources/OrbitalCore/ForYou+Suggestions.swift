import Foundation

// Filas de TMDB → sugerencias (cada una necesita su IMDb, que viene en su ficha). Sin estado: lo usan Para ti, Colecciones,
// el filtro avanzado y Buscar. Aparte de ForYou.swift para que no pase de su tope de líneas.
extension ForYou {
    /// Filas de TMDB → sugerencias (cada una necesita su IMDb: se piden sus detalles a la vez; la que falla se salta).
    static func suggestions(_ rows: [JSON], kind: String, reason: SuggestionReason, tmdb: Tmdb) async -> [Suggestion] {
        let details = await withTaskGroup(of: (Int, TmdbDetails?).self) { group in
            for (i, row) in rows.enumerated() {
                guard let id = row["id"]?.intValue else { continue }
                group.addTask { (i, try? await tmdb.details(kind: kind, tmdbID: id)) }
            }
            var out = [TmdbDetails?](repeating: nil, count: rows.count)
            for await (i, d) in group { out[i] = d }
            return out
        }
        return details.compactMap { d -> Suggestion? in
            guard let d, let imdb = d.imdb, !d.title.isEmpty else { return nil }
            return Suggestion(kind: kind, imdb: imdb, title: d.title, year: d.year, runtime: d.runtime, overview: d.overview,
                              poster: d.poster ?? String(format: metahubPoster, imdb), wide: d.backdrop ?? String(format: metahubBackground, imdb),
                              logo: String(format: metahubLogo, imdb), reason: reason, next: nil)
        }
    }

    /// Una fila de TMDB ya con sus detalles → sugerencia (nil sin IMDb o sin nombre).
    public static func suggestion(_ d: TmdbDetails, row: TmdbRow, reason: SuggestionReason) -> Suggestion? {
        guard let imdb = d.imdb, !d.title.isEmpty else { return nil }
        var s = Suggestion(kind: d.kind, imdb: imdb, title: d.title, year: d.year, runtime: d.runtime, overview: d.overview,
                           poster: d.poster ?? String(format: metahubPoster, imdb), wide: d.backdrop ?? String(format: metahubBackground, imdb),
                           logo: String(format: metahubLogo, imdb), reason: reason, next: nil)
        s.tmdbRating = row.voteAverage > 0 ? row.voteAverage : nil
        return s
    }

    /// Como `suggestions`, pero entrega en orden lo que ya está listo mientras llegan los demás (`deliver`, con los nuevos de
    /// cada vez): la primera fila sale en cuanto llega su detalle, no al llegar el de la última. Devuelve false si `deliver`
    /// pidió parar (cambió el filtro).
    public static func streamSuggestions(_ rows: [TmdbRow], reason: SuggestionReason, tmdb: Tmdb,
                                         deliver: @MainActor ([Suggestion]) -> Bool) async -> Bool {
        await withTaskGroup(of: (Int, TmdbDetails?).self) { group in
            for (i, row) in rows.enumerated() { group.addTask { (i, await detailsRetrying(row, tmdb: tmdb)) } }
            var slots = [Suggestion??](repeating: nil, count: rows.count)   // nil: en camino; .some(nil): no sirve
            var next = 0
            for await (i, d) in group {
                slots[i] = .some(d.flatMap { suggestion($0, row: rows[i], reason: reason) })
                var batch: [Suggestion] = []
                while next < slots.count, let ready = slots[next] { if let ready { batch.append(ready) }; next += 1 }
                if !batch.isEmpty, await !deliver(batch) { group.cancelAll(); return false }
            }
            return true
        }
    }

    /// La ficha de una fila; si no contesta (TMDB tarda o dice «espera»), una vez más. Antes el título se perdía sin avisar y
    /// la búsqueda avanzada salía con huecos.
    static func detailsRetrying(_ row: TmdbRow, tmdb: Tmdb) async -> TmdbDetails? {
        if let d = try? await tmdb.details(kind: row.kind, tmdbID: row.id) { return d }
        guard !Task.isCancelled else { return nil }
        return try? await tmdb.details(kind: row.kind, tmdbID: row.id)
    }

    /// Filas de TMDB de películas y series juntas → sugerencias, en su orden (cada una con su IMDb; un título repetido, una vez).
    public static func suggestions(_ rows: [TmdbRow], reason: SuggestionReason, tmdb: Tmdb) async -> [Suggestion] {
        let details = await withTaskGroup(of: (Int, TmdbDetails?).self) { group in
            for (i, row) in rows.enumerated() { group.addTask { (i, await detailsRetrying(row, tmdb: tmdb)) } }
            var out = [TmdbDetails?](repeating: nil, count: rows.count)
            for await (i, d) in group { out[i] = d }
            return out
        }
        var seen = Set<String>()
        return details.enumerated().compactMap { i, d -> Suggestion? in
            guard let d, let s = suggestion(d, row: rows[i], reason: reason), seen.insert(s.imdb).inserted else { return nil }
            return s
        }
    }
}
