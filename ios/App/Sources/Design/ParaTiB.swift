import SwiftUI

// Las piezas de Para ti B (docs/producto/inicio-benchmark/para-ti/): los círculos para saltar a cada parte, la portada del mosaico y la
// tarjeta de «¿Qué vemos hoy?».

/// La portada de Para ti: un muro de pósters inclinado que se funde con el fondo, con su porqué y «Pasear por el mosaico».
/// El muro sube detrás de la barra y baja un poco bajo los círculos, apagándose poco a poco en las dos orillas (antes se
/// cortaba en seco); el espacio de la página no cambia. Cada vez que se arma salen otros pósters en otro orden, y el muro
/// se desliza despacio sobre su diagonal (quieto con «Reducir movimiento» o fuera de pantalla).
struct MosaicCover: View {
    let posters: [String]
    let onWalk: () -> Void
    @State private var order: [String] = []
    @State private var onScreen = true
    /// El muro de la última vez (de qué pósters salió y su orden): sobrevive a que la pantalla se vuelva a armar.
    @MainActor private static var remembered: (source: [String], order: [String]) = ([], [])
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: DS.ParaTiB.coverHeight)
            .overlay {
                // El arte ocupa más que su marco (arriba y abajo) pero no ensancha la página: se recorta a los lados.
                ZStack { moving; veil }
                    .padding(.top, -DS.ParaTiB.coverBleedUp).padding(.bottom, -DS.ParaTiB.coverBleedDown)
                    .mask { fade }
                    .clipped()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .overlay(alignment: .bottomTrailing) {
                // El ícono del mosaico abajo a la derecha, negro sobre blanco (Fernando, 31 oct 2026: en vez de «Pasear por
                // el mosaico»).
                Button(action: onWalk) {
                    Image(systemName: "square.grid.3x3.fill").font(DS.TextRecipe.cardTitle.font.weight(.semibold))
                        .foregroundStyle(DS.backdropDeep)
                        .frame(width: DS.ParaTiB.walkButton, height: DS.ParaTiB.walkButton)
                        .background(DS.paper, in: Circle())
                        .shadow(color: DS.scrimStrong, radius: DS.Space.s2, y: DS.Space.s1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Pasear por el mosaico"))
                .accessibilityIdentifier("paraTi-walk-mosaic")
                .padding(.horizontal, DS.Space.gutter)
            }
            .onScrollVisibilityChange(threshold: DS.ParaTiB.coverVisibleFrom) { onScreen = $0 }
            // Otro muro cuando llegan otros pósters; al volver del mosaico, el mismo de antes (Fernando, 31 oct 2026: revolverlo
            // otra vez pedía pósters nuevos y el muro se quedaba negro unos segundos).
            .onChange(of: posters, initial: true) {
                if Self.remembered.source == posters, !Self.remembered.order.isEmpty { order = Self.remembered.order; return }
                // Revueltos y, si son pocos, repetidos hasta llenar el muro (al jalar para actualizar no queda hueco arriba).
                let pool = posters.shuffled()
                order = pool.isEmpty ? [] : (0..<DS.ParaTiB.coverPosters).map { pool[$0 % pool.count] }
                Self.remembered = (posters, order)
            }
    }

    /// El vaivén: el muro baja y sube un renglón sobre su diagonal, sin prisa (quieto con «Reducir movimiento» o fuera de pantalla).
    @ViewBuilder private var moving: some View {
        if reduceMotion || !onScreen {
            wall
        } else {
            wall.phaseAnimator([false, true]) { view, drifted in
                view.offset(x: drifted ? DS.ParaTiB.coverDriftX : 0, y: drifted ? DS.ParaTiB.coverDrift : 0)
            } animation: { _ in DS.ParaTiB.coverDriftAnimation }
        }
    }

    /// Un muro fijo (no perezoso): girado y más alto que su marco dentro del desplazamiento de la página, una rejilla perezosa
    /// no sabía qué piezas se veían y las armaba tarde (al volver del mosaico se quedaba negro unos segundos).
    private var wall: some View {
        let columns = DS.ParaTiB.coverColumns
        let rows = stride(from: 0, to: order.count, by: columns).map { Array(order[$0..<min($0 + columns, order.count)]) }
        return VStack(spacing: DS.Space.s2) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: DS.Space.s2) {
                    ForEach(rows[r].indices, id: \.self) { c in PosterView(url: rows[r][c], title: "", maxPoints: DS.Image.mosaic) }
                }
            }
        }
        .frame(width: DS.ParaTiB.coverWall)
        .rotationEffect(.degrees(DS.ParaTiB.coverTilt))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Las orillas: arriba sube mucho más que la pantalla (al jalar para actualizar siguen los pósters, Fernando, 31 oct
    /// 2026) y pasa detrás del título y la barra sin corte; abajo se apaga
    /// hasta perderse bajo los círculos.
    private var fade: some View {
        let up = DS.ParaTiB.coverBleedUp, total = up + DS.ParaTiB.coverHeight + DS.ParaTiB.coverBleedDown
        return LinearGradient(stops: [
            .init(color: .black.opacity(DS.ParaTiB.coverUnderBar), location: 0),
            .init(color: .black.opacity(DS.ParaTiB.coverUnderBar), location: (up - DS.ParaTiB.coverTitleZone) / total),
            .init(color: .black, location: up / total),
            .init(color: .black, location: (up + DS.ParaTiB.coverHeight * DS.ParaTiB.coverBaseAt) / total),
            .init(color: .clear, location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }

    /// Un velo bajo el porqué y el botón, para que se lean sobre cualquier póster; sigue de largo bajo los círculos.
    private var veil: some View {
        let up = DS.ParaTiB.coverBleedUp, total = up + DS.ParaTiB.coverHeight + DS.ParaTiB.coverBleedDown
        return LinearGradient(stops: [
            .init(color: DS.bg.opacity(DS.ParaTiB.coverTitleVeil), location: 0),   // el título grande se lee encima
            .init(color: DS.bg.opacity(DS.ParaTiB.coverTitleVeil), location: (up - DS.ParaTiB.coverTitleZone) / total),
            .init(color: .clear, location: up / total),
            .init(color: .clear, location: (up + DS.ParaTiB.coverHeight * DS.ParaTiB.coverClearAt) / total),
            .init(color: DS.bg.opacity(DS.ParaTiB.coverBaseVeil), location: (up + DS.ParaTiB.coverHeight) / total),
            .init(color: DS.bg.opacity(DS.ParaTiB.coverBaseVeil), location: 1),
        ], startPoint: .top, endPoint: .bottom)
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
