import Foundation
import OrbitalAddons

/// Un texto para la pantalla armado como **clave del catálogo + datos** (F10, 11 nov 2026). El catálogo de la app está en
/// español y la clave es el texto mismo («No pude conectar con Trakt: %@»), así que la app lo traduce directo, sin tener que
/// reconocer un texto ya armado por su forma. `description` es el texto en español, el de siempre.
public struct UserText: Sendable, Equatable, CustomStringConvertible {
    public enum Arg: Sendable, Equatable {
        /// Un dato que puede ser, a su vez, otro texto armado en español (la app lo traduce si lo reconoce).
        case text(String)
        /// Un número para `%lld`.
        case number(Int)
        /// Otro texto con su propia clave.
        case nested(UserText)
    }
    public let key: String
    public let args: [Arg]
    public init(_ key: String, _ args: Arg...) { self.key = key; self.args = args }

    public var description: String {
        guard !args.isEmpty else { return key }
        return String(format: key, arguments: args.map { arg -> CVarArg in
            switch arg {
            case .text(let s): s
            case .number(let n): n
            case .nested(let t): t.description
            }
        })
    }
}

/// Un error que sabe cómo decirse en la pantalla (las familias: red, Trakt, Real-Debrid, descargas).
public protocol UserFacingError: Error, CustomStringConvertible {
    var userText: UserText { get }
}

public extension UserFacingError {
    var description: String { userText.description }
}

// MARK: las familias

extension NetworkError: UserFacingError {
    /// Lo que dice viene de muchos lados (el sistema, un servicio): se traduce si es un texto del catálogo.
    public var userText: UserText { UserText(description) }
}

extension TraktError: UserFacingError {
    public var userText: UserText {
        switch self {
        case .network(let reason): UserText("No pude conectar con Trakt: %@", .text(reason))
        case .http(let status): UserText("Trakt respondió HTTP %lld", .number(status))
        case .invalid(let m), .auth(let m): UserText(m)
        }
    }
}

extension DownloadError: UserFacingError {
    public var userText: UserText {
        switch self {
        case .notEnoughSpace(let needed, let free):
            UserText("Hacen falta %@ MB y hay %@ MB libres.", .text("\(needed / 1_000_000)"), .text("\(free / 1_000_000)"))
        case .alreadyDownloaded: UserText("Ya está descargado.")
        case .noURL: UserText("Esta versión no tiene un enlace para descargar.")
        case .unsafePath: UserText("El nombre de este título no sirve para guardarlo.")
        }
    }
}

extension CinemetaError: UserFacingError {
    /// Revisión del 11 nov 2026: ya no se traduce reconociendo «No pude leer el catálogo: …» por su forma.
    public var userText: UserText {
        switch self {
        case .network(let reason): UserText("No pude leer el catálogo: %@", .text(reason))
        case .unexpected: UserText("Respuesta inesperada de Cinemeta")
        case .notFound: UserText("Título no encontrado")
        }
    }
}

extension DebridError: UserFacingError {
    /// Todos son textos fijos (la causa técnica de `.network` no se enseña).
    public var userText: UserText { UserText(description) }
}
