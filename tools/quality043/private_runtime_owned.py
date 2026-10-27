"""Source-only adapter; importing this file does not load a DLL or launch anything.

Future Root/TestBridge use (NOT authorization to run):
    child = launch_private_owned(command, environment, cwd, binary_log, envelope)
    # Same poll(), sample(), kill(), pid and resource envelope as OwnedChild.
    drained = child.close(absolute_monotonic_cleanup_deadline)
close() False retains the owned job/desktop for bounded cleanup; do not report
success or release the test lane. On construction failure, error.owned_child
retains a cleanup target when needed. Preserve the outer job deadline.

Caller supplies pinned executable/identity checks, synthetic saves, muted audio,
windowed arguments and the unchanged memory/CPU/affinity/process-count envelope.
Caller must have no other inheritable desktop handles (shared launcher inherits
handles). Default station ACLs apply: this is no security sandbox. GPU/VRAM,
desktop heap, drivers and rendering stalls remain shared and uncapped here.
No desktop activation/input APIs; no GPU/display/performance proof from source.
"""
OWNED_SOURCE = ("C:/Users/bligh/Documents/Codex/2026-10-20/how/work/"
                "resume-v030-v038/qa-sol/qa/fast-suite-r4-sol/owned_child.py")
OWNED_SHA256 = "d1827e315760bd07bf8a431162b7b4cfd94ba170a1c2c243e5edd868e722fae4"


def launch_private_owned(command, environment, cwd, log, envelope):
    """Launch only when the caller owns the shared lane and GPU authorization."""
    import ctypes as C
    from ctypes import wintypes as W
    import hashlib
    import os
    from pathlib import Path
    import time
    import types
    import uuid

    if os.name != "nt":
        raise OSError("Windows only")
    source = Path(OWNED_SOURCE).read_bytes()
    if hashlib.sha256(source).hexdigest() != OWNED_SHA256:
        raise RuntimeError("Immutable OwnedChild source identity changed")
    # Per-launch namespace: never patch the shared module or its on-disk file.
    base = types.ModuleType("_private_runtime_owned_source")
    exec(compile(source, OWNED_SOURCE, "exec"), base.__dict__)
    user = C.WinDLL("user32", use_last_error=True)
    user.CreateDesktopW.argtypes = [W.LPCWSTR, W.LPCWSTR, C.c_void_p,
                                   W.DWORD, W.DWORD, C.c_void_p]
    user.CreateDesktopW.restype = W.HANDLE
    user.CloseDesktop.argtypes, user.CloseDesktop.restype = [W.HANDLE], W.BOOL
    desktop_name = "BrassTideQA_" + uuid.uuid4().hex

    class Startup(base.Startup):
        def __init__(self):
            super().__init__()
            self.desktop = desktop_name  # STARTUPINFOW.lpDesktop, same station.

    base.Startup = Startup

    class PrivateOwnedChild(base.OwnedChild):
        def close(self, deadline):
            if getattr(self, "job", None):
                pi = getattr(self, "pi", None)
                pending = pi and pi.process
                if pending:
                    # Exact creation handle also covers failed job assignment.
                    self.k.TerminateProcess(pi.process, 130)
                self.kill()  # Only the inherited owned job, never a PID search.
                while True:
                    usage = base.Accounting()
                    self._check(self.k.QueryInformationJobObject(
                        self.job, 1, C.byref(usage), C.sizeof(usage), None))
                    if usage.active == 0 and (not pending or
                            self.k.WaitForSingleObject(pi.process, 0) == 0):
                        break
                    remaining = deadline - time.monotonic()
                    if remaining <= 0:
                        return False  # Keep BOTH handles for caller cleanup.
                    time.sleep(min(0.01, remaining))
                # Zero active processes is proven before inherited handle cleanup.
                # Its return may be False if the deadline just elapsed; the above
                # proof still holds (an empty, private job cannot spawn a child).
                super().close(deadline)
            if self.desktop_handle:
                if not user.CloseDesktop(self.desktop_handle):
                    raise C.WinError(C.get_last_error())
                self.desktop_handle = None
            return True

    child = PrivateOwnedChild.__new__(PrivateOwnedChild)
    child.desktop_name, child.desktop_handle = desktop_name, None
    # DESKTOP_READOBJECTS | DESKTOP_CREATEWINDOW | DESKTOP_WRITEOBJECTS.
    # No generic rights, hook rights, or DESKTOP_SWITCHDESKTOP (0x100).
    # NULL security attributes: non-inheritable handle; no ACL modification.
    child.desktop_handle = user.CreateDesktopW(desktop_name, None, None,
                                               0, 0x0083, None)
    if not child.desktop_handle:
        raise C.WinError(C.get_last_error())  # No process/default-desktop fallback.
    try:
        base.OwnedChild.__init__(child, command, environment, cwd, log, envelope)
    except BaseException as error:
        # The inherited constructor invokes our close() on ordinary failure.
        # A retained job means drain was not proven; keep it reachable for Root.
        error.owned_child = child
        if not getattr(child, "job", None):
            try:
                child.close(time.monotonic())
            except BaseException as cleanup_error:
                cleanup_error.owned_child = child
                raise
        raise
    return child
