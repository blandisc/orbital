import XCTest
@testable import OrbitalCore

/// D6-A · seguir desde Trakt en el punto exacto, igual que la TV: `tests/fixtures/ios/resume_trakt.json` (lo genera
/// `scripts/ios_golden.py` con `trakt.playback_entry` y `trakt.latest_resume`) corrido con las funciones del iPhone
/// (`TraktParsing.playback` y `ResumePoint.latest`).
final class ResumeTraktGoldenTests: XCTestCase {
    /// Cada fila de `/sync/playback`: lo que la TV entiende, el iPhone lo entiende igual (y lo que la TV descarta, también).
    func testPlaybackRowsReadLikeOnTheTV() throws {
        let rows = try XCTUnwrap(try Fixtures.json("ios/resume_trakt.json")["playback"]?.array)
        XCTAssertEqual(rows.count, 6)
        for item in rows {
            // El golden trae la fila sin `id` (la TV no lo usa para leerla); el iPhone lo pide para poder borrarla luego.
            var row = try XCTUnwrap(item["row"])
            if case .object(var fields) = row, fields["id"] == nil { fields["id"] = 1; row = .object(fields) }
            let got = TraktParsing.playback(row)
            guard let key = item["key"]?.string, let info = item["info"] else {
                XCTAssertNil(got, "la TV la descarta: \(row)"); continue
            }
            let playback = try XCTUnwrap(got, key)
            let target = playback.target
            XCTAssertEqual(target.isEpisode ? "\(target.imdb):\(target.season!):\(target.episode!)" : target.imdb, key)
            XCTAssertEqual(playback.progress, try XCTUnwrap(info["percent"]?.doubleValue), accuracy: 1e-9, key)
            XCTAssertEqual(playback.pausedAt.timeIntervalSince1970, try XCTUnwrap(info["paused_at"]?.doubleValue), accuracy: 1e-3, key)
            XCTAssertEqual(playback.runtime.map { Double($0) * 60 }, info["runtime"]?.doubleValue, key)
        }
    }

    /// Lo más reciente entre lo de aquí y la pausa de Trakt, al segundo exacto (sin regresar unos segundos).
    func testLatestResumeMatchesTheTV() throws {
        let cases = try XCTUnwrap(try Fixtures.json("ios/resume_trakt.json")["latest"]?.array)
        XCTAssertEqual(cases.count, 8)
        let video = "tt1160419"
        for (index, c) in cases.enumerated() {
            let seconds = try XCTUnwrap(c["stremio_seconds"]?.doubleValue)
            let when = c["stremio_when"]?.doubleValue, duration = c["duration"]?.doubleValue
            // Lo de este teléfono (en la TV, lo de Stremio): solo si hubo algo.
            var entry: LibraryEntry?
            if when != nil || seconds > 0 {
                var e = LibraryEntry(metaID: video, kind: "movie", name: "Dune")
                e.videoID = video; e.position = seconds; e.duration = duration ?? 0; e.updatedAt = when ?? 0
                entry = e
            }
            var trakt: TraktPlayback?
            var runtime: Double?
            if let t = c["trakt"], t.object != nil {
                runtime = t["runtime"]?.doubleValue
                trakt = TraktPlayback(id: 1, progress: try XCTUnwrap(t["percent"]?.doubleValue),
                                      pausedAt: Date(timeIntervalSince1970: try XCTUnwrap(t["paused_at"]?.doubleValue)),
                                      target: TraktTarget(imdb: video), runtime: runtime.map { Int($0 / 60) })
            }
            let point = ResumePoint.latest(local: entry, videoID: video, trakt: trakt)
            // Sin la duración del archivo, la TV usa la de Trakt; el reproductor del iPhone, la del video (la misma aquí).
            let got = point.seconds(duration: duration ?? runtime ?? 0)
            XCTAssertEqual(got, try XCTUnwrap(c["seconds"]?.doubleValue), accuracy: 1e-6, "caso \(index + 1): \(c)")
        }
    }
}
