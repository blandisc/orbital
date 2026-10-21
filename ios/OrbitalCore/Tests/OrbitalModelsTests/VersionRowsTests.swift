import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// «Elegir versión» con las versiones reales de Intensa-Mente 2 (Torrentio, octubre de 2026).
@MainActor
final class VersionRowsTests: XCTestCase {
    func source(_ i: Int, _ res: String, _ first: String, gb: Double, site: String, flags: String = "", cached: Bool = true) -> Source {
        let stream: JSON = .object(["name": .string("Torrentio\n\(res)\(cached ? " [RD+]" : "")"), "title": .string("\(first)\n👤 10 💾 \(gb) GB ⚙️ \(site)\n\(flags)"),
                                    "url": .string("https://rd.example/\(i).mkv")])
        return Streams.parse(stream, addon: "Torrentio", transportURL: "", index: i, origin: TitleOrigin(language: "en", country: "United States", year: 2024))
    }

    func testRowsByLanguageWithTheBestOfEachQuality() {
        let all = [
            source(1, "4k", "Inside.Out.2.2024.2160p.WEB-DL.DV.HDR10.PLUS.ENG.LATINO.DDP5.1.Atmos.H265-BEN.THE.MEN", gb: 17.72, site: "TorrentGalaxy", flags: "🇬🇧 🇲🇽"),
            source(2, "1080p", "IntensaMente.2.2024.1080p-Dual-Lat", gb: 2.93, site: "Cinecalidad", flags: "🇲🇽"),
            source(3, "1080p", "IntensaMente 2 (2024) 1080p WEBDL LAT - ZeiZ", gb: 12.32, site: "Cinecalidad", flags: "🇲🇽"),
            source(4, "4k", "Inside.Out.2.2024.2160p.WEB-DL.DDP5.1.Atmos.DV.HDR.H.265-FLUX[TGx]", gb: 16.65, site: "TorrentGalaxy"),
            source(5, "1080p", "Inside Out 2 2024 1080p BluRay", gb: 1.78, site: "YTS"),
            source(6, "1080p", "Del reves 2 (Inside Out 2) (2024) [Bluray 1080p][Esp]", gb: 6.73, site: "Wolfmax4k", flags: "🇪🇸"),
            source(7, "4k", "Inside Out 2 2024 Bluray 2160p AV1 HDR10 EN/FR/ES OPUS 7.1-UH [UserHEVC]", gb: 6.43, site: "1337x", flags: "🇬🇧 🇪🇸 🇫🇷", cached: false),
            source(8, "1080p", "Izvrnuto.obrnuto.2.(2024).1080p.x265.hrvatski", gb: 3.03, site: "1337x", flags: "🇭🇷"),
            source(9, "720p", "Inside Out 2 (Intensa-mente 2) (2024) ts-hq lat.mp4", gb: 1.94, site: "Cinecalidad", flags: "🇲🇽"),
        ]
        let prefs = Preferences(audio: "es", quality: "1080p", spanish: "es-419")
        let ranked = Streams.rank(all, prefs: prefs, kind: "movie")
        let rows = SourcesModel.languageRows(ranked, prefs: prefs, limitGB: 5)
        XCTAssertEqual(rows.main.map(\.code), ["es-419", "en", "es-ES", "es"], "latino, el original, castellano, español que no dice cuál")
        let latino = rows.main[0]
        XCTAssertTrue(latino.yours)
        XCTAssertEqual(latino.options.map(\.quality), ["4K", "1080p"], "solo las calidades que hay")
        let latino1080 = latino.options[1]
        XCTAssertEqual(latino1080.others.count, 1, "la otra latina de 1080p va en «Otras»")
        XCTAssertTrue(rows.main[1].original)
        XCTAssertEqual(rows.main[2].options.first?.evidence, .site, "[Esp] de Wolfmax4k: castellano, lo dice el sitio")
        XCTAssertEqual(Set(rows.more.map(\.code)), ["fr", "hr"], "los demás idiomas, aparte")
        XCTAssertTrue(rows.main.flatMap(\.options).contains { $0.recommended }, "la recomendada se marca")
        XCTAssertEqual(ranked.first.flatMap { Streams.playingLanguage($0, prefs)?.code }, "es-419", "la recomendada suena en latino")
    }
}
