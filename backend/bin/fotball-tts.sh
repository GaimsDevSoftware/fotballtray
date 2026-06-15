#!/usr/bin/env bash
# fotball-tts.sh — speak the latest AI commentary in a British-commentator
# delivery (Peter Drury "screamer" energy on goals). Reads text + event type
# from commentary.json, synthesises (Kokoro if installed, else piper), then
# shapes the prosody: a GOAL/big moment SOARS — much higher pitch, faster and
# louder; the run of play is slower, lower and measured.
# usage: fotball-tts.sh <match_id> [pulse_device_name]
set -uo pipefail

MID="${1:?match id required}"
DEV="${2:-}"
CACHE="$HOME/.cache/fotballtray"
PIPER="$HOME/.local/bin/piper"; command -v "$PIPER" >/dev/null || PIPER="$(command -v piper || true)"
PIPER_VOICE="$HOME/.local/share/piper/en_GB-alan-medium.onnx"
KOKORO_MODEL="$HOME/.local/share/kokoro/kokoro-v1.0.onnx"
KOKORO_PY="$HOME/.local/bin/fotball-kokoro.py"

TEXT=$(python3 -c "import json;print((json.load(open('$CACHE/commentary.json')).get('$MID') or {}).get('text',''))" 2>/dev/null)
TYPE=$(python3 -c "import json;print((json.load(open('$CACHE/commentary.json')).get('$MID') or {}).get('type','general'))" 2>/dev/null)
[ -z "$TEXT" ] && exit 0

# Delivery by moment. Excitement comes from a modest PITCH lift + loudness, NOT
# from speeding up (tempo is kept natural so it never sounds like helium).
case "$TYPE" in
    goal|owngoal|redcard)
        KOKORO_SPEED=1.04; PIPER_LEN=1.0;  PIPER_VOL=1.0; PIPER_NW=0.9
        PITCH=1.10; GAIN=5 ;;                 # higher + louder, but pace stays natural
    *)
        KOKORO_SPEED=0.96; PIPER_LEN=1.05; PIPER_VOL=0.85; PIPER_NW=0.78
        PITCH=0.99; GAIN=-1 ;;                # calm and measured
esac

WAV="$CACHE/tts_${MID}.wav"
ok=0
if [ -f "$KOKORO_MODEL" ] && [ -f "$KOKORO_PY" ]; then
    printf '%s' "$TEXT" | python3 "$KOKORO_PY" "$WAV" "$KOKORO_SPEED" 2>/dev/null && ok=1
fi
if [ "$ok" -eq 0 ] && [ -n "$PIPER" ] && [ -f "$PIPER_VOICE" ]; then
    printf '%s\n' "$TEXT" | "$PIPER" --model "$PIPER_VOICE" --length-scale "$PIPER_LEN" \
        --volume "$PIPER_VOL" --noise-w-scale "$PIPER_NW" --output_file "$WAV" 2>/dev/null && ok=1
fi

# Pitch-only shift (atempo restores duration, so the PACE stays natural — no
# chipmunk/helium) + loudness.
if [ "$ok" -eq 1 ] && command -v ffmpeg >/dev/null; then
    SR=$(ffprobe -v error -show_entries stream=sample_rate -of default=nk=1:nw=1 "$WAV" 2>/dev/null || echo 24000)
    SR2=$(python3 -c "print(int($SR*$PITCH))" 2>/dev/null || echo "$SR")
    INV=$(python3 -c "print(round(1/$PITCH,4))" 2>/dev/null || echo 1)
    if ffmpeg -y -v error -i "$WAV" -af "asetrate=${SR2},aresample=${SR},atempo=${INV},volume=${GAIN}dB" "${WAV}.ex.wav" 2>/dev/null; then
        mv -f "${WAV}.ex.wav" "$WAV"
    fi
fi

if [ "$ok" -eq 1 ]; then
    if [ -n "$DEV" ]; then
        paplay --device="$DEV" "$WAV" 2>/dev/null || paplay "$WAV" 2>/dev/null || aplay "$WAV" 2>/dev/null
    else
        paplay "$WAV" 2>/dev/null || aplay "$WAV" 2>/dev/null
    fi
else
    command -v espeak-ng >/dev/null && espeak-ng -v en-gb -s 165 "$TEXT" 2>/dev/null
fi
