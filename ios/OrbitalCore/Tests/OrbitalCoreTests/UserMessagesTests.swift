import XCTest
@testable import OrbitalCore

final class UserMessagesTests: XCTestCase {
    func testTechnicalTextBecomesAPlainSentence() {
        XCTAssertEqual(UserMessages.humanize("No pude cambiar tu lista de Stremio: HTTP 503"),
                       "No pude cambiar tu lista de Stremio. Revisa tu conexión e intenta de nuevo.")
        XCTAssertEqual(UserMessages.humanize("The Internet connection appears to be offline."), "Sin conexión. Revisa tu internet e intenta de nuevo.")
        XCTAssertEqual(UserMessages.humanize("Error Domain=NSURLErrorDomain Code=-1001"), "Sin conexión. Revisa tu internet e intenta de nuevo.")
        XCTAssertEqual(UserMessages.humanize("User not found"), "Ese correo no tiene cuenta de Stremio.")
        XCTAssertEqual(UserMessages.humanize("Ya está descargado."), "Ya está descargado.", "lo normal no se toca")
    }
}
