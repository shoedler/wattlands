class_name TankFiring
extends RefCounted
## The tank's firing in the view (docs/games/tank.md v3 "Firing"), ported from the r6b mock
## (assets/tank/v3/tools_src/tank_r6.gd: recoil(), rock(), jolt(), shake(), blast(), bursts()):
##   main gun  the blast from the baked sheets (TankRig.blast): on the muzzle the star flash with
##             the brake's jets and the fire ball with its fragments ("air"); latched where the shot
##             left the muzzle, at its bore angle, and scrolled with the world like TankFx's puffs
##             (blast_at, blast_shift), the smoke cloud and ring ("smoke"), the dust, the shockwave
##             and the pebbles on the road ("ground") and 26 sparks; 11 px recoil, the hull's
##             2 degree rock on its springs, a 2 px jolt, the scene flash (TankLightDraw) and a
##             three-frame screen shake (the view's stage offset)
##   bow guns  per round, alternating guns: a star flash at the muzzle for FLASH_BOW_S, a tracer
##             TRACER_W px wide and TRACER_LEN long (white head, yellow, orange tail; its glow on the
##             Light layer, tracers()), a case tumbling down from under the receiver, a 1.5 px kick
## Timed on the view's own clock from the shot cues; nothing feeds the rules.

const F_WHITE := Color("#fff8e0")
const F_YEL := Color("#ffd848")
const F_ORA := Color("#ff8a20")
const CASE_HI := Color("#e0bd74")
const CASE_LO := Color("#a07c40")
## How long the main gun's effects run (s) and the scene flash (s).
const MAIN_S := 2.0
const FLASH_S := 0.14
## The bow guns' rounds kept for drawing (s) and at most how many.
const ROUND_S := 0.9
const MAX_ROUNDS := 24
const TRACER_SPEED := 240.0
## A bow round's tracer (px) and its muzzle flash (s).
const TRACER_LEN := 11
const TRACER_W := 2
const FLASH_BOW_S := 0.08
## The loader's adapter: where the stow and the chambering sit in the r6 7 s cycle.
const STOW_TO := 3.4
const CHAMBER_FROM := 3.4
const CHAMBER_TO := 6.3
const RESET_FROM := 6.3
## A stow's last share is the tray going back down (RESET).
const STOW_RESET_K := 0.9
## How long chambering the next shell takes (brief: about 1 s; TankSteamState.chamber_s counts down).
const CHAMBER_S := 1.0

## Seconds since the main gun's last shot (large when none).
var fire_t: float = 99.0
## Main-gun shots seen.
var shots: int = 0
## Where the last shot left the muzzle (stage px) and its bore angle: the smoke, the dust and the
## sparks stay there, scrolled by `blast_shift` (the world's scroll since the shot, stage px).
var blast_at: Vector2 = Vector2.ZERO
var blast_ang: float = 0.0
var blast_shift: float = 0.0
## The bow guns' rounds: {k (gun), age (s)}.
var rounds: Array[Dictionary] = []
var _next_bow: int = 0


## Advances `dt` s; the world scrolled `scroll` stage px (TankView.scroll_px) meanwhile.
func step(dt: float, scroll: float = 0.0) -> void:
	fire_t += dt
	if fire_t < MAIN_S:
		blast_shift += scroll
	var keep: Array[Dictionary] = []
	for r in rounds:
		r["age"] = float(r["age"]) + dt
		if float(r["age"]) < ROUND_S:
			keep.append(r)
	rounds = keep


## A main-gun shot leaving the muzzle at `at` (stage px) along `ang` (radians).
func fire_main(at: Vector2 = Vector2.ZERO, ang: float = 0.0) -> void:
	fire_t = 0.0
	shots += 1
	blast_at = at
	blast_ang = ang
	blast_shift = 0.0


## Where the latched blast (smoke, dust, sparks) stands now (stage px).
func latched() -> Vector2:
	return blast_at - Vector2(blast_shift, 0.0)


## A bow round from gun `gun` (0 upper, 1 lower; the next one, alternating, when -1); returns the
## gun.
func bow_round(gun: int = -1) -> int:
	var k := _next_bow if gun < 0 else clampi(gun, 0, 1)
	_next_bow = (k + 1) % 2
	if rounds.size() >= MAX_ROUNDS:
		rounds.pop_front()
	rounds.append({"k": k, "age": 0.0})
	return k


func bow_kicking(k: int, dur: float) -> bool:
	for r in rounds:
		if int(r["k"]) == k and float(r["age"]) < dur:
			return true
	return false


func active() -> bool:
	return fire_t < MAIN_S or not rounds.is_empty()


func recoil() -> float:
	return TankInterior.recoil(fire_t)


## The hull's rock on its springs after the shot (degrees, negative = nose up).
func rock() -> float:
	return rock_at(fire_t)


static func rock_at(ft: float) -> float:
	if ft < 0.0 or ft > 1.8:
		return 0.0
	return -2.2 * exp(-ft * 2.6) * cos(ft * 9.0) * minf(ft / 0.05, 1.0)


## The jolt (px back along the bore) in the first frames.
func jolt() -> float:
	return jolt_at(fire_t)


static func jolt_at(ft: float) -> float:
	if ft < 0.0 or ft > 0.15:
		return 0.0
	return 2.0 if ft < 0.07 else 1.0


## The screen shake (canvas px) for the first three 30 fps frames after the shot.
func screen_shake() -> Vector2i:
	return shake_at(fire_t)


static func shake_at(ft: float) -> Vector2i:
	if ft < 0.0 or ft >= 0.1:
		return Vector2i.ZERO
	var k := clampi(int(floor(ft * 30.0)), 0, 2)
	return [Vector2i(2, -1), Vector2i(-2, 1), Vector2i(1, 1)][k]


## The scene flash's strength (1 at the shot, 0 after FLASH_S).
func flash_k() -> float:
	if fire_t < 0.0 or fire_t >= FLASH_S:
		return 0.0
	return 1.0 - fire_t / FLASH_S


## The blast sheet's frame `fire_t` s after the shot (-1 when the part is over).
static func frame_at(ft: float, fps: float, frames: int) -> int:
	if ft < 0.0:
		return -1
	var f := int(floor(ft * fps))
	return f if f < frames else -1


# --- Drawing (the view's Tank layer, stage px) --------------------------------------------------------------


func draw(ci: CanvasItem, v: TankView) -> void:
	if fire_t < MAIN_S:
		_blast(ci, v)
	if not rounds.is_empty():
		_rounds(ci, v)


func _blast(ci: CanvasItem, v: TankView) -> void:
	var rig := v.rig
	var at := latched()
	var gnd: Dictionary = rig.blast.get("ground", {})
	if not gnd.is_empty():
		var f := frame_at(fire_t, rig.blast_fps, int(gnd["frames"]))
		if f >= 0:
			var gy := v.ground_y(at.x)
			_sheet(ci, gnd, f, rig.blast_cols, Vector2(roundf(at.x), roundf(gy)), 0.0)
	var smoke: Dictionary = rig.blast.get("smoke", {})
	if not smoke.is_empty():
		var f3 := frame_at(fire_t, rig.blast_fps, int(smoke["frames"]))
		if f3 >= 0:
			_sheet(ci, smoke, f3, rig.blast_cols, at.round(), blast_ang)
	var air: Dictionary = rig.blast.get("air", {})
	if not air.is_empty():
		var f2 := frame_at(fire_t, rig.blast_fps, int(air["frames"]))
		if f2 >= 0:
			_sheet(ci, air, f2, rig.blast_cols, v.muzzle(), v.barrel_vector().angle())
	if fire_t < 0.5:
		var ft := floorf(fire_t * rig.blast_fps) / rig.blast_fps
		for j in 26:
			var sa := blast_ang + (TankPx.h2(j, 6, 47) - 0.5) * 2.0
			var spd := 120.0 + 180.0 * TankPx.h2(j, 7, 47)
			var dv := Vector2(cos(sa), sin(sa))
			var p0 := at + dv * spd * ft + Vector2(0, 80.0 * ft * ft)
			TankBody._line(ci, p0 - dv * 4.0, p0, F_YEL if j % 3 else F_ORA)


func _sheet(ci: CanvasItem, part: Dictionary, f: int, cols: int, at: Vector2, ang: float) -> void:
	var sz: Vector2 = part["size"]
	var src := Rect2(Vector2(float(f % cols) * sz.x, float(f / cols) * sz.y), sz)
	ci.draw_set_transform(at, ang, Vector2.ONE)
	ci.draw_texture_rect_region(part["tex"], Rect2(-(part["origin"] as Vector2), sz), src)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


## A bow round's tracer as drawn `age` s after it left muzzle `m` along `sd`: its head (stage px).
static func tracer_head(m: Vector2, sd: Vector2, age: float) -> Vector2:
	return m + sd * (TRACER_SPEED * age + 4.0)


## The bow rounds' tracer heads and muzzle flashes now, for the Light layer's glow: [{p (the
## tracer's head), muzzle, flash (0..1 while the muzzle flash burns, else 0)}].
func tracers(v: TankView) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in rounds:
		var k := int(r["k"])
		var age := float(r["age"])
		var m := v.bow_muzzle(k)
		var sd := v.bow_shot(k)
		out.append({"p": _head(v, m, sd, age), "muzzle": m, "flash": _bow_flash(age)})
	return out


## A tracer's head, stopped where it strikes the near threat the guns fire at.
static func _head(v: TankView, m: Vector2, sd: Vector2, age: float) -> Vector2:
	var tp := tracer_head(m, sd, age)
	if v.bow_target != Vector2.ZERO and m.distance_to(tp) > m.distance_to(v.bow_target):
		return v.bow_target
	return tp


static func _bow_flash(age: float) -> float:
	return clampf(1.0 - age / FLASH_BOW_S, 0.0, 1.0) if age < FLASH_BOW_S else 0.0


## The bow guns' rounds (tank_r6 bursts(), heavier): the flash, the tracer, the case.
func _rounds(ci: CanvasItem, v: TankView) -> void:
	var wins: Array[Rect2] = [
		v.rig.windows.get("boxwin", Rect2()), v.rig.windows.get("boxwin2", Rect2())
	]
	for r in rounds:
		var k := int(r["k"])
		var age := float(r["age"])
		var m := v.bow_muzzle(k)
		var sd := v.bow_shot(k)
		var nn := Vector2(-sd.y, sd.x)
		var tp := _head(v, m, sd, age)
		if age < ROUND_S and (v.bow_target == Vector2.ZERO or tp != v.bow_target):
			for s in TRACER_LEN:
				var c := F_WHITE if s < 3 else (F_YEL if s < 6 else F_ORA)
				if s >= TRACER_LEN - 2:
					c = Color(F_ORA, 0.55)
				var q := (tp - sd * float(s)).floor()
				ci.draw_rect(Rect2(q, Vector2(1, TRACER_W)), c)
		if age < FLASH_BOW_S:
			var big := age < FLASH_BOW_S * 0.5
			for s2 in 7 if big else 5:
				var q1 := m + sd * s2
				ci.draw_rect(Rect2(q1.floor(), Vector2.ONE), F_WHITE if s2 < 3 else F_YEL)
			var arms := [-3.0, -2.0, -1.0, 1.0, 2.0, 3.0] if big else [-2.0, -1.0, 1.0, 2.0]
			for e: float in arms:
				var q2 := m + sd + nn * e
				ci.draw_rect(Rect2(q2.floor(), Vector2.ONE), F_ORA if absf(e) > 1.0 else F_YEL)
		if age < 0.55:
			var w: Rect2 = wins[k]
			var e0 := v.at_sprite(Vector2(w.position.x + 6.0, w.end.y))
			var cp := e0 + Vector2(-14.0 * age, 20.0 * age + 0.5 * 260.0 * age * age)
			var tumble := int(floor(age * 24.0)) % 2
			ci.draw_rect(Rect2(cp.floor(), Vector2.ONE), CASE_HI)
			var o := Vector2(1, 0) if tumble == 0 else Vector2(0, 1)
			ci.draw_rect(Rect2(cp.floor() + o, Vector2.ONE), CASE_LO)


# --- The loader's picture (the adapter) ---------------------------------------------------------------------


## The loader's picture for TankInterior from the contracts (TankSteamState): {lt (s into the r6
## 7 s cycle, < 0 idle), ready (rounds shown in the rack), fire_t}. The rack count is `rack`; the
## next round's stow is `load_t` (0..1, while the Loader is manned and the rack not full); the
## chambering after a shot is `chamber_s` counting down from CHAMBER_S.
static func loader_view(state: TankState, steam: TankStationState, p_fire_t: float) -> Dictionary:
	var sst := steam as TankSteamState
	if sst == null:
		return from_fields(0, -1.0, -1.0, p_fire_t)
	var stow_k := -1.0
	if not sst.is_empty() and sst.load_t > 0.0 and sst.load_t < 1.0 and not state.hull.breakdown:
		stow_k = sst.load_t
	var chamber_k := -1.0
	if sst.chamber_s > 0.0:
		chamber_k = clampf(1.0 - sst.chamber_s / CHAMBER_S, 0.0, 0.999)
	return from_fields(sst.rack, stow_k, chamber_k, p_fire_t)


## Maps the rack count, the next round's stow (0..1, < 0 none) and the chambering (0..1, < 0 none)
## onto the r6 cycle: the chambering is FEED .. BREECH SHUT, a stow RACK .. STOW and then RESET (the
## stowed round shown racked while the tray goes down).
static func from_fields(ready: int, stow_k: float, chamber_k: float, p_fire_t: float) -> Dictionary:
	var lt := -1.0
	var shown := clampi(ready, 0, 3)
	if chamber_k >= 0.0 and chamber_k < 1.0:
		lt = CHAMBER_FROM + (CHAMBER_TO - CHAMBER_FROM) * chamber_k
	elif stow_k >= 0.0 and stow_k < 1.0 and ready < 3:
		if stow_k < STOW_RESET_K:
			lt = STOW_TO * stow_k / STOW_RESET_K
		else:
			lt = (
				RESET_FROM
				+ (TankInterior.CYCLE - RESET_FROM) * (stow_k - STOW_RESET_K) / (1.0 - STOW_RESET_K)
			)
			shown = mini(shown + 1, 3)
	return {"lt": lt, "ready": shown, "fire_t": p_fire_t}
