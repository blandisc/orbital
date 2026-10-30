# Inicio del iPhone: benchmark y propuestas (29–30 oct 2026)

- `tres-opciones.html`: benchmark de apps de streaming y de seguimiento tipo Trakt, y tres opciones
  (1 «Tu tablero», 2 «Portada con tu lugar», 3 «Elige por mí»). Canvas: https://claude.ai/artifact/9LZn3FXan8J1NT5yt334aY
- `combinada.html`: lo que pidió Fernando el 30 oct, la opción 2 con lo útil de la 1. Portada de borde a borde,
  «Seguir viendo» encimado en su borde, «Lo nuevo de lo tuyo» («Ya salió» + «Sale pronto» en una línea de tiempo
  con la marca HOY) y el selector Todo · Series · Películas como tres íconos en la barra (sin cápsulas de texto).
  Maqueta interactiva con el arte real: https://claude.ai/artifact/RWJ6tgdTH6mqVAKoTW24b6
  El arte (`img/`) vive solo en el Canvas, no en el repo; abierto desde aquí, el HTML sale sin imágenes.

El Inicio sigue en pausa: son propuestas, no hay código.

## Decisiones de Fernando (30 oct)

- Inicio, en este orden: portada (tendencias) · Seguir viendo encimado · Lo nuevo de lo tuyo · Sugerencias de Trakt ·
  Por lo que viste (el mazo de Para ti) · Top 10 con el logo y el color de su plataforma · Mi lista.
- Selector Todo · Series · Películas: tres íconos en la barra de arriba.
- El porqué (la línea sobre cada título) va en turquesa, el color de la luna, no en ámbar.

## Para ti (30 oct)

Dos propuestas en Claude Design: https://claude.ai/artifact/BofggKdSbNMJC5guyoFXs3
(`para-ti/A-puertas.dc.html`, `para-ti/B-escaparate.dc.html`; las imágenes viven en el lienzo).
Para ti deja de repetir el Inicio: sin portada, Porque viste, Top 10 ni próximos estrenos.
- A «Puertas»: ¿Qué vemos? arriba, Nuevo en tus plataformas, Aprobadas por la crítica, Colecciones en una cuadrícula,
  Lo que ves y tus listas. El mosaico es un botón de la barra.
- B «Escaparate»: el mosaico como portada, índice de círculos, la temporada del día, ¿Qué vemos? como mazo que se
  desliza, Nuevo en renglones, crítica con su número, álbum de premios y Lo que ves.

### 30 oct: Fernando eligió B y pidió meter todos los cortes

`para-ti/B-completo.dc.html` (artboard «B completo») y `para-ti/inventario.dc.html` (qué hay hoy en Para ti y adónde
va cada cosa). Grupos: Ahora (tendencia, popular, nuevo en tus plataformas, crítica) · Temporadas (la de hoy en grande
+ las otras cuatro) · Plataformas (rankings de las 6 + catálogo de Netflix/Disney+/HBO Max) · Estudios (8) · Premios
(6 + álbum) · Géneros (14) · Años (1980–hoy, por década) · Listas famosas (nuevo: Criterion, Top 250 de IMDb) · Tuyo
(Mi lista, Favoritos, tus series, listas de Trakt) · Lo que ves. Al Inicio se mudan: Porque viste, Recomendadas y
Próximos estrenos. Salen: el Destacado (lo reemplaza el mosaico) y los catálogos de complementos (desacoplar Stremio).

**Inicio cerrado (30 oct, v6):** Fernando dio por cerrada la propuesta del Inicio.

### 30 oct: Para ti interactivo

`para-ti/B-interactivo.dc.html` (el Canvas abre directo en él): Para ti completo que se desplaza, «Pasear por el
mosaico» (muro de pósters; tocas uno y sale su ficha rápida con Ver y Guardar) y «¿Qué vemos hoy?» como Tinder
(arrastras a la derecha para guardar y a la izquierda para descartar, o usas ✕ ▶ ＋; los cuatro ánimos cambian el mazo).
Cada fila lleva el porqué arriba en turquesa y el título abajo, como el Inicio; los grupos son títulos grandes.

### 30 oct: Para ti B, alta fidelidad

Fernando eligió «B completo». Temporadas se elige sola con la fecha: la que corre hoy en grande (o la próxima si no
hay ninguna), con cuántos días le quedan, y las demás por cercanía. Todo se puede tocar en `B-interactivo`: cada fila,
«Ver todo», tarjeta o círculo abre su colección (encabezado con su arte, orden, cuadrícula; los rankings con número),
cada póster abre su ficha rápida y «Lo que ves» abre su resumen. Listas famosas suma «Las 100 del siglo XXI» del
New York Times (2025).
