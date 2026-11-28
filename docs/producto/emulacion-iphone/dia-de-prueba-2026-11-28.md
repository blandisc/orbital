# Día de prueba en el iPhone de Fer (IN1-A) — 28 nov 2026

Fer dio IN1-A (probar ya en su iPhone 17 Pro Max, sin esperar al Duo) y OK1, OK2, OK3. Esto es lo que quedó.

## Lo que ya está en su iPhone

| Consola | Motor | Juego | Estado |
| --- | --- | --- | --- |
| Game Boy Advance | Delta (fork, `mx.iracheta.orbital.portatiles`) | Pokémon Esmeralda | Instalado, el juego ya está dentro. Falta abrirlo con el iPhone desbloqueado. |
| Switch | nxnative (`mx.iracheta.orbital.mps`) | Mario Party Superstars 1.1.1 | Instalado, convertido con 82 789 de 82 790 sombras listas, contador de cuadros encendido. Falta abrirlo. |
| GameCube | iCube (`mx.iracheta.orbital.gamecube`) | Pikmin | Compilando. Necesita JIT (StikDebug + LocalDevVPN, los instala Fer). |

Todo firmado con su equipo de Apple (B7KRCF776Z); nada se subió a la App Store ni a terceros.

## Lo que no se pudo y por qué

- **Abrir los juegos en el iPhone:** iOS no deja abrir apps con el iPhone bloqueado. En cuanto Fer lo desbloquee se
  abren, se toman capturas y se anota si arranca, los cuadros por segundo y el calor.
- **DS:** en la Lenovo no hay juegos de DS; se probó solo Game Boy Advance.
- **Otros juegos de Switch:** nxnative pide la versión exacta. Luigi's Mansion 3 pide la 1.4.0 y Mario Kart 8 la
  4.0.x; esas actualizaciones no están en la Lenovo. Mario Wonder 1.0.0 sí coincide, pero convertirlo pide ~25 GB libres.
- **God of War III (PS4, Olympus):** pesa ~35 GB; hoy la Mac tiene ~19 GB libres. Además necesita JIT.
- **Xbox (DukeX):** no identifiqué en la Lenovo un juego de Xbox que DukeX corra (los de 360, Black Ops II y Dante's Inferno, siguen pendientes de X1).

## Cómo se copió (OK1)

La Lenovo no deja entrar conexiones (firewall de Windows; crear la regla pide ser administrador y se le dejó a Fer). Se
hizo al revés: la Mac abrió un receptor temporal con clave y la Lenovo empujó solo los archivos de prueba (Esmeralda,
Pikmin, las dos actualizaciones de Mario Party y las llaves). Se cerró al terminar. Las llaves viven fuera del repo.

## Para abrir cada motor desde Orbital

- Delta ya trae su enlace (`delta://`), así que Orbital puede abrirlo directo.
- nxnative e iCube no traen enlace: en su fork hay que agregar uno (`orbital-mps://`, `orbital-gc://`) para que la
  ficha del juego en Orbital lo abra (K1-A: se entra solo por Orbital).

## Siguiente

1. Fer desbloquea el iPhone → abro los tres, capturas, cuadros y calor.
2. Fer instala StikDebug y LocalDevVPN → iCube con JIT.
3. Enlaces de nxnative e iCube en sus forks, y la ficha de Orbital que los abre.
4. Más espacio (disco externo) → God of War III y Mario Wonder.
