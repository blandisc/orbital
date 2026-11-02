"""Letterboxd sin API, solo leer (como el iPhone: OrbitalCore/Letterboxd.swift; Fernando, 1 nov 2026). Todo sale de lo
público de tu perfil:

    GET https://letterboxd.com/{usuario}/rss/              tu diario: las últimas ~50, con estrellas, ♥ y reseña
    GET https://letterboxd.com/{usuario}/lists/            tus listas (nombre, cuántas películas)
    GET https://letterboxd.com/{usuario}/list/{lista}/     las películas de una lista (de 100 en 100: /page/2/)
    GET https://letterboxd.com/film/{película}/            su IMDb (se recuerda para siempre)
    GET https://letterboxd.com/imdb/{tt…}/                 una película por su IMDb: su promedio y sus reseñas populares

Orbital nunca escribe en Letterboxd.
"""

from __future__ import annotations

import html as html_lib
import re
import urllib.error
import urllib.request

SITE = "https://letterboxd.com"
# Un navegador cualquiera: con otro nombre, Letterboxd contesta con la pantalla de «comprobando que eres humano».
AGENT = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36")
MAX_LIST_PAGES, MAX_LISTS_PAGES = 5, 3
PUBLIC_REVIEWS = 8


class LetterboxdError(Exception):
    pass


class LetterboxdNotFound(LetterboxdError):
    def __init__(self) -> None:
        super().__init__("No encontré ese usuario en Letterboxd")


def clean_user(raw: str | None) -> str | None:
    """Un usuario de Letterboxd: letras, números y «_» (lo que se escriba con @, la dirección o espacios se limpia)."""
    user = str(raw or "").strip().strip("@/").replace("https://letterboxd.com/", "").replace("letterboxd.com/", "")
    user = user.split("/")[0].lower()
    return user if re.fullmatch(r"[a-z0-9_]{2,40}", user) else None


def _text(raw: str) -> str:
    """Un pedazo de HTML a texto: los <br> son saltos, sin etiquetas y con sus entidades («&amp;», «&#233;», «&oacute;»)."""
    raw = raw.replace("<br />", "\n").replace("<br/>", "\n").replace("<br>", "\n")
    return html_lib.unescape(re.sub(r"<[^>]+>", "", raw)).strip()


def _tag(name: str, text: str) -> str | None:
    m = re.search(rf"<{re.escape(name)}>(.*?)</{re.escape(name)}>", text, re.S)
    return m.group(1).strip() if m else None


def parse_diary(xml: str) -> list[dict]:
    """El RSS de tu diario → [{title, year, slug, tmdb, watched (AAAA-MM-DD), rating (0.5–5), liked, rewatch, review}]."""
    out = []
    for raw in xml.split("<item>")[1:]:
        item = raw.split("</item>")[0]
        title = _tag("letterboxd:filmTitle", item)
        if not title:
            continue  # lo que no es una película (una lista nueva)
        link = _tag("link", item) or ""
        slug = m.group(1) if (m := re.search(r"/film/([^/]+)", link)) else None
        rating = _tag("letterboxd:memberRating", item)
        year = _tag("letterboxd:filmYear", item)
        tmdb = _tag("tmdb:movieId", item)
        out.append({"title": html_lib.unescape(title), "year": int(year) if year and year.isdigit() else None, "slug": slug,
                    "tmdb": int(tmdb) if tmdb and tmdb.isdigit() else None, "watched": _tag("letterboxd:watchedDate", item),
                    "rating": float(rating) if rating else None, "liked": _tag("letterboxd:memberLike", item) == "Yes",
                    "rewatch": _tag("letterboxd:rewatch", item) == "Yes",
                    "review": review_from_description(_tag("description", item) or "")})
    return out


def review_from_description(raw: str) -> str | None:
    """La reseña de una entrada: los párrafos que no son el póster, «Watched on…» ni el aviso de spoilers."""
    text = raw.replace("<![CDATA[", "").replace("]]>", "")
    paragraphs = [p.split("</p>")[0] for p in text.split("<p>")[1:]]
    kept = [t for t in (_text(p) for p in paragraphs if "<img" not in p)
            if t and not t.startswith("Watched on ") and not t.startswith("This review may contain spoilers")]
    return "\n\n".join(kept) or None


def parse_lists(html: str) -> list[dict]:
    """Tu página de listas → [{slug, name, count}]."""
    out = []
    for block in html.split('<article class="list-summary')[1:]:
        m = re.search(r'<h2 class="name[^"]*">\s*<a href="/[^/]+/list/([^/"]+)/">([^<]+)</a>', block)
        if not m:
            continue
        count = re.search(r'<span class="value">([\d,]+)&nbsp;film', block)
        out.append({"slug": m.group(1), "name": html_lib.unescape(m.group(2)).strip(),
                    "count": int(count.group(1).replace(",", "")) if count else None})
    return out


def parse_films(html: str) -> list[dict]:
    """Una página de una lista → [{slug, title, year}] en su orden (solo su cuadrícula, no las otras listas de al lado)."""
    grid = html.split("poster-list-overlapped")[0]
    seen, out = set(), []
    for name, slug in re.findall(r'data-item-name="([^"]+)"[^>]*?data-item-slug="([^"]+)"', grid, re.S):
        if slug in seen:
            continue
        seen.add(slug)
        full = html_lib.unescape(name)
        m = re.fullmatch(r"(.*) \((\d{4})\)", full)
        out.append({"slug": slug, "title": m.group(1) if m else full, "year": int(m.group(2)) if m else None})
    return out


def parse_film_page(html: str) -> dict | None:
    """La página de una película → {imdb, kind, tmdb}; None si no trae su IMDb."""
    imdb = re.search(r"imdb\.com/title/(tt\d+)", html)
    if not imdb:
        return None
    tmdb = re.search(r'data-tmdb-id="(\d+)"', html)
    kind = re.search(r'data-tmdb-type="(\w+)"', html)
    return {"imdb": imdb.group(1), "kind": "series" if kind and kind.group(1) == "tv" else "movie",
            "tmdb": int(tmdb.group(1)) if tmdb else None}


def parse_film_info(html: str) -> dict | None:
    """La página de una película → {slug, average (0.5–5), reviews: [{author, rating, text, likes, spoiler}]}."""
    if "data-tmdb-id" not in html and "twitter:data2" not in html:
        return None
    slug = re.search(r'<meta property="og:url" content="https://letterboxd\.com/film/([^/"]+)/"', html)
    average = re.search(r'name="twitter:data2" content="([\d.]+) out of 5"', html)
    reviews = []
    for raw in html.split('<article class="production-viewing')[1:PUBLIC_REVIEWS + 1]:
        block = raw.split("</article>")[0]
        author = re.search(r'<strong class="displayname">([^<]+)</strong>', block)
        if not author:
            continue
        body = block.split("js-review-body", 1)[1] if "js-review-body" in block else ""
        body = body.split("viewing-actions")[0]
        text = "\n\n".join(t for t in (_text(p) for p in re.findall(r"<p>(.*?)</p>", body, re.S)) if t)
        if not text:
            continue
        stars = re.search(r'aria-label="([★½]+)"', block)
        likes = re.search(r'data-count="(\d+)"', block)
        reviews.append({"author": html_lib.unescape(author.group(1)).strip(),
                        "rating": stars.group(1).count("★") + (0.5 if "½" in stars.group(1) else 0) if stars else None,
                        "text": text, "likes": int(likes.group(1)) if likes else None,
                        "spoiler": "This review may contain spoilers" in block})
    return {"slug": slug.group(1) if slug else None, "average": float(average.group(1)) if average else None, "reviews": reviews}


class Letterboxd:
    """Lo público de un perfil de Letterboxd. `user()` da el usuario vigente (el de Ajustes › Cuentas)."""

    def __init__(self, user: str | None = None, timeout: float = 15) -> None:
        self.user = clean_user(user)
        self.timeout = timeout

    @property
    def configured(self) -> bool:
        return self.user is not None

    def page(self, path: str) -> str:
        request = urllib.request.Request(SITE + path, headers={"User-Agent": AGENT, "Accept-Language": "en"})
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:  # noqa: S310 - solo letterboxd.com
                return response.read().decode("utf-8", "replace")
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                raise LetterboxdNotFound() from exc
            raise LetterboxdError(f"Letterboxd no contestó ({exc.code})") from exc

    def diary(self, user: str | None = None) -> list[dict]:
        return parse_diary(self.page(f"/{user or self.user}/rss/"))

    def lists(self) -> list[dict]:
        out: list[dict] = []
        for n in range(1, MAX_LISTS_PAGES + 1):
            found = parse_lists(self.page(f"/{self.user}/lists/" + (f"page/{n}/" if n > 1 else "")))
            out += [row for row in found if all(row["slug"] != o["slug"] for o in out)]
            if len(found) < 12:  # Letterboxd enseña 12 por página
                break
        return out

    def list_films(self, slug: str) -> list[dict]:
        if not re.fullmatch(r"[a-z0-9-]{1,120}", slug or ""):
            raise LetterboxdError("Lista inválida")
        out: list[dict] = []
        for n in range(1, MAX_LIST_PAGES + 1):
            found = parse_films(self.page(f"/{self.user}/list/{slug}/" + (f"page/{n}/" if n > 1 else "")))
            out += [f for f in found if all(f["slug"] != o["slug"] for o in out)]
            if len(found) < 100:
                break
        return out

    def resolve(self, slug: str) -> dict | None:
        """El IMDb (y si es película o serie) de una película de Letterboxd."""
        if not re.fullmatch(r"[a-z0-9-]{1,160}", slug or ""):
            return None
        return parse_film_page(self.page(f"/film/{slug}/"))

    def info(self, imdb: str) -> dict | None:
        """Su promedio y sus reseñas populares, por su IMDb (Letterboxd lleva de /imdb/tt… a su página). None si no la tiene."""
        if not re.fullmatch(r"tt\d{1,12}", imdb or ""):
            return None
        try:
            return parse_film_info(self.page(f"/imdb/{imdb}/"))
        except LetterboxdNotFound:
            return None
