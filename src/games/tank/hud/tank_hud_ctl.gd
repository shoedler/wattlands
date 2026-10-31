class_name TankHudCtl
extends HudArtControl
## Base of Torque Company's own HUD Controls (brief 3.6; the way Turbo Reel's FishingHudControl
## works). Each sits alone in a Rect2i of the HudSpec (`art_rect`, art px of the 960 x 540 base,
## TankHud.LAYOUT); the HudLayer anchors that rect on the current art canvas
## (PixelViewport.anchor_art_rect) and sizes the Control to it on screen. It draws in art px under
## a scale transform (u() screen px per art px, 2 at 1080p) with nearest filtering, so everything
## lands on the art grid. It ignores the mouse, refreshes every frame, gets the local rider's
## telemetry from the HudLayer (set_telemetry) and reads everything else from TankGame.state. It
## only reads the state.

const D := preload("res://src/games/tank/hud/tank_hud_draw.gd")

var game: TankGame = null


## Sets the game and the rect the spec places the Control in, names it after its class.
func setup(p_game: TankGame, rect: Rect2i) -> TankHudCtl:
	game = p_game
	place_at(rect)
	return self


func has_state() -> bool:
	return game != null and game.state != null


func st() -> TankState:
	return game.state


func local_peer() -> int:
	return game.ctx.local_peer if game != null and game.ctx != null else 0


## The local rider (the first rider when the local peer has none, e.g. a spectator).
func local_rider() -> TankRiderState:
	var r := st().rider(local_peer())
	if r == null and not st().riders.is_empty():
		r = st().riders[0]
	return r


## The art canvas the HUD lays out on (the HudLayer's flex size; the 960 x 540 base without one).
func canvas() -> Vector2i:
	return canvas_or(TankHud.BASE)


## Where this Control's rect sits on the canvas (anchored like the HUD does).
func canvas_rect() -> Rect2i:
	return TankHud.anchored(art_rect, canvas())


## `key` translated, `{0}`.. filled from `args`.
func tx(key: String, args: Array = []) -> String:
	return TankHud.tx(game, key, args)


func rider_name(r: TankRiderState) -> String:
	if game != null and game.ctx != null:
		var p := game.ctx.player(r.peer)
		if p != null and p.name != "":
			return p.name
	return "Rider %d" % (r.slot + 1)


static func slot_color(slot: int) -> Color:
	return Wl.SLOT_COLORS[posmod(slot, Wl.SLOT_COLORS.size())]
