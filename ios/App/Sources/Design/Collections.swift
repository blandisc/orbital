import SwiftUI
import OrbitalCore

/// Una colección (Para ti › Listas): la tarjeta en abanico con su emblema al frente y, debajo, su nombre y su dato
/// («Óscar · Mejor película», «Para ver en pareja · 24 títulos»).
struct CollectionCard<Emblem: View>: View {
    let title: Text
    let detail: Text
    let name: String
    let posters: [String?]
    let tint: Color
    /// Con su nombre y dato debajo (Premios); sin ellos cuando el emblema ya lo dice (Estudios).
    var captioned = true
    @ViewBuilder var emblem: () -> Emblem

    var body: some View { bodyContent.pointerHover(.lift) }
    @ViewBuilder private var bodyContent: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            // Con nombre debajo (Premios) el reflejo es parte de la tarjeta; sin él (Estudios, Temporadas, Géneros) termina la fila
            // y lo pide la fila (`CenteredCarousel(reflected:)`), que también ajusta el aire con lo que sigue.
            if captioned { FanCard(name: name, posters: posters, tint: tint, emblem: emblem).reflected(weight: tint) }
            else { FanCard(name: name, posters: posters, tint: tint, emblem: emblem).rowReflection(weight: tint) }
            if captioned {
                VStack(alignment: .leading, spacing: 0) {
                    title.recipe(.cardTitle).lineLimit(1)
                    detail.recipe(.caption).lineLimit(1)
                }
                .padding(.horizontal, DS.Space.s1)
            }
        }
        .frame(width: DS.PlatformFan.width, alignment: .leading)
        // VoiceOver dice el nombre y la categoría («Óscar, Mejor película»), no el id interno del premio («palm»).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(captioned ? Text("\(title)\(Text(verbatim: ", "))\(detail)") : title)
    }
}

/// La estatuilla de un premio, recortada, con el halo de su color (el emblema de su colección).
struct AwardEmblem: View {
    let id: String
    var body: some View {
        Image("Awards/" + id).resizable().scaledToFit()
            .frame(height: DS.Collections.emblem)
            .shadow(color: DS.Collections.tint(id), radius: DS.Collections.glow)
            .accessibilityHidden(true)
    }
}

/// El sello de Trakt (el emblema de tus listas).
struct TraktEmblem: View {
    var body: some View {
        Image(systemName: "checkmark").font(DS.TextRecipe.section.font.weight(.heavy)).foregroundStyle(DS.paper)
            .frame(width: DS.PlatformFan.logo, height: DS.PlatformFan.logo)
            .background(DS.RatingBrand.trakt, in: Circle())
            .shadow(color: DS.RatingBrand.trakt, radius: DS.PlatformFan.glow)
            .accessibilityHidden(true)
    }
}

/// Un premio en Colecciones: su estatuilla al frente, sobre sus tres ganadores más recientes, y su nombre debajo.
struct AwardCard: View {
    let award: AwardCollection

    var body: some View { bodyContent.pointerHover(.lift) }
    @ViewBuilder private var bodyContent: some View {
        CollectionCard(title: AwardNames.title(award.id), detail: AwardNames.category(award.id), name: award.id,
                       posters: award.suggestions.prefix(3).map { Optional($0.poster) }, tint: DS.Collections.tint(award.id)) {
            AwardEmblem(id: award.id)
        }
    }
}

/// Cómo se llama cada premio y qué categoría es la colección.
enum AwardNames {
    static func title(_ id: String) -> Text {
        switch id {
        case "oscar": Text("Óscar"); case "emmy": Text("Emmy"); case "globe": Text("Globos de Oro"); case "palm": Text("Cannes")
        case "bafta": Text(verbatim: "BAFTA"); case "ariel": Text("Ariel"); default: Text(verbatim: id)
        }
    }

    static func category(_ id: String) -> Text {
        switch id {
        case "emmy": Text("Mejor serie de drama"); case "globe": Text("Mejor película dramática"); case "palm": Text("Palma de Oro")
        case "ariel": Text("Cine mexicano"); default: Text("Mejor película")
        }
    }
}

/// De dónde viene una lista: su sello junto al título (Trakt, uno de tus complementos, Rotten Tomatoes o tu Orbital).
enum ListSource: Hashable {
    case trakt, addon, critics, orbital
    /// Cómo dice la consola que una lista viene de Rotten Tomatoes (vía MDBList).
    static let criticsOrigin = "Rotten Tomatoes"
    /// El nombre del servicio tal cual; «Complemento», en el idioma de la app.
    var name: Text {
        switch self {
        case .trakt: Text(verbatim: "Trakt"); case .addon: Text("Complemento"); case .critics: Text(verbatim: "Rotten Tomatoes"); case .orbital: Text(verbatim: "Orbital")
        }
    }
    /// Rotten Tomatoes y Trakt se dicen con su ícono, no con su nombre: caben junto a cualquier título (Fernando, 30 oct
    /// 2026: el cuadro rojo «TRAKT» se leía como un botón).
    var icon: String? {
        switch self { case .critics: "rating-rotten-tomatoes"; case .trakt: "rating-trakt"; default: nil }
    }
    var isIcon: Bool { icon != nil }
    var color: Color {
        switch self {
        case .trakt: DS.RatingBrand.trakt; case .addon: DS.Collections.addon; case .critics: DS.Collections.critics; case .orbital: DS.Collections.orbital
        }
    }
}

/// El sello de origen: el nombre del servicio en mayúsculas sobre su color. Rotten Tomatoes y Trakt, con su ícono (como los
/// logos de calificación).
struct SourceBadge: View {
    let source: ListSource
    var body: some View {
        if let icon = source.icon {
            // El jitomate o el círculo de Trakt, a la altura de las mayúsculas del título (`DS.Size.markSmall`, como la marca de Orbital).
            Image(icon).resizable().scaledToFit().frame(height: DS.Size.markSmall)
                .accessibilityLabel(Text("De \(source.name)"))
        } else { label }
    }

    private var label: some View {
        source.name.textCase(.uppercase)
            .font(DS.TextRecipe.caption.font.weight(.bold)).tracking(DS.Collections.badgeRadius / 10)   // negrita, como `.source-badge` de la TV
            .foregroundStyle(DS.paper)
            .padding(.horizontal, DS.Space.s1 + DS.Size.hairline).padding(.vertical, DS.Size.hairline)
            .lineLimit(1).fixedSize()   // un sello no se parte en dos renglones («COMPLE / MENTO»)
            .background(source.color, in: RoundedRectangle(cornerRadius: DS.Collections.badgeRadius, style: .continuous))
            .accessibilityLabel(Text("De \(source.name)"))
    }
}

/// Un título de lo que viste, para elegir «Porque vi…».
struct BecauseSeed: Identifiable, Equatable {
    let id: String
    let title: String
    let poster: String?
    /// Qué es y de qué año: «Serie · 2005».
    var detail: String = ""
}

/// Las relacionadas del título de arriba: ya están, vienen en camino (el mazo ya cambió) o Trakt no tiene ninguna.
enum BecauseRelated: Equatable { case ready, loading, none }

/// «Porque viste X, te recomendamos»: el mazo de cartas de lo último que viste (la de arriba es el título elegido; se
/// avienta a un lado o con ‹ › para pasar al siguiente) y abajo lo que Trakt relaciona con él. Sin elegir, cambia solo cada día.
struct BecauseCard<Related: View>: View {
    let seeds: [BecauseSeed]
    let selected: String
    var state: BecauseRelated = .ready
    var choose: (String) -> Void = { _ in }
    /// La versión de Inicio: de fondo, el póster del título de arriba desenfocado (la tarjeta toma su color) y todo encima
    /// como en la sala oscura. Sin ella, la superficie de siempre (Para ti).
    var artBackdrop = false
    @ViewBuilder var related: () -> Related
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var index: Int { seeds.firstIndex { $0.id == selected } ?? 0 }
    private var current: BecauseSeed? { seeds.indices.contains(index) ? seeds[index] : seeds.first }

    var body: some View { bodyContent.pointerHover(.lift) }
    @ViewBuilder private var bodyContent: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            deckHeader
            // Siempre del mismo alto: mientras llegan, unos pósters vacíos en su lugar (la tarjeta no brinca ni parece trabada).
            Group {
                switch state {
                case .ready:
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: DS.Space.s2) { related() }
                            .environment(\.posterCaptions, false)
                    }
                case .loading:
                    HStack(spacing: DS.Space.s2) {
                        ForEach(0..<DS.Collections.relatedPlaceholders, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.fill)
                                .frame(width: DS.Collections.relatedPoster, height: DS.Collections.relatedPoster / DS.Poster.aspect)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
                    .accessibilityElement().accessibilityLabel(Text("Buscando recomendaciones"))
                case .none:
                    Text("Trakt aún no relaciona nada con este título. Prueba con otro.").recipe(.footnote)
                        .frame(maxWidth: .infinity, minHeight: DS.Collections.relatedPoster / DS.Poster.aspect, alignment: .leading)
                }
            }
            .id(selected)   // otro título: las relacionadas entran desde el principio
            .transition(.opacity)
        }
        .padding(DS.Space.s3)
        .modifier(BecauseBackdrop(poster: artBackdrop ? current?.poster : nil))
        .animation(reduceMotion ? nil : .snappy(duration: DS.Collections.deckSettle), value: selected)
        .sensoryFeedback(.selection, trigger: selected)
    }

    // MARK: mazo
    private var deckHeader: some View {
        HStack(alignment: .center, spacing: DS.Space.s4) {
            BecauseDeck(seeds: seeds, index: index) { step in
                guard !seeds.isEmpty else { return }
                choose(seeds[(index + step + seeds.count) % seeds.count].id)
            }
            // La columna mide siempre lo del mazo (el nombre tiene su lugar de dos renglones y las flechas van abajo): antes un
            // nombre largo la estiraba y la tarjeta, con todo lo de abajo, cambiaba de alto al pasar de un título a otro.
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                // «Porque viste · 3 de 8»: en qué carta vas, en el mismo renglón (junto a las flechas no cabía en un iPhone angosto).
                Text("\(Text("Porque viste"))\(seeds.count > 1 ? Text("\(Text(verbatim: " · "))\(Text("\(index + 1) de \(seeds.count)"))") : Text(verbatim: ""))")
                    .recipe(.secondary).monospacedDigit().lineLimit(1)
                Text(verbatim: current?.title ?? "").recipe(.title)
                    .lineLimit(2, reservesSpace: true).minimumScaleFactor(DS.Collections.becauseTitleScale).allowsTightening(true)
                    .contentTransition(.opacity)
                // Qué es y de qué año.
                Text(verbatim: current?.detail ?? "").recipe(.footnote).lineLimit(1)
                    .contentTransition(.opacity)
                Spacer(minLength: DS.Space.s2)
                if seeds.count > 1 {
                    HStack(spacing: DS.Space.s2) {
                        Button { choose(seeds[(index - 1 + seeds.count) % seeds.count].id) } label: { Image(systemName: "chevron.left").font(.system(size: DS.Collections.deckNavGlyph, weight: .semibold)).frame(width: DS.Collections.deckNav, height: DS.Collections.deckNav) }   // ds-exception: la flecha se mide con su círculo, no con Dynamic Type
                            .accessibilityLabel(Text("Anterior"))
                        Button { choose(seeds[(index + 1) % seeds.count].id) } label: { Image(systemName: "chevron.right").font(.system(size: DS.Collections.deckNavGlyph, weight: .semibold)).frame(width: DS.Collections.deckNav, height: DS.Collections.deckNav) }   // ds-exception: la flecha se mide con su círculo, no con Dynamic Type
                            .accessibilityLabel(Text("Siguiente"))
                    }
                    .buttonStyle(.glass).buttonBorderShape(.circle)
                }
            }
            .frame(minHeight: DS.Collections.deckHeight, alignment: .topLeading)
            Spacer(minLength: 0)
        }
    }
}

/// El fondo de `BecauseCard`: la superficie de siempre o, en Inicio, el póster del título de arriba desenfocado con un velo
/// (y lo de encima como en la sala oscura, que se lee sobre cualquier arte).
private struct BecauseBackdrop: ViewModifier {
    let poster: String?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
        if let poster {
            content.onArt()
                .background {
                    ZStack {
                        DS.scrimStrong
                        PosterView(url: poster, title: "", aspect: nil, bleed: true)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .scaleEffect(DS.Collections.becauseArtScale)   // sin orillas claras por el desenfoque
                            .blur(radius: DS.Collections.becauseBlur)
                            .opacity(DS.Collections.becauseArtOpacity)
                            .id(poster)
                            .transition(.opacity)
                        // Un velo parejo (arriba van «Porque viste · 3 de 8» y el nombre) y más firme abajo, donde van los pósters.
                        ArtVeil(kind: .full)
                    }
                    .clipShape(shape)
                    .accessibilityHidden(true)
                }
        } else {
            content.background(DS.surface, in: shape)
        }
    }
}

/// El mazo de «Porque viste»: la carta de arriba es el título elegido y debajo se asoman los siguientes. Arrastrarla a un
/// lado (o tocarla) la avienta y queda la siguiente.
struct BecauseDeck: View {
    let seeds: [BecauseSeed]
    let index: Int
    let step: (Int) -> Void
    @State private var drag: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let count = min(DS.Collections.deckDepth, seeds.count)
        let shown = (0..<count).map { seeds[(index + $0) % max(1, seeds.count)] }
        ZStack {
            ForEach(Array(shown.enumerated()).reversed(), id: \.element.id) { depth, seed in
                let top = depth == 0
                PosterView(url: seed.poster, title: seed.title)
                    .frame(width: DS.Collections.deckPoster)
                    .shadow(DS.Elevation.medium)
                    .scaleEffect(1 - CGFloat(depth) * DS.Collections.deckShrink)
                    .rotationEffect(.degrees(Double(depth) * DS.Collections.deckTurn + (top ? Double(drag) / Double(DS.Collections.deckThrow) * DS.Collections.deckTurn * 2 : 0)))
                    .offset(x: CGFloat(depth) * DS.Collections.deckShift + (top ? drag : 0), y: CGFloat(depth) * DS.Collections.deckShift)
                    .transition(.asymmetric(insertion: .opacity, removal: .opacity))
            }
        }
        .frame(width: DS.Collections.deckPoster + DS.Collections.deckShift * CGFloat(DS.Collections.deckDepth), alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: DS.Space.s2)
            .onChanged { drag = $0.translation.width }
            .onEnded { value in
                // Se avienta si pasó el umbral o si el dedo iba rápido (como en una pila de cartas real).
                let thrown = abs(value.translation.width) > DS.Collections.deckThrow || abs(value.predictedEndTranslation.width) > DS.Collections.deckThrow * 3
                if thrown { fly(value.translation.width < 0 ? -1 : 1) }
                else { withAnimation(reduceMotion ? nil : .snappy(duration: DS.Collections.deckSettle)) { drag = 0 } }
            })
        .onTapGesture { fly(-1) }
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: seeds.indices.contains(index) ? seeds[index].title : ""))
        .accessibilityHint(Text("Desliza hacia arriba o abajo para cambiar el título"))
        .accessibilityAdjustableAction { direction in step(direction == .increment ? 1 : -1) }
        .accessibilityIdentifier("because-deck")
    }

    /// La carta de arriba sale volando hacia ese lado y las de abajo suben (−1: a la izquierda, pasa a la siguiente).
    private func fly(_ direction: CGFloat) {
        guard !reduceMotion else { step(direction < 0 ? 1 : -1); return }
        withAnimation(.easeIn(duration: DS.Collections.deckFly)) { drag = direction * DS.Collections.deckFlyDistance }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(DS.Collections.deckFly))
            withAnimation(.snappy(duration: DS.Collections.deckSettle)) {
                drag = 0
                step(direction < 0 ? 1 : -1)
            }
        }
    }
}

/// Un año en «Por año»: cuatro pósters de ese año en mosaico y el número grande encima.
struct YearCard: View {
    let year: Int
    let posters: [String]

    var body: some View { bodyContent.pointerHover(.lift) }
    @ViewBuilder private var bodyContent: some View {
        ZStack(alignment: .bottomLeading) {
            let half = DS.Collections.yearWidth / 2
            LazyVGrid(columns: [GridItem(.fixed(half), spacing: 0), GridItem(.fixed(half), spacing: 0)], spacing: 0) {
                ForEach(0..<4, id: \.self) { i in
                    PosterView(url: i < posters.count ? posters[i] : nil, title: String(year), aspect: nil, bleed: true, maxPoints: DS.Image.card)
                        .frame(width: half, height: DS.Collections.yearHeight / 2)
                }
            }
            ArtVeil()
            Text(verbatim: String(year))
                .font(DS.TextRecipe.display.font).fontWeight(.heavy).fontDesign(.rounded).monospacedDigit()
                .foregroundStyle(DS.paper)
                .padding(.horizontal, DS.Space.s3).padding(.bottom, DS.Space.s1)
        }
        .frame(width: DS.Collections.yearWidth, height: DS.Collections.yearHeight)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: String(year)))
    }
}
