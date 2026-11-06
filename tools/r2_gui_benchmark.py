"""Replay the full original Main callbacks against fixed synthetic 47-building checkpoints."""
import argparse
import json
import os
from pathlib import Path
import re
import statistics
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    assert not sys.flags.optimize
    assert subprocess.check_output([args.godot, '--version'], text=True).strip() == (ROOT / '.godot-version').read_text().strip()
    source, output = args.source.resolve(), args.output.resolve()
    assert source.is_relative_to(ROOT / '.local') and output.is_relative_to(ROOT / '.local') and not output.exists()
    output.mkdir(parents=True)
    rows = []
    for phase in ('suspend', 'return'):
        for repeat in range(3):
            run = output / f'{phase}-{repeat + 1}'
            run.mkdir()
            env = dict(os.environ, APPDATA=str(run / 'user'), XDG_DATA_HOME=str(run / 'user'))
            cmd = [args.godot, '--headless', '--path', str(ROOT), '--audio-driver', 'Dummy', '--script', 'res://tests/r2_gui_replay.gd', '--', '--bench-source=' + source.as_posix(), '--bench-phase=' + phase, '--flow-resume', '--flow-output=' + (run / 'report').as_posix()]
            result = subprocess.run(cmd, cwd=ROOT, env=env, capture_output=True, text=True, encoding='utf8', timeout=180)
            (run / 'engine.log').write_text(result.stdout + result.stderr, encoding='utf8')
            assert result.returncode == 0 and not re.search(r'(?m)^(?:SCRIPT ERROR|ERROR):', result.stdout + result.stderr), run
            profile = json.loads((run / 'report/profile.json').read_text('utf8'))
            assert profile['error'] == 0 and profile['failures'] == 0, profile
            rows.append(profile)
            print(phase, repeat + 1, profile['actual_sync_usec'] / 1000, flush=True)
    summary = {}
    for phase in ('suspend', 'return'):
        chosen = [r for r in rows if r['metadata']['phase'] == phase]
        assert len({r['metadata']['request_hash'] for r in chosen}) == 1
        assert len({r['final_record_hash'] for r in chosen}) == 1
        times = [r['actual_sync_usec'] / 1000 for r in chosen]
        summary[phase] = dict(min_ms=min(times), median_ms=statistics.median(times), max_ms=max(times), request_hash=chosen[0]['metadata']['request_hash'], final_record_hash=chosen[0]['final_record_hash'], all_under_500_ms=max(times) <= 500)
    (output / 'summary.json').write_text(json.dumps(summary, indent=2), encoding='utf8')

if __name__ == '__main__':
    main()
