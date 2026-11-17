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
LIBRARIES = {
    'linux.x86_64': 'route_kernel.so',
    'windows.x86_64': 'route_kernel.dll',
    'macos.arm64': 'route_kernel.arm64.dylib',
    'macos.x86_64': 'route_kernel.x86_64.dylib',
    'macos.universal': 'route_kernel.dylib',
}
MACOS_TARGETS = ('macos.arm64', 'macos.x86_64')


def host_target() -> str:
    system = {'Linux': 'linux', 'Windows': 'windows', 'Darwin': 'macos'}.get(platform.system(), platform.system().lower())
    machine = {'AMD64': 'x86_64', 'amd64': 'x86_64', 'aarch64': 'arm64'}.get(platform.machine(), platform.machine())
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
        # A failed thin build also invalidates the fat library that may contain it.
        cleanup = [target, 'macos.universal'] if target in MACOS_TARGETS else [target]
        for failed in cleanup:
            if failed in LIBRARIES:
                (FOLDER / LIBRARIES[failed]).unlink(missing_ok=True)
        print(f'BH_NAVIGATION_BUILD fallback: {target}: {error}; strict AStarGrid2D enabled', flush=True)
        if required:
            raise
        return None


def _cached(library: Path, stamp: Path, identity: str) -> bool:
    if not library.is_file() or not stamp.is_file():
        return False
    try:
        previous = json.loads(stamp.read_text(encoding='utf-8'))
        return (previous.get('source') == identity
                and previous.get('sha256') == hashlib.sha256(library.read_bytes()).hexdigest())
    except (OSError, ValueError, AttributeError):
        return False


def _macos_sdk(env: dict) -> dict:
    if platform.system() != 'Darwin':
        raise RuntimeError('macOS builds require an existing Apple SDK on macOS')
    sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True, env=env, timeout=15).strip()
    settings = Path(sdk) / 'SDKSettings.json'
    if not Path(sdk).is_dir() or not settings.is_file():
        raise RuntimeError('Apple macOS SDK unavailable; install Xcode Command Line Tools explicitly')
    return {'path': sdk,
            'version': subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-version'], text=True, env=env, timeout=15).strip(),
            'settings_sha256': hashlib.sha256(settings.read_bytes()).hexdigest()}


def _build_universal(engine: str, compiler: str | None) -> Path:
    if platform.system() != 'Darwin':
        raise RuntimeError('macOS universal builds require Apple tools on macOS')
    libraries = [build(engine, target, compiler, required=True) for target in MACOS_TARGETS]
    folder = FOLDER / 'macos.universal'
    env = isolated_env(folder)
    lipo = subprocess.check_output(['xcrun', '--find', 'lipo'], text=True, env=env, timeout=15).strip()
    metadata = {'target': 'macos.universal', 'lipo': lipo,
                'lipo_sha256': hashlib.sha256(Path(lipo).read_bytes()).hexdigest(),
                'inputs': {target: hashlib.sha256(library.read_bytes()).hexdigest()
                           for target, library in zip(MACOS_TARGETS, libraries)}}
    identity = hashlib.sha256(json.dumps(metadata, sort_keys=True).encode() + Path(__file__).read_bytes()).hexdigest()
    library = FOLDER / LIBRARIES['macos.universal']
    stamp = folder / 'build.json'
    if _cached(library, stamp, identity):
        print('BH_NAVIGATION_BUILD cached: macos.universal', flush=True)
        return library
    temporary = folder / library.name
    subprocess.run([lipo, '-create', *map(str, libraries), '-output', str(temporary)],
                   cwd=ROOT, env=env, check=True, timeout=60)
    subprocess.run([lipo, str(temporary), '-verify_arch', 'arm64', 'x86_64'],
                   cwd=ROOT, env=env, check=True, timeout=15)
    temporary.replace(library)
    metadata.update(source=identity, sha256=hashlib.sha256(library.read_bytes()).hexdigest())
    stamp.write_text(json.dumps(metadata, indent=2), encoding='utf-8')
    print(f'BH_NAVIGATION_BUILD built: macos.universal {library.relative_to(ROOT)}', flush=True)
    return library


def _build(engine: str, target: str, compiler: str | None) -> Path:
    if target not in LIBRARIES:
        raise RuntimeError(f'Unsupported helper target {target}')
    if target == 'macos.universal':
        return _build_universal(engine, compiler)
    if target in MACOS_TARGETS and platform.system() != 'Darwin':
        raise RuntimeError('macOS builds require an existing Apple SDK on macOS')
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
    flags = ['-std=c11', '-O3', '-ffp-contract=off', '-fno-fast-math',
             '-Wall', '-Wextra', '-Werror', '-Wno-cast-function-type']
    sdk = _macos_sdk(env) if target in MACOS_TARGETS else {}
    if sdk:
        flags += ['-dynamiclib', '-arch', target.split('.')[1], '-isysroot', sdk['path'],
                  '-mmacosx-version-min=11.0', '-Wl,-install_name,@rpath/' + LIBRARIES[target]]
    else:
        flags += ['-shared']
    if target == 'linux.x86_64':
        flags += ['-fPIC']
    compiler_version = subprocess.check_output([compiler, '--version'], text=True, env=env, timeout=15)
    metadata = {'target': target, 'compiler': compiler, 'compiler_version': compiler_version,
                'flags': flags, 'sdk': sdk}
    identity = hashlib.sha256(source.read_bytes() + Path(__file__).read_bytes() + lock.encode()
                              + json.dumps(metadata, sort_keys=True).encode()).hexdigest()
    library = FOLDER / LIBRARIES[target]
    stamp = folder / 'build.json'
    if _cached(library, stamp, identity):
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
    # A thin rebuild makes any existing universal output stale until relinked.
    if target in MACOS_TARGETS:
        (FOLDER / LIBRARIES['macos.universal']).unlink(missing_ok=True)
    metadata.update(source=identity, sha256=hashlib.sha256(library.read_bytes()).hexdigest())
    stamp.write_text(json.dumps(metadata, indent=2), encoding='utf-8')
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
