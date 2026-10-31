import SwiftUI
import OrbitalCore

// «¿Qué vemos hoy?» · Encuentra tu match perfecto (docs/producto/inicio-benchmark/para-ti/B-interactivo.dc.html): el mazo
// de cartas que se arrastran (derecha guarda, izquierda descarta) y los ánimos como mosaicos con ícono.

/// Una carta: el póster grande y, encima, por qué te la propone, el nombre, año · duración · tipo y sus géneros; arriba a la
/// derecha su calificación de Trakt. Al arrastrarla (o al tocar un botón) asoma un sello: «MI LISTA» o «PASO».
struct MatchCard: View {
    let suggestion: Suggestion
    /// Los géneros ya en el idioma de la app (los pone la pantalla).
    var genres: [String] = []
    /// -1…1: cuánto se ha arrastrado a la izquierda o a la derecha (para el sello que asoma).
    var lean: Double = 0

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear.overlay { PosterView(url: suggestion.poster, title: suggestion.title, aspect: nil, bleed: true).scaledToFill() }
                .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            ArtVeil(at: DS.Match.veilFrom)   // más arriba que de costumbre: el porqué, el nombre, los datos y los géneros
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text(badgeKey(suggestion.reason)).recipe(.eyebrow, color: DS.eyebrow).lineLimit(1)
                Text(verbatim: suggestion.title).font(DS.TextRecipe.title.font.weight(.bold)).foregroundStyle(DS.paper).lineLimit(2)
                facts.recipe(.footnote, color: DS.onArtSecondary).lineLimit(1)
                if !genres.isEmpty {
                    HStack(spacing: DS.Space.s1) {
                        ForEach(genres.prefix(DS.Match.genres), id: \.self) { g in
                            Text(verbatim: g).recipe(.caption, color: DS.paper).fontWeight(.semibold).lineLimit(1)
                                .padding(.horizontal, DS.Space.s2).padding(.vertical, DS.Space.s1 / 2)
                                .background(DS.paper.opacity(DS.Match.chipFill), in: Capsule())
                        }
                    }
                }
            }
            .padding(DS.Space.s4)
            .onArt()
        }
        .overlay(alignment: .topTrailing) {
            if let rating = suggestion.traktRating, rating > 0 {
                HStack(spacing: DS.Space.s1) {
                    Image("rating-trakt").resizable().scaledToFit().frame(width: DS.Match.ratingLogo, height: DS.Match.ratingLogo)
                    Text(verbatim: "\(Int((rating * 10).rounded())) %").recipe(.footnote, color: DS.paper).fontWeight(.heavy)
                }
                .padding(.horizontal, DS.Space.s2).padding(.vertical, DS.Space.s1)
                .background(DS.badgeBackground, in: Capsule())
                .padding(DS.Space.s3)
                .accessibilityLabel(Text("Calificación en Trakt: \(Int((rating * 10).rounded())) por ciento"))
            }
        }
        .overlay(alignment: lean > 0 ? .topLeading : .topTrailing) {
            if abs(lean) > DS.Match.hintFrom {
                Text(lean > 0 ? "MI LISTA" : "PASO").font(DS.TextRecipe.section.font.weight(.black)).tracking(DS.Match.stampTracking)
                    .foregroundStyle(lean > 0 ? DS.brandMoon : DS.paper)
                    .padding(.horizontal, DS.Space.s3).padding(.vertical, DS.Space.s1)
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                        .strokeBorder(lean > 0 ? DS.brandMoon : DS.paper, lineWidth: DS.Match.stampLine))
                    .background(DS.scrim, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                    .rotationEffect(.degrees(lean > 0 ? -DS.Match.stampTilt : DS.Match.stampTilt))
                    .padding(DS.Space.s5)
                    .opacity(min(1, (abs(lean) - DS.Match.hintFrom) * DS.Match.hintRamp))
                    .accessibilityHidden(true)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous))
        .shadow(color: DS.scrimStrong, radius: DS.Space.s4, y: DS.Space.s2)
        .accessibilityElement(children: .combine)
    }

    /// «2024 · 2 h 28 min · Película» (lo que falte, no se dice).
    private var facts: Text {
        var parts: [Text] = []
        if let year = suggestion.year { parts.append(Text(verbatim: String(year))) }
        if let minutes = suggestion.runtime, minutes > 0 {
            let h = minutes / 60, m = minutes % 60
            parts.append(h == 0 ? Text("\(m) min") : m == 0 ? Text("\(h) h") : Text("\(h) h \(m) min"))
        }
        parts.append(suggestion.kind == "series" ? Text("Serie") : Text("Película"))
        return parts.dropFirst().reduce(parts[0]) { Text("\($0) · \($1)") }
    }
}

/// Lo que pide un botón del mazo: la carta de arriba sale volando igual que al arrastrarla.
enum MatchCommand: Equatable { case save, discard }

/// El mazo: la de arriba se arrastra (pasado el umbral sale volando y avisa); detrás asoman las dos que siguen, más chicas.
/// Los botones de abajo mandan `command` y la carta sale volando igual que al arrastrarla.
struct MatchDeck: View {
    let cards: [Suggestion]
    var genres: (Suggestion) -> [String] = { $0.genres }
    @Binding var command: MatchCommand?
    let onSave: (Suggestion) -> Void
    let onDiscard: (Suggestion) -> Void
    let onOpen: (Suggestion) -> Void
    @State private var drag: CGSize = .zero
    @State private var width: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Array(cards.prefix(3).enumerated().reversed()), id: \.element.imdb) { i, s in
                    let top = i == 0
                    MatchCard(suggestion: s, genres: genres(s), lean: top ? Double(drag.width / (geo.size.width / 2)) : 0)
                        // Un tamaño fijo dentro del mazo: el póster a sangre no la estira más allá de la pantalla.
                        .frame(width: geo.size.width, height: min(geo.size.height, geo.size.width * DS.Match.cardAspect))
                        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous))
                        .scaleEffect(top ? 1 : 1 - CGFloat(i) * DS.Match.behindShrink)
                        .offset(y: top ? 0 : CGFloat(i) * DS.Match.behindDrop)
                        .offset(top ? drag : .zero)
                        .rotationEffect(.degrees(top ? Double(drag.width) / DS.Match.tiltDivisor : 0))
                        .allowsHitTesting(top)
                        .gesture(top ? swipe(width: geo.size.width, s) : nil)
                        .onTapGesture { if top { onOpen(s) } }
                        .accessibilityAction(named: Text("Guardar en Mi lista")) { onSave(s) }
                        .accessibilityAction(named: Text("Paso")) { onDiscard(s) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: geo.size.width, initial: true) { _, w in width = w }
        }
        .animation(DS.Motion.spring(reduceMotion), value: cards.first?.imdb)
        .onChange(of: command) { _, asked in
            guard let asked, let s = cards.first else { command = nil; return }
            command = nil
            fly(right: asked == .save, s, width: width, from: .zero)
        }
    }

    private func swipe(width: CGFloat, _ s: Suggestion) -> some Gesture {
        DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { g in
                let far = abs(g.translation.width) > width * DS.Match.threshold || abs(g.predictedEndTranslation.width) > width
                guard far else { withAnimation(DS.Motion.spring(reduceMotion)) { drag = .zero }; return }
                fly(right: g.translation.width > 0, s, width: width, from: g.translation)
            }
    }

    /// La carta asoma su sello, sale volando de lado y entonces se guarda o se descarta.
    private func fly(right: Bool, _ s: Suggestion, width: CGFloat, from: CGSize) {
        Task { @MainActor in
            if from == .zero {   // desde un botón: primero se inclina y enseña el sello, como al arrastrar
                withAnimation(DS.Motion.base(reduceMotion)) { drag = CGSize(width: (right ? 1 : -1) * width * DS.Match.threshold, height: 0) }
                try? await Task.sleep(for: DS.Match.flyOut)
            }
            withAnimation(DS.Motion.base(reduceMotion)) { drag = CGSize(width: right ? width * 2 : -width * 2, height: from.height) }
            try? await Task.sleep(for: DS.Match.flyOut)
            drag = .zero
            if right { onSave(s) } else { onDiscard(s) }
        }
    }
}

