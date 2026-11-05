"""R1 support regressions using new synthetic progress; never rebind a checkpoint."""
import argparse, json, os, re, shutil, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if sys.flags.optimize:
    raise RuntimeError('Optimized Python is prohibited for check gates')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', required=True)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    out = args.output.resolve()
    assert out.is_relative_to(ROOT / '.local') and not out.exists()
    assert subprocess.check_output([args.godot, '--version'], text=True).strip() == (ROOT / '.godot-version').read_text().strip()
    out.mkdir(parents=True)
    summaries = []

    def run(phase, script, profile, resume=False):
        env = dict(os.environ, APPDATA=str(profile / 'user'), HOME=str(profile / 'home'), XDG_DATA_HOME=str(profile / 'user'))
        cmd = [args.godot, '--headless', '--path', str(ROOT), '--script', 'res://tests/' + script + '.gd', '--',
               '--flow-output=' + (out / phase).as_posix(), '--bh-rescue-seed=m9-combat-01-sample-02']
        if resume:
            cmd += ['--flow-resume']
        result = subprocess.run(cmd, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
        (out / (phase + '.txt')).write_bytes(result.stdout)
        assert result.returncode == 0 and not re.search(rb'(?m)^(SCRIPT ERROR|ERROR):', result.stdout), phase
        report = json.loads((out / phase / 'report.json').read_text(encoding='utf8'))
        assert report['failures'] == 0, phase
        summaries.append(dict(phase=phase, pid=report['pid'], checks=len(report['checks'])))
        print(summaries[-1], flush=True)

    run('input', 'support_input_flow', out / 'input-profile')
    profile = out / 'fixture'
    run('first', 'combat_flow', profile)
    # Keep one small fixture at its original binding path; no history/profile rewriting.
    shutil.copytree(profile / 'user', out / 'checkpoint-original', ignore=shutil.ignore_patterns('shader_cache', 'logs'))
    run('green-toxic', 'support_boundary_flow', profile, True)
    run('recovery', 'support_recovery_flow', profile, True)
    shutil.move(str(profile / 'user'), str(out / 'after-toxic-user'))
    shutil.copytree(out / 'checkpoint-original', profile / 'user')
    run('boss', 'support_boundary_flow', profile, True)
    (out / 'summary.json').write_text(json.dumps({'results': summaries, 'physical_input': 'NOT_TESTED', 'production_gate': 'BLOCKED'}, indent=2))


if __name__ == '__main__':
    main()
