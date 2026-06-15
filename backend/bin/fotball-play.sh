#!/usr/bin/env bash
# fotball-play.sh - play a widget sound file on a chosen Pulse/PipeWire device.
# QtMultimedia's MediaPlayer device-switching is unreliable on PipeWire, so the
# widget routes sounds through here (paplay --device) for a reliable output.
# usage: fotball-play.sh <soundfile|abspath> [pulse_device_name]
set -uo pipefail

F="${1:?sound file required}"
DEV="${2:-}"
SND="$HOME/.local/share/plasma/plasmoids/org.kde.fotballtray/contents/sounds/$F"
[ -f "$SND" ] || SND="$F"   # also accept an absolute path
[ -f "$SND" ] || exit 0

if [ -n "$DEV" ]; then
    paplay --device="$DEV" "$SND" 2>/dev/null || paplay "$SND" 2>/dev/null || aplay "$SND" 2>/dev/null
else
    paplay "$SND" 2>/dev/null || aplay "$SND" 2>/dev/null
fi
