"""Lee lo que graba medir-mac-sin-manos.sh: el arranque en frío y, por orden, cuánto trabajó el hilo de la pantalla, cuándo
quedó quieta y el congelamiento más largo. Uso: medir_mac_sin_manos.py <carpeta> <epoch del open> <pid de la app>"""
import collections, datetime, json, re, subprocess, sys, xml.etree.ElementTree as ET

out, t_open, pid = sys.argv[1], float(sys.argv[2]), sys.argv[3]
mine = f"pid: {pid})"   # solo la de la Mac: la Orbital de un simulador también se llama así


def export(trace, *args):
    return subprocess.run(["xcrun", "xctrace", "export", "--input", trace, *args], capture_output=True, text=True).stdout


def read(trace):
    """Muestras del hilo principal de Orbital y congelamientos (inicio, ms), en segundos del reloj."""
    found = re.search(r"<start-date>([^<]+)</start-date>", export(trace, "--toc"))
    if not found: sys.exit(f"{trace}: sin grabación (Instruments no la cerró); repite la ronda")
    start = datetime.datetime.fromisoformat(found.group(1)).timestamp()
    def table(schema):
        return ET.fromstring(export(trace, "--xpath", f'/trace-toc/run[@number="1"]/data/table[@schema="{schema}"]'))
    p = table("time-profile"); ids = {e.get("id"): e for e in p.iter() if e.get("id")}
    d = lambda e: ids[e.get("ref")] if e.get("ref") else e
    main = sorted(start + int(d(r.find("sample-time")).text) / 1e9 for r in p.iter("row")
                  if "Main Thread" in (d(r.find("thread")).get("fmt") or "") and mine in (d(r.find("thread")).get("fmt") or ""))
    h = table("potential-hangs"); hid = {e.get("id"): e for e in h.iter() if e.get("id")}
    hr = lambda e: hid[e.get("ref")] if e.get("ref") else e
    hangs = []
    for row in h.iter("row"):
        st = [e for e in row.iter() if e.tag in ("start-time", "event-time", "sample-time")]; ln = [e for e in row.iter() if e.tag == "duration"]
        procs = [hr(e).get("fmt") or "" for e in row.iter() if e.tag == "process"]
        if procs and not any(f"({pid})" in x or f"pid: {pid}" in x for x in procs): continue
        if st and ln: hangs.append((start + int(hr(st[0]).text) / 1e9, int(hr(ln[0]).text) / 1e6))
    return main, hangs, start


def window(samples, hangs, t, hi):
    w = [x for x in samples if t <= x < hi]
    bins = collections.Counter(int((x - t) / 0.05) for x in w); dense = [k for k, c in bins.items() if c >= 15]
    return len(w), (max(dense) + 1) * 50 if dense else 0, max([ms for a, ms in hangs if t - 0.05 <= a <= hi] or [0])


main, hangs, _ = read(f"{out}/arranque.trace")
work, quiet, worst = window(main, hangs, t_open, t_open + 5)
print(f"ARRANQUE quieta {quiet} ms · trabajo {work} ms (primeros 5 s) · bloqueo mayor {worst:.0f} ms")

marks, frames = [], []
for line in open(f"{out}/marcas.ndjson"):
    try: e = json.loads(line)
    except ValueError: continue
    msg = e.get("eventMessage", "")
    if msg.startswith("mark "):
        marks.append((msg[5:], datetime.datetime.strptime(e["timestamp"][:26], "%Y-%m-%d %H:%M:%S.%f").timestamp()))
    elif msg.startswith("frames "):   # lo que mide `scroll` cuadro por cuadro (MacDrive.ScrollDriver)
        frames.append((marks[-1][0] if marks else "?", msg))
main, hangs, began = read(f"{out}/ordenes.trace")
print(f"{'orden':<28}{'trabajo':>8}{'quieta':>8}{'bloqueo':>8}")
for i, (name, t) in enumerate(marks):
    hi = marks[i + 1][1] - 0.05 if i + 1 < len(marks) else t + 5
    if t < began: print(f"{name[:28]:<28}{'—':>8}{'—':>8}{'—':>8}  (Instruments aún no grababa)"); continue
    work, quiet, worst = window(main, hangs, t, hi)
    print(f"{name[:28]:<28}{work:>8}{quiet:>8}{worst:>8.0f}")
if frames:
    print("\nDESLIZAR (cuadro por cuadro; tirones = ms atrasados por segundo, < 5 fluido, > 10 se nota)")
    for name, msg in frames: print(f"{name[:28]:<28}{msg}")
