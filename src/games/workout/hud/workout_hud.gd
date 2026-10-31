class_name WorkoutHud
extends RefCounted
## Workout's HUD (BRIEF 3.7, 3.9): the game's own Controls at Rect2i placements in art px of the
## 960 x 540 base, which the HudLayer anchors on the flexible canvas, no kit widgets, in an enamel road
## sign look (WorkoutHudDraw), and the host-side calls' helpers (banners at interval starts, the
## Rolling road and sprint power bands, the in-band readout):
##  - top centre: the timeline (WorkoutHudTimeline), the toasts top left under the sky, banners under it;
##  - bottom left: my numbers (WorkoutHudMine: watts, %FTP, cadence, the instruction, W' and the gear);
##  - bottom centre: the crew (WorkoutHudCrew); bottom right: the score (WorkoutHudScore).
## WorkoutHudModel holds what they show. The platform's rescue, warm-up and link notices stay on.

const READOUT_TIB := "workout_tib"
## Teammate status refresh (sim steps) when nothing flips.
const STATUS_EVERY_TICKS := 20
## Local in-band readout refresh (sim steps).
const READOUT_EVERY_TICKS := 10
const SPRINT_WARN_S := 10.0
const BANNER_S := 4.0
## Sprint power band shown on the gauge (x FTP) outside the warm-up (the rule needs 1.2).
const SPRINT_BAND := [1.2, 1.6]
## The first 300 s of the plan are the warm-up (BRIEF 4.6.8): no sprint band there.
const WARMUP_S := 300.0
## The layout (art px of the 960 x 540 base; the HudLayer anchors it on the flexible canvas).
const LAYOUT := {
	"timeline": Rect2i(240, 6, 480, 66),
	"mine": Rect2i(6, 440, 222, 94),
	"crew": Rect2i(288, 468, 416, 66),
	"score": Rect2i(770, 468, 184, 66),
	"toasts": Rect2i(6, 76, 300, 24),
	"banners": Rect2i(280, 104, 400, 32),
}
## The palette for the platform's toasts, banners and help.
const PALETTE := {
	"panel": WorkoutHudDraw.PANEL,
	"panel_border": WorkoutHudDraw.FRAME,
	"text": WorkoutHudDraw.TEXT,
	"text_dim": WorkoutHudDraw.DIM,
	"bar_bg": WorkoutHudDraw.TRACK,
	"bar_fg": WorkoutHudDraw.FRAME,
	"accent": WorkoutHudDraw.AMBER,
	"banner_bg": WorkoutHudDraw.PANEL,
	"banner_text": WorkoutHudDraw.TEXT,
	"band": WorkoutHudDraw.BAND,
	"glow": WorkoutHudDraw.AMBER,
	"glow_text": WorkoutHudDraw.TEXT,
	"font_scale_px": 18,
	"text_px": 36,
	"key_px": 54,
	"grid_px": 2,
	"corner_radius": 0,
	"text_outline": false,
}
## The help overlay: [string key, at, arrow_to] in art px of the base (each arrow ends inside the
## plate it explains, so it moves with that plate, except the blocks': it ends on the strip on the bank,
## which HudLayer.help_art_point moves with the bottom and right edges).
const HELP := [
	["WORKOUT_HELP_NUMBERS", Vector2(150, 404), Vector2(70, 462)],
	["WORKOUT_HELP_CADENCE", Vector2(340, 330), Vector2(170, 462)],
	["WORKOUT_HELP_TIMELINE", Vector2(480, 100), Vector2(480, 40)],
	["WORKOUT_HELP_BLOCKS", Vector2(660, 380), Vector2(560, 440)],
	["WORKOUT_HELP_CREW", Vector2(560, 300), Vector2(496, 490)],
	["WORKOUT_HELP_GEARS", Vector2(440, 424), Vector2(170, 524)],
]


## The HudSpec: Workout's Controls only, shows_power (my numbers show raw W and %FTP), the palette
## and the help.
static func spec(game: WorkoutGame = null) -> HudSpec:
	var hs := HudSpec.new()
	_add(hs, WorkoutHudTimeline.new(), game, "timeline")
	_add(hs, WorkoutHudMine.new(), game, "mine")
	_add(hs, WorkoutHudCrew.new(), game, "crew")
	_add(hs, WorkoutHudScore.new(), game, "score")
	hs.toasts_at(LAYOUT["toasts"])
	hs.banners_at(LAYOUT["banners"])
	hs.shows_power = true
	hs.show_safety_banners = true
	hs.help = help()
	var pal := PALETTE.duplicate()
	pal["font"] = WorkoutHudDraw.font()
	hs.palette = pal
	return hs


static func _add(hs: HudSpec, c: WorkoutHudCtl, game: WorkoutGame, key: String) -> void:
	var r: Rect2i = LAYOUT[key]
	hs.add_control(c.setup(game, r), r)


static func help() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Array in HELP:
		out.append({"text": str(e[0]), "at": e[1], "arrow_to": e[2]})
	return out


## The power band (W) for `rider` in SIM phase `index`, or [] for none:
## Rolling road: the session band (76-105% FTP); a FREE sprint after the warm-up:
## 120-160% FTP; a sprint inside the first 300 s: none (the rider stays easy there); a
## longer FREE phase (free riding, WorkoutSession.is_sprint false): none.
static func band_for(state: WorkoutState, index: int, rider: WorkoutRiderState) -> Array:
	var p := state.phase(index)
	if p == null or p.mode != Wl.SIM:
		return []
	if p.kind == Wl.FREE:
		if state.phase_start_s(index) < WARMUP_S or not WorkoutSession.is_sprint(p):
			return []
		return [float(SPRINT_BAND[0]) * rider.ftp, float(SPRINT_BAND[1]) * rider.ftp]
	return [
		float(state.band_pct[0]) / 100.0 * rider.ftp, float(state.band_pct[1]) / 100.0 * rider.ftp
	]


## Banner key and args for the start of phase `index` ({} for none: the cool-down has the
## platform's own).
static func interval_banner(state: WorkoutState, index: int, strings: GameStrings) -> Dictionary:
	var p := state.phase(index)
	if p == null or p.kind == Wl.COOLDOWN:
		return {}
	var args := {"label": strings.t(p.label), "time": WorkoutSession.clock(p.duration_s)}
	if p.mode == Wl.ERG:
		if p.has_ramp():
			args["from"] = int(round(p.target_pct))
			args["to"] = int(round(p.ramp_to_pct))
			return {"key": "WORKOUT_BANNER_RAMP", "args": args}
		args["pct"] = int(round(p.target_pct))
		return {"key": "WORKOUT_BANNER_ERG", "args": args}
	if p.kind == Wl.FREE:
		return {
			"key":
			"WORKOUT_BANNER_SPRINT" if WorkoutSession.is_sprint(p) else "WORKOUT_BANNER_FREE",
			"args": args
		}
	args["lo"] = int(round(float(state.band_pct[0])))
	args["hi"] = int(round(float(state.band_pct[1])))
	return {"key": "WORKOUT_BANNER_ROLLING", "args": args}


## "94%" for a 0..1 fraction.
static func pct_text(fraction: float) -> String:
	return "%d%%" % int(round(clampf(fraction, 0.0, 1.0) * 100.0))
