"""M15 ordinary-entry acceptance in isolated progress; never sends OS input."""
import argparse
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--seed', required=True)
    parser.add_argument('--type', choices=['supply', 'equipment', 'rescue', 'airdrop'], required=True)
    parser.add_argument('--size', choices=['small', 'medium', 'large'], default='medium')
    parser.add_argument('--native', action='store_true')
    parser.add_argument('--preview', action='store_true')
    parser.add_argument('--movie', action='store_true')
    parser.add_argument('--direct', action='store_true')
    args = parser.parse_args()
    assert not sys.flags.optimize and (not args.movie or args.native)
    assert subprocess.check_output([args.godot, '--version'], text=True).strip() == (ROOT / '.godot-version').read_text().strip()
    out = args.output.resolve()
    assert out.is_relative_to(ROOT / '.local') and not out.exists()
    out.mkdir(parents=True)
    env = dict(os.environ, HOME=str(out / 'home'), APPDATA=str(out / 'user'), XDG_DATA_HOME=str(out / 'user'))
    rows = []
    phases = ['first', 'resume'] if args.type in ['equipment','airdrop'] and not args.preview and not args.direct else ['first']
    for phase in phases:
        cmd = [args.godot, '--path', str(ROOT), '--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy']
        if not args.native:
            cmd.append('--headless')
        flags = ['--flow-output=' + (out / phase).as_posix(), '--bh-rescue-seed=' + args.seed,
                 '--level-type=' + args.type, '--flow-size=' + args.size]
        if args.preview:
            flags.append('--flow-preview')
        if args.direct:
            flags.append('--level-direct')
        if phase == 'resume':
            flags.append('--flow-resume')
        encoder = None
        if args.movie:
            with socket.socket() as sock:
                sock.bind(('127.0.0.1', 0))
                port = sock.getsockname()[1]
            with (out / (phase + '-encode.txt')).open('w') as log:
                encoder = subprocess.Popen(['ffmpeg', '-hide_banner', '-loglevel', 'warning', '-f', 'rawvideo',
                    '-pixel_format', 'rgba', '-video_size', '1280x720', '-framerate', '30', '-i',
                    f'tcp://127.0.0.1:{port}?listen=1', '-an', '-c:v', 'libx264', '-preset', 'veryfast',
                    '-crf', '24', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(out / (phase + '-1x.mp4'))], stdout=log, stderr=log)
            cmd += ['--fixed-fps', '30', '--max-fps', '30', '--disable-vsync']
            flags.append('--flow-stream=' + str(port))
        cmd += ['--script', 'res://tests/level_flow.gd', '--', *flags]
        started = time.monotonic()
        with (out / (phase + '.txt')).open('w') as log:
            if args.native and sys.platform == 'win32':
                from windows_test_process import DesktopProcess
                process = DesktopProcess(cmd, ROOT, env, log, log)
            else:
                process = subprocess.Popen(cmd, cwd=ROOT, env=env, stdout=log, stderr=log)
            while process.poll() is None:
                if time.monotonic() - started > 240:
                    process.kill()
                    raise subprocess.TimeoutExpired(cmd, 240)
                time.sleep(.02)
            code = process.wait() if args.native and sys.platform == 'win32' else process.wait(timeout=10)
        if encoder:
            assert encoder.wait(timeout=20) == 0
        console = (out / (phase + '.txt')).read_text('utf-8')
        assert code == 0 and not re.search(r'(?m)^(SCRIPT ERROR|ERROR):', console), (phase, console[-2500:])
        report = json.loads((out / phase / 'report.json').read_text('utf-8'))
        assert report['failures'] == 0, phase
        rows.append(dict(phase=phase, pid=report['pid'], checks=len(report['checks']),
                         seconds=round(time.monotonic() - started, 3), frames=report['video_frames']))
        print(rows[-1], flush=True)
    (out / 'summary.json').write_text(json.dumps(dict(results=rows, renderer='gl_compatibility',
        native=args.native, physical_input='NOT_VERIFIED', production_gate='BLOCKED'), indent=2), encoding='utf-8')


if __name__ == '__main__':
    main()
