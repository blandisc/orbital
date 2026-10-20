# Flujos de Orbital con el mando

Auditoría de todo lo que una persona puede hacer, y si se puede hacer **solo con el mando**
(GameSir o los controles de la Legion Go) sin soltarlo ni toparse con una ventana que no responde.

✅ con el mando · ⚠️ con el mando, con una salvedad · ❌ necesita teclado, ratón o pantalla táctil

## Arrancar y navegar

| Flujo | Cómo | Estado |
|---|---|---|
| Encender la Legion Go y llegar a Orbital | Acceso directo de inicio (`pythonw -m orbital`) | ✅ |
| Moverse entre juegos y filas | D-pad / stick; LT/RT saltan de 5 en 5 | ✅ |
| Cambiar de sección (Para ti, Inicio, Juegos, Películas y series, TV en vivo, Apps) | LB / RB (en TV en vivo, primero pasan de categoría: ver más abajo) | ✅ |
| Buscar juegos, películas y series desde cualquier lugar | Vista (⧉) o la píldora "Buscar". Teclado grande: A escribe, X borra, Y espacio, **B vuelve**; Borrar todo (se vuelve Deshacer), Atrás, Dictar y Buscar. Con la caja vacía, tus búsquedas recientes. Resultados por grupo: En tu consola (juegos y apps), Películas, Series. Con un teclado físico se escribe directo | ✅ |
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
| Cerrar el juego | GameSir: mantener LB + RB + Select 1,5 s (barra encima del juego, cierre inmediato; antes Start + Select + Home, que chocaba con los combos del propio GameSir —Start + Select cambia de modo, Home + Start reinicia sus ajustes— y con la Vista de tareas que Windows abre al mantener Home desde 2026-10-18). Otros mandos: Start + Select + Home. Controles de la Legion Go: mantener Start + Select 1,5 s (no tienen Home ni cambio de modo) o Legion L dos veces seguidas. Ninguno choca con el cambio de modo del GameSir (Start+Select o Home sostenidos) | ✅ |
| Cerrar desde Orbital | ☰ → Cerrar… o Y → Cerrar (pide confirmación) | ✅ |
| El juego se cierra solo | Orbital vuelve al frente con el tiempo jugado | ✅ |
| Juego de Steam | A lo abre; el atajo de cerrar (GameSir: LB + RB + Select) lo cierra si está al frente | ⚠️ Steam puede mostrar sus propios avisos (sincronización en la nube, actualizaciones); se manejan con el mando en Steam, no en Orbital |

## Entrar y salir de un juego: todos los casos

Lo que Orbital hace en cada situación. La regla: **Orbital solo se pone al frente cuando el juego
de verdad terminó**, y nunca le quita el foco a otra cosa que estés usando.

| Situación | Qué pasa | Estado |
|---|---|---|
| Abres un juego de un emulador | Orbital se queda ENCIMA desde antes de abrir el emulador (nunca se asoma). Pantalla de carga: la portada en órbita sobre estrellas que avanzan. Cuando el juego está listo **y en pantalla completa** (espera hasta 4 s a que deje de cambiar de tamaño), salto a velocidad luz y Orbital se funde sobre el juego: sin brincos. B la salta | ✅ (nuevo) |
| Abres otra cosa con un juego abierto | Te pregunta "¿Cerrar X?": "Volver a X" (primero) o "Cerrar y abrir". Un video se cierra sin preguntar (su avance queda guardado) | ✅ (nuevo) |
| Dejas un video en pausa | A los 15 min se cierra solo; sigues donde te quedaste (`sessions.video_idle_minutes`) | ✅ (nuevo) |
| Dejas un juego congelado (saliste con Home) | A la hora se cierra solo y te avisa; lo no guardado se pierde (`sessions.game_idle_minutes`, 0 = nunca) | ✅ (nuevo) |
| Abres un juego y su ventana aparece detrás de Orbital (Windows lo hace a veces) | Orbital se la pasa al frente en cuanto existe, solo si Orbital sigue al frente | ✅ (nuevo) |
| El emulador se relanza a sí mismo al arrancar (xemu) | Orbital sigue al proceso nuevo; no sale encima del juego | ✅ (nuevo; antes salía a los 2 s) |
| Un lanzador abre el juego y se cierra (`launch-eden.cmd`, lanzadores propios) | Orbital sigue al juego, no al lanzador | ✅ (nuevo) |
| El juego se cierra normal (menú del juego, el atajo de cerrar, Legion L ×2, "cierra el juego") | Orbital al frente, con el tiempo jugado y la tarjeta enfocada | ✅ |
| El juego truena | Igual que cerrarse: Orbital al frente con "De vuelta de…" | ✅ |
| El juego se cierra solo a los pocos segundos | "X se cerró enseguida" como error (revisa ROM, firmware, claves), no "De vuelta de…" | ✅ (nuevo) |
| El emulador no está (lo moviste o desinstalaste) | Mensaje claro y, si hay otro emulador, "Abrir con …" en el mismo momento | ✅ (nuevo) |
| A sobre un juego que ya se cerró por su cuenta | "No encuentro la ventana de X" (antes A no hacía nada) | ✅ (nuevo) |
| Home en el juego | Orbital al frente; el emulador se congela (un video se pausa) | ✅ |
| Home otra vez, Legion L o A en "Continuar" | De vuelta al juego, descongelado | ✅ |
| Vuelves al juego por tu cuenta (Alt+Tab, toque) | Se descongela solo | ✅ |
| Orbital se cierra de golpe con un juego congelado | Al volver a abrir, lo descongela | ✅ |
| Cerrar un juego que siguió en otro proceso | Cierra ese proceso, no el lanzador que ya no existe | ✅ (nuevo) |
| Abres desde ES-DE o Steam (no desde Orbital) | Home lleva a Orbital y regresa; el atajo de cerrar lo cierra si está al frente | ✅ |
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
| Enviar al iPhone | Y en el reproductor (Más › iPhone), en la ficha (botón con el ícono del teléfono) o con Y sobre un video de Seguir viendo: «Enviar al iPhone» lo deja para abrir allá (tarjeta «Desde la TV» en Inicio). Solo aparece con un iPhone conectado; avisa «Enviado al iPhone: se abre cuando tengas Orbital a la mano» | ✅ (nuevo) |
| Descargar en el iPhone | Mismo lugar: «Descargar en el iPhone» baja el episodio en curso (o el que sigue) en el iPhone: «Se descargará en el iPhone en cuanto abras Orbital ahí (o en segundo plano si iOS lo permite)» | ✅ (nuevo) |
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

## TV en vivo

Los canales de México (lista pública de iptv-org), en el mismo mpv que las películas pero **sin película**: no
hay a dónde adelantar, no se guarda avance y no entra en «Seguir viendo». Ver `docs/tv-en-vivo.md` (cómo funciona
y qué se midió).

| Flujo | Cómo | Estado |
|---|---|---|
| Llegar a la sección | LB / RB hasta «TV en vivo» (entre Películas y series y Apps). Muestra los canales, con su logo y su número, por categorías | ✅ (nuevo) |
| Cambiar de categoría | **LB / RB** pasan de una categoría a otra (Todos · General · Noticias · Deportes…). En la primera o la última siguen a la sección de al lado, así nunca te quedas atrapado. Las categorías con menos de 3 canales se juntan en «Otros» | ✅ (nuevo) |
| Moverse por los canales | D-pad / stick; LT/RT saltan una pantalla (3 filas). La barra de arriba dice en qué canal vas («5 de 40»). ↑ desde la primera fila llega a las categorías | ✅ (nuevo) |
| Logos | Cada canal con su logo, **parejo**: Orbital lo baja una vez, lo recorta y, si es oscuro, lo pone sobre una placa clara para que se lea sobre el fondo oscuro; queda guardado (funciona sin Internet y la TV no le pide imágenes a internet). Sin logo, las letras del nombre | ✅ (nuevo) |
| Canales que fallaron una vez | Salen **al final** de su categoría, atenuados y con «Sin señal reciente»; el encabezado los cuenta («174 canales · 51 sin señal reciente»). Con un segundo fallo se ocultan | ✅ (nuevo) |
| Ver un canal | **A**. Pantalla de carga («Sintonizando») y, con la primera imagen, el canal a pantalla completa (~2 s). Si había un juego abierto, antes pregunta «¿Cerrar X?» | ✅ (nuevo) |
| Volver al canal que ya ves | Su casilla dice **«Al aire»**; **A** (o Home) vuelve a él, sin sintonizarlo otra vez. El pie lo dice («A Volver al canal», «Home Volver a …»). **A en otro canal** lo sintoniza en el mismo reproductor y trae su ventana: sin pantalla de carga ni cerrar nada | ✅ (nuevo) |
| Cambiar de canal viendo la tele | **↑ ↓ o LT/RT**: ↑ y RT, el siguiente; ↓ y LT, el anterior (la lista da la vuelta). La barra enseña a dónde vas al instante («Sintonizando…») y solo se sintoniza el último si pulsas varias veces. Los canales que ya fallaron una vez se saltan al cambiar (siguen en la guía, atenuados). Cambiar es `loadfile … replace` en el mismo mpv: no se cierra nada | ✅ (nuevo) |
| Elegir de una lista | **Y**: guía «Categoría \| Canales» encima del video (que sigue). ◀ ▶ cambian de columna, **LT/RT saltan una página**, A elige, B cierra. Los canales que fallaron dicen «Sin señal reciente». Elegir otra categoría también cambia la lista por la que saltan ↑ ↓ | ✅ (nuevo) |
| Volumen y silencio | ◀ ▶ volumen · **A** sin sonido (no pausa: una tele en vivo pausada vuelve atrasada). Una **píldora fija «Sin sonido»** arriba a la izquierda se queda mientras dure (la barra del canal se va sola). Home no deshace un silencio que pusiste tú | ✅ (nuevo) |
| Audio | X (si el canal trae más de una pista) | ✅ |
| Barra del canal | Número, nombre, estado (● En vivo · Sintonizando… · Sin señal), categoría, calidad y hora. Sale al sintonizar y al tocar un botón; se va sola | ✅ (nuevo) |
| Salir | **B (mantener)**, como en todo el reproductor. Orbital avisa «De vuelta de la TV en vivo» (no «Guardé dónde ibas») | ✅ |
| Home en un canal | Orbital al frente y el canal **sigue al aire sin sonido** (no se pausa). Home otra vez vuelve con sonido y la barra. Olvidado en Orbital más de 15 min (`sessions.video_idle_minutes`), se cierra solo | ✅ (nuevo) |
| Un canal no abre | Se marca y salta solo al siguiente de la lista («X no abre · pasando a Y»), hasta 3 seguidos. Si siguen sin abrir, se queda en «Sin señal» para que decidas (↑ ↓) | ✅ (nuevo) |
| Un canal se corta a media vista | mpv reconecta solo; si no puede, primero se reintenta el mismo canal una vez y luego se marca y se salta | ✅ (nuevo) |
| Canales que ya no sirven | Se revisan al arrancar y cada ~6 h (manifiesto, calidad y un trozo de video real). Un canal se oculta tras **dos** fallos seguidos y vuelve solo cuando abre otra vez. Los que nunca se han revisado se muestran; los que ya fallaron una vez, atenuados | ✅ (nuevo) |
| Sin Internet | Se usa la última lista guardada; ningún canal se oculta por una caída del Wi-Fi. Sin lista guardada, la sección lo dice («Aún no hay canales») | ✅ (nuevo) |
| Volver a buscar canales | **X**: baja la lista otra vez y revisa cuáles abren (avisa al terminar) | ✅ (nuevo) |
| Volver al Inicio | **B**: primero al primer canal; otra vez, a Inicio | ✅ |

## Con el dedo (Legion Go sin dock)

Todo funciona igual con toques o con el control; Orbital cambia solo según lo que uses.

| Flujo | Cómo | Estado |
|---|---|---|
| Recorrer una fila / cambiar de fila | Deslizar de lado / de arriba abajo (en TV en vivo: de lado cambia de categoría) | ✅ |
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
| Tu consola | La primera vez (y en ☰ → Ajustes → Mantenimiento → Tu consola): qué encontró Orbital (Steam, emuladores, ES-DE, Stremio, reproductor, Alexa) y cómo resolver lo que falta | ✅ (nuevo) |
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
