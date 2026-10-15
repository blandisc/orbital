# Orbital · Diagnóstico de producto y plan (octubre 2026)

Documento del Product Manager. Qué es Orbital hoy, cómo se compara con lo mejor que hay afuera, qué
le falta y en qué orden se ataca. Lo que se verificó en código, pruebas y simulador se dice como hecho;
lo que viene de investigación externa lleva su fuente.

## 1. Resumen ejecutivo

Orbital ya no es «un launcher para la Legion Go». Es **una experiencia multiplataforma de entretenimiento
personal**: la consola en la TV (juegos, películas y series, TV en vivo, voz) y, desde octubre, **la app de
iPhone** (películas y series, reproductor propio, descargas), unidas por la cuenta de Stremio como eje y por
un enlace directo con la consola (QR, «Ver en la TV», claves y sesión de Trakt prestadas).

La base es sólida y rara de ver en un proyecto personal: sistema de diseño verificado por pruebas en las
dos plataformas, lógica compartida probada contra los mismos casos en Python y Swift, y una cultura de
auditorías de UX con el mando. Las tres brechas que separan a Orbital de «lo mejor que hay afuera» son:

1. **Descubrimiento.** Tenemos acceso a todo el catálogo, pero la curaduría es débil: «lo más popular en
   Netflix» hoy es popularidad genérica de TMDB filtrada por plataforma, no el Top 10 real; solo cubre
   Netflix, Disney+ y HBO Max; y en el iPhone se calcula aparte (otra caché, otras claves).
2. **Experiencia conectada.** Existe el cimiento (QR, «Ver en la TV») pero no la sensación de un solo
   producto: el iPhone no sabe qué está pasando en la TV, no la controla, y «Para ti» no es el mismo en los
   dos lados.
3. **Reproductor del iPhone.** Funciona (AetherEngine, PiP, AirPlay, pantalla bloqueada, Up Next) pero
   le faltan los gestos que hacen que Infuse se sienta «de verdad»: brillo y volumen deslizando, buscar
   arrastrando, 2× manteniendo el dedo.

Las tres se atacan en la **ola 1** (ya en marcha, implementada por Sonnet con especificaciones de este
documento). Las olas 2 y 3 quedan como backlog priorizado en Multica.

## 2. Estado actual, verificado

### 2.1 Consola (Windows · Legion Go · TV)

| Área | Estado | Evidencia |
|---|---|---|
| Juegos (Steam, emuladores, ES-DE, GeForce NOW) | Completo y maduro: detección, portadas, favoritos, emulador alternativo, entrar/salir de un juego cubierto caso por caso | `docs/flujos-con-mando.md` (todo ✅ salvo avisos de Windows/Steam) |
| Películas y series (Stremio + complementos + Real-Debrid) | Seguir viendo, ficha, fuentes puntuadas, reproductor mpv con panel de idiomas, Saltar intro, Siguiente episodio, ¿Sigues viendo? | `orbital/player*.py`, `library/streams.py` |
| TV en vivo (M3U México) | Nueva: categorías, salud de canales, modo en vivo en mpv | `docs/tv-en-vivo.md` |
| Para ti | Mosaico + Listas: Trakt, TMDB (3 plataformas), RAWG, complementos de Stremio, juegos locales | `orbital/foryou.py` (703 líneas) |
| Voz (Alexa) | Abrir, buscar, seguir viendo, cerrar, moverse | `orbital/voice.py` |
| Con el dedo / táctil | Reciente: desplazamiento real, reproductor con botones tocables | commits de octubre |
| Sistema de diseño | Tokens + catálogo de 29 componentes; `design-system.test.mjs` bloquea colores, duraciones, capas y letras a mano, tokens sin uso y CSS muerto. **Cero excepciones documentadas** | `docs/sistema-de-diseno.md` |
| Estabilidad | 129 pruebas web en verde; suite Python amplia (robustez, flujos de reproductor, voz, supervisor); CI con pyright y ruff | `node --test`, `pytest` |

### 2.2 iPhone (rama `claude/ios-app-compile-iphone-d6be95`, 141 archivos, ~20 k líneas)

Recorrido en el simulador «Orbital QA» en modo demostración (Inicio, Para ti, Ver, Descargas, ficha,
fuentes, reproductor):

| Área | Estado | Observación del recorrido |
|---|---|---|
| Inicio | Destacado «Seguir viendo» con avance y «quedan 20 min», Seguir viendo, Mi lista, estado «Stremio al día» | Bien. Jerarquía clara, póster a sangre, botón blanco prominente |
| Para ti | Mosaico (sin juegos) y Listas; sin Trakt/TMDB cae a «lo popular de Stremio» con aviso | Bien resuelto el estado vacío. Las listas repiten la lógica de la TV en Swift (`ForYou.swift`) |
| Ver | Buscar + Películas/Series populares (Cinemeta) | **Delgada**: es la pestaña con más potencial de descubrimiento y solo tiene dos filas |
| Ficha | Continuar T2 E5, Mi lista, Descargar, Fuentes, **En la TV**, temporadas, episodios con miniatura y descarga por episodio | Muy completa. La sinopsis sale en inglés si no hay clave de TMDB |
| Fuentes | Hoja con Ver/Descargar, recomendada arriba, chips (Al instante, tamaño, HDR) | Igual que la TV: misma puntuación |
| Reproductor | Horizontal, PiP, AirPlay, pantalla bloqueada, subtítulos, Up Next, Saltar intro, pellizcar para llenar, doble toque ±10 s | **Faltan gestos de Infuse** (ver §3) |
| Descargas | Cola, espacio, Solo con Wi-Fi, Actividad en vivo / Dynamic Island, reanudación con enlace nuevo de Real-Debrid | Estado vacío correcto |
| Conexión con la consola | QR en la TV (Ajustes › Cuentas › iPhone), «Ver en la TV», claves de TMDB/Trakt y sesión de Trakt prestadas por el puerto público | Cimiento correcto; falta el camino de vuelta (TV → iPhone) |
| Sistema de diseño | Componentes nativos de iOS 26 (Liquid Glass), tokens desde `palette.json`, `DesignTests` impide estilos propios; 2 excepciones documentadas | Coherente con la TV sin copiarla: decisión correcta |
| Estabilidad | `swift test`: **142 pruebas en verde** (OrbitalCore); modelos probados con motor y red falsos; valores de referencia generados desde Python (`scripts/ios_golden.py`) | Sin probar aún contra Infuse, Real-Debrid y Trakt reales (lo dice su README) |

**Deuda que encontré:** la rama de iOS no está en `main` (esta evaluación la junta); en Mac el Python
usa `.venv/Scripts/python` de Windows en las instrucciones; `tests/test_alexa.py::test_ensure_token_keeps_comments`
falla en Mac (pendiente confirmar si es solo de plataforma).

## 3. Benchmark: lo mejor que hay afuera

| Producto | Lo que hace mejor que Orbital | Lo que Orbital hace mejor |
|---|---|---|
| **Infuse** (Apple) | Reproductor: gestos (brillo izquierda, volumen derecha, 2× manteniendo, tiempos de salto configurables), calidad de decodificación, biblioteca cuidada | Orbital trae fuentes (Real-Debrid) y descubrimiento; Infuse solo reproduce lo que ya tienes |
| **Plex** | Descover/Watchlist universal, «qué hay en tus servicios», control remoto de otra pantalla desde el teléfono (Plex Companion) | Plex ya cobra por streaming remoto y es pesado; Orbital es tuyo y gratis |
| **Stremio 5** | Calendario de estrenos por serie, guía de TV en vivo en Discover, Continue Watching sincronizado | Orbital tiene juegos, voz, TV y mejor reproductor en la TV (mpv con panel propio) |
| **Nuvio** (open source, Stremio addons) | Perfiles, sincronización delta entre dispositivos, 500+ plugins propios | Orbital tiene sistema de diseño serio, pruebas y la consola; Nuvio es la referencia a vigilar para iOS |
| **Netflix / Apple TV app** | Curaduría editorial, Top 10 oficial por país, «porque viste X», tráilers en el destacado | No aplica: ellos son el catálogo; Orbital puede agregarlos |

**Hallazgos de datos para descubrimiento** (son los que cambian el juego):

- **Netflix publica su Top 10 oficial por país cada semana en un TSV abierto**
  (`https://www.netflix.com/tudum/top10/data/all-weeks-countries.tsv`, ~90 países, desde 2021, rango por
  semana, categorías Films/TV). Esto es «lo más visto en Netflix México» de verdad, no popularidad de TMDB.
- **JustWatch** expone (sin documentar) un GraphQL público con `popularTitles` filtrable por país y
  por plataforma, con ids externos (TMDB/IMDb). Cubre Disney+, HBO Max, Prime Video, Apple TV+,
  Paramount+, etc. Hay clientes de referencia (`simple-justwatch-python-api`). Riesgo: puede cambiar sin
  aviso; se trata como fuente opcional con caché larga y caída silenciosa.
- **Trakt** tiene `trending`, `popular` y `watched/weekly` (ya usamos los dos primeros). Las cuentas
  gratuitas quedan limitadas a **una app comunitaria conectada**; por eso prestar la sesión de la consola
  al iPhone (ya hecho) es la decisión correcta.

## 4. Visión y principios

**Orbital es una sola experiencia: descubres donde estés y ves donde quieras.**

1. **La cuenta de Stremio es el eje**; la consola es el cerebro (claves, caché, curaduría, reproductor
   grande); el iPhone es la ventana de bolsillo y el control.
2. **La curaduría se calcula una vez** (en la consola) y se ve igual en la TV y en el iPhone. El iPhone
   solo calcula por su cuenta cuando no hay consola.
3. **Nada se crea suelto** en ninguna plataforma (ya es regla; se mantiene).
4. **Todo se puede hacer con el mando en la TV y con una mano en el iPhone.**

## 5. Plan por olas

### Ola 1 (ahora; implementa Sonnet, especificación en cada encargo)

| # | Qué | Plataforma | Por qué primero |
|---|---|---|---|
| 1 | **Gestos del reproductor como Infuse**: brillo (mitad izquierda), volumen (mitad derecha), buscar arrastrando en horizontal con burbuja de tiempo, 2× manteniendo el dedo, indicadores sobre el video | iPhone | Pedido explícito; cierra la brecha más visible con Infuse |
| 2 | **Charts reales por plataforma**: Top 10 oficial de Netflix (TSV) y populares de JustWatch por plataforma y país; más plataformas (Prime Video, Apple TV+, Paramount+); listas con número de puesto en Para ti › Listas | Consola (Python + web) | Es el corazón del descubrimiento; una sola implementación sirve a las dos pantallas |
| 3 | **Para ti compartido**: cuando el iPhone está conectado a la consola, sus listas vienen de `/api/foryou` por el puerto público (misma curaduría, misma caché); sin consola, sigue como hoy | iPhone + puerto público | Experiencia conectada de verdad y sin duplicar lógica en Swift |
| 4 | **«Viendo en la TV» en el iPhone**: la consola publica qué reproduce (título, episodio, avance, pausa) y acepta pausa, ±10 s, episodio siguiente, salir; el Inicio del iPhone lo enseña como tarjeta con controles | Consola + iPhone | El camino de vuelta del enlace; lo que Plex Companion hace y Infuse no |

### Ola 2 (siguiente; backlog en Multica)

- «Seguir en el iPhone» desde la TV (Y → opción en el reproductor): el iPhone abre el mismo episodio donde va.
- Pestaña **Ver** del iPhone con las mismas listas de la consola (Top 10, plataformas, géneros) y tráilers.
- Calendario de estrenos de tus series (Cinemeta ya da fechas; Stremio lo tiene).
- «Porque viste X» con Trakt `related` sobre lo último visto.
- Fichas en español sin clave de TMDB (caché de sinopsis en la consola; el iPhone la pide a la consola).
- Juntar la rama de iOS a `main` y CI para `swift test` y `swift build` del app.

### Ola 3 (después)

- Perfiles (quién ve) sobre la misma cuenta de Stremio.
- Widgets de iOS: Seguir viendo y «Viendo en la TV».
- Modo ambiente del mosaico en el iPhone (está en la TV).
- Apple TV (tvOS) con el mismo OrbitalCore.
- Guía de programación para TV en vivo (EPG) y la TV en vivo también en el iPhone (ver y mandar a la TV).

## 6. Criterios de «hecho» para la ola 1

- Pruebas: web (`node --test`), Python (`pytest`), Swift (`swift test`) y guardián del sistema de diseño
  en verde; ruff limpio. Sin excepciones nuevas de diseño sin documentar.
- Cada fuente externa nueva (Netflix TSV, JustWatch) es opcional: si falla, su lista queda vacía y no tumba
  nada; con fixtures grabadas en `tests/fixtures/`.
- Español primero, textos en palabras (sin códigos ni «undefined»), y en el iPhone todo texto en
  `Localizable.xcstrings` (`scripts/ios_strings.py --check`).
- Los gestos del iPhone respetan Reducir movimiento y accesibilidad (los botones siguen existiendo).
