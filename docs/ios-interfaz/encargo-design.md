# Encargo para Claude Design: pantallas de Orbital para iPhone

Pega este texto completo en una sesión nueva de Claude Design (claude.ai/design). Es el contexto
entero: no hace falta nada más.

---

## Qué quiero

Presenta las pantallas de **Orbital para iPhone** en un lienzo de diseño: cada pantalla es un cuadro
independiente, colocados uno junto al otro, agrupados en filas con un título por fila, para
recorrerlos y compararlos. Tamaño iPhone 390 × 844; el reproductor en horizontal, 844 × 390.
Todo en español. Pósteres de color liso como marcadores (no hace falta arte real).

Después iremos rebotando pantallas en ese lienzo: yo te diré qué cambiar y tú ajustas.

## Qué es la app

Orbital es una interfaz de consola para la TV (Windows, con mando) que reproduce películas y series
con los complementos de Stremio y Real-Debrid. Esta es su **app compañera para iPhone**: solo
multimedia (películas y series, sin juegos), funciona por sí sola, y lo que ves en el iPhone aparece
en la TV y al revés, porque **la cuenta de Stremio es el eje** (biblioteca, avance, Mi lista).
Trakt cuelga de eso: la app lee tu watchlist, listas y recomendaciones de Trakt, y avisa a Trakt de lo
que reproduces (scrobble). Uso personal, no va a la App Store.

Reproductor propio dentro de la app (AetherEngine), con descargas para ver sin conexión y un botón
«Abrir en Infuse» de respaldo para archivos difíciles.

## Identidad visual (la misma que Orbital en la TV)

- Grafito oscuro. **Fondo** `#0c0c0e`; **superficies** `#131316` y `#18181c`; **tarjetas** `#1e1e23`;
  **línea fina** `rgba(255,255,255,.09)`; **relleno de botón secundario y chip** `rgba(255,255,255,.10)`.
- **Texto** `#f5f4f0`; **secundario** `#a3a3ab`; **tenue** `rgba(255,255,255,.5)`.
- **Botón principal**: fondo `#f5f4f0`, texto `#070708`. Nada de azul de acento.
- **Acentos solo para estados**: `#5fd6c6` verde azulado (listo, visto, al instante), `#f4c24d` ámbar
  (aviso), `#f0574d` rojo (error). Barra de avance clara (`#f5f4f0`) sobre `rgba(255,255,255,.2)`.
- El **fondo de cada pantalla toma el tono del póster** del título enfocado, muy oscurecido.
- Radios: tarjetas 10 px, botones 13 px, chips píldora. Tipografía del sistema (SF). Títulos grandes
  con peso 700. **Sin mayúsculas espaciadas** nunca.
- Etiquetas (badges) sobre arte: placa oscura `rgba(7,7,8,.8)` con texto claro: «Recomendada»,
  «Sin estrenar», «En tu lista», «Seguir viendo».

## Navegación

Barra de pestañas abajo, **cuatro**: **Inicio · Para ti · Ver · Descargas**. Buscar vive arriba de
«Ver». Ajustes en el avatar de Inicio. Arriba a la derecha, un estado discreto: «Stremio al día» o
«3 cambios por subir».

## Filas del lienzo y pantallas

### Fila 1 · «Lo esencial»

**1. Inicio.** Marca «Orbital» arriba a la izquierda; a la derecha el estado «Stremio al día» y el
avatar. Destacado grande con el arte del título y etiqueta «Seguir viendo»: **Severance**,
«Temporada 2 · Episodio 5 · te quedan 31 min», barra de avance al 46 %, botones **Continuar**
(principal) · Descargar · Más. Debajo: fila **«Mi lista»** (pósteres: Dune: Parte dos, The Bear, Andor)
y fila **«Pendientes en Trakt»** (tu watchlist).

**2. Ficha.** Arte grande arriba que se funde con el fondo; título **Severance** (34 px, 750);
«2022 · Ciencia ficción · 2 temporadas · 8,7». Botones **Continuar T2 E5** (principal) · + Mi lista ·
Descargar. Interruptor «En tu watchlist de Trakt» (encendido). Sinopsis de dos líneas. Chips
«Temporada 1 · Temporada 2» (la 2 activa). Lista de episodios, cada uno con miniatura, número y
nombre, y su estado: «4 · Alguien está vivo — 52 min» con ✓ verde azulado (visto); «5 · Trojan's
Horse — Te quedan 31 min» con barra al 46 % y botón de descarga; «6 · Attila — 49 min · Descargado»
con ícono verde.

**3. Fuentes (hoja inferior sobre la ficha atenuada).** Asa arriba. Título «Severance · T2 E5»,
subtítulo «Fuentes de Real-Debrid · recomendada arriba». Selector **Ver | Descargar** (Ver activo).
Cuatro filas, la primera resaltada con borde claro:
- **1080p · Español latino · x265** — chips: «Recomendada» (verde azulado), «2,1 GB», «HDR», «Al instante» (verde azulado)
- **2160p · Inglés + subtítulos · REMUX** — «34 GB» (ámbar), «Dolby Vision», «Atmos»
- **1080p · Inglés · WEB-DL** — «3,4 GB», «Subtítulos es»
- **720p · Español · WEB** — «0,9 GB»
Nota abajo: «En datos móviles te avisamos antes de usar fuentes de más de 5 GB».

**4. Reproductor (horizontal, 844 × 390).** Video a pantalla completa, controles sobre un degradado.
Arriba: ‹ atrás, centro «Severance / T2 · E5 · Trojan's Horse», a la derecha PiP y ⋯. Centro:
−10 · **Pausa** (grande) · +10. Abajo: barra de avance con tirador, «24:12» y «−27:48», chips
«Español · AC3 5.1», «Subt. es», «1×». **Panel lateral derecho «Audio y subtítulos»**: Audio →
«Español latino · AC3 5.1» ✓, «Inglés · EAC3 Atmos»; Subtítulos → «Español (forzados + completos)» ✓,
«Inglés», «Sin subtítulos»; «Retraso de subtítulos 0,0 s»; Más → «Otra fuente…», **«Abrir en Infuse ↗»**.
Gestos (ponlos como nota bajo el cuadro): un toque muestra controles; doble toque a los lados ±10 s;
arrastrar busca; bloqueo de pantalla.

### Fila 2 · «Para ti»

Selector arriba **Mosaico | Listas**.

**5. Para ti · Mosaico.** Igual al de Orbital en la TV: **tres columnas de imágenes** a distintas
alturas (pósteres altos y algún arte ancho), **solo series y películas, sin juegos**. La columna
enfocada es más ancha y su pieza enfocada crece y muestra: etiqueta «Recomendada», ícono de
esquina (serie o película), título **Shōgun** grande y un dato «2024 · 8,7 · 1 temporada». Las demás
piezas van sin texto. Deslizar sube todo; quieto un rato, entra en ambiente y se mueve solo.

**6. Para ti · Listas · Trakt.** Chips de fuente deslizables: **Todo · Trakt · Netflix · Disney+ ·
HBO Max** (Trakt activo). Estado «Trakt al día» arriba a la derecha. Subselector **Watchlist · Tus
listas · Viendo · Recomendadas · Tendencia · Popular**. Rótulo «Tuyo · 24 pendientes» y cuadrícula de
3 columnas (Severance, Dune: Parte dos, Andor, Shōgun, Oppenheimer, Past Lives), cada póster con
etiqueta «En tu lista». Más abajo rótulo «Descubrir · En tendencia» con otra cuadrícula.
Si Trakt no está conectado: una tarjeta «Conecta Trakt» en vez de la lista.

**7. Para ti · Listas · plataformas.** Chip «Todo» activo. Encabezado «Popular en tus plataformas ·
México». Un riel por plataforma con su logo cuadrado, nombre y «Lo más popular»: **Netflix**
(Adolescence, Stranger Things, Wednesday), **Disney+** (Andor, Ahsoka, Daredevil), **HBO Max** (The Last
of Us, Succession, Hacks). Interruptor **Series | Películas** arriba.

### Fila 3 · «Sin conexión y extras»

**8. Descargas.** Título «Descargas», chip «Solo con Wi‑Fi». Tarjeta «Ocupan 14,8 GB · 52 GB libres»
con barra. Sección **«Descargando · 1 de 2»**: Severance · T2 E5, barra al 64 %, «1,3 de 2,1 GB · 12
min», botón pausa; Dune: Parte dos, «En cola · 3,2 GB», botón ✕. Sección **«Listas para ver · Sin
conexión»**: Andor · T1 E1–E3, «3 episodios · 4,5 GB», chip verde azulado «Siguiente se descarga al
terminar».

**9. Reproductor · Siguiente episodio.** Igual al reproductor, con el video al final (créditos) y,
abajo a la derecha, una tarjeta «Siguiente episodio: T2 E6 · Attila» con miniatura, cuenta atrás
«Empieza en 8 s» y botones **Ver ahora** · Cancelar.

**10. Ajustes.** Lista agrupada: Cuenta (Stremio: fernando@…, Trakt: @fernando, Real-Debrid vía
complementos); Idioma de la app (Español | English); Audio preferido (Español latino); Subtítulos
(Español, Solo forzados); Calidad al transmitir (Hasta 1080p en datos, Máxima en Wi‑Fi); Descargas
(Solo con Wi‑Fi, Reponer el siguiente episodio); Reproductor (AetherEngine, Abrir en Infuse por
defecto: no).

## Variantes para comparar (opcional, si da tiempo)

Como una fila extra «Direcciones para Inicio»: **A · Destacado fijo** (la de arriba), **B · Carrusel**
de hasta 5 títulos en «Seguir viendo», **C · Lista compacta** sin destacado (filas de miniaturas
anchas con barra de avance).

## Conexiones entre cuadros

Flechas finas: cada pestaña → Ficha; Ficha → Fuentes; Fuentes → Reproductor (Ver) o → Descargas
(Descargar); Descargas → Reproductor (ver sin conexión); Reproductor → «Abrir en Infuse» (app externa).

## Reglas para el rebote

- Español, frases normales, nada de mayúsculas espaciadas.
- No inventes funciones nuevas sin marcarlas como propuesta.
- Si algo no cabe en 390 px, el texto se corta con «…» en una línea; nunca se sale del cuadro.
