"""medir-posters.py — cuánto tarda en verse el mosaico de Explorar, haciendo lo mismo que el iPhone con cada póster: preguntar a
TMDB por su póster (`/find` con el id de IMDb, a lo más LOOKUPS a la vez) y bajar la versión ligera (w342, sin esperar turno)
y la buena (w500, a lo más DL a la vez). Usa la clave de TMDB de ios/App/Secrets.xcconfig (no va a git).

    python3 ios/scripts/medir-posters.py ids.txt 4          # como era antes del 25 nov 2026 (DL=12)
    DL=24 python3 ios/scripts/medir-posters.py ids.txt 32   # como es ahora

ids.txt: ids de IMDb («tt…»), uno por renglón; se usan los primeros 96. Dice cuándo se ve la mitad, cuándo todos y cuándo
termina todo.
"""
import concurrent.futures as cf
import json
import re
import sys
import threading
import time
import urllib.request

key=re.search(r'ORBITAL_TMDB_KEY\s*=\s*(\S+)',open(__import__('pathlib').Path(__file__).resolve().parent.parent/'App/Secrets.xcconfig').read()).group(1)
ids=open(sys.argv[1]).read().split()[:96]
gate=int(sys.argv[2]); sizes=(sys.argv[3] if len(sys.argv)>3 else 'w342,w500').split(','); lang=sys.argv[4] if len(sys.argv)>4 else 'es-MX'
dl=threading.Semaphore(int(__import__("os").environ.get("DL","12"))); lk=threading.Semaphore(gate)
def get(u):
    with urllib.request.urlopen(urllib.request.Request(u,headers={'User-Agent':'bench'}),timeout=20) as r: return r.read()
t0=time.time(); first={}; done={}
def one(i):
    with lk:
        d=json.loads(get(f'https://api.themoviedb.org/3/find/{i}?api_key={key}&external_source=imdb_id&language={lang}'))
    rows=d.get('movie_results',[])+d.get('tv_results',[]); p=next((r['poster_path'] for r in rows if r.get('poster_path')),None)
    if not p: return
    for s in sizes:
        if s=='w342': get(f'https://image.tmdb.org/t/p/{s}{p}')
        else:
            with dl: get(f'https://image.tmdb.org/t/p/{s}{p}')
        first.setdefault(i,time.time()-t0)
    done[i]=time.time()-t0
with cf.ThreadPoolExecutor(200) as ex: list(ex.map(one,ids))
f=sorted(first.values()); print(f"{sys.argv[2:]} pósters {len(f)} · mitad visibles {f[len(f)//2]:.1f}s · todos visibles {f[-1]:.1f}s · todo listo {max(done.values()):.1f}s")
