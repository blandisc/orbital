import XCTest
@testable import OrbitalCore
@testable import OrbitalModels
import OrbitalAddons

/// Fernando, 12 nov, Los Simpson T11E2: «me salen puros episodios en inglés… Me salieron todas de Comet», con latino primero en
/// «Tus idiomas». Decidió: «Sí, vamos a hacer la 2 y la 3» (revisar por dentro el audio; decir «hay latino, pero hay que pedirlo
/// a la nube» y cuándo un complemento no contestó). Regla de `docs/ios-interfaz.md`: si tu idioma existe, la app te lo dice
/// aunque no arranque al instante; y si un complemento no contestó, también.
@MainActor
final class LatinoNubeModelTests: XCTestCase {
    static let id = "tt1160419"
    static let comet = "https://c.example"
    static let latinoHash = "6c3f0b4a1e2d5f7a8b9c0d1e2f3a4b5c6d7e8f90"
    static let multi = "https://c.example/p/multi.mkv"

    func rig() throws -> ServicesRig {
        let rig = try ServicesRig()
        rig.secrets.set(AddonKeys.realDebridToken, String(repeating: "K", count: 52))
        rig.secrets.set(SecretKey.ownAddons, "https://a.example/manifest.json\n\(Self.comet)/manifest.json")
        rig.http.json["\(Self.comet)/manifest.json"] = ["name": "Comet", "resources": ["stream"], "types": ["movie", "series"], "idPrefixes": ["tt"]]
        rig.services.settings.update { $0.audio = "es"; $0.latinSpanish = true }
        return rig
    }

    /// Comet: tres en inglés al instante (una «MULTi» en MKV). Torrentio con Real-Debrid: una en inglés al instante. Sin
    /// Real-Debrid, Torrentio sí tiene una en latino.
    func serve(_ rig: ServicesRig, multiAudio: [(language: String, name: String?)] = [("eng", "English"), ("fre", "Français")]) throws {
        rig.http.json["\(Self.comet)/stream/movie/\(Self.id).json"] = ["streams": [
            ["name": "[RD⚡] Comet 1080p", "description": "📄 Dune.2021.1080p.WEB-DL.DDP5.1.Atmos.H.264-FLUX.mp4\n💾 8.1 GB", "url": "https://c.example/p/flux.mp4"],
            ["name": "[RD⚡] Comet 1080p", "description": "📄 Dune.2021.MULTi.1080p.BluRay.x264-AMIABLE.mkv\n💾 12.4 GB", "url": .string(Self.multi)],
        ]]
        rig.http.json["https://a.example/stream/movie/\(Self.id).json"] = ["streams": [
            ["name": "[RD+] Torrentio\n720p", "title": "Dune.2021.720p.WEBRip.x264.AAC-YTS.mp4\n👤 90 💾 1.3 GB ⚙️ YTS",
             "url": "https://a.example/resolve/realdebrid/K/1111111111111111111111111111111111111111/null/0/x.mp4"],
        ]]
        let base = try XCTUnwrap(rig.services.debridRequests.keylessBase)
        rig.http.json["\(base)/stream/movie/\(Self.id).json"] = ["streams": [
            ["name": "Torrentio\n1080p", "title": "Dune (2021) 1080p BluRay Latino\n👤 15 💾 2.3 GB ⚙️ Cinecalidad\n🇲🇽", "infoHash": .string(Self.latinoHash), "fileIdx": 0],
        ]]
        rig.http.raw[Self.multi] = MatroskaTracks.sampleHeader(audio: multiAudio)
        rig.http.statuses[Self.multi] = 206
        try? FileManager.default.removeItem(at: rig.root)
    }

    func list(_ rig: ServicesRig) async throws -> SourcesModel {
        try await Task.sleep(nanoseconds: 50_000_000)   // `Services` configura la búsqueda en una tarea
        let list = SourcesModel(rig.services, kind: "movie", metaID: Self.id, videoID: Self.id)
        await list.load()
        return list
    }

    /// Todo lo que arranca al instante está en inglés, pero el latino existe: «Hay latino, pero hay que pedirlo a la nube», con
    /// la de latino lista para pedir (R4), aunque la lista sí tenga otras que pedir.
    func testWhenYourLanguageOnlyExistsToRequestTheListSaysSo() async throws {
        let rig = try rig()
        try serve(rig)
        let list = try await list(rig)
        XCTAssertFalse(list.languageRows.contains { $0.code == "es-419" && $0.options.contains { $0.speed != .realDebridMustDownload } },
                       "precondición: ningún latino arranca al instante")
        let yours = try XCTUnwrap(list.yoursToRequest, "el renglón «hay que pedirlo»")
        XCTAssertEqual(yours.code, "es-419")
        XCTAssertEqual(list.source(yours.option.id)?.torrent?.hash, Self.latinoHash)
        XCTAssertEqual(yours.option.speed, .realDebridMustDownload)
    }

    /// «Revisar por dentro»: la «MULTi» que arranca al instante trae una pista «Español Latino»; queda «Comprobado» en latino,
    /// se guarda para la próxima (y para su paquete) y ya no se ofrece pedir otra.
    func testCheckingInsideFindsLatinoAndTheListUpdates() async throws {
        let rig = try rig()
        try serve(rig, multiAudio: [("eng", "English"), ("spa", "Español Latino")])
        let list = try await list(rig)
        let row = try XCTUnwrap(list.languageRows.first { $0.code == "es-419" })
        let card = try XCTUnwrap(row.options.first { list.source($0.id)?.playbackURL?.absoluteString == Self.multi })
        XCTAssertNotEqual(card.speed, .realDebridMustDownload)
        let key = try XCTUnwrap(list.source(card.id)?.key)
        XCTAssertTrue(rig.services.titlePrefs.checkedAudio(key)?.contains { $0.code == "es-419" } == true, "queda guardado")
        XCTAssertNil(list.yoursToRequest, "ya hay latino al instante: no se ofrece pedir")
        XCTAssertEqual(rig.http.calls.filter { $0 == Self.multi }.count, 1, "una sola lectura")
        XCTAssertFalse(rig.http.calls.contains("https://c.example/p/flux.mp4"), "un MP4 no se revisa")
    }

    /// Lo revisado que no trae tu idioma también se guarda («Comprobado» en inglés y francés) y no se vuelve a leer.
    func testCheckingInsideThatFindsNothingNewIsNotRepeated() async throws {
        let rig = try rig()
        try serve(rig)
        let list = try await list(rig)
        let multi = try XCTUnwrap(list.ranked.first { $0.playbackURL?.absoluteString == Self.multi })
        XCTAssertEqual(multi.audio.filter { $0.evidence == .checked }.map(\.code).sorted(), ["en", "fr"])
        XCTAssertNotNil(list.yoursToRequest, "sigue diciendo que el latino hay que pedirlo")
        await list.load()
        XCTAssertEqual(rig.http.calls.filter { $0 == Self.multi }.count, 1)
    }

    /// Un complemento que no contestó lo dice, y «Reintentar» le vuelve a preguntar: lo que traiga entra a la lista.
    func testAQuietAddonIsNamedAndRetryBringsItsVersions() async throws {
        let rig = try rig()
        try serve(rig)
        rig.http.statuses["https://a.example/stream/movie/\(Self.id).json"] = 503
        let list = try await list(rig)
        XCTAssertEqual(list.quiet, ["Torrentio"], "«No contestó a tiempo: Torrentio»")
        XCTAssertFalse(list.ranked.contains { $0.addon == "Torrentio" })
        rig.http.statuses = [Self.multi: 206]
        await list.retryQuiet()
        XCTAssertEqual(list.quiet, [])
        XCTAssertTrue(list.ranked.contains { $0.addon == "Torrentio" })
    }
}
