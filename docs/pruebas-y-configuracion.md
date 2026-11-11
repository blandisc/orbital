# Pruebas y configuración pendientes

## Configurar una vez

| # | Qué | Cómo |
|---|---|---|
| 1 | Home no abra la Xbox Game Bar | Configuración → Juegos → Xbox Game Bar → desactivar "Abrir Xbox Game Bar con este botón del mando" |
| 2 | Cuenta de Stremio (Seguir viendo, biblioteca) | `C:\Users\ferna\orbital\.venv\Scripts\python -m orbital stremio login` |
| 2b | Subtítulos en inglés por defecto | Ya vienen así en el reproductor de Orbital (`stremio.subtitles: en`). Solo si usas `player: stremio`: en Stremio, Configuración → Reproductor → idioma de subtítulos = English |
| 2c | Reproductor de Orbital (mpv) | Ya instalado en `%LOCALAPPDATA%\orbital\mpv` (compilación de shinchiro, sin firma digital). Para volver al de Stremio: `player: stremio` en config.yaml |
| 3 | Permiso de micrófono para dictar | La primera vez que uses "Dictar" en Buscar, acepta el permiso del micrófono |
| 4 | Alexa | Instalar Tailscale → `tailscale funnel --bg 8711` → `orbital alexa setup` → skill alojada por Amazon (README, sección Alexa) → `orbital alexa check` |
| 5 | (Opcional) Mover los emuladores fuera de Descargas | El Sensor de almacenamiento de Windows puede borrar Descargas; Orbital también busca en `C:\Emuladores` |

## Probar con el mando

### Consola
- [ ] Al encender la Legion Go, Orbital abre solo (acceso directo de inicio).
- [ ] En el escritorio, Home abre Orbital; Home otra vez se queda en Orbital.
- [ ] En un juego, Home → Orbital; Home → de vuelta al juego.
- [ ] Controles de la Legion: un toque de Start + Select en un juego trae Orbital; mantenido 1,5 s, lo cierra. En Orbital, el toque no hace nada (son ☰ y buscar). Si Legion L abre algo, `orbital.log` dice «Al frente una ventana de Lenovo: …».
- [ ] Un toque de Legion L hace lo mismo que Home (con Legion Space 1.3; la 1.4 ya no trae legionspace.exe); dos toques seguidos (menos de 2 s) desde un juego lo cierran. Legion Space no se queda abierto.
- [ ] Cambiar de modo el GameSir (Start+Select o Home sostenidos) no cierra el juego.
- [ ] Home+X, Home+B… dentro de Eden siguen haciendo lo de Eden (no mueven a Orbital).
- [ ] GameSir: LB + RB + Select sostenidos en un juego (otros mandos: Start + Select + Home): aparece el aviso encima del juego; soltar antes no cierra; sostener 1,5 s cierra sin preguntar.
- [ ] Ese mismo atajo también cierra un juego de Steam que esté al frente.
- [ ] A sobre el juego abierto dice "Continuar" y regresa a él (no abre otra copia).
- [ ] ☰ → Ventanas abiertas salta a otra app; ☰ → Apagado → Suspender.
- [ ] El mando vibra al llegar al final de una fila y al abrir un juego.

### Emuladores
- [ ] Zelda con Eden reconoce el GameSir sin configurarlo y A es A.
- [ ] Un juego de cada uno: Ryujinx, Dolphin (GameCube y Wii), mGBA, xemu, PPSSPP.
- [ ] Al cerrar cada uno, Orbital vuelve al frente y suma el tiempo jugado.

### Stremio
- [ ] Buscar: escribir 2-3 letras con el teclado del mando; los resultados aparecen solos.
- [ ] Dictar en Buscar (botón ☰ o la tecla Dictar).
- [ ] Una serie abre sus episodios; LB/RB cambia de temporada.
- [ ] En el reproductor de Stremio: A pausa, ←/→ adelanta/regresa, ↑/↓ volumen, Y pantalla completa (F11), B vuelve. Verificado: Stremio acepta las teclas que manda Orbital.
- [ ] A en un episodio o película arranca con la fuente recomendada; Y abre "Elegir fuente" para escoger otra (↑/↓ y A; B cierra).
- [ ] La fuente elegida abre el reproductor de Orbital a pantalla completa (verificado: Interstellar arrancó en 1,5 s con audio y subtítulos en inglés).
- [ ] En el reproductor: A pausa, ←/→ 10 s, LB/RB 1 min, ↑/↓ volumen, X audio, Y subtítulos, B sale y vuelve a Orbital.
- [ ] Home en el reproductor pausa y va a Orbital; Home otra vez regresa con la barra de progreso.
- [ ] Ver unos minutos, salir con B: "Seguir viendo" (en Orbital y en Stremio) muestra el avance; al volver a abrirlo sigue donde te quedaste.
- [ ] Terminar un episodio: "Seguir viendo" pasa al siguiente.
- [ ] Algo sin subtítulos en inglés dentro del video: se agregan los de tu addon de subtítulos (si tienes OpenSubtitles).

### GeForce NOW
- [ ] En Juegos aparece la fila "GeForce NOW" con los juegos de tu "Mi biblioteca" que se pueden jugar (se lee de la app de GFN; ábrela de vez en cuando para que se actualice).
- [ ] A en un juego de GFN lo abre directo en la nube (no lo pude probar: abre una sesión de tu cuenta).

### TV en vivo
- [ ] La sección «TV en vivo» (LB/RB desde Películas y series): categorías arriba, canales con su número; LB/RB cambian de categoría y, en la primera/última, de sección.
- [ ] A en un canal: pantalla de carga y, ~2 s después, el canal a pantalla completa con la barra (número, nombre, «En vivo»).
- [ ] ↑ ↓ y LT/RT cambian de canal; pulsar varias veces seguidas carga solo el último. Ver que ↑ es el siguiente (número mayor).
- [ ] Y abre la guía; elegir otra categoría y un canal; B la cierra.
- [ ] ◀ ▶ volumen y A silencio (la barra dice «Sin sonido»); X abre Audio.
- [ ] Un canal que no abre (apagar el Wi-Fi no sirve: elegir uno de los atenuados): «pasando a…» y salta solo.
- [ ] Home en un canal: sin sonido; Home otra vez: vuelve con sonido. B mantenido sale y avisa «De vuelta de la TV en vivo».
- [ ] Con un juego abierto, A en un canal pregunta «¿Cerrar…?».
- [ ] Sin Internet: la sección muestra la lista guardada y ningún canal desaparece.

### Pantalla de carga y sesiones
- [ ] Al abrir un juego de Eden no se ven la lista de juegos ni ventanas de Eden: la pantalla de Orbital se queda hasta que el juego arranca, se funde a negro y aparece el juego.
- [ ] B en la pantalla de carga la salta.
- [ ] El arte de la pantalla de carga entra completo (nunca por pedazos) y no se traba mientras el juego abre; sin internet, las estrellas y la inicial del título en la tarjeta.
- [ ] Una película en caché: alcanzas a ver su fondo antes de que empiece.
- [ ] Con un juego abierto, abrir otro pregunta "¿Cerrar…?" y "Volver a…" regresa al juego.
- [ ] Un video en pausa 15 min se cierra solo; al reabrirlo sigue donde te quedaste.

### Steam
- [ ] El héroe muestra el logotipo, las horas reales y el tamaño; Marvel Rivals avisa "Actualización pendiente".
- [ ] Tras jugar algo de Steam, sus horas se actualizan en Orbital (unos segundos después de cerrar).

### Voz (cuando Alexa esté configurada)
- [ ] "Alexa, pídele a mi consola que abra Zelda".
- [ ] "…que quiero ver The Office" → episodios en Orbital.
- [ ] "…que busque Dune" → búsqueda de Orbital ya escrita.
- [ ] "…que salga al escritorio" / "…que abra la consola".
- [ ] "Alexa, pregúntale a Orbital qué está abierto".
- [ ] "…que ponga Interstellar": arranca en el reproductor de Orbital sin tocar el control.
- [ ] Con un video puesto: "…que pause", "…que adelante 5 minutos", "…que ponga subtítulos en español", "…que cambie el audio a inglés".
- [ ] Con una serie puesta: "…que ponga el siguiente episodio".
- [ ] "…que abra (un juego) en la nube" abre tu juego de GeForce NOW.
- [ ] Con la Legion Go apagada: Alexa dice que no pudo conectar con tu consola.

## La CI manda

La CI es la revisión automática de GitHub (`.github/workflows/ci.yml`). Corre en cada commit, y la regla es una:
**nadie construye sobre rojo**. Si la CI está en rojo, lo primero es arreglarla; no se agrega nada nuevo encima.

Qué corre:

- **Windows (la TV):** revisión de código (ruff), tipos (pyright), pruebas de Python, pruebas de la interfaz web, pruebas
  de humo en un navegador real (Playwright), que los ejemplos compartidos Python a Swift (`tests/fixtures/ios`) estén al
  día (`scripts/ios_golden.py` y `git diff`) y que el paquete incluya la interfaz y los íconos.
- **macOS, pruebas:** `swift test` del paquete `OrbitalCore` (incluye la prueba del sistema de diseño del iPhone), con una
  versión de Xcode fija (`XCODE_VERSION` arriba del archivo).
- **macOS, app del iPhone:** XcodeGen genera el proyecto y `xcodebuild` compila la app para el simulador, sin firma, en
  Debug y en Release. Usa un `Secrets.xcconfig` con claves vacías (las reales no están en git). Por ahora es **provisional**: el
  compilador de la CI rechaza dos expresiones de la app (comentario en `ci.yml`), así que ese job avisa pero no pone la CI
  en rojo ni frena la etiqueta; cuando compile, se vuelve obligatorio.

`tv-estable`: es una etiqueta de git que apunta al último commit de `main` donde **todo lo anterior pasó**. Un último paso
de la CI la mueve solo cuando `main` queda en verde (si el commit falla, la etiqueta se queda donde estaba; solo avanza, nunca
retrocede aunque dos corridas terminen en desorden). La TV se actualiza desde esa etiqueta y no desde `main`, así que
nunca recibe algo que la CI no aprobó. Para ver dónde está: `git fetch origin tag tv-estable -f && git log -1 tv-estable`.

## El contrato con el iPhone (`tests/fixtures/contract`)

La TV y la app del iPhone hablan por el puerto público. Para que un cambio en la TV no rompa al iPhone sin que nadie se
entere, `tests/test_contract_fixtures.py` llama con datos de demostración a cada ruta que usa la app compañera y guarda la
respuesta real en `tests/fixtures/contract/<nombre>.json` (con la petición, el estado y la respuesta). El lado Swift
decodifica esos mismos archivos. Lo que cambia en cada corrida (fechas, ids, llaves, la versión de Orbital, rutas de la
carpeta temporal) se guarda normalizado: texto «`<llave>`» y números fijos del mismo tipo.

- Si la prueba falla, la forma de una respuesta cambió. Si fue a propósito, regenera y revisa el diff:
  `ORBITAL_UPDATE_CONTRACT=1 python -m pytest -q tests/test_contract_fixtures.py` (en la consola:
  `.venv\Scripts\python`). Después avisa al lado Swift para que sus pruebas decodifiquen lo nuevo.
- Solo campos nuevos: un iPhone viejo ignora lo que no conoce. Si algo deja de existir o cambia de tipo, sube
  `companion.API_VERSION` (`orbital/companion.py`).
- `/api/ping` y `/api/companion` dicen `api` (la versión del contrato) y `capabilities` (lo que esta TV sabe hacer, con
  nombres estables). Al agregar una ruta para el iPhone, agrégala a `companion.CAPABILITIES`; la prueba revisa que cada
  capacidad apunte a rutas que existen.
