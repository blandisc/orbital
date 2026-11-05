import SwiftUI
import OrbitalCore
import OrbitalModels

/// La fila horizontal de portadas (`Rail`) y la portada que lleva a la ficha (`TitleLink`). Sin reflejos: se quitaron de toda
/// la app (Fernando, 2 nov 2026, C1/F3/G4/H1: un efecto de moda que no decía nada del título).
extension EnvironmentValues {
    /// El nombre bajo cada póster: sí en cuadrículas, no en las tiras de una sección (el póster ya lo dice).
    @Entry var posterCaptions = true
}


/// Una fila horizontal de portadas con su título; con `route`, el encabezado dice cuántos hay y abre la lista completa.
struct Rail<Content: View>: View {
    let title: LocalizedStringKey
    var trailing: LocalizedStringKey?
    var count: Int?
    var route: HomeListRoute?
    /// El porqué arriba del título y de dónde viene (su sello).
    var eyebrow: Text?
    var source: ListSource?
    /// Una fila de descubrir junto a lo tuyo (Inicio): el título un paso más chico (`DSSectionHead(quiet:)`).
    var quiet = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Group {
                if let route {
                    NavigationLink(value: route) { DSSectionHead(title: Text(title), trailing: trailing.map { Text($0) }, count: count, chevron: true, source: source, eyebrow: eyebrow, quiet: quiet) }
                        .buttonStyle(.plain)
                } else {
                    DSSectionHead(title: Text(title), trailing: trailing.map { Text($0) }, count: count, source: source, eyebrow: eyebrow, quiet: quiet)
                }
            }
            .padding(.horizontal, DS.Space.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: DS.Space.s3) { content() }.scrollTargetLayout().environment(\.posterCaptions, false)
            }
            .contentMargins(.horizontal, DS.Space.gutter, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .edgeBump()   // al final de la fila, un golpe suave en la mano
        }
    }
}

/// Una portada que lleva a la ficha, con su nombre debajo.
struct TitleLink: View {
    let route: TitleRoute
    var badge: LocalizedStringKey?
    /// El ícono de la placa (el calendario de cuándo sale).
    var badgeSymbol: String?
    /// Su puesto en una plataforma: la píldora con su logo (`PlatformBadge`).
    var platformRank: (rank: Int, platform: String)?
    /// Está en tu watchlist: un marcador en la esquina (sin texto que se corte en un póster angosto).
    var bookmarked = false
    /// El puesto en un Top 10 (chart de Netflix, JustWatch…), si la lista lo trae.
    var rank: Int?
    var progress: Double?
    var width: CGFloat = DS.Poster.railWidth
    /// Un renglón más debajo del nombre («2021 · Película»): distingue títulos que se llaman igual.
    var detail: Text?
    /// Cuántos renglones puede ocupar `detail` (2 con letra de accesibilidad en Buscar).
    var detailLines = 1
    /// Otro póster si el primero no carga (Buscar: el de TMDB).
    var fallbackPoster: String? = nil
    @Environment(\.posterCaptions) private var captions

    var body: some View {
        TitleNavigationLink(route: route) {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                PosterCard(title: route.title, poster: route.poster, badge: badge, badgeSymbol: badgeSymbol, platformRank: platformRank, bookmarked: bookmarked, rank: rank, progress: progress, width: width, fallback: fallbackPoster)
                    .titleZoomSource(route)
                // En una tira (Editorial) el póster habla solo; en una cuadrícula (resultados, géneros) el nombre ayuda a distinguir.
                if captions {
                    Text(route.title).recipe(.footnote).lineLimit(1).frame(width: width, alignment: .leading)
                    if let detail { detail.recipe(.footnote).lineLimit(detailLines).frame(width: width, alignment: .leading) }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("title-link")   // para las pruebas de interfaz
    }
}
