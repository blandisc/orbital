#!/bin/zsh
# medir-clics-mac.sh — cuánto tarda la Orbital instalada en la Mac en responder a cada clic (23 nov 2026, Fernando: «primero
# quiero evidencia de que lo que hiciste efectivamente mejoró»). Mide la app de verdad (Release, tu cuenta, tu ventana), no la
# demostración ni una compilación Debug: Instruments (Time Profiler) se pega a la app abierta y graba mientras das clics.
#
# Uso:  ios/scripts/medir-clics-mac.sh <segundos> <carpeta de salida> [archivo de clics]
#   1. Abre Orbital y espera ~30 s a que termine de cargar Inicio.
#   2. Corre el script y da tus clics (uno cada ~4 s) mientras graba.
#   3. Opcional: anota la hora de cada clic justo después de darlo, un renglón «nombre segundos-epoch» (por ejemplo
#      `echo "explorar $(python3 -c 'import time;print(time.time())')" >> clics.txt`): así cada medida queda ligada a su clic.
#      Sin archivo, se separa por ráfagas de trabajo.
# Deja la grabación en <carpeta>/clics.trace (bórrala al terminar: trae las variables de entorno de la app) y escribe:
#   trabajo ms   — cuánto trabajó el hilo de la pantalla después del clic
#   quieta en ms — cuándo dejó de trabajar en serio (lo que tarda en verse terminada)
#   bloqueo ms   — el congelamiento más largo según Apple (>250 ms se siente, >500 ms es un «Hang»)
# Se mide antes y después de un cambio, con la misma secuencia y la app recién abierta las dos veces.
set -euo pipefail
SECS=${1:?segundos}; OUT=${2:?carpeta}; CLICKS=${3:-}
mkdir -p "$OUT"
pid=$(pgrep -f 'Wrapper/Orbital.app/Orbital' | head -1); [[ -n $pid ]] || { echo "Abre Orbital primero" >&2; exit 1; }
rm -rf "$OUT/clics.trace"
echo "Grabando ${SECS} s (Orbital $pid)…"
xcrun xctrace record --template 'Time Profiler' --attach "$pid" --time-limit "${SECS}s" --output "$OUT/clics.trace" >/dev/null
python3 "${0:A:h}/medir_clics.py" "$OUT/clics.trace" $CLICKS
