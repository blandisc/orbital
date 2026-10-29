"""Medidas de rendimiento de Orbital contra su presupuesto (docs/metricas.md).

Dos modos, los dos sin tocar nada de verdad:

    python scripts/perf_budget.py demo  [--url http://127.0.0.1:8737] [--out perf.json]
        La interfaz en Edge sin ventana contra el servidor de demostración: arranque, peticiones,
        botón → cuadro pintado, abrir la ficha, CPU en reposo por sección, memoria. Teclas solo aquí.

    python scripts/perf_budget.py real  [--seconds 60] [--out perf.json]
        La Orbital de la tele, solo leyendo: GET de la API (nada de POST ni teclas), CPU y memoria de
        sus procesos y el uso de GPU de su Edge durante un rato. Aborta si hay algo abierto.

Cada medida sale junto a su presupuesto y dice si cumple.
"""

from __future__ import annotations

import argparse
import json
import statistics
import subprocess
import sys
import time
import urllib.request

REAL = "http://127.0.0.1:8710"
NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)

# Presupuestos (docs/metricas.md). «≤» siempre: menos es mejor.
BUDGET = {
    "arranque_ms": 2500,             # abrir → Inicio usable (la marca ya en su lugar)
    "peticiones_arranque": 25,       # llamadas a /api en los primeros 8 s
    "boton_p50_ms": 50,              # botón → cuadro pintado
    "boton_p95_ms": 100,
    "cambio_seccion_p95_ms": 150,    # LB/RB → la sección nueva pintada
    "ficha_ms": 300,                 # A → la ficha a la vista (con datos locales)
    "tareas_largas": 0,              # tareas de más de 50 ms al moverse
    "reposo_cpu_pct": 2.0,           # de un núcleo, la página quieta (cualquier sección)
    "memoria_js_mb": 60,
    "api_local_p95_ms": 50,          # status, ui, settings, library (en caché)
    "api_listas_p95_ms": 300,        # una lista de Películas y series ya en caché
    "servidor_reposo_cpu_pct": 1.0,  # proceso del servidor, de un núcleo
    "edge_reposo_cpu_pct": 3.0,      # todos los procesos del Edge de Orbital
    "gpu_reposo_pct": 3.0,
    "supervisor_mb": 20,
    "servidor_mb": 250,
}

INIT = """
window.__perf = { inputs: [], long: [], marks: {} };
const after = (fn) => requestAnimationFrame(() => { const c = new MessageChannel(); c.port1.onmessage = fn; c.port2.postMessage(0); });
addEventListener('keydown', (e) => { const t0 = e.timeStamp; after(() => window.__perf.inputs.push({ key: e.key, ms: performance.now() - t0 })); }, true);
new PerformanceObserver((l) => l.getEntries().forEach((e) => window.__perf.long.push(Math.round(e.duration)))).observe({ type: 'longtask', buffered: true });
const watch = () => {
  const boot = document.getElementById('boot');
  if (!window.__perf.marks.listo && document.body?.dataset.view && (!boot || boot.classList.contains('boot--leaving'))) window.__perf.marks.listo = performance.now();
  if (!window.__perf.marks.listo) requestAnimationFrame(watch);
};
requestAnimationFrame(watch);
window.__visible = (sel, limit = 8000) => new Promise((done) => { const t0 = performance.now();
  const tick = () => { const el = document.querySelector(sel); if (el && !el.hidden && el.getBoundingClientRect().width) after(() => done(performance.now() - t0));
    else if (performance.now() - t0 > limit) done(-1); else requestAnimationFrame(tick); };
  tick(); });
"""


def pct(values, p):
    if not values:
        return None
    values = sorted(values)
    return round(values[min(len(values) - 1, int(round(p / 100 * (len(values) - 1))))], 1)


def get_ms(url, times=5):
    out = []
    for _ in range(times):
        t0 = time.perf_counter()
        try:
            with urllib.request.urlopen(url, timeout=20) as res:
                res.read()
        except OSError:
            return None
        out.append((time.perf_counter() - t0) * 1000)
    return {"frio_ms": round(out[0], 1), "p50_ms": pct(out[1:] or out, 50), "p95_ms": pct(out[1:] or out, 95)}


def api_latencies(base, list_ids):
    paths = ["/api/status", "/api/ui", "/api/settings", "/api/library", "/api/foryou", "/api/system"]
    paths += [f"/api/foryou/list?id={i}" for i in list_ids]
    return {p: get_ms(base + p) for p in paths}


def first_lists(base, n=3):
    try:
        with urllib.request.urlopen(base + "/api/foryou", timeout=20) as res:
            lists = json.load(res).get("lists", [])
    except (OSError, ValueError):
        return []
    return [urllib.request.quote(l["id"]) for l in lists if l.get("group") != "games"][:n]


# ---------------------------------------------------------------- demo
def demo(url):
    from playwright.sync_api import sync_playwright

    r = {}
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="msedge", headless=True)
        page = browser.new_page(viewport={"width": 1920, "height": 1080})
        page.add_init_script(INIT)
        cdp = page.context.new_cdp_session(page)
        cdp.send("Performance.enable")
        api = []
        page.on("request", lambda q: api.append(q.url.split("?")[0].split("/api/", 1)[1]) if "/api/" in q.url else None)

        def metrics():
            return {m["name"]: m["value"] for m in cdp.send("Performance.getMetrics")["metrics"]}

        def idle(seconds=10):
            a = metrics()
            page.wait_for_timeout(seconds * 1000)
            b = metrics()
            return round((b["TaskDuration"] - a["TaskDuration"]) / seconds * 100, 1)

        def keys(seq, gap=180):
            page.evaluate("window.__perf.inputs = []; window.__perf.long = []")
            for k in seq:
                page.keyboard.press(k)
                page.wait_for_timeout(gap)
            page.wait_for_timeout(300)
            return page.evaluate("window.__perf")

        page.goto(url)
        page.wait_for_function("window.__perf.marks.listo", timeout=30000)
        r["arranque_ms"] = round(page.evaluate("window.__perf.marks.listo"))
        page.wait_for_timeout(8000)
        r["peticiones_arranque"] = len(api)
        r["peticiones_por_ruta"] = {k: api.count(k) for k in sorted(set(api), key=api.count, reverse=True)[:6]}
        page.keyboard.press("Escape")  # el asistente de primera vez
        page.wait_for_timeout(1500)

        moves, longs = [], []
        perf = keys(["ArrowRight", "ArrowRight", "ArrowLeft", "ArrowLeft", "ArrowDown", "ArrowUp"] * 3)
        moves += [i["ms"] for i in perf["inputs"]]
        longs += perf["long"]
        r["reposo_cpu_pct"] = {"inicio": idle()}

        sections = []
        for name in ("para_ti", "juegos", "peliculas_series", "tv"):  # Para ti está a la izquierda de Inicio
            perf = keys(["q" if name == "para_ti" else "e"], gap=1500)
            sections += [i["ms"] for i in perf["inputs"]]
            r["reposo_cpu_pct"][name] = idle()
            if name == "para_ti":
                page.wait_for_timeout(30000)
                r["reposo_cpu_pct"]["para_ti_40s"] = idle()
            if name == "peliculas_series":
                # X en un destacado: «Episodios», la ficha (A reproduciría). -1 = no se abrió en 8 s.
                page.evaluate("window.__ficha = window.__visible('.title')")
                page.keyboard.press("x")
                r["ficha_ms"] = round(page.evaluate("window.__ficha"))
                page.wait_for_timeout(1500)
                page.keyboard.press("Escape")
                page.wait_for_timeout(800)
                perf = keys(["ArrowRight", "ArrowRight", "ArrowLeft", "ArrowLeft", "ArrowDown", "ArrowUp"] * 3)
                moves += [i["ms"] for i in perf["inputs"]]
                longs += perf["long"]
            if name == "para_ti":
                page.keyboard.press("e")  # de vuelta a Inicio para seguir el recorrido
                page.wait_for_timeout(1500)
        r["boton_p50_ms"], r["boton_p95_ms"] = pct(moves, 50), pct(moves, 95)
        r["cambio_seccion_p95_ms"] = pct(sections, 95)
        r["tareas_largas"] = len(longs)
        r["tareas_largas_ms"] = sorted(longs, reverse=True)[:5]
        m = metrics()
        r["memoria_js_mb"] = round(m["JSHeapUsedSize"] / 1e6, 1)
        r["nodos_dom"] = int(m["Nodes"])
        browser.close()
    r["api"] = api_latencies(url.rstrip("/"), first_lists(url.rstrip("/")))
    return r


# ---------------------------------------------------------------- real (solo lectura)
def ps(script):
    return subprocess.run(["powershell", "-NoProfile", "-Command", script], capture_output=True, text=True,
                          creationflags=NO_WINDOW, timeout=120).stdout


PROCS = r"""
$p = Get-CimInstance Win32_Process | Where-Object { ($_.Name -like 'python*' -and $_.CommandLine -match '-m orbital') -or ($_.Name -eq 'msedge.exe' -and $_.CommandLine -match 'orbital') }
$p | ForEach-Object { [pscustomobject]@{ pid = $_.ProcessId; parent = $_.ParentProcessId; name = $_.Name; cpu = ($_.KernelModeTime + $_.UserModeTime) / 1e7; mb = [math]::Round($_.PrivatePageCount / 1MB); gpu = ($_.CommandLine -match 'type=gpu-process') } } | ConvertTo-Json
"""


def processes():
    data = json.loads(ps(PROCS) or "[]")
    return data if isinstance(data, list) else [data]


def real(seconds):
    with urllib.request.urlopen(REAL + "/api/status", timeout=5) as res:
        if json.load(res).get("running"):
            sys.exit("Hay algo abierto en la tele: no mido (vuelve a correrlo cuando esté libre).")
    r = {"api": api_latencies(REAL, first_lists(REAL))}
    before = {p["pid"]: p for p in processes()}
    gpu = next((p["pid"] for p in before.values() if p["gpu"]), None)
    samples = []
    if gpu:
        counter = f"\\GPU Engine(pid_{gpu}_*engtype_3D)\\Utilization Percentage"
        out = ps(f"(Get-Counter '{counter}' -SampleInterval 1 -MaxSamples {seconds}).CounterSamples | "
                 "Group-Object Timestamp | ForEach-Object { ($_.Group | Measure-Object CookedValue -Sum).Sum }")
        samples = [float(x.replace(",", ".")) for x in out.split() if x.strip()]
    else:
        time.sleep(seconds)
    after = {p["pid"]: p for p in processes()}
    use = {pid: round((after[pid]["cpu"] - before[pid]["cpu"]) / seconds * 100, 2) for pid in after if pid in before}
    pythons = [p for p in after.values() if p["name"].startswith("python")]
    server = max(pythons, key=lambda p: p["mb"], default=None)
    supervisor = next((p for p in pythons if server and p["pid"] != server["pid"] and p["mb"] > 5), None)
    edges = [p for p in after.values() if p["name"] == "msedge.exe"]
    r.update({
        "segundos": seconds,
        "servidor_reposo_cpu_pct": use.get(server["pid"]) if server else None,
        "servidor_mb": server["mb"] if server else None,
        "supervisor_mb": supervisor["mb"] if supervisor else None,
        "edge_reposo_cpu_pct": round(sum(use.get(p["pid"], 0) for p in edges), 2),
        "edge_mb": sum(p["mb"] for p in edges),
        "gpu_reposo_pct": round(statistics.mean(samples), 2) if samples else None,
        "gpu_max_pct": round(max(samples), 2) if samples else None,
    })
    return r


# ---------------------------------------------------------------- informe
def verdicts(r):
    flat = dict(r)
    if isinstance(r.get("reposo_cpu_pct"), dict):
        flat["reposo_cpu_pct"] = max(r["reposo_cpu_pct"].values())
    api = r.get("api") or {}
    local = [v["p95_ms"] for k, v in api.items() if v and k in ("/api/status", "/api/ui", "/api/settings", "/api/library")]
    lists = [v["p95_ms"] for k, v in api.items() if v and k.startswith("/api/foryou/list")]
    if local:
        flat["api_local_p95_ms"] = max(local)
    if lists:
        flat["api_listas_p95_ms"] = max(lists)
    return {k: {"valor": flat[k], "presupuesto": b, "cumple": flat[k] <= b}
            for k, b in BUDGET.items() if isinstance(flat.get(k), (int, float)) and flat[k] >= 0}  # -1: no se pudo medir


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["demo", "real"])
    ap.add_argument("--url", default="http://127.0.0.1:8737/")
    ap.add_argument("--seconds", type=int, default=60)
    ap.add_argument("--out")
    a = ap.parse_args()
    r = demo(a.url) if a.mode == "demo" else real(a.seconds)
    r["presupuesto"] = verdicts(r)
    text = json.dumps(r, indent=1, ensure_ascii=False)
    if a.out:
        with open(a.out, "w", encoding="utf-8") as f:
            f.write(text)
    print(text)


if __name__ == "__main__":
    main()
