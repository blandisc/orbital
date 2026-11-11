import Foundation

/// Un nombre escrito en otro alfabeto (cirílico, griego, árabe, hebreo, chino, japonés, coreano, tailandés…) cuando la app
/// está en español o inglés. Revisión 2 del 11 nov: en Buscar salía «Бархан» entre las Dunas. No se esconde (puede ser
/// justo lo que buscas), pero va después de lo que se lee en tu idioma.
public enum OtherScript {
    public static func isOther(_ text: String) -> Bool {
        var latin = 0, other = 0
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            switch scalar.value {
            case 0x0041...0x024F, 0x1E00...0x1EFF: latin += 1
            default: other += 1
            }
        }
        return other > latin
    }

    /// Lo que se lee en tu alfabeto primero, sin cambiar el orden dentro de cada grupo.
    public static func readableFirst<T>(_ items: [T], name: (T) -> String) -> [T] {
        items.filter { !isOther(name($0)) } + items.filter { isOther(name($0)) }
    }
}
