#!/usr/bin/env bash
# Renders the real frames the README's images are made from, into build/readme_frames/.
# Run it from Git Bash, from anywhere; then run: node assets/readme/compose.mjs
# Windowed, one Godot slot per step (the Godot lock may queue them). Mock trainers only.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
. tools/env.sh

out=build/readme_frames
rm -rf "$out"
mkdir -p "$out"

# Turbo Reel: a giant grouper fight by the old wreck.
tools/screenshot --scene=res://tests/games/fishing/view/preview/fishing_view_wreck.tscn \
  --frames=90 --size=1920x1080 "--out=$out/fishing_wreck"

# Castellum Rotae: a session with two riders and two bots, the last wave's siege tower on the road.
tools/screenshot --game=siege --content=short --players=2 --bots=2 --seed=5 --at=1400 --sim-speed=30 \
  "--out=$out/siege" --timeout=300

# Workout: the game's own frame renderer, a sprint under the gantry with the crowd out.
tools/godot.sh --timeout=300 --path . -s src/games/workout/tools/render_frames.gd -- \
  "--out=$out/workout" --only=sprint_4

# Diesel Domestiques: an Ambush session, one rider and three bots, holding force and a shell coming in.
tools/screenshot --game=tank --content=ambush_15 --players=1 --bots=3 --seed=2 --at=430 --sim-speed=20 \
  --options='{"difficulty":"normal"}' "--out=$out/tank" --timeout=300

# The tank with no HUD, for the hero.
TANK_FIXTURE="kind=v4:far_duel;flex;crew=4;nohud;nopip;fire=0" \
  tools/screenshot --scene=res://tests/games/tank/view/fixture_scene.tscn --frames=120 --size=1920x1080 \
  "--out=$out/tank_plate"
