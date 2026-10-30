import XCTest
@testable import OrbitalCore

final class UserMessagesTests: XCTestCase {
    func testTechnicalTextBecomesAPlainSentence() {
        XCTAssertEqual(UserMessages.humanize("No pude cambiar tu lista de Stremio: HTTP 503"),
                       "No pude cambiar tu lista de Stremio. El servicio no contesta ahora; intenta en un rato.", "un 5xx no es tu internet")
        XCTAssertEqual(UserMessages.humanize("No pude cambiar tu lista de Stremio: The network connection was lost."),
                       "No pude cambiar tu lista de Stremio. Revisa tu conexión e intenta de nuevo.")
        XCTAssertEqual(UserMessages.humanize("No pude cambiar tus favoritos de Trakt: HTTP 401"),
                       "No pude cambiar tus favoritos de Trakt. Tu sesión se cerró: vuelve a conectar la cuenta en Ajustes.")
        XCTAssertEqual(UserMessages.humanize("HTTP 502"), "El servicio no contesta ahora. Intenta en un rato.")
        XCTAssertEqual(UserMessages.humanize("No pude guardar el archivo: The file couldn’t be saved because there isn’t enough space."),
                       "Se llenó el iPhone. Libera espacio y toca Reintentar.")
        XCTAssertEqual(UserMessages.humanize("The Internet connection appears to be offline."), "Sin conexión. Revisa tu internet e intenta de nuevo.")
        XCTAssertEqual(UserMessages.humanize("Error Domain=NSURLErrorDomain Code=-1001"), "Sin conexión. Revisa tu internet e intenta de nuevo.")
        XCTAssertEqual(UserMessages.humanize("User not found"), "Ese correo no tiene cuenta de Stremio.")
        XCTAssertEqual(UserMessages.humanize("Ya está descargado."), "Ya está descargado.", "lo normal no se toca")
    }
}
