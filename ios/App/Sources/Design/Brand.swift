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
                .stroke(style: StrokeStyle(lineWidth: DS.Brand.ringStroke * unit, lineCap: .round))
                .opacity(DS.Brand.ringOpacity)
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

/// La marca con su nombre: el planeta, «orbital» en minúsculas y negrita, y la luna como punto arriba a la derecha de la
/// palabra. Al aparecer (`animated`), el anillo se dibuja y luego la luna cae en su lugar con un resorte corto; tocarla le da
/// un saltito. Con «Reducir movimiento», quieta.
struct OrbitalWordmark: View {
    /// El tamaño de la letra de «orbital».
    var size: CGFloat
    var animated = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var landed = false
    @State private var hops = 0

    var body: some View {
        let still = !animated || reduceMotion
        HStack(alignment: .center, spacing: size * DS.Brand.markGap) {
            OrbitalMark(size: size * DS.Brand.markScale, animated: animated)
            HStack(alignment: .firstTextBaseline, spacing: size * DS.Brand.moonGap) {
                Text(verbatim: "orbital").font(.system(size: size, weight: .bold, design: .rounded)).tracking(size * DS.Brand.tracking)
                Circle()
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
