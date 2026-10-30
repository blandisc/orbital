# Modo degradado del iPhone (29 oct 2026)

Qué ve quien usa Orbital en el iPhone cuando algo falla, y qué puede hacer. La regla: **decir la causa de verdad y dar
una salida**. No basta con «Revisa tu conexión»: antes casi toda falla terminaba así, aunque el iPhone tuviera internet
y el que no contestaba fuera Trakt, un complemento o Real-Debrid.

## Cómo se decide la causa

`Degraded` (`ios/OrbitalCore/Sources/OrbitalCore/Degraded.swift`, con pruebas en `DegradedTests`) tiene tres causas:

| Causa | Cuándo | Salida principal |
|---|---|---|
| `offline`: «Sin internet» | El monitor de red del iPhone (`Connectivity`, `NWPathMonitor`) dice que no hay red, o el error es de «sin red» (`notConnectedToInternet`, `networkConnectionLost`…) | **Tus descargas** (y «Intentar de nuevo» al lado) |
| `down(servicio)`: «Trakt no contesta», «Tus complementos no contestan»… | Hay internet, pero ese servicio falló (5xx, tiempo agotado, sin respuesta) | **Intentar de nuevo** |
| `notConnected(servicio)`: «Conecta Trakt», «Falta conectar Real-Debrid»… | Falta conectarlo, o su sesión se cerró (401/403) | **Abrir Ajustes** |

La app le pasa a los modelos si hay red con `Services.isOnline` (en la app, `Connectivity.shared.isOnline`; en la
demostración, `-demo-offline` lo apaga). Antes el monitor existía pero nadie le preguntaba.

Los textos técnicos que llegan a la pantalla pasan por `UserMessages.humanize`: un `HTTP 5xx` dice «El servicio no
contesta ahora; intenta en un rato», un `HTTP 401/403` dice «Tu sesión se cerró: vuelve a conectar la cuenta en Ajustes» y
«no hay espacio» (a media descarga) dice «Se llenó el iPhone. Libera espacio y toca Reintentar». Solo lo que de verdad es
la red dice «Revisa tu conexión».

La pieza visual es `DSDegradedNotice` (catálogo en `docs/ios-proyeccion.md`): título con ícono, qué sigue funcionando y
el botón de la salida.

## Escenarios

### Sin internet

| Pantalla | Qué ve | Qué puede hacer |
|---|---|---|
| Inicio | «Sin internet» arriba; debajo, lo guardado en el iPhone (Seguir viendo, Mi lista). Ya no dice «Todavía nada» | Tus descargas · Intentar de nuevo |
| Buscar (sin escribir) | Con copia de lo popular, la copia sin aviso; sin copia, «Sin internet» | Tus descargas · Intentar de nuevo |
| Buscar (escribiendo) | «No pude buscar. Revisa tu conexión.» | Escribir otra vez |
| Ficha | «No pude cargar la ficha. Revisa tu conexión.»; el botón grande dice «Sin conexión» | Intentar de nuevo |
| Ver (sin fuentes por la red) | Aviso «Sin internet · No pude buscar dónde verlo» | Reintentar |
| Reproductor | «Sin conexión · Revisa tu conexión a internet e intenta de nuevo. Lo que descargaste sí se puede ver.» | Intentar de nuevo · **Ver tus descargas** · Cerrar |
| Control de la TV | «Tu iPhone no tiene internet · Conéctalo al Wi-Fi de tu casa» (antes culpaba a la consola) | Intentar de nuevo |
| Descargas | Se ven y se reproducen; las que bajan esperan («Esperando Wi-Fi») | — |
| Lo que marcas (visto, Mi lista, favoritos) | Se guarda en el iPhone y viaja a Trakt al volver la red (`TraktOutbox`, `LibrarySync`) | — |

### Trakt

| Escenario | Pantalla | Qué ve | Salida |
|---|---|---|---|
| Sin conectar (o sin la aplicación de Trakt) | Buscar | «Conecta Trakt · Lo más popular, los géneros y tus recomendaciones vienen de Trakt» (antes: «Revisa tu conexión») | Abrir Ajustes |
| | Para ti | «Conecta Trakt o tu Orbital» | Abrir Ajustes |
| | Inicio | Sin las filas de Trakt (watchlist, favoritos, Para ti); lo demás igual | — |
| Sesión vencida (401) | Toda la app | Se intenta renovar una vez; si no, aviso «Tu sesión de Trakt se cerró · Conectar» | Ajustes |
| Caído (5xx, tiempo agotado) | Buscar sin copia | «Trakt no contesta · Lo tuyo está guardado en el iPhone y se sincroniza solo cuando vuelva» | Intentar de nuevo |
| | Buscar escribiendo | Cinemeta responde en su lugar (sin aviso) | — |
| | Inicio, Para ti | Se queda lo último que llegó | — |
| | Cambios (favoritos, listas) | Quedan en la cola y se mandan después; si no, «… El servicio no contesta ahora; intenta en un rato» | — |

### Complementos y Real-Debrid

| Escenario | Pantalla | Qué ve | Salida |
|---|---|---|---|
| Ningún complemento contesta (con internet) | Ficha › Ver | «Tus complementos no contestan · Hay internet, pero ninguno respondió» (antes: «Sin internet») | Reintentar (abre el reproductor, que vuelve a preguntar) |
| | Ficha, renglón de versión | «Tus complementos no contestan» | — |
| | Versiones | «Tus complementos no contestan: hay internet, pero ninguno respondió. Intenta en un rato.» | — |
| | Reproductor | «Tus complementos no contestan · Suele ser momentáneo» | Intentar de nuevo · Cerrar |
| Sin Real-Debrid en la app y sin versiones | Ficha › Ver | «No encontré dónde verlo · Conecta tu Real-Debrid en Ajustes» (antes: «Real-Debrid aún no lo tiene») | Ajustes |
| Real-Debrid vencido | Ficha › Ver | «Tu Real-Debrid venció hace N días» | Renovar |
| Real-Debrid no tiene el título | Ficha, reproductor | «Real-Debrid aún no lo tiene · Los estrenos suelen llegar unas horas después» | Cerrar |

La clave de Real-Debrid puede vivir solo en las direcciones de tus complementos (sin guardarla en Ajustes): por eso «falta
Real-Debrid» solo se sugiere cuando además no hubo versiones.

### Descargas

| Escenario | Qué ve | Salida |
|---|---|---|
| No cabe al pedirla | «No cabe en el iPhone · Hacen falta X y hay Y libres» | Descargas |
| Se llenó a media descarga | «Se llenó el iPhone. Libera espacio y toca Reintentar.» (antes: el texto del sistema, en el idioma del iPhone) | Reintentar |
| Enlace caducado | Se pide uno nuevo solo; si no se puede: «El enlace de esta versión caducó…» | ▶ busca otro |
| Servidor falla | «El servidor falló. Se vuelve a intentar.» | Reintentar |

### Tu Orbital (la consola)

| Escenario | Qué ve | Salida |
|---|---|---|
| Consola apagada u otra red | «Tu Orbital no contesta · Revisa que la consola esté prendida y en la misma red» | Intentar de nuevo |
| El iPhone sin internet | «Tu iPhone no tiene internet» | Intentar de nuevo |
| Token cambió | «Tu Orbital ya no reconoce este iPhone · Vuelve a conectarlos» | Escanear el código |

## Cómo probarlo en el simulador

Con la demostración (`-demo`), sin tocar cuentas de verdad:

| Bandera | Simula |
|---|---|
| `-demo-offline` | Modo avión: todo falla con «sin red» y `isOnline` es falso |
| `-demo-down trakt,addons,rd,tmdb,cinemeta,orbital` | Con internet, esos servicios contestan 503 (caídos). Se combinan con comas |
| `-demo-trakt` | Trakt conectado (sin esto, Trakt está «sin conectar») |
| `-demo-rd premium\|soon\|expired\|free\|invalid` | Estados de Real-Debrid |
| `-demo-voice-fail orbital\|token\|tunnel\|offline` | Fallas de la voz y de la consola |
| `-demo-player-state error` | La pantalla de falla del reproductor |

Ejemplos:

```bash
xcrun simctl launch <udid> mx.iracheta.orbital -demo -demo-offline                         # Inicio sin internet
xcrun simctl launch <udid> mx.iracheta.orbital -demo -demo-tab 2                           # Buscar sin Trakt
xcrun simctl launch <udid> mx.iracheta.orbital -demo -demo-trakt -demo-down trakt -demo-tab 2   # Buscar con Trakt caído
xcrun simctl launch <udid> mx.iracheta.orbital -demo -demo-down addons -demo-title movie:tt1375666 -demo-open play   # complementos caídos
```

## Pendiente

- Inicio y Para ti con Trakt caído se quedan con lo último, sin aviso: está bien mientras haya copia; sin copia, falta decirlo.
- Los géneros de Buscar sin Trakt salen vacíos (el aviso de arriba lo explica, pero la pantalla del género no).
- TMDB caído o sin clave: faltan colecciones e imágenes en silencio (`Degraded.down(.tmdb)` ya tiene su texto).
- `SessionModel.addonError` (falló leer tus complementos de Stremio) no se enseña en ningún lado.
