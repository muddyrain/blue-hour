"""Exercise two real isolated Windows processes against one original progress path."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--profile', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if not output.is_relative_to(ROOT / '.local/m49'):
        parser.error('Use this task isolated output')
    output.mkdir(parents=True, exist_ok=True)
    common = [sys.executable, str(ROOT / 'tools/m49_flow.py'), '--output', str(output),
              '--profile', str(args.profile.resolve()), '--godot', args.godot, '--resume',
              '--script', 'm49_runtime_flow.gd', '--timeout', '180']
    marker = output / 'writer-owner/writer-owner-ready.json'
    release = output / 'writer-owner/release-owner'
    with (output / 'writer-owner-runner.txt').open('xb') as log:
        owner = subprocess.Popen(common + ['writer-owner', '--runtime-case=writer-owner'],
                                 cwd=ROOT, stdout=log, stderr=log)
        try:
            deadline = time.monotonic() + 90
            while not marker.exists():
                if owner.poll() is not None or time.monotonic() > deadline:
                    raise RuntimeError('Owner did not reach its real writer boundary; retain log')
                time.sleep(0.05)
            contender = subprocess.run(common + ['writer-contender', '--runtime-case=writer-contender'],
                                       cwd=ROOT, capture_output=True, timeout=90)
            (output / 'writer-contender-runner.txt').write_bytes(contender.stdout + contender.stderr)
            if contender.returncode:
                raise RuntimeError('Contender verification failed; retain both processes evidence')
        finally:
            # Only this test-created owner is signalled; its native driver releases normally.
            release.parent.mkdir(parents=True, exist_ok=True)
            release.touch(exist_ok=False)
            owner.wait(timeout=120)
    if owner.returncode:
        raise RuntimeError('Owner did not exit successfully')
    print(json.dumps({'owner': owner.pid, 'scope': 'two native isolated desktops, same canonical writer',
                      'status': 'PASS'}, indent=2))


if __name__ == '__main__':
    main()
