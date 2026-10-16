import Foundation
import OrbitalCore

/// «Para ti»: el mosaico y las listas (Trakt y plataformas). Solo películas y series.
///
/// Con tu Orbital conectada, la curaduría se calcula una vez allá y aquí solo se enseña (mismas listas y
/// caché que la TV, por `RemoteForYou`); sin ella, o si no contesta, se calcula aquí mismo con `ForYou` local
/// (lo de siempre, sin aviso de error: la persona ni se entera de que falló el salto a la consola).
@MainActor
public final class ParaTiModel: ObservableModel {
    public enum Mode: Equatable { case mosaic, lists }
    public enum Chip: Hashable, Identifiable {
        case all, trakt, platform(String)
        public var id: String { switch self { case .all: "all"; case .trakt: "trakt"; case .platform(let b): b } }
    }
    /// De dónde salió lo que ves: la consola (misma curaduría que la TV) o este iPhone (lógica local).
    public enum Source: Equatable { case console, phone }

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
    /// El mosaico es lo popular de Stremio (sin Trakt ni TMDB todavía): la pantalla invita a conectarlos.
    public private(set) var isGeneric = false { didSet { changed() } }
    /// De dónde vino lo que se ve ahora: la pantalla lo enseña en un pie discreto.
    public private(set) var source: Source = .phone { didSet { changed() } }
    private let services: Services

    public init(_ services: Services) { self.services = services; super.init() }

    public var traktLists: [ForYouList] { lists.filter { $0.group != .platforms } }
    public var platformLists: [ForYouList] { lists.filter { $0.group == .platforms } }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        railItems = [:]
        if services.orbital.isConfigured, await loadFromConsole() { return }
        await loadFromPhone()
    }

    /// Intenta traer «Para ti» de tu Orbital. `false` sin tocar nada: quien llama cae a la lógica local.
    private func loadFromConsole() async -> Bool {
        let remote = services.forYouRemote
        guard let fetchedLists = try? await remote.lists(), let fetchedMosaic = try? await remote.mosaic() else { return false }
        source = .console
        traktLinked = fetchedLists.contains { $0.id == "watchlist" || $0.id == "mine" }
        lists = fetchedLists
        chips = [.all] + (traktLists.isEmpty ? [] : [.trakt]) + platformLists.compactMap { $0.brand.map(Chip.platform) }
        if !chips.contains(chip) { chip = .all }
        watchlistKeys = (try? await remote.watchlistKeys()) ?? []
        mosaic = fetchedMosaic
        isGeneric = false
        error = mosaic.isEmpty && lists.isEmpty ? "Tu Orbital no tiene sugerencias todavía." : nil
        await loadVisible()
        return true
    }

    private func loadFromPhone() async {
        source = .phone
        traktLinked = await services.forYou.traktLinked
        lists = await services.forYou.lists()
        chips = [.all] + (traktLists.isEmpty ? [] : [.trakt]) + platformLists.compactMap { $0.brand.map(Chip.platform) }
        if !chips.contains(chip) { chip = .all }
        watchlistKeys = await services.forYou.watchlistKeys()
        mosaic = await services.forYou.mosaic()
        // Sin Trakt ni TMDB el mosaico no quedaría vacío: lo más popular de Stremio (Cinemeta no pide claves).
        isGeneric = mosaic.isEmpty
        if isGeneric { mosaic = await popular() }
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
            railItems[key(list)] = await itemsFromCurrentSource(listID: list.id)
        }
    }

    private func itemsFromCurrentSource(listID: String) async -> [Suggestion] {
        switch source {
        case .console: return (try? await services.forYouRemote.items(listID: listID, kind: kind)) ?? []
        case .phone: return (try? await services.forYou.items(listID: listID, kind: kind)) ?? []
        }
    }

    public func items(for list: ForYouList) -> [Suggestion] { railItems[key(list)] ?? [] }

    /// Lo más popular de Cinemeta, series y películas alternadas, en tu idioma.
    private func popular() async -> [Suggestion] {
        async let series = popular("series"), movies = popular("movie")
        let dismissed = await services.forYou.dismissedIDs()
        return ForYou.interleave([await series, await movies], limit: ForYou.mosaicSize).filter { !dismissed.contains($0.imdb) }
    }

    private func popular(_ kind: String) async -> [Suggestion] {
        guard let metas = try? await services.cinemeta.catalog(kind) else { return [] }
        let top = Array(metas.prefix(ForYou.mosaicSize / 2))
        let localized = await services.localizer.catalog(kind: kind, metas: top)
        return zip(top, localized).compactMap { original, translated in
            guard let id = original["id"]?.string, id.hasPrefix("tt"), let name = original["name"]?.string,
                  let poster = CinemetaParsing.medium(original["poster"]?.string) else { return nil }
            let info = CinemetaParsing.describe(translated)
            let minutes = Int(CinemetaParsing.runtimeSeconds(info.runtime) / 60)
            return Suggestion(kind: kind, imdb: id, title: translated["name"]?.string ?? name, year: Int(info.year.prefix(4)),
                              runtime: minutes > 0 ? minutes : nil,
                              overview: info.description, poster: poster, wide: original["background"]?.string ?? poster,
                              logo: "https://images.metahub.space/logo/medium/\(id)/img", reason: .popular)
        }
    }

    /// «No me interesa».
    public func dismiss(_ s: Suggestion) async {
        switch source {
        case .console: await services.forYouRemote.dismiss(s.imdb)
        case .phone: await services.forYou.dismiss(s.imdb)
        }
        mosaic.removeAll { $0.imdb == s.imdb }
        railItems = railItems.mapValues { $0.filter { $0.imdb != s.imdb } }
    }

    /// El botón «Actualizar»: limpia la caché (de la consola o local, según de dónde viniera) y vuelve a cargar.
    public func refresh() async {
        switch source {
        case .console: await services.forYouRemote.clearCache()
        case .phone: await services.forYou.clearCache()
        }
        railItems = [:]
        await load()
    }
}
