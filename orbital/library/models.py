from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class LibraryItem:
    id: str
    title: str
    category: str  # "steam", "emulators", "media", "apps"
    source: str  # p. ej. "steam", id del emulador, "stremio"
    subtitle: str = ""
    image: str | None = None
    # Cómo se lanza: un URI (steam://, stremio://, https://) o un comando.
    uri: str | None = None
    argv: list[str] = field(default_factory=list)
    cwd: str | None = None

    def public(self) -> dict:
        return {
            "id": self.id,
            "title": self.title,
            "category": self.category,
            "source": self.source,
            "subtitle": self.subtitle,
            "image": self.image,
        }
