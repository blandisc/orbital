import SwiftUI
import OrbitalCore

// «Una por una» de «Decide por mí» (docs/producto/inicio-benchmark/para-ti/B-interactivo.dc.html): el mazo de cartas que
// se arrastran (derecha guarda, izquierda descarta, arriba «Para hoy») y, debajo, los datos de la de arriba.

/// Una carta: solo el arte, a sangre y del tamaño del póster (sin franjas a los lados), con las esquinas y la sombra de la
/// carta. Los datos van fuera, debajo (`MatchCardInfo`): nunca encima del arte (pulido de DE2, 13 nov 2026). Al
/// arrastrarla (o al tocar un botón) se tiñe y asoma un sello con su símbolo, como Tinder: «Paso» en rojo (izquierda),
/// «Guardar» en verde (derecha) y «Para hoy» en azul (arriba). El sello crece con el avance (de `DS.MatchLive.stampFrom` a su
/// tamaño): se siente que lo estás empujando. En letra normal, sin mayúsculas sostenidas.
struct MatchCard: View {
    @Environment(\.titleName) var titleName
    let suggestion: Suggestion
    /// -1…1: cuánto se ha arrastrado a la izquierda o a la derecha.
    var lean: Double = 0
    /// 0…1: cuánto se ha arrastrado hacia arriba («Para hoy»).
    var rise: Double = 0

    /// Hacia dónde va y cuánto (lo que más se haya arrastrado manda).
    private var pull: (color: Color, label: LocalizedStringKey, symbol: String, amount: Double, alignment: Alignment, tilt: Double)? {
        if rise > abs(lean), rise > DS.Match.hintFrom { return (DS.Match.tonight, "Para hoy", DS.Symbol.matchTonight, rise, .bottom, 0) }
        guard abs(lean) > DS.Match.hintFrom else { return nil }
        return lean > 0 ? (DS.Match.keep, "Guardar", DS.Symbol.matchKeep, abs(lean), .topLeading, -DS.Match.stampTilt)
                        : (DS.Match.pass, "Paso", DS.Symbol.matchPass, abs(lean), .topTrailing, DS.Match.stampTilt)
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
                    let shown = min(1, (pull.amount - DS.Match.hintFrom) * DS.Match.hintRamp)
                    Label { Text(pull.label) } icon: { Image(systemName: pull.symbol) }
                        .font(DS.TextRecipe.section.font)
                        .foregroundStyle(pull.color)
                        .padding(.horizontal, DS.Space.s3).padding(.vertical, DS.Space.s1)
                        .overlay(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous).strokeBorder(pull.color, lineWidth: DS.Match.stampLine))
                        .background(DS.scrim, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                        .scaleEffect(DS.MatchLive.stampFrom + (1 - DS.MatchLive.stampFrom) * shown)
                        .rotationEffect(.degrees(pull.tilt))
                        .padding(pull.alignment == .bottom ? DS.Space.s8 : DS.Space.s5)
                        .opacity(shown)
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

/// El mazo: la de arriba se arrastra y gira un poco; asoma el sello de su lado, creciendo con el avance, y los botones de
/// abajo se encienden de ese color (`pull`). Al cruzar el umbral el teléfono da un toque; soltada después, sale volando con la
/// velocidad del dedo y la de atrás sube a su lugar (las de atrás ya van subiendo mientras arrastras). Soltada antes, regresa
/// sin rebote. Debajo, los datos de la de arriba (`MatchCardInfo`), alineados a su orilla. Los botones de afuera mandan
/// `command` y la carta sale volando igual que al arrastrarla. Con «Reducir movimiento» la carta se funde en su lugar.
struct MatchDeck: View {
    let cards: [Suggestion]
    var genres: (Suggestion) -> [String] = { $0.genres }
    @Binding var command: MatchCommand?
    /// Hacia dónde va la de arriba y cuánto: lo leen los botones de abajo para encenderse.
    var pull: MatchPull?
    let onSave: (Suggestion) -> Void
    let onDiscard: (Suggestion) -> Void
    /// Hacia arriba o la ★: «Para hoy».
    var onTonight: (Suggestion) -> Void = { _ in }
    let onOpen: (Suggestion) -> Void
    @State private var drag: CGSize = .zero
    /// De qué carta es `drag`: la que salió volando se queda fuera hasta que el mazo la quita, y la que sube a su lugar no
    /// hereda su desplazamiento (antes regresaba al centro un instante antes de irse).
    @State private var dragID: String?
    private var liveDrag: CGSize { cards.first?.imdb == dragID ? drag : .zero }
    @State private var width: CGFloat = 0
    @State private var height: CGFloat = 0
    /// Ya pasó el umbral: soltarla la manda (el toque en la mano avisa al cruzarlo).
    @State private var armed = false
    /// «Reducir movimiento»: la carta que sale se funde en su lugar en vez de volar.
    @State private var fading = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Cuántas asoman detrás.
    private let behind = 2

    var body: some View {
        // Las cartas y sus datos los acomoda `MatchDeckLayout` en una sola pasada: los datos apartan su alto primero y la
        // carta toma lo que sobra (antes la orilla de los datos se guardaba en un estado al medir la carta, y cada cambio
        // volvía a medir todo: con el encabezado de la hoja, la app se colgaba al abrir «Una por una»; 13 nov 2026).
        MatchDeckLayout(behind: behind, gap: DS.Space.s3, infoFullWidth: typeSize.isAccessibilitySize) {
            GeometryReader { geo in
                let fit = MatchDeckLayout.fitted(geo.size, behind: behind)
                ZStack(alignment: .top) {
                    ForEach(Array(cards.prefix(behind + 1).enumerated().reversed()), id: \.element.imdb) { i, s in
                        card(s, at: i, fit: fit, in: geo.size)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .onChange(of: geo.size, initial: true) { _, size in width = size.width; height = size.height }
            }
            if let first = cards.first {
                // A la orilla de la carta; con letra de accesibilidad, de margen a margen (no se corta en «En Par…»).
                MatchCardInfo(suggestion: first, genres: genres(first))
                    .id(first.imdb)
                    .transition(.opacity)
            }
        }
        .animation(DS.Motion.snap(reduceMotion), value: cards.first?.imdb)
        .onChange(of: cards.first?.imdb) { dragID = nil; drag = .zero; fading = false }   // «Deshacer» la regresa a su lugar
        .dsFeedback(.impact(weight: .medium), trigger: armed) { was, now in !was && now }
        #if DEBUG
        // Capturas a medio arrastre: la de arriba se queda inclinada hacia «Guardar» con su sello y el botón encendido.
        .task(id: width) {
            guard Demo.isOn, Demo.has("-demo-deck-pull"), width > 0, let s = cards.first else { return }
            try? await Task.sleep(for: .seconds(1))   // ds-exception: guion de capturas, solo en DEBUG (Demo)
            dragID = s.imdb; drag = CGSize(width: width * DS.Match.threshold * 0.85, height: 0)   // ds-exception: Demo, a medio camino del umbral
            let p = progress(drag); pull?.set(p.toward, p.amount)
        }
        #endif
        .onChange(of: command) { _, asked in
            guard let asked, let s = cards.first else { command = nil; return }
            command = nil
            fly(asked == .tonight ? .up : asked == .save ? .right : .left, s, from: .zero, velocity: .zero)
        }
    }

    /// Cuánto se ha arrastrado la de arriba hacia su lado más fuerte, en partes del umbral (1: ya sale).
    private func progress(_ t: CGSize) -> (toward: MatchCommand?, amount: Double) {
        let up = Double(max(0, -t.height) / max(1, height * DS.Match.threshold))
        let side = Double(abs(t.width) / max(1, width * DS.Match.threshold))
        if up > side { return (.tonight, up) }
        return side > 0 ? (t.width > 0 ? .save : .discard, side) : (nil, 0)
    }

    /// Una carta del mazo: la de arriba se arrastra; las de atrás, más chicas desde su orilla de abajo, asoman `behindPeek`
    /// cada una y van subiendo a su lugar mientras arrastras la de arriba. Aparte del cuerpo: el compilador de la CI (Xcode
    /// 26.3) no alcanzaba a revisarlo todo junto.
    private func card(_ s: Suggestion, at i: Int, fit: CGSize, in size: CGSize) -> some View {
        let top = i == 0
        let moved = liveDrag
        let lean: Double = top ? Double(moved.width / max(1, size.width / 2)) : 0
        let rise: Double = top ? Double(max(0, -moved.height) / max(1, size.height / 2)) : 0
        let depth: CGFloat = top ? 0 : CGFloat(i) - CGFloat(min(1, progress(moved).amount))
        return MatchCard(suggestion: s, lean: lean, rise: rise)
            .frame(width: fit.width, height: fit.height)
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous))
            .scaleEffect(1 - depth * DS.Match.behindShrink, anchor: .bottom)
            .offset(y: depth * DS.Match.behindPeek)
            .offset(top ? moved : .zero)
            .rotationEffect(.degrees(top ? Double(moved.width) / DS.Match.tiltDivisor : 0))
            .opacity(top && fading && s.imdb == dragID ? 0 : 1)
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
            .onChanged { g in
                if dragID != s.imdb { dragID = s.imdb }
                drag = g.translation
                let p = progress(g.translation)
                pull?.set(p.toward, p.amount)
                if (p.amount >= 1) != armed { armed = p.amount >= 1 }
            }
            .onEnded { g in
                let t = g.translation, p = g.predictedEndTranslation
                armed = false
                // Hacia arriba manda si es más vertical que de lado (como el Súper de Tinder).
                if -t.height > abs(t.width), -t.height > height * DS.Match.threshold || -p.height > height {
                    fly(.up, s, from: t, velocity: g.velocity); return
                }
                let far = abs(t.width) > width * DS.Match.threshold || abs(p.width) > width
                guard far else {   // regresa sin rebote
                    withAnimation(DS.Motion.snap(reduceMotion)) { drag = .zero; pull?.set(nil, 0) }
                    return
                }
                fly(t.width > 0 ? .right : .left, s, from: t, velocity: g.velocity)
            }
    }

    /// Lo que tarda en salir: lo que le falta entre la velocidad del dedo (al doble, porque frena al final), sin bajar de
    /// `throwMin` ni pasar de `throwMax`. Desde un botón (sin velocidad), lo más.
    private func throwTime(from: CGSize, to: CGSize, velocity: CGSize) -> Double {
        let speed = Double(hypot(velocity.width, velocity.height))
        guard speed > 1 else { return DS.MatchLive.throwMax }
        let distance = Double(hypot(to.width - from.width, to.height - from.height))
        return min(DS.MatchLive.throwMax, max(DS.MatchLive.throwMin, 2 * distance / speed))
    }

    /// Hacia dónde sale: fuera de la pantalla por su lado, siguiendo la línea del dedo.
    private func away(_ direction: Direction, from start: CGSize, velocity: CGSize) -> CGSize {
        let drift = DS.MatchLive.throwMax / 2
        switch direction {
        case .left: return CGSize(width: -width * 2, height: start.height + velocity.height * drift)
        case .right: return CGSize(width: width * 2, height: start.height + velocity.height * drift)
        case .up: return CGSize(width: start.width + velocity.width * drift, height: -height * 2)
        }
    }

    /// La carta asoma su sello, sale volando hacia donde iba (con la velocidad del dedo) y entonces se guarda, se descarta o
    /// queda «Para hoy». Con «Reducir movimiento» se funde en su lugar.
    private func fly(_ direction: Direction, _ s: Suggestion, from: CGSize, velocity: CGSize) {
        let toward: MatchCommand = switch direction { case .left: .discard; case .right: .save; case .up: .tonight }
        dragID = s.imdb
        Task { @MainActor in
            if reduceMotion {
                pull?.set(toward, 1)
                withAnimation(DS.Motion.fade) { fading = true }
                try? await Task.sleep(for: DS.Match.flyOut)
            } else {
                if from == .zero {   // desde un botón: primero se inclina y enseña el sello, como al arrastrar
                    let hint: CGSize = switch direction {
                    case .left: CGSize(width: -width * DS.Match.threshold, height: 0)
                    case .right: CGSize(width: width * DS.Match.threshold, height: 0)
                    case .up: CGSize(width: 0, height: -height * DS.Match.threshold)
                    }
                    withAnimation(DS.Motion.base(reduceMotion)) { drag = hint; pull?.set(toward, 1) }
                    try? await Task.sleep(for: DS.Match.flyOut)
                }
                let start = from == .zero ? drag : from
                let target = away(direction, from: start, velocity: velocity)
                let time = throwTime(from: start, to: target, velocity: velocity)
                withAnimation(DS.Motion.fling(reduceMotion, duration: time)) { drag = target }
                try? await Task.sleep(for: .seconds(time))
            }
            pull?.set(nil, 0)   // la carta se queda fuera (o fundida) hasta que el mazo la quita
            switch direction { case .right: onSave(s); case .left: onDiscard(s); case .up: onTonight(s) }
        }
    }
}

/// El lugar del mazo: primero los datos de la carta (`MatchCardInfo`, de alto fijo: cada renglón aparta su lugar) y la carta
/// en lo que sobra, del tamaño de su póster; los datos empiezan en la orilla de la carta. Todo en una pasada, sin estados que
/// se persigan.
struct MatchDeckLayout: Layout {
    let behind: Int
    let gap: CGFloat
    /// Los datos de margen a margen (letra de accesibilidad), no a la orilla de la carta.
    var infoFullWidth = false

    /// La carta llena su arte: mide lo que el póster (ancho entre alto `DS.Poster.aspect`), cabe en el lugar con lo que
    /// asoman las de atrás y no pasa de `DS.Match.cardMax` (iPad y Mac).
    static func fitted(_ area: CGSize, behind: Int) -> CGSize {
        let room = max(0, area.height - DS.Match.behindPeek * CGFloat(behind))
        let w = max(0, min(area.width, room * DS.Poster.aspect, DS.Match.cardMax))
        return CGSize(width: w, height: w / DS.Poster.aspect)
    }

    private func infoHeight(_ subviews: Subviews, width: CGFloat) -> CGFloat {
        subviews.count > 1 ? subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil)).height + gap : 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? DS.Match.cardMax
        let info = infoHeight(subviews, width: width)
        return CGSize(width: width, height: proposal.height ?? (DS.Match.cardMax / DS.Poster.aspect + info))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let deck = subviews.first else { return }
        let info = infoHeight(subviews, width: bounds.width)
        let room = max(0, bounds.height - info)
        deck.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: room))
        guard subviews.count > 1 else { return }
        let inset = infoFullWidth ? 0 : max(0, (bounds.width - Self.fitted(CGSize(width: bounds.width, height: room), behind: behind).width) / 2)
        subviews[1].place(at: CGPoint(x: bounds.minX + inset, y: bounds.minY + room + gap),
                          proposal: ProposedViewSize(width: bounds.width - inset * 2, height: nil))
    }
}
