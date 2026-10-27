"""Pinned Godot entry point; Python 3.10+, standard library only."""

import argparse
import datetime
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
LOCK = (ROOT / ".godot-version").read_text(encoding="utf-8").strip()
TEMPLATE_VERSION = ".".join(LOCK.split(".")[:4])
LOGS = ROOT / ".local" / "validation"


def engine_path(explicit):
    local = ROOT / ".local" / "toolchain.json"
    config = json.loads(local.read_text(encoding="utf-8-sig")) if local.exists() else {}
    value = explicit or os.environ.get("GODOT_BIN") or config.get("godot")
    value = value or shutil.which("godot") or shutil.which("godot4")
    if not value or not Path(value).is_file():
        raise RuntimeError("Godot not found. Pass --godot PATH, set GODOT_BIN, or .local/toolchain.json.")
    result = subprocess.run([value, "--version"], capture_output=True, text=True, timeout=15)
    actual = result.stdout.strip()
    if result.returncode or actual != LOCK:
        raise RuntimeError(f"Engine mismatch: expected {LOCK}; got {actual!r} (exit {result.returncode}).")
    return str(Path(value).resolve())


def invoke(engine, label, args, timeout=120):
    LOGS.mkdir(parents=True, exist_ok=True)
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    log_path = LOGS / f"{stamp}-{label}.txt"
    args = list(args)
    driver = ["--audio-driver", "Dummy"] if "--headless" in args else []
    if "--script" in args:
        if "--" not in args:
            args.append("--")
        args.append("--bh-audio-settings=" + str(LOGS / (stamp + "-audio.json")))
        args.append("--bh-progress=" + str(LOGS / (stamp + "-progress") / "run.json"))
    engine_log = LOGS / f"{stamp}-{label}-engine.log"
    command = [engine, "--path", str(ROOT), "--language", "en", "--log-file", str(engine_log), *driver, *args]
    env = os.environ.copy()
    if "--headless" in args and label != "export":
        user_root = ROOT / ".local" / ("c1-user" if label.startswith("hud-") else "check-user")
        user_root.mkdir(parents=True, exist_ok=True)
        env["APPDATA"] = str(user_root)
        env["XDG_DATA_HOME"] = str(user_root)
    print(f"[{label}] {' '.join(args)}", flush=True)
    with log_path.open("w", encoding="utf-8") as output:
        try:
            result = subprocess.run(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT,
                                    timeout=timeout, env=env)
        except subprocess.TimeoutExpired as error:
            raise RuntimeError(f"{label} timed out after {timeout}s. Log: {log_path}") from error
    text = log_path.read_text(encoding="utf-8", errors="replace")
    print(text, end="", flush=True)
    plain = re.sub(r"\x1b\[[0-9;]*m", "", text)
    if result.returncode or re.search(r"(?m)^(?:SCRIPT ERROR|ERROR):", plain):
        raise RuntimeError(f"{label} failed (exit {result.returncode}). Log: {log_path}")
    print(f"PASS {label}; log: {log_path.relative_to(ROOT)}", flush=True)


def templates_path():
    if sys.platform == "win32":
        base = Path(os.environ["APPDATA"]) / "Godot"
    elif sys.platform == "darwin":
        base = Path.home() / "Library" / "Application Support" / "Godot"
    else:
        base = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share")) / "godot"
    return base / "export_templates" / TEMPLATE_VERSION


def require_templates():
    directory = templates_path()
    names = ("windows_debug_x86_64.exe", "windows_release_x86_64.exe")
    missing = [name for name in names if not (directory / name).is_file()]
    if missing:
        raise RuntimeError(f"Missing {TEMPLATE_VERSION} Windows templates in {directory}: {', '.join(missing)}")
    print(f"Templates present: {TEMPLATE_VERSION} (debug + release x86_64)", flush=True)
    return directory


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("doctor", "check", "run", "export"))
    parser.add_argument("--godot", help="Godot executable; paths with spaces are supported")
    args = parser.parse_args()
    try:
        engine = engine_path(args.godot)
        print(f"Engine: {LOCK}", flush=True)
        if args.action == "doctor":
            print(f"Executable: {engine}")
            require_templates()
        elif args.action == "run":
            invoke(engine, "run", ["--rendering-method", "gl_compatibility"], timeout=None)
        else:
            invoke(engine, "import", ["--headless", "--editor", "--import"])
            invoke(engine, "smoke", ["--headless", "--script", "res://tests/smoke.gd"])
            invoke(engine, "presentation", ["--headless", "--script", "res://tests/presentation.gd"])
            invoke(engine, "combat-time", ["--headless", "--script", "res://tests/combat_time.gd"])
            audio_tests = LOGS / ("audio-tests-" + datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f"))
            invoke(engine, "audio-exercise", ["--headless", "--script", "res://tests/audio_settings/check.gd", "--",
                   "--b1-test-dir=" + str(audio_tests), "--b1-test-mode=exercise"])
            invoke(engine, "audio-restart", ["--headless", "--script", "res://tests/audio_settings/check.gd", "--",
                   "--b1-test-dir=" + str(audio_tests), "--b1-test-mode=restart"])
            invoke(engine, "integration", ["--headless", "--script", "res://tests/integration.gd"])
            invoke(engine, "persistence", ["--headless", "--script", "res://tests/persistence.gd"])
            invoke(engine, "camp-food", ["--headless", "--script", "res://tests/camp_food.gd"])
            invoke(engine, "weapons", ["--headless", "--script", "res://tests/weapon_inventory.gd"])
            invoke(engine, "survivors", ["--headless", "--script", "res://tests/survivors.gd"])
            invoke(engine, "survivor-growth", ["--headless", "--script", "res://tests/survivor_growth.gd"])
            invoke(engine, "production-ui", ["--headless", "--script", "res://tests/production_ui.gd"])
            invoke(engine, "street-content", ["--headless", "--script", "res://tests/street_content.gd"])
            invoke(engine, "character-identity", ["--headless", "--script", "res://tests/character_identity.gd"])
            invoke(engine, "combat-los", ["--headless", "--script", "res://tests/combat_los.gd"])
            invoke(engine, "night-pressure", ["--headless", "--script", "res://tests/night_pressure.gd"])
            invoke(engine, "expedition-commands", ["--headless", "--script", "res://tests/expedition_commands.gd"])
            invoke(engine, "contact-damage", ["--headless", "--script", "res://tests/contact_damage.gd"])
            invoke(engine, "market-exposure", ["--headless", "--script", "res://tests/market_exposure.gd"])
            invoke(engine, "navigation-nearest", ["--headless", "--script", "res://tests/navigation_nearest.gd"])
            for size in ("1280x720", "1024x640"):
                invoke(engine, "hud-" + size, ["--headless", "--script", "res://tests/expedition_hud/check.gd", "--",
                       "--c1-resolution=" + size, "--c1-report=" + str(LOGS / ("hud-" + size + ".json"))])
            for validator in ("tools/validate_assets.py", "tests/audio_settings/check_runner.py", "tools/check_persistence_lock.py"):
                validation = subprocess.run([sys.executable, str(ROOT / validator)], cwd=ROOT)
                if validation.returncode:
                    raise RuntimeError(validator + " failed")
            if args.action == "export":
                require_templates()
                output = ROOT / "builds" / "windows" / "blue-hour.exe"
                output.parent.mkdir(parents=True, exist_ok=True)
                invoke(engine, "export", ["--headless", "--export-release", "Windows Desktop", str(output)])
                if not output.is_file() or not output.with_suffix(".pck").is_file():
                    raise RuntimeError("Export returned without both EXE and PCK.")
                print(f"Exported: {output.relative_to(ROOT)} (requires adjacent PCK)")
    except (RuntimeError, OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
