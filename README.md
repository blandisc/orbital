# Orbital

Interfaz tipo consola para la **Lenovo Legion Go**: conéctala a la TV, navega con el mando y abre
tus juegos de **Steam**, tus **emuladores**, **Stremio** y otras apps desde una sola pantalla. Además
se controla con la voz a través de **Alexa**.

```
 ┌──────────────────── Legion Go (Windows 11) ─────────────────────┐
 │                                                                 │
 │  Edge en kiosko (perfil propio) ──▶ Orbital :8710 (solo local)  │
 │  interfaz + mando (Gamepad API)       ├─ Steam                  │
 │            ▲                          ├─ Emuladores (detectados)│
 │            └──── eventos SSE ─────────├─ ES-DE (portadas, favs) │
 │                                       ├─ Stremio (Seguir viendo)│
 │                                       └─ voz                    │
 │                                             ▲                   │
 │                     Orbital :8711 (solo voz, con token)         │
 │                                             ▲                   │
 │                       Tailscale Funnel (HTTPS, gratis)          │
 └─────────────────────────────────────────────┼───────────────────┘
                                               │
 "Alexa, pídele a mi consola que abra Hades" ─▶ Skill ─▶ AWS Lambda
```

## Qué hace

| Fuente | Cómo funciona |
|---|---|
| **Steam** | Lee `libraryfolders.vdf` + `appmanifest_*.acf` (todas las bibliotecas y discos), filtra Proton y runtimes, usa la portada local o la del CDN y lanza con `steam://rungameid/<id>`. Incluye un atajo a Big Picture. |
| **Emuladores** | Se **detectan solos** (Ryujinx, Eden, Dolphin, mGBA, xemu, Xenia, DuckStation, PCSX2, PPSSPP, melonDS, Cemu…) en Descargas, Escritorio, `C:\Emuladores`, etc. Si quieres cambiar algo, se sobrescribe en `config.yaml`. Cada sistema tiene su propia fila. |
| **ES-DE** | Si usas ES-DE, Orbital toma de ahí la carpeta de ROMs, los nombres del scraper, las portadas de `downloaded_media`, tus **favoritos** (fila propia) y oculta los juegos marcados como ocultos. También agrega un acceso a ES-DE. |
| **Stremio** | Abre Stremio 4/5 y, si vinculas tu cuenta, muestra la fila **Seguir viendo** con pósters, progreso y episodio (T2 E4); con A abre directo la ficha de ese episodio. Por voz: "sigue viendo", "continúa The Office", "busca Dune en Stremio". |
| **Apps** | Cualquier ejecutable o URL (ES-DE, YouTube TV, Playnite…). |
| **Voz** | `/api/voice` acepta intents de Alexa o texto libre en español ("abre hollow knight", "busca dune en stremio", "cierra el juego", "ve a la derecha"). |

### Controles

| Mando | Teclado | Acción |
|---|---|---|
| D-pad / stick | Flechas | Moverse (↑↓ cambia de fila) |
| A | Enter | Jugar |
| X | X | Abrir con el emulador alternativo (p. ej. Eden) |
| Y | Y | Opciones del juego: favorito, abrir con…, usar siempre…, ocultar |
| ☰ / View | M | Menú: actualizar, sonidos, cerrar el juego, mostrar ocultos, **salir al escritorio** |
| B | Esc | Volver al inicio / cerrar menú |
| LB / RB | RePág / AvPág | Saltar de 5 en 5 |

Con el ratón o la pantalla táctil: un toque selecciona y el segundo abre. Los indicadores del pie
cambian solos según uses el mando o el teclado.

Al cerrar un emulador (o un juego de Steam en Windows, que se detecta por el registro de Steam),
Orbital vuelve al frente, guarda el tiempo jugado y actualiza "Jugado recientemente". El historial
y las preferencias se guardan en `state.json`, junto a `config.yaml`.

## Instalación en la Legion Go (Windows 11)

1. Instala [Git](https://git-scm.com) y clona este repo (por ejemplo en `C:\Orbital`).
2. En PowerShell:
   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\install-windows.ps1
   ```
   Esto instala Python si hace falta, crea un entorno virtual, copia `config.example.yaml` a
   `%APPDATA%\orbital\config.yaml` con un token aleatorio y crea el acceso directo de inicio.
3. **No hace falta editar nada**: los emuladores se detectan solos y las ROMs, nombres y portadas
   salen de ES-DE. Solo si algo no aparece, revisa `%APPDATA%\orbital\config.yaml`.
4. Comprueba lo que detecta: `.venv\Scripts\python -m orbital --list`. Primero muestra un
   diagnóstico (`OK` / `!!`) de Steam, ES-DE y cada emulador, con cuántos juegos encontró.
5. Arranca: `.venv\Scripts\python -m orbital` (abre Edge en pantalla completa).

**Salir al escritorio:** menú ☰ → *Salir al escritorio* (pide confirmación), o "Alexa, dile a mi
consola que salga al escritorio". Orbital sigue funcionando en segundo plano: "Alexa, dile a mi
consola que abra la consola" la vuelve a mostrar.

**Ventana propia:** Orbital abre Edge con un perfil aparte (`%LOCALAPPDATA%\orbital\browser`), así
que no se mezcla con tu Edge de siempre, siempre abre en pantalla completa aunque Edge ya esté
abierto y no muestra "¿Restaurar páginas?".

**Tip para modo consola:** en Legion Space desactiva "abrir al iniciar" y en Windows configura el
inicio de sesión automático; así, al encender la Legion Go, arranca directo en Orbital.

### Emuladores detectados automáticamente

| Sistema | Emulador | Carpeta ES-DE | Argumentos |
|---|---|---|---|
| Nintendo Switch | Ryujinx (principal) · Eden / Citron / Sudachi (alternativos) | `switch` | `--fullscreen {rom}` / `-f -g {rom}` |
| GameCube / Wii | Dolphin | `gc` / `wii` | `-b -e {rom}` |
| Game Boy Advance | mGBA | `gba` | `-f {rom}` |
| Xbox / Xbox 360 | xemu (ISO en XISO) / Xenia Canary | `xbox` / `xbox360` | `-full-screen -dvd_path {rom}` / `--fullscreen {rom}` |
| PlayStation 1 / 2 / PSP | DuckStation / PCSX2 / PPSSPP | `psx` / `ps2` / `psp` | `-batch -fullscreen {rom}` / `--fullscreen {rom}` |
| Nintendo DS / Wii U | melonDS / Cemu | `nds` / `wiiu` | `-f {rom}` / `-f -g {rom}` |

Busca en: Descargas (4 niveles de subcarpetas), Escritorio, `%USERPROFILE%\Emuladores`,
`C:\Emuladores`, `C:\Emulators`, la carpeta `Emulators` de ES-DE, `%LOCALAPPDATA%\Programs` y
Archivos de programa. Si hay dos copias del mismo emulador, usa la más reciente. Puedes añadir
carpetas con `detect.dirs` o apagarlo con `detect.enabled: false`.

En Switch se ignoran las actualizaciones y DLC (`[UPD]`, `[DLC]`) para que no salgan como juegos.

**Varios emuladores para un sistema:** si dos emuladores tienen el mismo `system` (Ryujinx y Eden),
los juegos salen una sola vez. Se abren con el primero de la lista, salvo que en ES-DE hayas
elegido otro para ese juego (*Editar metadatos → Emulador alternativo*) o para todo el sistema
(*Otros ajustes → Emuladores alternativos*). También puedes elegirlo desde Orbital con el botón Y
(*Usar siempre Eden*) o abrir una sola vez con el otro usando X.

**Rutas con comodines** (si configuras uno a mano): `'%USERPROFILE%\Downloads\**\xemu.exe'`
encuentra xemu en cualquier subcarpeta de Descargas, sin importar la versión.

> Ojo: el *Sensor de almacenamiento* de Windows puede borrar automáticamente lo que hay en
> Descargas. Conviene mover los emuladores a `C:\Emuladores` (Orbital también busca ahí), o
> revisar que esa opción esté desactivada.

### SteamOS / Bazzite / Linux

```bash
python3 -m venv .venv && .venv/bin/pip install -e .
mkdir -p ~/.config/orbital && cp config.example.yaml ~/.config/orbital/config.yaml
cp scripts/orbital.service ~/.config/systemd/user/ && systemctl --user enable --now orbital
```
En Game Mode puedes añadir Chromium como "juego no de Steam" apuntando a `http://127.0.0.1:8710`.

## Stremio: "Seguir viendo"

Vincula tu cuenta una vez (en la Legion Go, con teclado):

```powershell
.venv\Scripts\python -m orbital stremio login     # correo y contraseña (la contraseña no se guarda)
.venv\Scripts\python -m orbital stremio status    # comprueba y lista lo que tienes a medias
```

Si prefieres no escribir tu contraseña: abre web.stremio.com con tu sesión, abre la consola del
navegador (F12) y ejecuta `JSON.parse(localStorage.getItem("profile")).auth.key`; luego
`orbital stremio key <esa-clave>`. Para desvincular: `orbital stremio logout`.

Cómo funciona:

- Orbital guarda solo la **clave de sesión** en `%APPDATA%\orbital\secrets.json` (solo tu usuario
  puede leerlo). Nunca se envía a la interfaz web.
- Lee tu biblioteca con la API de Stremio (`api.strem.io`, `datastoreGet`) y aplica la misma regla
  que Stremio para "Seguir viendo": no quitado y con progreso guardado. Se actualiza al arrancar, al
  cerrar Stremio y cada 3 minutos mientras la interfaz está abierta, sin bloquearla.
- Al pulsar A abre `stremio:///detail/<tipo>/<id>/<episodio>`, la ficha del episodio en Stremio.
- Lo que no está a medias no tiene fila, pero la voz lo encuentra ("abre The Office").

> ⚠️ La API de Stremio **no es oficial**: el formato se tomó del código de Stremio (stremio-core).
> Si Stremio la cambia, la fila desaparece y `orbital stremio status` muestra el error; el resto de
> Orbital sigue igual. Tampoco pude comprobar desde aquí que los enlaces `stremio:///detail/...`
> abran el episodio en tu versión de Stremio para Windows; si solo abren el inicio, avísame.

## Alexa

```
"Alexa, pídele a mi consola que abra Zelda"
   │  Alexa (nube de Amazon) → LaunchGameIntent, game="zelda"
   ▼
AWS Lambda (alexa/lambda_function.py) ── verifica que la petición es de TU skill
   │  POST https://<tu-equipo>.<tailnet>.ts.net/api/voice   Authorization: Bearer <token>
   ▼
Tailscale Funnel (túnel HTTPS gratis, dirección fija) ──► 127.0.0.1:8711 en la Legion Go
   ▼
Orbital, puerto de Alexa (solo voz y ping, SIEMPRE con token) → abre Zelda con Ryujinx
   ▼
"Abriendo The Legend of Zelda…" (Alexa lo dice y aparece un aviso en pantalla)
```

**Seguridad:** el túnel solo llega al puerto **8711**, que únicamente acepta comandos de voz con el
token. La interfaz y la API completa (8710) nunca salen a internet: además, rechazan cualquier
petición cuyo `Host` no sea `localhost`, aunque alguien apunte el túnel ahí por error.
`orbital alexa check` comprueba las tres cosas.

### 1. Token y túnel (en la Legion Go)

```powershell
.venv\Scripts\python -m orbital alexa setup     # crea el token fijo y te dice los valores para la Lambda
```

1. Instala [Tailscale](https://tailscale.com/download) e inicia sesión (cuenta gratuita).
2. En PowerShell: `tailscale funnel --bg 8711`. La primera vez te da un enlace para activar HTTPS y
   Funnel en tu cuenta: ábrelo y acepta. Con `--bg` queda activo aunque reinicies.
3. Reinicia Orbital y comprueba: `.venv\Scripts\python -m orbital alexa check`. Tiene que salir
   todo en `OK`. Con `orbital alexa say "abre zelda"` pruebas un comando real por el túnel.

### 2. La skill (consola de Alexa)

1. Entra en la [consola de desarrolladores de Alexa](https://developer.amazon.com/alexa/console/ask)
   con **la misma cuenta de Amazon que tu Echo** → *Create Skill*.
2. Nombre: *Mi consola*. Idioma: **Spanish (MX)**. Tipo: *Other → Custom*. Hosting: *Provision your
   own*. Plantilla: *Start from scratch*.
3. *Interaction Model → JSON Editor*: pega `alexa/interaction_model.es-MX.json` → *Save* → *Build*.
4. Copia el **Skill ID** (`amzn1.ask.skill...`).

### 3. La Lambda (consola de AWS, nivel gratuito)

1. En [AWS Lambda](https://console.aws.amazon.com/lambda) elige la región **US East (N. Virginia)**
   → *Create function* → *Author from scratch*, runtime **Python 3.12**.
2. Pega el contenido de `alexa/lambda_function.py` en el editor → *Deploy*.
3. *Configuration → Environment variables*: `ORBITAL_URL`, `ORBITAL_TOKEN` (los que imprimió
   `orbital alexa setup`) y `ALEXA_SKILL_ID`.
4. *Add trigger → Alexa Skills Kit* → activa la verificación y pega el Skill ID.
5. Copia el ARN de la función y pégalo en la skill: *Endpoint → AWS Lambda ARN → Default region* → *Save*.

### 4. Probar

En la consola de Alexa, pestaña *Test* → activa *Development*, y escribe o di:
"abre mi consola" y luego "abre zelda". Como la skill queda en modo desarrollo, funciona en todos
los Echo de tu cuenta sin publicarla.

### Frases

| Di… | Hace |
|---|---|
| "Alexa, abre mi consola" | Muestra Orbital (si saliste al escritorio) y pregunta qué quieres |
| "Alexa, pídele a mi consola que abra Hollow Knight" | Abre el juego |
| "Alexa, pídele a mi consola que abra Zelda con Eden" | Abre con el emulador alternativo |
| "Alexa, pídele a mi consola que siga viendo" / "…que continúe The Office" | Retoma en Stremio |
| "Alexa, pídele a mi consola que busque Dune en Stremio" | Abre la ficha (o la búsqueda) |
| "Alexa, pídele a mi consola que cierre el juego" | Cierra el emulador en curso |
| "Alexa, pídele a mi consola que salga al escritorio" / "…que muestre la consola" | Sale / vuelve |
| "Alexa, dile a mi consola que se mueva a la derecha" | Mueve la selección |
| "Alexa, pregúntale a mi consola qué está abierto" | Te dice qué está corriendo |

### Atajos con Rutinas (frases cortas)

Las skills propias siempre necesitan "pídele a mi consola que…". Para frases cortas usa las Rutinas
de la app Alexa: *Más → Rutinas → +* → *Cuando esto ocurra: Voz* → "a jugar Zelda" → *Agregar
acción → Personalizado* → `pídele a mi consola que abra zelda`. Ideas: "modo película" →
`pídele a mi consola que siga viendo`; "apaga la consola" → `pídele a mi consola que salga al escritorio`.

### Limitaciones conocidas

- La Legion Go tiene que estar **encendida** con Orbital abierto: Alexa no puede despertarla.
- **No lo pude probar con un Echo real**: está probada toda la cadena Lambda → túnel simulado →
  Orbital, y el modelo de voz se valida automáticamente, pero la primera vez revisa la pestaña Test.
- Hay un reporte de un usuario de que Tailscale 1.102.1 en Windows no publicaba Funnel en internet
  (sí dentro de la tailnet). Si `alexa check` va bien pero la pestaña Test de Alexa dice que no
  conecta, revisa la versión de Tailscale.

## API

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/api/library` | Biblioteca agrupada por filas |
| POST | `/api/library/refresh` | Vuelve a escanear |
| POST | `/api/launch` | `{"id": "steam:367520", "runner": null}` (`runner` = emulador alternativo) |
| POST | `/api/prefs` | `{"id": …, "favorite": true, "hidden": false, "runner": "switch-eden"}` |
| POST | `/api/prefs/unhide-all` | Vuelve a mostrar los juegos ocultos |
| GET | `/api/system` | Wi-Fi y última actividad de Alexa |
| GET | `/api/ui` · POST `/api/ui/exit` | ¿Se puede salir? · Salir al escritorio |
| — | Puerto 8711: GET `/api/ping`, POST `/api/voice` | Solo para Alexa por el túnel, siempre con token |
| GET | `/api/art/<id>?kind=cover\|hero` | Portada o fondo (solo imágenes asociadas a un elemento) |
| GET | `/api/status` | Lo que está abierto |
| POST | `/api/stop` | Cierra el proceso lanzado por Orbital |
| POST | `/api/voice` | `{"intent": "...", "slots": {...}}` o `{"text": "abre hades"}` |
| GET | `/api/events` | Server-Sent Events para la UI (avisos, navegación por voz) |

Seguridad: las peticiones que vienen del propio equipo no necesitan token; las que llegan desde la red
o a través de un proxy o túnel (cabeceras `X-Forwarded-For`, `CF-Connecting-IP`…) sí. Las peticiones con
un `Origin` de otra web se rechazan, para que una página maliciosa no pueda lanzar cosas en tu equipo.

## Interfaz (frontend)

Módulos ES nativos que Edge ejecuta directamente: **sin paso de compilación, sin dependencias**.

```
orbital/web/
  index.html                 # solo carga main.css y main.js
  styles/
    tokens.css               # capa 1: primitivos (paleta, espacios, tipografía, movimiento, layout)
    themes/nordic.css        # capa 2: tokens semánticos del tema (--color-accent, --scrim-hero...)
    base.css                 # reset y globales
    components/*.css         # un archivo por componente, nomenclatura BEM (.card__title, .card--focused)
    main.css                 # orden de importación
  js/
    main.js                  # controlador: estado + API + entrada + componentes
    components/              # Card, Shelf, Hero, Button, Glyph, Sheet, StatusBar, Hints,
                             # LaunchOverlay, Toast, Backdrop — fábricas que devuelven { el, … }
    core/                    # dom (helper h()), api, input, menus, library, format, sound, storage, tokens
```

Reglas del sistema:

- **Los componentes solo usan tokens semánticos**, nunca colores ni medidas sueltas ni primitivos
  (`--palette-*`). Para un tema nuevo (B2 verde CRT, A-Prime…) copia `themes/nordic.css`, cambia los
  valores, impórtalo en `main.css` y pon `<html data-theme="b2">`.
- **El DOM se crea con `h()`** (`core/dom.js`) usando `textContent`: los títulos de los juegos nunca
  se insertan como HTML.
- **Los componentes no conocen la lógica**: reciben datos y callbacks (`onPress`, `onCommand`). Los
  menús son datos (`core/menus.js`) con un `command` que ejecuta `main.js`.
- **La entrada se abstrae en acciones** (`up`, `select`, `options`…): teclado, rueda, táctil, mando
  y Alexa (`navigate`) pasan por el mismo `handleAction`.
- El layout que necesita JS (ancho de tarjeta, alto de fila) se lee de los tokens con `tokenPx()`,
  no está duplicado en el código.
- La lógica pura (`format`, `library`, `menus`, `input`) tiene pruebas con `node --test`.

## Desarrollo

```bash
pip install -e ".[dev]"
pytest                              # backend (Python)
npm test                            # lógica del frontend (node --test, sin dependencias)
python -m orbital --ui none -v      # solo el servidor; abre http://127.0.0.1:8710
```

Estructura:
```
orbital/
  config.py      # carga y validación de config.yaml
  catalog.py     # biblioteca unificada, búsqueda difusa y lanzamiento
  launcher.py    # procesos y URIs multiplataforma
  voice.py       # intents de Alexa y comandos de texto
  server.py      # API FastAPI + SSE + seguridad
  state.py       # recientes, tiempo jugado y preferencias (state.json)
  system.py      # traer Orbital al frente (Windows) y estado del Wi-Fi
  library/       # steam.py, emulators.py, esde.py, stremio.py, vdf.py
  web/           # interfaz (ver "Interfaz")
alexa/           # Lambda + modelo de interacción
scripts/         # instalación en Windows y servicio systemd
```

## Hoja de ruta

- [ ] Accesos directos "no Steam" (`shortcuts.vdf` binario) para quien usa Steam ROM Manager.
- [x] Portadas, nombres y favoritos de ES-DE.
- [x] "Jugado recientemente", tiempo jugado, favoritos y ocultos propios.
- [x] Volver a Orbital automáticamente al cerrar un juego.
- [x] Tema Nordic con sistema de tokens.
- [ ] Temas B2 Green CRT y A-Prime (solo falta su archivo de tokens).
- [ ] Portadas de SteamGridDB para lo que ES-DE no tenga.
- [ ] Control de volumen y suspensión por voz.
- [ ] Empaquetar como `.exe` (PyInstaller) para no depender de Python.
