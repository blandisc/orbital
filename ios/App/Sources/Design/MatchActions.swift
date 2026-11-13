import SwiftUI
import Observation

// Los botones del mazo de «Una por una» con vida (pulido 2 de DE2, 13 nov 2026: «Pon un toque de color… una animación, una
// interacción»): se encienden del color de su sello mientras arrastras la carta hacia su lado, y su símbolo da un saltito
// cuando la carta sale por ellos (con el botón o con el dedo).

/// Hacia dónde va la carta de arriba y cuánto (0…1, 1 es el umbral en que ya sale volando). Lo escribe el mazo con cada
/// movimiento del dedo y lo leen solo los botones: un objeto aparte para que no se vuelva a pintar toda la pantalla.
@MainActor
@Observable
final class MatchPull {
    private(set) var toward: MatchCommand?
    private(set) var amount: Double = 0

    func set(_ toward: MatchCommand?, _ amount: Double) {
        let clamped = toward == nil ? 0 : min(1, max(0, amount))
        if self.toward != toward { self.toward = toward }
        if self.amount != clamped { self.amount = clamped }
    }

    /// Cuánto se enciende el botón de `command` (0 si la carta va hacia otro lado).
    func lit(_ command: MatchCommand?) -> Double { command != nil && toward == command ? amount : 0 }
}

/// Un botón del mazo (Paso · Para hoy · Guardar · Ver): un círculo de `DSIconButton` del color de su sello que se enciende
/// (se llena un poco de su color y crece tantito) mientras la carta va hacia su lado, y cuyo símbolo salta (`kick`) cuando la
/// carta sale por él. «Ver» (`command` nil) no se enciende.
struct MatchActionButton: View {
    let command: MatchCommand?
    let symbol: String
    let label: LocalizedStringKey
    let tint: Color
    let pull: MatchPull
    var kick = 0
    let action: () -> Void

    var body: some View {
        let lit = pull.lit(command)
        DSIconButton(symbol: symbol, label: label, size: .large, steady: true, kick: kick, action: action)
            .foregroundStyle(tint)
            .background { Circle().fill(tint.opacity(DS.MatchLive.litFill * lit)).allowsHitTesting(false) }
            .scaleEffect(1 + DS.MatchLive.litGrow * lit)
    }
}

/// Lo que se toca entero (un cartel de «Tres que caben») se hunde tantito al apretarlo, en cuanto lo tocas.
struct DSPressStyle: ButtonStyle {   // ds-exception: el hundido de un cartel que se toca entero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? DS.DecideLive.pressed : 1)
            .animation(DS.Motion.press, value: configuration.isPressed)
    }
}
