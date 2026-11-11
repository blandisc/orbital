import Foundation
import OrbitalCore

/// Lo que no se pudo guardar en Trakt (la bitácora de la cola única, `TraktQueue.discards`), para Ajustes › Cuentas › Trakt:
/// un renglón discreto «N cosas no se pudieron guardar en Trakt» que abre la lista con qué fue, cuándo y por qué, en palabras
/// llanas, y «Reintentar» para lo que venció (revisión del 11 nov 2026: antes se guardaba y nadie lo veía).
@MainActor
public final class TraktDiscardsModel: ObservableModel {
    /// Un renglón de la lista. Los textos son llaves del catálogo (`Localizable.xcstrings`); el título va tal cual.
    public struct Row: Equatable, Identifiable, Sendable {
        public var id: String
        /// Qué era: «Visto», «Tu calificación»… (llave del catálogo).
        public var action: String
        /// De qué título: su nombre si la app lo conoce; si no, su id. Con «T2 · E5» si era un episodio.
        public var title: String
        public var season: Int?
        public var episode: Int?
        /// Cuántos eran, si eran varios.
        public var count: Int
        public var at: Date
        /// Por qué (llave del catálogo; con `%lld` el código que dijo Trakt).
        public var reason: String
        public var status: Int?
        public var canRetry: Bool
        let discard: TraktDiscard
    }

    public private(set) var rows: [Row] = [] { didSet { if rows != oldValue { changed() } } }
    private let services: Services

    public init(_ services: Services) {
        self.services = services
        super.init()
        reload()
    }

    /// Cuántos hay (para el renglón de Ajustes: sin ninguno, no sale).
    public var count: Int { rows.count }

    public func reload() {
        let library = services.library
        rows = services.traktQueue.discards.reversed().enumerated().map { index, d in
            let name = d.target.flatMap { library.entry($0.imdb)?.name }.flatMap { $0.isEmpty ? nil : $0 }
            return Row(id: "\(d.at)-\(index)", action: Self.action(d), title: name ?? d.target?.imdb ?? d.what,
                       season: d.target?.season, episode: d.target?.episode, count: d.count ?? 1, at: Date(timeIntervalSince1970: d.at),
                       reason: Self.reason(d), status: d.status, canRetry: d.canRetry, discard: d)
        }
    }

    /// «Reintentar»: vuelve a la cola y se manda en cuanto haya red.
    public func retry(_ row: Row) async {
        services.traktQueue.retry(row.discard)
        reload()
        await services.watch.flushPending()
        reload()
    }

    /// «Borrar la lista»: ya lo viste.
    public func clear() {
        services.traktQueue.clearDiscards()
        reload()
    }

    static func action(_ d: TraktDiscard) -> String {
        switch d.kind {
        case .watched?: (d.count ?? 1) > 1 ? "Marcar como vistos" : "Marcar como visto"
        case .unwatched?: "Marcar como no visto"
        case .rewatched?: "Otra vista o una fecha cambiada"
        case .viewingRemovals?: "Borrar vistas"
        case .continueRemoval?: "Quitar de Seguir viendo"
        case .progress?: "Dónde te quedaste"
        case .watchlist?: "Mi lista"
        case .favorites?: "Favoritos"
        case .rating?: "Tu calificación"
        case .hidden?: "Series que dejaste"
        case .note?: "Tu nota"
        case .list?: "Una de tus listas"
        case nil: "Algo de tu cuenta"
        }
    }

    static func reason(_ d: TraktDiscard) -> String {
        switch d.cause {
        case .expired?: "Pasaron 30 días sin poder mandarlo"
        case .refused?: d.status == 404 ? "Trakt ya no lo encuentra (la lista o el título se borró)" : "Trakt no lo aceptó (código %lld)"
        case .invalid?: "Trakt no reconoce el título"
        case nil: d.reason.contains("venció") ? "Pasaron 30 días sin poder mandarlo" : "Trakt no lo aceptó"
        }
    }
}
