import SwiftUI
import OrbitalCore

/// P1 · P2-B · «Para ver aquí, conecta un servicio de nube» (Fernando, 18 nov 2026; prototipo `screens/cloud.js`): tres
/// pasos en una escena. Tú eliges (un dedo toca un póster en tu iPhone) → tu servicio la tiene (el póster sube en arco a la
/// nube, que se infla al recibirlo, y le brota su palomita) → aquí, al instante (baja en otro arco a tu pantalla, que se
/// enciende con el rayo y la barrita del reproductor avanza). Los arcos se dibujan delante del póster y luego quedan tenues.
/// Con «Reducir movimiento», quieta en su final.
struct GuideCloudScene: View {
    /// Cuatro pósters para el iPhone; el segundo es el que viaja.
    let posters: [(url: String?, title: String)]
    let start: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let size = CGSize(width: 402, height: 236), end = 3.2
    private static let s0 = CGPoint(x: 86, y: 101), c1 = CGPoint(x: 140, y: 14), k = CGPoint(x: 201, y: 112)
    private static let c2 = CGPoint(x: 272, y: 26), pl = CGPoint(x: 332, y: 120)
    private static let mini = CGSize(width: 28, height: 42)

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / Self.size.width
            TimelineView(.animation(minimumInterval: DS.Welcome.introFrame, paused: reduceMotion)) { ctx in
                let t = reduceMotion ? Self.end + 1 : ctx.date.timeIntervalSince(start)
                scene(t).frame(width: Self.size.width, height: Self.size.height).scaleEffect(scale, anchor: .topLeading)
            }
        }
        .aspectRatio(Self.size.width / Self.size.height, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(Text("Así funciona: eliges algo, tu servicio de nube lo tiene y lo ves aquí al instante"))
    }

    /// Una curva de Bézier cuadrática; pasado el final (el resorte se pasa un pelo) sigue derecho por la tangente.
    private static func quad(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, _ u: Double) -> CGPoint {
        if u <= 1 {
            let v = 1 - u
            return CGPoint(x: v * v * a.x + 2 * v * u * c.x + u * u * b.x, y: v * v * a.y + 2 * v * u * c.y + u * u * b.y)
        }
        let e = u - 1
        return CGPoint(x: b.x + (b.x - c.x) * 2 * e, y: b.y + (b.y - c.y) * 2 * e)
    }

    private func arc(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint) -> Path {
        Path { $0.move(to: a); $0.addQuadCurve(to: b, control: c) }
    }

    private func poster(_ i: Int) -> some View {
        let item = posters.indices.contains(i) ? posters[i] : nil
        return PosterView(url: item?.url, title: item?.title ?? "", aspect: nil, maxPoints: DS.Image.mosaic)   // no-es-título: ya pasó por titleName en la pantalla
    }

    @ViewBuilder private func scene(_ t: Double) -> some View {
        let M = GuideTraktScene.Motion.self
        let clamp = { (x: Double) in min(max(x, 0), 1) }
        let smooth = { (a: Double, b: Double, x: Double) -> Double in let c = clamp((x - a) / (b - a)); return c * c * (3 - 2 * c) }
        let pre = M.spring(t - 0.6, 0.3, 0), u1 = M.spring(t - 0.85, 0.85, 0.12), u2 = M.spring(t - 1.9, 0.85, 0.12)
        let k1 = clamp(u1), k2 = clamp(u2)
        let first = t < 1.9
        let pos = first ? Self.quad(Self.s0, Self.c1, Self.k, u1) : Self.quad(Self.k, Self.c2, Self.pl, u2)
        let flyScale = first ? (t < 0.85 ? 1 + 0.12 * pre : 1.12 + (0.8 - 1.12) * k1 + 0.2 * sin(.pi * k1)) : 0.8 + (1.15 - 0.8) * k2 + 0.18 * sin(.pi * k2)
        let flyTilt = first ? -6 * sin(2 * .pi * k1) * 0.6 : 6 * sin(2 * .pi * k2) * 0.6
        let lift = first ? max(sin(.pi * k1), 0.35 * pre * (1 - k1)) : sin(.pi * k2)
        let bump = { (a: Double, k: Double) in k * max(0, M.spring(t - a, 0.35, 0.4) - M.spring(t - a - 0.14, 0.35, 0.4)) }
        let arcOpacity = { (a: Double) -> Double in t < a ? 0 : t < a + 0.75 ? 0.55 : 0.55 + (0.16 - 0.55) * M.easeOut((t - a - 0.75) / 0.5) }
        let dash = StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [3, 5])
        let devices = [M.item(t, 0, 10), M.item(t, 0.06, 10), M.item(t, 0.12, 10)]
        ZStack(alignment: .topLeading) {
            // Los arcos: se dibujan delante del póster (un poco adelantados) y luego quedan tenues.
            arc(Self.s0, Self.c1, Self.k).trim(from: 0, to: clamp(k1 * 1.15)).stroke(DS.fresh, style: dash).opacity(arcOpacity(0.85))
            arc(Self.k, Self.c2, Self.pl).trim(from: 0, to: clamp(k2 * 1.15)).stroke(DS.fresh, style: dash).opacity(arcOpacity(1.9))
            // Tú eliges: tu iPhone con cuatro pósters; el dedo toca el segundo.
            phone(t).offset(x: 28, y: 60 + devices[0].rise).opacity(devices[0].opacity)
            // Tu servicio la tiene: la nube se infla al recibirlo y al soltarlo.
            cloud(t).scaleEffect(1 + bump(1.3, 0.09) + bump(1.88, 0.04))
                .offset(x: 141, y: 52 + devices[1].rise).opacity(devices[1].opacity)
            // Aquí, al instante: la pantalla se enciende.
            screen(t).offset(x: 284, y: 92 + devices[2].rise).opacity(devices[2].opacity)
            // El póster que viaja.
            poster(1).frame(width: Self.mini.width, height: Self.mini.height)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "checkmark").font(DS.styled(.caption2).weight(.heavy)).foregroundStyle(DS.onPrimary)
                        .frame(width: 20, height: 20).background(DS.success, in: Circle())
                        .overlay(Circle().stroke(DS.bg, lineWidth: 2.5))
                        .offset(x: 8, y: -8)
                        .scaleEffect(max(0, M.spring(t - 1.42, 0.55, 0.45)) * (1 - smooth(1.9, 2.05, t)))
                }
                .shadow(color: DS.scrimStrong.opacity(0.35 + lift * 0.25), radius: 4 + lift * 10, y: 3 + lift * 12)
                .scaleEffect(flyScale).rotationEffect(.degrees(flyTilt))
                .position(pos)
                .opacity(t < 0.6 ? 0 : 1 - smooth(0.72, 1, u2))
            // Los tres pasos, en palabras.
            label(Text("Tú eliges"), x: 70, t: t, delay: 0.28)
            label(Text("Tu servicio la tiene"), x: 201, t: t, delay: 0.33)
            label(Text("\(Image(systemName: "bolt.fill")) Aquí, al instante"), x: 332, t: t, delay: 0.38)
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
    }

    private func phone(_ t: Double) -> some View {
        let M = GuideTraktScene.Motion.self
        let tap = min(max((t - 0.55) / 0.45, 0), 1)
        let spots: [CGPoint] = [CGPoint(x: 12, y: 20), CGPoint(x: 44, y: 20), CGPoint(x: 12, y: 66), CGPoint(x: 44, y: 66)]
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DS.surface)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(DS.ink500, lineWidth: 2))
            RoundedRectangle(cornerRadius: 11, style: .continuous).fill(DS.bg).padding(5)
            Capsule().fill(DS.scrimStrong).frame(width: 24, height: 6).offset(x: 30, y: 9)
            ForEach(0..<4, id: \.self) { i in
                poster(i).frame(width: Self.mini.width, height: Self.mini.height)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous))
                    .offset(x: spots[i].x, y: spots[i].y)
            }
            RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(DS.fresh, lineWidth: 2)
                .frame(width: 32, height: 46).offset(x: 42, y: 18).opacity(M.easeOut((t - 0.6) / 0.2))
            Circle().fill(DS.text.opacity(0.5)).frame(width: 44, height: 44)
                .scaleEffect(0.35 + (1.4 - 0.35) * M.easeOut(tap)).opacity(t < 0.55 ? 0 : 0.55 * (1 - tap))
                .offset(x: 58 - 22, y: 41 - 22)
        }
        .frame(width: 84, height: 124, alignment: .topLeading)
    }

    private func cloud(_ t: Double) -> some View {
        let glow = (t > 1.3 && t < 1.9) ? sin(.pi * (t - 1.3) / 0.6) * 0.16 : 0
        return ZStack {
            Image(systemName: "cloud.fill").resizable().scaledToFit().foregroundStyle(DS.surfaceRaised)
            Image(systemName: "cloud").resizable().scaledToFit().foregroundStyle(DS.ink500)
            Image(systemName: "cloud.fill").resizable().scaledToFit().foregroundStyle(DS.fresh).opacity(glow)
        }
        .frame(width: 120, height: 99)
    }

    private func screen(_ t: Double) -> some View {
        let M = GuideTraktScene.Motion.self
        let arrive = M.spring(t - 2.3, 0.5, 0.25)
        let glow = (t > 2.28 && t < 2.88) ? sin(.pi * (t - 2.28) / 0.6) * 0.28 : 0
        let inner = RoundedRectangle(cornerRadius: 7, style: .continuous)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 11, style: .continuous).fill(DS.surface)
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(DS.ink500, lineWidth: 2))
            ZStack(alignment: .bottomLeading) {
                inner.fill(DS.bg)
                Image(systemName: "play.fill").foregroundStyle(DS.text).opacity(0.22 * (1 - M.easeOut((t - 2.2) / 0.2)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                PosterView(url: posters.indices.contains(1) ? posters[1].url : nil, title: posters.indices.contains(1) ? posters[1].title : "",
                           aspect: nil, bleed: true, maxPoints: DS.Image.mosaic)
                    .frame(width: 86, height: 46).clipped()
                    .scaleEffect(0.6 + 0.4 * arrive).opacity(M.easeOut((t - 2.26) / 0.2))
                Capsule().fill(DS.text.opacity(0.22)).frame(height: 2.5)
                    .overlay(alignment: .leading) {
                        GeometryReader { g in Capsule().fill(DS.fresh).frame(width: g.size.width * 0.22 * M.easeOut((t - 2.5) / 0.7)) }
                    }
                    .padding(.horizontal, 6).padding(.bottom, 5)
                inner.fill(DS.fresh).opacity(glow)
            }
            .frame(width: 86, height: 46).clipShape(inner).offset(x: 5, y: 5)
            Image(systemName: "bolt.fill").font(DS.styled(.caption).weight(.bold)).foregroundStyle(DS.onPrimary)
                .frame(width: 26, height: 26).background(DS.fresh, in: Circle()).overlay(Circle().stroke(DS.bg, lineWidth: 3))
                .scaleEffect(max(0, M.spring(t - 2.42, 0.55, 0.45)))
                .offset(x: 96 - 15, y: -11)
        }
        .frame(width: 96, height: 56, alignment: .topLeading)
    }

    private func label(_ text: Text, x: CGFloat, t: Double, delay: Double) -> some View {
        let item = GuideTraktScene.Motion.item(t, delay, 6)
        return text.font(DS.TextRecipe.caption.font).foregroundStyle(DS.textMuted).multilineTextAlignment(.center)
            .frame(width: 118).position(x: x, y: 198 + 18 + item.rise).opacity(item.opacity)
    }
}

/// El «Listo» de tu nube: arriba, la nube con su palomita (crece con un resorte pequeño); abajo, «Listas al instante» con
/// cuatro pósters en ola corta, y a cada uno le brota su rayo (0.62 s, uno tras otro). El texto va en medio, de la pantalla.
enum GuideCloudReady {
    static let end = 1.5

    static func badge(_ t: Double) -> some View {
        let M = GuideTraktScene.Motion.self
        let a = M.spring(t, 0.5, 0.25)
        return ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 28, style: .continuous).fill(DS.surfaceRaised).frame(width: 96, height: 96)
                .overlay(Image(systemName: "cloud.fill").font(DS.styled(.largeTitle)).foregroundStyle(DS.text))
            Image(systemName: "checkmark").font(DS.styled(.subheadline).weight(.heavy)).foregroundStyle(DS.onPrimary)
                .frame(width: 32, height: 32).background(DS.success, in: Circle()).overlay(Circle().stroke(DS.bg, lineWidth: 3))
                .offset(x: 6, y: 4).scaleEffect(max(0, M.spring(t - 0.28, 0.55, 0.45)))
        }
        .scaleEffect(0.72 + 0.28 * a).opacity(M.easeOut(t / 0.25))
        .accessibilityHidden(true)
    }

    static func row(_ posters: [(url: String?, title: String)], _ t: Double) -> some View {
        let M = GuideTraktScene.Motion.self
        let rl = M.item(t, 0.32, 8)
        return VStack(spacing: DS.Space.s3) {
            Text("\(Image(systemName: "bolt.fill")) Listas al instante").recipe(.label, color: DS.fresh)
                .opacity(rl.opacity).offset(y: rl.rise)
            HStack(spacing: DS.Space.s3) {
                ForEach(Array(posters.prefix(4).enumerated()), id: \.offset) { i, item in
                    let p = M.item(t, 0.36 + 0.06 * Double(i), 14)
                    PosterView(url: item.url, title: item.title, aspect: nil, maxPoints: DS.Image.mosaic)   // no-es-título: ya pasó por titleName en la pantalla
                        .frame(width: DS.Guide.readyPoster.width, height: DS.Guide.readyPoster.height)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: "bolt.fill").font(DS.styled(.caption2).weight(.bold)).foregroundStyle(DS.onPrimary)
                                .frame(width: 22, height: 22).background(DS.fresh, in: Circle()).overlay(Circle().stroke(DS.bg, lineWidth: 2.5))
                                .offset(x: 7, y: -7).scaleEffect(max(0, M.spring(t - 0.62 - 0.08 * Double(i), 0.55, 0.45)))
                        }
                        .opacity(p.opacity).offset(y: p.rise)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
