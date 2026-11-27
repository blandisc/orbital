#!/usr/bin/env python3
"""Escribe `ios/App/project.catalyst.yml`: la app de Mac de verdad (Mac Catalyst), sacada de `project.yml`.

Así hay un solo proyecto que mantener: este script copia `project.yml` y le cambia solo lo que la Mac necesita. Si un
cambio ya no encuentra su línea (alguien editó `project.yml`), se detiene y dice cuál.

- Nombre `OrbitalCatalyst` (crea `OrbitalCatalyst.xcodeproj`, esquema `Orbital`).
- Mac Catalyst con idioma Mac (familia 6, «Optimize Interface for Mac»): se dibuja al 100 %.
- Las bibliotecas del motor de video desde `ios/Vendor/catalyst` (ver `catalyst_bibliotecas.py`).
- Sin el widget, el grupo de apps ni los avisos: la Mac no tiene actividades en vivo. Con su llavero (pide perfil).
- Firmada con el equipo (automática): compilar con `-allowProvisioningUpdates`.
- Su propio identificador, para no pisar la Orbital instalada.

Uso (desde la raíz del repo):
    python3 ios/scripts/catalyst_proyecto.py && (cd ios/App && xcodegen generate --spec project.catalyst.yml)
"""

from __future__ import annotations

import sys
from pathlib import Path

APP = Path(__file__).resolve().parents[1] / "App"
BUNDLE_ID = "mx.iracheta.orbital.macprueba"

EDITS: list[tuple[str, str]] = [
    ("name: Orbital\n", "name: OrbitalCatalyst\n"),
    ("    revision: 60ac862285ec641d67a984964634b54b57151704   # 7.35.1\n",
     "    revision: 60ac862285ec641d67a984964634b54b57151704   # 7.35.1\n"
     "  # Las mismas que pide AetherEngine, con su rebanada de Mac Catalyst (un paquete local pisa al de GitHub).\n"
     "  FFmpegBuild:\n    path: ../Vendor/catalyst/FFmpegBuild\n"
     "  LibDovi:\n    path: ../Vendor/catalyst/LibDovi\n"
     "  LibTrueHD:\n    path: ../Vendor/catalyst/LibTrueHD\n"),
    ("      - target: OrbitalWidgets               # la actividad en vivo de las descargas\n", ""),
    ("        PRODUCT_BUNDLE_IDENTIFIER: mx.iracheta.orbital\n", f"        PRODUCT_BUNDLE_IDENTIFIER: {BUNDLE_ID}\n"),
    ('        TARGETED_DEVICE_FAMILY: "1,2"         # iPhone y iPad (y la Mac con chip de Apple, «Diseñada para iPad»)\n'
     "        SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD: YES\n",
     '        TARGETED_DEVICE_FAMILY: "1,2,6"       # 6 = idioma Mac: la Mac la dibuja al 100 %\n'
     "        SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD: NO\n"
     "        SUPPORTS_MACCATALYST: YES\n"
     "        DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER: NO\n"
     # Firma automática con el equipo de project.yml: Xcode registra el identificador y esta Mac la primera vez
     # (`-allowProvisioningUpdates`). Con firma de verdad hay `application-identifier`: descargas en segundo plano.
     "        CODE_SIGN_STYLE: Automatic\n"),
    ("    entitlements:\n"
     "      path: Build/Orbital.entitlements\n"
     "      properties:\n"
     "        com.apple.security.application-groups: [group.mx.iracheta.orbital]   # el snapshot del widget «Lo siguiente para ti»\n"
     "        aps-environment: development   # LA-B: la TV mantiene al día la isla «Viendo en la TV» con avisos de Apple\n",
     # Solo el llavero de la app: pide un perfil de verdad, y con él llega `application-identifier` (lo que piden las
     # descargas en segundo plano). Sin grupo de apps: en macOS su carpeta saca un aviso de permiso oculto.
     "    entitlements:\n"
     "      path: Build/Catalyst.entitlements\n"
     "      properties:\n"
     "        keychain-access-groups: [$(AppIdentifierPrefix)" + BUNDLE_ID + "]\n"),
    ("        LSSupportsOpeningDocumentsInPlace: false\n", ""),   # en macOS no se permite en NO
    # Su propia ficha: si las dos escribieran Build/Info.plist, generar un proyecto rompería el otro.
    ("      path: Build/Info.plist\n", "      path: Build/Catalyst-Info.plist\n"),
]


def main() -> None:
    text = (APP / "project.yml").read_text()
    for old, new in EDITS:
        if text.count(old) != 1:
            sys.exit(f"project.yml cambió: no encuentro (una sola vez)\n{old}")
        text = text.replace(old, new)
    header = "# GENERADO por ios/scripts/catalyst_proyecto.py desde project.yml: no se edita a mano.\n"
    (APP / "project.catalyst.yml").write_text(header + text)
    print("listo: ios/App/project.catalyst.yml")


if __name__ == "__main__":
    main()
