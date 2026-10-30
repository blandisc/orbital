#!/bin/zsh
# Regresión de los flujos nuevos del iPhone (Inicio, Para ti, mazo, filtro, Lo que ves, Colecciones, cielo) en un simulador.
#   scripts/ios_regression.sh <udid> <bitácora.log>
# DD=<carpeta de compilación> si usas otra (una copia aparte del proyecto usa la suya); por omisión /tmp/dd-orbital.
# xcodebuild se queda colgado juntando diagnósticos al terminar: en cuanto salen los resultados se detiene ese proceso.
U=$1; L=$2
cd ${0:A:h}/../ios/App
xcodebuild test -project Orbital.xcodeproj -scheme Orbital -destination "id=$U" -derivedDataPath ${DD:-/tmp/dd-orbital} -jobs 4 \
  -only-testing:OrbitalUITests/NewFlowsRegressionUITests -only-testing:OrbitalUITests/HomeNewUITests \
  -only-testing:OrbitalUITests/ParaTiBUITests -only-testing:OrbitalUITests/SkyUITests > $L 2>&1 &
until grep -qE "Test Suite 'Selected tests' (passed|failed)|BUILD FAILED|TEST FAILED" $L; do sleep 5; done
sleep 2; pkill -f "xcodebuild test -project Orbital.xcodeproj -scheme Orbital -destination id=$U"
echo "pasan: $(grep -cE 'Test Case.*passed' $L) · fallan: $(grep -cE 'Test Case.*failed' $L)"
grep -E "Test Case.*failed|error:" $L | sed 's|.*UITests/||;s|OrbitalUITests\.||' | cut -c1-220
