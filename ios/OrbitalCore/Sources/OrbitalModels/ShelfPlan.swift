import Foundation
import OrbitalCore

/// Un estante de «Para ti › Listas»: qué lista(s) de la consola pinta y cómo se ve. Sin SwiftUI, para poder probarlo.
public struct ShelfPlan: Identifiable, Hashable, Sendable {
    public enum Style: Sendable, Hashable {
        /// Top 10 de Netflix: cifra enorme a la izquierda de cada póster (`chart:*`).
        case top10
        /// Lo más visto de una plataforma (`jw:*`, respaldo TMDB): puesto discreto sobre el póster.
        case platform
        /// Lo tuyo, tendencias, catálogos de complementos.
        case plain
    }

    public var id: String
    /// La lista que da título, logo y dato; si hay varias fusionadas, la primera.
    public var list: ForYouList
    /// Los ids de todas las listas que alimentan al estante (en «Lo tuyo»: watchlist y «Tus series»).
    public var listIDs: [String]
    public var style: Style
    public var title: String { list.title }
    public var splitsKinds: Bool { list.splitsKinds }

    public static func == (a: ShelfPlan, b: ShelfPlan) -> Bool { a.id == b.id && a.listIDs == b.listIDs && a.style == b.style }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

public enum ShelfPlanner {
    /// El orden del feed (brief de Para ti en el iPhone, §3):
    /// Lo tuyo → Top 10 en Netflix → plataformas `jw:*` (y el respaldo de TMDB solo si no hay `jw` de esa marca) →
    /// En tendencia / Lo más popular → catálogos de complementos. «Seguir viendo» y «Mi lista» de Stremio viven en Inicio.
    public static func plan(_ lists: [ForYouList]) -> [ShelfPlan] {
        func has(_ id: String) -> ForYouList? { lists.first { $0.id == id } }
        var out: [ShelfPlan] = []

        // Lo tuyo: watchlist y «Tus series» de Trakt, en un solo estante.
        let mine = ["watchlist", "mine"].compactMap(has)
        if let first = mine.first {
            var head = first
            head.title = ""            // la interfaz le pone «Lo tuyo»
            head.meta = ""
            out.append(ShelfPlan(id: "mine", list: head, listIDs: mine.map(\.id), style: .plain))
        }
        if let recs = has("recs") { out.append(ShelfPlan(id: recs.id, list: recs, listIDs: [recs.id], style: .plain)) }
        for list in lists where list.id.hasPrefix("list:") { out.append(ShelfPlan(id: list.id, list: list, listIDs: [list.id], style: .plain)) }

        // Top 10 (Netflix y lo que mande la consola con `chart:`).
        for list in lists where list.id.hasPrefix("chart:") { out.append(ShelfPlan(id: list.id, list: list, listIDs: [list.id], style: .top10)) }

        // Plataformas: JustWatch primero; el respaldo de TMDB solo si no hay nada de esa marca.
        let jw = lists.filter { $0.id.hasPrefix("jw:") }
        let covered = Set(jw.compactMap(\.brand) + lists.filter { $0.id.hasPrefix("chart:") }.compactMap(\.brand))
        for list in jw { out.append(ShelfPlan(id: list.id, list: list, listIDs: [list.id], style: .platform)) }
        for list in lists where list.group == .platforms && !list.id.hasPrefix("jw:") && !list.id.hasPrefix("chart:") {
            if let brand = list.brand, covered.contains(brand) { continue }
            out.append(ShelfPlan(id: list.id, list: list, listIDs: [list.id], style: .platform))
        }

        // Tendencias y popular (Trakt o el catálogo de Stremio).
        for id in ["trend", "popular", "cinemeta"] { if let l = has(id) { out.append(ShelfPlan(id: id, list: l, listIDs: [id], style: .plain)) } }

        // Catálogos de complementos: lo que queda (`<complemento>:<catálogo>`).
        let known = Set(out.flatMap(\.listIDs)).union(["continue", "mylist", "estrenos"])   // los estrenos son el estante de calendario, no una lista
        for list in lists where !known.contains(list.id) && list.group == .discover && list.brand == nil {
            out.append(ShelfPlan(id: list.id, list: list, listIDs: [list.id], style: .plain))
        }
        return out
    }

    /// Cuántas sugerencias de un estante pueden ser «Para ti hoy» (rota entre ellas con «Actualizar»).
    public static let featuredPool = 6

    /// El destacado: la primera sugerencia con arte ancho (`wide`) del primer estante que tenga alguna; con cada
    /// «Actualizar» (`rotation`) pasa a la siguiente del mismo estante.
    public static func featured(_ shelves: [(plan: ShelfPlan, items: [Suggestion])], rotation: Int) -> (plan: ShelfPlan, item: Suggestion)? {
        for shelf in shelves {
            let pool = Array(shelf.items.filter { !$0.wide.isEmpty }.prefix(featuredPool))
            guard !pool.isEmpty else { continue }
            return (shelf.plan, pool[((rotation % pool.count) + pool.count) % pool.count])
        }
        return nil
    }
}
