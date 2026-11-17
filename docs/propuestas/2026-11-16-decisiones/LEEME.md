# Lo que Fernando tiene que decidir · TV (16 nov 2026)

Encargo de la sesión de la TV: un **Canvas** con las decisiones pendientes. Nada de esto está construido. Fernando contesta
por ID («PS-1 sí, CO-2 no»). Va por pantalla; en cada una, «Hoy» y «Propuesta» lado a lado cuando hay maqueta, los
recuadros rojos con su ID y abajo qué cambia, en una o dos frases. Al final, «Opcionales» y «Sin marca en pantalla». Que se
lea en el teléfono.

Las imágenes miden 1280×720. Los recuadros vienen en coordenadas de 1920×1080 (`[x, y, ancho, alto]`): multiplica por 2/3
para las `.jpg`, o úsalos en porcentaje (x/19.2 %, y/10.8 %).

## 1 · Películas y series: la fila de arriba (PS)

| Imagen | Qué es | Recuadros |
| --- | --- | --- |
| `ps-hoy.jpg` | Hoy | «Texto sin ícono» [61, 139, 338, 54] · «Solo ícono; se estira al enfocar» [677, 139, 190, 54] |
| `ps-propuesta.jpg` | Propuesta | PS-1 [61, 139, 450, 54] · PS-2 [791, 139, 673, 54] · PS-3 [995, 147, 40, 38] |

- **PS-1 · «Todo», «Películas» y «Series» con su ícono**: cuadrícula, claqueta y pantalla, los mismos del iPhone. La
  elegida sigue con su raya.
- **PS-2 · Guardado, Colecciones y Filtro avanzado con su nombre siempre**, como ya lleva «Decide por mí»: misma letra,
  mismo ícono, mismo foco; ya no se estiran al enfocarlos.
- **PS-3 · Colecciones con un ícono de pilas** en lugar del trofeo (el trofeo se lee «Premios»).

## 2 · Subir hasta arriba (PS-4)

| Imagen | Qué es | Recuadros |
| --- | --- | --- |
| `ps4-hoy.jpg` | Hoy, en una fila de abajo | PS-4 [377, 1004, 125, 40] |

- **PS-4 · B ya sube a la primera fila, pero el pie dice «Atrás».** Propuesta: que diga «Subir» cuando no estás arriba, y
  que en las listas (Guardado, un género) B también suba antes de cerrar.

## 3 · Colecciones (CO)

| Imagen | Qué es | Recuadros |
| --- | --- | --- |
| `co-hoy.jpg` | Hoy (demo, sin Trakt) | CO-1 [207, 471, 512, 136] · CO-2 [745, 506, 64, 64] |
| `co-cargando.jpg` | Hoy, la primera vez con tus datos | CO-3 [776, 262, 370, 125] |

- **CO-1 · La enfocada crece y se encima con la de al lado.** Propuesta: el foco de siempre, sin agrandarla.
- **CO-2 · Todas llevan el mismo trofeo en un círculo.** Propuesta: cada premio con su estatuilla (ya existe en la lista
  del Óscar); las listas, su logo.
- **CO-3 · La primera vez, más de 8 s solo con «Contando lo que viste…».** Propuesta: las tarjetas ya, y el «0 de 27»
  llega cuando termina de contar.

## 4 · Filtro avanzado (FA)

| Imagen | Qué es | Recuadros |
| --- | --- | --- |
| `fa-hoy.jpg` | Hoy | FA-1 [411, 225, 1100, 570] |
| `fa-referencia-filtros.jpg` | Referencia: el panel «Filtros» de «Decide por mí», ya construido | — |

- **FA-1 · Filtro avanzado es una lista de renglones con ‹ valor ›, que no usa ninguna otra pantalla.** Propuesta: el mismo
  panel de vidrio que «Filtros» de «Decide por mí»: cada pregunta (Formato, Género, Época, Calificación, Fama, Dónde verla,
  País) en su renglón de píldoras, ✓ en lo elegido, y abajo «Ver 592 títulos». Así los dos filtros de Películas y series se
  ven y se manejan igual.

## 5 · Opcionales

| Imagen | Qué es | Recuadros |
| --- | --- | --- |
| `estrellas-hoy.jpg` | El aviso al calificar, hoy | OP-1 [1573, 123, 270, 90] |

- **OP-1 · El aviso «Oppenheimer · ★★★★» al calificar, con las estrellas en ámbar** (como ya van en la hoja y en el iPhone).
- **OP-2 · «Control GameSir conectado · Jugador 1» sin la marca**: «Control conectado · Jugador 1» (el de desconectado ya
  no la lleva).
- **OP-3 · «Quedan N» en el panel «Filtros»** de «Decide por mí»: hoy dice «Al cerrar, elijo otras tres con esto»; contar
  cuántas quedan pide un cambio en el servidor.
- **OP-4 · Insignias de botón más grandes en toda la app** (AD-13): las letras Y/X pegadas a los botones redondos miden
  unos 20 px; subirlas a 28 px se lee mejor a 3 m, pero cambia todos los botones.

## Sin marca en pantalla

Recomendación de la sesión de la TV: **PS-1, PS-2, PS-3, PS-4, CO-1, CO-3, FA-1 y OP-1** (consistencia y cosas que hoy se
ven rotas o lentas). CO-2 vale la pena si hay estatuillas para todos. OP-3 solo si la cuenta importa. OP-4 conviene verlo en
la tele antes.

Ya hecho hoy y por comprobar con el mando en la tele (no hay que decidir): R3 para «Decide por mí», el aviso nuevo de
calificar, el «Cargando…» del reproductor y «Se desconectó el control».
