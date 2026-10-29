import SwiftUI
import UIKit
import CoreImage
import OrbitalCore
import OrbitalModels

// Las piezas del catálogo de Orbital para iPhone. Una pantalla se arma con estas; si falta una, se agrega aquí.
// Equivalencias con la TV: Chip, Badge, Progress, SectionHead, Card (PosterCard), FeatureTile (HeroCard), Mosaic (`Design/Mosaic.swift` ↔ `foryou-mosaic`), Button, Sheet.


/// Lo que se ve sobre el video: indicador de gesto, cargando, burbuja de búsqueda, píldora de velocidad y píldora de aviso.
/// El indicador de brillo o volumen sobre el video, como en Infuse: un ícono y una barra fina que sube o baja
/// con el valor, sobre vidrio nativo. Una sola pieza para los dos gestos (cambia el ícono y el valor).
struct DSGestureIndicator: View {
    let symbol: String
    let value: Double   // 0…1
    /// El largo de la barra: más corta cuando el video es bajito (en vertical va dentro de la imagen).
    var barHeight: CGFloat = DS.Gesture.indicatorBarHeight

    /// Mínimo: el ícono y una barra delgada, sin panel ni porcentaje. Una sombra suave lo separa de una imagen clara.
    var body: some View {
        VStack(spacing: DS.Space.s2) {
            Image(systemName: symbol).font(DS.TextRecipe.footnote.font).foregroundStyle(DS.text)
            ZStack(alignment: .bottom) {
                Capsule().fill(DS.track)
                Capsule().fill(DS.text).frame(height: barHeight * min(1, max(0, value)))
            }
            .frame(width: DS.Gesture.indicatorBarWidth, height: barHeight)
        }
        .shadow(DS.Elevation.medium)
        .accessibilityHidden(true)
    }
}

/// La única animación de carga del reproductor (abrir, buscar versión, volver a la app, llenar el búfer): una órbita delgada con una
/// luna turquesa que la recorre con su estela, la marca de Orbital sin textos. Con «Reducir movimiento», la luna late en su lugar.
struct DSLoader: View {
    var size: CGFloat = DS.Loader.size
    /// La órbita tenue de fondo; dentro del botón grande no va (la orilla del botón ya es la órbita).
    var showsTrack = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let turn = reduceMotion ? 0.75 : t.truncatingRemainder(dividingBy: DS.Loader.seconds) / DS.Loader.seconds
            let angle = turn * 2 * .pi
            let radius = size / 2
            let trail = DS.Loader.trail
            ZStack {
                if showsTrack { Circle().stroke(DS.track, lineWidth: DS.Loader.ringWidth) }
                Circle().trim(from: 0, to: trail)
                    .stroke(AngularGradient(colors: [.clear, DS.brandMoon.opacity(DS.Loader.trailOpacity)], center: .center,
                                            startAngle: .zero, endAngle: .degrees(360 * Double(trail))),
                            style: StrokeStyle(lineWidth: DS.Loader.trailWidth, lineCap: .round))
                    .rotationEffect(.radians(angle) - .degrees(360 * Double(trail)))   // la punta de la estela, justo en la luna
                Circle().fill(DS.brandMoon)
                    .frame(width: DS.Loader.moon, height: DS.Loader.moon)
                    .shadow(color: DS.brandMoon, radius: DS.Loader.moonGlow)
                    .opacity(reduceMotion ? 0.55 + 0.45 * abs(sin(t * .pi / DS.Loader.seconds)) : 1)
                    .offset(x: radius * cos(angle), y: radius * sin(angle))
            }
            .frame(width: size, height: size)
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Cargando"))
    }
}

/// La burbuja de «buscar arrastrando»: el tiempo destino grande y la diferencia pequeña («+1:20»).
struct DSSeekBubble: View {
    let time: String
    let delta: String

    var body: some View {
        VStack(spacing: DS.Space.s1) {
            Text(time).font(DS.TextRecipe.section.font.weight(.bold)).foregroundStyle(DS.text).monospacedDigit()
            Text(delta).font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted).monospacedDigit()
        }
        .padding(.horizontal, DS.Space.s5).padding(.vertical, DS.Space.s3)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
        .accessibilityHidden(true)
    }
}

/// La píldora «2×» mientras mantienes el dedo (como YouTube/Infuse): sobre vidrio, abajo al centro.
struct DSSpeedPill: View {
    /// Se quedó fijo en ×2 (deslizaste hacia abajo hasta que vibró): dice cómo quitarlo.
    var locked = false
    /// Mientras mantienes: el anillo se llena al deslizar hacia abajo (0…1).
    var progress: Double = 0
    /// El dedo sigue puesto: dice qué hace deslizar.
    var holding = false
    /// Ya iba fijo al apoyar el dedo: deslizar hacia arriba lo quita.
    var unlocks = false
    var body: some View {
        HStack(spacing: DS.Space.s2) {
            if locked && !holding {
                Image(systemName: "lock.fill").font(DS.TextRecipe.footnote.font.weight(.bold)).transition(.scale.combined(with: .opacity))
            } else {
                ZStack {
                    Circle().stroke(DS.track, lineWidth: DS.PlayerPanel.ringWidth)
                    Circle().trim(from: 0, to: progress).stroke(DS.text, style: StrokeStyle(lineWidth: DS.PlayerPanel.ringWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: DS.PlayerPanel.ring * 0.75, height: DS.PlayerPanel.ring * 0.75)
            }
            Text(verbatim: "2×").font(DS.TextRecipe.secondary.font.weight(.bold))
            if holding {
                (Text(Image(systemName: unlocks ? "arrow.up" : "arrow.down")) + Text(" ")
                    + (unlocks ? Text("Desliza para quitar") : Text("Desliza para fijar")))
                    .font(DS.TextRecipe.footnote.font)
            } else if locked {
                Text("Toca para quitar").font(DS.TextRecipe.footnote.font)
            }
        }
        .foregroundStyle(DS.text)
        .padding(.horizontal, DS.Space.s4).padding(.vertical, DS.Space.s2)
        .glassEffect(.regular, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(locked ? "speed-pill-locked" : "speed-pill")
    }
}

/// Un aviso breve en una cápsula de vidrio (p. ej. el modo de zoom del reproductor al cambiarlo).
/// `detail`: un segundo renglón más tenue (p. ej. por qué está ahí esa versión de subtítulos).
struct DSToastPill: View {
    let text: LocalizedStringKey
    var detail: Text? = nil
    var body: some View {
        VStack(spacing: 0) {
            Text(text).font(DS.TextRecipe.secondary.font.weight(.semibold)).foregroundStyle(DS.text).contentTransition(.numericText())
            if let detail { detail.recipe(.caption).lineLimit(1) }
        }
            .padding(.horizontal, DS.Space.s4).padding(.vertical, DS.Space.s2)
            .glassEffect(.regular, in: Capsule())
    }
}
