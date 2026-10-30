import Foundation
import OrbitalCore

/// Un estante de «Para ti › Listas»: qué lista(s) de la consola pinta y cómo se ve. Sin SwiftUI, para poder probarlo.
public struct ShelfPlan: Identifiable, Hashable, Sendable {
    public enum Style: Sendable, Hashable {
        /// Una lista con puesto (Top 10 de Netflix `chart:*`, tendencias de JustWatch `jw:*`): cifra enorme a la izquierda de
        /// cada póster, como `RankedCard` en la TV.
        case top10
        /// Lo popular de una plataforma sin puesto (respaldo de TMDB).
        case platform
        /// Lo tuyo, tendencias, catálogos de complementos.
        case plain
    }

    public var id: String
    /// La lista que da título, logo y dato; si hay varias fusionadas, la primera.
    public var list: ForYouList
    /// Los ids de las listas que alimentan al estante (una por estante, como en la TV).
    public var listIDs: [String]
    public var style: Style
    /// El respaldo de TMDB de una marca que también tiene lista con puesto: solo se ve si esa lista llega vacía.
    public var isFallback = false
    public var title: String { list.title }
    public var splitsKinds: Bool { list.splitsKinds }

    public static func == (a: ShelfPlan, b: ShelfPlan) -> Bool { a.id == b.id && a.listIDs == b.listIDs && a.style == b.style }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

public enum ShelfPlanner {
    /// El orden de la TV (`orbital/foryou.py`, `lists()`), que manda en los dos lados:
    /// Recomendadas → Tus series → Tu watchlist → tus listas de Trakt → En tendencia → Lo más popular → catálogos de complementos →
    /// plataformas (el Top 10 de Netflix, `jw:*` y el respaldo de TMDB solo si no hay nada más de esa marca).
    /// «Seguir viendo» y «Mi lista» viven en Inicio; «Próximos estrenos» es su propio estante de calendario.
    public static func plan(_ lists: [ForYouList]) -> [ShelfPlan] {
        let skipped: Set<String> = ["continue", "mylist", "estrenos"]
        let chartBrands = Set(lists.filter { $0.id.hasPrefix("chart:") || $0.id.hasPrefix("jw:") }.compactMap(\.brand))
        var out: [ShelfPlan] = []
        // Orden estable: la posición de cada lista en el orden de la TV; dentro de cada grupo, como llegaron.
        for (_, list) in lists.enumerated().sorted(by: { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }) {
            guard !skipped.contains(list.id) else { continue }
            let style: ShelfPlan.Style
            var fallback = false
            if list.id.hasPrefix("chart:") || list.id.hasPrefix("jw:") { style = .top10 }
            else if list.group == .platforms {
                // El respaldo de TMDB de una marca con Top 10 o JustWatch entra, pero solo se ve si esa lista llega vacía
                // (la consola lo manda justo cuando JustWatch no trajo nada).
                if let brand = list.brand, chartBrands.contains(brand) { fallback = true }
                style = .platform
            } else {
                guard list.group != .platforms, list.brand == nil || list.group == .mine else { continue }
                style = .plain
            }
            var plan = ShelfPlan(id: list.id, list: list, listIDs: [list.id], style: style)
            plan.isFallback = fallback
            out.append(plan)
        }
        return out
    }

    /// El lugar de una lista en el orden de la TV.
    private static func rank(_ list: ForYouList) -> Int {
        switch list.id {
        case "recs": return 0
        case "mine": return 1
        case "watchlist": return 2
        case _ where list.id.hasPrefix("list:"): return 3
        case "trend": return 4
        case "popular", "cinemeta": return 5
        case _ where list.id.hasPrefix("chart:"): return 7
        case _ where list.id.hasPrefix("jw:"): return 8
        case _ where list.group == .platforms: return 9
        default: return 6   // catálogos de complementos
        }
    }
}
