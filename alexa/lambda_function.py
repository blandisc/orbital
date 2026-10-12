"""Skill personalizada de Alexa para Orbital (Python, sin dependencias).

Funciona igual como skill alojada por Amazon ("Alexa-hosted", recomendado: sin cuenta de AWS) o
como Lambda propia. La configuración sale de `orbital.json` junto a este archivo (lo genera
`orbital alexa setup`) o de variables de entorno, que tienen prioridad:
  url       / ORBITAL_URL     Dirección pública del túnel (p. ej. https://legion.tu-tailnet.ts.net)
  token     / ORBITAL_TOKEN   El mismo valor que server.token en config.yaml
  skill_id  / ALEXA_SKILL_ID  (opcional) El ID de tu skill: rechaza peticiones de otras skills
"""

from __future__ import annotations

import http.client
import json
import os
import threading
import urllib.error
import urllib.request
from pathlib import Path


def _settings() -> dict:
    path = Path(__file__).with_name("orbital.json")
    try:
        data = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
    except ValueError:
        data = {}
    return {
        "url": (os.environ.get("ORBITAL_URL") or data.get("url") or "").rstrip("/"),
        "token": os.environ.get("ORBITAL_TOKEN") or data.get("token") or "",
        "skill_id": os.environ.get("ALEXA_SKILL_ID") or data.get("skill_id") or "",
    }


_SETTINGS = _settings()
ORBITAL_URL = _SETTINGS["url"]
ORBITAL_TOKEN = _SETTINGS["token"]
ALEXA_SKILL_ID = _SETTINGS["skill_id"]
TIMEOUT = 6  # s en TOTAL para hablar con la consola: Alexa corta a los ~8 s
MAX_SPEECH = 600  # Alexa acepta hasta 8000 caracteres; nadie quiere oír tanto

HELP = ("Puedes decir: abre Hollow Knight, pon Interstellar, sigue viendo, pausa, "
        "adelanta cinco minutos, salta la intro, pon subtítulos en español, pon el capítulo cinco, "
        "siguiente episodio o cierra el juego.")
# Intents de Amazon que se pueden decir con la skill abierta ("pausa", "continúa", "siguiente").
BUILT_IN = {"AMAZON.PauseIntent": "PauseIntent", "AMAZON.ResumeIntent": "ResumeIntent",
            "AMAZON.NextIntent": "NextEpisodeIntent", "AMAZON.PreviousIntent": "PreviousEpisodeIntent"}
OFFLINE = "No pude conectar con tu consola. ¿Está encendida y con Orbital abierto?"
SLOW = "Tu consola tardó en contestar. Si no pasó nada, vuelve a pedirlo."
BROKEN = "Algo salió mal con tu consola."


class Unreachable(Exception):
    pass


def speak(text, end: bool = True) -> dict:
    # Siempre texto que Alexa pueda decir: ni vacío, ni None, ni un número, ni 10 000 caracteres.
    text = text.strip() if isinstance(text, str) else ""
    if not text:
        text = "Listo."
    if len(text) > MAX_SPEECH:
        text = text[:MAX_SPEECH].rsplit(" ", 1)[0] + "…"
    response = {"outputSpeech": {"type": "PlainText", "text": text}, "shouldEndSession": end}
    if not end:
        response["reprompt"] = {"outputSpeech": {"type": "PlainText", "text": HELP}}
    return {"version": "1.0", "response": response}


def _post(req) -> bytes:
    with urllib.request.urlopen(req, timeout=TIMEOUT) as res:
        return res.read(1_000_000)


def call_orbital(intent: str, slots: dict[str, str] | None = None) -> dict:
    """Envía el intent a Orbital. Devuelve {"ok", "speech"}; lanza Unreachable si no hay conexión.
    El plazo es total: un túnel que gotea un byte cada medio segundo ya no la deja colgada 20 s."""
    if not ORBITAL_URL or not ORBITAL_TOKEN:
        return {"ok": False, "speech": "La skill no está configurada: falta la dirección o el token de tu consola."}
    req = urllib.request.Request(
        f"{ORBITAL_URL}/api/voice",
        data=json.dumps({"intent": intent, "slots": slots or {}}).encode(),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {ORBITAL_TOKEN}"},
        method="POST",
    )
    box: dict = {}

    def run() -> None:
        try:
            box["body"] = _post(req)
        except Exception as exc:  # noqa: BLE001 - se traduce abajo a algo que Alexa pueda decir
            box["error"] = exc

    worker = threading.Thread(target=run, daemon=True)
    worker.start()
    worker.join(TIMEOUT + .5)
    if worker.is_alive():
        return {"ok": False, "speech": SLOW}
    exc = box.get("error")
    if isinstance(exc, urllib.error.HTTPError):
        if exc.code == 401:
            return {"ok": False, "speech": "Tu consola rechazó el token. Vuelve a copiar el archivo orbital de la skill."}
        if exc.code == 429:
            return {"ok": False, "speech": "Hubo demasiados intentos con un token equivocado. Espera unos minutos."}
        if exc.code in (502, 503, 504):
            raise Unreachable from exc  # el túnel está, pero Orbital no responde
        return {"ok": False, "speech": "Tu consola respondió con un error."}
    if isinstance(exc, (urllib.error.URLError, TimeoutError, OSError, http.client.HTTPException)):
        raise Unreachable from exc
    if exc is not None:
        return {"ok": False, "speech": BROKEN}
    try:
        data = json.loads(box.get("body", b"").decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        return {"ok": False, "speech": BROKEN}  # una página de error del túnel, no Orbital
    if not isinstance(data, dict):
        return {"ok": False, "speech": BROKEN}
    speech = data.get("speech")
    return {"ok": bool(data.get("ok")), "speech": speech if isinstance(speech, str) and speech.strip() else "Listo."}


def slot_values(intent: dict) -> dict[str, str]:
    values = {}
    slots = intent.get("slots") if isinstance(intent, dict) else None
    for name, slot in (slots.items() if isinstance(slots, dict) else ()):
        if not isinstance(slot, dict):
            continue
        resolved = (slot.get("slotValue") or {}).get("resolutions") or slot.get("resolutions") or {}
        value = slot.get("value")
        # Si el slot tiene sinónimos (DIRECTION), usa el valor canónico.
        for auth in resolved.get("resolutionsPerAuthority") or [] if isinstance(resolved, dict) else []:
            if not isinstance(auth, dict) or (auth.get("status") or {}).get("code") != "ER_SUCCESS_MATCH":
                continue
            first = (auth.get("values") or [{}])[0]
            canonical = ((first or {}).get("value") or {}).get("name") if isinstance(first, dict) else None
            if isinstance(canonical, str) and canonical:
                value = canonical
                break
        if isinstance(value, str) and value.strip():
            values[name] = value.strip()[:200]
    return values


def skill_id(event: dict) -> str | None:
    session = (event.get("session") or {}).get("application") or {}
    context = ((event.get("context") or {}).get("System") or {}).get("application") or {}
    return session.get("applicationId") or context.get("applicationId")


def lambda_handler(event: dict, context=None) -> dict:
    if ALEXA_SKILL_ID and skill_id(event if isinstance(event, dict) else {}) != ALEXA_SKILL_ID:
        # Otra skill (o alguien) usando tu Lambda: no se reenvía nada a la consola.
        raise PermissionError("applicationId no autorizado")
    try:
        return _handle(event)
    except Unreachable:
        return speak(OFFLINE)
    except Exception:  # noqa: BLE001 - Alexa siempre recibe algo que decir, nunca «hubo un problema con la skill»
        return speak(BROKEN)


def _handle(event: dict) -> dict:
    request = event.get("request") if isinstance(event, dict) else None
    request = request if isinstance(request, dict) else {}
    kind = request.get("type")
    if kind == "LaunchRequest":
        # "Alexa, abre mi consola": muestra la interfaz si saliste al escritorio.
        answer = call_orbital("OpenOrbitalIntent")
        if not answer["ok"] and answer["speech"] != "Listo.":
            return speak(answer["speech"])  # token rechazado, demasiados intentos…: dilo, no «listo»
        return speak("Orbital listo. ¿Qué quieres jugar o ver?", end=False)
    if kind == "SessionEndedRequest":
        return {"version": "1.0", "response": {}}
    if kind != "IntentRequest":
        return speak("No entendí.")

    intent = request.get("intent") if isinstance(request.get("intent"), dict) else {}
    name = intent.get("name")
    if not isinstance(name, str) or not name:
        return speak("No entendí. " + HELP, end=False)
    if name == "AMAZON.HelpIntent":
        return speak(HELP, end=False)
    if name in ("AMAZON.StopIntent", "AMAZON.CancelIntent"):
        return speak("Hasta luego.")
    if name == "AMAZON.FallbackIntent":
        return speak("No entendí. " + HELP, end=False)
    if name == "AMAZON.NavigateHomeIntent":
        name, slots = "NavigateIntent", {"direction": "home"}
    elif name in BUILT_IN:
        name, slots = BUILT_IN[name], {}
    else:
        slots = slot_values(intent)
    return speak(call_orbital(name, slots)["speech"])
