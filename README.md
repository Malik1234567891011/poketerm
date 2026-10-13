# poketerm

A living Pokémon world inside [Ghostty](https://ghostty.org) + [Claude Code](https://claude.com/claude-code).
Pikachu follows your cursor, text in certain colours crackles with electricity, and Claude's status line is a battle HUD.

![poketerm demo](art/demo.gif)

## Install

Needs macOS, [Ghostty](https://ghostty.org), zsh (the macOS default) and python3.

```sh
git clone https://github.com/Malik1234567891011/poketerm ~/poketerm
~/poketerm/install.sh            # or: install.sh --no-claude
```

Then open a new Ghostty window. The installer is safe to re-run, and it only *adds* to your setup:

- an include line at the end of your Ghostty config (your own settings stay put; poketerm's win where they overlap)
- one `source` line at the end of `~/.zshrc`
- the Departure Mono font, if you don't have it
- in `~/.claude/settings.json`: the `custom:poketerm` theme, status line, spinner verbs and two sound hooks,
  next to any hooks you already have (a backup goes to `~/.claude/settings.json.before-poketerm`)

Uninstall with `~/poketerm/uninstall.sh`. It removes exactly those pieces.

## What it does

**GPU shader (`shaders/poketerm.src.glsl`)**, a post-process over every Ghostty frame:
- **Partner Pokémon** follows your cursor. It walks while you type, hops to new lines (Pikachu leaves pixel lightning and fires its Shock animation when it lands), naps with Zzz after 30s idle, and flinches when a command fails. When an app hides the cursor (Claude Code), it walks to the grass in the bottom-right corner and sleeps there.
- **Living ink**: text printed in four exact colours becomes an animated material.
  The shader recognises the colour on the GPU, so any program can use it.

  | ink | rgb | effect |
  |---|---|---|
  | electric | `255;209;5` | current flowing through the letters, crackles |
  | shiny | `240;183;253` | holographic rainbow with glints |
  | fire | `255;106;19` | flickering flame gradient |
  | ghost | `156;124;243` | wobbles and phases like Gengar |

  Example: `printf '\e[38;2;255;209;5mthis crackles\e[0m\n'`
- Night sky with twinkling stars and shooting stars, and tall grass that sways (and rustles when something hides in it).
- A battle intro on every new window: a Poké Ball spins in, fills the screen and splits open.

**Shell (`shell/poketerm.zsh`)**
- Wild encounter on every new window: a PMD portrait with a typed text box. There's a 1/64 shiny chance.
- Prompt in living ink: the folder is electric, the branch is shiny when clean and fire when dirty, and `fainted N` (ghost ink) appears after a failed command. That ink is also what tells the shader to make your partner flinch.
- A location sign when you walk into a different repo.

**Claude Code (`claude/`)**
- Battle-HUD status line: `OPUS 5.5 · HP ▰▰▰▰▰▰▰▰▰▱ 91% · PP 93% · repo · branch`
  (HP = context window left, PP = 5-hour usage limit left).
- `custom:poketerm` theme. Claude's accent and spinner are in electric ink, so they crackle. The input box border is shiny ink, permission prompts are fire, and plan mode is ghost.
- The spinner shows Pokémon moves ("Thunderbolting…", "Waiting for Snorlax to move…").
- Original 8-bit jingles: a level-up when Claude finishes and a "!" alert when it needs you.

**Ghostty**: custom Poké Ball app icon, chiptune bell, Departure Mono pixel font.

## Commands

```
poke                         show party + roster
poke random                  a random partner every new window (default)
poke party pikachu           pin one partner
poke party eevee gengar mew  pin up to three followers
poke wild [NAME] [shiny]     summon an encounter
poke off / poke on           disable / enable the shader
poke reload                  rebuild + reload Ghostty
```

Roster: pikachu gengar jigglypuff ditto voltorb eevee charmander bulbasaur squirtle snorlax mew psyduck mimikyu gastly

Set `POKETERM_GREET=0` in `~/.zshrc` before the source line to skip encounters.

## Layout

```
shaders/poketerm.src.glsl  shader source (edit this)  -> tools/build.py -> poketerm.glsl
tools/pmd.py               loads PMD sprite sheets into frames
tools/build.py             bakes the party into the shader + portraits into shell/sprites
tools/render.py            offline renderer: runs the real shader on a simulated terminal
tools/check.sh             builds + validates the shader against Ghostty's GLSL prelude
tools/sounds.py            synthesises the jingles
tools/claude_setup.py      adds/removes the Claude Code settings
tools/icon.py              draws the app icon
art/pmd/<name>/            PMD SpriteCollab sheets + portraits
```

## Notes for whoever edits this next

- Ghostty on macOS hands the shader **y-down** coordinates (fragCoord, texture, cursor rects with
  `xy` = left/bottom). The shader converts everything to y-up at the top of `mainImage`.
- The screen texture can be linear or sRGB depending on renderer settings. The shader works it out
  every frame from the top-left padding pixel (`G_LINEAR`).
- Ink only counts on thin strokes with background nearby (`isStroke`), so pixel art that happens to
  use an ink-like colour is left alone.

## Credits

Pokémon sprites and portraits are from [PMD SpriteCollab](https://github.com/PMDCollab/SpriteCollab)
(CC BY-NC 4.0); per-sprite artists are in `art/pmd/*/credits.txt`. Pokémon © Nintendo / Game Freak / Creatures.
Everything else (shader, effects, inks, intro, HUD, sounds, icon) is original.
This is an unofficial, non-commercial fan project, not affiliated with Nintendo, Game Freak, Creatures or The Pokémon Company.
Font: [Departure Mono](https://departuremono.com) (OFL).
