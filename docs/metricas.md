# Métricas de rendimiento de Orbital

Orbital es una consola de TV que comparte la Legion Go con los juegos. Eso decide qué se mide: **que responda al
instante** cuando la usas y **que no gaste nada** cuando no la usas (o cuando un juego o un video están al frente). Lo
segundo pesa tanto como lo primero: cada punto de CPU o GPU que Orbital se queda, se lo quita al juego.

Cada métrica tiene un **presupuesto**: un número que no se debe pasar. `scripts/perf_budget.py` las mide y dice si
cumplen. Se mide siempre igual, para poder comparar antes y después de un cambio.

```bash
# La interfaz con teclas, contra el servidor de demostración (nunca la tele):
python scripts/demo_server.py --port 8737
python scripts/perf_budget.py demo --url http://127.0.0.1:8737/ --out antes.json

# La Orbital de la tele, solo leyendo (GET a la API, CPU, memoria y GPU de sus procesos durante 60 s).
# Aborta si hay algo abierto. Las capturas y los reinicios siguen el candado de la tele.
python scripts/perf_budget.py real --seconds 60 --out tele.json
```

## Cómo leer los números

- **p50 / p95**: la mitad de las veces tarda menos que p50; 19 de cada 20, menos que p95. El p95 es el que se siente:
  un menú que casi siempre es rápido pero a veces se traba se percibe lento.
- **% de un núcleo**: 100 % = un núcleo entero ocupado. La Legion Go tiene 8; aun así, lo que Orbital usa en reposo
  baja los cuadros del juego y la batería.
- **Demo vs. tele**: la demo (Edge sin ventana) dibuja por software, así que exagera la CPU en absoluto; sirve para
  comparar antes y después y para medir la respuesta a botones. El reposo, la GPU y la memoria de verdad se miden en
  la tele.

## Presupuestos

| Familia | Métrica | Presupuesto | Por qué ese número |
|---|---|---|---|
| Respuesta | Botón → cuadro pintado (p50 / p95) | ≤ 50 ms / ≤ 100 ms | 100 ms es el umbral de «instantáneo». La TV ya suma 20–50 ms de retraso propio: Orbital no debe gastar más que eso. |
| | LB/RB → la sección nueva pintada (p95) | ≤ 150 ms | Cambiar de sección es un salto grande: se tolera un poco más, sin pasar de lo que se nota como espera. |
| | A → la ficha a la vista (datos locales) | ≤ 300 ms | Abrir algo puede tardar un poco si hay una entrada animada; más de 300 ms se siente como carga. |
| | Tareas de más de 50 ms al moverte | 0 | Una tarea larga congela el foco: el mando «se pega». |
| Arranque | Abrir → Inicio usable | ≤ 2,5 s | Lo que tarda la animación de entrada más un margen; con la biblioteca en caché no debería esperar a nada. |
| | Peticiones a la API en los primeros 8 s | ≤ 25 | Cada petición compite con el Inicio; lo que no se ve todavía puede esperar. |
| Reposo | Página quieta, cualquier sección (demo) | ≤ 2 % de un núcleo | Quieta no hay nada que dibujar: lo que se gaste es trabajo de más. |
| | Servidor quieto (tele) | ≤ 1 % de un núcleo | Solo atiende sondeos y eventos. |
| | Edge de Orbital quieto (tele, todos sus procesos) | ≤ 3 % de un núcleo | Medido el 20 oct, tras quitar el fondo animado: 3 % es alcanzable. |
| | GPU de Orbital quieta (tele) | ≤ 3 % | Ídem (antes del arreglo del 20 oct llegó a 38 %). |
| | Con un juego al frente | ≈ 0 y ningún proceso nuevo por minuto | Nadie mira Orbital: los sondeos esperan. |
| Memoria | Vigilante (supervisor) | ≤ 20 MB | Solo abre y vigila al servidor. |
| | Servidor | ≤ 250 MB | Biblioteca, cachés de arte y listas. |
| | Memoria JS de la página | ≤ 60 MB | Y que no crezca con las horas (eso es una fuga). |
| API local | `status`, `ui`, `settings`, `library` (p95) | ≤ 50 ms | Datos en memoria: no hay excusa para más. |
| | Una lista de Películas y series en caché (p95) | ≤ 300 ms | Puede armar portadas y calificaciones; sin red. |
| | Esa lista en frío, con red | ≤ 1,5 s | Depende de TMDB/Trakt; se pide antes de que la veas. |

**Acciones largas**, que se miden aparte (registro de la tele, todavía sin automatizar):

| Acción | Presupuesto | Nota |
|---|---|---|
| A en un juego → pantalla de carga | ≤ 100 ms | Es respuesta a un botón: la pantalla de carga debe salir ya, aunque el juego tarde. |
| Pantalla de carga → juego al frente | Se registra, sin presupuesto fijo | Depende del emulador y del juego; sirve para ver si un cambio lo empeora. |
| A en un video → primer cuadro (p50 / p95) | ≤ 3 s / ≤ 6 s | Con la fuente en caché. Una fuente nueva puede tardar más: lo dice la pantalla de carga. |

## Línea base (29 de octubre de 2026)

**La tele, a mediodía, sin nadie usándola** (`real`, 60 s, solo lectura; estaba en Para ti, en ambiente):

| Métrica | Medido | Presupuesto | |
|---|---|---|---|
| Edge de Orbital, CPU | 82 % de un núcleo | ≤ 3 % | ✗ |
| GPU de Orbital | 36 % (máx. 38 %) | ≤ 3 % | ✗ |
| Servidor, CPU | 9,7 % de un núcleo | ≤ 1 % | ✗ (sirve las imágenes de las piezas que van llegando) |
| Vigilante | 43 MB | ≤ 20 MB | ✗ |
| Servidor | 154 MB | ≤ 250 MB | ✓ |
| `status`, `ui`, `settings` (p95) | 17–27 ms | ≤ 50 ms | ✓ |
| `library` (p50 / p95) | 44 / 190 ms | ≤ 50 ms | ✗ en p95 |
| Listas de Películas y series en caché (p95) | 16–33 ms | ≤ 300 ms | ✓ |

**La demo, antes y después de la auditoría** (rama `claude/auditoria-rendimiento`, mismo script y misma máquina):

| Métrica | Antes | Después | Presupuesto |
|---|---|---|---|
| Peticiones en los primeros 8 s | 96 | 19 | ≤ 25 |
| Arranque | 1,35 s | 1,35 s | ≤ 2,5 s |
| Botón → cuadro (p50 / p95) | 17 / 24 ms | 17 / 24 ms | ≤ 50 / 100 ms |
| Cambio de sección (p95) | 167 ms | 154 ms | ≤ 150 ms ✗ |
| Abrir la ficha (p50 de 5) | 32 ms | 35 ms | ≤ 300 ms |
| Tareas de más de 50 ms al recorrer todo | 1 (196 ms) | 1 (208 ms) | 0 ✗ |
| Para ti quieto, segundos 0–10 | 41 % | 25 % | (deriva a propósito) |
| Para ti quieto, segundos 100–110 | 29 % | **0,9 %** | ≤ 2 % |
| Inicio · Juegos · TV quietos | 1,7 · 1,6 · 1,4 % | 1,9 · 1,2 · 1,3 % | ≤ 2 % |
| Películas y series quieta | 3,7 % | 3,4 % | ≤ 2 % ✗ (el carrusel de Destacados avanza cada 8 s) |
| Memoria JS · nodos | 4,3 MB · 4.306 | 4,3 MB · 2.794 | ≤ 60 MB |
| Vigilante (lo que importa) | 42,9 MB | 16,4 MB | ≤ 20 MB |

Pendiente de medir en la tele cuando la rama esté en `main`: el reposo real de Para ti y la GPU.

**Lo que sigue fuera de presupuesto:** la tarea larga de ~200 ms (al entrar a una sección pesada), el cambio de sección
justo encima de 150 ms, Películas y series quieta por el carrusel, y el p95 de `/api/library` en la tele.

## Lo que falta medir

- **Respuesta con uso real.** La demo mide botones simulados. Para el p95 verdadero, la interfaz puede anotar en la tele
  cuánto tarda cada botón en pintarse (ya manda una traza de entrada al servidor, `entrada.log`) y un resumen diario
  diría el p50 y el p95 de uso real.
- **Lanzar un juego y el primer cuadro de un video**, con la hora de cada paso en `orbital.log`.
- **Horas encendida**: memoria del servidor y de la página cada hora, para encontrar fugas.
