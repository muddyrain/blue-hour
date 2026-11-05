"""Bounded Mac task flow. Isolated profiles, offscreen renderer, no OS input."""
import argparse, json, os, re, socket, subprocess, sys, time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--native', action='store_true')
    parser.add_argument('--movie', action='store_true')
    parser.add_argument('--case', choices=['airdrop','supply','equipment','rescue','early','rescue-death','rescue-roster4'], required=True)
    args = parser.parse_args()
    assert subprocess.check_output([args.godot,'--version'], text=True).strip() == (ROOT/'.godot-version').read_text().strip()
    out = args.output.resolve()
    assert out.is_relative_to(ROOT/'.local')
    out.mkdir(parents=True, exist_ok=False)
    (out/'home').mkdir()
    (out/'user').mkdir()
    env = dict(os.environ, HOME=str(out/'home'), APPDATA=str(out/'user'), XDG_DATA_HOME=str(out/'user'))
    guard = None
    if args.native:
        assert sys.platform == 'darwin'
        guard = out/'background_guard.dylib'
        subprocess.run(['clang','-dynamiclib','-framework','AppKit','-framework','Foundation','-o',str(guard),str(ROOT/'tools/macos_background.m')],check=True,capture_output=True)
    assert not args.movie or (args.native and args.case=='airdrop'), 'movie uses one native airdrop journey'
    results = []
    for phase in ['first','resume'] if args.case == 'airdrop' and not args.movie else ['first']:
        command = [args.godot,'--path',str(ROOT),'--audio-driver','Dummy','--rendering-method','gl_compatibility']
        command += ['--position','-16000,-16000'] if args.native else ['--headless']
        command += ['--script','res://tests/'+('task_movie' if args.movie else 'task_flow')+'.gd','--','--flow-output='+str(out/phase),'--task-case='+args.case,'--bh-rescue-seed='+('task-v4-2' if args.case=='equipment' else 'task-v4-3')]
        if phase != 'first': command += ['--flow-resume']
        started = time.monotonic()
        if args.native:
            assert sys.platform == 'darwin', 'This native launcher is Mac only'
            env['DYLD_INSERT_LIBRARIES'] = str(guard)
        encoder = None
        encoding_log = None
        if args.movie:
            with socket.socket() as probe:
                probe.bind(('127.0.0.1',0)); port=probe.getsockname()[1]
            encoding_log=(out/'encoding.txt').open('w')
            encoder=subprocess.Popen(['ffmpeg','-hide_banner','-loglevel','warning','-f','rawvideo','-pixel_format','rgba','-video_size','1280x720','-framerate','30','-i',f'tcp://127.0.0.1:{port}?listen=1','-an','-c:v','libx264','-preset','veryfast','-crf','21','-pix_fmt','yuv420p','-movflags','+faststart',str(out/'task-1x-full.mp4')],stdout=encoding_log,stderr=encoding_log)
            flag=command.index('--')
            command[flag:flag]=['--fixed-fps','30','--max-fps','30','--disable-vsync']
            command+=['--flow-stream='+str(port)]
            time.sleep(.3)
        with (out/(phase+'.txt')).open('w') as log:
            audit = {'samples':0, 'pids':[]}
            def sample_foreground():
                text = subprocess.check_output(['osascript','-l','JavaScript','-e','ObjC.import("AppKit"); $.NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier'],text=True,timeout=5)
                pid = int(text.strip())
                audit['samples'] += 1
                if pid not in audit['pids']: audit['pids'].append(pid)
                temporary = out/'foreground.tmp'
                temporary.write_text(json.dumps(audit))
                temporary.replace(out/'foreground.json')
            if args.native: sample_foreground()
            proc = None
            try:
                proc = subprocess.Popen(command, env=env, cwd=ROOT, stdout=log, stderr=log)
                while proc.poll() is None:
                    if time.monotonic()-started > 300:
                        raise subprocess.TimeoutExpired(command,300)
                    if args.native:
                        sample_foreground()
                        if proc.pid in audit['pids']:
                            raise AssertionError('Renderer became foreground; stopped')
                    time.sleep(.15)
                result = proc
            finally:
                if proc and proc.poll() is None:
                    proc.kill(); proc.wait()
                if encoder:
                    try:
                        if proc and proc.returncode==0: assert encoder.wait(timeout=30)==0
                    finally:
                        if encoder.poll() is None: encoder.kill(); encoder.wait()
                        encoding_log.close()
        console = (out/(phase+'.txt')).read_text()
        assert result.returncode == 0 and not re.search(r'(?m)^(SCRIPT ERROR|ERROR):',console), (phase,result.returncode,console[-2500:])
        report = json.loads((out/phase/'report.json').read_text())
        assert report['failures'] == 0, report
        if args.native: assert report['pid'] not in audit['pids'], audit
        row = dict(phase=phase,pid=report['pid'],checks=len(report['checks']),wall_seconds=round(time.monotonic()-started,3))
        results.append(row)
        print(row, flush=True)
    (out/'summary.json').write_text(json.dumps(dict(case=args.case,native=args.native,phases=results),indent=2))

if __name__ == '__main__': main()
