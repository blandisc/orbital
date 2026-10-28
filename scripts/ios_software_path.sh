#!/bin/zsh
# Prueba el reproductor del iPhone con MKV 4:3 como los de Los Simpson, por las dos rutas del motor (nativa y de software), en el
# simulador. Genera los videos con ffmpeg, los sirve desde la Mac y corre PlayerSoftwarePathUITests; deja las capturas en
# /tmp/orbital-software-path. Uso: scripts/ios_software_path.sh [udid-del-simulador]
set -euo pipefail
UDID=${1:-99C2A2FC-62AE-4D85-B17B-48C6B60410B9}   # «Orbital QA»
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=/tmp/orbital-43
SHOTS=/tmp/orbital-software-path
PORT=8765
mkdir -p "$WORK" "$SHOTS"

# Dos minutos de 640×480 (4:3) con tono: H.264 (ruta nativa) y MPEG-4 Parte 2 (siempre por la ruta de software).
[[ -f $WORK/s43-h264.mkv ]] || ffmpeg -loglevel error -y -f lavfi -i "testsrc2=size=640x480:rate=24" -f lavfi -i "sine=frequency=440" \
  -t 120 -c:v libx264 -pix_fmt yuv420p -c:a aac "$WORK/s43-h264.mkv"
[[ -f $WORK/s43-mpeg4.mkv ]] || ffmpeg -loglevel error -y -f lavfi -i "testsrc2=size=640x480:rate=24" -f lavfi -i "sine=frequency=440" \
  -t 120 -c:v mpeg4 -q:v 5 -c:a aac "$WORK/s43-mpeg4.mkv"

python3 -m http.server $PORT --bind 127.0.0.1 --directory "$WORK" >/dev/null 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null; xcrun simctl shutdown "$UDID" 2>/dev/null || true' EXIT
sleep 1

cd "$ROOT/ios/App"
xcodegen -q
for run in "h264:0" "mpeg4:1" "h264:1"; do
  file=${run%%:*}; software=${run##*:}
  echo "== s43-$file.mkv, ruta de software: $software"
  TEST_RUNNER_DEMO_VIDEO="http://127.0.0.1:$PORT/s43-$file.mkv" TEST_RUNNER_DEMO_SOFTWARE=$software TEST_RUNNER_SHOTS="$SHOTS/$file-$software" \
    xcodebuild test -project Orbital.xcodeproj -scheme Orbital -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath /tmp/orbital-dd -only-testing:OrbitalUITests/PlayerSoftwarePathUITests 2>&1 \
    | grep -E "error:|Test Case.*(passed|failed)" || true
done
echo "Capturas en $SHOTS"
