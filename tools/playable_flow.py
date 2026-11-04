"""Isolated daily journey + suspend/new-PID acceptance; optional macOS background movie.

Uses real viewport controls and existing business intentions. Never OS input.
The movie accelerates simulation, and is not a performance/physical-input test.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import socket
import time
import sys
import signal

if sys.flags.optimize:
    raise RuntimeError("Optimized Python is prohibited for acceptance gates")

ROOT = Path(__file__).resolve().parents[1]


def stop_application(folder, project):
    """Stop only the PID published by this fresh run, after checking its command."""
    pid_file = folder / 'pid.json'
    # Parse failures may precede the script PID marker. The two fresh absolute
    # arguments identify only this launch; recheck ownership before each signal.
    if pid_file.exists():
        candidates = [int(json.loads(pid_file.read_text())['pid'])]
    else:
        table = subprocess.check_output(['ps', '-axo', 'pid=,command='], text=True)
        candidates = [int(line.split(None, 1)[0]) for line in table.splitlines()
                      if str(project) in line and '--flow-output=' + str(folder) in line]
    for pid in candidates:
        for sig in [signal.SIGTERM, signal.SIGKILL]:
            process = subprocess.run(['ps', '-p', str(pid), '-o', 'command='], capture_output=True, text=True)
            if process.returncode or str(project) not in process.stdout or '--flow-output=' + str(folder) not in process.stdout:
                break
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                break
            for _ in range(20):
                time.sleep(0.05)
                if subprocess.run(['ps', '-p', str(pid)], capture_output=True).returncode:
                    break


def stop_child(process):
    if process is not None and process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=3)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--native-movie', action='store_true')
    parser.add_argument('--scenario', choices=['rogue', 'fixed'], default='rogue')
    args = parser.parse_args()
    version = subprocess.check_output([args.godot, '--version'], text=True).strip()
    assert version == (ROOT / '.godot-version').read_text().strip()
    output = args.output.resolve()
    assert output.is_relative_to(ROOT / '.local'), 'Only a fresh isolated .local directory'
    output.mkdir(parents=True, exist_ok=False)
    env = dict(os.environ, HOME=str(output / 'home'), APPDATA=str(output / 'user'), XDG_DATA_HOME=str(output / 'user'))
    project = ROOT
    if args.native_movie:
        assert os.uname().sysname == 'Darwin', 'Native background launcher is macOS only'
        project = output / 'background-project'
        project.mkdir()
        for name in ['src', 'assets', 'tests', '.godot']:
            (project / name).symlink_to(ROOT / name, target_is_directory=True)
        # Only window flags differ; source/resources are the same files, never copies.
        (project / 'project.godot').write_text((ROOT / 'project.godot').read_text().replace(
            '[display]', '[display]\nwindow/size/no_focus=true\nwindow/size/mode=1'), encoding='utf-8')
    reports = []
    phases = ['first', 'restore', 'second', 'third', 'fourth', 'final'] if args.scenario == 'rogue' else ['first', 'resume']
    for phase in phases:
        folder = output / phase
        flags = ['--flow-output=' + str(folder)] + (['--flow-resume'] if phase != 'first' else [])
        if args.scenario == 'rogue':
            flags += ['--bh-rescue-seed=rogue-sample-008']
        else:
            flags += ['--flow-fixed', '--bh-enemy-trial', '--bh-safe-suspend', '--bh-camp-prototype', '--bh-progress=' + str(output / 'fixed/run.enemy-v1.json')]
        encoder = None
        encoding_log = None
        try:
            if args.native_movie and phase == ('second' if args.scenario == 'rogue' else 'first'):
                with socket.socket() as probe:
                    probe.bind(('127.0.0.1', 0))
                    port = probe.getsockname()[1]
                flags += ['--flow-stream=' + str(port)]
                encoding_log = (output / 'encoding.txt').open('xb')
                encoder = subprocess.Popen(['ffmpeg', '-hide_banner', '-loglevel', 'warning', '-f', 'rawvideo',
                    '-pixel_format', 'rgba', '-video_size', '1280x720', '-framerate', '30', '-i', f'tcp://127.0.0.1:{port}?listen=1',
                    '-an', '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '23', '-pix_fmt', 'yuv420p',
                    '-movflags', '+faststart', str(output / 'playable-flow.mp4')], stdout=encoding_log, stderr=encoding_log)
                time.sleep(0.3)
            command = [args.godot, '--path', str(project), '--rendering-method', 'gl_compatibility',
                       '--audio-driver', 'Dummy', '--script', 'res://tests/rogue_flow.gd' if args.scenario == 'rogue' else 'res://tests/playable_flow.gd', '--', *flags]
            stdout = output / (phase + '.txt')
            stderr = output / (phase + '-error.txt')
            if args.native_movie:
                command = ['/usr/bin/open', '-W', '-g', '-j', '-n', '-a', str(Path(args.godot).parents[2]),
                           '--stdout', str(stdout), '--stderr', str(stderr), '--env', 'HOME=' + env['HOME'],
                           '--env', 'APPDATA=' + env['APPDATA'], '--env', 'XDG_DATA_HOME=' + env['XDG_DATA_HOME'],
                           '--args', *command[1:]]
                subprocess.run(command, cwd=ROOT, env=env, check=True, timeout=420)
            else:
                command.insert(1, '--headless')
                with stdout.open('xb') as log:
                    subprocess.run(command, cwd=ROOT, env=env, stdout=log, stderr=log, check=True, timeout=300)
            if encoder:
                assert encoder.wait(timeout=45) == 0, 'encoder failed'
        except BaseException:
            if args.native_movie:
                stop_application(folder, project)
            raise
        finally:
            stop_child(encoder)
            if encoding_log is not None:
                encoding_log.close()
        console = stdout.read_text(errors='replace') + (stderr.read_text(errors='replace') if stderr.exists() else '')
        assert not re.search(r'(?m)^(SCRIPT ERROR|ERROR):', console), console[-3000:]
        result = json.loads((folder / 'report.json').read_text())
        assert result['failures'] == 0, result['checks']
        reports.append({'phase': phase, 'checks': len(result['checks']), 'pid': result['pid'], 'status': 'PASS'})
        print(phase, reports[-1], flush=True)
    (output / 'summary.json').write_text(json.dumps({'status': 'PASS', 'reports': reports,
        'native_movie': args.native_movie, 'scenario':args.scenario, 'engine': version, 'physical_input': 'NOT_TESTED',
        'display_FPS': 'NOT_MEASURED', 'Windows': 'NOT_RUN_CURRENT_MAC_SCOPE'}, indent=2))


if __name__ == '__main__':
    main()
