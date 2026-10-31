# Reglas comunes para los agentes que arreglan (31 oct 2026)

Repo: /Users/fer.iracheta/code/orbital (app iOS en ios/; proyecto ios/App/Orbital.xcodeproj generado con xcodegen desde ios/App/project.yml; paquete ios/OrbitalCore). Hallazgos: docs/producto/auditoria-ios-2026-10-31/hallazgos.md. Lee primero: /Users/fer.iracheta/code/orbital/CLAUDE.md, ios/README.md, docs/ios-proyeccion.md, y la memoria en /Users/fer.iracheta/.claude/projects/-Users-fer-iracheta-code-orbital/memory/MEMORY.md (abre solo las notas que te sirvan: shared-worktree-sessions, xcodebuild-test-cuelga, ios-gesture-testing, simulador-trampas-imagenes, swiftui-render-storm-focused-value, encabezados-dos-niveles, iconos-no-pills, estandarizar-sin-que-lo-pida, no-browsing-onedrive).

## Alcance (Fernando, 31 oct)
- TODO es SOLO para la app iOS (ios/). Lo único fuera de ios/ que se vale es lo estrictamente necesario para que la CI de GitHub pase. No toques orbital/, tests/web/, design/tokens.json, design/vocabulario.json, alexa/ ni docs de la TV: otra sesión trabaja ahí la paridad TV↔iPhone. Si una prueba de iOS exige cambiar algo compartido, ajusta el lado iOS o la prueba (con motivo), no la TV.

## Trabajo en el mismo checkout
- Otro agente trabaja al mismo tiempo en el mismo árbol. SOLO edita los archivos de tu carril (te los dicen en tu encargo). Si necesitas tocar uno de otro carril, no lo hagas: anótalo en tu informe como pendiente.
- Commitea en `main` con rutas explícitas (`git add <rutas>`; nunca `git add -A` ni `.`), en commits chicos por tema. Antes de commitear: `git pull --rebase origin main` (si hay conflicto, no improvises: detente y repórtalo). Luego `git push origin main` (reintenta con espera si falla por red).
- Mensajes de commit en español claro, al estilo de `git log` (qué cambia para quien usa la app y por qué, y qué prueba lo cubre). Termina cada mensaje con la línea:
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  No pongas nombres de modelo en ningún otro lado.

## Compilar y probar
- Máximo 2 `xcodebuild` a la vez en la Mac, sumando todas las sesiones (hay una de Cénit). Antes de cada xcodebuild: `pgrep -f "Xcode.app/Contents/Developer/usr/bin/xcodebuild" | wc -l`; si hay 2 o más, espera sondeando cada 30 s (en un bucle de bash con `until`, no `sleep` suelto). Siempre `-derivedDataPath /tmp/dd-orbital`. Si otra compilación usa esa carpeta, espera tu turno.
- Pruebas del paquete: `cd ios/OrbitalCore && swift test` (o `--filter`). Si no compila por archivos a medias del otro carril, sigue la nota shared-worktree-sessions (copia a /tmp/orbital-t-<tu-carril>).
- Pruebas de interfaz: solo las de tu cambio, no la suite completa en cada intento. `xcodebuild test` se puede colgar al final: córrelo en segundo plano, espera «Test Suite 'Selected tests' passed|failed» en la bitácora y mata SOLO tu proceso.
- Antes de commitear algo que use `Demo.`/`DemoHTTPClient`, compila también `-configuration Release`.
- Simuladores (skill ~/code/interoperabilidad/skills/simuladores/SKILL.md): el carril que lo necesite usa el que le asignen; uno a la vez; apágalo al terminar con `xcrun simctl shutdown <udid>` (NUNCA `shutdown all`); no toques «Cénit iPhone 17 Pro» ni el simulador del otro carril. No instales nada en el iPhone real. Solo datos de demo (`-demo …`), nunca el OneDrive del usuario.
- Pruebas que deben quedar verdes al terminar tu carril: `swift test` completo de OrbitalCore (incluye DesignTests, DesignBoundaryTests, FileBudgetTests, PlatformBoundaryTests) y la compilación de la app en Debug y Release.

## Calidad
- Arregla la causa, no el síntoma. Cada arreglo de lógica lleva una prueba que fallaba antes y pasa después cuando sea razonable.
- Respeta el sistema de diseño (docs/ios-proyeccion.md, Design/Tokens*.swift, DesignTests): nada de números sueltos; íconos en vez de cápsulas de texto; controles nativos de Apple.
- No partas archivos solo para pasar el tope de 600 líneas: divide por responsabilidad.
- Lo que quien usa la app ve debe seguir igual salvo que el arreglo sea justo cambiarlo.
- Evidencia (regla del dueño): para cada arreglo que se VE (pantalla, cuelgue), guarda captura de antes y de después en `/tmp/orbital-evidencia/<carril>/` (fuera del repo) con nombres `NN-tema-antes.png` / `NN-tema-despues.png`. Si juntarla toma más de ~2 minutos, sáltala y dilo.
- Lo temporal tuyo va en /tmp y lo borras al terminar. Al final no debe quedar ningún xcodebuild ni simulador tuyo encendido.

## Informe final (en español claro)
Por cada hallazgo de tu carril: hecho / hecho distinto (por qué) / no hecho (por qué), con commit. Pruebas corridas y su resultado con la salida resumida. Pendientes que tocan otros carriles. Rutas de las capturas.
