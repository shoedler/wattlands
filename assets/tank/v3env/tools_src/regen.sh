#!/usr/bin/env bash
# MOCK (tank v3 background): bakes assets/tank/v3env/planes/<strength>/*.png (moderate, strong, extreme).
# Run from the repository root in Git Bash:  bash assets/tank/v3env/tools_src/regen.sh [--only=<strength>]
set -eu
cd "$(dirname "${BASH_SOURCE[0]}")/../../../.."
source tools/env.sh >/dev/null 2>&1
mkdir -p build/v3mock/tools
cp assets/tank/v3env/tools_src/*.gd build/v3mock/tools/
for i in 1 2 3 4 5; do
	set +e
	env -u FAL_KEY -u WATTLANDS_ALLOW_ART tools/godot.sh --timeout=1500 --headless --path . \
		-s build/v3mock/tools/env_planes.gd -- "$@" >build/v3mock/tools/env_planes.log 2>&1
	rc=$?
	set -e
	[ "$rc" -ne 75 ] && break
done
grep -E "SCRIPT ERROR|^ERROR|env_planes:" build/v3mock/tools/env_planes.log | sort | uniq -c | head -20 || true
exit "$rc"
