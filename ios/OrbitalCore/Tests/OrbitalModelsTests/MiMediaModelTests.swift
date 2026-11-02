import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// Descargas › Mi media (todo con red falsa, nunca el OneDrive de nadie): sin OneDrive no hay nada que revisar; revisar la
/// carpeta arma la biblioteca (lo más reciente primero, filtros, orden por nombre, «Recién agregado» y lo que no se
/// reconoció); sin red lo dice y se queda lo que ya tenías; «Corregir ficha» se recuerda; al abrir, lo que ya viste en Trakt
/// se oculta con «Sin ver» y regresar pronto no repite todo.
@MainActor
final class MiMediaModelTests: XCTestCase {
    func children(_ path: String) -> String { "\(OneDrive.graph)\(OneDrive.childrenPath(path))" }

    /// OneDrive conectado (sesión de mentira) y, si se da, la carpeta elegida.
    func connect(_ rig: ServicesRig, folder: String? = "Pelis") {
        rig.services.settings.update { $0.oneDriveClientID = "app-123"; if let folder { $0.oneDriveFolder = folder } }
        rig.secrets.set(SecretKey.oneDriveTokens, #"{"access_token":"acc","refresh_token":"ref","expires_at":\#(rig.clock.now.timeIntervalSince1970 + 86400)}"#)
    }

    /// La carpeta: una serie (subida el 7 oct), una película reciente (5 oct), una vieja (2024) y un video sin ficha.
    func stockFolder(_ rig: ServicesRig) {
        rig.http.json[children("Pelis")] = ["value": [
            ["id": "a1", "name": "Dune Part Two (2024) 1080p.mkv", "size": 8_000_000_000, "file": [:], "createdDateTime": "2025-10-05T10:00:00Z"],
            ["id": "a2", "name": "Severance.S01E03.mkv", "size": 900_000_000, "file": [:], "createdDateTime": "2025-10-07T10:00:00Z"],
            ["id": "a3", "name": "Severance.S01E04.mkv", "size": 900_000_000, "file": [:], "createdDateTime": "2025-10-07T11:00:00Z"],
            ["id": "a4", "name": "Arrival (2016).mp4", "size": 4_000_000_000, "file": [:], "createdDateTime": "2024-01-01T10:00:00Z"],
            ["id": "a5", "name": "Vacaciones 2019.mp4", "size": 100, "file": [:], "createdDateTime": "2025-10-08T10:00:00Z"]]]
        let search = "https://v3-cinemeta.strem.io/catalog"
        rig.http.json["\(search)/movie/top/search=Dune%20Part%20Two.json"] = ["metas": [["id": "tt15239678", "type": "movie", "name": "Dune: Part Two", "releaseInfo": "2024"]]]
        rig.http.json["\(search)/series/top/search=Severance.json"] = ["metas": [["id": "tt11280740", "type": "series", "name": "Severance", "releaseInfo": "2022-"]]]
        rig.http.json["\(search)/movie/top/search=Arrival.json"] = ["metas": [["id": "tt2543164", "type": "movie", "name": "Arrival", "releaseInfo": "2016"]]]
        rig.http.json["\(search)/movie/top/search=Vacaciones.json"] = ["metas": []]
    }

    func testSinOneDriveNoHayNadaQueRevisar() async throws {
        let rig = try ServicesRig()
        let model = MiMediaModel(rig.services)
        XCTAssertFalse(model.ready)
        XCTAssertFalse(model.needsFolder, "sin conectar no se pide carpeta")
        await model.rescan()
        XCTAssertTrue(model.all.isEmpty)
        XCTAssertNil(model.error)
        XCTAssertNil(model.scannedAt)
        XCTAssertFalse(rig.http.calls.contains { $0.hasPrefix(OneDrive.graph) })
        connect(rig, folder: nil)
        XCTAssertTrue(model.needsFolder, "conectado, pero sin carpeta elegida")
        XCTAssertFalse(model.ready)
    }

    func testRevisarArmaLaBibliotecaConFiltrosOrdenYLoNuevo() async throws {
        let rig = try ServicesRig()
        connect(rig)
        stockFolder(rig)
        let model = MiMediaModel(rig.services)
        await model.rescan()
        XCTAssertNil(model.error)
        XCTAssertFalse(model.scanning)
        XCTAssertEqual(model.scannedAt, rig.clock.now)
        XCTAssertEqual(model.all.map(\.imdb), ["tt11280740", "tt15239678", "tt2543164"], "lo más reciente primero")
        XCTAssertEqual(model.movies, 2)
        XCTAssertEqual(model.series, 1)
        XCTAssertEqual(model.unmatched.map(\.name), ["Vacaciones 2019.mp4"], "lo que no se reconoció, para corregirlo")
        model.filter = .movies
        XCTAssertEqual(model.shown.map(\.imdb), ["tt15239678", "tt2543164"])
        model.filter = .series
        XCTAssertEqual(model.shown.map(\.imdb), ["tt11280740"])
        model.filter = .all; model.sort = .name
        XCTAssertEqual(model.shown.map(\.name), ["Arrival", "Dune: Part Two", "Severance"])
        XCTAssertEqual(model.recent.map(\.imdb), ["tt11280740", "tt15239678"], "«Recién agregado»: las últimas dos semanas")
        let arrival = try XCTUnwrap(model.all.first { $0.imdb == "tt2543164" })
        XCTAssertFalse(model.isNew(arrival))
        // De vuelta (otra sesión): lo guardado, al instante y sin red.
        rig.http.offline = true
        XCTAssertEqual(MiMediaModel(rig.services).all.count, 3)
    }

    func testSinRedAlRevisarLoDiceYSeQuedaLoQueYaTenias() async throws {
        let rig = try ServicesRig()
        connect(rig)
        stockFolder(rig)
        let model = MiMediaModel(rig.services)
        await model.rescan()
        rig.http.offline = true
        await model.rescan()
        XCTAssertEqual(model.error, "No pude conectar con OneDrive.")
        XCTAssertFalse(model.scanning)
        XCTAssertEqual(model.all.count, 3, "lo de antes no se borra")
        XCTAssertTrue(rig.services.oneDrive.linked, "un corte de red no desconecta")
    }

    func testCorregirUnoSinFichaLoPasaALaBibliotecaYSeRecuerda() async throws {
        let rig = try ServicesRig()
        connect(rig)
        stockFolder(rig)
        let model = MiMediaModel(rig.services)
        await model.rescan()
        let info = try XCTUnwrap(model.unmatched.first?.info)
        await model.fix(info, to: SearchResult(kind: "movie", metaID: "tt0085995", title: "National Lampoon's Vacation", poster: nil, year: "1983"))
        XCTAssertTrue(model.unmatched.isEmpty)
        XCTAssertEqual(model.all.first { $0.imdb == "tt0085995" }?.name, "National Lampoon's Vacation")
        XCTAssertEqual(MiMediaModel(rig.services).all.count, 4, "al volver a abrir sigue corregido")
    }

    func testAlAbrirLoVistoEnTraktSeOcultaConSinVerYRegresarProntoNoRepiteTodo() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        connect(rig)
        stockFolder(rig)
        rig.http.json["https://api.trakt.tv/sync/watched/movies"] = [["movie": ["title": "Arrival", "ids": ["imdb": "tt2543164"]]]]
        rig.http.json["https://api.trakt.tv/sync/watched/shows?extended=full"] = []
        let model = MiMediaModel(rig.services)
        await model.load()
        XCTAssertEqual(model.all.count, 3, "la primera vez se revisa la carpeta")
        XCTAssertEqual(model.watched, ["tt2543164"])
        model.filter = .unwatched
        XCTAssertEqual(model.shown.map(\.imdb), ["tt11280740", "tt15239678"])
        let asked = rig.http.calls.count
        rig.clock.advance(60)
        await model.load()
        XCTAssertEqual(rig.http.calls.count, asked, "al regresar de una ficha no se repite todo")
        // «Ver»: la película es ella misma; la serie empieza por el primer episodio que tienes.
        let series = try XCTUnwrap(model.all.first { $0.kind == "series" })
        let movie = try XCTUnwrap(model.all.first { $0.imdb == "tt15239678" })
        let next = await model.continueVideo(series)
        XCTAssertEqual(next, "tt11280740:1:3")
        let film = await model.continueVideo(movie)
        XCTAssertEqual(film, "tt15239678")
    }
}
