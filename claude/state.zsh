#!/bin/zsh
# Tells the poketerm shader what Claude Code is doing. Called from Claude Code hooks:
#   state.zsh work   a prompt was sent          state.zsh tool   a tool is running
#   state.zsh need   Claude is asking you       state.zsh done   Claude finished
#   state.zsh end    the session closed
# The shader can only see pixels and uniforms, so the state travels as palette slot
# 255 (#eeeeee) with its blue nudged up 1-13 steps, which no one can see in text.
# A small background ticker escalates the working level over time:
#   1 <20s  2 <1m  3 <3m  4 longer  5 needs you  6-13 finishing (1.6s)  then reset.
emulate -L zsh
zmodload zsh/datetime zsh/zselect zsh/mathfunc 2>/dev/null

# Our window's tty: walk up the process tree to the outermost ancestor that has one
# (hooks themselves may run without a controlling terminal). A session hosted by the
# Claude daemon is drawn in the window of the claude that spawned it ("pid":N).
outer_tty() {
  local p=$1 t="" ; local -a f
  while (( p > 1 )); do
    f=(${=$(ps -o tty= -o ppid= -p $p 2>/dev/null)})
    (( ${#f} == 2 )) || break
    if [[ $f[1] == '??' ]]; then [[ -n $t ]] && break; else t=$f[1]; fi
    p=$f[2]
  done
  print -r -- $t
}
tty=$2   # the ticker is handed its tty: by then its parent is gone
if [[ -z $tty ]]; then
  start=$PPID p=$PPID
  while (( p > 1 )); do
    args=$(ps -o args= -p $p 2>/dev/null) || break
    if [[ $args == *--spawned-by*'"pid":'[0-9]* ]]; then start=${${args##*\"pid\":}%%[^0-9]*}; break; fi
    p=$(ps -o ppid= -p $p 2>/dev/null) || break
  done
  tty=$(outer_tty $start)
fi
[[ -n $tty && -w /dev/$tty ]] || exit 0

dir=${TMPDIR:-/tmp}/poketerm
mkdir -p $dir
sf=$dir/$tty.state
now=$EPOCHREALTIME
local -a st=(off 0 0)
[[ -r $sf ]] && st=(${=$(<$sf)})
mode=$st[1] start=$st[2] since=$st[3]

case $1 in
  work) mode=work start=$now since=$now ;;
  tool) [[ $mode == work ]] || start=$now; mode=work since=$now ;;
  need) [[ $mode == work ]] || exit 0; mode=need since=$now ;;   # skip idle reminders
  done) [[ $mode == off ]] && exit 0; mode=done since=$now ;;
  end)  mode=off ;;
  tick) ;;
  *) exit 1 ;;
esac

if [[ $1 != tick ]]; then
  print -r -- "$mode $start $since" > $sf
  # make sure exactly one ticker runs for this window
  pf=$dir/$tty.pid
  if ! { [[ -r $pf ]] && kill -0 $(<$pf) 2>/dev/null }; then
    ( setopt nomonitor; zsh $0 tick $tty </dev/null >/dev/null 2>&1 & print $! > $pf )
  fi
  exit 0
fi

# ---- the ticker
send() { print -n "$1" > /dev/$tty 2>/dev/null || exit 0 }
last=-1
while true; do
  [[ -r $sf ]] && st=(${=$(<$sf)}) || st=(off 0 0)
  mode=$st[1] start=$st[2] since=$st[3]
  now=$EPOCHREALTIME
  code=0
  case $mode in
    work)
      el=$(( now - start ))
      if (( now - since > 1200 )); then code=0      # no news for 20 min: probably interrupted
      elif (( el < 20 )); then code=1
      elif (( el < 60 )); then code=2
      elif (( el < 180 )); then code=3
      else code=4; fi ;;
    need) code=5 ;;
    done)
      d=$(( now - since ))
      (( d < 1.6 )) && code=$(( 6 + int(d / 0.2) )) ;;
  esac
  if (( code != last )); then
    if (( code == 0 )); then send $'\e]104;255\e\\'
    else send $(printf '\e]4;255;rgb:ee/ee/%02x\e\\' $(( 238 + code ))); fi
    last=$code
  fi
  if (( code == 0 )); then
    print -r -- "off 0 0" > $sf
    rm -f $dir/$tty.pid
    exit 0
  fi
  zselect -t 10 2>/dev/null; (( $? <= 1 )) || sleep 0.1
done
