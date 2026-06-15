#!/usr/bin/env bash
# fotball-llm-ctl.sh - management helper for the Football Live LLM commentator.
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

# Open a URL in the user's browser, robustly. Two problems are solved here:
#  1. On KDE, xdg-open delegates to kde-open/kioclient which can fail silently,
#     so we launch the real browser binary directly (default-browser .desktop
#     Exec → known binary → opener as last resort).
#  2. When called from the Plasma "executable" engine (tray menu / config dialog),
#     a plain `setsid … &` child can get reaped when the engine disconnects the
#     source. So we FULLY detach via `systemd-run --user` (a transient unit that
#     plasmashell cannot kill); `setsid` is only the fallback.
browser_open() {
    local URL="$1" DESK EXECLINE dir b cmd=""
    : >>"$HOME/.cache/fotballtray/open.log" 2>/dev/null
    DESK=$(xdg-settings get default-web-browser 2>/dev/null || true)
    if [ -n "$DESK" ]; then
        for dir in "$HOME/.local/share/applications" /usr/local/share/applications /usr/share/applications; do
            [ -f "$dir/$DESK" ] || continue
            EXECLINE=$(grep -m1 '^Exec=' "$dir/$DESK" | sed 's/^Exec=//; s/ *%[uUfFick]//g')
            [ -n "$EXECLINE" ] && { cmd="$EXECLINE"; break; }
        done
    fi
    if [ -z "$cmd" ]; then
        for b in firefox chromium chromium-browser google-chrome brave-browser microsoft-edge; do
            command -v "$b" >/dev/null 2>&1 && { cmd="$b"; break; }
        done
    fi
    [ -z "$cmd" ] && command -v xdg-open >/dev/null 2>&1 && cmd="xdg-open"
    [ -z "$cmd" ] && return 1
    echo "$(date '+%F %T') open via: $cmd  $URL" >>"$HOME/.cache/fotballtray/open.log" 2>/dev/null
    # `sh -c '<cmd> "$0"' "$URL"` keeps multi-word cmds (e.g. "env … firefox") and
    # the URL intact. systemd-run detaches it from the caller entirely.
    if command -v systemd-run >/dev/null 2>&1; then
        systemd-run --user --quiet --collect sh -c "$cmd \"\$0\"" "$URL" 2>>"$HOME/.cache/fotballtray/open.log" && return 0
    fi
    setsid sh -c "$cmd \"\$0\"" "$URL" >/dev/null 2>&1 &
    return 0
}

# Commentator style/language profiles (the "plugin" system).
PROFILES_DIR="$HOME/.local/share/fotballtray/commentators"
PROFILE_FILE="$HOME/.cache/fotballtray/commentator-profile"
active_style() { cat "$PROFILE_FILE" 2>/dev/null || echo british; }

# Generic completion via the ACTIVE backend (cloud or Ollama). $1=system $2=user.
# Echoes the model's text. JSON payloads are built in Python (robust quoting).
llm_complete() {
    local SYS="$1" USR="$2" BASE KEY MODEL M
    if cloud_active; then
        BASE=$(grep -oP 'LLM_API_BASE=\K\S+' "$CLOUD_CONF" 2>/dev/null)
        KEY=$(grep -oP 'LLM_API_KEY=\K\S+'  "$CLOUD_CONF" 2>/dev/null)
        MODEL=$(grep -oP 'LLM_MODEL=\K\S+'  "$CLOUD_CONF" 2>/dev/null)
        # Build an ordered list of candidate models (configured one first, then a
        # preference list of capable instruct models), so a rate-limited free model
        # falls through to the next one.
        local CANDS
        CANDS=$(curl -s --max-time 12 "$BASE/models" -H "Authorization: Bearer $KEY" \
            | CFG="$MODEL" python3 -c 'import sys,json,os
try:
    ids=[m.get("id","") for m in json.load(sys.stdin).get("data",[])]
except Exception: ids=[]
free=[i for i in ids if i.endswith(":free")] or ids
pref=("llama-3.3-70b","llama-3.1-70b","deepseek-chat","deepseek-v3","qwen-2.5-72b","qwen3","mistral","gemini-2","gemma")
out=[]
cfg=os.environ.get("CFG","")
if cfg and cfg!="auto": out.append(cfg)
for p in pref:
    c=next((i for i in free if p in i.lower() and i not in out), "")
    if c: out.append(c)
for i in free:
    if i not in out: out.append(i)
print("\n".join(out[:5]))')
        [ -z "$CANDS" ] && return 1
        local m txt
        while IFS= read -r m; do
            [ -z "$m" ] && continue
            txt=$(curl -s --max-time 90 "$BASE/chat/completions" \
                -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
                -d "$(M="$m" S="$SYS" U="$USR" python3 -c 'import json,os; print(json.dumps({"model":os.environ["M"],"max_tokens":2000,"temperature":0.7,"messages":[{"role":"system","content":os.environ["S"]},{"role":"user","content":os.environ["U"]}]}))')" \
                | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin)
    if "error" in d: print("");
    else:
        c=d.get("choices") or []; print(c[0]["message"].get("content","") if c else "")
except Exception: print("")')
            if [ -n "$txt" ]; then printf '%s' "$txt"; return 0; fi
        done <<< "$CANDS"
        return 1
    else
        M=$(current_model); ensure_serving || return 1
        curl -s --max-time 120 "$OLLAMA_URL/api/generate" \
            -d "$(M="$M" S="$SYS" U="$USR" python3 -c 'import json,os; print(json.dumps({"model":os.environ["M"],"system":os.environ["S"],"prompt":os.environ["U"],"stream":False,"think":False,"options":{"temperature":0.7,"num_predict":2000}}))')" \
            | python3 -c 'import sys,json
try: print(json.load(sys.stdin).get("response",""))
except Exception: print("")'
    fi
}

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
        STY=$(active_style)
        ACCENT=$(python3 -c "import json,os;print(json.load(open(os.path.expanduser('$PROFILES_DIR/$STY.json'))).get('accent','#2E9BF0'))" 2>/dev/null || echo "#2E9BF0")
        printf '{"backend":"%s","cloudBase":"%s","cloudModel":"%s","style":"%s","accent":"%s","ollamaInstalled":%s,"ollamaRunning":%s,"model":"%s","modelInstalled":%s,"serviceActive":%s,"serviceEnabled":%s,"models":"%s"}\n' \
            "$BACKEND" "$CB" "$CM" "$STY" "$ACCENT" "$OI" "$OR" "$M" "$MI" "$SA" "$SE" "$MODELS"
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
    make-style)
        # Wizard: turn a plain-text description into a full commentator profile.
        # The model writes the creative parts; we guarantee a valid voice/lang +
        # a good shout-on-goals prosody, so the result is always functional.
        DESC="${2:?description required}"
        SYS="You design commentator profiles for a football text-to-speech app. Output ONLY one JSON object - no prose, no code fence."
        USR="Create a football commentator profile from this description: \"$DESC\".
Return JSON with EXACTLY these keys:
  name: a short style name (max 40 chars)
  language: EXACTLY one of [British English, American English, Spanish, Brazilian Portuguese, Italian, French, Hindi, Japanese, Chinese]
  accent: a hex colour (like #E63946) that suits the style
  systemPrompt: a vivid system prompt for the commentator persona. It MUST make the model reply IN that language, present-tense and live, ERUPT on a goal, be dramatic on a red card, and end with hard rules: reply with ONLY the commentary line (no labels or quotes), 1-2 sentences, max ~35 words, normal spelling.
Output ONLY the JSON object."
        OUT=$(llm_complete "$SYS" "$USR") || { echo "FAILED: the model did not respond."; exit 1; }
        [ -z "$OUT" ] && { echo "FAILED: empty model output (all free models busy - try again in a minute)."; exit 1; }
        OUT="$OUT" python3 - <<'PY'
import sys, json, re, os, unicodedata
raw = os.environ.get("OUT", "")
raw = re.sub(r'<think>.*?</think>', '', raw, flags=re.S|re.I)   # drop reasoning
raw = re.sub(r'```(?:json)?|```', '', raw)                       # drop code fences
m = re.search(r'\{.*\}', raw, re.S)
if not m: print("FAILED: no JSON in the model output."); sys.exit(1)
try: d = json.loads(m.group(0))
except Exception as e: print("FAILED: invalid JSON from model."); sys.exit(1)
VMAP = {"British English":("bm_george","en-gb"),"American English":("am_michael","en-us"),
        "Spanish":("em_alex","es"),"Brazilian Portuguese":("pm_alex","pt-br"),
        "Italian":("im_nicola","it"),"French":("ff_siwis","fr-fr"),
        "Hindi":("hm_omega","hi"),"Japanese":("jm_kumo","ja"),"Chinese":("zm_yunjian","cmn")}
lang = d.get("language","British English")
voice, tts = VMAP.get(lang, VMAP["British English"])
name = (str(d.get("name") or "Custom style")).strip()[:40]
sp = (d.get("systemPrompt") or "").strip()
if not sp: print("FAILED: the model returned an empty persona."); sys.exit(1)
accent = (d.get("accent") or "#2E9BF0").strip()
if not re.match(r'^#?[0-9A-Fa-f]{6}$', accent): accent = "#2E9BF0"
if not accent.startswith("#"): accent = "#"+accent
slug = unicodedata.normalize("NFKD", name).encode("ascii","ignore").decode().lower()
slug = re.sub(r'[^a-z0-9]+','-',slug).strip('-') or "custom"
# don't clobber a built-in
if slug in ("british","american","spanish","brazilian","italian"): slug = slug+"-custom"
prof = {"id":slug,"name":name,"language":lang,"voice":voice,"ttsLang":tts,"accent":accent,
        "systemPrompt":sp,
        "prosody":{"goal":{"speed":1.09,"pitch":1.16,"gain":8,"shout":True},
                   "owngoal":{"speed":1.0,"pitch":1.08,"gain":4,"shout":True},
                   "redcard":{"speed":1.0,"pitch":1.06,"gain":4,"shout":True},
                   "general":{"speed":0.98,"pitch":1.0,"gain":0,"shout":False}}}
dd = os.path.expanduser("~/.local/share/fotballtray/commentators")
os.makedirs(dd, exist_ok=True)
open(os.path.join(dd, slug+".json"),"w").write(json.dumps(prof, ensure_ascii=False, indent=2))
print("DONE: created style '%s' (%s) - id %s." % (name, lang, slug))
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
    list-models)
        # list-models <provider|baseurl> [apikey]
        # A CURATED short-list (≤5) of FREE models well suited to writing short,
        # dramatic commentary lines - each with a one-line pro/con. "Auto" first.
        # If no key is given and a cloud key is already saved, reuse it.
        PROV="${2:?provider required}"; KEY="${3:-}"
        BASE=$(provider_base "$PROV")
        if [ -z "$KEY" ] && cloud_active; then
            SAVED_BASE=$(grep -oP 'LLM_API_BASE=\K\S+' "$CLOUD_CONF" 2>/dev/null)
            [ "$SAVED_BASE" = "$BASE" ] && KEY=$(grep -oP 'LLM_API_KEY=\K\S+' "$CLOUD_CONF" 2>/dev/null)
        fi
        AUTO='{"id":"auto","label":"Auto - recommended","pros":"Always picks a working free model for you.","cons":"You don’t choose which one."}'
        if [ -z "$KEY" ]; then echo "[$AUTO]"; exit 0; fi
        curl -s --max-time 12 "$BASE/models" -H "Authorization: Bearer $KEY" \
            | AUTO="$AUTO" python3 -c '
import sys, json, os
try:
    ids = [m.get("id","") for m in json.load(sys.stdin).get("data",[]) if m.get("id")]
except Exception:
    ids = []
free = [i for i in ids if i.endswith(":free")]
pool = free if free else ids        # OpenRouter→:free; Groq/Gemini→all (free tier)

# Curated catalog (family keyword → label, why good, the trade-off). Order = priority.
catalog = [
  ("llama-3.3-70b", "Llama 3.3 70B",
     "Best all-rounder: natural, dramatic, follows the brief and the word limit.",
     "A little slower than the small models."),
  ("deepseek",      "DeepSeek V3",
     "Most vivid and theatrical - superb at goal “screamers”.",
     "Can run long or get carried away with flourish."),
  ("qwen",          "Qwen 72B",
     "Crisp and obedient - sticks tightly to one or two sentences.",
     "A touch less poetic than the others."),
  ("gemini-2",      "Gemini Flash",
     "Very fast - the lowest latency for live moments.",
     "Can play it safe and sound a bit flat."),
  ("mistral",       "Mistral",
     "Light and quick, fine for short lines on modest hardware.",
     "Least dramatic flair of the bunch."),
]
out = [json.loads(os.environ["AUTO"])]
seen = set()
for key, label, pros, cons in catalog:
    m = next((i for i in pool if key in i.lower() and i not in seen), None)
    if m:
        out.append({"id": m, "label": label, "pros": pros, "cons": cons}); seen.add(m)
    if len(out) >= 5: break          # auto + up to 4 curated
print(json.dumps(out))' 2>/dev/null || echo "[$AUTO]"
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
            -d "{\"model\":\"$MODEL\",\"max_tokens\":80,\"temperature\":0.9,\"messages\":[{\"role\":\"system\",\"content\":\"You are a British TV football commentator like Peter Drury - poetic, dramatic. Reply with ONLY the line, max 35 words.\"},{\"role\":\"user\",\"content\":\"GOAL! Erupt: Haaland thunders one into the top corner to make it 2-1 for Norway at the World Cup.\"}]}" \
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
        SYS="You are a British TV football commentator in the style of Peter Drury - poetic, dramatic, breathless. Reply with ONLY the commentary line, max 35 words."
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
        # Speak a fixed sample commentary line via TTS - backend-agnostic, so it
        # tests the VOICE + audio device whether the engine is Ollama or cloud.
        DEV="${2:-}"
        python3 - <<'PY'
import json, os
p = os.path.expanduser("~/.cache/fotballtray/commentary.json")
try: d = json.load(open(p))
except Exception: d = {}
if not isinstance(d, dict): d = {}
d["__test__"] = {"text": "Haaland rises like a thunderclap, and Norway surge ahead - a world-class strike, two-one, sending a nation into rapture!", "type": "goal"}
json.dump(d, open(p, "w"), ensure_ascii=False)
PY
        ( "$HOME/.local/bin/fotball-tts.sh" __test__ "$DEV" >/dev/null 2>&1 & )
        echo "DONE: speaking a test line in the commentary voice."
        ;;
    *)
        echo "usage: $0 {status|install-ollama|pull-model <m>|set-model <m>|enable|disable|test|test-voice [dev]|key-url <prov>|open-key <prov>|test-cloud <prov> <key> [model]|set-cloud <prov> <key> [model]|use-local}"; exit 2 ;;
esac
