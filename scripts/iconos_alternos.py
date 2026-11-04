#!/usr/bin/env python3
"""Genera los íconos alternos de la app (dorado, corona, noche, cloaca) a partir del ícono normal.

Uso (desde la raíz del repo):  python3 scripts/iconos_alternos.py [hoja.png]

- Parte de `ic_launcher_foreground.png` de xxxhdpi (432 px, el 💩 normal) y de `assets/emoji/crown.png`.
- Escribe en android/app/src/main/res/mipmap-*/ los PNG `ic_launcher_<id>.png` (cuadrado, para
  Androids viejos), `ic_launcher_<id>_foreground.png`, `ic_launcher_<id>_background.png` y
  `ic_launcher_<id>_monochrome.png`, y los XML adaptativos en mipmap-anydpi-v26/.
- Con un argumento también deja una hoja de contacto con los 5 íconos (a 192 y a 48 px).
- Se puede volver a correr: sobreescribe solo lo suyo. Necesita Pillow.
"""
import colorsys
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(RAIZ, 'android/app/src/main/res')
BASE = 432  # lado del foreground en xxxhdpi
DENSIDADES = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}  # x 108 px
IDS = ['dorado', 'corona', 'noche', 'cloaca']


def cargar_base():
    fg = Image.open(os.path.join(RES, 'mipmap-xxxhdpi/ic_launcher_foreground.png')).convert('RGBA')
    mono = Image.open(os.path.join(RES, 'mipmap-xxxhdpi/ic_launcher_monochrome.png')).convert('RGBA')
    return fg, mono


def tinte(img, f):
    """Aplica f(r,g,b)->(r,g,b) a los píxeles con color (deja el blanco de ojos y boca como está)."""
    out = img.copy()
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            if s < 0.18 and v > 0.8:  # blanco
                continue
            nr, ng, nb = f(h, s, v)
            px[x, y] = (round(nr * 255), round(ng * 255), round(nb * 255), a)
    return out


def dorado(h, s, v):
    # El marrón pasa a oro: tono 45 grados, más claro y saturado.
    return colorsys.hsv_to_rgb(0.125, min(1, 0.55 + s * 0.4), min(1, 0.45 + v * 0.75))


def noche(h, s, v):
    return colorsys.hsv_to_rgb(0.68, min(1, 0.25 + s * 0.35), min(1, 0.30 + v * 0.65))


def cloaca(h, s, v):
    return colorsys.hsv_to_rgb(0.27, min(1, 0.45 + s * 0.4), min(1, 0.25 + v * 0.7))


def degradado(tam, arriba, abajo):
    g = Image.new('RGBA', (tam, tam))
    d = ImageDraw.Draw(g)
    for y in range(tam):
        t = y / (tam - 1)
        c = tuple(round(arriba[i] + (abajo[i] - arriba[i]) * t) for i in range(3)) + (255,)
        d.line([(0, y), (tam, y)], fill=c)
    return g


def fondo_dorado():
    f = degradado(BASE, (255, 232, 130), (224, 160, 0))
    d = ImageDraw.Draw(f)
    # Destellos de cuatro puntas, dentro de la parte que se ve en todos los recortes.
    for x, y, r in ((105, 120, 22), (330, 105, 28), (320, 300, 18), (110, 300, 14)):
        d.polygon([(x, y - r), (x + r / 4, y - r / 4), (x + r, y), (x + r / 4, y + r / 4), (x, y + r),
                   (x - r / 4, y + r / 4), (x - r, y), (x - r / 4, y - r / 4)], fill=(255, 252, 215, 255))
    return f


def fondo_corona():
    return degradado(BASE, (90, 40, 150), (40, 16, 84))


def fondo_noche():
    f = degradado(BASE, (20, 24, 70), (6, 8, 28))
    d = ImageDraw.Draw(f)
    for x, y, r in ((100, 110, 5), (340, 215, 4), (95, 250, 4), (135, 85, 3), (330, 320, 4), (110, 330, 3), (260, 345, 3)):
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 250, 220, 255))
    # Luna creciente arriba a la derecha.
    d.ellipse([255, 85, 325, 155], fill=(255, 238, 170, 255))
    d.ellipse([275, 78, 345, 148], fill=(14, 17, 54, 255))
    return f


def fondo_cloaca():
    f = degradado(BASE, (46, 84, 52), (18, 36, 26))
    d = ImageDraw.Draw(f)
    # Burbujas y rejilla de alcantarilla abajo.
    for x, y, r in ((105, 120, 14), (325, 140, 10), (320, 270, 15), (100, 255, 9), (300, 95, 7)):
        d.ellipse([x - r, y - r, x + r, y + r], outline=(150, 220, 140, 255), width=4)
    for i in range(6):
        x = 40 + i * 70
        d.line([(x, 340), (x, BASE)], fill=(10, 22, 16, 255), width=10)
    d.line([(0, 340), (BASE, 340)], fill=(10, 22, 16, 255), width=10)
    return f


def poner_corona(fg):
    """El 👑 Fluent sobre la punta del 💩, algo ladeada; baja el 💩 un poco para que quepa."""
    corona = Image.open(os.path.join(RAIZ, 'assets/emoji/crown.png')).convert('RGBA')
    base = Image.new('RGBA', fg.size, (0, 0, 0, 0))
    chico = fg.resize((round(BASE * 0.92),) * 2, Image.LANCZOS)
    base.alpha_composite(chico, (round(BASE * 0.04) + 0, round(BASE * 0.10)))
    c = corona.resize((170, 170), Image.LANCZOS).rotate(-12, expand=True, resample=Image.BICUBIC)
    base.alpha_composite(c, (156, 24))
    return base


def silueta(img):
    """Monocromo: todo lo que tenga alfa, en blanco."""
    a = img.getchannel('A')
    return Image.merge('RGBA', (a.point(lambda v: 255), a.point(lambda v: 255), a.point(lambda v: 255), a))


def con_borde(fg, color, ancho=7):
    """Contorno del color dado alrededor del 💩 (se lee mejor a 48 px sobre fondos oscuros)."""
    a = fg.getchannel('A').filter(ImageFilter.MaxFilter(ancho * 2 + 1))
    borde = Image.new('RGBA', fg.size, color + (0,))
    borde.putalpha(a)
    borde.alpha_composite(fg)
    return borde


def construir():
    fg, mono = cargar_base()
    v = {}
    v['dorado'] = (fondo_dorado(), con_borde(tinte(fg, dorado), (120, 70, 0), 5), mono)
    cor = poner_corona(fg)
    v['corona'] = (fondo_corona(), cor, silueta(cor))
    v['noche'] = (fondo_noche(), con_borde(tinte(fg, noche), (200, 210, 255), 4), mono)
    v['cloaca'] = (fondo_cloaca(), con_borde(tinte(fg, cloaca), (10, 30, 14), 5), mono)
    return fg, v


def mascara_legacy(tam):
    """Esquinas apenas redondeadas, como el ícono normal."""
    m = Image.new('L', (tam * 4,) * 2, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, tam * 4 - 1, tam * 4 - 1], radius=tam * 4 // 7, fill=255)
    return m.resize((tam, tam), Image.LANCZOS)


def legacy(fondo, fg, tam):
    """PNG cuadrado de tam px: fondo + 💩 recortado al 100%."""
    im = fondo.resize((BASE, BASE), Image.LANCZOS).copy()
    im.alpha_composite(fg)
    # El foreground adaptativo es 108 dp con el dibujo al centro: se recorta la parte visible (72 dp).
    corte = BASE * 72 // 108
    o = (BASE - corte) // 2
    im = im.crop((o, o, o + corte, o + corte)).resize((tam, tam), Image.LANCZOS)
    im.putalpha(mascara_legacy(tam))
    return im


def guardar(im, carpeta, nombre, lado):
    d = os.path.join(RES, carpeta)
    os.makedirs(d, exist_ok=True)
    im.resize((lado, lado), Image.LANCZOS).save(os.path.join(d, nombre), optimize=True)


XML = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_{i}_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_{i}_foreground"/>
    <monochrome android:drawable="@mipmap/ic_launcher_{i}_monochrome"/>
</adaptive-icon>
"""


def escribir(v):
    for i, (fondo, fg, mono) in v.items():
        for dens, k in DENSIDADES.items():
            car = f'mipmap-{dens}'
            ad = round(108 * k)
            guardar(fondo, car, f'ic_launcher_{i}_background.png', ad)
            guardar(fg, car, f'ic_launcher_{i}_foreground.png', ad)
            guardar(mono, car, f'ic_launcher_{i}_monochrome.png', ad)
            lg = round(48 * k)
            legacy(fondo, fg, lg).save(os.path.join(RES, car, f'ic_launcher_{i}.png'), optimize=True)
        with open(os.path.join(RES, 'mipmap-anydpi-v26', f'ic_launcher_{i}.xml'), 'w') as f:
            f.write(XML.format(i=i))


def hoja(fg, v, destino):
    normal = Image.open(os.path.join(RES, 'mipmap-xxxhdpi/ic_launcher.png')).convert('RGBA')
    iconos = [('normal', normal)] + [(i, legacy(v[i][0], v[i][1], 192)) for i in IDS]
    W = 20 + len(iconos) * 212
    h = Image.new('RGBA', (W, 340), (235, 235, 235, 255))
    d = ImageDraw.Draw(h)
    for n, (nombre, ic) in enumerate(iconos):
        x = 20 + n * 212
        h.alpha_composite(ic, (x, 20))
        h.alpha_composite(ic.resize((48, 48), Image.LANCZOS), (x, 240))
        d.text((x, 225 if False else 300), nombre, fill=(0, 0, 0, 255))
    h.convert('RGB').save(destino)


if __name__ == '__main__':
    fg, v = construir()
    escribir(v)
    if len(sys.argv) > 1:
        hoja(fg, v, sys.argv[1])
    print('listo:', ', '.join(IDS))
