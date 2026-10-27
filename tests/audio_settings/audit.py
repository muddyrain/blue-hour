"""Audit B1's ownership boundary, portable references and text/asset identities."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OWNED = ("src/features/audio_settings/", "assets/audio/b1/", "tests/audio_settings/",
         "docs/evidence/b1-audio-settings/", "docs/handoffs/b1-audio-settings.md")


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT).decode("utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", default="92a8a7b2807355192ad9e102ca79c79f24c61152")
    parser.add_argument("--output", required=True, help="JSON evidence inside this worktree")
    args = parser.parse_args()
    output = Path(args.output).resolve()
    output.relative_to(ROOT)
    baseline = git("rev-parse", args.base + "^{commit}").strip()
    subprocess.run(["git", "merge-base", "--is-ancestor", baseline, "HEAD"], cwd=ROOT, check=True)
    changed = set(git("diff", "--name-only", "-z", baseline).split("\0"))
    changed.update(git("ls-files", "--others", "--exclude-standard", "-z").split("\0"))
    changed.discard("")
    assert all(path.startswith(OWNED) for path in changed), sorted(changed)
    tracked = git("ls-files", "-z").split("\0")
    files = sorted({path for path in tracked + list(changed) if path and (ROOT / path).is_file()})
    uids = {}
    for relative in files:
        path = ROOT / relative
        if path.suffix not in (".uid", ".import"):
            continue
        text = path.read_text(encoding="utf-8")
        for uid in re.findall(r"uid://[a-z0-9]+", text):
            assert uid not in uids, (uid, relative, uids.get(uid))
            uids[uid] = relative
    hashes = {}
    for relative in sorted(changed):
        path = ROOT / relative
        if path == output or relative.startswith("docs/evidence/"):
            continue
        data = path.read_bytes()
        hashes[relative] = hashlib.sha256(data).hexdigest()
        if path.suffix == ".wav":
            assert data[:4] == b"RIFF" and data[8:12] == b"WAVE"
            continue
        text = data.decode("utf-8")
        assert b"\r" not in data and "\ufffd" not in text and not data.startswith(b"\xef\xbb\xbf"), relative
        if not relative.startswith("docs/"):
            assert not re.search(r"(?<![A-Za-z])[A-Za-z]:[/\\]", text), relative
        for target in re.findall(r'res://([a-zA-Z0-9_./-]+)', text):
            if ".godot/" in target or target in (".local/", "audio.json") or "not_present" in target:
                continue  # generated imports, deliberate negative fixtures and data directory
            parts = target.rstrip("/").split("/")
            current = ROOT
            for part in parts:
                assert part in [entry.name for entry in current.iterdir()], (relative, target)
                current /= part
    subprocess.run(["git", "diff", "--check", baseline], cwd=ROOT, check=True)
    report = {"baseline": baseline, "branch": git("branch", "--show-current").strip(),
              "root": str(ROOT), "owned_paths": sorted(changed), "shared_files_unchanged": True,
              "utf8_lf_and_resource_case": "pass", "unique_import_and_script_uids": len(uids),
              "runtime_machine_paths": "none", "sha256": hashes}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"PASS B1 ownership / baseline ancestry / UTF-8 LF / paths / UIDs: {output}")


if __name__ == "__main__":
    main()
