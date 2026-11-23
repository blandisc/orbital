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

/// Las portadas de una fila de tarjetas (Géneros, Premios…): cada tarjeta toma sus primeros `count` sin repetir los que ya
/// usaron las de antes. Antes Acción, Aventura y Animación enseñaban los mismos tres pósters (el anime del año era el primero
/// de las tres; revisión de la Mac, 22 nov 2026). Si a una le faltan nuevos, completa con los suyos de siempre.
public enum CoverSpread {
    public static func pick<T, ID: Hashable>(_ rows: [[T]], count: Int, id: (T) -> ID) -> [[T]] {
        var used = Set<ID>()
        return rows.map { row in
            var picked = Array(row.filter { !used.contains(id($0)) }.prefix(count))
            for item in row where picked.count < count && !picked.contains(where: { id($0) == id(item) }) { picked.append(item) }
            picked.forEach { used.insert(id($0)) }
            return picked
        }
    }
}
