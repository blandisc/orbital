# Reproductor de la TV: pendientes que pidió Fernando (6 nov 2026)

Para la sesión de la TV. Lo pidió Fernando desde la sesión del iPhone; aquí no se tocó el reproductor de escritorio.
Antes de empezar: `docs/sistema-de-diseno.md` y las cuatro superficies (control, teclado, mouse y touch).

1. **Pausa › columna «Reproducción» cortada.** Al pausar para escoger episodios y versiones, toda la columna de
   «Reproducción» se corta. Cada renglón lleva un ícono y el texto acomodado para leerse completo (dos renglones si
   hace falta, nunca «…» a media palabra).
2. **Cristal en el reproductor.** El reproductor no tiene la estética de cristal del resto de la app. Aplicarla a sus
   paneles y a sus botones, incluidos «Elegir», «Cerrar» y los demás.
3. **«Episodios y versión»: textos cortados.** Al escoger episodio o versión solo se lee completo «Al instante»;
   «Idioma dudoso» y los demás se cortan. Hay que decidir qué se hace ahí (más ancho, dos renglones, o ícono con su nombre
   para VoiceOver, como el iPhone, D10: íconos, no cápsulas de texto).
   **1–3 hechos (8 nov):** íconos y nombres enteros en Reproducción, vidrio con los tokens (`player_ui.glass`) y, en Versión,
   íconos con leyenda (la decisión está en `docs/sistema-de-diseno.md` § 8). Falta verlo con mando en la Lenovo.
4. Ya hecho desde el iPhone (no tocar): lo que la TV manda al control como leyenda del botón Y ahora dice
   «Episodios y versión» en series (`player_screen.py`), igual que la pantalla.

Al terminar, el commit dice qué pasa en el iPhone y lo pendiente entra a `docs/producto/paridad-registro.md`.

## Más pendientes (Fernando, 8 nov)

5. **Atajos del control de la Legion Go no funcionan: ni «regresar a Orbital» ni «cerrar el juego».** Pistas desde el
   código (sin probar en la Lenovo): `orbital/gamepad.py` elige el combo de cerrar por la marca que reporta XInput
   (`close_combo_for`: Lenovo `0x17EF` → Start + Select; cualquier otra → Start + Select + Home). Si los controles de la
   Legion se reportan con otra marca (modo Xbox, `0x045E`, o sin marca), piden Home, que la Legion no tiene. «Regresar a
   Orbital» va con Home (`ComboDetector`, eventos «home»): en la Legion no hay camino. Revisar en la Lenovo qué marca
   reporta (Ajustes › Controles la enseña), dar a la Legion un atajo para regresar (p. ej. Select mantenido o el botón
   Legion L) y decirlo en Ajustes › Controles y en el menú (regla: todo atajo de mando tiene camino visible).
6. **Animación de los avisos del escritorio.** Pulir cómo aparecen, no lo que dicen: primero sale la alerta (el ícono) y
   luego la cajita de texto crece y rebota un poco (ejemplo de Fernando: «se desconectó el control»). Con
   `prefers-reduced-motion`, solo aparecer. Tokens de duración y curva en `styles/tokens.css`; la prueba del sistema de
   diseño cuida duraciones a mano. Aplica a los avisos dentro de Orbital y a los de encima del juego (`overlay.py`).
