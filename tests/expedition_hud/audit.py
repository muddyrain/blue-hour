"""Audit C1 delivery scope, UTF-8, resource paths/UIDs and reproducible input hashes."""

import hashlib
import json
from pathlib import Path
import re
import subprocess

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
BASELINE = "92a8a7b2807355192ad9e102ca79c79f24c61152"
PARENT_C1 = "b597a3686626cab4f7f919a064d16dca7f4b38df"
EVIDENCE = ROOT / "docs/evidence/c1-expedition-hud/c1-1"
ALLOWED = ("src/features/expedition_hud/", "assets/ui/c1/", "tests/expedition_hud/",
           "docs/evidence/c1-expedition-hud/", "docs/handoffs/c1-expedition-hud.md")


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT).decode("utf-8").splitlines()


def main():
    changed = set(git("diff", "--name-only", BASELINE))
    changed.update(git("ls-files", "--others", "--exclude-standard"))
    assert all(path.startswith(ALLOWED) for path in changed), sorted(changed)
    files = sorted(path for path in changed if (ROOT / path).is_file())
    inputs = {}
    image_evidence = {}
    for name in files:
        path = ROOT / name
        if path.suffix in {".png", ".jpg"}:
            with Image.open(path) as image:
                assert image.format == ("PNG" if path.suffix == ".png" else "JPEG"), name
                image_evidence[name] = {"size": list(image.size), "format": image.format,
                                        "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
        if path.suffix not in {".gd", ".tscn", ".tres", ".uid", ".py", ".md", ".txt", ".json"}:
            continue
        raw = path.read_bytes()
        content = raw.decode("utf-8")
        assert "\ufffd" not in content and not raw.startswith(b"\xef\xbb\xbf"), name
        assert b"\r" not in raw, f"Expected LF: {name}"
        if name.startswith(("src/", "assets/", "tests/")):
            assert not re.search(r"(?<![A-Za-z0-9_])[A-Za-z]:[\\/]", content), f"Machine path: {name}"
            inputs[name] = hashlib.sha256(raw).hexdigest()
        if path.suffix in {".gd", ".tscn", ".tres"}:
            for relative in re.findall(r'["\']res://([^"\']+)["\']', content):
                # Writable evidence locations are runtime parameters, not resources.
                if relative.startswith(".local/"):
                    continue
                current = ROOT
                for part in Path(relative).parts:
                    assert part in {child.name for child in current.iterdir()}, f"Case/missing: {name}: {relative}"
                    current = current / part
                assert current.exists(), relative
            if path.suffix == ".gd":
                uid_file = path.with_suffix(".gd.uid")
                assert uid_file.is_file(), f"Missing UID: {name}"
                assert re.fullmatch(r"uid://[a-z0-9]+\n", uid_file.read_text(encoding="utf-8")), str(uid_file)
    all_uids = [path.read_text().strip() for path in (ROOT / "src").rglob("*.gd.uid")]
    all_uids += [path.read_text().strip() for path in (ROOT / "tests").rglob("*.gd.uid")]
    assert len(all_uids) == len(set(all_uids)), "Duplicate script resource UID"
    for resolution in ["1280x720", "1440x900"]:
        report = json.loads((EVIDENCE / f"auto-{resolution}.json").read_text())
        assert report["failures"] == 0, resolution
        assert report["window_size"] == [int(value) for value in resolution.split("x")], report["window_size"]
        rendered = json.loads((EVIDENCE / f"render-{resolution}.json").read_text())
        assert rendered["failures"] == 0 and rendered["display"] == "Windows", resolution
        for run in [report, rendered]:
            assert len(run["mixed_sequences"]) == 6, resolution
            assert run["source_sha256_at_start"] == run["source_sha256_at_end"]
            for name, expected in run["source_sha256_at_end"].items():
                assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == expected, name
    desktop = json.loads((EVIDENCE / "desktop-check.json").read_text(encoding="utf-8"))
    assert all(check["passed"] for check in desktop["checks"]), "Desktop check failure"
    for check in desktop["checks"]:
        assert (EVIDENCE / check["image"]).is_file(), check
    result = {"baseline": BASELINE, "parent_c1_commit": PARENT_C1, "scope_passed": True, "utf8_lf_passed": True,
              "resource_paths_and_script_uids_passed": True, "inputs_sha256": inputs,
              "changed_files": files, "desktop_input_verified": True,
              "image_evidence": image_evidence,
              "runtime_input_hashes_match_current_files": True,
              "formal_expedition_integrated": False}
    destination = EVIDENCE / "source-audit.json"
    destination.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"PASS C1 audit: {len(files)} files in allowed scope; UTF-8/LF, resource case/UID, {len(inputs)} source hashes")


if __name__ == "__main__":
    main()
