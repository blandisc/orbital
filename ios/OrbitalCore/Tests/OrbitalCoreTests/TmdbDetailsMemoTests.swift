import XCTest
@testable import OrbitalCore

/// La memoria en disco de los detalles de TMDB: lo pedido se queda entre arranques y lo viejo se vuelve a pedir.
final class TmdbDetailsMemoTests: XCTestCase {
    func testKeepsDetailsOnDiskAndForgetsOldOnes() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("memo-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let details = TmdbDetails(kind: "movie", tmdbID: 1, imdb: "tt0000001", title: "Una", year: 2000, overview: "",
                                  runtime: nil, seasons: nil, episodes: nil, poster: nil, backdrop: nil)
        let memo = TmdbDetailsMemo(file: file)
        await memo.set("es-MX:movie:1", details)
        try await Task.sleep(nanoseconds: 1_300_000_000)   // se escribe un segundo después
        let again = TmdbDetailsMemo(file: file)
        let hit = await again.get("es-MX:movie:1")
        XCTAssertEqual(hit, details, "sigue ahí en el siguiente arranque")
        let expired = TmdbDetailsMemo(file: file, ttl: 0)
        let miss = await expired.get("es-MX:movie:1")
        XCTAssertNil(miss, "lo viejo se vuelve a pedir")
    }
}
