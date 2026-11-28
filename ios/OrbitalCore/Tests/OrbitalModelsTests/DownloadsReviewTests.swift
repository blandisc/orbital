import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// Fallas de Descargas que encontró la revisión del 27 nov 2026.
@MainActor
final class DownloadsReviewTests: XCTestCase {
    private func movie(_ version: String) -> DownloadItem {
        DownloadItem(id: "tt1|tt1|\(version)", kind: "movie", metaID: "tt1", videoID: "tt1", title: "Peli", originalTitle: "Peli", subtitle: "",
                     poster: nil, addon: "Torrentio", sourceIndex: 1, expectedBytes: 1000, relativePath: "tt1/\(version)/video.mkv", createdAt: 1)
    }

    /// Borrar, «Deshacer» y borrar otra vez: la espera del primero ya no borra el archivo, y el segundo «Deshacer» sí la regresa.
    func testDeletingAgainAfterUndoKeepsItsOwnUndo() async throws {
        let rig = try ServicesRig()
        try await rig.services.downloads.enqueue(movie("a"), url: URL(string: "https://rd.example/a")!)
        let model = DownloadsModel(rig.services, freeSpace: { 50_000_000_000 })
        let run = Task { await model.run() }
        try await Task.sleep(nanoseconds: 50_000_000)
        model.delete(["tt1|tt1|a"], undoWindow: .milliseconds(150))
        await model.undoDelete(["tt1|tt1|a"])
        model.delete(["tt1|tt1|a"], undoWindow: .seconds(30))
        try await Task.sleep(nanoseconds: 400_000_000)
        let still = await rig.services.downloads.item("tt1|tt1|a")
        XCTAssertNotNil(still, "la espera del primer borrado no borra el segundo")
        await model.undoDelete(["tt1|tt1|a"])
        XCTAssertEqual(model.items.map(\.id), ["tt1|tt1|a"], "el segundo «Deshacer» la regresa")
        run.cancel()
    }

    /// Dos subtítulos del mismo idioma seguidos: dos archivos, no uno encima del otro.
    func testTwoSubtitlesOfTheSameLanguageAreBothKept() async throws {
        let rig = try ServicesRig()
        let downloads = rig.services.downloads
        try await downloads.enqueue(movie("a"), url: URL(string: "https://rd.example/a")!)
        let first = await downloads.addSubtitle(id: "tt1|tt1|a", language: "es", data: Data("uno".utf8))
        let second = await downloads.addSubtitle(id: "tt1|tt1|a", language: "es", data: Data("dos".utf8))
        XCTAssertTrue(first && second)
        let saved = await downloads.item("tt1|tt1|a")
        let item = try XCTUnwrap(saved)
        XCTAssertEqual(item.subtitleFiles.count, 2)
        XCTAssertEqual(Set(item.subtitleFiles).count, 2, "cada uno con su nombre")
    }
}
