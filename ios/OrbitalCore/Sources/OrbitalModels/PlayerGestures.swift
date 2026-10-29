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

    /// Brillo o volumen (0…1): arrastrar `travel` puntos hacia arriba los pone al máximo; hacia abajo, al mínimo. Se parte
    /// siempre del valor que tenía al empezar el arrastre, no del centro de la pantalla. `travel` lo decide la pantalla
    /// (`verticalTravel`): antes era toda la altura del teléfono y en vertical, con el video de 220 puntos, recorrerlo entero
    /// subía «un pedacito».
    public static func verticalValue(start: Double, dragHeight dy: Double, travel: Double) -> Double {
        guard travel > 0 else { return start }
        return max(0, min(1, start - dy / travel))
    }

    /// Cuánto hay que arrastrar para ir de 0 a 1: el alto del video, y nunca más que `share` de la pantalla (en horizontal el
    /// video es la pantalla entera y recorrerla toda era demasiado). Nunca menos de `minimum`, para que un roce no lo dispare.
    public static func verticalTravel(videoHeight: Double, screenHeight: Double, share: Double, minimum: Double) -> Double {
        max(minimum, min(videoHeight, screenHeight * share))
    }

    /// Cuánto hay que deslizar hacia abajo, desde donde apoyaste el dedo, para fijar el ×2. Si hasta el borde
    /// de abajo queda menos que `preferred`, se usa ese hueco, pero nunca menos de `minimum`.
    public static func fastForwardLockDistance(roomBelow: Double, preferred: Double, minimum: Double) -> Double {
        max(minimum, min(preferred, roomBelow))
    }
}
