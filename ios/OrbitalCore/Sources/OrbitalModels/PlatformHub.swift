import Foundation
import OrbitalCore

/// Un ranking de una plataforma: una lista con puesto en un tipo (series o películas).
public struct PlatformRanking: Identifiable, Hashable, Sendable {
    public enum Source: String, Sendable {
        /// El Top 10 oficial de Netflix de la semana en tu país (`chart:netflix`).
        case netflixTop10
        /// La tendencia del día en JustWatch (`jw:<marca>`).
        case justWatch
        /// Lo más popular según TMDB (sin puesto oficial; solo si la plataforma no tiene otro ranking).
        case popular
    }
    public var listID: String
    public var kind: String
    public var source: Source
    public var id: String { "\(listID):\(kind)" }

    public init(listID: String, kind: String, source: Source) { self.listID = listID; self.kind = kind; self.source = source }
}

/// Una plataforma con todos sus rankings: la tarjeta en abanico de «Tus plataformas» y su página.
public struct PlatformHub: Identifiable, Hashable, Sendable {
    public var brand: String
    public var name: String
    public var logo: String?
    public var rankings: [PlatformRanking]
    public var id: String { brand }
}

public enum PlatformPlanner {
    /// Las listas de plataformas agrupadas por marca, en el orden en que llegan (Netflix primero, como en la TV). Cada una
    /// con sus rankings de series y de películas; lo popular de TMDB solo si la marca no trae ningún ranking.
    public static func hubs(_ lists: [ForYouList]) -> [PlatformHub] {
        var order: [String] = []
        var ranked: [String: [PlatformRanking]] = [:], popular: [String: [PlatformRanking]] = [:], logos: [String: String] = [:]
        for list in lists where list.group == .platforms {
            guard let brand = list.brand else { continue }
            if !order.contains(brand) { order.append(brand) }
            if logos[brand] == nil, let logo = list.logo { logos[brand] = logo }
            let kinds = list.splitsKinds ? ["series", "movie"] : ["series"]
            let source: PlatformRanking.Source = list.id.hasPrefix("chart:") ? .netflixTop10 : list.id.hasPrefix("jw:") ? .justWatch : .popular
            let rankings = kinds.map { PlatformRanking(listID: list.id, kind: $0, source: source) }
            if source == .popular { popular[brand, default: []] += rankings } else { ranked[brand, default: []] += rankings }
        }
        return order.compactMap { brand in
            let rankings = ranked[brand] ?? popular[brand] ?? []
            guard !rankings.isEmpty else { return nil }
            return PlatformHub(brand: brand, name: name(of: brand), logo: logos[brand], rankings: rankings)
        }
    }

    static func name(of brand: String) -> String {
        if brand == "netflix" { return "Netflix" }
        return Charts.justWatchPlatforms.first { $0.brand == brand }?.name ?? Tmdb.platforms.first { $0.brand == brand }?.name ?? brand.capitalized
    }
}
