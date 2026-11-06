"""M10 current-system isolated search acceptance; release-EXE input evidence is separate."""
import argparse, json, os, re, subprocess, sys, time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if sys.flags.optimize:
    raise RuntimeError('Optimized Python is prohibited for check gates')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', required=True)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--party-view', action='store_true', help='Windows independent desktop, existing native renderer')
    args = parser.parse_args()
    out = args.output.resolve()
    assert out.is_relative_to(ROOT / '.local') and not out.exists()
    assert subprocess.check_output([args.godot, '--version'], text=True).strip() == (ROOT / '.godot-version').read_text().strip()
    out.mkdir(parents=True)
    rows = []

    def run(phase, script, profile, seed='m9-r1', resume=False, native=False):
        env = dict(os.environ, APPDATA=str(profile / 'user'), HOME=str(profile / 'home'), XDG_DATA_HOME=str(profile / 'user'))
        cmd = [args.godot, '--path', str(ROOT), '--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--script', 'res://tests/' + script + '.gd']
        if not native:
            cmd += ['--headless']
        cmd += ['--', '--flow-output=' + (out / phase).as_posix(), '--bh-rescue-seed=' + seed]
        if resume:
            cmd += ['--flow-resume']
        if native:
            cmd += ['--party-world=' + (out / 'first/checkpoint.json').as_posix(), '--party-output=' + (out / phase).as_posix()]
        with (out / (phase + '.txt')).open('wb') as log:
            if native:
                assert sys.platform == 'win32'
                from windows_test_process import DesktopProcess
                proc = DesktopProcess(cmd, ROOT, env, log, log)
                deadline = time.monotonic() + 120
                while proc.poll() is None and time.monotonic() < deadline:
                    time.sleep(.15)
                if proc.poll() is None:
                    proc.kill()
                code = proc.wait()
            else:
                code = subprocess.run(cmd, cwd=ROOT, env=env, stdout=log, stderr=log, timeout=120).returncode
        raw = (out / (phase + '.txt')).read_bytes()
        assert code == 0 and not re.search(rb'(?m)^(SCRIPT ERROR|ERROR):', raw), phase
        report = json.loads((out / phase / 'report.json').read_text(encoding='utf8'))
        assert report['failures'] == 0, phase
        row = dict(phase=phase, checks=len(report['checks']), native=native)
        rows.append(row)
        print(row, flush=True)

    run('first', 'search_flow', out / 'normal-profile')
    run('resume', 'search_flow', out / 'normal-profile', resume=True)
    run('indoor', 'search_boundaries', out / 'indoor-profile')
    run('outdoor', 'search_boundaries', out / 'outdoor-profile', seed='m10-search-boundary-01')
    run('rescue', 'search_boundaries', out / 'rescue-profile')
    if args.party_view:
        run('party', 'search_party_view', out / 'party-profile', native=True)
    (out / 'summary.json').write_text(json.dumps({'results': rows, 'physical_input': 'NOT_TESTED', 'production_gate': 'BLOCKED'}, indent=2))


if __name__ == '__main__':
    main()
