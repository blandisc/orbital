import SwiftUI
import OrbitalCore

// «¿Qué vemos hoy?» · Encuentra tu match perfecto (docs/producto/inicio-benchmark/para-ti/B-interactivo.dc.html): el mazo
// de cartas que se arrastran (derecha guarda, izquierda descarta) y los ánimos como mosaicos con ícono.

/// Una carta: el póster grande con su nombre, año y géneros; al arrastrarla asoma un ícono (✓ guardar, ✕ descartar).
struct MatchCard: View {
    let suggestion: Suggestion
    /// -1…1: cuánto se ha arrastrado a la izquierda o a la derecha (para el ícono que asoma).
    var lean: Double = 0

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear.overlay { PosterView(url: suggestion.poster, title: suggestion.title, aspect: nil, bleed: true).scaledToFill() }.clipped()
            LinearGradient(colors: [.clear, DS.scrimStrong], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(verbatim: suggestion.title).font(DS.TextRecipe.title.font.weight(.bold)).foregroundStyle(DS.paper).lineLimit(2)
                Text(verbatim: [suggestion.year.map(String.init), suggestion.genres.prefix(2).joined(separator: " · ")].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .recipe(.footnote, color: DS.onArtSecondary).lineLimit(1)
            }
            .padding(DS.Space.s4)
        }
        .overlay(alignment: lean > 0 ? .topLeading : .topTrailing) {
            if abs(lean) > DS.Match.hintFrom {
                Image(systemName: lean > 0 ? "bookmark.fill" : "xmark")
                    .font(DS.TextRecipe.title.font.weight(.bold)).foregroundStyle(lean > 0 ? DS.backdropDeep : DS.paper)
                    .frame(width: DS.Match.hint, height: DS.Match.hint)
                    .background(lean > 0 ? DS.brandMoon : DS.scrimStrong, in: Circle())
                    .padding(DS.Space.s4)
                    .opacity(min(1, (abs(lean) - DS.Match.hintFrom) * DS.Match.hintRamp))
                    .accessibilityHidden(true)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous))
        .shadow(color: DS.scrimStrong, radius: DS.Space.s4, y: DS.Space.s2)
        .accessibilityElement(children: .combine)
    }
}

/// El mazo: la de arriba se arrastra (pasado el umbral sale volando y avisa); detrás asoman las dos que siguen, más chicas.
struct MatchDeck: View {
    let cards: [Suggestion]
    let onSave: (Suggestion) -> Void
    let onDiscard: (Suggestion) -> Void
    let onOpen: (Suggestion) -> Void
    @State private var drag: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Array(cards.prefix(3).enumerated().reversed()), id: \.element.imdb) { i, s in
                    let top = i == 0
                    MatchCard(suggestion: s, lean: top ? Double(drag.width / (geo.size.width / 2)) : 0)
                        .scaleEffect(top ? 1 : 1 - CGFloat(i) * DS.Match.behindShrink)
                        .offset(y: top ? 0 : CGFloat(i) * DS.Match.behindDrop)
                        .offset(top ? drag : .zero)
                        .rotationEffect(.degrees(top ? Double(drag.width) / DS.Match.tiltDivisor : 0))
                        .allowsHitTesting(top)
                        .gesture(top ? swipe(width: geo.size.width, s) : nil)
                        .onTapGesture { if top { onOpen(s) } }
                        .accessibilityAction(named: Text("Guardar")) { onSave(s) }
                        .accessibilityAction(named: Text("Descartar")) { onDiscard(s) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(DS.Motion.spring(reduceMotion), value: cards.first?.imdb)
    }

    private func swipe(width: CGFloat, _ s: Suggestion) -> some Gesture {
        DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { g in
                let far = abs(g.translation.width) > width * DS.Match.threshold || abs(g.predictedEndTranslation.width) > width
                guard far else { withAnimation(DS.Motion.spring(reduceMotion)) { drag = .zero }; return }
                let right = g.translation.width > 0
                withAnimation(DS.Motion.base(reduceMotion)) { drag = CGSize(width: right ? width * 2 : -width * 2, height: g.translation.height) }
                Task { @MainActor in
                    try? await Task.sleep(for: DS.Match.flyOut)
                    drag = .zero
                    if right { onSave(s) } else { onDiscard(s) }
                }
            }
    }
}

/// Un ánimo como mosaico: ícono y nombre; el elegido con fondo turquesa al 18 % y borde turquesa.
struct MoodTile: View {
    let symbol: String
    let title: Text
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: DS.Space.s1) {
                Image(systemName: symbol).font(DS.TextRecipe.cardTitle.font).foregroundStyle(selected ? DS.brandMoon : DS.text)
                title.recipe(.caption, color: DS.text).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
            }
            .frame(maxWidth: .infinity, minHeight: DS.Match.mood)
            .background(selected ? DS.Filter.selectedFill : DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous).strokeBorder(selected ? DS.brandMoon : .clear, lineWidth: DS.Size.hairline * 2))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
