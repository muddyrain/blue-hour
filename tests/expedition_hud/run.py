"""C1-only runner: pinned engine, child-process user data and explicit scene/log paths."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
LOCAL = ROOT / ".local"
EVIDENCE = ROOT / "docs/evidence/c1-expedition-hud"
PREVIEW = "res://src/features/expedition_hud/preview.tscn"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["check", "preview", "capture"])
    parser.add_argument("--godot", help="Pinned engine executable, or use .local/toolchain.json")
    parser.add_argument("--resolution", choices=["1280x720", "1024x640", "1440x900"], default="1280x720")
    parser.add_argument("--sample", type=int, choices=range(6), default=0)
    parser.add_argument("--evidence-subdir", default="c1-1", help="Relative folder inside C1 evidence; original C1 records stay intact")
    args = parser.parse_args()
    evidence = (EVIDENCE / args.evidence_subdir).resolve()
    if not evidence.is_relative_to(EVIDENCE.resolve()):
        parser.error("Evidence folder must stay inside C1 evidence.")
    config = LOCAL / "toolchain.json"
    configured = json.loads(config.read_text(encoding="utf-8-sig")) if config.exists() else {}
    engine = Path(args.godot or os.environ.get("GODOT_BIN") or configured.get("godot", ""))
    if not engine.is_file():
        parser.error("Pass --godot or configure .local/toolchain.json with the pinned engine.")
    engine = engine.resolve()
    env = os.environ.copy()
    # Godot's Windows user data base is APPDATA. Keep even the shared check's
    # implicit engine log local; no global environment or project config edits.
    env["APPDATA"] = str(LOCAL / "c1-user")
    env["XDG_DATA_HOME"] = str(LOCAL / "c1-user")
    env["XDG_CONFIG_HOME"] = str(LOCAL / "c1-user/config")
    env["XDG_CACHE_HOME"] = str(LOCAL / "c1-user/cache")
    env["GODOT_BIN"] = str(engine)
    for path in [LOCAL / "c1-logs", LOCAL / "c1-preview", LOCAL / "c1-user", evidence]:
        path.mkdir(parents=True, exist_ok=True)
    version = subprocess.check_output([str(engine), "--version"], text=True, env=env).strip()
    expected = (ROOT / ".godot-version").read_text(encoding="utf-8").strip()
    if version != expected:
        raise RuntimeError(f"Engine mismatch: {version!r} != {expected!r}")
    common = [str(engine), "--path", str(ROOT), "--audio-driver", "Dummy", "--language", "en"]

    def run(label, command, timeout=180):
        result = subprocess.run(command, cwd=ROOT, env=env, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=timeout,
                                creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
        output = result.stdout.decode("utf-8", errors="strict")
        output = re.sub(r"\x1b\[[0-9;]*m", "", output)
        output = re.sub(r"\r+\n", "\n", output)
        clean = output.replace(str(ROOT), "<C1>").replace(str(ROOT).replace("\\", "/"), "<C1>")
        clean = clean.replace(str(engine), "<PINNED_GODOT>")
        clean = "\n".join(line.rstrip() for line in clean.splitlines()) + "\n"
        (evidence / f"{label}.txt").write_text(clean, encoding="utf-8", newline="\n")
        print(clean, end="", flush=True)
        if result.returncode or re.search(r"(?m)^(SCRIPT ERROR|ERROR|FAIL):", output):
            raise RuntimeError(f"{label} failed, exit={result.returncode}")

    if args.action == "check":
        # Preserve the shared entry point and its real result, without patching it.
        run("project-check", [sys.executable, "tools/godot.py", "check"])
        for resolution in ["1280x720", "1440x900"]:
            run(f"auto-{resolution}", common + ["--headless", "--resolution", resolution,
                "--log-file", str(LOCAL / f"c1-logs/auto-{resolution}.log"),
                "--script", "res://tests/expedition_hud/check.gd", "--",
                f"--c1-resolution={resolution}",
                f"--c1-report={evidence / ('auto-' + resolution + '.json')}"])
    elif args.action == "preview":
        # This action intentionally opens an interactive window; never part of check.
        subprocess.run(common + ["--resolution", args.resolution, "--windowed",
            "--log-file", str(LOCAL / "c1-logs/preview.log"), PREVIEW, "--",
            f"--c1-sample={args.sample}"], cwd=ROOT, env=env, check=True)
    else:
        run(f"render-{args.resolution}", common + ["--resolution", args.resolution, "--windowed",
            "--log-file", str(LOCAL / f"c1-logs/render-{args.resolution}.log"),
            "--script", "res://tests/expedition_hud/check.gd", "--",
            f"--c1-resolution={args.resolution}",
            f"--c1-report={evidence / ('render-' + args.resolution + '.json')}",
            f"--c1-capture={evidence}"])


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, subprocess.SubprocessError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        sys.exit(1)
