"""Skill personalizada de Alexa para Orbital (Python, sin dependencias).

Funciona igual como skill alojada por Amazon ("Alexa-hosted", recomendado: sin cuenta de AWS) o
como Lambda propia. La configuración sale de `orbital.json` junto a este archivo (lo genera
`orbital alexa setup`) o de variables de entorno, que tienen prioridad:
  url       / ORBITAL_URL     Dirección pública del túnel (p. ej. https://legion.tu-tailnet.ts.net)
  token     / ORBITAL_TOKEN   El mismo valor que server.token en config.yaml
  skill_id  / ALEXA_SKILL_ID  (opcional) El ID de tu skill: rechaza peticiones de otras skills
"""

from __future__ import annotations

import json
import os
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
TIMEOUT = 6  # Alexa corta a los ~8 s

HELP = ("Puedes decir: abre Hollow Knight, pon Interstellar, sigue viendo, pausa, "
        "adelanta cinco minutos, pon subtítulos en español, siguiente episodio o cierra el juego.")
# Intents de Amazon que se pueden decir con la skill abierta ("pausa", "continúa", "siguiente").
BUILT_IN = {"AMAZON.PauseIntent": "PauseIntent", "AMAZON.ResumeIntent": "ResumeIntent",
            "AMAZON.NextIntent": "NextEpisodeIntent"}
OFFLINE = "No pude conectar con tu consola. ¿Está encendida y con Orbital abierto?"


class Unreachable(Exception):
    pass


def speak(text: str, end: bool = True) -> dict:
    response = {"outputSpeech": {"type": "PlainText", "text": text}, "shouldEndSession": end}
    if not end:
        response["reprompt"] = {"outputSpeech": {"type": "PlainText", "text": HELP}}
    return {"version": "1.0", "response": response}


def call_orbital(intent: str, slots: dict[str, str] | None = None) -> dict:
    """Envía el intent a Orbital. Devuelve {"ok", "speech"}; lanza Unreachable si no hay conexión."""
    if not ORBITAL_URL or not ORBITAL_TOKEN:
        return {"ok": False, "speech": "La skill no está configurada: falta la dirección o el token de tu consola."}
    req = urllib.request.Request(
        f"{ORBITAL_URL}/api/voice",
        data=json.dumps({"intent": intent, "slots": slots or {}}).encode(),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {ORBITAL_TOKEN}"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as res:
            data = json.load(res)
            return {"ok": bool(data.get("ok")), "speech": data.get("speech", "Listo.")}
    except urllib.error.HTTPError as exc:
        if exc.code == 401:
            return {"ok": False, "speech": "Tu consola rechazó el token. Vuelve a copiar el archivo orbital de la skill."}
        if exc.code in (502, 503, 504):
            raise Unreachable from exc  # el túnel está, pero Orbital no responde
        return {"ok": False, "speech": "Tu consola respondió con un error."}
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        raise Unreachable from exc


def slot_values(intent: dict) -> dict[str, str]:
    values = {}
    for name, slot in (intent.get("slots") or {}).items():
        resolved = (slot.get("slotValue") or {}).get("resolutions") or slot.get("resolutions") or {}
        value = slot.get("value")
        # Si el slot tiene sinónimos (DIRECTION), usa el valor canónico.
        for auth in resolved.get("resolutionsPerAuthority", []):
            if auth.get("status", {}).get("code") == "ER_SUCCESS_MATCH":
                value = auth["values"][0]["value"]["name"]
                break
        if value:
            values[name] = value
    return values


def skill_id(event: dict) -> str | None:
    session = (event.get("session") or {}).get("application") or {}
    context = ((event.get("context") or {}).get("System") or {}).get("application") or {}
    return session.get("applicationId") or context.get("applicationId")


def lambda_handler(event: dict, context=None) -> dict:
    if ALEXA_SKILL_ID and skill_id(event) != ALEXA_SKILL_ID:
        # Otra skill (o alguien) usando tu Lambda: no se reenvía nada a la consola.
        raise PermissionError("applicationId no autorizado")

    request = event.get("request", {})
    kind = request.get("type")
    try:
        if kind == "LaunchRequest":
            # "Alexa, abre mi consola": muestra la interfaz si saliste al escritorio.
            call_orbital("OpenOrbitalIntent")
            return speak("Orbital listo. ¿Qué quieres jugar o ver?", end=False)
        if kind == "SessionEndedRequest":
            return {"version": "1.0", "response": {}}
        if kind != "IntentRequest":
            return speak("No entendí.")

        intent = request["intent"]
        name = intent["name"]
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
    except Unreachable:
        return speak(OFFLINE)
