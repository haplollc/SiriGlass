#!/bin/zsh
# usage: Scripts/record.sh <voice.wav> <out.mp4> <cues> <length seconds>
# Records the demo's scripted take on a simulator, for the README's media.
#
# PACE (default 4) slows the take's clock so a busy machine still gets every
# frame; Scripts/sync.py reads the take's timing back out of the clock stamp
# in the corner and Scripts/retime.py rebuilds it at a steady 60 fps. The
# take is drawn once first (Scripts/still.sh), so the shader pipeline is
# built before the recording starts; on a busy machine that can take half a
# minute. STAGE=iPhone opens on the home screen instead of the orb.
#
# SIM picks the simulator (a UDID or name; default the booted one).
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
SIM=${SIM:-booted}
VOICE="$1"; OUT="$2"; CUES="$3"; LENGTH="$4"
PACE=${PACE:-4}
HOLD=${HOLD:-2}
STAGE=${STAGE:-orb}
APP=com.haplo.SiriGlassDemo

# Warm up: draw the take once so the pipeline is cached.
SIM="$SIM" STAGE="$STAGE" "$HERE/still.sh" "$VOICE" "${WARM_AT:-2.6}" "${OUT%.mp4}_warm.png" "$CUES" >/dev/null

xcrun simctl terminate "$SIM" $APP 2>/dev/null || true
# Let the warm-up's last frame leave the screen before recording: it
# carries a clock stamp of its own (retime.py would drop it anyway).
python3 -c "import time; time.sleep(1.5)"
rm -f "$OUT"
xcrun simctl io "$SIM" recordVideo --codec h264 --force "$OUT" &
REC=$!
python3 -c "import time; time.sleep(1.5)"
env SIMCTL_CHILD_SIRIGLASS_DEMO=1 SIMCTL_CHILD_SIRIGLASS_AUDIO="$VOICE" \
    SIMCTL_CHILD_SIRIGLASS_CUES="$CUES" SIMCTL_CHILD_SIRIGLASS_STAGE="$STAGE" \
    SIMCTL_CHILD_SIRIGLASS_PACE="$PACE" SIMCTL_CHILD_SIRIGLASS_HOLD="$HOLD" \
    xcrun simctl launch "$SIM" $APP >/dev/null
python3 -c "import time; time.sleep($HOLD + $LENGTH * $PACE + 4)"
kill -INT $REC
wait $REC 2>/dev/null || true
ffprobe -v error -show_entries format=duration:stream=width,height,avg_frame_rate,nb_frames -of default=nw=1 "$OUT"
