# poketerm

A living Pokémon world inside Ghostty + Claude Code. Built for Malik's Mac.

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
- Battle-HUD status line: `◓ OPUS 5.5 Lv.90 · HP ▰▰▰▰▱ · PP 63 · ₽4.21 · ⌁ repo · branch`
  (HP = context left, PP = 5-hour rate limit left, ₽ = cost).
- `custom:poketerm` theme. Claude's accent and spinner are in electric ink, so they crackle. The input box border is shiny ink, permission prompts are fire, and plan mode is ghost.
- The spinner shows Pokémon moves ("Thunderbolting…", "Waiting for Snorlax to move…").
- Original 8-bit jingles: a level-up when Claude finishes and a "!" alert when it needs you.

**Ghostty**: custom Poké Ball app icon, chiptune bell, Departure Mono pixel font.

## Commands

```
poke                         show party + roster
poke party pikachu           solo partner (default)
poke party eevee gengar mew  up to three followers
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
tools/icon.py              draws the app icon
art/pmd/<name>/            PMD SpriteCollab sheets + portraits
```

Installed pieces: `~/.config/ghostty/config` -> `ghostty/config`, a source line at the end of
`~/.zshrc`, `~/.claude/themes/poketerm.json` -> `claude/poketerm-theme.json`, and
`theme` / `statusLine` / `spinnerVerbs` / `hooks` in `~/.claude/settings.json`
(the original is backed up at `~/.claude/settings.json.before-poketerm`).

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
Personal, non-commercial use. Everything else (shader, effects, inks, intro, HUD, sounds, icon) is original.
Font: [Departure Mono](https://departuremono.com) (OFL).
