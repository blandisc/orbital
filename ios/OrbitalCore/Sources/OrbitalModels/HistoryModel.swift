import Foundation
import OrbitalCore

/// El Historial (G5-B, D7-A; F5 de la revisión del 10 nov 2026): todo lo que viste, de 100 en 100, por mes, con las repetidas
/// marcadas. La pantalla solo pinta: qué se carga, qué se borra, cómo se deshace y cuándo hay «Ver más» vive aquí, con
/// pruebas (`HistoryModelTests`), para que lo que la pasada de pulido de la ola 3 arregló a mano no regrese.
@MainActor
public final class HistoryModel: ObservableModel {
    /// Un mes del Historial: «Noviembre», «Octubre 2025».
    public struct Month: Identifiable, Equatable, Sendable {
        public let id: String
        public let entries: [TraktHistoryEntry]
    }

    public private(set) var entries: [TraktHistoryEntry] = [] { didSet { regroup(); changed() } }
    /// Por mes, lo más nuevo primero. Se rearma una vez por cambio de `entries` (A13), no en cada pintado.
    public private(set) var months: [Month] = []
    /// Las repetidas: el mismo título o capítulo con menos de una hora de otra vista (se queda la primera).
    public private(set) var repeats: Set<Int> = []
    /// ¿La última página vino llena? Entonces hay «Ver más».
    public private(set) var more = true { didSet { if oldValue != more { changed() } } }
    public private(set) var loading = false { didSet { if oldValue != loading { changed() } } }
    public private(set) var failed = false { didSet { if oldValue != failed { changed() } } }
    /// El nombre del mes de una fecha (la interfaz lo da en el idioma de la app). Cambiarlo rearma los meses.
    public var monthName: @MainActor (Date) -> String { didSet { regroup(); changed() } }

    private var page = 1
    private let services: Services

    public init(_ services: Services, monthName: @escaping @MainActor (Date) -> String) {
        self.services = services
        self.monthName = monthName
        super.init()
    }

    /// El video de una entrada: la película o «tt…:temporada:capítulo».
    public static func videoID(_ e: TraktHistoryEntry) -> String {
        guard let s = e.target.season, let n = e.target.episode else { return e.target.imdb }
        return "\(e.target.imdb):\(s):\(n)"
    }

    /// La primera página, si aún no hay nada.
    public func loadIfNeeded() async { if entries.isEmpty { await loadMore() } }

    /// La página que sigue (de 100 en 100). Lo que ya estaba no se repite.
    public func loadMore() async {
        guard !loading else { return }
        loading = true; failed = false
        do {
            let found = try await services.watch.history(page: page)
            let known = Set(entries.map(\.id))
            entries += found.entries.filter { !known.contains($0.id) }
            more = found.full   // contado antes de quitar lo borrado aquí: «Ver más» no se apaga antes de tiempo
            page += 1
        } catch { failed = true }
        loading = false
    }

    /// Desde el principio (deslizar hacia abajo, tras cambiar una fecha o deshacer).
    public func reload() async {
        guard !loading else { return }   // con una página en camino, reiniciar la dejaría caer en una lista vacía
        entries = []; page = 1; more = true
        await loadMore()
    }

    /// Lo quita de la lista ya (la pantalla lo anima) y devuelve el envío a Trakt. El Historial solo ve las páginas que cargó:
    /// la película no deja de contar como vista sin preguntarle a Trakt si quedan vistas más viejas (`sure: false`).
    public func remove(_ e: TraktHistoryEntry) -> @MainActor () async -> Void {
        let left = entries.filter { $0.target == e.target && $0.id != e.id }.count
        entries.removeAll { $0.id == e.id }
        let watch = services.watch
        return { await watch.removeViewing(TraktViewing(id: e.id, at: e.at), kind: e.kind, metaID: e.target.imdb, videoID: Self.videoID(e),
                                           remaining: left, sure: false) }
    }

    /// «Deshacer» de «Vista borrada»: la misma vista, con su fecha, otra vez; luego la lista desde el principio.
    public func undoRemove(_ e: TraktHistoryEntry) async {
        await services.watch.addViewing(kind: e.kind, metaID: e.target.imdb, videoID: Self.videoID(e), name: e.title, at: e.at)
        await reload()
    }

    /// Otra fecha: la nueva entra y la vieja sale solo cuando la nueva llegó a Trakt (nunca se pierde la vista).
    public func move(_ e: TraktHistoryEntry, to date: Date) async {
        await services.watch.moveViewing(TraktViewing(id: e.id, at: e.at), kind: e.kind, videoID: Self.videoID(e), to: date)
        await reload()
    }

    /// «Agregar»: una película que viste fuera de Orbital, con su fecha (las series se marcan en su ficha).
    public func addMovie(metaID: String, title: String, at date: Date) async {
        await services.watch.addViewing(kind: "movie", metaID: metaID, videoID: metaID, name: title, at: date)
        await reload()
    }

    /// Quita todas las repetidas de una vez (un solo envío). Lo visto no cambia: de cada una queda la primera. Devuelve cuántas.
    public func removeRepeats() -> (count: Int, send: @MainActor () async -> Void) {
        let ids = Array(repeats)
        entries.removeAll { ids.contains($0.id) }
        let watch = services.watch
        return (ids.count, { await watch.removeViewings(ids) })
    }

    private func regroup() {
        repeats = Trakt.repeats(entries)
        var order: [String] = []
        var groups: [String: [TraktHistoryEntry]] = [:]
        for e in entries {
            let key = monthName(e.at)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(e)
        }
        months = order.map { Month(id: $0, entries: groups[$0] ?? []) }
    }
}
