class_name Wl
extends RefCounted
## Shared platform constants (contract, frozen after W0; additive changes only).
##
## Phase kinds, modes, roles, scaling modes and `clamped_by` rule names are plain
## Strings so they survive JSON (reports, network, content) unchanged.

const BUILD := "0.2.1"
## Network protocol version (BRIEF 5.3 `hello.proto`, 5.5 schemas).
const PROTO := 1
const RELAY_GAME := "wattlands"
## Fixed sim step (BRIEF 3.6): every sim, governor and mock rule advances in these steps.
const SIM_DT := 0.05
const SIM_HZ := 20
const SNAPSHOT_HZ := 10
const TELEMETRY_HZ := 5
const ROSTER_HZ := 2
## Peer id meaning "every rider" in HudFeed.toast/banner and Transport.send.
const ALL_PEERS := 0
## Host peer id assigned by the relay.
const HOST_PEER := 1

# Phase kinds (PlanPhase.kind, PhaseState.kind)
const WARMUP := "WARMUP"
const WORK := "WORK"
const RECOVERY := "RECOVERY"
const FREE := "FREE"
const COOLDOWN := "COOLDOWN"
const PHASE_KINDS: Array[String] = [WARMUP, WORK, RECOVERY, FREE, COOLDOWN]

# Trainer modes
const ERG := "ERG"
const SIM := "SIM"
const RESISTANCE := "RESISTANCE"
const OFF := "OFF"

# Session roles (GameContext.role)
const SOLO := "SOLO"
const HOST := "HOST"
const CLIENT := "CLIENT"

# Effort scaling modes (BRIEF 3.3)
const FAIR_FTP := "FAIR_FTP"
const WKG := "WKG"
const RAW := "RAW"
const SCALING_MODES: Array[String] = [FAIR_FTP, WKG, RAW]

# SIM grade sources (PlanPhase.grade_source)
const GRADE_FLAT := "flat"
const GRADE_COURSE := "course"
const GRADE_GAME := "game"

# How a phase ended (BRIEF 5.5 `phase.ended_by`)
const ENDED_DURATION := "duration"
const ENDED_MAX_S := "max_s"
const ENDED_END_PHASE := "end_phase"
const ENDED_FINISHED := "finished"
const ENDED_START := "start"

# `clamped_by` rule names reported by the SafetyGovernor (BRIEF 4.6). A report lists
# every rule that changed the requested value, in the order they applied.
const CLAMP_UNVERIFIED := "unverified"  ## 4.6.1 x0.85 while FTP is unverified
const CLAMP_CEILING := "ceiling"  ## 4.6.1 min(150% FTP, 1000 W, trainer max)
const CLAMP_LONG_PHASE := "long_phase"  ## 4.6.1 105% cap in phases longer than 300 s
const CLAMP_LIMIT_105 := "limit_105"  ## 4.6.1 duration limit latched at 105%
const CLAMP_LIMIT_120 := "limit_120"  ## 4.6.1 duration limit latched at 120%
const CLAMP_WARMUP := "warmup"  ## 4.6.8 warm-up caps (ERG 65%, grade -2..+3, no haptics)
const CLAMP_FLOOR := "floor"  ## 4.6.1 floor max(30% FTP, 50 W)
const CLAMP_RESCUE := "rescue"  ## 4.6.3 50% FTP during rescue
const CLAMP_COASTING := "coasting"  ## 4.6.4 floor while coasting
const CLAMP_SLEW := "slew"  ## 4.6.2 increases at most 30 W/s
const CLAMP_SWITCH := "switch_ramp"  ## 4.5 ramped ERG<->SIM entry target
const CLAMP_PANIC := "panic"  ## 4.6.5 emergency safe
const CLAMP_GRADE_RANGE := "grade_range"  ## 4.6.6 user grade range (default -5..+10)
const CLAMP_GRADE_LIMIT := "grade_limit"  ## 4.6.6 total -10..+16
const CLAMP_HAPTIC := "haptic_limit"  ## 4.6.6 haptic <= +3% (or equal wind force), <= 8 s (only when that bound bites)
const CLAMP_HAPTIC_INTENSITY := "haptic_intensity"  ## 4.6.6 haptic scaled by the rider's intensity setting
const CLAMP_FACTOR := "factor_bounds"  ## 4.6.6 crr/cw factors in [0.5, 1.0]
const CLAMP_PAUSE := "paused"  ## 4.1 paused: ERG floor or SIM flat

# Directive refusal reasons (DirectiveResult.reason, applied records)
const REFUSE_NO_PHASE := "no_phase"
const REFUSE_COOLDOWN := "cooldown"
const REFUSE_RANGE := "outside_range_pct"
const REFUSE_SIM_BLOCK_LENGTH := "sim_block_length"
const REFUSE_SWITCH_SPACING := "switch_spacing"
const REFUSE_MODE_GRADE := "mode_grade_outside_sim"
const REFUSE_HAPTIC_ERG := "haptic_in_erg"
const REFUSE_HAPTIC_OFF := "haptics_off"
const REFUSE_HAPTIC_WARMUP := "haptic_in_warmup"
const REFUSE_HAPTIC_COOLDOWN := "haptic_cooldown"
const REFUSE_BAD_FIELDS := "bad_fields"
const REFUSE_UNKNOWN_PEER := "unknown_peer"
const REFUSE_NOT_OPEN_ENDED := "not_open_ended"
const REFUSE_MIN_S := "before_min_s"
const REFUSE_PLAN_INVALID := "plan_invalid"
const REFUSE_NOT_AUTHORITY := "not_authority"
## mode "ERG" requested inside a SIM phase (a SIM block exists only in an ERG phase).
const REFUSE_ERG_IN_SIM := "erg_in_sim_phase"
## course_grade outside a grade_source "game" phase.
const REFUSE_NOT_GAME_GRADE := "grade_source_not_game"
## A SIM block requested during rescue, coasting, AFK or pause.
const REFUSE_SIM_BLOCK_UNSAFE := "sim_block_unsafe"

# Input actions (BRIEF 3.5). The input map in project.godot defines each.
const ACTIONS: Array[StringName] = [
	&"confirm",
	&"back",
	&"up",
	&"down",
	&"left",
	&"right",
	&"ability_1",
	&"ability_2",
	&"item",
	&"swap",
	&"shift_up",
	&"shift_down",
	&"pause",
	&"panic",
]

# Pedal gestures (BRIEF 3.5). `surge` doubles as confirm, `coast` as back, `stop_5s` as pause.
const G_PEDAL_START := &"pedal_start"
const G_SURGE := &"surge"
const G_COAST := &"coast"
const G_STOP_5S := &"stop_5s"
const GESTURES: Array[StringName] = [G_PEDAL_START, G_SURGE, G_COAST, G_STOP_5S]
## The shared not_pedaling detector's name (BRIEF 3.5): a state, never a fired gesture.
const G_NOT_PEDALING := &"not_pedaling"

# Session slot looks (BRIEF 3.9): colorblind-safe colors (Okabe-Ito), always with a shape
# and a pattern. Slots 4-7 repeat 0-3 with hollow shapes.
const SLOT_COLORS: Array[Color] = [
	Color("#D55E00"),  # red (vermillion)
	Color("#0072B2"),  # blue
	Color("#F0E442"),  # yellow
	Color("#009E73"),  # green (bluish green)
]
const SLOT_COLOR_NAMES: Array[String] = ["red", "blue", "yellow", "green"]
const SLOT_SHAPES: Array[String] = ["circle", "triangle", "square", "diamond"]
const SLOT_PATTERNS: Array[String] = ["solid", "dashed", "dotted", "double"]
const MAX_SLOTS := 8


## The session look for a slot index: {color, color_name, shape, pattern, hollow}.
static func slot_look(slot_index: int) -> Dictionary:
	var i := posmod(slot_index, 4)
	return {
		"color": SLOT_COLORS[i],
		"color_name": SLOT_COLOR_NAMES[i],
		"shape": SLOT_SHAPES[i],
		"pattern": SLOT_PATTERNS[i],
		"hollow": posmod(slot_index, MAX_SLOTS) >= 4,
	}


## True for every phase kind a plan may contain.
static func is_phase_kind(kind: String) -> bool:
	return PHASE_KINDS.has(kind)
