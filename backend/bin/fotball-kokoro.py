#!/usr/bin/env python3
"""Synthesise commentary with Kokoro (British male voice) → WAV.
usage: echo "text" | fotball-kokoro.py <outfile.wav> [speed]
"""
import os
import sys

out = sys.argv[1] if len(sys.argv) > 1 else "/tmp/kokoro.wav"
speed = float(sys.argv[2]) if len(sys.argv) > 2 else 1.0
text = sys.stdin.read().strip()
if not text:
    sys.exit(0)

home = os.path.expanduser("~/.local/share/kokoro")
voice = os.environ.get("KOKORO_VOICE", "bm_george")  # British male

from kokoro_onnx import Kokoro
import soundfile as sf

k = Kokoro(os.path.join(home, "kokoro-v1.0.onnx"), os.path.join(home, "voices-v1.0.bin"))
samples, sr = k.create(text, voice=voice, speed=speed, lang="en-gb")
sf.write(out, samples, sr)
