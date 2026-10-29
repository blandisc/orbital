import SwiftUI

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
            RoundedRectangle(cornerRadius: DS.Radius.md).fill(DS.fill)
                .aspectRatio(DS.Poster.aspect, contentMode: .fit)
                .frame(width: DS.Poster.railWidth)
        }
        .accessibilityHidden(true)
    }
}

/// El lugar de un feed (Inicio, Para ti) la primera vez, mientras llega: la tarjeta del destacado y un estante, del mismo
/// tamaño que lo de verdad (nada salta al llegar).
struct FeedSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Editorial.sectionGap) {
            RoundedRectangle(cornerRadius: DS.Deck.radius).fill(DS.fill)
                .frame(height: DS.Deck.height)
                .padding(.horizontal, DS.Deck.sideMargin)
            HStack(spacing: DS.Space.s3) { ShelfSkeleton() }
                .padding(.horizontal, DS.Space.gutter)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
        }
        .accessibilityHidden(true)
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
            Text(verbatim: "\(rank)").font(DS.Size.rankFont).foregroundStyle(tint.map { $0.opacity(DS.PlatformFan.numberTint) } ?? DS.ink500)
                .shadow(color: tint ?? .clear, radius: DS.PlatformFan.numberGlow)
                .tracking(DS.Size.rankTracking)
                .lineLimit(1).fixedSize()
                .padding(.bottom, -DS.Space.s3)   // la cifra se apoya en la base del póster (sin el hueco del renglón)
                .accessibilityHidden(true)
            PosterView(url: poster, title: title).frame(width: width)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Puesto \(rank)")).accessibilityValue(Text(title))
        .accessibilityIdentifier("ranked-poster")   // para las pruebas de interfaz
    }
}
