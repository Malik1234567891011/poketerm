"""Load PMD SpriteCollab animation sheets (art/pmd/<name>/) into frames.

Sprites and portraits: PMD SpriteCollab (CC BY-NC 4.0) — see art/pmd/*/credits.txt.
Each sheet is a grid: columns = frames, rows = 8 facing directions
(Down, DownRight, Right, UpRight, Up, UpLeft, Left, DownLeft). Single-row
sheets (Sleep) have one direction. All frames of a species share the cell
centre, so anims of different cell sizes line up by their centres.
"""
import pathlib
import xml.etree.ElementTree as ET

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
PMD = ROOT / "art" / "pmd"
RIGHT = 2

ROSTER = {
    "pikachu": "Shock", "gengar": "Charge", "jigglypuff": "Charge", "eevee": "TailWhip", "charmander": "Charge", "bulbasaur": "Charge",
    "squirtle": "Charge", "snorlax": "Charge", "mew": "Charge", "psyduck": "Charge",
    "gastly": "Lick", "darkrai": "SpAttack",
}
GHOSTS = {"gengar", "gastly", "darkrai"}  # float, and vanish instead of hopping
ANIMS = ["Walk", "Idle", "Sleep", "Hop", "Hurt", "special"]


def anim_data(name):
    root = ET.parse(PMD / name / "AnimData.xml").getroot()
    out = {}
    for a in root.iter("Anim"):
        n = a.findtext("Name")
        out[n] = {
            "copy": a.findtext("CopyOf"),
            "fw": int(a.findtext("FrameWidth") or 0),
            "fh": int(a.findtext("FrameHeight") or 0),
            "dur": [int(d.text) for d in a.iter("Duration")],
        }
    for n, a in out.items():
        if a["copy"]:
            src = out[a["copy"]]
            a.update(fw=src["fw"], fh=src["fh"], dur=src["dur"], file=a["copy"])
        else:
            a["file"] = n
    return out


def load(name):
    """-> {anim: [(RGBA frame image, cx, cy, seconds)]} using right-facing rows.

    cx, cy = position of the cell centre inside the frame image (y down).
    """
    data = anim_data(name)
    out = {}
    for anim in ANIMS:
        want = ROSTER[name] if anim == "special" else anim
        for cand in (want, "Charge", "Idle"):
            a = data.get(cand)
            if a and (PMD / name / f"{a['file']}-Anim.png").exists():
                break
        sheet = Image.open(PMD / name / f"{a['file']}-Anim.png").convert("RGBA")
        rows = sheet.height // a["fh"]
        row = RIGHT if rows >= 8 else 0
        frames = []
        for i, d in enumerate(a["dur"]):
            cell = sheet.crop((i * a["fw"], row * a["fh"], (i + 1) * a["fw"], (row + 1) * a["fh"]))
            frames.append((cell, a["fw"] / 2, a["fh"] / 2, d / 60.0))
        out[anim] = frames
    return out


def palette(frames_by_anim, max_colors=15):
    """Shared <=15 colour palette for a species; returns (palette, mapper)."""
    cols = {}
    for frames in frames_by_anim.values():
        for img, *_ in frames:
            for r, g, b, al in img.getdata():
                if al > 127:
                    cols[(r, g, b)] = cols.get((r, g, b), 0) + 1
    pal = sorted(cols, key=lambda c: -cols[c])
    if len(pal) > max_colors:
        # merge the rarest colours into their nearest kept neighbour
        keep = pal[:max_colors]
        remap = {c: min(keep, key=lambda k: sum((a - b) ** 2 for a, b in zip(c, k))) for c in pal}
        pal = keep
    else:
        remap = {c: c for c in pal}
    index = {c: i + 1 for i, c in enumerate(pal)}
    return pal, (lambda rgba: 0 if rgba[3] <= 127 else index[remap[rgba[:3]]])
