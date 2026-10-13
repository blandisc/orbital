import Foundation
import OrbitalCore

/// «Para ti»: el mosaico y las listas (Trakt y plataformas). Solo películas y series.
@MainActor
public final class ParaTiModel: ObservableModel {
    public enum Mode: Equatable { case mosaic, lists }
    public enum Chip: Hashable, Identifiable {
        case all, trakt, platform(String)
        public var id: String { switch self { case .all: "all"; case .trakt: "trakt"; case .platform(let b): b } }
    }

    public var mode: Mode = .mosaic { didSet { changed() } }
    public private(set) var mosaic: [Suggestion] = [] { didSet { changed() } }
    public private(set) var lists: [ForYouList] = [] { didSet { changed() } }
    public private(set) var chips: [Chip] = [.all] { didSet { changed() } }
    public private(set) var chip: Chip = .all { didSet { changed() } }
    public private(set) var kind = "series" { didSet { changed() } }
    public private(set) var traktList = "watchlist" { didSet { changed() } }
    public private(set) var railItems: [String: [Suggestion]] = [:] { didSet { changed() } }
    public private(set) var watchlistKeys = Set<String>() { didSet { changed() } }
    public private(set) var traktLinked = false { didSet { changed() } }
    public private(set) var isLoading = false { didSet { changed() } }
    public private(set) var error: String? { didSet { changed() } }
    private let services: Services

    public init(_ services: Services) { self.services = services; super.init() }

    public var traktLists: [ForYouList] { lists.filter { $0.group != .platforms } }
    public var platformLists: [ForYouList] { lists.filter { $0.group == .platforms } }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        traktLinked = await services.forYou.traktLinked
        lists = await services.forYou.lists()
        chips = [.all] + (traktLists.isEmpty ? [] : [.trakt]) + platformLists.compactMap { $0.brand.map(Chip.platform) }
        if !chips.contains(chip) { chip = .all }
        watchlistKeys = await services.forYou.watchlistKeys()
        mosaic = await services.forYou.mosaic()
        if mosaic.isEmpty && lists.isEmpty { error = services.appSettings.traktEnabled ? nil : "Conecta Trakt o agrega una clave de TMDB en Ajustes para ver sugerencias." }
        else { error = nil }
        await loadVisible()
    }

    public func select(_ chip: Chip) async { self.chip = chip; await loadVisible() }
    public func select(traktList id: String) async { traktList = id; await loadVisible() }
    public func setKind(_ kind: String) async { self.kind = kind == "movie" ? "movie" : "series"; await loadVisible() }

    /// Las listas que se ven ahora (según el chip) y su contenido.
    public var visibleLists: [ForYouList] {
        switch chip {
        case .all: return platformLists + (traktLists.contains { $0.id == "watchlist" } ? traktLists.filter { $0.id == "watchlist" } : [])
        case .trakt: return traktLists.filter { $0.id == traktList }
        case .platform(let brand): return platformLists.filter { $0.brand == brand }
        }
    }

    public func key(_ list: ForYouList) -> String { "\(list.id):\(list.splitsKinds ? kind : "-")" }

    private func loadVisible() async {
        let wanted = visibleLists
        for list in wanted where railItems[key(list)] == nil {
            railItems[key(list)] = (try? await services.forYou.items(listID: list.id, kind: kind)) ?? []
        }
    }

    public func items(for list: ForYouList) -> [Suggestion] { railItems[key(list)] ?? [] }

    /// «No me interesa».
    public func dismiss(_ s: Suggestion) async {
        await services.forYou.dismiss(s.imdb)
        mosaic.removeAll { $0.imdb == s.imdb }
        railItems = railItems.mapValues { $0.filter { $0.imdb != s.imdb } }
    }

    public func refresh() async { await services.forYou.clearCache(); railItems = [:]; await load() }
}
