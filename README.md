# FootballTray — KDE Plasma 6 widget

Live football scores in your system tray, with match details, line-ups, group
tables, knockout brackets and optional AI commentary.

![Tray](screenshots/01-tray-live.png)

## Features

- **Glanceable tray widget** — current score, teams and match clock, with a
  blinking live indicator during play.
- **Full popup** — live & finished matches, kickoff times, goalscorers, group
  standings, knockout brackets, and a detailed match card with line-ups and
  player ratings.
- **Sharp rendering** on 4K / fractional-scaled displays; crisp text with
  optional outline and drop shadow (configurable per style group).
- **Optional AI live commentary** — British-TV-style lines on goals, cards and
  the run of play, optionally read aloud in a British voice. Run it **locally**
  on your own GPU (via [Ollama](https://ollama.com)), or use a **free cloud
  provider** (OpenRouter, Groq, Gemini, OpenCode Zen) if you have no GPU — set
  up with a single paste of a free API key. In local mode, no data leaves your
  machine.

## Install

FootballTray is a panel widget **plus** a small local data backend (a Python
fetcher + a localhost JSON server) that feeds it live scores. The one-line
installer sets up both.

```sh
git clone https://github.com/GaimsDevSoftware/fotballtray.git
cd fotballtray
./install.sh
```

Then add it: right-click your panel → **Add Widgets** → search **FootballTray**.

To remove everything: `./uninstall.sh` (add `--purge` to also delete cached data).

### Requirements
- **KDE Plasma 6** (`kpackagetool6`, `systemctl --user`)
- **Python 3** with the `requests` module (`python3-requests`)
- *Optional — spoken commentary:* a TTS voice — [piper](https://github.com/rhasspy/piper)
  (`en_GB-alan-medium`) or [Kokoro](https://github.com/hexgrad/kokoro), plus
  `paplay` (PipeWire/PulseAudio)
- *Optional — AI commentary:* either [Ollama](https://ollama.com) (local GPU) or a
  free cloud API key (OpenRouter / Groq / Gemini — no GPU, no card)

## Live AI commentary (optional)

In the widget's **Settings → Commentary** tab, choose an engine:
- **Local GPU (Ollama)** — runs entirely on your machine; nothing leaves it.
- **Free cloud (no GPU)** — pick a provider, click **Get free key**, paste it,
  and **Set up cloud**. It tests the key, picks a free model and switches over.

Use **Test voice** / **Test commentary** to hear it.

## License

[MIT](LICENSE) © 2026 GaimsDevSoftware
