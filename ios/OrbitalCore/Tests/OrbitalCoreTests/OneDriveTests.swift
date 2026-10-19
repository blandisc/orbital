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

    func testLibraryGroupsTitlesWithVersionsAndPicksPerPurpose() async throws {
        let http = FakeHTTP(), clock = Clock()
        let drive = linkedDrive(http, clock: clock)
        http.json[children("Pelis")] = ["value": [
            ["id": "a1", "name": "Dune Part Two (2024) 2160p HDR.mkv", "size": 40_000_000_000, "file": [:], "createdDateTime": "2026-10-16T20:00:00Z"],
            ["id": "a0", "name": "Dune Part Two (2024) 1080p.mkv", "size": 8_000_000_000, "file": [:], "createdDateTime": "2026-10-16T20:00:00Z"],
            ["id": "a2", "name": "Severance.S01E03.mkv", "size": 900_000_000, "file": [:], "createdDateTime": "2026-10-17T09:00:00.123Z"],
            ["id": "a3", "name": "Severance.S01E04.mkv", "size": 900_000_000, "file": [:]],
            ["id": "a4", "name": "Vacaciones 2019.mp4", "size": 100, "file": [:]]]]
        http.json["https://v3-cinemeta.strem.io/catalog/movie/top/search=Dune%20Part%20Two.json"] = ["metas": [
            ["id": "tt0000001", "type": "movie", "name": "Dune", "releaseInfo": "2021"],
            ["id": "tt15239678", "type": "movie", "name": "Dune: Part Two", "releaseInfo": "2024", "poster": "https://p/dune.jpg"]]]
        http.json["https://v3-cinemeta.strem.io/catalog/series/top/search=Severance.json"] = ["metas": [["id": "tt11280740", "type": "series", "name": "Severance", "releaseInfo": "2022-"]]]
        http.json["https://v3-cinemeta.strem.io/catalog/movie/top/search=Vacaciones.json"] = ["metas": [["id": "tt9", "type": "movie", "name": "Vacation", "releaseInfo": "2015"]]]
        http.json["\(OneDrive.graph)/me/drive/items/a0?$select=id,@microsoft.graph.downloadUrl"] = ["@microsoft.graph.downloadUrl": "https://public.onedrive.example/a0"]
        http.json["\(OneDrive.graph)/me/drive/items/a1?$select=id,@microsoft.graph.downloadUrl"] = ["@microsoft.graph.downloadUrl": "https://public.onedrive.example/a1"]

        let library = OneDriveLibrary(drive: drive, cinemeta: Cinemeta(http: http), kv: InMemoryKeyValueStore(), folder: { "Pelis" }, clock: { clock.now })
        let index = try await library.scan()
        XCTAssertEqual(index.entries.count, 4)
        XCTAssertEqual(index.unmatchedFiles?.map(\.name), ["Vacaciones 2019.mp4"], "con año, solo una ficha de ese año (±1): si no, sin ficha")
        XCTAssertEqual(http.calls.filter { $0.contains("search=Severance") }.count, 1, "una serie se busca una vez, no por episodio")

        let titles = library.titles()
        XCTAssertEqual(titles.map(\.id), ["series:tt11280740", "movie:tt15239678"], "lo más reciente primero")
        XCTAssertEqual(titles.last?.name, "Dune: Part Two")
        XCTAssertEqual(titles.last?.entries.map(\.file.id), ["a1", "a0"], "la mejor versión primero")
        XCTAssertEqual(titles.last?.bestResolution, "4K")
        XCTAssertEqual(library.pick("tt15239678", purpose: .watch)?.file.id, "a1", "para ver, la mejor")
        XCTAssertEqual(library.pick("tt15239678", purpose: .download)?.file.id, "a0", "para bajar al iPhone, la de 1080p")
        let watch = await library.source("tt15239678", purpose: .watch)
        XCTAssertEqual(watch?.playbackURL?.absoluteString, "https://public.onedrive.example/a1")
        XCTAssertEqual(watch?.addon, OneDriveLibrary.addonName)
        let chosen = await library.source("tt15239678", purpose: .watch, preferring: OneDriveLibrary.describe(index.entries.first { $0.file.id == "a0" }!.file).index)
        XCTAssertEqual(chosen?.playbackURL?.absoluteString, "https://public.onedrive.example/a0", "la versión que elegiste")
        XCTAssertEqual(library.versions("tt11280740:1:3").count, 1)
        let refreshed = await library.refreshURL(release: "Dune Part Two (2024) 1080p.mkv")
        XCTAssertEqual(refreshed?.absoluteString, "https://public.onedrive.example/a0", "una descarga de Mi media renueva su enlace por el nombre del archivo")
    }

    func testAFixIsRememberedForEveryFileWithThatName() async throws {
        let http = FakeHTTP(), clock = Clock(), kv = InMemoryKeyValueStore()
        let drive = linkedDrive(http, clock: clock)
        http.json[children("Pelis")] = ["value": [["id": "a4", "name": "Vacaciones 2019.mp4", "size": 100, "file": [:]]]]
        http.json["https://v3-cinemeta.strem.io/catalog/movie/top/search=Vacaciones.json"] = ["metas": []]
        let library = OneDriveLibrary(drive: drive, cinemeta: Cinemeta(http: http), kv: kv, folder: { "Pelis" }, clock: { clock.now })
        let first = try await library.scan()
        XCTAssertEqual(first.unmatched, 1)
        let info = try XCTUnwrap(first.unmatchedFiles?.first?.info)
        await library.fix(info, to: .init(imdb: "tt0085995", name: "National Lampoon's Vacation", poster: nil, year: "1983"))
        XCTAssertEqual(library.titles().map(\.imdb), ["tt0085995"], "al momento, sin volver a leer la carpeta")
        XCTAssertEqual(library.saved?.unmatched, 0)
        let again = try await library.scan()
        XCTAssertEqual(again.entries.map(\.imdb), ["tt0085995"], "y en la siguiente revisión")
        XCTAssertEqual(http.calls.filter { $0.contains("search=Vacaciones") }.count, 1, "lo corregido ya no se busca")
    }

    func testWithoutAFolderNothingIsAsked() async {
        let http = FakeHTTP()
        let library = OneDriveLibrary(drive: linkedDrive(http), cinemeta: Cinemeta(http: http), kv: InMemoryKeyValueStore(), folder: { "" })
        let refreshed = await library.refreshIfStale()
        XCTAssertFalse(refreshed)
        XCTAssertNil(library.saved)
        XCTAssertTrue(http.calls.isEmpty)
    }
}
