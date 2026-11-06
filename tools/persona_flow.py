"""Current-system M12 acceptance. Synthetic profiles, original gameplay owners, no OS input."""
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
    parser.add_argument('--native', action='store_true')
    parser.add_argument('--legacy', action='store_true')
    parser.add_argument('--movie', action='store_true')
    parser.add_argument('--kill-after-suspend', action='store_true', help='Kill first process after its completed SUSPEND_READY report, before normal cleanup')
    args = parser.parse_args()
    assert not sys.flags.optimize and (not args.movie or args.native)
    out = args.output.resolve()
    assert out.is_relative_to(ROOT / '.local') and not out.exists()
    assert subprocess.check_output([args.godot, '--version'], text=True).strip() == (ROOT / '.godot-version').read_text().strip()
    out.mkdir(parents=True)
    env = dict(os.environ, HOME=str(out / 'home'), APPDATA=str(out / 'user'), XDG_DATA_HOME=str(out / 'user'))
    if args.native:
        assert sys.platform == 'darwin'
        guard = out / 'background_guard.dylib'
        subprocess.run(['clang', '-dynamiclib', '-framework', 'AppKit', '-framework', 'Foundation', '-o', str(guard), str(ROOT / 'tools/macos_background.m')], check=True, capture_output=True)
        env['DYLD_INSERT_LIBRARIES'] = str(guard)
    rows = []
    for phase in ['first', 'resume']:
        flags = ['--flow-output=' + str(out / phase), '--bh-rescue-seed=m9-r1']
        if args.legacy:
            flags.append('--flow-legacy-persona')
            if phase == 'first': flags.append('--flow-bootstrap-m11')
        if phase == 'resume':
            flags.append('--flow-resume')
        cmd = [args.godot, '--path', str(ROOT), '--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy']
        cmd += ['--position', '-16000,-16000'] if args.native else ['--headless']
        encoder = None
        if args.movie:
            with socket.socket() as sock:
                sock.bind(('127.0.0.1', 0))
                port = sock.getsockname()[1]
            with (out / (phase + '-encode.txt')).open('w') as log:
                encoder = subprocess.Popen(['ffmpeg', '-hide_banner', '-loglevel', 'warning', '-f', 'rawvideo', '-pixel_format', 'rgba', '-video_size', '1280x720', '-framerate', '30', '-i', f'tcp://127.0.0.1:{port}?listen=1', '-an', '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '22', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(out / (phase + '-1x.mp4'))], stdout=log, stderr=log)
            cmd += ['--fixed-fps', '30', '--max-fps', '30', '--disable-vsync']
            flags.append('--flow-stream=' + str(port))
            time.sleep(.3)
        cmd += ['--script', 'res://tests/persona_flow.gd', '--', *flags]
        start = time.monotonic()
        killed = False
        with (out / (phase + '.txt')).open('w') as log:
            process = subprocess.Popen(cmd, cwd=ROOT, env=env, stdout=log, stderr=log)
            while process.poll() is None:
                if time.monotonic() - start > 300:
                    process.kill()
                    raise subprocess.TimeoutExpired(cmd, 300)
                if args.kill_after_suspend and phase == 'first' and (out / phase / 'report.json').exists():
                    process.kill()
                    killed = True
                    break
                time.sleep(.02)
            code = process.wait(timeout=15)
        if encoder:
            assert encoder.wait(timeout=30) == 0
        text = (out / (phase + '.txt')).read_text()
        assert code == (-9 if killed else 0) and not re.search(r'(?m)^(SCRIPT ERROR|ERROR):', text), phase
        report = json.loads((out / phase / 'report.json').read_text())
        assert report['failures'] == 0, phase
        rows.append(dict(phase=phase, pid=report['pid'], checks=len(report['checks']), seconds=round(time.monotonic()-start, 2), frames=report['video_frames'], killed_after_durable_suspend=killed))
        print(rows[-1], flush=True)
    (out / 'summary.json').write_text(json.dumps(dict(results=rows, renderer='gl_compatibility', native=args.native, physical_input='NOT_TESTED', production_gate='BLOCKED'), indent=2))


if __name__ == '__main__':
    main()
