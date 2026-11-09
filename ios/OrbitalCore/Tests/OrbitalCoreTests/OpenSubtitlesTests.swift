import XCTest
@testable import OrbitalCore

/// La API oficial de OpenSubtitles con respuestas de su documentación (sin red ni cuenta de verdad).
final class OpenSubtitlesTests: XCTestCase {
    static let search: JSON = ["total_count": 3, "data": [
        ["id": "1", "attributes": ["language": "es", "download_count": 50, "release": "Show.S01E05.720p.WEB", "hearing_impaired": false,
                                   "moviehash_match": false, "files": [["file_id": 111, "file_name": "a.srt"]]]],
        ["id": "2", "attributes": ["language": "es", "download_count": 9, "release": "Show.S01E05.1080p.BluRay",
                                   "moviehash_match": true, "files": [["file_id": 222]]]],
        ["id": "3", "attributes": ["language": "en", "download_count": 900, "files": []]],
    ]]

    func makeAPI(_ http: FakeHTTP, secrets: SecretsStore = InMemorySecrets()) -> OpenSubtitlesAPI {
        OpenSubtitlesAPI(http: http, apiKey: "app-key", secrets: secrets, version: "1.2", languages: { ["spa", "en", "es"] })
    }

    func testQueryIsSortedLowercaseAndUsesTheSeriesForAnEpisode() {
        let items = OpenSubtitlesAPI.query(videoID: "tt0096697:3:7", file: FileFingerprint(hash: "abc", size: 1), languages: ["spa", "en"])!
        XCTAssertEqual(items.map(\.name), ["episode_number", "languages", "moviehash", "order_by", "parent_imdb_id", "season_number"])
        XCTAssertEqual(items.first { $0.name == "parent_imdb_id" }?.value, "96697", "sin «tt» ni ceros al frente")
        XCTAssertEqual(items.first { $0.name == "languages" }?.value, "en,es")
        XCTAssertNil(OpenSubtitlesAPI.query(videoID: "kitsu:1", file: nil, languages: []))
    }

    func testParsePutsTheExactCopyFirstAndSkipsEntriesWithoutFiles() {
        let options = OpenSubtitlesAPI.parse(Self.search)
        XCTAssertEqual(options.map(\.fileID), ["222", "111"])
        XCTAssertTrue(options[0].exactFile)
        XCTAssertEqual(options[0].url.absoluteString, "opensubtitles://file/222")
        XCTAssertEqual(options[1].downloads, 50)
    }

    func testSearchSendsTheAppKeyAndIsRemembered() async {
        let http = FakeHTTP()
        http.prefix["https://api.opensubtitles.com/api/v1/subtitles"] = Self.search
        let api = makeAPI(http)
        let first = await api.search(kind: "series", videoID: "tt1:1:5", file: nil)
        _ = await api.search(kind: "series", videoID: "tt1:1:5", file: nil)
        XCTAssertEqual(first?.count, 2)
        XCTAssertEqual(http.calls.count, 1, "la misma búsqueda no se repite")
        XCTAssertEqual(http.headers.first?["Api-Key"], "app-key")
        XCTAssertEqual(http.headers.first?["User-Agent"], "Orbital v1.2")
    }

    func testLoginKeepsTheTokenButNotThePasswordAndDownloadUsesIt() async throws {
        let http = FakeHTTP()
        let secrets = InMemorySecrets()
        http.json["https://api.opensubtitles.com/api/v1/login"] = ["token": "jwt", "base_url": "api.opensubtitles.com", "status": 200,
                                                                  "user": ["allowed_downloads": 20, "vip": false]]
        http.json["https://api.opensubtitles.com/api/v1/download"] = ["link": "https://dl.opensubtitles.com/x.srt", "remaining": 19]
        let api = makeAPI(http, secrets: secrets)
        let account = try await api.login(username: " fer ", password: "secreta")
        XCTAssertEqual(account.username, "fer")
        XCTAssertEqual(account.remaining, 20)
        XCTAssertFalse(secrets.get(SecretKey.openSubtitlesAccount)?.contains("secreta") ?? true, "la contraseña no se guarda")
        let link = try await api.resolve(URL(string: "opensubtitles://file/222")!)
        XCTAssertEqual(link.absoluteString, "https://dl.opensubtitles.com/x.srt")
        XCTAssertEqual(http.headers.last?["Authorization"], "Bearer jwt")
        let remaining = await api.account()?.remaining
        XCTAssertEqual(remaining, 19)
        _ = try await api.resolve(URL(string: "opensubtitles://file/222")!)
        XCTAssertEqual(http.calls.filter { $0.hasSuffix("/download") }.count, 1, "el mismo no gasta cuota dos veces")
    }

    func testDownloadWithoutAccountOrQuotaSaysWhy() async throws {
        let http = FakeHTTP()
        let secrets = InMemorySecrets()
        let api = makeAPI(http, secrets: secrets)
        do { _ = try await api.resolve(URL(string: "opensubtitles://file/1")!); XCTFail() }
        catch { XCTAssertEqual(error as? OpenSubtitlesError, .notConnected) }
        await api.adopt(OpenSubtitlesAccount(username: "fer", token: "jwt"))
        http.statuses["https://api.opensubtitles.com/api/v1/download"] = 406
        do { _ = try await api.resolve(URL(string: "opensubtitles://file/1")!); XCTFail() }
        catch { XCTAssertEqual(error as? OpenSubtitlesError, .quota) }
    }

    func testMergeKeepsTheAPIFirstAndDropsTheAddonCopyOfTheSameFile() {
        let api = OpenSubtitlesAPI.parse(Self.search)
        let addon = [SubtitleOption(url: URL(string: "https://os.strem.io/222.srt")!, language: "spa", source: "OpenSubtitles", fileID: "222"),
                     SubtitleOption(url: URL(string: "https://os.strem.io/333.srt")!, language: "spa", source: "OpenSubtitles", fileID: "333")]
        let merged = StreamFinder.merge(official: api, addons: addon)
        XCTAssertEqual(merged.map(\.fileID), ["222", "111", "333"])
    }

    func testWithoutTheAppKeyTheAPIIsOff() async {
        let api = OpenSubtitlesAPI(http: FakeHTTP(), apiKey: " ", secrets: InMemorySecrets())
        XCTAssertFalse(api.available)
        let found = await api.search(kind: "movie", videoID: "tt1", file: nil)
        XCTAssertNil(found)
    }
}
