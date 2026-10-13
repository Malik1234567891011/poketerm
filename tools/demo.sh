#!/bin/zsh
# Scripted terminal session used to screenshot/record poketerm.
E=$'\e'
ink() { printf "${E}[38;2;%sm%s${E}[0m" "$1" "$2"; }
typeit() { local s=$1; for ((i=1;i<=${#s};i++)); do printf '%s' "${s[i]}"; sleep ${2:-0.07}; done; }
clear
sleep 1.3
print -n "~/poketerm ❯ "; sleep 0.6
typeit "git status"; sleep 0.4; print
print "On branch main\nnothing to commit, working tree clean"
print -n "~/poketerm ❯ "; sleep 0.8
print
print -n "  "; ink "255;209;5" "ELECTRIC INK  ⚡ crackles with current"; print
print -n "  "; ink "240;183;253" "SHINY INK  ✦ holographic like a shiny"; print
print -n "  "; ink "255;106;19" "FIRE INK  burns from below"; print
print -n "  "; ink "156;124;243" "GHOST INK  wobbles like Gengar"; print
print "  normal text stays normal"
print -n "~/poketerm ❯ "; sleep 0.5
typeit "echo pika pika" 0.09; sleep 0.3
sleep ${1:-40}
