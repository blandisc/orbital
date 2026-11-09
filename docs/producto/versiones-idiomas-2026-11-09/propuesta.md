# Elegir versión e idioma en el iPhone: revisión y propuesta (9 nov 2026)

Revisión de experto, sin construir nada. Para Fer, que decide como PM. Al decidir, la TV se entera por el registro de paridad
(`docs/producto/paridad-registro.md`).

## Cómo está hoy (lo que encontré en el código)

- **«Ver» de la ficha** arranca solo con la recomendada (`SourcesModel.toPlay`): primero lo que pediste y ya llegó, luego
  la versión con la que lo dejaste, luego la de la misma «familia» de la serie. Debajo dice «🇲🇽 Latino · 1080p».
- **La hoja «Versión»** (`SourcesSheet`) tiene encabezado + ⓘ, dos pestañas de texto («Por idioma» / «Todas las fuentes»), en
  un episodio un segmento «Solo este episodio | Desde aquí», y una fila por idioma con **una cápsula por calidad**
  (`VersionChip`: «1080p · 2,9 GB · Al instante»). Encima de cada fila, otra etiqueta de texto: «Tu idioma», «Original»,
  «Tal vez», «No dice si latino o castellano».
- **Tocar una cápsula abre una segunda hoja** (`VersionCard`) con «Ver» / «Descargar». Elegir una versión cuesta 3 toques y 2
  hojas.
- **Mientras busca**: dos filas fantasma (`VersionsSkeleton`). Bien. Pero no dice cuánto falta ni quién no ha contestado
  hasta que termina (`AddonQuietLine`).
- **Si no hay ninguna versión**: la hoja **queda en blanco** (no hay estado vacío en `byLanguage`; solo sale el error si hubo
  error). La causa buena (`UnavailableCause`: Real-Debrid vencido, sin complementos…) solo la usa el botón «Ver» de la
  ficha, no la hoja.
- **Idioma desconocido**: el español sin variante va a una fila «Español» con la etiqueta «No dice si latino o
  castellano»; lo dudoso dice «Tal vez» en ámbar. Correcto, pero en palabras largas y en cápsula.
- **Episodios**: tocar un episodio reproduce; «Versión de este episodio…» vive en «⋯» y al mantener presionado (desde hoy,
  uno visto también arranca desde el inicio con la versión de la serie).

## Problemas, en orden de cuánto te molestan

1. Cápsulas de texto por todos lados (calidad, «Tu idioma», «Tal vez», pestañas). Es lo que no te gusta.
2. Dos hojas para elegir una versión.
3. Hoja vacía cuando no hay nada: parece que se trabó.
4. «Solo este episodio | Desde aquí» es una pregunta técnica que se hace antes de elegir.
5. Latino no siempre se ve como «lo tuyo» a primera vista cuando la fila es «Español» sin variante.

## Opciones

### V1 · Lista con íconos, un toque (recomendada)
Cada idioma es un encabezado con su bandera (🇲🇽 Latino, 🇪🇸 Castellano, 🇺🇸 Inglés). Debajo, renglones (no cápsulas): a la
izquierda un ícono de calidad (`4k.tv` / `tv` / `iphone`), el tamaño en gris, y a la derecha íconos de estado: ⚡ al instante,
☁︎ hay que pedirla, ✦ la recomendada, ⚠︎ «tal vez». **Tocar el renglón reproduce**; mantener presionado: Descargar, Infuse,
Otras del mismo tipo, nombre técnico. La tarjeta se va.
- Gana: un toque, cero cápsulas, se lee como la app de Música o TV de Apple.
- Pierde: los detalles («cómo sabemos el idioma») quedan a un toque largo; hay que enseñar los íconos (la ⓘ ya existe).

### V2 · Solo tu idioma, lo demás plegado
Igual que hoy, pero la hoja abre mostrando **solo Latino** (o tu primer idioma) y un renglón «Otros idiomas 🇪🇸 🇺🇸 🇯🇵 ›».
- Gana: casi siempre eliges latino; menos que leer.
- Pierde: si latino no existe, un toque de más; sigue con cápsulas si no se combina con V1.

### V3 · Quitar la pestaña «Todas las fuentes» y el segmento del episodio
«Todas» pasa a un botón chico al pie («Ver todas las fuentes, 34»). «Solo este episodio / Desde aquí» se vuelve un aviso
**después** de elegir: «¿Seguir la serie en Castellano?» con Sí / Solo este.
- Gana: el encabezado queda limpio; la pregunta llega cuando tiene sentido.
- Pierde: un aviso más después de elegir (solo cuando cambias de idioma, no siempre).

### V4 · Estado vacío con la causa y una salida
Si no hay versiones, la hoja dice por qué con la misma tabla que «Ver» (`UnavailableCause`): un ícono grande, una frase
(«Tu Real-Debrid venció») y un botón («Renovar», «Pedirlo y avisarme», «Reintentar»). Si latino no existe pero inglés sí:
«No hay en latino. 🇺🇸 Inglés con subtítulos ▶» arriba de todo.
- Gana: nunca una hoja en blanco; el caso «no hay latino» se resuelve en un toque.
- Pierde: nada importante; es trabajo de la hoja (la tabla ya existe).

### V5 · Mientras tarda: decir quién falta
El esqueleto se queda, y abajo los logos de los complementos que van contestando (✓ Torrentio, … Comet). A los 8 s, «Ver lo
que ya hay» para no esperar al lento.
- Gana: la espera se entiende; no te quedas viendo grises.
- Pierde: un detalle más en pantalla durante unos segundos.

### V6 · Idioma desconocido con ícono, no con frase
«No dice si latino o castellano» y «Tal vez» se vuelven un ícono `questionmark.circle` junto a la bandera 🇲🇽/🇪🇸 combinada (o
bandera gris). La frase completa solo en VoiceOver y al mantener presionado. Una versión «tal vez latino» va dentro de Latino
con su ⚠︎, no en una fila aparte, para que todo lo posiblemente latino quede junto.
- Gana: menos texto; latino concentra todo lo que podría serlo.
- Pierde: el riesgo de que una «tal vez» sea castellano se ve con un ícono, no con palabras.

## Recomendación

**V1 + V4 + V3**, en ese orden. V1 quita las cápsulas y una hoja entera (lo que más se siente); V4 arregla la hoja en blanco,
que hoy parece un error; V3 limpia el encabezado. V2, V5 y V6 después, cuando veas V1 en tu iPhone: con V1, V2 puede sobrar.

Para la TV: V1 y V4 aplican igual (lista con íconos, causa en la hoja); V3 ya es así en la TV (no tiene pestañas); se anota en el
registro de paridad al decidir.
