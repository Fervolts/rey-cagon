#!/usr/bin/env python3
# Músicas de los minijuegos con un motivo común: la palabra CAGAR.
# Cada letra es una nota (C = do, A = la, G = sol, R = re) y suena con el ritmo de su letra en Morse:
# raya = 3 semicorcheas, punto = 1, una de silencio entre elementos y tres entre letras.
# CAGAR ocupa 49 semicorcheas: tres compases y la primera del cuarto. El resto del cuarto compás es la respuesta.
# Usa los instrumentos y la mezcla circular de sonidos.py (loop sin corte por construcción).
# Uso: python3 scripts/musica_cagar.py [carpeta_salida]   (por defecto assets/sonidos)

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np  # noqa: E402
import sonidos as s  # noqa: E402

s.CALIDADES.update({'m9': [0, 3, 7, 10, 14], '9': [0, 4, 7, 10, 14], 'add9': [0, 4, 7, 14]})

MORSE = {'C': '-.-.', 'A': '.-', 'G': '--.', 'R': '.-.'}
PALABRA = 'CAGAR'
# Notas literales de la palabra: do la sol la re.
CAGAR = [s.midi(n) for n in ('C5', 'A4', 'G4', 'A4', 'D5')]


def morse(palabra=PALABRA):
    # -> lista de (inicio, duración, índice de letra, es_raya) en semicorcheas
    out, pos = [], 0
    for i, letra in enumerate(palabra):
        for k, el in enumerate(MORSE[letra]):
            d = 3 if el == '-' else 1
            out.append((pos, d, i, el == '-'))
            pos += d + (1 if k < len(MORSE[letra]) - 1 else 0)
        pos += 3
    return out


def motivo(p, bus, beat0, notas, instrumento, g=1.0, unidad=0.25, humano=0.0, octava=0):
    for ini, d, i, raya in morse():
        dur = d * unidad * p.spb * (0.92 if raya else 0.7)
        p.poner(bus, beat0 + ini * unidad, instrumento(s.hz(notas[i] + 12 * octava), dur), g * (1.0 if raya else 0.82), humano)


def ritmo_morse(p, bus, beat0, golpe, g=1.0, unidad=0.25):
    # La rítmica: CAGAR en Morse sin altura (raya acentuada).
    for ini, d, _, raya in morse():
        p.poner(bus, beat0 + ini * unidad, golpe, g * (1.0 if raya else 0.6))


def respuesta(p, bus, beat0, texto, instrumento, g=1.0, legato=0.85):
    # Respuesta en el cuarto compás de la frase (desde el beat 13).
    return s.tocar_melodia(p, bus, texto, instrumento, beat0 + 13, g, legato)


def musica_tuberia():
    s.semilla('musica_tuberia')
    p = s.Pista(140, 16)
    frases = [
        (['C', 'Am7', 'Dm7', 'G7'], 0, 'B4/1 D5/1 F5/1 E5/1 D5/1 B4/1'),
        (['C', 'Am7', 'Dm7', 'G7'], 0, 'G5/1 F5/1 E5/1 D5/1 E5/1 F5/1'),
        (['F', 'Dm7', 'Gm7', 'C7'], 5, 'E5/1 G5/1 Bb5/1 A5/1 G5/1 E5/1'),
        (['C', 'Am7', 'Dm7', 'G7'], 0, 'B4/1 C5/1 D5/1 F5/1 E5/1 D5/1'),
    ]
    for f, (acordes, tr, resp) in enumerate(frases):
        b0 = f * 16
        notas = [n + tr for n in CAGAR]
        motivo(p, 'lead', b0, notas, s.kazoo)
        respuesta(p, 'lead' if f != 1 else 'glock', b0, resp, s.kazoo if f != 1 else (lambda hz, d: s.campana(hz * 2, 0.6)))
        if f >= 1:
            motivo(p, 'glock', b0, notas, lambda hz, d: s.campana(hz * 2, 0.6), 0.9)
        if f >= 2:
            ritmo_morse(p, 'morse', b0, s.madera(1500), 0.9)
        for c, nombre in enumerate(acordes):
            bc = b0 + c * 4
            r = s.raiz_bajo(nombre, 40)
            quinta = r + 7 if r + 7 <= 55 else r - 5
            sig = s.raiz_bajo(frases[(f + 1) % 4][0][0] if c == 3 else acordes[c + 1], 40)
            if c == 3:
                _, iv = s.acorde(nombre)
                for i, mm in enumerate([r, r + iv[1], r + 7, sig - 1 if sig > r else sig + 1]):
                    p.poner('bajo', bc + i, s.tuba(s.hz(mm), 0.75 * p.spb), 1.0)
            else:
                p.poner('bajo', bc, s.tuba(s.hz(r), 0.8 * p.spb), 1.0)
                p.poner('bajo', bc + 2, s.tuba(s.hz(quinta), 0.8 * p.spb), 0.9)
                if c == 1:
                    p.poner('bajo', bc + 3.5, s.tuba(s.hz(r + 12), 0.4 * p.spb), 0.6)
            for bb in (1, 3):
                for mm in s.voces(nombre, 55):
                    p.poner('pah', bc + bb, s.acorde_metal(mm, 0.4 * p.spb), 1.0)
            p.poner('bombo', bc, s.kick())
            p.poner('bombo', bc + 2, s.kick())
            p.poner('caja', bc + 1, s.snare())
            p.poner('caja', bc + 3, s.snare())
            if f >= 2:
                for k in range(16):
                    p.poner('hat', bc + k * 0.25, s.hat(), 0.55 if k % 2 else 0.35)
                if c % 2 == 1:
                    p.poner('hat', bc + 3.5, s.hat(abierto=True), 0.5)
            else:
                for k in range(8):
                    p.poner('hat', bc + k * 0.5, s.hat(), 0.7 if k % 2 else 0.4)
        for k, g in enumerate([0.4, 0.55, 0.7, 0.9]):
            p.poner('caja', b0 + 15 + k * 0.25, s.snare(), g * (1 if f % 2 else 0.6))
    p.poner('hat', 0, s.platillo(), 0.6)
    p.poner('hat', 32, s.platillo(), 0.6)
    return p.mezcla({
        'lead': (-14, 0.18, 0.25), 'glock': (-26, 0.3, 0.3), 'bajo': (-18, 0.05, 0), 'pah': (-25, 0.15, 0),
        'bombo': (-19, 0.02, 0), 'caja': (-23, 0.12, 0), 'hat': (-31, 0.05, 0), 'morse': (-27, 0.15, 0),
    }, reverb_tau=0.18, eco_beats=0.75, eco_fb=0.25)


def musica_destapa():
    s.semilla('musica_destapa')
    p = s.Pista(124, 16)
    frases = [
        (['Am', 'Fadd9', 'Dm', 'E7'], 0, 'G#4/1 B4/1 D5/1 E5/1 D5/1 B4/1'),
        (['Am', 'Fadd9', 'Dm', 'E7'], 0, 'E5/1 G#5/1 B5/1 D6/1 B5/1 G#5/1'),
        (['Dm', 'Bbadd9', 'Gm', 'A7'], 5, 'C#5/1 E5/1 G5/1 A5/1 G5/1 E5/1'),
        (['Am', 'Fadd9', 'Dm', 'E7'], 0, 'E5/1 D5/1 B4/1 G#4/1 B4/1 D5/1'),
    ]
    for f, (acordes, tr, resp) in enumerate(frases):
        b0 = f * 16
        notas = [n + tr for n in CAGAR]
        pz = lambda hz, d: s.pizz(hz, min(d, 0.5))  # noqa: E731
        motivo(p, 'lead', b0, notas, pz)
        motivo(p, 'lead2', b0, notas, pz, octava=-1)
        respuesta(p, 'lead', b0, resp, pz)
        if f >= 2:
            ritmo_morse(p, 'morse', b0, s.madera(2300), 0.9)
        for c, nombre in enumerate(acordes):
            bc = b0 + c * 4
            r = s.raiz_bajo(nombre, 40)
            sig = s.raiz_bajo(frases[(f + 1) % 4][0][0] if c == 3 else acordes[c + 1], 40)
            if c == 3:
                for i, mm in enumerate([r, r + 7, r + 12, sig + 1 if sig < r else sig - 1]):
                    p.poner('bajo', bc + i, s.bajo_bambolea(s.hz(mm), 0.9 * p.spb))
            else:
                for i, mm in enumerate([r, r + 7, r, r + 12]):
                    p.poner('bajo', bc + i, s.bajo_bambolea(s.hz(mm), 0.9 * p.spb), 1.0 if i % 2 == 0 else 0.8)
            for k in range(8):
                p.poner('tic', bc + k * 0.5, s.madera(1900 if k % 2 == 0 else 1350), 0.8 if k % 2 == 0 else 0.6)
            p.poner('bombo', bc, s.kick(suave_=True))
            p.poner('bombo', bc + 2, s.kick(suave_=True))
            if c % 2 == 1:
                p.poner('bombo', bc + 2.5, s.kick(suave_=True), 0.6)
            p.poner('caja', bc + 1, s.snare(), 0.6)
            p.poner('caja', bc + 3, s.snare(), 0.7)
            if f >= 1:
                for k in range(16):
                    p.poner('shaker', bc + k * 0.25, s.shaker(), 0.9 if k % 4 == 2 else 0.5)
                for k in (0.5, 1.5, 2.5, 3.5):
                    for mm in s.voces(nombre, 57):
                        p.poner('acordes', bc + k, s.pizz(s.hz(mm), 0.3 * p.spb), 1.0)
        ch = s.voces(acordes[3], 69)
        p.poner('burbujas', b0 + 12.5, s.burbuja_nota(s.hz(ch[0] + 12)), 1.0)
        p.poner('burbujas', b0 + 15.5, s.burbuja_nota(s.hz(ch[-1] + 12)), 0.9)
        for k, g in enumerate([0.35, 0.5, 0.65, 0.8]):
            p.poner('caja', b0 + 15 + k * 0.25, s.snare(), g * (1 if f % 2 else 0.6))
    return p.mezcla({
        'lead': (-15, 0.18, 0.2), 'lead2': (-23, 0.1, 0), 'acordes': (-29, 0.25, 0), 'bajo': (-18, 0.03, 0),
        'tic': (-28, 0.1, 0), 'bombo': (-20, 0.02, 0), 'caja': (-26, 0.15, 0), 'shaker': (-34, 0.05, 0),
        'burbujas': (-26, 0.3, 0.4), 'morse': (-27, 0.15, 0),
    }, reverb_tau=0.22, eco_beats=0.75, eco_fb=0.3)


def vibrafono(f, dur, sr=s.SRM):
    # Barras afinadas 1:4:10, motor de trémolo y pedal: suena lo que dura la nota y se apaga.
    n = s.muestras(dur + 0.08, sr)
    t = np.arange(n) / sr
    y = np.sin(s.TAU * f * t) * np.exp(-t / 1.3)
    y += 0.22 * np.sin(s.TAU * f * 4 * t) * np.exp(-t / 0.22)
    y += 0.05 * np.sin(s.TAU * f * 10 * t) * np.exp(-t / 0.05)
    y *= 1 - 0.22 * (1 - np.cos(s.TAU * 5.2 * t)) / 2
    apagar = np.clip((dur + 0.08 - t) / 0.08, 0, 1)
    return y * apagar * (1 - np.exp(-t / 0.0008))


def marimba_afinada(f, dur, sr=s.SRM):
    t = s.tiempo(dur, sr)
    esc = (440 / f) ** 0.35
    y = np.sin(s.TAU * f * t + 0.6 * np.exp(-t / 0.012) * np.sin(s.TAU * f * t)) * np.exp(-t / (0.45 * esc))
    y += 0.3 * np.sin(s.TAU * f * 4 * t) * np.exp(-t / (0.08 * esc))
    y += 0.08 * np.sin(s.TAU * f * 10 * t) * np.exp(-t / (0.02 * esc))
    return y * (1 - np.exp(-t / 0.0006))


def rhodes(f, dur, sr=s.SRM):
    # Piano eléctrico por FM 1:1, dos voces apenas desafinadas.
    n = s.muestras(dur + 0.15, sr)
    t = np.arange(n) / sr
    indice = 1.1 * np.exp(-t / 0.18) + 0.25
    y = sum(np.sin(s.TAU * f * c * t + indice * np.sin(s.TAU * f * c * t)) for c in (2 ** (-3 / 1200), 2 ** (3 / 1200)))
    y *= np.exp(-t / 1.6) * np.clip((dur + 0.15 - t) / 0.15, 0, 1)
    return y * (1 - np.exp(-t / 0.002))


# Voicings abiertos (sin segundas en el grave): la nota del motivo siempre es nota del acorde.
VOICING = {
    'Fmaj7': ['A3', 'C4', 'E4', 'G4'], 'Am7': ['G3', 'C4', 'E4'], 'Dm7': ['F3', 'A3', 'C4', 'E4'],
    'Gm7': ['Bb3', 'D4', 'F4', 'A4'], 'C7': ['Bb3', 'E4', 'G4'], 'Bbmaj7': ['A3', 'D4', 'F4'],
}
RAIZ = {'Fmaj7': 'F2', 'Am7': 'A2', 'Dm7': 'D2', 'Gm7': 'G2', 'C7': 'C2', 'Bbmaj7': 'Bb1'}


def musica_fusion():
    s.semilla('musica_fusion')
    p = s.Pista(108, 16)
    a = ['Fmaj7', 'Am7', 'Dm7', 'Gm7 C7']
    frases = [
        (a, 0, 'A4/1 Bb4/1 C5/1 E5/1 G5/1 E5/1'),
        (a, 0, 'D5/1 E5/1 G5/1 Bb5/1 A5/1 G5/1'),
        (['Bbmaj7', 'Dm7', 'Gm7', 'C7'], 5, 'E5/1 G5/1 Bb5/1 D6/1 C6/1 Bb5/1'),
        (a, 0, 'G5/1 E5/1 D5/1 C5/1 Bb4/1 G4/1'),
    ]
    vib = lambda hz, d: vibrafono(hz, d)  # noqa: E731
    mar = lambda hz, d: marimba_afinada(hz, 0.9)  # noqa: E731
    for f, (acordes, tr, resp) in enumerate(frases):
        b0 = f * 16
        notas = [n + tr for n in CAGAR]
        motivo(p, 'lead', b0, notas, vib, humano=0.003)
        respuesta(p, 'resp', b0, resp, mar, 0.9)
        if f == 3:
            motivo(p, 'doble', b0, notas, lambda hz, d: marimba_afinada(hz, 0.7), octava=1, humano=0.003)
        if f >= 2:
            ritmo_morse(p, 'morse', b0, s.shaker(), 1.0)
        for c, compas in enumerate(acordes):
            bc = b0 + c * 4
            partes = compas.split()
            largo = 4 / len(partes)
            for k, nombre in enumerate(partes):
                bk = bc + k * largo
                vs = [s.midi(x) for x in VOICING[nombre]]
                # Rhodes: golpe en el 1 y empujón en el "y" del 2.
                for b, d, g in ([(0, 1.4, 1.0), (1.5, 2.3, 0.75)] if largo == 4 else [(0, 1.8, 1.0)]):
                    for m in vs:
                        p.poner('rhodes', bk + b, rhodes(s.hz(m), d * p.spb), g, humano=0.004)
                r = s.midi(RAIZ[nombre])
                if largo == 4:
                    sig = s.midi(RAIZ[(acordes[c + 1] if c < 3 else frases[(f + 1) % 4][0][0]).split()[0]])
                    paso = sig + (1 if sig < r else -1) if abs(sig - r) > 2 else r + 7
                    pasos = [(0, r, 1.3), (1.5, r, 0.45), (2.5, r + 7, 0.9), (3.5, paso, 0.45)]
                else:
                    pasos = [(0, r, 1.2), (1.5, r + 7, 0.45)]
                for b, m, d in pasos:
                    p.poner('bajo', bk + b, s.bajo_pluck(s.hz(m), d * p.spb), 1.0, humano=0.003)
                if f >= 1:
                    arp = vs + [vs[1] + 12, vs[0] + 12]
                    for i in range(int(largo * 2)):
                        p.poner('kalimba', bk + i * 0.5, s.kalimba(s.hz(arp[i % len(arp)] + 12), 0.6), 0.8 if i % 2 == 0 else 0.55, humano=0.004)
            p.poner('bombo', bc, s.kick(suave_=True))
            p.poner('bombo', bc + 2.5, s.kick(suave_=True), 0.8)
            if c % 2 == 1:
                p.poner('bombo', bc + 1.75, s.kick(suave_=True), 0.5)
            p.poner('caja', bc + 1, s.snare(seco=False, oscuro=True), 0.8, humano=0.003)
            p.poner('caja', bc + 3, s.snare(seco=False, oscuro=True), 0.85, humano=0.003)
            for k in range(16 if f >= 1 else 8):
                paso = 0.25 if f >= 1 else 0.5
                p.poner('hat', bc + k * paso, s.hat(), (0.7 if (k * paso) % 1 == 0 else 0.4) * (0.8 if f >= 1 else 1), humano=0.003)
        for k, g in enumerate([0.3, 0.45, 0.6, 0.75]):
            p.poner('caja', b0 + 15 + k * 0.25, s.snare(seco=False, oscuro=True), g * (1 if f % 2 else 0.5))
    p.poner('hat', 0, s.platillo(), 0.4)
    p.poner('hat', 32, s.platillo(), 0.4)
    return p.mezcla({
        'lead': (-14, 0.25, 0.12), 'resp': (-19, 0.3, 0.2), 'doble': (-25, 0.3, 0.1), 'rhodes': (-21, 0.3, 0),
        'kalimba': (-29, 0.3, 0.15), 'bajo': (-19, 0.04, 0), 'bombo': (-21, 0.02, 0), 'caja': (-27, 0.2, 0),
        'hat': (-34, 0.05, 0), 'morse': (-31, 0.1, 0),
    }, reverb_tau=0.3, eco_beats=1.0, eco_fb=0.25)


MUSICAS = {'musica_tuberia': musica_tuberia, 'musica_destapa': musica_destapa, 'musica_fusion': musica_fusion}


def main():
    salida = sys.argv[1] if len(sys.argv) > 1 else s.SALIDA
    os.makedirs(salida, exist_ok=True)
    for nombre, f in MUSICAS.items():
        x = f()
        s.escribir_m4a(os.path.join(salida, nombre + '.m4a'), x, s.SRM)
        print(f'{nombre:16s} {len(x) / s.SRM:5.2f} s')


if __name__ == '__main__':
    main()
