#!/usr/bin/env bash
# fotball-tts.sh — speak the latest AI commentary in the chosen commentator's
# voice + delivery. Reads text + event type from commentary.json, resolves the
# ACTIVE commentator profile (voice, language, prosody), synthesises (Kokoro if
# installed, else piper), then shapes the delivery: a GOAL/big moment is SHOUTED
# — higher pitch, breathless pace, compressed + EQ-boosted in the human "shout"
# band, and loud — while the run of play stays calm and measured.
# usage: fotball-tts.sh <match_id> [pulse_device_name]
set -uo pipefail

MID="${1:?match id required}"
DEV="${2:-}"
CACHE="$HOME/.cache/fotballtray"
PROFILES="$HOME/.local/share/fotballtray/commentators"
PROFILE_ID=$(cat "$CACHE/commentator-profile" 2>/dev/null || echo british)
PIPER="$HOME/.local/bin/piper"; command -v "$PIPER" >/dev/null || PIPER="$(command -v piper || true)"
PIPER_VOICE="$HOME/.local/share/piper/en_GB-alan-medium.onnx"
KOKORO_MODEL="$HOME/.local/share/kokoro/kokoro-v1.0.onnx"
KOKORO_PY="$HOME/.local/bin/fotball-kokoro.py"

TEXT=$(python3 -c "import json;print((json.load(open('$CACHE/commentary.json')).get('$MID') or {}).get('text',''))" 2>/dev/null)
TYPE=$(python3 -c "import json;print((json.load(open('$CACHE/commentary.json')).get('$MID') or {}).get('type','general'))" 2>/dev/null)
[ -z "$TEXT" ] && exit 0
[ -z "$TYPE" ] && TYPE=general

# Normalise the text FOR SPEECH ONLY (the on-screen text keeps "2-1"). A scoreline
# like "2-1" / "2 – 1" is otherwise read as "two DASH one"; turn the dash between
# two numbers (digits or number-words) into a spoken space → "two one".
TEXT=$(printf '%s' "$TEXT" | python3 -c '
import sys, re
t = sys.stdin.read()
nums = r"(?:\d+|nil|nought|zero|one|two|three|four|five|six|seven|eight|nine|ten)"
# digits/number-words joined by a hyphen/dash → space (handles "2-1", "two-nil", "2 – 1")
t = re.sub(r"\b(%s)\s*[-‐‑‒–—]\s*(%s)\b" % (nums, nums),
           r"\1 \2", t, flags=re.IGNORECASE)
sys.stdout.write(t)
' 2>/dev/null || printf '%s' "$TEXT")

# ── Resolve the active profile → voice, language, and per-event prosody ─────────
# Emits: VOICE LANG SPEED PITCH GAIN SHOUT  (space separated). Falls back to a
# sensible British default if the profile file is missing.
read -r VOICE LANG SPEED PITCH GAIN SHOUT <<EOF
$(PROFILE_ID="$PROFILE_ID" PROFILES="$PROFILES" TYPE="$TYPE" python3 - <<'PY'
import json, os
pid = os.environ["PROFILE_ID"]; d = os.environ["PROFILES"]; t = os.environ["TYPE"]
prof = {"voice":"bm_george","ttsLang":"en-gb","prosody":{
    "goal":{"speed":1.07,"pitch":1.16,"gain":8,"shout":True},
    "general":{"speed":0.96,"pitch":0.99,"gain":-1,"shout":False}}}
try:
    with open(os.path.join(d, pid + ".json")) as f: prof = json.load(f)
except Exception:
    pass
pr = prof.get("prosody", {})
m = pr.get(t) or pr.get("general") or {"speed":1.0,"pitch":1.0,"gain":0,"shout":False}
print(prof.get("voice","bm_george"), prof.get("ttsLang","en-gb"),
      m.get("speed",1.0), m.get("pitch",1.0), m.get("gain",0),
      1 if m.get("shout") else 0)
PY
)
EOF
: "${VOICE:=bm_george}" "${LANG:=en-gb}" "${SPEED:=1.0}" "${PITCH:=1.0}" "${GAIN:=0}" "${SHOUT:=0}"

WAV="$CACHE/tts_${MID}.wav"
ok=0
if [ -f "$KOKORO_MODEL" ] && [ -f "$KOKORO_PY" ]; then
    printf '%s' "$TEXT" | KOKORO_VOICE="$VOICE" KOKORO_LANG="$LANG" \
        python3 "$KOKORO_PY" "$WAV" "$SPEED" 2>/dev/null && ok=1
fi
if [ "$ok" -eq 0 ] && [ -n "$PIPER" ] && [ -f "$PIPER_VOICE" ]; then
    # piper fallback: louder + more expressive on shouted moments.
    if [ "$SHOUT" = 1 ]; then PLEN=1.0; PVOL=1.0; PNW=0.9; else PLEN=1.05; PVOL=0.85; PNW=0.78; fi
    printf '%s\n' "$TEXT" | "$PIPER" --model "$PIPER_VOICE" --length-scale "$PLEN" \
        --volume "$PVOL" --noise-w-scale "$PNW" --output_file "$WAV" 2>/dev/null && ok=1
fi

# ── Delivery shaping (ffmpeg) ───────────────────────────────────────────────────
# Pitch is shifted via asetrate→aresample→atempo(1/pitch), which RAISES pitch
# without the chipmunk/helium speed-up (the breathless pace already comes from
# the synth SPEED). A shouted moment then adds the acoustics of real shouting:
#   acompressor  — pins the dynamics up so it sits forward and "pushed"
#   equalizer    — lifts the ~2.4 kHz vocal-effort band where a shout's strain lives
#   volume+alimiter — loud, but clipping-safe
if [ "$ok" -eq 1 ] && command -v ffmpeg >/dev/null; then
    SR=$(ffprobe -v error -show_entries stream=sample_rate -of default=nk=1:nw=1 "$WAV" 2>/dev/null || echo 24000)
    SR2=$(python3 -c "print(int($SR*$PITCH))" 2>/dev/null || echo "$SR")
    INV=$(python3 -c "print(round(1/$PITCH,4))" 2>/dev/null || echo 1)
    if [ "$SHOUT" = 1 ]; then
        AF="asetrate=${SR2},aresample=${SR},atempo=${INV},acompressor=threshold=-20dB:ratio=4:attack=4:release=130:makeup=2,equalizer=f=2400:t=o:w=1.5:g=5,volume=${GAIN}dB,alimiter=level_in=1:level_out=1:limit=0.98"
    else
        AF="asetrate=${SR2},aresample=${SR},atempo=${INV},volume=${GAIN}dB"
    fi
    if ffmpeg -y -v error -i "$WAV" -af "$AF" "${WAV}.ex.wav" 2>/dev/null; then
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
