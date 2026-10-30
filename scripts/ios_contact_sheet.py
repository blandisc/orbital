"""Junta capturas de 4 en 4 (lado a lado, con su nombre) para revisarlas de un vistazo.

    python3 scripts/ios_contact_sheet.py <carpeta-con-png> <prefijo-de-salida>

Escribe <prefijo>-1.jpg, <prefijo>-2.jpg… Necesita Pillow.
"""
import glob
import os
import sys

from PIL import Image, ImageDraw

src, out = sys.argv[1], sys.argv[2]
files = sorted(glob.glob(os.path.join(src, '*.png')))
for k in range(0, len(files), 4):
    group = files[k:k + 4]
    ims = [Image.open(f).convert('RGB') for f in group]
    w = 500
    ims = [im.resize((w, int(im.height * w / im.width))) for im in ims]
    h = max(im.height for im in ims) + 30
    sheet = Image.new('RGB', (w * len(ims) + 10 * (len(ims) - 1), h), 'white')
    d = ImageDraw.Draw(sheet)
    for i, (im, f) in enumerate(zip(ims, group)):
        x = i * (w + 10)
        sheet.paste(im, (x, 30))
        d.text((x + 5, 8), os.path.basename(f), fill='black')
    sheet.save(f'{out}-{k // 4 + 1}.jpg', quality=72)
    print(f'{out}-{k // 4 + 1}.jpg')
