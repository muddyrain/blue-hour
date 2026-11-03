"""Process isolation only: named Windows desktop, never switch or inject OS input."""
import ctypes, os, subprocess
from ctypes import wintypes as W

K=ctypes.WinDLL('kernel32',use_last_error=True)
U=ctypes.WinDLL('user32',use_last_error=True)
class SI(ctypes.Structure):
    _fields_=[('cb',W.DWORD),('lpReserved',W.LPWSTR),('lpDesktop',W.LPWSTR),('lpTitle',W.LPWSTR),('dwX',W.DWORD),('dwY',W.DWORD),('dwXSize',W.DWORD),('dwYSize',W.DWORD),('dwXCountChars',W.DWORD),('dwYCountChars',W.DWORD),('dwFillAttribute',W.DWORD),('dwFlags',W.DWORD),('wShowWindow',W.WORD),('cbReserved2',W.WORD),('lpReserved2',ctypes.c_void_p),('hStdInput',W.HANDLE),('hStdOutput',W.HANDLE),('hStdError',W.HANDLE)]
class PI(ctypes.Structure):
    _fields_=[('hProcess',W.HANDLE),('hThread',W.HANDLE),('dwProcessId',W.DWORD),('dwThreadId',W.DWORD)]
U.CreateDesktopW.argtypes=[W.LPCWSTR,W.LPCWSTR,ctypes.c_void_p,W.DWORD,W.DWORD,ctypes.c_void_p]
U.CreateDesktopW.restype=W.HANDLE
U.CloseDesktop.argtypes=[W.HANDLE]
K.CreateProcessW.argtypes=[W.LPCWSTR,W.LPWSTR,ctypes.c_void_p,ctypes.c_void_p,W.BOOL,W.DWORD,ctypes.c_void_p,W.LPCWSTR,ctypes.POINTER(SI),ctypes.POINTER(PI)]
K.CreateProcessW.restype=W.BOOL
K.WaitForSingleObject.argtypes=[W.HANDLE,W.DWORD]
K.GetExitCodeProcess.argtypes=[W.HANDLE,ctypes.POINTER(W.DWORD)]
K.TerminateProcess.argtypes=[W.HANDLE,W.UINT]
K.CloseHandle.argtypes=[W.HANDLE]

class DesktopProcess:
    def __init__(self,cmd,cwd,env,stdout,stderr):
        import msvcrt
        self.name='BHValidation'+str(os.getpid())
        self.desktop=U.CreateDesktopW(self.name,None,None,0,0x01ff,None)
        if not self.desktop: raise ctypes.WinError(ctypes.get_last_error())
        self.stdin=open(os.devnull,'rb')
        si=SI();si.cb=ctypes.sizeof(si);si.lpDesktop='winsta0\\'+self.name
        si.dwFlags=0x100
        for field,file in [('hStdInput',self.stdin),('hStdOutput',stdout),('hStdError',stderr)]:
            handle=msvcrt.get_osfhandle(file.fileno());os.set_handle_inheritable(handle,True);setattr(si,field,handle)
        self.pi=PI()
        block=ctypes.create_unicode_buffer('\0'.join(k+'='+v for k,v in sorted(env.items()))+'\0\0')
        line=ctypes.create_unicode_buffer(subprocess.list2cmdline(cmd))
        ok=K.CreateProcessW(None,line,None,None,True,0x400|0x08000000,block,str(cwd),ctypes.byref(si),ctypes.byref(self.pi))
        if not ok:
            U.CloseDesktop(self.desktop);self.stdin.close()
            raise ctypes.WinError(ctypes.get_last_error())
        K.CloseHandle(self.pi.hThread)
        self.pid=self.pi.dwProcessId
    def poll(self):
        if K.WaitForSingleObject(self.pi.hProcess,0)==258:return None
        result=W.DWORD();K.GetExitCodeProcess(self.pi.hProcess,ctypes.byref(result));return result.value
    def kill(self):K.TerminateProcess(self.pi.hProcess,1)
    def wait(self):
        K.WaitForSingleObject(self.pi.hProcess,0xffffffff)
        code=self.poll();K.CloseHandle(self.pi.hProcess);U.CloseDesktop(self.desktop);self.stdin.close()
        return code


class WindowsFileLock:
    """Keep a real exclusive file handle until the owned case has exited."""
    def __init__(self, path):
        create = K.CreateFileW
        create.argtypes = [W.LPCWSTR, W.DWORD, W.DWORD, ctypes.c_void_p, W.DWORD, W.DWORD, W.HANDLE]
        create.restype = W.HANDLE
        self.handle = create(str(path), 0xc0000000, 0, None, 3, 0x80, None)
        if self.handle == ctypes.c_void_p(-1).value:
            raise ctypes.WinError(ctypes.get_last_error())
    def __enter__(self):
        return self
    def __exit__(self, *args):
        K.CloseHandle(self.handle)
