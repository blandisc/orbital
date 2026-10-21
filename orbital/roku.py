"""La tele (Roku TV): encenderla y ponerla en la entrada de Orbital, por la red local (ECP, puerto 8060).

«Alexa, abre Orbital» prende la tele, cambia a la entrada del Legion Go y muestra la consola. Nada corre en
segundo plano: solo se habla con la tele cuando se pide. `orbital tv setup` la encuentra y guarda cuál es.
"""

from __future__ import annotations

import logging
import re
import socket
import threading
import time
import urllib.request
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path

from .config import TvConfig

log = logging.getLogger(__name__)

PORT = 8060
SSDP = ("239.255.255.250", 1900)


@dataclass
class Found:
    host: str
    serial: str = ""
    mac: str = ""  # para despertarla por Wi-Fi si está en reposo profundo
    name: str = ""
    power: str = ""  # "PowerOn" si está prendida
    input: str = ""  # "hdmi1" si está en una entrada (no en una app de Roku)


def discover(timeout: float = 2.5) -> list[Found]:
    """Las Roku de la red (SSDP), con su número de serie y la MAC para despertarlas."""
    msg = (b"M-SEARCH * HTTP/1.1\r\nHost: 239.255.255.250:1900\r\nMan: \"ssdp:discover\"\r\n"
           b"ST: roku:ecp\r\nMX: 2\r\n\r\n")
    found: dict[str, Found] = {}
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.settimeout(0.5)
        sock.sendto(msg, SSDP)
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            try:
                data, _ = sock.recvfrom(4096)
            except OSError:
                continue
            text = data.decode("latin-1")
            where = re.search(r"(?im)^location:\s*http://([^:/\s]+)", text)
            if not where:
                continue
            serial = re.search(r"(?im)^usn:\s*uuid:roku:ecp:(\S+)", text)
            mac = re.search(r"(?im)^wakeup:\s*mac=([0-9a-f:]{17})", text)
            found[where.group(1)] = Found(where.group(1), serial.group(1) if serial else "", mac.group(1) if mac else "")
    return list(found.values())


def _request(host: str, path: str, post: bool = False, timeout: float = 3.0) -> str:
    req = urllib.request.Request(f"http://{host}:{PORT}{path}", data=b"" if post else None,
                                 method="POST" if post else "GET")
    with urllib.request.urlopen(req, timeout=timeout) as res:
        return res.read().decode("utf-8", "replace")


def describe(found: Found) -> Found:
    """Completa nombre, si está prendida y en qué entrada está."""
    info = ET.fromstring(_request(found.host, "/query/device-info"))
    found.name = info.findtext("friendly-device-name") or info.findtext("model-name") or found.host
    found.power = info.findtext("power-mode") or ""
    found.serial = found.serial or info.findtext("serial-number") or ""
    if not found.mac:
        mac = info.findtext("wifi-mac") if info.findtext("network-type") == "wifi" else info.findtext("ethernet-mac")
        found.mac = mac or ""
    app = ET.fromstring(_request(found.host, "/query/active-app")).find("app")
    app_id = app.get("id", "") if app is not None else ""
    found.input = app_id.removeprefix("tvinput.") if app_id.startswith("tvinput.") else ""
    return found


def wake_on_lan(mac: str) -> None:
    raw = bytes.fromhex(mac.replace(":", "").replace("-", ""))
    if len(raw) != 6:
        return
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        sock.sendto(b"\xff" * 6 + raw * 16, ("255.255.255.255", 9))


class RokuTv:
    """La tele de Orbital. Sin `host` en la configuración no hace nada."""

    WAIT = 20.0  # s: lo que puede tardar en prender desde el reposo profundo

    def __init__(self, config: TvConfig) -> None:
        self.config = config
        self._busy = threading.Lock()

    @property
    def enabled(self) -> bool:
        return bool(self.config.host)

    def _power(self, host: str) -> str:
        info = ET.fromstring(_request(host, "/query/device-info", timeout=2.0))
        return info.findtext("power-mode") or ""

    def _reachable_host(self) -> str | None:
        """La IP guardada; si cambió (DHCP), la busca por su número de serie."""
        try:
            self._power(self.config.host)
            return self.config.host
        except (OSError, ET.ParseError):
            pass
        if self.config.mac:
            wake_on_lan(self.config.mac)  # en reposo profundo no contesta hasta despertarla
        deadline = time.monotonic() + self.WAIT
        while time.monotonic() < deadline:
            try:
                self._power(self.config.host)
                return self.config.host
            except (OSError, ET.ParseError):
                pass
            if self.config.serial:
                for each in discover(timeout=1.5):
                    if each.serial == self.config.serial:
                        log.info("La tele cambió de IP: %s → %s (actualiza tv.host)", self.config.host, each.host)
                        self.config.host = each.host
                        return each.host
            time.sleep(1.0)
        return None

    def turn_on(self) -> bool:
        """Prende la tele y la pone en la entrada de Orbital. True si quedó así."""
        if not self.enabled or not self._busy.acquire(blocking=False):
            return False  # ya hay otro «prende la tele» en camino
        try:
            host = self._reachable_host()
            if host is None:
                log.warning("La tele (%s) no contesta: ¿«Inicio rápido de TV» está activado?", self.config.host)
                return False
            deadline = time.monotonic() + self.WAIT
            while self._power(host) != "PowerOn":
                _request(host, "/keypress/PowerOn", post=True)
                if time.monotonic() > deadline:
                    log.warning("La tele no prendió a tiempo")
                    return False
                time.sleep(1.0)
            _request(host, f"/launch/tvinput.{self.config.input}", post=True)
            log.info("Tele prendida en %s", self.config.input)
            return True
        except (OSError, ET.ParseError) as exc:
            log.warning("No pude prender la tele: %s", exc)
            return False
        finally:
            self._busy.release()

    def turn_on_soon(self) -> None:
        """Igual que turn_on pero sin esperar (Alexa necesita su respuesta en segundos)."""
        if self.enabled:
            threading.Thread(target=self.turn_on, name="tv-on", daemon=True).start()


def tv_section(found: Found) -> str:
    return (f"\ntv:\n  # La tele (Roku TV) que Orbital prende con «Alexa, abre Orbital». La escribió `orbital tv setup`.\n"
            f"  host: {found.host}\n  serial: {found.serial}\n  mac: \"{found.mac}\"\n  input: {found.input}\n")


def save(config_path: Path, found: Found) -> None:
    """Escribe (o reemplaza) la sección tv: de config.yaml sin tocar lo demás (ni los comentarios)."""
    lines = (config_path.read_text(encoding="utf-8-sig") if config_path.exists() else "").splitlines()
    if "tv:" in lines:  # la anterior: su línea y las sangradas que le siguen
        start = end = lines.index("tv:")
        while end + 1 < len(lines) and (not lines[end + 1].strip() or lines[end + 1][0] in " #"):
            end += 1
        del lines[start:end + 1]
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text("\n".join(lines).rstrip("\n") + "\n" + tv_section(found), encoding="utf-8")
