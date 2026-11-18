"""Opt-in continuous campaign regression with a real process restart at day six.

python3 tools/check_ten_day.py --godot /home/box/.local/bin/godot --headless
Artifacts and all engine user directories stay under this checkout's .local/.
"""
import argparse
import datetime
import json
import os
from pathlib import Path
import re
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--headless', action='store_true', help='Skip native screenshots explicitly')
    parser.add_argument('--hunger', action='store_true', help='Separate directed three-return starvation control; never part of the ten-day path')
    args = parser.parse_args()
    output = (args.output or ROOT / '.local' / ('ten-day-' + datetime.datetime.now().strftime('%Y%m%d-%H%M%S') + '-' + uuid.uuid4().hex[:8])).resolve()
    if not output.is_relative_to(ROOT / '.local'):
        raise ValueError('Use an isolated project-local output')
    output.mkdir(parents=True, exist_ok=False)
    env = dict(os.environ, DISPLAY=':3', LIBGL_ALWAYS_SOFTWARE='1', BH_TEN_DAY_OUTPUT=str(output))
    for name, directory in {'HOME': 'home', 'APPDATA': 'data', 'XDG_DATA_HOME': 'data',
                            'XDG_CONFIG_HOME': 'config', 'XDG_CACHE_HOME': 'cache',
                            'XDG_STATE_HOME': 'state', 'XDG_RUNTIME_DIR': 'runtime'}.items():
        location = output / directory
        location.mkdir(exist_ok=True)
        env[name] = str(location)
    (output / 'runtime').chmod(0o700)
    version = subprocess.check_output([args.godot, '--version'], env=env, text=True).strip()
    if version != (ROOT / '.godot-version').read_text(encoding='utf8').strip():
        raise ValueError('Pinned engine required: ' + version)
    command = [args.godot, '--path', str(ROOT), '--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy']
    if args.headless:
        command += ['--headless']
    flags = ['--', '--bh-progress=' + str(output / 'run.enemy-v1.json'), '--bh-audio-settings=' + str(output / 'audio.json')]
    rows = []
    for mode in (['import', 'hunger'] if args.hunger else ['import', 'new', 'resume', 'verify']):
        env['BH_TEN_DAY_MODE'] = mode
        invocation = command + (['--headless', '--editor', '--import', '--quit'] if mode == 'import' else ['--script', 'res://tests/campaign_ten_day.gd']) + flags
        started = time.monotonic()
        with (output / (mode + '-console.txt')).open('w', encoding='utf8') as log:
            result = subprocess.run(invocation, env=env, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, timeout=1800)
        text = (output / (mode + '-console.txt')).read_text(encoding='utf8')
        summaries = [json.loads(line.removeprefix('BH_TEN_DAY_SUMMARY ')) for line in text.splitlines() if line.startswith('BH_TEN_DAY_SUMMARY ')]
        passed = result.returncode == 0 and not re.search(r'(?m)^(SCRIPT ERROR|ERROR):', text) and (mode == 'import' or len(summaries) == 1 and summaries[0]['failures'] == 0)
        rows.append({'process': mode, 'exit': result.returncode, 'passed': passed, 'seconds': round(time.monotonic() - started, 3), 'summary': summaries})
        (output / 'processes.json').write_text(json.dumps(rows, indent=2), encoding='utf8')
        print(json.dumps(rows[-1]), flush=True)
        if not passed:
            raise RuntimeError('Continuous path stopped; inspect ' + str(output))
    print('BH_TEN_DAY_OUTPUT ' + str(output), flush=True)


if __name__ == '__main__':
    main()
