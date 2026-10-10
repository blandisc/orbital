# Pruebas y configuración pendientes

## Configurar una vez

| # | Qué | Cómo |
|---|---|---|
| 1 | Home no abra la Xbox Game Bar | Configuración → Juegos → Xbox Game Bar → desactivar "Abrir Xbox Game Bar con este botón del mando" |
| 2 | Cuenta de Stremio (Seguir viendo, biblioteca) | `C:\Users\ferna\orbital\.venv\Scripts\python -m orbital stremio login` |
| 2b | Subtítulos en inglés por defecto | Ya vienen así en el reproductor de Orbital (`stremio.subtitles: en`). Solo si usas `player: stremio`: en Stremio, Configuración → Reproductor → idioma de subtítulos = English |
| 2c | Reproductor de Orbital (mpv) | Ya instalado en `%LOCALAPPDATA%\orbital\mpv` (compilación de shinchiro, sin firma digital). Para volver al de Stremio: `player: stremio` en config.yaml |
| 3 | Permiso de micrófono para dictar | La primera vez que uses "Dictar" en Buscar, acepta el permiso del micrófono |
| 4 | Alexa | `orbital alexa setup` → instalar Tailscale → `tailscale funnel --bg 8711` → skill y Lambda (README, sección Alexa) → `orbital alexa check` |
| 5 | (Opcional) Mover los emuladores fuera de Descargas | El Sensor de almacenamiento de Windows puede borrar Descargas; Orbital también busca en `C:\Emuladores` |

## Probar con el mando

### Consola
- [ ] Al encender la Legion Go, Orbital abre solo (acceso directo de inicio).
- [ ] En el escritorio, Home abre Orbital; Home otra vez se queda en Orbital.
- [ ] En un juego, Home → Orbital; Home → de vuelta al juego.
- [ ] Legion L hace lo mismo que Home; dos toques seguidos abren Legion Space.
- [ ] Home+X, Home+B… dentro de Eden siguen haciendo lo de Eden (no mueven a Orbital).
- [ ] Select+Start sostenido en un juego: aparece el aviso encima del juego; soltar antes no cierra; sostener 1,5 s cierra sin preguntar.
- [ ] Select+Start también cierra un juego de Steam que esté al frente.
- [ ] A sobre el juego abierto dice "Continuar" y regresa a él (no abre otra copia).
- [ ] ☰ → Ventanas abiertas salta a otra app; ☰ → Apagado → Suspender.
- [ ] El mando vibra al llegar al final de una fila y al abrir un juego.

### Emuladores
- [ ] Zelda con Eden reconoce el GameSir sin configurarlo y A es A.
- [ ] Un juego de cada uno: Ryujinx, Dolphin (GameCube y Wii), mGBA, xemu, PPSSPP.
- [ ] Al cerrar cada uno, Orbital vuelve al frente y suma el tiempo jugado.

### Stremio
- [ ] Buscar: escribir 2-3 letras con el teclado del mando; los resultados aparecen solos.
- [ ] Dictar en Buscar (botón ☰ o la tecla Dictar).
- [ ] Una serie abre sus episodios; LB/RB cambia de temporada.
- [ ] En el reproductor de Stremio: A pausa, ←/→ adelanta/regresa, ↑/↓ volumen, Y pantalla completa (F11), B vuelve. Verificado: Stremio acepta las teclas que manda Orbital.
- [ ] Al elegir un episodio o película aparece "Elige la fuente" con la recomendada enfocada; arranca sola en 5 s o con A; ↑/↓ para otra.
- [ ] La fuente elegida abre el reproductor de Orbital a pantalla completa (verificado: Interstellar arrancó en 1,5 s con audio y subtítulos en inglés).
- [ ] En el reproductor: A pausa, ←/→ 10 s, LB/RB 1 min, ↑/↓ volumen, X audio, Y subtítulos, B sale y vuelve a Orbital.
- [ ] Home en el reproductor pausa y va a Orbital; Home otra vez regresa con la barra de progreso.
- [ ] Ver unos minutos, salir con B: "Seguir viendo" (en Orbital y en Stremio) muestra el avance; al volver a abrirlo sigue donde te quedaste.
- [ ] Terminar un episodio: "Seguir viendo" pasa al siguiente.
- [ ] Algo sin subtítulos en inglés dentro del video: se agregan los de tu addon de subtítulos (si tienes OpenSubtitles).

### Steam
- [ ] El héroe muestra el logotipo, las horas reales y el tamaño; Marvel Rivals avisa "Actualización pendiente".
- [ ] Tras jugar algo de Steam, sus horas se actualizan en Orbital (unos segundos después de cerrar).

### Voz (cuando Alexa esté configurada)
- [ ] "Alexa, pídele a mi consola que abra Zelda".
- [ ] "…que quiero ver The Office" → episodios en Orbital.
- [ ] "…que busque Dune" → búsqueda de Orbital ya escrita.
- [ ] "…que salga al escritorio" / "…que abra la consola".
- [ ] "Alexa, pregúntale a mi consola qué está abierto".
