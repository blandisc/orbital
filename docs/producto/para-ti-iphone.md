# Para ti en el iPhone: brief de UX/UI (rework de Listas, mosaico fluido, widget)

Objetivo del usuario: **descubrir qué ver tiene que ser fácil, bonito y agradable.** Hoy el mosaico tiene la
firma de la consola pero se traba, y Listas es «chips de texto + cuadrícula», que no invita a explorar.

## 1. Diagnóstico de Listas (hoy)

- Una fila de chips (Todo · Trakt · Netflix · Disney+ …) y una cuadrícula plana debajo: todo pesa lo mismo,
  no hay historia ni jerarquía, y hay que tocar un chip para saber qué hay.
- El puesto del Top 10 se ve como insignia pequeña; en Netflix el número ES la pieza.
- No se explica por qué se sugiere algo («Porque viste…», «En tendencia esta semana»).
- Series · Películas es un selector global que cambia todo de golpe.

## 2. Principio de diseño

**Listas es un feed de estantes** (como el Inicio de Netflix o la pestaña Ver de Apple TV): se desplaza en
vertical, cada estante se desplaza en horizontal, y cada estante dice *de dónde viene y por qué*. El mosaico
sigue siendo el modo «sin pensar»; Listas es el modo «elijo yo». Mismo vocabulario y mismas listas que la
consola (`/api/foryou`), sin calcular nada nuevo en el iPhone.

## 3. Estructura de Listas (de arriba abajo)

| Estante | Pieza | Detalle |
|---|---|---|
| **Destacado «Para ti hoy»** | `FeatureTile` (la misma del Inicio) | Una sola sugerencia: arte a sangre, logo del título, etiqueta con la razón («Recomendada por Trakt», «N.º 1 en Netflix»), botón «Ver» y «Más». Rota al refrescar. |
| **Selector Series · Películas** | `Picker` segmentado nativo, pegado arriba al desplazar | Solo filtra los estantes que tienen `split`. |
| **Lo tuyo** (solo si Trakt está conectado) | Estante `Shelf` con `PosterCard` | Watchlist y «Tus series» en un solo estante, encabezado con ícono de Trakt y «Lo que dejaste pendiente». |
| **Top 10 en Netflix** | `Shelf` **con número grande** a la izquierda de cada póster (estilo Netflix: cifra enorme en gris, póster encima a la derecha) | Encabezado con logo de Netflix y «Esta semana en México». |
| **Lo más visto en Disney+ / HBO Max / Prime Video / Apple TV+ / Paramount+** | `Shelf` con `PosterCard` + puesto discreto | Encabezado con el logo de la plataforma a la misma altura siempre (`DSPlatformLogo`). |
| **En tendencia · Lo más popular** (Trakt o Stremio) | `Shelf` | Encabezado con ícono y dato («Lo más visto esta semana»). |
| **Catálogos de tus complementos** (Prime Video, Apple TV+ de Stremio, Rotten Tomatoes…) | `Shelf` | Encabezado «De <complemento>». |

Reglas:
- Cada encabezado de estante es tocable: abre la lista completa en cuadrícula (la vista de hoy, reutilizada)
  con el mismo título y logo.
- Cada póster: toque = ficha; mantener = menú (Ver, Mi lista, Descargar, En la TV, No me interesa).
- Estantes vacíos no se pintan; una lista que falla se omite sin aviso (igual que la consola).
- Esqueletos de póster mientras carga; nunca «salta» el contenido al llegar.
- Aire inferior para la barra de pestañas; letra grande: los encabezados caben en dos líneas.
- Si no hay consola ni Trakt ni TMDB: Destacado + «Lo más popular en Stremio» + un estante «Conecta
  Trakt o tu Orbital» con una acción (no una tarjeta gris).

## 4. Mosaico: fluidez

Hoy se traba. Causas probables (a verificar con Instruments): imágenes de metahub a tamaño completo sin
reducción ni caché en disco, `TimelineView` reactivando todo el mosaico en cada tick, relayout de todas las
columnas por cada cambio de foco o desplazamiento, 96 piezas vivas a la vez.

Objetivo medible en iPhone real: 60 fps al desplazar y al enfocar, sin saltos al cargar imágenes.
Medidas: reducción de imágenes al tamaño de pieza (`downsample` con ImageIO) + caché en memoria y disco;
las columnas solo reaccionan a su propio foco; el tick del ambiente mueve solo un `offset` (sin recalcular
layout); piezas fuera de pantalla no se renderizan (`LazyVStack` o recorte manual); `drawingGroup` donde
convenga; `Reduce motion` apaga ambiente y acercamiento.

## 5. Widget «Lo siguiente para ti»

Elegido sobre el calendario porque el calendario aún no existe (CEN-22); cuando entre, el mismo widget
enseña «Próximo estreno». WidgetKit, tamaños pequeño y mediano (y bloqueo de pantalla):
- Pequeño: póster del siguiente («Seguir viendo» con avance o, si terminaste, el siguiente episodio),
  logo o título, «T2 · E6» y «quedan 20 min». Tocar abre el reproductor en ese episodio (`orbital-ios://play?…`).
- Mediano: el siguiente + dos más de «Seguir viendo» en renglones.
- Datos: el app escribe un `WidgetSnapshot` en el App Group al refrescar Inicio; el widget nunca llama a
  la red. Recarga con `WidgetCenter` al terminar algo o al cambiar la lista.
- Mismos tokens y piezas (`PosterCard`, `Progress`), fondo con el tinte del arte.
