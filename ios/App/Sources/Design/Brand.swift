import SwiftUI

/// La marca de Orbital, la misma de la TV (icons.js · mark): un planeta de contorno y un solo anillo que lo cruza por delante,
/// de abajo a la izquierda a arriba a la derecha. La luna no va aquí: es el punto de «orbital» (`OrbitalWordmark`) o, en el
/// ícono de la app, un punto aparte arriba a la derecha.
struct OrbitalMark: View {
    var size: CGFloat
    /// Al aparecer, el anillo se dibuja de una punta a la otra (como al arrancar la TV). Con «Reducir movimiento», quieto.
    var animated = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    var body: some View {
        let unit = size / DS.Brand.box
        ZStack {
            MarkPlanet().stroke(lineWidth: DS.Brand.planetStroke * unit)
            MarkRing().trim(from: 0, to: drawn || !animated || reduceMotion ? 1 : 0)
                .stroke(style: StrokeStyle(lineWidth: DS.Brand.ringStroke * unit, lineCap: .round))   // sólido (antes semitransparente)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task {
            guard animated, !reduceMotion, !drawn else { return }
            withAnimation(.easeOut(duration: DS.Brand.drawSeconds)) { drawn = true }
        }
    }
}

/// El planeta: un círculo centrado en la caja de 32.
struct MarkPlanet: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = rect.width / DS.Brand.box
        let r = DS.Brand.planetRadius * unit
        return Path(ellipseIn: CGRect(x: rect.midX - r, y: rect.midY - r, width: 2 * r, height: 2 * r))
    }
}

/// El anillo: «M3.2 20.4 c3.8 3.1 21.2-2.4 26-8.8» de la TV.
struct MarkRing: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = rect.width / DS.Brand.box
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * unit, y: rect.minY + y * unit) }
        var path = Path()
        path.move(to: point(3.2, 20.4))
        path.addCurve(to: point(29.2, 11.6), control1: point(7.0, 23.5), control2: point(24.4, 18.0))
        return path
    }
}

/// La marca con su nombre: el planeta, «orbital» en minúsculas y negrita, y la luna (turquesa, `DS.brandMoon`) como punto
/// arriba a la derecha de la palabra. Al aparecer (`animated`), el anillo se dibuja y luego la luna cae en su lugar con un resorte corto; tocarla le da
/// un saltito. Con «Reducir movimiento», quieta.
struct OrbitalWordmark: View {
    /// El tamaño de la letra de «orbital».
    var size: CGFloat
    var animated = false
    /// Sin el planeta: solo la palabra y su luna (en un iPhone angosto no cabe todo en la barra de Inicio).
    var showsMark = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var landed = false
    @State private var hops = 0

    var body: some View {
        let still = !animated || reduceMotion
        HStack(alignment: .center, spacing: size * DS.Brand.markGap) {
            if showsMark { OrbitalMark(size: size * DS.Brand.markScale, animated: animated) }
            HStack(alignment: .firstTextBaseline, spacing: size * DS.Brand.moonGap) {
                Text(verbatim: "orbital").font(DS.Brand.wordFont(size)).tracking(size * DS.Brand.tracking)
                // La luna, en el turquesa de la marca (como la barra de la TV y el ícono).
                Circle().fill(DS.brandMoon)
                    .frame(width: size * DS.Brand.moon, height: size * DS.Brand.moon)
                    .alignmentGuide(.firstTextBaseline) { $0.height + size * DS.Brand.moonRise }
                    .scaleEffect(still || landed ? 1 : DS.Brand.moonFromScale)
                    .offset(x: still || landed ? 0 : size * DS.Brand.moonFromX, y: still || landed ? 0 : size * DS.Brand.moonFromY)
                    .opacity(still || landed ? 1 : 0)
                    .keyframeAnimator(initialValue: CGFloat(0), trigger: hops) { moon, lift in moon.offset(y: lift) } keyframes: { _ in
                        SpringKeyframe(-size * DS.Brand.moon, duration: DS.Brand.drawSeconds / 3)
                        SpringKeyframe(0, duration: DS.Brand.drawSeconds / 2)
                    }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if !reduceMotion { hops += 1 } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Orbital"))
        .accessibilityAddTraits(.isHeader)
        .task {
            guard !still, !landed else { return }
            try? await Task.sleep(nanoseconds: UInt64(DS.Brand.moonDelay * 1e9))
            withAnimation(DS.Motion.spring(false)) { landed = true }
        }
    }
}

/// La entrada de la app (arranque en frío): sobre el fondo de la app, el anillo se dibuja sobre el planeta, las letras de
/// «orbital» suben una tras otra y la luna cae a su lugar con un rebote corto; luego el logotipo vuela y se encoge hasta
/// donde vive el de Inicio (arriba a la izquierda) mientras Inicio aparece debajo. Unos 1.4 s; si Inicio no está a la vista,
/// se desvanece en su lugar. Con «Reducir movimiento», todo quieto y un fundido. Los mismos tiempos que la TV y la computadora.
struct LaunchSplash: View {
    /// Dónde está el logotipo de Inicio en la pantalla (si se ve): ahí termina.
    let target: CGRect?
    let finished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false
    @State private var lettersUp = false
    @State private var moonIn = false
    @State private var leaving = false
    @State private var natural = CGRect.zero
    private let size = DS.Splash.wordSize

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let flies = target != nil && natural.width > 0 && !reduceMotion
            ZStack {
                DS.bg.opacity(leaving ? 0 : 1)
                wordmark
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { if !leaving { natural = $0 } }
                    .scaleEffect(leaving && flies ? (target?.width ?? natural.width) / natural.width : 1)
                    .offset(x: leaving && flies ? (target?.midX ?? 0) - center.x : 0, y: leaving && flies ? (target?.midY ?? 0) - center.y : 0)
                    .opacity(leaving && !flies ? 0 : 1)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(!leaving)
        .accessibilityHidden(true)
        .task { await run() }
    }

    private var wordmark: some View {
        let mark = size * DS.Brand.markScale, unit = mark / DS.Brand.box
        return HStack(alignment: .center, spacing: size * DS.Brand.markGap) {
            ZStack {
                MarkPlanet().stroke(lineWidth: DS.Brand.planetStroke * unit)
                MarkRing().trim(from: 0, to: drawn ? 1 : 0)
                    .stroke(style: StrokeStyle(lineWidth: DS.Brand.ringStroke * unit, lineCap: .round))
            }
            .frame(width: mark, height: mark)
            HStack(alignment: .firstTextBaseline, spacing: size * DS.Brand.moonGap) {
                HStack(spacing: size * DS.Brand.tracking) {
                    ForEach(Array("orbital".enumerated()), id: \.offset) { i, letter in
                        Text(verbatim: String(letter)).font(DS.Brand.wordFont(size))
                            .opacity(lettersUp ? 1 : 0)
                            .offset(y: lettersUp ? 0 : size * DS.Splash.letterRise)
                            .animation(reduceMotion ? nil : DS.Splash.letter.delay(Double(i) * DS.Splash.letterStagger), value: lettersUp)
                    }
                }
                Circle().fill(DS.brandMoon)
                    .frame(width: size * DS.Brand.moon, height: size * DS.Brand.moon)
                    .alignmentGuide(.firstTextBaseline) { $0.height + size * DS.Brand.moonRise }
                    .scaleEffect(moonIn ? 1 : DS.Brand.moonFromScale)
                    .offset(x: moonIn ? 0 : size * DS.Brand.moonFromX, y: moonIn ? 0 : size * DS.Brand.moonFromY)
                    .opacity(moonIn ? 1 : 0)
            }
        }
        .foregroundStyle(DS.text)
        .fixedSize()
    }

    private func run() async {
        if reduceMotion {
            drawn = true; lettersUp = true; moonIn = true
            try? await Task.sleep(for: .seconds(DS.Splash.still))
            withAnimation(.easeOut(duration: DS.Splash.fade)) { leaving = true }
            try? await Task.sleep(for: .seconds(DS.Splash.fade))
            return finished()
        }
        try? await Task.sleep(for: .seconds(DS.Splash.start))
        withAnimation(.easeOut(duration: DS.Splash.ring)) { drawn = true }
        lettersUp = true
        try? await Task.sleep(for: .seconds(DS.Splash.moonAt))
        withAnimation(DS.Splash.moon) { moonIn = true }
        try? await Task.sleep(for: .seconds(DS.Splash.leaveAt))
        withAnimation(DS.Splash.leave) { leaving = true }
        try? await Task.sleep(for: .seconds(DS.Splash.leaveSeconds))
        finished()
    }
}
