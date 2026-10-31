import Foundation

/// Alternar listas (series y películas, o varias fuentes): uno de cada una por turno, sin repetir, hasta `limit`. Antes
/// había cuatro copias de este ciclo (Para ti, Buscar, el mosaico y lo nuevo de tus plataformas) que se iban separando
/// (auditoría, 31 oct 2026, B4).
public enum Interleave {
    public static func turns<T, ID: Hashable>(_ batches: [[T]], limit: Int = .max, id: (T) -> ID) -> [T] {
        var out: [T] = [], seen = Set<ID>(), i = 0
        while out.count < limit, batches.contains(where: { i < $0.count }) {
            for batch in batches where i < batch.count && out.count < limit && seen.insert(id(batch[i])).inserted { out.append(batch[i]) }
            i += 1
        }
        return out
    }

    /// Sugerencias: sin repetir el mismo título (IMDb).
    public static func suggestions(_ batches: [[Suggestion]], limit: Int = .max) -> [Suggestion] {
        turns(batches, limit: limit, id: \.imdb)
    }
}
