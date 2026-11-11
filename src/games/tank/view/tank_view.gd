class_name TankView
extends TankViewHud
## The 2D view (docs/games/tank.md v3 and 3): the night forest road at 960 x 540 art px with the one
## v3 tank (the reference's landship rebuilt as pixel art, r6). make_view() returns this Node2D; the
## PixelViewport shows it. It only reads TankGame.state and the cue events; it never writes the state.
##
## Layers, back to front (all under `stage`, offset vertically on taller or shorter canvases and by
## the screen shake): Back (the forest planes at their parallax, the verge, the road band following
## the relief, the near shoulder; TankForest), World (free roam's little bases, the halt line, bushes,
## obstacles, wrecks aging on sim time, the near threats in their two lanes on the relief;
## TankWorldDraw), WorldLight (additive: every world light, behind the tank: the bases' and the halt
## line's lamps, fires, the tank's pools on the road), Tank (the tank: TankBody's sprite drawn
## rotated as a whole onto the terrain, then the main gun's blast and the bow guns' rounds;
## TankFiring), Light (additive: the tank's own lights rotated with the hull: room lamps, the
## headlight, both searchlights, the position lights, the scene flash, shells and flashes;
## TankLightDraw), Front (smoke and the foreground plane), Post (the tilt-shift shading); then the
## per-frame depth of field (TankDof) over the near panel.
##
## The split screen (v4, SPEC_TANK section 4; TankFarMap holds the rects): the near panel on the left,
## a riveted seam (TankSeam) with the target's range, the far panel on the right (TankFarPanel, a
## SubViewport with its own night forest, drawn opaque over the near stage), with the shell screen
## (TankPip) in its top. Far enemies, the Behemoth and a stage's little base live there; near threats,
## obstacles and drill wrecks on the near stage, in rules px, 0..NEAR_SPAN_PX past the nose mapped onto
## the road up to the seam (sx). A far shell crosses all three (TankShellPath).
##
## Tank lost (SPEC_TANK 4.7): a boom and a short dim, then while hull.tow_s runs the tank creeps back with
## its tracks reversed under heavy smoke and the far panel goes black (its veil); stage_restart forgets
## the history and fades up from black.
##
## The tank (TankBody, a SubViewport): the base art with the rooms painted live (TankInterior: each
## seat's machine turning on its rider's crank, a rider on each manned seat, a bare saddle and a
## still crank on an empty one; the ready rack and the breech in their turret windows; both
## bow-gun receivers), the track and the road wheels on per-wheel suspension (TankSuspension) over
## the relief (TankGround: the rules' terrain plus seeded bumps), the hull fitted to the contacts
## and bobbing on its springs, the main gun at its elevation with the r6 recoil, the bow guns
## tilting toward their target. Firing (TankFiring): the blast, the recoil, the hull's rock, the
## jolt, the scene flash and the screen shake (the stage's offset, never Engine time).
##
## Scale: the rules' 640 x 360 units x 1.5 (sx/sy). The hull's rules span maps onto the art hull
## and the ground ahead onto the near panel's road (near_k); a wider canvas (pixel_flex) stretches that
## up to the art's own scale and shows more road past it, a narrower one squeezes it.
##
## Time: positions come from a snapshot history (TankSnapHistory) drawn at a SnapRenderClock's render_t.
## Machines turn by their rider's cadence integrated over render time; cosmetic randomness comes
## from TankFx.rng and TankGround's phases, seeded from ctx.seed.
##
## Free roam: the planes scroll with the hull's place on the valley road (plane_x); while the tank
## drives west the World, WorldLight, Tank, Light and Front layers are drawn mirrored; a turn hides
## the flip behind a dust cloud; a turning place stands at each end of the road.
##
## Hooks: play_evade(kind), fire(kind) (a shot's effects; the `shot` cue calls it), power_ratio(),
## set_canvas_size() (tests), and the HUD's geometry (hud_*), found through the game's meta
## TankHudGeom.VIEW_META, which the view sets.
##
## The code: TankViewBase, TankViewMotion, TankViewSeats, TankViewWorld and TankViewHud are the layers of a chain
## under this class, each calling only down. This class holds the frame order, the build and the draw layers.


func _ready() -> void:
	audio = TankAudio.new()
	audio.game = game
	add_child(audio)
	if game != null:
		game.cue.connect(audio.on_cue)
		game.cue.connect(_on_cue)
		game.snapshot_applied.connect(_on_snapshot_applied)
	_build()


func _process(delta: float) -> void:
	if auto_process:
		advance(delta)


# --- Build ---------------------------------------------------------------------------------------------


func _build() -> void:
	if _built or game == null or game.state == null:
		return
	_built = true
	rig = TankRig.shared()
	var ctx := game.ctx
	var sd := ctx.seed if ctx != null else 1
	fx.seed_rng(sd)
	dust_fx.seed_rng(sd + 2)
	ground = TankGround.new(sd)
	ground.base_y = GROUND
	if ctx != null:
		clock.min_delay_s = (
			SnapRenderClock.CLIENT_DELAY_S
			if ctx.role == Wl.CLIENT
			else SnapRenderClock.HOST_DELAY_S
		)
	interior = TankInterior.new(rig)
	body = TankBody.new(rig)
	body.interior = interior.tex
	add_child(body)
	stage = Node2D.new()
	stage.name = "Stage"
	add_child(stage)
	for n: String in ["Back", "World", "WorldLight", "Tank", "Light", "Front", "Post"]:
		var l := Node2D.new()
		l.name = n
		l.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if n == "Light" or n == "WorldLight":
			var m := CanvasItemMaterial.new()
			m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			l.material = m
			l.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		if n == "Back":
			l.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		stage.add_child(l)
		_layers[n] = l
	(_layers["Back"] as Node2D).draw.connect(_draw_back)
	(_layers["World"] as Node2D).draw.connect(_draw_world)
	(_layers["WorldLight"] as Node2D).draw.connect(_draw_world_light)
	(_layers["Tank"] as Node2D).draw.connect(_draw_tank)
	(_layers["Light"] as Node2D).draw.connect(_draw_light)
	(_layers["Front"] as Node2D).draw.connect(_draw_front)
	(_layers["Post"] as Node2D).draw.connect(_draw_post)
	dof = TankDof.new()
	dof.enabled = miniature_option()
	add_child(dof)
	_build_panels(sd)
	game.set_meta(TankHudGeom.VIEW_META, self)


## The far panel's SubViewport and, over the near stage in this order, its sprite, the seam and the PiP.
func _build_panels(sd: int) -> void:
	if game.state.content != null:
		_far_v0 = game.state.content.num("tanks", "gun.far.v0_mps", _far_v0)
		_far_g = game.state.content.num("tanks", "gun.far.g_mps2", _far_g)
	far = TankFarPanel.new(self, sd)
	add_child(far)
	_far_sprite = Node2D.new()
	_far_sprite.name = "FarSprite"
	_far_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_far_sprite.draw.connect(_draw_far)
	add_child(_far_sprite)
	seam = TankSeam.new(self)
	add_child(seam)
	pip = TankPip.new(self)
	add_child(pip)


func _exit_tree() -> void:
	if (
		game != null
		and game.has_meta(TankHudGeom.VIEW_META)
		and game.get_meta(TankHudGeom.VIEW_META) == self
	):
		game.remove_meta(TankHudGeom.VIEW_META)


## The local rider's `miniature` player option (default on).
func miniature_option() -> bool:
	if game == null or game.ctx == null:
		return true
	var me := game.ctx.local_player()
	if me == null:
		return true
	return bool(me.options.get("miniature", true))


func set_miniature(on: bool) -> void:
	if dof != null:
		dof.enabled = on


func set_canvas_size(size: Vector2) -> void:
	canvas_override = size


func layer(n: String) -> Node2D:
	return _layers.get(n, null)


# --- Frame ---------------------------------------------------------------------------------------------


## One frame of `delta` seconds: history and render clock, layout, the relief, seats and machines,
## cues, the tank's pose, effects, the layers' redraw and the audio.
func advance(delta: float) -> void:
	if game == null or game.state == null:
		return
	_build()
	if not _built:
		return
	var state := game.state
	frames += 1
	dt = minf(delta, 0.1)
	time += dt
	_poll_history(state)
	clock.advance(delta, history)
	var rt := clock.render_t
	var render_dt := 0.0
	if _last_render_t >= 0.0 and clock.is_set():
		render_dt = clampf(rt - _last_render_t, 0.0, 0.25)
	_last_render_t = rt
	var sim_adv := 0.0
	if _last_sim_t >= 0.0:
		sim_adv = maxf(state.t - _last_sim_t, 0.0)
	_last_sim_t = state.t
	if dof != null:
		dof.note_frame(delta, sim_adv)
	_layout()
	hull_x = history.hull_x_at(rt, state.hull.x_px) if clock.is_set() else state.hull.x_px
	cam_x = hull_x - float(TankConst.REAR_SCREEN_X)
	_roam_frame(state)
	_panels_frame()
	var cam_px := cam_x * S
	scroll_px = cam_px - _prev_cam_px if _cam_primed else 0.0
	if absf(scroll_px) > 200.0:
		scroll_px = 0.0
	_prev_cam_px = cam_px
	_cam_primed = true
	travel += state.hull.speed_mps * TankConst.PX_PER_M * S * render_dt
	_tow_frame(state, dt)
	hangar_look = TankHangar.look(self, state)
	_relief(state)
	var feed := rider_feed(state, rt)
	# render_t stalls at the newest snapshot then catches up (SnapRenderClock): on a client that
	# would make the strokes lurch, so a client's machines run on the frame's dt.
	var phase_dt := dt if game.ctx != null and game.ctx.role == Wl.CLIENT else render_dt
	_seats(state, feed, phase_dt)
	_search(state, dt)
	_process_cues(state)
	_feed_rounds(state)
	firing.step(dt, scroll_px)
	_track_enemies(state)
	_far_frame(state, dt)
	_bow_aim(dt)
	_pose(dt)
	_paint(state)
	_age_wrecks(state)
	_emit(state, feed, dt)
	fx.step(dt, scroll_px)
	dust_fx.step(dt, scroll_px)
	_shake_frame()
	if dof != null:
		dof.update(canvas, BAND + Vector2(y_off, y_off), panels["near"])
	body.refresh()
	for l: Node2D in _layers.values():
		l.queue_redraw()
	for n: Node2D in [_far_sprite, seam, pip]:
		n.queue_redraw()
	if audio != null:
		audio.update(
			state,
			delta,
			game.ctx.local_peer if game.ctx != null else 0,
			audio_feed(state),
			travel / (TankConst.PX_PER_M * S),
			not far.rects.is_empty() or far.boss_box.has_area()
		)


func _layout() -> void:
	canvas = canvas_size()
	y_off = roundf((canvas.y - BASE.y) * 0.5)
	tank_pos = Vector2(TANK_AT.x + maxf(canvas.x - BASE.x, 0.0) * WIDE_SHIFT, TANK_AT.y)


## The split screen on this frame's canvas (mirrored going west: far on the left).
func _panels_frame() -> void:
	panels = TankFarMap.panels(canvas, mirrored)
	far.layout(canvas, mirrored, y_off)
	seam.rect = Rect2(panels["seam"])
	pip.rect = Rect2(panels["pip"])
	pip.position = pip.rect.position


## The far panel's frame, and its enemies' and the Behemoth's rects on the canvas.
func _far_frame(state: TankState, step_dt: float) -> void:
	far.frame(state, step_dt)
	pip.frame(state, step_dt)
	far.age_wrecks(state.t)
	far_rects.clear()
	for id: int in far.rects:
		far_rects[id] = far.canvas_rect(far.rects[id], far_panel_x())


## The canvas the view draws on (art px): the override, else the PixelViewport's SubViewport.
func canvas_size() -> Vector2:
	if canvas_override != Vector2.ZERO:
		return canvas_override
	var vp := get_viewport() if is_inside_tree() else null
	if vp is SubViewport:
		return Vector2((vp as SubViewport).size)
	return BASE


## The stage's offset: the canvas' vertical offset plus the shot's screen shake (a camera offset).
func _shake_frame() -> void:
	shake_px = Vector2(firing.screen_shake())
	if stage != null:
		stage.position = Vector2(0, y_off) + shake_px


# --- Layers ---------------------------------------------------------------------------------------------


func _draw_back() -> void:
	if _built and game.state != null:
		TankForest.draw_back(layer("Back"), self)


func _draw_world() -> void:
	if _built and game.state != null:
		TankWorldDraw.draw_world(layer("World"), self, game.state)


func _draw_world_light() -> void:
	if _built and game.state != null:
		TankLightDraw.draw_world(layer("WorldLight"), self, game.state)


## The near threats, over the world's lights; the tank: its sprite (TankBody) rotated as a whole, nearest; the turn's
## dust; the blast and the bow guns' rounds.
func _draw_tank() -> void:
	if not _built or game.state == null:
		return
	var ci := layer("Tank")
	dust_fx.draw_smoke(ci)
	fx.draw_smoke(ci, true)
	fx.draw_leaves(ci)
	TankWorldDraw.draw_near_threats(ci, self, game.state)
	ci.draw_set_transform_matrix(xf)
	ci.draw_texture(body.get_texture(), -Vector2(TankBody.PAD, TankBody.PAD))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	TankWorldDraw.draw_turn_dust(ci, self, game.state)
	firing.draw(ci, self)


## The far panel's picture over the near stage, opaque.
func _draw_far() -> void:
	if _built and far != null and not panels.is_empty():
		_far_sprite.draw_texture(far.get_texture(), (panels["far"] as Rect2).position)


func _draw_light() -> void:
	if _built and game.state != null:
		TankLightDraw.draw(layer("Light"), self, game.state)


func _draw_front() -> void:
	if not _built or game.state == null:
		return
	var ci := layer("Front")
	fx.draw_solid(ci)
	fx.draw_smoke(ci)
	if mirrored:
		ci.draw_set_transform(Vector2(canvas.x, 0), 0.0, Vector2(-1, 1))
	TankForest.draw_front(ci, self)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Tilt-shift shading: the top and the bottom of the frame darkened (the planes carry the blur).
func _draw_post() -> void:
	if not _built:
		return
	var ci := layer("Post")
	var w := canvas.x
	var top := -y_off - 4.0
	var clear := Color(0, 0, 0, 0)
	var t1 := Color(0, 0, 0, 0.16)
	ci.draw_polygon(
		PackedVector2Array([Vector2(0, top), Vector2(w, top), Vector2(w, 215), Vector2(0, 215)]),
		PackedColorArray([t1, t1, clear, clear])
	)
	var b1 := Color(0, 0, 0, 0.45)
	var bottom := canvas.y - y_off + 4.0
	ci.draw_polygon(
		PackedVector2Array(
			[Vector2(0, 445), Vector2(w, 445), Vector2(w, bottom), Vector2(0, bottom)]
		),
		PackedColorArray([clear, clear, b1, b1])
	)
	var black := maxf(TOW_DIM_ALPHA * tow_dim_s / TOW_DIM_S, restart_fade_s / RESTART_FADE_S)
	if black > 0.0:
		ci.draw_rect(Rect2(0, top, w, bottom - top), Color(0, 0, 0, black))
