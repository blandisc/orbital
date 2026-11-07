import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// Biblioteca › Guardado (BI1-A, 3 nov 2026): Mi lista de Trakt por omisión, tus listas con un toque (recordada en este
/// aparato), y cómo vas con cada título: por ver, a medias (Trakt o el avance de aquí) o vista, con su barra.
@MainActor
final class SavedModelTests: XCTestCase {
    private func row(_ imdb: String, _ title: String, kind: String) -> JSON {
        let key = kind == "movie" ? "movie" : "show"
        let item: JSON = ["title": .string(title), "year": 2020, "ids": ["imdb": .string(imdb), "trakt": 1]]
        return .object(["listed_at": "2026-11-01T10:00:00.000Z", "type": .string(key), key: item])
    }

    private func trakt(_ rig: ServicesRig) {
        rig.http.prefix["https://api.trakt.tv/sync/watchlist"] = .array([row("tt0000001", "Una película", kind: "movie"), row("tt0000002", "Una serie", kind: "series"),
                                                                       row("tt0000003", "Otra película", kind: "movie"), row("tt0000004", "Otra serie", kind: "series")])
        rig.http.json["https://api.trakt.tv/users/me/lists"] = [["name": "Para ver con Ana", "ids": ["trakt": 103]], ["name": "Terror de octubre", "ids": ["trakt": 104]]]
        rig.http.prefix["https://api.trakt.tv/users/me/lists/103/items"] = .array([row("tt0000009", "De la lista", kind: "movie")])
        rig.http.json["https://api.trakt.tv/sync/watched/movies"] = [["movie": ["ids": ["imdb": "tt0000001"]]]]
        // Otra serie: 4 de 8 capítulos (a medias).
        rig.http.prefix["https://api.trakt.tv/sync/watched/shows"] = [["show": ["aired_episodes": 8, "ids": ["imdb": "tt0000004"]],
                                                                       "seasons": [["number": 1, "episodes": [["number": 1], ["number": 2], ["number": 3], ["number": 4]]]]]]
    }

    func testSinTraktNoPideNadaYQuedaVacia() async throws {
        let rig = try ServicesRig()
        let model = SavedModel(rig.services)
        await model.load()
        XCTAssertFalse(model.traktLinked)
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertTrue(model.loadedOnce, "ya se sabe que no hay nada: el vacío con «Conectar Trakt»")
        XCTAssertFalse(rig.http.calls.contains { $0.contains("api.trakt.tv") }, "sin Trakt no se pide nada")
    }

    func testMiListaConTusListasYComoVasConCadaTitulo() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        trakt(rig)
        // Una película a medias en este aparato y una serie empezada aquí (Trakt aún no sabe).
        rig.services.library.update("tt0000003", make: { LibraryEntry(metaID: "tt0000003", kind: "movie", name: "Otra película") }) { e in
            e.position = 1800; e.duration = 7200
        }
        rig.services.library.update("tt0000002", make: { LibraryEntry(metaID: "tt0000002", kind: "series", name: "Una serie") }) { e in
            e.seen = ["tt0000002:1:1"]
        }
        let model = SavedModel(rig.services)
        await model.load()
        XCTAssertEqual(model.selected, SavedModel.watchlist, "abre en Mi lista")
        XCTAssertEqual(model.items.map(\.imdb), ["tt0000001", "tt0000002", "tt0000003", "tt0000004"])
        XCTAssertEqual(model.lists.map(\.id), ["watchlist", "list:103", "list:104"])
        XCTAssertEqual(model.lists.last?.name, "Terror de octubre")
        let byID = Dictionary(uniqueKeysWithValues: model.items.map { ($0.imdb, $0) })
        XCTAssertEqual(model.state(of: byID["tt0000001"]!), .watched)
        XCTAssertEqual(model.progress(of: byID["tt0000001"]!), 1, "vista: la barra completa")
        XCTAssertEqual(model.state(of: byID["tt0000003"]!), .inProgress)
        XCTAssertEqual(model.progress(of: byID["tt0000003"]!) ?? 0, 0.25, accuracy: 0.001, "dónde te quedaste")
        XCTAssertEqual(model.state(of: byID["tt0000004"]!), .inProgress)
        XCTAssertEqual(model.progress(of: byID["tt0000004"]!) ?? 0, 0.5, accuracy: 0.001, "4 de 8 capítulos")
        XCTAssertEqual(model.state(of: byID["tt0000002"]!), .inProgress, "empezada aquí aunque Trakt no lo sepa")
        XCTAssertEqual(model.states.values.filter { $0 == .unwatched }.count, 0)
    }

    func testCambiarDeListaSeRecuerdaYSiLaBorrasteVuelveAMiLista() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        trakt(rig)
        let model = SavedModel(rig.services)
        await model.load()
        await model.choose("list:103")
        XCTAssertEqual(model.items.map(\.imdb), ["tt0000009"])
        let again = SavedModel(rig.services)
        XCTAssertEqual(again.selected, "list:103", "abre en la que dejaste")
        // La borraste en Trakt: de vuelta a Mi lista.
        rig.http.json["https://api.trakt.tv/users/me/lists"] = [["name": "Terror de octubre", "ids": ["trakt": 104]]]
        let fresh = try ServicesRig(traktLinked: true, traktClientID: "CID")
        trakt(fresh)
        fresh.http.json["https://api.trakt.tv/users/me/lists"] = [["name": "Terror de octubre", "ids": ["trakt": 104]]]
        fresh.services.kv.set("library.saved.list", data: Data("list:103".utf8))
        let gone = SavedModel(fresh.services)
        await gone.load()
        XCTAssertEqual(gone.selected, SavedModel.watchlist)
        XCTAssertEqual(gone.items.count, 4)
    }

    func testSiTraktNoContestaLoDiceParaReintentar() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        rig.http.offline = true
        let model = SavedModel(rig.services)
        await model.load()
        XCTAssertTrue(model.failed)
        XCTAssertFalse(model.loading)
    }

    /// Editar tus listas (Fernando, 6 nov 2026): quitar sale al instante y llega a Trakt; si Trakt no acepta, regresa a su
    /// lugar. «Deshacer» (agregar) lo regresa donde estaba. Mi lista también se edita; las demás listas no.
    func testQuitarYAgregarEnTuListaDeTrakt() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        trakt(rig)
        rig.http.prefix["https://api.trakt.tv/users/me/lists/103/items"] = .array([row("tt0000009", "De la lista", kind: "movie"),
                                                                                  row("tt0000010", "Otra de la lista", kind: "series")])
        let model = SavedModel(rig.services)
        await model.load()
        await model.choose("list:103")
        XCTAssertTrue(model.canEdit)
        XCTAssertEqual(model.selectedName, "Para ver con Ana")
        let first = try XCTUnwrap(model.items.first)
        let removed = await model.remove(first)
        XCTAssertTrue(removed)
        XCTAssertEqual(model.items.map(\.imdb), ["tt0000010"])
        XCTAssertTrue(rig.http.calls.contains("https://api.trakt.tv/users/me/lists/103/items/remove"))
        // «Deshacer»: regresa a su lugar (el primero).
        await model.add(first)
        XCTAssertEqual(model.items.map(\.imdb), ["tt0000009", "tt0000010"])
        // Trakt no acepta (403): sale y vuelve.
        rig.http.statuses["https://api.trakt.tv/users/me/lists/103/items/remove"] = 403
        let failed = await model.remove(first)
        XCTAssertFalse(failed)
        XCTAssertEqual(model.items.map(\.imdb), ["tt0000009", "tt0000010"], "si falla, regresa a su lugar")
    }

    func testMiListaSeEditaYLasDemasNo() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        trakt(rig)
        let model = SavedModel(rig.services)
        await model.load()
        XCTAssertTrue(model.canEdit, "Mi lista es tuya")
        let first = try XCTUnwrap(model.items.first)
        await model.remove(first)
        XCTAssertFalse(model.items.contains { $0.imdb == first.imdb })
        XCTAssertTrue(TitleActions.isEditable(listID: "watchlist"))
        XCTAssertTrue(TitleActions.isEditable(listID: "list:103"))
        for readOnly in ["mine", "recs", "trend", "chart:nfx", "jw:nfx", ForYou.favoritesList] {
            XCTAssertFalse(TitleActions.isEditable(listID: readOnly), readOnly)
        }
    }
}
