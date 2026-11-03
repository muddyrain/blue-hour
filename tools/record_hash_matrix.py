"""Bounded Windows persistence cases using synthetic, project-local profiles only."""
import argparse
import ctypes
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1048576), b''):
            value.update(block)
    return value.hexdigest()


def dump(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False), encoding='utf-8')


def snapshot(folder, held_files=()):
    # Only explicitly held paths are marked unreadable; all other read failures remain errors.
    held = {str(p.resolve()).casefold() for p in held_files}
    return {str(p.relative_to(folder)): ('EXCLUSIVE_HANDLE_HELD' if str(p.resolve()).casefold() in held else digest(p))
            for p in sorted(folder.rglob('*')) if p.is_file()}


def accepted_case(code, result_exists, failures, text, outcome, barrier, unchanged):
    clean = re.sub(r'\x1b\[[0-9;]*m', '', text)
    if re.search(r'(?m)^(SCRIPT ERROR|ERROR):|^FAILED(?:\s|$)', clean):
        return False
    if outcome == 'WINDOWS_TERMINATEPROCESS_AT_OBSERVED_BARRIER':
        return barrier is not None and barrier.get('failures') == 0 and unchanged
    return outcome == 'normal_exit' and code == 0 and result_exists and failures == 0


class Matrix:
    def __init__(self, args):
        self.args = args
        self.output = args.output.resolve()
        allowed = ROOT / '.local/p0-record-hash-02'
        if not self.output.is_relative_to(allowed) or self.output == allowed:
            raise ValueError('Use an explicit run beneath .local/p0-record-hash-02')
        if not re.fullmatch(r'[a-z0-9-]+', args.tag):
            raise ValueError('Invalid run tag')
        for folder in ['report', 'evidence', 'scratch', 'protected-profile', 'deliverables']:
            (self.output/folder).mkdir(parents=True, exist_ok=True)
        self.result = self.output/'report'/f'matrix-{args.tag}.json'
        if self.result.exists():
            raise ValueError('Existing run refused; choose a new tag')
        self.rows = []
        requested = args.exe or args.godot
        actual = requested
        if not args.exe and os.name == 'nt' and requested.name.endswith('_console.exe'):
            # The console binary is a launcher; barriers must target the actual engine PID.
            actual = requested.with_name(requested.name.replace('_console.exe','.exe'))
            if not actual.is_file():
                raise ValueError('Direct pinned engine binary is required for PID barriers')
        self.engine = str(actual)
        if not args.exe:
            version = subprocess.check_output([self.engine, '--version'], text=True, timeout=15).strip()
            if version != (ROOT/'.godot-version').read_text(encoding='utf-8').strip():
                raise ValueError('Pinned engine required')

    def profile(self, name):
        path = self.output/'protected-profile'/f'{self.args.tag}-{name}'/'run.enemy-v1.json'
        path.parent.mkdir(parents=True, exist_ok=True)
        return path

    def run(self, label, profile, flags=(), *, kind='process', mode='read', native=False,
            barrier=None, kill=False, while_held=None, timeout=180, movie=False, held_files=()):
        folder = self.output/'evidence'/f'{self.args.tag}-{label}'
        folder.mkdir(exist_ok=False)
        data = folder/'data' if kind == 'process' else folder
        params = ['--bh-enemy-trial', '--bh-safe-suspend', '--bh-progress='+str(profile),
                  '--bh-audio-settings='+str(profile.parent/'audio.json')]
        if kind == 'process':
            params += ['--verify-record-process', '--process-output='+str(data), '--process-mode='+mode]
        elif kind == 'recovery':
            params += ['--verify-recovery='+str(data), '--recovery-case='+mode,
                       '--recovery-point=hash-cycle', '--recovery-map=market']
        elif kind == 'camp':
            params += ['--verify-record-hash='+str(data), '--camp-case='+mode, '--bh-camp-prototype']
        else:
            raise ValueError('Unknown case kind')
        command = [self.engine]
        if not self.args.exe:
            command += ['--path', str(ROOT)]
        command += ['--rendering-method', 'gl_compatibility']
        if not native:
            command += ['--headless']
        if movie:
            command += ['--write-movie',str(folder/'native.avi'),'--fixed-fps','30','--quit-after','1200']
        command += ['--', *params, *flags]
        env = dict(os.environ, APPDATA=str(folder/'appdata'), XDG_DATA_HOME=str(folder/'xdg'), PYTHONIOENCODING='utf-8')
        start = datetime.datetime.now(datetime.timezone.utc).isoformat()
        before = snapshot(profile.parent,held_files)
        begin = time.monotonic()
        outcome = 'normal_exit'
        observed = None
        at_barrier = None
        if native:
            if os.name != 'nt':
                raise RuntimeError('Native acceptance requires Windows')
            from windows_test_process import DesktopProcess
            factory = DesktopProcess
        else:
            factory = subprocess.Popen
        with (folder/'console.log').open('xb') as log:
            process = factory(command, cwd=ROOT, env=env, stdout=log, stderr=log)
            while process.poll() is None:
                if movie and sum(p.stat().st_size for p in folder.glob('native.*')) > 600 * 1024 * 1024:
                    process.kill()
                    outcome = 'MOVIE_BYTE_LIMIT'
                    break
                if time.monotonic()-begin > timeout:
                    process.kill()
                    outcome = 'TIMEOUT'
                    break
                if barrier and (data/'barrier.json').exists():
                    try:
                        observed = json.loads((data/'barrier.json').read_text(encoding='utf-8'))
                    except (ValueError, OSError):
                        time.sleep(.02)
                        continue
                    if observed.get('pid') != process.pid:
                        process.kill()
                        process.wait()
                        raise RuntimeError('Barrier PID mismatch')
                    at_barrier = snapshot(profile.parent)
                    if while_held:
                        try:
                            while_held(process, data)
                        except BaseException:
                            process.kill()
                            process.wait()
                            raise
                    if kill:
                        # Popen.kill/TerminateProcess kills this exact owned Windows PID.
                        process.kill()
                        outcome = 'WINDOWS_TERMINATEPROCESS_AT_OBSERVED_BARRIER'
                    elif not (data/'release').exists():
                        (data/'release').write_text('release', encoding='ascii')
                    barrier = None
                time.sleep(.03)
            code = process.wait()
        text = (folder/'console.log').read_text(encoding='utf-8', errors='replace')
        clean = re.sub(r'\x1b\[[0-9;]*m', '', text)
        result_file = data/('result.json' if kind == 'process' else 'report.json')
        result = json.loads(result_file.read_text(encoding='utf-8')) if result_file.exists() else {}
        row = dict(case=label, pid=process.pid, started=start,
                   ended=datetime.datetime.now(datetime.timezone.utc).isoformat(), exit=code,
                   seconds=round(time.monotonic()-begin, 3), outcome=outcome,
                   layer='release-exe' if self.args.exe else 'source-engine', display='isolated-windows-desktop' if native else 'headless',
                   barrier=observed, barrier_files=at_barrier, command=command, before=before, after=snapshot(profile.parent,held_files),
                   checks=result.get('checks', []), failures=result.get('failures'), state=result.get('state'), reason=result.get('reason'))
        row['pass'] = accepted_case(code,result_file.exists(),result.get('failures'),clean,outcome,observed,at_barrier == row['after'])
        if kill:
            row['prekill_files_unchanged'] = at_barrier == row['after']
            row['pass'] = row['pass'] and row['prekill_files_unchanged']
        self.rows.append(row)
        dump(self.result, dict(status='RUNNING', cases=self.rows, production_gate='BLOCKED', physical_input='NOT_VERIFIED'))
        print(label, 'PASS' if row['pass'] else 'FAIL', flush=True)
        if not row['pass']:
            raise RuntimeError(f'{label}: see {folder}/console.log')
        return data

    def preflight(self):
        profile = self.profile('world')
        first = self.run('S1', profile, kind='recovery', mode='save')
        # Exact world bytes, not a lossy ordinary-JSON diagnostic, are the oracle.
        self.run('S2-same', profile, mode='same-resave')
        s2 = self.output/'evidence'/f'{self.args.tag}-S2-same'/'data'/'consumed.json'
        self.run('S3-ack', profile, ['--process-old='+str(s2)], mode='retry-ack')
        self.run('resume-commit', profile, ['--recovery-expected='+str(first/'snapshot.exact.json')], kind='recovery', mode='resume')
        self.run('commit-reopen', profile, mode='activate')
        self.run('training', profile, mode='train')
        self.run('camp-edit', profile, mode='edit')
        self.run('edited-reopen', profile, ['--expected-state=CAMP'], mode='inspect')

    def finish(self):
        dump(self.result, dict(status='PASS', cases=self.rows, production_gate='BLOCKED', physical_input='NOT_VERIFIED'))

    def full(self):
        if os.name != 'nt':
            raise RuntimeError('Windows kill and sharing semantics require Windows')
        if not self.args.mixed_journal or not self.args.mixed_journal.resolve().is_relative_to(self.output):
            raise ValueError('Supply the final public codec check mixed-valid journal within this task run')
        if self.args.scope == 'safety':
            main_profile = self.args.profile.resolve()
            if not main_profile.is_relative_to(self.output/'protected-profile') or not main_profile.is_file():
                raise ValueError('Resume only an explicit existing synthetic task profile')
        else:
            self.preflight()
            main_profile = self.profile('world')
            self.run('old-worlds-after-edits',main_profile,mode='replay')
            def contender(process, folder):
                self.run('writer-contender',main_profile,mode='busy')
                self.run('writer-case-alias',Path(str(main_profile).upper()),mode='busy')
            self.run('writer-owner',main_profile,mode='hold',barrier=True,while_held=contender)
        from windows_test_process import WindowsFileLock
        for name, path in [('primary',main_profile),('record',Path(str(main_profile)+'.txn/journal/00000001/record.json')),('binding',Path(str(main_profile)+'.txn/binding.json'))]:
            original = snapshot(main_profile.parent)
            with WindowsFileLock(path):
                self.run('exclusive-'+name,main_profile,['--expected-state=BLOCKED'],mode='inspect',held_files=[path])
            if original != snapshot(main_profile.parent):
                raise RuntimeError('Locked read mutated protected originals')
        # A fresh UI-created synthetic profile per destructive save boundary.
        for point, expected in [('before_record_write','BLOCKED'),('after_record_flush','BLOCKED'),('after_record_publish','SUSPENDED'),('before_binding_write','SUSPENDED'),('after_binding_flush','SUSPENDED')]:
            profile = self.profile('kill-suspend-'+point)
            killed = self.run('kill-suspend-'+point,profile,['--recovery-barrier='+point],kind='recovery',mode='save',barrier=True,kill=True)
            flags = ['--expected-state='+expected]
            if expected == 'SUSPENDED': flags += ['--process-world-expected='+str(killed/'snapshot.exact.json')]
            self.run('restart-suspend-'+point,profile,flags,mode='inspect')
        for point in ['after_record_publish','before_binding_write']:
            profile = self.profile('kill-claim-'+point)
            self.run('claim-seed-'+point,profile,kind='recovery',mode='save')
            self.run('kill-claim-'+point,profile,['--process-barrier='+point,'--barrier-phase=RESUME_CLAIMED'],mode='same-resave',barrier=True,kill=True)
            self.run('restart-claim-'+point,profile,['--expected-state=BLOCKED'],mode='inspect')
        for point in ['ready-published','before_camp_write','after_camp_write','before_commit_receipt','commit-published']:
            profile = self.profile('kill-result-'+point)
            seed=self.run('result-seed-'+point,profile,kind='recovery',mode='save')
            killed=self.run('kill-result-'+point,profile,['--recovery-expected='+str(seed/'snapshot.exact.json'),'--recovery-barrier='+point],kind='recovery',mode='resume',barrier=True,kill=True)
            self.run('restart-result-'+point,profile,['--process-camp-expected='+str(killed/'camp.expected.exact.json')],mode='activate')
        for point, phase in [('after_record_publish','EDIT_READY'),('after_camp_write','')]:
            killed=self.run('kill-training-'+point,main_profile,['--process-barrier='+point,'--barrier-phase='+phase],mode='train',barrier=True,kill=True)
            self.run('restart-training-'+point,main_profile,['--process-camp-expected='+str(killed/'operation.expected.exact.json')],mode='activate')
        self.run('old-worlds-after-training',main_profile,mode='replay')
        journey=self.profile('real-journey')
        self.run('real-rescue-one',journey,kind='camp',mode='hash-rescue',timeout=480)
        self.run('real-rescue-two',journey,kind='camp',mode='hash-rescue',timeout=480)
        death=self.run('real-death-replace-camp',journey,kind='camp',mode='hash-death-replace',timeout=480)
        camp=json.loads((death/'report.json').read_text(encoding='utf-8'))['camp']
        if len(camp['crew']) != 5 or sum(m['health'] > 0 for m in camp['crew']) != 4 or not camp['journey']['deaths'] or not any(m['health'] == 0 and m['condition'] == 'dead' for m in camp['crew']):
            raise RuntimeError('Actual death/replacement contract not reached')
        self.run('real-journey-new-pid',journey,['--expected-state=CAMP','--process-camp-expected='+str(death/'camp.expected.exact.json')],mode='inspect')
        self.run('real-journey-old-worlds',journey,mode='replay')
        fixtures=self.output/'scratch'/f'legacy-{self.args.tag}'
        fixtures.mkdir()
        for path in (ROOT/'tests/synthetic').glob('*.json'):
            shutil.copy2(path,fixtures/path.name)
        self.run('legacy-camp',self.profile('legacy'),['--legacy-fixtures='+str(fixtures)],mode='legacy')
        self.run('mixed-chain-new-pid',self.profile('mixed'),['--process-journal='+str(self.args.mixed_journal.resolve())],mode='journal-read')
        if self.args.legacy_exe:
            profile=self.profile('downgrade')
            self.run('downgrade-new-save',profile,kind='recovery',mode='save')
            before=snapshot(profile.parent)
            current=self.engine
            try:
                self.engine=str(self.args.legacy_exe.resolve())
                self.run('old-exe-refuses-new-records',profile,kind='recovery',mode='blocked')
            finally:
                self.engine=current
            if before != snapshot(profile.parent):
                raise RuntimeError('Old executable modified new-format synthetic originals')
        if self.args.native:
            profile=self.profile('native')
            seed=self.run('native-S1',profile,kind='recovery',mode='save',native=True,movie=True)
            self.run('native-resume-result',profile,['--recovery-expected='+str(seed/'snapshot.exact.json')],kind='recovery',mode='resume',native=True)
            self.run('native-camp-new-pid',profile,mode='activate')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path)
    parser.add_argument('--exe', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--tag', required=True)
    parser.add_argument('--scope', choices=['preflight','full','safety'], default='preflight')
    parser.add_argument('--profile',type=Path,help='Existing synthetic profile for continuing safety cases only')
    parser.add_argument('--mixed-journal',type=Path,help='Authenticated mixed-valid fixture from the final public codec check')
    parser.add_argument('--legacy-exe',type=Path,help='Read-only older executable for explicit synthetic downgrade refusal')
    parser.add_argument('--native',action='store_true',help='Render on a separate Windows desktop, without switching desktops or OS input')
    args = parser.parse_args()
    if (args.godot is None) == (args.exe is None):
        parser.error('Specify exactly one of --godot or --exe')
    if args.scope == 'safety' and args.profile is None:
        parser.error('--scope safety requires --profile')
    matrix = Matrix(args)
    try:
        matrix.full() if args.scope in ['full','safety'] else matrix.preflight()
        matrix.finish()
    except Exception:
        dump(matrix.result, dict(status='FAIL', cases=matrix.rows, production_gate='BLOCKED', physical_input='NOT_VERIFIED'))
        raise


if __name__ == '__main__':
    main()
