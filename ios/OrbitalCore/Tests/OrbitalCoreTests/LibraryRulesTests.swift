import XCTest
@testable import OrbitalCore

final class LibraryRulesTests: XCTestCase {
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
            let encoded = c["encoded"]?.string
            // Leer lo que escribió Python.
            let parsed = Set(try XCTUnwrap(c["parsed"]?.array).compactMap(\.string))
            XCTAssertEqual(LibraryRules.parseWatched(encoded, videoIDs: ids), parsed, "leer, caso \(i)")
        }
    }

    func testISOMatchesPython() {
        XCTAssertEqual(LibraryRules.iso(NOW), "2025-10-09T08:53:20.000Z")
        XCTAssertEqual(LibraryRules.iso(1_760_000_000.678), "2025-10-09T08:53:20.678Z")
    }
}

func number(_ json: JSON?) -> Double {
    switch json {
    case .int(let i)?: return Double(i)
    case .double(let d)?: return d
    default: return 0
    }
}
