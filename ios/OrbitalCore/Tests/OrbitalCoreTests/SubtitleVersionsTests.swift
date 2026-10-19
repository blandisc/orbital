import XCTest
@testable import OrbitalCore

final class SubtitleVersionsTests: XCTestCase {
    private func opt(_ n: Int, _ lang: String, _ release: String?, downloads: Int? = nil, hi: Bool = false, forced: Bool = false) -> SubtitleOption {
        SubtitleOption(url: URL(string: "https://subs.example/\(n)")!, language: lang, release: release, downloads: downloads, hearingImpaired: hi, foreignOnly: forced)
    }

    func testLanguageCodes() {
        XCTAssertEqual(SubtitleLanguage.code("spa"), "es")
        XCTAssertEqual(SubtitleLanguage.code("es-419"), "es")
        XCTAssertEqual(SubtitleLanguage.code("pob"), "pt")
        XCTAssertEqual(SubtitleLanguage.code("ger"), "de")
        XCTAssertEqual(SubtitleLanguage.code("eng"), "en")
        XCTAssertNil(SubtitleLanguage.code(""))
    }

    func testReleaseTraits() {
        let t = ReleaseTraits.parse("Lost.S01E02.720p.WEB-DL.DD5.1.H.264-NTb.mkv")
        XCTAssertEqual(t, ReleaseTraits(source: "WEB-DL", group: "ntb"))
        XCTAssertEqual(ReleaseTraits.parse("Lost.S01E02.1080p.BluRay.x264-ROVERS").source, "BluRay")
        XCTAssertEqual(ReleaseTraits.parse("Lost S01E02 HDTV XviD-LOL").match(ReleaseTraits(source: "HDTV", group: "lol")), 3)
        XCTAssertEqual(ReleaseTraits.parse("Lost.S01E02.WEBRip").match(ReleaseTraits(source: "WEB-DL", group: nil)), 0)
    }

    func testRankingEmbeddedThenMatchingCopyThenDownloads() {
        let tracks = [MediaTrack(id: 3, kind: .subtitle, language: "spa", title: "Español"),
                      MediaTrack(id: 4, kind: .subtitle, language: "eng")]
        let found = [opt(1, "spa", "Lost.S01E02.HDTV-LOL", downloads: 9000),
                     opt(2, "spa", "Lost.S01E02.720p.WEB-DL-NTb", downloads: 10),
                     opt(3, "spa", "Lost.S01E02.1080p.WEB-DL-FLUX", downloads: 50),
                     opt(4, "spa", nil, downloads: 20_000),
                     opt(5, "eng", "Lost.S01E02.720p.WEB-DL-NTb")]
        let ranked = SubtitleVersions.ranked(language: "es", tracks: tracks, found: found, release: "Lost.S01E02.720p.WEB-DL.H264-NTb.mkv")
        XCTAssertEqual(ranked.map(\.id), ["track-3", "https://subs.example/2", "https://subs.example/3", "https://subs.example/4", "https://subs.example/1"])
        XCTAssertTrue(ranked[0].fromVideo)
        XCTAssertTrue(ranked[1].matchesCopy)
        XCTAssertEqual(ranked[1].match, 3)
        XCTAssertFalse(ranked[3].matchesCopy)
    }

    func testHidesHearingImpairedAndForcedEverywhere() {
        let tracks = [MediaTrack(id: 1, kind: .subtitle, language: "eng", title: "English SDH"),
                      MediaTrack(id: 2, kind: .subtitle, language: "eng", title: "Forced"),
                      MediaTrack(id: 3, kind: .subtitle, language: "eng", isForced: true),
                      MediaTrack(id: 4, kind: .subtitle, language: "eng", title: "Signs & Songs"),
                      MediaTrack(id: 5, kind: .subtitle, language: "eng", title: "English (CC)"),
                      MediaTrack(id: 6, kind: .subtitle, language: "eng", title: "English")]
        let found = [opt(1, "eng", "x", hi: true), opt(2, "eng", "y", forced: true), opt(3, "eng", "Show.S01E01.WEB.HI-GRP"), opt(4, "eng", "Show.S01E01.WEB-GRP")]
        let ranked = SubtitleVersions.ranked(language: "en", tracks: tracks, found: found, release: nil)
        XCTAssertEqual(ranked.map(\.id), ["track-6", "https://subs.example/4"])
        XCTAssertEqual(SubtitleVersions.languages(tracks: tracks, found: found).first?.count, 2)
    }

    func testLanguagesByCount() {
        let langs = SubtitleVersions.languages(tracks: [MediaTrack(id: 1, kind: .subtitle, language: "fre")],
                                               found: [opt(1, "eng", nil), opt(2, "eng", nil), opt(3, "spa", nil)])
        XCTAssertEqual(langs.map(\.code), ["en", "es", "fr"])
        XCTAssertEqual(langs.map(\.count), [2, 1, 1])
    }

    func testRememberedPickChoosesSameGroupNextEpisode() {
        let kv = InMemoryKeyValueStore()
        let picks = SubtitlePicks(kv)
        let ep1 = SubtitleVersions.ranked(language: "es", tracks: [], found: [opt(1, "spa", "Lost.S01E01.720p.WEB-DL-NTb")], release: nil)
        picks.remember(metaID: "tt0411008", SubtitlePick(ep1[0]))
        // Se guarda: otra instancia (otra vez que abres la app) lo lee.
        let pick = SubtitlePicks(kv).pick(metaID: "tt0411008")
        XCTAssertEqual(pick, SubtitlePick(language: "es", group: "ntb", name: "Lost.S01E01.720p.WEB-DL-NTb"))
        let ep2 = SubtitleVersions.ranked(language: "es", tracks: [MediaTrack(id: 7, kind: .subtitle, language: "spa")],
                                          found: [opt(2, "spa", "Lost.S01E02.HDTV-LOL", downloads: 900), opt(3, "spa", "Lost.S01E02.720p.WEB-DL-NTb")], release: nil)
        XCTAssertEqual(pick?.best(in: ep2)?.id, "https://subs.example/3")
        // Sin una de esa copia: la primera (la del video).
        XCTAssertEqual(SubtitlePick(language: "es", group: "zzz").best(in: ep2)?.id, "track-7")
        XCTAssertNil(SubtitlePick(language: "fr").best(in: ep2))
    }
}
