import XCTest
@testable import OrbitalCore

/// Letterboxd sin API: el diario (RSS), las listas y la página de cada película (HTML) y el archivo de exportación (.zip con
/// CSV). Las muestras son del formato real (1 nov 2026).
final class LetterboxdTests: XCTestCase {
    static let rss = #"""
<rss><channel><item> <title>The Invite, 2026 - ★★★★</title> <link>https://letterboxd.com/dave/film/the-invite-2026/</link> <guid isPermaLink="false">letterboxd-watch-1567225730</guid> <pubDate>Mon, 2 Nov 2026 03:11:48 +1300</pubDate> <letterboxd:watchedDate>2026-11-01</letterboxd:watchedDate> <letterboxd:rewatch>No</letterboxd:rewatch> <letterboxd:filmTitle>The Invite</letterboxd:filmTitle> <letterboxd:filmYear>2026</letterboxd:filmYear> <letterboxd:memberRating>4.0</letterboxd:memberRating> <letterboxd:memberLike>Yes</letterboxd:memberLike> <tmdb:movieId>950028</tmdb:movieId> <description><![CDATA[ <p><img src="https://a.ltrbxd.com/resized/film-poster/8/5/4/8/3/1/854831-the-invite-2026-0-600-0-900-crop.jpg?v=ee72905e48"/></p> <p>Watched on Sunday November 1, 2026.</p> ]]></description> <dc:creator>Dave Vis</dc:creator> </item>
		
			<item> <title>Primetime, 2026 - ★★★½</title> <link>https://letterboxd.com/dave/film/primetime-2026/</link> <guid isPermaLink="false">letterboxd-watch-1562782832</guid> <pubDate>Sat, 31 Oct 2026 02:24:45 +1300</pubDate> <letterboxd:watchedDate>2026-10-30</letterboxd:watchedDate> <letterboxd:rewatch>No</letterboxd:rewatch> <letterboxd:filmTitle>Primetime</letterboxd:filmTitle> <letterboxd:filmYear>2026</letterboxd:filmYear> <letterboxd:memberRating>3.5</letterboxd:memberRating> <letterboxd:memberLike>No</letterboxd:memberLike> <tmdb:movieId>1375441</tmdb:movieId> <description><![CDATA[ <p><img src="https://a.ltrbxd.com/resized/film-poster/1/2/6/2/0/1/9/1262019-primetime-2026-0-600-0-900-crop.jpg?v=41640d6988"/></p> <p>Watched on Friday October 30, 2026.</p> ]]></description> <dc:creator>Dave Vis</dc:creator> </item>
<item> <title>Roma, 2018 - ★★★★½</title> <link>https://letterboxd.com/fer/film/roma-2018/</link> <guid isPermaLink="false">letterboxd-review-99</guid> <letterboxd:watchedDate>2026-10-20</letterboxd:watchedDate> <letterboxd:rewatch>Yes</letterboxd:rewatch> <letterboxd:filmTitle>Roma</letterboxd:filmTitle> <letterboxd:filmYear>2018</letterboxd:filmYear> <letterboxd:memberRating>4.5</letterboxd:memberRating> <letterboxd:memberLike>Yes</letterboxd:memberLike> <tmdb:movieId>426426</tmdb:movieId> <description><![CDATA[ <p><img src="https://a.ltrbxd.com/x.jpg"/></p> <p><em>This review may contain spoilers.</em></p> <p>Cuar&oacute;n &amp; su casa. Precioso.</p> ]]></description> </item>
<item> <title>Una lista</title> <link>https://letterboxd.com/fer/list/x/</link> <guid isPermaLink="false">letterboxd-list-1</guid> <description>nada</description> </item>
</channel></rss>
"""#
    static let listsPage = #"""
<article class="list-summary js-list-summary js-list" data-film-list-id="1"> <div class="body"> <h2 class="name prettify"> <a href="/fer/list/para-el-domingo/">Para el domingo &amp; algo</a> </h2> <div class="content-reactions-strip -filmlist"> <span class="value">35&nbsp;films</span></div></div></article>
<article class="list-summary js-list-summary js-list" data-film-list-id="2"> <div class="body"> <h2 class="name prettify"> <a href="/fer/list/terror/">Terror</a> </h2> <span class="value">1,204&nbsp;films</span></div></article>
"""#
    static let listPage = #"""
<li class="posteritem"><div class="react-component" data-item-name="The Testament of Ann Lee (2025)" data-item-slug="the-testament-of-ann-lee" data-item-link="/film/the-testament-of-ann-lee/"></div></li>
<li class="posteritem"><div class="react-component" data-item-name="Y tu mam&#225; tambi&#233;n (2001)" data-item-slug="y-tu-mama-tambien" data-item-link="/film/y-tu-mama-tambien/"></div></li>
<li class="posteritem"><div class="react-component" data-item-name="The Testament of Ann Lee (2025)" data-item-slug="the-testament-of-ann-lee"></div></li>
<section class="list js-list -overlapped"><div class="poster-list-overlapped -p70"><li><div data-item-name="Kokuho (2025)" data-item-slug="kokuho"></div></li></div></section>
"""#
    static let filmPage = #"<body class="film" data-tmdb-id="1401281" data-tmdb-type="movie"> <a href="http://www.imdb.com/title/tt34819091/maindetails" data-track-action="IMDb">IMDb</a>"#
    static let zip = "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"

    func testElDiarioTraeEstrellasCorazonOtraVezYReseña() throws {
        let entries = Letterboxd.parseDiary(Self.rss)
        XCTAssertEqual(entries.count, 3, "la lista nueva no es una película")
        let first = try XCTUnwrap(entries.first)
        XCTAssertEqual(first.title, "The Invite")
        XCTAssertEqual(first.year, 2026)
        XCTAssertEqual(first.tmdbID, 950028)
        XCTAssertEqual(first.rating, 4.0)
        XCTAssertEqual(first.traktRating, 8, "★★★★ son 8 en Trakt")
        XCTAssertTrue(first.liked)
        XCTAssertNil(first.review, "«Watched on…» no es una reseña")
        XCTAssertEqual(first.slug, "the-invite-2026")
        let roma = try XCTUnwrap(entries.last)
        XCTAssertEqual(roma.review, "Cuarón & su casa. Precioso.", "sin el aviso de spoilers ni el póster")
        XCTAssertTrue(roma.rewatch)
        XCTAssertEqual(roma.traktRating, 9)
    }

    func testTusListasYSusPeliculas() {
        let lists = Letterboxd.parseLists(Self.listsPage, user: "fer")
        XCTAssertEqual(lists, [LetterboxdList(slug: "para-el-domingo", name: "Para el domingo & algo", count: 35),
                               LetterboxdList(slug: "terror", name: "Terror", count: 1204)])
        let films = Letterboxd.parseFilms(Self.listPage)
        XCTAssertEqual(films, [LetterboxdFilm(slug: "the-testament-of-ann-lee", title: "The Testament of Ann Lee", year: 2025),
                               LetterboxdFilm(slug: "y-tu-mama-tambien", title: "Y tu mamá también", year: 2001)], "sin repetir ni las de otras listas al lado")
        XCTAssertEqual(Letterboxd.parseFilmPage(Self.filmPage), LetterboxdMatch(imdb: "tt34819091", kind: "movie", tmdbID: 1401281))
    }

    func testElUsuarioSeLimpia() {
        XCTAssertEqual(Letterboxd.cleanUser(" @FerIG "), "ferig")
        XCTAssertEqual(Letterboxd.cleanUser("https://letterboxd.com/dave/films/"), "dave")
        XCTAssertNil(Letterboxd.cleanUser("dos palabras"))
    }

    func testLaPaginaDeUnaPeliculaSeRecuerda() async {
        let http = FakeHTTP()
        http.json["https://letterboxd.com/film/roma-2018/"] = .string("x")
        let kv = InMemoryKeyValueStore()
        let lb = Letterboxd(http: http, kv: kv)
        let none = await lb.resolve(slug: "roma-2018")
        XCTAssertNil(none, "sin IMDb en la página, nada")
        kv.set("lb-film.roma-2018", data: try? JSONEncoder().encode(LetterboxdMatch(imdb: "tt6155172", kind: "movie", tmdbID: 426426)))
        let calls = http.calls.count
        let saved = await lb.resolve(slug: "roma-2018")
        XCTAssertEqual(saved?.imdb, "tt6155172")
        XCTAssertEqual(http.calls.count, calls, "lo recordado no se vuelve a pedir")
    }

    func testElArchivoDeExportacionJuntaDiarioReseñasYCalificaciones() throws {
        let archive = try LetterboxdArchive.read(files: [("letterboxd-fer-2026.zip", try XCTUnwrap(Data(base64Encoded: Self.zip)))])
        let dune = try XCTUnwrap(archive.entries.first { $0.title == "Dune: Part Two" })
        XCTAssertEqual(archive.entries.filter { $0.title == "Dune: Part Two" }.count, 1, "el diario, la reseña y la calificación son la misma")
        XCTAssertEqual(dune.rating, 4.5)
        XCTAssertTrue(dune.rewatch)
        XCTAssertEqual(dune.review, "Enorme, otra vez.\nY mejor.")
        XCTAssertEqual(dune.watched, LetterboxdEntry.day("2026-10-01"))
        XCTAssertEqual(archive.entries.first?.title, "Dune: Part Two", "lo más reciente primero")
        let roma = try XCTUnwrap(archive.entries.first { $0.title == "Roma" })
        XCTAssertNil(roma.watched, "calificada sin entrada en el diario: sin fecha")
        XCTAssertEqual(roma.rating, 4)
        XCTAssertEqual(archive.watchlist.map(\.title), ["Perfect Days"])
        XCTAssertEqual(archive.lists.first?.list.name, "Para el domingo")
        XCTAssertEqual(archive.lists.first?.films.map(\.slug), ["roma-2018", "y-tu-mama-tambien"])
        XCTAssertThrowsError(try LetterboxdArchive.read(files: [("otra.csv", Data("a,b\n1,2\n".utf8))]))
    }

    func testCSVConComillasYSaltos() {
        XCTAssertEqual(CSV.rows("a,\"b, c\",\"d\"\"e\"\n1,\"dos\nlíneas\",3\n"), [["a", "b, c", "d\"e"], ["1", "dos\nlíneas", "3"]])
    }

    /// Tus listas de Letterboxd salen en Explorar (junto a las de Trakt) y cada película llega con su IMDb.
    func testTusListasSonEstantesDeExplorar() async throws {
        let http = FakeHTTP(), kv = InMemoryKeyValueStore()
        kv.set(ForYou.letterboxdUserKey, data: Data("fer".utf8))
        http.raw["https://letterboxd.com/fer/lists/"] = Data(Self.listsPage.utf8)
        http.raw["https://letterboxd.com/fer/list/para-el-domingo/"] = Data(Self.listPage.utf8)
        http.raw["https://letterboxd.com/film/the-testament-of-ann-lee/"] = Data(Self.filmPage.utf8)
        http.raw["https://letterboxd.com/film/y-tu-mama-tambien/"] = Data(#"<body data-tmdb-id="1391" data-tmdb-type="movie"><a href="https://www.imdb.com/title/tt0245574/">"#.utf8)
        let fy = ForYou(trakt: nil, tmdb: nil, http: http, region: { "MX" }, kv: kv)
        let lists = await fy.lists()
        let shelf = try XCTUnwrap(lists.first { $0.id == "lb:para-el-domingo" })
        XCTAssertEqual(shelf.title, "Para el domingo & algo")
        XCTAssertEqual(shelf.source, "Letterboxd")
        XCTAssertEqual(shelf.group, .mine)
        let items = try await fy.items(listID: "lb:para-el-domingo")
        XCTAssertEqual(items.map(\.imdb), ["tt34819091", "tt0245574"])
        XCTAssertEqual(items.last?.title, "Y tu mamá también")
    }

    /// Lo que dice Letterboxd de una película (su página real, recortada): el promedio y sus reseñas populares, con quién,
    /// sus estrellas, cuántos «me gusta» y si trae spoilers.
    func testElPromedioYLasReseñasPopulares() throws {
        let html = #"""
        <meta property="og:url" content="https://letterboxd.com/film/dune-part-two/" /><meta name="twitter:data2" content="4.37 out of 5" />
        <body data-tmdb-id="693134">
        <article class="production-viewing -viewing js-production-viewing" data-person="clairersc"> <strong class="displayname">claire</strong>
        <span class="inline-symbol inline-rating"><svg aria-label="★★★★"> <title>★★★★</title></svg></span>
        <p class="body-text -prose js-spoiler-container"><em>This review may contain spoilers.</em></p>
        <div class="body-text -prose -reset js-review-body js-collapsible-text" hidden> <p>damn it sucks when your boyfriend thinks he&#8217;s jesus</p> </div>
        <div class="viewing-actions"><p class="like-link-target" data-count="66624"></p></div></article>
        <article class="production-viewing -viewing" data-person="b"> <strong class="displayname">Bryan</strong>
        <svg aria-label="★★★★½"></svg> <div class="body-text js-review-body"> <p>Need a friend like Stilgar</p> </div>
        <div class="viewing-actions"><p data-count="42829"></p></div></article>
        """#
        let info = try XCTUnwrap(Letterboxd.parseFilmInfo(html))
        XCTAssertEqual(info.slug, "dune-part-two")
        XCTAssertEqual(info.average, 4.37)
        XCTAssertEqual(info.reviews.map(\.author), ["claire", "Bryan"])
        XCTAssertEqual(info.reviews.first?.text, "damn it sucks when your boyfriend thinks he’s jesus")
        XCTAssertEqual(info.reviews.first?.rating, 4)
        XCTAssertEqual(info.reviews.first?.likes, 66624)
        XCTAssertTrue(info.reviews.first?.spoiler == true)
        XCTAssertEqual(info.reviews.last?.rating, 4.5)
        XCTAssertFalse(info.reviews.last?.spoiler == true)
    }

    func testLoQueLetterboxdNoTieneSeRecuerda() async {
        let http = FakeHTTP(), kv = InMemoryKeyValueStore()
        http.statuses["https://letterboxd.com/imdb/tt0903747/"] = 404
        let lb = Letterboxd(http: http, kv: kv)
        let first = await lb.info(imdb: "tt0903747")
        XCTAssertNil(first)
        let calls = http.calls.count
        let again = await lb.info(imdb: "tt0903747")
        XCTAssertNil(again)
        XCTAssertEqual(http.calls.count, calls, "una serie que Letterboxd no tiene no se vuelve a preguntar en días")
    }
}
