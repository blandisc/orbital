#!/bin/zsh
# Las cuatro combinaciones de una pantalla antes de cerrarla: claro y oscuro, en un iPhone chico y en uno grande.
#   scripts/ios_capture_matrix.sh <udid-chico> <udid-grande> <carpeta> <nombre> [banderas de demo…]
#   p. ej.: scripts/ios_capture_matrix.sh <SE> <17 Pro> /tmp/capturas para-ti -demo-tab 1
# Prende un simulador a la vez, instala la compilación de $APP (por omisión /tmp/dd-orbital/…/Orbital.app), captura y lo apaga.
SMALL=$1; BIG=$2; D=$3; n=$4; shift 4
APP=${APP:-/tmp/dd-orbital/Build/Products/Debug-iphonesimulator/Orbital.app}
HERE=${0:A:h}
for pair in "${SMALL}:chico" "${BIG}:grande"; do   # con llaves: en zsh «$SMALL:c» es un modificador
  U=${pair%%:*}; size=${pair#*:}
  xcrun simctl boot $U 2>/dev/null; xcrun simctl bootstatus $U -b >/dev/null 2>&1
  xcrun simctl install $U $APP
  for mode in light dark; do $HERE/ios_capture.sh $U $D "$n-$size-$mode" -demo-appearance $mode "$@"; done
  xcrun simctl shutdown $U
done
echo
