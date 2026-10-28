#!/usr/bin/env bash
# Bakes the forest planes into assets/tank/v3/planes/ (moderate tilt-shift). Then import.
#   bash assets/tank/v3/tools_src/env_regen.sh [--only=strong|extreme  (into build/v3planes/)]
set -eu
cd "$(dirname "${BASH_SOURCE[0]}")/../../../.."
source tools/env.sh >/dev/null 2>&1
mkdir -p build/v3mock
for i in 1 2 3 4 5; do
	set +e
	env -u FAL_KEY -u WATTLANDS_ALLOW_ART tools/godot.sh --timeout=1500 --headless --path . \
		-s assets/tank/v3/tools_src/env/env_planes.gd -- "$@" >build/v3mock/env_planes.log 2>&1
	rc=$?
	set -e
	[ "$rc" -ne 75 ] && break
done
grep -E "SCRIPT ERROR|^ERROR|env_planes:" build/v3mock/env_planes.log | sort | uniq -c | head -20 || true
exit "$rc"
