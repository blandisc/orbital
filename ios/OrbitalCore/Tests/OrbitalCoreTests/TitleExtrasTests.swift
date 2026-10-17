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

final class LiveChannelArtTests: XCTestCase {
    func testALiveChannelShowsItsLogoAndFallsBackToThePoster() throws {
        let live = try XCTUnwrap(OrbitalRemote.NowPlaying.parse(["kind": "tv", "live": true, "title": "Los Simpson 24/7", "logo": "https://img/simpsons.png", "poster": "https://img/p.jpg"]))
        XCTAssertEqual(live.art, "https://img/simpsons.png", "en vivo, el logotipo del canal")
        let noLogo = try XCTUnwrap(OrbitalRemote.NowPlaying.parse(["kind": "tv", "live": true, "title": "Canal 5", "poster": "https://img/p.jpg"]))
        XCTAssertEqual(noLogo.art, "https://img/p.jpg")
        let movie = try XCTUnwrap(OrbitalRemote.NowPlaying.parse(["kind": "movie", "title": "Dune", "poster": "https://img/d.jpg", "logo": "https://img/l.png"]))
        XCTAssertEqual(movie.art, "https://img/d.jpg", "una película, su póster")
    }
}

final class YearInReviewTests: XCTestCase {
    func testDaysHoursStreakGenreAndTop() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!
        func at(_ d: Int, _ h: Int = 20) -> Date { cal.date(from: DateComponents(year: 2026, month: 3, day: d, hour: h))! }
        let plays = [TraktPlay(at: at(1), kind: "movie", imdb: "tt1", title: "Dune", minutes: 155, genres: ["science-fiction"]),
                     TraktPlay(at: at(2), kind: "series", imdb: "tt2", title: "Severance", minutes: 50, genres: ["drama", "science-fiction"]),
                     TraktPlay(at: at(2, 22), kind: "movie", imdb: "tt3", title: "Past Lives", minutes: 105, genres: ["romance"]),
                     TraktPlay(at: at(3), kind: "series", imdb: "tt2", title: "Severance", minutes: 50, genres: ["drama", "science-fiction"]),
                     TraktPlay(at: at(9), kind: "series", imdb: "tt2", title: "Severance", minutes: 50, genres: ["drama", "science-fiction"])]
        let y = YearInReview.make(plays, year: 2026, calendar: cal)
        XCTAssertEqual(y.days[cal.startOfDay(for: at(1))], .movies)
        XCTAssertEqual(y.days[cal.startOfDay(for: at(2))], .both, "película y serie el mismo día")
        XCTAssertEqual(y.hours, 7, "410 min")
        XCTAssertEqual(y.longestStreak, 3, "1, 2 y 3 de marzo")
        XCTAssertEqual(y.movies, 2); XCTAssertEqual(y.episodes, 3)
        XCTAssertEqual(y.topGenre, "science-fiction")
        XCTAssertEqual(y.top.first?.title, "Severance")
    }

    func testAHistoryRowIsAPlay() throws {
        let movie = try XCTUnwrap(TraktParsing.play(["type": "movie", "watched_at": "2026-03-01T20:00:00.000Z",
                                                     "movie": ["title": "Dune", "runtime": 155, "genres": ["drama"], "ids": ["imdb": "tt1160419"]]]))
        XCTAssertEqual(movie.minutes, 155)
        let ep = try XCTUnwrap(TraktParsing.play(["type": "episode", "watched_at": "2026-03-02T20:00:00Z", "episode": ["runtime": 48],
                                                  "show": ["title": "Severance", "runtime": 55, "ids": ["imdb": "tt11280740"]]]))
        XCTAssertEqual(ep.kind, "series"); XCTAssertEqual(ep.minutes, 48, "el del episodio, no el de la serie")
        XCTAssertNil(TraktParsing.play(["type": "movie", "movie": ["title": "x"]]), "sin fecha no cuenta")
    }
}

final class AwardsTests: XCTestCase {
    func testEveryAwardHasWinnersNewestFirstWithIMDbIDs() {
        XCTAssertEqual(Awards.all.map(\.id), ["oscar", "emmy", "globe", "palm", "bafta", "ariel"])
        for award in Awards.all {
            XCTAssertGreaterThan(award.winners.count, 20, award.id)
            XCTAssertTrue(award.winners.allSatisfy { $0.imdb.hasPrefix("tt") }, award.id)
            XCTAssertEqual(award.winners.map(\.awardYear), award.winners.map(\.awardYear).sorted(by: >), "\(award.id): del más reciente")
            XCTAssertEqual(award.suggestions.first?.reason, .console(String(award.winners[0].awardYear)), "el año del premio, bajo el póster")
        }
        XCTAssertEqual(Awards.all.first { $0.id == "emmy" }?.kind, "series")
    }
}
