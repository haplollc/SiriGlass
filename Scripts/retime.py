#!/usr/bin/env python3
"""Rebuilds a paced SiriGlass demo recording at a steady 60 fps from its stamps.

usage: retime.py <raw.mp4> <out.mp4> --length 10.2 [--fps 60] [--no-delogo]

A simulator recording's timestamps wobble under load (a frame can land tens
of milliseconds late), but every frame of the take carries its own clock in
the corner stamp (see sync.py). For each output frame this picks the
recorded frame whose stamp is nearest that instant of the take, so the
result is timed exactly by the take's clock: second 0 is the take's start
and the voice file lines up from its first sample.
"""
import argparse
import os
import subprocess
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sync import frame_times, stamps  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("raw")
    ap.add_argument("out")
    ap.add_argument("--length", type=float, required=True)
    ap.add_argument("--fps", type=float, default=60)
    ap.add_argument("--no-delogo", action="store_true",
                    help="keep the bottom strip as recorded (when the page hid the home indicator)")
    args = ap.parse_args()

    times = np.array(frame_times(args.raw))
    clocks = np.array(stamps(args.raw, len(times)))
    # Only frames of the take itself. A frame left on screen from before it
    # (the warm-up still's frozen instant as the app is killed, the
    # springboard) can carry a readable stamp, and keeping it would hold
    # back every real frame until the clock caught up with it. The take's
    # frames all lie on one line, recording time against take time, so
    # find that line from the stamps themselves (the median slope between
    # frames well apart) and keep only the frames on it.
    valid = np.flatnonzero((clocks > 0.0) & (clocks < args.length + 1))
    t, c = times[valid], clocks[valid]
    span = max(len(valid) // 3, 1)
    dc = c[span:] - c[:-span]
    pace = np.median((t[span:] - t[:-span])[dc > 0.1] / dc[dc > 0.1])
    start = np.median(t - pace * c)
    valid = valid[np.abs(t - pace * c - start) < 0.25]
    # …and a clock that never runs backwards (a misread stamp would).
    keep, last = [], -1.0
    for i in valid:
        if clocks[i] >= last:
            keep.append(i)
            last = clocks[i]
    keep = np.array(keep)
    kc = clocks[keep]
    print(f"# pace {pace:.3f}; {len(keep)} frames of the take, "
          f"{int(np.sum((clocks > 0.0) & (clocks < args.length + 1))) - len(keep)} stray ones dropped")

    n_out = int(round(args.length * args.fps))
    picks, errors = [], []
    for k in range(n_out):
        t = k / args.fps
        j = int(np.argmin(np.abs(kc - t)))
        picks.append(int(keep[j]))
        errors.append(abs(kc[j] - t))
    errors = np.array(errors) * 1000
    repeats = sum(1 for a, b in zip(picks, picks[1:]) if a == b)
    print(f"# {n_out} frames from {len(set(picks))} recorded ones; timing error "
          f"median {np.median(errors):.1f} ms, max {errors.max():.1f} ms; {repeats} repeated")

    w, h = 1320, 2868
    size = w * h * 3
    dec = subprocess.Popen(["ffmpeg", "-v", "error", "-i", args.raw, "-fps_mode", "passthrough",
                            "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], stdout=subprocess.PIPE)
    # The system's home indicator isn't on a real home screen: fill its
    # strip in from the wallpaper round it.
    delogo = [] if args.no_delogo else ["-vf", "delogo=x=415:y=2822:w=490:h=30"]
    enc = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24",
                            "-s", f"{w}x{h}", "-r", str(args.fps), "-i", "-", *delogo,
                            "-c:v", "libx264", "-preset", "medium", "-crf", "10",
                            "-pix_fmt", "yuv420p", args.out], stdin=subprocess.PIPE)
    wanted = {}
    for p in picks:
        wanted[p] = wanted.get(p, 0) + 1
    last_needed = max(picks)
    index = 0
    while index <= last_needed:
        frame = dec.stdout.read(size)
        if len(frame) < size:
            break
        for _ in range(wanted.get(index, 0)):
            enc.stdin.write(frame)
        index += 1
    dec.stdout.close()
    dec.kill()
    enc.stdin.close()
    enc.wait()
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
