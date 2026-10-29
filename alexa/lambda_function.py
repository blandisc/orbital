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
import time
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

HELP = ("Puedes decir: prende la tele, pon The Office, sigue viendo, pausa, siguiente episodio, sube el volumen, "
        "pon el canal ADN 40 o apaga la tele. "
        "La lista completa está en la app de Orbital del iPhone, en Ajustes.")
# Sin coincidencia: corto y con ejemplos de lo que sí se puede (la ayuda entera era demasiado larga para repetirla).
FALLBACK = "No entendí eso. Prueba con: quiero ver Interstellar, pon la tele o qué sale hoy."
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


RETRY_WITHIN = 2.5  # s: si la conexión falló así de rápido (el túnel despertando), se intenta una vez más


def call_orbital(intent: str | None, slots: dict[str, str] | None = None, *, text: str | None = None) -> dict:
    """Envía el intent (o la frase tal cual, `text`) a Orbital. Devuelve {"ok", "speech"}; lanza Unreachable si no hay
    conexión. Si la conexión falla rápido (el túnel despertando) se intenta una vez más: antes un tropiezo del túnel era
    «No pude conectar con tu consola» aunque estuviera encendida."""
    started = time.monotonic()
    try:
        return _call_orbital(intent, slots, text)
    except Unreachable:
        if time.monotonic() - started > RETRY_WITHIN:
            raise
        return _call_orbital(intent, slots, text)


def _call_orbital(intent: str | None, slots: dict[str, str] | None, text: str | None) -> dict:
    """Un intento. El plazo es total: un túnel que gotea un byte cada medio segundo ya no la deja colgada 20 s."""
    if not ORBITAL_URL or not ORBITAL_TOKEN:
        return {"ok": False, "speech": "La skill no está configurada: falta la dirección o el token de tu consola."}
    payload = {"text": text} if text is not None else {"intent": intent, "slots": slots or {}}
    req = urllib.request.Request(
        f"{ORBITAL_URL}/api/voice",
        data=json.dumps(payload).encode(),
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


def slot_values(intent: dict, canonical: bool = True) -> dict[str, str]:
    """Los slots dichos. `canonical`: el valor canónico si tiene sinónimos (DIRECTION); el comodín va tal cual se oyó."""
    values = {}
    slots = intent.get("slots") if isinstance(intent, dict) else None
    for name, slot in (slots.items() if isinstance(slots, dict) else ()):
        if not isinstance(slot, dict):
            continue
        resolved = (slot.get("slotValue") or {}).get("resolutions") or slot.get("resolutions") or {}
        value = slot.get("value")
        # Si el slot tiene sinónimos (DIRECTION), usa el valor canónico.
        for auth in (resolved.get("resolutionsPerAuthority") or [] if isinstance(resolved, dict) and canonical else []):
            if not isinstance(auth, dict) or (auth.get("status") or {}).get("code") != "ER_SUCCESS_MATCH":
                continue
            first = (auth.get("values") or [{}])[0]
            resolved_name = ((first or {}).get("value") or {}).get("name") if isinstance(first, dict) else None
            if isinstance(resolved_name, str) and resolved_name:
                value = resolved_name
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
        try:
            call_orbital("GuideIntent")  # la guía en la tele (si la consola no contesta, la ayuda se dice igual)
        except Unreachable:
            pass
        return speak(HELP, end=False)
    if name in ("AMAZON.StopIntent", "AMAZON.CancelIntent"):
        return speak("Hasta luego.")
    if name == "AMAZON.FallbackIntent":
        # Alexa no da el texto, pero la consola lo anota (voz.log) y lo avisa en la tele: antes no quedaba rastro.
        # Lo que dice es siempre el de aquí (una consola sin actualizar contestaría «Ese comando todavía no está disponible»).
        call_orbital("FallbackIntent")
        return speak(FALLBACK, end=False)
    if name in ("FreeTextIntent", "CommandIntent"):
        # Lo que Alexa no supo acomodar en otro intent («por favor pon…», «pausa en Orbital»): la frase tal cual a la
        # consola, que la entiende con el mismo intérprete del iPhone (antes Alexa decía «No entendí» sin preguntarle).
        # CommandIntent es el comodín: la frase entera, sin frase de apoyo.
        query = slot_values(intent, canonical=False).get("query" if name == "FreeTextIntent" else "command", "")
        if not query:
            return speak(FALLBACK, end=False)
        return speak(call_orbital(None, text=query)["speech"])
    if name == "AMAZON.NavigateHomeIntent":
        name, slots = "NavigateIntent", {"direction": "home"}
    elif name in BUILT_IN:
        name, slots = BUILT_IN[name], {}
    else:
        slots = slot_values(intent)
    return speak(call_orbital(name, slots)["speech"])
