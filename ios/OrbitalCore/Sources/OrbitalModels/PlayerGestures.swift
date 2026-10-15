import Foundation
import OrbitalCore

/// El eje que ganó un arrastre en el reproductor. `undecided` mientras el dedo no se mueve lo suficiente (ahí
/// mandan el toque simple y el doble toque, que no pasan por aquí).
public enum GestureAxis: Sendable, Equatable { case undecided, horizontal, vertical }

/// Qué controla un arrastre vertical, según en qué mitad de la pantalla empezó (como Infuse).
public enum VerticalGesture: Sendable, Equatable { case brightness, volume }

/// La aritmética de los gestos del reproductor —brillo, volumen, buscar arrastrando, 2× manteniendo el dedo—,
/// sin UIKit ni SwiftUI: solo números, para poder probarla sin un reproductor de verdad. `PlayerScreen` traduce
/// los puntos de pantalla (`CGFloat`) a estos números (`Double`) y aplica el resultado al motor, a `UIScreen`
/// o al volumen del sistema; nunca al revés.
public enum PlayerGestures {
    /// Qué mitad de la pantalla decide brillo (izquierda) o volumen (derecha), por dónde empezó el dedo.
    public static func verticalGesture(startX: Double, screenWidth: Double) -> VerticalGesture {
        startX < screenWidth / 2 ? .brightness : .volume
    }

    /// El eje dominante de un arrastre, decidido una sola vez con el desplazamiento acumulado desde que empezó
    /// (antes de `DesignTokens.Gesture.axisThreshold` puntos no hay eje: el toque y el doble toque siguen mandando).
    public static func dominantAxis(dx: Double, dy: Double) -> GestureAxis {
        let distance = max(abs(dx), abs(dy))
        guard distance >= DesignTokens.Gesture.axisThreshold else { return .undecided }
        return abs(dx) >= abs(dy) ? .horizontal : .vertical
    }

    /// Segundos que vale arrastrar el ancho completo de la pantalla: un % de la duración o un tope fijo, lo que
    /// sea menor. Sin duración conocida (en vivo, o aún cargando) se usa el tope fijo.
    public static func seekLimitSeconds(duration: Double) -> Double {
        guard duration > 0 else { return DesignTokens.Gesture.seekMaxSeconds }
        return min(duration * DesignTokens.Gesture.seekMaxFraction, DesignTokens.Gesture.seekMaxSeconds)
    }

    /// A dónde saltaría el video si sueltas ahora (no se aplica hasta soltar: por eso la burbuja, y solo la burbuja,
    /// se mueve con el dedo).
    public static func seekTarget(startPosition: Double, duration: Double, dragWidth dx: Double, screenWidth: Double) -> Double {
        guard screenWidth > 0 else { return startPosition }
        let delta = (dx / screenWidth) * seekLimitSeconds(duration: duration)
        let target = startPosition + delta
        guard duration > 0 else { return max(0, target) }
        return max(0, min(target, duration))
    }

    /// Brillo o volumen (0…1): arrastrar toda la altura de la pantalla hacia arriba los pone al máximo; hacia
    /// abajo, al mínimo. Se parte siempre del valor que tenía al empezar el arrastre, no del centro de la pantalla.
    public static func verticalValue(start: Double, dragHeight dy: Double, screenHeight: Double) -> Double {
        guard screenHeight > 0 else { return start }
        return max(0, min(1, start - dy / screenHeight))
    }
}
