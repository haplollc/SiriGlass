#!/usr/bin/env python3
"""Reads the demo take's clock out of a simulator recording.

usage: sync.py <raw.mp4> [--pace 4]

In demo mode the page stamps its clock (4 ms steps) as a 4 x 4 grid of
black-or-white 3 pt cells in the screen's top-left corner, where the device
frame's rounded corner hides it. This decodes the stamp on every recorded
frame, fits recording time against take time, and prints:

    TRIM=<seconds into the recording where the take's clock reads 0>
    SPEED=<recording seconds per take second>

plus how densely the take was sampled, so a stuttery capture shows up before
it is rendered.
"""
import argparse
import subprocess
import sys

import numpy as np

CELL = 9          # px: 3 pt cells on a 3x screen
SIZE = CELL * 4


def frame_times(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0",
                          "-show_entries", "frame=pts_time", "-of", "csv=p=0", path],
                         capture_output=True, text=True, check=True).stdout
    return [float(line.split(",")[0]) for line in out.split() if line.strip()]


def stamps(path, count):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-fps_mode", "passthrough",
                          "-vf", f"crop={SIZE}:{SIZE}:0:0,format=gray", "-f", "rawvideo", "-"],
                         capture_output=True, check=True).stdout
    frames = np.frombuffer(raw, dtype=np.uint8).reshape(-1, SIZE, SIZE)[:count]
    values = []
    for f in frames:
        v = 0
        for bit in range(16):
            x = (bit % 4) * CELL + CELL // 2
            y = (bit // 4) * CELL + CELL // 2
            if f[y - 1:y + 2, x - 1:x + 2].mean() < 128:
                v |= 1 << bit
        values.append(v * 0.004)
    return values


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("raw")
    ap.add_argument("--pace", type=float, default=4)
    args = ap.parse_args()

    times = frame_times(args.raw)
    clocks = stamps(args.raw, len(times))
    pairs = [(t, c) for t, c in zip(times, clocks)]
    running = [(t, c) for t, c in pairs if c > 0.02]
    if len(running) < 10:
        sys.exit("no running clock found in the recording")

    t = np.array([p[0] for p in running])
    c = np.array([p[1] for p in running])
    # Frames from before the app was up hold whatever the springboard had in
    # that corner: keep only the stamps that agree with the pace.
    guess = np.median(t - args.pace * c)
    keep = np.abs(t - args.pace * c - guess) < 0.25
    t, c = t[keep], c[keep]
    speed, start = np.polyfit(c, t, 1)          # t = start + speed * c
    residual = t - (start + speed * c)
    print(f"TRIM={start:.4f}")
    print(f"SPEED={speed:.4f}")
    # How evenly the take was sampled: gaps between successive stamps, in
    # take seconds, against the 1/60 s the finished video needs.
    order = np.sort(np.unique(np.round(c, 3)))
    gaps = np.diff(order)
    print(f"# frames with a running clock: {len(running)}, take covered "
          f"{c.min():.2f}-{c.max():.2f} s, fit residual max {np.abs(residual).max() * 1000:.0f} ms")
    print(f"# take-time gap between frames: median {np.median(gaps) * 1000:.1f} ms, "
          f"95th pct {np.percentile(gaps, 95) * 1000:.1f} ms, max {gaps.max() * 1000:.1f} ms "
          f"(a 60 fps video needs <= 16.7 ms)")


if __name__ == "__main__":
    main()
