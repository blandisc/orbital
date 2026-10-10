# Flujos de Orbital con el mando

Auditoría de todo lo que una persona puede hacer, y si se puede hacer **solo con el mando**
(GameSir o los controles de la Legion Go) sin soltarlo ni toparse con una ventana que no responde.

✅ con el mando · ⚠️ con el mando, con una salvedad · ❌ necesita teclado, ratón o pantalla táctil

## Arrancar y navegar

| Flujo | Cómo | Estado |
|---|---|---|
| Encender la Legion Go y llegar a Orbital | Acceso directo de inicio (`pythonw -m orbital`) | ✅ |
| Moverse entre juegos y filas | D-pad / stick; LB/RB saltan de 5 en 5 | ✅ |
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
| Ir a Orbital sin cerrar el juego | Home (solo, al soltarlo) o Legion L | ✅ |
| Volver al juego desde Orbital | Home, Legion L, o A sobre el juego ("Continuar") | ✅ |
| Cerrar el juego | Mantener Select + Start 1,5 s: aviso encima del juego y cierre inmediato | ✅ |
| Cerrar desde Orbital | ☰ → Cerrar… o Y → Cerrar (pide confirmación) | ✅ |
| El juego se cierra solo | Orbital vuelve al frente con el tiempo jugado | ✅ |
| Juego de Steam | A lo abre; Select + Start lo cierra si está al frente | ⚠️ Steam puede mostrar sus propios avisos (sincronización en la nube, actualizaciones); se manejan con el mando en Steam, no en Orbital |

## Multimedia y apps

| Flujo | Cómo | Estado |
|---|---|---|
| Abrir Stremio / YouTube / ES-DE / Big Picture | A | ✅ |
| Ver una película o episodio | Elegir en Orbital → fuente recomendada (5 s o A) → reproductor de Orbital (mpv) a pantalla completa, desde donde te quedaste | ✅ |
| En el reproductor | A pausa · ←/→ ±10 s (mantener: continuo) · LB/RB ±1 min · ↑/↓ volumen · X audio · Y subtítulos · B salir | ✅ |
| Home en el reproductor | Pausa el video y va a Orbital; Home otra vez vuelve con la barra de progreso (A sigue) | ✅ |
| Seguir viendo | Al salir del reproductor, el avance se guarda en tu cuenta de Stremio (Orbital, Stremio y otros dispositivos); al terminar un episodio, queda el siguiente | ✅ |
| Navegar dentro de Stremio | depende de Stremio | ⚠️ Stremio no se maneja del todo con mando (con `player: stremio` se usa su reproductor) |
| Volver a Orbital desde una app | Home o Legion L | ✅ |
| Cambiar entre apps abiertas | ☰ → Ventanas abiertas | ✅ |

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
