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

    /// Cuánto más ancho que la imagen puede ser el marco antes de dejar de recortarla (1.25: un póster 2:3 en un marco de 0.83
    /// o más ancho ya no se recorta).
    public static let narrowLimit = 1.25

    public static func choose(image: CGSize, box: CGSize, limit: Double = narrowLimit) -> ArtFit {
        guard image.width > 0, image.height > 0, box.width > 0, box.height > 0 else { return .fill }
        let imageAspect = image.width / image.height, boxAspect = box.width / box.height
        return boxAspect / imageAspect > limit ? .whole : .fill
    }
}
