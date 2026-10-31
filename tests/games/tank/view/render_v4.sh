#!/usr/bin/env bash
# Renders every v4 fixture at 960x540 and 852x480 to build/tank/v4_frames/. Windowed; holds one Godot slot per run.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../../../.."
names="${*:-advance_far far_duel boss_far near_ambush bow_duel incoming tank_lost restart repair bots hard easy_breakdown roam_west cap_v4}"
for n in $names; do
  for pair in 960x540:1920x1080 852x480:1704x960; do
    canvas="${pair%%:*}"; window="${pair##*:}"
    out="build/tank/v4_frames/$n/$canvas"; mkdir -p "$out"
    TANK_FIXTURE="kind=v4:$n;flex;crew=${TANK_CREW:-3}" \
      tools/screenshot --scene=res://tests/games/tank/view/fixture_scene.tscn --frames=90 "--size=$window" "--out=$out"
  done
done
