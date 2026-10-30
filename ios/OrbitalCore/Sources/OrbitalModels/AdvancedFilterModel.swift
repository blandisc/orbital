import Foundation
import OrbitalCore

/// El cajón del filtro avanzado: lo que eliges (sin pedir nada mientras eliges: sin conteos en vivo) y, al tocar «Ver
/// resultados», la búsqueda en TMDB por páginas. Lo último que usaste se recuerda para la próxima vez.
@MainActor
public final class AdvancedFilterModel: ObservableModel {
    public var filter = AdvancedFilter() { didSet { if filter != oldValue { changed() } } }
    public private(set) var results: [Suggestion] = [] { didSet { changed() } }
    public private(set) var isLoading = false { didSet { changed() } }
    public private(set) var failed = false { didSet { changed() } }
    /// Ya no hay más páginas.
    public private(set) var exhausted = false
    private var page = 0
    private var searched: AdvancedFilter?

    private let services: Services
    public init(_ services: Services) { self.services = services; super.init() }

    /// Sin la clave de TMDB no hay de dónde buscar (la pantalla lo dice y lleva a Ajustes).
    public var available: Bool { services.tmdb.configured }

    /// Busca desde la primera página con el filtro de ahora (si es el mismo de la última vez, no vuelve a pedir).
    public func search() async {
        guard searched != filter || results.isEmpty else { return }
        searched = filter; page = 0; exhausted = false; results = []; failed = false
        await more()
    }

    /// La siguiente página (al llegar al final de la cuadrícula).
    public func more() async {
        guard !isLoading, !exhausted, available else { return }
        let asked = filter
        isLoading = true
        defer { isLoading = false }
        do {
            let rows = try await services.tmdb.discover(asked, page: page + 1)
            guard asked == filter else { return }   // cambiaste el filtro mientras llegaba: se descarta
            page += 1
            if rows.isEmpty { exhausted = true; return }
            let found = await ForYou.suggestions(rows, reason: .popular, tmdb: services.tmdb)
            let have = Set(results.map(\.imdb))
            results += found.filter { !have.contains($0.imdb) }
        } catch {
            failed = results.isEmpty
        }
    }

    /// Quitar todo (el «Limpiar» del cajón).
    public func clear() { filter = AdvancedFilter(); results = []; searched = nil }
}
