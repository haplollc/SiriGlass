#!/usr/bin/env python3
"""Builds the README's GIFs from retimed takes (record.sh, then retime.py).

usage: Scripts/media.py banner <orb_60.mp4> <iphone_60.mp4> <assets-dir> [--until 6.2] [--open 1.6]
       Scripts/media.py card <take_60.mp4> <orb|island> <assets-dir/name> [--until 9.5] [--open 2.0]

banner: the orb and the drop under the island side by side, from two takes
of the same voice and cues, so the two drops pour out, listen, think and go
home together. card: one of them on its own. Each comes out twice, as
<name>-light.gif and <name>-dark.gif, its rounded corners smoothed onto
GitHub's light and dark page colours, for a <picture> to choose between.

Every take starts and ends with the drop at home, so the GIFs loop without
a seam; --until cuts the quiet tail after it has gone home, and --open
starts the loop that far in, so its first frame (all a still view of a GIF
shows) has the drop out and lit rather than an empty stage.
"""
import argparse
import os
import subprocess
import tempfile

from PIL import Image, ImageDraw

W, H = 1320, 2868                 # a 17 Pro Max screen, px
PAGES = {"light": (255, 255, 255), "dark": (13, 17, 23)}
FPS = 25

# What each card shows, in screen pixels: the orb in the middle of its white
# stage (with the shadow under it), or the top of the home screen with the
# island and the drop hanging from it.
CROPS = {
    "orb": (0, 761, W, 761 + 1003),
    "island": (0, 0, W, 1003),
}


def frames(video, fps=FPS, until=None):
    """The video's frames as RGB images, at `fps`, up to `until` seconds."""
    proc = subprocess.Popen(["ffmpeg", "-v", "error", "-i", video, *(["-t", str(until)] if until else []), "-vf", f"fps={fps}",
                             "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], stdout=subprocess.PIPE)
    size = W * H * 3
    while True:
        raw = proc.stdout.read(size)
        if len(raw) < size:
            break
        yield Image.frombytes("RGB", (W, H), raw)
    proc.wait()


def rounded(size, radius):
    """An anti-aliased rounded-rectangle mask."""
    s = 4
    mask = Image.new("L", (size[0] * s, size[1] * s), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0] * s - 1, size[1] * s - 1), radius=radius * s, fill=255)
    return mask.resize(size, Image.LANCZOS)


def card(frame, kind, size):
    return frame.crop(CROPS[kind]).resize(size, Image.LANCZOS)


def border(canvas, box, radius, page):
    """A hairline round a white card on a white page, so the card has an edge."""
    if page == "light":
        ImageDraw.Draw(canvas).rounded_rectangle(box, radius=radius, outline=(216, 222, 228), width=1)


def rotate(folder, seconds, fps):
    """Starts the loop `seconds` in: the frames before move to the end."""
    names = sorted(n for n in os.listdir(folder) if n.endswith(".png"))
    k = int(round(seconds * fps)) % max(len(names), 1)
    if not k:
        return
    for i, name in enumerate(names):
        os.rename(os.path.join(folder, name), os.path.join(folder, f"r{(i - k) % len(names):04d}.png"))
    for i in range(len(names)):
        os.rename(os.path.join(folder, f"r{i:04d}.png"), os.path.join(folder, f"{i:04d}.png"))


def encode(folder, out, fps=FPS, start=0.0):
    """PNG frames to a GIF: one palette for the whole loop, ordered dither
    (it doesn't crawl where nothing moves), and only what changed stored
    per frame."""
    rotate(folder, start, fps)
    palette = os.path.join(folder, "palette.png")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-framerate", str(fps), "-i", os.path.join(folder, "%04d.png"),
                    "-vf", "palettegen=max_colors=256:stats_mode=full", palette], check=True)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-framerate", str(fps), "-i", os.path.join(folder, "%04d.png"),
                    "-i", palette, "-lavfi", "paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle",
                    "-loop", "0", out], check=True)
    print(out, f"{os.path.getsize(out) / 1e6:.1f} MB")


def banner(orb_video, island_video, assets, until=None, start=0.0):
    pad, gap = 24, 24
    cw, ch = 408, 310
    radius = 40
    size = (pad * 2 + cw * 2 + gap, pad * 2 + ch)
    mask = rounded((cw, ch), radius)
    boxes = [(pad, pad), (pad + cw + gap, pad)]
    with tempfile.TemporaryDirectory() as light, tempfile.TemporaryDirectory() as dark:
        for n, (a, b) in enumerate(zip(frames(orb_video, until=until), frames(island_video, until=until))):
            cards = [card(a, "orb", (cw, ch)), card(b, "island", (cw, ch))]
            for page, folder in (("light", light), ("dark", dark)):
                canvas = Image.new("RGB", size, PAGES[page])
                for c, (x, y) in zip(cards, boxes):
                    canvas.paste(c, (x, y), mask)
                    border(canvas, (x, y, x + cw - 1, y + ch - 1), radius, page)
                canvas.save(os.path.join(folder, f"{n:04d}.png"))
        encode(light, os.path.join(assets, "banner-light.gif"), start=start)
        encode(dark, os.path.join(assets, "banner-dark.gif"), start=start)


def single(video, kind, name, fps=20, until=None, start=0.0):
    cw, ch = 480, 365
    radius = 44
    mask = rounded((cw, ch), radius)
    with tempfile.TemporaryDirectory() as light, tempfile.TemporaryDirectory() as dark:
        for n, frame in enumerate(frames(video, fps, until)):
            c = card(frame, kind, (cw, ch))
            for page, folder in (("light", light), ("dark", dark)):
                canvas = Image.new("RGB", (cw, ch), PAGES[page])
                canvas.paste(c, (0, 0), mask)
                border(canvas, (0, 0, cw - 1, ch - 1), radius, page)
                canvas.save(os.path.join(folder, f"{n:04d}.png"))
        encode(light, f"{name}-light.gif", fps, start)
        encode(dark, f"{name}-dark.gif", fps, start)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="what", required=True)
    b = sub.add_parser("banner")
    b.add_argument("orb")
    b.add_argument("island")
    b.add_argument("assets")
    b.add_argument("--until", type=float)
    b.add_argument("--open", type=float, default=0.0)
    c = sub.add_parser("card")
    c.add_argument("video")
    c.add_argument("kind", choices=CROPS)
    c.add_argument("name")
    c.add_argument("--until", type=float)
    c.add_argument("--open", type=float, default=0.0)
    args = ap.parse_args()
    if args.what == "banner":
        banner(args.orb, args.island, args.assets, args.until, getattr(args, "open"))
    else:
        single(args.video, args.kind, args.name, until=args.until, start=getattr(args, "open"))


if __name__ == "__main__":
    main()
