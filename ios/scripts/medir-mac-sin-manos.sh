#!/bin/zsh
# medir-mac-sin-manos.sh — arranque en frío, pestañas y fichas de la Orbital instalada en la Mac, sin clics (24 nov 2026).
# Los clics por accesibilidad suman su propio trabajo y no siempre hay permiso: aquí la app misma sigue unas órdenes y deja una
# marca antes de cada una (`MacDrive`, en `Support/Perf.swift`), e Instruments graba.
#
# Antes: compila Release con las órdenes (solo para medir; la app normal no las trae) e instálala:
#   xcodebuild build … -configuration Release 'OTHER_SWIFT_FLAGS=$(inherited) -DMAC_DRIVE'
#   ios/scripts/instalar-en-mac.sh <ruta a Orbital.app>
# Uso:  ios/scripts/medir-mac-sin-manos.sh <carpeta de salida> [órdenes]   (por omisión ios/scripts/mac-sin-manos.txt)
#       ORBITAL_ARGS='-macStillGlass YES' …: banderas de más para la app (pruebas de una sola cosa).
# Escribe el arranque (cuándo quedó quieta, trabajo del hilo de la pantalla en los primeros 5 s y el congelamiento más largo)
# y, por orden, trabajo / quieta en / bloqueo, como medir-clics-mac.sh. Mide con la Mac tranquila (carga < 6) y con al menos
# tres rondas antes y después. Al terminar, reinstala la compilación normal y borra la carpeta: las grabaciones traen las
# variables de entorno de la app.
set -euo pipefail
# Solo la Orbital de la Mac (en /Applications, dentro de «Wrapper»): la de un simulador también se llama Orbital y es de otra sesión.
mac='Wrapper/Orbital.app/Orbital'
OUT=${1:?carpeta}; ORDERS=${2:-${0:A:h}/mac-sin-manos.txt}
here=${0:A:h}; mkdir -p "$OUT"; rm -rf "$OUT/arranque.trace" "$OUT/ordenes.trace"
script=$(grep -v '^\s*$' "$ORDERS" | paste -sd'|' -)
secs=$(python3 -c "import sys;print(int(sum(float(l.split()[1]) for l in open(sys.argv[1]) if l.startswith('wait'))+10))" "$ORDERS")
pkill -f "$mac" 2>/dev/null || true; sleep 3
xcrun xctrace record --template 'Time Profiler' --all-processes --time-limit 14s --output "$OUT/arranque.trace" >/dev/null 2>&1 &
sleep 3
t0=$(python3 -c 'import time;print(time.time())')
open /Applications/Orbital.app --args -macDrive "$script" ${=ORBITAL_ARGS:-}
wait
pid=$(pgrep -f "$mac" | head -1)
# A veces Instruments no suelta la app al acabar el tiempo (24 nov: 27 min colgado): se le da un minuto de más y se corta.
xcrun xctrace record --template 'Time Profiler' --attach "$pid" --time-limit "${secs}s" --output "$OUT/ordenes.trace" >/dev/null 2>&1 &
rec=$!
for _ in {1..$((secs + 60))}; do kill -0 $rec 2>/dev/null || break; sleep 1; done
if kill -0 $rec 2>/dev/null; then kill -INT $rec; sleep 5; kill $rec 2>/dev/null || true; echo "Instruments no terminó a tiempo: repite la ronda" >&2; fi
wait $rec 2>/dev/null || true
/usr/bin/log show --style ndjson --start "$(date -r ${t0%.*} '+%Y-%m-%d %H:%M:%S')" \
  --predicate 'subsystem == "mx.iracheta.orbital" AND category == "drive"' 2>/dev/null > "$OUT/marcas.ndjson"
python3 "$here/medir_mac_sin_manos.py" "$OUT" "$t0" "$pid"
