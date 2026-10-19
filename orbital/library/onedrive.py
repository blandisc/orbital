"""OneDrive: tus películas y series guardadas ahí, como una fuente más de Orbital (sin Jellyfin ni Real-Debrid).

  · Conectar: el inicio de sesión oficial de Microsoft con un código (como Trakt): en el celular entras a
    microsoft.com/link y escribes el código de la tele. Hace falta el «ID de la aplicación» que registras gratis en
    Microsoft Entra (Ajustes › Cuentas › Clave de OneDrive). Solo pide leer tus archivos (Files.Read).
  · La carpeta la eliges tú en Ajustes; Orbital solo mira esa (y sus subcarpetas, hasta DEPTH niveles).
  · Cada video se reconoce por su nombre («Dune Part Two (2024).mkv», «Severance.S01E03.1080p.mkv») y se busca su ficha.
  · Ver: Microsoft da una dirección temporal del archivo (~1 h) y el reproductor de Orbital la abre directo; lee por
    partes, sin bajar el archivo completo.
"""

from __future__ import annotations

import logging
import re
import threading
import time
from pathlib import PurePosixPath
from urllib.parse import quote

from ..net import NET_ERRORS, http_json
from .trakt import DeviceCode

log = logging.getLogger(__name__)

LOGIN = "https://login.microsoftonline.com/common/oauth2/v2.0"
GRAPH = "https://graph.microsoft.com/v1.0"
SCOPE = "Files.Read offline_access"
TOKENS_KEY = "onedrive_tokens"
CLIENT_KEY = "onedrive_client"
VIDEO_EXTS = {".mkv", ".mp4", ".m4v", ".avi", ".mov", ".webm", ".ts", ".wmv"}
DEPTH = 4  # subcarpetas que se recorren («Series/Adventure Time/Temporada 5»)
MAX_FILES = 5000


def added_at(text) -> float | None:
    """«2026-10-12T03:04:05Z» (createdDateTime de Graph) → segundos desde 1970; None si no viene."""
    from datetime import datetime

    try:
        return datetime.fromisoformat(str(text).replace("Z", "+00:00")).timestamp() if text else None
    except ValueError:
        return None


class OneDriveError(Exception):
    pass


class OneDriveAuthError(OneDriveError):
    pass


def parse_name(name: str) -> dict | None:
    """Qué es un archivo por su nombre: {"kind", "title", "year", "season", "episode"}; None si no es video.
    «Dune Part Two (2024) 2160p.mkv» → película «Dune Part Two», 2024. «Severance.S01E03.1080p.mkv» → serie, T1 E3."""
    path = PurePosixPath(name)
    if path.suffix.lower() not in VIDEO_EXTS:
        return None
    stem = re.sub(r"[._]+", " ", path.stem)
    stem = re.sub(r"\[[^\]]*\]|\{[^}]*\}", " ", stem)
    if (m := re.search(r"\b[Ss](\d{1,2})\s*[Ee](\d{1,3})\b|\b(\d{1,2})x(\d{2,3})\b", stem)):
        season, episode = int(m.group(1) or m.group(3)), int(m.group(2) or m.group(4))
        title = stem[:m.start()]
        year = re.search(r"\b(19|20)\d{2}\b", title)
        title = re.sub(r"\(?\b(19|20)\d{2}\b\)?", " ", title)
        return {"kind": "series", "title": _clean(title), "year": int(year.group(0)) if year else None,
                "season": season, "episode": episode}
    year = None
    # El año es el último que sea año de verdad (no futuro): «Blade Runner 2049 (2017)» es de 2017; «2012.mkv», un título.
    years = [m for m in re.finditer(r"\(?\b((?:19|20)\d{2})\b\)?", stem)
             if m.start() > 0 and int(m.group(1)) <= time.gmtime().tm_year + 1]
    if years:
        year, stem = int(years[-1].group(1)), stem[:years[-1].start()]
    stem = re.split(r"\b(2160p|1080p|720p|480p|4k|uhd|bluray|blu ray|web ?dl|webrip|hdrip|dvdrip|x264|x265|hevc|remux)\b", stem,
                    flags=re.I)[0]
    title = _clean(stem)
    return {"kind": "movie", "title": title, "year": year, "season": None, "episode": None} if title else None


def _clean(text: str) -> str:
    return re.sub(r"\s+", " ", re.sub(r"[()\-–]+\s*$", "", text)).strip(" -–()")


class OneDrive:
    def __init__(self, credentials, timeout: float = 15) -> None:
        self.credentials = credentials
        self.timeout = timeout
        self._lock = threading.Lock()

    # --- cuenta ------------------------------------------------------------------------------------
    @property
    def client_id(self) -> str:
        return (self.credentials.get(CLIENT_KEY) or "").strip()

    @property
    def configured(self) -> bool:
        return bool(self.client_id)

    @property
    def linked(self) -> bool:
        return bool(self._tokens())

    def _tokens(self) -> dict | None:
        raw = self.credentials.get(TOKENS_KEY)
        if not raw:
            return None
        import json
        try:
            data = json.loads(raw)
        except ValueError:
            return None
        return data if isinstance(data, dict) and data.get("access_token") else None

    def _save(self, data: dict) -> None:
        import json
        tokens = {"access_token": data.get("access_token"), "refresh_token": data.get("refresh_token") or (self._tokens() or {}).get("refresh_token"),
                  "expires_at": time.time() + float(data.get("expires_in") or 3600)}
        self.credentials.set(TOKENS_KEY, json.dumps(tokens))

    def unlink(self) -> None:
        self.credentials.set(TOKENS_KEY, None)

    def device_code(self) -> DeviceCode:
        if not self.configured:
            raise OneDriveError("Falta el ID de la aplicación de OneDrive: agrégalo en Ajustes › Cuentas.")
        try:
            status, data = http_json(f"{LOGIN}/devicecode", method="POST", timeout=self.timeout,
                                     form={"client_id": self.client_id, "scope": SCOPE})
        except NET_ERRORS as exc:
            raise OneDriveError(f"No pude conectar con Microsoft: {exc}") from exc
        if status != 200 or not isinstance(data, dict) or not data.get("device_code"):
            detail = (data or {}).get("error_description", "") if isinstance(data, dict) else ""
            raise OneDriveError("Microsoft no dio un código. Revisa el ID de la aplicación en Ajustes › Cuentas." +
                                (f" ({detail.splitlines()[0][:120]})" if detail else ""))
        return DeviceCode(str(data["device_code"]), str(data["user_code"]),
                          str(data.get("verification_uri") or "https://www.microsoft.com/link"),
                          min(max(float(data.get("interval") or 5), 1.0), 60.0),
                          time.time() + min(max(float(data.get("expires_in") or 900), 1.0), 3600.0))

    def poll_device(self, code: DeviceCode) -> str:
        """Una consulta: "linked", "pending", "slow", "expired", "denied" o "invalid"."""
        status, data = http_json(f"{LOGIN}/token", method="POST", timeout=self.timeout, form={
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code", "client_id": self.client_id,
            "device_code": code.device_code})
        if status == 200 and isinstance(data, dict) and data.get("access_token"):
            self._save(data)
            return "linked"
        error = (data or {}).get("error") if isinstance(data, dict) else None
        return {"authorization_pending": "pending", "slow_down": "slow", "expired_token": "expired",
                "authorization_declined": "denied", "bad_verification_code": "invalid"}.get(error or "", "pending")

    def _access(self) -> str:
        with self._lock:
            tokens = self._tokens()
            if not tokens:
                raise OneDriveAuthError("Conecta tu OneDrive en Ajustes › Cuentas.")
            if time.time() > float(tokens.get("expires_at") or 0) - 300:
                try:
                    status, data = http_json(f"{LOGIN}/token", method="POST", timeout=self.timeout, form={
                        "grant_type": "refresh_token", "client_id": self.client_id,
                        "refresh_token": tokens.get("refresh_token") or "", "scope": SCOPE})
                except NET_ERRORS as exc:
                    raise OneDriveError(f"No pude conectar con Microsoft: {exc}") from exc
                if status != 200 or not isinstance(data, dict) or not data.get("access_token"):
                    self.unlink()
                    raise OneDriveAuthError("Tu sesión de OneDrive caducó: vuelve a conectarla en Ajustes › Cuentas.")
                self._save(data)
                tokens = self._tokens() or {}
            return str(tokens.get("access_token") or "")

    # --- archivos ----------------------------------------------------------------------------------
    def _get(self, url: str) -> dict:
        try:
            status, data = http_json(url if url.startswith("http") else f"{GRAPH}{url}", timeout=self.timeout,
                                     headers={"Authorization": f"Bearer {self._access()}"})
        except NET_ERRORS as exc:
            raise OneDriveError(f"No pude conectar con OneDrive: {exc}") from exc
        if status == 401:
            raise OneDriveAuthError("Tu sesión de OneDrive caducó: vuelve a conectarla en Ajustes › Cuentas.")
        if status == 404:
            raise OneDriveError("Esa carpeta ya no está en tu OneDrive.")
        if status != 200 or not isinstance(data, dict):
            raise OneDriveError(f"OneDrive respondió HTTP {status}")
        return data

    @staticmethod
    def _children_url(path: str) -> str:
        path = path.strip("/")
        select = "$select=id,name,size,folder,file,createdDateTime&$top=200"  # cuándo lo subiste: «Recién agregado»
        return f"/me/drive/root/children?{select}" if not path else f"/me/drive/root:/{quote(path)}:/children?{select}"

    def children(self, path: str = "") -> list[dict]:
        """Lo que hay en una carpeta (las que tú abres al elegir dónde están tus películas)."""
        out, url = [], self._children_url(path)
        while url and len(out) < MAX_FILES:
            data = self._get(url)
            out += [r for r in data.get("value") or [] if isinstance(r, dict)]
            url = data.get("@odata.nextLink")
        return out

    def folders(self, path: str = "") -> list[dict]:
        return [{"name": r["name"], "path": f"{path.strip('/')}/{r['name']}".strip("/"), "count": (r.get("folder") or {}).get("childCount", 0)}
                for r in self.children(path) if r.get("folder") and r.get("name")]

    def videos(self, path: str) -> list[dict]:
        """Los videos de esa carpeta y sus subcarpetas: {"id", "name", "path", "size", ...lo que dice su nombre}."""
        found: list[dict] = []

        def walk(folder: str, depth: int) -> None:
            for r in self.children(folder):
                if len(found) >= MAX_FILES:
                    return
                name = r.get("name") or ""
                if r.get("folder") and depth < DEPTH:
                    walk(f"{folder}/{name}".strip("/"), depth + 1)
                elif r.get("file") and (info := parse_name(name)):
                    found.append({"id": r["id"], "name": name, "path": f"{folder}/{name}".strip("/"), "size": r.get("size") or 0,
                                  "added": added_at(r.get("createdDateTime")), **info})
        walk(path.strip("/"), 0)
        return found

    def stream_url(self, item_id: str) -> str:
        """La dirección temporal del archivo (~1 h), para que el reproductor lo lea por partes."""
        if not re.fullmatch(r"[A-Za-z0-9!._-]{1,200}", item_id or ""):
            raise OneDriveError("Archivo inválido")
        data = self._get(f"/me/drive/items/{item_id}?$select=id,@microsoft.graph.downloadUrl")
        url = data.get("@microsoft.graph.downloadUrl")
        if not isinstance(url, str) or not url.startswith("https://"):
            raise OneDriveError("OneDrive no dio la dirección del archivo.")
        return url
