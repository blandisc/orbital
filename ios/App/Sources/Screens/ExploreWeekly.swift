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
        let cards = model.weekly.filter { !Self.isStrip($0) }, strips = model.weekly.filter(Self.isStrip)
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            DSChapterHead(label: CollectionSection.weekly.title, symbol: CollectionSection.weekly.symbol)
            if !cards.isEmpty {
            CenteredCarousel(items: cards, id: \.id, cardWidth: DS.PlatformFan.width) { collection in
                let list = model.weeklyList(collection.id)
                let words = list?.words(env.services.appSettings.uiLanguage)
                let name = words?.title ?? collection.id
                let art = DS.Collections.art(list?.art, id: collection.id), tint = DS.Collections.artTint(art)
                NavigationLink(value: RepisaCollectionRoute(id: collection.id)) {
                    // Con el color y el ícono de su tema, como Temporadas y Géneros (antes todas en gris).
                    CollectionCard(title: Text(verbatim: name), detail: Text(verbatim: words?.about ?? ""), name: name,
                                   posters: Self.covers(collection), tint: tint) {
                        CollectionIconEmblem(slug: art, name: name, glow: tint)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("weekly-\(collection.id)")
            }
            }
            // Las cortas: solo su tira (el encabezado abre la colección entera).
            ForEach(strips, id: \.id) { collection in strip(collection) }
        }
    }

    static func isStrip(_ collection: CanonCollection) -> Bool {
        // Las de «Hoy» (por ánimo y recetas) traen un tope de títulos, no son cortas: van en tarjeta, en su rueda.
        !collection.items.isEmpty && collection.total <= DS.Collections.stripMax && !collection.id.hasPrefix(RepisaModel.todayPrefix)
    }

    /// La imagen de un capítulo («serie:temporada:episodio»), la misma fuente que el resto de los capítulos.
    static func still(_ item: CanonCollection.Item) -> String? {
        let parts = item.imdb.split(separator: ":")
        guard parts.count == 3 else { return nil }
        return "https://episodes.metahub.space/\(parts[0])/\(parts[1])/\(parts[2])/w780.jpg"
    }

    private func strip(_ collection: CanonCollection) -> some View {
        let words = env.repisa.weeklyList(collection.id)?.words(env.services.appSettings.uiLanguage)
        return Shelf(title: Text(verbatim: words?.title ?? collection.id), destination: RepisaCollectionRoute(id: collection.id)) {
            ForEach(collection.items) { item in
                if let still = Self.still(item) {
                    // Un capítulo (los especiales de Los Simpson): su imagen y su nombre, no el póster de la serie repetido.
                    TitleNavigationLink(route: RepisaCollectionView.titleRoute(item)) {
                        StillCard(title: item.title, art: still, data: item.year.map { [String($0)] } ?? [], fallback: item.poster)   // no-es-título: el nombre de un capítulo de la colección, no el de la serie
                    }
                    .buttonStyle(.plain)
                } else {
                    TitleLink(route: RepisaCollectionView.titleRoute(item), detail: item.year.map { Text(verbatim: String($0)) })
                }
            }
        }
        .padding(.top, DS.Space.s2)
        .accessibilityIdentifier("weekly-strip-\(collection.id)")
    }

    /// Los primeros pósters sin repetir (los capítulos de una serie comparten el de su serie: sale una vez).
    static func covers(_ collection: CanonCollection) -> [String?] {
        var seen = Set<String>()
        return collection.items.map(\.poster).filter { seen.insert($0).inserted }.prefix(DS.Collections.coversPerCard).map { Optional($0) }
    }
}
