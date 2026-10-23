class_name FishingLayout
extends RefCounted
## Lane geometry and HUD placement in art pixels at pixel_base [640, 360] (brief 3.2; G0, owned by
## the view and HUD builder afterwards). Pure functions: the view, the HUD and their tests share
## them. `i` is the lane (= slot index), `n` the lane count (1-4).
##
## HUD placement (G0 decision "HUD layout", docs/decisions/fishing.md):
##  - deck bar y 0-23: one game Control (trip clock, the local rider's phase chip, fish row or gaff
##    meter, catch board, hookup level) plus the kit `wbal` and `gear` widgets in their own rects;
##  - the local lane's HUD zone (x 427-639): the kit timeline (213 x 36) on top, then one 36 px row:
##    power gauge (100), strain bar (5), cadence (97), slack bar (5) - each kit widget at its
##    minimum rect, so W and rpm keep >= 48 px at 1080p;
##  - the PANIC button owns art x >= 503, y >= 316: when the row would reach it (the bottom lane at
##    3 and 4 lanes) the timeline is left out (the deck bar's phase chip stands in) and the row
##    moves to the zone's top;
##  - every other lane: one compact FishingLaneHud (213 x <= 36) at its zone's top, clear of PANIC;
##  - toasts below the deck bar; banners over the local lane's left two-thirds.

const ROW_H := 36
const TIMELINE_H := 36
const GAP := 2
const POWER_W := 100
const METER_W := 5
const CADENCE_W := 97


static func lane_h(n: int) -> int:
	return FishingConst.PLAY_H / clampi(n, 1, 4)


static func lane_y(i: int, n: int) -> int:
	return FishingConst.DECK_H + i * lane_h(n)


static func lane_rect(i: int, n: int) -> Rect2i:
	return Rect2i(0, lane_y(i, n), FishingConst.PIXEL_W, lane_h(n))


## Row heights {sky, surface, water, reef} for lane height h (sky max(30, 0.28 h), reef
## max(12, 0.14 h), water the rest: 38 px at 4 lanes).
static func rows(h: int) -> Dictionary:
	var sky := maxi(30, roundi(0.28 * h))
	var reef := maxi(12, roundi(0.14 * h))
	return {
		"sky": sky,
		"surface": FishingConst.SURFACE_H,
		"water": h - sky - FishingConst.SURFACE_H - reef,
		"reef": reef
	}


## Top of the surface strip in lane i.
static func surface_y(i: int, n: int) -> int:
	return lane_y(i, n) + int(rows(lane_h(n))["sky"])


## Top of the water rows and their height in lane i.
static func water_y(i: int, n: int) -> int:
	return surface_y(i, n) + FishingConst.SURFACE_H


static func water_h(n: int) -> int:
	return int(rows(lane_h(n))["water"])


## Fish mouth x: 96 + (d / d_max) x (324 - fish width), so the fish stays left of x 420.
static func fish_mouth_x(d: float, d_max: float, fish_w: int) -> int:
	var f := clampf(d / maxf(d_max, 1.0), 0.0, 1.0)
	return FishingConst.FISH_X0 + roundi(f * float(FishingConst.FISH_SPAN - fish_w))


## Hint and lure centre x: 96 + (d / 80 m) x 300.
static func hint_x(d: float) -> int:
	var f := clampf(d / FishingConst.HINT_D_REF, 0.0, 1.0)
	return FishingConst.HINT_X0 + roundi(f * float(FishingConst.HINT_SPAN))


## Fish top y for depth z (0 surface, 1 reef) in lane i, keeping the sprite inside the water.
static func fish_y(z: float, i: int, n: int, fish_h: int) -> int:
	var span := maxi(water_h(n) - fish_h, 0)
	return water_y(i, n) + roundi(clampf(z, 0.0, 1.0) * span)


static func hud_zone(i: int, n: int) -> Rect2i:
	return Rect2i(FishingConst.HUD_X, lane_y(i, n), FishingConst.HUD_W, lane_h(n))


static func panic_rect() -> Rect2i:
	return Rect2i(
		FishingConst.PANIC_X,
		FishingConst.PANIC_Y,
		FishingConst.PIXEL_W - FishingConst.PANIC_X,
		FishingConst.PIXEL_H - FishingConst.PANIC_Y
	)


static func clear_of_panic(r: Rect2i) -> bool:
	return not r.intersects(panic_rect())


static func deck_rect() -> Rect2i:
	return Rect2i(0, 0, FishingConst.PIXEL_W, FishingConst.DECK_H)


## The kit W' bar and gear indicator inside the deck bar.
static func deck_wbal_rect() -> Rect2i:
	return Rect2i(362, 4, 80, 16)


static func deck_gear_rect() -> Rect2i:
	return Rect2i(306, 0, 54, 24)


## The local lane's HUD rects: {"timeline" (Rect2i(), size 0, when left out), "power", "strain",
## "cadence", "slack"}.
static func local_hud(i: int, n: int) -> Dictionary:
	var zone := hud_zone(i, n)
	var timeline := Rect2i(zone.position.x, zone.position.y, FishingConst.HUD_W, TIMELINE_H)
	var row_y := zone.position.y + TIMELINE_H + GAP
	if not clear_of_panic(Rect2i(zone.position.x, row_y, FishingConst.HUD_W, ROW_H)):
		timeline = Rect2i()
		row_y = zone.position.y
	var x := zone.position.x
	var power := Rect2i(x, row_y, POWER_W, ROW_H)
	x += POWER_W + 1
	var strain := Rect2i(x, row_y, METER_W, ROW_H)
	x += METER_W + 1
	var cadence := Rect2i(x, row_y, CADENCE_W, ROW_H)
	x += CADENCE_W + 1
	var slack := Rect2i(x, row_y, METER_W, ROW_H)
	return {
		"timeline": timeline, "power": power, "strain": strain, "cadence": cadence, "slack": slack
	}


## Another lane's compact FishingLaneHud rect (top of its zone, <= 36 px, clear of PANIC).
static func lane_hud(i: int, n: int) -> Rect2i:
	var zone := hud_zone(i, n)
	return Rect2i(zone.position.x, zone.position.y, FishingConst.HUD_W, mini(ROW_H, zone.size.y))


static func toast_rect() -> Rect2i:
	return Rect2i(160, FishingConst.DECK_H + 2, 320, 22)


## Banners (warm-up, rescue) cover the local lane's left two-thirds.
static func banner_rect(i: int, n: int) -> Rect2i:
	return Rect2i(0, lane_y(i, n), FishingConst.HUD_X, lane_h(n))
