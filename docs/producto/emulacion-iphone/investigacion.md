# Juegos en Orbital Ultra (iPhone): investigación

3 nov 2026. Canvas con las opciones y decisiones: https://claude.ai/artifact/X3f9bdqV7qYN2Xd9aofZ9D (`canvas.html`).
Estado: **investigación, nada construido**. Espera las decisiones D1–D3 de Fernando.

## Lo que se encontró
- Apple permite emuladores retro en la App Store desde abril de 2024 (Delta, PPSSPP, RetroArch, Provenance, Gamma).
- Sin JIT corren bien GB/GBA, NES/SNES/Genesis, DS, PS1 y casi todo PSP en iPhones recientes.
- GameCube/Wii (DolphiniOS) y Switch (MeloNX) necesitan JIT. iOS 26 trajo TXM y lo rompió; StikDebug lo regresa
  app por app; la 26.4 lo volvió a romper; en 26.6 y 27 solo funciona con algunas apps (SideStore, jun 2026).
  MeloNX además pide el permiso de más memoria y cuenta de desarrollador de pago.
- En iOS no se le puede pasar un juego a otra app y abrirlo como en Windows: Delta tiene enlaces `delta://` solo para
  juegos ya importados en Delta; para el resto, «Abrir en…» (como Infuse) importa el archivo.
- La tele usa mGBA, melonDS, DuckStation y PPSSPP sueltos (`orbital/library/detect.py`). Sus núcleos libretro leen las
  mismas partidas (la `.sav` de mGBA es la `.srm`; PPSSPP usa la misma carpeta `SAVEDATA`), así que la partida se puede
  cruzar entre la tele y el iPhone. Los estados rápidos (save states) no se cruzan de forma confiable.

## Opciones (detalle en el Canvas)
- **E1** abrir Delta/PPSSPP desde Orbital. **E2** motores dentro de Ultra (libretro) con la partida compartida.
  **E3** transmitir la consola (Apollo en la Legion Go + Moonlight en el iPhone).
- Recomendación: **D1-B** (E2 para lo ligero, E3 para lo pesado), **D2-B** (mando solo dentro del juego; choca con la
  regla del 29 oct de no usar mando en la app, por eso se pregunta), **D3-A** (Switch solo por transmisión).

## Restricciones
- Solo en Ultra (`ORBITAL_ULTRA`): los núcleos son GPL/MPL; repartir Plus por TestFlight obligaría a publicar el código.
- La tele no cambia. Si se construye, va una fila al registro de paridad.

## GameCube y Switch (3 nov, «para mí es súper importante»)
- **G1 desde la consola:** el iPhone pide a la tele `POST /api/launch` (ya existe en `orbital/api/play.py`; el iPhone
  aún no lo usa) y abre Moonlight contra Apollo en la Legion Go (pantalla virtual del tamaño del iPhone). Cualquier iOS.
- **G2 en el iPhone:** DolphiniOS y MeloNX compilados con la cuenta de Fernando, con App Group compartido con Ultra
  (juegos, partidas, llaves y firmware del Switch desde la consola) y JIT por StikDebug
  (`stikdebug://enable-jit?bundle-id=…&pid=…&script-name=universal.js` en TXM). Una vez: modo desarrollador, archivo de
  emparejamiento desde la Mac, LocalDevVPN. DolphiniOS 5.0.0b6 dice funcionar en iOS 27; MeloNX sin confirmar en 27.
  MeloNX pide «Increased Memory Limit» y recomienda iPhone 15 Pro o más nuevo.
- **G3** Dolphin dentro de Orbital con StikJIT integrado: posible, meses; Switch (Ryujinx/.NET) no.
- Recomendación: **D3-B** (G1 primero, G2 después). D4: falta saber el modelo del iPhone.
