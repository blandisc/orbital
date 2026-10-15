import XCTest
@testable import OrbitalCore

final class StremioLibraryTests: XCTestCase {
    func testZlibReadsWhatPythonWrites() throws {
        for (i, c) in try XCTUnwrap(Fixtures.json("ios/zlib.json").array).enumerated() {
            let raw = [UInt8](try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(c["raw_b64"]?.string))))
            for key in ["zlib_b64", "zlib0_b64", "zlib9_b64"] {
                let packed = [UInt8](try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(c[key]?.string))))
                XCTAssertEqual(try Zlib.decompress(packed), raw, "caso \(i) \(key)")
            }
            XCTAssertEqual(try Zlib.decompress(Zlib.compressStored(raw)), raw, "ida y vuelta, caso \(i)")
        }
    }

    func testZlibRejectsDamagedData() {
        XCTAssertThrowsError(try Zlib.decompress([1, 2, 3]))
        var packed = Zlib.compressStored([1, 2, 3, 4])
        packed[packed.count - 1] ^= 0xff
        XCTAssertThrowsError(try Zlib.decompress(packed))
    }

    func testWatchedBitfieldMatchesPython() throws {
        for (i, c) in try XCTUnwrap(Fixtures.json("ios/watched.json").array).enumerated() {
            let ids = try XCTUnwrap(c["video_ids"]?.array).compactMap(\.string)
            let seen = Set(try XCTUnwrap(c["seen"]?.array).compactMap(\.string))
            let encoded = c["encoded"]?.string
            // Leer lo que escribió Python.
            let parsed = Set(try XCTUnwrap(c["parsed"]?.array).compactMap(\.string))
            XCTAssertEqual(StremioLibrary.parseWatched(encoded, videoIDs: ids), parsed, "leer, caso \(i)")
            // Lo que escribimos nosotros lo lee el mismo código (y tiene el mismo ancla y largo).
            let mine = StremioLibrary.encodeWatched(seen, videoIDs: ids)
            if i == 6 { continue }  // el catálogo cambió de largo: solo se prueba la lectura con el ancla
            XCTAssertEqual(mine == nil, encoded == nil, "caso \(i)")
            if let mine, let encoded {
                XCTAssertEqual(mine.split(separator: ":").dropLast().joined(separator: ":"),
                               encoded.split(separator: ":").dropLast().joined(separator: ":"), "ancla y largo, caso \(i)")
                if c["video_ids"]?.array?.count == ids.count, parsed == seen {
                    XCTAssertEqual(StremioLibrary.parseWatched(mine, videoIDs: ids), seen, "ida y vuelta, caso \(i)")
                }
            }
        }
    }

    func testWithProgressMatchesPython() throws {
        for (i, c) in try XCTUnwrap(Fixtures.json("ios/progress.json").array).enumerated() {
            let a = try XCTUnwrap(c["args"])
            let raw = c["raw"].flatMap { $0.isNull ? nil : $0 }
            let result = StremioLibrary.withProgress(
                raw, metaID: a["meta_id"]!.string!, kind: a["kind"]!.string!, name: a["name"]!.string!, poster: a["poster"]?.string,
                videoID: a["video_id"]!.string!, position: number(a["position"]), duration: number(a["duration"]),
                watched: number(a["watched"]), nextVideo: a["next_video"]?.string, now: number(a["now"]),
                videoIDs: a["video_ids"]?.array?.compactMap(\.string))
            // Los bytes comprimidos de `watched` pueden diferir (Python comprime, aquí se guardan sin comprimir):
            // lo que cuenta es que signifiquen lo mismo.
            let ids = a["video_ids"]?.array?.compactMap(\.string) ?? []
            XCTAssertEqual(normalized(result, ids), normalized(try XCTUnwrap(c["result"]), ids), "caso \(i)")
        }
    }

    func testResumeSecondsMatchesPython() throws {
        for (i, c) in try XCTUnwrap(Fixtures.json("ios/resume.json").array).enumerated() {
            let raw = c["raw"].flatMap { $0.isNull ? nil : $0 }
            XCTAssertEqual(StremioLibrary.resumeSeconds(raw, videoID: c["video_id"]!.string!), number(c["seconds"]), accuracy: 1e-9, "caso \(i)")
        }
    }

    func testLibraryToggleAndDismissMatchPython() throws {
        let cases = try XCTUnwrap(Fixtures.json("ios/toggle.json").array)
        for c in cases.prefix(2) {
            let a = try XCTUnwrap(c["args"])
            let raw = c["raw"].flatMap { $0.isNull ? nil : $0 }
            let result = StremioLibrary.libraryToggled(raw, metaID: a["meta_id"]!.string!, kind: a["kind"]!.string!, name: a["name"]!.string!,
                                                       poster: a["poster"]?.string, add: c["add"]!.bool!, now: number(a["now"]))
            XCTAssertEqual(result, c["result"])
        }
        let d = cases[2]
        XCTAssertEqual(StremioLibrary.dismissed(try XCTUnwrap(d["dismiss_input"]), now: NOW), d["result"])
    }

    func testParseItemMatchesPython() throws {
        for (i, c) in try XCTUnwrap(Fixtures.json("ios/parse_item.json").array).enumerated() {
            let w = StremioLibrary.parseItem(try XCTUnwrap(c["raw"]))
            guard let expected = c["result"], !expected.isNull else { XCTAssertNil(w, "caso \(i)"); continue }
            let got = try XCTUnwrap(w, "caso \(i)")
            XCTAssertEqual(got.id, expected["id"]?.string)
            XCTAssertEqual(got.type, expected["type"]?.string)
            XCTAssertEqual(got.name, expected["name"]?.string)
            XCTAssertEqual(got.poster, expected["poster"]?.string)
            XCTAssertEqual(got.videoID, expected["video_id"]?.string)
            XCTAssertEqual(got.timeOffset, expected["time_offset"]?.intValue)
            XCTAssertEqual(got.duration, expected["duration"]?.intValue)
            XCTAssertEqual(got.inContinue, expected["in_continue"]?.bool)
            XCTAssertEqual(got.inLibrary, expected["in_library"]?.bool)
            XCTAssertEqual(got.episode.season, expected["season"]?.intValue, "caso \(i)")
            XCTAssertEqual(got.episode.episode, expected["episode"]?.intValue, "caso \(i)")
            XCTAssertEqual(got.lastWatched ?? -1, expected["last_watched"].flatMap { $0.isNull ? nil : number($0) } ?? -1, accuracy: 0.001)
            XCTAssertEqual(got.progress ?? -1, expected["progress"].flatMap { $0.isNull ? nil : number($0) } ?? -1, accuracy: 1e-9)
        }
    }

    func testISOMatchesPython() {
        XCTAssertEqual(StremioLibrary.iso(NOW), "2025-10-09T08:53:20.000Z")
        XCTAssertEqual(StremioLibrary.iso(1_760_000_000.678), "2025-10-09T08:53:20.678Z")
    }
}

func number(_ json: JSON?) -> Double {
    switch json {
    case .int(let i)?: return Double(i)
    case .double(let d)?: return d
    default: return 0
    }
}

/// El item con `state.watched` convertido a los episodios que marca (para compararlo sin depender de los bytes).
func normalized(_ item: JSON, _ ids: [String]) -> JSON {
    guard var object = item.object, var state = object["state"]?.object else { return item }
    if let watched = state["watched"]?.string {
        state["watched"] = .array(StremioLibrary.parseWatched(watched, videoIDs: ids).sorted().map(JSON.string))
    }
    object["state"] = .object(state)
    return .object(object)
}
