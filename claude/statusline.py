#!/usr/bin/env python3
"""poketerm battle HUD for the Claude Code status line.

  ◓◓◓ OPUS 5.5 Lv.90  HP ▰▰▰▰▰▰▰▱▱▱ 72%  PP 63  ₽4.21  ⌁ prova · main

HP = context window left, PP = 5-hour rate limit left, ₽ = session cost.
Names are printed in poketerm's "living ink" colours, which the Ghostty
shader animates (electric / shiny / fire).
"""
import json
import os
import subprocess
import sys

ESC = "\x1b["
RST = ESC + "0m"
BOLD = ESC + "1m"


def rgb(r, g, b):
    return f"{ESC}38;2;{r};{g};{b}m"


ELEC, SHINY, FIRE, GHOST = rgb(255, 209, 5), rgb(240, 183, 253), rgb(255, 106, 19), rgb(156, 124, 243)
DIM, TXT = rgb(90, 96, 128), rgb(217, 210, 194)
RED, WHITE = rgb(238, 74, 63), rgb(244, 244, 236)
LEVELS = {"low": 25, "medium": 50, "high": 75, "xhigh": 90, "max": 100}


def hp_color(p):
    if p > 50:
        return rgb(88, 208, 104)
    if p > 20:
        return rgb(248, 200, 56)
    return rgb(240, 88, 56)


def bar(p, n=10):
    full = max(0, min(n, round(p / 100 * n)))
    return hp_color(p) + "▰" * full + DIM + "▱" * (n - full) + RST


def branch(cwd):
    try:
        out = subprocess.run(["git", "-C", cwd, "branch", "--show-current"], capture_output=True,
                             text=True, timeout=0.3)
        return out.stdout.strip()
    except Exception:
        return ""


def party_size():
    try:
        with open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "party.conf")) as f:
            return max(1, min(3, len(f.read().split())))
    except OSError:
        return 1


def main():
    try:
        d = json.load(sys.stdin)
    except Exception:
        d = {}
    sep = f" {DIM}·{RST} "
    parts = []

    balls = (RED + "◓" + RST) * party_size()
    model = (d.get("model") or {}).get("display_name") or "CLAUDE"
    model = model.replace("Claude ", "").upper()
    lv = LEVELS.get(((d.get("effort") or {}).get("level") or "").lower())
    head = f"{balls} {ELEC}{BOLD}{model}{RST}"
    if lv:
        head += f" {TXT}Lv.{lv}{RST}"
    parts.append(head)

    cw = d.get("context_window") or {}
    left = cw.get("remaining_percentage")
    if left is None and cw.get("used_percentage") is not None:
        left = 100 - cw["used_percentage"]
    if left is not None:
        left = max(0, min(100, float(left)))
        label = f"{FIRE}{BOLD}HP{RST}" if left <= 20 else f"{TXT}HP{RST}"
        parts.append(f"{label} {bar(left)} {hp_color(left)}{left:.0f}%{RST}")

    five = ((d.get("rate_limits") or {}).get("five_hour") or {}).get("used_percentage")
    if five is not None:
        pp = max(0, 100 - float(five))
        parts.append(f"{TXT}PP{RST} {(SHINY if pp > 30 else FIRE)}{pp:.0f}{RST}")

    cost = (d.get("cost") or {}).get("total_cost_usd")
    if cost is not None:
        parts.append(f"{TXT}₽{float(cost):.2f}{RST}")

    ws = d.get("workspace") or {}
    cwd = ws.get("current_dir") or d.get("cwd") or os.getcwd()
    repo = ((ws.get("repo") or {}).get("name")) or os.path.basename(cwd.rstrip("/")) or "~"
    b = branch(cwd)
    loc = f"{DIM}⌁{RST} {TXT}{repo}{RST}"
    if b:
        loc += f" {DIM}·{RST} {SHINY}{b}{RST}"
    parts.append(loc)

    print(sep.join(parts))


if __name__ == "__main__":
    main()
