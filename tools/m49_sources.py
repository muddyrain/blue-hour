"""Retain and restore exact Windows test bytes at their original bound path."""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import socket

ROOT = Path(__file__).resolve().parents[1]
LOCAL = (ROOT / '.local/m49').resolve()


def manifest(folder):
    return {p.relative_to(folder).as_posix(): {'size': p.stat().st_size,
            'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
            for p in sorted(folder.rglob('*')) if p.is_file()}


def idle(profile):
    slots = list(profile.rglob('playable-v1/run.enemy-v1.json'))
    for slot in slots:
        identity = slot.resolve().as_posix().lower()
        port = 49152 + int(hashlib.sha256(identity.encode()).hexdigest()[:8], 16) % 16384
        with socket.socket() as probe:
            probe.bind(('127.0.0.1', port))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('save', 'restore'))
    parser.add_argument('profile', type=Path)
    parser.add_argument('snapshot', type=Path)
    args = parser.parse_args()
    profile, snapshot = args.profile.resolve(), args.snapshot.resolve()
    for path in (profile, snapshot):
        if not path.is_relative_to(LOCAL) or path == LOCAL or path.is_symlink():
            raise RuntimeError('Only this task local isolated directories are allowed')
    if snapshot.is_relative_to(profile) or profile.is_relative_to(snapshot):
        raise RuntimeError('Snapshot and original must be separate directories')
    idle(profile)
    witness = snapshot.with_suffix('.manifest.json')
    if args.action == 'save':
        if snapshot.exists() or witness.exists():
            raise RuntimeError('Retain existing snapshots; select a new name')
        before = manifest(profile)
        shutil.copytree(profile, snapshot)
        if manifest(snapshot) != before:
            raise RuntimeError('Snapshot byte verification failed')
        witness.write_text(json.dumps({'original_bound_profile': str(profile), 'files': before},
                                     indent=2, ensure_ascii=False), encoding='utf-8')
    else:
        saved = json.loads(witness.read_text(encoding='utf-8'))
        if saved['original_bound_profile'] != str(profile) or manifest(snapshot) != saved['files']:
            raise RuntimeError('Original path or retained source bytes do not match')
        # Both absolute targets were checked above against this task's isolated root.
        if profile.exists():
            shutil.rmtree(profile)
        shutil.copytree(snapshot, profile)
        if manifest(profile) != saved['files']:
            raise RuntimeError('Original bound path byte restoration failed')
    print(json.dumps({'action': args.action, 'profile': str(profile), 'snapshot': str(snapshot),
                      'files': len(manifest(profile))}, ensure_ascii=True))


if __name__ == '__main__':
    main()
