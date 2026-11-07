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
4. Ya hecho desde el iPhone (no tocar): lo que la TV manda al control como leyenda del botón Y ahora dice
   «Episodios y versión» en series (`player_screen.py`), igual que la pantalla.

Al terminar, el commit dice qué pasa en el iPhone y lo pendiente entra a `docs/producto/paridad-registro.md`.
