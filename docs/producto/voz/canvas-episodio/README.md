# Canvas «Elegir episodio: ¿teléfono o tele?»

Fuente de https://claude.ai/artifact/SdhN6NK4N8aMBvVwsEwu6D (29 oct 2026). Decidido por Fernando: los episodios se eligen en el teléfono; la tele sigue mientras tanto.

## Cómo se arma (ya existe todo en `main`, según la sesión de voz; revisado en el código)

- **La lista:** el iPhone la saca solo de Cinemeta con `Cinemeta.meta(kind: "series", id: metaID)` (`ios/OrbitalCore/Sources/OrbitalCore/Cinemeta.swift`), campo `videos` (`season`, `episode`, `id` «tt…:S:E», `released`). No pasa por la consola: la tele sigue igual.
- **Esconder:** los especiales (temporada 0) y los que aún no salen (`released` en el futuro), igual que la voz.
- **Ponerlo:** `OrbitalRemote.play(kind: "series", metaID:, videoID: "tt…:S:E", title: "The Office · T2 E5")` → `POST /api/stremio/play` con `video_id`: ese episodio exacto, con la fuente recomendada y donde ibas. Sin `video_id` abre la ficha en la tele (no se quiere aquí).
- **Marcar el que se ve:** `GET /api/companion/now` → `playing.video_id/season/episode` (ya lo usa «Viendo en la TV»). El `picked` de la voz es el `meta_id` de la serie, no del episodio.
