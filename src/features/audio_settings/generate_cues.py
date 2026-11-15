"""Original warm one-shots: deterministic Python stdlib DSP, no sampled input.

Codex assisted the code. No audio model, recording or third-party sound is used.
Regeneration refreshes WAVs, manifest and provenance. No playback is performed.
"""

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
SEED = 20261115
PEAK = 0.55
SPECS = {
    "ui_confirm": (0.20, "felt C5/E5 upward dyad"),
    "ui_back": (0.20, "felt E5/C5 downward dyad"),
    "fire": (0.19, "filtered air snap and descending wooden 230-150 Hz body"),
    "melee_swing": (0.24, "band-limited air swish with rounded 220 Hz contact"),
    "hit": (0.16, "wooden 370/590 Hz tap and filtered air; no flesh sample"),
    "survivor_hit": (0.23, "padded 210/280 Hz double knock; no vocalization"),
    "collect_complete": (0.48, "felt C5/E5/G5 ascending completion"),
    "bus_start": (0.90, "warm small motor rising 72-114 Hz with soft latch"),
    "bus_board": (0.32, "two soft door/step taps and rounded E5 bell"),
    "bus_depart": (0.85, "warm 90-145 Hz motor lift with C5 send-off"),
    "screamer_warning": (0.54, "two rounded rising A4/D5 reed pulses; no scream"),
    "toxic_warning": (0.46, "three airy puffs with descending E5/C5/G4 droplets"),
    "burst_warning": (0.48, "three ascending low wooden pressure taps; no explosion"),
    "hound_warning": (0.30, "quick G4/C5 wooden pair; no animal recording"),
    "nightfall": (0.78, "low C4/G3 felt bell cadence, once; no rumble or loop"),
}


def tone(t, hz, onset=0.0, decay=14.0):
    age = t - onset
    if age < 0:
        return 0.0
    return min(1.0, age / 0.006) * math.exp(-decay * age) * math.sin(math.tau * hz * age)


def notes(t, sequence, decay=14.0):
    return sum(tone(t, hz, onset, decay) for hz, onset in sequence)


def synthesize(cue, duration):
    rng = random.Random(f"{SEED}:{cue}")
    low = mellow = 0.0
    samples = []
    for i in range(round(duration * RATE)):
        t = i / RATE
        low += 0.25 * (rng.uniform(-1.0, 1.0) - low)
        mellow += 0.07 * (low - mellow)
        air = low - mellow
        if cue.startswith("ui_"):
            pair = (523.25, 659.25) if cue == "ui_confirm" else (659.25, 523.25)
            value = notes(t, [(pair[0], 0), (pair[1], 0.065)], 24)
        elif cue == "fire":
            phase = math.tau * (230 * t - 210 * t * t)
            value = (0.75 * air + 0.55 * math.sin(phase)) * math.exp(-19 * t)
            value += 0.12 * tone(t, 760, 0.014, 40)
        elif cue == "melee_swing":
            value = 2.2 * air * math.sin(math.pi * t / duration) ** 2 + 0.24 * tone(t, 220, 0.13, 26)
        elif cue == "hit":
            value = notes(t, [(370, 0), (590, 0.008)], 34) + 0.35 * air * math.exp(-30 * t)
        elif cue == "survivor_hit":
            value = notes(t, [(210, 0), (280, 0.055)], 25) + 0.20 * mellow * math.exp(-18 * t)
        elif cue == "collect_complete":
            value = notes(t, [(523.25, 0), (659.25, 0.09), (783.99, 0.18)], 12)
        elif cue in ("bus_start", "bus_depart"):
            hz, slope = (72, 23.3) if cue == "bus_start" else (90, 32.3)
            phase = math.tau * (hz * t + slope * t * t)
            motor = math.sin(phase) + 0.42 * math.sin(2 * phase) + 0.14 * math.sin(3 * phase)
            value = (motor + 0.15 * mellow) * min(1, t / 0.10) * min(1, (duration - t) / 0.24)
            value += 0.30 * tone(t, 330 if cue == "bus_start" else 523.25, 0.025, 22)
        elif cue == "bus_board":
            value = notes(t, [(240, 0), (320, 0.07), (659.25, 0.13)], 22)
        elif cue == "screamer_warning":
            value = notes(t, [(440, 0), (587.33, 0.20)], 9)
            value += 0.12 * notes(t, [(880, 0), (1174.66, 0.20)], 14)
        elif cue == "toxic_warning":
            value = notes(t, [(659.25, 0), (523.25, 0.12), (392, 0.24)], 24)
            value += sum(1.8 * air * math.exp(-20 * (t - onset)) for onset in (0, 0.12, 0.24) if t >= onset)
        elif cue == "burst_warning":
            value = notes(t, [(196, 0), (261.63, 0.14), (349.23, 0.26)], 20) + 0.12 * air * math.exp(-7 * t)
        elif cue == "hound_warning":
            value = notes(t, [(392, 0), (523.25, 0.08)], 18)
        elif cue == "nightfall":
            value = notes(t, [(261.63, 0), (196, 0.20)], 5.5) + 0.16 * tone(t, 392, 0.20, 8)
        else:
            raise ValueError(cue)
        samples.append(value)
    mean = sum(samples) / len(samples)
    for i in range(len(samples)):
        attack = min(1, i / (RATE * 0.004))
        release = min(1, (len(samples) - 1 - i) / (RATE * 0.020))
        samples[i] = (samples[i] - mean) * math.sin(math.pi / 2 * min(attack, release)) ** 2
    gain = PEAK / max(abs(x) for x in samples)
    return [round(x * gain * 32767) for x in samples]


def generate():
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = {
        "source": "Original mathematical synthesis; no recordings, audio models, external audio or Deadly Days assets.",
        "ai_generated_audio": False, "ai_assisted_code": True,
        "generator": "src/features/audio_settings/generate_cues.py",
        "generator_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "format": "mono PCM signed 16-bit little-endian WAV, 44100 Hz, no loops",
        "seed": SEED,
        "processing": "DC reduction, 4 ms attack / 20 ms release sine-squared envelope, peak normalized to 0.55",
        "status": "integrated; headphone and speaker listening pending", "assets": [],
    }
    provenance_path = ROOT / "assets/PROVENANCE.json"
    provenance = json.loads(provenance_path.read_text(encoding="utf-8"))
    for cue, (duration, method) in SPECS.items():
        pcm = synthesize(cue, duration)
        path = OUT / (cue + ".wav")
        with wave.open(str(path), "wb") as output:
            output.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
            output.writeframes(struct.pack("<" + "h" * len(pcm), *pcm))
        relative = path.relative_to(ROOT).as_posix()
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        manifest["assets"].append({
            "cue": cue, "file": relative, "duration_s": duration, "method": method,
            "peak": max(abs(x) for x in pcm) / 32768,
            "rms": math.sqrt(sum(x * x for x in pcm) / len(pcm)) / 32768, "sha256": digest,
        })
        row = next((item for item in provenance["files"] if item["path"] == relative), None)
        if row is None:
            row = {"path": relative}
            provenance["files"].append(row)
        row.update({
            "sha256": digest,
            "origin": "Original mathematical synthesis using Python standard-library DSP; Codex-assisted generator code; no audio model or sampled input",
            "tool": manifest["generator"], "ai_generated_audio": False, "ai_assisted_code": True,
            "license": "No additional license granted",
        })
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    provenance_path.write_text(json.dumps(provenance, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"BH_AUDIO generated {len(SPECS)} original WAVs and registered SHA256 provenance (no playback)")


if __name__ == "__main__":
    generate()
