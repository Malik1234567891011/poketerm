"""Add or remove poketerm's pieces in ~/.claude/settings.json.

  python3 claude_setup.py install   theme, status line, spinner verbs, sound hooks
  python3 claude_setup.py uninstall removes exactly those, leaves everything else

A copy of the original is kept at ~/.claude/settings.json.before-poketerm.
"""
import json
import pathlib
import shutil
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CLAUDE = pathlib.Path.home() / ".claude"
SETTINGS = CLAUDE / "settings.json"
BACKUP = CLAUDE / "settings.json.before-poketerm"
THEME = CLAUDE / "themes" / "poketerm.json"

VERBS = ["Thunderbolting", "Using Quick Attack", "Charging Solar Beam", "Throwing a Poké Ball",
         "Evolving", "Consulting Professor Oak", "Searching the tall grass", "Studying the Pokédex",
         "Hatching an Egg", "Using Hyper Beam", "Rolling out", "Using Psychic", "Teleporting",
         "Surfing", "Using Cut", "Using Strength", "Flying to Cinnabar",
         "Healing at the Pokémon Center", "Trading at the Cable Club", "Waiting for Snorlax to move",
         "Fishing with a Super Rod", "Battling the Elite Four", "Training on Route 22",
         "Riding the S.S. Anne", "Using Dig", "Using Metronome", "Splashing", "Catching 'em all"]


def sound(name, vol):
    return {"type": "command", "command": f"afplay -v {vol} '{ROOT}/sounds/{name}.wav'", "async": True}


def state(arg):
    return {"type": "command", "command": f"zsh '{ROOT}/claude/state.zsh' {arg}", "async": True}


# sounds, plus the state signal that lets the shader react to what Claude is doing
HOOKS = {
    "UserPromptSubmit": [state("work")],
    "PreToolUse": [state("tool")],
    "Notification": [sound("alert", 0.45), state("need")],
    "Stop": [sound("levelup", 0.35), state("done")],
    "SessionEnd": [state("end")],
}


def ours(hook):
    cmd = hook.get("command", "")
    return "poketerm" in cmd and ("afplay" in cmd or "state.zsh" in cmd)


def strip_hooks(s):
    for event in list(s.get("hooks", {})):
        groups = []
        for g in s["hooks"][event]:
            g["hooks"] = [h for h in g.get("hooks", []) if not ours(h)]
            if g["hooks"]:
                groups.append(g)
        if groups:
            s["hooks"][event] = groups
        else:
            del s["hooks"][event]
    if s.get("hooks") == {}:
        del s["hooks"]


def install(s):
    if SETTINGS.exists() and not BACKUP.exists():
        shutil.copy(SETTINGS, BACKUP)
    THEME.parent.mkdir(parents=True, exist_ok=True)
    if THEME.is_symlink() or THEME.exists():
        THEME.unlink()
    THEME.symlink_to(ROOT / "claude" / "poketerm-theme.json")
    s["theme"] = "custom:poketerm"
    s["statusLine"] = {"type": "command", "command": f"python3 '{ROOT}/claude/statusline.py'", "padding": 0}
    s["spinnerVerbs"] = {"mode": "replace", "verbs": VERBS}
    strip_hooks(s)
    for event, hooks in HOOKS.items():
        s.setdefault("hooks", {}).setdefault(event, []).append({"hooks": hooks})


def uninstall(s):
    if s.get("theme") == "custom:poketerm":
        del s["theme"]
    if "poketerm" in (s.get("statusLine") or {}).get("command", ""):
        del s["statusLine"]
    if (s.get("spinnerVerbs") or {}).get("verbs") == VERBS:
        del s["spinnerVerbs"]
    strip_hooks(s)
    if THEME.is_symlink():
        THEME.unlink()


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else "install"
    s = json.loads(SETTINGS.read_text()) if SETTINGS.exists() else {}
    {"install": install, "uninstall": uninstall}[action](s)
    CLAUDE.mkdir(exist_ok=True)
    SETTINGS.write_text(json.dumps(s, indent=2, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
