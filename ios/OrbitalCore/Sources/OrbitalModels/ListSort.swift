import Foundation
import OrbitalCore

/// Cómo se ordena una lista abierta (el «Ordenar» de «Ordenar y filtrar»; la pantalla pone los nombres). El mismo en toda
/// lista: cada una ofrece los órdenes que tienen sentido con sus datos (`offered`) y recuerda el suyo (`saved`).
public enum ListSort: String, CaseIterable, Sendable {
    /// Como viene la lista (sin orden elegido).
    case added
    /// «Agregadas: más recientes» y «Agregadas: más viejas» (Fernando, 13 nov 2026: «Que en mis listas también pueda ordenar
    /// por agregadas más recientemente o menos recientemente a la lista»): cuándo lo pusiste en la lista (`Suggestion.addedAt`).
    case addedNewest, addedOldest
    case best, imdb, trakt, letterboxd, newest, oldest, title, shortest

    /// Los órdenes que tienen sentido con estos títulos, en el orden del menú. Uno que no aplica no aparece (nunca una
    /// opción muerta): «Agregadas…» solo si alguno trae cuándo se agregó (Mi lista y tus listas), IMDb si se puede pedir,
    /// Trakt si la lista trae su calificación, Letterboxd con películas y «Más cortas» con duración.
    public static func offered(for items: [Suggestion], imdbAvailable: Bool) -> [ListSort] {
        allCases.filter { s in
            switch s {
            case .addedNewest, .addedOldest: items.contains { $0.addedAt != nil }
            case .imdb: imdbAvailable
            case .trakt: items.contains { $0.traktRating != nil }
            case .letterboxd: items.contains { $0.kind == "movie" }   // Letterboxd califica películas
            case .shortest: items.contains { $0.runtime != nil }
            // Como la TV: sin «Como viene» (sin orden elegido, la lista va como llega) ni «más viejas».
            case .added, .oldest: false
            default: true
            }
        }
    }

    /// Por cuándo se agregó, lo más reciente primero (o al revés). Lo que no trae fecha (lo guardado antes de que se
    /// guardara) va al final, en el orden en que venía; los empates también conservan su orden.
    public static func byAdded(_ items: [Suggestion], newestFirst: Bool) -> [Suggestion] {
        let dated = items.enumerated().filter { $0.element.addedAt != nil }.sorted { a, b in
            let (x, y) = (a.element.addedAt!, b.element.addedAt!)
            if x == y { return a.offset < b.offset }
            return newestFirst ? x > y : x < y
        }
        return dated.map(\.element) + items.filter { $0.addedAt == nil }
    }

    // MARK: lo que se recuerda
    /// Cada lista recuerda su orden en este aparato (`list-sort.<lista>`).
    static func key(_ listID: String) -> String { "list-sort.\(listID)" }

    /// El orden que elegiste en esta lista; sin elegir (o uno que ya no existe), como viene.
    public static func saved(listID: String, defaults: UserDefaults = .standard) -> ListSort {
        defaults.string(forKey: key(listID)).flatMap(ListSort.init(rawValue:)) ?? .added
    }

    public static func remember(_ sort: ListSort, listID: String, defaults: UserDefaults = .standard) {
        defaults.set(sort.rawValue, forKey: key(listID))
    }
}
