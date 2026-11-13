# Antes de decir «listo» en la app de Apple

Lista corta, nacida de errores reales (13 nov 2026). Es ligera a propósito: cinco comprobaciones, no un trámite.
Aplica a cualquier pantalla o pieza que se toque en `ios/App`.

1. **Se mide, no se ve a ojo.** Márgenes, alineación y espacios se comprueban con números: los marcos de los elementos
   en una prueba de interfaz, o midiendo la captura. Lo mínimo: márgenes izquierdo y derecho iguales, lo que comparte
   renglón comparte centro, nada se encima ni se corta, y el aire de abajo es el de los lados.
   *Por qué:* los botones del mazo de «Decide por mí» salieron cortados por la carta y nadie lo midió.
2. **Se toca, no solo se fotografía.** Cada control nuevo o movido se toca de ida y vuelta en una prueba de interfaz con
   tiempo límite (abrir, cambiar, regresar). Una captura no demuestra que algo funcione.
   *Por qué:* «Una por una» congelaba la app y no dejaba regresar; la pasada anterior solo tenía capturas.
3. **Se prueba en el tamaño del iPhone de Fernando.** iPhone 17 Pro (402 pt de ancho) con iOS 27, además del más chico
   (SE) y el más grande. Lo que solo se probó en Pro Max y SE no está probado.
   *Por qué:* el congelamiento dependía del ancho real y no salió en los otros dos.
4. **Si la app truena o se congela, primero el registro.** Antes de suponer la causa se lee el registro del iPhone
   (cierres en `systemCrashLogs`; la bitácora del reproductor). La copia se borra al terminar.
   *Por qué:* el latino que no aparecía y el «truene» de los filtros se resolvieron al leer el registro, no antes.
5. **El informe dice la verdad en tres palabras.** Cada punto va como «comprobado con toques», «hecho sin comprobar» o
   «no hecho». Lo que no se vio en pantalla no se anuncia como listo, y se instala solo si el número de compilación
   coincide con el esperado.

Lo que se corrige y puede repetirse se vuelve regla del repo con su prueba (regla 16 de la casa); las reglas de diseño
viven en `docs/ios-interfaz.md`. Para quien dirige agentes: todo en primer plano con tiempo límite y, a lo más, tres
agentes con simulador a la vez.
