"""Skill personalizada de Alexa para Orbital (AWS Lambda, Python 3.12, sin dependencias).

Variables de entorno de la Lambda:
  ORBITAL_URL    URL pública del túnel hacia tu Legion Go (p. ej. https://orbital.tudominio.com)
  ORBITAL_TOKEN  El mismo valor que server.token en config.yaml
"""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.request

ORBITAL_URL = os.environ.get("ORBITAL_URL", "").rstrip("/")
ORBITAL_TOKEN = os.environ.get("ORBITAL_TOKEN", "")
TIMEOUT = 6  # Alexa corta a los ~8 s

HELP = ("Puedes decir: abre Hollow Knight, busca Interstellar en Stremio, "
        "abre Stremio, cierra el juego o muévete a la derecha.")


def speak(text: str, end: bool = True) -> dict:
    response = {"outputSpeech": {"type": "PlainText", "text": text}, "shouldEndSession": end}
    if not end:
        response["reprompt"] = {"outputSpeech": {"type": "PlainText", "text": HELP}}
    return {"version": "1.0", "response": response}


def call_orbital(intent: str, slots: dict[str, str]) -> str:
    if not ORBITAL_URL or not ORBITAL_TOKEN:
        return "La skill no está configurada: faltan ORBITAL_URL u ORBITAL_TOKEN."
    req = urllib.request.Request(
        f"{ORBITAL_URL}/api/voice",
        data=json.dumps({"intent": intent, "slots": slots}).encode(),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {ORBITAL_TOKEN}"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as res:
            return json.load(res).get("speech", "Listo.")
    except urllib.error.HTTPError as exc:
        if exc.code == 401:
            return "Orbital rechazó el token. Revisa la configuración."
        return "Orbital respondió con un error."
    except (urllib.error.URLError, TimeoutError):
        return "No pude conectar con tu consola. ¿Está encendida?"


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


def lambda_handler(event: dict, context=None) -> dict:
    request = event.get("request", {})
    kind = request.get("type")
    if kind == "LaunchRequest":
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
    if name == "AMAZON.NavigateHomeIntent":
        return speak(call_orbital("NavigateIntent", {"direction": "home"}))
    if name == "AMAZON.FallbackIntent":
        return speak("No entendí. " + HELP, end=False)
    return speak(call_orbital(name, slot_values(intent)))
