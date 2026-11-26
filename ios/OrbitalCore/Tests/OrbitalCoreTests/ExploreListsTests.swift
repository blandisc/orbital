import XCTest
@testable import OrbitalCore

/// «Esta semana» en Explorar: la tabla de `listas/explorar.json` se lee bien, cada lista tiene una sola fuente y sus fechas, las
/// de temporada salen en su temporada (también las que cruzan el año) y las demás rotan sin repetirse hasta dar la vuelta.
final class ExploreListsTests: XCTestCase {
    /// La tabla de verdad, la del repositorio (la misma que lee la TV).
    func repoTable() throws -> ExploreTable {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" && !FileManager.default.fileExists(atPath: url.appendingPathComponent("listas/explorar.json").path) {
            url.deleteLastPathComponent()
        }
        let data = try Data(contentsOf: url.appendingPathComponent("listas/explorar.json"))
        return try XCTUnwrap(ExploreTable.parse(data), "listas/explorar.json no se lee")
    }

    func day(_ s: String) -> Date {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]; f.timeZone = TimeZone(identifier: "UTC")
        return f.date(from: s)!
    }
    var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

    func testLaTablaDelRepositorioEstaBien() throws {
        let table = try repoTable()
        XCTAssertGreaterThan(table.rotate, 0)
        XCTAssertEqual(Set(table.lists.map(\.id)).count, table.lists.count, "ids repetidos")
        let canon = Set(Canon.lists.map(\.id) + Canon.awards().map(\.id))
        for list in table.lists {
            XCTAssertFalse(canon.contains(list.id), "\(list.id) choca con una colección")
            let sources = [list.mdblist != nil, list.trakt != nil, list.items != nil].filter { $0 }.count
            XCTAssertEqual(sources, 1, "\(list.id): una sola fuente")
            if let s = list.mdblist ?? list.trakt { XCTAssertEqual(s.split(separator: "/").count, 2, "\(list.id): usuario/lista") }
            XCTAssertEqual(list.from == nil, list.to == nil, "\(list.id): las dos fechas o ninguna")
            if let from = list.from, let to = list.to {
                XCTAssertNotNil(ExploreList.monthDay(from), "\(list.id): \(from)"); XCTAssertNotNil(ExploreList.monthDay(to), "\(list.id): \(to)")
            }
            XCTAssertFalse(list.title.isEmpty || list.about.isEmpty, "\(list.id): nombre y de qué se trata")
            for e in list.items ?? [] {
                XCTAssertTrue(e.id.range(of: "^tt\\d+(:\\d+:\\d+)?$", options: .regularExpression) != nil, "\(list.id): \(e.id)")
                XCTAssertEqual(e.kind == "episode", e.id.contains(":"), "\(list.id): \(e.id) y su tipo")
            }
        }
        XCTAssertTrue(table.lists.contains { !$0.dated }, "hay listas que rotan")
    }

    /// Ninguna tarjeta gris (Fernando, 23 nov 2026): cada lista dice su ícono y su color, y ese ícono existe en la app.
    func testCadaListaTieneSuIconoYExiste() throws {
        var root = URL(fileURLWithPath: #filePath)
        while root.path != "/" && !FileManager.default.fileExists(atPath: root.appendingPathComponent("listas/explorar.json").path) { root.deleteLastPathComponent() }
        let assets = root.appendingPathComponent("ios/App/Resources/Assets.xcassets/Collections")
        for list in try repoTable().lists {
            let art = try XCTUnwrap(list.art, "\(list.id): sin «art»")
            XCTAssertTrue(FileManager.default.fileExists(atPath: assets.appendingPathComponent("\(art).imageset").path), "\(list.id): no hay ícono «\(art)»")
        }
    }

    /// Una lista con orden («la n.º 1») va en el orden de la fuente: la AFI empieza con Citizen Kane y acaba con Ben-Hur (en
    /// MDBList venía al revés; por eso va escrita en la tabla).
    func testLaAFIVaEnSuOrden() throws {
        let afi = try XCTUnwrap(try repoTable().lists.first { $0.id == "afi-100" }?.items)
        XCTAssertEqual(afi.count, 100)
        XCTAssertEqual(afi.first?.title, "Citizen Kane")
        XCTAssertEqual(afi.last?.title, "Ben-Hur")
        XCTAssertEqual(Set(afi.map(\.id)).count, 100)
    }

    func testLasDeTemporadaSalenEnSuTemporadaYPrimero() throws {
        let table = try repoTable()
        let october = table.thisWeek(day("2026-10-15"), calendar: utc).map(\.id)
        XCTAssertEqual(october.first, "simpsons-halloween")
        XCTAssertFalse(october.contains("simpsons-navidad"))
        // Cruza el año: del 1 de diciembre al 6 de enero.
        XCTAssertTrue(table.thisWeek(day("2027-01-03"), calendar: utc).map(\.id).contains("simpsons-navidad"))
        XCTAssertFalse(table.thisWeek(day("2026-11-23"), calendar: utc).contains { $0.dated })
    }

    func testLasDemasRotanYPasanTodasAntesDeRepetir() {
        let wheel = (1...6).map { ExploreList(id: "l\($0)", title: "L\($0)", about: "x", mdblist: "u/l\($0)") }
        let table = ExploreTable(rotate: 4, lists: wheel)
        let monday = day("2026-11-23")
        let thisWeek = table.thisWeek(monday, calendar: utc).map(\.id)
        XCTAssertEqual(thisWeek.count, 4)
        XCTAssertEqual(table.thisWeek(monday.addingTimeInterval(6 * 86400), calendar: utc).map(\.id), thisWeek, "igual toda la semana")
        let next = table.thisWeek(monday.addingTimeInterval(7 * 86400), calendar: utc).map(\.id)
        XCTAssertNotEqual(next, thisWeek)
        XCTAssertEqual(Set(thisWeek + next), Set(wheel.map(\.id)), "en dos semanas pasan las seis")
    }

    /// La misma rueda que la TV (`tests/test_weekly.py`): el lunes 23 nov 2026 es la semana 2968 → empieza en la quinta.
    func testIgualQueLaTV() {
        let table = ExploreTable(rotate: 4, lists: (0..<6).map { ExploreList(id: "l\($0)", title: "L", about: "x", mdblist: "u/l") })
        XCTAssertEqual(table.thisWeek(day("2026-11-23"), calendar: utc).map(\.id), ["l4", "l5", "l0", "l1"])
    }

    func testUnCapituloAbreSuSerieYLlevaSuPoster() {
        let item = CanonCollection.Item(imdb: "tt0096697:2:3", kind: "episode", title: "La casita del horror I", year: 1990)
        XCTAssertEqual(item.episode?.show, "tt0096697")
        XCTAssertEqual(item.episode?.video, "tt0096697:2:3")
        XCTAssertEqual(item.poster, String(format: ForYou.metahubPoster, "tt0096697"))
        XCTAssertNil(CanonCollection.Item(imdb: "tt0111161", kind: "movie", title: "Sueño de fuga", year: 1994).episode)
    }

    /// «Hoy» (LD-C, 25 nov 2026): cada receta tiene nombre en los dos idiomas, un ícono que existe, géneros que el filtro
    /// conoce, y cada día salen dos distintas; ninguna se repite antes de que pasen todas.
    func testLasRecetasDeHoyRotanYEstanBien() throws {
        let table = try repoTable()
        let recipes = try XCTUnwrap(table.recipes)
        XCTAssertGreaterThanOrEqual(recipes.count, 20)
        XCTAssertEqual(Set(recipes.map(\.id)).count, recipes.count, "dos recetas con el mismo id")
        let slugs = Set(Tmdb.filterGenres.map(\.slug))
        for r in recipes {
            XCTAssertNotNil(r.en, "\(r.id) sin inglés")
            XCTAssertTrue(r.filter.genres.isSubset(of: slugs), "\(r.id): género que no existe")
        }
        // Cada día una por ánimo primero (Fernando, 26 nov 2026: «cuando te sientas triste, películas feel good»), y cada rueda
        // pasa todas antes de repetir.
        let n = table.daily ?? 2, day = 86400.0
        let moods = recipes.filter { $0.id.hasPrefix(ExploreTable.moodPrefix) }
        XCTAssertGreaterThanOrEqual(moods.count, 6, "pocas listas por ánimo")
        var seenMoods: [String] = [], seenRest: [String] = []
        for d in 0..<moods.count {
            let today = table.recipesToday(Date(timeIntervalSince1970: Double(d) * day + 3600))
            XCTAssertEqual(today.count, n)
            XCTAssertTrue(today.first?.id.hasPrefix(ExploreTable.moodPrefix) ?? false, "el día \(d) no empieza con una por ánimo")
            seenMoods += today.prefix(1).map(\.id); seenRest += today.dropFirst().map(\.id)
        }
        XCTAssertEqual(Set(seenMoods).count, seenMoods.count, "se repitió una por ánimo antes de que pasaran todas")
        XCTAssertEqual(Set(seenRest).count, seenRest.count, "se repitió una receta antes de que pasaran todas")
    }
}

/// IV-B: un toque en Idioma pasa al siguiente audio; en Subtítulos, los quita o pone los de tu idioma.
final class TrackCycleTests: XCTestCase {
    typealias T = OrbitalRemote.NowPlaying.Track
    func testIdiomaPasaAlSiguienteYDaLaVuelta() {
        let a = [T(id: "1", label: "Español (Latino)", selected: true), T(id: "2", label: "Inglés", selected: false)]
        XCTAssertEqual(TrackCycle.nextAudio(a), "2")
        XCTAssertEqual(TrackCycle.nextAudio([T(id: "1", label: "x", selected: false), T(id: "2", label: "y", selected: true)]), "1")
        XCTAssertNil(TrackCycle.nextAudio([T(id: "1", label: "Inglés", selected: true)]))
    }
    func testSubtitulosSeQuitanOPonenLosTuyos() {
        let s = [T(id: "a", label: "Inglés · SDH", selected: false), T(id: "b", label: "Español", selected: false)]
        XCTAssertEqual(TrackCycle.toggleSubtitles(s), "b")
        XCTAssertEqual(TrackCycle.toggleSubtitles(s, language: "en"), "a")
        XCTAssertEqual(TrackCycle.toggleSubtitles([T(id: "a", label: "Inglés", selected: true)]), "no")
        XCTAssertEqual(TrackCycle.toggleSubtitles([T(id: "a", label: "Francés", selected: false)]), "a")
        XCTAssertNil(TrackCycle.toggleSubtitles([]))
    }

    /// Palabras completas: «Estonio» no cuenta como español ni «Endonesio» como inglés (26 nov 2026).
    func testSubtitulosBuscanElIdiomaPorPalabraCompleta() {
        let s = [T(id: "et", label: "Estonio", selected: false), T(id: "es", label: "Español", selected: false), T(id: "en", label: "English", selected: false)]
        XCTAssertEqual(TrackCycle.toggleSubtitles(s), "es")
        XCTAssertEqual(TrackCycle.toggleSubtitles([T(id: "x", label: "Endonesio", selected: false), s[2]], language: "en"), "en")
    }

    /// Regla «Una tecla del control no se parte en dos renglones»: el nombre de la pista llega en una palabra.
    func testElNombreDeLaPistaCabeEnUnaPalabra() {
        for (label, want) in [("Español latino", "Latino"), ("Español (España)", "Castellano"), ("Inglés 5.1 · SDH", "Inglés"),
                              ("Inglés · Subtítulos · de Netflix", "Inglés"), ("Japanese", "Japanese")] {
            XCTAssertEqual(TrackCycle.short(label), want)
            XCTAssertFalse(TrackCycle.short(label).contains(" "), label)
        }
    }
}
