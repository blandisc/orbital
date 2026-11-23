import SwiftUI
import OrbitalCore
import OrbitalModels

/// «Esta semana» en Explorar (Fernando, 23 nov 2026, ED-B y ED-C): las listas de `listas/explorar.json` que tocan hoy. Primero
/// los especiales de temporada (los de Halloween y Navidad de Los Simpson, el terror en octubre), luego las listas famosas que
/// rotan cada lunes. Cada tarjeta es como las de Premios (abanico de pósters, nombre y de qué se trata debajo) y abre su
/// colección, la misma pantalla que Criterion o el Top 250. Sin tabla ni copia guardada, la sección no sale.
struct ExploreWeekly: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let model = env.repisa
        let _ = model.track()
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            DSChapterHead(label: CollectionSection.weekly.title, symbol: CollectionSection.weekly.symbol)
            CenteredCarousel(items: model.weekly, id: \.id, cardWidth: DS.PlatformFan.width) { collection in
                let list = model.weeklyList(collection.id)
                let name = list?.title ?? collection.id
                NavigationLink(value: RepisaCollectionRoute(id: collection.id)) {
                    CollectionCard(title: Text(verbatim: name), detail: Text(verbatim: list?.about ?? ""), name: name,
                                   posters: Self.covers(collection), tint: DS.Collections.genre(collection.id)) { EmptyView() }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("weekly-\(collection.id)")
            }
        }
    }

    /// Los primeros pósters sin repetir (los capítulos de una serie comparten el de su serie: sale una vez).
    static func covers(_ collection: CanonCollection) -> [String?] {
        var seen = Set<String>()
        return collection.items.map(\.poster).filter { seen.insert($0).inserted }.prefix(DS.Collections.coversPerCard).map { Optional($0) }
    }
}
