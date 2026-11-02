# Explorar: cambiar de pestaña más rápido (2 nov 2026)

Fernando: «cada vez que cambio a Explorar cambia lento, como que recarga las imágenes. Saca una medida, redúcela y trae evidencia».

## Cómo se midió

Simulador «Orbital QA» (iPhone 17 Pro, iOS 26.3), compilación de prueba (Debug), modo demostración. La app cambia sola de
Inicio a Explorar seis veces (`-demo -perf -demo-free-tabs -demo-tab-cycle 6`) y en cada vuelta anota:

- **aparece**: milisegundos desde que se pide Explorar hasta que su pantalla aparece (`xtab.appear`).
- **tirón**: el cuadro que más tardó en los 2 s siguientes (`HitchMeter`; a 60 Hz un cuadro dura ~17 ms).
- **perdido**: todo el tiempo que los cuadros se atrasaron en esos 2 s (lo que se siente como «lento»).
- **imágenes releídas**: imágenes que se tuvieron que volver a leer del disco o la red al volver (`orbital-net.log`).

La vuelta 1 es la primera vez (se cargan las imágenes); la mediana es de las vueltas 2 a 6, que es lo que se siente al ir y
venir. Las bitácoras crudas se generan con `/tmp/xtab/measure.sh` (ver abajo).

## Resultado

| | aparece | tirón | perdido | imágenes releídas |
|---|---|---|---|---|
| **Antes** | 135 ms | 260 ms | 308 ms | 53 por cambio |
| **Después** | 93 ms | 159–198 ms | 153–184 ms | 0 |
| Piso: cambiar a Descargas (pantalla sencilla) | 111 ms | 216 ms | 207 ms | 0 |

Explorar quedó al nivel de cambiar a una pantalla sencilla: lo que queda es lo que cuesta cambiar de pestaña en sí.

## Qué se cambió

1. **El caché de imágenes en memoria va con la memoria del teléfono** (1/32, entre 96 y 256 MB; antes 96 fijos). Los fondos
   grandes de Inicio sacaban de la memoria los ~100 pósters del muro de Explorar y al volver se releían y preparaban otra
   vez: de 53 imágenes releídas por cambio a 0 (`ImagePipeline.memoryBytes`).
2. **Las columnas del muro se quedan colgadas de su pantalla** mientras el muro existe (antes se descolgaban y volvían a
   colgar en cada cambio de pestaña) (`DriftView.didMoveToWindow`).
3. **La lista de Explorar es perezosa**: al volver solo se acomoda lo que se ve (antes todos los grupos: plataformas,
   colecciones, años, listas) (`ListsView`, `LazyVStack`).

## Las corridas

```
== antes2
vuelta  aparece(ms)  tirón(ms)  perdido(ms)  imágenes-releídas  de-red
     1          110        208          653                153       7
     2          135        232          315                 55       0
     3          140        113          112                 53       0
     4          115        260          256                 44       0
     5          127        297          308                 37       0
     6          144        328          320                 54       0
mediana (vueltas 2..): aparece 135 ms · tirón 260 ms · perdido 308 ms · imágenes 53
== fix1b
vuelta  aparece(ms)  tirón(ms)  perdido(ms)  imágenes-releídas  de-red
     1          101        397         1004                153       7
     2          159        400          452                 55       0
     3          143        392          447                 51       0
     4          142        300          329                 42       0
     5          129        248          280                 35       0
     6          125        249          348                 44       0
mediana (vueltas 2..): aparece 142 ms · tirón 300 ms · perdido 348 ms · imágenes 44
== fix2a
vuelta  aparece(ms)  tirón(ms)  perdido(ms)  imágenes-releídas  de-red
     1          121        423         1142                153       7
     2          114        222          208                  0       0
     3          125        232          207                  0       0
     4          115        227          225                  0       0
     5          115        232          228                  0       0
     6          118        228          211                  0       0
mediana (vueltas 2..): aparece 115 ms · tirón 228 ms · perdido 211 ms · imágenes 0
== fix2b
vuelta  aparece(ms)  tirón(ms)  perdido(ms)  imágenes-releídas  de-red
     1           95        304          687                 74       3
     2          105        180          174                  0       0
     3          106        182          166                  0       0
     4          109        193          177                  0       0
     5          104        181          179                  0       0
     6          103        182          166                  0       0
mediana (vueltas 2..): aparece 105 ms · tirón 182 ms · perdido 174 ms · imágenes 0
== fix3a
vuelta  aparece(ms)  tirón(ms)  perdido(ms)  imágenes-releídas  de-red
     1           93        427          760                 31       1
     2           87        156          141                  0       0
     3           95        159          142                  0       0
     4           90        158          153                  0       0
     5           93        166          166                  0       0
     6          100        177          176                  0       0
mediana (vueltas 2..): aparece 93 ms · tirón 159 ms · perdido 153 ms · imágenes 0
== fix3b
vuelta  aparece(ms)  tirón(ms)  perdido(ms)  imágenes-releídas  de-red
     1          103        490         1151                103       5
     2           94        196          190                  0       0
     3           91        188          185                  0       0
     4          101        198          183                  0       0
     5           93        198          184                  0       0
     6           97        198          181                  0       0
mediana (vueltas 2..): aparece 94 ms · tirón 198 ms · perdido 184 ms · imágenes 0
== descargas
vuelta  aparece(ms)  tirón(ms)  perdido(ms)  imágenes-releídas  de-red
     1          112        482         1214                103       5
     2          104        216          204                  0       0
     3          108        215          207                  0       0
     4          111        216          215                  0       0
     5          130         34            9                  0       0
     6          124        256          252                  0       0
mediana (vueltas 2..): aparece 111 ms · tirón 216 ms · perdido 207 ms · imágenes 0
```

`antes2`: sin cambios. `fix1b`: solo (2) (con imágenes releídas aún). `fix2a`/`fix2b`: (1) y (2). `fix3a`/`fix3b`: los tres. `descargas`: los tres, cambiando a Descargas (el piso).
