#!/bin/zsh
# usage: Scripts/still.sh <voice.wav> <seconds> <out.png> [cues]
# Opens the demo holding its scripted take at one instant and screenshots
# it, for checking the look frame by frame. STAGE=iPhone starts on the home
# screen; DEBUG=1 draws the glass alone.
#
# Waits for real pixels: on a busy machine a shader's pipeline can take half
# a minute to build the first time. A capture counts once the take's clock
# stamp (top-left corner) reads the frozen instant, the drop's ink is where
# it should be (when the take has it out), and two captures in a row agree.
#
# SIM picks the simulator (a UDID or name; default the booted one).
set -e
SIM=${SIM:-booted}
VOICE="$1"; AT="$2"; OUT="$3"
CUES="${4:-summon=0.45,think=7.54,dismiss=8.64}"
STAGE=${STAGE:-orb}
APP=com.haplo.SiriGlassDemo
xcrun simctl terminate "$SIM" $APP 2>/dev/null || true
env SIMCTL_CHILD_SIRIGLASS_DEMO=1 SIMCTL_CHILD_SIRIGLASS_AUDIO="$VOICE" \
    SIMCTL_CHILD_SIRIGLASS_CUES="$CUES" SIMCTL_CHILD_SIRIGLASS_FREEZE="$AT" \
    SIMCTL_CHILD_SIRIGLASS_STAGE="$STAGE" SIMCTL_CHILD_SIRIGLASS_DEBUG="${DEBUG:-0}" \
    xcrun simctl launch "$SIM" $APP >/dev/null
python3 -c "import time; time.sleep(${SETTLE:-2.5})"
PREV="${OUT%.png}.prev.png"
rm -f "$PREV"
for i in {1..90}; do
  xcrun simctl io "$SIM" screenshot --type=png "$OUT" >/dev/null 2>&1
  if python3 - "$OUT" "$PREV" "$AT" "$CUES" "$STAGE" "${DEBUG:-0}" <<'PY'
import sys
from PIL import Image, ImageChops
out, prev, at, cues, stage, debug = sys.argv[1:7]
at = float(at)
c = dict(kv.split("=") for kv in cues.split(",") if "=" in kv)
summon, dismiss = float(c.get("summon", 0.45)), float(c.get("dismiss", 1e9))
current, out_from, out_to = stage, summon, dismiss
if "switch" in c:
    sw = float(c["switch"])
    if at >= sw:
        current = "iPhone" if stage == "orb" else "orb"
        out_from = sw + 0.6
    else:
        out_to = sw
im = Image.open(out).convert("RGB")
W, H = im.size
s = 3.0                                   # px per pt on a 3x phone
# The take's clock, as the corner stamp shows it.
value = 0
for bit in range(16):
    x, y = (bit % 4) * 3 * s + 1.5 * s, (bit // 4) * 3 * s + 1.5 * s
    if sum(im.getpixel((int(x), int(y)))) / 3 < 128:
        value |= 1 << bit
stamped = value == (int(at * 250) & 0xFFFF)
# The drop's ink, when the take has it out (not with the glass alone).
drop_ok = True
if out_from + 0.4 < at < out_to and debug != "1":
    if current == "iPhone":
        box = (int(W / 2 - 60 * s), int(54 * s), int(W / 2 + 60 * s), int(66 * s))
    else:
        # The ink fills the orb's upper half; its middle is the light.
        box = (int(W / 2 - 60 * s), int(H * 0.42 - 75 * s), int(W / 2 + 60 * s), int(H * 0.42 - 45 * s))
    px = list(im.crop(box).convert("L").get_flattened_data())
    drop_ok = sum(1 for v in px if v < 80) > len(px) / 2
try:
    same = ImageChops.difference(im, Image.open(prev).convert("RGB")).getbbox() is None
except FileNotFoundError:
    same = False
im.save(prev)
sys.exit(0 if stamped and drop_ok and same else 1)
PY
  then break; fi
  python3 -c "import time; time.sleep(2)"
done
rm -f "$PREV"
echo "$OUT"
