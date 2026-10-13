#!/bin/zsh
# poketerm installer. Safe to re-run.
#   ./install.sh               everything
#   ./install.sh --no-claude   skip the Claude Code theme / status line / sounds
set -e
H=${0:A:h}
step() { print -P "%F{yellow}◓%f $1" }
want_claude=1
[[ $1 == --no-claude ]] && want_claude=0

[[ $OSTYPE == darwin* ]] || { print -u2 "poketerm is macOS-only for now (Ghostty shader paths, afplay, osascript)."; exit 1 }
[[ -d /Applications/Ghostty.app || -d ~/Applications/Ghostty.app ]] \
  || print -u2 "warning: Ghostty not found in /Applications. Get it at https://ghostty.org — the shell and Claude parts still work."

# 1. Python + Pillow, only needed when you change your party (`poke party ...`)
if [[ ! -x $H/tools/.venv/bin/python ]]; then
  step "setting up tools/.venv (Pillow, for rebuilding the party)"
  python3 -m venv $H/tools/.venv && $H/tools/.venv/bin/pip install -q --disable-pip-version-check pillow \
    || print -u2 "  couldn't install Pillow; everything works except changing the party"
fi
[[ -f $H/party.conf ]] || print pikachu > $H/party.conf

# 2. Departure Mono font (OFL)
if [[ -z $(print -l ~/Library/Fonts/DepartureMono*(N) /Library/Fonts/DepartureMono*(N)) ]]; then
  step "installing the Departure Mono font"
  tmp=$(mktemp -d)
  curl -fsSL -o $tmp/f.zip https://github.com/rektdeckard/departure-mono/releases/download/v1.500/DepartureMono-1.500.zip \
    && unzip -qo $tmp/f.zip -d $tmp && cp $tmp/**/DepartureMono-Regular.otf ~/Library/Fonts/ \
    || print -u2 "  font download failed; install Departure Mono from https://departuremono.com"
  rm -rf $tmp
fi

# 3. Ghostty: write our config, then include it from yours
step "configuring Ghostty"
sed "s|@POKETERM@|$H|g" $H/ghostty/config.in > $H/ghostty/config
gdir=~/Library/Application\ Support/com.mitchellh.ghostty
gconf=""
for c in $gdir/config.ghostty $gdir/config ~/.config/ghostty/config.ghostty ~/.config/ghostty/config; do
  [[ -e $c ]] && { gconf=$c; break }
done
if [[ -z $gconf ]]; then
  mkdir -p ~/.config/ghostty
  gconf=~/.config/ghostty/config
fi
if [[ ${gconf:A} == $H/ghostty/config ]]; then
  :  # already symlinked straight to ours
elif ! grep -qF "$H/ghostty/config" $gconf 2>/dev/null; then
  print "\n# poketerm (remove with $H/uninstall.sh)\nconfig-file = $H/ghostty/config" >> $gconf
  print "  added an include to $gconf"
fi

# 4. zsh
step "hooking into ~/.zshrc"
line="[ -f '$H/shell/poketerm.zsh' ] && source '$H/shell/poketerm.zsh'"
grep -qF "$H/shell/poketerm.zsh" ~/.zshrc 2>/dev/null || print "\n# poketerm\n$line" >> ~/.zshrc

# 5. Claude Code
if (( want_claude )); then
  step "adding the Claude Code theme, status line, spinner and sounds"
  python3 $H/tools/claude_setup.py install
fi

# 6. bake the shader for the current party
step "building the shader"
$H/bin/poke reload >/dev/null 2>&1 || true

print -P "\n%F{yellow}poketerm installed.%f Open a new Ghostty window (or press ⌘⇧, to reload)."
print "Try: poke party eevee gengar mew  ·  poke wild mew shiny  ·  poke off"
