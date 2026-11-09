import SwiftUI
import OrbitalModels

// Estantes de «Para ti › Listas» (equivalentes a `shelf`, `card__rank` y `tiles` de la consola; ver ios/README.md).

/// A dónde lleva el encabezado de un estante: la lista completa en cuadrícula.
struct ShelfRoute: Hashable { var id: String }

/// Un estante: encabezado tocable (logo o ícono de la fuente, título, dato secundario y chevron) y, debajo, una tira
/// horizontal que se detiene en cada póster. Mientras carga enseña esqueletos del mismo tamaño (nada salta al llegar).
struct Shelf<Content: View>: View {
    let title: Text
    var meta: Text?
    /// Sin ruta, el encabezado no es un botón (los estantes de relleno).
    var route: ShelfRoute?
    var loading = false
    /// De dónde viene (su sello junto al título).
    var source: ListSource?
    /// El porqué arriba del título, en ámbar (va en lugar de `meta`, abajo).
    var eyebrow: Text?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            header.padding(.horizontal, DS.Space.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: DS.Space.s3) {
                    if loading { ShelfSkeleton() } else { content() }
                }
                .scrollTargetLayout()
                .environment(\.posterCaptions, false)
            }
            .contentMargins(.horizontal, DS.Space.gutter, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .edgeBump()   // al final de la fila, un golpe suave en la mano
        }
    }

    @ViewBuilder private var header: some View {
        if let route {
            NavigationLink(value: route) { headerRow(chevron: true) }.buttonStyle(.plain)
        } else { headerRow(chevron: false) }
    }

    private func headerRow(chevron: Bool) -> some View {
        DSSectionHead(title: title, chevron: chevron, meta: meta, source: source, eyebrow: eyebrow)
    }
}

/// Pósters vacíos mientras llega un estante.
struct ShelfSkeleton: View {
    var body: some View {
        ForEach(0..<4, id: \.self) { _ in
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.fill)
                .aspectRatio(DS.Poster.aspect, contentMode: .fit)
                .frame(width: DS.Poster.railWidth)
        }
        .accessibilityHidden(true)
    }
}

/// El lugar de un feed (Inicio, Explorar) la primera vez, mientras llega: la portada a sangre con la medida de la de verdad
/// (`DS.HomeHero.current`) y un estante debajo (nada salta al llegar). Antes dibujaba la tarjeta del carrusel 3D que ya no existe.
struct HeroSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Layout.betweenSubsections) {
            Rectangle().fill(DS.fill)
                .aspectRatio(DS.HomeHero.current, contentMode: .fit)
                .frame(maxWidth: .infinity)
            HStack(spacing: DS.Space.s3) { ShelfSkeleton() }
                .padding(.horizontal, DS.Space.gutter)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
        }
        .accessibilityHidden(true)
    }
}

/// «Ver todo» de lo más popular hoy. Una ruta (no `isPresented`): así los títulos de adentro también se abren.
struct PopularRoute: Hashable {}

/// «Lo más popular hoy»: el Top 10 de lo que más se está viendo ahora en Trakt, con la cifra grande (el mismo lenguaje que
/// los rankings de tus plataformas). Películas y series alternadas. Una franja más de Explorar (BX, Fernando, 9 nov 2026:
/// antes vivía en Buscar, que se quedó solo para buscar); su «Ver todo» abre `PopularGridView`.
struct PopularTodayShelf: View {
    let items: [CatalogItem]
    /// Cuántos van en la franja con puesto (un Top 10).
    static let count = 10

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            NavigationLink(value: PopularRoute()) {
                DSSectionHead(title: "Lo más popular hoy", chevron: true, meta: Text("Lo más visto hoy en Trakt"))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, DS.Space.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: DS.Space.s3) {
                    ForEach(Array(items.prefix(Self.count).enumerated()), id: \.element.id) { index, item in
                        let route = TitleRoute(kind: item.kind, metaID: item.metaID, title: item.title, poster: item.poster)
                        TitleNavigationLink(route: route) {
                            RankedPosterCard(rank: index + 1, title: item.title, poster: item.poster, zoom: route)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, DS.Space.gutter, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .edgeBump()   // al final de la fila, un golpe suave en la mano, como los demás estantes
        }
    }
}

/// Un puesto del Top 10 al estilo Netflix: la cifra enorme en gris, parcialmente detrás del póster, que va encima a la derecha.
struct RankedPosterCard: View {
    let rank: Int
    let title: String
    let poster: String?
    var width: CGFloat = DS.Poster.railWidth
    /// Cuánto se movió y si es nuevo (el Top 10 real de la TV): va bajo el póster.
    var movement: Int?
    var isNew = false
    /// El color de la plataforma: la cifra toma un tono suyo y su brillo (la página de rankings). Sin él, gris.
    var tint: Color?
    /// La ficha que abre: el zoom sale solo del póster. Puesto en toda la tarjeta, la sombra del zoom pintaba una mancha
    /// negra detrás del número (Fernando, 1 nov 2026).
    var zoom: TitleRoute?

    var body: some View { bodyContent.pointerHover(.lift) }
    @ViewBuilder private var bodyContent: some View {
        VStack(alignment: .trailing, spacing: DS.Space.s1) {
            numberAndPoster
            if isNew || movement != nil { MovementBadge(movement: movement, isNew: isNew).frame(width: width, alignment: .leading) }
        }
    }

    private var numberAndPoster: some View {
        // El «10», del mismo tamaño que las demás: sus cifras más juntas y el póster le tapa un poco más el cero (como Netflix).
        // El «1» es angosto: el póster casi lo tapaba; con él, apenas se encima.
        HStack(alignment: .bottom, spacing: rank >= 10 ? -DS.Size.rankTwoDigitsOverlap : rank == 1 ? -DS.Space.s1 : -DS.Space.s5) {
            // La cifra con su halo (Fernando, 1 nov 2026: el halo sí; la mancha negra de detrás era la sombra del zoom).
            Text(verbatim: "\(rank)").font(DS.Size.rankFont).foregroundStyle(tint.map { $0.opacity(DS.PlatformFan.numberTint) } ?? DS.ink500)
                .glow(tint ?? .clear)
                .tracking(DS.Size.rankTracking)
                .lineLimit(1).fixedSize()
                .padding(.bottom, -DS.Space.s3)   // la cifra se apoya en la base del póster (sin el hueco del renglón)
                .accessibilityHidden(true)
            Group {
                if let zoom { PosterView(url: poster, title: title).frame(width: width).titleZoomSource(zoom) }
                else { PosterView(url: poster, title: title).frame(width: width) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Puesto \(rank)")).accessibilityValue(Text(title))
        .accessibilityIdentifier("ranked-poster")   // para las pruebas de interfaz
    }
}
