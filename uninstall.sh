#!/usr/bin/env bash
# FootballTray - uninstaller. Keeps your ~/.cache/fotballtray data unless you
# pass --purge.
set -uo pipefail

echo "▶ Removing FootballTray…"
systemctl --user disable --now fotball-fetcher.service fotball-server.service \
    football-commentator.service football-sofascore.service 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/"{fotball-fetcher,fotball-server,football-commentator,football-sofascore}.service
rm -rf "$HOME/.config/systemd/user/football-commentator.service.d"
systemctl --user daemon-reload

rm -f "$HOME/.local/bin/"{fotball-data-fetcher,fotball-kokoro,football-commentator,football-sofascore}.py \
      "$HOME/.local/bin/"{fotball-llm-ctl,fotball-tts,fotball-play}.sh \
      "$HOME/.cache/fotballtray/httpserver.py"

kpackagetool6 --type Plasma/Applet --remove org.kde.fotballtray 2>/dev/null || true

if [ "${1:-}" = "--purge" ]; then
    rm -rf "$HOME/.cache/fotballtray"
    echo "✓ Removed FootballTray and its data."
else
    echo "✓ Removed FootballTray. Your data in ~/.cache/fotballtray was kept (use --purge to delete)."
fi
