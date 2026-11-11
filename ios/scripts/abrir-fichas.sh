#!/bin/zsh
# abrir-fichas.sh — abre la ficha de una película y la de una serie en un simulador y dice si la app se cerró (revisión del
# 11 nov 2026). Sirve para la compilación Debug y la Release: el cierre de `TitleView.oneColumnLayout` (EXC_BAD_ACCESS, 11 nov)
# solo salía al abrir una ficha, así que esto es lo mínimo que hay que correr antes de dar por buena una compilación.
#
# Uso:  ios/scripts/abrir-fichas.sh <Orbital.app> <udid del simulador> [veces]
#   Ejemplo:
#     ios/scripts/abrir-fichas.sh /tmp/dd-orbital/Build/Products/Debug-iphonesimulator/Orbital.app <udid> 3
#   El simulador ya debe estar prendido (`xcrun simctl boot <udid>`) y es tuyo: este script no lo apaga ni lo borra.
#   Deja las capturas en /tmp/orbital-fichas/ (bórralas al terminar).
set -euo pipefail
APP=${1:?falta la ruta de Orbital.app}
UDID=${2:?falta el udid del simulador}
TIMES=${3:-2}
BUNDLE=mx.iracheta.orbital
OUT=/tmp/orbital-fichas
mkdir -p "$OUT"
xcrun simctl install "$UDID" "$APP"
reports_before=$(ls ~/Library/Logs/DiagnosticReports 2>/dev/null | grep -c '^Orbital' || true)
fails=0
for i in $(seq 1 "$TIMES"); do
  for title in movie:tt0816692 series:tt0386676; do
    xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
    xcrun simctl launch "$UDID" "$BUNDLE" -demo -demo-no-idle -demo-title "$title" >/dev/null
    sleep 6   # la ficha llega, carga sus datos y entra la animación
    running=$(xcrun simctl spawn "$UDID" launchctl list)   # sin `| grep -q`: con pipefail, el corte de grep parecía un cierre
    if [[ "$running" == *"UIKitApplication:$BUNDLE"* ]]; then
      xcrun simctl io "$UDID" screenshot "$OUT/${title/:/-}-$i.png" >/dev/null 2>&1
      echo "bien: $title (vuelta $i)"
    else
      echo "SE CERRÓ: $title (vuelta $i)"; fails=$((fails + 1))
    fi
  done
done
xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
reports_after=$(ls ~/Library/Logs/DiagnosticReports 2>/dev/null | grep -c '^Orbital' || true)
(( reports_after > reports_before )) && { echo "Hay un reporte de cierre nuevo en ~/Library/Logs/DiagnosticReports"; fails=$((fails + 1)); }
(( fails == 0 )) && echo "Las fichas abren sin cerrarse." || { echo "$fails problema(s)."; exit 1; }
