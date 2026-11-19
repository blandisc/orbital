import SwiftUI
import OrbitalCore

// Las escenas de la guía de bienvenida (revisión del director, Fernando, 4 nov 2026: «dale que sí con tus recomendaciones»;
// docs/producto/guia-aprende/guia-revision.html). Una sola cosa viva por pantalla y la luna como hilo que cruza de una a otra.

/// G7 · Tu Inicio en miniatura: lo que elegiste baja a sus filas («Porque te gustó…», «Nuevo en tus plataformas»), una pieza
/// tras otra. Al final, `grow` lo hace crecer a pantalla completa (se vuelve el Inicio de verdad).
struct GuideMiniHome: View {
    @Environment(\.titleName) var titleName
    let liked: [Suggestion]
    let more: [Suggestion]
    let logos: [String]
    var grow = false
    /// Si la primera fila puede decir «Porque te gustó…» (G4-B, 18 nov 2026); sin gustos elegidos, no.
    var chose = true
    @State private var landed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            HStack(spacing: DS.Space.s2) {
                OrbitalWordmark(size: DS.Size.headerWordmarkCompact, showsMark: false).foregroundStyle(DS.text)
                Spacer()
            }
            row(title: chose ? liked.first.map { Text("Porque te gustó \(titleName($0.title, id: $0.imdb, kind: $0.kind))") } ?? Text("Para ti") : Text("Para ti"),
                items: Array(liked.prefix(3)), delay: 0)
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                HStack(spacing: DS.Space.s2) {
                    (logos.isEmpty ? Text("Lo popular de ahora") : Text("Nuevo en tus plataformas")).recipe(.footnote, color: DS.eyebrow)
                    ForEach(logos.prefix(3), id: \.self) { DSPlatformLogo(url: $0).frame(maxWidth: DS.GuideScene.logo) }
                }
                posters(Array(more.prefix(3)), delay: 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)   // F: la tarjeta a todo lo ancho (ocupaba la mitad)
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
                PosterView(url: item.poster, title: titleName(item.title, id: item.imdb, kind: item.kind), maxPoints: DS.GuideScene.homePoster)
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
                    .keyframeAnimator(initialValue: Flight(), trigger: trigger) { [size = geo.size] moon, f in
                        moon.position(x: f.x * size.width, y: f.y * size.height).opacity(f.shown)
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
