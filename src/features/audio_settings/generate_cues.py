"""Six original B1 candidates: Python standard-library DSP, no sampled input."""

import hashlib
import json
import math
from pathlib import Path
import random
import struct
import wave

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "assets/audio/b1"
RATE = 44100
SEED = 20261024
SPECS = {
    "ui_confirm": (0.18, "two soft sine notes: 660 / 880 Hz, onset 0 / 0.065 s"),
    "ui_back": (0.17, "two soft sine notes: 660 / 440 Hz, onset 0 / 0.065 s"),
    "fire": (0.16, "low-pass noise (alpha .32), decay 38/s + 150 Hz body decay 30/s"),
    "hit": (0.12, "low-pass noise (alpha .32), decay 52/s + 310 Hz body decay 45/s"),
    "collect_complete": (0.48, "sine triad 523.25 / 659.25 / 783.99 Hz, onset 0 / .09 / .18 s"),
    "bus_start": (1.15, "rising motor 48 to 103.2 Hz + harmonics 2/3 + filtered noise; 12 Hz modulation"),
}


def tone(t, hz, onset, decay):
    age = t - onset
    if age < 0:
        return 0.0
    return min(1.0, age / 0.006) * math.exp(-decay * age) * math.sin(math.tau * hz * age)


def generate():
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = {
        "source": "Original mathematical synthesis; no recordings, external audio or Deadly Days assets.",
        "generator": "src/features/audio_settings/generate_cues.py",
        "generator_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "format": "mono PCM signed 16-bit little-endian WAV, 44100 Hz, no loops",
        "seed": SEED,
        "processing": "mean removed, 4 ms attack / 20 ms release sine-squared envelope, peak normalized to 0.55",
        "status": "candidates; listening pending",
        "assets": [],
    }
    for cue, (duration, method) in SPECS.items():
        rng = random.Random(SEED)
        filtered = 0.0
        samples = []
        count = round(duration * RATE)
        for i in range(count):
            t = i / RATE
            filtered += 0.32 * (rng.uniform(-1, 1) - filtered)
            if cue.startswith("ui_"):
                hz = 880 if cue == "ui_confirm" else 440
                value = tone(t, 660, 0, 32) + 0.8 * tone(t, hz, .065, 32)
            elif cue in ("fire", "hit"):
                decay, hz, body_decay = (38, 150, 30) if cue == "fire" else (52, 310, 45)
                value = filtered * math.exp(-decay * t) + .45 * tone(t, hz, 0, body_decay)
            elif cue == "collect_complete":
                value = sum(tone(t, hz, onset, 14) for hz, onset in
                            [(523.25, 0), (659.25, .09), (783.99, .18)])
            else:
                phase = math.tau * (48 * t + 24 * t * t)
                value = (math.sin(phase) + .3 * math.sin(2 * phase) + .15 * math.sin(3 * phase))
                value = value * (.75 + .25 * math.sin(math.tau * 12 * t)) + .15 * filtered
                value *= min(1, t / .12) * min(1, (duration - t) / .35)
            samples.append(value)
        mean = sum(samples) / count
        for i in range(count):
            attack = min(1, i / (RATE * .004))
            release = min(1, (count - 1 - i) / (RATE * .020))
            samples[i] = (samples[i] - mean) * math.sin(math.pi / 2 * min(attack, release)) ** 2
        gain = .55 / max(abs(x) for x in samples)
        pcm = [round(x * gain * 32767) for x in samples]
        path = OUT / (cue + ".wav")
        with wave.open(str(path), "wb") as output:
            output.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
            output.writeframes(struct.pack("<" + "h" * count, *pcm))
        manifest["assets"].append({
            "cue": cue, "file": path.relative_to(ROOT).as_posix(), "duration_s": duration,
            "method": method, "peak": max(abs(x) for x in pcm) / 32768,
            "rms": math.sqrt(sum(x*x for x in pcm) / count) / 32768,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        })
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    print("B1 generated six original candidate WAVs (no playback)")


if __name__ == "__main__":
    generate()
