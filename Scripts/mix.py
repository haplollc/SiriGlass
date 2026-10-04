#!/usr/bin/env python3
"""Lays the demo video's soundtrack: the voice the drop reacted to, plus
a soft glass chime as the drop comes out and a fainter one as it goes back.

usage: mix.py <voice.wav> <out.wav> --summon 0.45 [5.27] --dismiss [4.67] 8.75 [--tap 4.55]

The chimes are synthesised here (two sine notes with a glassy overtone each)
and mixed into the soundtrack only, never into the file the app analyses, so
they don't move the light.
"""
import argparse
import wave

import numpy as np

RATE = 48_000


def note(freq, start, length, amp, tau, total):
    out = np.zeros(total, np.float32)
    n = int(length * RATE)
    t = np.arange(n) / RATE
    env = (1 - np.exp(-t / 0.006)) * np.exp(-t / tau)
    tone = (np.sin(2 * np.pi * freq * t) + 0.32 * np.sin(2 * np.pi * freq * 2.0 * t + 0.4)
            + 0.12 * np.sin(2 * np.pi * freq * 3.01 * t + 1.1) * np.exp(-t / (tau * 0.4)))
    i = int(start * RATE)
    seg = (tone * env * amp).astype(np.float32)
    out[i:i + n] += seg[:max(0, min(n, total - i))]
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("voice")
    ap.add_argument("out")
    ap.add_argument("--summon", type=float, nargs="+", required=True)
    ap.add_argument("--dismiss", type=float, nargs="+", required=True)
    ap.add_argument("--tap", type=float, nargs="*", default=[], help="a soft click for each tap on the stage picker")
    args = ap.parse_args()

    with wave.open(args.voice) as w:
        assert w.getframerate() == RATE and w.getnchannels() == 1
        voice = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768
    total = len(voice)

    # Out: a rising fifth, E5 then B5. Back in: the same, falling and softer.
    chimes = np.zeros(total, np.float32)
    for t in args.summon:
        chimes += note(659.25, t, 1.4, 0.10, 0.34, total) + note(987.77, t + 0.075, 1.4, 0.085, 0.38, total)
    for t in args.dismiss:
        chimes += note(987.77, t, 1.0, 0.060, 0.24, total) + note(659.25, t + 0.07, 1.0, 0.055, 0.28, total)
    # A tap: a short, soft tick.
    for t in args.tap:
        i = int(t * RATE)
        n = int(0.03 * RATE)
        tt = np.arange(n) / RATE
        tick = (np.sin(2 * np.pi * 2400 * tt) * 0.6 + np.sin(2 * np.pi * 1200 * tt) * 0.4) * np.exp(-tt / 0.006) * 0.12
        chimes[i:i + n] += tick[:max(0, min(n, total - i))].astype(np.float32)
    # A touch of width on the chimes so they sit around the voice.
    delay = int(0.0004 * RATE)
    left = voice + chimes
    right = voice + np.concatenate([np.zeros(delay, np.float32), chimes[:-delay]])
    stereo = np.stack([left, right], axis=1)
    peak = np.abs(stereo).max()
    if peak > 0.95:
        stereo *= 0.95 / peak
    pcm = (np.clip(stereo, -1, 1) * 32767).astype(np.int16)
    with wave.open(args.out, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
