import XCTest
@testable import OrbitalCore

/// F2 · Las reglas para elegir versión son las de `design/streams-rules.json`, las mismas que lee la TV: banderas, palabras,
/// códigos, sitios, topes de tamaño y esperas. La app no lee el repo al correr; si alguien cambia el archivo y no el iPhone
/// (o al revés), esto falla. Y los goldens de la TV (`streams_rules.json`, `streams_marks.json`) corridos con el iPhone.
final class StreamsRulesTests: XCTestCase {
    func rules() throws -> [String: Any] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        let data = try Data(contentsOf: url.appendingPathComponent("design/streams-rules.json"))
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// (patrón, sin distinguir mayúsculas, idioma) de una lista de reglas.
    func patterns(_ list: Any?) throws -> [String] {
        try XCTUnwrap(list as? [[String: Any]]).map { "\($0["pattern"] as? String ?? "?") /\($0["flags"] as? String ?? "?")/ \($0["lang"] as? String ?? "?")" }
    }

    func patterns(_ list: [(NSRegularExpression, String)]) -> [String] {
        list.map { "\($0.0.pattern) /\($0.0.options.contains(.caseInsensitive) ? "i" : "")/ \($0.1)" }
    }

    func testVersionIsTheOneTheIPhoneKnows() throws {
        XCTAssertEqual(try rules()["version"] as? Int, 1, "una versión nueva de las reglas: revisar el iPhone")
    }

    func testFlagsWordsCodesAndSites() throws {
        let rules = try rules()
        let flags = try XCTUnwrap(rules["flags"] as? [String: String])
        XCTAssertEqual(Dictionary(Streams.flagLanguages, uniquingKeysWith: { a, _ in a }), flags, "`flags`")
        XCTAssertEqual(Streams.flagLanguages.count, flags.count, "una bandera repetida en el iPhone")
        // En orden: la primera que coincide gana.
        XCTAssertEqual(patterns(Streams.wordLanguages + Streams.moreWordLanguages), try patterns(rules["words"]), "`words`")
        XCTAssertEqual(patterns(Streams.codeLanguages), try patterns(rules["codes"]), "`codes`")
        XCTAssertEqual(Streams.siteLanguages, try XCTUnwrap(rules["sites"] as? [String: String]), "`sites`")
    }

    func testSizeCapsAndWaits() throws {
        let rules = try rules()
        let size = try XCTUnwrap(rules["size"] as? [String: Any])
        XCTAssertEqual(Streams.SizeRule.tooBig, try XCTUnwrap(size["too_big_gb"] as? [String: Double]))
        XCTAssertEqual(Streams.SizeRule.tooBigDefault, size["too_big_default_gb"] as? Double)
        XCTAssertEqual(Streams.SizeRule.seriesFactor, size["series_factor"] as? Double)
        let small = try XCTUnwrap(size["too_small_gb"] as? [String: Double])
        XCTAssertEqual(Streams.SizeRule.tooSmallMovie, small["movie"])
        XCTAssertEqual(Streams.SizeRule.tooSmallSeries, small["series"])
        // `unify` › size.too_big_gb.1440p: una 1440p tiene el tope de 1080p (25 GB), no el de «sin calidad» (15).
        XCTAssertEqual(Streams.tooBigGB("1440p", kind: "movie"), 25)
        XCTAssertEqual(Streams.tooBigGB("1440p", kind: "series"), 25 * 0.3, accuracy: 1e-9)
        XCTAssertEqual(Streams.tooBigGB("720p", kind: "movie"), 15)
        let waits = try XCTUnwrap(rules["waits"] as? [String: Any])
        XCTAssertEqual(StreamFinder.perAddonWait, waits["per_addon_s"] as? Double)
        XCTAssertEqual(SearchLimits().perAddon, StreamFinder.perAddonWait)
        XCTAssertEqual(StreamFinder.slowAfter, waits["find_deadline_s"] as? Double)
    }

    /// `unify`: lo que ya cambió el iPhone dice que está en las dos.
    func testUnifyIsDoneOnTheIPhone() throws {
        let unify = try XCTUnwrap(try rules()["unify"] as? [[String: Any]])
        for rule in unify where rule["changes"] as? String == "ios" {
            XCTAssertFalse((rule["estado"] as? String ?? "").contains("pendiente"), "\(rule["rule"] ?? "?") sigue pendiente en el iPhone")
        }
    }

    func parse(_ streams: [JSON]) -> [Source] {
        streams.enumerated().map { Streams.parse($1, addon: "Torrentio", transportURL: "https://t.example/manifest.json", index: $0) }
    }

    /// Tu orden de idiomas, la calidad (también 1440p) y el idioma original: el mismo orden, puntaje y resolución que la TV.
    func testRulesGoldenRanksLikeTheTV() throws {
        let cases = try XCTUnwrap(Fixtures.json("ios/streams_rules.json").array)
        XCTAssertEqual(cases.count, 30)
        var skipped = 0
        defer { XCTAssertEqual(skipped, 6, "solo los de «original» primero") }
        for c in cases {
            let languages = try XCTUnwrap(c["languages"]?.array?.compactMap(\.string))
            let quality = try XCTUnwrap(c["quality"]?.string), kind = try XCTUnwrap(c["kind"]?.string)
            // «Idioma original» hasta arriba no existe en el iPhone (Ajustes › Tus idiomas no lo deja: el primero es tu idioma,
            // `AppSettings.setLanguages`); la TV lo toma como un idioma llamado «original». Esos casos no aplican aquí.
            if languages.first == "original" { skipped += 1; continue }
            // Como `streams.prefs_from_languages` de la TV: el primero es tu idioma (con su doblaje) y lo demás, el plan B.
            let first = languages[0], spanish = Streams.spanishVariants.contains(first)
            var prefs = Preferences(audio: spanish ? "es" : first, quality: quality, spanish: spanish ? first : "")
            prefs.languages = languages
            var sources = parse(try XCTUnwrap(c["streams"]?.array))
            for i in sources.indices { sources[i].originalLanguage = c["original"]?.string }
            let ranked = Streams.rank(sources, prefs: prefs, kind: kind)
            let label = "\(languages) \(quality) \(kind)"
            XCTAssertEqual(ranked.map(\.index), c["order"]?.array?.compactMap(\.intValue), "orden \(label)")
            for s in ranked {
                XCTAssertEqual(s.score, try XCTUnwrap(c["scores"]?[String(s.index)]?.doubleValue), accuracy: 1e-9, "puntaje \(s.index) \(label)")
                XCTAssertEqual(s.resolution, c["resolution"]?[String(s.index)]?.string, "resolución \(s.index) \(label)")
            }
        }
    }

    /// Las marcas de idioma que la TV aprendió del iPhone (banderas latinas, «[lat]», «Esp-Cast», «Homero»…): lo mismo aquí.
    func testMarksGoldenReadsLikeTheTV() throws {
        let cases = try XCTUnwrap(Fixtures.json("ios/streams_marks.json").array)
        XCTAssertEqual(cases.count, 18)
        for (i, c) in cases.enumerated() {
            let s = Streams.parse(try XCTUnwrap(c["stream"]), addon: "Torrentio", transportURL: "https://t.example/manifest.json", index: i)
            let title = c["stream"]?["title"]?.string ?? ""
            XCTAssertEqual(Dictionary(s.audio.map { ($0.code, $0.evidence.tv) }, uniquingKeysWith: { a, _ in a }),
                           c["audio_langs"]?.object?.compactMapValues(\.string), "audio_langs \(title)")
            XCTAssertEqual(s.languages, c["languages"]?.array?.compactMap(\.string), "idiomas \(title)")
            XCTAssertEqual(s.dub, c["dub"]?.string, "doblaje \(title)")
        }
    }
}
