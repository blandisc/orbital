#!/bin/zsh
# bordes.sh — la pasada de «bordes» del iPhone (I12, revisión del 10 nov 2026).
#
# Toma las mismas pantallas en las tres condiciones donde la interfaz se rompe primero:
#   normal  · el iPhone grande, tamaño de letra normal, modo oscuro
#   se      · el iPhone SE (pantalla chica), letra normal, oscuro
#   se-xl   · el iPhone SE con letra de accesibilidad grande y modo claro
# y deja las capturas en una carpeta para revisarlas a ojo: nada cortado, nada encimado, nada pegado a la orilla.
#
# Uso:  ios/scripts/bordes.sh <udid-grande> <udid-se> [carpeta]
#   La app ya debe estar instalada en los dos simuladores (compilada en modo demo). Al terminar, el SE vuelve a letra
#   normal (large) y oscuro, y los dos simuladores se apagan (solo esos dos, nunca «shutdown all»).
#   Ejemplo:  ios/scripts/bordes.sh 99C2A2FC-62AE-4D85-B17B-48C6B60410B9 CB9A4A0B-EA46-43E8-B1E9-C1E9B2A5BE3E
set -u
BIG=${1:?falta el udid del iPhone grande}
SE=${2:?falta el udid del iPhone SE}
OUT=${3:-/tmp/orbital-bordes}
APP=mx.iracheta.orbital
WAIT=${BORDES_WAIT:-6}
mkdir -p "$OUT"

# nombre | banderas de demo
SCREENS=(
  "inicio|-demo-tab 0"
  "explorar|-demo-tab 1"
  "buscar|-demo-tab 2 -demo-search dune"
  "biblioteca|-demo-tab 3 -demo-trakt"
  "descargas|-demo-tab 3 -demo-library downloads"
  "historial|-demo-open history -demo-trakt"
  "ajustes|-demo-open settings"
  "ficha|-demo-title movie:tt1160419 -demo-trakt"
  "version|-demo-title movie:tt1160419 -demo-open sources"
  "guardar|-demo-title movie:tt1160419 -demo-open save"
)

shoot() {   # shoot <udid> <condición>
  local u=$1 cond=$2
  for entry in "${SCREENS[@]}"; do
    local name=${entry%%|*} flags=${entry#*|}
    xcrun simctl terminate "$u" "$APP" >/dev/null 2>&1
    xcrun simctl launch "$u" "$APP" -demo -demo-no-idle ${=flags} >/dev/null || { echo "no abrió: $name"; continue; }
    sleep "$WAIT"
    xcrun simctl io "$u" screenshot "$OUT/$cond-$name.png" >/dev/null 2>&1 && echo "$OUT/$cond-$name.png"
  done
  xcrun simctl terminate "$u" "$APP" >/dev/null 2>&1
}

condition() {   # condition <udid> <condición> <tamaño> <apariencia>
  xcrun simctl boot "$1" >/dev/null 2>&1; xcrun simctl bootstatus "$1" >/dev/null
  xcrun simctl ui "$1" content_size "$3"
  xcrun simctl ui "$1" appearance "$4"
  shoot "$1" "$2"
}

# Uno a la vez: cada simulador se apaga antes de prender el siguiente.
condition "$BIG" normal large dark
xcrun simctl shutdown "$BIG"
condition "$SE" se large dark
condition "$SE" se-xl accessibility-large light
xcrun simctl ui "$SE" content_size large
xcrun simctl ui "$SE" appearance dark
xcrun simctl shutdown "$SE"
echo "Listo: $OUT ($(ls "$OUT" | wc -l | tr -d ' ') capturas)"
