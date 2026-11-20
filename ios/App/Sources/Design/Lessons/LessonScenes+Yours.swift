import SwiftUI

// «Lo tuyo, al día» (prototipo `scenes.js`, l-trakt … l-try): qué guarda Trakt, seguir en otro aparato, marcar visto y
// calificar, los estrenos y «Pruébalo». Medidas del lienzo de 402 × 330.

/// Qué guarda Trakt: su logo y tres renglones (lo visto, tu lista, dónde ibas) que llegan uno tras otro.
struct LessonYoursTrakt: View {
    let t: Double
    let art: LessonArt
    static let end = 2.2

    var body: some View {
        let M = LessonMotion.self
        let logo = M.pop(t, 0.05)
        ZStack(alignment: .topLeading) {
            Image("rating-trakt").resizable().scaledToFit().sceneBox(40, 40)
                .sceneBox(64, 64).dsCard(fill: DS.surfaceRaised)
                .scaleEffect(CGFloat(M.lerp(0.6, 1, logo))).sceneAt(169, 18).opacity(M.clamp(t / 0.2))
            ForEach(0..<3, id: \.self) { i in
                let e = M.enter(t, 0.3 + Double(i) * 0.1 - Double(i * i) * 0.015)
                row(i).sceneBox(342, 60).sceneAt(30, CGFloat(100 + i * 70)).scenePut(e.o, 0, e.y)
            }
        }
    }

    private func row(_ i: Int) -> some View {
        let symbol = ["checkmark.circle.fill", "bookmark.fill", "play.circle.fill"][i]
        let tint = [DS.success, DS.ListTint.bookmark, DS.fresh][i]
        let title = [Text("Lo que viste"), Text("Tu lista"), Text("Dónde ibas")][i]
        let detail = [Text("412 películas · 61 series"), Text("38 por ver"), Text("\(art.show(0).title) · T2 E3 · minuto 34")][i]
        return HStack(spacing: DS.Space.s2) {
            DSIconTile(symbol: symbol, tint: tint, side: DS.Lesson.rowIcon)
            VStack(alignment: .leading, spacing: DS.Lesson.tight) {
                title.font(DS.TextRecipe.cardTitle.font).foregroundStyle(DS.text)
                detail.font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.s2)
        .dsCard(translucent: true)
    }
}

/// Seguir en otro aparato: el iPhone se pausa en el minuto 34 (se oscurece), un punto turquesa viaja por el hilo y el iPad
/// se prende en el mismo cuadro.
struct LessonYoursHandoff: View {
    let t: Double
    let art: LessonArt
    static let end = 2.2
    private static let a = CGPoint(x: 100, y: 66), c = CGPoint(x: 150, y: 10), b = CGPoint(x: 214, y: 58)

    var body: some View {
        let M = LessonMotion.self
        let phone = M.enter(t, 0.05), pad = M.enter(t, 0.1), chip = M.spring(t - 1.3, 0.5, 0.2)
        let hop = M.smooth(0.75, 1.2, t), dot = M.quad(Self.a, Self.c, Self.b, hop)
        ZStack(alignment: .topLeading) {
            LessonThread(a: Self.a, c: Self.c, b: Self.b, drawn: M.smooth(0.7, 1.1, t), width: DS.Stroke.selected)
            Circle().fill(DS.fresh).sceneBox(10, 10)
                .scenePut(M.smooth(0.75, 0.8, t) * M.lerp(1, 0, M.smooth(1.15, 1.25, t)), dot.x - 5, dot.y - 5)
            LessonPhone(w: 92, h: 170) {
                LessonVideo(item: art.show(0), w: 76, h: 44, progress: 0.57, corner: DS.Radius.xs, showsBar: false).sceneAt(3, 50)
                    .opacity(M.lerp(1, DS.Opacity.dimmed, M.smooth(0.5, 0.7, t)))
                Image(systemName: "pause.fill").font(DS.TextRecipe.cardTitle.font).foregroundStyle(DS.paper)
                    .sceneWidth(82).sceneAt(0, 62).opacity(M.smooth(0.5, 0.7, t))
                Text(verbatim: "34:12").font(DS.TextRecipe.badge.font).monospacedDigit().foregroundStyle(DS.textMuted)
                    .sceneWidth(82).sceneAt(0, 102).opacity(M.smooth(0.5, 0.7, t))
            }
            .sceneAt(40, 70).scenePut(phone.o, 0, phone.y)
            LessonPhone(w: 190, h: 140, corner: DS.Lesson.padCorner) {
                LessonVideo(item: art.show(0), w: 168, h: 94, progress: 0.57 + 0.06 * M.smooth(1.3, 3.4, t), corner: DS.Radius.sm).sceneAt(6, 14)
                    .opacity(M.lerp(DS.Opacity.dimmed, 1, M.smooth(1.1, 1.35, t)))
            }
            .sceneAt(180, 60).scenePut(pad.o * M.lerp(0.55, 1, M.smooth(1.1, 1.35, t)), 0, pad.y)
            LessonCaption(text: Text("iPhone"), w: 92).sceneAt(40, 246).opacity(phone.o)
            LessonCaption(text: Text("iPad"), w: 190).sceneAt(180, 206).opacity(pad.o)
            LessonChip { Text("Sigue en el minuto \(Text(verbatim: "34").foregroundStyle(DS.fresh).bold())") }
                .sceneAt(196, 236).scenePut(M.clamp((t - 1.25) / 0.2), 0, (1 - chip) * 8)
        }
    }
}

/// Los episodios de una temporada en miniatura, con su círculo para marcar visto (y, en «Pruébalo», seguir la serie).
struct LessonEpisodes: View {
    let art: LessonArt
    var marked: Bool
    var tryMode = false
    var following = false
    var mark: (() -> Void)?
    var follow: ((Bool) -> Void)?
    /// Cómo aparece la palomita del episodio 3 al marcarlo (0 → 1): crece desde chica.
    var pop: Double = 1

    var body: some View {
        LessonCard(title: Text("\(art.show(0).title) · Temporada 2"), w: 358) {
            ForEach(0..<4, id: \.self) { i in
                let on = i < 2 || (i == 2 && marked), n = i + 1
                LessonRow(title: Text("Episodio \(n)"), detail: on ? Text("Visto") : Text(verbatim: "51 min")) { EmptyView() } trailing: {
                    Button { if i == 2 { mark?() } } label: {
                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                            .font(DS.TextRecipe.section.font).foregroundStyle(on ? DS.fresh : DS.textFaint)
                            .contentTransition(.symbolEffect(.replace))
                            .scaleEffect(i == 2 && on ? CGFloat(LessonMotion.lerp(0.6, 1, pop)) : 1)
                            .frame(minWidth: DS.Size.touchTarget, minHeight: DS.Size.touchTarget)
                            .overlay { if tryMode && i == 2 && !marked { LessonTryRing(round: true).padding(DS.Space.s1) } }
                    }
                    .buttonStyle(.plain)
                    .disabled(mark == nil || i != 2)
                    .accessibilityLabel(Text("Marcar visto el episodio \(n)"))
                    .accessibilityIdentifier("lesson-try-episode-\(n)")
                }
            }
            if tryMode {
                LessonRow(title: Text("Seguir la serie"), detail: following ? Text("Listo: te avisamos el día que salga") : Text("Te avisamos el día del estreno")) {
                    Image(systemName: "bell.fill").foregroundStyle(DS.fresh)
                } trailing: {
                    Toggle(isOn: Binding(get: { following }, set: { follow?($0) })) { Text("Seguir la serie") }
                        .labelsHidden()
                        .overlay { if tryMode && marked && !following { LessonTryRing(round: true).padding(-DS.Space.s1) } }
                        .accessibilityIdentifier("lesson-try-follow")
                }
            }
        }
    }
}

/// Marcar visto y calificar: el toque en el círculo del episodio 3 y, al marcarlo, las estrellas de tu calificación.
struct LessonYoursMark: View {
    let t: Double
    let art: LessonArt
    static let end = 2.4

    var body: some View {
        let M = LessonMotion.self
        let e = M.enter(t, 0.05, 14), rate = M.spring(t - 1.2, 0.5, 0.2)
        ZStack(alignment: .topLeading) {
            LessonEpisodes(art: art, marked: t > 0.9, pop: M.pop(t, 0.9)).sceneAt(22, 10).scenePut(e.o, 0, e.y)
            LessonChip {
                Text("Tu nota")
                HStack(spacing: DS.Space.s1) {
                    ForEach(0..<5, id: \.self) { i in
                        Image(systemName: t > 1.4 + Double(i) * 0.1 && i < 4 ? "star.fill" : "star").foregroundStyle(DS.warning)
                    }
                }
            }
            .sceneWidth(402).sceneAt(0, 268).scenePut(M.clamp((t - 1.15) / 0.2), 0, (1 - rate) * 8)
            LessonFinger(t: t, x: 342, y: 184, at: 0.9)
        }
    }
}

/// Los estrenos: la pantalla bloqueada con el aviso de hoy y, abajo, esta semana del calendario de Inicio (la de verdad,
/// con hoy marcado): el anillo turquesa une el aviso con su día.
struct LessonYoursAlert: View {
    let t: Double
    let art: LessonArt
    static let end = 2.0
    @Environment(\.locale) private var locale

    /// Los siete días de esta semana (empieza en lunes) y cuál es hoy.
    private var week: (days: [Date], today: Int) {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let now = Date(), start = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
        return (days, days.firstIndex { cal.isDate($0, inSameDayAs: now) } ?? 3)
    }

    var body: some View {
        let M = LessonMotion.self
        let note = M.spring(t - 0.45, 0.5, 0.12), cal = M.enter(t, 0.9), ring = M.pop(t, 1.3)
        let (days, today) = week, later = today < 5 ? today + 2 : today - 2
        ZStack(alignment: .topLeading) {
            Text(verbatim: "9:41").font(DS.TextRecipe.stat.font).foregroundStyle(DS.text)
                .sceneWidth(402).sceneAt(0, 8).opacity(M.clamp(t / 0.3))
            LessonNote(title: Text("Orbital · Sale hoy"), detail: Text("\(art.show(1).title) · Nuevo episodio, ya disponible"))
                .sceneAt(DS.Space.s6, 76).scenePut(M.clamp((t - 0.4) / 0.2), 0, (1 - note) * -60)
            HStack(alignment: .top, spacing: DS.Space.s2) {
                ForEach(0..<7, id: \.self) { i in
                    VStack(spacing: DS.Space.s1) {
                        Text(days[i].formatted(.dateTime.weekday(.narrow).locale(locale))).font(DS.TextRecipe.caption.font).foregroundStyle(DS.textMuted)
                        Text(days[i].formatted(.dateTime.day().locale(locale))).font(DS.TextRecipe.label.font)
                            .foregroundStyle(i == today ? DS.fresh : DS.text)
                            .sceneBox(30, 30)
                            .overlay(Circle().strokeBorder(DS.fresh, lineWidth: DS.Stroke.selected).scaleEffect(CGFloat(M.lerp(1.4, 1, ring))).opacity(i == today ? ring : 0))
                        if i == today || i == later {
                            LessonPoster(item: art.show(i == today ? 1 : 0), w: 40, h: 60, radius: DS.Radius.xs)
                        }
                    }
                    .sceneWidth(46)
                }
            }
            .sceneWidth(402).sceneAt(0, 176).scenePut(cal.o, 0, cal.y)
        }
    }
}

/// «Pruébalo»: marca el episodio 3 y sigue la serie. Nada se manda a Trakt.
struct LessonYoursTry: View {
    let t: Double
    let art: LessonArt
    let done: () -> Void
    @State private var marked = false
    @State private var following = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let e = LessonMotion.enter(t, 0.05, 14)
        ZStack(alignment: .topLeading) {
            LessonEpisodes(art: art, marked: marked, tryMode: true, following: following,
                           mark: { withAnimation(DS.Motion.spring(reduceMotion)) { marked = true }; if following { done() } },
                           follow: { on in withAnimation(DS.Motion.base(reduceMotion)) { following = on }; if on && marked { done() } })
                .sceneAt(22, 6).scenePut(e.o, 0, e.y)
        }
    }
}
