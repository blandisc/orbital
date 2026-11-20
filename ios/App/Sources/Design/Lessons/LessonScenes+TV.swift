import SwiftUI

// «Tu TV» (prototipo `scenes.js`, t-send … t-try): mandarlo a la TV, el iPhone como control, la voz, lo que pasa mientras
// juegas y «Pruébalo» con una TV de práctica. Medidas del lienzo de 402 × 330; la TV, a la derecha.
enum LessonTVLayout {
    static let tv = CGRect(x: 168, y: 40, width: 214, height: 124)
}

/// Una fila de pósters en la TV, con el foco turquesa en uno.
struct LessonTVRow: View {
    let art: LessonArt
    let focus: Int

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            ForEach(0..<4, id: \.self) { i in
                LessonPoster(item: art.mixed(i), w: 40, h: 60, radius: DS.Radius.xs, shadow: false)
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous).strokeBorder(DS.fresh, lineWidth: DS.Stroke.selected).opacity(i == focus ? 1 : 0))
                    .scaleEffect(i == focus ? DS.Scene.lifted : 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// «Ver en la TV»: el toque en el iPhone, el póster viaja en arco a la TV y la TV se prende con la película.
struct LessonTVSend: View {
    let t: Double
    let art: LessonArt
    static let end = 2.0

    var body: some View {
        let M = LessonMotion.self, tv = LessonTVLayout.tv
        let phone = M.enter(t, 0.05), screen = M.enter(t, 0.1)
        let k = M.smooth(0.72, 1.2, t)
        let p = M.quad(CGPoint(x: 88, y: 150), CGPoint(x: 170, y: -20), CGPoint(x: tv.midX, y: tv.minY + 60), k)
        ZStack(alignment: .topLeading) {
            LessonPhone(w: 120, h: 196) {
                LessonPoster(item: art.movie(0), w: 70, h: 105, radius: DS.Radius.xs).sceneAt(20, 18)
                LessonPlayButton(title: Text("Ver en la TV"), symbol: "tv", compact: true).sceneBox(102, 28).sceneAt(4, 134)
            }
            .sceneAt(28, 80).scenePut(phone.o, 0, phone.y)
            LessonTV(w: tv.width, h: tv.height) {
                LessonVideo(item: art.movie(0), w: tv.width, h: tv.height, progress: 0.02 + 0.1 * M.smooth(1.4, 4, t), corner: 0)
                    .opacity(M.smooth(1.1, 1.35, t))
            }
            .sceneAt(tv.minX, tv.minY).scenePut(screen.o * M.lerp(0.6, 1, M.smooth(1.05, 1.3, t)), 0, screen.y)
            LessonPoster(item: art.movie(0), w: 42, h: 63, radius: DS.Radius.xs)
                .scenePut(M.smooth(0.7, 0.76, t) * M.lerp(1, 0, M.smooth(1.12, 1.2, t)), p.x - 21, p.y - 31, CGFloat(M.lerp(1, 0.8, k)), -8 * sin(.pi * k))
            LessonFinger(t: t, x: 88, y: 233, at: 0.6)
        }
    }
}

/// El iPhone como control: el dedo desliza sobre el círculo y el foco avanza en la TV, uno por cada deslizada.
struct LessonTVRemote: View {
    let t: Double
    let art: LessonArt
    static let end = 2.0
    private static let swipes = [0.8, 1.4]

    var body: some View {
        let M = LessonMotion.self, tv = LessonTVLayout.tv
        let phone = M.enter(t, 0.05), screen = M.enter(t, 0.1)
        let focus = t < 0.8 ? 0 : t < 1.4 ? 1 : 2
        ZStack(alignment: .topLeading) {
            LessonPhone(w: 110, h: 210) {
                Circle().fill(DS.fillStrong).sceneBox(80, 80).sceneAt(10, 50)
                ForEach(0..<2, id: \.self) { n in
                    let s = Self.swipes[n]
                    Circle().fill(DS.paper.opacity(DS.Lesson.fingerFill))
                        .overlay(Circle().strokeBorder(DS.paper.opacity(DS.Lesson.fingerRim), lineWidth: DS.Stroke.regular))
                        .sceneBox(30, 30)
                        .scenePut(M.smooth(s - 0.34, s - 0.26, t) * M.lerp(1, 0, M.smooth(s, s + 0.1, t)),
                                  35 - 18 + 36 * M.smooth(s - 0.3, s, t), 75)
                }
                Text("Desliza para moverte").font(DS.TextRecipe.caption.font).foregroundStyle(DS.textMuted).multilineTextAlignment(.center)
                    .sceneWidth(100).sceneAt(0, 146)
            }
            .sceneAt(28, 70).scenePut(phone.o, 0, phone.y)
            LessonTV(w: tv.width, h: tv.height) { LessonTVRow(art: art, focus: focus).animation(DS.Motion.press, value: focus) }
                .sceneAt(tv.minX, tv.minY).scenePut(screen.o, 0, screen.y)
        }
    }
}

/// Háblale: el borde del iPhone se prende como Siri, lo que dices se escribe en la burbuja y la TV pasa del episodio 1 al 2.
struct LessonTVVoice: View {
    let t: Double
    let art: LessonArt
    @Environment(\.locale) private var locale
    static let end = 2.2

    var body: some View {
        let M = LessonMotion.self, tv = LessonTVLayout.tv
        let phone = M.enter(t, 0.05), screen = M.enter(t, 0.1)
        let said = Strings.tr("«Siguiente episodio en Orbital»", language: locale.language.languageCode?.identifier ?? "es")
        let shown = Int((Double(said.count) * M.smooth(0.35, 1.2, t)).rounded())
        let listening = M.smooth(0.2, 0.4, t) * M.lerp(1, 0, M.smooth(1.4, 1.7, t)), next = M.smooth(1.4, 1.7, t)
        ZStack(alignment: .topLeading) {
            LessonPhone(w: 110, h: 210) {
                Circle().fill(RadialGradient(colors: [DS.paper, DS.fresh, DS.brandMoon.opacity(DS.Opacity.faint)], center: .init(x: 0.4, y: 0.35),
                                             startRadius: 0, endRadius: 24))
                    .sceneBox(40, 40)
                    .scaleEffect(1 + 0.12 * sin(t * 9) * listening)
                    .sceneAt(30, 120).opacity(M.lerp(DS.Opacity.faint, 1, listening))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 110 * DS.Lesson.phoneCorner, style: .continuous)
                    .strokeBorder(AngularGradient(colors: [DS.fresh, DS.brandMoon, DS.paper, DS.fresh], center: .center,
                                                  angle: .degrees(t * 120)), lineWidth: DS.Stroke.selected)
                    .opacity(listening)
            }
            .sceneAt(28, 70).scenePut(phone.o, 0, phone.y)
            LessonTV(w: tv.width, h: tv.height) {
                ZStack(alignment: .bottomLeading) {
                    LessonVideo(item: art.show(1), w: tv.width, h: tv.height, progress: M.lerp(0.97, 0.01, next), showsBar: true)
                    ZStack(alignment: .leading) {
                        Text("\(art.show(1).title) · T4 E1").opacity(M.lerp(1, 0, next))
                        Text("\(art.show(1).title) · T4 E2").opacity(next)
                    }
                    .font(DS.TextRecipe.badge.font).foregroundStyle(DS.paper).padding(.horizontal, DS.Space.s2).padding(.bottom, DS.Space.s4)
                }
            }
            .sceneAt(tv.minX, tv.minY).scenePut(screen.o, 0, screen.y)
            Text(verbatim: String(said.prefix(shown)))
                .font(DS.TextRecipe.secondary.font).foregroundStyle(DS.text)
                .padding(.horizontal, DS.Space.s2).padding(.vertical, DS.Space.s2)
                .background(DS.surfaceRaised, in: UnevenRoundedRectangle(topLeadingRadius: DS.Radius.lg, bottomLeadingRadius: DS.Radius.xs,   // ds-exception: la burbuja de lo que dices (su pico abajo a la izquierda)
                                                                         bottomTrailingRadius: DS.Radius.lg, topTrailingRadius: DS.Radius.lg))
                .sceneWidth(230, alignment: .leading, fits: true)
                .sceneAt(56, 10).opacity(shown > 0 ? 1 : 0)
        }
    }
}

/// Mientras juegas: la TV con el juego (colinas y sol) y el iPhone con los tres paneles del compañero de juego, como en la
/// app: la guía, tus notas y el temporizador que corre.
struct LessonTVGame: View {
    let t: Double
    static let end = 2.0

    var body: some View {
        let M = LessonMotion.self, tv = LessonTVLayout.tv
        let screen = M.enter(t, 0.05), phone = M.enter(t, 0.12)
        let left = 25 * 60 - 1 - Int(max(0, (t - 0.5) * 2))
        ZStack(alignment: .topLeading) {
            LessonTV(w: tv.width, h: tv.height) { LessonGameView(t: t, w: tv.width, h: tv.height) }
                .sceneAt(tv.minX, tv.minY).scenePut(screen.o, 0, screen.y)
            LessonPhone(w: 124, h: 236) {
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    panel(0, title: Text("Guía")) { line(0.9) }
                    panel(1, title: Text("Notas")) { line(1); line(0.6) }
                    panel(2, title: Text("Temporizador"), lit: true) {
                        Text(verbatim: String(format: "%d:%02d", left / 60, left % 60)).font(DS.TextRecipe.title.font).monospacedDigit().foregroundStyle(DS.text)
                        Text("Te aviso al terminar").font(DS.TextRecipe.caption.font).foregroundStyle(DS.textMuted).lineLimit(2)
                    }
                }
                .sceneWidth(102).sceneAt(6, 22)
            }
            .sceneAt(28, 50).scenePut(phone.o, 0, phone.y)
        }
    }

    private func panel(_ i: Int, title: Text, lit: Bool = false, @ViewBuilder content: () -> some View) -> some View {
        let e = LessonMotion.enter(t, 0.25 + Double(i) * 0.08, 8)
        return VStack(alignment: .leading, spacing: DS.Lesson.tight) {
            title.font(DS.TextRecipe.badge.font).foregroundStyle(lit ? DS.fresh : DS.textMuted)
            content()
        }
        .padding(DS.Space.s2).frame(maxWidth: .infinity, alignment: .leading)
        .dsCard(translucent: true)
        .scenePut(e.o, 0, e.y)
    }

    private func line(_ share: CGFloat) -> some View {
        Capsule().fill(DS.fillStrong).sceneBox(82 * share, 4)
    }
}

/// Lo que se ve en la TV mientras juegas: cielo, sol y dos colinas que se mueven despacio.
struct LessonGameView: View {
    let t: Double
    let w: CGFloat
    let h: CGFloat

    var body: some View {
        let drift = CGFloat(t) * 6
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [DS.Match.tonight.opacity(DS.Opacity.dimmed), DS.surface], startPoint: .top, endPoint: .bottom)
            Circle().fill(DS.warning).sceneBox(26, 26).sceneAt(w * 0.68, h * 0.18)
            hill(base: h * 0.72, peak: h * 0.42, shift: -drift).fill(DS.ListTint.list.opacity(DS.Opacity.dimmed))
            hill(base: h * 0.86, peak: h * 0.58, shift: drift * 0.5 + w * 0.3).fill(DS.ListTint.list)
        }
    }

    private func hill(base: CGFloat, peak: CGFloat, shift: CGFloat) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 0, y: h))
            p.addLine(to: CGPoint(x: 0, y: base))
            p.addQuadCurve(to: CGPoint(x: w * 0.6, y: base), control: CGPoint(x: w * 0.3 + shift, y: peak - (base - peak)))
            p.addQuadCurve(to: CGPoint(x: w, y: base - 6), control: CGPoint(x: w * 0.8 - shift, y: peak))
            p.addLine(to: CGPoint(x: w, y: h))
            p.closeSubpath()
        }
    }
}

/// «Pruébalo», con una TV de práctica: «Ver en la TV» manda la película y, con la película de fondo, las flechas mueven el
/// foco por la fila (cualquiera de las dos cuenta).
struct LessonTVTry: View {
    let t: Double
    let art: LessonArt
    let done: () -> Void
    @State private var sentAt: Double?
    @State private var focus = 1
    @State private var moved = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let M = LessonMotion.self, tv = LessonTVLayout.tv
        let e = M.enter(t, 0.05)
        let s = sentAt.map { t - $0 } ?? -1
        let k = M.smooth(0, 0.6, s)
        let p = M.quad(CGPoint(x: 90, y: 104), CGPoint(x: 170, y: -20), CGPoint(x: tv.midX, y: tv.minY + 60), k)
        let ready = s > 1.3
        ZStack(alignment: .topLeading) {
            LessonPhone(w: 124, h: 220) {
                Button { if sentAt == nil { sentAt = t } } label: {
                    LessonPlayButton(title: Text("Ver en la TV"), symbol: "tv", compact: true)
                }
                .buttonStyle(.plain)
                .overlay { if sentAt == nil { LessonTryRing(round: true).padding(-DS.Space.s1) } }
                .sceneBox(106, 30).sceneAt(4, 20)
                .accessibilityIdentifier("lesson-try-send")
                Circle().fill(DS.fillStrong).sceneBox(90, 90)
                    .overlay { if ready && !moved { LessonTryRing(round: true).padding(-DS.Space.s1) } }
                    .sceneAt(12, 78)
                HStack(spacing: DS.Space.s6) {
                    arrow("chevron.left", label: Text("Izquierda"), id: "left") { focus = max(0, focus - 1) }
                    arrow("chevron.right", label: Text("Derecha"), id: "right") { focus = min(3, focus + 1) }
                }
                .sceneWidth(114).sceneAt(0, 101)
            }
            .sceneAt(28, 64).scenePut(e.o, 0, e.y)
            LessonTV(w: tv.width, h: tv.height) {
                ZStack {
                    LessonVideo(item: art.movie(0), w: tv.width, h: tv.height, progress: 0.05, corner: 0)
                        .opacity(s > 0.55 ? (ready ? DS.Opacity.faint : 1) : 0)
                    LessonTVRow(art: art, focus: focus).opacity(ready ? 1 : s > 0 ? 0 : DS.Opacity.faint)
                        .animation(DS.Motion.press, value: focus)
                }
                .animation(DS.Motion.base(reduceMotion), value: s > 0.55)
                .animation(DS.Motion.base(reduceMotion), value: ready)
            }
            .sceneAt(tv.minX, tv.minY).scenePut(e.o, 0, e.y)
            LessonPoster(item: art.movie(0), w: 42, h: 63, radius: DS.Radius.xs)
                .scenePut(s > 0 && s < 0.6 ? 1 : 0, p.x - 21, p.y - 31, CGFloat(M.lerp(1, 0.8, k)))
            if ready && !moved {
                LessonCaption(text: Text("Ahora muévete con las flechas"), w: tv.width).sceneAt(tv.minX, tv.maxY + 40)
            }
        }
    }

    private func arrow(_ symbol: String, label: Text, id: String, action: @escaping () -> Void) -> some View {
        Button {
            guard sentAt != nil else { return }
            action()
            if !moved { moved = true; done() }
        } label: {
            Image(systemName: symbol).font(DS.TextRecipe.cardTitle.font).foregroundStyle(DS.text)
                .frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier("lesson-try-\(id)")
    }
}
