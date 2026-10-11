"""Rutas HTTP de Orbital, una pieza por área. `server.create_app` las junta.

  * library   — biblioteca, preferencias, carátulas
  * play      — abrir, estado, cerrar, ventanas y energía
  * media     — películas y series (Stremio, Cinemeta, reproductor)
  * ui        — la interfaz: ajustes, recargar, mostrar, salir
  * live      — eventos en vivo (SSE) y voz
  * diagnostics — qué ve Orbital de su equipo (para "Diagnóstico")

Cada módulo expone `router(deps)`: las dependencias llegan explícitas en `Deps`, no por globales.
"""
