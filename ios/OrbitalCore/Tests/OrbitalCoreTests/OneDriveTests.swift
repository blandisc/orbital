import XCTest
@testable import OrbitalCore

final class OneDriveTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_792_000_000)   // 2026

    func testNamesAreReadLikeTheTV() {
        func p(_ n: String) -> OneDriveName? { OneDriveName.parse(n, now: now) }
        XCTAssertEqual(p("Dune Part Two (2024) 2160p.mkv"), OneDriveName(kind: "movie", title: "Dune Part Two", year: 2024))
        XCTAssertEqual(p("Severance.S01E03.1080p.WEB-DL.mkv"), OneDriveName(kind: "series", title: "Severance", year: nil, season: 1, episode: 3))
        XCTAssertEqual(p("The.Matrix.1999.1080p.BluRay.x264.mkv"), OneDriveName(kind: "movie", title: "The Matrix", year: 1999))
        XCTAssertEqual(p("2012.mkv"), OneDriveName(kind: "movie", title: "2012", year: nil), "un año al principio es el título")
        XCTAssertEqual(p("Adventure Time 5x12.mp4"), OneDriveName(kind: "series", title: "Adventure Time", year: nil, season: 5, episode: 12))
        XCTAssertEqual(p("Blade Runner 2049 (2017).mp4"), OneDriveName(kind: "movie", title: "Blade Runner 2049", year: 2017), "el año es el último que sea real")
        XCTAssertEqual(p("El Chavo [Latino] S02E10.avi"), OneDriveName(kind: "series", title: "El Chavo", year: nil, season: 2, episode: 10))
        XCTAssertEqual(p("Doctor.Who.2005.S01E01.mkv")?.year, 2005)
        XCTAssertNil(p("notas.txt"))
    }

    func makeDrive(_ http: FakeHTTP, secrets: InMemorySecrets = InMemorySecrets(), clock: Clock = Clock()) -> OneDrive {
        OneDrive(http: http, secrets: secrets, clientID: { "app-123" }, clock: { clock.now })
    }

    func testDeviceCodeLinksAndKeepsTheSessionInTheKeychain() async throws {
        let http = FakeHTTP(), secrets = InMemorySecrets()
        let drive = makeDrive(http, secrets: secrets)
        http.json["\(OneDrive.login)/devicecode"] = ["device_code": "dev", "user_code": "ABCD-1234", "verification_uri": "https://www.microsoft.com/link", "interval": 5, "expires_in": 900]
        let code = try await drive.deviceCode()
        XCTAssertEqual(code.userCode, "ABCD-1234")
        let body = String(data: http.bodies(for: "\(OneDrive.login)/devicecode").first ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("client_id=app-123") && body.contains("scope=Files.Read%20offline_access"), body)

        http.json["\(OneDrive.login)/token"] = ["error": "authorization_pending"]
        http.statuses["\(OneDrive.login)/token"] = 400
        let pending = try await drive.pollDevice(code)
        XCTAssertEqual(pending, .pending)
        http.json["\(OneDrive.login)/token"] = ["access_token": "acc", "refresh_token": "ref", "expires_in": 3600]
        http.statuses["\(OneDrive.login)/token"] = 200
        let linked = try await drive.pollDevice(code)
        XCTAssertEqual(linked, .linked)
        XCTAssertTrue(drive.linked)
        XCTAssertNotNil(secrets.get(SecretKey.oneDriveTokens))
    }

    func linkedDrive(_ http: FakeHTTP, clock: Clock = Clock()) -> OneDrive {
        let secrets = InMemorySecrets()
        secrets.set(SecretKey.oneDriveTokens, #"{"access_token":"acc","refresh_token":"ref","expires_at":\#(clock.now.timeIntervalSince1970 + 3600)}"#)
        return makeDrive(http, secrets: secrets, clock: clock)
    }

    func children(_ path: String) -> String { "\(OneDrive.graph)\(OneDrive.childrenPath(path))" }

    func testWalksOnlyTheChosenFolderAndKeepsVideos() async throws {
        let http = FakeHTTP()
        let drive = linkedDrive(http)
        http.json[children("Videos")] = ["value": [
            ["id": "f1", "name": "Severance", "folder": ["childCount": 1]],
            ["id": "a1", "name": "Dune Part Two (2024).mkv", "size": 1000, "file": [:]],
            ["id": "a2", "name": "notas.txt", "size": 10, "file": [:]]]]
        http.json[children("Videos/Severance")] = ["value": [["id": "a3", "name": "Severance.S01E03.mkv", "size": 500, "file": [:]]]]
        let videos = try await drive.videos("/Videos/")
        XCTAssertEqual(videos.map(\.id), ["a3", "a1"])
        XCTAssertEqual(videos.first?.path, "Videos/Severance/Severance.S01E03.mkv")
        XCTAssertFalse(http.calls.contains { $0.contains("/me/drive/root/children") }, "solo la carpeta elegida, nunca la raíz")
    }

    func testAnExpiredSessionRefreshesOnceAndARejectionUnlinks() async throws {
        let http = FakeHTTP(), clock = Clock()
        let drive = linkedDrive(http, clock: clock)
        clock.now = clock.now.addingTimeInterval(3600)
        http.json["\(OneDrive.login)/token"] = ["access_token": "acc2", "expires_in": 3600]
        http.json[children("V")] = ["value": []]
        _ = try await drive.children("V")
        XCTAssertEqual(http.calls.filter { $0.hasSuffix("/token") }.count, 1)
        clock.now = clock.now.addingTimeInterval(7200)
        http.statuses["\(OneDrive.login)/token"] = 400
        do { _ = try await drive.children("V"); XCTFail("debía pedir volver a conectar") }
        catch { XCTAssertEqual(error as? OneDriveError, .auth("Tu sesión de OneDrive caducó: vuelve a conectarla en Ajustes.")) }
        XCTAssertFalse(drive.linked)
    }

    func testLibraryMatchesNamesAndOffersYourCopyFirst() async throws {
        let http = FakeHTTP(), clock = Clock()
        let drive = linkedDrive(http, clock: clock)
        http.json[children("Pelis")] = ["value": [
            ["id": "a1", "name": "Dune Part Two (2024) 2160p.mkv", "size": 40_000_000_000, "file": [:]],
            ["id": "a2", "name": "Severance.S01E03.mkv", "size": 900_000_000, "file": [:]],
            ["id": "a3", "name": "Severance.S01E04.mkv", "size": 900_000_000, "file": [:]]]]
        http.json["https://v3-cinemeta.strem.io/catalog/movie/top/search=Dune%20Part%20Two.json"] = ["metas": [
            ["id": "tt0000001", "type": "movie", "name": "Dune", "releaseInfo": "2021"],
            ["id": "tt15239678", "type": "movie", "name": "Dune: Part Two", "releaseInfo": "2024"]]]
        http.json["https://v3-cinemeta.strem.io/catalog/series/top/search=Severance.json"] = ["metas": [["id": "tt11280740", "type": "series", "name": "Severance", "releaseInfo": "2022-"]]]
        http.json["\(OneDrive.graph)/me/drive/items/a1?$select=id,@microsoft.graph.downloadUrl"] = ["id": "a1", "@microsoft.graph.downloadUrl": "https://public.onedrive.example/a1"]
        http.json["\(OneDrive.graph)/me/drive/items/a2?$select=id,@microsoft.graph.downloadUrl"] = ["id": "a2", "@microsoft.graph.downloadUrl": "https://public.onedrive.example/a2"]

        let kv = InMemoryKeyValueStore()
        let library = OneDriveLibrary(drive: drive, cinemeta: Cinemeta(http: http), kv: kv, folder: { "Pelis" }, clock: { clock.now })
        let index = try await library.scan()
        XCTAssertEqual(index.entries.map(\.videoID), ["tt15239678", "tt11280740:1:3", "tt11280740:1:4"])
        XCTAssertEqual(http.calls.filter { $0.contains("search=Severance") }.count, 1, "una serie se busca una vez, no por episodio")

        let movie = await library.sources(kind: "movie", videoID: "tt15239678")
        XCTAssertEqual(movie.first?.playbackURL?.absoluteString, "https://public.onedrive.example/a1")
        XCTAssertEqual(movie.first?.resolution, "4K")
        XCTAssertTrue(movie.first?.cached ?? false)
        let episode = await library.sources(kind: "series", videoID: "tt11280740:1:3")
        XCTAssertEqual(episode.count, 1)
        let none = await library.sources(kind: "series", videoID: "tt11280740:2:1")
        XCTAssertTrue(none.isEmpty)

        // En la lista de fuentes, tu copia va primero aunque un complemento tenga una «mejor».
        http.json["https://a.example/manifest.json"] = ["name": "Torrentio", "resources": ["stream"], "types": ["movie", "series"], "idPrefixes": ["tt"]]
        http.json["https://a.example/stream/movie/tt15239678.json"] = ["streams": [["name": "T\n1080p [RD+]", "title": "Dune 1080p Latino\n💾 2.1 GB 🇲🇽", "url": "https://rd.example/a"]]]
        let registry = AddonRegistry(http: http, account: nil, own: { ["https://a.example"] }, clock: { clock.now })
        let finder = StreamFinder(http: http, registry: registry, clock: { clock.now }, local: { await library.sources(kind: $0, videoID: $1) })
        let found = try await finder.find(kind: "movie", videoID: "tt15239678", prefs: Preferences(audio: "es", quality: "1080p"))
        XCTAssertEqual(found.map(\.addon), ["OneDrive", "Torrentio"])
        let best = try await finder.best(kind: "movie", videoID: "tt15239678", prefs: Preferences(audio: "es", quality: "1080p"), binge: "otro")
        XCTAssertEqual(best?.addon, "OneDrive")
    }

    func testWithoutAFolderNothingIsAsked() async {
        let http = FakeHTTP()
        let library = OneDriveLibrary(drive: linkedDrive(http), cinemeta: Cinemeta(http: http), kv: InMemoryKeyValueStore(), folder: { "" })
        let found = await library.sources(kind: "movie", videoID: "tt1")
        XCTAssertTrue(found.isEmpty)
        XCTAssertTrue(http.calls.isEmpty)
    }
}
