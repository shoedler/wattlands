class_name SiegeShopPanel
extends Control
## The break shop (docs/games/siege.md 2.4 "Shop", 3 HUD): a PedalScanList with text of at least
## 32 px. The top entry is Autopilot's pick for the rider, the second "Save gold", then what else
## they could buy (SiegeShopModel). It follows the local trainer mode, so in an ERG break a rider
## with pedal navigation on (PlayerSlot.pedal_nav) who only pedals gets the top entry
## auto-confirmed after two scan cycles; that pick goes out tagged "auto" and never ends the
## rider's zero-input shop fallback. A pick sends SiegeIntents.buy(item, at, via == "auto")
## through ctx.intents. Visible only while the shop is open (every break, the build break too).
## The root is a transparent Control so a Rect2i slot can stretch it; the card keeps its height.

const ITEM_PX := 32
const REFRESH_EVERY_S := 0.25

var game: SiegeGame = null
var card: PanelContainer = null
var title_label: Label = null
var countdown_label: Label = null
var list: PedalScanList = null
## Tests set this to stand in for SiegeAutopilot.shop_picks (an Array of normalized buys).
var picks_override: Variant = null
var signature: String = ""
var entries: Array[Dictionary] = []
var _since: float = REFRESH_EVERY_S


func _init() -> void:
	name = "SiegeShopPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = WlTheme.get_theme()
	card = PanelContainer.new()
	card.name = "Card"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := WlTheme.panel_style()
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	card.add_theme_stylebox_override("panel", style)
	card.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	card.grow_vertical = Control.GROW_DIRECTION_END
	add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	# the gold shows in the readout above; the title stays for tests and screen readers, hidden
	title_label = SiegeHudPanel.make_label(WlTheme.BODY_PX, WlTheme.TEXT, true)
	title_label.visible = false
	box.add_child(title_label)
	countdown_label = SiegeHudPanel.make_label(WlTheme.LABEL_PX, WlTheme.WARN, true)
	box.add_child(countdown_label)
	list = PedalScanList.new()
	list.name = "Items"
	list.item_font_px = ITEM_PX
	list.add_theme_constant_override("separation", 0)
	list.follow_local_mode = true
	list.erg_auto_confirm = true
	list.item_picked.connect(_on_item_picked)
	box.add_child(list)
	visible = false


func _process(delta: float) -> void:
	_since += delta
	refresh()


## Visible while the shop is open for the local rider; refreshes the entries a few times a
## second and rebuilds the list only when they changed (set_items restarts the scan).
func refresh() -> void:
	var s := game.state if game != null else null
	var r := SiegeHudModel.own_rider(game)
	if s == null or r == null or not s.shop_open():
		visible = false
		return
	visible = true
	var me := game.ctx.local_player() if game.ctx != null else null
	list.pedal_nav = me != null and me.pedal_nav
	# the scan hint (with the ERG auto-pick countdown) is for pedal navigation; it wraps inside
	# the shop's rect instead of widening it
	list.show_hint = list.pedal_nav
	_style_hint()
	var tx := SiegeHudModel.strings_of(game)
	title_label.text = (
		"%s   %s %d" % [tx.t("SIEGE_SHOP_TITLE"), tx.t("SIEGE_HUD_GOLD"), floori(r.gold)]
	)
	var left := _autobuy_in_s(s, r)
	countdown_label.visible = left > 0.0
	if left > 0.0:
		countdown_label.text = tx.t("SIEGE_SHOP_COUNTDOWN", [ceili(left)])
	if _since >= REFRESH_EVERY_S or entries.is_empty():
		_since = 0.0
		rebuild(tx, r)


func _style_hint() -> void:
	var hint := list.get_node_or_null("Hint") as Label
	if hint == null or hint.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART:
		return
	hint.label_settings = WlTheme.label_settings(WlTheme.SMALL_PX - 2, WlTheme.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(10, 0)


## Seconds until Autopilot buys for a rider still on the zero-input shop fallback (0: never).
func _autobuy_in_s(s: SiegeState, r: SiegeRiderState) -> float:
	if not SiegeShop.autopiloted(r) or s.content == null:
		return 0.0
	var at: Variant = (s.content.balance.get("autopilot", {}) as Dictionary).get("shop_at_s", [])
	var first := float((at as Array)[0]) if at is Array and not (at as Array).is_empty() else 0.0
	return maxf(first - s.phase_elapsed_s, 0.0)


## Recomputes the entries and rebuilds the list when they changed.
func rebuild(tx: GameStrings, r: SiegeRiderState) -> void:
	var s := game.state
	var picks: Array[Dictionary] = []
	if picks_override is Array:
		picks.assign(picks_override)
	else:
		picks = SiegeAutopilot.shop_picks(s, r, 1)
	entries = SiegeShopModel.entries(s, r, tx, picks)
	var sig := SiegeShopModel.signature(entries)
	if sig == signature:
		return
	signature = sig
	var items: Array = []
	for e in entries:
		items.append(
			{
				"id": e["id"],
				"text": e["text"],
				"detail": e["detail"],
				"disabled": bool(e["disabled"])
			}
		)
	list.set_items(items)


func _on_item_picked(_index: int, id: Variant, via: String) -> void:
	if not (id is Dictionary):
		return
	var item := str((id as Dictionary).get("item", ""))
	if item == SiegeIds.ITEM_SAVE or item == "":
		return
	var at := int((id as Dictionary).get("at", 0))
	if game != null and game.ctx != null and game.ctx.intents != null:
		game.ctx.intents.send(SiegeIntents.buy(item, at, via == "auto"))
