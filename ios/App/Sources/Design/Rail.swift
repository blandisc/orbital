import SwiftUI
import OrbitalCore
import OrbitalModels

/// La fila horizontal de portadas (`Rail`) y la portada que lleva a la ficha (`TitleLink`), con su reflejo opcional.
extension EnvironmentValues {
    /// El nombre bajo cada póster: sí en cuadrículas, no en las tiras de una sección (el póster ya lo dice).
    @Entry var posterCaptions = true
    /// Los pósters de esta fila llevan su reflejo debajo (lo pone `Rail(reflected:)`).
    @Entry var railReflected = false
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
    /// Con el reflejo de cada póster debajo. La fila se encarga de todo: se lo pone a sus pósters y deja que la sección siguiente
    /// se monte sobre la parte desvanecida (`reflectionTail`), así el aire con lo que sigue es el mismo en toda la app. Antes
    /// cada pantalla lo ajustaba a mano y en Inicio no: entre «Para ti» y el Top 10 quedaba el reflejo entero más el aire.
    var reflected = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        if reflected { rail.environment(\.railReflected, true).reflectionTail() } else { rail }
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Group {
                if let route {
                    NavigationLink(value: route) { DSSectionHead(title: Text(title), trailing: trailing.map { Text($0) }, count: count, chevron: true, source: source, eyebrow: eyebrow) }
                        .buttonStyle(.plain)
                } else {
                    DSSectionHead(title: Text(title), trailing: trailing.map { Text($0) }, count: count, source: source, eyebrow: eyebrow)
                }
            }
            .padding(.horizontal, DS.Space.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: DS.Space.s3) { content() }.scrollTargetLayout().environment(\.posterCaptions, false)
            }
            .contentMargins(.horizontal, DS.Space.gutter, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
        }
    }
}

/// Una portada que lleva a la ficha, con su nombre debajo.
struct TitleLink: View {
    let route: TitleRoute
    var badge: LocalizedStringKey?
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
    @Environment(\.posterCaptions) private var captions
    /// El reflejo del póster lo decide su fila (`Rail`, `Shelf` con `reflected: true`), nunca cada póster.
    @Environment(\.railReflected) private var railReflected

    var body: some View {
        link.modifier(OptionalPosterReflection(on: railReflected && !captions, url: route.poster, title: route.title, width: width))
    }

    private var link: some View {
        NavigationLink(value: route) {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                PosterCard(title: route.title, poster: route.poster, badge: badge, bookmarked: bookmarked, rank: rank, progress: progress, width: width)
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

private struct OptionalPosterReflection: ViewModifier {
    let on: Bool
    let url: String?
    let title: String
    let width: CGFloat
    func body(content: Content) -> some View {
        if on { content.posterReflection(url, title: title, width: width) } else { content }
    }
}

