# Juegos en Orbital Ultra: los mismos que en la TV (27 nov 2026)

Sigue a `investigacion.md` (3 nov, G1–G3, D1–D6, que esta propuesta reemplaza). Fer pidió (27 nov): «que Orbital iOS
tenga las mismas funcionalidades que Orbital pantalla… Switch 2, Game Boy Advance, GameCube, Xbox». Estado:
**investigación, nada construido**. Canvas: `paridad-tv.html`. Revisada por dos agentes (producto y técnica) antes de
entregarla.

## En una línea

**En casa, todo lo de la TV se puede jugar en el iPhone transmitiéndolo desde la Legion Go. Fuera de casa, por ahora
solo GBA, DS, PS1 y PSP corren en el propio iPhone.** Switch, GameCube y Xbox dentro del iPhone dependen del «modo
rápido» de iOS, que en iOS 27 está roto o a medias.

## Qué tiene hoy la TV (`orbital/library/detect.py · KNOWN`)

Switch (Ryujinx, Eden, Citron, Sudachi), GameCube y Wii (Dolphin), GBA (mGBA), Xbox (xemu), Xbox 360 (Xenia), PS1
(DuckStation), PS2 (PCSX2), PSP (PPSSPP), DS (melonDS), Wii U (Cemu), PS3 (RPCS3), PS4 (shadPS4), y ~166 sistemas más
por las reglas de ES-DE.

**Switch 2 no está en la TV.** Solo existe Eden-NX2 (29 oct 2026), una prueba para Windows que arranca Mario Kart World
y DK Bananza con tirones; pide 8 GB de memoria de video y 16 GB de RAM (la Legion Go comparte 16 GB entre todo). La de
Android no es oficial y quedó abandonada. Para iPhone no hay nada. **No es decisión: se vigila** y se avisa cuando cambie.

## Qué cambió desde el 3 nov

1. **JIT en iOS 27: no confirmado, con malas señales.** La tabla de StikDebug marca 26.4 en adelante como «sin probar o
   parcial»; hay reportes de fallas en 27.0 (5 oct) y 27.2.1 (Kernarium #71), y ningún arreglo oficial. Sin JIT no
   corren MeloNX (Switch), DolphiniOS con JIT, DukeX (Xbox) ni XeniOS (360). La recomendación del 3 nov (apps hermanas
   con JIT, D5-B) deja de ser el primer paso; se prueba en el iPhone de Fer antes de descartarla.
2. **iCube (Provenance, de DolphiniOS) para GameCube/Wii** tiene dos caminos: sin JIT (un video a 60 cps que nadie ha
   medido) y con JIT bajo TXM (cambios del 19 sep). Se puede compilar con la cuenta de Fer.
3. **Xbox en iPhone ya existe**, en pañales: DukeX (xemu, Xbox original) y XeniOS (Xenia, 360, alfa, ~340 juegos en su
   lista, pide 15 Pro o más nuevo). Los dos piden JIT.
4. **D4 resuelto:** iPhone 17 Pro con iOS 27. Le sobra fuerza; estorba el JIT, no el aparato.

## Cada consola, por dónde puede llegar

| Consola | En el iPhone, sin JIT | En el iPhone, con JIT | Transmitida desde la consola |
|---|---|---|---|
| GBA, DS, PS1, PSP | **Sí, ya** | no hace falta | sí |
| GameCube, Wii | quizás (iCube, por medir) | iCube / DolphiniOS | **sí** |
| Switch | no | MeloNX | **sí** |
| Switch 2 | no | no existe | cuando la TV lo tenga |
| Xbox | no | DukeX | **sí** |
| Xbox 360 | no | XeniOS (alfa) | **sí** |
| PS2, Wii U, PS3, PS4 | no (PS2: Play!, muy lento) | no | **sí** |

## Los caminos

- **T · Transmitir.** Apollo (fork de Sunshine) en la Legion Go crea una pantalla del tamaño del iPhone; el iPhone pide el
  juego a la consola y recibe la imagen. Todo el catálogo, partidas en un solo lugar, cualquier iOS.
  - **T-A · app Moonlight (App Store).** Solo para probar si se siente bien: Moonlight no abre un juego directo (no tiene
    enlace para eso), así que es «Orbital pide el juego → Atajo abre Moonlight en la consola → entras al escritorio»;
    para volver, a mano.
  - **T-B · el receptor dentro de Orbital** (`moonlight-common-c`, GPLv3: solo Ultra). Imagen, audio, controles y
    emparejamiento, con la pausa y el «salir» de Orbital. **4–6 semanas.**
- **L · GBA, DS, PS1 y PSP en el iPhone, sin wifi.**
  - **L-0 · apps de la App Store** (Delta, PPSSPP, RetroArch) con «Abrir en…» desde Orbital. Días. Las partidas se quedan
    en esas apps (no vuelven solas a la TV).
  - **L-1 · dentro de Orbital** (mGBA es MPL-2.0; melonDS, SwanStation y PPSSPP GPL: solo Ultra). La partida normal va y
    viene con la TV (la de mGBA es la misma; PPSSPP usa la misma carpeta); el guardado rápido no. **5–8 semanas** las
    cuatro con botones, guardado y portadas.
- **P · Switch, GameCube y Xbox dentro del iPhone.** Se vigila (JIT de iOS 27, iCube). Se prueba en medio día; no se
  construye todavía.

## Hoyos que la propuesta resuelve

- **La consola ya está al alcance.** El iPhone ya habla con la Legion Go por https (túnel) o Tailscale, con token
  (`OrbitalRemote.swift`); `/api/launch` (`orbital/api/play.py`) va por ahí. Moonlight también puede ir por Tailscale:
  fuera de casa se puede **probar** (retraso y datos por medir); no se promete.
- **En qué pantalla sale el juego.** Al transmitir, la pantalla virtual de Apollo tiene que ser la principal (o la única)
  mientras dura; si no, el juego sale en la TV y el iPhone ve el escritorio. Apollo maneja una pantalla virtual por
  cliente (Apollo #874). Se comprueba en la prueba de medio día.
- **Modo transmisión en la TV.** Mientras se transmite, la interfaz de la TV no reacciona al mando ni roba el foco, y el
  candado de la tele lo marca.
- **La Legion Go dormida.** No tiene puerto de red y despertarla por wifi no es confiable. Primera versión: el iPhone
  dice «Tu consola está dormida · Préndela para jugar»; después, ajustar su energía para que no se duerma de noche.
- **Recientes y horas jugadas** son las mismas en la TV y en el iPhone (lo cuenta la consola en los dos casos de T; en
  L-1 el iPhone le avisa al terminar).

## Lo que hay que decidir (códigos del Canvas)

- **J1 · Por dónde empezar.** J1-A transmitir (todo, en casa) · J1-B GBA y compañía en el iPhone (en cualquier lado) ·
  J1-C esperar al JIT. **Recomendado: J1-A**, y L después.
- **J2 · Transmitir dentro o fuera de Orbital.** J2-A app Moonlight · J2-B dentro. **Recomendado: J2-A solo para la
  prueba; J2-B para quedarse.**
- **J3 · Con qué juegas.** Botones en pantalla para GBA y DS, sí o sí. Para Switch, GameCube y Xbox: J3-A un mando
  Bluetooth, solo dentro del juego y solo en Ultra (excepción a la regla del 29 oct) · J3-B solo botones en pantalla.
  **Recomendado: J3-A**: los juegos 3D con botones en pantalla casi no se juegan.
- **J4 · Si la TV está en uso.** J4-A el iPhone pregunta «La TV está en uso · ¿La tomo?» y la TV avisa antes de cerrar ·
  J4-B espera a que se libere · J4-C la TV muestra lo que juegas en el iPhone. **Recomendado: J4-A.**
- **J5 · Dónde vive «Juegos» en el iPhone.** J5-A quinta pestaña · J5-B dentro de Biblioteca · J5-C una franja en
  Inicio. **Recomendado: J5-A**, solo en Ultra (Plus y la App Store siguen con cuatro).
- **J6 · GBA y compañía.** J6-A apps de la App Store (L-0) · J6-B dentro de Orbital (L-1). **Recomendado: J6-B**, después
  de transmitir; J6-A si los quieres ya para un viaje.

## Si dice J1-A · J2-A · J3-A · J4-A · J5-A · J6-B

1. **Prueba de medio día, sin construir.** Apollo en la Legion Go, Moonlight en el 17 Pro, un mando Bluetooth. Media hora
   de Switch y una de GameCube por wifi: retraso, batería y calor. Regla: si una hora gasta más de 30 % de batería o se
   siente el retraso al saltar, no se sigue con T y se replantea. De paso: iCube y MeloNX tal cual, para saber cómo está
   el JIT en su iPhone.
2. **La TV:** encender Apollo solo cuando el iPhone pide jugar, modo transmisión, candado, pantalla virtual principal.
3. **El iPhone (J5-A):** pestaña «Juegos» con el catálogo de la consola (portadas, Recientes, por consola, como la TV);
   «Jugar» → la consola abre el juego → Moonlight.
4. **J2-B:** el receptor dentro de Orbital.
5. **J6-B:** GBA, DS, PS1 y PSP dentro de Orbital, sin wifi.
6. **Vigilar:** JIT de iOS 27, iCube sin JIT, Eden-NX2 (Switch 2).

## Reglas que no cambian

- Solo Ultra (`Edition.ultra`), instalada con Xcode: por licencia, Plus (TestFlight) y la App Store no lo llevan.
- iPad y Mac nunca son Ultra: no llevan nada de esto.
- La TV gana lo del punto 2; va una fila al registro de paridad cuando se construya.

## Fuentes

- Switch 2: techspot.com/news/114408, tweaktown.com/news/114420, tech-insider.org (Android abandonado).
- JIT: github.com/StephenDev0/StikDebug (tabla de versiones), github.com/imxieyi/Kernarium/issues/71,
  lovegame.space/en/news/melonx-2-7-release.
- iCube: nintendowire.com/news/2026/09/21/…, heldgames.com/guides/icube-gamecube-wii-iphone-jitless.
- Xbox: github.com/MaftyManicEMU/DukeX; heldgames.com/guides/xenios-xbox-360-iphone.
- Transmitir: github.com/moonlight-stream/moonlight-ios (sin enlace para abrir un juego),
  github.com/moonlight-stream/moonlight-common-c (GPLv3), github.com/ClassicOldSong/Apollo/issues/874.
