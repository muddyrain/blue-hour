"""M8 Mac short-run acceptance: real owners, fresh profiles and exact checkpoint branches."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import sys
import time

from playable_flow import stop_child

ROOT = Path(__file__).resolve().parents[1]


def main():
    if sys.flags.optimize:
        raise RuntimeError("Acceptance requires assertions")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--native', action='store_true')
    parser.add_argument('--movie', action='store_true')
    parser.add_argument('--positive-only', action='store_true')
    args = parser.parse_args()
    engine = subprocess.check_output([args.godot, '--version'], text=True).strip()
    assert engine == (ROOT / '.godot-version').read_text().strip()
    out = args.output.resolve()
    assert out.is_relative_to(ROOT / '.local')
    assert not args.movie or args.native
    out.mkdir(parents=True, exist_ok=False)
    env = dict(os.environ, HOME=str(out / 'home'), APPDATA=str(out / 'user'), XDG_DATA_HOME=str(out / 'user'))
    for name in ['home', 'user']:
        (out / name).mkdir()
    if args.native:
        assert sys.platform == 'darwin'
        guard = out / 'background_guard.dylib'
        subprocess.run(['clang', '-dynamiclib', '-framework', 'AppKit', '-framework', 'Foundation',
                        '-o', str(guard), str(ROOT / 'tools/macos_background.m')], check=True, capture_output=True)
        env['DYLD_INSERT_LIBRARIES'] = str(guard)
    rows = []
    foreground = {'samples': 0, 'pids': []}

    def sample_foreground():
        value = subprocess.check_output(['osascript', '-l', 'JavaScript', '-e',
            'ObjC.import("AppKit"); $.NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier'], text=True, timeout=5)
        pid = int(value.strip())
        foreground['samples'] += 1
        if pid not in foreground['pids']:
            foreground['pids'].append(pid)
        (out / 'foreground.json').write_text(json.dumps(foreground))

    def checkpoint(name):
        target = out / 'checkpoints' / name
        target.mkdir(parents=True)
        for folder in ['home', 'user']:
            shutil.copytree(out / folder, target / folder)

    def restore(name, archive):
        # Synthetic profile only. Restore exact bytes at the SAME absolute binding
        # paths; preserve the previous branch rather than rewriting receipt paths.
        target = out / 'branches' / archive
        target.mkdir(parents=True)
        for folder in ['home', 'user']:
            (out / folder).rename(target / folder)
            shutil.copytree(out / 'checkpoints' / name / folder, out / folder)

    def run(phase):
        flags = ['--flow-output=' + str(out / phase)]
        if phase != 'new-journey':
            flags.append('--bh-rescue-seed=m8-run-sample-01')
        if phase != 'first':
            flags.append('--flow-resume')
        cmd = [args.godot, '--path', str(ROOT), '--audio-driver', 'Dummy', '--rendering-method', 'gl_compatibility']
        cmd += ['--position', '-16000,-16000'] if args.native else ['--headless']
        cmd += ['--script', 'res://tests/campaign_flow.gd', '--', *flags]
        encoder = None
        encoding_log = None
        if args.movie and phase in ['fight', 'victory']:
            with socket.socket() as probe:
                probe.bind(('127.0.0.1', 0))
                port = probe.getsockname()[1]
            encoding_log = (out / (phase + '-encode.txt')).open('w')
            encoder = subprocess.Popen(['ffmpeg', '-hide_banner', '-loglevel', 'warning', '-f', 'rawvideo',
                '-pixel_format', 'rgba', '-video_size', '1280x720', '-framerate', '30', '-i', f'tcp://127.0.0.1:{port}?listen=1',
                '-an', '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '22', '-pix_fmt', 'yuv420p',
                '-movflags', '+faststart', str(out / (phase + '-1x.mp4'))], stdout=encoding_log, stderr=encoding_log)
            flag = cmd.index('--')
            cmd[flag:flag] = ['--fixed-fps', '30', '--max-fps', '30', '--disable-vsync']
            cmd.append('--flow-stream=' + str(port))
            time.sleep(.3)
        started = time.monotonic()
        proc = None
        try:
            with (out / (phase + '.txt')).open('w') as log:
                if args.native:
                    sample_foreground()
                proc = subprocess.Popen(cmd, cwd=ROOT, env=env, stdout=log, stderr=log)
                while proc.poll() is None:
                    if time.monotonic() - started > 300:
                        raise subprocess.TimeoutExpired(cmd, 300)
                    if args.native:
                        sample_foreground()
                        assert proc.pid not in foreground['pids'], 'background renderer became foreground'
                    time.sleep(.2)
            if encoder:
                assert encoder.wait(timeout=30) == 0
            console = (out / (phase + '.txt')).read_text()
            assert proc.returncode == 0 and not re.search(r'(?m)^(SCRIPT ERROR|ERROR):', console), (phase, proc.returncode, console[-1500:])
            result = json.loads((out / phase / 'report.json').read_text())
            assert result['failures'] == 0, (phase, result['checks'])
            if args.native:
                assert result['pid'] not in foreground['pids']
            row = dict(phase=phase, checks=len(result['checks']), pid=result['pid'], wall_seconds=round(time.monotonic()-started, 3))
            rows.append(row)
            print(row, flush=True)
        finally:
            stop_child(proc)
            stop_child(encoder)
            if encoding_log:
                encoding_log.close()

    run('first')
    checkpoint('windup')
    run('fight')
    checkpoint('defeated')
    run('victory')
    run('readback')
    checkpoint('victory')
    if not args.positive_only:
        restore('windup', 'victory-original')
        run('early')
        restore('windup', 'early-original')
        run('stationary')
        restore('defeated', 'stationary-original')
        run('wipe')
        run('defeat-readback')
        restore('victory', 'wipe-original')
        run('new-journey')
        restore('victory', 'new-journey-original')
    result = dict(status='PASS', engine=engine, native=args.native, movie=args.movie, phases=rows,
                  checkpoint_reuse='synthetic exact bytes at original absolute binding paths; all branches preserved',
                  physical_input='NOT_VERIFIED', display_fps='NOT_MEASURED', Windows='NOT_RUN_CURRENT_MAC_SCOPE')
    (out / 'summary.json').write_text(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
