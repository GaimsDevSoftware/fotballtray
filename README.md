# FootballTray

A KDE Plasma 6 widget that keeps live football scores in your system tray. Click it for the details: line-ups, goalscorers, group tables, knockout brackets, player ratings. It can even call the game out loud for you.

![Tray](screenshots/01-tray-live.png)

## What you get

- **A glanceable tray widget** with the score, the teams, the clock, and a blinking dot while the match is live.
- **A full popup** with live and finished matches, kickoff times, goalscorers, group standings, knockout brackets, and a proper match card with line-ups and player ratings.
- **Sharp on 4K and fractional scaling**, with optional text outline and drop shadow (set per style group).
- **Optional AI commentary.** It writes British-TV-style lines on goals, cards and the run of play, and can read them aloud in a British voice. Run it locally on your own GPU with [Ollama](https://ollama.com), or use a free cloud provider (OpenRouter, Groq, Gemini, OpenCode Zen) if you don't have a GPU. Cloud setup is one paste of a free API key. In local mode nothing leaves your machine.

## Install

FootballTray is a panel widget plus a small local backend (a Python fetcher and a localhost JSON server) that feeds it scores. The installer sets up both.

```sh
git clone https://github.com/GaimsDevSoftware/fotballtray.git
cd fotballtray
./install.sh
```

Then right-click your panel, pick **Add Widgets**, and search for **FootballTray**.

To remove it: `./uninstall.sh` (add `--purge` to wipe the cached data too).

### You'll need
- **KDE Plasma 6** (`kpackagetool6`, `systemctl --user`)
- **Python 3** with `requests` (`python3-requests`)
- *For spoken commentary (optional):* a TTS voice, either [piper](https://github.com/rhasspy/piper) (`en_GB-alan-medium`) or [Kokoro](https://github.com/hexgrad/kokoro), plus `paplay` (PipeWire/PulseAudio)
- *For AI commentary (optional):* either [Ollama](https://ollama.com) for local GPU, or a free cloud API key (OpenRouter, Groq, Gemini). No GPU, no card needed.

## Turning on AI commentary (optional)

Open the widget's **Settings**, go to the **Commentary** tab, and pick an engine:
- **Local GPU (Ollama):** runs entirely on your machine, nothing leaves it.
- **Free cloud (no GPU):** pick a provider, click **Get free key**, paste the key, then **Set up cloud**. It tests the key, picks a free model, and switches over.

Hit **Test voice** or **Test commentary** to hear it.

## License

[MIT](LICENSE), 2026 GaimsDevSoftware
