#!/bin/zsh
# medir-repintado.sh — cuántas veces se vuelve a pintar (se evalúa el `body` de) Inicio, la ficha y el reproductor
# (V9, revisión del 10 nov 2026). Abre cada pantalla con la demostración y `-perf-bodies` (solo Debug), espera a que llegue
# todo y lee el resumen que deja la app (`tmp/orbital-bodies.txt` en su contenedor). Menos es mejor: cada vuelta de más es
# trabajo que el iPhone hace sin que cambie nada a la vista. Se corre antes y después de un cambio con el mismo simulador.
#
# Uso:  ios/scripts/medir-repintado.sh <udid del simulador> [Orbital.app] [vueltas] [segundos por pantalla]
#   Ejemplo:
#     ios/scripts/medir-repintado.sh <udid> /tmp/dd-orbital/Build/Products/Debug-iphonesimulator/Orbital.app 2 12
#   El simulador ya debe estar prendido (`xcrun simctl boot <udid>`) y es tuyo: este script no lo apaga ni lo borra.
#   Compilación Debug (en Release la bandera no existe). Deja los resúmenes en /tmp/orbital-repintado/ (bórralos al terminar).
set -euo pipefail
UDID=${1:?falta el udid del simulador}
APP=${2:-/tmp/dd-orbital/Build/Products/Debug-iphonesimulator/Orbital.app}
ROUNDS=${3:-2}
WAIT=${4:-12}
BUNDLE=mx.iracheta.orbital
OUT=/tmp/orbital-repintado
mkdir -p "$OUT"
[[ -d "$APP" ]] || { echo "No encuentro $APP" >&2; exit 1; }
xcrun simctl install "$UDID" "$APP"

# Cada escenario: nombre y argumentos de la demostración. `-demo-no-idle`: nada se mueve solo (el mosaico, la portada).
typeset -A scenes
scenes=(
  inicio            ""
  ficha-pelicula    "-demo-title movie:tt0816692"
  ficha-serie       "-demo-title series:tt0386676"
  reproductor       "-demo-title series:tt0386676 -demo-open play"
)
order=(inicio ficha-pelicula ficha-serie reproductor)

for scene in $order; do
  for round in $(seq 1 "$ROUNDS"); do
    xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
    data=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)
    rm -f "$data/tmp/orbital-bodies.txt"
    # shellcheck disable=SC2086
    xcrun simctl launch "$UDID" "$BUNDLE" -demo -demo-no-idle -perf-bodies ${=scenes[$scene]} >/dev/null
    sleep "$WAIT"
    summary="$OUT/$scene-$round.txt"
    if [[ -f "$data/tmp/orbital-bodies.txt" ]]; then cp "$data/tmp/orbital-bodies.txt" "$summary"; else : > "$summary"; fi
    echo "$scene (vuelta $round): $(tr '\n' ' ' < "$summary")"
  done
done
xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
echo "Resúmenes en $OUT"
