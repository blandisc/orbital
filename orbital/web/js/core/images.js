/**
 * Cada imagen del tamaño en que se ve. Una tarjeta de 133 px pedía el fondo de 1920 × 1080 de metahub (8 MB ya
 * decodificado, por tarjeta) y Edge acumulaba más de 1 GB en su proceso de GPU. Orbital las reduce una vez y las guarda
 * (orbital/remote_art.py para las de internet, thumbs.py para el arte local).
 */

// Los mismos que orbital/remote_art.py · HOSTS y WIDTHS.
const HOSTS = new Set(["images.metahub.space", "live.metahub.space", "episodes.metahub.space", "image.tmdb.org", "cdn.cloudflare.steamstatic.com",
  "cdn.akamai.steamstatic.com", "shared.cloudflare.steamstatic.com", "shared.akamai.steamstatic.com",
  "steamcdn-a.akamaihd.net", "thumbnails.libretro.com", "media.rawg.io", "walter-r2.trakt.tv",
  "cdn.thegamesdb.net", "upload.wikimedia.org", "cdn2.steamgriddb.com"]); // las dos últimas: «Elegir imagen» de los juegos
const WIDTHS = [160, 240, 320, 480, 640, 960, 1280, 1920];

/** El ancho fijo más cercano por arriba, contando la densidad de la pantalla. */
export function snapWidth(cssWidth, ratio = globalThis.devicePixelRatio || 1) {
  const want = Math.ceil(cssWidth * Math.min(ratio, 2));
  return WIDTHS.find((w) => w >= want) ?? WIDTHS[WIDTHS.length - 1];
}

/** `url` pedida a `cssWidth` px de ancho; lo que no se puede reducir, tal cual. */
export function sized(url, cssWidth, ratio) {
  if (typeof url !== "string" || !url) return url;
  const w = snapWidth(cssWidth, ratio);
  if (url.startsWith("/api/art/")) {
    return /[?&]w=/.test(url) || /[?&]kind=logo/.test(url) ? url : `${url}${url.includes("?") ? "&" : "?"}w=${w}`;
  }
  let host = "";
  try { host = new URL(url).hostname; } catch { return url; }
  return url.startsWith("https://") && HOSTS.has(host) ? `/api/img?w=${w}&u=${encodeURIComponent(url)}` : url;
}
