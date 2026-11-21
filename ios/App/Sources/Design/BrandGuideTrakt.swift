import SwiftUI
import OrbitalModels

/// TK-V2 (Fernando, 18 nov 2026; prototipo en `docs/producto/guia-trabajos-2026-11-18/onboarding/screens/trakt.js`): tu
/// serie viaja de un aparato al otro. La tarjeta aparece en el iPhone, se despega, sigue un arco inclinándose hacia donde
/// va, se pasa un pelo y se asienta en el otro aparato (iPad; la TV en Ultra; la Mac si estás en el iPad), que destella
/// turquesa al recibirla. El arco se dibuja un paso delante de ella y luego queda tenue. Es una función pura del tiempo:
/// con «Reducir movimiento» se pinta el final, quieto.
struct GuideTraktScene: View {
    enum Receiver { case iPad, tv, mac }
    let receiver: Receiver
    /// En la de la tienda no se reproduce: la tarjeta dice «vista» y no lleva barra.
    let watches: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    static let size = CGSize(width: 360, height: 280)
    static let end = 2.8

    var body: some View {
        GeometryReader { geo in
            let scale = min(1, geo.size.width / Self.size.width)
            TimelineView(.animation(minimumInterval: DS.Welcome.introFrame, paused: reduceMotion)) { ctx in
                let t = reduceMotion ? Self.end + 1 : ctx.date.timeIntervalSince(start)
                frame(min(t, Self.end + 1))
            }
            .frame(width: Self.size.width, height: Self.size.height)
            .scaleEffect(scale, anchor: .top)
            .frame(width: geo.size.width, height: Self.size.height * scale, alignment: .top)
        }
        .frame(height: Self.size.height)
        .accessibilityHidden(true)
        .onAppear { start = Date() }
    }

    // MARK: la geometría (puntos del lienzo de 360 × 280)

    private var left: CGRect { CGRect(x: 14, y: 62, width: 96, height: 196) }
    private var right: CGRect {
        switch receiver {
        case .tv: CGRect(x: 174, y: 80, width: 178, height: 104)
        case .mac: CGRect(x: 188, y: 92, width: 156, height: 100)
        case .iPad: CGRect(x: 186, y: 92, width: 160, height: 116)
        }
    }
    private var dockL: (p: CGPoint, s: CGFloat) { (CGPoint(x: left.midX, y: left.maxY - 62), 0.56) }
    private var dockR: (p: CGPoint, s: CGFloat) {
        switch receiver {
        case .tv: (CGPoint(x: right.midX, y: right.midY + 10), 0.86)
        case .mac: (CGPoint(x: right.midX, y: right.midY + 8), 0.8)
        case .iPad: (CGPoint(x: right.midX, y: right.midY + 12), 0.8)
        }
    }
    private var control: CGPoint {
        CGPoint(x: (dockL.p.x + dockR.p.x) / 2 - 6, y: min(dockL.p.y, dockR.p.y) - 150)
    }

    private func arc() -> Path {
        var path = Path(); path.move(to: dockL.p); path.addQuadCurve(to: dockR.p, control: control); return path
    }

    @ViewBuilder private func frame(_ t: Double) -> some View {
        let devL = Motion.item(t, 0, 10), devR = Motion.item(t, 0.08, 10)
        let appear = Motion.spring(t - 0.5, 0.45, 0.2), lift = Motion.spring(t - 0.88, 0.3, 0)
        let u = Motion.spring(t - 1.02, 0.95, 0.12), uc = min(max(u, 0), 1)
        let pos = point(u)
        let cardScale = t < 1.02 ? dockL.s * (0.85 + 0.15 * appear) * (1 + 0.08 * lift)
            : dockL.s * 1.08 + (dockR.s - dockL.s * 1.08) * uc + 0.34 * sin(.pi * uc)
        let cardLift = max(sin(.pi * uc), 0.3 * lift * (1 - uc))
        let reveal = min(max(uc * 1.18 + (t > 0.95 ? 0.04 : 0), 0), 1)
        let arcOpacity = t < 0.95 ? 0 : t < 1.85 ? 0.6 : 0.6 + (0.18 - 0.6) * Motion.easeOut((t - 1.85) / 0.6)
        let glow = (t > 1.68 && t < 2.28) ? sin(.pi * (t - 1.68) / 0.6) * 0.22 : 0
        ZStack(alignment: .topLeading) {
            GuideDevice(kind: .phone, rect: left).opacity(devL.opacity).offset(y: devL.rise)
            GuideDevice(kind: receiver == .tv ? .tv : receiver == .mac ? .mac : .tablet, rect: right, glow: glow)
                .opacity(devR.opacity).offset(y: devR.rise)
            arc().trim(from: 0, to: reveal)
                .stroke(DS.brandMoon, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [3, 5]))
                .opacity(arcOpacity)
            GuideShowCard(watches: watches, lift: cardLift)
                .scaleEffect(cardScale)
                .rotationEffect(.degrees(-5 * sin(2 * .pi * uc)))
                .position(pos)
                .opacity(min(max((t - 0.5) / 0.22, 0), 1))
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
    }

    /// Dónde va la tarjeta: sobre el arco mientras `u` ≤ 1; si el resorte se pasa, sigue la tangente un pelo y regresa.
    private func point(_ u: Double) -> CGPoint {
        let a = dockL.p, c = control, b = dockR.p
        if u <= 1 {
            let v = 1 - u
            return CGPoint(x: v * v * a.x + 2 * v * u * c.x + u * u * b.x, y: v * v * a.y + 2 * v * u * c.y + u * u * b.y)
        }
        let e = u - 1
        return CGPoint(x: b.x + (b.x - c.x) * 2 * e, y: b.y + (b.y - c.y) * 2 * e)
    }

    /// Las curvas del prototipo: el resorte de SwiftUI escrito como función del tiempo (respuesta y rebote) y la entrada
    /// estándar (aparece en 0.42 s y sube con un resorte sin rebote).
    enum Motion {
        static func spring(_ t: Double, _ response: Double, _ bounce: Double) -> Double {
            guard t > 0 else { return 0 }
            let w = 2 * .pi / response, z = 1 - bounce
            if z >= 1 { return 1 - exp(-w * t) * (1 + w * t) }
            let wd = w * sqrt(1 - z * z)
            return 1 - exp(-z * w * t) * (cos(wd * t) + (z * w / wd) * sin(wd * t))
        }
        static func easeOut(_ x: Double) -> Double { let c = min(max(x, 0), 1); return 1 - pow(1 - c, 3) }
        static func item(_ t: Double, _ start: Double, _ rise: CGFloat) -> (opacity: Double, rise: CGFloat) {
            (easeOut((t - start) / 0.42), rise * CGFloat(1 - spring(t - start, 0.55, 0)))
        }
    }
}

/// Un aparato dibujado con línea: su contorno, la pantalla oscura con unas rayitas de contenido y, al recibir, un destello.
struct GuideDevice: View {
    enum Kind { case phone, tablet, tv, mac }
    let kind: Kind
    let rect: CGRect
    var glow: Double = 0

    var body: some View {
        let outer: CGFloat = kind == .phone ? 18 : kind == .tablet ? 13 : kind == .tv ? 7 : 8
        let inset: CGFloat = kind == .phone ? 5 : 6
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: outer, style: .continuous).fill(DS.surface).strokeBorder(DS.textMuted.opacity(0.45), lineWidth: 2)   // ds-exception: dibujo de la escena de la guía
            RoundedRectangle(cornerRadius: max(outer - inset, 3), style: .continuous)
                .fill(LinearGradient(colors: [DS.surfaceRaised, DS.surface], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: max(outer - inset, 3), style: .continuous).fill(DS.brandMoon.opacity(glow)))
                .padding(inset)
            VStack(alignment: .leading, spacing: 7) {
                ForEach(0..<(kind == .phone ? 5 : 3), id: \.self) { i in
                    Capsule().fill(DS.text.opacity(0.09)).frame(width: (rect.width - 32) * (i % 2 == 1 ? 0.62 : 0.85), height: 4)   // ds-exception: dibujo de la escena de la guía
                }
            }
            .padding(.top, kind == .phone ? 30 : 18).padding(.leading, 16)
            if kind == .phone {
                Capsule().fill(.black).frame(width: 26, height: 7).frame(maxWidth: .infinity).padding(.top, 9)   // ds-exception: dibujo de la escena de la guía
            }
        }
        .frame(width: rect.width, height: rect.height)
        .overlay(alignment: .bottom) {
            if kind == .tv {
                Capsule().fill(DS.textMuted.opacity(0.45)).frame(width: 60, height: 4).offset(y: 17)   // ds-exception: dibujo de la escena de la guía
            } else if kind == .mac {
                Capsule().fill(DS.textMuted.opacity(0.45)).frame(width: rect.width + 32, height: 8).offset(y: 9)   // ds-exception: dibujo de la escena de la guía
            }
        }
        .position(x: rect.midX, y: rect.midY)
    }
}

/// La tarjeta que viaja (ilustración): un póster, «Shōgun» y dónde te quedaste, con su barrita turquesa. La sombra crece
/// mientras va en el aire (`lift`).
struct GuideShowCard: View {
    let watches: Bool
    var lift: Double = 0

    var body: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(LinearGradient(colors: [DS.ListTint.calendar, DS.surface], startPoint: .top, endPoint: .bottom))
                .overlay(Circle().fill(DS.danger.opacity(0.8)).frame(width: 14).offset(y: -4))   // ds-exception: dibujo de la escena de la guía
                .frame(width: 28, height: 42)   // ds-exception: dibujo de la escena de la guía
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "Shōgun").font(DS.styled(.subheadline).weight(.semibold)).foregroundStyle(DS.text)
                if watches {
                    Text("T1 E7 · quedan 18 min").font(DS.styled(.caption)).foregroundStyle(DS.textMuted).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
                    Capsule().fill(DS.text.opacity(0.14)).frame(height: 3)   // ds-exception: dibujo de la escena de la guía
                        .overlay(alignment: .leading) { GeometryReader { g in Capsule().fill(DS.brandMoon).frame(width: g.size.width * 0.62) } }
                        .padding(.top, 4)
                } else {
                    Text("\(Text(Image(systemName: "checkmark")).foregroundStyle(DS.brandMoon)) \(Text("T1 E7 · vista"))")
                        .font(DS.styled(.caption)).foregroundStyle(DS.textMuted).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
                }
            }
        }
        .padding(EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 10))
        .frame(width: 168, height: 54, alignment: .leading)   // ds-exception: dibujo de la escena de la guía
        .background(DS.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.35 + lift * 0.25), radius: 5 + lift * 13, y: 4 + lift * 16)   // ds-exception: dibujo de la escena de la guía
    }
}

/// TK-L2: tu inicial en el anillo de la marca, la palomita, «Listo, <nombre>» y tres números que cuentan a la vez (sin que
/// bailen: cifras de ancho fijo). Una cuenta nueva dice «Tu Trakt está listo» y no enseña ceros. Mientras se trae lo tuyo,
/// los números esperan en gris.
struct TraktRecognized: View {
    let name: String?
    let brought: OnboardingModel.Brought?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var avatar = false
    @State private var badge = false
    @State private var text = false
    @State private var counted = false

    var body: some View {
        let fresh = brought?.isEmpty == true
        VStack(spacing: DS.Space.s4) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(AngularGradient(colors: [DS.brandMoon, DS.ListTint.library, DS.ListTint.calendar, DS.brandMoon], center: .center, angle: .degrees(210)))
                    .overlay(Circle().fill(DS.surfaceRaised).padding(3))   // ds-exception: dibujo de la escena de la guía
                    .overlay(Text(verbatim: String((name ?? "T").prefix(1)).uppercased()).font(DS.styled(.largeTitle).weight(.semibold)).foregroundStyle(DS.text))
                    .frame(width: DS.Guide.avatar, height: DS.Guide.avatar)
                Image(systemName: "checkmark").font(DS.styled(.subheadline).weight(.heavy)).foregroundStyle(DS.onPrimary)
                    .frame(width: DS.Guide.avatarBadge, height: DS.Guide.avatarBadge)
                    .background(DS.brandMoon, in: Circle())
                    .overlay(Circle().strokeBorder(DS.bg, lineWidth: 3))
                    .scaleEffect(badge ? 1 : 0.01)
            }
            .scaleEffect(avatar ? 1 : 0.72).opacity(avatar ? 1 : 0)
            VStack(spacing: DS.Space.s2) {
                (fresh ? Text("Tu Trakt está listo") : name.map { Text("Listo, \($0)") } ?? Text("Listo"))
                    .recipe(.display, color: DS.text)
                (fresh ? Text("Lo que veas se guarda aquí, en todos tus aparatos.") : Text("Tu Trakt ya está conectado."))
                    .font(DS.Welcome.lead).foregroundStyle(DS.textMuted)
            }
            .multilineTextAlignment(.center)
            .opacity(text ? 1 : 0).offset(y: text ? 0 : DS.Welcome.rise)
            if !fresh {
                HStack(spacing: 0) {
                    count(brought?.watched, Text("vistas"))
                    Divider().frame(height: DS.Guide.countDivider)
                    count(brought?.listed, Text("en Mi lista"))
                    Divider().frame(height: DS.Guide.countDivider)
                    count(brought?.shows, Text("series que sigues"))
                }
                .padding(.top, DS.Space.s4)
                .opacity(text ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DS.Space.s8)
        .task {
            if reduceMotion { avatar = true; badge = true; text = true; counted = true; return }
            withAnimation(DS.Guide.avatarIn) { avatar = true }
            try? await Task.sleep(for: DS.Guide.textAfterAvatar)
            withAnimation(DS.Motion.enter(reduceMotion)) { text = true }
            try? await Task.sleep(for: DS.Guide.badgeAfterText)
            withAnimation(DS.Guide.badgePop) { badge = true }
            try? await Task.sleep(for: DS.Guide.countAfterBadge)
            withAnimation(DS.Guide.countUp) { counted = true }
        }
    }

    private func count(_ value: Int?, _ label: Text) -> some View {
        VStack(spacing: DS.Space.s1) {
            if let value {
                Text(counted ? value : 0, format: .number)
                    .font(DS.styled(.title).weight(.semibold)).monospacedDigit().foregroundStyle(DS.text)
                    .contentTransition(.numericText(value: Double(counted ? value : 0)))
            } else {
                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous).fill(DS.fill).frame(width: 44, height: 30)   // ds-exception: espacio del número mientras llega
            }
            label.recipe(.caption, color: DS.textMuted).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
