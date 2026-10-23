import Foundation

/// Un renglón de la zona de listas de «Guardar en…» (arriba de las fijas).
public enum SaveSheetRow: Equatable, Identifiable, Sendable {
    /// Una de tus listas de Trakt.
    case list(SavedList)
    /// Su lugar apartado mientras llegan (del mismo alto que un renglón de verdad; no se puede tocar).
    case skeleton(Int)
    /// Ya llegaron y no tienes ninguna.
    case empty

    public var id: String {
        switch self {
        case .list(let list): "list:\(list.id)"
        case .skeleton(let i): "skeleton:\(i)"
        case .empty: "empty"
        }
    }
}

/// El orden y el espacio de «Guardar en…» para que nada salte ni se recorra al llegar las listas (solo aritmética, con pruebas):
/// - Arriba, tus listas de Trakt: las que cambiaron (o creaste) más reciente primero; mientras llegan, renglones esqueleto.
/// - Abajo, siempre en el mismo lugar, las fijas (`SaveDestination.fixed`: tu watchlist y Mi lista); no dependen de la red.
/// - La zona de listas aparta su alto al abrir la hoja (`reservedRows`) y ya no cambia: si llegan más, se desplaza adentro.
public enum SaveSheetPlan {
    /// Recientes primero (por `updatedAt`); las que no traen fecha, al final y en el orden en que vinieron.
    public static func order(_ lists: [SavedList]) -> [SavedList] {
        lists.enumerated().sorted { a, b in
            switch (a.element.updatedAt, b.element.updatedAt) {
            case let (x?, y?) where x != y: return x > y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.offset < b.offset
            }
        }.map(\.element)
    }

    /// Los renglones de la zona de listas: `nil` = todavía no llegan (tantos esqueletos como `expected`).
    public static func rows(lists: [SavedList]?, expected: Int) -> [SaveSheetRow] {
        guard let lists else { return (0..<max(1, expected)).map(SaveSheetRow.skeleton) }
        return lists.isEmpty ? [.empty] : order(lists).map(SaveSheetRow.list)
    }

    /// Cuántos renglones aparta la zona de listas al abrir: las que ya llegaron, si no las que tenías la última vez
    /// (`cached`), si no `fallback`; entre 1 y `cap` (más que eso se desplaza dentro de la zona).
    public static func reservedRows(loaded: Int?, cached: Int, fallback: Int, cap: Int) -> Int {
        let guess = loaded ?? (cached > 0 ? cached : fallback)
        return max(1, min(cap, guess))
    }
}
