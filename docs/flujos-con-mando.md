# Flujos de Orbital con el mando

Auditoría de todo lo que una persona puede hacer, y si se puede hacer **solo con el mando**
(GameSir o los controles de la Legion Go) sin soltarlo ni toparse con una ventana que no responde.

✅ con el mando · ⚠️ con el mando, con una salvedad · ❌ necesita teclado, ratón o pantalla táctil

## Arrancar y navegar

| Flujo | Cómo | Estado |
|---|---|---|
| Encender la Legion Go y llegar a Orbital | Acceso directo de inicio (`pythonw -m orbital`) | ✅ |
| Moverse entre juegos y filas | D-pad / stick; LT/RT saltan de 5 en 5 | ✅ |
| Cambiar de sección (Inicio, Juegos, Películas y series, Apps) | LB / RB | ✅ |
| Buscar juegos, películas y series desde cualquier lugar | Vista (⧉) o la píldora "Buscar" de arriba; tus juegos salen primero, al instante | ✅ |
| Películas y series | Abre en "Seguir viendo"; los catálogos debajo; Buscar es el atajo | ✅ |
| Volver al inicio | B | ✅ |
| Cada fila recuerda su último juego | automático | ✅ |
| Llegar al final de una fila | la tarjeta rebota y el mando vibra | ✅ |
| Si la ventana de Orbital se cierra sola | se reabre (máx. 3 veces por minuto) | ✅ |

## Jugar

| Flujo | Cómo | Estado |
|---|---|---|
| Abrir un juego | A (la portada vuela a "Abriendo", el mando vibra) | ✅ |
| Abrir con el emulador alternativo (Ryujinx/Eden) | X | ✅ |
| Usar siempre otro emulador, favorito, ocultar | Y → menú lateral | ✅ |
| Ir a Orbital sin cerrar el juego | Home (solo, al soltarlo) o un toque de Legion L | ✅ |
| Volver al juego desde Orbital | Home, Legion L, o A sobre el juego ("Continuar") | ✅ |
| Cerrar el juego | GameSir: mantener Start + Select + Home 1,5 s (barra encima del juego, cierre inmediato). Controles de la Legion Go: Legion L dos veces seguidas. Ninguno choca con el cambio de modo del GameSir (Start+Select o Home sostenidos) | ✅ |
| Cerrar desde Orbital | ☰ → Cerrar… o Y → Cerrar (pide confirmación) | ✅ |
| El juego se cierra solo | Orbital vuelve al frente con el tiempo jugado | ✅ |
| Juego de Steam | A lo abre; Start + Select + Home lo cierra si está al frente | ⚠️ Steam puede mostrar sus propios avisos (sincronización en la nube, actualizaciones); se manejan con el mando en Steam, no en Orbital |

## Entrar y salir de un juego: todos los casos

Lo que Orbital hace en cada situación. La regla: **Orbital solo se pone al frente cuando el juego
de verdad terminó**, y nunca le quita el foco a otra cosa que estés usando.

| Situación | Qué pasa | Estado |
|---|---|---|
| Abres un juego de un emulador | Pantalla de carga de Orbital (portada y fondo del juego) ENCIMA del emulador hasta que el juego está listo (pantalla completa o su nombre en la ventana); se funde a negro y aparece el juego. Ya no se ven la lista de Eden ni sus ventanas. B la salta | ✅ (nuevo; verificado: Smash Bros. listo en 13 s) |
| Abres otra cosa con un juego abierto | Te pregunta "¿Cerrar X?": "Volver a X" (primero), "Cerrar y abrir" o "Abrir sin cerrar". Un video se cierra sin preguntar (su avance queda guardado) | ✅ (nuevo) |
| Dejas un video en pausa | A los 15 min se cierra solo; sigues donde te quedaste (`sessions.video_idle_minutes`) | ✅ (nuevo) |
| Dejas un juego congelado (saliste con Home) | A la hora se cierra solo y te avisa; lo no guardado se pierde (`sessions.game_idle_minutes`, 0 = nunca) | ✅ (nuevo) |
| Abres un juego y su ventana aparece detrás de Orbital (Windows lo hace a veces) | Orbital se la pasa al frente en cuanto existe, solo si Orbital sigue al frente | ✅ (nuevo) |
| El emulador se relanza a sí mismo al arrancar (xemu) | Orbital sigue al proceso nuevo; no sale encima del juego | ✅ (nuevo; antes salía a los 2 s) |
| Un lanzador abre el juego y se cierra (`launch-eden.cmd`, lanzadores propios) | Orbital sigue al juego, no al lanzador | ✅ (nuevo) |
| El juego se cierra normal (menú del juego, Start + Select + Home, Legion L ×2, "cierra el juego") | Orbital al frente, con el tiempo jugado y la tarjeta enfocada | ✅ |
| El juego truena | Igual que cerrarse: Orbital al frente con "De vuelta de…" | ✅ |
| Home en el juego | Orbital al frente; el emulador se congela (un video se pausa) | ✅ |
| Home otra vez, Legion L o A en "Continuar" | De vuelta al juego, descongelado | ✅ |
| Vuelves al juego por tu cuenta (Alt+Tab, toque) | Se descongela solo | ✅ |
| Orbital se cierra de golpe con un juego congelado | Al volver a abrir, lo descongela | ✅ |
| Cerrar un juego que siguió en otro proceso | Cierra ese proceso, no el lanzador que ya no existe | ✅ (nuevo) |
| Abres desde ES-DE o Steam (no desde Orbital) | Home lleva a Orbital y regresa; Start + Select + Home lo cierra si está al frente | ✅ |
| Un aviso de Windows o de Steam sale encima | Orbital no compite por el foco; Home sigue funcionando | ⚠️ el aviso se maneja con el mando en su app |

## Multimedia y apps

| Flujo | Cómo | Estado |
|---|---|---|
| Abrir Stremio / YouTube / ES-DE / Big Picture | A | ✅ |
| Ver una película o episodio | Elegir en Orbital → fuente recomendada (5 s o A) → reproductor de Orbital (mpv) a pantalla completa, desde donde te quedaste | ✅ |
| En el reproductor | Barra de Orbital encima del video con título, progreso, idioma de audio y subtítulos, y la leyenda de cada botón. A pausa · ←/→ ±10 s (mantener: continuo) · LB/RB ±1 min · ↑/↓ volumen · B salir | ✅ |
| Cambiar audio o subtítulos | X (audio) o Y (subtítulos) abren un menú con las pistas del video por idioma ("Inglés · 5.1 · E-AC3", "Español · Forzados", "Sin subtítulos", "Buscar subtítulos en…"); ↑/↓ y A eligen, B cierra | ✅ |
| Home en el reproductor | Pausa el video y va a Orbital; Home otra vez vuelve con la barra de progreso (A sigue) | ✅ |
| Seguir viendo | Al salir del reproductor, el avance se guarda en tu cuenta de Stremio (Orbital, Stremio y otros dispositivos); al terminar un episodio, queda el siguiente | ✅ |
| Navegar dentro de Stremio | depende de Stremio | ⚠️ Stremio no se maneja del todo con mando (con `player: stremio` se usa su reproductor) |
| Volver a Orbital desde una app | Home o un toque de Legion L | ✅ |
| Cambiar entre apps abiertas | ☰ → Ventanas abiertas | ✅ |

## Con el dedo (Legion Go sin dock)

Todo funciona igual con toques o con el control; Orbital cambia solo según lo que uses.

| Flujo | Cómo | Estado |
|---|---|---|
| Recorrer una fila / cambiar de fila | Deslizar de lado / de arriba abajo | ✅ |
| Ver un juego / abrirlo | Tocar la portada / tocarla otra vez | ✅ |
| Cambiar de sección, buscar, menú | Tocar las pestañas, la píldora "Buscar" o la marca "orbital" | ✅ |
| Volver (buscar, episodios, fuentes, menú) | Botón "Atrás" abajo a la izquierda (solo aparece al usar el dedo) | ✅ |
| Saltar la pantalla de carga | Tocarla | ✅ |
| En el reproductor | Tocar el video pausa o reanuda y muestra la barra; el doble toque ya no sale de pantalla completa | ✅ |
| Ir a Orbital desde un juego | Legion L (un toque) | ✅ |

## Sistema

| Flujo | Cómo | Estado |
|---|---|---|
| Actualizar biblioteca, sonidos, mostrar ocultos | ☰ | ✅ |
| Salir al escritorio y volver | ☰ → Salir al escritorio; Home para volver | ✅ |
| Suspender, reiniciar, apagar | ☰ → Apagado | ✅ |
| Vista de tareas de Windows | 3 dedos hacia arriba (panel o pantalla) | ⚠️ funciona con Orbital abierto, pero la Vista de tareas no se maneja con mando: mejor ☰ → Ventanas abiertas |

## Fuera del alcance de Orbital (configuración única)

| Situación | Qué hacer |
|---|---|
| Home abre la Xbox Game Bar | Configuración → Juegos → Xbox Game Bar → desactivar "Abrir Xbox Game Bar con este botón del mando" |
| Eden pedía "¿Seguro?" con Select + Start | Resuelto: se quitaron esos atajos de Eden (`qt-config.ini`, con respaldo) |
| A/B cruzados en el GameSir T4n Lite | M + A durante 2 s intercambia A↔B y X↔Y en el propio control |
| Avisos de Windows (UAC, actualizaciones) | No se manejan con mando; aparecen pocas veces |
| Primer arranque de un emulador (llaves, firmware) | Configurar una vez con teclado o pantalla táctil |
