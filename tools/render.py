"""Offline renderer: runs the real poketerm shader over a simulated terminal.

Lets the shader be previewed (and recorded) without a visible Ghostty window.
  .venv/bin/python render.py demo out_dir [seconds] [fps]
Produces out_dir/frame_XXXX.png; stitch with ffmpeg.
"""
import os
import pathlib
import re
import sys

import moderngl
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
FONT = os.path.expanduser("~/Library/Fonts/DepartureMono-Regular.otf")
SCALE = 2           # retina
PT = 14             # font-size in the Ghostty config
BG = (0x11, 0x13, 0x1C)
FG = (0xE8, 0xE3, 0xD3)
CURSOR = (0xFF, 0xD2, 0x3F)
PAD_X, PAD_TOP, PAD_BOT = 16 * SCALE, 12 * SCALE, 28 * SCALE

PRELUDE = """#version 410 core
#define POKETERM_HARNESS 1
uniform vec3  iResolution;
uniform float iTime;
uniform float iTimeDelta;
uniform float iFrameRate;
uniform int   iFrame;
uniform vec4  iMouse;
uniform vec4  iDate;
uniform vec4  iCurrentCursor;
uniform vec4  iPreviousCursor;
uniform vec4  iCurrentCursorColor;
uniform vec4  iPreviousCursorColor;
uniform int   iCurrentCursorStyle;
uniform int   iPreviousCursorStyle;
uniform int   iCursorVisible;
uniform float iTimeCursorChange;
uniform float iTimeFocus;
uniform int   iFocus;
uniform vec3  iPalette[256];
uniform vec3  iBackgroundColor;
uniform vec3  iForegroundColor;
uniform vec3  iCursorColor;
uniform vec3  iCursorText;
uniform vec3  iSelectionForegroundColor;
uniform vec3  iSelectionBackgroundColor;
#define CURSORSTYLE_BLOCK        0
#define CURSORSTYLE_BLOCK_HOLLOW 1
#define CURSORSTYLE_BAR          2
#define CURSORSTYLE_UNDERLINE    3
#define CURSORSTYLE_LOCK         4
uniform sampler2D iChannel0;
out vec4 _fragColor;
void mainImage(out vec4 fragColor, in vec2 fragCoord);
void main() { mainImage(_fragColor, vec2(gl_FragCoord.x, iResolution.y - gl_FragCoord.y)); }
"""

SGR = re.compile(r"\x1b\[([0-9;]*)m")


class Term:
    def __init__(self, cols, rows):
        self.cols, self.rows = cols, rows
        self.lines = [[] for _ in range(rows)]
        self.row = self.col = 0
        self.fg = FG
        self.visible = True
        self.claude = 0   # palette-255 state code from claude/state.zsh

    def write(self, s):
        pos = 0
        for m in SGR.finditer(s):
            self._text(s[pos:m.start()])
            self._sgr(m.group(1))
            pos = m.end()
        self._text(s[pos:])

    def _sgr(self, params):
        p = [int(x) for x in params.split(";") if x] or [0]
        if p[0] == 0:
            self.fg = FG
        elif p[:2] == [38, 2]:
            self.fg = tuple(p[2:5])

    def _text(self, s):
        for ch in s:
            if ch == "\n":
                self.row += 1
                self.col = 0
                if self.row >= self.rows:
                    self.lines.pop(0)
                    self.lines.append([])
                    self.row = self.rows - 1
                continue
            line = self.lines[self.row]
            while len(line) <= self.col:
                line.append((" ", FG))
            line[self.col] = (ch, self.fg)
            self.col += 1

    def backspace(self):
        self.col = max(0, self.col - 1)
        line = self.lines[self.row]
        if self.col < len(line):
            line[self.col] = (" ", FG)


def timeline(name):
    """Return [(time, fn(term))] events for a named scenario."""
    ev = []
    if name.startswith("ansi:"):
        raw = open(name[5:], "rb").read()
        def show(T):
            S = from_ansi(raw, T.cols, T.rows)
            T.__dict__.update(S.__dict__)
        return [(0.0, show)]
    t = 1.3

    def at(dt, fn):
        nonlocal t
        t += dt
        ev.append((t, fn))

    def typeit(s, d=0.08):
        for ch in s:
            at(d, lambda T, ch=ch: T.write(ch))

    E = "\x1b"
    ink = lambda rgb, s: f"{E}[38;2;{rgb}m{s}{E}[0m"
    at(0, lambda T: T.write("~/poketerm ❯ "))
    if name == "demo":
        at(0.5, lambda T: None)
        typeit("git status")
        at(0.4, lambda T: T.write("\nOn branch main\nnothing to commit, working tree clean\n~/poketerm ❯ "))
        at(1.2, lambda T: T.write("\n  " + ink("255;209;5", "ELECTRIC INK  crackles with current")
                                  + "\n  " + ink("240;183;253", "SHINY INK  holographic like a shiny")
                                  + "\n  " + ink("255;106;19", "FIRE INK  burns from below")
                                  + "\n  " + ink("156;124;243", "GHOST INK  wobbles like Gengar")
                                  + "\n  normal text stays normal\n~/poketerm ❯ "))
        at(0.8, lambda T: None)
        typeit("echo pika pika", 0.1)
        at(0.5, lambda T: T.backspace())
        at(0.12, lambda T: T.backspace())
        at(0.12, lambda T: T.backspace())
        typeit("chu", 0.12)
        at(0.6, lambda T: T.write("\npika pchu\n~/poketerm ❯ "))
        at(0.7, lambda T: None)
        typeit("cat pokedex.txt", 0.07)
        at(0.4, lambda T: T.write("\ncat: pokedex.txt: No such file or directory\n\n~/poketerm " + ink("156;124;243", "fainted 1") + " ❯ "))
    if name == "claude":
        # Claude Code takes over (cursor hidden), works for a long time, asks, finishes.
        # Timeline is compressed: each state is held for a few seconds.
        def claude_ui(T):
            T.visible = False
            T.write("claude\n\n" + ink("255;209;5", "✻ Thunderbolting…") + "  (esc to interrupt)\n\n> fix the flaky test\n")
        at(0.8, claude_ui)
        for code, hold in ((1, 3.0), (2, 3.0), (3, 3.0), (4, 3.5), (5, 2.5)):
            at(hold if code > 1 else 0.6, lambda T, c=code: setattr(T, "claude", c))
        for code in range(6, 14):
            at(0.2, lambda T, c=code: setattr(T, "claude", c))
        at(0.2, lambda T: setattr(T, "claude", 0))
    if name == "hops":
        # a few quick commands so the party hops line to line, then one fails
        for cmd in ("ls", "pwd", "whoami"):
            at(1.4, lambda T: None)
            typeit(cmd, 0.06)
            at(0.3, lambda T, c=cmd: T.write("\n" + {"ls": "art bin claude", "pwd": "/Users/ash/poketerm", "whoami": "ash"}[c] + "\n~/poketerm ❯ "))
        at(1.2, lambda T: None)
        typeit("cat pokedex.txt", 0.05)
        at(0.4, lambda T: T.write("\ncat: pokedex.txt: No such file or directory\n\n~/poketerm " + ink("156;124;243", "fainted 1") + " ❯ "))
    return ev


class Renderer:
    def __init__(self, cols=int(os.environ.get("COLS", 92)), rows=int(os.environ.get("ROWS", 22))):
        self.font = ImageFont.truetype(FONT, PT * SCALE)
        asc, desc = self.font.getmetrics()
        self.cw = round(self.font.getlength("M"))
        self.ch = round((asc + desc) * 1.12)
        self.asc = asc
        self.cols, self.rows = cols, rows
        self.W = PAD_X * 2 + cols * self.cw
        self.H = PAD_TOP + PAD_BOT + rows * self.ch
        self.ctx = moderngl.create_standalone_context(require=410)
        src = (ROOT / "shaders" / "poketerm.glsl").read_text()
        self.prog = self.ctx.program(
            vertex_shader="#version 410 core\nin vec2 p; void main(){ gl_Position = vec4(p,0,1); }",
            fragment_shader=PRELUDE + src)
        vbo = self.ctx.buffer(np.array([-1, -1, 1, -1, -1, 1, 1, 1], dtype="f4").tobytes())
        self.vao = self.ctx.vertex_array(self.prog, [(vbo, "2f", "p")])
        self.fbo = self.ctx.simple_framebuffer((self.W, self.H))
        self.tex = self.ctx.texture((self.W, self.H), 4)

    def cell_xy(self, row, col):
        return PAD_X + col * self.cw, PAD_TOP + row * self.ch

    def draw_term(self, T):
        img = Image.new("RGBA", (self.W, self.H), BG + (255,))
        d = ImageDraw.Draw(img)
        for (r, c), bgc in getattr(T, "bg_cells", {}).items():
            x, y = self.cell_xy(r, c)
            d.rectangle([x, y, x + self.cw - 1, y + self.ch - 1], fill=bgc)
        for r, line in enumerate(T.lines):
            for c, (ch, fg) in enumerate(line):
                x, y = self.cell_xy(r, c)
                if T.visible and r == T.row and c == T.col:
                    continue
                if ch in "\u2580\u2584":
                    yy = y if ch == "\u2580" else y + self.ch // 2
                    d.rectangle([x, yy, x + self.cw - 1, yy + self.ch // 2 - 1], fill=fg)
                    continue
                d.text((x, y + (self.ch - self.asc) // 2 - 2), ch, font=self.font, fill=fg)
        if T.visible:
            x, y = self.cell_xy(T.row, T.col)
            d.rectangle([x, y, x + self.cw - 1, y + self.ch - 1], fill=CURSOR)
            line = T.lines[T.row]
            if T.col < len(line):
                d.text((x, y + (self.ch - self.asc) // 2 - 2), line[T.col][0], font=self.font, fill=BG)
        return img

    def cursor_vec(self, row, col):
        x, y = self.cell_xy(row, col)
        return (x, y + self.ch, self.cw, self.ch)  # Ghostty/Metal: left, bottom in y-down px, then w,h

    def set(self, name, val):
        if name in self.prog:
            self.prog[name].value = val

    def run(self, scenario, out, seconds, fps):
        os.makedirs(out, exist_ok=True)
        ev = timeline(scenario)
        T = Term(self.cols, self.rows)
        cur = prev = (0, 0)
        tchange = 0.0
        i = 0
        img = self.draw_term(T)
        times = [float(x) for x in os.environ["TIMES"].split(",")] if os.environ.get("TIMES") else \
            [fi / fps for fi in range(int(seconds * fps))]
        for fi, t in enumerate(times):
            changed = False
            while i < len(ev) and ev[i][0] <= t:
                ev[i][1](T)
                if (T.row, T.col) != cur:
                    prev, cur, tchange = cur, (T.row, T.col), ev[i][0]
                i += 1
                changed = True
            if changed or fi == 0:
                img = self.draw_term(T)
                self.tex.write(img.tobytes())
            self.tex.use(0)
            self.set("iChannel0", 0)
            self.set("iResolution", (self.W, self.H, 1.0))
            self.set("iTime", t)
            self.set("iTimeDelta", 1 / fps)
            self.set("iFrame", fi)
            self.set("iCurrentCursor", self.cursor_vec(*cur))
            self.set("iPreviousCursor", self.cursor_vec(*prev))
            self.set("iTimeCursorChange", tchange)
            self.set("iCursorVisible", 1 if T.visible else 0)
            self.set("iFocus", 1)
            pal = [(0.93, 0.93, 0.93)] * 256
            if T.claude:
                pal[255] = (238 / 255, 238 / 255, (238 + T.claude) / 255)
            if "iPalette" in self.prog:
                self.prog["iPalette"].value = pal
            self.set("iBackgroundColor", tuple(c / 255 for c in BG))
            self.set("iForegroundColor", tuple(c / 255 for c in FG))
            self.set("iCursorColor", tuple(c / 255 for c in CURSOR))
            self.fbo.use()
            self.vao.render(moderngl.TRIANGLE_STRIP)
            data = self.fbo.read(components=3)
            Image.frombytes("RGB", (self.W, self.H), data).transpose(Image.FLIP_TOP_BOTTOM).save(f"{out}/frame_{fi:04d}.png")


def from_ansi(raw, cols=92, rows=22):
    cols, rows = int(os.environ.get("COLS", cols)), int(os.environ.get("ROWS", rows))
    """Run raw terminal output through pyte and return a Term snapshot."""
    import pyte
    scr = pyte.Screen(cols, rows)
    st = pyte.ByteStream(scr)
    st.feed(raw.replace(b"\n", b"\r\n"))
    T = Term(cols, rows)
    hexc = lambda c, d: tuple(int(c[i:i + 2], 16) for i in (0, 2, 4)) if len(c) == 6 else d
    T.bg_cells = {}
    for y in range(rows):
        line = []
        for x in range(cols):
            ch = scr.buffer[y][x]
            fg = hexc(ch.fg, FG)
            if ch.bg != "default":
                T.bg_cells[(y, x)] = hexc(ch.bg, BG)
            line.append((ch.data or " ", fg))
        T.lines[y] = line
    T.row, T.col = scr.cursor.y, scr.cursor.x
    T.visible = not scr.cursor.hidden
    return T


if __name__ == "__main__":
    scen = sys.argv[1] if len(sys.argv) > 1 else "demo"
    out = sys.argv[2] if len(sys.argv) > 2 else "/tmp/pk"
    secs = float(sys.argv[3]) if len(sys.argv) > 3 else 12
    fps = int(sys.argv[4]) if len(sys.argv) > 4 else 30
    Renderer().run(scen, out, secs, fps)

