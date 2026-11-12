"""Serial, exact-source M48/M49 Windows measurements; never clears OS disk caches."""
import argparse
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('suite', choices=('short', 'scale', 'long'))
    parser.add_argument('variant', choices=('before', 'after'))
    parser.add_argument('--godot', required=True)
    parser.add_argument('--label', default='')
    args = parser.parse_args()
    project = ROOT / '.local/m49/baseline' if args.variant == 'before' else ROOT
    output = ROOT / '.local/m49/measurements'
    output.mkdir(parents=True, exist_ok=True)
    if args.suite == 'short':
        cases = [(str(i), ROOT / '.local/m49/paired-short/profile',
                  ROOT / '.local/m49/paired-short/original', 'm49_comparison_flow.gd', []) for i in range(1, 5)]
    elif args.suite == 'scale':
        cases = [(str(i), ROOT / '.local/m49/scales/profile', ROOT / f'.local/m49/scales/original-{i}',
                  'm49_scale_flow.gd', ['--archive-mode=measure', f'--archive-count={i}', '--measure-catalog-ui'] +
                  (['--ten-refreshes'] if args.variant == 'after' and i == 20 else [])) for i in (0, 5, 20)]
    else:
        cases = [('100', ROOT / '.local/m49/long/profile-setup', ROOT / '.local/m49/long/original-prepared',
                  'm49_scale_flow.gd', ['--archive-mode=measure', '--archive-count=0', '--measure-catalog-ui'])]
    for number, profile, snapshot, script, flags in cases:
        phase = f'{args.suite}-{args.variant}-{number}' + (f'-{args.label}' if args.label else '')
        if (output / phase).exists():
            raise RuntimeError('Retain all samples; choose a fresh label')
        subprocess.run([sys.executable, 'tools/m49_sources.py', 'restore', str(profile), str(snapshot)],
                       cwd=ROOT, check=True)
        subprocess.run([sys.executable, 'tools/m49_flow.py', phase, '--project', str(project),
            '--output', str(output), '--profile', str(profile), '--script', script, '--resume',
            '--seed', 'm38-wave-01' if args.suite != 'long' else 'm48-economy-015',
            '--godot', args.godot, '--timeout', '5400', *flags], cwd=ROOT, check=True)


if __name__ == '__main__':
    main()
