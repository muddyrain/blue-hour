"""Offline contracts for original audio; no engine, playback or player saves."""
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import re
import struct
import unittest
import wave

ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / "src/features/audio_settings/generate_cues.py"
spec = importlib.util.spec_from_file_location("audio_generator", MODULE)
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)


class AudioAssets(unittest.TestCase):
    def test_registry_and_provenance(self):
        manifest = json.loads((ROOT / "assets/audio/b1/manifest.json").read_text(encoding="utf-8"))
        provenance = json.loads((ROOT / "assets/PROVENANCE.json").read_text(encoding="utf-8"))
        service = (ROOT / "src/features/audio_settings/audio_service.gd").read_text(encoding="utf-8")
        registered = set(re.findall(r'&"(\w+)": \{"channel"', service))
        self.assertEqual(registered, set(generator.SPECS))
        self.assertEqual(registered, {row["cue"] for row in manifest["assets"]})
        self.assertEqual(manifest["generator_sha256"], hashlib.sha256(MODULE.read_bytes()).hexdigest())
        self.assertFalse(manifest["ai_generated_audio"])
        self.assertTrue(manifest["ai_assisted_code"])
        for asset in manifest["assets"]:
            with self.subTest(cue=asset["cue"]):
                path = ROOT / asset["file"]
                digest = hashlib.sha256(path.read_bytes()).hexdigest()
                self.assertEqual(digest, asset["sha256"])
                rows = [row for row in provenance["files"] if row["path"] == asset["file"]]
                self.assertEqual(len(rows), 1)
                self.assertEqual(rows[0]["sha256"], digest)
                self.assertEqual(rows[0]["tool"], manifest["generator"])
                self.assertFalse(rows[0]["ai_generated_audio"])

    def test_waveforms_and_mix_headroom(self):
        service = (ROOT / "src/features/audio_settings/audio_service.gd").read_text(encoding="utf-8")
        world, ui = [int(re.search(rf"const {key}: int = (\d+)", service)[1])
                     for key in ("WORLD_VOICES", "UI_VOICES")]
        gain = float(re.search(r"const VOICE_GAIN: float = ([\d.]+)", service)[1])
        peak_sum = 0.0
        for cue, (duration, _) in generator.SPECS.items():
            with self.subTest(cue=cue):
                with wave.open(str(ROOT / "assets/audio/b1" / (cue + ".wav")), "rb") as sound:
                    self.assertEqual((sound.getnchannels(), sound.getsampwidth(), sound.getframerate()), (1, 2, 44100))
                    samples = struct.unpack("<" + "h" * sound.getnframes(), sound.readframes(sound.getnframes()))
                self.assertEqual(len(samples), round(duration * 44100))
                self.assertEqual((samples[0], samples[-1]), (0, 0))
                peak = max(abs(x) for x in samples) / 32768
                rms = math.sqrt(sum(x * x for x in samples) / len(samples)) / 32768
                self.assertLessEqual(peak, 0.551)
                self.assertGreater(rms, 0.07)
                self.assertLess(abs(sum(samples) / len(samples) / 32768), 0.01)
                self.assertEqual(list(samples), generator.synthesize(cue, duration))
                peak_sum = max(peak_sum, peak * gain * (world + ui))
        self.assertLess(peak_sum, 10 ** (-1 / 20), "coherent sum keeps at least 1 dB headroom")


if __name__ == "__main__":
    unittest.main()
