import XCTest
@testable import OrbitalCore

/// La ficha rica de TMDB: elenco, clasificación, tráiler, recomendaciones, dónde verlo y personas.
final class TitleExtrasTests: XCTestCase {
    let movie: JSON = [
        "id": 438631, "vote_average": .double(7.8), "vote_count": 12000,
        "production_companies": [["name": "Legendary Pictures", "logo_path": "/leg.png"]],
        "credits": [
            "cast": [["id": 1, "name": "Timothée Chalamet", "character": "Paul Atreides", "profile_path": "/t.jpg"],
                     ["id": 2, "name": "Zendaya", "character": "Chani", "profile_path": .null]],
            "crew": [["id": 3, "name": "Denis Villeneuve", "job": "Director"], ["id": 3, "name": "Denis Villeneuve", "job": "Screenplay"],
                     ["id": 4, "name": "Frank Herbert", "job": "Novel"], ["id": 5, "name": "Alguien", "job": "Editor"]]],
        "release_dates": ["results": [
            ["iso_3166_1": "US", "release_dates": [["certification": "PG-13"]]],
            ["iso_3166_1": "MX", "release_dates": [["certification": ""], ["certification": "B"]]]]],
        "videos": ["results": [
            ["site": "YouTube", "key": "featurette1", "type": "Featurette", "name": "Así se hizo"],
            ["site": "Vimeo", "key": "x", "type": "Trailer"],
            ["site": "YouTube", "key": "trailer1", "type": "Trailer", "name": "Tráiler oficial"]]],
        "recommendations": ["results": [["id": 693134, "title": "Dune: Part Two", "poster_path": "/d2.jpg", "release_date": "2024-02-27"], ["id": 9, "title": ""]]],
        "watch/providers": ["results": ["MX": ["flatrate": [["provider_name": "HBO Max", "logo_path": "/max.png"]]]]],
    ]

    func testParsesWhatTheRichPageShows() {
        let x = Tmdb.parseExtras(movie, kind: "movie", region: "MX")
        XCTAssertEqual(x.cast.map(\.name), ["Timothée Chalamet", "Zendaya"])
        XCTAssertEqual(x.cast.first?.role, "Paul Atreides")
        XCTAssertEqual(x.cast.first?.photo, "https://image.tmdb.org/t/p/w185/t.jpg")
        XCTAssertNil(x.cast.last?.photo, "sin foto: la pieza pone sus iniciales")
        XCTAssertEqual(x.crew.map(\.name), ["Denis Villeneuve", "Frank Herbert"], "dirección y guion, cada persona una vez; el montaje no")
        XCTAssertEqual(x.certification, "B", "la de tu país (la vacía no cuenta)")
        XCTAssertEqual(x.rating, 7.8)
        XCTAssertEqual(x.trailer?.key, "trailer1", "el tráiler de YouTube, aunque venga después")
        XCTAssertEqual(x.extras.map(\.key), ["featurette1"])
        XCTAssertEqual(x.recommendations.map(\.title), ["Dune: Part Two"], "sin nombre no se enseña")
        XCTAssertEqual(x.recommendations.first?.year, 2024)
        XCTAssertEqual(x.providers.map(\.name), ["HBO Max"])
        XCTAssertEqual(x.studios.map(\.name), ["Legendary Pictures"])
    }

    func testCertificationFallsBackToTheUSAndSeriesUseContentRatings() {
        XCTAssertEqual(Tmdb.parseExtras(movie, kind: "movie", region: "ES").certification, "PG-13")
        let series: JSON = ["id": 1, "content_ratings": ["results": [["iso_3166_1": "US", "rating": "TV-MA"]]],
                            "created_by": [["id": 7, "name": "Dan Erickson"]], "networks": [["name": "Apple TV+"]]]
        let x = Tmdb.parseExtras(series, kind: "series", region: "MX")
        XCTAssertEqual(x.certification, "TV-MA")
        XCTAssertEqual(x.crew.first?.role, "Creator")
        XCTAssertEqual(x.studios.map(\.name), ["Apple TV+"], "en una serie, la cadena")
    }

    func testAPersonsWorkIsTheMostPopularFirstWithoutRepeats() {
        let raw: JSON = ["id": 1, "name": "Zendaya", "biography": " Actriz. ", "profile_path": "/z.jpg",
                         "combined_credits": [
                            "cast": [["id": 10, "media_type": "movie", "title": "Dune", "poster_path": "/a.jpg", "popularity": 50, "character": "Chani"],
                                     ["id": 20, "media_type": "tv", "name": "Euphoria", "poster_path": "/e.jpg", "popularity": 90, "character": "Rue"],
                                     ["id": 30, "media_type": "movie", "title": "Sin póster", "popularity": 99]],
                            "crew": [["id": 20, "media_type": "tv", "name": "Euphoria", "poster_path": "/e.jpg", "popularity": 90, "job": "Producer"]]]]
        let p = Tmdb.parsePerson(raw)
        XCTAssertEqual(p.biography, "Actriz.")
        XCTAssertEqual(p.credits.map(\.title), ["Euphoria", "Dune"])
        XCTAssertEqual(p.credits.first?.kind, "series")
        XCTAssertEqual(p.credits.first?.role, "Rue")
    }
}

final class AudioBadgeTests: XCTestCase {
    func testTheSoundOfASourceAsBadges() {
        func badges(_ title: String) -> [String] {
            Source(index: 0, addon: "T", stream: ["title": .string(title)], transportURL: "").audioBadges
        }
        XCTAssertEqual(badges("Dune.2021.2160p.DV.TrueHD.Atmos.7.1"), ["Atmos", "TrueHD", "7.1"], "7.1 gana a 5.1")
        XCTAssertEqual(badges("Show.S01E01.1080p.WEB-DL.DDP5.1"), ["DD+"])
        XCTAssertEqual(badges("Movie.1080p.BluRay.DTS-HD.MA.5.1"), ["DTS-HD", "5.1"], "DTS-HD, no también DTS")
    }

    func testTheBestAvailableIsTheSharpestWithTheMostBadges() {
        func src(_ i: Int, _ res: String, _ hdr: [String], _ title: String, tags: [String] = []) -> Source {
            var s = Source(index: i, addon: "T", stream: ["title": .string(title)], transportURL: "")
            s.resolution = res; s.hdr = hdr; s.tags = tags
            return s
        }
        let sources = [src(0, "1080p", ["HDR"], "a.1080p.Atmos"), src(1, "4K", [], "b.2160p"), src(2, "4K", ["DV"], "c.2160p.DV.Atmos"),
                       src(3, "4K", ["DV", "HDR"], "d.2160p.Trailer", tags: ["Tráiler"])]
        XCTAssertEqual(Source.best(sources)?.index, 2, "4K con DV y Atmos; el tráiler no cuenta")
        XCTAssertNil(Source.best([]))
    }
}

final class IntroDBTests: XCTestCase {
    func testReadsIntroRecapAndCreditsInSeconds() {
        let json: JSON = ["imdb_id": "tt0944947", "intro": ["start_sec": 437, "end_sec": 531], "recap": .null,
                          "outro": ["start_sec": .double(3631.5), "end_sec": .double(3699.5)], "post_credits": .null]
        let s = IntroDB.parse(json)
        XCTAssertEqual(s.intro, 437...531)
        XCTAssertNil(s.recap)
        XCTAssertEqual(s.credits?.lowerBound, 3631.5, "los créditos (outro) en segundos")
        XCTAssertTrue(IntroDB.parse(["intro": ["start_sec": 50, "end_sec": 10]]).isEmpty, "un tramo al revés no cuenta")
    }

    func testAsksBySeasonAndEpisodeOrAsAMovie() async {
        let http = FakeHTTP()
        http.json["https://api.introdb.app/segments?imdb_id=tt0944947&season=1&episode=1"] = ["intro": ["start_sec": 10, "end_sec": 70]]
        http.json["https://api.introdb.app/segments?imdb_id=tt0133093&is_movie=true"] = ["intro": .null, "outro": .null]
        let db = IntroDB(http: http)
        let episode = await db.segments(videoID: "tt0944947:1:1")
        XCTAssertEqual(episode?.intro, 10...70)
        let movie = await db.segments(videoID: "tt0133093")
        XCTAssertNil(movie, "sin marcas: nada")
        let notImdb = await db.segments(videoID: "kitsu:1:1")
        XCTAssertNil(notImdb, "sin id de IMDb no se pregunta")
    }
}
