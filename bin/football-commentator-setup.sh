#!/usr/bin/env bash
# football-commentator-setup.sh
# One-shot setup for the Sofascore poller + Ollama commentary system.
# Run once: bash ~/.local/bin/football-commentator-setup.sh

set -euo pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
fail() { echo -e "${RED}✗${NC} $*"; }

echo "=== Football Live — kommentator-oppsett ==="
echo ""

# ── 1. Python dependencies ──────────────────────────────────────────────────
echo "→ Sjekker Python-avhengigheter..."
python3 -c "import requests" 2>/dev/null && ok "requests installert" || {
    warn "requests mangler — installerer..."
    pip3 install --user requests
}

# ── 2. Ollama ───────────────────────────────────────────────────────────────
echo ""
echo "→ Sjekker Ollama..."
if command -v ollama &>/dev/null; then
    ok "Ollama funnet: $(ollama --version 2>/dev/null | head -1)"
else
    warn "Ollama ikke installert. Installerer..."
    curl -fsSL https://ollama.com/install.sh | sh
    ok "Ollama installert"
fi

# Start Ollama if not running
if ! curl -s http://localhost:11434/api/tags &>/dev/null; then
    echo "→ Starter Ollama server..."
    ollama serve &>/dev/null &
    sleep 3
fi

# ── 3. Pull model ───────────────────────────────────────────────────────────
echo ""
echo "→ Sjekker Ollama-modell..."
DEFAULT_MODEL="${OLLAMA_MODEL:-phi4-mini}"

if ollama list 2>/dev/null | grep -q "$DEFAULT_MODEL"; then
    ok "Modell '$DEFAULT_MODEL' allerede installert"
else
    echo "→ Laster ned '$DEFAULT_MODEL' (~2.5 GB, kan ta noen minutter)..."
    ollama pull "$DEFAULT_MODEL"
    ok "Modell klar"
fi

# ── 4. Test commentary generation ───────────────────────────────────────────
echo ""
echo "→ Tester kommentargenerering..."
TEST_PROMPT='Beskriv dette målet på norsk i 1-2 setninger:
{"minutter": "78'"'"'", "spiller": "Erling Haaland", "hjemmelag": "Norway", "bortelag": "Germany", "stilling": "2-1", "liga": "VM 2026"}'

RESULT=$(ollama run "$DEFAULT_MODEL" "$TEST_PROMPT" 2>/dev/null | head -3)
if [ -n "$RESULT" ]; then
    ok "Kommentargenerering fungerer:"
    echo "    \"$RESULT\""
else
    warn "Modellen svarte ikke — sjekk at Ollama kjører"
fi

# ── 5. Systemd services ──────────────────────────────────────────────────────
echo ""
echo "→ Aktiverer systemd-tjenester..."
systemctl --user daemon-reload

for svc in football-sofascore football-commentator; do
    if systemctl --user is-enabled "$svc" &>/dev/null; then
        ok "$svc.service allerede aktivert"
    else
        systemctl --user enable "$svc"
        ok "$svc.service aktivert"
    fi
    systemctl --user restart "$svc"
    sleep 1
    if systemctl --user is-active --quiet "$svc"; then
        ok "$svc.service kjører"
    else
        fail "$svc.service startet ikke — sjekk: journalctl --user -u $svc -n 20"
    fi
done

# ── 6. Summary ───────────────────────────────────────────────────────────────
echo ""
echo "=== Oppsett fullført ==="
echo ""
echo "Tjenester:"
echo "  Status:   systemctl --user status football-sofascore football-commentator"
echo "  Logger:   journalctl --user -u football-commentator -f"
echo "  Arkiv:    cat ~/.cache/fotballtray/commentary_archive.jsonl"
echo ""
echo "Bytt modell:"
echo "  ollama pull llama3.2:3b"
echo "  systemctl --user set-environment OLLAMA_MODEL=llama3.2:3b"
echo "  systemctl --user restart football-commentator"
echo ""
echo "For fintuning: samle par fra commentary_archive.jsonl"
echo "  Format: {input: <event_json>, output: <commentary>}"
echo "  Verktøy: unsloth (pip install unsloth) + LoRA på GPU"
