#!/usr/bin/env python3
"""Genera los efectos de UI de xat (WAV mono 16-bit, 44100 Hz).

Solo stdlib. Salida determinista (seed fijo). Peak <= -6 dBFS, con fade
in/out para evitar clicks. Escribe en app/sfx/.
"""

import math
import os
import random
import struct
import wave

SR = 44100
PEAK = 10 ** (-6 / 20)  # -6 dBFS
SEED = 20260108
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "app", "sfx")

random.seed(SEED)


def buf(dur):
    return [0.0] * int(round(SR * dur))


def _env(i, n, attack, release, decay):
    """Envolvente: ataque lineal, decaimiento exponencial, release al final."""
    e = math.exp(-(i / SR) / decay) if decay > 0 else 1.0
    a = max(1, int(SR * attack))
    r = max(1, int(SR * release))
    if i < a:
        e *= i / a
    if i > n - r:
        e *= max(0.0, (n - i) / r)
    return e


def add_sweep(b, start, dur, f0, f1, amp=1.0, attack=0.004, release=0.012, decay=0.09):
    """Tono con barrido exponencial de frecuencia (fase acumulada)."""
    i0 = int(SR * start)
    n = int(SR * dur)
    ph = 0.0
    for i in range(n):
        j = i0 + i
        if j >= len(b):
            break
        t = i / SR
        f = f0 * (f1 / f0) ** (t / dur) if dur > 0 else f0
        ph += 2 * math.pi * f / SR
        b[j] += amp * _env(i, n, attack, release, decay) * math.sin(ph)


def add_tone(b, start, dur, freq, amp=1.0, harm=0.0, harm3=0.0,
             attack=0.005, release=0.012, decay=0.08):
    """Tono senoidal con armónicos opcionales (2do y 3ro)."""
    i0 = int(SR * start)
    n = int(SR * dur)
    for i in range(n):
        j = i0 + i
        if j >= len(b):
            break
        t = i / SR
        s = math.sin(2 * math.pi * freq * t)
        if harm:
            s += harm * math.sin(2 * math.pi * 2 * freq * t)
        if harm3:
            s += harm3 * math.sin(2 * math.pi * 3 * freq * t)
        b[j] += amp * _env(i, n, attack, release, decay) * s


def add_noise(b, start, dur, amp=1.0, attack=0.001, release=0.008, decay=0.03):
    """Ruido de una-pole lowpass: 'pop'/click suave sin agudos duros."""
    i0 = int(SR * start)
    n = int(SR * dur)
    y = 0.0
    for i in range(n):
        j = i0 + i
        if j >= len(b):
            break
        x = random.uniform(-1.0, 1.0)
        y += 0.25 * (x - y)  # lowpass simple -> suaviza el ruido
        b[j] += amp * _env(i, n, attack, release, decay) * y


def finalize(b):
    """Normaliza a -6 dBFS y aplica fade global in/out de 5 ms."""
    m = max((abs(x) for x in b), default=0.0)
    g = (PEAK / m) if m > 0 else 1.0
    b = [x * g for x in b]
    f = max(1, int(SR * 0.005))
    n = len(b)
    for i in range(min(f, n)):
        k = i / f
        b[i] *= k
        b[n - 1 - i] *= k
    return b


def write_wav(name, b):
    path = os.path.join(OUT_DIR, name + ".wav")
    frames = bytearray()
    for x in b:
        v = int(round(max(-1.0, min(1.0, x)) * 32767))
        frames += struct.pack("<h", v)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(bytes(frames))
    print("%-12s %.3fs  %d bytes" % (name + ".wav", len(b) / SR, os.path.getsize(path)))


def gen_send():
    # "whoosh-pop": barrido ascendente rápido + pop grave suave.
    b = buf(0.18)
    add_sweep(b, 0.0, 0.14, 420.0, 1150.0, amp=0.9, decay=0.07)
    add_tone(b, 0.0, 0.06, 170.0, amp=0.7, harm=0.2, decay=0.025)
    add_noise(b, 0.0, 0.03, amp=0.18, decay=0.012)
    return b


def gen_receive():
    # Campana suave de dos notas: E5 -> B5, seno + 2do armónico, decay exp.
    b = buf(0.25)
    add_tone(b, 0.00, 0.18, 659.255, amp=0.9, harm=0.25, decay=0.075)
    add_tone(b, 0.10, 0.15, 987.767, amp=0.8, harm=0.20, decay=0.080)
    return b


def gen_tool_start():
    # Tick/blip apagado y corto.
    b = buf(0.12)
    add_tone(b, 0.0, 0.05, 480.0, amp=0.9, harm=0.10, decay=0.030)
    add_tone(b, 0.0, 0.03, 240.0, amp=0.4, decay=0.018)
    return b


def gen_tool_done():
    # Tick brillante y diminuto, más agudo.
    b = buf(0.15)
    add_tone(b, 0.0, 0.06, 1318.51, amp=0.9, harm=0.15, decay=0.030)
    add_tone(b, 0.03, 0.05, 1975.53, amp=0.4, harm=0.10, decay=0.025)
    return b


def gen_approve():
    # Chime ascendente de tercera mayor: C5 -> E5, con brillo.
    b = buf(0.35)
    add_tone(b, 0.00, 0.28, 523.251, amp=0.9, harm=0.22, decay=0.16)
    add_tone(b, 0.09, 0.24, 659.255, amp=0.9, harm=0.18, decay=0.15)
    add_tone(b, 0.16, 0.18, 783.991, amp=0.35, harm=0.12, decay=0.12)
    return b


def gen_alert():
    # Dos pulsos suaves de atención (pendiente de aprobación), no alarma.
    b = buf(0.40)
    add_tone(b, 0.00, 0.13, 622.25, amp=0.8, harm=0.15,
             attack=0.020, release=0.030, decay=0.075)
    add_tone(b, 0.20, 0.13, 622.25, amp=0.8, harm=0.15,
             attack=0.020, release=0.030, decay=0.075)
    return b


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, gen in [
        ("send", gen_send),
        ("receive", gen_receive),
        ("tool_start", gen_tool_start),
        ("tool_done", gen_tool_done),
        ("approve", gen_approve),
        ("alert", gen_alert),
    ]:
        write_wav(name, finalize(gen()))


if __name__ == "__main__":
    main()
