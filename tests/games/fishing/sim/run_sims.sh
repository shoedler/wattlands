#!/usr/bin/env bash
# tests/games/fishing/sim/run_sims.sh: Turbo Reel's simulation matrix through tools/run_game_sim,
# then node tests/games/fishing/sim/check_sims.mjs over the reports (with fit_check on every FIT).
#
#   bash tests/games/fishing/sim/run_sims.sh [--quick] [scenario ...]
#   FISHING_SIMS="r1 w3" bash tests/games/fishing/sim/run_sims.sh
#
# Scenarios (default: all; one report per run in build/fishing/sims/, FISHING_SIMS_OUT):
#   r1   roam_30, 1 band-tracker (erg+band), Autopilot
#   r2   roam_30, 4 band-trackers
#   r3   roam_30, 1 band-tracker + 3 bots, seeds 1-5 (FISHING_SEEDS)
#   r4   roam_10, 1 rider at erg:compliance=1.0 (no band: the zero-input default), Autopilot
#   r5   roam_30, 2 band-trackers, --ftp=300,200 --unverified --haptics-off=1
#   r6   roam_30, 2 band-trackers, slot 1 stops pedaling at 900 s for 60 s (paused or AFK)
#   r7   big_game_30, 2 band-trackers + 2 bots: only tuna and grouper bite, everyone fishes
#   w1   threshold, 2 band-trackers
#   w2   base_60, 2 band-trackers
#   w3   e2e_2min, 3 band-trackers
#   d    roam_10, 2 band-trackers + 2 bots, seed 7, twice (the same hash)
#   fit  fit_check on every FIT of the runs (check_sims --fit)
# --quick (CI) runs w3, d and fit.
#
# Every run goes through tools/run_game_sim at --sim-speed=200; a run that exits non-zero stops
# the script (75: the Godot lock wait timed out, rerun). Environment: FISHING_SIMS_OUT,
# FISHING_SEEDS, FISHING_SKIP_CHECK=1 (runs only), FISHING_GODOT_TIMEOUT (seconds per run, default
# 1800). tools/run_game_sim sets the locks.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../../../.." && pwd)"
cd "$repo"
out="${FISHING_SIMS_OUT:-build/fishing/sims}"
timeout_s="${FISHING_GODOT_TIMEOUT:-1800}"
seeds="${FISHING_SEEDS:-1 2 3 4 5}"

mode=default
wanted=""
for a in "$@"; do
  case "$a" in
    --quick) mode=quick ;;
    -h | --help)
      sed -n '2,28p' "$0"
      exit 0
      ;;
    -*)
      printf 'run_sims: unknown option %s\n' "$a" >&2
      exit 2
      ;;
    *) wanted="$wanted $a" ;;
  esac
done
order="r1 r2 r3 r4 r5 r6 r7 w1 w2 w3 d fit"
if [ -z "${wanted// /}" ]; then
  if [ "$mode" = quick ]; then
    wanted="w3 d fit"
  else
    wanted="${FISHING_SIMS:-$order}"
  fi
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
mkdir -p "$out"

band='erg+band'

# run <name> <run_game_sim flags...>: one run; stops the script when it fails.
run() {
  local name="$1"
  shift
  printf '== %s\n' "$name"
  local code=0
  tools/run_game_sim --game=fishing --sim-speed=200 "--godot-timeout=$timeout_s" \
    "--report=$out/$name.json" "$@" || code=$?
  if [ "$code" -ne 0 ]; then
    printf 'run_sims: %s failed with exit %s\n' "$name" "$code" >&2
    exit "$code"
  fi
}

scenario_r1() { run r1_roam30_solo --content=roam_30 --players=1 "--rider=$band" --seed=1; }
scenario_r2() { run r2_roam30_four --content=roam_30 --players=4 "--rider=$band" --seed=2; }
scenario_r3() {
  local s
  for s in $seeds; do
    run "r3_roam30_bots_seed${s}" --content=roam_30 --players=1 --bots=3 "--rider=$band" --seed="$s"
  done
}
scenario_r4() {
  run r4_roam10_autopilot --content=roam_10 --players=1 --rider=erg:compliance=1.0 --autopilot=all --seed=1
}
scenario_r5() {
  run r5_roam30_unverified --content=roam_30 --players=2 "--rider=$band" --ftp=300,200 \
    --unverified --haptics-off=1 --seed=3
}
scenario_r6() {
  run r6_roam30_paused --content=roam_30 --players=2 "--rider=$band" \
    "--rider=erg+band+cadence_drop:rpm=0,at_s=900,for_s=60" --seed=4
}
scenario_r7() {
  run r7_biggame --content=big_game_30 --players=2 --bots=2 "--rider=$band" --seed=5
}
scenario_w1() { run w1_threshold --content=threshold --players=2 "--rider=$band" --seed=1; }
scenario_w2() { run w2_base60 --content=base_60 --players=2 "--rider=$band" --seed=1; }
scenario_w3() { run w3_e2e --content=e2e_2min --players=3 "--rider=$band" --seed=1; }
scenario_d() {
  run d_roam_a --content=roam_10 --players=2 --bots=2 "--rider=$band" --seed=7
  run d_roam_b --content=roam_10 --players=2 --bots=2 "--rider=$band" --seed=7
}
scenario_fit() { :; } # check_sims --fit below

for sc in $order; do
  case " $wanted " in *" $sc "*) "scenario_$sc" ;; esac
done

if [ "${FISHING_SKIP_CHECK:-0}" = "1" ]; then
  exit 0
fi
args=("$out" "--seeds=${seeds// /,}")
only="ALL"
fit=""
for sc in $wanted; do
  case "$sc" in
    fit) fit="--fit" ;;
    *) only="$only,$(printf '%s' "$sc" | tr '[:lower:]' '[:upper:]')" ;;
  esac
done
if [ "$mode" = quick ] || [ -n "${*:-}" ] || [ -n "${FISHING_SIMS:-}" ]; then
  args+=("--only=$only")
fi
[ -n "$fit" ] && args+=("$fit")
node tests/games/fishing/sim/check_sims.mjs "${args[@]}"
