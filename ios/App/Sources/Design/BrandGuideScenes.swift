import SwiftUI
import OrbitalCore

// Las escenas de la guía de bienvenida (revisión del director, Fernando, 4 nov 2026: «dale que sí con tus recomendaciones»;
// docs/producto/guia-aprende/guia-revision.html). Una sola cosa viva por pantalla y la luna como hilo que cruza de una a otra.

/// G2 · Tu órbita: un planeta chico con su anillo; lo que eliges entra en órbita como una miniatura que llega volando. Con tres,
/// el anillo se cierra y llega la luna (`onClosed`, para el toque en la mano). Con «Reducir movimiento», todo en su lugar.
struct GuideOrbit: View {
    let picked: [Suggestion]
    var needed = 3
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var closed: Bool { picked.count >= needed }

    var body: some View {
        ZStack {
            // El anillo se va cerrando con cada elegido.
            Ellipse().trim(from: 0, to: min(1, Double(picked.count) / Double(needed)))
                .stroke(closed ? DS.text : DS.textMuted, style: StrokeStyle(lineWidth: DS.Stroke.selected, lineCap: .round))
                .frame(width: DS.GuideScene.orbitWidth, height: DS.GuideScene.orbitHeight)
                .rotationEffect(.degrees(DS.Welcome.tilt))
            Ellipse().stroke(DS.fill, lineWidth: DS.Stroke.regular)
                .frame(width: DS.GuideScene.orbitWidth, height: DS.GuideScene.orbitHeight)
                .rotationEffect(.degrees(DS.Welcome.tilt))
            MarkPlanet().frame(width: DS.GuideScene.planet, height: DS.GuideScene.planet).foregroundStyle(DS.text)
            ForEach(Array(picked.prefix(DS.Welcome.posters).enumerated()), id: \.element.imdb) { i, item in
                PosterView(url: item.poster, title: item.title, maxPoints: DS.GuideScene.mini)
                    .frame(height: DS.GuideScene.mini)
                    .offset(slot(i))
                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .offset(y: DS.Welcome.fallFrom / 2).combined(with: .scale(scale: DS.Scene.lifted * DS.Scene.lifted)).combined(with: .opacity),
                                                                      removal: .offset(y: -DS.Welcome.fallFrom / 3).combined(with: .opacity)))
            }
            Circle().fill(DS.brandMoon).frame(width: DS.Welcome.moon, height: DS.Welcome.moon)
                .offset(x: DS.GuideScene.orbitWidth / 2, y: -DS.GuideScene.orbitHeight / 2)
                .scaleEffect(closed ? 1 : 0)
        }
        .frame(height: DS.GuideScene.orbitHeight + DS.GuideScene.mini * 1.4)
        .animation(DS.Motion.spring(reduceMotion), value: picked.map(\.imdb))
        .animation(DS.Motion.pop(reduceMotion), value: closed)
        .accessibilityElement()
        .accessibilityLabel(Text("\(String(picked.count)) en tu órbita"))
    }

    /// El lugar de cada miniatura en la elipse inclinada (como el anillo de la marca).
    private func slot(_ i: Int) -> CGSize {
        let angle = Double.pi * (0.9 + 1.3 * Double(i) / Double(max(DS.Welcome.posters - 1, 1)))
        let a = DS.GuideScene.orbitWidth / 2, b = DS.GuideScene.orbitHeight / 2
        let x = a * cos(angle), y = b * sin(angle), t = DS.Welcome.tilt * .pi / 180
        return CGSize(width: x * cos(t) - y * sin(t), height: x * sin(t) + y * cos(t))
    }
}

/// G7 · Tu Inicio en miniatura: lo que elegiste baja a sus filas («Porque te gustó…», «Nuevo en tus plataformas»), una pieza
/// tras otra. Al final, `grow` lo hace crecer a pantalla completa (se vuelve el Inicio de verdad).
struct GuideMiniHome: View {
    let liked: [Suggestion]
    let more: [Suggestion]
    let logos: [String]
    var grow = false
    @State private var landed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            HStack(spacing: DS.Space.s2) {
                OrbitalWordmark(size: DS.Size.headerWordmarkCompact, showsMark: false).foregroundStyle(DS.text)
                Spacer()
            }
            row(title: liked.first.map { Text("Porque te gustó \($0.title)") } ?? Text("Para ti"), items: Array(liked.prefix(3)), delay: 0)
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                HStack(spacing: DS.Space.s2) {
                    Text("Nuevo en tus plataformas").recipe(.footnote, color: DS.eyebrow)
                    ForEach(logos.prefix(3), id: \.self) { DSPlatformLogo(url: $0).frame(maxWidth: DS.GuideScene.logo) }
                }
                posters(Array(more.prefix(3)), delay: 3)
            }
        }
        .padding(DS.Space.s4)
        .dsCard(.card)
        .scaleEffect(grow && !reduceMotion ? DS.GuideScene.grow : 1)
        .opacity(grow ? 0 : 1)
        .task { landed = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Tu Inicio, armado con lo que te gusta"))
    }

    private func row(title: Text, items: [Suggestion], delay: Int) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            title.recipe(.footnote, color: DS.eyebrow).lineLimit(1)
            posters(items, delay: delay)
        }
    }

    private func posters(_ items: [Suggestion], delay: Int) -> some View {
        HStack(spacing: DS.Space.s2) {
            ForEach(Array(items.enumerated()), id: \.element.imdb) { i, item in
                PosterView(url: item.poster, title: item.title, maxPoints: DS.GuideScene.homePoster)
                    .frame(height: DS.GuideScene.homePoster)
                    .offset(y: landed || reduceMotion ? 0 : -DS.Welcome.fallFrom / 3)
                    .opacity(landed || reduceMotion ? 1 : 0)
                    .animation(DS.Motion.spring(reduceMotion)?.delay(Double(delay + i) * DS.GuideScene.landStep), value: landed)
            }
        }
    }
}

/// El hilo de la guía: al pasar a otra pantalla, la luna sale de abajo (del botón), viaja en curva hasta su marca del arco y
/// se queda ahí. Una sola cosa cruza de pantalla en pantalla. Con «Reducir movimiento», no viaja.
struct GuideMoonFlight: View {
    /// Cambia en cada paso (dispara el vuelo).
    let trigger: Int
    /// Dónde termina, en fracción del ancho (la marca del arco).
    let to: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            if !reduceMotion, trigger > 0 {
                Circle().fill(DS.brandMoon).frame(width: DS.OrbitArc.moon, height: DS.OrbitArc.moon)
                    .keyframeAnimator(initialValue: Flight(), trigger: trigger) { moon, f in
                        moon.position(x: f.x * geo.size.width, y: f.y * geo.size.height).opacity(f.shown)
                    } keyframes: { _ in
                        KeyframeTrack(\.x) { CubicKeyframe(0.5, duration: 0.01); CubicKeyframe(to, duration: DS.GuideScene.flight) }
                        KeyframeTrack(\.y) { CubicKeyframe(0.92, duration: 0.01); CubicKeyframe(0.02, duration: DS.GuideScene.flight) }   // ds-exception: de abajo (el botón) al arco
                        KeyframeTrack(\.shown) { LinearKeyframe(1, duration: DS.GuideScene.flight); LinearKeyframe(0, duration: DS.GuideScene.fadeOut) }
                    }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    struct Flight { var x = 0.5, y = 0.92, shown = 0.0 }
}

/// G3 · Lo que tienes, como objetos de línea: una nube (Real-Debrid), dos aparatos unidos por un hilo (Trakt) y una TV. Encendido,
/// la nube se llena, el hilo se dibuja de punta a punta y la pantalla de la TV prende.
struct GuideHaveObject: View {
    enum Kind { case cloud, thread, tv }
    let kind: Kind
    let on: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch kind {
            case .cloud:
                Image(systemName: on ? "cloud.fill" : "cloud").font(.system(size: DS.GuideScene.object, weight: .light))   // ds-exception: un dibujo, no texto
                    .foregroundStyle(on ? DS.fresh : DS.text)
                    .contentTransition(.symbolEffect(.replace))
            case .thread:
                HStack(spacing: 0) {
                    Image(systemName: "iphone").font(.system(size: DS.GuideScene.object / 2, weight: .light))   // ds-exception: un dibujo, no texto
                    Capsule().fill(DS.fill).frame(height: DS.Stroke.selected).overlay(alignment: .leading) {
                        GeometryReader { geo in Capsule().fill(DS.fresh).frame(width: on ? geo.size.width : 0) }
                    }
                    .frame(width: DS.GuideScene.object / 2)
                    Image(systemName: "ipad").font(.system(size: DS.GuideScene.object / 2, weight: .light))   // ds-exception: un dibujo, no texto
                }
                .foregroundStyle(DS.text)
            case .tv:
                Image(systemName: on ? "tv.fill" : "tv").font(.system(size: DS.GuideScene.object, weight: .light))   // ds-exception: un dibujo, no texto
                    .foregroundStyle(on ? DS.fresh : DS.text)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .frame(height: DS.GuideScene.object * 1.2)
        .scaleEffect(on ? DS.Scene.lifted : 1)
        .animation(DS.Motion.pop(reduceMotion), value: on)
        .accessibilityHidden(true)
    }
}
