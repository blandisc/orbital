import XCTest
@testable import OrbitalCore

/// QA de «Elegir versión» (octubre 2026): cada prueba es un fallo encontrado con nombres reales de Torrentio/Peerflix.
/// Dicen lo que DEBERÍA pasar: hoy fallan.
final class VersionQAFindingsTests: XCTestCase {
    let american = TitleOrigin(language: "en", country: "United States", year: 2000)

    func audio(_ first: String, flags: String = "", site: String = "", name: String = "Torrentio\n1080p", origin: TitleOrigin?) -> [AudioLanguage] {
        let description = "\(first)\n👤 10 💾 2 GB ⚙️ \(site)\n\(flags)"
        return Streams.audio(name: name, description: description, filename: "", site: site, origin: origin)
    }

    // MARK: 1. Palabras del TÍTULO de la película leídas como idioma
    /// «Cast Away» (Náufrago): las 29 versiones de Torrentio salen «Castellano · Lo dice el nombre» y ninguna en inglés.
    func testQA01_CastAwayIsNotCastilian() {
        let found = audio("Cast.Away.2000.1080p.BluRay.H264.AAC-RARBG", site: "RARBG", origin: american)
        XCTAssertEqual(found, [AudioLanguage("en", .original)], "«Cast» es parte del título, no «castellano»")
    }

    /// «The Italian Job», «The French Dispatch», «The Spanish Prisoner», «The Danish Girl», «Russian Doll»: el título dice un idioma.
    func testQA02_LanguageWordsInsideTheTitle() {
        XCTAssertEqual(audio("The.Italian.Job.2003.1080p.BluRay.x264-SiNNERS", site: "1337x", origin: american), [AudioLanguage("en", .original)])
        XCTAssertEqual(audio("The Spanish Prisoner 1997 1080p BluRay", site: "YTS", origin: american), [AudioLanguage("en", .original)])
        XCTAssertEqual(audio("The.French.Dispatch.2021.1080p.WEBRip.x264-RARBG", site: "RARBG", origin: american), [AudioLanguage("en", .original)])
        XCTAssertEqual(audio("Russian.Doll.S01E01.1080p.NF.WEB-DL", origin: american), [AudioLanguage("en", .original)])
    }

    // MARK: 2. «Eng Sub» / «English subs»: el idioma de ANTES de «sub» es el de los subtítulos
    func testQA03_LanguageRightBeforeSubIsTheSubtitle() {
        let spanish = TitleOrigin(language: "es", country: "Mexico, Spain", year: 2006)
        XCTAssertEqual(audio("Pans.Labyrinth[2006]DvDrip[Eng.Sub]-aXXo", site: "ThePirateBay", origin: spanish).map(\.base), ["es"],
                       "audio en español con subtítulos en inglés, no audio en inglés")
        let french = TitleOrigin(language: "fr", country: "France", year: 2011)
        XCTAssertEqual(audio("The Intouchables (2011)-François Cluzet-1080p-H264-AC 3 (DolbyDigital-5.1)-Eng.Sub-DEMO & nickarad", origin: french),
                       [AudioLanguage("fr", .original)])
        let korean = TitleOrigin(language: "ko", country: "South Korea")
        XCTAssertEqual(audio("Crash.Landing.on.You.E01.1080p.NF.WEB-DL.ENG.SUB", origin: korean), [AudioLanguage("ko", .original)])
    }

    // MARK: 3. Banderas de una lista de SUBTÍTULOS tomadas como audio (≤ 4 banderas)
    /// Erai-raws «[Multiple Subtitle]»: Torrentio pone 🇬🇧 🇵🇹 🇲🇽 (los subtítulos) y salen como audio latino «Lo dice el nombre».
    func testQA04_EraiRawsSubtitleFlagsAreNotAudio() {
        let japanese = TitleOrigin(language: "ja", country: "Japan")
        let found = audio("[Erai-raws] Shingeki no Kyojin - 01 ~ 25 [1080p][Multiple Subtitle]", flags: "Multi Subs / 🇬🇧 / 🇵🇹 / 🇲🇽", site: "NyaaSi", origin: japanese)
        XCTAssertFalse(found.contains { $0.code == "es-419" && $0.evidence.solid }, "es japonés con subtítulos: \(found)")
        XCTAssertTrue(found.contains { $0.code == "ja" })
    }

    /// «[BluRay 1080p - REPACK - SUBS: FR EN ES] Le fabuleux destin d'Amélie Poulain»: la recomendada para quien quiere latino.
    func testQA05_SubsListInTheNameAndFlagsAreTheSame() {
        let french = TitleOrigin(language: "fr", country: "France, Germany", year: 2002)
        let found = audio("[BluRay 1080p - REPACK - SUBS: FR EN ES] Le fabuleux destin d'Amélie Poulain (2001)", flags: "🇬🇧 / 🇪🇸 / 🇫🇷", origin: french)
        XCTAssertFalse(found.contains { $0.base == "es" && $0.evidence.solid }, "ES ahí es un subtítulo: \(found)")
    }

    // MARK: 4. Idiomas que no se reconocen
    /// «Jap», «Japanese», «Jpn» no están en la lista: 47 de 2,700 versiones reales pierden el japonés («Eng 5.1 AAC Jap 5.1 AAC»).
    func testQA06_JapaneseWordIsRecognized() {
        let japanese = TitleOrigin(language: "ja", country: "Japan", year: 1997)
        let found = audio("Princess Mononoke (1997) (1080p BluRay x265 10-bit Eng 5.1 AAC Jap 5.1 AAC) [WeSLeY]", site: "1337x", origin: japanese)
        XCTAssertTrue(found.contains { $0.code == "ja" }, "dice «Jap»: \(found)")
    }

    /// Peerflix (complemento en español): la bandera va en `name` («Peerflix 🇪🇸 1080p») y el sitio con 🌐: nada de eso se lee.
    func testQA07_PeerflixFlagInTheNameIsIgnored() {
        let stream: JSON = .object(["name": "Peerflix 🇪🇸 1080p", "description": "Shrek 1 (2001).avi\n  👤 0 🌐 Peerflix", "url": "https://rd.example/s.avi"])
        let src = Streams.parse(stream, addon: "Peerflix", transportURL: "", index: 0, origin: american)
        XCTAssertTrue(src.audio.contains { $0.base == "es" }, "Peerflix dice 🇪🇸 y sale \(src.audio)")
    }

    /// «Ingles» (sin acento, como lo escriben los sitios españoles) y «[ES-EN]» no cuentan: 53 de 173 de Peerflix pierden el inglés.
    func testQA08_SpanishSpelledEnglishIsRecognized() {
        let found = audio("Coco [BluRay 1080p][AC3 5.1 Castellano DTS 5.1-Ingles+Subs][ES-EN]", origin: american)
        XCTAssertTrue(found.contains { $0.code == "en" }, "trae inglés: \(found)")
    }

    /// RARBG/GalaxyRG «DUBBED» sin idioma = doblaje al inglés de una película extranjera. Sale «Castellano · Es el original».
    func testQA09_DubbedWithoutLanguageIsNotTheOriginal() {
        let spain = TitleOrigin(language: "es", country: "Spain")
        let found = audio("Money.Heist.S01.DUBBED.1080p.WEBRip.x265-RARBG", site: "RARBG", origin: spain)
        XCTAssertNotEqual(found, [AudioLanguage("es-ES", .original)], "DUBBED: no es el audio original")
    }

    /// «NORDiC» = subtítulos nórdicos con el audio original; sale «Nórdico» y sin inglés.
    func testQA10_NordicReleasesKeepTheOriginalAudio() {
        let found = audio("Home Alone 1990 NORDiC 1080p BluRay x264-RAPiDCOWS", flags: "🇩🇰 / 🇫🇮 / 🇸🇪 / 🇳🇴", origin: american)
        XCTAssertTrue(found.contains { $0.code == "en" }, "Mi pobre angelito NORDiC trae inglés: \(found)")
    }

    // MARK: 5. El país del título: Argentina + España es argentina
    /// «Relatos salvajes» y «El secreto de sus ojos»: Cinemeta dice «Argentina, Spain» y salen CASTELLANO «Es el original».
    func testQA11_ArgentineCoproductionWithSpainIsLatino() {
        XCTAssertEqual(TitleOrigin(language: "es", country: "Argentina, Spain, France, United Kingdom").originalCode, "es-419", "Relatos salvajes")
        XCTAssertEqual(TitleOrigin(language: "es", country: "Argentina, Spain").originalCode, "es-419", "El secreto de sus ojos")
    }

    // MARK: 6. «¿Otro título?» cuando Cinemeta da el año del estreno en EE. UU.
    /// El viaje de Chihiro: Cinemeta dice 2003 (EE. UU.), los nombres 2001 → 34 de 52 versiones con «¿Otro título?» (−1500) y la
    /// recomendada es una SIN año. Igual Totoro (1990 vs 1988: 31/50), Cinema Paradiso (1990 vs 1988: 31/33), Ciudad de Dios (2004 vs 2002: 29/33).
    func testQA12_OtherTitleFalsePositiveWithLateUSRelease() {
        XCTAssertFalse(Streams.otherTitle(release: "Spirited.Away.2001.1080p.BluRay.x264-OFT", year: 2003))
        XCTAssertFalse(Streams.otherTitle(release: "Cinema.Paradiso.1988.DC.ITALIAN.1080p.BluRay.H264.AAC-VXT", year: 1990))
        XCTAssertFalse(Streams.otherTitle(release: "City Of God 2002 1080p BluRay x264-CiNEFiLE", year: 2004))
    }

    // MARK: 7. Orden: una «Dual-Lat» segura pierde contra «SPANISH» que no dice cuál
    /// Encanto, real: «Encanto.2021.SPANiSH.1080p.DSNP.WEB-DL.x264-dem3nt3» (grupo español: castellano) gana a «Encanto.2021.1080P-Dual-Lat»
    /// de Cinecalidad para quien eligió LATINO. Igual Akira.
    func testQA13_SureDualLatinoBeatsUnspecifiedSpanishForLatinoUsers() {
        func source(_ first: String, site: String, flags: String) -> Source {
            let stream: JSON = .object(["name": "Torrentio\n1080p [RD+]", "title": .string("\(first)\n👤 10 💾 2.5 GB ⚙️ \(site)\n\(flags)"), "url": "https://rd.example/x.mkv"])
            return Streams.parse(stream, addon: "Torrentio", transportURL: "", index: first.count, origin: TitleOrigin(language: "en", country: "United States", year: 2021))
        }
        let spanish = source("Encanto.2021.SPANiSH.1080p.DSNP.WEB-DL.x264-dem3nt3", site: "1337x", flags: "🇪🇸")
        let dualLat = source("Encanto.2021.1080P-Dual-Lat", site: "Cinecalidad", flags: "Dual Audio / 🇲🇽")
        let prefs = Preferences(audio: "es", quality: "1080p", spanish: "es-419")
        XCTAssertEqual(Streams.rank([spanish, dualLat], prefs: prefs).first?.release, dualLat.release,
                       "latino seguro (con inglés) antes que un «Spanish» que puede ser castellano")
    }
}
