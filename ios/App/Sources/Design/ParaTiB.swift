import SwiftUI

// Las piezas de Para ti B (docs/producto/inicio-benchmark/para-ti/): el título de cada grupo, los círculos para saltar a
// cada parte, la portada del mosaico y la tarjeta de «¿Qué vemos hoy?».

/// El título de un grupo de Para ti («Ahora», «Plataformas», «Premios»…): grande, con una frase gris a la derecha.
struct DSGroupTitle: View {
    let title: Text
    var meta: Text?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            title.recipe(.title).accessibilityAddTraits(.isHeader)
            Spacer(minLength: DS.Space.s2)
            if let meta { meta.recipe(.footnote, color: DS.textMuted).lineLimit(1) }
        }
        .padding(.horizontal, DS.Space.gutter)
    }
}

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
                LinearGradient(stops: [.init(color: DS.bg.opacity(DS.ParaTiB.coverTopVeil), location: 0), .init(color: .clear, location: DS.ParaTiB.coverClearAt),
                                       .init(color: DS.bg, location: 1)], startPoint: .top, endPoint: .bottom)
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
struct DecideCard: View {
    let posters: [String]
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: DS.Space.s4) {
                ZStack(alignment: .topLeading) {
                    ForEach(Array(posters.prefix(3).enumerated().reversed()), id: \.offset) { i, url in
                        PosterView(url: url, title: "")
                            .frame(width: DS.ParaTiB.deckPoster)
                            .rotationEffect(.degrees(Double(i) * DS.ParaTiB.deckTurn))
                            .offset(x: CGFloat(i) * DS.ParaTiB.deckShift)
                            .opacity(i == 0 ? 1 : DS.ParaTiB.deckBehind)
                    }
                }
                .frame(width: DS.ParaTiB.deckPoster + DS.ParaTiB.deckShift * 2, alignment: .leading)
                .accessibilityHidden(true)
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
        .accessibilityIdentifier("paraTi-decide")
    }
}
