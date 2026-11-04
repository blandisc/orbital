import Foundation
import OrbitalCore

/// Cómo vas con un título: por ver, a medias o vista (el filtro «Estado» de una lista abierta).
public enum WatchState: String, CaseIterable, Sendable { case unwatched, inProgress, watched }

/// Biblioteca › Guardado (BI1-A, Fernando, 3 nov 2026): tu referencia rápida. Mi lista de Trakt (tu watchlist) por omisión
/// y, con un toque, cualquiera de tus listas de Trakt (las mismas de Para ti). Cada título dice cómo vas (por ver, a medias,
/// vista) y cuánto llevas: el avance de este aparato en una película y los capítulos vistos de una serie (Trakt).
@MainActor
public final class SavedModel: ObservableModel {
    /// Una lista que se puede ver aquí: Mi lista (`watchlist`, sin nombre: la pantalla lo pone) o una tuya de Trakt.
    public struct SavedList: Equatable, Sendable, Identifiable {
        public let id: String
        public let name: String
        public init(id: String, name: String) { self.id = id; self.name = name }
    }

    public static let watchlist = "watchlist"
    static let selectedKey = "library.saved.list"

    /// Mi lista primero y luego tus listas de Trakt, en el orden en que las acomodaste.
    public private(set) var lists: [SavedList] = [SavedList(id: SavedModel.watchlist, name: "")] { didSet { if lists != oldValue { changed() } } }
    /// La lista que ves (se recuerda en este aparato).
    public private(set) var selected: String { didSet { if selected != oldValue { changed() } } }
    public private(set) var items: [Suggestion] = [] { didSet { if items != oldValue { changed() } } }
    /// Todavía no llega la lista (la primera vez o al cambiar de lista).
    public private(set) var loading = false { didSet { if loading != oldValue { changed() } } }
    /// Trakt no contestó: el vacío dice «Reintentar».
    public private(set) var failed = false { didSet { if failed != oldValue { changed() } } }
    /// Lo que viste según Trakt (películas y cuánto llevas de cada serie).
    public private(set) var watched = TraktWatchedState() { didSet { if watched != oldValue { changed() } } }
    /// Ya se pidió una vez (antes de eso no se enseña el vacío).
    public private(set) var loadedOnce = false { didSet { if loadedOnce != oldValue { changed() } } }

    private let services: Services

    public init(_ services: Services) {
        self.services = services
        selected = services.kv.data(Self.selectedKey).flatMap { String(data: $0, encoding: .utf8) } ?? Self.watchlist
        super.init()
    }

    public var traktLinked: Bool { services.trakt?.linked ?? false }

    /// Mi lista (o la que elegiste), tus listas y lo que viste, a la vez.
    public func load() async {
        guard traktLinked, let trakt = services.trakt else { items = []; lists = [SavedList(id: Self.watchlist, name: "")]; loadedOnce = true; return }
        refreshProgress()
        let forYou = services.forYou
        async let own = forYou.ownTraktLists()
        async let seen = try? trakt.watchedState()
        await loadItems()
        lists = [SavedList(id: Self.watchlist, name: "")] + (await own).map { SavedList(id: "list:\($0.id)", name: $0.name) }
        if !lists.contains(where: { $0.id == selected }) {   // la borraste en Trakt: de vuelta a Mi lista
            select(Self.watchlist)
            await loadItems()
        }
        if let found = await seen { watched = found }
    }

    /// Cambiar de lista (un toque): se recuerda y se pide la nueva.
    public func choose(_ id: String) async {
        guard id != selected else { return }
        select(id)
        items = []
        await loadItems()
    }

    private func select(_ id: String) {
        selected = id
        services.kv.set(Self.selectedKey, data: id.data(using: .utf8))
    }

    private func loadItems() async {
        let id = selected
        loading = true
        defer { if id == selected { loading = false; loadedOnce = true } }
        do {
            let found = try await services.forYou.items(listID: id)
            guard id == selected, !Task.isCancelled else { return }   // cambiaste de lista mientras llegaba
            items = found
            failed = false
        } catch {
            guard id == selected else { return }
            failed = items.isEmpty
        }
    }

    /// Cómo vas con un título: vista (Trakt), a medias (Trakt o el avance de este aparato) o por ver.
    public func state(of s: Suggestion) -> WatchState {
        if watched.movies.contains(s.imdb) || (watched.shows[s.imdb] ?? 0) >= 1 { return .watched }
        if (watched.shows[s.imdb] ?? 0) > 0 || localProgress(s.imdb) != nil || startedHere(s.imdb) { return .inProgress }
        return .unwatched
    }

    /// Cuánto llevas (0–1) para la barra del póster: vista, completa; una serie, sus capítulos vistos; una película, dónde te
    /// quedaste. Por ver: sin barra.
    public func progress(of s: Suggestion) -> Double? {
        switch state(of: s) {
        case .unwatched: return nil
        case .watched: return 1
        case .inProgress: return watched.shows[s.imdb] ?? localProgress(s.imdb)
        }
    }

    /// El estado de cada título de la lista (para el filtro «Estado»).
    public var states: [String: WatchState] {
        Dictionary(items.map { ($0.imdb, state(of: $0)) }, uniquingKeysWith: { first, _ in first })
    }

    /// El avance a medias de este aparato (una película o el capítulo en curso), si hay.
    private func localProgress(_ imdb: String) -> Double? {
        guard let entry = entries[imdb] else { return nil }
        if entry.duration > 0, entry.position > 0 { return min(1, entry.position / entry.duration) }
        if let fraction = entry.fraction, fraction > 0 { return min(1, fraction) }
        return nil
    }

    /// Una serie que empezaste aquí (algún capítulo visto) aunque Trakt aún no lo sepa.
    private func startedHere(_ imdb: String) -> Bool { entries[imdb].map { $0.kind == "series" && !$0.seen.isEmpty } ?? false }

    /// Lo de este aparato (avance y capítulos vistos), leído al pedir la lista y al volver a ella (`refreshProgress`).
    private var entries: [String: LibraryEntry] = [:]

    /// Vuelve a leer el avance de este aparato (viste algo y regresaste a Guardado).
    public func refreshProgress() {
        let fresh = Dictionary(services.library.all.map { ($0.metaID, $0) }, uniquingKeysWith: { first, _ in first })
        if fresh != entries { entries = fresh; changed() }
    }
}
