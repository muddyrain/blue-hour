"""Native factual journal, v4 migration and ordinary-map regression with isolated progress."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time

from godot import ROOT, LOCK, engine_path
from playtest_m301 import binding as old_binding
from playtest_m302 import lock_file


def binding(source):
    inputs = old_binding(source)
    inputs.update({p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                   for p in (ROOT / 'assets').rglob('*.gdshader')})
    return inputs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', action='store_true')
    parser.add_argument('--suite', choices=('m503', 'm5ux01', 'm5combat02', 'm5combat03'), default='m503')
    parser.add_argument('--seed-progress', type=Path, help='Copy an existing validated v5 fixture into the isolated run')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--size', default='1280x720')
    parser.add_argument('--record', action='store_true')
    parser.add_argument('--fast', action='store_true', help='Use fixed30fps engine time without writing a movie; not a realtimeFPS measurement')
    parser.add_argument('--seed-audio', type=Path, help='Copy an existing verified audio fixture before the first isolated process')
    parser.add_argument('--modes', default='scavenge,market,reopen-scavenge,reopen-market')
    args = parser.parse_args()
    output = args.output.resolve()
    output.relative_to((ROOT / '.local').resolve())
    output.mkdir(parents=True, exist_ok=False)
    exe = Path(engine_path(None)) if args.source else ROOT / 'builds/windows/blue-hour.exe'
    if args.source and exe.name.endswith('_console.exe'):
        exe = exe.with_name(exe.name.replace('_console.exe', '.exe'))
        probe = subprocess.run([str(exe), '--version'], capture_output=True, text=True, timeout=15)
        if probe.returncode or probe.stdout.strip() != LOCK:
            raise RuntimeError('Source GUI version mismatch')
    inputs = binding(args.source)
    progress = output / 'progress/run.json'
    audio = output / 'audio/audio.json'
    if args.seed_audio:
        audio.parent.mkdir(parents=True)
        shutil.copyfile(args.seed_audio, audio)
        (output / 'audio-fixture.json').write_text(json.dumps({'source':str(args.seed_audio.resolve()),'sha256':hashlib.sha256(audio.read_bytes()).hexdigest()},indent=2),encoding='utf-8')
    user = output / 'user'
    user.mkdir()
    env = os.environ.copy()
    env.update(APPDATA=str(user), XDG_DATA_HOME=str(user), PYTHONIOENCODING='utf-8')
    processes = []
    expected = None
    if args.seed_progress:
        progress.parent.mkdir(parents=True)
        shutil.copyfile(args.seed_progress, progress)
        shutil.copyfile(args.seed_progress, progress.with_suffix('.json.bak'))
        expected = args.seed_progress.resolve()
    modes = tuple(args.modes.split(','))
    allowed = ('scavenge', 'market', 'reopen-scavenge', 'reopen-market', 'inspect', 'legacy', 'custom', 'custom-reopen', 'corrupt', 'los-repair', 'los-market', 'los-choice-repair', 'los-choice-market', 'los-range', 'night-repair', 'night-market', 'short-repair', 'short-market', 'abort-night')
    allowed += ('contact-open-repair', 'contact-open-market', 'contact-corner-repair', 'contact-corner-market', 'contact-search-repair', 'contact-search-market')
    if any(mode not in allowed for mode in modes):
        raise RuntimeError('Unknown isolated M503 stage')
    if modes[0] in ('legacy', 'custom', 'custom-reopen', 'corrupt'):
        progress.parent.mkdir(parents=True)
        seed = ROOT / 'tests/fixtures/m5-02/market/saved-run.json'
        shutil.copyfile(seed, progress)
        shutil.copyfile(ROOT / 'tests/fixtures/m5-02/scavenge/saved-run.json', progress.with_suffix('.json.bak'))
        expected = seed
        if modes[0] == 'corrupt':
            progress.write_bytes(b'{M503 invalid primary preserved for explicit backup choice')
    for mode in modes:
        stage = output / mode
        stage.mkdir()
        command = [str(exe), '--rendering-method', 'gl_compatibility', '--resolution', args.size,
                   '--log-file', str(stage / 'engine.log')]
        if args.source:
            command += ['--path', str(ROOT)]
        if args.fast and not args.record:
            command += ['--fixed-fps', '30', '--disable-vsync']
        if args.record and (mode.startswith('contact-') or mode in ('scavenge', 'market', 'los-repair', 'los-market', 'los-choice-repair', 'los-choice-market', 'los-range', 'night-repair', 'night-market', 'short-repair', 'short-market', 'abort-night')):
            command += ['--write-movie', str(stage / 'native-run.avi'), '--fixed-fps', '30', '--disable-vsync']
        command += ['--', '--verify-' + args.suite + '=' + str(stage), '--m402-mode=' + mode,
                    '--bh-progress=' + str(progress), '--bh-audio-settings=' + str(audio)]
        if mode.startswith('contact-'):
            command += ['--show-dev-menu']
        if mode.startswith('los-'):
            command += ['--show-dev-menu', '--bh-los-map=' + ('market_loop' if mode.endswith('market') else 'repair_lane')]
            if mode == 'los-range':
                command += ['--bh-los-case=range']
        if mode.startswith('contact-corner-'):
            command += ['--bh-los-map=' + ('market_loop' if mode.endswith('market') else 'repair_lane')]
        if mode.startswith('short-'):
            command += ['--bh-threat-rehearsal']
        if expected:
            command += ['--m402-expected=' + str(expected)]
        (stage / 'command.json').write_text(json.dumps(command, indent=2), encoding='utf-8')
        held = None
        started = datetime.datetime.now(datetime.timezone.utc).isoformat()
        try:
            with (stage / 'run.txt').open('w', encoding='utf-8') as log:
                process = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, env=env)
                deadline = time.monotonic() + 900
                while process.poll() is None:
                    if not held and (stage / 'hold-lock.request').exists() and not (stage / 'lock-held.json').exists():
                        held = lock_file(progress)
                        (stage / 'lock-held.json').write_text(json.dumps({'held': True, 'utc': datetime.datetime.now(datetime.timezone.utc).isoformat()}), encoding='utf-8')
                    if held and (stage / 'release-lock.request').exists():
                        if not held[0].CloseHandle(held[1]):
                            raise OSError('Cannot release file handle')
                        held = None
                        (stage / 'lock-released.json').write_text(json.dumps({'released': True, 'utc': datetime.datetime.now(datetime.timezone.utc).isoformat()}), encoding='utf-8')
                    text = re.sub(r'\x1b\[[0-9;]*m', '', (stage / 'run.txt').read_text(encoding='utf-8', errors='replace'))
                    if re.search(r'(?m)^(?:SCRIPT ERROR|ERROR):', text) or time.monotonic() > deadline:
                        process.terminate()
                        process.wait(timeout=10)
                        raise RuntimeError('Native proof stopped on error/timeout: ' + str(stage))
                    time.sleep(0.05)
                code = process.returncode
        finally:
            if held:
                held[0].CloseHandle(held[1])
        report_path = stage / 'run-report.json'
        report = json.loads(report_path.read_text(encoding='utf-8')) if report_path.exists() else None
        processes.append({'mode': mode, 'pid': process.pid, 'report_pid': report.get('pid') if report else None,
                          'started_utc': started, 'ended_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'exit_code': code})
        (output / 'processes.json').write_text(json.dumps(processes, indent=2), encoding='utf-8')
        text = re.sub(r'\x1b\[[0-9;]*m', '', (stage / 'run.txt').read_text(encoding='utf-8', errors='replace'))
        if code or not report or report['failures'] or report['pid'] != process.pid or re.search(r'(?m)^(?:SCRIPT ERROR|ERROR|WARNING):', text):
            raise RuntimeError('Native report failed: ' + str(stage))
        for path in (progress, progress.with_suffix('.json.bak'), audio):
            if path.exists():
                shutil.copyfile(path, stage / ('saved-audio.json' if path == audio else 'saved-' + path.name))
        if binding(args.source) != inputs:
            raise RuntimeError('Runtime inputs changed during native proof')
        expected = stage / 'camp.json'
        print(f"PASS M503 {mode}: pid={process.pid}, behavior={report['behavior_checks']}, screenshots={report['capture_checks']}, day={report['state']['day']}, food={report['state']['food']}, cash={report['state']['cash']}, weapons={len(report['state']['weapons'])}", flush=True)
    if len({item['pid'] for item in processes}) != len(modes):
        raise RuntimeError('Expected distinct independent processes')
    (output / 'binding.json').write_text(json.dumps({'inputs': inputs, 'unchanged': binding(args.source) == inputs}, indent=2), encoding='utf-8')


if __name__ == '__main__':
    main()
