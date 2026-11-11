"""Real-Debrid y tus complementos: la clave, el estado de la cuenta, traer y cambiar complementos."""

from __future__ import annotations

import logging
import math
import re
import threading
import time
from dataclasses import asdict

from ..library import addons, realdebrid, stremio_api, torrentio
from ..net import NET_FAILURES
from .base import ADDONS_KEY, RD_ACCOUNT, RD_KEY, RD_STATUS_TTL, STREMIO_KEY
from .items import addon_gives
from .library import _Library

log = logging.getLogger("orbital.watch")  # el mismo nombre de siempre: los avisos y la bitácora no cambian


class _Accounts(_Library):
    """Real-Debrid y tus complementos: la clave, el estado de la cuenta, traer y cambiar complementos."""

    # --- Real-Debrid propio («La TV sin Stremio», corte S2) ------------------
    def rd_token(self) -> str | None:
        """La clave de tu Real-Debrid. La consola guarda la suya; la primera vez la toma de tu Torrentio y lo avisa (AD-2).
        Si la tomó de ahí y tu Torrentio trae otra, cambia a esa: nunca se queda con una vieja."""
        own = self.credentials.get(RD_KEY)
        source = self.state.prefs(RD_ACCOUNT).get("source")
        if own and source not in (None, "torrentio"):  # te la mandó el iPhone: no se cambia sola
            return own
        torrentio = self.rd._torrentio_token() if hasattr(self, "rd") else None
        if not torrentio or torrentio == own:
            return own or torrentio
        self.credentials.set(RD_KEY, torrentio)
        self.state.set_pref(RD_ACCOUNT, "source", "torrentio")
        self._rd_status = (0.0, None, {})
        self.events.publish({"type": "toast", "ok": True,
                             "message": "Tu Torrentio trae otra clave de Real-Debrid: ahora uso esa" if own
                             else "Tomé tu clave de Real-Debrid de tu Torrentio",
                             "detail": "La ves en Ajustes › Cuentas › Real-Debrid"})
        return torrentio

    def debrid_status(self, fresh: bool = False) -> dict:
        """Tu Real-Debrid para Ajustes › Cuentas y para la ficha: {"linked", "source", "user", "premium", "expires",
        "days", "problem", "ends_with"}. `problem`: "expired" | "no_premium" | "bad_key" | "offline" | None. Le pregunta a
        Real-Debrid como mucho cada media hora (o al ver un «RD error»)."""
        token = self.rd_token()
        if not token:
            return {"linked": False}
        when, cached_token, cached = self._rd_status
        if not fresh and cached_token == token and time.time() - when < RD_STATUS_TTL:
            return cached
        out = {"linked": True, "source": self.state.prefs(RD_ACCOUNT).get("source") or "torrentio", "user": None,
               "premium": False, "expires": None, "days": None, "problem": None, "ends_with": token[-4:].upper()}
        try:
            user = realdebrid.RealDebrid(token).user()
        except realdebrid.RealDebridError as exc:
            out["problem"] = "bad_key" if exc.bad_key else "no_premium" if exc.no_premium else "offline"
            if out["problem"] == "offline" and cached:  # sin internet: lo de la última vez
                return cached
        else:
            out["user"] = str(user.get("username") or "") or None
            expires = None
            try:
                raw = str(user.get("expiration") or "")
                from datetime import datetime
                expires = datetime.fromisoformat(raw.replace("Z", "+00:00")).timestamp() if raw else None
            except ValueError:
                expires = None
            out["expires"] = expires
            out["premium"] = user.get("type") == "premium"
            if expires:
                out["days"] = max(0, math.ceil((expires - time.time()) / 86400))
            if not out["premium"]:
                out["problem"] = "expired" if expires and expires < time.time() else "no_premium"
        self._rd_status = (time.time(), token, out)
        return out

    def debrid_summary(self) -> dict:
        """Para Ajustes (sin esperar a Real-Debrid): lo último que se supo, y si ya es viejo se pregunta por detrás; al
        tenerlo llega «settings-changed». Con «Tus pedidos» (la libreta, sin enlaces)."""
        when, token, cached = self._rd_status
        current = self.credentials.get(RD_KEY) or (self.rd._torrentio_token() if not token else token)
        if not current:
            return {"linked": False, "account": None, "requests": self.rd.listing()["requests"]}
        if not cached or token != current or time.time() - when >= RD_STATUS_TTL:
            def ask() -> None:
                self.debrid_status()
                self.events.publish({"type": "settings-changed"})
            threading.Thread(target=ask, daemon=True, name="rd-status").start()
        listed = self.rd.listing()
        return {**(cached or {"linked": True, "loading": True}), "account": listed["account"], "requests": listed["requests"]}

    # --- Ajustes › Complementos («La TV sin Stremio», S1) ---------------------
    def addon_status(self) -> dict:
        """Lo que enseña Ajustes › Complementos: de dónde salen, cada uno con qué aporta y si contesta."""
        known = {a.url: a for a in self.addons.known()}
        entries = []
        for entry in self.addon_list.entries():
            found = known.get(entry.address or "")
            row = {
                "id": entry.id, "name": entry.name, "origin": entry.origin, "on": entry.on(),
                "only_on": entry.only_on, "gives": addon_gives(found),
                "health": self.addons.health.status(entry.address) if entry.on() and entry.address else {"state": "off"},
            }
            if entry.template:  # TV-1: la interfaz distingue OpenSubtitles (solo subtítulos) de lo que da versiones
                row["template"] = entry.template
            if entry.template == "torrentio":  # se configura aquí (corte S3); sin tu clave no se puede armar
                row.update(options=entry.options, needs_key=entry.address is None)
            entries.append(row)
        raw = self.addon_list._raw()
        return {"source": self.addon_list.source, "imported_at": self.addon_list.imported_at,
                "stremio_linked": self.stremio_linked, "entries": entries,
                "changed_by": raw.get("changed_by_name") or raw.get("changed_by"), "changed_at": raw.get("changed_at")}

    def _copy_stremio_addons(self) -> None:
        """Lo que salía de tu cuenta de Stremio pasa a tu lista, una sola vez y sin preguntar (Fernando, 4 nov: Stremio ya
        no es para traer complementos). Sin internet o sin la cuenta se intenta en el siguiente arranque; mientras, las
        fuentes salen de tu lista (Torrentio de Orbital)."""
        try:
            done = self.import_addons()
            log.info("Copié tus complementos de Stremio a tu lista: %s", done)
        except Exception as exc:  # noqa: BLE001 — sin internet, sin cuenta o una respuesta rara: se intenta en el siguiente arranque
            log.info("Todavía no pude copiar tus complementos de Stremio: %s", exc)

    def import_addons(self) -> dict:
        """Copia tus complementos de la cuenta de Stremio a tu lista (solo para no perder nada al dejar de leerlos de ahí:
        `_copy_stremio_addons`). Ya no hay botón para esto."""
        key = self.credentials.get(STREMIO_KEY)
        if not key:
            raise ValueError("Primero conecta tu cuenta de Stremio")
        result = self.stremio_client.request("addonCollectionGet", {"authKey": key, "update": True})
        raw = result.get("addons") if isinstance(result, dict) else None
        found = []
        for item in raw if isinstance(raw, list) else []:
            if isinstance(item, dict) and isinstance(item.get("transportUrl"), str):
                manifest = item.get("manifest") if isinstance(item.get("manifest"), dict) else None
                url = addons.manifest_url(item["transportUrl"])
                if url:
                    found.append(((manifest or {}).get("name") or "", url, manifest))
        done = self.addon_list.import_from_stremio(found)
        self.addons.forget()
        return done

    def change_addon(self, ident: str, action: str) -> dict:
        """Prender, apagar, subir, bajar o quitar uno de tu lista. Quitar devuelve lo quitado para «Deshacer»."""
        if action in ("on", "off"):
            self.addon_list.set_enabled(ident, action == "on")
            gone = None
        elif action in ("up", "down"):
            self.addon_list.move(ident, -1 if action == "up" else 1)
            gone = None
        elif action == "remove":
            gone = asdict(self.addon_list.remove(ident))
            self._removed_addons[ident] = gone  # para «Deshacer»: solo regresa lo que quitaste aquí
        else:
            raise ValueError(action)
        self.addons.forget()
        return {**self.addon_status(), "removed": gone}

    def restore_addon(self, ident: str) -> dict:
        self.addon_list.restore(self._removed_addons.pop(ident))
        self.addons.forget()
        return self.addon_status()

    def receive_addons(self, body: dict, device: str, keyed: dict | None = None) -> dict:
        """PUT /api/addons (corte S6): la lista que cambiaste en el iPhone; la TV la junta y deja de leer la de Stremio.
        `keyed`: el aparato de la llave (K1-A), que solo cambia su propio prendido y puede traer direcciones con clave."""
        saved = self.addon_list.receive(body, device, keyed)
        self.addons.forget()
        self.streams.forget_all()
        self.events.publish({"type": "settings-changed"})
        return saved

    def set_torrentio(self, options: dict) -> dict:
        """Ajustes › Complementos › Torrentio (corte S3): tus opciones, revisadas contra las de Torrentio
        (design/addons-contract.json). Se guarda al cambiar; lo que la TV no conoce de tu Torrentio se queda."""
        clean: dict = {}
        known = lambda values, allowed: [v for v in dict.fromkeys(values or []) if v in allowed] if isinstance(values, list) else []  # noqa: E731
        clean["language"] = known(options.get("language"), torrentio.LANGUAGES)
        clean["qualityfilter"] = known(options.get("qualityfilter"), torrentio.QUALITIES)
        clean["providers"] = known(options.get("providers"), torrentio.PROVIDERS)
        clean["debridoptions"] = known(options.get("debridoptions"), ("nodownloadlinks", "nocatalog"))
        if options.get("sort") in torrentio.SORTS[1:]:
            clean["sort"] = options["sort"]
        limit = options.get("limit")
        if isinstance(limit, int) and not isinstance(limit, bool) and 1 <= limit <= 999:
            clean["limit"] = limit
        size = options.get("sizefilter")
        if isinstance(size, str) and re.fullmatch(r"\d+(\.\d+)?(GB|MB)(,\d+(\.\d+)?(GB|MB))?", size.upper()):
            clean["sizefilter"] = size.upper()
        before = self.addon_list.torrentio().options or {}
        if before.get("verbatim"):
            clean["verbatim"] = before["verbatim"]
        self.addon_list.set_options(clean)
        self.addons.forget()
        self.streams.forget_all()
        return {**self.addon_status(), "previous": before}

    @staticmethod
    def check_rd_token(token: str) -> str:
        """El usuario de Real-Debrid de esa clave (para «¿Usar la cuenta fernando?»). ValueError si no la reconoce y
        ConnectionError si no contesta. Una cuenta sin Premium sí cuenta: la clave sirve."""
        token = token.strip()
        if not 20 <= len(token) <= 128 or not token.isalnum():
            raise ValueError("Esa no parece una clave de Real-Debrid")
        try:
            try:
                user = realdebrid.RealDebrid(token).user()
            except realdebrid.RealDebridError as exc:
                if not (exc.bad_key and token != token.upper()):
                    raise
                user = realdebrid.RealDebrid(token.upper()).user()  # escrita en minúsculas con el teclado de la TV
        except realdebrid.RealDebridError as exc:
            if exc.bad_key:
                raise ValueError("Real-Debrid no reconoce esa clave") from exc
            if exc.no_premium:
                return ""
            raise ConnectionError("Real-Debrid no contestó. Inténtalo en un momento.") from exc
        return str(user.get("username") or "")

    def set_rd_token(self, token: str, by: str, source: str = "iphone") -> dict:
        """Tu clave fija de Real-Debrid: «Pasar a la TV» desde el iPhone (K1-A), desde cualquier celular (CA2-A) o pegada
        en la TV (TEC-4). Se prueba con Real-Debrid antes de guardarla; si no sirve, la de antes se queda. ValueError si
        Real-Debrid no la reconoce y ConnectionError si no contesta. Nunca se reemplaza sola (solo la de Torrentio)."""
        token = token.strip()
        self.check_rd_token(token)
        changed = self.credentials.get(RD_KEY) != token
        self.credentials.set(RD_KEY, token)
        self.state.set_pref(RD_ACCOUNT, "source", source)
        self._rd_status = (0.0, None, {})
        self.addons.forget()
        self.streams.forget_all()
        if changed and source == "iphone":  # lo de la TV y el celular lo confirmaste en la TV: ahí se dice
            self.events.publish({"type": "toast", "ok": True, "message": f"«{by}» cambió la clave de Real-Debrid",
                                 "detail": "Si no fuiste tú, quítalo en Ajustes › Cuentas"})
        self.events.publish({"type": "settings-changed"})
        status = self.debrid_status(fresh=True)
        return {k: v for k, v in status.items() if k != "token"}

    def _rd_key_brought(self, key: str) -> None:
        """La clave que venía en el Torrentio que trajiste de Stremio: la consola la guarda como suya y lo dice."""
        if self.credentials.get(RD_KEY):
            return
        self.credentials.set(RD_KEY, key)
        self.state.set_pref(RD_ACCOUNT, "source", "torrentio")
        self.events.publish({"type": "toast", "ok": True, "message": "Tomé tu clave de Real-Debrid de tu Torrentio",
                             "detail": "La ves en Ajustes › Cuentas › Real-Debrid"})

    def set_addon_source(self, source: str) -> dict:
        """Solo «own» (4 nov: ya no se regresa a los de tu cuenta de Stremio). ValueError con otra cosa."""
        self.addon_list.set_source(source)
        self.addons.forget()
        return self.addon_status()

    def bring_from_stremio(self) -> dict:
        """«Traer de tu Stremio» (SS-8, corte S5): tus complementos (si no los habías traído) y Mi lista de Stremio a la
        watchlist de Trakt; desde ahí Stremio ya no se lee y solo recibe copia si la dejas. Sin Trakt, ValueError: Stremio
        sigue siendo tu lista (P-4). Devuelve {"addons", "my_list", "already"}."""
        auth = self.credentials.get(STREMIO_KEY)
        if not auth:
            raise ValueError("Primero conecta tu cuenta de Stremio")
        trakt = self.trakt_library.client()
        if trakt is None:
            raise ValueError("Primero conecta Trakt: tu avance y Mi lista van ahí")
        brought = self.import_addons() if not self.addon_list.imported_at else {"added": 0, "kept": 0, "skipped": 0}
        raw = self.stremio_client.library(auth)
        mine = [w for w in stremio_api.parse_library(raw) if w.in_library and w.type in ("movie", "series")]
        try:
            have = {str(e.get("imdb") or e.get("id") or "") for e in trakt.watchlist() if isinstance(e, dict)}
        except Exception:  # noqa: BLE001 — sin la lista de Trakt se intenta agregar todo (agregar dos veces no duplica)
            have = set()
        added = already = 0
        for w in mine:
            if w.id in have:
                already += 1
                continue
            try:
                trakt.set_watchlist(w.type, w.id, True)
                added += 1
            except Exception as exc:  # noqa: BLE001 — uno que falla no detiene a los demás
                log.info("No pude pasar %s a Mi lista de Trakt: %s", w.id, exc)
        self.state.set_setting("stremio_role", "backup")
        self.refresh_trakt(background=True)
        self.refresh_stremio(background=True)
        return {"addons": brought.get("added", 0), "my_list": added, "already": already}

    STREMIO_LIST = "Mi lista Stremio"

    def move_stremio_to_trakt_list(self) -> dict:
        """Fernando, 4 nov 2026: «Crear una nueva lista en Trakt que se llame Mi lista Stremio. Pásalo todo y luego
        quítala.» Todo lo de tu Mi lista de Stremio (películas y series) va a esa lista personal de Trakt (no a tu
        watchlist; en Stremio no se borra nada). Se comprueba leyendo la lista de vuelta y, solo si llegó todo, se
        desconecta tu cuenta de Stremio de la TV (queda como respaldo para ver torrents). ValueError sin Trakt o sin la
        cuenta. Devuelve {"stremio", "in_list", "missing", "unlinked", "list_id"}."""
        auth = self.credentials.get(STREMIO_KEY)
        if not auth:
            raise ValueError("Tu cuenta de Stremio ya no está conectada")
        trakt = self.trakt_library.client()
        if trakt is None:
            raise ValueError("Primero conecta Trakt: ahí va tu lista")
        raw = self.stremio_client.library(auth)
        mine = [w for w in stremio_api.parse_library(raw) if w.in_library and w.type in ("movie", "series")]
        list_id = trakt.named_list(self.STREMIO_LIST, create=True)
        if not list_id:
            raise ValueError("Trakt no creó la lista")
        trakt.add_list_items(list_id, [(w.type, w.id) for w in mine])
        have = {str(e.get("imdb")) for e in trakt.list_items(list_id) if isinstance(e, dict)}
        missing = [w.id for w in mine if w.id not in have]  # también lo que no tiene IMDb (Trakt no lo acepta)
        unlinked = not missing
        if unlinked:
            self.unlink_stremio()
            self.state.set_setting("stremio_role", "backup")
            self.refresh_trakt(background=True)
        log.info("Mi lista de Stremio a Trakt: %d de %d (faltan %s); cuenta %s", len(mine) - len(missing), len(mine),
                 missing[:10], "desconectada" if unlinked else "conectada")
        return {"stremio": len(mine), "in_list": len(mine) - len(missing), "missing": missing, "unlinked": unlinked,
                "list_id": list_id}

    def own_addons(self) -> list[str]:  # los de `orbital stremio addon add`, de antes de tu lista (S1)
        return addons.clean_urls(self.credentials.get(ADDONS_KEY))

    def add_addon(self, url: str) -> addons.Addon:
        """Agrega un complemento tuyo (comprueba antes que responde y que da algo que Orbital usa)."""
        clean = addons.manifest_url(url)
        if not clean:
            raise ValueError("Eso no es la dirección de un complemento (https://…/manifest.json o stremio://…)")
        try:
            found = addons.parse_manifest(addons.fetch_json(clean), clean)
        except NET_FAILURES as exc:
            raise ValueError(f"El complemento no respondió ({addons.redact(clean)}): {exc}") from exc
        if not found:
            raise ValueError("Ese complemento no da fuentes, subtítulos, fichas ni catálogos")
        self.credentials.set(ADDONS_KEY, [*self.own_addons(), clean])
        self.addon_list.import_from_stremio([(found.name, clean, None)])  # 4 nov: las fuentes salen de tu lista
        self.addons.forget()
        return found

    def remove_addon(self, number: int) -> str:
        """Quita el complemento número `number` (1 = el primero de `orbital stremio addons`)."""
        own = self.own_addons()
        if not 1 <= number <= len(own):
            raise ValueError(f"No hay complemento {number}: tienes {len(own)}")
        gone = own.pop(number - 1)
        self.credentials.set(ADDONS_KEY, own or None)
        entry = next((e for e in self.addon_list.entries() if e.url == gone and e.origin != "orbital"), None)
        if entry is not None:
            self.addon_list.remove(entry.id)
        self.addons.forget()
        return addons.redact(gone)
