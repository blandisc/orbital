# Orbital para iPhone

App compañera de Orbital para ver **películas y series** en el iPhone con tus complementos de Stremio y Real-Debrid.
Uso personal: no va a la App Store (la regla 5.2.3 lo impide); se instala con tu cuenta de desarrollador o TestFlight interno.

- **Stremio es la cuenta eje**: lo que ves aquí (avance, visto, Mi lista) se guarda en tu cuenta y aparece en Orbital, y al revés.
- **Trakt** cuelga de eso: tu watchlist, tus listas y recomendaciones en «Para ti», y el *scrobble* de lo que ves.
- **Reproductor propio** (AetherEngine, con AVPlayer de respaldo) y **«Abrir en Infuse»** para los archivos difíciles.
- **Descargas** con enlaces de Real-Debrid, para ver sin conexión.
- Español e inglés (interfaz y fichas).
- Solo fuentes con enlace http(s) (Real-Debrid): las de torrent sin Real-Debrid (`infoHash`) no se ofrecen.

## Estructura

```
ios/
  OrbitalCore/            paquete de Swift (sin interfaz). Se prueba con `swift test`, en Mac o Linux.
    Sources/OrbitalCore     la lógica portada de Orbital (Python): Stremio, complementos, fuentes, Cinemeta,
                            TMDB, Trakt, reproducción (avance, cola sin conexión), descargas, Infuse, ajustes
    Sources/OrbitalModels   modelos de vista (inicio, ficha, reproductor, Para ti…): sin SwiftUI, también se prueban
  App/                    la app (SwiftUI). Se genera con XcodeGen (project.yml)
    Sources/Design          sistema de diseño: tokens y piezas (los colores salen de palette.json de Orbital)
    Sources/Screens         pantallas
    Sources/Platform        descargas en segundo plano, motores de video, red, disco
    Resources               Localizable.xcstrings (es/en), iconos
scripts/ios_golden.py     valores de referencia que generan las funciones de Python de Orbital (tests/fixtures/ios)
scripts/ios_strings.py    genera y comprueba el catálogo de textos
```

## Probar

```bash
cd ios/OrbitalCore && swift test         # lógica y modelos (con los mismos casos que las pruebas de Python)
python scripts/ios_golden.py             # regenera los valores de referencia si cambia la lógica de Python
python scripts/ios_strings.py --check    # ningún texto sin traducir
```

Las pruebas de Swift leen `tests/fixtures/` (los mismos datos de ejemplo que usan las de Python) y los valores que genera
`scripts/ios_golden.py` a partir de las funciones de Python: si Swift y Python dan distinto, la prueba falla.

## Instalar en tu iPhone

1. `brew install xcodegen`, luego `cd ios/App && xcodegen` y abre `Orbital.xcodeproj`.
2. En `project.yml` pon tu **equipo** (`DEVELOPMENT_TEAM`) y tu **identificador** (`PRODUCT_BUNDLE_IDENTIFIER`).
3. Ejecuta en tu iPhone (iOS 18+). Con cuenta de desarrollador de pago el perfil dura un año.
4. Al abrir: entra con tu cuenta de **Stremio**. En Ajustes agrega (opcional) la clave de **TMDB** (fichas en español y
   plataformas) y el *client id* de tu aplicación de **Trakt**.

## Lo que está verificado y lo que no

| | Estado |
|---|---|
| `OrbitalCore` y `OrbitalModels` | Compilados y probados (Swift 6.2, Linux): `swift test` (193 pruebas). Pasaron además dos revisiones independientes (compilación y lógica/seguridad); sus hallazgos están corregidos y con prueba. |
| Los modelos de vista y su lógica de reproducción | Probados con un motor y una red falsos. |
| Sistema de diseño (colores = `palette.json`, sin valores sueltos en pantallas) | Verificado con pruebas. |
| **SwiftUI, descargas en segundo plano, AVPlayer, Keychain** | **Escritos, solo revisados de sintaxis. No se han compilado ni ejecutado**: no había Xcode ni iPhone. Al compilar por primera vez pueden salir errores de tipos. |
| **AetherEngine** (`Platform/AetherEnginePlayer.swift`) | Escrito contra el README de la versión 7.35, sin compilar. Activo con la bandera `AETHER_ENGINE`; sin ella la app usa AVPlayer (MP4/HLS, sin MKV). |
| Infuse, Real-Debrid, Trakt reales | Sin probar contra los servicios reales. Ver «Pruebas pendientes en el iPhone». |

## Pruebas pendientes en el iPhone

1. ¿Infuse reproduce la URL (¿pide Pro?), y llega `x-success` con `position` al cerrar, al terminar y al matar la app?
2. AetherEngine con tus archivos de Real-Debrid (4K HDR/Dolby Vision, PGS, varios audios): arranque, seek, PiP, batería, temperatura.
3. Descargas: que el enlace caducado se renueve y se reanude, y que el archivo descargado se reproduzca.
4. Trakt: que la app pueda conectarse a tu cuenta (las cuentas gratuitas permiten una sola «app comunitaria»; Stremio ya la ocupa).
5. Que lo guardado en Stremio aparezca en Orbital (con el título original, no el traducido) y al revés.

## Descargas: cómo se reanudan

- **Pausa o corte de red**: se conserva lo bajado con los datos de reanudación de `URLSession` y se continúa mientras el enlace valga.
- **Enlace de Real-Debrid caducado** (403/404/410): se pide un enlace nuevo al mismo complemento y la descarga empieza de nuevo desde cero
  (los datos de reanudación están atados al enlace viejo).
- **Relanzar la app**: una descarga que el sistema siguió en segundo plano se adopta, no se reinicia.
- iOS cancela las descargas si cierras la app deslizándola en el selector de apps.

## Excepciones al sistema de diseño

`DesignTests` revisa que las pantallas no escriban colores, medidas, opacidades ni esperas a mano. Una línea se exime con `ds-exception: motivo`:

| Dónde | Motivo |
|---|---|
| `Design/Components.swift` (`averageColor`) | el color sale de los píxeles del póster, no es un valor de diseño |

## Límites conocidos

- Los enlaces de Real-Debrid pueden quedar en la memoria de la app mientras corre; no se guardan en disco (sesión efímera, Keychain para lo guardado).
- Infuse recibe la URL del video y devuelve `orbital-ios://…` a quien la abra: es inherente a la API de Infuse.

- Infuse solo avisa **al cerrar** y no da la duración: el avance de lo visto en Infuse es de «mejor esfuerzo».
- El mosaico de «Para ti» no tiene aún el «modo ambiente» ni el acercamiento lento de la TV.
- PiP y AirPlay dependen del motor; el reproductor propio todavía no los expone en la interfaz.
- Los mensajes de error que arman los modelos en español no se traducen todos al inglés.
- La API de Stremio no es oficial: si cambia, falla aquí y en Orbital a la vez.
