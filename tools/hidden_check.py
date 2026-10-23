"""Bounded hidden child runner; terminate only its owned handle on fatal compilation."""
import os
import re
import subprocess
import threading
import time

FATAL = re.compile(r"Parse Error:|Compile Error:|Failed to load script .*Compilation failed")

def run_hidden(command, *, env=None, timeout=60):
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, encoding="utf-8", errors="replace", env=env,
        creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
    lines=[]
    fatal=threading.Event()
    def read():
        for line in process.stdout:
            lines.append(line)
            if FATAL.search(line): fatal.set()
    reader=threading.Thread(target=read,daemon=True)
    reader.start()
    started=time.monotonic()
    timed_out=False
    while process.poll() is None:
        if fatal.is_set() or time.monotonic()-started >= timeout:
            timed_out=not fatal.is_set()
            process.terminate()  # Handle belongs to this exact launched child.
            try: process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=3)
            break
        try: process.wait(timeout=0.05)
        except subprocess.TimeoutExpired: pass
    reader.join(timeout=3)
    output="".join(lines)
    if timed_out:
        raise subprocess.TimeoutExpired(command,timeout,output=output.encode("utf-8"),stderr=b"")
    if fatal.is_set(): output+="\nFAIL fatal compilation stopped this owned background test.\n"
    return subprocess.CompletedProcess(command,process.returncode,output,"")

if __name__=="__main__":
    import sys
    start=time.monotonic()
    normal=run_hidden([sys.executable,"-c","print('normal child')"],timeout=2)
    assert normal.returncode==0 and "normal child" in normal.stdout
    broken=run_hidden([sys.executable,"-c","import time;print('Parse Error: test fixture',flush=True);time.sleep(30)"],timeout=2)
    assert "FAIL fatal compilation" in broken.stdout
    try: run_hidden([sys.executable,"-c","import time;time.sleep(30)"],timeout=0.15)
    except subprocess.TimeoutExpired: pass
    else: raise AssertionError("Owned child timeout did not fire")
    assert time.monotonic()-start<4
    print("Hidden child runner: normal exit, fatal compile and owned timeout passed.")
