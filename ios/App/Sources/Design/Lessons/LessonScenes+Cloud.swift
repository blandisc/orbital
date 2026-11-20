import SwiftUI
import OrbitalAddons

// «Tu nube» (prototipo `scenes.js`, n-play … n-try): el gancho, qué es la nube, «Por pedir», lo que cuesta, una cuenta por
// persona y «Pruébalo». Cada escena es pura en `t` (segundos desde que entra); las medidas son del lienzo de 402 × 330.

/// El gancho: la ficha (póster y «Ver»); el dedo toca «Ver» y ese mismo marco crece hasta ser el video (un objeto que se
/// transforma, no dos que se cruzan); luego, qué versión eligió, apoyado en la orilla del video.
struct LessonCloudPlay: View {
    let t: Double
    let art: LessonArt
    static let end = 2.2
    private static let poster = CGRect(x: 131, y: 20, width: 140, height: 210), video = CGRect(x: 26, y: 56, width: 350, height: 197)

    var body: some View {
        let M = LessonMotion.self
        let film = art.movie(0)
        let e = M.enter(t, 0.05, 14), k = M.clamp(M.spring(t - 0.75, 0.5, 0))
        let r = CGRect(x: M.lerp(Self.poster.minX, Self.video.minX, k), y: M.lerp(Self.poster.minY, Self.video.minY, k),
                       width: M.lerp(Self.poster.width, Self.video.width, k), height: M.lerp(Self.poster.height, Self.video.height, k))
        let chip = M.enter(t, 1.2, 8)
        ZStack(alignment: .topLeading) {
            ZStack {
                LessonVideo(item: film, w: r.width, h: r.height, progress: 0.08 + 0.3 * M.smooth(1.2, 2.2, t),
                            showsBar: k > 0.9).opacity(M.smooth(0.85, 1.1, t))
                LessonPoster(item: film, w: r.width, h: r.height).opacity(M.lerp(1, 0, M.smooth(0.85, 1.1, t)))
            }
            .sceneBox(r.width, r.height).sceneAt(r.minX, r.minY).scenePut(e.o, 0, e.y)
            LessonPlayButton(title: Text("Ver"), symbol: "play.fill").sceneBox(140, 40).sceneAt(131, 248)
                .scenePut(e.o * (1 - M.smooth(0.75, 0.95, t)), 0, e.y)
            LessonChip { Text.flagMark("es-MX"); Text("Latino · 1080p ·"); LessonReadiness(state: .instant) }
                .sceneWidth(402).sceneAt(0, 266).scenePut(chip.o, 0, chip.y)
            LessonFinger(t: t, x: 201, y: 268, at: 0.6)
        }
    }
}

/// Qué es la nube, dibujado: tu iPhone, la nube con copias adentro y el hilo turquesa por el que una baja a tu pantalla.
struct LessonCloudWhat: View {
    let t: Double
    let art: LessonArt
    @Environment(\.locale) private var locale
    static let end = 1.5
    private static let from = CGPoint(x: 262, y: 120), via = CGPoint(x: 186, y: 34), to = CGPoint(x: 112, y: 166)

    var body: some View {
        let M = LessonMotion.self
        let phone = M.enter(t, 0.05), cloud = M.enter(t, 0.1)
        let k = M.smooth(0.55, 1.05, t), fly = M.quad(Self.from, Self.via, Self.to, k)
        ZStack(alignment: .topLeading) {
            LessonThread(a: Self.from, c: Self.via, b: Self.to, drawn: M.smooth(0.3, 0.7, t))
            LessonPhone(w: 100, h: 180) {
                ZStack {
                    DS.video.opacity(DS.Opacity.faint)
                    LessonVideo(item: art.movie(0), w: 80, h: 52, corner: DS.Radius.xs, showsBar: false).opacity(M.smooth(1.0, 1.2, t))
                }
                .sceneBox(80, 52).clipShape(RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous)).sceneAt(5, 41)
            }
            .sceneAt(62, 120).scenePut(phone.o, 0, phone.y)
            ZStack(alignment: .topLeading) {
                Image(systemName: "cloud.fill").resizable().scaledToFit().foregroundStyle(DS.surfaceRaised).sceneBox(170, 120)
                Image(systemName: "cloud").resizable().scaledToFit().fontWeight(.ultraLight).foregroundStyle(DS.fresh).sceneBox(170, 120)
                LessonPoster(item: art.movie(1), w: 34, h: 51).sceneAt(34, 48)
                LessonPoster(item: art.movie(0), w: 34, h: 51).sceneAt(68, 40).opacity(k > 0.02 ? DS.Opacity.faint : 1)
                LessonPoster(item: art.show(0), w: 34, h: 51).sceneAt(102, 50)
            }
            .sceneAt(200, 92).scenePut(cloud.o, 0, cloud.y)
            LessonPoster(item: art.movie(0), w: 34, h: 51)
                .scenePut(t < 0.55 || t > 1.1 ? 0 : 1, fly.x - 17, fly.y - 25, M.lerp(1, 0.6, k))
            LessonCaption(text: Text("Tu iPhone"), w: 120).sceneAt(52, 306).opacity(M.clamp((t - 0.3) / 0.3))
            LessonCaption(text: Text("Tu nube (Real-Debrid)", cloud: art.cloud, locale: locale), w: 170).sceneAt(200, 216)   // edición: la lección de la nube solo sale con instantStreams
                .opacity(M.clamp((t - 0.3) / 0.3))
        }
    }
}

/// La hoja de Versión en miniatura: tres versiones de la película; la de Castellano está «Por pedir» y se puede pedir.
struct LessonVersionCard: View {
    let art: LessonArt
    /// 0 sin pedir, de 0 a 1 mientras baja, y lista al pasar de 1.
    let asked: Double
    var tryMe = false
    var ask: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let state: LessonReadiness.State = asked > 1 ? .ready : asked > 0 ? .progress(Int(asked * 100)) : .request
        LessonCard(title: Text("Versión · \(art.movie(0).title)"), w: 358) {
            LessonRow(title: Text("Latino"), detail: Text(verbatim: "1080p · 5.1")) { flag("es-MX") } trailing: { LessonReadiness(state: .instant) }
            LessonRow(title: Text("Inglés"), detail: Text(verbatim: "4K · Dolby Vision")) { flag("en-US") } trailing: { LessonReadiness(state: .instant) }
            Button { ask?() } label: {
                LessonRow(title: Text("Castellano"),
                          detail: asked > 1 ? Text("1080p · lista para ver") : asked > 0 ? Text("Pidiendo a tu nube…") : Text(verbatim: "1080p")) {
                    flag("es-ES")
                } trailing: { LessonReadiness(state: state) }
                .overlay(alignment: .bottom) {
                    if asked > 0 && asked <= 1 { LessonProgress(value: asked, tint: DS.fresh).padding(.horizontal, DS.Space.s4).padding(.bottom, DS.Space.s1) }
                }
                .overlay { if tryMe && asked == 0 { LessonTryRing() } }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // Sin `.disabled`: lo apagaría en gris, y es el renglón protagonista (en la demo y mientras corre el porcentaje).
            .allowsHitTesting(ask != nil && asked == 0)
            .accessibilityLabel(Text("Pedir la versión en castellano"))
            .accessibilityIdentifier("lesson-try-ask")
        }
    }

    private func flag(_ code: String) -> some View { (Text.flagMark(code) ?? Text(verbatim: "")).font(DS.TextRecipe.cardTitle.font) }
}

/// Lo que más confunde, en su lugar real: el dedo toca «Por pedir», corre el porcentaje y cae el aviso de que ya está.
struct LessonCloudAsk: View {
    let t: Double
    let art: LessonArt
    static let end = 2.2

    var body: some View {
        let M = LessonMotion.self
        let card = M.enter(t, 0.05, 14), p = M.smooth(0.7, 1.5, t), note = M.spring(t - 1.6, 0.5, 0.12)
        ZStack(alignment: .topLeading) {
            LessonVersionCard(art: art, asked: t > 1.55 ? 1.01 : p).sceneAt(22, 84).scenePut(card.o, 0, card.y)
            LessonNote(title: Text(verbatim: "Orbital"), detail: Text("Castellano ya está en tu nube: \(art.movie(0).title)"))
                .sceneAt(DS.Space.s6, 10).scenePut(M.clamp((t - 1.55) / 0.2), 0, (1 - note) * -70)
            LessonFinger(t: t, x: 328, y: 258, at: 0.6)
        }
    }
}

/// Lo que cuesta, sin letra chica: los tres planes de Real-Debrid (el de 15 días marcado: el que conviene para probar) y el
/// aviso que manda Orbital antes de que se acabe. Con otra nube, sin precios (cada una tiene los suyos): solo el aviso.
struct LessonCloudPrice: View {
    let t: Double
    let art: LessonArt
    @Environment(\.locale) private var locale
    static let end = 2.2
    private static let plans: [(LocalizedStringKey, String, String)] = [("15 días", "3 €", "≈ $60"), ("30 días", "4 €", "≈ $80"), ("90 días", "9 €", "≈ $180")]

    var body: some View {
        let M = LessonMotion.self
        let note = M.spring(t - 0.8, 0.5, 0.12)
        ZStack(alignment: .topLeading) {
            if art.cloud == .realDebrid {
                ForEach(Self.plans.indices, id: \.self) { i in
                    let e = M.enter(t, 0.05 + Double(i) * 0.05 - (i == 2 ? 0.02 : 0), CGFloat(16 - i * 3))
                    plan(Self.plans[i].0, Self.plans[i].1, Self.plans[i].2, first: i == 0).sceneAt(CGFloat(29 + i * 120), 112).scenePut(e.o, 0, e.y)
                }
                LessonCaption(text: Text("Precios aproximados de real-debrid.com, en pesos mexicanos"), w: 402).sceneAt(0, 262).opacity(M.clamp((t - 0.4) / 0.3))
            } else {
                let e = M.enter(t, 0.05, 16)
                VStack(spacing: DS.Space.s2) {
                    Image(systemName: "creditcard").font(DS.TextRecipe.display.font).foregroundStyle(DS.fresh)
                    Text("Se paga en su página").font(DS.TextRecipe.cardTitle.font).foregroundStyle(DS.text)
                }
                .sceneBox(402, 160).sceneAt(0, 110).scenePut(e.o, 0, e.y)
            }
            LessonNote(title: Text(verbatim: "Orbital"), detail: Text("Te quedan 3 días de Real-Debrid · Renovar", cloud: art.cloud, locale: locale), symbol: "cloud.fill")   // edición: la lección de la nube solo sale con instantStreams
                .sceneAt(DS.Space.s6, 10).scenePut(M.clamp((t - 0.75) / 0.2), 0, (1 - note) * -70)
        }
    }

    private func plan(_ days: LocalizedStringKey, _ price: String, _ pesos: String, first: Bool) -> some View {
        VStack(spacing: DS.Space.s1) {
            Text(days).font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted)
            Text(verbatim: price).font(DS.TextRecipe.title.font).monospacedDigit().foregroundStyle(DS.text)
            Text(verbatim: pesos).font(DS.TextRecipe.footnote.font).monospacedDigit().foregroundStyle(DS.textMuted)
            if first { Text("para probar").font(DS.TextRecipe.footnote.font).foregroundStyle(DS.fresh) }
        }
        .sceneBox(104, 132)
        .dsCard(fill: first ? DS.fresh.opacity(DS.Opacity.selectedFill) : DS.surfaceRaised)
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
            .strokeBorder(first ? DS.fresh : DS.hairline, lineWidth: first ? DS.Stroke.selected : DS.Stroke.hairline))
    }
}

/// Por qué se corta: tu cuenta (arriba, con su hilo a cada iPhone) en dos aparatos a la vez. El tuyo sigue; el otro se
/// oscurece y se detiene con el mensaje que de verdad sale en la app.
struct LessonCloudOne: View {
    let t: Double
    let art: LessonArt
    static let end = 2.0

    var body: some View {
        let M = LessonMotion.self
        let key = M.enter(t, 0.05, 8), cut = M.smooth(1.3, 1.55, t)
        ZStack(alignment: .topLeading) {
            LessonThread(a: CGPoint(x: 186, y: 30), c: CGPoint(x: 130, y: 34), b: CGPoint(x: 113, y: 66), drawn: M.smooth(0.3, 0.7, t))
            LessonThread(a: CGPoint(x: 216, y: 30), c: CGPoint(x: 272, y: 34), b: CGPoint(x: 289, y: 66), drawn: M.smooth(0.3, 0.7, t))
            LessonChip { Image(systemName: "key.fill").foregroundStyle(DS.fresh); Text("Tu cuenta") }
                .sceneWidth(402).sceneAt(0, 8).scenePut(key.o, 0, key.y)
            ForEach(0..<2, id: \.self) { i in
                let e = M.enter(t, 0.1 + Double(i) * 0.06)
                LessonPhone(w: 118, h: 196) {
                    LessonVideo(item: i == 0 ? art.movie(0) : art.show(0), w: 108, h: 61,
                                progress: i == 0 ? 0.2 + 0.3 * M.smooth(0.3, 2.6, t) : 0.4 + 0.12 * M.smooth(0.3, 1.3, min(t, 1.3)), corner: 0)
                        .opacity(i == 1 ? M.lerp(1, DS.Opacity.dimmed, cut) : 1)
                        .sceneAt(0, 50)
                    if i == 1 {
                        VStack(spacing: DS.Space.s1) {
                            Image(systemName: "pause.circle.fill").font(DS.TextRecipe.cardTitle.font)
                            Text("Se cortó: tu cuenta está en otro aparato").fixedSize(horizontal: false, vertical: true)
                        }
                        .font(DS.TextRecipe.caption.font).foregroundStyle(DS.danger).multilineTextAlignment(.center)
                            .sceneWidth(100).sceneAt(4, 112)
                            .scenePut(M.clamp((t - 1.3) / 0.25), 0, (1 - M.easeOut((t - 1.3) / 0.4)) * 6)
                    }
                }
                .sceneAt(CGFloat(54 + i * 176), 66).scenePut(e.o, 0, e.y)
            }
            LessonCaption(text: Text("Tú"), w: 118).sceneAt(54, 270).opacity(M.clamp((t - 0.3) / 0.3))
            LessonCaption(text: Text("Tu primo, con tu cuenta"), w: 140).sceneAt(219, 270).opacity(M.clamp((t - 0.3) / 0.3))
        }
    }
}

/// «Pruébalo»: la misma hoja de Versión, de verdad. Tocar «Por pedir» corre el porcentaje y llega el aviso. Nada se pide.
struct LessonCloudTry: View {
    let t: Double
    let art: LessonArt
    let done: () -> Void
    @State private var askedAt: Double?

    var body: some View {
        let M = LessonMotion.self
        let card = M.enter(t, 0.05, 14)
        let s = askedAt.map { t - $0 } ?? -1
        let p = s < 0 ? 0 : s > 1.05 ? 1.01 : M.smooth(0, 1.0, s)
        let note = M.spring(s - 1.05, 0.5, 0.12)
        ZStack(alignment: .topLeading) {
            LessonVersionCard(art: art, asked: p, tryMe: true, ask: { askedAt = t })
                .sceneAt(22, 84).scenePut(card.o, 0, card.y)
            LessonNote(title: Text(verbatim: "Orbital"), detail: Text("Castellano ya está en tu nube (de práctica)"))
                .sceneAt(DS.Space.s6, 10).scenePut(s > 1.0 ? 1 : 0, 0, (1 - note) * -70)
                .accessibilityHidden(s < 1.0)
        }
        .onChange(of: s > 1.1) { _, arrived in if arrived { done() } }
    }
}
