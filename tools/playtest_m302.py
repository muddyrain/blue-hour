"""Same build, separate native processes, four resource choices plus migration and corruption."""
import argparse
import ctypes
from ctypes import wintypes
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time
from godot import ROOT, LOCK, engine_path
from playtest_m301 import binding


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def lock_file(path):
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.CreateFileW.argtypes = [wintypes.LPCWSTR,wintypes.DWORD,wintypes.DWORD,ctypes.c_void_p,
                                  wintypes.DWORD,wintypes.DWORD,wintypes.HANDLE]
    kernel.CreateFileW.restype = wintypes.HANDLE
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    handle = kernel.CreateFileW(str(path),0x80000000,1,None,3,0,None)
    if handle == wintypes.HANDLE(-1).value:
        raise ctypes.WinError(ctypes.get_last_error())
    return kernel, handle


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", action="store_true")
    parser.add_argument("--output",type=Path,required=True)
    parser.add_argument("--size",default="1280x720")
    parser.add_argument("--record",action="store_true")
    parser.add_argument("--modes",default="day1,day2,day3,day4,reopen,legacy,corrupt")
    args = parser.parse_args()
    output=args.output.resolve()
    output.relative_to((ROOT/".local").resolve())
    output.mkdir(parents=True,exist_ok=False)
    exe=Path(engine_path(None)) if args.source else ROOT/"builds/windows/blue-hour.exe"
    if args.source and exe.name.endswith("_console.exe"):
        candidate=exe.with_name(exe.name.replace("_console.exe",".exe"))
        probe=subprocess.run([str(candidate),"--version"],capture_output=True,text=True,timeout=15)
        if probe.returncode or probe.stdout.strip()!=LOCK:
            raise RuntimeError("Source GUI engine version mismatch")
        exe=candidate
    before=binding(args.source)
    progress=output/"progress/run.json"
    audio=output/"audio/audio.json"
    env=os.environ.copy()
    user=output/"user"
    user.mkdir()
    env.update(APPDATA=str(user),XDG_DATA_HOME=str(user))
    expected=None
    processes=[]
    states=[]
    modes=args.modes.split(",")
    if any(m not in ("day1","day2","day3","day4","reopen","legacy","corrupt") for m in modes):
        raise ValueError("Unknown proof mode")
    for mode in modes:
        stage=output/mode
        stage.mkdir()
        target=progress
        if mode=="legacy":
            target=output/"legacy-progress/run.json"
            target.parent.mkdir()
            shutil.copyfile(ROOT/"tests/fixtures/m3-01/final-second/saved-run.json",target)
            shutil.copyfile(ROOT/"tests/fixtures/m3-01/final-first/saved-run.json",target.with_suffix(".json.bak"))
            expected=target
        elif mode=="corrupt":
            target=output/"corrupt-progress/run.json"
            target.parent.mkdir()
            target.write_bytes(b'{"schema_version":2,"food":')
            shutil.copyfile(progress,target.with_suffix(".json.bak"))
            expected=target.with_suffix(".json.bak")
        command=[str(exe),"--rendering-method","gl_compatibility","--resolution",args.size,
                 "--log-file",str(stage/"engine.log")]
        if args.source:
            command += ["--path",str(ROOT)]
        if args.record:
            command += ["--write-movie",str(stage/"native-run.avi"),"--fixed-fps","30","--disable-vsync"]
        command += ["--","--verify-m302="+str(stage),"--m302-mode="+mode,
                    "--bh-progress="+str(target),"--bh-audio-settings="+str(audio)]
        if expected:
            command += ["--m302-expected="+str(expected)]
        (stage/"command.json").write_text(json.dumps(command,indent=2),encoding="utf-8")
        held=None
        if mode=="day3":
            held=lock_file(target)
        started=datetime.datetime.now(datetime.timezone.utc).isoformat()
        try:
            with (stage/"run.txt").open("w",encoding="utf-8") as log:
                process=subprocess.Popen(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,env=env)
                deadline=time.monotonic()+300
                while process.poll() is None:
                    if held and (stage/"release-lock.request").exists():
                        kernel,handle=held
                        if not kernel.CloseHandle(handle):
                            raise ctypes.WinError(ctypes.get_last_error())
                        held=None
                        (stage/"lock-released.json").write_text(json.dumps({"released":True,"utc":datetime.datetime.now(datetime.timezone.utc).isoformat()}),encoding="utf-8")
                    text=(stage/"run.txt").read_text(encoding="utf-8",errors="replace")
                    if re.search(r"(?m)^(?:SCRIPT ERROR|ERROR):",text):
                        process.terminate()
                        process.wait(timeout=10)
                        raise RuntimeError(f"Native failure, process stopped; inspect {stage}")
                    if time.monotonic()>deadline:
                        process.kill()
                        process.wait()
                        raise RuntimeError(f"Native proof timed out: {stage}")
                    time.sleep(0.05)
                code=process.returncode
        finally:
            if held:
                held[0].CloseHandle(held[1])
        report_path=stage/"run-report.json"
        report=json.loads(report_path.read_text(encoding="utf-8")) if report_path.exists() else None
        item={"mode":mode,"pid":process.pid,"report_pid":report.get("pid") if report else None,
              "started_utc":started,"ended_utc":datetime.datetime.now(datetime.timezone.utc).isoformat(),"exit_code":code}
        processes.append(item)
        (output/"processes.json").write_text(json.dumps(processes,indent=2),encoding="utf-8")
        plain=re.sub(r"\x1b\[[0-9;]*m","",(stage/"run.txt").read_text(encoding="utf-8"))
        if code or not report or report["failures"] or report["pid"]!=process.pid or re.search(r"(?m)^(?:SCRIPT ERROR|ERROR|WARNING):",plain):
            raise RuntimeError(f"FAIL native {mode}; inspect {stage}")
        for p in (target,target.with_suffix(".json.bak"),audio):
            if p.exists():
                shutil.copyfile(p,stage/("saved-audio.json" if p==audio else "saved-"+p.name))
        if binding(args.source)!=before:
            raise RuntimeError("Source/binary inputs changed during proof")
        if mode in ("day1","day2","day3","day4"):
            states.append({"mode":mode,"pid":process.pid,"before":report["before"],"state":report["state"]})
            expected=stage/"camp.json"
        print(f"PASS native {mode}: pid={process.pid}, behavior={report['behavior_checks']}, screenshots={report['capture_checks']}, day={report['state']['day']} food={report['state']['food']} cash={report['state']['cash']}",flush=True)
    (output/"binding.json").write_text(json.dumps({"inputs":before,"unchanged":binding(args.source)==before},indent=2),encoding="utf-8")
    (output/"days.json").write_text(json.dumps(states,indent=2),encoding="utf-8")
    print(f"PASS separate native processes; {output}")


if __name__=="__main__":
    main()
