# Boceto: «Lo mejor del género» y «Por temporada» en Buscar

Rama `exp/explorar-genero-temporada`. Es un **prototipo** para ver la idea funcionando en el iPhone, no una función terminada.

## Qué se pidió

Fernando: «Top género, o sea las tops del género, y por estación: por Halloween, por Navidad, por San Valentín».

## Dónde está

En la pestaña **Buscar**, cuando no has escrito nada (la pantalla de exploración: Top 10 de hoy y «Por género»).
Las dos filas nuevas van entre «Lo más popular hoy» y «Por género»:

1. **Por temporada** (primero, porque es lo más «de hoy»).
2. **Lo mejor del género**.

## Qué hace cada fila

**Por temporada.** Una tira de botones con las temporadas (Halloween, Día de Muertos, Navidad, San Valentín, Verano) y,
abajo, los pósters de esa colección. Tocar un póster abre su ficha, como en el resto de la app. La temporada que va hoy
aparece primero y ya elegida: hoy (23 de octubre) es **Halloween**.

**Lo mejor del género.** Una tira de botones con los géneros (Acción, Comedia, Drama, Terror…) y, abajo, los 10 títulos
mejor calificados de ese género, con el número grande al lado de cada póster (el mismo estilo del Top 10 de hoy).
Mezcla películas y series.

## De dónde vienen los datos

- **Lo mejor del género: datos reales.** Se piden a Cinemeta (el catálogo de Stremio que la app ya usa), a su lista
  «mejor calificadas en IMDb» de ese género. Si esa lista no contesta, se usa lo popular del género y se ordena por la
  calificación de IMDb. No hace falta cuenta ni clave.
- **Por temporada: datos de ejemplo.** Los títulos de cada temporada los escribí a mano (por ejemplo, Halloween:
  *Halloween*, *Hocus Pocus*, *Wednesday*, *Beetlejuice*…; los nombres van en inglés). Los pósters sí son los de verdad. En el código está marcado
  como «DATOS DE EJEMPLO».

## Cómo se elige la temporada

Cada temporada tiene fechas fijas que se repiten cada año y no se enciman:

| Temporada | Del | Al |
|---|---|---|
| Halloween | 25 sep | 31 oct |
| Día de Muertos | 1 nov | 10 nov |
| Navidad | 25 nov | 6 ene |
| San Valentín | 25 ene | 14 feb |
| Verano | 1 jun | 31 ago |

Si hoy cae dentro de una, esa va primero. Si cae entre dos (por ejemplo, en abril), va primero **la siguiente en llegar**
(en abril, Verano). Las demás siguen en el orden en que llegan en el calendario.

## Qué es prototipo y qué ya sirve

| Ya sirve (podría quedarse así) | Todavía es prototipo |
|---|---|
| La regla de fechas (pura y con pruebas) | Las listas de títulos de cada temporada (escritas a mano) |
| Pedir a Cinemeta los mejor calificados de un género | Los títulos de «Lo mejor del género» salen en inglés (no se traducen con TMDB) |
| Las filas usan piezas que ya existían (botones nativos `DSChipRow`, Top 10 `RankedPosterCard`, pósters `TitleLink`) | Los textos nuevos aún no están en el catálogo de traducciones al inglés |
| Funciona en modo demostración, sin cuenta | Falta probarlo en un iPhone y con letra de accesibilidad grande (solo se compiló) |
| | No hay «Ver todo» en ninguna de las dos filas |

## Esfuerzo estimado para terminarlo

**2 a 4 días**:

- Listas de temporada reales (½–1½ días): con TMDB (palabras clave «halloween», «christmas», «valentine's day») cuando
  hay clave, o listas que se editen desde la consola, con las de ejemplo como respaldo.
- Traducir los títulos con TMDB, como ya hace «Por género» (½ día).
- Textos al catálogo español/inglés (`scripts/ios_strings.py`) y «Ver todo» con la cuadrícula que ya existe (½ día).
- Revisar en el simulador: varios iPhone, modo claro/oscuro, letra de accesibilidad, VoiceOver; y decidir qué hacer si
  una calificación de IMDb tiene muy pocos votos (½–1 día).

## Para tomar capturas

```bash
xcrun simctl launch booted mx.iracheta.orbital -demo -demo-tab 2 -demo-browse-scroll temporada
xcrun simctl launch booted mx.iracheta.orbital -demo -demo-tab 2 -demo-browse-scroll genero -demo-genre-top Horror
xcrun simctl launch booted mx.iracheta.orbital -demo -demo-tab 2 -demo-browse-scroll temporada -demo-season navidad
```

## Parte técnica (breve)

- `ios/OrbitalCore/Sources/OrbitalModels/Seasons.swift` (nuevo): `MonthDay`, `SeasonalCollection`, `Seasons.ordered(on:calendar:forced:)`
  y `Seasons.current(on:)` (puros, sin SwiftUI), `Seasons.all` (datos de ejemplo) y `GenreTop.rank` (ordena por
  calificación, sin repetidos, sin calificación al final).
- `ios/OrbitalCore/Tests/OrbitalModelsTests/SeasonsTests.swift` (nuevo): temporada por fecha, cruce de año, entre
  temporadas, temporada forzada, que no se enciman y el orden por calificación. **No se corrió** (`swift test`) en esta
  sesión: solo se tenía permiso para compilar la app.
- `Cinemeta.catalog(_:genre:list:)`: nuevo parámetro `list` (por omisión `top`, sin cambio para lo que ya existe);
  `imdbRating` no se guarda en disco.
- `CatalogModel.topRated(genre:)`: pide `imdbRating` de películas y series; si viene vacío cae a `top` y ordena aquí.
  Suposición no verificada en esta sesión (sin acceso a internet): que el catálogo `imdbRating` de Cinemeta acepta
  `genre=`; por eso existe el respaldo.
- `BrowseView.swift`: secciones `seasonal` y `genreTop`, `BrowseChip` (opción de filtro) y `BrowseAnchor` (ids para
  desplazar). La pantalla va dentro de un `ScrollViewReader` para `-demo-browse-scroll`.
- `Support/Demo.swift`: `-demo-genre-top`, `-demo-season`, `-demo-browse-scroll` (solo Debug), documentados en `ios/README.md`.
- Sin estilos propios ni valores sueltos: solo tokens `DS.*` y piezas del catálogo.
