#!/usr/bin/env bash
# Renders the real, HUD-less frames the picker cards are cut from, into build/picker_cards/frames/.
# Run it from Git Bash, from anywhere; then run: node tools/picker_cards/compose.mjs
# Windowed, one Godot slot per step (the Godot lock may queue them). Mock trainers only, no fal.
# Workout's card is not here: src/games/workout/art/bake.mjs bakes it with the rest of its art.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
. tools/env.sh

out=build/picker_cards/frames
rm -rf "$out"
mkdir -p "$out"

# Castellum Rotae: the view's own demo, every treadwheel routed, tilt-shift off.
tools/screenshot --scene=res://src/games/siege/view/v2/siege_v2_demo.tscn --frames=60 --size=1920x1080 \
  --siege-demo-mock-pose --siege-demo-sharp "--out=$out/siege" --timeout=300

# Diesel Domestiques: the four-rider landship, gun raised, lamps on. nohud and nopip drop the HUD and the shell screen.
TANK_FIXTURE="kind=v4:far_duel;flex;crew=4;nohud;nopip;fire=0" \
  tools/screenshot --scene=res://tests/games/tank/view/fixture_scene.tscn --frames=160 --size=1920x1080 \
  "--out=$out/tank" --timeout=300

# Turbo Reel: a boat, the taut line and a giant grouper, no HUD (the preview's card scenario).
tools/screenshot --scene=res://tests/games/fishing/view/preview/fishing_view_card.tscn --frames=60 --size=1920x1080 \
  "--out=$out/fishing" --timeout=300
