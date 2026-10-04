#!/usr/bin/env python3
"""Makes the voice the demo's take reacts to, and prints its cues.

usage: Scripts/voice.py <out.wav> [--voice Samantha] [--rate 185] [--switch] [--lead 5]
                        [--lines "First request." "Second request."]

Two requests spoken with macOS `say`, laid on silence: a lead-in while the
drop comes out of the island, a breath between them, and a tail for thinking
and the drop's exit. The demo analyses this same file (SIRIGLASS_AUDIO), and
the render lays it under the video, so what you hear is what moved the light.
It never says the wake word, so playing the video can't wake a nearby phone.

With --lead 5 the first five seconds are silent: the UI tests check that the
drop stays calm before anyone speaks. --lines replaces the two requests (one
short one makes a take short enough to loop as a GIF).

Prints the SIRIGLASS_CUES line and the take's length on stdout.
"""
import argparse
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

RATE = 48_000
LINES = [
    "What's the weather going to be like in Tokyo this weekend?",
    "Remind me to pack an umbrella.",
]
SUMMON = 0.45        # the drop starts coming out
LEAD = 1.35          # first word
GAP = 0.75           # between the two requests
SWITCH_AFTER = 0.45  # with --switch: the tap on iPhone, after the first ask
SWITCH_TO_SPEECH = 1.55  # …and the second ask once the drop is back out
THINK_AFTER = 0.95   # Siri waits a beat after you stop
THINK_FOR = 1.10     # then thinks, then leaves
TAIL = 0.95          # home screen after the drop is back in


def speak(text, voice, rate, folder):
    path = os.path.join(folder, f"line{abs(hash(text))}.wav")
    subprocess.run(["say", "-v", voice, "-r", str(rate), "-o", path,
                    f"--data-format=LEI16@{RATE}", text], check=True)
    with wave.open(path) as w:
        assert w.getframerate() == RATE and w.getnchannels() == 1
        data = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768
    # say pads each line with silence; trim it so the timing is ours.
    loud = np.flatnonzero(np.abs(data) > 0.004)
    data = data[loud[0]:loud[-1] + 1] if loud.size else data
    # Short fades so no line starts or ends on a click.
    fade = min(int(0.006 * RATE), len(data) // 2)
    ramp = np.linspace(0, 1, fade, dtype=np.float32)
    data[:fade] *= ramp
    data[len(data) - fade:] *= ramp[::-1]
    return data


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--voice", default="Samantha")
    ap.add_argument("--rate", type=int, default=185)
    ap.add_argument("--lead", type=float, default=LEAD,
                    help="silence before the first word (the UI test uses a long one)")
    ap.add_argument("--switch", dest="switch", action="store_true",
                    help="leave room between the requests for the take to move from the orb to the iPhone")
    ap.add_argument("--lines", nargs="+", default=LINES, help="what to say, one request per argument")
    args = ap.parse_args()

    with tempfile.TemporaryDirectory() as folder:
        lines = [speak(t, args.voice, args.rate, folder) for t in args.lines]

    pieces = [np.zeros(int(args.lead * RATE), np.float32)]
    switch = None
    for i, line in enumerate(lines):
        if i:
            if args.switch:
                # The tap on the picker, the orb leaving, the screens
                # crossing and the drop coming back out before the next ask.
                first_end = sum(len(p) for p in pieces) / RATE
                switch = first_end + SWITCH_AFTER
                gap = switch + SWITCH_TO_SPEECH - first_end
            else:
                gap = GAP
            pieces.append(np.zeros(int(gap * RATE), np.float32))
        pieces.append(line)
    speech_end = sum(len(p) for p in pieces) / RATE
    think = speech_end + THINK_AFTER
    dismiss = think + THINK_FOR
    total = dismiss + 0.5 + TAIL
    pieces.append(np.zeros(int((total - speech_end) * RATE), np.float32))
    voice = np.concatenate(pieces)
    voice *= 0.89 / max(np.abs(voice).max(), 1e-6)

    pcm = (np.clip(voice, -1, 1) * 32767).astype(np.int16)
    with wave.open(args.out, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())

    cues = f"summon={SUMMON:.2f}" + (f",switch={switch:.2f}" if switch else "") + f",think={think:.2f},dismiss={dismiss:.2f}"
    print(f"SIRIGLASS_CUES={cues}")
    print(f"SPEECH={args.lead:.2f}-{speech_end:.2f}")
    print(f"LENGTH={total:.2f}")


if __name__ == "__main__":
    sys.exit(main())
