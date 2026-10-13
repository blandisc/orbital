# Interfaz de la app compañera de iPhone (propuesta)

Maqueta: `docs/ios-interfaz/maqueta.html` (se abre en el navegador) y `maqueta.png`. Es una propuesta
visual con la paleta real de Orbital (`orbital/web/styles/palette.json`); los pósteres son marcadores.

## 1. Idea

La app es **Orbital en el bolsillo**: mismo grafito oscuro, el color lo pone el título enfocado, sin
mayúsculas espaciadas, español primero. Hace dos cosas que Orbital en la TV no hace: **ver en el
teléfono** (reproductor propio, descargas) y **consultar tu Orbital** (juegos y «Para ti»).

## 2. Navegación

Cinco pestañas abajo, las mismas secciones que la TV:

| Pestaña | Contenido | De dónde sale |
|---|---|---|
| Inicio | Seguir viendo (destacado), Mi lista, avance de Para ti | Stremio + Orbital |
| Para ti | Mosaico de sugerencias con etiquetas; filtros Todo/Series/Películas/Juegos | Tu Orbital (`foryou`) |
| Ver | Películas y series: buscar, catálogos, ficha | Stremio, Cinemeta, TMDB |
| Juegos | Biblioteca (Steam y emuladores), solo consulta | Tu Orbital |
| Descargas | Cola, espacio, lo disponible sin red | Local |

Buscar vive arriba de «Ver»; Ajustes en el avatar de Inicio (cuenta de Stremio, idioma, audio,
subtítulos, Wi‑Fi/móvil, emparejar con Orbital con QR). Un indicador junto al nombre dice si tu Orbital
responde («en casa» / «Tu PC» / «sin conexión»: entonces Juegos y Para ti muestran la última copia con un aviso).

## 3. Pantallas (ver la maqueta)

1. **Inicio**: destacado «Continuar T2 E5» con barra de avance y botones Continuar · Descargar · Más.
2. **Para ti**: mosaico con etiquetas («Recomendada», «Sin estrenar»…).
3. **Ficha**: Continuar, Mi lista, Descargar (serie o episodio), temporadas, episodios con estado
   (visto ✓ del bitfield de Stremio, a medias, descargado).
4. **Fuentes**: hoja inferior con «Ver / Descargar». Solo fuentes `url` de Real-Debrid. La recomendada
   arranca sola al tocar Continuar; esta hoja es para elegir otra.
5. **Descargas**: espacio usado, cola, listas para ver sin conexión, «reponer el siguiente».
6. **Juegos**: consolas como filtros y cuadrícula; solo lectura en la primera etapa.
7. **Reproductor** (horizontal): toque muestra controles, doble toque ±10 s, arrastre busca, panel único de
   audio y subtítulos (se recuerda por serie), menú ⋯ con «Otra fuente» y **«Abrir en Infuse»**,
   «Siguiente episodio» con cuenta atrás en los créditos.

## 4. Sistema de diseño en Swift (la regla «nada se crea suelto», también aquí)

- Paquete `OrbitalDesign` con **tokens**: `Palette` (los mismos valores de `palette.json`), `Space`,
  `Radius`, `Font` (escala de Orbital sobre Dynamic Type, equivale a «Tamaño del texto»), `Motion`
  (duración y curva; respeta «Reducir movimiento»).
- **Catálogo de piezas** (equivalencia con Orbital): `Chip`, `Badge`, `ProgressBar`, `SectionHead`,
  `PosterCard` (`card`), `FeatureTile` (`tiles`), `EpisodeRow`, `SourceRow` (`sources`), `DownloadRow`,
  `Sheet` (`sheet`), `Toast`, `StatusPill`, `PlayerControls`, `TrackPanel`. Una pantalla solo se arma con
  estas piezas; si falta una, se añade al catálogo.
- **Prueba automática** (`swift test`): los valores de `Palette` coinciden con `palette.json` (misma idea
  que la prueba que ya existe entre `tokens.css` y `player_ui.py`), y ningún archivo de pantalla escribe un
  color, tamaño o duración a mano.
- El fondo toma el tono del título (como `--art-tint`), calculado del póster.

## 4b. Bilingüe

Textos en `Localizable.xcstrings` (es base, en); fichas según el idioma de la app; lo guardado en Stremio
lleva el título original. Audio y subtítulos tienen su propio idioma, separado.

## 5. Decisiones que quedan abiertas

- Si «Ver» y «Para ti» deben fundirse en una sola pestaña (hoy son dos para igualar la TV).
- Si Juegos permite en el futuro lanzar desde el teléfono (hoy solo consulta, por seguridad).
- Estilo del destacado: póster fijo (maqueta) o carrusel.
