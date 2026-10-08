# Orbital

Interfaz tipo consola para la **Lenovo Legion Go**: conéctala a la TV, navega con el mando y abre
tus juegos de **Steam**, tus **emuladores**, **Stremio** y otras apps desde una sola pantalla. Además
se controla con la voz a través de **Alexa**.

```
 ┌──────────── Legion Go (Windows 11 o SteamOS/Bazzite) ─────────────┐
 │                                                                   │
 │  Edge/Chromium en kiosko ──HTTP──▶ Orbital (Python, :8710)        │
 │  (UI + mando vía Gamepad API)        ├─ Steam (steam://rungameid) │
 │            ▲                         ├─ Emuladores (RetroArch, …) │
 │            └──── eventos SSE ────────├─ Stremio                   │
 │                                      └─ /api/voice                │
 │                                              ▲                    │
 │                         cloudflared (túnel HTTPS + token)         │
 └──────────────────────────────────────────────┼────────────────────┘
                                                │
   "Alexa, abre mi consola y juega Hades" ─▶ Skill de Alexa ─▶ AWS Lambda
```

## Qué hace

| Fuente | Cómo funciona |
|---|---|
| **Steam** | Lee `libraryfolders.vdf` + `appmanifest_*.acf` (todas las bibliotecas y discos), filtra Proton y runtimes, usa la portada local o la del CDN y lanza con `steam://rungameid/<id>`. Incluye un atajo a Big Picture. |
| **Emuladores** | Cada emulador se define en `config.yaml` con su ejecutable, argumentos (`{rom}`, `{rom_dir}`, `{rom_name}`) y extensiones. Cada sistema tiene su propia fila en la pantalla. |
| **ES-DE** | Si usas ES-DE, Orbital toma de ahí la carpeta de ROMs, los nombres del scraper, las portadas de `downloaded_media`, tus **favoritos** (fila propia) y oculta los juegos marcados como ocultos. También agrega un acceso a ES-DE. |
| **Stremio** | Detecta Stremio 4/5 (o Flatpak en Linux); si no lo encuentra usa el protocolo `stremio://`. Por voz puede buscar títulos con `stremio:///search?search=…`. |
| **Apps** | Cualquier ejecutable o URL (ES-DE, YouTube TV, Playnite…). |
| **Voz** | `/api/voice` acepta intents de Alexa o texto libre en español ("abre hollow knight", "busca dune en stremio", "cierra el juego", "ve a la derecha"). |

### Controles

| Mando | Teclado | Acción |
|---|---|---|
| D-pad / stick | Flechas | Moverse (↑↓ cambia de fila) |
| A | Enter | Jugar |
| X | X | Abrir con el emulador alternativo (p. ej. Eden) |
| Y | Y | Opciones del juego: favorito, abrir con…, usar siempre…, ocultar |
| ☰ / View | M | Menú: actualizar, sonidos, cerrar el juego, mostrar ocultos |
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
3. Edita `%APPDATA%\orbital\config.yaml`: solo tienes que cambiar la ruta `executable` de cada
   emulador (las carpetas de ROMs salen de ES-DE).
4. Comprueba lo que detecta: `.venv\Scripts\python -m orbital --list`. Primero muestra un
   diagnóstico (`OK` / `!!`) de Steam, ES-DE y cada emulador, con cuántos juegos encontró.
5. Arranca: `.venv\Scripts\python -m orbital` (abre Edge en pantalla completa).

**Tip para modo consola:** en Legion Space desactiva "abrir al iniciar" y en Windows configura el
inicio de sesión automático; así, al encender la Legion Go, arranca directo en Orbital.

### Emuladores incluidos en `config.example.yaml`

| Sistema | Emulador | Carpeta ES-DE | Argumentos |
|---|---|---|---|
| Nintendo Switch | Ryujinx (principal) + Eden (alternativo) | `switch` | `--fullscreen {rom}` / `-f -g {rom}` |
| GameCube | Dolphin | `gc` | `-b -e {rom}` |
| Wii | Dolphin | `wii` | `-b -e {rom}` |
| Game Boy Advance | mGBA (o RetroArch + mgba) | `gba` | `-f {rom}` |
| Xbox | xemu (ISO en formato XISO) | `xbox` | `-full-screen -dvd_path {rom}` |
| Xbox 360 (comentado) | Xenia Canary | `xbox360` | `--fullscreen {rom}` |

En Switch, `exclude` evita que las actualizaciones y DLC (`[UPD]`, `[DLC]`) aparezcan como juegos.

**Varios emuladores para un sistema:** si dos emuladores tienen el mismo `system` (Ryujinx y Eden),
los juegos salen una sola vez. Se abren con el primero de la lista, salvo que en ES-DE hayas
elegido otro para ese juego (*Editar metadatos → Emulador alternativo*) o para todo el sistema
(*Otros ajustes → Emuladores alternativos*). Orbital lo detecta por el nombre del ejecutable
(o por `esde_label`).

**Rutas con comodines:** `'%USERPROFILE%\Downloads\**\xemu.exe'` encuentra xemu en cualquier
subcarpeta de Descargas, sin importar la versión. Si hay varias copias, usa la más reciente.

> Ojo: el *Sensor de almacenamiento* de Windows puede borrar automáticamente lo que hay en
> Descargas. Conviene mover los emuladores a algo como `C:\Emuladores` (y cambiar la ruta a
> `'C:\Emuladores\**\xemu.exe'`), o revisar que esa opción esté desactivada.

### SteamOS / Bazzite / Linux

```bash
python3 -m venv .venv && .venv/bin/pip install -e .
mkdir -p ~/.config/orbital && cp config.example.yaml ~/.config/orbital/config.yaml
cp scripts/orbital.service ~/.config/systemd/user/ && systemctl --user enable --now orbital
```
En Game Mode puedes añadir Chromium como "juego no de Steam" apuntando a `http://127.0.0.1:8710`.

## Alexa

Alexa no puede hablar directamente con tu red local, así que el flujo es:
**Alexa → AWS Lambda → túnel HTTPS → Orbital**, y el túnel exige el token de `config.yaml`.

1. **Túnel** (gratis con Cloudflare): instala `cloudflared` y crea un túnel con nombre hacia
   `http://127.0.0.1:8710` (p. ej. `orbital.tudominio.com`). Cualquier petición que llegue por el
   túnel necesita `Authorization: Bearer <token>`; sin él, Orbital responde 401.
2. **Skill**: en la [consola de desarrolladores de Alexa](https://developer.amazon.com/alexa/console/ask)
   crea una skill *Custom* en **Español (MX)** con backend "Provision your own" y pega
   `alexa/interaction_model.es-MX.json` en el JSON Editor. El nombre de invocación es "mi consola".
3. **Lambda**: crea una función Python 3.12 con `alexa/lambda_function.py`, añade el disparador
   "Alexa Skills Kit" con el ID de tu skill y define las variables `ORBITAL_URL` y `ORBITAL_TOKEN`.
4. Copia el ARN de la Lambda en el endpoint de la skill, compila y pruébala en la pestaña *Test*.

Frases de ejemplo:
- "Alexa, abre mi consola y juega Hades"
- "Alexa, pídele a mi consola que busque Interstellar en Stremio"
- "Alexa, dile a mi consola que cierre el juego"
- "Alexa, dile a mi consola muévete a la derecha"

> "Cerrar el juego" solo termina los procesos que abrió Orbital (emuladores, apps). Los juegos de
> Steam y Stremio los gestiona su propia app, así que Orbital no los cierra a ciegas.

## API

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/api/library` | Biblioteca agrupada por filas |
| POST | `/api/library/refresh` | Vuelve a escanear |
| POST | `/api/launch` | `{"id": "steam:367520", "runner": null}` (`runner` = emulador alternativo) |
| POST | `/api/prefs` | `{"id": …, "favorite": true, "hidden": false, "runner": "switch-eden"}` |
| POST | `/api/prefs/unhide-all` | Vuelve a mostrar los juegos ocultos |
| GET | `/api/system` | Wi-Fi y última actividad de Alexa |
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
