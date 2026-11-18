"""Build failure/skip and packaging contracts; never invoke a compiler or real profile."""
from pathlib import Path
import contextlib
import io
import json
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import build_navigation as native


class NavigationBuildTests(unittest.TestCase):
    def test_host_platform_mapping(self):
        for system, machine, expected in [('Darwin', 'arm64', 'macos.arm64'),
                                           ('Darwin', 'x86_64', 'macos.x86_64'),
                                           ('Linux', 'aarch64', 'linux.arm64'),
                                           ('Windows', 'AMD64', 'windows.x86_64')]:
            with self.subTest(expected=expected), patch.object(native.platform, 'system', return_value=system), \
                    patch.object(native.platform, 'machine', return_value=machine):
                self.assertEqual(native.host_target(), expected)

    def test_unsupported_platform_is_optional(self):
        with patch.object(native, 'host_target', return_value='linux.arm64'):
            self.assertIsNone(native.build('unused'))

    def test_macos_cross_build_is_not_attempted_without_apple_host(self):
        for target in [*native.MACOS_TARGETS, 'macos.universal']:
            with self.subTest(target=target), tempfile.TemporaryDirectory(dir=native.ROOT / '.local') as folder, \
                    patch.object(native, 'FOLDER', Path(folder)), \
                    patch.object(native.platform, 'system', return_value='Linux'), \
                    patch.object(native.subprocess, 'check_output', side_effect=AssertionError('must not invoke tools')):
                self.assertIsNone(native.build('engine', target))

    def test_missing_compiler_falls_back(self):
        with tempfile.TemporaryDirectory(dir=native.ROOT / '.local') as folder, \
                patch.object(native, 'FOLDER', Path(folder)), \
                patch.object(native.subprocess, 'check_output', return_value=(native.ROOT / '.godot-version').read_text().strip()), \
                patch.object(native.shutil, 'which', return_value=None):
            self.assertIsNone(native.build('engine', 'windows.x86_64'))

    def test_failed_build_removes_stale_binary(self):
        for target in native.LIBRARIES:
            with self.subTest(target=target), tempfile.TemporaryDirectory(dir=native.ROOT / '.local') as folder, \
                    patch.object(native, 'FOLDER', Path(folder)), \
                    patch.object(native, '_build', side_effect=RuntimeError('compiler failure')):
                library = Path(folder) / native.LIBRARIES[target]
                library.touch()
                universal = Path(folder) / native.LIBRARIES['macos.universal']
                universal.touch()
                self.assertIsNone(native.build('engine', target))
                self.assertFalse(library.exists())
                if target in native.MACOS_TARGETS:
                    self.assertFalse(universal.exists())
                with self.assertRaises(RuntimeError):
                    native.build('engine', target, required=True)

    @contextlib.contextmanager
    def _fake_toolchain(self):
        """Emulate generated public metadata and compiler/lipo output, not native code."""
        with tempfile.TemporaryDirectory(dir=native.ROOT / '.local') as folder:
            commands = []
            lipo = Path(folder) / 'lipo'
            lipo.write_bytes(b'local test lipo identity')
            sdk = {'path': '/test/sdk', 'version': '15.0', 'settings_sha256': 'sdk-v1'}

            def output(command, **_kwargs):
                if command == ['engine', '--version']:
                    return (native.ROOT / '.godot-version').read_text().strip()
                if command == ['cc', '--version']:
                    return 'Apple clang test version'
                if command == ['xcrun', '--find', 'lipo']:
                    return str(lipo)
                self.fail('unexpected external tool: ' + repr(command))

            def run(command, **kwargs):
                commands.append(command)
                if '--dump-extension-api' in command:
                    api = {'builtin_class_sizes': [{'build_configuration': 'float_64', 'sizes': [
                        {'name': 'PackedInt32Array', 'size': 16}, {'name': 'StringName', 'size': 8},
                        {'name': 'String', 'size': 8}]}]}
                    (Path(kwargs['cwd']) / 'extension_api.json').write_text(json.dumps(api))
                elif '-o' in command:
                    Path(command[command.index('-o') + 1]).write_bytes(' '.join(command).encode())
                elif '-output' in command:
                    Path(command[command.index('-output') + 1]).write_bytes(b'universal mock')
                elif '-verify_arch' in command:
                    # Apple lipo consumes every trailing token as an architecture.
                    self.assertEqual(command[2:], ['-verify_arch', 'arm64', 'x86_64'])
                    self.assertTrue(Path(command[1]).is_file())
                elif '--dump-gdextension-interface' not in command:
                    self.fail('unexpected run: ' + repr(command))
                return subprocess.CompletedProcess(command, 0)

            with patch.object(native, 'FOLDER', Path(folder)), \
                    patch.object(native.platform, 'system', return_value='Darwin'), \
                    patch.object(native.shutil, 'which', side_effect=lambda executable: executable), \
                    patch.object(native, '_macos_sdk', return_value=sdk), \
                    patch.object(native.subprocess, 'check_output', side_effect=output), \
                    patch.object(native.subprocess, 'run', side_effect=run):
                yield Path(folder), commands, sdk

    def test_macos_architecture_and_strict_math_commands(self):
        with self._fake_toolchain() as (folder, commands, _sdk):
            for target in native.MACOS_TARGETS:
                library = native.build('engine', target, required=True)
                self.assertEqual(library, folder / native.LIBRARIES[target])
                compile_command = [command for command in commands if '-o' in command][-1]
                for flag in ['-dynamiclib', '-ffp-contract=off', '-fno-fast-math', '-mmacosx-version-min=11.0']:
                    self.assertIn(flag, compile_command)
                self.assertNotIn('-shared', compile_command)
                self.assertEqual(compile_command[compile_command.index('-arch') + 1], target.split('.')[1])
                self.assertEqual(compile_command[compile_command.index('-isysroot') + 1], '/test/sdk')

    def test_sdk_change_and_corrupt_output_invalidate_cache(self):
        with self._fake_toolchain() as (_folder, commands, sdk):
            library = native.build('engine', 'macos.arm64', required=True)
            before = len(commands)
            self.assertEqual(native.build('engine', 'macos.arm64', required=True), library)
            self.assertEqual(len(commands), before)
            sdk['settings_sha256'] = 'sdk-v2'
            native.build('engine', 'macos.arm64', required=True)
            self.assertGreater(len(commands), before)
            before = len(commands)
            library.write_bytes(b'damaged')
            native.build('engine', 'macos.arm64', required=True)
            self.assertGreater(len(commands), before)

    def test_universal_contains_both_architectures_and_rebuilds_after_thin_change(self):
        with self._fake_toolchain() as (folder, commands, sdk):
            library = native.build('engine', 'macos.universal', required=True)
            self.assertEqual(library, folder / 'route_kernel.dylib')
            link = [command for command in commands if '-create' in command][-1]
            for target in native.MACOS_TARGETS:
                self.assertIn(str(folder / native.LIBRARIES[target]), link)
            self.assertIn([str(folder / 'lipo'), str(folder / 'macos.universal/route_kernel.dylib'),
                           '-verify_arch', 'arm64', 'x86_64'], commands)
            before = len(commands)
            native.build('engine', 'macos.universal', required=True)
            self.assertEqual(len(commands), before)
            (folder / 'lipo').write_bytes(b'updated local test lipo identity')
            native.build('engine', 'macos.universal', required=True)
            self.assertGreater(len(commands), before)
            before = len(commands)
            sdk['version'] = '16.0'
            native.build('engine', 'macos.arm64', required=True)
            self.assertFalse(library.exists())
            native.build('engine', 'macos.universal', required=True)
            self.assertTrue(library.exists())
            self.assertGreater(len(commands), before)

    def test_failed_universal_slice_cannot_reuse_old_fat_output(self):
        with self._fake_toolchain() as (folder, _commands, _sdk):
            library = folder / 'route_kernel.dylib'
            library.write_bytes(b'old fat output')
            original = native._build

            def fail_x86(engine, target, compiler):
                if target == 'macos.x86_64':
                    raise RuntimeError('second slice failed')
                return original(engine, target, compiler)

            with patch.object(native, '_build', side_effect=fail_x86):
                self.assertIsNone(native.build('engine', 'macos.universal'))
            self.assertFalse(library.exists())

    def test_run_skips_build_without_platform_restriction(self):
        for target in ['windows.x86_64', *native.MACOS_TARGETS]:
            with self.subTest(target=target), patch.object(native, 'host_target', return_value=target), \
                    patch.object(native.subprocess, 'run', side_effect=AssertionError('must not build')), \
                    contextlib.redirect_stdout(io.StringIO()) as output:
                native.report_available()
                self.assertIn('skipped: ' + target, output.getvalue())

    def test_manifest_uses_official_platform_keys_without_auto_scan(self):
        folder = native.ROOT / 'src/features/expedition/native'
        self.assertFalse(list(folder.glob('*.gdextension')))
        manifest = (folder / 'route_kernel.cfg').read_text()
        for target, name in native.LIBRARIES.items():
            if target != 'macos.universal':  # A fat binary is a build target, not an OS feature.
                self.assertIn(f'{target} = "res://.local/navigation-native/{name}"', manifest)


if __name__ == '__main__':
    unittest.main()
