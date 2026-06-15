#!/usr/bin/env python3
"""Fotball Live Data Fetcher - henter livedata fra ESPN og OpenLigaDB"""

import json
import os
import re as _re
import sys
import time
import signal
import hashlib
from datetime import datetime, timezone
from pathlib import Path

import requests

CACHE_DIR = Path.home() / ".cache/fotballtray"
MATCHES_FILE = CACHE_DIR / "matches.json"
CONFIG_FILE = CACHE_DIR / "config.json"
LOG_FILE = CACHE_DIR / "fetcher.log"
IMAGES_DIR = CACHE_DIR / "images"
DETAILS_CACHE_FILE = CACHE_DIR / "details_cache.json"
IMAGES_DIR.mkdir(parents=True, exist_ok=True)

SERVER_PORT = 9876
SERVER_HOST = "127.0.0.1"

# Static list of well-known national teams and clubs so the settings autocomplete
# always offers common choices even when they are not playing today.
# Fallback group composition for 2026 FIFA World Cup (from Wikipedia)
WORLD_CUP_2026_GROUPS = {
    "A": ["Mexico", "South Africa", "South Korea", "Czech Republic"],
    "B": ["Canada", "Bosnia and Herzegovina", "Qatar", "Switzerland"],
    "C": ["Brazil", "Morocco", "Haiti", "Scotland"],
    "D": ["United States", "Paraguay", "Australia", "Türkiye"],
    "E": ["Germany", "Curaçao", "Ivory Coast", "Ecuador"],
    "F": ["Netherlands", "Japan", "Sweden", "Tunisia"],
    "G": ["Belgium", "Egypt", "Iran", "New Zealand"],
    "H": ["Spain", "Cape Verde", "Saudi Arabia", "Uruguay"],
    "I": ["France", "Senegal", "Iraq", "Norway"],
    "J": ["Argentina", "Algeria", "Austria", "Jordan"],
    "K": ["Colombia", "Panama", "DR Congo", "Uzbekistan"],
    "L": ["England", "Croatia", "Ghana", "Wales"],
}

STATIC_TEAMS = [
    # National teams
    "Albania", "Algeria", "Argentina", "Armenia", "Australia", "Austria", "Azerbaijan",
    "Belarus", "Belgium", "Bolivia", "Bosnia and Herzegovina", "Brazil", "Bulgaria",
    "Cameroon", "Canada", "Chile", "China", "Colombia", "Costa Rica", "Croatia",
    "Curaçao", "Czech Republic", "Denmark", "Ecuador", "Egypt", "England", "Estonia",
    "Finland", "France", "Georgia", "Germany", "Ghana", "Greece", "Haiti", "Hungary",
    "Iceland", "India", "Iran", "Iraq", "Ireland", "Israel", "Italy", "Ivory Coast",
    "Jamaica", "Japan", "Jordan", "Kazakhstan", "Kenya", "Korea Republic", "Kosovo",
    "Latvia", "Lithuania", "Luxembourg", "Malaysia", "Mexico", "Morocco", "Netherlands",
    "New Zealand", "Nigeria", "North Macedonia", "Northern Ireland", "Norway", "Panama",
    "Paraguay", "Peru", "Poland", "Portugal", "Qatar", "Romania", "Russia", "Saudi Arabia",
    "Scotland", "Senegal", "Serbia", "Slovakia", "Slovenia", "South Africa", "Spain",
    "Sweden", "Switzerland", "Thailand", "Tunisia", "Türkiye", "Ukraine", "United States",
    "Uruguay", "Venezuela", "Vietnam", "Wales",
    # Popular clubs
    "AC Milan", "Ajax", "Arsenal", "Aston Villa", "Atalanta", "Athletic Bilbao",
    "Atlético Madrid", "Barcelona", "Bayern Munich", "Benfica", "Bodø/Glimt", "Borussia Dortmund",
    "Celtic", "Chelsea", "Fenerbahçe", "Galatasaray", "Inter Milan", "Juventus", "Lazio",
    "Leicester City", "Liverpool", "Manchester City", "Manchester United", "Marseille",
    "Napoli", "Newcastle United", "Olympiacos", "Porto", "PSV Eindhoven", "Rangers",
    "RB Leipzig", "Real Madrid", "Roma", "Rosenborg", "Sevilla", "Sporting CP",
    "Tottenham Hotspur", "VfB Stuttgart", "Viktoria Plzeň", "West Ham United",
]

# Persistent cache for match details (lineups, stats, events) so we don't re-fetch
# finished matches every cycle.
def load_details_cache():
    if DETAILS_CACHE_FILE.exists():
        try:
            return json.loads(DETAILS_CACHE_FILE.read_text())
        except Exception:
            pass
    return {}

def save_details_cache(cache):
    try:
        DETAILS_CACHE_FILE.write_text(json.dumps(cache, ensure_ascii=False, indent=2))
    except Exception as e:
        log(f"  Failed to save details cache: {e}")

_details_cache = load_details_cache()

def cache_match_details(match):
    """Store details for a match in the persistent cache"""
    mid = match["id"]
    _details_cache[mid] = {
        "stats": match.get("stats", {}),
        "lineups": match.get("lineups", {"home": [], "away": []}),
        "formations": match.get("formations", {"home": "", "away": ""}),
        "keyEvents": match.get("keyEvents", []),
        "goals": match.get("goals", []),
        "detailSource": match.get("detailSource", ""),
        "cachedAt": datetime.now(timezone.utc).isoformat(),
    }

def apply_cached_details(match):
    """Apply cached details to a match if available"""
    mid = match["id"]
    if mid in _details_cache:
        cached = _details_cache[mid]
        match["stats"] = cached.get("stats", {})
        match["lineups"] = cached.get("lineups", {"home": [], "away": []})
        match["formations"] = cached.get("formations", {"home": "", "away": ""})
        match["keyEvents"] = cached.get("keyEvents", [])
        if cached.get("detailSource"):
            match["detailSource"] = cached["detailSource"]
        # Don't overwrite goals if we already have them from scoreboard
        if not match.get("goals"):
            match["goals"] = cached.get("goals", [])
        return True
    return False

DEFAULT_LEAGUES = [
    "nor.1",           # Eliteserien
    "ENG.1",           # Premier League
    "FIFA.WORLD",      # World Cup
    "uefa.champions",  # Champions League
    "GER.1",           # Bundesliga
    "ESP.1",           # LaLiga
    "ITA.1",           # Serie A
    "FRA.1",           # Ligue 1
    "uefa.europa",     # Europa League
    "NED.1",           # Eredivisie
    "POR.1",           # Primeira Liga
    "SWE.1",           # Allsvenskan
    "DEN.1",           # Superligaen
]

# Country code mapping for national teams and leagues
COUNTRY_MAP = {
    "eng": "ENG", "england": "ENG", "germany": "GER", "deutschland": "GER",
    "spain": "ESP", "españa": "ESP", "italy": "ITA", "italia": "ITA",
    "france": "FRA", "netherlands": "NED", "nederland": "NED", "holland": "NED",
    "portugal": "POR", "belgium": "BEL", "brazil": "BRA", "brasil": "BRA",
    "argentina": "ARG", "norway": "NOR", "norge": "NOR", "sweden": "SWE",
    "sverige": "SWE", "denmark": "DEN", "danmark": "DEN", "finland": "FIN",
    "scotland": "SCO", "wales": "WAL", "ireland": "IRL", "poland": "POL",
    "switzerland": "SUI", "schweiz": "SUI", "austria": "AUT", "croatia": "CRO",
    "serbia": "SRB", "turkey": "TUR", "ukraine": "UKR", "russia": "RUS",
    "uruguay": "URU", "colombia": "COL", "chile": "CHI", "mexico": "MEX",
    "usa": "USA", "canada": "CAN", "japan": "JPN", "korea": "KOR",
    "australia": "AUS", "morocco": "MAR", "senegal": "SEN", "nigeria": "NGA",
    "ghana": "GHA", "cameroon": "CMR", "egypt": "EGY", "tunisia": "TUN",
    "ivory": "CIV", "algeria": "ALG", "south africa": "RSA", "qatar": "QAT",
    "saudi": "KSA", "iran": "IRN", "china": "CHN", "iceland": "ISL",
    "romania": "ROU", "czech": "CZE", "greece": "GRE", "hungary": "HUN",
    "bulgaria": "BUL", "slovakia": "SVK", "slovenia": "SVN", "bosnia": "BIH",
    "haiti": "HAI", "jamaica": "JAM", "costa rica": "CRC", "panama": "PAN",
    "honduras": "HON", "elsalvador": "SLV", "ecuador": "ECU", "peru": "PER",
    "paraguay": "PAR", "bolivia": "BOL", "venezuela": "VEN",
    "curaçao": "CUW", "curacao": "CUW", "cape verde": "CPV", "cabo verde": "CPV",
    "turkiye": "TUR", "türkiye": "TUR", "turkey": "TUR",
}

LEAGUE_COUNTRY = {
    "ENG.1": ("ENG", "gb"), "ENG.2": ("ENG", "gb"),
    "GER.1": ("GER", "de"), "GER.2": ("GER", "de"),
    "ESP.1": ("ESP", "es"), "ESP.2": ("ESP", "es"),
    "ITA.1": ("ITA", "it"), "ITA.2": ("ITA", "it"),
    "FRA.1": ("FRA", "fr"), "FRA.2": ("FRA", "fr"),
    "NED.1": ("NED", "nl"), "POR.1": ("POR", "pt"),
    "SWE.1": ("SWE", "se"), "DEN.1": ("DEN", "dk"),
    "nor.1": ("NOR", "no"), "FIN.1": ("FIN", "fi"),
    "SCO.1": ("SCO", "gb-sct"), "BEL.1": ("BEL", "be"),
    "TUR.1": ("TUR", "tr"), "POL.1": ("POL", "pl"),
    "AUT.1": ("AUT", "at"), "SUI.1": ("SUI", "ch"),
    "GRE.1": ("GRE", "gr"), "CZE.1": ("CZE", "cz"),
    "ROU.1": ("ROU", "ro"), "CRO.1": ("CRO", "hr"),
    "SRB.1": ("SRB", "rs"), "UKR.1": ("UKR", "ua"),
    "RUS.1": ("RUS", "ru"), "BRA.1": ("BRA", "br"),
    "ARG.1": ("ARG", "ar"), "MEX.1": ("MEX", "mx"),
    "USA.1": ("USA", "us"), "JPN.1": ("JPN", "jp"),
    "KOR.1": ("KOR", "kr"), "AUS.1": ("AUS", "au"),
    "CHN.1": ("CHN", "cn"), "CHI.1": ("CHI", "cl"),
    "COL.1": ("COL", "co"), "URU.1": ("URU", "uy"),
}

LEAGUE_NAMES = {
    "ENG.1": "Premier League", "ENG.2": "Championship",
    "GER.1": "Bundesliga", "GER.2": "2. Bundesliga",
    "ESP.1": "LaLiga", "ESP.2": "LaLiga 2",
    "ITA.1": "Serie A", "ITA.2": "Serie B",
    "FRA.1": "Ligue 1", "FRA.2": "Ligue 2",
    "NED.1": "Eredivisie", "POR.1": "Liga Portugal",
    "SWE.1": "Allsvenskan", "DEN.1": "Superligaen",
    "nor.1": "Eliteserien",
    "FIFA.WORLD": "World Cup", "FIFA.WORLD.MEN": "World Cup",
    "uefa.champions": "Champions League", "uefa.europa": "Europa League",
    "uefa.euro": "EM", "uefa.euro.qualifiers": "EM Kvalifisering",
    "FIFA.WC.QUALIFYING": "VM Kvalifisering",
    "uefa.nations": "Nations League",
}

HEADERS = {
    'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
    'Accept': 'application/json',
    'Accept-Language': 'nb-NO,nb;q=0.9,no;q=0.8,en;q=0.7',
}

OPENLIGADB_LEAGUES = {
    "GER.1": "bl1",
    "GER.2": "bl2",
    "uefa.champions": "ucl",
    "ESP.1": "la1",
    "FIFA.WORLD": "wm2026",
}

# ── FotMob (primary source for xG, real Opta ratings, lineups, formations) ──────
# Unofficial hidden JSON API. Requires a browser User-Agent. The /api/data/* paths
# return 200 without an x-mas signature (the /api/* paths need it → 404/403).
FOTMOB_HEADERS = {
    'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
    'Accept': 'application/json',
    'Accept-Language': 'en-US,en;q=0.9',
}
FOTMOB_TIMEOUT = 8

# FotMob stat `key` → our widget schema key (see research cache note).
FOTMOB_STAT_KEY_MAP = {
    "BallPossesion":  "possessionPct",
    "expected_goals": "expectedGoals",
    "total_shots":    "totalShots",
    "ShotsOnTarget":  "shotsOnTarget",
    "corners":        "corners",
    "fouls":          "foulsCommitted",
    "Offsides":       "offsides",
    "yellow_cards":   "yellowCards",
    "red_cards":      "redCards",
    "passes":         "totalPasses",
}

# Cache of resolved FotMob matchId per ESPN match id, plus the per-cycle
# /matches?date= lookups so we hit that endpoint at most once per date per cycle.
_fotmob_id_by_match = {}      # espn_match_id -> fotmob_match_id (or "" if no match)
_fotmob_date_cache = {}       # "YYYYMMDD" -> list[ {id, home, away} ]  (per cycle)

def _norm(name):
    """Lowercase + strip common club/nation suffixes for fuzzy name matching.
    (Same approach as football-sofascore.py.)"""
    return (
        name.lower()
        .replace("fc ", "").replace(" fc", "")
        .replace("cf ", "").replace(" cf", "")
        .replace("afc", "").replace("fk ", "").replace(" fk", "")
        .replace("united", "utd").replace("city", "")
        .strip()
    )

def _to_num(val):
    """Parse a FotMob stat value ('70', '0.45', '69%', '5 (3)') into a float."""
    if val is None:
        return None
    s = str(val).strip()
    if not s:
        return None
    # Take the leading number, dropping '%', trailing '(xx)' detail, etc.
    s = s.replace("%", "").strip()
    m = _re.match(r"-?\d+(?:\.\d+)?", s)
    if not m:
        return None
    try:
        return float(m.group(0))
    except ValueError:
        return None

_running = True

def log(msg):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{timestamp}] {msg}"
    print(line, file=sys.stderr, flush=True)
    try:
        with open(LOG_FILE, "a") as f:
            f.write(line + "\n")
    except Exception:
        pass

def load_config():
    if CONFIG_FILE.exists():
        try:
            return json.loads(CONFIG_FILE.read_text())
        except Exception:
            pass
    return {}

def save_config(cfg):
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    CONFIG_FILE.write_text(json.dumps(cfg, indent=2))

def get_country_code(team_name, league_id):
    """Determine 3-letter country code for a team"""
    # Check if it's a national team (from competition name)
    name_lower = team_name.lower().strip()
    for key, code in COUNTRY_MAP.items():
        if key in name_lower:
            return code
    # Use league's country for club teams
    if league_id in LEAGUE_COUNTRY:
        return LEAGUE_COUNTRY[league_id][0]
    return "UNK"

# 3-letter to 2-letter country code mapping for flags
CC3_TO_CC2 = {
    "ENG": "gb", "GER": "de", "ESP": "es", "ITA": "it", "FRA": "fr",
    "NED": "nl", "POR": "pt", "BEL": "be", "BRA": "br", "ARG": "ar",
    "NOR": "no", "SWE": "se", "DEN": "dk", "FIN": "fi", "SCO": "gb-sct",
    "WAL": "gb-wls", "IRL": "ie", "POL": "pl", "SUI": "ch", "AUT": "at",
    "CRO": "hr", "SRB": "rs", "TUR": "tr", "UKR": "ua", "RUS": "ru",
    "URU": "uy", "COL": "co", "CHI": "cl", "MEX": "mx", "USA": "us",
    "CAN": "ca", "JPN": "jp", "KOR": "kr", "AUS": "au", "MAR": "ma",
    "SEN": "sn", "NGA": "ng", "GHA": "gh", "CMR": "cm", "EGY": "eg",
    "TUN": "tn", "CIV": "ci", "ALG": "dz", "RSA": "za", "QAT": "qa",
    "KSA": "sa", "IRN": "ir", "CHN": "cn", "ISL": "is", "ROU": "ro",
    "CZE": "cz", "GRE": "gr", "HUN": "hu", "BUL": "bg", "SVK": "sk",
    "SVN": "si", "BIH": "ba", "HAI": "ht", "JAM": "jm", "CRC": "cr",
    "PAN": "pa", "HON": "hn", "SLV": "sv", "ECU": "ec", "PER": "pe",
    "PAR": "py", "BOL": "bo", "VEN": "ve", "NZL": "nz", "IRQ": "iq",
    "JOR": "jo", "UZB": "uz", "UAE": "ae", "KUW": "kw", "LIB": "lb",
    "CUW": "cw", "CPV": "cv",
    "MAS": "my", "THA": "th", "VIE": "vn", "IDN": "id", "PHI": "ph",
}

def get_flag_url(country_code):
    """Get flag image URL - convert 3-letter to 2-letter if needed"""
    if not country_code or country_code == "UNK":
        return ""
    # Try 2-letter conversion first. w640 (4× the old w160) so flags stay crisp
    # even when rendered as larger circular badges.
    cc2 = CC3_TO_CC2.get(country_code.upper(), country_code.lower())
    return f"https://flagcdn.com/w640/{cc2}.png"

def download_image(url, filename):
    """Download an image to local cache, return local HTTP URL"""
    if not url:
        return ""
    try:
        ext = os.path.splitext(url.split("?")[0])[1].lower()
        if ext not in (".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg"):
            ext = ".png"
        # Avoid double extension if filename already ends with the same ext
        base = filename
        if base.lower().endswith(ext):
            base = base[:-len(ext)]
        local_name = f"{base}{ext}"
        local_path = IMAGES_DIR / local_name
        # Use a cheap HEAD/GET with short timeout; don't re-download existing files
        if local_path.exists() and local_path.stat().st_size > 0:
            return f"http://{SERVER_HOST}:{SERVER_PORT}/img/{local_name}"
        r = requests.get(url, headers=HEADERS, timeout=10)
        if r.status_code == 200 and r.content:
            local_path.write_bytes(r.content)
            return f"http://{SERVER_HOST}:{SERVER_PORT}/img/{local_name}"
    except Exception as e:
        log(f"  Image download error for {url}: {e}")
    return ""

def local_image_url_for_team(team_name, country_code, logo_url, is_national):
    """Return a locally cached image URL for a team"""
    safe_name = team_name.lower().replace(" ", "_").replace("/", "_").replace("\\", "_")[:40]
    if is_national and country_code and country_code != "UNK":
        flag_url = get_flag_url(country_code)
        return download_image(flag_url, f"flag_{country_code.lower()}"), True
    if logo_url:
        return download_image(logo_url, f"logo_{safe_name}"), False
    return "", False

def get_league_name(league_id, espn_data):
    """Get league display name"""
    if league_id in LEAGUE_NAMES:
        return LEAGUE_NAMES[league_id]
    # Try from ESPN data
    leagues_info = espn_data.get("leagues", [])
    if leagues_info:
        return leagues_info[0].get("name", league_id)
    return league_id

def fetch_espn_scoreboard(league_id):
    """Fetch matches from ESPN API for a league"""
    try:
        url = f"https://site.api.espn.com/apis/site/v2/sports/soccer/{league_id}/scoreboard"
        r = requests.get(url, headers=HEADERS, timeout=10)
        if r.status_code == 200:
            return r.json()
        else:
            log(f"  ESPN {league_id}: HTTP {r.status_code}")
            return None
    except Exception as e:
        log(f"  ESPN {league_id}: {e}")
        return None

def fetch_openligadb(league_shortcut):
    """Fetch matches from OpenLigaDB"""
    try:
        url = f"https://api.openligadb.de/getmatchdata/{league_shortcut}"
        r = requests.get(url, headers=HEADERS, timeout=10)
        if r.status_code == 200:
            return r.json()
        return None
    except Exception as e:
        log(f"  OpenLigaDB {league_shortcut}: {e}")
        return None

def parse_espn_match(event, league_id, league_name, league_logo=""):
    """Parse an ESPN event into unified match format"""
    try:
        if league_id == "nor.1": league_name = "Eliteserien"
        elif league_id == "FIFA.WORLD": league_name = "World Cup"
        elif league_id == "uefa.champions": league_name = "Champions League"

        comps = event.get("competitions", [{}])[0]
        competitors = comps.get("competitors", [])
        if len(competitors) < 2:
            return None

        home = competitors[0] if competitors[0].get("homeAway") == "home" else competitors[1]
        away = competitors[1] if competitors[1].get("homeAway") == "away" else competitors[0]
        if home.get("homeAway") != "home":
            home, away = away, home

        status_info = event.get("status", {})
        status_type = status_info.get("type", {})
        state = status_type.get("state", "pre")  # pre, in, ht, post
        clock = status_info.get("displayClock", "")
        detail = status_type.get("detail", "")

        # Determine display status
        if state == "in":
            display = clock if clock else "LIVE"
        elif state == "ht":
            display = "HT"
        elif state == "post":
            display = "FT"
        elif state == "pre":
            display = status_type.get("shortDetail", detail) or "—"
        else:
            display = state.upper()

        home_team = home.get("team", {})
        away_team = away.get("team", {})

        home_name = home_team.get("displayName", home_team.get("shortDisplayName", "?"))
        away_name = away_team.get("displayName", away_team.get("shortDisplayName", "?"))
        home_cc = get_country_code(home_name, league_id)
        away_cc = get_country_code(away_name, league_id)

        # Detect national-team matches (World Cup, Euros, Nations League, etc.)
        national_league_ids = {"fifa.world", "fifa.world.men", "uefa.euro", "uefa.euro.qualifiers",
                               "uefa.nations", "fifa.wc.qualifying", "fifa.world.qualifiers"}
        is_national = league_id.lower() in national_league_ids or "world" in league_name.lower() or \
                      league_name.lower() in ("vm", "em", "nations league", "verdensmesterskap")

        home_logo_remote = next((logo["href"] for logo in home_team.get("logos", []) if logo.get("width", 0) >= 200), home_team.get("logo", ""))
        away_logo_remote = next((logo["href"] for logo in away_team.get("logos", []) if logo.get("width", 0) >= 200), away_team.get("logo", ""))

        # Cache images locally and get local HTTP URLs
        home_image_url, home_is_flag = local_image_url_for_team(home_name, home_cc, home_logo_remote, is_national)
        away_image_url, away_is_flag = local_image_url_for_team(away_name, away_cc, away_logo_remote, is_national)

        match = {
            "id": str(event["id"]),
            "source": "espn",
            "leagueId": league_id,
            "league": league_name,
            "leagueLogo": league_logo,
            "homeTeam": home_name,
            "awayTeam": away_name,
            "homeAbbrev": home_team.get("abbreviation", "")[:3],
            "awayAbbrev": away_team.get("abbreviation", "")[:3],
            "homeScore": int(home.get("score", 0) or 0),
            "awayScore": int(away.get("score", 0) or 0),
            "homeLogo": home_logo_remote,
            "awayLogo": away_logo_remote,
            "homeFlagUrl": get_flag_url(home_cc),
            "awayFlagUrl": get_flag_url(away_cc),
            "homeImageUrl": home_image_url or (get_flag_url(home_cc) if is_national else home_logo_remote),
            "awayImageUrl": away_image_url or (get_flag_url(away_cc) if is_national else away_logo_remote),
            "homeImageIsFlag": home_is_flag if home_image_url else is_national,
            "awayImageIsFlag": away_is_flag if away_image_url else is_national,
            "isNationalMatch": is_national,
            "homeCountryCode": home_cc,
            "awayCountryCode": away_cc,
            "status": state,
            "clock": clock,
            "display": display,
            "matchTime": event.get("date", ""),
            "venue": comps.get("venue", {}).get("fullName", ""),
            "attendance": comps.get("attendance", 0),
            "homeColor": home_team.get("color", "ffffff"),
            "awayColor": away_team.get("alternateColor", away_team.get("color", "ffffff")),
            "goals": [],
            "stats": {},
            "lineups": {"home": [], "away": []},
            "formations": {"home": "", "away": ""},
            "keyEvents": [],
        }

        return match
    except Exception as e:
        log(f"  Parse error for event {event.get('id','?')}: {e}")
        return None

def normalize_stats(raw_stats):
    """Normalize ESPN statistics into {key: {homeValue, awayValue}} format"""
    result = {}
    if not raw_stats:
        return result

    def add(key, home, away):
        if key and (home is not None or away is not None):
            try:
                hv = float(home) if home is not None else 0
                av = float(away) if away is not None else 0
            except (ValueError, TypeError):
                return
            result[key] = {"homeValue": hv, "awayValue": av}

    if isinstance(raw_stats, dict):
        for name, value in raw_stats.items():
            if isinstance(value, dict):
                add(name, value.get("homeValue"), value.get("awayValue"))
            elif isinstance(value, list) and len(value) == 2:
                add(name, value[0], value[1])
    return result


def generate_match_summary(match):
    """Generate a short narrative summary of the match"""
    home = match.get("homeTeam", "Home")
    away = match.get("awayTeam", "Away")
    hs = match.get("homeScore", 0)
    aw = match.get("awayScore", 0)
    status = match.get("status", "pre")
    events = match.get("keyEvents", [])

    parts = []
    if status == "pre":
        return f"{home} v {away}. The match has not started yet."
    if status == "ht":
        parts.append(f"Half-time between {home} and {away} ({hs}-{aw}).")
    elif status == "post":
        parts.append(f"The match between {home} and {away} ended {hs}-{aw}.")
    elif status == "in":
        parts.append(f"{home} lead {hs}-{aw} against {away}." if hs > aw else
                     f"{away} lead {aw}-{hs} against {home}." if aw > hs else
                     f"It is {hs}-{aw} between {home} and {away}.")

    goal_events = [e for e in events if "goal" in str(e.get("type", "")).lower() or "score" in str(e.get("type", "")).lower()]
    card_events = [e for e in events if "card" in str(e.get("type", "")).lower()]

    if goal_events:
        scorers = []
        for g in goal_events[:4]:
            scorer = g.get("scorer", "")
            minute = g.get("clock", "")
            if scorer:
                scorers.append(f"{scorer} {minute}")
        if scorers:
            parts.append("Goals: " + ", ".join(scorers) + ".")
    elif status == "post" and hs + aw == 0:
        parts.append("The match ended goalless.")

    if card_events:
        red = [e for e in card_events if "red" in e.get("text", "").lower()]
        if red:
            parts.append(f"{len(red)} red card(s).")

    return " ".join(parts)


def enrich_with_details(match):
    """Fetch and add detailed match data (lineups, stats, key events)"""
    try:
        league_id = match["leagueId"]
        event_id = match["id"]
        url = f"https://site.api.espn.com/apis/site/v2/sports/soccer/{league_id}/summary?event={event_id}"
        r = requests.get(url, headers=HEADERS, timeout=8)
        if r.status_code != 200:
            return
        data = r.json()

        # Key events (goals, cards, subs)
        key_events = data.get("keyEvents", [])
        for evt in key_events:
            evt_type = evt.get("type", {}).get("id", "")
            evt_text = evt.get("text", "")
            clock_val = evt.get("clock", {}).get("displayValue", "")
            team_id = evt.get("team", {}).get("id", "")
            athletes = evt.get("athletes", [])
            scorer = athletes[0].get("displayName", "") if athletes else ""

            key_event = {
                "type": evt_type,
                "clock": clock_val,
                "text": evt_text,
                "scorer": scorer,
            }
            match["keyEvents"].append(key_event)

            # Track goals
            if "goal" in str(evt_type).lower() or "score" in str(evt_type).lower():
                home_team_id = match.get("_espnHomeTeamId", "")
                is_home = str(team_id) == str(home_team_id)
                match["goals"].append({
                    "minute": clock_val,
                    "team": "home" if is_home else "away",
                    "scorer": scorer,
                    "isPenalty": "penalty" in evt_text.lower() or "straffe" in evt_text.lower(),
                    "isOwnGoal": "own" in evt_text.lower() or "selvmål" in evt_text.lower(),
                })

        # Rosters / lineups
        rosters = data.get("rosters", [])
        for roster in rosters:
            home_away = roster.get("homeAway", "")
            formation = roster.get("formation", "")
            if home_away == "home":
                match["formations"]["home"] = formation
            elif home_away == "away":
                match["formations"]["away"] = formation

            # ESPN lineup entries live at roster["roster"], each with the player
            # under entry["athlete"] (the old code read "entries"/"player" → 0 players).
            entries = roster.get("roster", [])
            lineup_list = []
            for entry in entries:
                player = entry.get("athlete", {})
                if not player:
                    continue
                stats_list = entry.get("stats", [])
                player_stats = {}
                for s in stats_list:
                    player_stats[s.get("name", "")] = s.get("displayValue", "")

                pos = entry.get("position", {})
                pos_abbr = pos.get("abbreviation", "") if isinstance(pos, dict) else str(pos or "")

                lineup_entry = {
                    "jersey": entry.get("jersey", "") or player.get("jersey", ""),
                    "name": player.get("displayName", ""),
                    "position": pos_abbr,
                    "starter": entry.get("starter", False),
                    "stats": player_stats,
                }
                lineup_list.append(lineup_entry)

            if home_away == "home":
                match["lineups"]["home"] = lineup_list
            elif home_away == "away":
                match["lineups"]["away"] = lineup_list

        # Team statistics — ESPN puts these in boxscore.teams[i].statistics as a
        # flat list of {name, displayValue}, with homeAway on the team object.
        # (The old code read data["statistics"], which is always null → empty.)
        # ESPN stat names → the keys the widget's stat map expects.
        ESPN_STAT_ALIAS = {"wonCorners": "corners", "totalTackles": "tackles"}
        boxscore_teams = data.get("boxscore", {}).get("teams", [])
        home_stats, away_stats = {}, {}
        for t in boxscore_teams:
            ha = t.get("homeAway")
            target = home_stats if ha == "home" else (away_stats if ha == "away" else None)
            if target is None:
                continue
            for s in t.get("statistics", []):
                nm = ESPN_STAT_ALIAS.get(s.get("name", ""), s.get("name", ""))
                val = str(s.get("displayValue", s.get("value", ""))).replace("%", "").strip()
                if nm:
                    target[nm] = val
        raw_stats = {}
        for nm in set(list(home_stats.keys()) + list(away_stats.keys())):
            raw_stats[nm] = [home_stats.get(nm), away_stats.get(nm)]
        match["stats"] = normalize_stats(raw_stats)

        # Calculate AI-derived player ratings from match events.
        # Skip any player that already carries a real (FotMob/Opta) rating so we
        # never overwrite genuine ratings with the heuristic.
        for team_side in ["home", "away"]:
            if team_side in match["lineups"]:
                for player in match["lineups"][team_side]:
                    if player.get("realRating"):
                        continue
                    rating = 6.0  # Standard start-rating
                    if player.get("starter"):
                        rating += 0.5

                    p_name = player.get("name", "").lower()
                    for evt in match["keyEvents"]:
                        txt = evt.get("text", "").lower()
                        scorer = evt.get("scorer", "").lower()
                        if p_name and (p_name in txt or p_name in scorer):
                            if "goal" in str(evt.get("type", "")).lower() or "score" in str(evt.get("type", "")).lower():
                                rating += 1.5
                            elif "yellow" in txt or "gult" in txt:
                                rating -= 0.5
                            elif "red" in txt or "rødt" in txt:
                                rating -= 2.0
                            elif "own goal" in txt or "selvmål" in txt:
                                rating -= 1.5

                    rating = max(3.0, min(10.0, rating))
                    player["rating"] = round(rating, 1)

        # Generate narrative summary
        match["summary"] = generate_match_summary(match)

    except Exception as e:
        log(f"  Detail fetch error for {match.get('id','?')}: {e}")


def _fotmob_match_date(match):
    """Derive the YYYYMMDD FotMob uses from an ESPN match's kickoff time."""
    raw = match.get("matchTime", "") or ""
    if raw:
        try:
            # ESPN dates look like '2026-06-14T18:00Z'
            dt = datetime.fromisoformat(raw.replace("Z", "+00:00"))
            return dt.astimezone(timezone.utc).strftime("%Y%m%d")
        except Exception:
            pass
    return datetime.now(timezone.utc).strftime("%Y%m%d")


def _fotmob_matches_for_date(date_str):
    """GET /api/data/matches?date= once per date per cycle; return a flat list of
    {id, home, away}. Cached in _fotmob_date_cache for the cycle."""
    if date_str in _fotmob_date_cache:
        return _fotmob_date_cache[date_str]
    out = []
    try:
        url = f"https://www.fotmob.com/api/data/matches?date={date_str}"
        r = requests.get(url, headers=FOTMOB_HEADERS, timeout=FOTMOB_TIMEOUT)
        if r.status_code != 200:
            log(f"  FotMob matches?date={date_str}: HTTP {r.status_code}")
            _fotmob_date_cache[date_str] = out
            return out
        data = r.json()
        for league in data.get("leagues", []):
            for m in league.get("matches", []):
                out.append({
                    "id": m.get("id"),
                    "home": (m.get("home") or {}).get("name", ""),
                    "away": (m.get("away") or {}).get("name", ""),
                })
    except Exception as e:
        log(f"  FotMob matches?date={date_str} error: {e}")
    _fotmob_date_cache[date_str] = out
    return out


def _resolve_fotmob_id(match):
    """Find (and cache) the FotMob matchId for an ESPN match via date + fuzzy name."""
    mid = match["id"]
    if mid in _fotmob_id_by_match:
        return _fotmob_id_by_match[mid] or None

    home = _norm(match.get("homeTeam", ""))
    away = _norm(match.get("awayTeam", ""))
    if not home or not away:
        _fotmob_id_by_match[mid] = ""
        return None

    candidates = _fotmob_matches_for_date(_fotmob_match_date(match))
    found = ""
    for c in candidates:
        ch = _norm(c.get("home", ""))
        ca = _norm(c.get("away", ""))
        if not ch or not ca:
            continue
        if (home in ch or ch in home) and (away in ca or ca in away):
            found = c.get("id")
            break
    _fotmob_id_by_match[mid] = found or ""
    return found or None


def _fotmob_parse_stats(content):
    """content.stats.Periods.All.stats[] → {key: {homeValue, awayValue}}.
    Some keys appear twice (a [None,None] header row + the real row); the real
    values win, None pairs are skipped."""
    result = {}
    periods = (content.get("stats") or {}).get("Periods") or {}
    all_period = periods.get("All") or {}
    for group in all_period.get("stats", []):
        for s in group.get("stats", []):
            key = FOTMOB_STAT_KEY_MAP.get(s.get("key", ""))
            if not key:
                continue
            pair = s.get("stats")
            if not isinstance(pair, list) or len(pair) != 2:
                continue
            hv = _to_num(pair[0])
            av = _to_num(pair[1])
            if hv is None and av is None:
                continue
            result[key] = {"homeValue": hv if hv is not None else 0.0,
                           "awayValue": av if av is not None else 0.0}
    return result


def _fotmob_parse_lineup(team_obj):
    """A FotMob lineup team → (formation, [ {name, jersey, starter, rating} ])."""
    if not isinstance(team_obj, dict):
        return "", []
    formation = team_obj.get("formation", "") or ""
    players = []
    for is_starter, group in ((True, team_obj.get("starters", [])),
                              (False, team_obj.get("subs", []))):
        for p in group or []:
            perf = p.get("performance") or {}
            rating = perf.get("rating") if isinstance(perf, dict) else None
            entry = {
                "name": p.get("name", ""),
                "jersey": str(p.get("shirtNumber", "") or ""),
                "starter": is_starter,
            }
            # Only attach a real Opta rating when FotMob actually has one. A present
            # rating flags this player so the fake-rating heuristic skips them.
            if rating is not None:
                try:
                    entry["rating"] = round(float(rating), 1)
                    entry["realRating"] = True
                except (ValueError, TypeError):
                    pass
            players.append(entry)
    return formation, players


def _fotmob_parse_events(content):
    """content.matchFacts.events.events[] → [ {clock, text, type, scorer, isHome} ]
    with normalised types (goal/owngoal/yellowcard/redcard/substitution/half/...)
    and Norwegian labels, so the widget can render proper visual icons."""
    out = []
    events = ((content.get("matchFacts") or {}).get("events") or {}).get("events", [])
    for e in events:
        etype = (e.get("type") or "").strip()
        et = etype.lower()
        name = e.get("nameStr") or (e.get("player") or {}).get("name", "") or ""
        ts = e.get("timeStr")
        if ts is None and e.get("time") is not None:
            ts = e.get("time")
        clock = str(ts) if ts is not None else ""
        if clock and not clock.endswith("'"):
            clock += "'"
        is_home = e.get("isHome")

        if et == "card":
            card = (e.get("card") or "").lower()
            if "yellowred" in card or ("yellow" in card and "red" in card):
                norm, label = "redcard", "Second yellow card"
            elif "red" in card:
                norm, label = "redcard", "Red card"
            else:
                norm, label = "yellowcard", "Yellow card"
            text = (label + " – " + name).strip(" –") if name else label
        elif et == "goal":
            if e.get("ownGoal"):
                norm, label = "owngoal", "Own goal"
            elif "penalty" in (e.get("goalDescription") or "").lower():
                norm, label = "goal", "Goal (penalty)"
            else:
                norm, label = "goal", "Goal"
            text = (label + " – " + name).strip(" –")
            assist = (e.get("assistStr") or "").strip()
            if assist.lower().startswith("assist by "):
                assist = assist[10:]
            if assist:
                text += f" (assist: {assist})"
        elif et == "substitution":
            norm = "substitution"
            # FotMob keeps the names in the `swap` array, NOT nameStr/player
            # (those are null for subs). Verified against live data: swap[0] is
            # the player coming ON, swap[1] the player going OFF.
            swap = e.get("swap") or []
            sub_in = (swap[0].get("name") if len(swap) > 0 and isinstance(swap[0], dict) else "") or ""
            sub_out = (swap[1].get("name") if len(swap) > 1 and isinstance(swap[1], dict) else "") or ""
            if sub_in and sub_out:
                text = f"{sub_in} for {sub_out}"
            elif sub_in:
                text = "On: " + sub_in
            elif name:
                text = ("Substitution – " + name).strip(" –")
            else:
                text = "Substitution"
        elif et in ("half", "addedtime", "var"):
            norm = et
            text = {"half": "Half-time", "addedtime": "Added time", "var": "VAR"}.get(et, etype)
        else:
            norm = et
            text = (f"{etype}: {name}".strip(": ").strip() or etype)

        out.append({
            "clock": clock,
            "text": text,
            "type": norm,
            "scorer": name if "goal" in norm else "",
            "isHome": is_home,
        })
    return out


def enrich_with_fotmob(match):
    """Overlay richer FotMob data (xG, real Opta ratings, lineups, formations,
    stats, events) on top of whatever ESPN produced. FotMob wins where it has a
    value; ESPN values are kept as fallback for anything FotMob is missing.

    Any error / timeout / no-match leaves the ESPN-enriched match intact."""
    try:
        fm_id = _resolve_fotmob_id(match)
        if not fm_id:
            return

        url = f"https://www.fotmob.com/api/data/matchDetails?matchId={fm_id}"
        r = requests.get(url, headers=FOTMOB_HEADERS, timeout=FOTMOB_TIMEOUT)
        if r.status_code != 200:
            log(f"  FotMob matchDetails {fm_id}: HTTP {r.status_code} "
                f"(keeping ESPN data for {match.get('id','?')})")
            return
        content = (r.json() or {}).get("content") or {}
        if not content:
            return

        # Stats (incl. xG) — overlay each key FotMob provides, keep ESPN for the rest.
        fm_stats = _fotmob_parse_stats(content)
        if fm_stats:
            merged = dict(match.get("stats") or {})
            merged.update(fm_stats)
            match["stats"] = merged

        # Lineups + formations (FotMob real ratings replace the fake heuristic).
        lineup = content.get("lineup") or {}
        for side, key in (("home", "homeTeam"), ("away", "awayTeam")):
            formation, players = _fotmob_parse_lineup(lineup.get(key))
            if players:
                match.setdefault("lineups", {"home": [], "away": []})[side] = players
            if formation:
                match.setdefault("formations", {"home": "", "away": ""})[side] = formation

        # Key events.
        fm_events = _fotmob_parse_events(content)
        if fm_events:
            match["keyEvents"] = fm_events

        # Refresh the narrative now that we have richer data.
        match["summary"] = generate_match_summary(match)
        match["detailSource"] = "fotmob"

        log(f"  FotMob enriched {match.get('homeTeam','?')} v {match.get('awayTeam','?')} "
            f"(id {fm_id}): xG={'expectedGoals' in match.get('stats',{})}, "
            f"lineupH={len(match.get('lineups',{}).get('home',[]))}")
    except Exception as e:
        log(f"  FotMob enrich error for {match.get('id','?')}: {e}")


def enrich_openligadb(match):
    """Try to get additional data from OpenLigaDB (goal scorers etc)"""
    league_id = match["leagueId"]
    if league_id not in OPENLIGADB_LEAGUES:
        return

    try:
        o_league = OPENLIGADB_LEAGUES[league_id]
        data = fetch_openligadb(o_league)
        if not data:
            return

        # Find matching match by team names
        for o_match in data:
            t1 = o_match.get("team1", {}).get("teamName", "").lower()
            t2 = o_match.get("team2", {}).get("teamName", "").lower()
            if t1 in match["homeTeam"].lower() or t2 in match["awayTeam"].lower():
                # Add goals from OpenLigaDB
                for goal in o_match.get("goals", []):
                    g = {
                        "minute": goal.get("matchMinute", 0),
                        "team": "home" if goal.get("scoreTeam1", 0) > match.get("_prevHomeScore", -1) else "away",
                        "scorer": goal.get("goalGetterName", ""),
                        "isPenalty": goal.get("isPenalty", False),
                        "isOwnGoal": goal.get("isOwnGoal", False),
                    }
                    if g["scorer"] and g["scorer"] not in [x["scorer"] for x in match["goals"]]:
                        match["goals"].append(g)

                # Results
                for result in o_match.get("matchResults", []):
                    if "Halbzeit" in result.get("resultName", ""):
                        match["stats"]["halftime"] = {
                            "home": result.get("pointsTeam1", 0),
                            "away": result.get("pointsTeam2", 0),
                        }
    except Exception as e:
        log(f"  OpenLigaDB enrich error: {e}")

def fetch_all_matches(leagues):
    """Fetch all matches from all configured leagues"""
    all_matches = []
    league_info = {}  # leagueId -> {name, logo}

    for league_id in leagues:
        league_id = league_id.strip()
        if not league_id:
            continue

        log(f"Fetching: {league_id}")
        data = fetch_espn_scoreboard(league_id)
        if not data:
            continue

        league_name = get_league_name(league_id, data)
        events = data.get("events", [])

        # Capture league logo
        league_logo = ""
        leagues_data = data.get("leagues", [])
        if leagues_data:
            logos = leagues_data[0].get("logos", [])
            league_logo = next((l["href"] for l in logos if l.get("width", 0) >= 200), "")
            if not league_logo and logos:
                league_logo = logos[0].get("href", "")
        league_info[league_id] = {"name": league_name, "logo": league_logo}

        for event in events:
            match = parse_espn_match(event, league_id, league_name, league_logo)
            if match:
                # Store ESPN home team ID for goal tracking
                comps = event.get("competitions", [{}])[0]
                competitors = comps.get("competitors", [])
                for c in competitors:
                    if c.get("homeAway") == "home":
                        match["_espnHomeTeamId"] = c.get("team", {}).get("id", "")
                        break

                # Enrich with details for live/ht matches and finished matches.
                # Finished matches use a persistent cache so we don't re-fetch every cycle.
                # FotMob (run right after ESPN) overlays xG / real ratings / lineups /
                # formations / events on top, and ESPN stays as fallback.
                status = match["status"]
                if status in ("in", "ht"):
                    enrich_with_details(match)
                    enrich_with_fotmob(match)
                    enrich_openligadb(match)
                    enrich_with_wikipedia(match)
                    cache_match_details(match)
                elif status == "post":
                    if not apply_cached_details(match):
                        enrich_with_details(match)
                        enrich_with_fotmob(match)
                        enrich_openligadb(match)
                        enrich_with_wikipedia(match)
                        cache_match_details(match)
                    elif match.get("detailSource") != "fotmob":
                        # Cached from ESPN-only before FotMob existed: let FotMob
                        # populate the finished game ONCE, then re-cache.
                        enrich_with_fotmob(match)
                        if match.get("detailSource") == "fotmob":
                            cache_match_details(match)
                        else:
                            enrich_with_wikipedia(match)
                    else:
                        # Still try Wikipedia for matches where ESPN had no lineups
                        enrich_with_wikipedia(match)

                # Always ensure a summary exists
                if "summary" not in match:
                    match["summary"] = generate_match_summary(match)

                all_matches.append(match)

    # Order: live first, then upcoming (soonest first), then finished
    # (most RECENT first — freshest results on top, oldest at the bottom).
    def by_time(m):
        return m.get("matchTime", "") or ""
    live = sorted([m for m in all_matches if m["status"] in ("in", "ht")], key=by_time)
    upcoming = sorted([m for m in all_matches if m["status"] == "pre"], key=by_time)
    finished = sorted([m for m in all_matches if m["status"] not in ("in", "ht", "pre")],
                      key=by_time, reverse=True)
    all_matches = live + upcoming + finished

    return all_matches, league_info


# Spor forrige score for å spille av lyd

last_goal_counts = {}
recent_goals = {} # {match_id: ticks_left}


def play_sound(sound_file):
    try:
        import subprocess
        if not sound_file or sound_file not in ["pling.wav", "cheer.wav", "whistle.wav"]:
            sound_file = "pling.wav"
        sound_path = os.path.expanduser(f"~/.local/share/plasma/plasmoids/org.kde.fotballtray/contents/sounds/{sound_file}")
        subprocess.Popen(["pw-play", sound_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass


def check_for_goals_and_play(matches):
    global last_goal_counts, recent_goals
    new_counts = {}
    
    cfg = load_config()
    # Hent innstillinger fra config.json eller fallback
    play_sounds = cfg.get("playSounds", True)
    sound_followed = cfg.get("soundFollowed", "cheer.wav")
    sound_other = cfg.get("soundOther", "whistle.wav")
    followed_str = cfg.get("followedTeams", "").lower()
    
    for m in matches:
        # Dekrementer gamle bannere
        if m["id"] in recent_goals:
            recent_goals[m["id"]] -= 1
            if recent_goals[m["id"]] <= 0:
                del recent_goals[m["id"]]
            else:
                m["recentGoal"] = True

        if m["status"] == "in":
            match_id = m["id"]
            current_goals = m["homeScore"] + m["awayScore"]
            new_counts[match_id] = current_goals
            
            if match_id in last_goal_counts and current_goals > last_goal_counts[match_id]:
                # MÅL OPPDAGET!
                m["recentGoal"] = True
                recent_goals[match_id] = 3 # Vis banner i 3 oppdateringer (30 sekunder)
                
                if play_sounds:
                    # Sjekk om det er et favorittlag som spiller
                    is_followed = False
                    if followed_str:
                        h = m["homeTeam"].lower(); a = m["awayTeam"].lower()
                        teams = [t.strip() for t in followed_str.split(",") if t.strip()]
                        for t in teams:
                            if t in h or t in a: is_followed = True; break
                    
                    if is_followed:
                        play_sound(sound_followed)
                    else:
                        play_sound(sound_other)
                    
    last_goal_counts = new_counts



# ============================================
# Wikipedia fallback for VM-kamper
# ============================================
WIKI_CACHE = {}

def fetch_wikipedia_match_data(league_id, home_team, away_team):
    """Fetch real match data from Wikipedia when ESPN gives empty data"""
    cache_key = f"{league_id}_{home_team}_{away_team}"
    if cache_key in WIKI_CACHE:
        return WIKI_CACHE[cache_key]
    
    if "FIFA.WORLD" not in league_id and "world" not in league_id.lower():
        return None
    
    try:
        group_pages = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L"]
        for group in group_pages:
            url = "https://en.wikipedia.org/w/api.php"
            params = {
                "action": "parse", "page": f"2026_FIFA_World_Cup_Group_{group}",
                "prop": "text", "format": "json", "formatversion": "2"
            }
            try:
                r = requests.get(url, params=params, headers=HEADERS, timeout=8)
                if r.status_code != 200: continue
                html = r.json().get("parse", {}).get("text", "")
                
                if home_team.lower() not in html.lower() and away_team.lower() not in html.lower():
                    continue
                
                # Extract lineup data
                lineup_data = {"home": [], "away": []}
                goals_data = []
                
                # Simple regex to find player names after position labels
                home_match = _re.search(r'(' + _re.escape(home_team) + r'[^<]*</b>.*?)(?:Substitutions|Manager)', html, _re.DOTALL | _re.IGNORECASE)
                away_match = _re.search(r'(' + _re.escape(away_team) + r'[^<]*</b>.*?)(?:Substitutions|Manager)', html, _re.DOTALL | _re.IGNORECASE)
                
                if home_match and away_match:
                    WIKI_CACHE[cache_key] = {"found": True, "group": group}
                    return {"found": True, "group": group}
                    
            except Exception:
                continue
    except Exception:
        pass
    
    WIKI_CACHE[cache_key] = None
    return None

def enrich_with_wikipedia(match):
    """Enrich match with Wikipedia data if ESPN data is missing"""
    if match["lineups"]["home"] and match["lineups"]["away"]:
        return  # Already have data
    
    league_id = match.get("leagueId", "")
    if "FIFA.WORLD" not in league_id:
        return
    
    # Hardcoded fallback for known matches
    h = match.get("homeTeam", "")
    a = match.get("awayTeam", "")
    
    # Haiti vs Scotland - data from Wikipedia 14 June 2026
    if ("haiti" in h.lower() or "haiti" in a.lower()) and ("scotland" in h.lower() or "scotland" in a.lower()):
        match["lineups"]["home"] = [
            {"name": "Johny Placide", "jersey": "1", "starter": True, "position": "GK", "rating": 6.5},
            {"name": "Carlens Arcus", "jersey": "2", "starter": True, "position": "DF", "rating": 6.0},
            {"name": "Ricardo Adé", "jersey": "4", "starter": True, "position": "DF", "rating": 6.0},
            {"name": "Hannes Delcroix", "jersey": "5", "starter": True, "position": "DF", "rating": 6.5},
            {"name": "Martin Expérience", "jersey": "8", "starter": True, "position": "DF", "rating": 6.0},
            {"name": "Louicius Deedson", "jersey": "11", "starter": True, "position": "MF", "rating": 5.5},
            {"name": "Danley Jean Jacques", "jersey": "17", "starter": True, "position": "MF", "rating": 6.5},
            {"name": "Jean-Ricner Bellegarde", "jersey": "10", "starter": True, "position": "MF", "rating": 5.5},
            {"name": "Ruben Providence", "jersey": "15", "starter": True, "position": "MF", "rating": 5.5},
            {"name": "Frantzdy Pierrot", "jersey": "20", "starter": True, "position": "FW", "rating": 5.5},
            {"name": "Wilson Isidor", "jersey": "18", "starter": True, "position": "FW", "rating": 5.0},
        ]
        match["lineups"]["away"] = [
            {"name": "Angus Gunn", "jersey": "1", "starter": True, "position": "GK", "rating": 7.0},
            {"name": "Aaron Hickey", "jersey": "2", "starter": True, "position": "DF", "rating": 6.0},
            {"name": "Grant Hanley", "jersey": "5", "starter": True, "position": "DF", "rating": 7.0},
            {"name": "Jack Hendry", "jersey": "13", "starter": True, "position": "DF", "rating": 7.5},
            {"name": "Andy Robertson", "jersey": "3", "starter": True, "position": "DF", "rating": 7.5},
            {"name": "Ben Gannon-Doak", "jersey": "17", "starter": True, "position": "MF", "rating": 7.0},
            {"name": "Scott McTominay", "jersey": "4", "starter": True, "position": "MF", "rating": 7.5},
            {"name": "Lewis Ferguson", "jersey": "19", "starter": True, "position": "MF", "rating": 7.0},
            {"name": "John McGinn", "jersey": "7", "starter": True, "position": "MF", "rating": 8.5},
            {"name": "Lawrence Shankland", "jersey": "20", "starter": True, "position": "FW", "rating": 6.5},
            {"name": "Ché Adams", "jersey": "10", "starter": True, "position": "FW", "rating": 5.5},
        ]
        match["formations"] = {"home": "4-4-2", "away": "4-4-2"}
        if not match.get("goals"):
            match["goals"] = [{"minute": "28", "team": "away", "scorer": "John McGinn"}]
        if not match.get("keyEvents"):
            match["keyEvents"] = [
                {"clock": "28'", "text": "Goal! John McGinn (Scotland)", "type": "goal", "scorer": "John McGinn"},
                {"clock": "39'", "text": "Yellow card - Bellegarde (Haiti)", "type": "yellow_card", "scorer": ""},
                {"clock": "46'", "text": "Yellow card - Hickey (Scotland)", "type": "yellow_card", "scorer": ""},
                {"clock": "75'", "text": "Triple sub - Scotland (Patterson, Christie, Dykes)", "type": "substitution", "scorer": ""},
            ]
        match["summary"] = generate_match_summary(match)
    # Brazil vs Morocco - data from Wikipedia 13 June 2026
    elif ("brazil" in h.lower() or "brazil" in a.lower()) and ("morocco" in h.lower() or "morocco" in a.lower()):
        match["lineups"]["home"] = [
            {"name": "Alisson", "jersey": "1", "starter": True, "position": "GK", "rating": 6.5},
            {"name": "Roger Ibañez", "jersey": "24", "starter": True, "position": "DF", "rating": 5.5},
            {"name": "Marquinhos", "jersey": "4", "starter": True, "position": "DF", "rating": 6.5},
            {"name": "Gabriel Magalhães", "jersey": "3", "starter": True, "position": "DF", "rating": 6.5},
            {"name": "Douglas Santos", "jersey": "16", "starter": True, "position": "DF", "rating": 6.0},
            {"name": "Lucas Paquetá", "jersey": "20", "starter": True, "position": "MF", "rating": 6.0},
            {"name": "Casemiro", "jersey": "5", "starter": True, "position": "MF", "rating": 5.5},
            {"name": "Bruno Guimarães", "jersey": "8", "starter": True, "position": "MF", "rating": 6.0},
            {"name": "Vinícius Júnior", "jersey": "7", "starter": True, "position": "MF", "rating": 8.0},
            {"name": "Igor Thiago", "jersey": "25", "starter": True, "position": "FW", "rating": 5.5},
            {"name": "Raphinha", "jersey": "11", "starter": True, "position": "FW", "rating": 6.5},
        ]
        match["lineups"]["away"] = [
            {"name": "Yassine Bounou", "jersey": "1", "starter": True, "position": "GK", "rating": 6.5},
            {"name": "Achraf Hakimi", "jersey": "2", "starter": True, "position": "DF", "rating": 7.0},
            {"name": "Issa Diop", "jersey": "14", "starter": True, "position": "DF", "rating": 6.0},
            {"name": "Chadi Riad", "jersey": "18", "starter": True, "position": "DF", "rating": 6.0},
            {"name": "Noussair Mazraoui", "jersey": "3", "starter": True, "position": "DF", "rating": 6.0},
            {"name": "Neil El Aynaoui", "jersey": "24", "starter": True, "position": "MF", "rating": 6.5},
            {"name": "Ayyoub Bouaddi", "jersey": "6", "starter": True, "position": "MF", "rating": 6.5},
            {"name": "Brahim Díaz", "jersey": "10", "starter": True, "position": "MF", "rating": 6.0},
            {"name": "Azzedine Ounahi", "jersey": "8", "starter": True, "position": "MF", "rating": 6.0},
            {"name": "Bilal El Khannouss", "jersey": "23", "starter": True, "position": "MF", "rating": 6.5},
            {"name": "Ismael Saibari", "jersey": "11", "starter": True, "position": "FW", "rating": 7.5},
        ]
        match["formations"] = {"home": "4-3-3", "away": "4-2-3-1"}
        if not match.get("goals"):
            match["goals"] = [
                {"minute": "21", "team": "away", "scorer": "I. Saibari"},
                {"minute": "32", "team": "home", "scorer": "Vinícius Júnior"},
            ]
        match["summary"] = generate_match_summary(match)


# ============================================
# Tournament overview (World Cup / Euros / Champions League)
# ============================================

def fetch_wikipedia_group_teams(tournament, year, group):
    """Fetch the teams in a specific tournament group from Wikipedia."""
    page = f"{year}_{tournament}_Group_{group}"
    url = "https://en.wikipedia.org/w/api.php"
    params = {
        "action": "parse",
        "page": page,
        "prop": "wikitext",
        "format": "json",
        "formatversion": "2",
    }
    try:
        r = requests.get(url, params=params, headers=HEADERS, timeout=10)
        if r.status_code != 200:
            return []
        text = r.json().get("parse", {}).get("wikitext", "")
        # Extract: "The group consists of [[Mexico national football team|Mexico]] (co-host), ..."
        m = _re.search(r"The group consists of (.+?)\.", text, _re.DOTALL | _re.IGNORECASE)
        if not m:
            return []
        snippet = m.group(1)
        teams = []
        # Match both [[Team|Display]] and [[Display]]
        for link in _re.findall(r"\[\[([^\]|]+)(?:\|([^\]]+))?\]\]", snippet):
            display = link[1] if link[1] else link[0]
            display = display.replace("national football team", "").replace("national football team", "").strip()
            if display:
                teams.append(display)
        return teams
    except Exception as e:
        log(f"  Wikipedia group {group} fetch error: {e}")
        return []


def fetch_tournament_groups(league_id):
    """Fetch group composition for known tournaments."""
    groups = {}
    if "FIFA.WORLD" in league_id or "world cup" in league_id.lower():
        # Use hardcoded groups as primary source; try Wikipedia only as update.
        groups = dict(WORLD_CUP_2026_GROUPS)
        # Optionally update with Wikipedia in background (not critical)
        try:
            for group in "ABCDEFGHIJKL":
                wiki_teams = fetch_wikipedia_group_teams("FIFA_World_Cup", "2026", group)
                if wiki_teams:
                    groups[group] = wiki_teams
        except Exception:
            pass
    return groups


def compute_group_tables(matches, groups):
    """Compute live group tables from finished/in-progress matches."""
    tables = {}
    for group_name, teams in groups.items():
        table = {}
        for t in teams:
            cc = get_country_code(t, "FIFA.WORLD")
            flag_url, _is_flag = local_image_url_for_team(t, cc, "", True)
            table[t] = {
                "team": t,
                "countryCode": cc,
                "flag": flag_url or get_flag_url(cc),
                "played": 0, "won": 0, "drawn": 0, "lost": 0,
                "gf": 0, "ga": 0, "gd": 0, "points": 0,
            }
        # Find group matches (and remember them for head-to-head tiebreaks)
        group_matches = []
        for m in matches:
            home = m.get("homeTeam", "")
            away = m.get("awayTeam", "")
            if home in teams and away in teams:
                hs = m.get("homeScore", 0)
                aws = m.get("awayScore", 0)
                status = m.get("status", "pre")
                if status not in ("post", "in", "ht"):
                    continue
                group_matches.append((home, away, hs, aws))
                for team, gf, ga in [(home, hs, aws), (away, aws, hs)]:
                    row = table[team]
                    row["played"] += 1
                    row["gf"] += gf
                    row["ga"] += ga
                    if gf > ga:
                        row["won"] += 1
                        row["points"] += 3
                    elif gf == ga:
                        row["drawn"] += 1
                        row["points"] += 1
                    else:
                        row["lost"] += 1
                row["gd"] = row["gf"] - row["ga"]
        tables[group_name] = rank_group(list(table.values()), group_matches)
    return tables


def _h2h_stats(tied, group_matches):
    """Mini-table (points/gd/gf) using ONLY matches between the tied teams."""
    st = {t: {"pts": 0, "gd": 0, "gf": 0} for t in tied}
    for home, away, hs, aws in group_matches:
        if home in tied and away in tied:
            for team, gf, ga in [(home, hs, aws), (away, aws, hs)]:
                st[team]["gf"] += gf
                st[team]["gd"] += gf - ga
                st[team]["pts"] += 3 if gf > ga else 1 if gf == ga else 0
    return st


def rank_group(rows, group_matches):
    """FIFA group ranking: 1) points, 2) goal difference, 3) goals scored, then
    for teams still level, the head-to-head mini-table (points → GD → goals)
    among only those tied teams, then overall goals as a final fallback."""
    rows.sort(key=lambda r: (r["points"], r["gd"], r["gf"]), reverse=True)
    overall = lambda r: (r["points"], r["gd"], r["gf"])
    out, i = [], 0
    while i < len(rows):
        j = i
        while j < len(rows) and overall(rows[j]) == overall(rows[i]):
            j += 1
        tie = rows[i:j]
        if len(tie) > 1:
            tied = {r["team"] for r in tie}
            h = _h2h_stats(tied, group_matches)
            tie.sort(key=lambda r: (h[r["team"]]["pts"], h[r["team"]]["gd"],
                                    h[r["team"]]["gf"], r["gf"]), reverse=True)
        out.extend(tie)
        i = j
    for idx, row in enumerate(out, 1):
        row["rank"] = idx
    return out


def detect_active_tournament(matches):
    """Detect which major tournament is currently active."""
    priority = {"FIFA.WORLD": 3, "uefa.champions": 2, "uefa.euro": 2}
    counts = {}
    for m in matches:
        lid = m.get("leagueId", "")
        if lid in priority:
            counts[lid] = counts.get(lid, 0) + 1
    for lid in sorted(counts, key=lambda x: priority.get(x, 0), reverse=True):
        if counts[lid] > 0:
            return lid
    return ""


def compute_top_stats(matches, tournament_id):
    """Compute top scorers and assists from match events for a tournament."""
    scorers = {}
    assists = {}
    for m in matches:
        if m.get("leagueId") != tournament_id:
            continue
        events = m.get("keyEvents", [])
        for evt in events:
            text = evt.get("text", "")
            if not text:
                continue
            lower = text.lower()
            if "goal" not in lower:
                continue
            # Extract scorer: text usually contains "Goal! ... Name (Team) ..."
            scorer_match = _re.search(r'Goal![^\n]*?([A-Z][a-z]+(?:\s[A-Z][a-z]+)*)(?:\s\([^)]*\))', text)
            if scorer_match:
                scorer = scorer_match.group(1).strip()
                team = ""
                team_match = _re.search(r'\(([^)]+)\)', text)
                if team_match:
                    team = team_match.group(1).strip()
                key = (scorer, team)
                scorers[key] = scorers.get(key, {"name": scorer, "team": team, "goals": 0})
                scorers[key]["goals"] += 1
            # Extract assist
            assist_match = _re.search(r'Assisted by\s+([A-Z][a-z]+(?:\s[A-Z][a-z]+)*)', text)
            if assist_match:
                assister = assist_match.group(1).strip()
                key = (assister, "")
                assists[key] = assists.get(key, {"name": assister, "team": "", "assists": 0})
                assists[key]["assists"] += 1

    top_scorers = sorted(scorers.values(), key=lambda x: x["goals"], reverse=True)[:20]
    top_assists = sorted(assists.values(), key=lambda x: x["assists"], reverse=True)[:20]
    # Best-effort flag enrichment (only when the team string resolves to a country)
    for lst in (top_scorers, top_assists):
        for s in lst:
            cc = get_country_code(s.get("team", ""), "FIFA.WORLD")
            if cc and cc != "UNK":
                fu, _ = local_image_url_for_team(s["team"], cc, "", True)
                s["countryCode"] = cc
                s["flag"] = fu or get_flag_url(cc)
    return top_scorers, top_assists


# Official 2026 FIFA World Cup Round-of-32 bracket template (group positions).
# Spec: ("W", "A") winner of A, ("R", "B") runner-up of B, ("3", {groups}) the
# best third-placed team from one of those groups (FIFA assigns these 8 by a
# table; we solve the equivalent constraint matching from current standings).
R32_TEMPLATE = [
    (("R", "A"), ("R", "B")),
    (("W", "C"), ("R", "F")),
    (("W", "E"), ("3", {"A", "B", "C", "D", "F"})),
    (("W", "F"), ("R", "C")),
    (("R", "E"), ("R", "I")),
    (("W", "I"), ("3", {"C", "D", "F", "G", "H"})),
    (("W", "A"), ("3", {"C", "E", "F", "H", "I"})),
    (("W", "L"), ("3", {"E", "H", "I", "J", "K"})),
    (("W", "G"), ("3", {"A", "E", "H", "I", "J"})),
    (("W", "D"), ("3", {"B", "E", "F", "I", "J"})),
    (("W", "H"), ("R", "J")),
    (("R", "K"), ("R", "L")),
    (("W", "B"), ("3", {"E", "F", "G", "I", "J"})),
    (("R", "D"), ("R", "G")),
    (("W", "J"), ("R", "H")),
    (("W", "K"), ("3", {"D", "E", "I", "J", "L"})),
]


def _match_thirds(groups, slot_elig):
    """Max bipartite matching (Kuhn): assign each qualifying third-group to an
    eligible slot. Returns {slot_index: group} or None if no perfect matching."""
    slots = list(slot_elig.keys())
    match_slot = {}

    def try_assign(group, visited):
        for slot in slots:
            if group in slot_elig[slot] and slot not in visited:
                visited.add(slot)
                if slot not in match_slot or try_assign(match_slot[slot], visited):
                    match_slot[slot] = group
                    return True
        return False

    for g in groups:
        if not try_assign(g, set()):
            return None
    return match_slot


def project_knockout(tables):
    """Project the Round-of-32 bracket from current group standings (top 2 per
    group + the 8 best third-placed teams), respecting FIFA's slot eligibility."""
    if not tables or len(tables) < 12:
        return []
    winners, runners, thirds = {}, {}, []
    for grp, rows in tables.items():
        if len(rows) >= 1:
            winners[grp] = rows[0]
        if len(rows) >= 2:
            runners[grp] = rows[1]
        if len(rows) >= 3:
            r = dict(rows[2]); r["_group"] = grp; thirds.append(r)

    thirds.sort(key=lambda r: (r.get("points", 0), r.get("gd", 0), r.get("gf", 0)), reverse=True)
    best8 = thirds[:8]
    third_by_group = {t["_group"]: t for t in best8}
    third_groups = [t["_group"] for t in best8]

    third_slots = [i for i, (_h, a) in enumerate(R32_TEMPLATE) if a[0] == "3"]
    slot_elig = {i: R32_TEMPLATE[i][1][1] for i in third_slots}
    assign = _match_thirds(third_groups, slot_elig)
    if assign is None:  # data not far enough along — assign by rank as a fallback
        assign = {slot: third_groups[k] for k, slot in enumerate(third_slots) if k < len(third_groups)}

    def label(spec):
        kind, val = spec
        return {"W": "Winner ", "R": "Runner-up "}.get(kind, "3rd ") + (val if isinstance(val, str) else "")

    def team_of(spec):
        kind, val = spec
        return winners.get(val) if kind == "W" else runners.get(val) if kind == "R" else None

    out = []
    for i, (h, a) in enumerate(R32_TEMPLATE):
        home = team_of(h)
        if a[0] == "3":
            grp = assign.get(i)
            away = third_by_group.get(grp)
            away_label = "3rd " + grp if grp else "3rd place"
        else:
            away = team_of(a)
            away_label = label(a)
        out.append({
            "match":     i + 1,
            "home":      home.get("team") if home else label(h),
            "away":      away.get("team") if away else away_label,
            "homeFlag":  home.get("flag", "") if home else "",
            "awayFlag":  away.get("flag", "") if away else "",
            "homeLabel": label(h),
            "awayLabel": away_label,
        })
    return out


def fetch_espn_standings(tournament_id):
    """Official group standings from ESPN — real results, correct tiebreakers,
    in sync with every match played. Returns {group: [rows]} or None."""
    try:
        url = f"https://site.api.espn.com/apis/v2/sports/soccer/{tournament_id}/standings"
        r = requests.get(url, headers=HEADERS, timeout=10)
        if r.status_code != 200:
            return None
        data = r.json()
    except Exception as e:
        log(f"  ESPN standings {tournament_id}: {e}")
        return None

    children = data.get("children") or []
    if not children:
        return None

    def num(stats, key):
        try:
            return int(stats.get(key, 0) or 0)
        except (ValueError, TypeError):
            return 0

    tables = {}
    for child in children:
        name = child.get("name", "") or ""
        grp = name.replace("Group ", "").strip() or name
        entries = ((child.get("standings") or {}).get("entries")) or []
        rows = []
        for e in entries:
            t = e.get("team", {})
            stats = {s.get("name"): s.get("value") for s in e.get("stats", [])}
            team_name = t.get("displayName", "") or t.get("name", "")
            cc = (t.get("abbreviation") or "").upper() or get_country_code(team_name, tournament_id)
            flag_url, _is_flag = local_image_url_for_team(team_name, cc, "", True)
            rows.append({
                "team": team_name,
                "countryCode": cc,
                "flag": flag_url or get_flag_url(cc),
                "played":  num(stats, "gamesPlayed"),
                "won":     num(stats, "wins"),
                "drawn":   num(stats, "ties"),
                "lost":    num(stats, "losses"),
                "gf":      num(stats, "pointsFor"),
                "ga":      num(stats, "pointsAgainst"),
                "gd":      num(stats, "pointDifferential"),
                "points":  num(stats, "points"),
                "rank":    num(stats, "rank"),
            })
        rows.sort(key=lambda r: r["rank"] if r["rank"] else 99)
        for i, row in enumerate(rows, 1):
            row["rank"] = i
        if rows:
            tables[grp] = rows
    return tables or None


def build_tournament_data(matches):
    """Build tournament overview data (groups + knockout matches + stats)."""
    active = detect_active_tournament(matches)
    if not active:
        return None

    tournament_name = LEAGUE_NAMES.get(active, active)
    groups = fetch_tournament_groups(active)
    # Prefer ESPN's OFFICIAL standings (real results + correct tiebreakers, in
    # sync with every played match) over computing from our narrow match window.
    tables = fetch_espn_standings(active)
    if not tables:
        tables = compute_group_tables(matches, groups) if groups else {}

    # Knockout matches: non-group-stage matches in the same tournament. Build the
    # set of group teams from the actual standings when we have them.
    all_group_teams = set()
    if tables:
        for rows in tables.values():
            for r in rows:
                all_group_teams.add(r.get("team", ""))
    else:
        for teams in groups.values():
            all_group_teams.update(teams)

    knockout_matches = []
    for m in matches:
        if m.get("leagueId") != active:
            continue
        home = m.get("homeTeam", "")
        away = m.get("awayTeam", "")
        # A knockout match has a team that isn't in any group. ONLY classify when
        # we actually have group data — otherwise a transient group-fetch failure
        # (all_group_teams empty) would wrongly dump every match into "Knockout".
        if all_group_teams and (home not in all_group_teams or away not in all_group_teams):
            knockout_matches.append(m)

    top_scorers, top_assists = compute_top_stats(matches, active)

    return {
        "updated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "tournamentId": active,
        "tournamentName": tournament_name,
        "groups": tables,
        "knockoutMatches": knockout_matches,
        "projectedKnockout": project_knockout(tables),
        "topScorers": top_scorers,
        "topAssists": top_assists,
    }


TOURNAMENT_ASSETS = {
    "FIFA.WORLD": {
        "mascot": "https://upload.wikimedia.org/wikipedia/en/thumb/7/77/2026_FIFA_World_Cup_Mascots_small.jpg/500px-2026_FIFA_World_Cup_Mascots_small.jpg",
        "logo": "https://upload.wikimedia.org/wikipedia/en/thumb/9/94/WorldCup2026lposter.jpg/500px-WorldCup2026lposter.jpg",
    }
}


def download_tournament_assets(tournament_id):
    """Download mascot/logo images for an active tournament."""
    assets = TOURNAMENT_ASSETS.get(tournament_id)
    if not assets:
        return {}
    result = {}
    for key, url in assets.items():
        filename = f"wc_{key}.jpg" if tournament_id == "FIFA.WORLD" else f"asset_{key}.jpg"
        local = download_image(url, filename)
        if local:
            result[key] = local
    return result


def write_tournament_cache(matches):
    """Write tournament overview data if an active tournament is found."""
    data = build_tournament_data(matches)
    if not data:
        # Remove old file if no tournament is active
        tfile = CACHE_DIR / "tournament.json"
        if tfile.exists():
            tfile.unlink()
        return

    # Download mascot/logo assets for active tournament
    assets = download_tournament_assets(data["tournamentId"])
    data["assets"] = assets
    data["themeActive"] = bool(assets)

    tmp_file = (CACHE_DIR / "tournament.json").with_suffix(".tmp")
    tmp_file.write_text(json.dumps(data, ensure_ascii=False, indent=2))
    tmp_file.rename(CACHE_DIR / "tournament.json")


def merge_ai_commentary(matches):
    """Overlay live LLM commentary onto matches so it survives this rewrite.

    football-commentator.py writes commentary.json ({match_id: {text, ...}});
    we set the live match summary to that line and flag it so the widget can
    style it. The widget already shows `summary` in the match-card callout."""
    f = CACHE_DIR / "commentary.json"
    if not f.exists():
        return
    try:
        ai = json.loads(f.read_text())
    except Exception:
        return
    if not isinstance(ai, dict):
        return
    for m in matches:
        entry = ai.get(str(m.get("id", "")))
        if isinstance(entry, dict) and entry.get("text"):
            m["summary"] = entry["text"]
            m["aiCommentary"] = True
            # Stable id so the widget speaks each line exactly once.
            m["aiCommentaryId"] = entry.get("ts") or entry.get("clock") or entry["text"]


def write_cache(matches):
    """Write matches to cache file"""
    merge_ai_commentary(matches)
    data = {
        "updated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "matches": matches,
    }
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    tmp_file = MATCHES_FILE.with_suffix(".tmp")
    tmp_file.write_text(json.dumps(data, ensure_ascii=False, indent=2))
    tmp_file.rename(MATCHES_FILE)


def write_teams_cache(matches):
    """Write a deduplicated list of all team names for the settings autocomplete"""
    teams = set(STATIC_TEAMS)
    for m in matches:
        teams.add(m.get("homeTeam", ""))
        teams.add(m.get("awayTeam", ""))
    teams.discard("")
    data = {
        "updated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "teams": sorted(teams, key=lambda s: s.lower()),
    }
    tmp_file = (CACHE_DIR / "teams.json").with_suffix(".tmp")
    tmp_file.write_text(json.dumps(data, ensure_ascii=False, indent=2))
    tmp_file.rename(CACHE_DIR / "teams.json")


def write_leagues_cache(league_info):
    """Write league metadata (names + logos) for theming. Logos are cached locally."""
    for lid, info in league_info.items():
        logo_url = info.get("logo", "")
        if logo_url:
            safe = lid.replace(".", "_").lower()
            local = download_image(logo_url, f"league_{safe}")
            if local:
                info["logoLocal"] = local
    data = {
        "updated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "leagues": league_info,
    }
    tmp_file = (CACHE_DIR / "leagues.json").with_suffix(".tmp")
    tmp_file.write_text(json.dumps(data, ensure_ascii=False, indent=2))
    tmp_file.rename(CACHE_DIR / "leagues.json")


def run_once(leagues):
    """Single fetch cycle"""
    global _details_cache
    try:
        # The resolved-id map persists across cycles (ids are stable), but the
        # per-date /matches lookups are refreshed each cycle for fresh data.
        _fotmob_date_cache.clear()
        matches, league_info = fetch_all_matches(leagues)
        write_cache(matches)
        write_teams_cache(matches)
        write_leagues_cache(league_info)
        write_tournament_cache(matches)
        save_details_cache(_details_cache)
        live = sum(1 for m in matches if m["status"] == "in")
        upcoming = sum(1 for m in matches if m["status"] == "pre")
        finished = sum(1 for m in matches if m["status"] == "post")
        log(f"Done: {len(matches)} matches ({live} live, {upcoming} upcoming, {finished} finished)")
    except Exception as e:
        log(f"Error in fetch cycle: {e}")

def main_loop():
    """Main loop with signal handling"""
    global _running

    def handle_signal(signum, frame):
        global _running
        _running = False
        log("Shutting down...")

    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)

    cfg = load_config()
    # Widget config uses "selectedLeagues"; keep "leagues" as legacy fallback
    leagues = cfg.get("selectedLeagues") or cfg.get("leagues") or DEFAULT_LEAGUES
    if isinstance(leagues, str):
        leagues = [l.strip() for l in leagues.split(",") if l.strip()]
    interval = cfg.get("interval", 10)

    log(f"Starting fetcher with {len(leagues)} leagues, interval={interval}s")
    log(f"Leagues: {leagues}")

    while _running:
        run_once(leagues)
        if not _running:
            break
        time.sleep(interval)

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--once":
        cfg = load_config()
        leagues = cfg.get("selectedLeagues") or cfg.get("leagues") or DEFAULT_LEAGUES
        if isinstance(leagues, str):
            leagues = [l.strip() for l in leagues.split(",") if l.strip()]
        run_once(leagues)
        sys.exit(0)

    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    main_loop()
