import os, pty, time, select, sys
CMD = sys.argv[1].encode()
pid, fd = pty.fork()
if pid == 0:
    os.execvp("virsh", ["virsh","-c","qemu:///system","console",sys.argv[2],"--force"])
else:
    seq = [b"\n", b"lab\n", b"lab\n", CMD + b"\n"]
    time.sleep(2)
    for c in seq:
        os.write(fd, c); time.sleep(2.5)
    end = time.time() + float(sys.argv[3])
    buf=b""
    while time.time() < end:
        r,_,_ = select.select([fd],[],[],0.5)
        if r:
            try: d=os.read(fd,4096)
            except OSError: break
            if not d: break
            buf+=d
    os.write(fd,b"\x1d"); time.sleep(0.4)
    sys.stdout.buffer.write(buf); sys.stdout.flush()
    os.kill(pid,9)
