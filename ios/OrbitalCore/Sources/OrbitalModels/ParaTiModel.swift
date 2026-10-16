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
    /// Por qué el destacado «Para ti hoy» es lo que es (la etiqueta sobre el arte).
    public enum FeaturedReason: Equatable {
        case recommendedByTrakt, rank(Int, platform: String), trending, other(SuggestionReason)
    }
    public struct Featured: Equatable {
        public var item: Suggestion
        public var shelfID: String?
        public var reason: FeaturedReason
    }
    /// De dónde salió lo que ves: la consola (misma curaduría que la TV) o este iPhone (lógica local).
    public enum Source: Equatable, Sendable { case console, phone }

    public var mode: Mode = .mosaic { didSet { changed() } }
    public private(set) var mosaic: [Suggestion] = [] { didSet { changed() } }
    public private(set) var lists: [ForYouList] = [] { didSet { changed() } }
    /// Los estantes del feed de Listas, en su orden (`ShelfPlanner`). Los vacíos se descartan al terminar de cargar.
    public private(set) var shelves: [ShelfPlan] = [] { didSet { changed() } }
    public private(set) var kind = "series" { didSet { changed() } }
    /// Las listas que aún se están pidiendo (su estante enseña esqueletos, no un hueco).
    public private(set) var loadingKeys = Set<String>() { didSet { changed() } }
    /// Cuántas veces se pidió «Actualizar»: el destacado pasa al siguiente de su estante.
    public private(set) var featuredRotation = 0 { didSet { changed() } }
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

    /// Los estantes que se pintan: con algo dentro, o todavía cargando (con esqueleto). Vacío o fallido: no se pinta.
    public var visibleShelves: [ShelfPlan] { shelves.filter { isLoading(shelf: $0) || !items(for: $0).isEmpty } }
    /// Ninguna fuente dio estantes: el feed cae a lo popular de Stremio y a la invitación a conectar fuentes.
    public var feedIsEmpty: Bool { !isLoading && visibleShelves.isEmpty }
    /// Mostrar «Conecta Trakt o tu Orbital»: no hay ninguna fuente tuya (solo lo popular de Stremio).
    public var needsSources: Bool { feedIsEmpty || isGeneric }
    /// «Series · Películas» solo tiene sentido si algún estante lo respeta.
    public var hasKindSplit: Bool { shelves.contains(where: \.splitsKinds) }

    public func isLoading(shelf: ShelfPlan) -> Bool {
        shelf.listIDs.contains { id in
            let k = key(listID: id, splits: shelf.splitsKinds)
            return loadingKeys.contains(k) || (isLoading && railItems[k] == nil)
        }
    }

    /// Lo que enseña un estante: las listas que lo forman, sin repetir títulos.
    public func items(for shelf: ShelfPlan) -> [Suggestion] {
        var seen = Set<String>()
        return shelf.listIDs.flatMap { railItems[key(listID: $0, splits: shelf.splitsKinds)] ?? [] }.filter { seen.insert($0.imdb).inserted }
    }

    /// «Para ti hoy»: la primera sugerencia con arte ancho del primer estante que la tenga (rota con «Actualizar»);
    /// sin estantes, la primera de lo popular del mosaico.
    public var featured: Featured? {
        let loaded = visibleShelves.map { (plan: $0, items: items(for: $0)) }
        if let pick = ShelfPlanner.featured(loaded, rotation: featuredRotation) {
            return Featured(item: pick.item, shelfID: pick.plan.id, reason: Self.reason(of: pick.item, in: pick.plan))
        }
        let stand = ShelfPlan(id: "mosaic", list: ForYouList(id: "mosaic", title: "", group: .discover, brand: nil, logo: nil, splitsKinds: false),
                              listIDs: [], style: .plain)
        if let pick = ShelfPlanner.featured([(stand, mosaic)], rotation: featuredRotation) {
            return Featured(item: pick.item, shelfID: nil, reason: Self.reason(of: pick.item, in: pick.plan))
        }
        return nil
    }

    static func reason(of item: Suggestion, in plan: ShelfPlan) -> FeaturedReason {
        if plan.style == .top10, let rank = item.rank { return .rank(rank, platform: platformName(plan.list)) }
        switch item.reason {
        case .recommended: return .recommendedByTrakt
        case .trending: return .trending
        default: return .other(item.reason)
        }
    }

    private static func platformName(_ list: ForYouList) -> String {
        guard let brand = list.brand else { return list.title }
        return Tmdb.platforms.first { $0.brand == brand }?.name ?? brand.capitalized
    }

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
        shelves = ShelfPlanner.plan(lists)
        watchlistKeys = (try? await remote.watchlistKeys()) ?? []
        mosaic = fetchedMosaic
        isGeneric = false
        error = mosaic.isEmpty && lists.isEmpty ? "Tu Orbital no tiene sugerencias todavía." : nil
        await loadShelves()
        return true
    }

    private func loadFromPhone() async {
        source = .phone
        traktLinked = await services.forYou.traktLinked
        lists = await services.forYou.lists()
        shelves = ShelfPlanner.plan(lists)
        watchlistKeys = await services.forYou.watchlistKeys()
        mosaic = await services.forYou.mosaic()
        // Sin Trakt ni TMDB el mosaico no quedaría vacío: lo más popular de Stremio (Cinemeta no pide claves).
        isGeneric = mosaic.isEmpty
        if isGeneric { mosaic = await popular() }
        if mosaic.isEmpty && lists.isEmpty { error = services.appSettings.traktEnabled ? nil : "Conecta Trakt o agrega una clave de TMDB en Ajustes para ver sugerencias." }
        else { error = nil }
        await loadShelves()
    }

    /// «Series · Películas»: solo cambia los estantes con `split`; el resto sigue igual.
    public func setKind(_ kind: String) async {
        self.kind = kind == "movie" ? "movie" : "series"
        await loadShelves()
    }

    public func key(_ list: ForYouList) -> String { key(listID: list.id, splits: list.splitsKinds) }
    func key(listID: String, splits: Bool) -> String { "\(listID):\(splits ? kind : "-")" }

    /// Pide el contenido de todos los estantes a la vez (cada uno aparece cuando llega; el orden no cambia).
    private func loadShelves() async {
        var wanted: [(key: String, listID: String)] = []
        for shelf in shelves {
            for id in shelf.listIDs {
                let k = key(listID: id, splits: shelf.splitsKinds)
                if railItems[k] == nil, !wanted.contains(where: { $0.key == k }) { wanted.append((k, id)) }
            }
        }
        guard !wanted.isEmpty else { return }
        loadingKeys.formUnion(wanted.map(\.key))
        let remote = services.forYouRemote, local = services.forYou, source = source, kind = kind
        await withTaskGroup(of: (String, [Suggestion]).self) { group in
            for entry in wanted {
                group.addTask {
                    switch source {
                    case .console: return (entry.key, (try? await remote.items(listID: entry.listID, kind: kind)) ?? [])
                    case .phone: return (entry.key, (try? await local.items(listID: entry.listID, kind: kind)) ?? [])
                    }
                }
            }
            for await (k, found) in group {
                railItems[k] = found
                loadingKeys.remove(k)
            }
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
        featuredRotation += 1
        await load()
    }
}
