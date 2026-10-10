# Pruebas y configuración pendientes

## Configurar una vez

| # | Qué | Cómo |
|---|---|---|
| 1 | Home no abra la Xbox Game Bar | Configuración → Juegos → Xbox Game Bar → desactivar "Abrir Xbox Game Bar con este botón del mando" |
| 2 | Cuenta de Stremio (Seguir viendo, biblioteca) | `C:\Users\ferna\orbital\.venv\Scripts\python -m orbital stremio login` |
| 2b | Subtítulos en inglés por defecto | En Stremio: Configuración → Reproductor → idioma de subtítulos = English (el reproductor de Stremio los elige solo) |
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
- [ ] En el reproductor de Stremio: A pausa, ←/→ adelanta/regresa, ↑/↓ volumen, Y pantalla completa, B vuelve.
- [ ] Al elegir un episodio o película aparece "Elige la fuente" con la recomendada enfocada; arranca sola en 5 s o con A; ↑/↓ para otra.
- [ ] La fuente elegida abre directo el reproductor de Stremio (sin su lista de fuentes).
- [ ] Al cerrar Stremio, Orbital vuelve y "Seguir viendo" se actualiza (con la cuenta vinculada).

### Steam
- [ ] El héroe muestra el logotipo, las horas reales y el tamaño; Marvel Rivals avisa "Actualización pendiente".
- [ ] Tras jugar algo de Steam, sus horas se actualizan en Orbital (unos segundos después de cerrar).

### Voz (cuando Alexa esté configurada)
- [ ] "Alexa, pídele a mi consola que abra Zelda".
- [ ] "…que quiero ver The Office" → episodios en Orbital.
- [ ] "…que busque Dune" → búsqueda de Orbital ya escrita.
- [ ] "…que salga al escritorio" / "…que abra la consola".
- [ ] "Alexa, pregúntale a mi consola qué está abierto".
