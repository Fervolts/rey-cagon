#!/usr/bin/env python3
# Genera los efectos (.wav) y las músicas (.m4a) de los minijuegos.
# Todo es síntesis propia: no usa grabaciones ni samples de nadie.
# Requiere solo numpy y ffmpeg. Uso: python3 scripts/sonidos.py
# Es determinista: cada sonido tiene su propia semilla fija.

import os
import shutil
import subprocess
import tempfile
import wave
import zlib

import numpy as np

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SALIDA = os.path.join(RAIZ, 'assets', 'sonidos')
SR = 22050      # efectos
SRM = 44100     # música
TAU = 2 * np.pi
PICO = 10 ** (-1 / 20)  # -1 dBFS
KBPS_MUSICA = 48

R = np.random.default_rng(0)


def semilla(nombre):
    # Semilla estable por nombre: cambiar un sonido no altera los demás.
    global R
    R = np.random.default_rng(zlib.crc32(nombre.encode()))


# ---------------------------------------------------------------- utilidades

def muestras(d, sr=SR):
    return int(round(d * sr))


def tiempo(d, sr=SR):
    return np.arange(muestras(d, sr)) / sr


def ruido(n):
    return R.standard_normal(n)


def filtro_fft(x, sr, bajo=None, alto=None, orden=2, circular=False):
    # Filtro de fase cero en frecuencia: 'bajo' corta graves, 'alto' corta agudos.
    n = len(x)
    m = n if circular else 1 << int(np.ceil(np.log2(max(2, n) * 2)))
    X = np.fft.rfft(x, m)
    f = np.fft.rfftfreq(m, 1 / sr)
    h = np.ones_like(f)
    if alto:
        h /= np.sqrt(1 + (f / alto) ** (2 * orden))
    if bajo:
        h /= np.sqrt(1 + (bajo / np.maximum(f, 1e-6)) ** (2 * orden))
    return np.fft.irfft(X * h, m)[:n]


def suave(n, corte, sr=SR):
    # Ruido lento normalizado (para jitter y modulaciones).
    x = filtro_fft(ruido(n), sr, alto=corte)
    return x / (np.std(x) + 1e-12)


def svf(x, fc, q=0.707, sr=SR, modo='bp'):
    # Filtro de estado variable (TPT) con corte y Q que cambian por muestra.
    n = len(x)
    fc = np.broadcast_to(np.asarray(fc, float), (n,))
    q = np.broadcast_to(np.asarray(q, float), (n,))
    g = np.tan(np.pi * np.clip(fc, 10, sr * 0.45) / sr)
    k = 1 / q
    a1 = 1 / (1 + g * (g + k))
    a2 = g * a1
    a3 = g * a2
    xs, A1, A2, A3, K = x.tolist(), a1.tolist(), a2.tolist(), a3.tolist(), k.tolist()
    ic1 = ic2 = 0.0
    out = [0.0] * n
    m = {'lp': 0, 'bp': 1, 'hp': 2}[modo]
    for i in range(n):
        v3 = xs[i] - ic2
        v1 = A1[i] * ic1 + A2[i] * v3
        v2 = ic2 + A2[i] * ic1 + A3[i] * v3
        ic1 = 2 * v1 - ic1
        ic2 = 2 * v2 - ic2
        if m == 0:
            out[i] = v2
        elif m == 1:
            out[i] = K[i] * v1
        else:
            out[i] = xs[i] - K[i] * v1 - v2
    return np.array(out)


def adsr(n, a, d, s, r, sr=SR):
    # Envolvente: ataque lineal, caída exponencial a 's', soltar con coseno al final.
    t = np.arange(n) / sr
    e = np.where(t < a, t / max(a, 1e-6), s + (1 - s) * np.exp(-(t - a) / max(d, 1e-6)))
    nr = min(n, muestras(r, sr))
    if nr > 0:
        e[n - nr:] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, nr))
    return e


def formante(fk, picos):
    # Suma de resonancias gaussianas: (centro, ancho, ganancia).
    return sum(g * np.exp(-0.5 * ((fk - c) / b) ** 2) for c, b, g in picos)


def aditivo(f0, peso, sr=SR, nmax=80):
    # Oscilador aditivo sin aliasing: peso(k, frecuencia_k) da la amplitud del armónico k.
    fase = TAU * np.cumsum(f0) / sr
    out = np.zeros(len(f0))
    ny = sr * 0.45
    for k in range(1, nmax + 1):
        fk = k * f0
        if fk.min() > ny:
            break
        lim = np.clip((ny - fk) / (sr * 0.04), 0, 1)
        out += peso(k, fk) * lim * np.sin(k * fase)
    return out


def seno_f(f, sr=SR):
    return np.sin(TAU * np.cumsum(f) / sr)


def mezclar(buf, sig, t0, g=1.0, sr=SR):
    i = muestras(t0, sr)
    j = min(len(buf), i + len(sig))
    if j > i:
        buf[i:j] += g * sig[:j - i]


def burbuja(f_ini, f_fin, barrido, tau, dur=None, sr=SR):
    # Burbuja: seno que sube de tono y se apaga (como una burbuja real).
    dur = dur or min(1.0, tau * 7)
    t = tiempo(dur, sr)
    f = f_ini * (f_fin / f_ini) ** np.clip(t / barrido, 0, 1)
    amp = (1 - np.exp(-t / 0.0015)) * np.exp(-t / tau)
    return seno_f(f, sr) * amp


def clic(dur, bajo, alto, tau, sr=SR):
    t = tiempo(dur, sr)
    return filtro_fft(ruido(len(t)), sr, bajo, alto) * np.exp(-t / tau)


def pulso(f0, ancho, picos, sr=SR, nmax=60, piso=0.12):
    # Pulso de ancho variable pasado por formantes (base de pedos y chupones).
    return aditivo(f0, lambda k, fk: np.sin(np.pi * k * ancho) / k * (piso + formante(fk, picos)), sr, nmax)


def norm(x):
    return x / (np.max(np.abs(x)) + 1e-12)


# ------------------------------------------------------------ cierre efectos

def terminar(x, sr=SR):
    # Quita DC, recorta el silencio del principio, fades sin clic y pico a -1 dBFS.
    x = svf(np.asarray(x, float), 22, 0.7, sr, 'hp')
    umbral = 10 ** (-45 / 20) * np.max(np.abs(x))
    i = int(np.argmax(np.abs(x) > umbral))
    x = x[i:].copy()
    fi = 8
    x[:fi] *= np.linspace(0, 1, fi)
    fo = min(muestras(0.02, sr), len(x) // 4)
    x[-fo:] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, fo))
    return x * PICO / np.max(np.abs(x))


def escribir_wav(ruta, x, sr):
    d = np.clip(np.round(x * 32767), -32768, 32767).astype('<i2')
    with wave.open(ruta, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(d.tobytes())


# ------------------------------------------------------------------ efectos

def fx_plop():
    b = np.zeros(muestras(0.3))
    mezclar(b, clic(0.006, 300, 3000, 0.0015), 0, 0.35)
    mezclar(b, burbuja(330, 1150, 0.07, 0.055), 0.002, 1.0)
    mezclar(b, burbuja(620, 1500, 0.04, 0.03), 0.085, 0.4)
    mezclar(b, burbuja(900, 1900, 0.03, 0.018), 0.15, 0.2)
    rizo = svf(ruido(len(b)), 1800, 2.0, modo='bp') * np.exp(-np.arange(len(b)) / SR / 0.07)
    return b + 0.06 * rizo


def fx_chapuzon():
    n = muestras(0.4)
    t = np.arange(n) / SR
    b = np.zeros(n)
    golpe = seno_f(45 + 75 * np.exp(-t / 0.035)) * np.exp(-t / 0.07)
    plaf = filtro_fft(ruido(n), SR, 80, 700) * np.exp(-t / 0.05)
    centro = 900 + 1800 * np.exp(-t / 0.08)
    salpicon = svf(ruido(n), centro, 0.9) * (1 - np.exp(-t / 0.003)) * np.exp(-t / 0.11)
    b += 1.0 * golpe + 0.5 * norm(plaf) + 0.45 * norm(salpicon)
    for _ in range(7):
        f = R.uniform(300, 900)
        mezclar(b, burbuja(f, f * R.uniform(1.6, 2.3), 0.04, R.uniform(0.015, 0.035)), R.uniform(0.04, 0.3), R.uniform(0.08, 0.2))
    return b


def flujo(n, f_alto, f_bajo, giro_ini, giro_fin, sr=SR):
    # Agua que se va en remolino: ruido en banda que baja y gira cada vez más rápido.
    t = np.arange(n) / sr
    giro = np.linspace(giro_ini, giro_fin, n)
    fase = TAU * np.cumsum(giro) / sr
    centro = (f_bajo + (f_alto - f_bajo) * np.exp(-t / (t[-1] * 0.45 + 1e-6))) * (1 + 0.22 * np.sin(fase))
    agua = svf(ruido(n), centro, 1.4, sr) * (1 + 0.35 * np.sin(fase + 1.0))
    siseo = filtro_fft(ruido(n), sr, 2500, 6000) * (0.6 + 0.4 * np.sin(fase * 2))
    return norm(agua) + 0.12 * norm(siseo)


def fx_descarga():
    n = muestras(1.3)
    t = np.arange(n) / SR
    b = np.zeros(n)
    # palanca: clic de plástico y golpe del mecanismo
    tic = clic(0.02, 1500, 7000, 0.002) + 0.6 * seno_f(np.full(muestras(0.02), 2300)) * np.exp(-tiempo(0.02) / 0.004)
    mezclar(b, norm(tic), 0, 0.8)
    clonc = seno_f(np.full(muestras(0.05), 320)) * np.exp(-tiempo(0.05) / 0.012) + 0.4 * clic(0.05, 200, 2000, 0.006)
    mezclar(b, norm(clonc), 0.055, 0.6)
    # remolino
    nf = muestras(1.17)
    env = np.clip(np.arange(nf) / SR / 0.1, 0, 1) ** 1.5 * np.where(np.arange(nf) / SR > 0.8, np.exp(-(np.arange(nf) / SR - 0.8) / 0.15), 1)
    mezclar(b, flujo(nf, 2000, 380, 4, 11) * env, 0.09, 0.55)
    for _ in range(45):
        t0 = R.uniform(0.15, 1.0)
        f = R.uniform(250, 1300)
        mezclar(b, burbuja(f, f * R.uniform(1.5, 2.2), 0.03, R.uniform(0.01, 0.03)), t0, R.uniform(0.04, 0.14))
    # gorgoteo final
    for t0, f, g in [(0.92, 210, 0.5), (1.0, 160, 0.6), (1.07, 240, 0.4), (1.13, 130, 0.55), (1.2, 180, 0.3)]:
        mezclar(b, burbuja(f, f * 2.3, 0.05, 0.035), t0, g)
        mezclar(b, burbuja(f / 2, f * 1.1, 0.05, 0.03), t0, g * 0.5)
    return b


def pedo(dur, tc, fc, sr=SR, chisporroteo=0.25):
    # Pedo cómico: pulso de ancho cambiante, tono con jitter y formantes de 'trompeta'.
    n = muestras(dur, sr)
    t = np.arange(n) / sr
    f = np.interp(t, tc, fc)
    f0 = f * (1 + 0.05 * suave(n, 45, sr) + 0.025 * np.sin(TAU * 7 * t))
    ancho = np.clip(0.2 + 0.08 * suave(n, 30, sr), 0.06, 0.45)
    picos = [(330, 170, 1.0), (820, 280, 0.6), (1600, 450, 0.22)]
    y = pulso(f0, ancho, picos, sr, 45)
    # aleteo irregular de amplitud
    y *= 1 + 0.25 * suave(n, 35, sr)
    y = np.tanh(2.2 * norm(y))
    aire = filtro_fft(ruido(n), sr, 150, 1000)
    y = y + 0.12 * norm(aire)
    # cierre: chisporrotea y se apaga
    ini = dur * (1 - chisporroteo)
    corte = np.where(t > ini, (0.55 + 0.45 * np.sin(TAU * 21 * t)) * np.exp(-(t - ini) / (dur * chisporroteo * 0.5)), 1)
    return y * adsr(n, 0.006, 0.1, 0.85, 0.03, sr) * corte


def fx_pujo():
    return pedo(0.35, [0, 0.04, 0.2, 0.35], [150, 178, 160, 118])


def fx_pujo_largo():
    return pedo(0.9, [0, 0.06, 0.35, 0.55, 0.9], [128, 150, 205, 168, 100], chisporroteo=0.2)


def fx_destapador():
    n = muestras(0.25)
    t = np.arange(n) / SR
    b = np.zeros(n)
    ns = muestras(0.16)
    ts = t[:ns]
    f0 = 75 + 110 * (ts / ts[-1]) ** 1.3
    ancho = np.clip(0.15 + 0.06 * suave(ns, 40), 0.05, 0.4)
    centro = 300 + 700 * ts / ts[-1]
    chupa = aditivo(f0, lambda k, fk: np.sin(np.pi * k * ancho) / k * (0.1 + np.exp(-0.5 * ((fk - centro) / 220) ** 2)), SR, 40)
    humedo = svf(ruido(ns), 600 + 900 * ts / ts[-1], 2.5)
    succion = (0.8 * norm(chupa) + 0.35 * norm(humedo)) * (0.55 + 0.45 * ts / ts[-1]) * adsr(ns, 0.004, 1, 1, 0.012)
    mezclar(b, succion, 0, 0.8)
    tp = tiempo(0.09)
    pop = seno_f(320 + 850 * np.exp(-tp / 0.012)) * np.exp(-tp / 0.018)
    mezclar(b, pop, 0.155, 1.0)
    mezclar(b, clic(0.01, 1500, 8000, 0.0015), 0.155, 0.5)
    return b


def fx_glug():
    b = np.zeros(muestras(0.6))
    for t0, f, g in [(0, 175, 1.0), (0.11, 225, 0.8), (0.2, 150, 0.9), (0.33, 205, 0.75), (0.45, 135, 0.7)]:
        x = burbuja(f, f * 2.2, 0.06, 0.05, 0.14)
        x = x + 0.35 * np.sign(x) * x ** 2  # algo de 2º armónico: más espeso
        mezclar(b, x, t0, g)
        mezclar(b, burbuja(f * 0.5, f * 0.9, 0.05, 0.04, 0.12), t0, g * 0.4)
    return svf(b, 1400, 0.6, modo='lp')


def fx_burbuja():
    b = np.zeros(muestras(0.12))
    mezclar(b, clic(0.006, 3000, 10000, 0.0008), 0, 0.6)
    mezclar(b, burbuja(2100, 3900, 0.03, 0.02), 0, 1.0)
    mezclar(b, burbuja(1800, 2700, 0.02, 0.012), 0.05, 0.3)
    return b


def marimba(f, dur, sr=SRM, dureza=0.5):
    # Marimba: modos de barra (1, 3.93, 9.2) con FM corta en el golpe.
    t = tiempo(dur, sr)
    esc = (440 / f) ** 0.35
    y = np.sin(TAU * f * t + 1.4 * dureza * np.exp(-t / 0.015) * np.sin(TAU * f * t)) * np.exp(-t / (0.5 * esc))
    for m, a, tau in [(3.93, 0.5 * dureza, 0.09), (9.2, 0.18 * dureza, 0.025)]:
        if f * m < sr * 0.45:
            y += a * np.sin(TAU * f * m * t) * np.exp(-t / (tau * esc))
    y += 0.25 * dureza * norm(filtro_fft(ruido(len(t)), sr, 1500, 6000)) * np.exp(-t / 0.002)
    return y * (1 - np.exp(-t / 0.0006))


def campana(f, dur, sr=SRM, brillo=1.0):
    # Glockenspiel: parciales 1, 2.76, 5.4, 8.9 y un poco de FM.
    t = tiempo(dur, sr)
    y = np.sin(TAU * f * t + 0.8 * brillo * np.exp(-t / 0.02) * np.sin(TAU * f * 3.5 * t)) * np.exp(-t / 0.45)
    for m, a, tau in [(2.76, 0.4, 0.2), (5.4, 0.25 * brillo, 0.08), (8.9, 0.12 * brillo, 0.04)]:
        if f * m < sr * 0.45:
            y += a * np.sin(TAU * f * m * t) * np.exp(-t / tau)
    return y * (1 - np.exp(-t / 0.0005))


def nota(nombre):
    # 'C#5' -> frecuencia en Hz
    return 440 * 2 ** ((midi(nombre) - 69) / 12)


CLASE = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}


def midi(nombre):
    p = CLASE[nombre[0]]
    i = 1
    while i < len(nombre) and nombre[i] in '#b':
        p += 1 if nombre[i] == '#' else -1
        i += 1
    return p + 12 * (int(nombre[i:]) + 1)


def hz(m):
    return 440 * 2 ** ((m - 69) / 12)


def fx_rollo():
    b = np.zeros(muestras(0.25))
    mezclar(b, marimba(nota('C6'), 0.25, SR, 0.8), 0, 0.8)
    mezclar(b, marimba(nota('G6'), 0.18, SR, 0.9), 0.07, 1.0)
    return b


def chispas(n, cantidad, f_min, f_max, sr=SR, t_max=None):
    # Destellos agudos aleatorios para el 'brillo'.
    b = np.zeros(n)
    t_max = t_max or n / sr
    for _ in range(cantidad):
        f = R.uniform(f_min, f_max)
        d = 0.06
        tt = tiempo(d, sr)
        mezclar(b, np.sin(TAU * f * tt) * np.exp(-tt / 0.012) * (1 - np.exp(-tt / 0.001)), R.uniform(0, t_max), R.uniform(0.3, 1.0), sr)
    return b


def fx_dorado():
    n = muestras(0.5)
    b = np.zeros(n)
    for i, nm in enumerate(['C6', 'E6', 'G6', 'C7']):
        mezclar(b, campana(nota(nm), 0.5 - i * 0.06, SR, 1.0), i * 0.06, 0.7 + 0.1 * i)
    b += 0.18 * chispas(n, 14, 5000, 9000, t_max=0.38)
    t = np.arange(n) / SR
    b += 0.05 * filtro_fft(ruido(n), SR, 6000, None) * np.exp(-t / 0.15)
    return b


def silbato(n, f_ini, f_fin, sr=SR):
    # Silbato de émbolo: seno con vibrato que sube, con algo de soplo.
    t = np.arange(n) / sr
    f = f_ini * (f_fin / f_ini) ** (t / t[-1]) * (1 + 0.012 * np.sin(TAU * 7 * t))
    tono = seno_f(f, sr) + 0.08 * seno_f(2 * f, sr)
    soplo = svf(ruido(n), f, 6, sr)
    return (tono + 0.25 * norm(soplo)) * adsr(n, 0.03, 1, 1, 0.07, sr)


def fx_combo():
    b = np.zeros(muestras(0.5))
    for i, nm in enumerate(['G5', 'B5', 'D6', 'G6']):
        mezclar(b, marimba(nota(nm), 0.2, SR, 0.8), i * 0.04, 0.6)
    mezclar(b, silbato(muestras(0.36), 700, 2100), 0.12, 0.55)
    return b


def fx_fusion(k):
    # k = 0..3: cada uno más agudo y brillante.
    s = [1.0, 1.3, 1.7, 2.25][k]
    n = muestras(0.3)
    b = np.zeros(n)
    nq = muestras(0.13)
    tq = np.arange(nq) / SR
    f0 = (85 + 50 * tq / tq[-1]) * s
    centro = (380 + 1100 * (tq / tq[-1]) ** 0.7) * s ** 0.6
    ancho = np.clip(0.18 + 0.07 * suave(nq, 40), 0.05, 0.4)
    blando = aditivo(f0, lambda kk, fk: np.sin(np.pi * kk * ancho) / kk * (0.1 + np.exp(-0.5 * ((fk - centro) / (200 * s ** 0.5)) ** 2)), SR, 40)
    humedo = svf(ruido(nq), centro * 1.3, 3.0)
    squelch = (norm(blando) + 0.3 * norm(humedo)) * adsr(nq, 0.004, 0.05, 0.6, 0.02)
    mezclar(b, squelch, 0, 0.75)
    mezclar(b, burbuja(300 * s, 820 * s, 0.05, 0.045), 0.1, 1.0)
    mezclar(b, burbuja(450 * s, 1250 * s, 0.035, 0.025), 0.17, 0.45)
    if k == 0:
        tt = tiempo(0.15)
        mezclar(b, seno_f(55 + 40 * np.exp(-tt / 0.04)) * np.exp(-tt / 0.05), 0.08, 0.6)
    if k >= 2:
        mezclar(b, campana(nota('E7') if k == 3 else nota('B6'), 0.18, SR, 0.6), 0.12, 0.25 if k == 2 else 0.4)
    if k == 3:
        b += 0.18 * chispas(n, 8, 6000, 9500, t_max=0.2)
    corte = 1400 * s ** 1.4
    return svf(b, corte, 0.7, modo='lp')


def fx_cucaracha():
    n = muestras(0.3)
    b = np.zeros(n)
    t0 = 0.0
    i = 0
    while t0 < 0.17:
        g = [1.0, 0.6, 0.8, 0.5, 0.9, 0.55][i % 6] * R.uniform(0.7, 1.0)
        mezclar(b, clic(0.004, 2500, 7500, 0.0007), t0, 0.5 * g)
        t0 += R.uniform(0.011, 0.019)
        i += 1
    # crujido: muchos chasquidos encimados + un golpecito
    for _ in range(45):
        mezclar(b, clic(0.005, 900, 6000, R.uniform(0.0005, 0.0015)), 0.18 + R.exponential(0.018), R.uniform(0.3, 1.0))
    tt = tiempo(0.08)
    mezclar(b, seno_f(110 + 120 * np.exp(-tt / 0.01)) * np.exp(-tt / 0.02), 0.18, 0.7)
    mezclar(b, filtro_fft(ruido(len(tt)), SR, 400, 3000) * np.exp(-tt / 0.03), 0.18, 0.25)
    return b


def plaf(dur, sr=SR):
    # Golpe húmedo: ruido grave con chasquido mojado.
    n = muestras(dur, sr)
    t = np.arange(n) / sr
    cuerpo = filtro_fft(ruido(n), sr, 120, 1800) * np.exp(-t / 0.045)
    moja = svf(ruido(n), 700 + 1500 * np.exp(-t / 0.02), 2.0, sr) * np.exp(-t / 0.03)
    return norm(cuerpo) + 0.5 * norm(moja)


def fx_fallo():
    n = muestras(0.35)
    t = np.arange(n) / SR
    b = 0.8 * plaf(0.35)
    golpe = seno_f(48 + 60 * np.exp(-t / 0.03)) * np.exp(-t / 0.09)
    b += 1.0 * golpe
    return svf(b, 2500, 0.7, modo='lp')


def metal(f0, brillo, sr, picos=None, nmax=40):
    # Metal (tuba, trombón, trompeta): armónicos que caen según 'brillo'.
    def peso(k, fk):
        w = k ** 0.4 * np.exp(-(k - 1) / brillo)
        return w * picos(fk) if picos is not None else w
    return aditivo(f0, peso, sr, nmax)


def trombon(f, dur, sr=SR, ultima=False):
    n = muestras(dur, sr)
    t = np.arange(n) / sr
    f0 = f * 2 ** (-0.5 / 12 * np.exp(-t / 0.03))
    if ultima:
        prof = 0.035 * np.clip((t - 0.1) / 0.3, 0, 1)
        f0 = f0 * (1 + prof * np.sin(TAU * 5.5 * t)) * 2 ** (-0.6 / 12 * np.clip((t - dur * 0.6) / (dur * 0.4), 0, 1))
    # sordina: la boca del 'wah' se abre y se cierra
    abre = np.sin(np.pi * np.clip(t / (dur * 0.85), 0, 1)) ** 0.7
    centro = 380 + 900 * abre
    y = metal(f0, 3 + 4 * abre, sr, lambda fk: 0.15 + np.exp(-0.5 * ((fk - centro) / 300) ** 2), 40)
    return y * adsr(n, 0.02, 0.2, 0.9, 0.05 if not ultima else 0.2, sr)


def fx_perdiste():
    b = np.zeros(muestras(1.6))
    mezclar(b, 0.7 * plaf(0.2) * np.exp(-tiempo(0.2) / 0.06), 0, 1.0)
    notas = [('Bb3', 0.2, 0.26), ('A3', 0.48, 0.26), ('Ab3', 0.76, 0.26), ('G3', 1.04, 0.56)]
    for i, (nm, t0, d) in enumerate(notas):
        x = trombon(nota(nm), d, SR, ultima=(i == 3))
        mezclar(b, 0.9 * norm(x), t0, 0.75)
    return b


def trompeta(f, dur, sr=SR, det=0.0):
    n = muestras(dur, sr)
    t = np.arange(n) / sr
    f0 = f * 2 ** (det / 1200) * 2 ** (-0.35 / 12 * np.exp(-t / 0.015)) * (1 + 0.004 * np.sin(TAU * 5.8 * t) * np.clip((t - 0.15) / 0.2, 0, 1))
    brillo = 6 * (1 - 0.55 * np.exp(-t / 0.025))
    y = metal(f0, brillo, sr, lambda fk: 0.4 + formante(fk, [(1300, 500, 1.0), (2700, 700, 0.4)]), 30)
    return y * adsr(n, 0.012, 0.1, 0.8, min(0.06, dur * 0.3), sr)


def fx_gana():
    n = muestras(1.6)
    b = np.zeros(n)
    frases = [(0.0, 0.09, ['C4', 'E4', 'G4']), (0.1, 0.09, ['E4', 'G4', 'C5']), (0.2, 0.09, ['G4', 'C5', 'E5']),
              (0.3, 0.25, ['C5', 'E5', 'G5']), (0.58, 0.08, ['G4', 'C5', 'E5']), (0.68, 0.55, ['C4', 'G4', 'C5', 'E5', 'G5'])]
    for t0, d, notas in frases:
        for nm in notas:
            for det in (-6, 6):
                mezclar(b, trompeta(nota(nm), d, SR, det), t0, 0.3)
    tt = tiempo(0.5)
    timbal = seno_f(np.full(len(tt), 98) * (1 + 0.2 * np.exp(-tt / 0.02))) * np.exp(-tt / 0.18)
    mezclar(b, timbal, 0.68, 1.2)
    mezclar(b, filtro_fft(ruido(len(tt)), SR, 4000, None) * np.exp(-tt / 0.2), 0.68, 0.25)
    nw = muestras(0.55)
    tw = np.arange(nw) / SR
    env = np.sin(np.pi * np.clip(tw / 0.55, 0, 1)) ** 1.2
    mezclar(b, flujo(nw, 2200, 300, 6, 13) * env, 1.05, 0.7)
    return b


def fx_boton():
    t = tiempo(0.05)
    tono = seno_f(700 + 300 * np.exp(-t / 0.006)) * np.exp(-t / 0.009)
    return tono + 0.15 * clic(0.05, 1000, 5000, 0.0008)


def fx_alerta():
    b = np.zeros(muestras(0.3))
    for t0 in (0.0, 0.16):
        n = muestras(0.1)
        f = np.full(n, 740.0)
        x = seno_f(f) + 0.12 * seno_f(3 * f) + 0.04 * seno_f(5 * f)
        mezclar(b, x * adsr(n, 0.003, 0.08, 0.6, 0.025), t0)
    return b


def fx_viento():
    n = muestras(0.6)
    t = np.arange(n) / SR
    centro = np.interp(t, [0, 0.3, 0.6], [350, 1900, 450])
    x = svf(ruido(n), centro, 1.6) + 0.3 * svf(ruido(n), centro * 0.5, 0.8, modo='lp')
    env = 0.3 + 0.7 * np.sin(np.pi * np.clip(t / 0.6, 0, 1)) ** 1.5
    env *= np.clip((0.6 - t) / 0.2, 0, 1)
    return x * env


EFECTOS = {
    'plop': fx_plop, 'chapuzon': fx_chapuzon, 'descarga': fx_descarga, 'pujo': fx_pujo,
    'pujo_largo': fx_pujo_largo, 'destapador': fx_destapador, 'glug': fx_glug, 'burbuja': fx_burbuja,
    'rollo': fx_rollo, 'dorado': fx_dorado, 'combo': fx_combo,
    'fusion1': lambda: fx_fusion(0), 'fusion2': lambda: fx_fusion(1),
    'fusion3': lambda: fx_fusion(2), 'fusion4': lambda: fx_fusion(3),
    'cucaracha': fx_cucaracha, 'fallo': fx_fallo, 'perdiste': fx_perdiste, 'gana': fx_gana,
    'boton': fx_boton, 'alerta': fx_alerta, 'viento': fx_viento,
}


# ------------------------------------------------------- instrumentos música

def kick(sr=SRM, suave_=False):
    t = tiempo(0.35, sr)
    y = seno_f(48 + 120 * np.exp(-t / 0.03), sr) * np.exp(-t / (0.16 if suave_ else 0.22))
    y = np.tanh(1.6 * y)
    y += (0.1 if suave_ else 0.25) * norm(filtro_fft(ruido(len(t)), sr, 1500, 6000)) * np.exp(-t / 0.003)
    return y * (1 - np.exp(-t / 0.0005))


def snare(sr=SRM, seco=True, oscuro=False):
    t = tiempo(0.25, sr)
    cuerpo = (np.sin(TAU * 190 * t) + 0.5 * np.sin(TAU * 330 * t)) * np.exp(-t / 0.04)
    rr = filtro_fft(ruido(len(t)), sr, 1200, 4500 if oscuro else 9000)
    rr = norm(rr) * np.exp(-t / (0.06 if seco else 0.12))
    return (0.6 * cuerpo + rr) * (1 - np.exp(-t / 0.0005))


def hat(sr=SRM, abierto=False):
    t = tiempo(0.25 if abierto else 0.06, sr)
    # metálico: cuadradas inarmónicas más ruido, solo agudos
    m = sum(np.sign(np.sin(TAU * f * t)) for f in (317, 432, 562, 731, 872, 1089))
    x = filtro_fft(0.5 * m + ruido(len(t)), sr, 7000, None, 3)
    return norm(x) * np.exp(-t / (0.09 if abierto else 0.018)) * (1 - np.exp(-t / 0.0004))


def platillo(sr=SRM):
    t = tiempo(1.2, sr)
    return norm(filtro_fft(ruido(len(t)), sr, 4500, None)) * np.exp(-t / 0.35) * (1 - np.exp(-t / 0.001))


def madera(f, sr=SRM):
    t = tiempo(0.06, sr)
    y = np.sin(TAU * f * t) * np.exp(-t / 0.018) + 0.4 * np.sin(TAU * f * 2.71 * t) * np.exp(-t / 0.008)
    return y * (1 - np.exp(-t / 0.0004))


def shaker(sr=SRM):
    t = tiempo(0.07, sr)
    return norm(filtro_fft(ruido(len(t)), sr, 4000, 11000)) * (1 - np.exp(-t / 0.006)) * np.exp(-t / 0.02)


def tuba(f, dur, sr=SRM):
    n = muestras(dur, sr)
    t = np.arange(n) / sr
    f0 = f * 2 ** (-0.6 / 12 * np.exp(-t / 0.02))
    brillo = 2.6 + 2.5 * np.exp(-t / 0.05)
    y = metal(f0, brillo, sr, lambda fk: 0.5 + formante(fk, [(450, 250, 0.8)]), 30)
    return y * adsr(n, 0.012, 0.09, 0.65, 0.05, sr)


def kazoo(f, dur, sr=SRM):
    n = muestras(dur, sr)
    t = np.arange(n) / sr
    vib = 1 + 0.008 * np.sin(TAU * 5.6 * t) * np.clip((t - 0.07) / 0.1, 0, 1)
    f0 = f * vib * 2 ** (-0.45 / 12 * np.exp(-t / 0.018)) * (1 + 0.003 * suave(n, 8, sr))
    picos = [(1050, 380, 1.0), (2500, 600, 0.55), (3600, 500, 0.2)]
    y = pulso(f0, 0.3, picos, sr, 50, piso=0.2)
    y = np.tanh(2.0 * norm(y))
    return y * adsr(n, 0.01, 0.12, 0.8, 0.035, sr)


def acorde_metal(m, dur, sr=SRM):
    # 'Pah' del oom-pah: metal corto y oscuro, con dos voces desafinadas.
    n = muestras(dur, sr)
    t = np.arange(n) / sr
    y = sum(metal(np.full(n, hz(m) * 2 ** (d / 1200)), np.full(n, 3.5), sr, None, 14) for d in (-7, 7))
    return y * adsr(n, 0.008, 0.06, 0.4, 0.04, sr)


def karplus(f, dur, sr=SRM, brillo=0.5, t60=0.8):
    # Cuerda pulsada (Karplus-Strong) con afinación exacta por remuestreo.
    N = max(2, int(np.ceil(sr / f - 0.5)))
    f_real = sr / (N + 0.5)
    r = f / f_real
    perdida = 10 ** (-3 / (f_real * t60))
    total = int(dur * sr * r) + N + 4
    exc = R.uniform(-1, 1, N)
    k = max(1, int((1 - brillo) * N * 0.4))
    exc = np.convolve(exc, np.ones(k) / k, mode='same')
    exc -= exc.mean()
    y = np.zeros(total + 1)
    y[1:N + 1] = exc
    i = N + 1
    while i < len(y):
        j = min(i + N, len(y))
        y[i:j] = perdida * 0.5 * (y[i - N:j - N] + y[i - N - 1:j - N - 1])
        i = j
    y = y[1:]
    pos = np.arange(muestras(dur, sr)) * r
    out = np.interp(pos, np.arange(len(y)), y)
    t = np.arange(len(out)) / sr
    return norm(out) * (1 - np.exp(-t / 0.0006))


def pizz(f, dur, sr=SRM):
    n = muestras(dur, sr)
    x = karplus(f, dur, sr, 0.45, 0.45)
    t = np.arange(n) / sr
    cuerpo = filtro_fft(x, sr, 180, 4500)
    return norm(cuerpo) * np.exp(-t / 0.18)


def bajo_pluck(f, dur, sr=SRM):
    n = muestras(dur, sr)
    x = karplus(f, dur + 0.05, sr, 0.25, 1.5)[:n]
    t = np.arange(n) / sr
    sub = np.sin(TAU * f * t) * np.exp(-t / 0.4)
    y = norm(x) + 0.35 * sub
    return y * adsr(n, 0.002, 0.3, 0.6, 0.04, sr)


def bajo_bambolea(f, dur, sr=SRM):
    # Bajo que se bambolea: entra desde abajo con portamento y vibrato lento.
    n = muestras(dur, sr)
    t = np.arange(n) / sr
    f0 = f * 2 ** (-1.2 / 12 * np.exp(-t / 0.035)) * (1 + 0.01 * np.sin(TAU * 4.5 * t))
    y = aditivo(f0, lambda k, fk: (1 / k ** 1.3) * np.exp(-fk / 900), sr, 20)
    return y * adsr(n, 0.01, 0.15, 0.6, 0.05, sr)


def kalimba(f, dur, sr=SRM):
    t = tiempo(dur, sr)
    y = np.sin(TAU * f * t + 0.9 * np.exp(-t / 0.01) * np.sin(TAU * f * 2 * t)) * np.exp(-t / 0.5)
    y += 0.25 * np.sin(TAU * f * 5.4 * t) * np.exp(-t / 0.03)
    return y * (1 - np.exp(-t / 0.0008))


def pad(ms, dur, sr=SRM):
    # Colchón suave: sierras desafinadas, oscuras, entrada lenta.
    n = muestras(dur, sr)
    y = np.zeros(n)
    for m in ms:
        for d in (-9, 0, 9):
            f0 = np.full(n, hz(m) * 2 ** (d / 1200))
            y += aditivo(f0, lambda k, fk: (1 / k) * np.exp(-fk / 1100), sr, 24)
    return y * adsr(n, 0.35, 1.0, 1.0, 0.35, sr)


def burbuja_nota(f, sr=SRM):
    # Burbuja afinada: sube rápido hasta la nota.
    t = tiempo(0.25, sr)
    fr = f * (0.55 + 0.45 * (1 - np.exp(-t / 0.025)))
    return (seno_f(fr, sr) + 0.15 * seno_f(2 * fr, sr)) * np.exp(-t / 0.09) * (1 - np.exp(-t / 0.002))


# ------------------------------------------------------------- composición

CALIDADES = {'': [0, 4, 7], 'm': [0, 3, 7], '7': [0, 4, 7, 10], 'm7': [0, 3, 7, 10],
             'maj7': [0, 4, 7, 11], 'sus': [0, 5, 7]}


def acorde(nombre):
    # 'Bbmaj7' -> (clase de la raíz, intervalos)
    p = CLASE[nombre[0]]
    i = 1
    if i < len(nombre) and nombre[i] in '#b':
        p += 1 if nombre[i] == '#' else -1
        i += 1
    return p % 12, CALIDADES[nombre[i:]]


def raiz_bajo(nombre, lo=40):
    p, _ = acorde(nombre)
    m = lo + ((p - lo) % 12)
    return m


def voces(nombre, lo=55):
    p, iv = acorde(nombre)
    return sorted(lo + ((p + x - lo) % 12) for x in iv)


def melodia(texto, transporte=0):
    # 'C5/1 r/1 E5/2 | ...' en corcheas -> lista de (beat, duración_beats, midi)
    out, pos = [], 0.0
    for tok in texto.split():
        if tok == '|':
            continue
        nm, d = tok.split('/')
        d = int(d) * 0.5
        if nm != 'r':
            out.append((pos, d, midi(nm) + transporte))
        pos += d
    return out, pos


class Pista:
    # Buffer circular: lo que se pasa del final entra por el principio (loop sin corte).
    def __init__(self, bpm, compases, sr=SRM, swing=0.5):
        self.sr, self.bpm, self.swing = sr, bpm, swing
        self.spb = 60 / bpm
        self.beats = compases * 4
        self.n = int(round(self.beats * self.spb * sr))
        self.buses = {}

    def beat_a_muestra(self, beat):
        b0 = np.floor(beat)
        fr = beat - b0
        if abs(fr - 0.5) < 1e-6:
            fr = self.swing
        return int(round((b0 + fr) * self.spb * self.sr))

    def poner(self, bus, beat, sig, g=1.0, humano=0.0):
        b = self.buses.setdefault(bus, np.zeros(self.n))
        i = (self.beat_a_muestra(beat) + (int(R.normal(0, humano) * self.sr) if humano else 0)) % self.n
        sig = sig * g
        while len(sig):
            j = min(self.n, i + len(sig))
            b[i:j] += sig[:j - i]
            sig = sig[j - i:]
            i = 0

    def mezcla(self, ajustes, reverb_tau=0.25, eco_beats=0.75, eco_fb=0.3):
        # ajustes: bus -> (nivel RMS en dB, envío a reverb, envío a eco)
        seco = np.zeros(self.n)
        env_rev = np.zeros(self.n)
        env_eco = np.zeros(self.n)
        for nombre, (nivel, rv, ec) in ajustes.items():
            x = self.buses.get(nombre)
            if x is None:
                continue
            g = 10 ** (nivel / 20) / (np.sqrt(np.mean(x ** 2)) + 1e-12)
            seco += g * x
            env_rev += g * rv * x
            env_eco += g * ec * x
        # eco circular con repeticiones cada vez más oscuras
        eco = np.zeros(self.n)
        d = int(round(eco_beats * self.spb * self.sr))
        x = env_eco
        for k in range(1, 5):
            x = filtro_fft(np.roll(x, d), self.sr, 200, 3500, 1, circular=True)
            eco += eco_fb ** (k - 1) * x
        # reverb por convolución circular con respuesta sintética (graves duran más)
        nir = muestras(reverb_tau * 7, self.sr)
        t = np.arange(nir) / self.sr
        ir = np.zeros(nir)
        for lo, hi, tau in [(None, 900, reverb_tau * 1.3), (900, 4000, reverb_tau), (4000, None, reverb_tau * 0.45)]:
            ir += filtro_fft(ruido(nir), self.sr, lo, hi) * np.exp(-t / tau)
        ir[:muestras(0.012, self.sr)] = 0
        ir /= np.sqrt(np.sum(ir ** 2))
        IR = np.fft.rfft(ir, self.n)
        rev = np.fft.irfft(np.fft.rfft(env_rev + 0.5 * eco) * IR, self.n)
        rev = filtro_fft(rev, self.sr, 250, None, 1, circular=True)
        total = seco + 0.45 * eco + 0.5 * rev
        total = filtro_fft(total, self.sr, 35, None, 2, circular=True)
        total = total - total.mean()
        total = np.tanh(1.4 * norm(total)) / np.tanh(1.4)
        return total * 10 ** (-3 / 20) / np.max(np.abs(total))  # margen: el AAC sobrepasa el pico


def tocar_melodia(p, bus, texto, instrumento, beat0=0, g=1.0, legato=0.92, transporte=0, humano=0.0):
    notas, largo = melodia(texto, transporte)
    for b, d, m in notas:
        p.poner(bus, beat0 + b, instrumento(hz(m), d * p.spb * legato), g, humano)
    return largo


def musica_tuberia():
    semilla('musica_tuberia')
    p = Pista(140, 16)
    acordes = ['C', 'Am', 'F', 'G', 'C', 'Am', 'Dm', 'G', 'F', 'Fm', 'C', 'A7', 'Dm', 'G7', 'C', 'G7']
    m = ("G4/1 C5/1 E5/1 G5/1 E5/1 C5/1 E5/2 | A5/1 G5/1 E5/1 C5/1 A4/2 r/2 | F5/1 E5/1 F5/1 A5/1 C6/2 A5/2 |"
         " G5/1 F#5/1 G5/1 A5/1 B5/2 G5/2 | G4/1 C5/1 E5/1 G5/1 E5/1 C5/1 E5/2 | A5/1 B5/1 C6/1 A5/1 E5/2 C5/2 |"
         " D5/1 F5/1 A5/1 D6/1 C6/1 A5/1 F5/2 | G5/1 F5/1 E5/1 D5/1 B4/2 r/2 | C6/2 A5/1 F5/1 C6/2 A5/2 |"
         " C6/2 Ab5/1 F5/1 C6/1 Db6/1 C6/2 | G5/1 E5/1 C5/1 E5/1 G5/1 C6/1 E6/2 | C#6/1 A5/1 E5/1 G5/1 A5/2 C#6/2 |"
         " D6/2 C6/1 A5/1 F5/2 D5/2 | G5/1 A5/1 B5/1 D6/1 F6/2 D6/2 | E6/1 D6/1 C6/1 G5/1 E5/1 G5/1 C6/2 |"
         " B5/1 A5/1 G5/1 F5/1 D5/1 B4/1 G4/2")
    tocar_melodia(p, 'lead', m, kazoo, transporte=-12, legato=0.85)
    # campanita que dobla la melodía en la segunda mitad
    notas, _ = melodia(m)
    for b, d, mm in notas:
        if b >= 32:
            p.poner('glock', b, campana(hz(mm), 0.6), 1.0)
    for c, nombre in enumerate(acordes):
        b0 = c * 4
        r = raiz_bajo(nombre, 40)
        quinta = r + 7 if r + 7 <= 55 else r - 5
        sig = raiz_bajo(acordes[(c + 1) % 16], 40)
        if c % 4 == 3:
            _, iv = acorde(nombre)
            for i, mm in enumerate([r, r + iv[1], r + 7, sig - 1 if sig > r else sig + 1]):
                p.poner('bajo', b0 + i, tuba(hz(mm), 0.75 * p.spb), 1.0)
        else:
            p.poner('bajo', b0, tuba(hz(r), 0.8 * p.spb), 1.0)
            p.poner('bajo', b0 + 2, tuba(hz(quinta), 0.8 * p.spb), 0.9)
            if c % 4 == 1:
                p.poner('bajo', b0 + 3.5, tuba(hz(r + 12), 0.4 * p.spb), 0.6)
        for bb in (1, 3):
            for mm in voces(nombre, 55):
                p.poner('pah', b0 + bb, acorde_metal(mm, 0.4 * p.spb), 1.0)
        # batería
        p.poner('bombo', b0, kick())
        p.poner('bombo', b0 + 2, kick())
        p.poner('caja', b0 + 1, snare())
        p.poner('caja', b0 + 3, snare(), 1.0)
        if c >= 8:
            for k in range(16):
                p.poner('hat', b0 + k * 0.25, hat(), 0.55 if k % 2 else 0.35)
            if c % 2 == 1:
                p.poner('hat', b0 + 3.5, hat(abierto=True), 0.5)
        else:
            for k in range(8):
                p.poner('hat', b0 + k * 0.5, hat(), 0.7 if k % 2 else 0.4)
        if c in (7, 15):
            for k, g in enumerate([0.4, 0.55, 0.7, 0.9]):
                p.poner('caja', b0 + 3 + k * 0.25, snare(), g)
    p.poner('hat', 0, platillo(), 0.6)
    p.poner('hat', 32, platillo(), 0.6)
    return p.mezcla({
        'lead': (-14, 0.18, 0.25), 'glock': (-27, 0.3, 0.3), 'bajo': (-18, 0.05, 0),
        'pah': (-25, 0.15, 0), 'bombo': (-19, 0.02, 0), 'caja': (-23, 0.12, 0), 'hat': (-31, 0.05, 0),
    }, reverb_tau=0.18, eco_beats=0.75, eco_fb=0.25)


def musica_destapa():
    semilla('musica_destapa')
    p = Pista(124, 16)
    acordes = ['Am', 'F', 'C', 'G', 'Am', 'F', 'Dm', 'E', 'F', 'G', 'Em', 'Am', 'Dm', 'E', 'Am', 'E7']
    m = ("A4/1 r/1 C5/1 E5/1 A5/1 r/1 E5/1 C5/1 | F5/1 r/1 E5/1 F5/1 A5/2 G5/1 F5/1 | E5/1 r/1 G5/1 E5/1 C5/1 r/1 E5/1 G5/1 |"
         " D5/1 B4/1 D5/1 G5/1 B5/2 r/2 | A4/1 r/1 C5/1 E5/1 A5/1 r/1 E5/1 C5/1 | F5/1 A5/1 C6/1 A5/1 F5/1 r/1 E5/1 F5/1 |"
         " D5/1 F5/1 A5/1 D6/1 C6/1 A5/1 F5/1 D5/1 | E5/1 G#5/1 B5/1 E6/1 D6/1 B5/1 G#5/1 E5/1 | C6/2 A5/1 F5/1 C6/1 r/1 A5/2 |"
         " D6/2 B5/1 G5/1 D6/1 r/1 B5/2 | B5/1 A5/1 G5/1 E5/1 G5/1 A5/1 B5/2 | C6/1 B5/1 A5/1 E5/1 A5/2 r/2 |"
         " D5/1 F5/1 A5/1 F5/1 D6/2 C6/1 A5/1 | G#5/1 B5/1 E6/1 B5/1 G#5/2 E5/2 | A5/1 E5/1 C5/1 E5/1 A5/1 C6/1 E6/2 |"
         " D6/1 B5/1 G#5/1 E5/1 D5/1 B4/1 G#4/2")
    notas, _ = melodia(m)
    for b, d, mm in notas:
        p.poner('lead', b, pizz(hz(mm), min(d, 1.0) * p.spb), 1.0)
        p.poner('lead2', b, pizz(hz(mm - 12), min(d, 1.0) * p.spb), 1.0)
    for c, nombre in enumerate(acordes):
        b0 = c * 4
        r = raiz_bajo(nombre, 40)
        sig = raiz_bajo(acordes[(c + 1) % 16], 40)
        if c % 8 == 7:
            for i, mm in enumerate([r, r + 7, r + 12, sig + 1 if sig < r else sig - 1]):
                p.poner('bajo', b0 + i, bajo_bambolea(hz(mm), 0.9 * p.spb))
        else:
            for i, mm in enumerate([r, r + 7, r, r + 12]):
                p.poner('bajo', b0 + i, bajo_bambolea(hz(mm), 0.9 * p.spb), 1.0 if i % 2 == 0 else 0.8)
        # tic-tac del reloj
        for k in range(8):
            p.poner('tic', b0 + k * 0.5, madera(1900 if k % 2 == 0 else 1350), 0.8 if k % 2 == 0 else 0.6)
        p.poner('bombo', b0, kick(suave_=True))
        p.poner('bombo', b0 + 2, kick(suave_=True))
        if c % 2 == 1:
            p.poner('bombo', b0 + 2.5, kick(suave_=True), 0.6)
        p.poner('caja', b0 + 1, snare(), 0.6)
        p.poner('caja', b0 + 3, snare(), 0.7)
        if c >= 8:
            for k in range(16):
                p.poner('shaker', b0 + k * 0.25, shaker(), 0.9 if k % 4 == 2 else 0.5)
            # acordes en pizzicato a contratiempo
            for k in (0.5, 1.5, 2.5, 3.5):
                for mm in voces(nombre, 57):
                    p.poner('acordes', b0 + k, pizz(hz(mm), 0.3 * p.spb), 1.0)
        # burbujas melódicas al final de frase
        if c % 4 == 3 or c in (9, 13):
            ch = voces(nombre, 69)
            p.poner('burbujas', b0 + 3, burbuja_nota(hz(ch[0] + 12)), 1.0)
            p.poner('burbujas', b0 + 3.5, burbuja_nota(hz(ch[-1] + 12)), 0.9)
        if c in (7, 15):
            for k, g in enumerate([0.35, 0.5, 0.65, 0.8]):
                p.poner('caja', b0 + 3 + k * 0.25, snare(), g)
    return p.mezcla({
        'lead': (-15, 0.18, 0.2), 'lead2': (-23, 0.1, 0), 'acordes': (-29, 0.25, 0), 'bajo': (-18, 0.03, 0),
        'tic': (-27, 0.1, 0), 'bombo': (-20, 0.02, 0), 'caja': (-26, 0.15, 0), 'shaker': (-34, 0.05, 0),
        'burbujas': (-26, 0.3, 0.4),
    }, reverb_tau=0.22, eco_beats=0.75, eco_fb=0.3)


def musica_fusion():
    semilla('musica_fusion')
    p = Pista(96, 12, swing=0.58)
    acordes = ['Fmaj7', 'Dm7', 'Bbmaj7', 'C7', 'Fmaj7', 'Dm7', 'Bbmaj7', 'C7', 'Gm7', 'Am7', 'Bbmaj7', 'C7']
    m = ("C6/1 A5/1 F5/1 A5/1 G5/2 F5/2 | A5/1 F5/1 D5/1 F5/1 E5/4 | D5/1 F5/1 Bb5/1 A5/1 G5/2 F5/2 | G5/2 E5/2 C5/2 r/2 |"
         " C6/1 A5/1 F5/1 A5/1 G5/2 F5/2 | A5/1 C6/1 D6/1 C6/1 A5/4 | Bb5/1 A5/1 G5/1 F5/1 D5/2 F5/2 | E5/1 G5/1 C6/1 Bb5/1 A5/2 G5/2 |"
         " F5/2 G5/1 Bb5/1 D6/2 Bb5/2 | C6/2 A5/1 G5/1 E5/2 C5/2 | D5/1 F5/1 A5/1 C6/1 D6/1 C6/1 A5/2 | G5/1 Bb5/1 C6/1 E6/1 D6/1 Bb5/1 G5/1 E5/1")
    notas, _ = melodia(m)
    for b, d, mm in notas:
        p.poner('lead', b, marimba(hz(mm), 1.2, SRM, 0.55), R.uniform(0.85, 1.0), humano=0.004)
        if d >= 2:  # nota larga: redoble suave de marimba
            for k in range(1, int(d * 2)):
                p.poner('lead', b + k * 0.5, marimba(hz(mm), 0.8, SRM, 0.3), 0.35, humano=0.004)
    for c, nombre in enumerate(acordes):
        b0 = c * 4
        r = raiz_bajo(nombre, 41)
        _, iv = acorde(nombre)
        sig = raiz_bajo(acordes[(c + 1) % 12], 41)
        for b, mm, d in [(0, r, 1.3), (1.5, r, 0.45), (2.0, r + 7, 0.9), (3.5, sig - 1 if c % 2 else r + 12, 0.45)]:
            p.poner('bajo', b0 + b, bajo_pluck(hz(mm), d * p.spb), 1.0, humano=0.003)
        p.poner('pad', b0, pad(voces(nombre, 53), 4 * p.spb + 0.3), 1.0)
        if c >= 4:
            ch = voces(nombre, 60)
            arp = ch + [ch[1] + 12, ch[2] + 12, ch[0] + 12, ch[2]]
            for k in range(8):
                p.poner('kalimba', b0 + k * 0.5, kalimba(hz(arp[k % len(arp)]), 0.7), 0.8 if k % 2 == 0 else 0.6, humano=0.004)
        # batería lo-fi
        p.poner('bombo', b0, kick(suave_=True))
        p.poner('bombo', b0 + 2.5, kick(suave_=True), 0.8)
        if c % 2 == 1:
            p.poner('bombo', b0 + 1.75, kick(suave_=True), 0.5)
        p.poner('caja', b0 + 1, snare(seco=False, oscuro=True), 0.8, humano=0.003)
        p.poner('caja', b0 + 3, snare(seco=False, oscuro=True), 0.85, humano=0.003)
        for k in range(8):
            p.poner('hat', b0 + k * 0.5, hat(), 0.7 if k % 2 == 0 else 0.45, humano=0.003)
        if c >= 8:
            for k in (1.75, 3.25, 3.75):
                p.poner('hat', b0 + k, hat(), 0.25)
    return p.mezcla({
        'lead': (-14, 0.25, 0.3), 'kalimba': (-25, 0.3, 0.2), 'bajo': (-19, 0.04, 0), 'pad': (-27, 0.4, 0),
        'bombo': (-21, 0.02, 0), 'caja': (-27, 0.2, 0), 'hat': (-33, 0.05, 0),
    }, reverb_tau=0.3, eco_beats=0.75, eco_fb=0.3)


MUSICAS = {'musica_tuberia': musica_tuberia, 'musica_destapa': musica_destapa, 'musica_fusion': musica_fusion}


def ffmpeg():
    return shutil.which('ffmpeg') or '/opt/homebrew/bin/ffmpeg'


def escribir_m4a(ruta, x, sr):
    with tempfile.TemporaryDirectory() as tmp:
        w = os.path.join(tmp, 'm.wav')
        escribir_wav(w, x, sr)
        subprocess.run([ffmpeg(), '-y', '-loglevel', 'error', '-i', w, '-c:a', 'aac', '-b:a', f'{KBPS_MUSICA}k',
                        '-ar', str(sr), '-ac', '1', '-map_metadata', '-1', '-fflags', '+bitexact',
                        '-flags:a', '+bitexact', '-movflags', '+faststart', ruta], check=True)


def main():
    import sys
    solo = set(sys.argv[1:])
    os.makedirs(SALIDA, exist_ok=True)
    for nombre, f in EFECTOS.items():
        if solo and nombre not in solo:
            continue
        semilla(nombre)
        x = terminar(f())
        escribir_wav(os.path.join(SALIDA, nombre + '.wav'), x, SR)
        print(f'{nombre:12s} {len(x) / SR:5.2f} s')
    for nombre, f in MUSICAS.items():
        if solo and nombre not in solo:
            continue
        x = f()
        escribir_m4a(os.path.join(SALIDA, nombre + '.m4a'), x, SRM)
        print(f'{nombre:12s} {len(x) / SRM:5.2f} s')


if __name__ == '__main__':
    main()
