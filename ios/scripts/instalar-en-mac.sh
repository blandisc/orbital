#!/bin/zsh
# Instala Orbital en /Applications de la Mac (chip de Apple, «Diseñada para iPad») para abrirla desde
# Launchpad, Spotlight o el Dock sin Xcode. Toma la compilación de aparato más reciente (Release-iphoneos)
# o la que le pases; el perfil de desarrollo ya incluye esta Mac.
#   ios/scripts/instalar-en-mac.sh [ruta/a/Orbital.app]
set -euo pipefail
src=${1:-/tmp/dd-orbital-release/Build/Products/Release-iphoneos/Orbital.app}
dest=/Applications/Orbital.app
[[ -d $src ]] || { echo "No encuentro $src: compila antes Release para iPhone o la Mac." >&2; exit 1; }
pkill -f 'Wrapper/Orbital.app/Orbital' 2>/dev/null || true   # solo la de la Mac: la de un simulador también se llama Orbital
rm -rf "$dest"
mkdir -p "$dest/Wrapper"
ditto "$src" "$dest/Wrapper/Orbital.app"
ln -s Wrapper/Orbital.app "$dest/WrappedBundle"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$dest"
echo "Orbital $(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$dest/Wrapper/Orbital.app/Info.plist") instalada en $dest"
open "$dest"
