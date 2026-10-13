"""Draw the poketerm Ghostty app icon: a Poké Ball whose bottom half is a terminal.

The top shell is the red half of a ball; the lower half is a night-sky screen
with a prompt, a block cursor and Pikachu (PMD sprite) sitting beside it.
"""
import pathlib

from PIL import Image, ImageDraw, ImageFilter

import pmd

ROOT = pathlib.Path(__file__).resolve().parent.parent
S = 1024
M = 100           # macOS icon grid margin
R = 185           # corner radius


def main():
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    box = (M, M, S - M, S - M)

    # drop shadow
    sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle((M, M + 14, S - M, S - M + 14), R, fill=(0, 0, 0, 120))
    canvas.alpha_composite(sh.filter(ImageFilter.GaussianBlur(18)))

    body = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(body)
    mid = S // 2 - 40
    # top: red shell with a darker bottom edge and a glossy highlight
    d.rounded_rectangle(box, R, fill=(226, 54, 44))
    d.rectangle((M, mid, S - M, S), fill=(17, 19, 28))
    d.rectangle((M, mid - 70, S - M, mid), fill=(196, 38, 34))
    d.ellipse((M + 70, M + 50, M + 330, M + 170), fill=(255, 120, 108))
    # band + button
    d.rectangle((M, mid, S - M, mid + 44), fill=(22, 18, 24))
    cx = S // 2 + 170
    d.ellipse((cx - 92, mid + 22 - 92, cx + 92, mid + 22 + 92), fill=(22, 18, 24))
    d.ellipse((cx - 58, mid + 22 - 58, cx + 58, mid + 22 + 58), fill=(240, 240, 232))
    d.ellipse((cx - 30, mid + 22 - 30, cx + 30, mid + 22 + 30), fill=(255, 255, 255))
    # screen: stars
    for x, y in ((180, 650), (300, 720), (760, 640), (840, 760), (520, 610), (650, 840)):
        d.rectangle((x, y, x + 7, y + 7), fill=(200, 214, 255))
    # prompt and cursor (chunky pixels)
    P = 14
    chev = [(0, 0), (1, 1), (2, 2), (1, 3), (0, 4)]
    for px, py in chev:
        d.rectangle((190 + px * P, 760 + py * P, 190 + px * P + P - 1, 760 + py * P + P - 1), fill=(255, 209, 5))
    d.rectangle((260, 746, 300, 840), fill=(255, 210, 63))
    # grass along the bottom of the screen
    for i in range(M, S - M, 12):
        h = 18 + (i * 37 % 23)
        d.rectangle((i, S - M - h, i + 7, S - M), fill=(46, 120, 60) if i % 24 else (70, 160, 80))

    # Pikachu idle frame from the PMD sheet, scaled with nearest neighbour
    img, cxf, cyf, _ = pmd.load("pikachu")["Idle"][0]
    img = img.crop(img.getbbox())
    k = 7
    img = img.resize((img.width * k, img.height * k), Image.NEAREST).transpose(Image.FLIP_LEFT_RIGHT)
    body.alpha_composite(img, (330, S - M - 40 - img.height))

    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, R, fill=255)
    canvas.paste(body, (0, 0), mask)
    out = ROOT / "art" / "icon.png"
    canvas.save(out)
    print("wrote", out)


if __name__ == "__main__":
    main()
