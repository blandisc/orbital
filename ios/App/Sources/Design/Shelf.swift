import SwiftUI

// Estantes de «Para ti › Listas» (equivalentes a `shelf`, `card__rank` y `tiles` de la consola; ver ios/README.md).

/// A dónde lleva el encabezado de un estante: la lista completa en cuadrícula.
struct ShelfRoute: Hashable { var id: String }

/// Un estante: encabezado tocable (logo o ícono de la fuente, título, dato secundario y chevron) y, debajo, una tira
/// horizontal que se detiene en cada póster. Mientras carga enseña esqueletos del mismo tamaño (nada salta al llegar).
struct Shelf<Content: View>: View {
    let title: Text
    var meta: Text?
    /// El logo de la plataforma (siempre a la misma altura) o, si no hay, un ícono de la fuente.
    var logo: String?
    var icon: OrbitalIcon?
    /// Sin ruta, el encabezado no es un botón (los estantes de relleno).
    var route: ShelfRoute?
    var loading = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            header.padding(.horizontal, DS.Space.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: DS.Space.s3) {
                    if loading { ShelfSkeleton() } else { content() }
                }
                .scrollTargetLayout()
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
        HStack(spacing: DS.Space.s3) {
            if let logo, !logo.isEmpty { DSPlatformLogo(url: logo) }
            else if let icon { ListIcon(icon: icon) }
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                title.recipe(.section).lineLimit(2).multilineTextAlignment(.leading)
                if let meta { meta.recipe(.footnote).lineLimit(2).multilineTextAlignment(.leading) }
            }
            Spacer(minLength: DS.Space.s2)
            if chevron { Image(systemName: "chevron.right").font(DS.TextRecipe.secondary.font.weight(.semibold)).foregroundStyle(DS.textMuted).accessibilityHidden(true) }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
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

    var body: some View {
        VStack(alignment: .trailing, spacing: DS.Space.s1) {
            numberAndPoster
            if isNew || movement != nil { MovementBadge(movement: movement, isNew: isNew).frame(width: width, alignment: .leading) }
        }
    }

    private var numberAndPoster: some View {
        HStack(alignment: .bottom, spacing: -DS.Space.s5) {
            Text(verbatim: "\(rank)").font(DS.Size.rankFont).foregroundStyle(tint.map { $0.opacity(DS.PlatformFan.numberTint) } ?? DS.ink500)
                .shadow(color: tint ?? .clear, radius: DS.PlatformFan.numberGlow)
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
