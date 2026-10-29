import Foundation

/// Cómo cabe una imagen en su marco. Llenar y recortar al centro sirve si la imagen y el marco tienen casi la misma forma; un
/// póster vertical dentro de un marco ancho (la ficha sin fondo, «Seguir viendo», una tarjeta de la TV) solo dejaba ver una tira
/// del medio: una cara partida o el título del póster a la mitad. Entonces la imagen va completa sobre una copia suya difuminada,
/// como el fondo del Inicio en la TV (`backdrop__layer--poster`). Solo aritmética: la vista decide con esto.
public enum ArtFit: Equatable, Sendable {
    /// Llena el marco y se recorta.
    case fill
    /// Completa, sobre su copia difuminada.
    case whole

    /// Cuánto más ancho que la imagen puede ser el marco antes de dejar de recortarla (1.4: un póster 2:3 llena la portada de la
    /// ficha, 0.9, perdiendo un poco de arriba y de abajo; en un marco de 0.93 o más ancho ya va completo).
    public static let narrowLimit = 1.4
    /// Un marco es alto (y pide un póster sin texto antes que un fondo 16:9, `TallArt`) si su ancho entre su alto es menor que esto.
    public static let tallBelow = 1.0
    /// Desde cuánto recorte (la parte de la imagen que queda fuera, en un eje) vale buscar al sujeto: menos, se recorta al centro.
    public static let focusFrom = 0.15

    public static func choose(image: CGSize, box: CGSize, limit: Double = narrowLimit) -> ArtFit {
        guard image.width > 0, image.height > 0, box.width > 0, box.height > 0 else { return .fill }
        let imageAspect = image.width / image.height, boxAspect = box.width / box.height
        return boxAspect / imageAspect > limit ? .whole : .fill
    }

    /// El tamaño al que se dibuja la imagen para llenar el marco (lo que sobra se recorta).
    public static func filled(image: CGSize, box: CGSize) -> CGSize {
        guard image.width > 0, image.height > 0 else { return box }
        let scale = max(box.width / image.width, box.height / image.height)
        return CGSize(width: image.width * scale, height: image.height * scale)
    }

    /// Si el recorte se come tanto que conviene mover la imagen hacia el sujeto (`focusFrom`).
    public static func needsFocus(image: CGSize, box: CGSize) -> Bool {
        let drawn = filled(image: image, box: box)
        guard drawn.width > 0, drawn.height > 0 else { return false }
        return (drawn.width - box.width) / drawn.width > focusFrom || (drawn.height - box.height) / drawn.height > focusFrom
    }

    /// Cuánto mover la imagen ya llena para que el sujeto (`focus`, 0…1 desde arriba a la izquierda) quede lo más al centro
    /// posible sin dejar huecos en el marco.
    public static func offset(image: CGSize, box: CGSize, focus: CGPoint) -> CGSize {
        let drawn = filled(image: image, box: box)
        func shift(_ size: Double, _ room: Double, _ at: Double) -> Double {
            let spare = max(0, size - room) / 2
            return min(spare, max(-spare, (0.5 - at) * size))
        }
        return CGSize(width: shift(drawn.width, box.width, focus.x), height: shift(drawn.height, box.height, focus.y))
    }
}
