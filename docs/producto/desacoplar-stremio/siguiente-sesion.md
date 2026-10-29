# Desacoplar Stremio · traspaso a la siguiente sesión (29 oct 2026)

Lo dejó la sesión «Propuesta desacoplamiento Streamio» (Mac, lanzada desde la app de iPhone) antes de archivarse.

## Dónde está todo

| Qué | Dónde |
|---|---|
| La propuesta completa (resumen ejecutivo arriba; cortes A–D, transición, estudio de precisión con la prueba real) | `docs/producto/desacoplar-stremio-iphone-2026-10-29.md` |
| Resumen ejecutivo + 13 maquetas (HTML de un solo archivo) | `docs/producto/desacoplar-stremio/resumen.html` |
| El mismo resumen publicado como Canvas (versión 2) | https://claude.ai/artifact/E6kErCUU4huy3SjwgfabsS (lo publicó la sesión web «Arquitectura macOS/iPad»; esta no tiene Artifact) |
| Solo las maquetas | `docs/producto/desacoplar-stremio/maquetas.html` y `maquetas.png` |

## Lo que ya decidió Fernando

1. **Trakt es el sincronizador** del avance, lo visto y Mi lista entre el celular y la computadora (y la nube).
   **Stremio queda solo de respaldo**: sigue recibiendo una copia mientras se compara (fases 1 y 2) y se suelta en la 3.
2. El flujo inicial del iPhone **no pide Stremio**. Real-Debrid y Trakt son obligatorios; Stremio se ofrece al final.
3. Solo Real-Debrid (con el protocolo listo para otros servicios).
4. Respaldo a Trakt cada 5 min mientras se reproduce: `start` y, 2 s después, `pause`.
5. Visto al **90 %**: hasta el 90 % o los créditos, a Trakt se le manda como mucho 79.9 %.
6. Los complementos se importan de Stremio una vez; no se escriben de vuelta.

## Lo que se probó el 29 oct (cuenta real, desde la Lenovo)

- La pausa de Trakt funciona. Guarda 2 o 3 decimales y pide al menos ~1 % (por debajo contesta 422 `progress_too_low`).
- `start` borra la pausa guardada. Una pausa repetida actualiza el avance pero **no** mueve `paused_at`.
- El 80 % de Trakt marca visto y borra el avance.
- **Ida y vuelta confirmada:** la consola dejó una película al 37.5 %, el iPhone arrancó ahí al darle «Ver», y al
  pausar escribió 45.098 %, que la Lenovo vio al momento.
- **Hueco encontrado:** en el iPhone, «Seguir viendo» y la ficha solo leen la biblioteca de Stremio
  (`HomeModel.loadLibrary`); Trakt solo se lee al reproducir (`WatchService.resumePoint`). La película no apareció en
  el Inicio. Lo resuelve el corte A.
- La cuenta quedó limpia (se pidió borrar el último avance de prueba a una sesión de la Lenovo).

## Lo que Fernando pidió para la siguiente sesión

1. **Revisar el plan otra vez**, con ojos frescos, y confirmarle en un resumen corto:
   - que Trakt va a ser el mecanismo de sincronización entre el celular y la computadora, y Stremio solo respaldo;
   - qué hace falta **del lado de la computadora** (la consola en la Lenovo) para que eso sea cierto. El alcance
     original era solo iOS, pero la sincronización celular ↔ computadora toca las dos. Hoy la consola ya retoma desde
     lo más reciente entre Stremio y Trakt al reproducir (commit 6dfea233; `orbital/watch.py` `resume_position`); falta
     ver de dónde arma su «Seguir viendo».
2. **Que «Stremio» ya no aparezca en el celular, sin perder contenido.** El inventario de lugares ya está en la
   propuesta (§4, corte D); hay que revisarlo y completarlo. Lo que dijo Fernando:
   - Se vale perder «Mi lista» de Stremio en el Inicio: pasa a la watchlist de Trakt.
   - **No** se vale perder «Lo más popular hoy» de Buscar (hoy es el top de Cinemeta): hay que reemplazarlo con otra
     fuente. Candidatas: Trakt `trending` o `watched/weekly`, TMDB `trending` (si hay clave), los Top 10 y JustWatch
     que ya trae la consola. Recomienda una con el porqué.
   - «Listas de Stremio» (los catálogos de complementos y de Cinemeta) también tienen que dejar de decir Stremio.
   - Si encuentras otro lugar con contenido de Stremio que se perdería, dilo.
3. **Rotten Tomatoes en Para ti:** ver si se pueden consumir públicamente las listas «Certified Fresh» (películas) y
   las series «Fresh», y agregarlas como sección en Para ti. Rotten Tomatoes no tiene API pública oficial. Revisa
   opciones como sus páginas de exploración, listas de Trakt que las copian, MDBList o un complemento. El código ya
   menciona una lista llamada «RT: Certified Fresh» como ejemplo de lista de Trakt o de complemento
   (`orbital/foryou.py` L251 y L523, `ListsView.swift` L499): averigua de dónde viene. Di qué es estable, qué es raspado
   (scraping) y qué riesgo tiene.
4. **Corrección (esta sí se construye ya):** en Para ti, en «Recomendadas», los pósters dicen «N.º 1 en Disney+»,
   «N.º 2 en Prime Video», «N.º 8 en …» en texto. Fernando quiere una **píldora mucho más chica y gráfica, con el
   ícono del servicio**, como se hizo en la app de escritorio (commit 48293874, «Para ti: «N.º 1 en Netflix» en la
   píldora de su plataforma, con su logo»; ver `orbital/web/js/components/card.js` y `styles/components/card.css`).
   En el iPhone el texto sale de `badgeText` (`App/Sources/Screens/ParaTiPieces.swift` L70–73) y pasa a `TitleLink`.
   Ya existe `DSPlatformLogo`. Pieza nueva al catálogo, nada suelto (`docs/ios-proyeccion.md`).

Después de la revisión y con el OK de Fernando: construir en el orden de la propuesta (A, y en paralelo B y D; luego
C), con la skill `orquesta` si conviene.

## Reglas que esta sesión aprendió y que siguen

- **Varias sesiones en el mismo checkout** (`~/code/orbital` en la Mac): hay cambios ajenos sin guardar. Haz commit solo
  de tus rutas; nunca stash, reset ni `pull` con lo ajeno encima. Si el push choca: `git worktree add /tmp/wt origin/main`,
  `cherry-pick` de tu commit, push desde ahí, borra el worktree.
- **Sin Canvas** si la sesión se lanza desde la app de iPhone: pide a una sesión hermana web (`list_sessions`, origin
  `web_claude_ai`) que publique el HTML con Artifact.
- **Pruebas contra Trakt:** desde la Lenovo, con la sesión de Trakt de la consola (`orbital/library/trakt.py`), sin
  imprimir tokens, 2 s entre escrituras, con una película de prueba, y limpiando al final. Esas sesiones piden el OK
  directo de Fernando antes de escribir en su cuenta.
- Nunca teclas ni POST a la Orbital real (127.0.0.1:8710).
- Decisiones para Fernando como PM no técnico, con algo visual si se puede; antes y después en cada corrección
  (salvo que tome más de ~2 min).

## Prompt para iniciar la siguiente sesión

```
Hola. Continúas el trabajo de «Desacoplar Stremio en el iPhone» de Orbital. Repo: ~/code/orbital (Mac).

Antes de nada, lee en este orden:
1. docs/producto/desacoplar-stremio/siguiente-sesion.md (el traspaso: qué se decidió, qué se probó y qué te toca).
2. docs/producto/desacoplar-stremio-iphone-2026-10-29.md (la propuesta completa; el resumen ejecutivo está arriba).
3. El CLAUDE.md del repo y docs/ios-proyeccion.md.

Lo que quiero de esta sesión, en orden:
1. Revisa el plan otra vez y confírmame en un resumen corto, como a un PM no técnico, que Trakt va a ser el
   mecanismo de sincronización entre mi celular y la computadora, y que Stremio solo va a ser respaldo. Dime qué hace
   falta del lado de la computadora para que eso sea cierto.
2. Dame el inventario de todo lo que en mi celular viene de Stremio o dice Stremio, con qué lo reemplazas para que ya
   no aparezca y no perdamos contenido. «Mi lista» de Stremio del Inicio se puede perder. «Lo más popular hoy» de
   Buscar no: reemplázalo con otra fuente y recomiéndame cuál.
3. Investiga si se pueden consumir públicamente las listas de Rotten Tomatoes «Certified Fresh» (películas) y las
   series «Fresh», para una sección en Para ti. Dime qué tan estable es y qué riesgo tiene.
4. Corrige ya, sin esperar lo demás: en Para ti › Recomendadas, el «N.º 1 en Disney+» en texto pasa a una píldora
   mucho más chica y gráfica con el ícono del servicio, como en la app de escritorio. Tráeme el antes y el después.

Muéstrame 1 a 3 de forma visual si se puede (un Canvas o una página HTML). Cuando te dé el OK, empezamos a construir
en el orden de la propuesta.
```
