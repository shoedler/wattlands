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

const CARD := Vector2(260, 124)
const GAP := 10.0
const MIN_SCALE := 0.5

## The local rider (marked "you").
var local_peer: int = 0
var include_local: bool = true
var vertical: bool = false

var _grid: GridContainer = null
var _cards: Dictionary = {}
var _roster: Dictionary = {}
var _max_width: float = INF


func _init() -> void:
	_ensure_base()
	widget_id = HudSpec.TEAMMATES
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
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	include_local = bool(p_options.get("include_local", true))
	vertical = bool(p_options.get("vertical", false))
	set_roster(_roster)


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
	_relayout_cards()


## Cards per row now.
func columns() -> int:
	return _grid.columns


## The whole roster ({peer: entry}); cards are added, updated and removed to match.
func set_roster(roster: Dictionary) -> void:
	_roster = {}
	for k: Variant in roster.keys():
		var e: Variant = roster[k]
		if e is Dictionary:
			_roster[int(k)] = (e as Dictionary).duplicate(true)
	_sync()


## Merge a teammate_status into one rider's entry (local feed).
func set_status(peer: int, status: Dictionary) -> void:
	var e: Dictionary = _roster.get(peer, {"name": "", "slot_index": 0})
	e["status"] = status.duplicate(true)
	_roster[peer] = e
	_sync()


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


func _relayout_cards() -> void:
	var n := maxi(1, _cards.size())
	if vertical:
		_grid.columns = 1
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


func _sync() -> void:
	var order: Array[int] = []
	for p: int in _roster.keys():
		if p == local_peer and not include_local:
			continue
		order.append(p)
	order.sort_custom(func(a: int, b: int) -> bool:
		var sa := int((_roster[a] as Dictionary).get("slot_index", 0))
		var sb := int((_roster[b] as Dictionary).get("slot_index", 0))
		return sa < sb if sa != sb else a < b)
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
			_grid.add_child(c)
			_cards[p] = c
		_grid.move_child(c, i)
		c.set_entry(p, _roster[p], p == local_peer)
	_relayout_cards()
