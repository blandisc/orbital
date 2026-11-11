#!/bin/zsh
# guardar-dsym.sh — guarda los símbolos (dSYM) de cada compilación que se instala, con su número (revisión del 11 nov 2026).
#
# Sin el dSYM de esa misma compilación, un cierre de la app que llega del iPhone (un .ips) solo dice direcciones: no se
# sabe en qué función pasó. Este script copia los dSYM de la compilación que acabas de instalar a una carpeta por número de
# compilación (CFBundleVersion), para poder leer después un cierre de esa versión.
#
# Uso:  ios/scripts/guardar-dsym.sh <carpeta de Products/Release-iphoneos> [carpeta destino]
#   Ejemplo (después de compilar e instalar):
#     ios/scripts/guardar-dsym.sh /tmp/dd-orbital/Build/Products/Release-iphoneos
#   Deja:  ~/Library/Developer/Orbital-dSYMs/<número>/Orbital.app.dSYM (y los de los widgets), más un uuids.txt.
#   Para leer un cierre:  xcrun atos -arch arm64 -o <número>/Orbital.app.dSYM/Contents/Resources/DWARF/Orbital -l <base> <dirección>
set -euo pipefail
PRODUCTS=${1:?falta la carpeta de Products (por ejemplo …/Build/Products/Release-iphoneos)}
DEST_ROOT=${2:-$HOME/Library/Developer/Orbital-dSYMs}
APP="$PRODUCTS/Orbital.app"
[[ -d "$APP" ]] || { echo "No encuentro $APP" >&2; exit 1; }
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Info.plist")
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Info.plist")
DEST="$DEST_ROOT/$BUILD"
mkdir -p "$DEST"
found=0
for dsym in "$PRODUCTS"/*.dSYM(N); do
  rsync -a --delete "$dsym" "$DEST/"
  found=$((found + 1))
done
(( found > 0 )) || { echo "No hay dSYM en $PRODUCTS (¿DEBUG_INFORMATION_FORMAT=dwarf-with-dsym?)" >&2; exit 1; }
: > "$DEST/uuids.txt"
for dsym in "$DEST"/*.dSYM(N); do xcrun dwarfdump --uuid "$dsym" >> "$DEST/uuids.txt"; done
echo "Orbital $VERSION ($BUILD): $found dSYM en $DEST"
