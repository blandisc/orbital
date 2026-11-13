import SwiftUI
import OrbitalCore

// «Una por una» de «Decide por mí» (docs/producto/inicio-benchmark/para-ti/B-interactivo.dc.html): el mazo de cartas que
// se arrastran (derecha guarda, izquierda descarta, arriba «Para hoy») y, debajo, los datos de la de arriba.

/// Una carta: solo el arte, a sangre y del tamaño del póster (sin franjas a los lados), con las esquinas y la sombra de la
/// carta. Los datos van fuera, debajo (`MatchCardInfo`): nunca encima del arte (pulido de DE2, 13 nov 2026). Al
/// arrastrarla (o al tocar un botón) se tiñe y asoma un sello, como Tinder: «PASO» en rojo (izquierda), «GUARDAR» en verde
/// (derecha) y «PARA HOY» en azul (arriba).
struct MatchCard: View {
    @Environment(\.titleName) var titleName
    let suggestion: Suggestion
    /// -1…1: cuánto se ha arrastrado a la izquierda o a la derecha.
    var lean: Double = 0
    /// 0…1: cuánto se ha arrastrado hacia arriba («Para hoy»).
    var rise: Double = 0

    /// Hacia dónde va y cuánto (lo que más se haya arrastrado manda).
    private var pull: (color: Color, label: LocalizedStringKey, amount: Double, alignment: Alignment, tilt: Double)? {
        if rise > abs(lean), rise > DS.Match.hintFrom { return (DS.Match.tonight, "Para hoy", rise, .bottom, 0) }
        guard abs(lean) > DS.Match.hintFrom else { return nil }
        return lean > 0 ? (DS.Match.keep, "Guardar", abs(lean), .topLeading, -DS.Match.stampTilt) : (DS.Match.pass, "Paso", abs(lean), .topTrailing, DS.Match.stampTilt)
    }

    var body: some View {
        let name = titleName(suggestion.title, id: suggestion.imdb, kind: suggestion.kind)
        Color.clear.overlay { PosterView(url: suggestion.poster, title: name, aspect: nil, bleed: true).scaledToFill() }
            .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            // El color de lo que va a pasar, desde la orilla hacia donde la llevas.
            .overlay {
                if let pull {
                    LinearGradient(colors: [pull.color.opacity(DS.Match.tintMax * min(1, pull.amount * DS.Match.hintRamp)), .clear],
                                   startPoint: pull.alignment == .bottom ? .top : (lean > 0 ? .trailing : .leading),
                                   endPoint: .center)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: pull?.alignment ?? .center) {
                if let pull {
                    Text(pull.label).dsCaps().font(DS.TextRecipe.section.font).tracking(DS.Match.stampTracking)
                        .foregroundStyle(pull.color)
                        .padding(.horizontal, DS.Space.s3).padding(.vertical, DS.Space.s1)
                        .overlay(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous).strokeBorder(pull.color, lineWidth: DS.Match.stampLine))
                        .background(DS.scrim, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                        .rotationEffect(.degrees(pull.tilt))
                        .padding(pull.alignment == .bottom ? DS.Space.s8 : DS.Space.s5)
                        .opacity(min(1, (pull.amount - DS.Match.hintFrom) * DS.Match.hintRamp))
                        .accessibilityHidden(true)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous))
            .shadow(DS.Elevation.floating)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: name))
    }
}

/// Los datos de la carta de arriba, debajo de ella y alineados a su orilla: el porqué en turquesa («En Apple TV+») con su
/// calificación de Trakt a la derecha, el nombre y una sola línea «2026 · Película · Acción, Aventura, Comedia» (los géneros
/// en texto, no en cápsulas). Cada renglón aparta su lugar: al pasar de carta el texto se funde y nada brinca.
struct MatchCardInfo: View {
    @Environment(\.titleName) var titleName
    @Environment(\.dynamicTypeSize) private var typeSize
    let suggestion: Suggestion
    /// Los géneros ya en el idioma de la app (los pone la pantalla).
    var genres: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                Eyebrow(text: Text(badgeKey(suggestion.reason)), reason: true)
                Spacer(minLength: DS.Space.s2)
                if let rating = TraktRatings.shown(suggestion.imdb, fallback: suggestion.traktRating), rating > 0 {
                    HStack(spacing: DS.Space.s1) {
                        Image("rating-trakt").resizable().scaledToFit().frame(width: DS.Match.ratingLogo, height: DS.Match.ratingLogo)
                        Text(verbatim: "\(TraktRatings.percent(rating))\u{00A0}%").recipe(.label, color: DS.text)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Calificación en Trakt: \(Int((rating * 10).rounded())) por ciento"))
                }
            }
            Text(verbatim: titleName(suggestion.title, id: suggestion.imdb, kind: suggestion.kind)).recipe(.cardTitle).lineLimit(typeSize.isAccessibilitySize ? 2 : 1, reservesSpace: true)
            facts.recipe(.footnote, color: DS.textMuted).lineLimit(1, reservesSpace: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("match-info")
    }

    /// «2026 · Película · Acción, Aventura, Comedia» (lo que falte, no se dice).
    private var facts: Text {
        var parts: [Text] = []
        if let year = suggestion.year { parts.append(Text(verbatim: String(year))) }
        parts.append(suggestion.kind == "series" ? Text("Serie") : Text("Película"))
        let shown = genres.prefix(DS.Match.genres)
        if !shown.isEmpty { parts.append(Text(verbatim: shown.joined(separator: ", "))) }
        return parts.dropFirst().reduce(parts[0]) { Text("\($0) · \($1)") }
    }
}

/// Lo que pide un botón del mazo: la carta de arriba sale volando igual que al arrastrarla.
enum MatchCommand: Equatable { case save, discard, tonight }

/// El mazo: la de arriba se arrastra (pasado el umbral sale volando y avisa; soltada antes, regresa a su lugar sin rebote);
/// detrás asoman por abajo las dos que siguen, un poco más chicas. Debajo, los datos de la de arriba (`MatchCardInfo`),
/// alineados a su orilla. Los botones de afuera mandan `command` y la carta sale volando igual que al arrastrarla.
struct MatchDeck: View {
    let cards: [Suggestion]
    var genres: (Suggestion) -> [String] = { $0.genres }
    @Binding var command: MatchCommand?
    let onSave: (Suggestion) -> Void
    let onDiscard: (Suggestion) -> Void
    /// Hacia arriba o la ★: «Para hoy».
    var onTonight: (Suggestion) -> Void = { _ in }
    let onOpen: (Suggestion) -> Void
    /// El alto del lugar de las cartas cuando el mazo va dentro de algo que se desliza (letra de accesibilidad); nil: el que haya.
    var cardsHeight: CGFloat?
    @State private var drag: CGSize = .zero
    @State private var width: CGFloat = 0
    @State private var height: CGFloat = 0
    /// Cuánto queda a cada lado de la carta, para que sus datos empiecen en su orilla.
    @State private var cardInset: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Cuántas asoman detrás.
    private let behind = 2

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            GeometryReader { geo in
                let fit = fitted(geo.size)
                ZStack(alignment: .top) {
                    ForEach(Array(cards.prefix(behind + 1).enumerated().reversed()), id: \.element.imdb) { i, s in
                        card(s, at: i, fit: fit, in: geo.size)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .onChange(of: geo.size, initial: true) { _, size in width = size.width; height = size.height; cardInset = max(0, (size.width - fitted(size).width) / 2) }
            }
            .frame(height: cardsHeight)
            if let first = cards.first {
                MatchCardInfo(suggestion: first, genres: genres(first))
                    .id(first.imdb)
                    .transition(.opacity)
                    // A la orilla de la carta; con letra de accesibilidad, de margen a margen (no se corta en «En Par…»).
                    .padding(.horizontal, typeSize.isAccessibilitySize ? 0 : cardInset)
            }
        }
        .animation(DS.Motion.snap(reduceMotion), value: cards.first?.imdb)
        .onChange(of: command) { _, asked in
            guard let asked, let s = cards.first else { command = nil; return }
            command = nil
            fly(asked == .tonight ? .up : asked == .save ? .right : .left, s, from: .zero)
        }
    }

    /// La carta llena su arte: mide lo que el póster (ancho entre alto `DS.Poster.aspect`), cabe en el lugar con lo que
    /// asoman las de atrás y no pasa de `DS.Match.cardMax` (iPad y Mac).
    private func fitted(_ area: CGSize) -> CGSize {
        let room = max(0, area.height - DS.Match.behindPeek * CGFloat(behind))
        let w = max(0, min(area.width, room * DS.Poster.aspect, DS.Match.cardMax))
        return CGSize(width: w, height: w / DS.Poster.aspect)
    }

    /// Una carta del mazo: la de arriba se arrastra; las de atrás, más chicas desde su orilla de abajo, asoman `behindPeek`
    /// cada una. Aparte del cuerpo: el compilador de la CI (Xcode 26.3) no alcanzaba a revisarlo todo junto.
    private func card(_ s: Suggestion, at i: Int, fit: CGSize, in size: CGSize) -> some View {
        let top = i == 0
        let lean: Double = top ? Double(drag.width / max(1, size.width / 2)) : 0
        let rise: Double = top ? Double(max(0, -drag.height) / max(1, size.height / 2)) : 0
        let scale: CGFloat = 1 - CGFloat(i) * DS.Match.behindShrink
        return MatchCard(suggestion: s, lean: lean, rise: rise)
            .frame(width: fit.width, height: fit.height)
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous))
            .scaleEffect(scale, anchor: .bottom)
            .offset(y: CGFloat(i) * DS.Match.behindPeek)
            .offset(top ? drag : .zero)
            .rotationEffect(.degrees(top ? Double(drag.width) / DS.Match.tiltDivisor : 0))
            .allowsHitTesting(top)
            .gesture(top ? swipe(width: size.width, s) : nil)
            .onTapGesture { if top { onOpen(s) } }
            .accessibilityAction(named: Text("Guardar")) { onSave(s) }
            .accessibilityAction(named: Text("Paso")) { onDiscard(s) }
            .accessibilityAction(named: Text("Para hoy")) { onTonight(s) }
    }

    private enum Direction { case left, right, up }

    private func swipe(width: CGFloat, _ s: Suggestion) -> some Gesture {
        DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { g in
                let t = g.translation, p = g.predictedEndTranslation
                // Hacia arriba manda si es más vertical que de lado (como el Súper de Tinder).
                if -t.height > abs(t.width), -t.height > height * DS.Match.threshold || -p.height > height {
                    fly(.up, s, from: t); return
                }
                let far = abs(t.width) > width * DS.Match.threshold || abs(p.width) > width
                guard far else { withAnimation(DS.Motion.snap(reduceMotion)) { drag = .zero }; return }   // regresa sin rebote
                fly(t.width > 0 ? .right : .left, s, from: t)
            }
    }

    /// La carta asoma su sello, sale volando hacia donde iba y entonces se guarda, se descarta o queda «Para hoy».
    private func fly(_ direction: Direction, _ s: Suggestion, from: CGSize) {
        Task { @MainActor in
            if from == .zero {   // desde un botón: primero se inclina y enseña el sello, como al arrastrar
                let hint: CGSize = switch direction {
                case .left: CGSize(width: -width * DS.Match.threshold, height: 0)
                case .right: CGSize(width: width * DS.Match.threshold, height: 0)
                case .up: CGSize(width: 0, height: -height * DS.Match.threshold)
                }
                withAnimation(DS.Motion.base(reduceMotion)) { drag = hint }
                try? await Task.sleep(for: DS.Match.flyOut)
            }
            let away: CGSize = switch direction {
            case .left: CGSize(width: -width * 2, height: from.height)
            case .right: CGSize(width: width * 2, height: from.height)
            case .up: CGSize(width: from.width, height: -height * 2)
            }
            withAnimation(DS.Motion.base(reduceMotion)) { drag = away }
            try? await Task.sleep(for: DS.Match.flyOut)
            drag = .zero
            switch direction { case .right: onSave(s); case .left: onDiscard(s); case .up: onTonight(s) }
        }
    }
}

