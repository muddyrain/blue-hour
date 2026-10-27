"""Prelocked native A/B trials, one isolated existing v5 per process."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
from godot import ROOT, engine_path
from playtest_m503 import binding


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', action='store_true')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--size', default='1280x720')
    parser.add_argument('--cases', default='a-hold,b-hold,b-avoid,b-avoid-ui')
    parser.add_argument('--seeds', default='3103,4103,5103,6103,7103')
    parser.add_argument('--record', action='store_true', help='Record seed5103 of a-hold,b-hold and b-avoid-ui')
    args = parser.parse_args()
    output = args.output.resolve()
    output.relative_to((ROOT / '.local').resolve())
    output.mkdir(parents=True, exist_ok=False)
    source = ROOT / 'tests/fixtures/m5-combat-02/normal/market/saved-run.json'
    audio_source = ROOT / 'tests/fixtures/m5-combat-02/normal/market/saved-audio.json'
    exe = Path(engine_path(None)) if args.source else ROOT / 'builds/windows/blue-hour.exe'
    if args.source and exe.name.endswith('_console.exe'):
        exe = exe.with_name(exe.name.replace('_console.exe', '.exe'))
    inputs = binding(args.source)
    rows = []
    seeds = list(map(int, args.seeds.split(',')))
    assert set(seeds) <= {3103, 4103, 5103, 6103, 7103}
    for case in args.cases.split(','):
        assert case in ('a-hold', 'b-hold', 'b-avoid', 'b-avoid-ui')
        for seed in ([5103] if case.endswith('-ui') else seeds):
            stage = output / (case + '-' + str(seed))
            stage.mkdir()
            progress = stage / 'progress/run.json'
            progress.parent.mkdir()
            shutil.copyfile(source, progress)
            shutil.copyfile(source, progress.with_suffix('.json.bak'))
            audio = stage / 'audio.json'
            shutil.copyfile(audio_source, audio)
            user = stage / 'user'
            user.mkdir()
            free_before = shutil.disk_usage(ROOT).free
            # Godot warns conservatively below10GiB. Preserve that exact warning;
            # never confuse it with gameplay warnings or silently drop evidence.
            if free_before < 2 * 1024**3:
                raise RuntimeError('Insufficient2GiB recording reserve; originals are preserved')
            command = [str(exe), '--rendering-method', 'gl_compatibility', '--resolution', args.size,
                       '--fixed-fps', '30', '--disable-vsync', '--log-file', str(stage / 'engine.log')]
            if args.source:
                command += ['--path', str(ROOT)]
            if args.record and seed == 5103 and case in ('a-hold', 'b-hold', 'b-avoid-ui'):
                command += ['--write-movie', str(stage / 'native-run.avi')]
            command += ['--', '--verify-m5combat03=' + str(stage), '--m402-mode=ab-' + case,
                        '--ab-seed=' + str(seed), '--bh-progress=' + str(progress),
                        '--bh-audio-settings=' + str(audio)]
            (stage / 'command.json').write_text(json.dumps(command, indent=2) + '\n', encoding='utf-8')
            env = dict(os.environ, APPDATA=str(user), XDG_DATA_HOME=str(user), PYTHONIOENCODING='utf-8')
            start = datetime.datetime.now(datetime.timezone.utc).isoformat()
            with (stage / 'run.txt').open('w', encoding='utf-8') as log:
                result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, env=env, timeout=600)
            report = json.loads((stage / 'run-report.json').read_text(encoding='utf-8'))
            text = re.sub(r'\x1b\[[0-9;]*m', '', (stage / 'run.txt').read_text(encoding='utf-8', errors='replace'))
            warnings = re.findall(r'(?m)^WARNING:.*$', text)
            unexpected = [w for w in warnings if not re.fullmatch(r'WARNING: Current available space on disk is low \([0-9.]+ GiB\)\. MovieWriter will fail during movie recording if the disk runs out of available space\.', w)]
            assert result.returncode == 0 and not report['failures'] and not unexpected
            assert not re.search(r'(?m)^(?:SCRIPT ERROR|ERROR):', text)
            assert inputs == binding(args.source), 'Runtime inputs changed'
            for p in (progress, progress.with_suffix('.json.bak'), audio):
                if p.exists():
                    shutil.copyfile(p, stage / ('saved-audio.json' if p == audio else 'saved-' + p.name))
            trial = json.loads((stage / 'market-ab.json').read_text(encoding='utf-8'))
            row = {'case': case, 'seed': seed, 'pid': report['pid'], 'exit_code': result.returncode,
                   'started_utc': start, 'ended_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                   'behavior_checks': report['behavior_checks'], 'captures': report['capture_checks'],
                   'health': trial['report']['health'], 'warnings': warnings,
                   'disk_free_before': free_before, 'disk_free_after': shutil.disk_usage(ROOT).free}
            rows.append(row)
            (output / 'processes.json').write_text(json.dumps({'processes': rows, 'binding': inputs}, indent=2) + '\n', encoding='utf-8')
            print('PASS native A/B', case, seed, 'pid', row['pid'], 'health', row['health'], 'warnings', len(warnings), flush=True)
    (output / 'binding.json').write_text(json.dumps({'inputs': inputs, 'unchanged': inputs == binding(args.source)}, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
