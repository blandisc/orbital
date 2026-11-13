import Foundation
import OrbitalCore

/// Decide por mí (13 nov 2026, DE1): lo que se ve puesto filtra, lo que quitas se deshace y, si no hay nada, dice por qué.
extension DecideModel {
    /// Algo que apartaste de los tres: cuál era, en qué lugar y qué entró en su lugar.
    public struct Removal: Equatable, Sendable {
        public let suggestion: Suggestion
        /// «No me interesa» (si no, «Hoy no»).
        public let dismissed: Bool
        let index: Int
        let replacement: String?
        public static func == (a: Removal, b: Removal) -> Bool { a.suggestion.imdb == b.suggestion.imdb && a.dismissed == b.dismissed }
    }

    /// «Deshacer» del aviso: vuelve a su lugar, vuelve a sugerirse (aquí y en Para ti) y la que había entrado se va.
    public func undoRemoval() async {
        guard let removal = lastRemoval else { return }
        lastRemoval = nil
        let s = removal.suggestion
        if removal.dismissed {
            pendingDismissals.removeAll { $0 == s.imdb }
            await services.forYou.undismiss(s.imdb)
        }
        var skipped = notTodayRaw()
        skipped[s.imdb] = nil
        services.kv.set(Self.skipKey, data: try? JSONEncoder().encode(skipped))
        var current = picks.filter { $0.imdb != s.imdb }
        if let replacement = removal.replacement, let at = current.firstIndex(where: { $0.imdb == replacement }) {
            current[at] = s
            shown.remove(replacement)   // la que había entrado puede volver a salir después
        } else {
            current.insert(s, at: min(removal.index, current.count))
        }
        picks = current
        exhausted = false
        select(s)
        dropUpcoming()
        fillUpcoming()
    }

    /// A la TV se le avisa lo que dijiste «No me interesa» cuando ya no se puede deshacer (al quitar otra o al cerrar).
    public func commitDismissals() async {
        let ids = pendingDismissals
        pendingDismissals = []
        guard services.orbital.isConfigured else { return }
        for id in ids { await services.forYouRemote.dismiss(id) }
    }

    // MARK: lo que se ve puesto, filtra (F3)
    /// El tiempo que se enseña puesto: solo el que elegiste. El de la hora ordena (lo que cabe sale primero) pero no filtra, y
    /// por eso la cápsula dice «Cualquier duración» (antes decía «1 h» y salían películas de tres horas).
    public var shownTime: Time? { timeChosen ? time : nil }

    /// Elegir el tiempo (nil: cualquier duración; vuelve el de la hora, solo para ordenar).
    public func chooseTime(_ t: Time?) async {
        setTime(t)
        await apply()
    }

    /// Lo mismo sin barajar todavía (la hoja de filtros aplica todo junto al salir).
    public func setTime(_ t: Time?) {
        if let t { time = t; timeChosen = true } else { time = Self.contextTime(services.now()); timeChosen = false }
    }

    /// «Quitar filtros»: todo menos el tipo (que se ve en su pastilla), igual en las dos pestañas. Sin barajar: quien llama
    /// decide cuándo (`apply`).
    public func clearFilters() {
        genres = []; decades = []; includeWatched = false; sourceIDs = []; fame = .any; awards = []
        minRating = 0; minLetterboxd = 0; mood = nil
        setTime(nil)
    }

    /// Una firma de los filtros puestos: la hoja de filtros solo vuelve a barajar al salir si cambió algo.
    public var filtersSignature: String { filtersKey }

    /// «Barajar» solo si hay más de las que ya se ven (con una o dos no haría nada; F4).
    public var canShuffle: Bool { count() > picks.count }

    // MARK: sin nada que proponer (F2)
    /// Por qué no hay propuesta: sin conexión, sin sugerencias todavía, o por los filtros (solo entonces se ofrece quitar uno).
    public enum Empty: Equatable, Sendable { case offline, nothingSuggested, filters }

    public var empty: Empty? {
        guard pick == nil, exhausted || (picks.isEmpty && !isLoading) else { return nil }
        let online = services.isOnline()
        if candidatesPool.isEmpty { return online ? .nothingSuggested : .offline }
        if activeFilters > 0 { return .filters }
        return online ? .nothingSuggested : .offline
    }

    /// «Reintentar» sin red: lo que se sugiere, otra vez (lo trae quien abrió la hoja), y otra vuelta.
    public func retry(pool newPool: [Suggestion], sources newSources: [Source]) async {
        var seen = Set<String>()
        pool = (newPool + newSources.flatMap(\.items)).filter { seen.insert($0.imdb).inserted }
        sources = newSources.filter { !$0.items.isEmpty || $0.load != nil }
        pick = nil; picks = []; exhausted = false
        await quick()
    }

    // MARK: de qué listas (F7) y opciones muertas (F13)
    /// Las listas tuyas (Mi lista, Favoritos, Tus series, tus listas de Trakt y de Letterboxd) van bajo «Tus listas», como en
    /// Explorar; lo demás bajo «Sugerencias» (antes «Mi lista» salía como sugerencia).
    public nonisolated static func origin(ofShelf id: String) -> String {
        let yours = ["watchlist", ForYou.favoritesList, "mine"].contains(id) || id.hasPrefix("list:") || id.hasPrefix("lb:")
        return yours ? yoursOrigin : suggestedOrigin
    }
    public nonisolated static let yoursOrigin = "Tus listas", suggestedOrigin = "Sugerencias"

    /// Una opción de «Afinar» se puede tocar si deja algo (o si ya está puesta, para quitarla): nunca «Documental · 0».
    public nonisolated static func offered(_ count: Int, selected: Bool) -> Bool { count > 0 || selected }
}
