"""Letterboxd, solo leer (como el iPhone): el diario, tus listas, de película a IMDb y lo que dice de una película."""

from orbital.library import letterboxd as lb

DIARY = """<rss><channel>
<item><title>Dune, 2021 - ★★★★½</title><link>https://letterboxd.com/fer/film/dune-2021/</link><guid>letterboxd-review-1</guid>
<letterboxd:watchedDate>2026-10-30</letterboxd:watchedDate><letterboxd:rewatch>Yes</letterboxd:rewatch>
<letterboxd:filmTitle>Dune</letterboxd:filmTitle><letterboxd:filmYear>2021</letterboxd:filmYear>
<letterboxd:memberRating>4.5</letterboxd:memberRating><letterboxd:memberLike>Yes</letterboxd:memberLike><tmdb:movieId>438631</tmdb:movieId>
<description><![CDATA[ <p><img src="https://a.ltrbxd.com/x.jpg"/></p> <p>Arena &amp; especias.<br />Otra vez.</p> <p>Watched on Friday October 30, 2026.</p> ]]></description></item>
<item><title>Una lista nueva</title><link>https://letterboxd.com/fer/list/x/</link></item>
</channel></rss>"""

LISTS = """<article class="list-summary"><h2 class="name prettify"><a href="/fer/list/terror-de-domingo/">Terror de domingo</a></h2>
<span class="value">1,234&nbsp;films</span></article><article class="list-summary"><h2 class="name"><a href="/fer/list/ghibli/">Ghibli &amp; más</a></h2></article>"""

FILMS = """<li data-item-name="Dune (2021)" data-other="1" data-item-slug="dune-2021"></li>
<li data-item-name="Arrival" data-item-slug="arrival-2016"></li><li data-item-name="Dune (2021)" data-item-slug="dune-2021"></li>
<section class="poster-list-overlapped"><li data-item-name="Otra (2000)" data-item-slug="otra"></li></section>"""

FILM = """<meta property="og:url" content="https://letterboxd.com/film/dune-2021/" /><meta name="twitter:data2" content="3.89 out of 5" />
<div data-tmdb-id="438631" data-tmdb-type="movie"></div><a href="http://www.imdb.com/title/tt1160419/maindetails">IMDb</a>
<article class="production-viewing -viewing"><strong class="displayname">Jay</strong><span aria-label="★★★★½"></span>
<div class="js-review-body"><p>La arena &#233;pica.</p></div><div class="viewing-actions" data-count="1520"></div></article>
<article class="production-viewing"><strong class="displayname">Ana</strong><p>This review may contain spoilers.</p>
<div class="js-review-body"><p>Paul muere.</p></div></article>"""


def test_a_user_is_cleaned_like_the_iphone():
    assert lb.clean_user(" @Fer_Nando ") == "fer_nando"
    assert lb.clean_user("https://letterboxd.com/fer/films/") == "fer"
    assert lb.clean_user("con espacios") is None and lb.clean_user("") is None


def test_the_diary_with_stars_heart_rewatch_and_the_review_without_poster_or_watched_on():
    [entry] = lb.parse_diary(DIARY)
    assert (entry["title"], entry["year"], entry["slug"], entry["tmdb"]) == ("Dune", 2021, "dune-2021", 438631)
    assert (entry["rating"], entry["liked"], entry["rewatch"], entry["watched"]) == (4.5, True, True, "2026-10-30")
    assert entry["review"] == "Arena & especias.\nOtra vez."


def test_your_lists_and_a_lists_films_in_order_without_the_other_lists_beside_it():
    assert lb.parse_lists(LISTS) == [{"slug": "terror-de-domingo", "name": "Terror de domingo", "count": 1234},
                                     {"slug": "ghibli", "name": "Ghibli & más", "count": None}]
    assert lb.parse_films(FILMS) == [{"slug": "dune-2021", "title": "Dune", "year": 2021}, {"slug": "arrival-2016", "title": "Arrival", "year": None}]


def test_a_film_page_gives_its_imdb_average_and_popular_reviews_with_spoilers_marked():
    assert lb.parse_film_page(FILM) == {"imdb": "tt1160419", "kind": "movie", "tmdb": 438631}
    info = lb.parse_film_info(FILM)
    assert (info["slug"], info["average"]) == ("dune-2021", 3.89)
    jay, ana = info["reviews"]
    assert (jay["author"], jay["rating"], jay["text"], jay["likes"], jay["spoiler"]) == ("Jay", 4.5, "La arena épica.", 1520, False)
    assert (ana["author"], ana["spoiler"]) == ("Ana", True)

