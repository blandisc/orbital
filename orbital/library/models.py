from __future__ import annotations

from dataclasses import asdict, dataclass, field
from pathlib import Path


@dataclass
class Runner:
    """Una forma de abrir el juego (p. ej. Ryujinx o Eden)."""

    id: str
    name: str
    argv: list[str]
    cwd: str | None = None


@dataclass
class LibraryItem:
    id: str
    title: str
    category: str  # "steam", "emulators", "media", "apps"
    source: str  # p. ej. "steam", id del emulador, "stremio"
    subtitle: str = ""  # sistema: "Nintendo Switch", "Steam"...
    image: str | None = None  # portada vertical (URL)
    hero: str | None = None  # imagen horizontal grande para el fondo (URL)
    # Cómo se lanza: un URI (steam://, stremio://, https://) o un comando.
    uri: str | None = None
    argv: list[str] = field(default_factory=list)
    cwd: str | None = None
    # Emuladores con alternativa: el primero que coincida con default_runner se usa por defecto.
    runners: list[Runner] = field(default_factory=list)
    default_runner: str | None = None
    steam_appid: int | None = None
    favorite: bool = False
    # Multimedia (Stremio): progreso 0..1 y última vez que se vio (epoch).
    progress: float | None = None
    last_watched: float | None = None
    # Imágenes en disco; se sirven por /api/art/<id> sin exponer la ruta.
    art_path: str | None = None
    hero_path: str | None = None
    logo_path: str | None = None
    icon_path: str | None = None  # apps: su ícono (p. ej. el de ES-DE, de su propia instalación)
    # Juegos de emulador: sistema y nombre de la ROM, para buscarles arte (scraper propio).
    system: str | None = None
    media_key: str | None = None
    # Datos extra para el héroe (Stremio: año, calificación, géneros, sinopsis, logotipo).
    extra: dict = field(default_factory=dict)

    def to_dict(self) -> dict:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict) -> LibraryItem:
        known = {k: v for k, v in data.items() if k in cls.__dataclass_fields__}
        # Una copia guardada con otra forma se rechaza aquí (y se vuelve a escanear), no a media interfaz.
        if not isinstance(known.get("id"), str) or not isinstance(known.get("title"), str):
            raise TypeError("elemento sin id o título")
        if not isinstance(known.get("extra", {}), dict) or not isinstance(known.get("runners") or [], list):
            raise TypeError("elemento con datos extra o emuladores inválidos")
        known["runners"] = [Runner(**r) for r in known.get("runners") or []]
        return cls(**known)

    def runner(self, runner_id: str | None = None) -> Runner | None:
        wanted = runner_id or self.default_runner
        return next((r for r in self.runners if r.id == wanted), self.runners[0] if self.runners else None)

    def public(self) -> dict:
        return {
            "id": self.id,
            "title": self.title,
            "category": self.category,
            "source": self.source,
            "subtitle": self.subtitle,
            "image": self.image,
            "hero": self.hero,
            "favorite": self.favorite,
            "progress": self.progress,
            **({"system": self.system} if self.system else {}),
            "runners": [{"id": r.id, "name": r.name} for r in self.runners],
            "runner": self.runner().id if self.runners else None,
            # Una copia: otro hilo (Cinemeta) completa `extra` mientras esto se convierte a JSON.
            **({"extra": dict(self.extra)} if self.extra else {}),
        }


def added_at(path) -> float | None:
    """Cuándo llegó un juego a esta PC: la fecha de creación de su archivo o carpeta (en Windows
    st_ctime es la creación, no cambia al abrirlo ni al actualizarlo)."""
    try:
        return Path(path).stat().st_ctime if path else None
    except OSError:
        return None
