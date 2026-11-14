#!/bin/bash
# instalar-iphone.sh — compila Orbital en Release para el iPhone conectado, lo instala y guarda sus símbolos (dSYM) con su
# número de compilación (revisión del 11 nov 2026). Cada instalación lleva su número (`git rev-list --count HEAD`): así
# un cierre que llega del iPhone se lee con los símbolos de esa misma compilación (`guardar-dsym.sh`).
#
# Uso:  ios/scripts/instalar-iphone.sh [udid del iPhone] [edición: ultra|plus|orbital]
#   Sin aparato, usa el primer iPhone conectado que vea `xcrun devicectl list devices`. Edición por omisión: ultra.
#   Necesita: Xcode con la cuenta del equipo del proyecto (DEVELOPMENT_TEAM de project.yml), XcodeGen, y
#   ios/App/Secrets.xcconfig (no está en git). Compila en /tmp/dd-orbital-release (la de las instalaciones en el iPhone, la misma que usa la sesión que coordina).
#   Antes revisa que no haya ya 2 compilaciones en la Mac (`pgrep -x xcodebuild`): si las hay, espera.
#   Al terminar, ábrela una vez en el iPhone para que Siri aprenda los atajos.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
DEVICE=${1:-}
EDITION=${2:-ultra}
DERIVED=/tmp/dd-orbital-release
PRODUCTS="$DERIVED/Build/Products/Release-iphoneos"

case "$EDITION" in ultra|plus|orbital) ;; *) echo "Edición desconocida: $EDITION (ultra, plus u orbital)" >&2; exit 1 ;; esac
[[ -f "$REPO/ios/App/Secrets.xcconfig" ]] || { echo "Falta ios/App/Secrets.xcconfig (cópialo de Secrets.example.xcconfig)" >&2; exit 1; }
running=$( (pgrep -x xcodebuild || true) | wc -l | tr -d ' ')   # sin ninguna, pgrep sale con 1 y pipefail cortaba el script en silencio
(( running < 2 )) || { echo "Ya hay $running compilaciones en la Mac: espera a que termine una." >&2; exit 1; }

if [[ -z "$DEVICE" ]]; then
  list=/tmp/orbital-devices.json
  xcrun devicectl list devices --json-output "$list" >/dev/null
  DEVICE=$(/usr/bin/python3 -c '
import json, sys
devices = json.load(open(sys.argv[1]))["result"]["devices"]
for d in devices:
    hw = d.get("hardwareProperties", {})
    if hw.get("deviceType") == "iPhone" and hw.get("reality") == "physical" and d.get("connectionProperties", {}).get("tunnelState") != "unavailable":   # Xcode también lista los simuladores
        print(hw.get("udid", "")); break
' "$list")
  rm -f "$list"
  [[ -n "$DEVICE" ]] || { echo "No veo ningún iPhone conectado (xcrun devicectl list devices)." >&2; exit 1; }
fi

BUILD=$(git -C "$REPO" rev-list --count HEAD)
echo "Compilando Orbital ($EDITION) número $BUILD para $DEVICE…"
cd "$REPO/ios/App"
xcodegen >/dev/null
log=/tmp/orbital-instalar.log
if ! xcodebuild build -project Orbital.xcodeproj -scheme Orbital -configuration Release \
     -destination "id=$DEVICE" -derivedDataPath "$DERIVED" -allowProvisioningUpdates \
     CURRENT_PROJECT_VERSION="$BUILD" ORBITAL_EDITION="$EDITION" DEBUG_INFORMATION_FORMAT=dwarf-with-dsym \
     > "$log" 2>&1; then
  grep -E "error:|BUILD FAILED" "$log" | sort -u | head -n 40
  echo "No compiló (registro completo en $log)." >&2
  exit 1
fi
rm -f "$log"

xcrun devicectl device install app --device "$DEVICE" "$PRODUCTS/Orbital.app"
"$HERE/guardar-dsym.sh" "$PRODUCTS"
echo "Instalada Orbital ($EDITION), compilación $BUILD. Ábrela una vez en el iPhone (los atajos de Siri)."
