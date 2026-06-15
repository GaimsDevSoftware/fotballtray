#!/usr/bin/env bash
# fotball-llm-ctl.sh — management helper for the Football Live LLM commentator.
# Invoked by the plasmoid settings (Plasma5Support executable engine) and usable
# standalone. Every action prints a final status line; `status` prints JSON.
set -uo pipefail

SERVICE="football-commentator"
SERVICE_FILE="$HOME/.config/systemd/user/${SERVICE}.service"
DROPIN_DIR="$HOME/.config/systemd/user/${SERVICE}.service.d"
OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"
DEFAULT_MODEL="gemma4:12b"
CLOUD_CONF="$DROPIN_DIR/cloud.conf"

# Map a friendly provider name to its OpenAI-compatible base URL. A value that
# already looks like a URL is passed through unchanged (custom providers).
provider_base() {
    case "$1" in
        openrouter)        echo "https://openrouter.ai/api/v1" ;;
        zen|opencode)      echo "https://opencode.ai/zen/v1" ;;
        groq)              echo "https://api.groq.com/openai/v1" ;;
        gemini|google)     echo "https://generativelanguage.googleapis.com/v1beta/openai" ;;
        http*://*)         echo "${1%/}" ;;
        *)                 echo "https://openrouter.ai/api/v1" ;;
    esac
}

# Where to send a user to create a FREE API key, per provider.
provider_keyurl() {
    case "$1" in
        openrouter)    echo "https://openrouter.ai/keys" ;;
        zen|opencode)  echo "https://opencode.ai/auth" ;;
        groq)          echo "https://console.groq.com/keys" ;;
        gemini|google) echo "https://aistudio.google.com/apikey" ;;
        *)             echo "https://openrouter.ai/keys" ;;
    esac
}

cloud_active() { [ -f "$CLOUD_CONF" ]; }

# Open a URL in the user's browser, robustly. On KDE, xdg-open delegates to
# kde-open/kioclient which can fail silently, so we launch the real browser
# binary directly (default browser via .desktop Exec → known binary → opener).
browser_open() {
    local URL="$1" DESK EXECLINE dir o b
    DESK=$(xdg-settings get default-web-browser 2>/dev/null || true)
    if [ -n "$DESK" ]; then
        for dir in "$HOME/.local/share/applications" /usr/local/share/applications /usr/share/applications; do
            [ -f "$dir/$DESK" ] || continue
            EXECLINE=$(grep -m1 '^Exec=' "$dir/$DESK" | sed 's/^Exec=//; s/ *%[uUfFick]//g')
            [ -n "$EXECLINE" ] && { setsid sh -c "$EXECLINE \"$URL\"" >/dev/null 2>&1 & return 0; }
        done
    fi
    for b in firefox chromium chromium-browser google-chrome brave-browser microsoft-edge; do
        command -v "$b" >/dev/null 2>&1 && { setsid "$b" "$URL" >/dev/null 2>&1 & return 0; }
    done
    for o in xdg-open gio kde-open6; do
        command -v "$o" >/dev/null 2>&1 || continue
        if [ "$o" = gio ]; then setsid gio open "$URL" >/dev/null 2>&1 &
        else setsid "$o" "$URL" >/dev/null 2>&1 & fi
        return 0
    done
    return 1
}

# Commentator style/language profiles (the "plugin" system).
PROFILES_DIR="$HOME/.local/share/fotballtray/commentators"
PROFILE_FILE="$HOME/.cache/fotballtray/commentator-profile"
active_style() { cat "$PROFILE_FILE" 2>/dev/null || echo british; }

have_ollama()    { command -v ollama >/dev/null 2>&1; }
ollama_running() { curl -s --max-time 3 "$OLLAMA_URL/api/tags" >/dev/null 2>&1; }

ensure_serving() {
    ollama_running && return 0
    have_ollama || return 1
    ( nohup ollama serve >/dev/null 2>&1 & )
    for _ in 1 2 3 4 5 6 7 8; do ollama_running && return 0; sleep 1; done
    return 1
}

current_model() {
    local m=""
    [ -d "$DROPIN_DIR" ] && m=$(grep -rhoP 'OLLAMA_MODEL=\K\S+' "$DROPIN_DIR"/*.conf 2>/dev/null | tail -1)
    [ -z "$m" ] && m=$(grep -oP '^Environment=OLLAMA_MODEL=\K\S+' "$SERVICE_FILE" 2>/dev/null | tail -1)
    echo "${m:-$DEFAULT_MODEL}"
}

model_installed() { ollama list 2>/dev/null | awk 'NR>1{print $1}' | grep -Fxq "$1"; }

case "${1:-status}" in
    status)
        M=$(current_model)
        OI=false; OR=false; MI=false; SA=false; SE=false; MODELS=""
        have_ollama && OI=true
        ollama_running && OR=true
        if [ "$OR" = true ]; then
            model_installed "$M" && MI=true
            MODELS=$(ollama list 2>/dev/null | awk 'NR>1{print $1}' | paste -sd, -)
        fi
        systemctl --user is-active  --quiet "$SERVICE" 2>/dev/null && SA=true
        systemctl --user is-enabled --quiet "$SERVICE" 2>/dev/null && SE=true
        BACKEND="ollama"; CB=""; CM=""
        if cloud_active; then
            BACKEND="cloud"
            CB=$(grep -oP 'LLM_API_BASE=\K\S+' "$CLOUD_CONF" 2>/dev/null | tail -1)
            CM=$(grep -oP 'LLM_MODEL=\K\S+'    "$CLOUD_CONF" 2>/dev/null | tail -1)
        fi
        printf '{"backend":"%s","cloudBase":"%s","cloudModel":"%s","style":"%s","ollamaInstalled":%s,"ollamaRunning":%s,"model":"%s","modelInstalled":%s,"serviceActive":%s,"serviceEnabled":%s,"models":"%s"}\n' \
            "$BACKEND" "$CB" "$CM" "$(active_style)" "$OI" "$OR" "$M" "$MI" "$SA" "$SE" "$MODELS"
        ;;
    key-url)
        # Print the signup URL for a provider's free key (for the settings "Get key" button).
        provider_keyurl "${2:-openrouter}"
        ;;
    list-styles)
        # JSON array of installed commentator profiles: [{id,name,language}, …]
        PROFILES_DIR="$PROFILES_DIR" python3 - <<'PY'
import json, os, glob
d = os.environ["PROFILES_DIR"]; out = []
for f in sorted(glob.glob(os.path.join(d, "*.json"))):
    try:
        p = json.load(open(f))
        out.append({"id": p.get("id", os.path.splitext(os.path.basename(f))[0]),
                    "name": p.get("name", "?"), "language": p.get("language", "")})
    except Exception:
        pass
print(json.dumps(out))
PY
        ;;
    set-style)
        ID="${2:?style id required}"
        if [ ! -f "$PROFILES_DIR/$ID.json" ]; then echo "FAILED: no such style '$ID'."; exit 1; fi
        mkdir -p "$(dirname "$PROFILE_FILE")"
        printf '%s' "$ID" > "$PROFILE_FILE"
        # The commentator reloads the profile every cycle; restart only to apply now.
        systemctl --user is-active --quiet "$SERVICE" && systemctl --user restart "$SERVICE" || true
        echo "DONE: commentator style set to '$ID'."
        ;;
    open-key)
        # Open the provider's free-key signup page in the user's browser.
        URL=$(provider_keyurl "${2:-openrouter}")
        browser_open "$URL" && echo "$URL" || { echo "FAILED: no way to open a browser."; exit 1; }
        ;;
    open-url)
        # Open an arbitrary URL (used by the tray "Support FootballTray" link).
        URL="${2:?url required}"
        case "$URL" in http://*|https://*) ;; *) echo "FAILED: refusing non-http URL."; exit 1 ;; esac
        browser_open "$URL" && echo "$URL" || { echo "FAILED: no way to open a browser."; exit 1; }
        ;;
    test-cloud)
        # test-cloud <provider|baseurl> <apikey> [model]
        PROV="${2:?provider required}"; KEY="${3:?api key required}"; MODEL="${4:-auto}"
        BASE=$(provider_base "$PROV")
        # Resolve "auto" → first free (or first) model from /models.
        if [ "$MODEL" = "auto" ]; then
            MODEL=$(curl -s --max-time 12 "$BASE/models" -H "Authorization: Bearer $KEY" \
                | python3 -c 'import sys,json
try:
    ids=[m.get("id","") for m in json.load(sys.stdin).get("data",[])]
    free=[i for i in ids if i.endswith(":free")] or ids
    print((free or [""])[0])
except Exception: print("")')
        fi
        [ -z "$MODEL" ] && { echo "FAILED: could not reach $BASE or no models (check the key)."; exit 1; }
        TEXT=$(curl -s --max-time 45 "$BASE/chat/completions" \
            -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
            -H "HTTP-Referer: https://store.kde.org/p/fotballtray" -H "X-Title: FootballTray" \
            -d "{\"model\":\"$MODEL\",\"max_tokens\":80,\"temperature\":0.9,\"messages\":[{\"role\":\"system\",\"content\":\"You are a British TV football commentator like Peter Drury — poetic, dramatic. Reply with ONLY the line, max 35 words.\"},{\"role\":\"user\",\"content\":\"GOAL! Erupt: Haaland thunders one into the top corner to make it 2-1 for Norway at the World Cup.\"}]}" \
            | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin); c=d.get("choices") or []
    print(c[0]["message"]["content"].strip() if c else "")
except Exception: print("")')
        [ -z "$TEXT" ] && { echo "FAILED: no response (key invalid, rate-limited, or model unavailable)."; exit 1; }
        echo "$TEXT"
        echo "DONE: cloud backend works (model: $MODEL)."
        ;;
    set-cloud)
        # set-cloud <provider|baseurl> <apikey> [model]
        PROV="${2:?provider required}"; KEY="${3:?api key required}"; MODEL="${4:-auto}"
        BASE=$(provider_base "$PROV")
        mkdir -p "$DROPIN_DIR"
        umask 077
        { printf '[Service]\n'
          printf 'Environment=LLM_BACKEND=openai\n'
          printf 'Environment=LLM_API_BASE=%s\n' "$BASE"
          printf 'Environment=LLM_API_KEY=%s\n'  "$KEY"
          printf 'Environment=LLM_MODEL=%s\n'    "$MODEL"
        } > "$CLOUD_CONF"
        chmod 600 "$CLOUD_CONF"
        systemctl --user daemon-reload
        systemctl --user is-active --quiet "$SERVICE" && systemctl --user restart "$SERVICE"
        echo "DONE: cloud backend set ($BASE, model $MODEL)."
        ;;
    use-local)
        # Revert to local Ollama (remove the cloud drop-in).
        rm -f "$CLOUD_CONF"
        systemctl --user daemon-reload
        systemctl --user is-active --quiet "$SERVICE" && systemctl --user restart "$SERVICE"
        echo "DONE: reverted to local Ollama."
        ;;
    install-ollama)
        if have_ollama; then echo "Ollama is already installed."; else
            echo "Installing Ollama…"
            curl -fsSL https://ollama.com/install.sh | sh || { echo "FAILED: installer error (may need privileges)"; exit 1; }
        fi
        ensure_serving && echo "DONE: Ollama ready." || echo "DONE: installed (start it with: ollama serve)."
        ;;
    pull-model)
        M="${2:?model name required}"
        ensure_serving || { echo "FAILED: Ollama is not running."; exit 1; }
        echo "Downloading '$M' (this can take several minutes)…"
        ollama pull "$M" && echo "DONE: model '$M' ready." || { echo "FAILED: could not pull '$M'."; exit 1; }
        ;;
    set-model)
        M="${2:?model name required}"
        if [ "$(current_model)" = "$M" ] && [ -f "$DROPIN_DIR/model.conf" ]; then
            echo "DONE: model already '$M'."; exit 0
        fi
        mkdir -p "$DROPIN_DIR"
        printf '[Service]\nEnvironment=OLLAMA_MODEL=%s\n' "$M" > "$DROPIN_DIR/model.conf"
        systemctl --user daemon-reload
        systemctl --user is-active --quiet "$SERVICE" && systemctl --user restart "$SERVICE"
        echo "DONE: model set to '$M'."
        ;;
    enable)
        ensure_serving || true
        systemctl --user enable --now "$SERVICE" && echo "DONE: live commentary enabled." || { echo "FAILED to enable service."; exit 1; }
        ;;
    disable)
        systemctl --user disable --now "$SERVICE" && echo "DONE: live commentary disabled." || { echo "FAILED to disable service."; exit 1; }
        ;;
    test)
        # Full pipeline test: GENERATE a line via the active backend (cloud or
        # Ollama) and SPEAK it. Tests the LLM + the voice together.
        DEV="${2:-}"
        SYS="You are a British TV football commentator in the style of Peter Drury — poetic, dramatic, breathless. Reply with ONLY the commentary line, max 35 words."
        USR="GOAL! Erupt: Haaland thunders one into the top corner to make it 2-1 for Norway at the World Cup."
        TEXT=""
        if cloud_active; then
            BASE=$(grep -oP 'LLM_API_BASE=\K\S+' "$CLOUD_CONF" 2>/dev/null)
            KEY=$(grep -oP 'LLM_API_KEY=\K\S+'  "$CLOUD_CONF" 2>/dev/null)
            MODEL=$(grep -oP 'LLM_MODEL=\K\S+'  "$CLOUD_CONF" 2>/dev/null)
            if [ -z "$MODEL" ] || [ "$MODEL" = auto ]; then
                MODEL=$(curl -s --max-time 12 "$BASE/models" -H "Authorization: Bearer $KEY" \
                    | python3 -c 'import sys,json
try:
    ids=[m.get("id","") for m in json.load(sys.stdin).get("data",[])]
    free=[i for i in ids if i.endswith(":free")] or ids
    print((free or [""])[0])
except Exception: print("")')
            fi
            [ -z "$MODEL" ] && { echo "FAILED: could not reach the cloud provider (check the key)."; exit 1; }
            TEXT=$(curl -s --max-time 45 "$BASE/chat/completions" \
                -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
                -H "HTTP-Referer: https://store.kde.org/p/fotballtray" -H "X-Title: FootballTray" \
                -d "{\"model\":\"$MODEL\",\"max_tokens\":120,\"temperature\":0.9,\"messages\":[{\"role\":\"system\",\"content\":\"$SYS\"},{\"role\":\"user\",\"content\":\"$USR\"}]}" \
                | python3 -c 'import sys,json
try:
    c=json.load(sys.stdin).get("choices") or []
    print(c[0]["message"]["content"].strip() if c else "")
except Exception: print("")')
        else
            M=$(current_model)
            ensure_serving || { echo "FAILED: Ollama is not running."; exit 1; }
            TEXT=$(curl -s --max-time 60 "$OLLAMA_URL/api/generate" \
                -d "{\"model\":\"$M\",\"system\":\"$SYS\",\"prompt\":\"$USR\",\"stream\":false,\"think\":false,\"options\":{\"temperature\":0.9,\"num_predict\":120}}" \
                | python3 -c 'import sys,json
try: print(json.load(sys.stdin).get("response","").strip())
except Exception: pass')
        fi
        [ -z "$TEXT" ] && { echo "FAILED: no response from the model."; exit 1; }
        echo "$TEXT"
        # Store as an excited (goal) line and SPEAK it with the matching voice.
        TEXT="$TEXT" python3 - <<'PY'
import json, os
p = os.path.expanduser("~/.cache/fotballtray/commentary.json")
try: d = json.load(open(p))
except Exception: d = {}
if not isinstance(d, dict): d = {}
d["__test__"] = {"text": os.environ.get("TEXT","").strip(), "type": "goal"}
json.dump(d, open(p, "w"), ensure_ascii=False)
PY
        ( "$HOME/.local/bin/fotball-tts.sh" __test__ "$DEV" >/dev/null 2>&1 & )
        ;;
    test-voice)
        # Speak a fixed sample commentary line via TTS — backend-agnostic, so it
        # tests the VOICE + audio device whether the engine is Ollama or cloud.
        DEV="${2:-}"
        python3 - <<'PY'
import json, os
p = os.path.expanduser("~/.cache/fotballtray/commentary.json")
try: d = json.load(open(p))
except Exception: d = {}
if not isinstance(d, dict): d = {}
d["__test__"] = {"text": "Haaland rises like a thunderclap, and Norway surge ahead — a world-class strike, two-one, sending a nation into rapture!", "type": "goal"}
json.dump(d, open(p, "w"), ensure_ascii=False)
PY
        ( "$HOME/.local/bin/fotball-tts.sh" __test__ "$DEV" >/dev/null 2>&1 & )
        echo "DONE: speaking a test line in the commentary voice."
        ;;
    *)
        echo "usage: $0 {status|install-ollama|pull-model <m>|set-model <m>|enable|disable|test|test-voice [dev]|key-url <prov>|open-key <prov>|test-cloud <prov> <key> [model]|set-cloud <prov> <key> [model]|use-local}"; exit 2 ;;
esac
