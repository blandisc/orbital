#!/bin/zsh
# Captura una pantalla del iPhone en el simulador, en modo demo (sin tocar la TV ni cuentas reales).
#   scripts/ios_capture.sh <udid> <carpeta> <nombre> [banderas de demo…]
#   p. ej.: scripts/ios_capture.sh C9AE… /tmp/capturas para-ti -demo-tab 1 -demo-appearance dark
# Necesita la app ya instalada en ese simulador (xcrun simctl install <udid> …/Orbital.app). Espera 8 s y guarda <nombre>.png.
U=$1; D=$2; n=$3; shift 3
mkdir -p $D
xcrun simctl terminate $U mx.iracheta.orbital >/dev/null 2>&1
xcrun simctl launch $U mx.iracheta.orbital -demo -demo-trakt -demo-tmdb -demo-console -demo-airings -demo-because -demo-mode lists "$@" >/dev/null
sleep 8
xcrun simctl io $U screenshot $D/$n.png >/dev/null 2>&1 && echo -n "$n "
