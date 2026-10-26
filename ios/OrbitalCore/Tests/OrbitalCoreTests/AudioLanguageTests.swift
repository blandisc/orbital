import XCTest
@testable import OrbitalCore

/// El idioma del audio de cada versión, con nombres reales de Torrentio (octubre de 2026) y las reglas de la TV.
final class AudioLanguageTests: XCTestCase {
    let american = TitleOrigin(language: "en", country: "United States")

    func audio(_ first: String, flags: String = "", site: String = "", name: String = "Torrentio\n1080p", origin: TitleOrigin? = nil, marks: String = "") -> [AudioLanguage] {
        let description = "\(first)\n👤 10 💾 2 GB ⚙️ \(site)\n\(flags) \(marks)"
        return Streams.audio(name: name, description: description, filename: "", site: site, origin: origin)
    }

    func testLatinoSaidByTheNameOrTheSite() {
        XCTAssertEqual(audio("Dune.part.two.2024.2160p.x265.hdr.5.1-dual-lat-cinecalidad.re.mkv", flags: "🇲🇽", site: "Cinecalidad", origin: american),
                       [AudioLanguage("es-419", .name), AudioLanguage("en", .original)], "«Dual-Lat»: latino y el original")
        XCTAssertEqual(audio("Inside.Out.2.2024.2160p.WEB-DL.DV.HDR10.PLUS.ENG.LATINO.DDP5.1.Atmos", flags: "🇬🇧 🇲🇽", origin: american),
                       [AudioLanguage("es-419", .name), AudioLanguage("en", .name)])
        XCTAssertEqual(audio("IntensaMente 2 (2024) 1080p WEBDL LAT - ZeiZ", flags: "🇲🇽", site: "Cinecalidad", origin: american).first, AudioLanguage("es-419", .name))
    }

    func testCastilianFromTheSiteEvenIfTheNameOnlySaysSpanish() {
        XCTAssertEqual(audio("Dune Parte Dos (2024) [4k 2160p][Esp]", flags: "🇪🇸", site: "MejorTorrent", origin: american), [AudioLanguage("es-ES", .site)])
        XCTAssertEqual(audio("Del reves 2 (Inside Out 2) (2024) [Bluray 1080p][Esp]", flags: "🇪🇸", site: "Wolfmax4k", origin: american), [AudioLanguage("es-ES", .site)])
    }

    func testSpanishThatDoesNotSayWhichStaysGeneric() {
        XCTAssertEqual(audio("Coco.2017.1080p.BluRay.x265-RARBG", flags: "🇬🇧 🇪🇸", site: "RARBG", origin: american),
                       [AudioLanguage("en", .name), AudioLanguage("es", .name)])
    }

    /// Roma dice «SPANISH» y es mexicana: es su audio original, latino.
    func testTheOriginalCountryTellsWhichSpanish() {
        let mexican = TitleOrigin(language: "es", country: "Mexico")
        XCTAssertEqual(audio("Roma.2018.SPANISH.2160p.NF.WEB-DL.x265.10bit.HDR.DDP5.1.Atmos-SMURF", flags: "🇪🇸", site: "RARBG", origin: mexican),
                       [AudioLanguage("es-419", .original)])
        let spanish = TitleOrigin(language: "es", country: "Spain")
        XCTAssertEqual(audio("La.Casa.de.Papel.S01E01.1080p.NF.WEB-DL", origin: spanish), [AudioLanguage("es-ES", .original)])
    }

    func testNothingSaysItSoItIsTheOriginal() {
        XCTAssertEqual(audio("Dune Part Two 2024 BluRay 1080p HEVC HDR 8ch-CAPTCHA", site: "ThePirateBay", origin: american), [AudioLanguage("en", .original)])
        XCTAssertEqual(audio("Spirited.Away.2001.1080p.BluRay", origin: TitleOrigin(language: "ja", country: "Japan")), [AudioLanguage("ja", .original)])
        XCTAssertEqual(audio("Something.2020.1080p.WEB"), [AudioLanguage("en", .unknown)], "sin saber el original: inglés, como la TV, pero «No dice idioma»")
    }

    /// Lo que va después de «Subtitulado» son subtítulos, no audio.
    func testSubtitleListsAreNotAudio() {
        XCTAssertEqual(audio("Crystal.Lake.S01E01.1080p.HDTV.Subtitulado.Esp.SC", origin: american), [AudioLanguage("en", .original)])
    }

    /// Muchas banderas sin «Multi Audio» son subtítulos; con la marca, cuentan pero como «tal vez».
    func testManyFlagsAreSubtitlesUnlessMarkedAsAudio() {
        let many = "🇬🇧 🇯🇵 🇮🇹 🇪🇸 🇫🇷 🇩🇪 🇵🇱 🇨🇿"
        XCTAssertEqual(audio("Some.Movie.2024.1080p.WEB-PAHE", flags: many, origin: american), [AudioLanguage("en", .original)])
        let marked = audio("Some.Movie.2024.1080p.WEB", flags: many, origin: american, marks: "Multi Audio")
        XCTAssertTrue(marked.contains(AudioLanguage("es", .maybe)))
    }

    func testCountryNamesGiveTheOriginal() {
        XCTAssertEqual(TitleOrigin(country: "Mexico").originalCode, "es-419")
        XCTAssertEqual(TitleOrigin(country: "Spain").originalCode, "es-ES")
        XCTAssertEqual(TitleOrigin(country: "United States, United Kingdom").originalCode, "en")
        XCTAssertEqual(TitleOrigin(language: "es").originalCode, "es")
        XCTAssertNil(TitleOrigin().originalCode)
    }

    /// Quieres latino: la latina primero, luego la que no dice cuál, luego la castellana, y el inglés al fondo.
    func testLatinoPreferenceOrder() {
        let prefs = Preferences(audio: "es", quality: "1080p", spanish: "es-419")
        func source(_ code: String, _ evidence: AudioLanguage.Evidence = .name) -> Source {
            var s = Source(index: 0, addon: "T", stream: .object([:]), transportURL: ""); s.resolution = "1080p"; s.cached = true
            s.setAudio([AudioLanguage(code, evidence)]); return s
        }
        let latino = Streams.score(source("es-419"), prefs: prefs), generic = Streams.score(source("es"), prefs: prefs)
        let castilian = Streams.score(source("es-ES"), prefs: prefs), english = Streams.score(source("en"), prefs: prefs)
        let maybeLatino = Streams.score(source("es-419", .maybe), prefs: prefs)
        XCTAssertGreaterThan(latino, generic); XCTAssertGreaterThan(generic, castilian); XCTAssertGreaterThan(castilian, english)
        XCTAssertGreaterThan(latino, maybeLatino, "lo que se sabe, antes que lo que es «tal vez»")
        XCTAssertEqual(Streams.score(source("es-ES"), prefs: Preferences(audio: "es", quality: "1080p")), Streams.score(source("es-419"), prefs: Preferences(audio: "es", quality: "1080p")),
                       "con «cualquiera», da igual cuál")
    }

    /// Lo comprobado al ver una versión gana a lo que dice el nombre, y se recuerda.
    func testCheckedTracksAreRemembered() {
        let prefs = TitlePreferences(InMemoryKeyValueStore())
        let tracks = [MediaTrack(id: 1, kind: .audio, language: "eng"), MediaTrack(id: 2, kind: .audio, language: "spa", title: "Latino"),
                      MediaTrack(id: 3, kind: .audio, language: "spa", title: "Castellano"), MediaTrack(id: 4, kind: .subtitle, language: "fre")]
        XCTAssertTrue(prefs.rememberChecked(key: "T|abc|0", tracks: tracks))
        XCTAssertFalse(prefs.rememberChecked(key: "T|abc|0", tracks: tracks), "lo mismo no cambia nada")
        XCTAssertEqual(prefs.checkedAudio("T|abc|0"), [AudioLanguage("en", .checked), AudioLanguage("es-419", .checked), AudioLanguage("es-ES", .checked)])
    }

    /// Torrentio a veces trae otra película con el mismo nombre: se marca y va al fondo.
    func testAnotherFilmWithTheSameNameIsMarked() {
        XCTAssertTrue(Streams.otherTitle(release: "Federico Fellinis Roma (1972) : 1080p X265 HEVC", year: 2018))
        XCTAssertFalse(Streams.otherTitle(release: "Roma.2018.SPANISH.2160p.NF.WEB-DL", year: 2018))
        XCTAssertFalse(Streams.otherTitle(release: "Dune Part Two 2024 BluRay", year: 2024))
        XCTAssertFalse(Streams.otherTitle(release: "BAFTA Best Pictures (1947 - 2021)", year: 2018), "una colección puede traer la buena")
        XCTAssertFalse(Streams.otherTitle(release: "Roma 2018 1080p WEBRip", year: nil))
    }
}
