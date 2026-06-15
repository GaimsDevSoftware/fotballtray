#!/usr/bin/env python3
"""
football-commentator.py — Ollama-powered live English football commentary.

Self-contained: watches the fetcher's matches.json for NEW high-value events
(goals, own goals, red cards) on live matches, asks a local Ollama model for a
one-line English commentary, and writes it to commentary.json — a small overlay
file that fotball-data-fetcher.py merges into each match's summary (so the
commentary survives the fetcher rewriting matches.json every cycle).

No Sofascore dependency (that API is Cloudflare-blocked); the events already
live in matches.json thanks to the FotMob/ESPN enrichment.

Run as a systemd user service (football-commentator.service).

    Environment=OLLAMA_MODEL=gemma4:12b     # any installed Ollama model
    Environment=OLLAMA_URL=http://localhost:11434
"""

import json
import logging
import os
import re
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import requests

# ── Config (override via environment variables) ────────────────────────────────

OLLAMA_URL   = os.environ.get("OLLAMA_URL",   "http://localhost:11434")
OLLAMA_MODEL = os.environ.get("OLLAMA_MODEL", "gemma4:12b")

# Cloud backend (OpenAI-compatible: OpenRouter, OpenCode Zen, Groq, Gemini shim…).
# When LLM_BACKEND=openai the commentator calls a hosted chat-completions API
# instead of local Ollama, so users with no GPU still get live commentary.
# LLM_MODEL="auto" → auto-pick a free model from the provider's /models list.
LLM_BACKEND  = os.environ.get("LLM_BACKEND", "ollama").strip().lower()
LLM_API_BASE = os.environ.get("LLM_API_BASE", "https://openrouter.ai/api/v1").rstrip("/")
LLM_API_KEY  = os.environ.get("LLM_API_KEY", "").strip()
LLM_MODEL    = os.environ.get("LLM_MODEL", "auto").strip()

CACHE_DIR       = Path.home() / ".cache" / "fotballtray"
MATCHES_FILE    = CACHE_DIR / "matches.json"
COMMENTARY_FILE = CACHE_DIR / "commentary.json"          # overlay merged by the fetcher
ARCHIVE_FILE    = CACHE_DIR / "commentary_archive.jsonl"  # every line, for fine-tuning
SEEN_FILE       = CACHE_DIR / "commentator_seen.json"
LOG_FILE        = CACHE_DIR / "commentator.log"

POLL_INTERVAL  = 5    # seconds between matches.json checks
OLLAMA_TIMEOUT = 45   # generation timeout

# Only these (rare, notable) events get a comment — calm-tech, no spam.
HIGH_VALUE = {"goal", "owngoal", "redcard"}

# ── English football system prompt ─────────────────────────────────────────────

SYSTEM_PROMPT = """\
You are a British television football commentator — the poetry of Peter Drury
married to the explosive timing of Martin Tyler, the voice of a Premier League
or World Cup night on Sky Sports.

Voice and style:
- Present tense, live and breathless — you are calling the action AS it happens.
- Vivid and theatrical: reach for a striking image or a line of poetry, build the
  drama with short punchy clauses and repetition for effect — but never waffle.
- On a goal, ERUPT: savour the scorer's name, then place the moment in the story
  of the match. Be dramatic for a red card; a touch sympathetic for an own goal.
- British English. Call it football. Mention the minute or score when it lands well.
Hard rules:
- Reply with ONLY the commentary line — no preamble, no labels, no quotation marks.
- 1-2 sentences, max ~35 words. Normal spelling (no "goooal" — the delivery carries it).
"""

EVENT_PROMPTS = {
    "goal":     "GOAL! Erupt — call this goal like a great commentator:\n",
    "owngoal":  "OWN GOAL! Call it dramatically but with a touch of sympathy:\n",
    "redcard":  "RED CARD! A dramatic, theatrical commentary line:\n",
}

# ── Commentator profile (style/language plugin) ────────────────────────────────
# The active profile is a JSON file under ~/.local/share/fotballtray/commentators/
# selected by id in ~/.cache/fotballtray/commentator-profile. Each profile supplies
# its own systemPrompt (and language/voice, the latter used by the TTS helper).
_DEFAULT_SYSTEM_PROMPT = SYSTEM_PROMPT
PROFILES_DIR = Path.home() / ".local" / "share" / "fotballtray" / "commentators"
PROFILE_FILE = CACHE_DIR / "commentator-profile"

def refresh_profile() -> None:
    """Reload SYSTEM_PROMPT from the active commentator profile (hot-swappable)."""
    global SYSTEM_PROMPT
    try:
        pid = PROFILE_FILE.read_text().strip() or "british"
        prof = json.loads((PROFILES_DIR / f"{pid}.json").read_text())
        SYSTEM_PROMPT = prof.get("systemPrompt") or _DEFAULT_SYSTEM_PROMPT
    except Exception:
        SYSTEM_PROMPT = _DEFAULT_SYSTEM_PROMPT

# Occasional "run of play" commentary (not tied to an event), every few minutes.
GENERAL_INTERVAL = 900  # 15 min of QUIET (no events) → a run-of-play comment
GENERAL_PROMPT = "Paint the run of play in a British commentator's voice — who is on top, the feel of the game, one line:\n"
_last_general = {}  # match_id → monotonic time of last general comment


def build_general_prompt(m):
    stats = m.get("stats") or {}
    def pair(k):
        v = stats.get(k) or {}
        return v.get("homeValue"), v.get("awayValue")
    details = {
        "minute":   str(m.get("clock") or m.get("display") or ""),
        "homeTeam": m.get("homeTeam", ""),
        "awayTeam": m.get("awayTeam", ""),
        "score":    f"{m.get('homeScore', 0)}-{m.get('awayScore', 0)}",
        "league":   m.get("league", ""),
    }
    for key, label in (("possessionPct", "possession"), ("expectedGoals", "xG"), ("totalShots", "shots")):
        h, a = pair(key)
        if h is not None:
            details[label] = f"{h}-{a}"
    return GENERAL_PROMPT + json.dumps({k: v for k, v in details.items() if v != ""},
                                       ensure_ascii=False, indent=2)


def maybe_general(model, m):
    """Generate an occasional run-of-play comment for a live match."""
    mid = str(m.get("id", ""))
    now = time.monotonic()
    last = _last_general.get(mid)
    if last is None:
        _last_general[mid] = now            # baseline on first sight, don't comment
        return 0
    if now - last < GENERAL_INTERVAL:
        return 0
    _last_general[mid] = now
    text = generate(build_general_prompt(m), model)
    if not text:
        return 0
    log.info("Run-of-play → %s", text)
    save_commentary(mid, "general", {"clock": m.get("clock", "")}, text)
    archive({"match_id": mid, "kind": "general",
             "context": {"homeTeam": m.get("homeTeam"), "awayTeam": m.get("awayTeam"),
                         "score": f"{m.get('homeScore',0)}-{m.get('awayScore',0)}",
                         "league": m.get("league")},
             "commentary": text, "model": model,
             "processed": datetime.now(timezone.utc).isoformat()})
    return 1

# ── Ollama helpers ─────────────────────────────────────────────────────────────

def ollama_is_running() -> bool:
    try:
        return requests.get(f"{OLLAMA_URL}/api/tags", timeout=3).status_code == 200
    except Exception:
        return False


def list_models() -> list:
    try:
        r = requests.get(f"{OLLAMA_URL}/api/tags", timeout=5)
        r.raise_for_status()
        return [m["name"] for m in r.json().get("models", [])]
    except Exception:
        return []


def pick_model(preferred: str) -> Optional[str]:
    """Best available model, preferring the configured one, then a small one."""
    available = list_models()
    if not available:
        return None
    if any(preferred == m or preferred in m for m in available):
        return preferred
    for cand in ["phi4-mini", "phi4", "llama3.2", "gemma4:12b", "gemma4", "qwen3-vl:8b", "qwen3"]:
        for m in available:
            if cand in m:
                log.info("Preferred model '%s' not installed, using '%s'", preferred, m)
                return m
    log.warning("Configured model not found; using '%s'", available[0])
    return available[0]


def _clean(text: str) -> str:
    # Drop any chain-of-thought, code fences, surrounding quotes and labels.
    text = re.sub(r"<think>.*?</think>", "", text, flags=re.S | re.I).strip()
    text = re.sub(r"^```.*?$|```$", "", text, flags=re.M).strip()
    for pre in ("Commentary:", "Commentator:", "Note:", "Here's", "Sure,"):
        if text.lower().startswith(pre.lower()):
            text = text[len(pre):].lstrip(" :-").strip()
    text = text.strip().strip('"').strip("'").strip()
    # Keep it to the first paragraph / a couple of sentences.
    return text.split("\n")[0].strip()


def generate(prompt: str, model: str) -> Optional[str]:
    """Backend-agnostic entry point used everywhere in the script."""
    if LLM_BACKEND == "openai":
        return generate_openai(prompt, model)
    return generate_ollama(prompt, model)


def generate_ollama(prompt: str, model: str) -> Optional[str]:
    try:
        r = requests.post(
            f"{OLLAMA_URL}/api/generate",
            json={
                "model": model,
                "system": SYSTEM_PROMPT,
                "prompt": prompt,
                "stream": False,
                "think": False,
                "options": {
                    "temperature": 0.8, "top_p": 0.9,
                    "num_predict": 90, "stop": ["\n\n", "###"],
                },
            },
            timeout=OLLAMA_TIMEOUT,
        )
        r.raise_for_status()
        return _clean(r.json().get("response", "")) or None
    except requests.Timeout:
        log.warning("Ollama timed out after %ds", OLLAMA_TIMEOUT)
        return None
    except Exception as e:
        log.warning("Ollama generate failed: %s", e)
        return None


# ── Cloud backend (OpenAI-compatible chat completions) ─────────────────────────

def generate_openai(prompt: str, model: str) -> Optional[str]:
    try:
        r = requests.post(
            f"{LLM_API_BASE}/chat/completions",
            headers={
                "Authorization": f"Bearer {LLM_API_KEY}",
                "Content-Type": "application/json",
                # OpenRouter attribution headers (harmless on other providers).
                "HTTP-Referer": "https://store.kde.org/p/fotballtray",
                "X-Title": "FootballTray",
            },
            json={
                "model": model,
                "messages": [
                    {"role": "system", "content": SYSTEM_PROMPT},
                    {"role": "user", "content": prompt},
                ],
                "temperature": 0.8, "top_p": 0.9, "max_tokens": 120,
            },
            timeout=OLLAMA_TIMEOUT,
        )
        r.raise_for_status()
        choices = r.json().get("choices") or []
        if not choices:
            return None
        return _clean(choices[0].get("message", {}).get("content", "")) or None
    except requests.Timeout:
        log.warning("Cloud LLM timed out after %ds", OLLAMA_TIMEOUT)
        return None
    except Exception as e:
        log.warning("Cloud LLM generate failed: %s", e)
        return None


def cloud_ready() -> bool:
    if not LLM_API_KEY:
        log.warning("LLM_BACKEND=openai but LLM_API_KEY is empty.")
        return False
    try:
        r = requests.get(
            f"{LLM_API_BASE}/models",
            headers={"Authorization": f"Bearer {LLM_API_KEY}"},
            timeout=8,
        )
        return r.status_code == 200
    except Exception:
        return False


def cloud_pick_model() -> Optional[str]:
    """Use the configured model, or auto-pick a sensible free one from /models."""
    if LLM_MODEL and LLM_MODEL.lower() != "auto":
        return LLM_MODEL
    try:
        r = requests.get(
            f"{LLM_API_BASE}/models",
            headers={"Authorization": f"Bearer {LLM_API_KEY}"},
            timeout=8,
        )
        r.raise_for_status()
        ids = [m.get("id", "") for m in r.json().get("data", [])]
        free = [i for i in ids if i.endswith(":free")]
        pool = free or ids
        # Prefer capable, fast instruct chat models for one-liners.
        for pref in ("deepseek/deepseek-chat", "meta-llama/llama-3.3-70b",
                     "meta-llama/llama-3.1-70b", "qwen/qwen-2.5-72b",
                     "google/gemini", "mistralai/mistral"):
            for i in pool:
                if pref in i:
                    return i
        return pool[0] if pool else None
    except Exception as e:
        log.warning("Could not list cloud models: %s", e)
        return None


def backend_ready() -> bool:
    return cloud_ready() if LLM_BACKEND == "openai" else ollama_is_running()


def resolve_model() -> Optional[str]:
    return cloud_pick_model() if LLM_BACKEND == "openai" else pick_model(OLLAMA_MODEL)


# ── Event extraction from matches.json ─────────────────────────────────────────

def event_kind(e: dict) -> str:
    t = str(e.get("type", "")).lower()
    if t in ("goal", "owngoal", "redcard", "yellowcard", "substitution"):
        return t
    txt = str(e.get("text", "")).lower()
    if "own goal" in txt:                 return "owngoal"
    if "red card" in txt:                 return "redcard"
    if re.search(r"\bgoal\b", txt):       return "goal"
    return t


def event_player(e: dict) -> str:
    if e.get("scorer"):
        return e["scorer"]
    txt = str(e.get("text", ""))
    # "Goal – Name", "Red card – Name (...)"
    if "–" in txt:
        name = txt.split("–", 1)[1]
        name = re.split(r"\(", name)[0]
        return name.strip()
    return ""


def event_key(match_id: str, e: dict, kind: str) -> str:
    return f"{match_id}|{kind}|{str(e.get('clock',''))}|{event_player(e)}"


def build_prompt(kind: str, e: dict, match: dict) -> str:
    template = EVENT_PROMPTS.get(kind, "Commentate this event:\n")
    details = {
        "minute":    str(e.get("clock", "?")),
        "event":     kind,
        "player":    event_player(e),
        "homeTeam":  match.get("homeTeam", ""),
        "awayTeam":  match.get("awayTeam", ""),
        "score":     f"{match.get('homeScore', 0)}-{match.get('awayScore', 0)}",
        "league":    match.get("league", ""),
    }
    return template + json.dumps({k: v for k, v in details.items() if v != ""},
                                 ensure_ascii=False, indent=2)


# ── Overlay + state I/O ─────────────────────────────────────────────────────────

def load_json(path: Path, default):
    try:
        return json.loads(path.read_text()) if path.exists() else default
    except Exception:
        return default


def save_commentary(match_id: str, kind: str, e: dict, text: str) -> None:
    data = load_json(COMMENTARY_FILE, {})
    if not isinstance(data, dict):
        data = {}
    data[match_id] = {
        "text":   text,
        "clock":  str(e.get("clock", "")),
        "type":   kind,
        "player": event_player(e),
        "ts":     datetime.now(timezone.utc).isoformat(),
    }
    tmp = COMMENTARY_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2))
    tmp.rename(COMMENTARY_FILE)


def archive(entry: dict) -> None:
    with open(ARCHIVE_FILE, "a") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")


# ── Main loop ──────────────────────────────────────────────────────────────────

def process(model: str, seen: dict) -> int:
    data = load_json(MATCHES_FILE, None)
    if not data:
        return 0
    matches = data.get("matches", []) if isinstance(data, dict) else []
    live = [m for m in matches if m.get("status") in ("in", "ht")]
    generated = 0

    for m in live:
        mid = str(m.get("id", ""))
        generated += maybe_general(model, m)
        events = m.get("keyEvents") or []
        hv = [(e, event_kind(e)) for e in events]
        hv = [(e, k) for (e, k) in hv if k in HIGH_VALUE]
        keys_now = [event_key(mid, e, k) for (e, k) in hv]

        # First time we see this match: baseline existing events, don't comment
        # on history (avoids a burst of stale commentary on startup).
        if mid not in seen:
            seen[mid] = keys_now
            continue

        prev = set(seen[mid])
        for (e, k), key in zip(hv, keys_now):
            if key in prev:
                continue
            prev.add(key)
            _last_general[mid] = time.monotonic()  # a happening resets the quiet clock
            log.info("New %s at %s: %s (%s v %s)", k, e.get("clock"),
                     event_player(e), m.get("homeAbbrev"), m.get("awayAbbrev"))
            text = generate(build_prompt(k, e, m), model)
            if not text:
                continue
            log.info("→ %s", text)
            save_commentary(mid, k, e, text)
            archive({"match_id": mid, "kind": k, "event": e,
                     "context": {"homeTeam": m.get("homeTeam"), "awayTeam": m.get("awayTeam"),
                                 "score": f"{m.get('homeScore',0)}-{m.get('awayScore',0)}",
                                 "league": m.get("league")},
                     "commentary": text, "model": model,
                     "processed": datetime.now(timezone.utc).isoformat()})
            generated += 1
        seen[mid] = list(prev | set(keys_now))

    return generated


def main() -> None:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [commentator] %(levelname)s %(message)s",
        handlers=[logging.StreamHandler(), logging.FileHandler(LOG_FILE)],
    )
    if LLM_BACKEND == "openai":
        log.info("Football commentator starting (backend: cloud %s, model pref: %s)",
                 LLM_API_BASE, LLM_MODEL)
    else:
        log.info("Football commentator starting (backend: ollama, model pref: %s)", OLLAMA_MODEL)

    seen = load_json(SEEN_FILE, {})
    if not isinstance(seen, dict):
        seen = {}
    model = None
    warned = False

    while True:
        try:
            refresh_profile()   # hot-swap commentator style/language
            if not backend_ready():
                if not warned:
                    if LLM_BACKEND == "openai":
                        log.warning("Cloud LLM not reachable at %s (check LLM_API_KEY).", LLM_API_BASE)
                    else:
                        log.warning("Ollama not reachable at %s — start it with: ollama serve", OLLAMA_URL)
                    warned = True
                time.sleep(20)
                continue
            warned = False
            if model is None:
                model = resolve_model()
                if not model:
                    log.warning("No model available for backend '%s'.", LLM_BACKEND)
                    time.sleep(20)
                    continue
                log.info("Using model: %s", model)
            n = process(model, seen)
            SEEN_FILE.write_text(json.dumps(seen, indent=2))
            if n:
                log.info("Generated %d commentary line(s)", n)
        except Exception:
            log.exception("Unexpected error in commentator loop")
        time.sleep(POLL_INTERVAL)


log = logging.getLogger("football-commentator")

if __name__ == "__main__":
    main()
