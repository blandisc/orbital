import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// QA de «Elegir versión» (octubre 2026): la hoja por idiomas y el aviso del reproductor. Dicen lo que DEBERÍA pasar: hoy fallan.
@MainActor
final class VersionQAModelFindingsTests: XCTestCase {
    func source(_ i: Int, name: String, _ first: String, gb: Double = 2.5, site: String = "1337x", flags: String = "", origin: TitleOrigin = TitleOrigin(language: "en", country: "United States", year: 2023)) -> Source {
        let stream: JSON = .object(["name": .string(name), "title": .string("\(first)\n👤 10 💾 \(gb) GB ⚙️ \(site)\n\(flags)"),
                                    "url": .string("https://rd.example/\(i).mkv")])
        return Streams.parse(stream, addon: "Torrentio", transportURL: "", index: i, origin: origin)
    }

    // MARK: la hoja
    /// «MULTi.SPANISH» con «Multi Audio» y 6 banderas (🇲🇽 entre ellas): trae «es» (nombre) y «es-419» (tal vez). Las dos van a la fila
    /// «Español (no dice cuál)»: la MISMA versión sale dos veces y «Otras 1» es ella misma.
    func testQA20_ASourceAppearsTwiceInTheSameRow() {
        let multi = source(1, name: "Torrentio\n1080p [RD+]", "Movie.2023.MULTi.SPANISH.1080p.WEB-DL.x264", flags: "Multi Audio / 🇬🇧 / 🇲🇽 / 🇪🇸 / 🇫🇷 / 🇩🇪 / 🇮🇹")
        let prefs = Preferences(audio: "es", quality: "1080p", spanish: "es-419")
        let rows = SourcesModel.languageRows(Streams.rank([multi], prefs: prefs), prefs: prefs, limitGB: 5)
        let spanish = try? XCTUnwrap(rows.main.first { $0.code == "es" })
        XCTAssertEqual(spanish?.options.first?.others, [], "«Otras» trae la misma versión: \(String(describing: spanish?.options))")
    }

    /// Clásico: la recomendada es la DVDRip sin resolución (en Real-Debrid, «Al instante») y hay una 1080p que aún no está.
    /// Como la fila tiene 1080p, se quita «SD»… y con ella la recomendada: ninguna opción de la hoja dice «Recomendada».
    func testQA21_TheRecommendedSDVersionDisappearsFromTheSheet() {
        let origin = TitleOrigin(language: "en", country: "United States", year: 1943)
        let dvd = source(1, name: "Torrentio\n[RD+]", "Casablanca.1942.DVDRip.XviD-FRAGMENT", gb: 1.4, origin: origin)
        let bluray = source(2, name: "Torrentio\n[RD download] 1080p", "Casablanca.1942.1080p.BluRay.x264-AMIABLE", gb: 9, origin: origin)
        let prefs = Preferences(audio: "en", quality: "1080p")
        let ranked = Streams.rank([dvd, bluray], prefs: prefs)
        XCTAssertEqual(ranked.first?.index, 1, "precondición: la DVDRip al instante es la recomendada («Ver»)")
        let rows = SourcesModel.languageRows(ranked, prefs: prefs, limitGB: 5)
        XCTAssertTrue(rows.main.flatMap(\.options).contains { $0.recommended }, "la que reproduce «Ver» no aparece en la hoja: \(rows.main.map { $0.options.map(\.quality) })")
    }

    // MARK: el reproductor
    let spaUntagged = MediaTrack(id: 2, kind: .audio, language: "spa")   // así etiqueta el español casi cualquier archivo, latino o no

    /// Ves «Show.S01E01.1080p.LATINO» y el archivo trae una pista «spa» sin nombre (lo normal). Pasa:
    ///   1. el aviso «Esta versión no trae latino · Cambiar a latino» sale aunque el nombre dice LATINO;
    ///   2. queda «Comprobado: Español (no dice cuál)», borrando el «es-419 · Lo dice el nombre»: comprobar EMPEORA el dato.
    func testQA22_UntaggedSpanishTrackDowngradesALatinoVersionAndTriggersAFalseOffer() async throws {
        let rig = try Rig()
        rig.http.json["https://a.example/stream/series/tt0386676%3A1%3A1.json"] = ["streams": [
            .object(["name": "T\n1080p [RD+]", "title": "Show.S01E01.1080p.LATINO\n💾 2 GB", "url": "https://rd.example/latino.mkv"]),
            .object(["name": "T\n1080p [RD+]", "title": "Show.S01E01.720p.Dual-Lat\n💾 1 GB", "url": "https://rd.example/dual.mkv"]),
        ]]
        rig.settings.update { $0.audio = "es"; $0.latinSpanish = true }
        await rig.model.begin(rig.request())
        let latino = try XCTUnwrap(rig.model.sourceChoices.first { $0.release.contains("LATINO") })
        XCTAssertEqual(rig.engine.loads.first?.url.absoluteString, "https://rd.example/latino.mkv")
        await rig.model.handle(rig.playing(0, audio: [spaUntagged], subs: [], selectedAudio: 2))
        XCTAssertNil(rig.model.notice, "no hay por qué ofrecer «Cambiar a latino»: \(String(describing: rig.model.notice))")
        let checked = rig.titlePrefs.checkedAudio(latino.key) ?? []
        XCTAssertTrue(checked.contains { $0.code == "es-419" }, "lo comprobado tiró el «latino» del nombre: \(checked)")
    }

    /// La latina falla al cargar; se cae a la siguiente (inglés). El aviso ofrece «Cambiar a latino»… a la que acaba de fallar.
    func testQA23_OfferPointsToTheSourceThatAlreadyFailed() async throws {
        let rig = try Rig()
        rig.http.json["https://a.example/stream/series/tt0386676%3A1%3A1.json"] = ["streams": [
            .object(["name": "T\n1080p [RD+]", "title": "Show.S01E01.1080p.LATINO\n💾 2 GB", "url": "https://rd.example/latino.mkv"]),
            .object(["name": "T\n1080p [RD+]", "title": "Show.S01E01.1080p.WEB-DL\n💾 2 GB", "url": "https://rd.example/english.mkv"]),
        ]]
        rig.engine.failing.insert("https://rd.example/latino.mkv")
        rig.settings.update { $0.audio = "es"; $0.latinSpanish = true }
        await rig.model.begin(rig.request())
        XCTAssertEqual(rig.engine.loads.last?.url.absoluteString, "https://rd.example/english.mkv", "precondición: cayó a la inglesa")
        await rig.model.handle(rig.playing(0, audio: [MediaTrack(id: 1, kind: .audio, language: "eng")], subs: [], selectedAudio: 1))
        if case .otherVersionHasYourLanguage(_, _, let index) = rig.model.notice {
            let target = rig.model.sourceChoices.first { $0.index == index }
            XCTAssertNotEqual(target?.playbackURL?.absoluteString, "https://rd.example/latino.mkv", "ofrece la versión que ya falló")
        }
    }

    /// Dos versiones «LATINO» que en realidad traen inglés. Aceptas el aviso y cambias a la segunda: el aviso te ofrece volver a
    /// la primera (ya comprobada: inglés), porque `sourceChoices` sigue con lo que decía el nombre. Ida y vuelta sin fin.
    func testQA24_OfferPingPongsBetweenTwoMislabeledVersions() async throws {
        let rig = try Rig()
        rig.http.json["https://a.example/stream/series/tt0386676%3A1%3A1.json"] = ["streams": [
            .object(["name": "T\n1080p [RD+]", "title": "Show.S01E01.1080p.WEB-DL\n💾 2 GB", "url": "https://rd.example/english.mkv"]),
            .object(["name": "T\n720p [RD+]", "title": "Show.S01E01.720p.LATINO\n💾 1 GB", "url": "https://rd.example/a.mkv"]),
            .object(["name": "T\n720p [RD+]", "title": "Show.S01E01.720p.LAT\n💾 1 GB", "url": "https://rd.example/b.mkv"]),
        ]]
        rig.settings.update { $0.audio = "es"; $0.latinSpanish = true }
        await rig.model.begin(rig.request())
        let eng = MediaTrack(id: 1, kind: .audio, language: "eng")
        await rig.model.handle(rig.playing(0, audio: [eng], subs: [], selectedAudio: 1))
        guard case .otherVersionHasYourLanguage(_, _, let first) = rig.model.notice else { return XCTFail("precondición: hay aviso (\(rig.model.sourceChoices.map(\.release)))") }
        await rig.model.switchSource(to: first)
        await rig.model.handle(rig.playing(10, audio: [eng], subs: [], selectedAudio: 1))   // la «latina» trae inglés
        guard case .otherVersionHasYourLanguage(_, _, let second) = rig.model.notice else { return }
        await rig.model.switchSource(to: second)
        await rig.model.handle(rig.playing(20, audio: [eng], subs: [], selectedAudio: 1))   // la otra «latina» también
        if case .otherVersionHasYourLanguage(_, _, let third) = rig.model.notice {
            XCTAssertNotEqual(third, first, "te ofrece volver a la que ya comprobaste que es inglés")
        }
    }

    /// Elegiste a propósito la versión en inglés en «Elegir versión»: igual sale «Esta versión no trae latino · Cambiar a latino».
    func testQA25_OfferEvenWhenYouPickedThisVersionOnPurpose() async throws {
        let rig = try Rig()
        rig.http.json["https://a.example/stream/series/tt0386676%3A1%3A1.json"] = ["streams": [
            .object(["name": "T\n1080p [RD+]", "title": "Show.S01E01.1080p.LATINO\n💾 2 GB", "url": "https://rd.example/latino.mkv"]),
            .object(["name": "T\n1080p [RD+]", "title": "Show.S01E01.1080p.WEB-DL\n💾 2 GB", "url": "https://rd.example/english.mkv"]),
        ]]
        rig.settings.update { $0.audio = "es"; $0.latinSpanish = true }
        let found = try await rig.finder.find(kind: "series", videoID: "tt0386676:1:1", prefs: rig.settings.value.preferences())
        let english = try XCTUnwrap(found.first { $0.release.contains("WEB-DL") })
        var request = rig.request()
        request.sourceIndex = english.index
        await rig.model.begin(request)
        await rig.model.handle(rig.playing(0, audio: [MediaTrack(id: 1, kind: .audio, language: "eng")], subs: [], selectedAudio: 1))
        XCTAssertNil(rig.model.notice, "la elegiste tú en la hoja")
    }
}
