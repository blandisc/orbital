import SwiftUI

// «¿Qué veo hoy?» (prototipo `scenes.js`, q-why … q-try): de dónde salen las sugerencias, «Decide por mí», «Una por una»,
// juntar filtros y «Pruébalo». Medidas del lienzo de 402 × 330. Revisadas por un crítico (19 nov 2026): cada gesto se ve
// (el botón que se toca, el dedo que arrastra), las cartas salen con la física del mazo real y «Para hoy» va en su azul.

/// De dónde salen las sugerencias: el mosaico de lo que te proponemos; la del centro se levanta y su porqué brota debajo.
struct LessonTodayWhy: View {
    let t: Double
    let art: LessonArt
    static let end = 1.6

    var body: some View {
        let M = LessonMotion.self
        let hi = M.smooth(0.6, 0.9, t), chip = M.spring(t - 0.85, 0.5, 0.2)
        ZStack(alignment: .topLeading) {
            ForEach([0, 1, 2, 3, 5, 6, 7, 8, 4], id: \.self) { i in
                let d = hypot(Double(i % 3 - 1), Double(i / 3 - 1))
                let e = M.enter(t, 0.04 + d * 0.05)
                let picked = i == 4
                LessonPoster(item: art.mixed(i), w: 58, h: 87, radius: DS.Radius.sm)
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                        .strokeBorder(DS.fresh, lineWidth: DS.Stroke.selected).opacity(picked ? hi : 0))
                    .scaleEffect(picked ? 1 + hi * 0.18 : 1)
                    .sceneAt(CGFloat(102 + (i % 3) * 70), CGFloat(6 + (i / 3) * 93))
                    .scenePut(e.o * (picked ? 1 : M.lerp(1, DS.Opacity.faint, hi)), 0, e.y - (picked ? hi * 6 : 0))
            }
            LessonChip { Image(systemName: "sparkles").foregroundStyle(DS.fresh); Text("Porque viste \(Text(art.movie(5).title).bold())") }
                .scaleEffect(M.lerp(0.9, 1, chip)).sceneWidth(402).sceneAt(0, 196)
                .scenePut(M.clamp((t - 0.85) / 0.2), 0, (1 - chip) * -8)
        }
    }
}

/// Las tres de «Decide por mí»: una serie al centro (la corta) y dos películas, cada una con su porqué debajo (sin girar).
struct LessonTodayTrio: View {
    let art: LessonArt
    /// 0 juntas en el mazo, 1 abiertas en abanico.
    let fan: Double
    /// Los porqués: de 0 a 1 cada uno.
    var reasons: [Double] = [1, 1, 1]
    /// La que elegiste (de práctica): pasa al centro, al frente y crece; las otras se apartan y se apagan.
    var chosen: Int?
    var choose: ((Int) -> Void)?

    func item(_ i: Int) -> LessonArt.Item { [art.movie(1), art.show(0), art.movie(2)][i] }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<3, id: \.self) { i in
                let d = Double(i - 1), picked = chosen == i, out = chosen != nil && !picked
                let dx = picked ? 0 : CGFloat(d * (out ? 150 : 118 * fan))
                let dy = picked ? -16 : CGFloat(abs(d) * 12 * fan)
                let scale = picked ? 1.12 : out ? 0.9 : CGFloat(LessonMotion.lerp(0.92, 1, fan))
                Button { choose?(i) } label: {
                    LessonPoster(item: item(i), w: 120, h: 180, radius: DS.Radius.md)
                        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .strokeBorder(DS.fresh, lineWidth: DS.Stroke.selected).opacity(picked ? 1 : 0))
                }
                .buttonStyle(.plain)
                .disabled(choose == nil)
                .accessibilityIdentifier("lesson-try-pick-\(i)")
                .scaleEffect(scale).rotationEffect(.degrees(picked ? 0 : d * 6 * fan))
                .sceneAt(141, 30)
                .scenePut(out ? DS.Opacity.faint : 1, dx, dy)
                .zIndex(picked ? 3 : i == 1 ? 2 : 1)
                reason(i).font(DS.TextRecipe.caption.font).foregroundStyle(DS.fresh).multilineTextAlignment(.center)
                    .lineLimit(2).sceneBox(112, 34)
                    .sceneAt(145, 222)
                    .scenePut(reasons[i] * (out ? 0 : 1), dx, dy + (picked ? 22 : 0) + CGFloat(1 - reasons[i]) * 6)
                    .zIndex(4) // ds-exception: orden dentro de la escena (los porqués, sobre las tres tarjetas)
            }
        }
    }

    private func reason(_ i: Int) -> Text {
        switch i {
        case 0: Text("Porque viste \(art.movie(5).title)")
        case 1: Text("Capítulos de media hora")
        default: Text("Está en tu Netflix")
        }
    }
}

/// «Decide por mí»: el dedo toca el botón y de ahí salen tres en abanico; los porqués aterrizan con ellas.
struct LessonTodayDecide: View {
    let t: Double
    let art: LessonArt
    static let end = 2.0

    var body: some View {
        let M = LessonMotion.self
        let e = M.enter(t, 0.05)
        ZStack(alignment: .topLeading) {
            LessonTodayTrio(art: art, fan: M.spring(t - 0.55, 0.55, 0.18), reasons: (0..<3).map { M.clamp((t - 1.0 - Double($0) * 0.07) / 0.25) })
                .opacity(M.smooth(0.5, 0.6, t))
            LessonTodayDecideButton().sceneBox(240, 52).scaleEffect(1 - 0.04 * M.smooth(0.42, 0.5, t)).sceneAt(81, 128)
                .scenePut(e.o * M.lerp(1, 0, M.smooth(0.5, 0.65, t)), 0, e.y)
            LessonFinger(t: t, x: 201, y: 154, at: 0.45)
        }
    }
}

/// El botón «Decide por mí» de la escena (el de verdad en «Pruébalo»).
struct LessonTodayDecideButton: View {
    var action: () -> Void = {}
    var body: some View {
        Button(action: action) { Label("Decide por mí", systemImage: DS.Symbol.decide).frame(maxWidth: .infinity) }
            .dsPrimaryButton().dsControlSize(.large)
    }
}

/// «Una por una», como el mazo de verdad: el dedo arrastra la carta, su sello crece con el arrastre y sale volando —
/// derecha «Guardar», izquierda «Paso», arriba «Para hoy»—; al final queda la siguiente con las tres pistas alrededor.
struct LessonTodaySwipe: View {
    let t: Double
    let art: LessonArt
    static let end = 3.3
    /// Cuándo empieza cada arrastre y hacia dónde (x, y).
    private static let flings: [(at: Double, dir: CGPoint)] = [(0.5, CGPoint(x: 1, y: 0)), (1.35, CGPoint(x: -1, y: 0)), (2.2, CGPoint(x: 0, y: -1))]

    var body: some View {
        let M = LessonMotion.self
        let e = M.enter(t, 0.05)
        ZStack(alignment: .topLeading) {
            ForEach((0..<4).reversed(), id: \.self) { i in
                let gone = i == 0 ? 0 : M.smooth(Self.flings[i - 1].at + 0.6, Self.flings[i - 1].at + 0.85, t)   // la de atrás avanza
                let behind = CGFloat(max(0, Double(i) - gone))
                let (drag, fly) = i < 3 ? (M.smooth(Self.flings[i].at, Self.flings[i].at + 0.4, t), M.easeOut((t - Self.flings[i].at - 0.4) / 0.25)) : (0, 0)
                let dir = i < 3 ? Self.flings[i].dir : .zero
                let off = CGPoint(x: dir.x * (80 * drag + 340 * fly), y: dir.y * (60 * drag + 300 * fly))
                card(art.mixed(i + 4), stamp: i < 3 ? i : nil, amount: drag)
                    .scaleEffect(1 - DS.Match.behindShrink * behind).rotationEffect(.degrees(Double(off.x) / DS.Match.tiltDivisor * 0.9))
                    .sceneAt(121, 30)
                    .scenePut(i == 3 ? e.o * M.lerp(0, 1, gone) : e.o, off.x, off.y + DS.Match.behindPeek * behind)
                    .zIndex(Double(4 - i))
            }
            ForEach(0..<3, id: \.self) { i in
                let d = Self.flings[i]
                LessonFinger(t: t, x: 201 + d.dir.x * 80 * M.smooth(d.at, d.at + 0.4, t), y: 150 + d.dir.y * 60 * M.smooth(d.at, d.at + 0.4, t), at: d.at)
            }
            hints.opacity(M.smooth(2.95, 3.2, t))
        }
    }

    /// Las tres pistas fijas al final: a la izquierda «Paso», a la derecha «Guardar», arriba «Para hoy».
    private var hints: some View {
        ZStack(alignment: .topLeading) {
            hint(Text("Paso"), DS.Symbol.matchPass, DS.Match.pass).sceneWidth(110).sceneAt(6, 140)
            hint(Text("Guardar"), DS.Symbol.matchKeep, DS.Match.keep).sceneWidth(110).sceneAt(286, 140)
            hint(Text("Para hoy"), DS.Symbol.matchTonight, DS.Match.tonight).sceneWidth(402).sceneAt(0, 2)
        }
    }

    private func hint(_ title: Text, _ symbol: String, _ tint: Color) -> some View {
        Label { title } icon: { Image(systemName: symbol) }.font(DS.TextRecipe.label.font).foregroundStyle(tint)
    }

    private func card(_ item: LessonArt.Item, stamp: Int?, amount: Double) -> some View {
        let tint: Color = stamp == 0 ? DS.Match.keep : stamp == 1 ? DS.Match.pass : DS.Match.tonight
        return LessonPoster(item: item, w: 160, h: 240, radius: DS.Radius.xxl)
            .overlay {
                if stamp != nil {
                    LinearGradient(colors: [tint.opacity(DS.Match.tintMax * amount), .clear],
                                   startPoint: stamp == 0 ? .trailing : stamp == 1 ? .leading : .bottom,
                                   endPoint: stamp == 0 ? .leading : stamp == 1 ? .trailing : .top)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous))
                }
            }
            .overlay(alignment: stamp == 0 ? .topLeading : stamp == 1 ? .topTrailing : .bottom) {
                if let stamp {
                    let title = stamp == 0 ? Text("Guardar") : stamp == 1 ? Text("Paso") : Text("Para hoy")
                    let symbol = stamp == 0 ? DS.Symbol.matchKeep : stamp == 1 ? DS.Symbol.matchPass : DS.Symbol.matchTonight
                    Label { title } icon: { Image(systemName: symbol) }
                        .font(DS.TextRecipe.section.font).foregroundStyle(tint)
                        .padding(.horizontal, DS.Space.s2).padding(.vertical, DS.Space.s1)
                        .background(DS.scrim, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous).strokeBorder(tint, lineWidth: DS.Match.stampLine))
                        .rotationEffect(.degrees(stamp == 0 ? -DS.Match.stampTilt : stamp == 1 ? DS.Match.stampTilt : 0))
                        .scaleEffect(LessonMotion.lerp(DS.MatchLive.stampFrom, 1, amount))
                        .padding(DS.Space.s2)
                        .opacity(amount)
                }
            }
    }
}

/// Juntar filtros: cada uno que se prende achica la lista de verdad (los pósters de abajo se apagan) y el número baja
/// contando; al final quedan tres.
struct LessonTodayFilter: View {
    let t: Double
    let art: LessonArt
    static let end = 2.2
    static let filters: [(LocalizedStringKey, String)] = [("Comedia", "theatermasks"), ("Años 90", "calendar"), ("Netflix", "play.tv")]
    static let counts = [2400, 380, 64, 3]
    /// Cuántos pósters siguen encendidos con cada filtro, y en qué orden se apagan (salteados, no de corrido).
    private static let lit = [16, 9, 5, 3]
    private static let order = [7, 2, 12, 5, 14, 0, 9, 3, 11, 15, 6, 1, 13, 8, 4, 10]
    private static func at(_ i: Int) -> Double { 0.5 + Double(i) * 0.5 }

    var body: some View {
        let M = LessonMotion.self
        let step = (0..<3).filter { t > Self.at($0) }.count
        let f = step == 0 ? 0 : M.easeOut((t - Self.at(step - 1)) / 0.35)
        let value = step == 0 ? Self.counts[0] : Int(M.lerp(Double(Self.counts[step - 1]), Double(Self.counts[step]), f).rounded())
        let e = M.enter(t, 0.05, 10)
        ZStack(alignment: .topLeading) {
            Label("Buscar", systemImage: "magnifyingglass").font(DS.TextRecipe.secondary.font).foregroundStyle(DS.textMuted)
                .padding(.horizontal, DS.Space.s4).sceneBox(354, 40).dsCard(translucent: true)
                .sceneAt(24, 4).scenePut(e.o, 0, e.y)
            HStack(spacing: DS.Space.s2) { ForEach(0..<3, id: \.self) { chip($0, t) } }
                .sceneWidth(402).sceneAt(0, 58).scenePut(e.o, 0, e.y)
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s1) {
                Text(verbatim: value.formatted(.number.locale(Locale(identifier: "es_MX")))).font(DS.TextRecipe.title.font).monospacedDigit().foregroundStyle(DS.text)
                Text("títulos").font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted)
            }
            .sceneWidth(402).sceneAt(0, 108).opacity(e.o)
            ForEach(0..<16, id: \.self) { i in
                let rank = Self.order.firstIndex(of: i) ?? 0
                let on = (0..<4).map { s in rank < Self.lit[s] ? 1.0 : 0.0 }
                let k = step == 0 ? on[0] : M.lerp(on[step - 1], on[step], M.smooth(0, 0.3, t - Self.at(step - 1)))
                let last = rank < 3 ? M.smooth(1.75, 2.05, t) : 0
                LessonPoster(item: art.mixed(i), w: 36, h: 54, radius: DS.Radius.xs, shadow: false)
                    .scaleEffect(1 + 0.08 * last)
                    .sceneAt(CGFloat(33 + (i % 8) * 43), CGFloat(152 + (i / 8) * 62))
                    .scenePut(e.o * M.lerp(DS.Opacity.faint * 0.4, 1, k), 0, e.y)
            }
        }
    }

    private func chip(_ i: Int, _ t: Double) -> some View {
        let M = LessonMotion.self
        let on = M.smooth(Self.at(i), Self.at(i) + 0.15, t), bump = max(0, 1 - abs(t - Self.at(i) - 0.08) / 0.15)
        return Label { Text(Self.filters[i].0) } icon: { Image(systemName: Self.filters[i].1) }
            .font(DS.TextRecipe.secondary.font).foregroundStyle(on > 0.5 ? DS.fresh : DS.textMuted)
            .padding(.horizontal, DS.Space.s2).frame(height: DS.Lesson.filterChip)
            .background(DS.fresh.opacity(DS.Opacity.selectedFill * on), in: Capsule())
            .background(DS.fill.opacity(M.lerp(1, 0, on)), in: Capsule())
            .overlay(Capsule().strokeBorder(DS.fresh, lineWidth: DS.Stroke.selected).opacity(on))
            .scaleEffect(1 + (DS.Scene.lifted - 1) * bump)
    }
}

/// «Pruébalo»: «Decide por mí» de verdad. Detrás del botón, el mazo; al tocarlo salen tres en abanico con sus porqués; tocas
/// una y pasa al frente como la de esta noche.
struct LessonTodayTry: View {
    let t: Double
    let art: LessonArt
    let done: () -> Void
    @State private var opened = false
    @State private var reasons = [0.0, 0, 0]
    @State private var chosen: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            LessonTodayTrio(art: art, fan: opened ? 1 : 0, reasons: reasons, chosen: chosen,
                            choose: opened ? { i in
                                let first = chosen == nil
                                withAnimation(DS.Motion.spring(reduceMotion)) { chosen = i }
                                if first { done() }
                            } : nil)
                .opacity(opened ? 1 : DS.Opacity.faint)
                .scaleEffect(opened ? 1 : 0.92)
            if !opened {
                LessonTodayDecideButton {
                    withAnimation(DS.Motion.spring(reduceMotion)) { opened = true }
                    for i in 0..<3 { withAnimation(DS.Motion.enter(reduceMotion)?.delay(0.35 + Double(i) * 0.08)) { reasons[i] = 1 } }
                }
                .overlay { LessonTryRing().padding(-DS.Space.s2) }
                .sceneBox(240, 52).sceneAt(81, 128)
                .accessibilityIdentifier("lesson-try-decide")
            }
            if let chosen {
                LessonChip { Image(systemName: DS.Symbol.matchTonight).foregroundStyle(DS.Match.tonight); Text("Para hoy: \(Text(LessonTodayTrio(art: art, fan: 1).item(chosen).title).bold())") }
                    .sceneWidth(402).sceneAt(0, 2).id(chosen).transition(.scale(scale: DS.Scene.pressed).combined(with: .opacity))
            }
        }
    }
}
