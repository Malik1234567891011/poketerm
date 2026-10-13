"""Run a real Claude Code session in a pty, emulate the screen with pyte, and
save the raw output stream so tools/render.py can draw it through the shader.

  .venv/bin/python cc_capture.py out.bin [cols] [rows]
"""
import os
import pty
import select
import sys
import time

out = sys.argv[1]
cols = int(sys.argv[2]) if len(sys.argv) > 2 else 110
rows = int(sys.argv[3]) if len(sys.argv) > 3 else 32
env = {k: v for k, v in os.environ.items() if not k.startswith("CLAUDE")}
env.update(TERM="xterm-256color", COLORTERM="truecolor", TERM_PROGRAM="ghostty", COLUMNS=str(cols), LINES=str(rows))

pid, fd = pty.fork()
if pid == 0:
    import fcntl, struct, termios
    fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    os.chdir(os.path.expanduser("~/poketerm"))
    os.execvpe("claude", ["claude"], env)

import fcntl, struct, termios
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
buf = bytearray()
script = [(6.0, b"\x1b[B"), (6.6, b"\r"), (11.0, b"In one short sentence, what is a Pikachu?"), (11.8, b"\r")]
t0 = time.time()
snaps = {}
while time.time() - t0 < 40:
    r, _, _ = select.select([fd], [], [], 0.05)
    if r:
        try:
            data = os.read(fd, 65536)
        except OSError:
            break
        if not data:
            break
        buf += data
        # answer the common terminal queries so the app doesn't stall
        if b"\x1b[c" in data or b"\x1b[0c" in data:
            os.write(fd, b"\x1b[?62;22c")
        if b"\x1b[>q" in data or b"\x1b[>0q" in data:
            os.write(fd, b"\x1bP>|ghostty 1.3.1\x1b\\")
        if b"\x1b]11;?" in data:
            os.write(fd, b"\x1b]11;rgb:1111/1313/1c1c\x1b\\")
    el = time.time() - t0
    while script and el >= script[0][0]:
        os.write(fd, script.pop(0)[1])
    for mark in (5.5, 9.0, 13.0, 18.0, 30.0, 39.5):
        if el >= mark and mark not in snaps:
            snaps[mark] = bytes(buf)
            open(f"{out}.{mark:g}", "wb").write(snaps[mark])
os.kill(pid, 9)
open(out, "wb").write(bytes(buf))
print("captured", len(buf), "bytes; snapshots", sorted(snaps))
