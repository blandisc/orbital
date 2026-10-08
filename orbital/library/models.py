from __future__ import annotations

from dataclasses import dataclass, field


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
            "runners": [{"id": r.id, "name": r.name} for r in self.runners],
            "runner": self.runner().id if self.runners else None,
        }
