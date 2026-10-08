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
| **Emuladores** | Cada emulador se define en `config.yaml` con su ejecutable, argumentos (`{rom}`, `{rom_dir}`, `{rom_name}`), carpetas y extensiones. Limpia los nombres (`Chrono_Trigger (USA) [!].smc` → *Chrono Trigger*). |
| **Stremio** | Detecta Stremio 4/5 (o Flatpak en Linux); si no lo encuentra usa el protocolo `stremio://`. Por voz puede buscar títulos con `stremio:///search?search=…`. |
| **Apps** | Cualquier ejecutable o URL (ES-DE, YouTube TV, Playnite…). |
| **Voz** | `/api/voice` acepta intents de Alexa o texto libre en español ("abre hollow knight", "busca dune en stremio", "cierra el juego", "ve a la derecha"). |

Controles: **D-pad / stick** para moverte, **A** para abrir, **B** para volver y **Y** para actualizar la biblioteca.
Con teclado: flechas, Enter, Esc y R. Los indicadores de abajo cambian según uses el mando o el teclado.

## Instalación en la Legion Go (Windows 11)

1. Instala [Git](https://git-scm.com) y clona este repo (por ejemplo en `C:\Orbital`).
2. En PowerShell:
   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\install-windows.ps1
   ```
   Esto instala Python si hace falta, crea un entorno virtual, copia `config.example.yaml` a
   `%APPDATA%\orbital\config.yaml` con un token aleatorio y crea el acceso directo de inicio.
3. Edita `%APPDATA%\orbital\config.yaml` con las rutas de tus emuladores y ROMs.
4. Comprueba lo que detecta: `.venv\Scripts\python -m orbital --list`
5. Arranca: `.venv\Scripts\python -m orbital` (abre Edge en pantalla completa).

**Tip para modo consola:** en Legion Space desactiva "abrir al iniciar" y en Windows configura el
inicio de sesión automático; así, al encender la Legion Go, arranca directo en Orbital.

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
| POST | `/api/launch` | `{"id": "steam:367520"}` |
| GET | `/api/status` | Lo que está abierto |
| POST | `/api/stop` | Cierra el proceso lanzado por Orbital |
| POST | `/api/voice` | `{"intent": "...", "slots": {...}}` o `{"text": "abre hades"}` |
| GET | `/api/events` | Server-Sent Events para la UI (avisos, navegación por voz) |

Seguridad: las peticiones que vienen del propio equipo no necesitan token; las que llegan desde la red
o a través de un proxy o túnel (cabeceras `X-Forwarded-For`, `CF-Connecting-IP`…) sí. Las peticiones con
un `Origin` de otra web se rechazan, para que una página maliciosa no pueda lanzar cosas en tu equipo.

## Desarrollo

```bash
pip install -e ".[dev]"
pytest
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
  library/       # steam.py, emulators.py, stremio.py, vdf.py
  web/           # interfaz (HTML/CSS/JS, Gamepad API)
alexa/           # Lambda + modelo de interacción
scripts/         # instalación en Windows y servicio systemd
```

## Hoja de ruta

- [ ] Accesos directos "no Steam" (`shortcuts.vdf` binario) para quien usa Steam ROM Manager.
- [ ] Portadas para ROMs (SteamGridDB o carpetas de *boxart* de ES-DE).
- [ ] Favoritos y "jugado recientemente".
- [ ] Volver a Orbital automáticamente al cerrar un juego (traer la ventana al frente).
- [ ] Temas visuales (retomar los de orbit-shell: B2 Green CRT, A-Prime, Nordic).
- [ ] Control de volumen y suspensión por voz.
- [ ] Empaquetar como `.exe` (PyInstaller) para no depender de Python.
