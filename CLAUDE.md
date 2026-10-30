# Orbital

Interfaz de consola para la TV (Windows, Legion Go), en español, que se usa con mando.

## Antes de tocar la interfaz

- Lee `docs/sistema-de-diseno.md`. **Nada se crea suelto**: toda pieza nueva entra al catálogo
  (`orbital/web/js/components/` + `orbital/web/styles/components/`) y todo valor visual es un token
  (`styles/tokens.css`, `styles/themes/orbital.css`). Las excepciones se marcan con
  `ds-exception: <motivo>` y se documentan en la sección «Excepciones».
- `tests/web/design-system.test.mjs` lo verifica: colores, duraciones, capas y tamaños de letra a mano,
  tokens inexistentes o sin uso, componentes fuera del catálogo, CSS muerto y colores fijos en JS.

## Las cuatro superficies

Todo cambio en la app de escritorio se diseña y se prueba para **control, teclado, mouse y touch** (regla completa en
`docs/sistema-de-diseno.md` § 5). Un atajo de mando siempre tiene camino visible en el menú, y el menú lo dice.

## Pruebas

```bash
node --test tests/web/*.test.mjs
```

```bash
.venv/Scripts/python -m pytest -q --ignore=tests/smoke
```

```bash
.venv/Scripts/python -m ruff check .
```

```bash
npx --yes pyright@1.1.390
```

(La CI de GitHub corre las cuatro; pyright necesita el `.venv` en el PATH para encontrar las dependencias.)

Pruebas de humo (navegador real): `ORBITAL_SMOKE_BROWSER=msedge .venv/Scripts/python -m pytest -q tests/smoke`.

## Ver la interfaz y probar en la TV

`scripts/demo_server.py --port <puerto>` levanta una biblioteca de demostración: es lo primero para ver la interfaz
sin tocar la TV.

Probar en la Orbital real (`127.0.0.1:8710`) con teclas, clics, toques o mando **sí se vale** (Fernando, 2026-10-30),
con cuidado, porque una tecla Enter ahí abre juegos de verdad:

- Antes, el candado de la tele (`%LOCALAPPDATA%\orbital\tele.lock`) y `GET /api/status` con `running` en null; si hay
  algo abierto, no se prueba.
- Respalda `%APPDATA%\orbital\state.json` y `config.yaml`; al terminar, regresa el historial, los ajustes y la
  resolución, y cierra todo lo que abriste.
- Ninguna ventana visible: usa `pythonw` y `CREATE_NO_WINDOW`.
