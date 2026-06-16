# Handover — Fotball Live tray widget

## Last updated
2026-06-14

## Current state
Widget files are complete in `~/.local/share/plasma/plasmoids/org.kde.fotballtray/`. A duplicate/conflicting slashed directory `org/kde/fotballtray/` was removed. Plasmashell was restarted after clearing QML cache. Verify in the system tray that the widget shows match data and not a placeholder document icon.

## Naming convention
This app is called **Fotball / football**. Never use the word **soccer** for file names, identifiers, UI labels, buttons, settings, variables, comments, or anywhere else in this project.

## Ongoing work
Claude Code is continuing to work on the app design after this session ended. Expect ongoing UI/UX polish, layout refinements, and visual consistency improvements in the next session.

## Future AI roadmap
The long-term goal is to add a **local, self-trained AI** for live match analysis. The AI will fetch live results in real time from established Norwegian sites (e.g. **VG Live**) down to the second, analyse match momentum, and present insights inside the widget. This is a post-MVP feature; the immediate priority is a stable, well-designed tray widget.

## What works
- Live match data from ESPN (+ OpenLigaDB/Wikipedia fallback) served via local HTTP server on `127.0.0.1:9876`.
- Tray widget with configurable display modes: text only, flag/logo + text, flag/logo only.
- Goal ticker/banner with configurable display mode, match count and speed.
- Sound notifications with selectable output device.
- Modern settings UI with card-based design, team autocomplete chips, league/turnering chip selector.
- Tournament window via right-click menu: group tables (A–L), knockout matches, top scorers and assists.
- Per-league/tournament theming with colors and animated branding header (World Cup mascot/logo animation included).
- Persistent detail cache for finished matches.
- Local image cache for flags, logos, league logos, WC mascot and logo.

## Recent changes
- Removed duplicate/conflicting plasmoid directory `org/kde/fotballtray/` (slashed). The canonical path is `org.kde.fotballtray/` (dotted).
- Cleared Plasma QML cache and restarted plasmashell.
- Fixed QML syntax error in `MatchDetailCard.qml` (`label":"` → `label:`).
- Switched context menu to Plasma 6 `Plasmoid.contextualActions` API.
- Made tournament window larger and group tables use a compact grid layout.
- Added hardcoded World Cup 2026 group fallback so tables always work.

## Known issues / limitations
- `Plasmoid.setAction` does NOT work in Plasma 6; use `Plasmoid.contextualActions`.
- Restarting plasmashell with `systemctl restart plasma-plasmashell.service` may fail because the service is disabled. Use `killall plasmashell; sleep 2; nohup plasmashell > /tmp/plasmashell.log 2>&1 &`.
- Knockout bracket is currently a simple list, not a true bracket visualization.
- Top scorers/assists extraction uses regex on event text; can miss hyphenated/ambiguous names.
- ESPN summary API often returns no lineups/stats for finished matches; data is best-effort.
- Settings config key is `selectedLeagues` while backend fetcher reads `leagues` — align these in a future refactor.

## Architecture reminders
- Backend: `~/.local/bin/fotball-data-fetcher.py`
- HTTP server: `~/.cache/fotballtray/httpserver.py`
- Cache: `~/.cache/fotballtray/`
- Plasmoid: `~/.local/share/plasma/plasmoids/org.kde.fotballtray/`
- Services: `fotball-fetcher.service`, `fotball-server.service` (user systemd)

## Useful commands
```bash
# Restart data services
systemctl --user restart fotball-fetcher.service
systemctl --user restart fotball-server.service

# Force-restart Plasma shell
killall plasmashell; sleep 2; nohup plasmashell > /tmp/plasmashell.log 2>&1 &

# Test endpoints
curl -s http://127.0.0.1:9876/matches.json | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d['matches']))"
curl -s http://127.0.0.1:9876/tournament.json | python3 -c "import json,sys; d=json.load(sys.stdin); print(list(d.get('groups',{}).keys()))"
curl -s http://127.0.0.1:9876/leagues.json | python3 -c "import json,sys; d=json.load(sys.stdin); print(list(d['leagues'].keys()))"
```

## Suggested next steps
1. Verify the widget renders correctly after the restart.
2. Continue UI/UX design polish (typography, spacing, animations, dark/light contrast).
3. Improve knockout bracket into a real bracket/tree visualization.
4. Add more player tournament stats: yellow/red cards, minutes played, clean sheets.
5. Add standings tables for regular leagues (not just tournaments).
6. Polish the goal ticker to show multiple matches in a true marquee when many are live.
7. Add dark/light theme aware assets for league logos.
8. Allow resizing the popup and persist size in config.
9. Add match reminders/notifications before kickoff for favorite teams.
10. Plan the local AI module: data sources (VG Live), model choice, training data, inference integration.

## Key files
- `contents/ui/main.qml` — root, data loading, sound, context actions, theme helpers.
- `contents/ui/CompactRepresentation.qml` — tray representation.
- `contents/ui/FullRepresentation.qml` — popup with matches + tournament tabs.
- `contents/ui/components/TournamentView.qml` — groups/knockout/stats tabs.
- `contents/ui/components/GroupTable.qml` — compact group table.
- `contents/ui/components/MatchDetailCard.qml` — expanded match card.
- `contents/ui/components/KnockoutView.qml` — knockout match list.
- `contents/ui/components/TeamSelector.qml` — team autocomplete in settings.
- `contents/ui/configGeneral.qml` — modern settings UI.
- `contents/ui/Theme.js` — per-league color mappings.
- `~/.local/bin/fotball-data-fetcher.py` — backend data fetcher and tournament logic.
