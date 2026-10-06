#!/usr/bin/env python3
"""Derived / synthesized SFX (all CC0 inputs, outputs CC0).

- footstep_concrete_N.wav: the CC0 carpet steps re-EQ'd for a hard floor
  (low thud cut, bright heel click + grit added, tighter tail).
- heartbeat.wav: one lub-dub cycle (~72 bpm) synthesized, loopable.
- fumble.wav: cloth/pocket pat with a small plastic knock, synthesized.

Run: python3 tools/gen_sfx.py
"""
import wave
from pathlib import Path

import numpy as np
from scipy.signal import butter, sosfilt

SR = 44100
OUT = Path(__file__).resolve().parent.parent / "audio" / "sfx"
rng = np.random.default_rng(7)


def load(name):
    with wave.open(str(OUT / name)) as w:
        x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768
        if w.getnchannels() == 2:
            x = x.reshape(-1, 2).mean(axis=1)
        return x


def save(name, x, peak=0.9):
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    with wave.open(str(OUT / name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())


def filt(x, kind, f, order=4):
    return sosfilt(butter(order, f, kind, fs=SR, output="sos"), x)


def env(n, attack, decay):
    t = np.arange(n) / SR
    return np.minimum(t / attack, 1.0) * np.exp(-t / decay)


def concrete_steps():
    for i in range(1, 5):
        src = load("footstep_carpet_%d.wav" % i)
        onset = int(np.argmax(np.abs(src) > 0.2 * np.max(np.abs(src))))
        body = filt(src, "highpass", 260.0)
        body = filt(body, "lowpass", 7000.0, 2)
        n = len(body)
        click = filt(rng.standard_normal(n), "bandpass", [2200.0, 6500.0], 2)
        click *= np.roll(env(n, 0.0004, 0.006), onset)
        grit = filt(rng.standard_normal(n), "bandpass", [3000.0, 9000.0], 2)
        grit *= np.roll(env(n, 0.004, 0.045), onset + int(0.01 * SR)) * 0.25
        x = body * 0.8 + click * 1.4 + grit
        # small hard-room slap
        for d, g in ((0.011, 0.25), (0.023, 0.14)):
            k = int(d * SR)
            x[k:] += x[:-k] * g
        tail = np.ones(n)
        cut = min(n, onset + int(0.22 * SR))
        tail[cut:] = np.exp(-np.arange(n - cut) / (0.03 * SR))
        save("footstep_concrete_%d.wav" % i, x * tail, 0.85)


def heartbeat():
    n = int(SR * 60 / 72)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for start, amp, f in ((0.0, 1.0, 52.0), (0.29, 0.7, 64.0)):
        k = int(start * SR)
        tt = t[: n - k]
        x[k:] += amp * np.sin(2 * np.pi * f * tt * (1 - 0.25 * tt)) * env(n - k, 0.006, 0.07)
    x = filt(x, "lowpass", 180.0, 2)
    save("heartbeat.wav", x, 0.9)


def fumble():
    n = int(SR * 0.55)
    x = np.zeros(n)
    for start in (0.0, 0.09, 0.2, 0.31):
        k = int(start * SR)
        m = n - k
        r = filt(rng.standard_normal(m), "bandpass", [700.0, 4500.0], 2) * env(m, 0.01, 0.05)
        x[k:] += r * rng.uniform(0.5, 1.0)
    k = int(0.24 * SR)
    m = n - k
    t = np.arange(m) / SR
    knock = np.sin(2 * np.pi * 820 * t) * env(m, 0.0005, 0.018) + filt(rng.standard_normal(m), "bandpass", [1500.0, 5000.0], 2) * env(m, 0.0003, 0.006)
    x[k:] += knock * 0.8
    save("fumble.wav", x, 0.75)


if __name__ == "__main__":
    concrete_steps()
    heartbeat()
    fumble()
