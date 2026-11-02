# Auditoría de la app iOS · 31 oct 2026

Revisión de fondo de la app del iPhone, iPad y Mac (código y arquitectura, sistema de diseño y regresión en el simulador)
sobre `de2dbd89`, y los arreglos que salieron de ella. Página para el celular con el diagnóstico:
https://claude.ai/artifact/4jHKNrWXKusqjGxZdd63kS

- `hallazgos.md`: todos los hallazgos con archivo y línea (R = regresión, A/B/C = código, D = diseño).
- `reglas-para-agentes.md`: cómo trabajan los agentes que arreglan (solo `ios/`, mismo checkout, compilaciones, evidencia).
- `estado.md`: qué quedó hecho, qué falta y en qué orden.

Decisión de Fernando (1 nov, reemplaza la del 31 oct): las cápsulas de temporada «T1, T2…» van solo en el reproductor; en la
ficha de la serie, Mi media y la hoja de episodios, una lista desplegable nativa (`DSSeasonMenu`). Hecho en la tanda 6.
Alcance (Fernando, 31 oct): todo es solo para la app iOS, salvo lo necesario para que la CI de GitHub pase.
