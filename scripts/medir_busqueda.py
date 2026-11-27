"""Mide la búsqueda con números, para comparar un antes y un después (26 nov 2026).

    python3 scripts/medir_busqueda.py relevancia [--repo OTRA_COPIA]   # ¿sale arriba lo que buscabas?
    python3 scripts/medir_busqueda.py posters [--rondas 5]              # ¿cuánto tardan los pósters de Buscar?

Relevancia: una lista fija de búsquedas, cada una con el título (o los títulos) que una persona espera arriba, escrita
antes de medir. Se corre el mismo orden que usa la TV (`orbital/library/cinemeta.py`, idéntico al del iPhone por la
prueba de paridad) contra Cinemeta real. Cuenta: acierto en el 1.º lugar, en los 3 primeros y el rango recíproco medio
(MRR: 1 si va primero, 1/2 si va segundo…, 0 si no sale en los 10 primeros). `--repo` apunta a otra copia del repo
(por ejemplo un `git worktree` en un commit viejo) para medir el antes con su propio código.

Pósters: lo que descarga la pantalla de Buscar del iPhone para los primeros 10 resultados de cada búsqueda. Antes:
cada póster pedía la versión ligera («small», 300 px) y, a la vez, la buena («medium»). Después: solo la «small», que
ya cubre la celda. Se mide en frío (conexión nueva por ronda), alternando el orden, y se reporta la mediana del tiempo
hasta que todos los pósters están completos y los bytes. Solo usa servidores públicos (Cinemeta, metahub).
"""

from __future__ import annotations

import argparse
import statistics
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

# Lo que una persona espera ver primero al escribir cada cosa (cualquiera de los ids cuenta como acierto).
GOLD: dict[str, set[str]] = {
    "avengers": {"tt4154796", "tt0848228", "tt4154756"},
    "batman": {"tt1877830", "tt0096895", "tt0468569", "tt0372784"},
    "matrix": {"tt0133093"},
    "the office": {"tt0386676"},
    "ofice": {"tt0386676"},
    "friends": {"tt0108778"},
    "breaking bad": {"tt0903747"},
    "harry potter": {"tt0241527", "tt0295297", "tt0304141", "tt0330373", "tt0373889", "tt0417741", "tt0926084", "tt1201607"},
    "star wars": {"tt0076759", "tt0080684", "tt0086190", "tt2488496"},
    "spider man": {"tt0145487", "tt10872600", "tt4633694", "tt2250912", "tt9362722"},
    "dune": {"tt1160419", "tt15239678"},
    "joker": {"tt7286456"},
    "titanic": {"tt0120338"},
    "game of thrones": {"tt0944947"},
    "the last of us": {"tt3581920"},
    "stranger things": {"tt4574334"},
    "inception": {"tt1375666"},
    "interstellar": {"tt0816692"},
    "simpsons": {"tt0096697"},
    "toy story": {"tt0114709", "tt0120363", "tt0435761", "tt1979376"},
    "frozen": {"tt2294629"},
    "avatar": {"tt0499549", "tt1630029", "tt0417299"},
    "oppenheimer": {"tt15398776"},
    "barbie": {"tt1517268"},
    "the bear": {"tt14452776"},
    "shrek": {"tt0126029"},
    "lord of the rings": {"tt0120737", "tt0167261", "tt0167260"},
    "succession": {"tt7660850"},
    "wednesday": {"tt13443470"},
    "squid game": {"tt10919420"},
}

# De control: escritas antes de ajustar la fórmula y nunca usadas para ajustarla (para no aprenderse la lista de arriba).
HOLDOUT: dict[str, set[str]] = {
    "the godfather": {"tt0068646"},
    "gladiator": {"tt0172495", "tt9218128"},
    "pulp fiction": {"tt0110912"},
    "the sopranos": {"tt0141842"},
    "lost": {"tt0411008"},
    "house of the dragon": {"tt11198330"},
    "mandalorian": {"tt8111088"},
    "jurassic park": {"tt0107290"},
    "finding nemo": {"tt0266543"},
    "the witcher": {"tt5180504"},
    "parasite": {"tt6751668"},
    "seinfeld": {"tt0098904"},
    "the boys": {"tt1190634"},
    "black mirror": {"tt2085059"},
    "gravity": {"tt1454468"},
    "up": {"tt1049413"},
    "her": {"tt1798709"},
    "cars": {"tt0317219"},
    "alien": {"tt0078748"},
    "fight club": {"tt0137523"},
}


def load(repo: Path):
    sys.path.insert(0, str(repo))
    from orbital.library import cinemeta  # noqa: PLC0415 (cada copia trae su propio código)
    return cinemeta


def ranked(cm, client, query: str) -> list[str]:
    movies, series = client.search("movie", query), client.search("series", query)
    if hasattr(cm, "fame_lookup"):   # después: parecido × fama
        return [r["meta_id"] for r in cm.search_results(query, movies, series, fame=cm.fame_lookup(client, movies, series, limit=10))]
    ties = cm.tie_popularity(client, query, movies, series, limit=10)   # antes: solo empates exactos
    return [r["meta_id"] for r in cm.search_results(query, movies, series, popularity=ties)]


def relevancia(repo: Path) -> None:
    cm = load(repo)
    client = cm.Cinemeta()
    for label, gold in (("Ajuste (30)", GOLD), ("Control (20)", HOLDOUT)):
        hits1 = hits3 = 0
        rr: list[float] = []
        print(f"— {label}")
        for query, want in gold.items():
            ids = ranked(cm, client, query)[:10]
            pos = next((i for i, x in enumerate(ids) if x in want), None)
            hits1 += pos == 0
            hits3 += pos is not None and pos < 3
            rr.append(0.0 if pos is None else 1 / (pos + 1))
            print(f"  {query:20} {'—' if pos is None else pos + 1:>2}  {' '.join(ids[:3])}")
        n = len(gold)
        print(f"  1.º lugar {hits1}/{n} ({hits1 / n:.0%}) · top 3 {hits3}/{n} ({hits3 / n:.0%}) · MRR {statistics.mean(rr):.3f}\n")


def fetch(url: str, start: float) -> tuple[int, float]:
    req = urllib.request.Request(url, headers={"User-Agent": "orbital-bench"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            size = len(r.read())
    except OSError:   # un póster que no existe (404): la celda se queda en su sombra, igual en los dos lados
        size = 0
    return size, time.perf_counter() - start


def batch(urls: list[str]) -> tuple[list[float], int]:
    """Todos a la vez, como el iPhone; devuelve cuándo terminó cada una (segundos) y los bytes."""
    start = time.perf_counter()
    with ThreadPoolExecutor(max_workers=len(urls)) as pool:
        done = list(pool.map(lambda u: fetch(u, start), urls))
    return [t for _, t in done], sum(size for size, _ in done)


def posters(rounds: int) -> None:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from orbital.library import cinemeta  # noqa: PLC0415
    client = cinemeta.Cinemeta()
    queries = ["avengers", "batman", "harry potter", "star wars", "toy story", "simpsons"]
    small = {q: [m["poster"] for m in client.search("movie", q)[:10] if "metahub" in str(m.get("poster"))] for q in queries}
    medium = {q: [u.replace("/poster/small/", "/poster/medium/") for u in small[q]] for q in queries}
    # «visible»: cuando ya hay algo en las 10 celdas; «completo»: cuando cada celda tiene su imagen final.
    visible: dict[str, list[float]] = {"antes": [], "después": []}
    complete: dict[str, list[float]] = {"antes": [], "después": []}
    sizes: dict[str, list[int]] = {"antes": [], "después": []}
    for i in range(rounds):
        for name in (["antes", "después"] if i % 2 == 0 else ["después", "antes"]):
            for q in queries:
                n = len(small[q])
                if name == "antes":   # la ligera y la buena de cada póster, a la vez (RemoteImage con 600 px)
                    times, size = batch(small[q] + medium[q])
                    visible[name].append(max(times[:n]))
                    complete[name].append(max(times[n:]))
                else:                 # solo la chica (Artwork.thumbnail)
                    times, size = batch(small[q])
                    visible[name].append(max(times))
                    complete[name].append(max(times))
                sizes[name].append(size)
    ms = lambda xs: statistics.median(xs) * 1000  # noqa: E731
    for name in ("antes", "después"):
        print(f"{name:8} visibles {ms(visible[name]):5.0f} ms · completos {ms(complete[name]):5.0f} ms (p90 "
              f"{statistics.quantiles(complete[name], n=10)[-1] * 1000:5.0f}) · {statistics.mean(sizes[name]) / 1024:5.0f} KB por búsqueda")
    print(f"\nCompletos: el después tarda {ms(complete['después']) / ms(complete['antes']):.0%} del antes · visibles: "
          f"{ms(visible['después']) / ms(visible['antes']):.0%} · bytes: {statistics.mean(sizes['después']) / statistics.mean(sizes['antes']):.0%}")
    print(f"({rounds} rondas × {len(queries)} búsquedas por lado, en frío, alternando cuál va primero)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("what", choices=["relevancia", "posters"])
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--rondas", type=int, default=5)
    args = parser.parse_args()
    relevancia(args.repo) if args.what == "relevancia" else posters(args.rondas)
