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


def musica_fusion():
    s.semilla('musica_fusion')
    p = s.Pista(96, 12, swing=0.58)
    frases = [
        (['Fmaj7', 'Dm9', 'Bbmaj7', 'C9'], 0, 'E5/1 G5/1 Bb5/1 D6/2 C6/1'),
        (['Bbmaj7', 'Gm9', 'Ebmaj7', 'F9'], 5, 'A5/1 C6/1 Eb6/1 G6/2 F6/1'),
        (['Fmaj7', 'Dm9', 'Bbmaj7', 'C9'], 12, 'G5/1 E5/1 D5/1 C5/2 Bb4/1'),
    ]
    mar = lambda hz, d: s.marimba(hz, 1.2, s.SRM, 0.55)  # noqa: E731
    for f, (acordes, tr, resp) in enumerate(frases):
        b0 = f * 16
        notas = [n + tr for n in CAGAR]
        motivo(p, 'lead', b0, notas, mar, humano=0.004)
        respuesta(p, 'lead', b0, resp, mar, 0.85)
        if f == 2:
            motivo(p, 'lead2', b0, notas, lambda hz, d: s.kalimba(hz, 0.8), octava=-1, humano=0.004)
        for c, nombre in enumerate(acordes):
            bc = b0 + c * 4
            r = s.raiz_bajo(nombre, 41)
            sig = s.raiz_bajo(frases[(f + 1) % 3][0][0] if c == 3 else acordes[c + 1], 41)
            for b, mm, d in [(0, r, 1.3), (1.5, r, 0.45), (2.0, r + 7, 0.9), (3.5, sig - 1 if c % 2 else r + 12, 0.45)]:
                p.poner('bajo', bc + b, s.bajo_pluck(s.hz(mm), d * p.spb), 1.0, humano=0.003)
            p.poner('pad', bc, s.pad(s.voces(nombre, 53), 4 * p.spb + 0.3), 1.0)
            if f >= 1:
                ch = s.voces(nombre, 60)
                arp = ch + [ch[1] + 12, ch[2] + 12, ch[0] + 12, ch[2]]
                for k in range(8):
                    p.poner('kalimba', bc + k * 0.5, s.kalimba(s.hz(arp[k % len(arp)]), 0.7), 0.8 if k % 2 == 0 else 0.6, humano=0.004)
            p.poner('bombo', bc, s.kick(suave_=True))
            p.poner('bombo', bc + 2.5, s.kick(suave_=True), 0.8)
            if c % 2 == 1:
                p.poner('bombo', bc + 1.75, s.kick(suave_=True), 0.5)
            p.poner('caja', bc + 1, s.snare(seco=False, oscuro=True), 0.8, humano=0.003)
            p.poner('caja', bc + 3, s.snare(seco=False, oscuro=True), 0.85, humano=0.003)
            for k in range(8):
                p.poner('hat', bc + k * 0.5, s.hat(), 0.7 if k % 2 == 0 else 0.45, humano=0.003)
        if f >= 1:
            ritmo_morse(p, 'morse', b0, s.shaker(), 1.0)
    return p.mezcla({
        'lead': (-14, 0.25, 0.3), 'lead2': (-24, 0.3, 0.2), 'kalimba': (-27, 0.3, 0.2), 'bajo': (-19, 0.04, 0),
        'pad': (-27, 0.4, 0), 'bombo': (-21, 0.02, 0), 'caja': (-27, 0.2, 0), 'hat': (-33, 0.05, 0), 'morse': (-31, 0.1, 0),
    }, reverb_tau=0.3, eco_beats=0.75, eco_fb=0.3)


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
