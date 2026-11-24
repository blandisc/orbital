"""Lee una grabación de Instruments de Orbital (medir-clics-mac.sh) y dice, por clic, cuánto trabajó el hilo de la pantalla,
cuándo quedó quieta y el congelamiento más largo. Uso: medir_clics.py <grabación.trace> [clics.txt]"""
import collections, datetime, re, subprocess, sys, xml.etree.ElementTree as ET

trace = sys.argv[1]
clicks = sys.argv[2] if len(sys.argv) > 2 else None


def table(schema):
    xpath = f'/trace-toc/run[@number="1"]/data/table[@schema="{schema}"]'
    out = subprocess.run(["xcrun", "xctrace", "export", "--input", trace, "--xpath", xpath], capture_output=True, text=True).stdout
    return ET.fromstring(out)


profile = table("time-profile")
by_id = {e.get("id"): e for e in profile.iter() if e.get("id")}
deref = lambda e: by_id[e.get("ref")] if e.get("ref") else e
samples = sorted(int(deref(r.find("sample-time")).text) / 1e9 for r in profile.iter("row")
                 if "Main Thread" in deref(r.find("thread")).get("fmt"))
hangs_table = table("potential-hangs")
hang_ids = {e.get("id"): e for e in hangs_table.iter() if e.get("id")}
href = lambda e: hang_ids[e.get("ref")] if e.get("ref") else e
hangs = []
for row in hangs_table.iter("row"):
    start = [e for e in row.iter() if e.tag in ("start-time", "event-time", "sample-time")]
    length = [e for e in row.iter() if e.tag == "duration"]
    if start and length:
        hangs.append((int(href(start[0]).text) / 1e9, int(href(length[0]).text) / 1e6))


def report(name, window):
    if not window:
        print(f"{name:<16}{0:>11}")
        return
    onset = window[0]
    buckets = collections.Counter(int((t - onset) / 0.05) for t in window)
    dense = [k for k, c in buckets.items() if c >= 15]   # 15 ms de trabajo en 50 ms
    settle = (max(dense) + 1) * 50 if dense else 0
    worst = max([d for s, d in hangs if window[0] - 0.05 <= s <= window[-1]] or [0])
    print(f"{name:<16}{len(window):>11}{settle:>14}{worst:>12.0f}")


print(f"{'clic':<16}{'trabajo ms':>11}{'quieta en ms':>14}{'bloqueo ms':>12}")
if clicks:
    toc = subprocess.run(["xcrun", "xctrace", "export", "--input", trace, "--toc"], capture_output=True, text=True).stdout
    start = datetime.datetime.fromisoformat(re.search(r"<start-date>([^<]+)</start-date>", toc).group(1)).timestamp()
    marks = [(n, float(t) - start) for n, t in (line.split() for line in open(clicks) if line.strip())]
    for i, (name, t) in enumerate(marks):
        lo = t - 1.2   # la hora se anota justo después del clic
        hi = marks[i + 1][1] - 1.2 if i + 1 < len(marks) else t + 8
        report(name, [x for x in samples if lo <= x < hi])
else:
    burst, bursts = [], []
    for t in samples:
        if burst and t - burst[-1] > 0.4:
            bursts.append(burst)
            burst = []
        burst.append(t)
    if burst:
        bursts.append(burst)
    for b in bursts:
        if len(b) >= 30:
            report(f"a los {b[0]:.1f} s", b)
