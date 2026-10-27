#!/usr/bin/env bash
# shoot.sh <out-dir> <screenshot flags...>   (env vars TANK_V3_* pass through); retries on exit 75
cd /c/Projects/wt/tank3-env
source tools/env.sh >/dev/null 2>&1
out="$1"; shift
mkdir -p "$out"
for i in 1 2 3 4 5 6; do
	env -u FAL_KEY -u WATTLANDS_ALLOW_ART tools/screenshot --game=tank --out="$out" "$@" >"$out/last.log" 2>&1
	rc=$?
	[ "$rc" -ne 75 ] && break
done
grep -E "screenshot:|SCRIPT ERROR" "$out/last.log" | sort | uniq -c | head -20
exit $rc
