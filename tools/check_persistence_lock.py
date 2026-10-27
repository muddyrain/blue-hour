"""Windows filesystem replacement failure: hold current file without delete sharing."""
import ctypes
from ctypes import wintypes
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
from godot import ROOT, LOGS, engine_path


def main():
    if sys.platform != "win32":
        print("SKIP Windows save lock: platform is not Windows")
        return
    directory = LOGS / ("save-lock-" + datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f"))
    directory.mkdir(parents=True, exist_ok=False)
    target = directory / "run.json"
    identity = "0123456789abcdef0123456789abcdef"
    for count, path in ((2, target), (1, target.with_suffix(".json.bak"))):
        data = dict(schema_version=1, profile_id=identity, day=count+2, cash=53+count*4,
                    settled_sorties=count, last_settlement_id=f"{identity}:{count}",
                    crew=[dict(id=1, health=200.0), dict(id=2, health=196.0)])
        path.write_text(json.dumps(data, indent=2), encoding="utf-8")
    files = [target, target.with_suffix(".json.bak")]
    before = {p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.CreateFileW.argtypes = [wintypes.LPCWSTR,wintypes.DWORD,wintypes.DWORD,ctypes.c_void_p,
                                  wintypes.DWORD,wintypes.DWORD,wintypes.HANDLE]
    kernel.CreateFileW.restype = wintypes.HANDLE
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    handle = kernel.CreateFileW(str(target), 0x80000000, 1, None, 3, 0, None)
    if handle == wintypes.HANDLE(-1).value:
        raise ctypes.WinError(ctypes.get_last_error())
    env = os.environ.copy()
    env.update(APPDATA=str(directory / "user"), XDG_DATA_HOME=str(directory / "user"))
    try:
        command = [engine_path(None), "--headless", "--audio-driver", "Dummy", "--path", str(ROOT),
                   "--log-file", str(directory / "engine.log"), "--script", "res://tests/persistence_locked.gd",
                   "--", "--locked-save=" + str(target)]
        with (directory / "run.txt").open("w", encoding="utf-8") as log:
            result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=30, env=env, cwd=ROOT)
    finally:
        kernel.CloseHandle(handle)
    after = {p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    text = (directory / "run.txt").read_text(encoding="utf-8")
    passed = result.returncode == 0 and before == after and "BH_LOCKED_SAVE error=" in text
    (directory / "report.json").write_text(json.dumps(dict(passed=passed,before=before,after=after,
        exit_code=result.returncode,method="real Windows handle denies write/delete sharing; not a production fault flag"),indent=2),encoding="utf-8")
    if not passed:
        raise RuntimeError(f"Save lock fixture failed: {directory}")
    print(text)
    print(f"PASS Windows locked replacement: current and backup hashes unchanged; {directory}")


if __name__ == "__main__":
    main()
