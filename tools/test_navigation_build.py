"""Build failure/skip and packaging contracts; never invoke a compiler or real profile."""
from pathlib import Path
import contextlib
import io
import tempfile
import unittest
from unittest.mock import patch
import build_navigation as native


class NavigationBuildTests(unittest.TestCase):
    def test_unsupported_platform_is_optional(self):
        with patch.object(native, 'host_target', return_value='macos.arm64'):
            self.assertIsNone(native.build('unused'))

    def test_missing_compiler_falls_back(self):
        with tempfile.TemporaryDirectory(dir=native.ROOT / '.local') as folder, \
                patch.object(native, 'FOLDER', Path(folder)), \
                patch.object(native.subprocess, 'check_output', return_value=(native.ROOT / '.godot-version').read_text().strip()), \
                patch.object(native.shutil, 'which', return_value=None):
            self.assertIsNone(native.build('engine', 'windows.x86_64'))

    def test_failed_build_removes_stale_binary(self):
        with tempfile.TemporaryDirectory(dir=native.ROOT / '.local') as folder, \
                patch.object(native, 'FOLDER', Path(folder)), \
                patch.object(native, '_build', side_effect=RuntimeError('compiler failure')):
            library = Path(folder) / native.LIBRARIES['windows.x86_64']
            library.touch()
            self.assertIsNone(native.build('engine', 'windows.x86_64'))
            self.assertFalse(library.exists())
            with self.assertRaises(RuntimeError):
                native.build('engine', 'windows.x86_64', required=True)

    def test_run_skips_build_without_platform_restriction(self):
        with patch.object(native, 'host_target', return_value='windows.x86_64'), \
                patch.object(native.subprocess, 'run', side_effect=AssertionError('must not build')), \
                contextlib.redirect_stdout(io.StringIO()) as output:
            native.report_available()
            self.assertIn('skipped: windows.x86_64', output.getvalue())

    def test_manifest_uses_official_platform_keys_without_auto_scan(self):
        folder = native.ROOT / 'src/features/expedition/native'
        self.assertFalse(list(folder.glob('*.gdextension')))
        manifest = (folder / 'route_kernel.cfg').read_text()
        for target, name in native.LIBRARIES.items():
            self.assertIn(f'{target} = "res://.local/navigation-native/{name}"', manifest)


if __name__ == '__main__':
    unittest.main()
