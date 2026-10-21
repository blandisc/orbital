# Búsqueda rápida (octubre 2026)

Por qué tardaba «Buscar» y qué se hizo. El iPhone ya está arreglado; la TV queda pendiente para su sesión.

## iPhone (hecho)

- Películas y series se piden por separado y cada una se ve en cuanto llega. Antes se esperaba a la más lenta, y si una
  fallaba se tiraba también la otra.
- Si un tipo falla, se reintenta solo ese.
- Si en 1.2 s no ha llegado nada, también se le pregunta a Trakt (si está configurado). Cinemeta toma su lugar al llegar.
- La búsqueda espera como máximo 4 s por intento (8 s de plazo total). Antes eran 10 s y 20 s de plazo, por intento.
- Las respuestas de Cinemeta se guardan en disco lo que Cinemeta permite (un día), en una sesión aparte sin claves.
  Los complementos siguen sin disco porque sus direcciones llevan claves.
- La conexión con Cinemeta se abre al entrar a Buscar, antes de la primera letra.
- Los nombres en español que ya se conocen se ponen desde el primer momento. Antes salían en inglés y cambiaban al rato.
- Espera tras teclear: 0.3 s → 0.2 s.
- El modelo solo avisa a la vista cuando algo cambió de verdad.

Medido con curl contra Cinemeta: una búsqueda que Cinemeta ya tiene guardada tarda 0.1–0.3 s. Una nueva tarda 0.9–3.3 s,
y a veces responde 504 tras 6 s.

## TV (pendiente, por impacto)

1. **Cinemeta espera mucho y en fila.**
   - Dónde:
     - `orbital/library/cinemeta.py:51`: timeout de 10 s.
     - `orbital/net.py:24`: lee hasta el doble.
     - `orbital/api/media.py:95-110`: reintenta Cinemeta y solo después Trakt.
     - `media.py:87-91`: espera películas y series juntas.
   - Arreglo:
     - timeout corto para búsqueda;
     - cada tipo por separado;
     - Trakt en paralelo si no hay nada en 1.2 s;
     - en el cliente, timeout de unos 8 s (`web/js/core/api.js:64`).
2. **La búsqueda hace fila detrás de los pósters.**
   - Por qué: con HTTP/1.1 hay 6 conexiones por host y `EventSource /api/events` ocupa una. Cada póster va por `/api/img`,
     y en frío espera en `remote_art._slots = BoundedSemaphore(4)` (`orbital/remote_art.py:34`, 72-85).
   - Además, las búsquedas viejas no se cancelan (`web/js/components/search.js:168-183`).
   - Arreglo:
     - `/api/img` en frío responde con un 307 al original y redimensiona en segundo plano;
     - un `AbortController` por tecla;
     - `fetchpriority="low"` en los pósters.
3. **Sin conexiones vivas.**
   - Dónde: `cinemeta.py:102-104` y `remote_art.py:53-56` abren `urlopen` nuevo cada vez.
   - Arreglo: un cliente compartido que mantenga las conexiones, y abrir la de Cinemeta al entrar a Buscar.
4. **Cada tecla borra y rehace la fila.**
   - Dónde: `search.js:165-166` (`showResults(local)` quita lo remoto) y `dom.js:40` (`replaceChildren`).
   - Arreglo:
     - mantener lo anterior hasta que llegue lo nuevo;
     - reusar las tarjetas por `item.id`;
     - escribir desde el teléfono con un solo `setText` (`main.js:342`);
     - `scrollLeft` en `requestAnimationFrame` (`search.js:89`).
5. **Imágenes.**
   - Dónde: `orbital/thumbs.py:43-47` codifica WebP dentro del candado global, así que todo va en fila.
   - Arreglo: pedir el póster al ancho real de la tarjeta (unos 320 px a 2×; hoy se piden 480).
6. **Animaciones detrás de Buscar.** El mosaico de Para ti y las estrellas del fondo siguen corriendo. Pausarlos con
   `[data-overlay="true"]` (`main.js:354` ya lo pone).
7. **Arranque (no afecta a la búsqueda).** Unos 66 JS y 40 CSS cargados con `@import`, todos con `Cache-Control: no-cache`
   (`orbital/server.py:217-222`).

Con 1 a 3, la primera respuesta debería quedar en 0.5–1 s, sin los atorones de 10–60 s cuando Cinemeta falla.

## Cuántos resultados (arreglado en el iPhone)

La búsqueda juntaba películas y series alternando y se quedaba con 18. Con los dos tipos de 9 o más, el filtro decía siempre
«Películas 9 · Series 9». El iPhone ya muestra todo lo que contesta Cinemeta. La TV tiene el mismo tope en
`orbital/library/cinemeta.py:292` (`search_results(..., limit=18)`).
