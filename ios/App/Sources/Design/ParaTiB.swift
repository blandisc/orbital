import SwiftUI

// Las piezas de Para ti B (docs/producto/inicio-benchmark/para-ti/): los círculos para saltar a cada parte, la portada del mosaico y la
// tarjeta de «¿Qué vemos hoy?».

/// Un círculo por cada parte de Para ti: tocarlo baja hasta ella.
struct SectionCircles<ID: Hashable>: View {
    struct Item: Identifiable { let id: ID; let title: Text; let symbol: String }
    let items: [Item]
    let jump: (ID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: DS.Space.s3) {
                // Por posición, no por su id: el id es el de la sección, y saltar a ella movería esta fila en vez de la página.
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Button { jump(item.id) } label: {
                        VStack(spacing: DS.Space.s2) {
                            Image(systemName: item.symbol).font(DS.TextRecipe.section.font)
                                .foregroundStyle(DS.text)
                                .frame(width: DS.ParaTiB.circle, height: DS.ParaTiB.circle)
                                .background(DS.fill, in: Circle())
                            item.title.recipe(.caption, color: DS.textMuted).lineLimit(1)
                        }
                        .frame(width: DS.ParaTiB.circleLabel)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .contentMargins(.horizontal, DS.Space.gutter, for: .scrollContent)
    }
}

/// La portada de Para ti: un muro de pósters inclinado (el mosaico, en quieto) que se funde con el fondo, con su porqué y
/// «Pasear por el mosaico».
struct MosaicCover: View {
    let posters: [String]
    let onWalk: () -> Void

    var body: some View {
        // El muro va como capa sobre un marco fijo: más ancho que la pantalla e inclinado, no ensancha la página.
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: DS.ParaTiB.coverHeight)
            .overlay {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s2), count: DS.ParaTiB.coverColumns), spacing: DS.Space.s2) {
                    ForEach(Array(posters.prefix(DS.ParaTiB.coverPosters).enumerated()), id: \.offset) { _, url in
                        PosterView(url: url, title: "")
                    }
                }
                .frame(width: DS.ParaTiB.coverWall)
                .rotationEffect(.degrees(DS.ParaTiB.coverTilt))
                .accessibilityHidden(true)
            }
            .overlay {
                // Arriba se funde con la barra; abajo un velo firme bajo el porqué y el botón, para que se lean sobre cualquier póster.
                LinearGradient(stops: [.init(color: DS.bg.opacity(DS.ParaTiB.coverTopVeil), location: 0), .init(color: .clear, location: DS.ParaTiB.coverClearAt),
                                       .init(color: DS.bg.opacity(DS.ParaTiB.coverBaseVeil), location: DS.ParaTiB.coverBaseAt), .init(color: DS.bg, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .clipped()
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    Eyebrow(text: Text("Todas las formas de encontrar qué ver"), reason: true)
                    Button(action: onWalk) { Label("Pasear por el mosaico", systemImage: "square.grid.3x3.fill") }
                        .dsPrimaryButton()
                        .accessibilityIdentifier("paraTi-walk-mosaic")
                }
                .padding(.horizontal, DS.Space.gutter).padding(.bottom, DS.Space.s3)
            }
    }
}

/// «¿Qué vemos hoy?»: la entrada a encontrar tu match (tres pósters en abanico, el porqué y cómo se usa).
struct MatchTeaser: View {
    let posters: [String]
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: DS.Space.s4) {
                PosterFan(posters: posters, width: DS.ParaTiB.deckPoster)
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Eyebrow(text: Text("Encuentra tu match perfecto"), reason: true)
                    Text("¿Qué vemos hoy?").recipe(.section)
                    Text("A la derecha la guardas, a la izquierda no.").recipe(.footnote, color: DS.textMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(DS.Space.s4)
            .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DS.Space.gutter)
        .accessibilityIdentifier("paraTi-match")
    }
}

/// Tres pósters en abanico, el primero al frente y los otros asomando girados detrás («¿Qué vemos hoy?», «La temporada»).
struct PosterFan: View {
    let posters: [String]
    let width: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(posters.prefix(DS.ParaTiB.matchFan).enumerated().reversed()), id: \.offset) { i, url in
                PosterView(url: url, title: "")
                    .frame(width: width)
                    .rotationEffect(.degrees(Double(i) * DS.ParaTiB.deckTurn))
                    .offset(x: CGFloat(i) * DS.ParaTiB.deckShift)
                    .opacity(i == 0 ? 1 : DS.ParaTiB.deckBehind)
            }
        }
        .frame(width: width + DS.ParaTiB.deckShift * CGFloat(DS.ParaTiB.matchFan - 1), alignment: .leading)
        .accessibilityHidden(true)
    }
}

/// «La temporada»: la de ahora (o la siguiente en llegar) en grande, con su color, cuándo, su frase, sus tres más vistos en
/// abanico y «Ver la colección».
struct SeasonFeature: View {
    let name: String
    let blurb: String
    let days: Int
    let posters: [String]
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.s4) {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Eyebrow(text: when, reason: true)
                Text(verbatim: name).recipe(.title).lineLimit(2).minimumScaleFactor(DS.Size.titleShrink)
                Text(verbatim: blurb).recipe(.footnote, color: DS.textMuted).lineLimit(2)
                DSCapsuleLabel(title: Text("Ver la colección"), symbol: "chevron.right", symbolFirst: false).padding(.top, DS.Space.s2)
            }
            Spacer(minLength: 0)
            if !posters.isEmpty { PosterFan(posters: posters, width: DS.ParaTiB.seasonPoster) }
        }
        .padding(DS.Space.s4)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous).fill(DS.surface)
                .overlay(LinearGradient(colors: [tint.opacity(DS.ParaTiB.seasonGlow), .clear], startPoint: .topTrailing, endPoint: .bottomLeading)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)))
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// «La temporada · ahora», «… · mañana» o «… · en 12 días».
    private var when: Text {
        switch days {
        case 0: Text("La temporada · ahora")
        case 1: Text("La temporada · mañana")
        default: Text("La temporada · en \(days) días")
        }
    }
}

/// Un renglón de «Tuyo» (Mi lista, Favoritos, Tus series y tus listas de Trakt): tres pósters encimados, el nombre, qué es y
/// cuántos tiene.
struct ListRow: View {
    let name: String
    let detail: Text
    let posters: [String]

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            ZStack(alignment: .leading) {
                ForEach(Array(posters.prefix(DS.ParaTiB.matchFan).enumerated().reversed()), id: \.offset) { i, url in
                    PosterView(url: url, title: "").frame(width: DS.Collections.stackPoster)
                        .offset(x: CGFloat(i) * DS.ParaTiB.rowShift)
                        .shadow(DS.Elevation.low.drop(DS.Space.s1))
                }
            }
            .frame(width: DS.Collections.stackPoster + DS.ParaTiB.rowShift * CGFloat(DS.ParaTiB.matchFan - 1), alignment: .leading)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(verbatim: name).recipe(.cardTitle).lineLimit(1)
                detail.recipe(.footnote, color: DS.textMuted).lineLimit(1)
            }
            Spacer(minLength: DS.Space.s2)
            Image(systemName: "chevron.right").font(DS.TextRecipe.footnote.font.weight(.semibold)).foregroundStyle(DS.textFaint)
        }
        .padding(DS.Space.s2)
        .padding(.trailing, DS.Space.s2)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
