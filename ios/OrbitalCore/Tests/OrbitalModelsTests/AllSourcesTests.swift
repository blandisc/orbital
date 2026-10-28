import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// «Todas las fuentes»: grupos por calidad, cuántas hay (sin ocultas), orden, filtros y qué tan rápido arranca cada una.
final class AllSourcesTests: XCTestCase {
    func source(_ i: Int, _ res: String, gb: Double = 0, seeders: Int = 0, cached: Bool = false, debrid: Bool = true,
                tags: [String] = [], audio: [AudioLanguage] = [AudioLanguage("en", .original)]) -> Source {
        var s = Source(index: i, addon: "Torrentio", stream: .null, transportURL: "")
        s.resolution = res; s.size = Int(gb * 1e9); s.seeders = seeders; s.cached = cached; s.debrid = debrid; s.tags = tags
        s.setAudio(audio)
        return s
    }

    var sample: [Source] {
        [
            source(1, "1080p", gb: 2.5, seeders: 40, cached: true, audio: [AudioLanguage("es-419", .name), AudioLanguage("en", .original)]),
            source(2, "4K", gb: 18, seeders: 12, cached: true, tags: ["REMUX"]),
            source(3, "1080p", gb: 0, seeders: 0),
            source(4, "1080p", gb: 1.2, seeders: 300, debrid: false),
            source(5, "720p", gb: 0.9, seeders: 5, cached: true, audio: [AudioLanguage("es-ES", .site)]),
            source(6, "", gb: 0.7, seeders: 2, tags: ["CAM"]),
            source(7, "1080p", gb: 3, seeders: 8, tags: [Streams.otherTitleTag]),
            source(8, "1080p", gb: 4, seeders: 9, cached: true),
            source(9, "480p", gb: 0.4, seeders: 1, tags: ["Tráiler"]),
            source(10, "", gb: 0.3, seeders: 3, audio: [AudioLanguage("ja", .checked)]),
        ]
    }

    func testGroupsByQualityInOrderWithAFewShownAndTheRestCounted() {
        let groups = AllSources.groups(sample)
        XCTAssertEqual(groups.map(\.quality), ["4K", "1080p", "720p", "Otras"], "solo las calidades que tienen algo; 480p solo traía un tráiler")
        let hd = groups[1]
        XCTAssertEqual(hd.total, 5)
        XCTAssertEqual(hd.shown.map(\.index), [1, 3, 4], "las tres primeras, en el orden de la recomendación")
        XCTAssertEqual(hd.more, 2)
        XCTAssertTrue(groups.flatMap(\.shown).contains { $0.index == 7 } || hd.more > 0, "«¿Otro título?» no se esconde")
        XCTAssertEqual(groups.last?.shown.map(\.index), [10], "sin resolución va a «Otras»; la CAM está oculta")
    }

    func testCountExcludesTheaterRecordingsAndTrailers() {
        let count = AllSources.count(sample)
        XCTAssertEqual(count.shown, 8)
        XCTAssertEqual(count.hidden, 2)
        XCTAssertEqual(AllSources.count(sample, filter: .init(onlyInRealDebrid: true)).shown, 4)
    }

    func testShowHiddenPutsThemAtTheEndOfTheirQuality() {
        let groups = AllSources.groups(sample, filter: .init(showHidden: true), shownPerGroup: 10)
        XCTAssertEqual(groups.map(\.quality), ["4K", "1080p", "720p", "480p", "Otras"])
        XCTAssertEqual(groups.last?.shown.map(\.index), [10, 6], "la CAM al final de «Otras»")
        XCTAssertEqual(groups[3].shown.map(\.index), [9])
        XCTAssertEqual(AllSources.hiddenTag(sample[5]), "CAM")
    }

    func testSmallestFirstPutsUnknownSizeLast() {
        let hd = AllSources.groups(sample, order: .smallest, shownPerGroup: 10)[1]
        XCTAssertEqual(hd.shown.map(\.index), [4, 1, 7, 8, 3], "1.2, 2.5, 3, 4 GB y la que no dice tamaño al final")
    }

    func testMostSeedersFirstPutsNoSeedersLast() {
        let hd = AllSources.groups(sample, order: .mostSeeders, shownPerGroup: 10)[1]
        XCTAssertEqual(hd.shown.map(\.index), [4, 1, 8, 7, 3])
    }

    func testFilters() {
        let rd = AllSources.groups(sample, filter: .init(onlyInRealDebrid: true), shownPerGroup: 10)
        XCTAssertTrue(rd.flatMap(\.shown).allSatisfy(\.cached))
        XCTAssertEqual(rd.flatMap(\.shown).map(\.index), [2, 1, 8, 5])
        let spanish = AllSources.groups(sample, filter: .init(language: "es"), shownPerGroup: 10)
        XCTAssertEqual(spanish.flatMap(\.shown).map(\.index), [1, 5], "«es» encuentra latino y castellano")
        let japanese = AllSources.groups(sample, filter: .init(language: "ja"))
        XCTAssertEqual(japanese.map(\.quality), ["Otras"])
        XCTAssertEqual(AllSources.Filter(onlyInRealDebrid: true, language: "es").activeCount, 2)
        XCTAssertEqual(AllSources.Filter().activeCount, 0)
        XCTAssertEqual(AllSources.languages(in: sample), ["en", "es", "ja"], "por cuántas fuentes los traen")
    }

    func testSpeedSaysOnlyWhatIsKnown() {
        XCTAssertEqual(SourceSpeed(source(1, "1080p", cached: true)), .inRealDebrid)
        XCTAssertEqual(SourceSpeed(source(1, "1080p", cached: false, debrid: true)), .realDebridMustDownload)
        XCTAssertEqual(SourceSpeed(source(1, "1080p", cached: false, debrid: false)), .unknown)
    }

    func testLanguageEvidenceIsHonest() {
        let s = source(1, "1080p", audio: [AudioLanguage("en", .original), AudioLanguage("es-419", .name), AudioLanguage("fr", .maybe),
                                           AudioLanguage("ja", .checked), AudioLanguage("es-ES", .site), AudioLanguage("de", .unknown)])
        let evidence = AllSources.languageEvidence(s)
        XCTAssertEqual(evidence.map(\.code), ["en", "es-419", "fr", "ja", "es-ES", "de"])
        XCTAssertEqual(evidence.map(\.kind), [.assumed, .name, .assumed, .checked, .site, .assumed])
    }

    func testPlayingLanguageGoesFirst() {
        let s = source(1, "1080p", audio: [AudioLanguage("en", .name), AudioLanguage("es-419", .name), AudioLanguage("fr", .maybe)])
        let latino = Preferences(audio: "es", spanish: "es-419")
        XCTAssertEqual(AllSources.languageEvidence(s, playingFirst: latino).map(\.code), ["es-419", "en", "fr"], "el que suena, primero")
        XCTAssertEqual(AllSources.languageEvidence(s, playingFirst: Preferences(audio: "en")).map(\.code), ["en", "es-419", "fr"], "ya iba primero")
        XCTAssertEqual(AllSources.otherLanguages(s, prefs: latino), ["en"], "los otros seguros, sin lo que solo se supone")
        XCTAssertEqual(AllSources.otherLanguages(source(1, "1080p", audio: [AudioLanguage("es-419", .name)]), prefs: latino), [], "uno solo: nada más")
    }

    func testFileNameAndBadge() {
        var s = source(1, "4K")
        s.release = "Movie.2024.2160p.DV"
        s.stream = .object(["behaviorHints": .object(["filename": .string("Movie.2024.2160p.DV.HDR.mkv")])])
        s.hdr = ["DV", "HDR"]
        XCTAssertEqual(AllSources.fileName(s), "Movie.2024.2160p.DV.HDR.mkv")
        XCTAssertEqual(AllSources.copyName(s), "Movie.2024.2160p.DV")
        XCTAssertEqual(AllSources.hdrBadge(s), "DV")
        s.release = ""
        XCTAssertEqual(AllSources.copyName(s), "Movie.2024.2160p.DV.HDR.mkv")
    }
}
