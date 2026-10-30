#!/usr/bin/env bash
# tests/games/siege/sim/run_sims.sh: brief section 4's simulation matrix, deduplicated, then
# fit_check on every FIT the runs wrote and check_sims.mjs over the reports.
#
#   bash tests/games/siege/sim/run_sims.sh [scenario ...]
#   SIEGE_SIMS="s9 s10" bash tests/games/siege/sim/run_sims.sh
#
# Scenarios (default: all of them). One report per run, in build/siege/sims/ (SIEGE_SIMS_OUT):
#   s9   short, vo2, sweetspot, endurance x 4 compliant Autopilot riders x seeds 1-3
#        (these runs also serve S1, S4 at 100%, S5 at offset 0 and T1, T3, T4)
#   s2   short with 1 human, 2 humans, 1 human + 3 bots, seeds 1-3
#   s3   short, vo2, sweetspot, endurance with a team that barely pedals: slot 0 at ERG
#        compliance 0.3, slots 1-3 at 0 W (AFK); HOST (ADR "S3 under the shared pause")
#   s4   short at erg:compliance=0.9 and 0.8, 4 riders, seeds 1-3 (100% comes from s9)
#   s5   drill at offset 0 (1 human); the vo2 offsets run is in s10
#   s6   sweetspot with erg+cadence_drop:rpm=40,at_s=1200
#   s7   vo2 seed 1 again (same arguments as s9's vo2 seed 1, another report name)
#   s10  vo2 and endurance with 4 surgers, and vo2 with 4 surgers at offsets +5, -10, 0, +5
#
# A scenario that needs another's report (s4, s7, T1 for s2 comes from s9) runs that report
# first when it is missing. Every run goes through tools/run_game_sim at --sim-speed=200 and
# stops this script on a non-zero exit (75: the Godot lock wait timed out, just rerun).
# Environment: SIEGE_SEEDS="1 2 3" (seeds), SIEGE_SIMS_OUT (report dir), SIEGE_SKIP_CHECK=1
# (runs only), SIEGE_FIT=0 (no fit_check), SIEGE_GODOT_TIMEOUT (seconds per run, default 1800).
# The locks (no hardware control, no network integrations) are exported by tools/run_game_sim.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../../../.." && pwd)"
cd "$repo"
out="${SIEGE_SIMS_OUT:-build/siege/sims}"
seeds="${SIEGE_SEEDS:-1 2 3}"
timeout_s="${SIEGE_GODOT_TIMEOUT:-1800}"
mkdir -p "$out"

contents="short vo2 sweetspot endurance"
surge='erg+surge:every_s=60,for_s=2,lift=0.2,sim_pct=130'
offsets='[{"wave_offset":5},{"wave_offset":-10},{"wave_offset":0},{"wave_offset":5}]'

# run <name> <run_game_sim flags...>: one run; stops the script when it fails.
run() {
  local name="$1"
  shift
  printf '== %s\n' "$name"
  local code=0
  tools/run_game_sim --game=siege --sim-speed=200 "--godot-timeout=$timeout_s" \
    "--report=$out/$name.json" "$@" || code=$?
  if [ "$code" -ne 0 ]; then
    printf 'run_sims: %s failed with exit %s\n' "$name" "$code" >&2
    exit "$code"
  fi
}

# have <name>: true when the report exists already (a dependency another scenario ran).
have() { [ -f "$out/$1.json" ]; }

# s9_run <content> <seed>
s9_run() {
  run "s9_${1}_seed${2}" --content="$1" --players=4 --bots=0 --rider=erg:compliance=1.0 --seed="$2"
}

scenario_s9() {
  local c s
  for c in $contents; do
    for s in $seeds; do s9_run "$c" "$s"; done
  done
}

scenario_s2() {
  local s
  for s in $seeds; do
    run "s2_short_1h_seed${s}" --content=short --players=1 --bots=0 --rider=erg:compliance=1.0 --seed="$s"
    run "s2_short_2h_seed${s}" --content=short --players=2 --bots=0 --rider=erg:compliance=1.0 --seed="$s"
    run "s2_short_1h3b_seed${s}" --content=short --players=1 --bots=3 --rider=erg:compliance=1.0 --seed="$s"
  done
}

scenario_s3() {
  local c
  for c in $contents; do
    run "s3_${c}_weak" --content="$c" --players=4 --bots=0 --rider=erg:compliance=0.3 \
      --rider=zero --rider=zero --rider=zero --seed=1
  done
}

scenario_s4() {
  local s
  for s in $seeds; do
    have "s9_short_seed${s}" || s9_run short "$s"
    run "s4_short_c90_seed${s}" --content=short --players=4 --bots=0 --rider=erg:compliance=0.9 --seed="$s"
    run "s4_short_c80_seed${s}" --content=short --players=4 --bots=0 --rider=erg:compliance=0.8 --seed="$s"
  done
}

scenario_s5() {
  run s5_drill --content=drill --players=1 --bots=0 --rider=erg:compliance=1.0 --seed=1
}

scenario_s6() {
  run s6_sweetspot_cadence_drop --content=sweetspot --players=4 --bots=0 \
    --rider=erg+cadence_drop:rpm=40,at_s=1200 --seed=1
}

scenario_s7() {
  have s9_vo2_seed1 || s9_run vo2 1
  run s7_vo2_seed1 --content=vo2 --players=4 --bots=0 --rider=erg:compliance=1.0 --seed=1
}

scenario_s10() {
  run s10_vo2 --content=vo2 --players=4 --bots=0 "--rider=$surge" --seed=1
  run s10_endurance --content=endurance --players=4 --bots=0 "--rider=$surge" --seed=1
  run s10_vo2_offsets --content=vo2 --players=4 --bots=0 "--rider=$surge" --seed=1 \
    "--player-options=$offsets"
}

order="s9 s2 s3 s4 s5 s6 s7 s10"
if [ "$#" -gt 0 ]; then
  wanted="$*"
else
  wanted="${SIEGE_SIMS:-$order}"
fi
wanted="${wanted//,/ }"
for sc in $wanted; do
  case " $order " in
    *" $sc "*) ;;
    *)
      printf 'run_sims: unknown scenario %s (one of: %s)\n' "$sc" "$order" >&2
      exit 2
      ;;
  esac
done
for sc in $order; do
  case " $wanted " in *" $sc "*) "scenario_$sc" ;; esac
done

# fit_check on the FIT files per content with the expected laps (lap-true phases + the
# cool-down's: short 8, vo2 14, sweetspot 6, endurance 4, drill 3). A failure is remembered, the
# scenario checks still run, and the script exits non-zero at the end.
status=0
if [ "${SIEGE_FIT:-1}" != "0" ]; then
  for pair in short:8 vo2:14 sweetspot:6 endurance:4 drill:3; do
    c="${pair%%:*}"
    laps="${pair##*:}"
    files=()
    for f in "$out"/fit/*_"${c}"_*.fit; do
      [ -e "$f" ] && files+=("$f")
    done
    if [ "${#files[@]}" -gt 0 ]; then
      printf '== fit_check %s (%s files, %s laps)\n' "$c" "${#files[@]}" "$laps"
      node tools/fit_check/check.mjs "${files[@]}" "--expect-laps=$laps" || status=1
    fi
  done
fi

# The checks that belong to the scenarios that ran (all of them when everything ran).
only=""
for sc in $wanted; do
  case "$sc" in
    s9) only="$only,S1,S5,S9" ;;
    s2) only="$only,S2" ;;
    s3) only="$only,S3" ;;
    s4) only="$only,S4" ;;
    s5) only="$only,S5" ;;
    s6) only="$only,S6" ;;
    s7) only="$only,S7" ;;
    s10) only="$only,S5,S10" ;;
  esac
done
only="${only#,}"

if [ "${SIEGE_SKIP_CHECK:-0}" != "1" ]; then
  if [ -n "$only" ] && { [ "$#" -gt 0 ] || [ -n "${SIEGE_SIMS:-}" ]; }; then
    node tests/games/siege/sim/check_sims.mjs "$out" "--only=$only" "--seeds=${seeds// /,}" || status=1
  else
    node tests/games/siege/sim/check_sims.mjs "$out" "--seeds=${seeds// /,}" || status=1
  fi
fi
exit "$status"
