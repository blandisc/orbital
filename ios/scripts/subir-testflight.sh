#!/bin/bash
# subir-testflight.sh — compila Orbital en Release para la tienda y la sube a App Store Connect (TestFlight) con el equipo
# personal de Fernando (18 nov 2026, cuenta de paga). Cada subida lleva su número (`git rev-list --count HEAD`) y sube
# también sus símbolos. Apple la procesa en 10 a 30 min; luego aparece en TestFlight y le llega al grupo interno.
#
# Uso:  ios/scripts/subir-testflight.sh [edición: ultra|plus|orbital]
#   Por ahora solo Ultra tiene app en App Store Connect («Orbital», mx.iracheta.orbital). Plus y Orbital usan el mismo
#   identificador: para darlas a otros hay que separarlas antes (otro PRODUCT_BUNDLE_IDENTIFIER y otra app).
#   Necesita: Xcode con la cuenta del equipo B7KRCF776Z (nunca el de Arca), XcodeGen y ios/App/Secrets.xcconfig.
#   Respeta el tope de 2 compilaciones en la Mac. Cada versión de TestFlight vence a los 90 días: súbela antes.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
EDITION=${1:-ultra}
TEAM=B7KRCF776Z
DERIVED=/tmp/dd-orbital-release
WORK=$(mktemp -d /tmp/orbital-testflight.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

case "$EDITION" in ultra|plus|orbital) ;; *) echo "Edición desconocida: $EDITION (ultra, plus u orbital)" >&2; exit 1 ;; esac
[[ -f "$REPO/ios/App/Secrets.xcconfig" ]] || { echo "Falta ios/App/Secrets.xcconfig (cópialo de Secrets.example.xcconfig)" >&2; exit 1; }
while (( $( (pgrep -x xcodebuild || true) | wc -l) >= 2 )); do echo "Ya hay 2 compilaciones en la Mac; espero…"; sleep 20; done

BUILD=$(git -C "$REPO" rev-list --count HEAD)
echo "Compilando Orbital ($EDITION) número $BUILD para TestFlight…"
cd "$REPO/ios/App"
xcodegen >/dev/null
if ! xcodebuild archive -project Orbital.xcodeproj -scheme Orbital -configuration Release -destination generic/platform=iOS \
     -archivePath "$WORK/Orbital.xcarchive" -derivedDataPath "$DERIVED" -allowProvisioningUpdates \
     CURRENT_PROJECT_VERSION="$BUILD" ORBITAL_EDITION="$EDITION" > "$WORK/archive.log" 2>&1; then
  grep -E "error:|ARCHIVE FAILED" "$WORK/archive.log" | sort -u | head -n 40
  echo "No compiló." >&2; exit 1
fi

cat > "$WORK/export.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>app-store-connect</string>
<key>destination</key><string>upload</string>
<key>teamID</key><string>$TEAM</string>
<key>signingStyle</key><string>automatic</string>
<key>manageAppVersionAndBuildNumber</key><false/>
<key>uploadSymbols</key><true/>
</dict></plist>
EOF
if ! xcodebuild -exportArchive -archivePath "$WORK/Orbital.xcarchive" -exportOptionsPlist "$WORK/export.plist" \
     -exportPath "$WORK/export" -allowProvisioningUpdates > "$WORK/upload.log" 2>&1; then
  grep -iE "error" "$WORK/upload.log" | sort -u | head -n 40
  echo "No se subió." >&2; exit 1
fi
echo "Subida Orbital ($EDITION), compilación $BUILD. En 10 a 30 min aparece en TestFlight."
