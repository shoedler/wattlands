class_name HudTeammates
extends HudWidget
## Kit widget `teammates` (BRIEF 3.9, 5.5; HudSpec.TEAMMATES): one card per rider from the
## roster (ctx.roster, 2 Hz on every peer), ordered by slot: the slot chip from
## Wl.slot_look (color + shape + pattern, hollow for slots 4-7), raw W, %FTP, in band,
## rescue, AFK, offline, and the latest teammate_status icon (a res:// texture path) and
## text. The strip is roster-driven; what it can't show, games draw in their own Control
## beside it. Options: {"include_local": bool (default true), "vertical": bool (default
## false)}. base_size and min_rect are one card (260 x 124; 170 x 84 at half scale); the strip grows by
## one card per rider.

## The local rider (marked "you").
var local_peer: int = 0
var include_local: bool = true

var _row: BoxContainer = null
var _cards: Dictionary = {}
var _roster: Dictionary = {}


func _init() -> void:
	_ensure_base()
	widget_id = HudSpec.TEAMMATES
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_row = HBoxContainer.new()
	_row.name = "Cards"
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_theme_constant_override("separation", 10)
	_content.add_child(_row)
	set_ui_scale(1.0)


func configure(p_options: Dictionary) -> void:
	super.configure(p_options)
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	include_local = bool(p_options.get("include_local", true))
	if bool(p_options.get("vertical", false)):
		var v := VBoxContainer.new()
		v.name = "Cards"
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_theme_constant_override("separation", 8)
		_content.remove_child(_row)
		_row.free()
		_cards.clear()
		_row = v
		_content.add_child(_row)
	set_roster(_roster)


func base_size() -> Vector2:
	return Vector2(260, 124)


func min_rect() -> Vector2:
	return Vector2(170, 84)


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
	for c in _row.get_children():
		if c is HudTeammateCard:
			out.append((c as HudTeammateCard).peer_id)
	return out


func _on_scale_changed() -> void:
	custom_minimum_size = Vector2.ZERO
	if _row == null:
		return
	for c in _row.get_children():
		if c is HudTeammateCard:
			(c as HudTeammateCard).set_card_scale(ui_scale)


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
			_row.remove_child(old)
			old.free()
			_cards.erase(p)
	for i in order.size():
		var p := order[i]
		var c: HudTeammateCard = _cards.get(p, null)
		if c == null:
			c = HudTeammateCard.new()
			c.name = "Card_%d" % p if p >= 0 else "Card_bot%d" % -p
			c.set_card_scale(ui_scale)
			_row.add_child(c)
			_cards[p] = c
		_row.move_child(c, i)
		c.set_entry(p, _roster[p], p == local_peer)
