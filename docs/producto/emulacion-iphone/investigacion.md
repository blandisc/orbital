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
