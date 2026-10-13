# poketerm — shell layer. Sourced from ~/.zshrc.
#
#  * wild-encounter greeting on every new Ghostty window (the shader's Poké Ball
#    opens onto it), with a 1/64 shiny chance
#  * a prompt written in "living ink": the shader animates these exact colours
#  * a location sign when you walk into a different repo
#  * `poke` command to change your party, toggle effects, summon encounters

POKETERM_HOME=${POKETERM_HOME:-${${(%):-%x}:A:h:h}}
[[ -o interactive ]] && path=($POKETERM_HOME/bin $path)

# exact 24-bit colours the shader turns into materials (keep in sync with the shader)
typeset -gA POKE_INK=(
  elec  $'\e[38;2;255;209;5m'
  shiny $'\e[38;2;240;183;253m'
  fire  $'\e[38;2;255;106;19m'
  ghost $'\e[38;2;156;124;243m'
)
typeset -g POKE_DIM=$'\e[38;2;90;96;128m' POKE_RST=$'\e[0m' POKE_BOLD=$'\e[1m'

_poke_type() {  # typewriter print: _poke_type <text> [delay]
  local s=$1 d=${2:-0.012} i
  for (( i = 1; i <= ${#s}; i++ )); do
    print -n -- "${s[i]}"
    sleep $d
  done
}

# A PMD-style encounter: portrait on the left, a text box typed out beside it.
poke_encounter() {
  # Pokémon portraits, plus any local extras (art/extra/<name>/, not in git)
  local -a files=($POKETERM_HOME/shell/sprites/*.normal.ans(N) $POKETERM_HOME/art/extra/*/*.normal.ans(N))
  (( ${#files} )) || return 0
  local name=${1:-${${files[RANDOM % ${#files} + 1]:t}%%.*}}
  local dir=$POKETERM_HOME/shell/sprites
  [[ -r $dir/$name.normal.ans ]] || dir=$POKETERM_HOME/art/extra/${(L)name}
  local shiny=${2:-$(( RANDOM % 64 == 0 ))}
  local mood=normal
  (( RANDOM % 4 == 0 )) && [[ -r $dir/$name.happy.ans ]] && mood=happy
  local file=$dir/$name.$mood.ans
  [[ -r $file ]] || return 0
  local -a art=("${(@f)$(<$file)}")
  local conf=$(<$POKETERM_HOME/party.conf 2>/dev/null)
  [[ $conf == (|random) ]] && conf=$(<$POKETERM_HOME/.partner 2>/dev/null)
  local -a team=(${(z)conf})
  local lead=${team[1]:-pikachu}
  local w=40 n=${#art} top=$(( ${#art} / 2 - 2 ))
  local pad="  " gap="   "
  local -a box=(
    "${POKE_DIM}╭${(l:$w::─:)}╮${POKE_RST}"
    "${POKE_DIM}│${POKE_RST}${(l:$w:: :)}${POKE_DIM}│${POKE_RST}"
    "${POKE_DIM}│${POKE_RST}${(l:$w:: :)}${POKE_DIM}│${POKE_RST}"
    "${POKE_DIM}╰${(l:$w::─:)}╯${POKE_RST}"
  )
  print
  local i
  for (( i = 1; i <= n; i++ )); do
    local j=$(( i - top ))
    if (( j >= 1 && j <= 4 )); then print -r -- "$pad${art[i]}$gap${box[j]}"
    else print -r -- "$pad${art[i]}"; fi
  done
  # type the two lines into the box (cursor up into it, then back down)
  local col=$(( ${#pad} + 40 + ${#gap} + 3 ))
  local up1=$(( n - top - 1 )) up2=$(( n - top - 2 ))
  local ink=${POKE_INK[elec]}
  (( shiny )) && ink=${POKE_INK[shiny]}
  print -n -- $'\e7'"\e[${up1}A\e[${col}G"
  _poke_type "A wild "
  print -n -- "$ink$POKE_BOLD"; _poke_type "$name"; print -n -- "$POKE_RST"
  _poke_type " appeared!"
  print -n -- $'\e8\e7'"\e[${up2}A\e[${col}G"
  if (( shiny )); then
    print -n -- "${POKE_INK[shiny]}"; _poke_type "✦ it's shiny!  "; print -n -- "$POKE_RST"
  fi
  print -n -- "${POKE_INK[fire]}"; _poke_type "Go! ${(U)lead}!"; print -n -- "$POKE_RST"
  print -n -- $'\e8'
}

# everything below is for interactive terminals only (not Claude Code's tool shells)
[[ -o interactive && -t 1 ]] || return 0

# ---------------------------------------------------------------- prompt
typeset -g _poke_t0=0 _poke_area=""
zmodload zsh/datetime 2>/dev/null

_poke_preexec() { _poke_t0=$EPOCHREALTIME; }

_poke_git() {
  local b
  b=$(git symbolic-ref --short -q HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null) || return
  if git diff --quiet --ignore-submodules HEAD 2>/dev/null; then
    print -rn -- "%{${POKE_INK[shiny]}%}${b}%{$POKE_RST%}"
  else
    print -rn -- "%{${POKE_INK[fire]}%}${b}*%{$POKE_RST%}"
  fi
}

_poke_precmd() {
  local code=$?
  local status_part="" took=""
  if (( code != 0 )); then
    status_part=" %{${POKE_INK[ghost]}%}fainted ${code}%{$POKE_RST%}"
  fi
  if (( _poke_t0 > 0 )); then
    local secs=$(( EPOCHREALTIME - _poke_t0 ))
    (( secs >= 5 )) && took=" %{$POKE_DIM%}$(printf '%.0fs' $secs)%{$POKE_RST%}"
    _poke_t0=0
  fi
  local dir=${PWD/#$HOME/~}
  local g=$(_poke_git)
  PROMPT=$'\n'"%{${POKE_INK[elec]}%}${dir:t}%{$POKE_RST%}${g:+ $g}${status_part}${took} %{$POKE_DIM%}❯%{$POKE_RST%} "
}

# location sign when you enter a different repo / top-level folder
_poke_chpwd() {
  local area=$(git rev-parse --show-toplevel 2>/dev/null)
  [[ -z $area ]] && return
  [[ $area == $_poke_area ]] && return
  _poke_area=$area
  local name=${(U)area:t}
  local w=$(( ${#name} + 6 ))
  print -- "${POKE_DIM}╭${(l:$w::─:)}╮${POKE_RST}"
  print -n -- "${POKE_DIM}│${POKE_RST}  ${POKE_INK[elec]}"
  _poke_type "$name" 0.02
  print -- "${POKE_RST}    ${POKE_DIM}│${POKE_RST}"
  print -- "${POKE_DIM}╰${(l:$w::─:)}╯${POKE_RST}"
}

autoload -Uz add-zsh-hook
add-zsh-hook preexec _poke_preexec
add-zsh-hook precmd _poke_precmd
add-zsh-hook chpwd _poke_chpwd
_poke_area=$(git rev-parse --show-toplevel 2>/dev/null)

# greet on new Ghostty surfaces (the shader's Poké Ball intro opens onto this)
# random partner each session: roll one, rebake the shader in the background and
# signal Ghostty to reload (SIGUSR2). `poke party X` pins one instead.
_poke_roll_partner() {
  [[ $(<$POKETERM_HOME/party.conf 2>/dev/null) == (|random) ]] || return 0
  local -a roster=($POKETERM_HOME/art/pmd/*(/N:t) $POKETERM_HOME/art/extra/*/anims.json(N:h:t))
  (( ${#roster} )) || return 0
  local pick=${roster[RANDOM % ${#roster} + 1]}
  print -r -- $pick > $POKETERM_HOME/.partner
  local py=$POKETERM_HOME/tools/.venv/bin/python; [[ -x $py ]] || py=python3
  # (the short wait lets a just-launched Ghostty finish starting before the reload signal)
  ( $py $POKETERM_HOME/tools/build.py --shader-only >/dev/null 2>&1 && sleep 0.8 && pkill -USR2 -x ghostty ) &!
}

if [[ $TERM_PROGRAM == ghostty && -z $_POKETERM_GREETED ]]; then
  export _POKETERM_GREETED=1
  if [[ -r $POKETERM_HOME/.try ]]; then
    # opened by `poke try NAME`: meet it, then rebake the shader with your real party
    local _try=$(<$POKETERM_HOME/.try)
    rm -f $POKETERM_HOME/.try
    poke_encounter ${(U)_try}
    local _py=$POKETERM_HOME/tools/.venv/bin/python; [[ -x $_py ]] || _py=python3
    ( $_py $POKETERM_HOME/tools/build.py --shader-only >/dev/null 2>&1 ) &!
  else
    _poke_roll_partner
    [[ ${POKETERM_GREET:-1} == 1 ]] && poke_encounter
  fi
fi
