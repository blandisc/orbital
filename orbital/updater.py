"""Actualizar Orbital desde la consola: trae lo nuevo de su repositorio, lo prueba y, si algo
falla, vuelve a la versión que tenías.

Pasos de "Actualizar ahora":
  1. Solo si no hay cambios a medio hacer en la carpeta (nunca se pisa trabajo sin guardar).
  2. git merge --ff-only con lo nuevo de la misma rama (sin mezclas raras).
  3. Si cambiaron las dependencias (requirements.lock), se instalan.
  4. Se corren las pruebas. Si fallan: git reset a la versión anterior (y sus dependencias).
  5. Orbital se reabre solo con la versión nueva (el vigilante lo reabre: código RESTART).
"""

from __future__ import annotations

import logging
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

log = logging.getLogger(__name__)

REPO = Path(__file__).resolve().parents[1]
CHECK_EVERY = 600.0  # s: no preguntar a GitHub más seguido


@dataclass
class UpdateInfo:
    available: int = 0  # cuántos cambios nuevos hay
    changes: list[str] = field(default_factory=list)  # sus títulos
    branch: str = ""
    error: str = ""  # por qué no se puede (sin git, cambios sin guardar, sin red…)

    def public(self) -> dict:
        return {"available": self.available, "changes": self.changes, "branch": self.branch, "error": self.error}


def _git(*args: str, repo: Path = REPO, timeout: float = 60) -> str:
    out = subprocess.run(["git", *args], cwd=repo, capture_output=True, text=True, encoding="utf-8",
                         errors="replace", timeout=timeout, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    if out.returncode:
        raise RuntimeError((out.stderr or out.stdout).strip().splitlines()[-1] if (out.stderr or out.stdout) else "git falló")
    return out.stdout.strip()


class Updater:
    def __init__(self, repo: Path = REPO, git=_git, run=subprocess.run, python: str = sys.executable) -> None:
        self.repo = repo
        self.git = lambda *a, **k: git(*a, repo=repo, **k)
        self.run = run
        self.python = python
        self._checked: tuple[float, UpdateInfo] | None = None

    def dirty(self) -> bool:
        """¿Hay cambios sin guardar en archivos de Orbital? (Lo no versionado no cuenta.)"""
        return any(not line.startswith("??") for line in self.git("status", "--porcelain").splitlines())

    def check(self, force: bool = False) -> UpdateInfo:
        if self._checked and not force and time.monotonic() - self._checked[0] < CHECK_EVERY:
            return self._checked[1]
        info = UpdateInfo()
        try:
            info.branch = self.git("rev-parse", "--abbrev-ref", "HEAD")
            self.git("fetch", "--quiet", "origin", info.branch, timeout=60)
            log_lines = self.git("log", "--format=%s", f"HEAD..origin/{info.branch}")
            info.changes = [line for line in log_lines.splitlines() if line][:20]
            info.available = int(self.git("rev-list", "--count", f"HEAD..origin/{info.branch}"))
            if info.available and self.dirty():
                info.error = "Hay cambios sin guardar en la carpeta de Orbital: no actualizo para no perderlos."
        except (OSError, RuntimeError, subprocess.TimeoutExpired, ValueError) as exc:
            info.error = f"No pude buscar actualizaciones: {exc}"
        self._checked = (time.monotonic(), info)
        return info

    def _lock_id(self) -> str:
        """Qué versión de requirements.lock hay ("" si no hay)."""
        try:
            return self.git("rev-parse", "HEAD:requirements.lock")
        except RuntimeError:
            return ""

    def _pip(self) -> None:
        lock = self.repo / "requirements.lock"
        if lock.exists():
            self.run([self.python, "-m", "pip", "install", "-q", "-r", str(lock)], cwd=self.repo, check=True,
                     capture_output=True, timeout=600, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))

    def _tests_pass(self) -> bool:
        result = self.run([self.python, "-m", "pytest", "-q", "-x", "-p", "no:cacheprovider", "--ignore=tests/smoke"],
                          cwd=self.repo, capture_output=True, text=True, timeout=900,
                          creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        if result.returncode:
            log.warning("Las pruebas de la versión nueva fallaron:\n%s", (result.stdout or "")[-2000:])
        return result.returncode == 0

    def apply(self, progress=lambda message: None) -> tuple[bool, str]:
        """(True, mensaje) si quedó la versión nueva; (False, por qué) si se quedó la anterior."""
        info = self.check(force=True)
        if info.error:
            return False, info.error
        if not info.available:
            return False, "Ya tienes la versión más reciente."
        before = self.git("rev-parse", "HEAD")
        lock_before = self._lock_id()
        try:
            progress(f"Descargando {info.available} cambio{'s' if info.available != 1 else ''}…")
            self.git("merge", "--ff-only", f"origin/{info.branch}")
            if self._lock_id() != lock_before:
                progress("Instalando lo que necesita…")
                self._pip()
            progress("Probando la versión nueva…")
            if self._tests_pass():
                log.info("Orbital actualizado: %s -> %s", before[:7], self.git("rev-parse", "--short", "HEAD"))
                return True, "Listo: Orbital se reabre con la versión nueva."
            reason = "La versión nueva no pasó sus pruebas"
        except (OSError, RuntimeError, subprocess.SubprocessError) as exc:
            reason = f"No se pudo actualizar ({exc})"
        progress("Volviendo a tu versión…")
        self.git("reset", "--hard", before)
        try:
            self._pip()
        except (OSError, subprocess.SubprocessError):
            log.warning("No pude reinstalar las dependencias de la versión anterior")
        self._checked = None
        return False, f"{reason}: sigues con la versión que tenías."
