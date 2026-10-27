#!/usr/bin/env bash
# g.sh script.gd args...  (prints only output that concerns build/v2 scripts, plus print() lines)
cd /c/Projects/wt/tank-mock && source tools/env.sh >/dev/null 2>&1
s=$1; shift
log=build/v2/last.log
env -u FAL_KEY -u WATTLANDS_ALLOW_ART tools/godot.sh --timeout=400 --headless --path . -s "build/v2/$s" -- "$@" >"$log" 2>&1
rc=$?
awk '/^(SCRIPT ERROR|ERROR|WARNING|USER)/{prev=$0; next} /v2/{ if (prev!="") print prev; print; prev=""; next} /^ *at:/{prev=""; next} /Godot Engine|^$/{next} {print}' "$log" | grep -v -E "^\s*$" | head -40
echo "rc=$rc"
