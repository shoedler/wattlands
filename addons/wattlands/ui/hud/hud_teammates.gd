class_name HudTeammates
extends HudWidget
## Kit widget `teammates` (BRIEF 3.9, 5.5; HudSpec.TEAMMATES): one card per rider from the
## roster (ctx.roster, 2 Hz on every peer), ordered by slot: the slot chip from
## Wl.slot_look (color + shape + pattern, hollow for slots 4-7), raw W, %FTP, in band,
## rescue, AFK, offline, and the latest teammate_status icon (a res:// texture path) and
## text. The strip is roster-driven; what it can't show, games draw in their own Control
## beside it. Options: {"include_local": bool (default true), "vertical": bool (default
## false)}.
## Size: a card is CARD (260 x 124) at scale 1; base_size() is the whole strip in one row
## (or one column). set_max_width() (HudLayer calls it for the top and bottom anchors, which
## must not run under the corner stacks) wraps the cards into two rows and then scales them
## down, never below MIN_SCALE. min_rect() is one card at MIN_SCALE.
## A Rect2i slot is fitted with set_max_size() instead (HudLayer calls it): one row scaled
## down to fit the slot's width and height, never below MIN_SCALE; only when that would go
## below MIN_SCALE does the strip wrap into two rows (scaled to the width and the height,
## again never below MIN_SCALE; a slot smaller than that overflows).

const CARD := Vector2(260, 124)
const GAP := 10.0
const MIN_SCALE := 0.5

## The local rider (marked "you").
var local_peer: int = 0
var include_local: bool = true
var vertical: bool = false

var _grid: GridContainer = null
var _cards: Dictionary = {}
## What the cards show: the roster with local statuses merged in.
var _roster: Dictionary = {}
## The latest roster as given to set_roster (int keys).
var _raw: Dictionary = {}
## Local teammate_status calls (a client's ctx.hud draws locally, HUD8): peer ->
## {"status": Dictionary, "base": Variant (the roster's own status for that peer when the
## local one was set), "base_known": bool}. A local status wins until the roster's own status
## for that peer changes, so the latest call or roster update shows.
var _local_status: Dictionary = {}
var _max_width: float = INF
var _max_height: float = INF
## True after set_max_size() (a Rect2i slot): prefer one row, scaled to the width and height.
var _slot_fit: bool = false


func _init() -> void:
	_ensure_base()
	widget_id = HudSpec.TEAMMATES
	_panel_visible = false
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_grid = GridContainer.new()
	_grid.name = "Cards"
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.add_theme_constant_override("h_separation", int(GAP))
	_grid.add_theme_constant_override("v_separation", int(GAP))
	_grid.columns = 1
	_content.add_child(_grid)
	set_ui_scale(1.0)


func configure(p_options: Dictionary) -> void:
	super.configure(p_options)
	_panel_visible = false
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	include_local = bool(p_options.get("include_local", true))
	vertical = bool(p_options.get("vertical", false))
	_merge()
	_sync()


func base_size() -> Vector2:
	var n := maxi(1, _cards.size())
	if vertical:
		return Vector2(CARD.x, n * CARD.y + (n - 1) * GAP)
	return Vector2(n * CARD.x + (n - 1) * GAP, CARD.y)


func min_rect() -> Vector2:
	return CARD * MIN_SCALE


## Fit the strip into `w` pixels: one row if it fits, else two rows, scaled down as needed.
func set_max_width(w: float) -> void:
	_max_width = maxf(w, 1.0)
	_max_height = INF
	_slot_fit = false
	_relayout_cards()


## Fit the strip into a Rect2i slot of `avail` pixels (1080p): one row scaled down to fit the
## width and the height, never below MIN_SCALE; if one row would need less than MIN_SCALE, two
## rows scaled to the width and the height, again never below MIN_SCALE.
func set_max_size(avail: Vector2) -> void:
	_max_width = maxf(avail.x, 1.0)
	_max_height = maxf(avail.y, 1.0)
	_slot_fit = true
	_relayout_cards()


## Cards per row now.
func columns() -> int:
	return _grid.columns


## The whole roster ({peer: entry}); cards are added, updated and removed to match. A local
## teammate_status (set_status) stays on its card until the roster's own status for that
## rider changes.
func set_roster(roster: Dictionary) -> void:
	_raw = {}
	for k: Variant in roster.keys():
		var e: Variant = roster[k]
		if e is Dictionary:
			_raw[int(k)] = (e as Dictionary).duplicate(true)
	_merge()
	_sync()


## Merge a teammate_status into one rider's entry (local feed: on a client it draws only
## here, HUD8). It survives later roster updates until the roster's own status for `peer`
## changes.
func set_status(peer: int, status: Dictionary) -> void:
	var known := _raw.has(peer)
	_local_status[peer] = {
		"status": status.duplicate(true),
		"base": _raw_status(peer) if known else null,
		"base_known": known,
	}
	_merge()
	_sync()


## The local teammate_status shown over the roster for `peer` ({} if none).
func local_status(peer: int) -> Dictionary:
	if not _local_status.has(peer):
		return {}
	return ((_local_status[peer] as Dictionary)["status"] as Dictionary).duplicate(true)


## Every local teammate_status still shown over the roster: {peer: status}.
func local_statuses() -> Dictionary:
	var out: Dictionary = {}
	for p: int in _local_status.keys():
		out[p] = local_status(p)
	return out


func roster() -> Dictionary:
	return _roster.duplicate(true)


func card(peer: int) -> HudTeammateCard:
	return _cards.get(peer, null)


## Peers shown, in slot order.
func peers() -> Array[int]:
	var out: Array[int] = []
	for c in _grid.get_children():
		if c is HudTeammateCard:
			out.append((c as HudTeammateCard).peer_id)
	return out


func fit_to(avail: Vector2) -> void:
	set_max_width(avail.x)


func _on_scale_changed() -> void:
	custom_minimum_size = Vector2.ZERO
	if _grid == null:
		return
	for c in _grid.get_children():
		if c is HudTeammateCard:
			(c as HudTeammateCard).set_card_scale(ui_scale)


func _on_palette_changed() -> void:
	if _grid == null:
		return
	for c in _grid.get_children():
		if c is HudTeammateCard:
			(c as HudTeammateCard).set_palette(palette)


func _relayout_cards() -> void:
	var n := maxi(1, _cards.size())
	if vertical:
		_grid.columns = 1
		return
	if _slot_fit:
		_relayout_slot(n)
		return
	var cols := n
	var row_w := n * CARD.x + (n - 1) * GAP
	if row_w > _max_width and n > 1:
		cols = ceili(n / 2.0)
		row_w = cols * CARD.x + (cols - 1) * GAP
	if _grid.columns != cols:
		_grid.columns = cols
	var s := 1.0
	if row_w > _max_width:
		s = maxf(MIN_SCALE, _max_width / row_w)
	set_ui_scale(s)


## Rect2i slot: one row if it fits at MIN_SCALE or more, else two rows.
func _relayout_slot(n: int) -> void:
	var row_w := n * CARD.x + (n - 1) * GAP
	var s := minf(1.0, minf(_max_width / row_w, _max_height / CARD.y))
	var cols := n
	if s < MIN_SCALE and n > 1:
		cols = ceili(n / 2.0)
		var wrap_w := cols * CARD.x + (cols - 1) * GAP
		var wrap_h := 2.0 * CARD.y + GAP
		s = minf(1.0, minf(_max_width / wrap_w, _max_height / wrap_h))
	if _grid.columns != cols:
		_grid.columns = cols
	set_ui_scale(maxf(MIN_SCALE, s))


static func _same(a: Variant, b: Variant) -> bool:
	return typeof(a) == typeof(b) and a == b


func _raw_status(peer: int) -> Variant:
	var e: Variant = _raw.get(peer, null)
	if e is Dictionary:
		return (e as Dictionary).get("status", null)
	return null


## _roster = the latest roster with the local statuses that still apply merged in.
func _merge() -> void:
	_roster = _raw.duplicate(true)
	for p: int in _local_status.keys():
		var o: Dictionary = _local_status[p]
		if _raw.has(p):
			var now: Variant = _raw_status(p)
			if not bool(o["base_known"]):
				o["base"] = now
				o["base_known"] = true
			elif not _same(now, o["base"]):
				_local_status.erase(p)
				continue
		var e: Dictionary = _roster.get(p, {"name": "", "slot_index": 0})
		e["status"] = (o["status"] as Dictionary).duplicate(true)
		_roster[p] = e


func _sync() -> void:
	var order: Array[int] = []
	for p: int in _roster.keys():
		if p == local_peer and not include_local:
			continue
		order.append(p)
	order.sort_custom(
		func(a: int, b: int) -> bool:
			var sa := int((_roster[a] as Dictionary).get("slot_index", 0))
			var sb := int((_roster[b] as Dictionary).get("slot_index", 0))
			return sa < sb if sa != sb else a < b
	)
	for p: int in _cards.keys():
		if not order.has(p):
			var old: HudTeammateCard = _cards[p]
			_grid.remove_child(old)
			old.free()
			_cards.erase(p)
	for i in order.size():
		var p := order[i]
		var c: HudTeammateCard = _cards.get(p, null)
		if c == null:
			c = HudTeammateCard.new()
			c.name = "Card_%d" % p if p >= 0 else "Card_bot%d" % -p
			c.set_card_scale(ui_scale)
			c.set_palette(palette)
			_grid.add_child(c)
			_cards[p] = c
		_grid.move_child(c, i)
		c.set_entry(p, _roster[p], p == local_peer)
	_relayout_cards()
