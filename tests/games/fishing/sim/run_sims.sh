#!/usr/bin/env bash
# tests/games/fishing/sim/run_sims.sh: brief 4.2's simulation matrix for Big Game Fishing, then
# node tests/games/fishing/sim/check_sims.mjs over the reports (with fit_check on every FIT).
#
#   bash tests/games/fishing/sim/run_sims.sh [--quick|--full] [scenario ...]
#   FISHING_SIMS="s10 s8" bash tests/games/fishing/sim/run_sims.sh
#
# Scenarios (default: all ten; one report per run in build/fishing/sims/, FISHING_SIMS_OUT):
#   s1   threshold, 2 band-trackers (erg+band)
#   s2   threshold, 1 rider at erg+band:offset_rpm=-18 (s2_low) and =18 (s2_high)
#   s3   free_30, 4 band-trackers, seeds 1-5 (--full or FISHING_SEEDS: 1-20)
#   s4   free_30 solo, erg:compliance=1.0, --autopilot=none and =all
#   s5   base_60, 2 band-trackers
#   s6   free_120, 1 band-tracker, on the first seed in 1-500 whose pre-roll holds a marlin
#        (tests/games/fishing/sim/fishing_marlin_seed.gd; the pure pre-roll, never a sim search)
#   s7   threshold, 1 rider, erg+band+cadence_drop:rpm=40,at_s=600,for_s=20
#   s8   free_30, 2 band-trackers, seed 7, twice (--quick: e2e_2min, 3 riders, twice)
#   s9   fit_check on every FIT of the runs (check_sims --fit: laps per rider from the report)
#   s10  e2e_2min, 3 band-trackers
# --quick (CI) runs s10, s8 on e2e_2min and s9. The matrix stays out of tools/run_tests.
#
# Riders send no intents, so they play as Autopilot (brief 2.5). Every run goes through
# tools/run_game_sim at --sim-speed=200; a run that exits non-zero stops the script (75: the Godot
# lock wait timed out, rerun). A missing marlin seed skips s6's run and fails S6 at the end.
# Environment: FISHING_SIMS_OUT, FISHING_SEEDS, FISHING_SKIP_CHECK=1 (runs only),
# FISHING_GODOT_TIMEOUT (seconds per run, default 1800). tools/run_game_sim sets the locks.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../../../.." && pwd)"
cd "$repo"
out="${FISHING_SIMS_OUT:-build/fishing/sims}"
timeout_s="${FISHING_GODOT_TIMEOUT:-1800}"

mode=default
wanted=""
for a in "$@"; do
  case "$a" in
    --quick) mode=quick ;;
    --full) mode=full ;;
    -h | --help)
      sed -n '2,25p' "$0"
      exit 0
      ;;
    -*)
      printf 'run_sims: unknown option %s\n' "$a" >&2
      exit 2
      ;;
    *) wanted="$wanted $a" ;;
  esac
done
if [ "$mode" = full ]; then
  seeds="${FISHING_SEEDS:-$(seq -s ' ' 1 20)}"
else
  seeds="${FISHING_SEEDS:-1 2 3 4 5}"
fi
order="s1 s2 s3 s4 s5 s6 s7 s8 s9 s10"
if [ -z "${wanted// /}" ]; then
  if [ "$mode" = quick ]; then
    wanted="s10 s8 s9"
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
s6_missing=0

# run <name> <run_game_sim flags...>: one run; stops the script when it fails.
run() {
  local name="$1"
  shift
  printf '== %s\n' "$name"
  local code=0
  tools/run_game_sim --game=fishing --bots=0 --sim-speed=200 "--godot-timeout=$timeout_s" \
    "--report=$out/$name.json" "$@" || code=$?
  if [ "$code" -ne 0 ]; then
    printf 'run_sims: %s failed with exit %s\n' "$name" "$code" >&2
    exit "$code"
  fi
}

scenario_s1() { run s1_threshold --content=threshold --players=2 "--rider=$band" --seed=1; }

scenario_s2() {
  run s2_low --content=threshold --players=1 --rider=erg+band:offset_rpm=-18 --seed=1
  run s2_high --content=threshold --players=1 --rider=erg+band:offset_rpm=18 --seed=1
}

scenario_s3() {
  local s
  for s in $seeds; do
    run "s3_free30_seed${s}" --content=free_30 --players=4 "--rider=$band" --seed="$s"
  done
}

scenario_s4() {
  run s4_ap_none --content=free_30 --players=1 --rider=erg:compliance=1.0 --autopilot=none --seed=1
  run s4_ap_all --content=free_30 --players=1 --rider=erg:compliance=1.0 --autopilot=all --seed=1
}

scenario_s5() { run s5_base60 --content=base_60 --players=2 "--rider=$band" --seed=1; }

scenario_s6() {
  local line seed=""
  line="$(tools/godot.sh --headless --path . -s tests/games/fishing/sim/fishing_marlin_seed.gd \
    -- --trip=free_120 --from=1 --to=500 2>/dev/null | grep -E '^marlin_seed=' | tail -1)" || true
  seed="${line#marlin_seed=}"
  if ! [[ "$seed" =~ ^[0-9]+$ ]]; then
    printf 'run_sims: s6 skipped: no free_120 seed in 1-500 pre-rolls a marlin (%s)\n' "${line:-no output}" >&2
    rm -f "$out/s6_free120_marlin.json"
    s6_missing=1
    return 0
  fi
  printf '== s6: marlin seed %s\n' "$seed"
  run s6_free120_marlin --content=free_120 --players=1 "--rider=$band" --seed="$seed"
}

scenario_s7() {
  run s7_threshold_drop --content=threshold --players=1 \
    --rider=erg+band+cadence_drop:rpm=40,at_s=600,for_s=20 --seed=1
}

scenario_s8() {
  if [ "$mode" = quick ]; then
    run s8_e2e_a --content=e2e_2min --players=3 "--rider=$band" --seed=3
    run s8_e2e_b --content=e2e_2min --players=3 "--rider=$band" --seed=3
  else
    run s8_free30_a --content=free_30 --players=2 "--rider=$band" --seed=7
    run s8_free30_b --content=free_30 --players=2 "--rider=$band" --seed=7
  fi
}

scenario_s9() { :; } # FIT: check_sims --fit below

scenario_s10() { run s10_e2e --content=e2e_2min --players=3 "--rider=$band" --seed=1; }

for sc in $order; do
  case " $wanted " in *" $sc "*) "scenario_$sc" ;; esac
done

if [ "${FISHING_SKIP_CHECK:-0}" = "1" ]; then
  exit 0
fi
only="ALL"
fit=""
for sc in $wanted; do
  case "$sc" in
    s9) fit="--fit" only="$only,S9" ;;
    *) only="$only,S${sc#s}" ;;
  esac
done
args=("$out" "--seeds=${seeds// /,}")
if [ "$mode" = quick ] || [ -n "${*:-}" ] || [ -n "${FISHING_SIMS:-}" ]; then
  args+=("--only=$only")
fi
[ -n "$fit" ] && args+=("$fit")
code=0
node tests/games/fishing/sim/check_sims.mjs "${args[@]}" || code=$?
if [ "$s6_missing" = "1" ]; then
  printf 'FAIL S6  no free_120 seed in 1-500 pre-rolls a marlin, so scenario 6 did not run
'
  [ "$code" -eq 0 ] && code=1
fi
exit "$code"
