"""Verdict and timeout regressions for the destructive-case orchestration boundary."""
import importlib.util
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('record_hash_matrix',ROOT/'tools/record_hash_matrix.py')
module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class VerdictTests(unittest.TestCase):
    def verdict(self,text='',barrier=None,outcome='WINDOWS_TERMINATEPROCESS_AT_OBSERVED_BARRIER',unchanged=True):
        return module.accepted_case(1,False,None,text,outcome,{'pid':123,'failures':0} if barrier is None else barrier,unchanged)

    def test_healthy_observed_kill_passes(self):
        self.assertTrue(self.verdict())

    def test_prebarrier_errors_never_pass(self):
        for text in ['SCRIPT ERROR: invalid object\n','ERROR: prior assertion\n','FAILED precondition\n','\x1b[31mSCRIPT ERROR: invalid object\x1b[0m\n']:
            with self.subTest(text=text):self.assertFalse(self.verdict(text))

    def test_missing_or_failed_barrier_prerequisites_refused(self):
        self.assertFalse(self.verdict(barrier={'pid':123}))
        self.assertFalse(self.verdict(barrier={'pid':123,'failures':1}))

    def test_timeout_and_changed_originals_refused(self):
        self.assertFalse(self.verdict(outcome='TIMEOUT'))
        self.assertFalse(self.verdict(unchanged=False))

    def test_normal_exit_requires_results_and_no_failures(self):
        self.assertTrue(module.accepted_case(0,True,0,'','normal_exit',None,False))
        self.assertFalse(module.accepted_case(0,False,0,'','normal_exit',None,False))
        self.assertFalse(module.accepted_case(0,True,1,'','normal_exit',None,False))
        self.assertFalse(module.accepted_case(0,True,0,'FAILED assertion\n','normal_exit',None,False))

    def test_malformed_barrier_cannot_bypass_deadline(self):
        parent=ROOT/'.local/p0-record-hash-02/win-01/scratch/runner-unit-tests'
        parent.mkdir(parents=True,exist_ok=True)
        with tempfile.TemporaryDirectory(dir=parent) as temporary:
            output=Path(temporary)
            for name in ['evidence','report','protected-profile']:(output/name).mkdir()
            profile=output/'protected-profile/run.enemy-v1.json'
            profile.write_text('{}',encoding='utf-8')
            matrix=module.Matrix.__new__(module.Matrix)
            matrix.output=output;matrix.args=SimpleNamespace(tag='unit',exe=Path('synthetic.exe'))
            matrix.engine='synthetic.exe';matrix.result=output/'report/result.json';matrix.rows=[]
            calls={'kill':0,'sleep':0,'clock':0}
            class Child:
                pid=123
                def __init__(self,*args,**kwargs):
                    data=Path(kwargs['stdout'].name).parent/'data';data.mkdir()
                    (data/'barrier.json').write_text('{incomplete',encoding='utf-8')
                def poll(self):return None
                def kill(self):calls['kill']+=1
                def wait(self):return 1
            def clock():calls['clock']+=1;return calls['clock']*0.1
            def sleep(seconds):
                calls['sleep']+=1
                if calls['sleep']>10:raise AssertionError('malformed barrier retry was unbounded')
            with patch.object(module.subprocess,'Popen',Child),patch.object(module.time,'monotonic',clock),patch.object(module.time,'sleep',sleep):
                with self.assertRaises(RuntimeError):matrix.run('malformed',profile,barrier=True,kill=True,timeout=.25)
            self.assertEqual(calls['kill'],1)
            self.assertEqual(matrix.rows[-1]['outcome'],'TIMEOUT')
            self.assertFalse(matrix.rows[-1]['pass'])


if __name__=='__main__':unittest.main()
