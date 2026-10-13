"""Extra (non-Pokémon) characters from fighting-game sprite sheets.

Sheets like the Spriters Resource rips put frames on a flat background with no
grid, so frames are found as connected blobs and picked by number:

  python3 extra.py contact art/extra/zoro      -> preview/contact_zoro.png (numbered frames)

art/extra/<name>/anims.json says which numbered frames make each animation:

  {"sheet": "sheet.png", "special": "Onigiri",
   "anims": {"Idle": {"frames": [0, 1, 2, 3], "fps": 8}, "Walk": ..., "Sleep": ...,
             "Hop": ..., "Hurt": ..., "Onigiri": ...},
   "portrait": {"frame": 0, "top": 34}}

art/extra/ is git-ignored: these are game rips and stay on this machine.
"""
import json
import pathlib
import sys

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent.parent
EXTRA = ROOT / "art" / "extra"
SCALE = 2.0   # device px per sprite pixel: fighter sprites are taller than PMD ones
# shader ids for characters with their own effects (defined even when the art is absent)
IDS = {"zoro": 100, "sasuke": 101, "shanks": 102, "gojo": 103}


def names():
    return sorted(p.name for p in EXTRA.glob("*") if (p / "anims.json").exists()) if EXTRA.exists() else []


def segment(sheet, gap=3, min_px=40):
    """Blobs of non-background pixels -> sorted list of (x0, y0, x1, y1).

    Pixels within `gap` of each other join (so a sword or slash effect stays
    with its body). Reading order: rows of blobs top to bottom, left to right.
    """
    img = sheet.convert("RGB")
    w, h = img.size
    px = img.load()
    bg = px[0, 0]
    solid = [[px[x, y] != bg for x in range(w)] for y in range(h)]
    seen = [[False] * w for _ in range(h)]
    boxes = []
    for y in range(h):
        for x in range(w):
            if not solid[y][x] or seen[y][x]:
                continue
            stack = [(x, y)]
            seen[y][x] = True
            x0 = x1 = x
            y0 = y1 = y
            n = 0
            while stack:
                cx, cy = stack.pop()
                n += 1
                x0, x1, y0, y1 = min(x0, cx), max(x1, cx), min(y0, cy), max(y1, cy)
                for ny in range(max(0, cy - gap), min(h, cy + gap + 1)):
                    row, srow = solid[ny], seen[ny]
                    for nx in range(max(0, cx - gap), min(w, cx + gap + 1)):
                        if row[nx] and not srow[nx]:
                            srow[nx] = True
                            stack.append((nx, ny))
            if n >= min_px:
                boxes.append((x0, y0, x1 + 1, y1 + 1))
    # group into visual rows by vertical overlap, then left to right
    boxes.sort(key=lambda b: (b[1] + b[3]) / 2)
    rows = []
    for b in boxes:
        mid = (b[1] + b[3]) / 2
        if rows and abs(mid - rows[-1][0]) < 22:
            rows[-1][1].append(b)
        else:
            rows.append([mid, [b]])
    return [b for _, r in rows for b in sorted(r)]


def contact(folder):
    folder = pathlib.Path(folder)
    meta = json.loads((folder / "anims.json").read_text()) if (folder / "anims.json").exists() else {}
    sheet = Image.open(folder / meta.get("sheet", "sheet.png")).convert("RGB")
    boxes = segment(sheet)
    out = sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST)
    d = ImageDraw.Draw(out)
    for i, (x0, y0, x1, y1) in enumerate(boxes):
        d.rectangle([x0 * 2, y0 * 2, x1 * 2, y1 * 2], outline=(255, 60, 60))
        d.text((x0 * 2 + 1, y0 * 2 - 10), str(i), fill=(255, 255, 0))
    dest = ROOT / "preview" / f"contact_{folder.name}.png"
    out.save(dest)
    print(f"{len(boxes)} frames -> {dest}")


def frame(sheet, box):
    """Crop a blob to RGBA with the background made transparent."""
    img = sheet.crop(box).convert("RGBA")
    bg = sheet.convert("RGB").getpixel((0, 0))
    img.putdata([(0, 0, 0, 0) if p[:3] == bg else p for p in img.getdata()])
    return img


def feet_x(img):
    """Horizontal anchor: the middle of the bottom few rows (the feet), so swords
    and slashes sticking out don't make the body jump around between frames."""
    w, h = img.size
    a = img.getchannel("A").load()
    for rows in (6, 12, h):
        xs = [x for y in range(max(0, h - rows), h) for x in range(w) if a[x, y] > 127]
        if xs:
            return (min(xs) + max(xs)) / 2
    return w / 2


def load(name, anim_names):
    """-> {anim: [(RGBA frame, cx, cy, seconds)]}, the same shape as pmd.load.

    Frames are anchored at their feet: cx under the feet, cy at the bottom edge.
    anim_names: the shader's slots, e.g. ["Walk", "Idle", "Sleep", "Hop", "Hurt", "special"].
    """
    folder = EXTRA / name
    meta = json.loads((folder / "anims.json").read_text())
    sheet = Image.open(folder / meta.get("sheet", "sheet.png")).convert("RGB")
    boxes = segment(sheet)
    out = {}
    for slot in anim_names:
        key = meta["special"] if slot == "special" else slot
        a = meta["anims"].get(key) or meta["anims"]["Idle"]
        frames = []
        for fi in a["frames"]:
            img = frame(sheet, boxes[fi])
            if meta.get("faces") == "left":
                img = img.transpose(Image.FLIP_LEFT_RIGHT)
            frames.append((img, feet_x(img), img.height, 1.0 / a.get("fps", 10)))
        out[slot] = frames
    return out


def portrait(name):
    """One whole frame (head to toe) for the shell's encounter screen."""
    folder = EXTRA / name
    meta = json.loads((folder / "anims.json").read_text())
    sheet = Image.open(folder / meta.get("sheet", "sheet.png")).convert("RGB")
    p = meta.get("portrait", {"frame": meta["anims"]["Idle"]["frames"][0]})
    img = frame(sheet, segment(sheet)[p["frame"]])
    if meta.get("faces") == "left":
        img = img.transpose(Image.FLIP_LEFT_RIGHT)
    return img.transpose(Image.FLIP_LEFT_RIGHT)   # face the text box on the right


if __name__ == "__main__":
    if sys.argv[1:2] == ["contact"]:
        contact(sys.argv[2])
