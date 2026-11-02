# La marca de Orbital

El planeta con su anillo y la luna turquesa, «pulido» el 1 nov 2026: el anillo es una pincelada que engorda al pasar por
delante y termina en punta, el hueco donde cruza el planeta es limpio y la luna va sobre una órbita concéntrica al anillo.

- **Las versiones se cuentan en lunas** sobre esa órbita: Orbital una, Plus dos, Ultra tres. **Listas pero apagadas**
  (Fernando, 1 nov): por ahora todas las apps llevan la de una luna. Cada una en clásico (grafito)
  y Cielo nocturno (azul de medianoche, lunas crema que brillan). La app de la TV lleva la marca sola, con una luna.
- **El nombre**: «orbital» en minúsculas con Sora SemiBold (licencia OFL), igual en la TV (`orbital/web/fonts`,
  `--font-brand`) y en el iPhone (`ios/App/Resources/Fonts`, `DS.Brand.wordFont`), con la luna como punto final junto a
  la «l».

Todo sale de un solo dibujo: `python scripts/make_icon.py` escribe estos SVG y PNG, los íconos del iPhone (AppIcon,
oscuro, teñido, Cielo nocturno y sus vistas previas) y los de Windows (`orbital/web/icons`). La marca chica de las apps
(`icons.js · mark`, `index.html`, `OrbitalMark`) usa la misma geometría en la caja de 32.
