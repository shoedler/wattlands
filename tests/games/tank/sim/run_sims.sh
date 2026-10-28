#!/usr/bin/env bash
# tests/games/tank/sim/run_sims.sh: brief section 4's simulation matrix (S1-S7), deduplicated per
# the run notes' reuse plan, then check_sims.mjs over the reports (which also runs fit_check on
# every FIT file the runs wrote). S8 is a GUT test (tests/games/tank/sim/test_tank_s8.gd).
#
#   bash tests/games/tank/sim/run_sims.sh [scenario ...]
#   TANK_SIMS="s2 s5" bash tests/games/tank/sim/run_sims.sh
#
# Scenarios (default: all). One report per run in build/tank/sims/ (TANK_SIMS_OUT):
#   s1  ashfall_road, compliant `erg` riders, crews 1-4 (crews 2-4 run as HOST) x seeds 1-3
#       (these runs also serve T1-T4, T6, T7 (crew 4) and, as the 100% leg, S3's T5, S4 and S7's first run)
#   s2  zero riders: crew 3 (HOST: the shared pause holds the depot) and crew 1 (SOLO: it pauses),
#       and crew 3 spinning at 10 W and 25 rpm (no pause, no AFK: every stage overruns)
#   s3  crew 3 at compliance 0.85 and 0.70 x seeds 1-3 (100% comes from s1)
#   s4  drill, compliant, crews 1-4 as the S4 rule checks' other content (s1 is the other)
#   s5  cadence_drop to 30 rpm at at_phase + at_target_pct=60: crew 3 in a Gun phase (slot 1, plan
#       phase 2, ERG 55-100% with the bank), crew 4 in a Lights phase (slot 3, plan phase 1, ERG 65-80%)
#       (v3: Drive digs in SIM, so no 90% gun line arms rescue any more)
#   s6  crew 3, haptics off for slot 0
#   s7  the s1 crew 3 seed 1 run again (same arguments, another report name)
#   s9  crew 1 with a scripted sprinter (mock `intervals`: 20 s at 300 W, 150 W for 17 s, FTP 200; it
#       is not a compliant rider, so its grade does not matter): the sprint half of the workout that
#       the compliant Autopilot runs never reach (Surge to evade, a gun line entered after a sprint).
#       S8 is the GUT test test_tank_s8.gd.
#   s10 crew 3 on the network path: every rider the same scripted sprinter (a client on the steam
#       engine surges in its window: its `over` reaches the host as Telemetry.intents, owned by the
#       steam engine; a client's `aim` needs a key, which headless sims cannot press: GUT-tested in
#       tests/games/tank/integration), and slot 1 stopping dead for 60 s in the stage 1 gun line
#       (rescue, AFK, a station on reserve, back; at_phase=2, ERG target >= 60%)
#   s11 free roam, compliant `erg` riders: roam_10 for crews 1 (SOLO) and 4 (HOST), roam_30 for crew 3 (HOST):
#       time up, the overtime bound, no patrol after time up, the FIT laps (drive-out, roam, cool-down), the grade
#   s12 free roam roam_10, crew 3 at 0 W (HOST): like s2's zero crew the host's shared pause holds the drive-out, so
#       the run ends at --max-sim-seconds still paused: no kill by crew fire, grade D
#   s13 v3 seat switching: crew 3 HOST with --autopilot=none (every human on the fallback, seated by the host's
#       Autopilot through replans, the two clients included): the lock, the replans, the switches, the laps
#
# A scenario that needs another's report (s3, s4, s7 need s1 crew 3; the checks of s1 reuse
# them) runs that report first when it is missing. Every run goes through tools/run_game_sim at
# --sim-speed=200 and stops this script on a non-zero exit (75: the Godot lock wait timed out,
# just rerun). A full matrix is about 50 runs, 10 to 60 s each on a quiet machine.
# Environment: TANK_SEEDS="1 2 3" (seeds), TANK_SIMS_OUT (report dir), TANK_SKIP_CHECK=1 (runs
# only), TANK_FIT=0 (no fit_check), TANK_GODOT_TIMEOUT (seconds per run, default 1800).
# The locks (no hardware control, no network integrations) are exported by tools/run_game_sim;
# the art variables never matter here (no art tool runs), but they are removed for good measure.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../../../.." && pwd)"
cd "$repo"
unset FAL_KEY WATTLANDS_ALLOW_ART || true
out="${TANK_SIMS_OUT:-build/tank/sims}"
seeds="${TANK_SEEDS:-1 2 3}"
timeout_s="${TANK_GODOT_TIMEOUT:-1800}"
mkdir -p "$out"

ERG='erg:compliance=1.0'
# Cadence collapse to 30 rpm for 30 s once the rider's own plan phase is `at_phase` and its
# applied ERG target is at least 60% FTP (the profile waits for it).
SPRINTER='intervals:on_w=300,off_w=150,on_s=12,off_s=28,rpm=100'
# S9's sprinter rides 20 s on, 17 s off, so its sprints cover an Advance's end (the first ends at
# about 490 s with the v2 content and this rider): a gun line entered while still sprinting.
S9_SPRINTER='intervals:on_w=300,off_w=150,on_s=20,off_s=17,rpm=100'
STOP='erg+cadence_drop:rpm=0,at_phase=2,at_target_pct=60,for_s=60'
DYNAMO_DROP='erg+cadence_drop:rpm=30,at_phase=2,at_target_pct=60,for_s=30'
ARC_DROP='erg+cadence_drop:rpm=30,at_phase=1,at_target_pct=60,for_s=30'
# Pedaling for the not_pedaling detector (cadence >= 20 rpm) with no effort to speak of.
IDLE='const:w=10,rpm=25'

# run <name> <run_game_sim flags...>: one run; stops the script when it fails.
run() {
  local name="$1"
  shift
  printf '== %s\n' "$name"
  local code=0
  tools/run_game_sim --game=tank --sim-speed=200 "--godot-timeout=$timeout_s" \
    "--report=$out/$name.json" "$@" || code=$?
  if [ "$code" -ne 0 ]; then
    printf 'run_sims: %s failed with exit %s\n' "$name" "$code" >&2
    exit "$code"
  fi
}

# have <name>: true when the report exists already (a dependency another scenario ran).
have() { [ -f "$out/$1.json" ]; }

# s1_run <crew> <seed>
s1_run() {
  run "s1_c${1}_seed${2}" --content=ashfall_road "--players=$1" --bots=0 "--rider=$ERG" "--seed=$2"
}

scenario_s1() {
  local c s
  for c in 1 2 3 4; do
    for s in $seeds; do s1_run "$c" "$s"; done
  done
}

scenario_s2() {
  # All three stop: the host's shared pause (BRIEF 3.5) holds the depot, so the run ends at
  # --max-sim-seconds still paused. The spinning crew pedals for every detector but gives nothing.
  run s2_c3_zero --content=ashfall_road --players=3 --bots=0 --rider=zero --seed=1 --max-sim-seconds=300
  run s2_c3_idle --content=ashfall_road --players=3 --bots=0 "--rider=$IDLE" --seed=1
  run s2_c1_zero --content=ashfall_road --players=1 --bots=0 --rider=zero --seed=1
}

scenario_s3() {
  local s
  for s in $seeds; do
    have "s1_c3_seed${s}" || s1_run 3 "$s"
    run "s3_c3_c85_seed${s}" --content=ashfall_road --players=3 --bots=0 \
      --rider=erg:compliance=0.85 "--seed=$s"
    run "s3_c3_c70_seed${s}" --content=ashfall_road --players=3 --bots=0 \
      --rider=erg:compliance=0.70 "--seed=$s"
  done
}

scenario_s4() {
  local c
  for c in 1 2 3 4; do
    run "s4_drill_c${c}" --content=drill "--players=$c" --bots=0 "--rider=$ERG" --seed=1
  done
  # The ashfall_road half of S4 reads s1's reports.
  local s
  for s in $seeds; do
    for c in 1 2 3 4; do have "s1_c${c}_seed${s}" || s1_run "$c" "$s"; done
  done
}

scenario_s5() {
  run s5_c3_dynamo_drop --content=ashfall_road --players=3 --bots=0 \
    "--rider=$ERG" "--rider=$DYNAMO_DROP" "--rider=$ERG" --seed=1
  run s5_c4_arc_drop --content=ashfall_road --players=4 --bots=0 \
    "--rider=$ERG" "--rider=$ERG" "--rider=$ERG" "--rider=$ARC_DROP" --seed=1
}

scenario_s6() {
  run s6_c3_haptics_off --content=ashfall_road --players=3 --bots=0 "--rider=$ERG" \
    --haptics-off=0 --seed=1
}

scenario_s7() {
  have s1_c3_seed1 || s1_run 3 1
  run s7_c3_seed1 --content=ashfall_road --players=3 --bots=0 "--rider=$ERG" --seed=1
}

scenario_s9() {
  run s9_c1_sprint --content=ashfall_road --players=1 --bots=0 "--rider=$S9_SPRINTER" --seed=1
}

scenario_s10() {
  run s10_c3_clients_sprint --content=ashfall_road --players=3 --bots=0 "--rider=$SPRINTER" --seed=1
  run s10_c3_dynamo_stop --content=ashfall_road --players=3 --bots=0 "--rider=$ERG" "--rider=$STOP" \
    "--rider=$ERG" --seed=1
}

scenario_s11() {
  run s11_roam10_c1 --content=roam_10 --players=1 --bots=0 "--rider=$ERG" --seed=1
  run s11_roam10_c4 --content=roam_10 --players=4 --bots=0 "--rider=$ERG" --seed=1
  run s11_roam30_c3 --content=roam_30 --players=3 --bots=0 "--rider=$ERG" --seed=1
}

scenario_s12() {
  run s12_roam10_c3_zero --content=roam_10 --players=3 --bots=0 --rider=zero --seed=1 --max-sim-seconds=300
}

scenario_s13() {
  run s13_c3_seats --content=ashfall_road --players=3 --bots=0 "--rider=$ERG" --autopilot=none --seed=1
}

order="s1 s2 s3 s4 s5 s6 s7 s9 s10 s11 s12 s13"
if [ "$#" -gt 0 ]; then
  wanted="$*"
else
  wanted="${TANK_SIMS:-$order}"
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

# The checks that belong to the scenarios that ran (all of them when everything ran).
only=""
for sc in $wanted; do
  only="$only,S${sc#s}"
done
only="${only#,}"

if [ "${TANK_SKIP_CHECK:-0}" != "1" ]; then
  args=("$out" "--seeds=${seeds// /,}")
  if [ "${TANK_FIT:-1}" != "0" ]; then args+=(--fit); fi
  if [ "$#" -gt 0 ] || [ -n "${TANK_SIMS:-}" ]; then args+=("--only=$only"); fi
  node tests/games/tank/sim/check_sims.mjs "${args[@]}"
fi
