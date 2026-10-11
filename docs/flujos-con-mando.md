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
| Buscar juegos, películas y series desde cualquier lugar | Vista (⧉) o la píldora "Buscar". Teclado grande: A escribe, X borra, Y espacio, **B vuelve**; Borrar todo (se vuelve Deshacer), Atrás, Dictar y Buscar. Con la caja vacía, tus búsquedas recientes. Resultados por grupo: Tus juegos y apps, Películas, Series. Con un teclado físico se escribe directo | ✅ |
| Películas y series | Abre en "Seguir viendo" ("T8 E23 · quedan 10 min"; A pone el episodio en el que ibas, directo; Y → Ver la ficha o Quitar de Seguir viendo); los catálogos debajo abren la ficha | ✅ |
| Inicio | "Continuar": tus juegos y videos juntos, por fecha; lo que está abierto va primero con la píldora "Abierto" | ✅ (nuevo) |
| Volver al inicio | B | ✅ |
| Cada fila recuerda su último juego | automático | ✅ |
| Llegar al final de una fila | la tarjeta rebota y el mando vibra | ✅ |
| Mantener la cruceta o el stick | Repite y, tras un momento, acelera; el rebote y la vibración del final de la fila solo en la pulsación. El stick usa el eje dominante (nunca fila y columna a la vez) | ✅ |
| Menús dentro de menús (☰ → Apagado, Ajustes…) | B regresa un nivel; la ruta se ve arriba del menú (Orbital › Ajustes) | ✅ |
| Si la ventana de Orbital se cierra sola | se reabre (máx. 3 veces por minuto) | ✅ |

## Jugar

| Flujo | Cómo | Estado |
|---|---|---|
| Abrir un juego | A (la portada vuela a "Abriendo", el mando vibra) | ✅ |
| Abrir con el emulador alternativo (Ryujinx/Eden) | X | ✅ |
| Usar siempre otro emulador, favorito, ocultar | Y → menú lateral | ✅ |
| Ir a Orbital sin cerrar el juego | Home (solo, al soltarlo) o un toque de Legion L | ✅ |
| Volver al juego desde Orbital | Home, Legion L, o A sobre el juego ("Continuar") | ✅ |
| Juego olvidado en pausa | Aviso 10 min antes de cerrarlo solo | ✅ (nuevo) |
| Cerrar el juego | GameSir: mantener Start + Select + Home 1,5 s (barra encima del juego, cierre inmediato). Controles de la Legion Go: mantener Start + Select 1,5 s (no tienen Home ni cambio de modo) o Legion L dos veces seguidas. Ninguno choca con el cambio de modo del GameSir (Start+Select o Home sostenidos) | ✅ |
| Cerrar desde Orbital | ☰ → Cerrar… o Y → Cerrar (pide confirmación) | ✅ |
| El juego se cierra solo | Orbital vuelve al frente con el tiempo jugado | ✅ |
| Juego de Steam | A lo abre; Start + Select + Home lo cierra si está al frente | ⚠️ Steam puede mostrar sus propios avisos (sincronización en la nube, actualizaciones); se manejan con el mando en Steam, no en Orbital |

## Entrar y salir de un juego: todos los casos

Lo que Orbital hace en cada situación. La regla: **Orbital solo se pone al frente cuando el juego
de verdad terminó**, y nunca le quita el foco a otra cosa que estés usando.

| Situación | Qué pasa | Estado |
|---|---|---|
| Abres un juego de un emulador | Orbital se queda ENCIMA desde antes de abrir el emulador (nunca se asoma). Pantalla de carga: la portada en órbita sobre estrellas que avanzan. Cuando el juego está listo **y en pantalla completa** (espera hasta 4 s a que deje de cambiar de tamaño), salto a velocidad luz y Orbital se funde sobre el juego: sin brincos. B la salta | ✅ (nuevo) |
| Abres otra cosa con un juego abierto | Te pregunta "¿Cerrar X?": "Volver a X" (primero), "Cerrar y abrir" o "Abrir sin cerrar". Un video se cierra sin preguntar (su avance queda guardado) | ✅ (nuevo) |
| Dejas un video en pausa | A los 15 min se cierra solo; sigues donde te quedaste (`sessions.video_idle_minutes`) | ✅ (nuevo) |
| Dejas un juego congelado (saliste con Home) | A la hora se cierra solo y te avisa; lo no guardado se pierde (`sessions.game_idle_minutes`, 0 = nunca) | ✅ (nuevo) |
| Abres un juego y su ventana aparece detrás de Orbital (Windows lo hace a veces) | Orbital se la pasa al frente en cuanto existe, solo si Orbital sigue al frente | ✅ (nuevo) |
| El emulador se relanza a sí mismo al arrancar (xemu) | Orbital sigue al proceso nuevo; no sale encima del juego | ✅ (nuevo; antes salía a los 2 s) |
| Un lanzador abre el juego y se cierra (`launch-eden.cmd`, lanzadores propios) | Orbital sigue al juego, no al lanzador | ✅ (nuevo) |
| El juego se cierra normal (menú del juego, Start + Select + Home, Legion L ×2, "cierra el juego") | Orbital al frente, con el tiempo jugado y la tarjeta enfocada | ✅ |
| El juego truena | Igual que cerrarse: Orbital al frente con "De vuelta de…" | ✅ |
| El juego se cierra solo a los pocos segundos | "X se cerró enseguida" como error (revisa ROM, firmware, claves), no "De vuelta de…" | ✅ (nuevo) |
| El emulador no está (lo moviste o desinstalaste) | Mensaje claro y, si hay otro emulador, "Abrir con …" en el mismo momento | ✅ (nuevo) |
| A sobre un juego que ya se cerró por su cuenta | "No encuentro la ventana de X" (antes A no hacía nada) | ✅ (nuevo) |
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
| Ver una película o episodio | La ficha: "Continuar T3 E5 · quedan 22 min" o "Ver" con el foco, "Desde el principio", reparto y dirección; en series, los episodios abren en el que ibas (vistos con ✓, a medias con su barra, por estrenar con su fecha). A arranca directo con la fuente recomendada (pantalla de carga con fases: Buscando dónde verlo → Conectando · 1080p · Al instante) | ✅ |
| Qué hay disponible | La ficha busca las fuentes al abrirse y lo dice antes de elegir: "4K · Dolby Vision · Atmos · Inglés, Español · Al instante" (y Ver arranca casi al instante) | ✅ (nuevo) |
| Episodios vistos | Los ✓ salen de tu cuenta de Stremio; terminar un episodio en Orbital lo marca también allá | ✅ (nuevo) |
| Cambiar de temporada | En la ficha: LB/RB (desde los botones baja a los episodios para que se vea el cambio); LT/RT saltan de 5 en 5 en series largas | ✅ (nuevo) |
| Mi lista y tráiler | En la ficha, o desde la tarjeta con Y → Añadir/Quitar de Mi lista: ★ añade o quita de Mi lista (tu biblioteca de Stremio, fila propia en Películas y series); el tráiler se abre en YouTube para TV (Home vuelve). Los botones secundarios son ícono hasta que los enfocas | ✅ (nuevo) |
| Al terminar un video | "Terminaste Interstellar" (si lo viste casi completo); si no, "Guardé dónde ibas en…" | ✅ (nuevo) |
| Elegir la fuente a mano | Y en la ficha: panel lateral con cada fuente en palabras de persona (Al instante / Tarda en empezar, idioma, HDR, sonido); A ve con esa, B vuelve a la ficha | ✅ |
| Una fuente no arranca o se corta | Prueba sola la siguiente en el mismo punto ("Esa fuente falló · probando otra"); si ninguna sirve, lo dice y vuelve a Orbital | ✅ (nuevo) |
| En el reproductor | Barra de Orbital con título, progreso (con marcas de capítulos), audio, subtítulos, la fuente y la leyenda. A pausa · ←/→ adelantar (mantener: 10 s → 30 s → 1 min) · LB/RB capítulo (o ±1 min) · LT/RT episodio anterior/siguiente · ↑/↓ volumen · **B oculta la barra; con la barra oculta, sale** | ✅ |
| Cambiar audio, subtítulos o fuente | X o Y abren un menú con pestañas Audio / Subtítulos / Fuente (LB/RB cambian de pestaña); en Subtítulos también el tamaño. ↑/↓ y A eligen, B cierra. Cambiar de fuente sigue en el mismo punto | ✅ |
| Home en el reproductor | Pausa el video y va a Orbital; Home otra vez vuelve con la barra de progreso (A sigue) | ✅ |
| Saltar intro / resumen | Si el archivo marca la intro con capítulos, aparece "Saltar intro" unos segundos: A salta, B sigue viendo | ✅ (nuevo) |
| Al terminar un episodio | Tarjeta "Siguiente episodio en 8" en los créditos (A ya, B me quedo); el siguiente se carga en el mismo reproductor. Tras 3 seguidos sin tocar el mando: "¿Sigues viendo?" | ✅ (nuevo) |
| Seguir viendo | El avance se guarda en tu cuenta de Stremio cada minuto, al pausar y al salir (Orbital, Stremio y otros dispositivos); al terminar un episodio, queda el siguiente | ✅ |
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
| Volver (buscar, ficha, fuentes, menú) | Botón "Atrás" abajo a la izquierda (solo aparece al usar el dedo) | ✅ |
| Saltar la pantalla de carga | Tocarla | ✅ |
| En el reproductor | Tocar el video pausa o reanuda y muestra la barra; el doble toque ya no sale de pantalla completa | ✅ |
| Ir a Orbital desde un juego | Legion L (un toque) | ✅ |

## Sistema

| Flujo | Cómo | Estado |
|---|---|---|
| Actualizar biblioteca, sonidos, mostrar ocultos | ☰ | ✅ |
| Salir al escritorio y volver | ☰ → Salir al escritorio; Home para volver | ✅ |
| Suspender, reiniciar, apagar | ☰ → Apagado. Reiniciar y Apagar piden confirmar (Cancelar primero) y avisan si hay un juego abierto | ✅ |
| Tu consola | La primera vez (y en ☰ → Ajustes → Revisar mi consola): qué encontró Orbital (Steam, emuladores, ES-DE, Stremio, reproductor, Alexa) y cómo resolver lo que falta | ✅ (nuevo) |
| Conectar Stremio | ☰ → Ajustes → Cuentas → Stremio: correo y contraseña con el teclado en pantalla (Y muestra la contraseña, LT/RT cambian de campo). Ya no hace falta la PC | ✅ (nuevo) |
| Ajustes | ☰ → Ajustes: Reproducción (idioma del audio, subtítulos, calidad, tamaño de subtítulos), Pantalla (tamaño del texto, márgenes de la TV, reducir movimiento), Sonido y vibración, Cuentas. A o ◀/▶ cambian el valor sin cerrar el menú | ✅ (nuevo) |
| Encender Orbital | Animación de arranque (planeta y órbitas) mientras se prepara la biblioteca; al volver de un juego, la interfaz "aterriza" | ✅ (nuevo) |
| Vista de tareas de Windows | 3 dedos hacia arriba (panel o pantalla) | ⚠️ funciona con Orbital abierto, pero la Vista de tareas no se maneja con mando: mejor ☰ → Ventanas abiertas |

## Fuera del alcance de Orbital (configuración única)

| Situación | Qué hacer |
|---|---|
| Home abre la Xbox Game Bar | Configuración → Juegos → Xbox Game Bar → desactivar "Abrir Xbox Game Bar con este botón del mando" |
| Eden pedía "¿Seguro?" con Select + Start | Resuelto: se quitaron esos atajos de Eden (`qt-config.ini`, con respaldo) |
| A/B cruzados en el GameSir T4n Lite | M + A durante 2 s intercambia A↔B y X↔Y en el propio control |
| Avisos de Windows (UAC, actualizaciones) | No se manejan con mando; aparecen pocas veces |
| Primer arranque de un emulador (llaves, firmware) | Configurar una vez con teclado o pantalla táctil |
