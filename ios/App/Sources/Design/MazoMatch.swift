import SwiftUI
import OrbitalCore

// «¿Qué vemos hoy?» · Encuentra tu match perfecto (docs/producto/inicio-benchmark/para-ti/B-interactivo.dc.html): el mazo
// de cartas que se arrastran (derecha guarda, izquierda descarta) y los ánimos como mosaicos con ícono.

/// Una carta: el póster grande y, encima, por qué te la propone, el nombre, año · duración · tipo y sus géneros; arriba a la
/// derecha su calificación de Trakt y abajo a la derecha el ▶ de «Ver ya». Al arrastrarla (o al tocar un botón) se tiñe y
/// asoma un sello, como Tinder: «PASO» en rojo (izquierda), «GUARDAR» en verde (derecha) y «PARA HOY» en azul (arriba).
struct MatchCard: View {
    let suggestion: Suggestion
    /// Los géneros ya en el idioma de la app (los pone la pantalla).
    var genres: [String] = []
    /// -1…1: cuánto se ha arrastrado a la izquierda o a la derecha.
    var lean: Double = 0
    /// 0…1: cuánto se ha arrastrado hacia arriba («Para hoy»).
    var rise: Double = 0
    /// «Ver ya»: el ▶ de la carta (solo en la de arriba).
    var onPlay: (() -> Void)?

    /// Hacia dónde va y cuánto (lo que más se haya arrastrado manda).
    private var pull: (color: Color, label: LocalizedStringKey, amount: Double, alignment: Alignment, tilt: Double)? {
        if rise > abs(lean), rise > DS.Match.hintFrom { return (DS.Match.tonight, "★ Para hoy", rise, .bottom, 0) }
        guard abs(lean) > DS.Match.hintFrom else { return nil }
        return lean > 0 ? (DS.Match.keep, "Guardar", abs(lean), .topLeading, -DS.Match.stampTilt) : (DS.Match.pass, "Paso", abs(lean), .topTrailing, DS.Match.stampTilt)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear.overlay { PosterView(url: suggestion.poster, title: suggestion.title, aspect: nil, bleed: true).scaledToFill() }
                .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            ArtVeil(at: DS.Match.veilFrom)   // más arriba que de costumbre: el porqué, el nombre, los datos y los géneros
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text(badgeKey(suggestion.reason)).recipe(.eyebrow, color: DS.eyebrow).lineLimit(1)
                Text(verbatim: suggestion.title).font(DS.TextRecipe.title.font).foregroundStyle(DS.paper).lineLimit(2)
                facts.recipe(.footnote, color: DS.onArtSecondary).lineLimit(1)
                if !genres.isEmpty {
                    HStack(spacing: DS.Space.s1) {
                        ForEach(genres.prefix(DS.Match.genres), id: \.self) { g in
                            Text(verbatim: g).recipe(.badge, color: DS.paper).lineLimit(1)
                                .padding(.horizontal, DS.Space.s2).padding(.vertical, DS.Space.s1 / 2)
                                .background(DS.paper.opacity(DS.Match.chipFill), in: Capsule())   // ds-exception: sobre el arte de la carta
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
                    Text(verbatim: "\(Int((rating * 10).rounded())) %").recipe(.label, color: DS.paper)
                }
                .padding(.horizontal, DS.Space.s2).padding(.vertical, DS.Space.s1)
                .background(DS.badgeBackground, in: Capsule())
                .padding(DS.Space.s3)
                .accessibilityLabel(Text("Calificación en Trakt: \(Int((rating * 10).rounded())) por ciento"))
            }
        }
        // El color de lo que va a pasar, desde la orilla hacia donde la llevas.
        .overlay {
            if let pull {
                LinearGradient(colors: [pull.color.opacity(DS.Match.tintMax * min(1, pull.amount * DS.Match.hintRamp)), .clear],
                               startPoint: pull.alignment == .bottom ? .top : (lean > 0 ? .trailing : .leading),
                               endPoint: pull.alignment == .bottom ? .center : .center)
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
        .overlay(alignment: .bottomTrailing) {
            if let onPlay {
                DSIconButton(symbol: "play.fill", label: "Ver ya", size: .regular, action: onPlay)
                    .padding(DS.Space.s3)
                    .accessibilityIdentifier("match-play")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous))
        .shadow(DS.Elevation.floating)
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
enum MatchCommand: Equatable { case save, discard, tonight }

/// El mazo: la de arriba se arrastra (pasado el umbral sale volando y avisa); detrás asoman las dos que siguen, más chicas.
/// Los botones de abajo mandan `command` y la carta sale volando igual que al arrastrarla.
struct MatchDeck: View {
    let cards: [Suggestion]
    var genres: (Suggestion) -> [String] = { $0.genres }
    @Binding var command: MatchCommand?
    let onSave: (Suggestion) -> Void
    let onDiscard: (Suggestion) -> Void
    /// Hacia arriba o la ★: «Para hoy».
    var onTonight: (Suggestion) -> Void = { _ in }
    let onOpen: (Suggestion) -> Void
    /// El ▶ de la carta de arriba: «Ver ya».
    var onPlay: ((Suggestion) -> Void)?
    @State private var drag: CGSize = .zero
    @State private var width: CGFloat = 0
    @State private var height: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Array(cards.prefix(3).enumerated().reversed()), id: \.element.imdb) { i, s in
                    let top = i == 0
                    MatchCard(suggestion: s, genres: genres(s), lean: top ? Double(drag.width / (geo.size.width / 2)) : 0,
                              rise: top ? Double(max(0, -drag.height) / (geo.size.height / 2)) : 0,
                              onPlay: top ? onPlay.map { play in { play(s) } } : nil)
                        // Un tamaño fijo dentro del mazo: el póster a sangre no la estira más allá de la pantalla.
                        // En el iPad y la Mac (mazo ancho y bajo) la carta no se ensancha más que un póster: se angosta y se centra.
                        .frame(width: geo.size.width > DS.Match.wideDeck ? min(geo.size.width, geo.size.height / DS.Match.cardAspectMin) : geo.size.width,
                               height: min(geo.size.height, geo.size.width * DS.Match.cardAspect))
                        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous))
                        .scaleEffect(top ? 1 : 1 - CGFloat(i) * DS.Match.behindShrink)
                        .offset(y: top ? 0 : CGFloat(i) * DS.Match.behindDrop)
                        .offset(top ? drag : .zero)
                        .rotationEffect(.degrees(top ? Double(drag.width) / DS.Match.tiltDivisor : 0))
                        .allowsHitTesting(top)
                        .gesture(top ? swipe(width: geo.size.width, s) : nil)
                        .onTapGesture { if top { onOpen(s) } }
                        .accessibilityAction(named: Text("Guardar")) { onSave(s) }
                        .accessibilityAction(named: Text("Paso")) { onDiscard(s) }
                        .accessibilityAction(named: Text("Para hoy")) { onTonight(s) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: geo.size, initial: true) { _, size in width = size.width; height = size.height }
        }
        .animation(DS.Motion.spring(reduceMotion), value: cards.first?.imdb)
        .onChange(of: command) { _, asked in
            guard let asked, let s = cards.first else { command = nil; return }
            command = nil
            fly(asked == .tonight ? .up : asked == .save ? .right : .left, s, from: .zero)
        }
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
                guard far else { withAnimation(DS.Motion.spring(reduceMotion)) { drag = .zero }; return }
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

