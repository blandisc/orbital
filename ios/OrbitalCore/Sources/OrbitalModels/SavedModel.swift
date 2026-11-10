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
    /// Mi lista entera, aunque veas otra lista (el tablero cuenta lo que tienes en ella).
    public internal(set) var watchlist: [Suggestion] = [] { didSet { if watchlist != oldValue { changed() } } }
    /// Tus listas de Trakt: unos pósters y cuántos títulos tiene cada una (los renglones de «Tus listas»).
    public private(set) var listPosters: [String: [String]] = [:] { didSet { if listPosters != oldValue { changed() } } }
    public internal(set) var listCounts: [String: Int] = [:] { didSet { if listCounts != oldValue { changed() } } }
    /// Ya se pidió una vez (antes de eso no se enseña el vacío).
    public private(set) var loadedOnce = false { didSet { if loadedOnce != oldValue { changed() } } }

    let services: Services

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
        async let mine = try? forYou.items(listID: Self.watchlist)
        await loadItems()
        if let found = await mine { watchlist = await localized(found) }
        lists = [SavedList(id: Self.watchlist, name: "")] + (await own).map { SavedList(id: "list:\($0.id)", name: $0.name) }
        if !lists.contains(where: { $0.id == selected }) {   // la borraste en Trakt: de vuelta a Mi lista
            select(Self.watchlist)
            await loadItems()
        }
        if let found = await seen { watched = found; watchedReady = true }
        await loadListPreviews()
    }

    /// Los pósters y la cifra de cada una de tus listas, a la vez (salen de la misma caché que Para ti).
    private func loadListPreviews() async {
        let forYou = services.forYou
        let ids = lists.map(\.id).filter { $0 != Self.watchlist }
        let found = await withTaskGroup(of: (String, [Suggestion]?).self) { group in
            for id in ids { group.addTask { (id, try? await forYou.items(listID: id)) } }
            var out: [String: [Suggestion]] = [:]
            for await (id, items) in group { if let items { out[id] = items } }
            return out
        }
        listPosters = found.mapValues { Array($0.prefix(3).map(\.poster)) }
        listCounts = found.mapValues(\.count)
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
            // Los nombres en tu idioma (PT23: «Dune: Parte dos», como la TV), por el mismo `Localizer` de las fichas. Primero
            // salen como los manda Trakt y se cambian al llegar (lo que ya se tradujo antes sale de su caché, sin esperar).
            let named = await localized(found)
            guard id == selected, !Task.isCancelled, items == found else { return }
            items = named
        } catch {
            guard id == selected else { return }
            failed = items.isEmpty
        }
    }

    /// Los títulos con su nombre en el idioma de la app (sin TMDB, tal cual).
    private func localized(_ found: [Suggestion]) async -> [Suggestion] {
        var out = found
        for kind in ["movie", "series"] {
            let at = out.indices.filter { out[$0].kind == kind }
            guard !at.isEmpty else { continue }
            let metas = at.map { JSON.object(["id": .string(out[$0].imdb), "name": .string(out[$0].title)]) }
            let translated = await services.localizer.catalog(kind: kind, metas: metas)
            for (i, meta) in zip(at, translated) {
                if let name = meta["name"]?.string, !name.isEmpty { out[i].title = name }
            }
        }
        return out
    }

    // MARK: por estado (G2-A)
    /// Lo que marcaste aquí como visto, antes de que Trakt lo cuente («Mover a… › Vista»).
    func noteWatched(_ s: Suggestion, at date: Date) {
        watched.movies.insert(s.imdb)
        watched.info[s.imdb] = TraktWatchedInfo(kind: s.kind, title: s.title, year: s.year, lastWatchedAt: date)
    }
    func forgetWatched(_ imdb: String) { watched.movies.remove(imdb) }
    /// Una lista recién hecha, al final de las tuyas (Trakt la pone ahí).
    func appendList(_ list: SavedList) { if !lists.contains(where: { $0.id == list.id }) { lists.append(list); listCounts[list.id] = 0 } }

    /// Ya llegó lo que viste en Trakt (sin eso, el tablero no sabe qué cambió solo).
    public private(set) var watchedReady = false
    static let snapshotKey = "saved-board-snapshot"

    /// Lo que cambió solo desde la última vez que viste el tablero; la primera vez, nada (se toma la foto).
    public func takeAutomaticChanges(_ board: SavedBoard) -> [SavedChange] {
        guard watchedReady else { return [] }
        let old = services.kv.data(Self.snapshotKey).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }
        let now = board.statuses
        services.kv.set(Self.snapshotKey, data: try? JSONEncoder().encode(now.mapValues(\.rawValue)))
        guard let old else { return [] }
        return board.automaticChanges(since: old.compactMapValues(TitleStatus.init(rawValue:)))
    }

    /// Lo que moviste aquí ya no se avisa como cambio solo.
    func noteMoved(_ imdb: String, to status: TitleStatus) {
        guard var old = services.kv.data(Self.snapshotKey).flatMap({ try? JSONDecoder().decode([String: String].self, from: $0) }) else { return }
        old[imdb] = status.rawValue
        services.kv.set(Self.snapshotKey, data: try? JSONEncoder().encode(old))
    }

    /// Lo tuyo por estado; `hidden`: las series que dejaste (`FollowModel`).
    public func board(hidden: Set<String>, hiddenNames: [String: String] = [:]) -> SavedBoard {
        SavedBoard.build(watchlist: watchlist, watched: watched, hidden: hidden, hiddenNames: hiddenNames)
    }

    // MARK: editar la lista (quitar y agregar)
    /// La lista que ves se puede editar: Mi lista y tus listas de Trakt, todas tuyas (con Trakt conectado).
    public var canEdit: Bool { traktLinked && TitleActions.isEditable(listID: selected) }

    /// El nombre de la lista que ves ("" en Mi lista: la pantalla lo pone).
    public var selectedName: String { lists.first { $0.id == selected }?.name ?? "" }

    /// Quita un título de la lista que ves: sale al instante y, si Trakt no acepta, regresa a su lugar (devuelve false).
    @discardableResult
    public func remove(_ s: Suggestion) async -> Bool {
        let list = selected
        setShown(s, shown: false)
        do { try await actions.setInList(s, listID: list, add: false); return true } catch {
            if list == selected { setShown(s, shown: true) }
            return false
        }
    }

    /// Agrega un título a la lista que ves (desde «Agregar» o «Deshacer»): entra al instante, al principio o donde estaba.
    @discardableResult
    public func add(_ s: Suggestion) async -> Bool {
        let list = selected
        setShown(s, shown: true)
        do { try await actions.setInList(s, listID: list, add: true); return true } catch {
            if list == selected { setShown(s, shown: false) }
            return false
        }
    }

    /// Lo que se quitó y dónde estaba (para regresarlo a su lugar con «Deshacer»).
    private var removed: [String: (Int, Suggestion)] = [:]
    lazy var actions = TitleActions(services)

    func setShown(_ s: Suggestion, shown: Bool) {
        if !shown {
            guard let i = items.firstIndex(where: { $0.imdb == s.imdb }) else { return }
            removed[s.imdb] = (i, items.remove(at: i))
        } else {
            guard !items.contains(where: { $0.imdb == s.imdb }) else { return }
            let (i, saved) = removed.removeValue(forKey: s.imdb) ?? (0, s)
            items.insert(saved, at: min(i, items.count))
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
