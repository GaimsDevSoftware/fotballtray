#!/usr/bin/env bash
# FootballTray — installer for the KDE Plasma 6 widget + its local data backend.
# Safe to re-run. Does not touch your data in ~/.cache/fotballtray.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

echo "▶ FootballTray installer"

# ── 1. Dependencies ────────────────────────────────────────────────────────────
command -v python3        >/dev/null || { echo "✗ python3 is required."; exit 1; }
command -v kpackagetool6  >/dev/null || { echo "✗ kpackagetool6 not found — this needs KDE Plasma 6."; exit 1; }
command -v systemctl      >/dev/null || { echo "✗ systemd (systemctl --user) is required."; exit 1; }
if ! python3 -c 'import requests' 2>/dev/null; then
    echo "⚠ Python 'requests' module missing — install it first:"
    echo "    sudo dnf install python3-requests   # Fedora"
    echo "    sudo apt install python3-requests    # Debian/Ubuntu"
    echo "    (or: pip install --user requests)"
fi

# ── 2. Backend scripts + data server ───────────────────────────────────────────
mkdir -p "$HOME/.local/bin" "$HOME/.cache/fotballtray" "$HOME/.config/systemd/user"
install -m 755 "$HERE"/backend/bin/*           "$HOME/.local/bin/"
install -m 755 "$HERE"/backend/server/httpserver.py "$HOME/.cache/fotballtray/"
cp "$HERE"/backend/systemd/*.service           "$HOME/.config/systemd/user/"
echo "✓ Backend installed to ~/.local/bin and ~/.cache/fotballtray"

# ── 3. The plasmoid ─────────────────────────────────────────────────────────────
if kpackagetool6 --type Plasma/Applet --list 2>/dev/null | grep -q "org.kde.fotballtray"; then
    # In-place file copy on update (kpackagetool6 -u is destructive — avoid it).
    DEST="$HOME/.local/share/plasma/plasmoids/org.kde.fotballtray"
    mkdir -p "$DEST"; cp -rf "$HERE/metadata.json" "$HERE/contents" "$DEST/"
    echo "✓ Widget updated"
else
    kpackagetool6 --type Plasma/Applet --install "$HERE"
    echo "✓ Widget installed"
fi

# ── 4. Start the data services (live scores). AI commentary stays opt-in. ───────
systemctl --user daemon-reload
systemctl --user enable --now fotball-server.service fotball-fetcher.service
echo "✓ Data services started"

cat <<'EOF'

✅ FootballTray is installed.

  • Add it:   right-click your panel → Add Widgets → search "FootballTray"
  • Configure favourite teams & leagues in the widget's Settings → Follow
  • Optional AI live commentary (Settings → Commentary):
        – Local GPU: install Ollama (button in settings)
        – No GPU:    pick a free cloud provider and paste a free API key
  • Optional spoken commentary needs a TTS voice (piper or kokoro) — see README.

Enjoy the football!
EOF
