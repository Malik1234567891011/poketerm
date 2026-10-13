#!/bin/zsh
# Validate built shaders against Ghostty's real GLSL prelude.
cd "${0:A:h}/.."
python3 tools/build.py || exit 1
ok=0
dir=shaders; [[ -n $POKETERM_PARTY ]] && dir=preview   # where build.py put it
for f in $dir/*.glsl(N); do
  [[ $f == *.src.glsl ]] && continue
  tmp=$(mktemp -t pk).frag
  cat tools/ghostty_prelude.glsl "$f" > $tmp
  if tools/bin/glslang -S frag -G --aml $tmp >/dev/null 2>$tmp.err && ! grep -q ERROR $tmp.err; then echo "ok   $f"; else echo "FAIL $f"; tools/bin/glslang -S frag -G --aml $tmp | grep -E 'ERROR|WARN' | head -20; ok=1; fi
  rm -f $tmp $tmp.err *.spv(N)
done
exit $ok
