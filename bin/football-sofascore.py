#!/usr/bin/env python3
"""
football-sofascore.py — Live incident poller for Football Live widget.

Polls the Sofascore (unofficial) REST API for live match incidents and
statistics, detects new events, and writes them to a commentary request
queue that football-commentator.py will pick up and process with Ollama.

Run as a systemd user service (football-sofascore.service).
"""

import hashlib
import json
import logging
import os
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import requests

# ── Paths ─────────────────────────────────────────────────────────────────────

CACHE_DIR = Path.home() / ".cache" / "fotballtray"
MATCHES_FILE = CACHE_DIR / "matches.json"
QUEUE_FILE = CACHE_DIR / "commentary_queue.jsonl"
SEEN_FILE = CACHE_DIR / "sofascore_seen.json"
LOG_FILE = CACHE_DIR / "sofascore.log"

POLL_INTERVAL = 20  # seconds between full poll cycles

# ── Sofascore API ──────────────────────────────────────────────────────────────

SF_BASE = "https://api.sofascore.com/api/v1"
SF_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"
    ),
    "Referer": "https://www.sofascore.com/",
    "Accept": "application/json",
    "Accept-Language": "no,en;q=0.9",
}
SF_TIMEOUT = 12


def sf_get(path: str, session: requests.Session) -> Optional[dict]:
    try:
        r = session.get(f"{SF_BASE}{path}", headers=SF_HEADERS, timeout=SF_TIMEOUT)
        r.raise_for_status()
        return r.json()
    except requests.HTTPError as e:
        if e.response is not None and e.response.status_code == 404:
            return None  # normal — match may not be on Sofascore
        log.warning("Sofascore HTTP error %s: %s", e.response.status_code if e.response else "?", path)
        return None
    except Exception as e:
        log.warning("Sofascore request failed (%s): %s", type(e).__name__, path)
        return None


def get_live_events(session: requests.Session) -> list[dict]:
    data = sf_get("/sport/football/events/live", session)
    return data.get("events", []) if data else []


def get_incidents(event_id: int, session: requests.Session) -> list[dict]:
    data = sf_get(f"/event/{event_id}/incidents", session)
    return data.get("incidents", []) if data else []


def get_statistics(event_id: int, session: requests.Session) -> list[dict]:
    data = sf_get(f"/event/{event_id}/statistics", session)
    return data.get("statistics", []) if data else []


def get_momentum(event_id: int, session: requests.Session) -> list[dict]:
    data = sf_get(f"/event/{event_id}/graph", session)
    return data.get("graphPoints", []) if data else []


# ── Team name matching ─────────────────────────────────────────────────────────

def _norm(name: str) -> str:
    """Lowercase + strip common club suffixes for fuzzy matching."""
    return (
        name.lower()
        .replace("fc ", "").replace(" fc", "")
        .replace("cf ", "").replace(" cf", "")
        .replace("afc", "").replace("fk ", "").replace(" fk", "")
        .replace("united", "utd").replace("city", "")
        .strip()
    )


def find_sofascore_id(espn_match: dict, sf_events: list[dict]) -> Optional[int]:
    """Match an ESPN match to a Sofascore event by team name similarity."""
    home = _norm(espn_match.get("homeTeam", ""))
    away = _norm(espn_match.get("awayTeam", ""))
    if not home or not away:
        return None

    for ev in sf_events:
        sf_home = _norm(ev.get("homeTeam", {}).get("name", ""))
        sf_away = _norm(ev.get("awayTeam", {}).get("name", ""))
        # Accept if both sides have a reasonable substring overlap
        if (home in sf_home or sf_home in home) and (away in sf_away or sf_away in away):
            return ev["id"]

    return None


# ── Incident normalisation ─────────────────────────────────────────────────────

# Maps Sofascore incidentType → our canonical type
INCIDENT_TYPE_MAP = {
    "goal":            "goal",
    "own_goal":        "own_goal",
    "yellow_card":     "yellow_card",
    "red_card":        "red_card",
    "yellow_red_card": "second_yellow",
    "substitution":    "substitution",
    "var":             "var",
    "penalty":         "penalty",
    "missed_penalty":  "missed_penalty",
    "period":          "period",   # half-time / full-time whistle
}

# Only request Ollama commentary for these high-value events
COMMENTARY_EVENTS = {"goal", "own_goal", "red_card", "second_yellow", "missed_penalty", "var"}


def normalise_incident(inc: dict) -> Optional[dict]:
    raw_type = (inc.get("incidentType") or "").lower()
    canonical = INCIDENT_TYPE_MAP.get(raw_type)
    if not canonical:
        return None

    minute = inc.get("time", 0)
    extra  = inc.get("addedTime", 0)
    clock  = f"{minute}+{extra}'" if extra else f"{minute}'"

    player  = (inc.get("player")  or {}).get("name", "")
    player2 = (inc.get("playerIn") or {}).get("name", "")  # sub-in / assist
    is_home = inc.get("isHome", None)

    return {
        "type":    canonical,
        "clock":   clock,
        "minute":  minute,
        "player":  player,
        "player2": player2,
        "side":    "home" if is_home else "away" if is_home is False else "unknown",
        "description": inc.get("description", ""),
    }


def incident_key(inc: dict) -> str:
    """Stable hash for deduplication across polls."""
    raw = f"{inc['type']}|{inc['clock']}|{inc['player']}"
    return hashlib.sha256(raw.encode()).hexdigest()[:16]


# ── State persistence ──────────────────────────────────────────────────────────

def load_seen() -> dict[str, list[str]]:
    try:
        return json.loads(SEEN_FILE.read_text()) if SEEN_FILE.exists() else {}
    except Exception:
        return {}


def save_seen(seen: dict[str, set]) -> None:
    SEEN_FILE.write_text(
        json.dumps({k: list(v) for k, v in seen.items()}, indent=2)
    )


# ── Commentary queue ───────────────────────────────────────────────────────────

def enqueue_commentary(event: dict, match: dict) -> None:
    """Append a commentary request to the JSONL queue."""
    entry = {
        "ts": datetime.now(timezone.utc).isoformat(),
        "match_id": str(match.get("id", "")),
        "event": event,
        "context": {
            "homeTeam":  match.get("homeTeam", ""),
            "awayTeam":  match.get("awayTeam", ""),
            "homeScore": match.get("homeScore", 0),
            "awayScore": match.get("awayScore", 0),
            "league":    match.get("league", ""),
            "clock":     event.get("clock", ""),
        },
    }
    with open(QUEUE_FILE, "a") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")


# ── Statistics enrichment ──────────────────────────────────────────────────────

STAT_KEY_MAP = {
    "Ball possession":   "possessionPct",
    "Total shots":       "totalShots",
    "Shots on target":   "shotsOnTarget",
    "Corner kicks":      "corners",
    "Yellow cards":      "yellowCards",
    "Red cards":         "redCards",
    "Fouls":             "foulsCommitted",
    "Offsides":          "offsides",
    "Passes":            "totalPasses",
    "Tackles":           "tackles",
    "Expected goals":    "expectedGoals",
}


def flatten_statistics(sf_stats: list[dict]) -> dict:
    """Convert Sofascore statistics structure to our flat stats format."""
    result = {}
    for period_group in sf_stats:
        if period_group.get("period") != "ALL":
            continue
        for group in period_group.get("groups", []):
            for item in group.get("statisticsItems", []):
                key = STAT_KEY_MAP.get(item.get("name", ""))
                if key:
                    home_str = item.get("home", "0").replace("%", "").strip()
                    away_str = item.get("away", "0").replace("%", "").strip()
                    try:
                        result[key] = {
                            "homeValue": float(home_str),
                            "awayValue": float(away_str),
                        }
                    except ValueError:
                        pass
    return result


# ── Main polling loop ──────────────────────────────────────────────────────────

def poll_once(session: requests.Session, seen: dict[str, set]) -> bool:
    """
    One polling cycle.
    Returns True if any data was enriched.
    """
    if not MATCHES_FILE.exists():
        return False

    try:
        data = json.loads(MATCHES_FILE.read_text())
    except json.JSONDecodeError:
        log.warning("matches.json is not valid JSON, skipping cycle")
        return False

    espn_matches = data.get("matches", [])
    live_matches = [m for m in espn_matches if m.get("status") in ("in", "ht")]

    if not live_matches:
        return False

    sf_live = get_live_events(session)
    log.info("Poll: %d ESPN live, %d Sofascore live", len(live_matches), len(sf_live))

    changed = False

    for match in live_matches:
        match_id = str(match.get("id", ""))
        sf_id = find_sofascore_id(match, sf_live)

        if not sf_id:
            log.debug("No Sofascore match for %s vs %s",
                      match.get("homeTeam"), match.get("awayTeam"))
            continue

        log.debug("Matched %s vs %s → Sofascore ID %d",
                  match.get("homeTeam"), match.get("awayTeam"), sf_id)

        # ── Incidents ──────────────────────────────────────────────────
        incidents    = get_incidents(sf_id, session)
        sf_stats     = get_statistics(sf_id, session)
        momentum     = get_momentum(sf_id, session)

        seen_keys = set(seen.get(match_id, []))
        new_events = []

        for inc in incidents:
            norm = normalise_incident(inc)
            if not norm:
                continue
            key = incident_key(norm)
            if key not in seen_keys:
                seen_keys.add(key)
                new_events.append(norm)
                if norm["type"] in COMMENTARY_EVENTS:
                    enqueue_commentary(norm, match)
                    log.info(
                        "⚽ New %s at %s: %s (%s vs %s)",
                        norm["type"], norm["clock"], norm["player"],
                        match.get("homeAbbrev", "?"), match.get("awayAbbrev", "?"),
                    )

        seen[match_id] = seen_keys

        # ── Write enriched data alongside matches.json ─────────────────
        # The main commentator process reads this to avoid races with matches.json
        enriched_file = CACHE_DIR / f"sf_enriched_{match_id}.json"
        enriched_file.write_text(json.dumps({
            "matchId":    match_id,
            "sfId":       sf_id,
            "incidents":  [normalise_incident(i) for i in incidents if normalise_incident(i)],
            "stats":      flatten_statistics(sf_stats),
            "momentum":   momentum[-30:] if len(momentum) > 30 else momentum,
            "updated":    datetime.now(timezone.utc).isoformat(),
        }, ensure_ascii=False, indent=2))

        if new_events:
            changed = True

    return changed


def main() -> None:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [sofascore] %(levelname)s %(message)s",
        handlers=[
            logging.StreamHandler(),
            logging.FileHandler(LOG_FILE),
        ],
    )

    log.info("Football Sofascore poller starting (interval: %ds)", POLL_INTERVAL)

    seen = load_seen()

    # Persistent session for connection reuse and cookie handling
    session = requests.Session()
    session.headers.update(SF_HEADERS)

    # Initial warmup — Sofascore sometimes needs a real browser visit first
    try:
        warmup = session.get("https://www.sofascore.com/", timeout=10)
        log.info("Sofascore warmup: %d", warmup.status_code)
    except Exception as e:
        log.warning("Warmup failed (OK if offline): %s", e)

    while True:
        try:
            poll_once(session, seen)
            save_seen(seen)
        except Exception:
            log.exception("Unexpected error in polling cycle")

        time.sleep(POLL_INTERVAL)


log = logging.getLogger("football-sofascore")

if __name__ == "__main__":
    main()
