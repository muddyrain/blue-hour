"""Optional precise helper build for maintainers; players never need a compiler."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
FOLDER = ROOT / '.local/navigation-native'
LIBRARIES = {'linux.x86_64': 'route_kernel.so', 'windows.x86_64': 'route_kernel.dll'}


def host_target() -> str:
    system = {'Linux': 'linux', 'Windows': 'windows'}.get(platform.system(), platform.system().lower())
    machine = {'AMD64': 'x86_64', 'amd64': 'x86_64'}.get(platform.machine(), platform.machine())
    return f'{system}.{machine}'


def isolated_env(folder: Path) -> dict:
    env = dict(os.environ)
    for key, name in {'HOME': 'home', 'APPDATA': 'data', 'XDG_DATA_HOME': 'data',
                      'XDG_CONFIG_HOME': 'config', 'XDG_CACHE_HOME': 'cache',
                      'XDG_STATE_HOME': 'state', 'XDG_RUNTIME_DIR': 'runtime',
                      'TMPDIR': 'tmp', 'TEMP': 'tmp', 'TMP': 'tmp'}.items():
        path = folder / name
        path.mkdir(parents=True, exist_ok=True)
        env[key] = str(path)
    (folder / 'runtime').chmod(0o700)
    return env


def report_available() -> None:
    target = host_target()
    library = FOLDER / LIBRARIES.get(target, 'unsupported')
    state = 'present (runtime load checked by Godot)' if library.is_file() else 'absent; strict AStarGrid2D fallback'
    print(f'BH_NAVIGATION_BUILD skipped: {target} {state}', flush=True)


def build(engine: str, target: str | None = None, compiler: str | None = None,
          required: bool = False) -> Path | None:
    target = target or host_target()
    try:
        return _build(engine, target, compiler)
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as error:
        # Remove failed/stale output so an optional build cannot accidentally use it.
        if target in LIBRARIES:
            (FOLDER / LIBRARIES[target]).unlink(missing_ok=True)
        print(f'BH_NAVIGATION_BUILD fallback: {target}: {error}; strict AStarGrid2D enabled', flush=True)
        if required:
            raise
        return None


def _build(engine: str, target: str, compiler: str | None) -> Path:
    if target not in LIBRARIES:
        raise RuntimeError(f'Unsupported helper target {target}')
    engine = shutil.which(engine) or str(Path(engine).resolve())
    lock = (ROOT / '.godot-version').read_text(encoding='utf-8').strip()
    if subprocess.check_output([engine, '--version'], text=True, timeout=15).strip() != lock:
        raise RuntimeError('Use the pinned single-precision Godot engine')
    compiler = compiler or ('x86_64-w64-mingw32-gcc' if target == 'windows.x86_64' and host_target() != target else 'cc')
    compiler = shutil.which(compiler)
    if compiler is None:
        raise RuntimeError('No C11 GCC/Clang toolchain; build on a maintainer machine or export fallback')
    source = ROOT / 'src/features/expedition/native/route_kernel.c'
    folder = FOLDER / target
    folder.mkdir(parents=True, exist_ok=True)
    env = isolated_env(folder)
    flags = ['-std=c11', '-O3', '-shared', '-ffp-contract=off', '-fno-fast-math',
             '-Wall', '-Wextra', '-Werror', '-Wno-cast-function-type']
    if target == 'linux.x86_64':
        flags += ['-fPIC']
    compiler_version = subprocess.check_output([compiler, '--version'], text=True, env=env, timeout=15)
    identity = hashlib.sha256(source.read_bytes() + Path(__file__).read_bytes() + lock.encode()
                              + target.encode() + compiler_version.encode() + str(flags).encode()).hexdigest()
    library = FOLDER / LIBRARIES[target]
    stamp = folder / 'build.json'
    if library.exists() and stamp.exists() and json.loads(stamp.read_text())['source'] == identity:
        print(f'BH_NAVIGATION_BUILD cached: {target}', flush=True)
        return library
    for option in ('--dump-gdextension-interface', '--dump-extension-api'):
        with (folder / (option[2:] + '.log')).open('w') as log:
            subprocess.run([engine, '--headless', option, '--quit'], cwd=folder, env=env,
                           stdout=log, stderr=subprocess.STDOUT, check=True, timeout=30)
    # These are opaque PUBLIC built-in buffers, not engine object layouts. Verify
    # our C storage against the engine-generated API metadata on every fresh build.
    api = json.loads((folder / 'extension_api.json').read_text())
    sizes = {row['name']: row['size'] for row in next(row['sizes'] for row in api['builtin_class_sizes']
                                                   if row['build_configuration'] == 'float_64')}
    if sizes['PackedInt32Array'] != 16 or sizes['StringName'] != 8 or sizes['String'] != 8:
        raise RuntimeError('Unsupported public built-in storage sizes')
    temporary = folder / LIBRARIES[target]
    subprocess.run([compiler, *flags, '-I', str(folder), str(source), '-o', str(temporary)],
                   cwd=ROOT, env=env, check=True, timeout=60)
    temporary.replace(library)
    stamp.write_text(json.dumps({'source': identity, 'target': target, 'compiler': compiler,
                                 'compiler_version': compiler_version, 'flags': flags}, indent=2), encoding='utf-8')
    print(f'BH_NAVIGATION_BUILD built: {target} {library.relative_to(ROOT)}', flush=True)
    return library


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('engine')
    parser.add_argument('--target', choices=LIBRARIES)
    parser.add_argument('--compiler', help='GCC/Clang executable, including MinGW cross compiler')
    parser.add_argument('--required', action='store_true', help='Fail packaging/CI if the helper cannot be built')
    args = parser.parse_args()
    build(args.engine, args.target, args.compiler, args.required)
