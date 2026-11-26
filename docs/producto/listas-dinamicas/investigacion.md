# Cómo ayudan los servicios a decidir qué ver (25 nov 2026)

Decisión de Fernando: **LD-C** (recetas + una hecha para ti) y **LV-A** (en Descubre). Las recetas viven en
`listas/explorar.json` (`recipes`, `daily`): cambiar la tabla en main cambia Explorar sin instalar nada.

## Hallazgos (resumen)
- Netflix arma la página entera y evita repetir títulos entre filas; usa miles de microgéneros (género + época + tono + origen).
- Mezcla editorial + personal funciona (Spotify, MUBI con «la película del día»).
- Explicar el porqué («Porque viste…», «8.1 en IMDb») da confianza; menos opciones a la vez (Top 10) reduce la parálisis.
- «Play Something» de Netflix (2021): un botón que elige por ti.
- Contexto: entre semana de noche gana lo corto; fin de semana, películas largas.
- No mostrar una y otra vez lo que ignoras; respetar la mezcla de gustos y dejar una fila «fuera de lo tuyo, pero cerca».

Fuentes: Netflix «Learning a Personalized Homepage»; Basilico, «Personalized Page Generation»; QCon SF 2018 (portadas);
SlashFilm y CNBC sobre «Play Something» (2021). Otras citadas de memoria: Steck «Calibrated Recommendations» (RecSys 2018).

## Ideas siguientes (por prioridad, sin decidir)
1. Porqué en cada tarjeta. 2. Recetas según el momento (corta entre semana, larga el domingo). 3. Bajar lo ignorado.
4. Un chip de ánimo o tiempo («Menos de 90 min»). 5. «La película del día» de las listas de críticos.
6. Arranque sin Trakt: pedir 3–5 títulos que te gustan. 7. Fila «fuera de lo tuyo, pero cerca».

## La TV
Lee la misma tabla, pero todavía no arma las recetas (pendiente en `docs/producto/paridad-registro.md`).
