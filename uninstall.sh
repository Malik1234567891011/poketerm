#!/bin/zsh
# Removes everything install.sh added. The repo folder itself is left alone.
H=${0:A:h}

gdir=~/Library/Application\ Support/com.mitchellh.ghostty
for c in $gdir/config.ghostty $gdir/config ~/.config/ghostty/config.ghostty ~/.config/ghostty/config; do
  [[ -e $c ]] || continue
  if [[ ${c:A} == $H/ghostty/config ]]; then
    rm $c && print "removed the $c symlink"
  elif grep -qF "$H/ghostty/config" $c; then
    sed -i '' -e '/^# poketerm (remove with/d' -e "\|^config-file = $H/ghostty/config\$|d" $c && print "cleaned $c"
  fi
done

if [[ -f ~/.zshrc ]]; then
  sed -i '' -e '/^# poketerm/d' -e "\|$H/shell/poketerm.zsh|d" ~/.zshrc && print "cleaned ~/.zshrc"
fi

python3 $H/tools/claude_setup.py uninstall && print "cleaned ~/.claude/settings.json"
print "poketerm removed. Open a new terminal; delete $H whenever you like."
