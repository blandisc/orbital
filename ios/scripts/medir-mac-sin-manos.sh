#!/bin/zsh
# medir-mac-sin-manos.sh — arranque en frío, pestañas y fichas de la Orbital instalada en la Mac, sin clics (24 nov 2026).
# Los clics por accesibilidad suman su propio trabajo y no siempre hay permiso: aquí la app misma sigue unas órdenes y deja una
# marca antes de cada una (`MacDrive`, en `Support/Perf.swift`), e Instruments graba.
#
# Antes: compila Release con las órdenes (solo para medir; la app normal no las trae) e instálala:
#   xcodebuild build … -configuration Release 'OTHER_SWIFT_FLAGS=$(inherited) -DMAC_DRIVE'
#   ios/scripts/instalar-en-mac.sh <ruta a Orbital.app>
# Uso:  ios/scripts/medir-mac-sin-manos.sh <carpeta de salida> [órdenes]   (por omisión ios/scripts/mac-sin-manos.txt)
# Escribe el arranque (cuándo quedó quieta, trabajo del hilo de la pantalla en los primeros 5 s y el congelamiento más largo)
# y, por orden, trabajo / quieta en / bloqueo, como medir-clics-mac.sh. Mide con la Mac tranquila (carga < 6) y con al menos
# tres rondas antes y después. Al terminar, reinstala la compilación normal y borra la carpeta: las grabaciones traen las
# variables de entorno de la app.
set -euo pipefail
OUT=${1:?carpeta}; ORDERS=${2:-${0:A:h}/mac-sin-manos.txt}
here=${0:A:h}; mkdir -p "$OUT"; rm -rf "$OUT/arranque.trace" "$OUT/ordenes.trace"
script=$(grep -v '^\s*$' "$ORDERS" | paste -sd'|' -)
secs=$(python3 -c "import sys;print(int(sum(float(l.split()[1]) for l in open(sys.argv[1]) if l.startswith('wait'))+10))" "$ORDERS")
pkill -x Orbital 2>/dev/null || true; sleep 3
xcrun xctrace record --template 'Time Profiler' --all-processes --time-limit 14s --output "$OUT/arranque.trace" >/dev/null 2>&1 &
sleep 3
t0=$(python3 -c 'import time;print(time.time())')
open /Applications/Orbital.app --args -macDrive "$script"
wait
xcrun xctrace record --template 'Time Profiler' --attach "$(pgrep -x Orbital)" --time-limit "${secs}s" --output "$OUT/ordenes.trace" >/dev/null 2>&1
/usr/bin/log show --style ndjson --start "$(date -r ${t0%.*} '+%Y-%m-%d %H:%M:%S')" \
  --predicate 'subsystem == "mx.iracheta.orbital" AND category == "drive"' 2>/dev/null > "$OUT/marcas.ndjson"
python3 "$here/medir_mac_sin_manos.py" "$OUT" "$t0"
