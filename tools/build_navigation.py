"""Build the pinned, precise native JPS helper into ignored project-local output."""
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def build(engine: str) -> None:
    engine = shutil.which(engine) or str(Path(engine).resolve())
    if (platform.system(), platform.machine()) != ('Linux', 'x86_64'):
        raise RuntimeError('The precise navigation kernel currently supports Linux x86_64 only')
    source = ROOT / 'src/features/expedition/native/route_kernel.c'
    folder = ROOT / '.local/navigation-native'
    folder.mkdir(parents=True, exist_ok=True)
    flags = ['-std=c11', '-O3', '-fPIC', '-shared', '-ffp-contract=off', '-fno-fast-math', '-Wall', '-Wextra', '-Werror', '-Wno-cast-function-type']
    identity = hashlib.sha256(source.read_bytes() + Path(__file__).read_bytes() + (ROOT / '.godot-version').read_bytes()).hexdigest()
    library = folder / 'route_kernel.so'
    stamp = folder / 'build.json'
    if library.exists() and stamp.exists() and json.loads(stamp.read_text())['source'] == identity:
        return
    compiler = shutil.which('cc')
    if compiler is None:
        raise RuntimeError('A C11 compiler (cc) is required for exact navigation; build output stays in .local/')
    env = dict(os.environ)
    for key, name in {'HOME':'home','APPDATA':'data','XDG_DATA_HOME':'data','XDG_CONFIG_HOME':'config','XDG_CACHE_HOME':'cache','XDG_STATE_HOME':'state','XDG_RUNTIME_DIR':'runtime'}.items():
        path = folder / name
        path.mkdir(exist_ok=True)
        env[key] = str(path)
    with (folder / 'header.log').open('w') as log:
        subprocess.run([engine, '--headless', '--dump-gdextension-interface', '--quit'], cwd=folder, env=env, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=30)
    temporary = folder / 'route_kernel.build.so'
    subprocess.run([compiler, *flags, '-I', str(folder), str(source), '-o', str(temporary)], cwd=ROOT, check=True, timeout=60)
    temporary.replace(library)
    stamp.write_text(json.dumps({'source':identity,'compiler':compiler,'flags':flags}, indent=2))


if __name__ == '__main__':
    import sys
    build(str(Path(sys.argv[1]).resolve()))
