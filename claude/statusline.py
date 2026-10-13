#!/usr/bin/env python3
"""poketerm battle HUD for the Claude Code status line.

  OPUS 5.5 · HP ▰▰▰▰▰▰▰▱▱▱ 72% · PP 63% · prova · main

HP = context window left, PP = 5-hour usage limit left.
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


def main():
    try:
        d = json.load(sys.stdin)
    except Exception:
        d = {}
    sep = f" {DIM}·{RST} "
    parts = []

    model = (d.get("model") or {}).get("display_name") or "CLAUDE"
    parts.append(f"{ELEC}{BOLD}{model.replace('Claude ', '').upper()}{RST}")

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
        parts.append(f"{TXT}PP{RST} {(SHINY if pp > 30 else FIRE)}{pp:.0f}%{RST}")

    ws = d.get("workspace") or {}
    cwd = ws.get("current_dir") or d.get("cwd") or os.getcwd()
    repo = ((ws.get("repo") or {}).get("name")) or os.path.basename(cwd.rstrip("/")) or "~"
    b = branch(cwd)
    loc = f"{TXT}{repo}{RST}"
    if b:
        loc += f" {DIM}·{RST} {SHINY}{b}{RST}"
    parts.append(loc)

    print(sep.join(parts))


if __name__ == "__main__":
    main()
