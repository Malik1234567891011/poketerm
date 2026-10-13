"""Procedural pixel-art sprites for poketerm.

Every sprite is built from simple shapes on a small grid, then given a
1px dark outline, so animation frames are just different shape params.
Palette indices (4 bits per pixel in the shader):
  0 transparent  1 outline  2 yellow  3 yellow shade  4 red cheek
  5 white        6 brown    7 black   8 ball red      9 ball white
  10 ball shade  11 spark   12 ball red shade
"""
import math

PALETTE = {
    0: None,
    1: (40, 26, 20),
    2: (255, 214, 64),
    3: (214, 160, 32),
    4: (236, 72, 56),
    5: (255, 255, 255),
    6: (150, 92, 40),
    7: (20, 14, 12),
    8: (232, 56, 48),
    9: (244, 244, 236),
    10: (176, 176, 168),
    11: (255, 250, 190),
    12: (168, 32, 32),
    # greeting-only colours (the shader palette stops at 15)
    16: (112, 78, 176),   # gengar
    17: (78, 52, 132),    # gengar shade
    18: (230, 40, 60),    # gengar eye
    19: (200, 150, 222),  # ditto
    20: (160, 112, 188),  # ditto shade
    21: (255, 182, 200),  # jigglypuff
    22: (226, 140, 166),  # jigglypuff shade
    23: (70, 160, 200),   # jigglypuff eye
}

W, H = 24, 20


class Canvas:
    def __init__(self, w=W, h=H):
        self.w, self.h = w, h
        self.px = [[0] * w for _ in range(h)]

    def set(self, x, y, c):
        x, y = int(round(x)), int(round(y))
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y][x] = c

    def ellipse(self, cx, cy, rx, ry, c):
        for y in range(self.h):
            for x in range(self.w):
                if ((x + .5 - cx) / rx) ** 2 + ((y + .5 - cy) / ry) ** 2 <= 1:
                    self.px[y][x] = c

    def poly(self, pts, c):
        for y in range(self.h):
            for x in range(self.w):
                if inside(pts, x + .5, y + .5):
                    self.px[y][x] = c

    def outline(self, oc=1):
        out = [row[:] for row in self.px]
        for y in range(self.h):
            for x in range(self.w):
                if self.px[y][x]:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < self.w and 0 <= ny < self.h and self.px[ny][nx] not in (0, oc):
                        out[y][x] = oc
                        break
        self.px = out

    def flipped(self):
        c = Canvas(self.w, self.h)
        c.px = [row[::-1] for row in self.px]
        return c


def inside(pts, x, y):
    n, hit = len(pts), False
    for i in range(n):
        x1, y1 = pts[i]
        x2, y2 = pts[(i + 1) % n]
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
            hit = not hit
    return hit


def rot(pts, ox, oy, deg):
    a = math.radians(deg)
    ca, sa = math.cos(a), math.sin(a)
    return [(ox + (x - ox) * ca - (y - oy) * sa, oy + (x - ox) * sa + (y - oy) * ca) for x, y in pts]


def thick(c, pts, w, col):
    """Draw a polyline as a chain of quads of width w."""
    for (x1, y1), (x2, y2) in zip(pts, pts[1:]):
        dx, dy = x2 - x1, y2 - y1
        l = math.hypot(dx, dy) or 1
        nx, ny = -dy / l * w / 2, dx / l * w / 2
        c.poly([(x1 + nx, y1 + ny), (x2 + nx, y2 + ny), (x2 - nx, y2 - ny), (x1 - nx, y1 - ny)], col)


def pikachu(bob=0, legs=(0, 0), ear=0, tail=0, eyes="open", mouth=False, arms=0, tuck=False, cheeks_spark=False):
    """Side-view chibi Pikachu facing right. Feet rest on row 19 when bob == 0."""
    c = Canvas()
    b = bob
    # tail: chunky lightning bolt from the lower back up to the upper left
    tp = rot([(8.6, 15.4 + b), (3.4, 13.6 + b), (6.8, 10.8 + b), (1.8, 8.6 + b)], 8.6, 14 + b, tail)
    thick(c, tp[:2], 1.7, 2)
    thick(c, tp[1:3], 1.8, 2)
    thick(c, tp[2:], 2.2, 2)
    tip = rot([(0.0, 4.0 + b), (4.6, 4.8 + b), (3.4, 9.2 + b), (0.2, 9.2 + b)], 8.6, 14 + b, tail)
    c.poly(tip, 2)
    thick(c, tp[:2], 2.2, 6)
    # legs / feet
    for i, (lx, ph) in enumerate(((10.4, legs[0]), (14.2, legs[1]))):
        col = 3 if i == 0 else 2
        if tuck:
            c.ellipse(lx + .8, 17.0 + b, 1.7, 1.2, col)
        else:
            fx = lx + ph * 1.8
            fy = 18.7 - abs(ph) * 1.2
            thick(c, [(lx, 16 + b), (fx, fy - .4)], 2.0, col)
            c.ellipse(fx + .5, fy - .3, 1.8, 1.0, col)
    # body
    c.ellipse(12.2, 14.8 + b, 4.4, 3.4, 2)
    c.set(8.8, 13.6 + b, 6)
    c.set(9.2, 12.4 + b, 6)
    # ears: wide base, black tips, pivot on the head
    e1 = [(11.8, 6.0 + b), (14.6, 4.4 + b), (10.8, -0.8 + b), (9.0, 0.0 + b)]
    k1 = [(10.8, 2.0 + b), (12.6, 1.4 + b), (10.8, -0.8 + b), (9.0, 0.0 + b)]
    c.poly(rot(e1, 12.6, 5.6 + b, ear), 2)
    c.poly(rot(k1, 12.6, 5.6 + b, ear), 7)
    e2 = [(15.0, 4.8 + b), (18.2, 5.0 + b), (17.8, -0.8 + b), (16.0, -0.8 + b)]
    k2 = [(15.7, 1.8 + b), (18.0, 1.8 + b), (17.8, -0.8 + b), (16.0, -0.8 + b)]
    c.poly(rot(e2, 16.6, 5.0 + b, ear * .6), 3)
    c.poly(rot(k2, 16.6, 5.0 + b, ear * .6), 7)
    # head
    c.ellipse(16.0, 9.0 + b, 6.0, 5.0, 2)
    # arm
    if arms:
        thick(c, [(16.0, 13.4 + b), (19.4 + arms, 11.4 + b - arms)], 1.8, 3)
    else:
        c.ellipse(16.4, 14.0 + b, 1.5, 1.1, 3)
    c.outline()
    if eyes == "open":
        for x, y in ((18, 7), (19, 7), (18, 8), (19, 8)):
            c.set(x, y + b, 7)
        c.set(18, 7 + b, 5)
    elif eyes == "closed":
        c.set(18, 8 + b, 1); c.set(19, 8 + b, 1)
    elif eyes == "happy":
        c.set(17, 8 + b, 1); c.set(18, 7 + b, 1); c.set(19, 8 + b, 1)
    c.set(21, 9 + b, 1)  # nose
    if mouth:
        c.set(19, 11 + b, 1); c.set(20, 11 + b, 4); c.set(20, 10 + b, 1)
    else:
        c.set(20, 10 + b, 1); c.set(19, 11 + b, 1)
    ch = 11 if cheeks_spark else 4
    for x, y in ((15, 10), (16, 10), (15, 11), (16, 11)):
        c.set(x, y + b, ch)
    return c


def frames():
    f = {}
    f["idle0"] = pikachu(bob=0, legs=(0, 0), ear=0, tail=0)
    f["idle1"] = pikachu(bob=0, legs=(0, 0), ear=-6, tail=6, eyes="open")
    f["blink"] = pikachu(bob=0, legs=(0, 0), ear=0, tail=0, eyes="closed")
    f["run0"] = pikachu(bob=0, legs=(.8, -.8), ear=-12, tail=-10)
    f["run1"] = pikachu(bob=-1, legs=(0, 0), ear=-16, tail=-4, tuck=True)
    f["run2"] = pikachu(bob=0, legs=(-.8, .8), ear=-12, tail=-10)
    f["run3"] = pikachu(bob=-1, legs=(0, 0), ear=-16, tail=-4, tuck=True)
    f["jump"] = pikachu(bob=-1, ear=-22, tail=-14, tuck=True, mouth=True, eyes="happy")
    f["zap"] = pikachu(bob=0, legs=(.4, -.4), ear=8, tail=10, mouth=True, arms=1, cheeks_spark=True, eyes="happy")
    f["sleep"] = pikachu(bob=1, legs=(0, 0), ear=-38, tail=18, eyes="closed", tuck=True)
    return f


def pokeball(open_amt=0):
    c = Canvas(12, 12)
    c.ellipse(6, 6, 5.5, 5.5, 9)
    for y in range(12):
        for x in range(12):
            if c.px[y][x] and y + .5 < 6 - open_amt:
                c.px[y][x] = 8
    for y in range(12):
        for x in range(12):
            if c.px[y][x] == 8 and (x > 7 and y > 3):
                c.px[y][x] = 12
            if c.px[y][x] == 9 and x > 7 and y > 7:
                c.px[y][x] = 10
    for x in range(12):
        if c.px[5][x] or c.px[6][x]:
            c.px[5][x] = 1 if c.px[5][x] else 0
    c.outline()
    c.ellipse(6, 6, 1.6, 1.6, 1)
    c.set(6, 5, 9); c.set(5, 5, 9)
    return c


def gengar(sleep=False):
    c = Canvas(24, 20)
    # spikes along the back and top, pointed ears
    for pts in ([(4, 9), (1, 6), (6, 7)], [(5, 6), (3, 2), (8, 5)], [(8, 4), (8, 0), (11, 4)],
                [(13, 4), (16, 0), (16, 5)], [(17, 6), (21, 2), (20, 8)], [(19, 9), (23, 6), (20, 11)]):
        c.poly(pts, 17)
    c.ellipse(12, 11.5, 9.0, 7.0, 16)
    c.ellipse(4.5, 18, 2.6, 1.6, 17); c.ellipse(19.5, 18, 2.6, 1.6, 17)
    c.ellipse(2.8, 13, 1.6, 2.2, 16); c.ellipse(21.2, 13, 1.6, 2.2, 16)
    c.outline()
    if sleep:
        for x in (6, 7, 8, 9, 15, 16, 17, 18):
            c.set(x, 10, 1)
    # eyes: angry red triangles with pupils
    for ex, d in (() if sleep else ((8, 1), (16, -1))):
        c.poly([(ex - 2.6 * d, 8.0), (ex + 1.8 * d, 9.2), (ex - 2.2 * d, 11.0)] if d > 0 else
               [(ex + 2.6, 8.0), (ex - 1.8, 9.2), (ex + 2.2, 11.0)], 18)
        c.set(ex - .5 * d, 9.5, 1)
    # grin with teeth
    for x in range(7, 18):
        y = 13 + (1 if 9 <= x <= 15 else 0)
        c.set(x, y, 9)
        c.set(x, y + 1, 9 if 9 <= x <= 15 else 1)
        if x % 2 == 0:
            c.set(x, y + (1 if 9 <= x <= 15 else 0), 10)
    c.set(6, 13, 1); c.set(18, 13, 1)
    for x in range(9, 16):
        c.set(x, 15.6, 1)
    return c


def ditto(sleep=False):
    c = Canvas(24, 20)
    c.ellipse(12, 13.5, 10.0, 5.5, 19)
    c.ellipse(6, 9.5, 4.0, 3.8, 19)
    c.ellipse(17, 9.0, 4.4, 4.0, 19)
    c.ellipse(12, 10.5, 4.0, 3.0, 19)
    c.ellipse(3.2, 16.5, 2.4, 2.0, 19)
    c.ellipse(21.0, 16.5, 2.4, 2.0, 19)
    for y in range(c.h):
        for x in range(c.w):
            if c.px[y][x] == 19 and y > 16:
                c.px[y][x] = 20
    c.outline()
    if sleep:
        c.set(8, 11, 1); c.set(9, 11, 1); c.set(15, 11, 1); c.set(16, 11, 1)
    else:
        c.set(9, 11, 1); c.set(15, 11, 1)
    for x in range(10, 15):
        c.set(x, 13 + (1 if 11 <= x <= 13 else 0), 1)
    return c


def voltorb(sleep=False):
    c = Canvas(24, 20)
    c.ellipse(12, 10, 9.4, 9.2, 9)
    for y in range(c.h):
        for x in range(c.w):
            if c.px[y][x] and y + .5 < 10:
                c.px[y][x] = 8
            if c.px[y][x] == 8 and x > 15 and y < 6:
                c.px[y][x] = 12
            if c.px[y][x] == 9 and x > 16 and y > 13:
                c.px[y][x] = 10
    c.outline()
    for x in range(3, 21):
        c.set(x, 10, 1)
    if sleep:
        for x in (6, 7, 8, 9, 10, 14, 15, 16, 17, 18):
            c.set(x, 8, 1)
    else:
        # angry eyes
        c.poly([(5.5, 5.5), (10.5, 7.5), (10.5, 9.4), (6.0, 9.4)], 1)
        c.poly([(18.5, 5.5), (13.5, 7.5), (13.5, 9.4), (18.0, 9.4)], 1)
        c.set(8, 8, 9); c.set(9, 8, 9); c.set(15, 8, 9); c.set(16, 8, 9)
    c.set(5, 3, 5); c.set(6, 3, 5); c.set(5, 4, 5)
    return c


def jigglypuff(sleep=False, sing=False):
    c = Canvas(24, 20)
    c.poly([(5, 6), (4, 1), (9, 3)], 21)
    c.poly([(19, 6), (20, 1), (15, 3)], 21)
    c.ellipse(12, 10, 8.4, 8.0, 21)
    c.ellipse(7, 18.4, 2.6, 1.3, 22); c.ellipse(17, 18.4, 2.6, 1.3, 22)
    c.ellipse(3.4, 11, 1.4, 2.0, 22); c.ellipse(20.6, 11, 1.4, 2.0, 22)
    c.outline()
    c.set(4, 2, 1); c.set(20, 2, 1)
    # forehead curl
    for x, y in ((11, 3), (12, 3), (13, 3), (13, 4), (12, 5), (11, 5), (11, 4), (12, 4)):
        c.set(x, y, 22)
    c.set(12, 4, 21)
    for ex in (8, 15):
        if sleep or sing:
            for dx in range(3):
                c.set(ex + dx, 10 - (1 if dx == 1 else 0), 1)
            continue
        for dx in range(3):
            for dy in range(3):
                c.set(ex + dx, 8 + dy, 23)
        c.set(ex + 1, 7, 1); c.set(ex, 8, 5); c.set(ex + 1, 8, 5); c.set(ex, 9, 5)
    if sing:
        c.ellipse(12, 14, 1.4, 1.6, 1)
        c.set(11.5, 14, 4)
    else:
        c.set(11, 13, 1); c.set(12, 13, 1)
    return c


ENCOUNTERS = {"PIKACHU": lambda: frames()["idle0"].flipped(), "GENGAR": gengar, "DITTO": ditto,
              "VOLTORB": voltorb, "JIGGLYPUFF": jigglypuff}

# alternate "shiny" colourings: palette index -> replacement index/rgb
SHINY = {"PIKACHU": {2: (255, 190, 60), 3: (222, 140, 30), 4: (255, 120, 160)},
         "GENGAR": {16: (120, 120, 200), 17: (80, 80, 150)},
         "DITTO": {19: (120, 190, 230), 20: (80, 150, 200)},
         "VOLTORB": {8: (60, 150, 230), 12: (40, 100, 180)},
         "JIGGLYPUFF": {21: (255, 210, 225), 22: (240, 170, 195)}}


def ansi(cv, shiny=None):
    """Render a canvas as truecolor half-block lines (2 pixel rows per line)."""
    pal = dict(PALETTE)
    if shiny:
        pal.update(shiny)
    rows = []
    for y in range(0, cv.h, 2):
        out = []
        for x in range(cv.w):
            top = pal[cv.px[y][x]]
            bot = pal[cv.px[y + 1][x]] if y + 1 < cv.h else None
            if top and bot:
                out.append("\x1b[38;2;%d;%d;%dm\x1b[48;2;%d;%d;%dm\u2580\x1b[0m" % (top + bot))
            elif top:
                out.append("\x1b[38;2;%d;%d;%dm\u2580\x1b[0m" % top)
            elif bot:
                out.append("\x1b[38;2;%d;%d;%dm\u2584\x1b[0m" % bot)
            else:
                out.append(" ")
        rows.append("".join(out).rstrip())
    while rows and not rows[-1].strip():
        rows.pop()
    while rows and not rows[0].strip():
        rows.pop(0)
    return rows


def all_frames():
    """Every frame the shader knows, in a fixed order."""
    f = frames()
    f["gengar"] = gengar(); f["gengar_sleep"] = gengar(sleep=True)
    f["ditto"] = ditto(); f["ditto_sleep"] = ditto(sleep=True)
    f["voltorb"] = voltorb(); f["voltorb_sleep"] = voltorb(sleep=True)
    f["jiggly"] = jigglypuff(); f["jiggly_sleep"] = jigglypuff(sleep=True); f["jiggly_sing"] = jigglypuff(sing=True)
    return f


if __name__ == "__main__":
    from PIL import Image
    import sys
    fs = frames()
    fs["ball"] = pokeball()
    for k, fn in ENCOUNTERS.items():
        if k != "PIKACHU":
            fs[k] = fn()
    S = 12
    cols = len(fs)
    img = Image.new("RGB", ((W + 2) * S * cols, (H + 2) * S), (26, 28, 44))
    for i, (name, cv) in enumerate(fs.items()):
        for y in range(cv.h):
            for x in range(cv.w):
                col = PALETTE[cv.px[y][x]]
                if col:
                    for yy in range(S):
                        for xx in range(S):
                            img.putpixel(((W + 2) * S * i + (x + 1) * S + xx, (y + 1) * S + yy), col)
    img.save(sys.argv[1] if len(sys.argv) > 1 else "preview/sprites.png")
