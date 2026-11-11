"""Actualizar Orbital desde la consola: trae lo nuevo de su repositorio, lo prueba y, si algo
falla, vuelve a la versión que tenías.

Pasos de "Actualizar ahora":
  1. Solo si no hay cambios a medio hacer en la carpeta (nunca se pisa trabajo sin guardar).
  2. git merge --ff-only con lo nuevo (sin mezclas raras). En `main`, si el repositorio tiene la etiqueta `tv-estable`
     (la mueve la CI cuando todo pasa, D8-A), se actualiza hasta esa etiqueta y no hasta la punta de `main`: la TV nunca
     baja algo que la CI no aprobó. Sin la etiqueta, hasta lo último de la rama, PERO solo si esta tele nunca la ha visto:
     si ya la vio alguna vez y luego falta, no se actualiza y lo dice (en la bitácora y en «Actualizar ahora»).
  3. Sin dependencias nuevas (requirements.lock igual): la versión nueva se prueba en una copia aparte (`git worktree`
     temporal) mientras Orbital sigue sirviendo la de siempre desde su carpeta, sin mezclar archivos viejos y nuevos
     (F9). Solo si pasa, la carpeta avanza (un merge --ff-only, al instante). Si falla, la carpeta ni se tocó.
  4. Con dependencias nuevas, como antes: se avanza la carpeta, se instalan y se prueba ahí (las dependencias viven en
     el mismo .venv, no se pueden probar aparte). Si fallan: git reset a la versión anterior (y sus dependencias).
  5. Orbital se reabre solo con la versión nueva (el vigilante lo reabre: código RESTART).
"""

from __future__ import annotations

import logging
import os
import shutil
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass, field
from pathlib import Path

log = logging.getLogger(__name__)

REPO = Path(__file__).resolve().parents[1]
CHECK_EVERY = 600.0  # s: no preguntar a GitHub más seguido
STABLE_TAG = "tv-estable"  # la mueve la CI cuando todo pasa en main (D8-A)
STABLE_BRANCH = "main"
SEEN_KEY = "orbital.stableseen"  # en el repositorio de la tele: ya se actualizó alguna vez desde tv-estable
MISSING_TAG = ("La etiqueta tv-estable ya no está en GitHub. Esta tele se actualiza solo con lo que la revisión "
               "automática aprobó, así que no actualizo hasta que vuelva.")


@dataclass
class UpdateInfo:
    available: int = 0  # cuántos cambios nuevos hay
    changes: list[str] = field(default_factory=list)  # sus títulos
    branch: str = ""
    error: str = ""  # por qué no se puede (sin git, cambios sin guardar, sin red…)
    ref: str = ""  # hasta dónde se actualiza: origin/<rama> o la etiqueta tv-estable (no se le enseña a nadie)

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
        from .supervisor import updating_flag

        self.updating_flag = updating_flag()

    def dirty(self) -> bool:
        """¿Hay cambios sin guardar en archivos de Orbital? (Lo no versionado no cuenta.)"""
        return any(not line.startswith("??") for line in self.git("status", "--porcelain").splitlines())

    def check(self, force: bool = False) -> UpdateInfo:
        if self._checked and not force and time.monotonic() - self._checked[0] < CHECK_EVERY:
            return self._checked[1]
        info = UpdateInfo()
        if getattr(sys, "frozen", False):
            info.error = "Esta copia es Orbital.exe: se actualiza empaquetando la versión nueva (scripts/build_exe.py)."
            self._checked = (time.monotonic(), info)
            return info
        try:
            info.branch = self.git("rev-parse", "--abbrev-ref", "HEAD")
            self.git("fetch", "--quiet", "origin", info.branch, timeout=60)
            info.ref = self._stable_ref() if info.branch == STABLE_BRANCH else ""
            if info.branch == STABLE_BRANCH and not info.ref and self._seen_stable():
                # Esta tele ya se actualizaba desde la etiqueta: si falta, no se baja la punta de main sin la CI.
                info.error = MISSING_TAG
                log.warning("La etiqueta %s ya no está en GitHub: no actualizo desde main sin la aprobación de la CI",
                            STABLE_TAG)
                self._checked = (time.monotonic(), info)
                return info
            info.ref = info.ref or f"origin/{info.branch}"
            log_lines = self.git("log", "--format=%s", f"HEAD..{info.ref}")
            info.changes = [line for line in log_lines.splitlines() if line][:20]
            info.available = int(self.git("rev-list", "--count", f"HEAD..{info.ref}"))
            if info.available and self.dirty():
                info.error = "Hay cambios sin guardar en la carpeta de Orbital: no actualizo para no perderlos."
        except (OSError, RuntimeError, subprocess.TimeoutExpired, ValueError) as exc:
            info.error = f"No pude buscar actualizaciones: {exc}"
        self._checked = (time.monotonic(), info)
        return info

    def _stable_ref(self) -> str:
        """La etiqueta tv-estable al día si existe en GitHub ("" si no). Se trae a la fuerza: la etiqueta se mueve. Que
        esta tele la vio queda anotado en su repositorio (`git config orbital.stableseen`): desde entonces, si un día
        falta, no se actualiza (`check`)."""
        if not self.git("ls-remote", "--tags", "origin", f"refs/tags/{STABLE_TAG}", timeout=60):
            return ""
        self.git("fetch", "--quiet", "--force", "origin", f"+refs/tags/{STABLE_TAG}:refs/tags/{STABLE_TAG}", timeout=60)
        if not self._seen_stable():
            try:
                self.git("config", "--local", SEEN_KEY, "true")
            except (OSError, RuntimeError, subprocess.SubprocessError):
                log.info("No pude anotar que esta tele ya vio la etiqueta %s", STABLE_TAG, exc_info=True)
        return f"refs/tags/{STABLE_TAG}"

    def _seen_stable(self) -> bool:
        try:
            return self.git("config", "--local", "--get", SEEN_KEY) == "true"
        except (OSError, RuntimeError, subprocess.SubprocessError):
            return False  # sin la clave, git sale con 1

    def _lock_id(self, ref: str = "HEAD") -> str:
        """Qué versión de requirements.lock hay en `ref` ("" si no hay)."""
        try:
            return self.git("rev-parse", f"{ref}:requirements.lock")
        except RuntimeError:
            return ""

    def _apply_aside(self, info: UpdateInfo, target: str, before: str, progress) -> tuple[bool, str]:
        """F9: prueba `target` en una copia aparte y solo si pasa avanza la carpeta. Orbital sigue sirviendo la versión de
        siempre, completa, mientras tanto."""
        aside = Path(tempfile.mkdtemp(prefix="orbital-update-"))
        try:
            progress(f"Descargando {info.available} cambio{'s' if info.available != 1 else ''}…")
            self.git("worktree", "add", "--detach", "--force", str(aside), target, timeout=300)
            progress("Probando la versión nueva…")
            if not self._tests_pass(aside):
                self._checked = None
                return False, "La versión nueva no pasó sus pruebas: sigues con la versión que tenías."
            self.git("merge", "--ff-only", target)
        except (OSError, RuntimeError, subprocess.SubprocessError) as exc:
            self._checked = None
            try:  # el merge --ff-only no deja nada a medias, pero si avanzó y algo después falló, de regreso
                if self.git("rev-parse", "HEAD") != before:
                    self.git("reset", "--hard", before)
            except (OSError, RuntimeError, subprocess.SubprocessError):
                return False, f"No se pudo actualizar ({exc}). No pude volver del todo a tu versión: reinicia Orbital."
            return False, f"No se pudo actualizar ({exc}): sigues con la versión que tenías."
        finally:
            self._drop_aside(aside)
        log.info("Orbital actualizado (probado aparte): %s -> %s", before[:7], self.git("rev-parse", "--short", "HEAD"))
        self._checked = None  # «hay N cambios» ya no es cierto
        return True, "Listo: Orbital se reabre con la versión nueva."

    def _drop_aside(self, aside: Path) -> None:
        """Quita la copia aparte; si Windows aún tiene un archivo abierto, la borra como pueda y git la olvida."""
        try:
            self.git("worktree", "remove", "--force", str(aside), timeout=120)
        except (OSError, RuntimeError, subprocess.SubprocessError):
            shutil.rmtree(aside, ignore_errors=True)
        try:
            self.git("worktree", "prune", timeout=60)
        except (OSError, RuntimeError, subprocess.SubprocessError):
            log.debug("No pude limpiar la lista de copias de git", exc_info=True)
        shutil.rmtree(aside, ignore_errors=True)

    def _pip(self) -> None:
        lock = self.repo / "requirements.lock"
        if lock.exists():
            self.run([self.python, "-m", "pip", "install", "-q", "-r", str(lock)], cwd=self.repo, check=True,
                     capture_output=True, timeout=600, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))

    def _tests_pass(self, where: Path | None = None) -> bool:
        """Las pruebas de la versión en `where` (la carpeta de Orbital, o la copia aparte). En la copia, PYTHONPATH
        primero: así se importa SU `orbital` y no el de la carpeta (que el .venv puede tener instalado como editable)."""
        where = where or self.repo
        env = {**os.environ, "PYTHONPATH": str(where) + (os.pathsep + os.environ["PYTHONPATH"]
                                                         if os.environ.get("PYTHONPATH") else "")}
        # `-m "not reloj"`: las pocas pruebas que dependen del reloj real (con la consola cargada podrían rechazar al azar una
        # versión buena) no corren aquí; sí en la CI, que ya las pasó antes de mover la etiqueta tv-estable.
        result = self.run([self.python, "-m", "pytest", "-q", "-x", "-p", "no:cacheprovider", "--ignore=tests/smoke",
                           "-m", "not reloj"],
                          cwd=where, capture_output=True, text=True, timeout=900, env=env,
                          creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        if result.returncode:
            log.warning("Las pruebas de la versión nueva fallaron:\n%s", (result.stdout or "")[-2000:])
        return result.returncode == 0

    def apply(self, progress=lambda message: None) -> tuple[bool, str]:
        """(True, mensaje) si quedó la versión nueva; (False, por qué) si se quedó la anterior. Mientras tanto deja la
        marca de «actualizando»: el vigilante no reinicia a Orbital por lento (las pruebas cargan la consola)."""
        flag = self.updating_flag
        try:
            flag.parent.mkdir(parents=True, exist_ok=True)
            flag.write_text(str(time.time()), encoding="utf-8")
        except OSError:
            log.debug("No pude dejar la marca de «actualizando»", exc_info=True)
        try:
            return self._apply(progress)
        finally:
            flag.unlink(missing_ok=True)

    def _apply(self, progress) -> tuple[bool, str]:
        info = self.check(force=True)
        if info.error:
            return False, info.error
        if not info.available:
            return False, "Ya tienes la versión más reciente."
        before = self.git("rev-parse", "HEAD")
        lock_before = self._lock_id()
        target = info.ref or f"origin/{info.branch}"
        if self._lock_id(target) == lock_before:
            return self._apply_aside(info, target, before, progress)
        try:
            progress(f"Descargando {info.available} cambio{'s' if info.available != 1 else ''}…")
            self.git("merge", "--ff-only", info.ref or f"origin/{info.branch}")
            if self._lock_id() != lock_before:
                progress("Instalando lo que necesita…")
                self._pip()
            progress("Probando la versión nueva…")
            if self._tests_pass():
                log.info("Orbital actualizado: %s -> %s", before[:7], self.git("rev-parse", "--short", "HEAD"))
                self._checked = None  # «hay N cambios» ya no es cierto
                return True, "Listo: Orbital se reabre con la versión nueva."
            reason = "La versión nueva no pasó sus pruebas"
        except (OSError, RuntimeError, subprocess.SubprocessError) as exc:
            reason = f"No se pudo actualizar ({exc})"
        progress("Volviendo a tu versión…")
        try:
            self.git("reset", "--hard", before)
            self._pip()
        except (OSError, RuntimeError, subprocess.SubprocessError):
            log.warning("No pude volver del todo a la versión anterior")
            self._checked = None
            return False, f"{reason}. No pude volver del todo a tu versión: reinicia Orbital."
        self._checked = None
        return False, f"{reason}: sigues con la versión que tenías."
