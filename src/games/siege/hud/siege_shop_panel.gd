class_name SiegeShopPanel
extends Control
## The break shop (brief 2.4 "Shop", 3 HUD): a PedalScanList with text of at least 32 px. The top
## entry is the Autopilot's recommendation (SiegeAutopilot.shop_picks), the second is "Save
## denarii", then what else the rider could buy. It follows the local trainer mode, so in an ERG
## break (every break is) a rider who only pedals gets the top entry auto-confirmed after two scan
## cycles; that pick goes out tagged "auto" and never ends the rider's zero-input shop fallback.
## A pick sends SiegeIntents.buy(item, pad, via == "auto") through ctx.intents. Visible only while
## the shop is open (every break, the build break included).
##
## The root is a transparent Control so a Rect2i slot can stretch it; the card inside keeps its
## own height.

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
	card.add_theme_stylebox_override("panel", WlTheme.panel_style())
	card.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	card.grow_vertical = Control.GROW_DIRECTION_END
	add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	title_label = SiegeHudPanel.make_label(WlTheme.MENU_PX, WlTheme.TEXT, true)
	box.add_child(title_label)
	countdown_label = SiegeHudPanel.make_label(WlTheme.BODY_PX, WlTheme.WARN, true)
	box.add_child(countdown_label)
	list = PedalScanList.new()
	list.name = "Items"
	list.item_font_px = ITEM_PX
	list.add_theme_constant_override("separation", 6)
	list.follow_local_mode = true
	list.erg_auto_confirm = true
	list.item_picked.connect(_on_item_picked)
	box.add_child(list)
	visible = false


func _process(delta: float) -> void:
	_since += delta
	refresh()


## Visible while the shop is open for the local rider; refreshes the entries a few times a
## second, rebuilding the list only when its content changed (set_items restarts the scan).
func refresh() -> void:
	var s := game.state if game != null else null
	var r := SiegeHudModel.own_rider(game)
	if s == null or r == null or not s.shop_open():
		visible = false
		return
	visible = true
	var tx := SiegeHudModel.strings_of(game)
	title_label.text = tx.t("SIEGE_SHOP_TITLE", [floori(r.denarii)])
	var left := SiegeHudModel.phase_remaining_s(game)
	var window := s.content.num("shop.countdown_s", 10.0) if s.content != null else 10.0
	var closing := left > 0.0 and left <= window
	countdown_label.visible = closing
	if closing:
		countdown_label.text = tx.t("SIEGE_SHOP_COUNTDOWN", [ceili(left)])
	if _since >= REFRESH_EVERY_S or entries.is_empty():
		_since = 0.0
		rebuild(tx, r)


## Recomputes the entries and rebuilds the list when they changed.
func rebuild(tx: GameStrings, r: SiegeRiderState) -> void:
	var s := game.state
	var picks: Array[Dictionary] = []
	if picks_override is Array:
		picks.assign(picks_override)
	else:
		picks = SiegeAutopilot.shop_picks(s, r, 2)
	entries = SiegeShopModel.entries(s, r, tx, picks)
	var sig := SiegeShopModel.signature(entries)
	if sig == signature:
		return
	signature = sig
	var items: Array = []
	for e in entries:
		(
			items
			. append(
				{
					"id": e["id"],
					"text": e["text"],
					"detail": e["detail"],
					"disabled": bool(e["disabled"]),
				}
			)
		)
	list.set_items(items)


func _on_item_picked(_index: int, id: Variant, via: String) -> void:
	if not (id is Dictionary):
		return
	var item := str((id as Dictionary).get("item", ""))
	if item == SiegeIds.ITEM_SAVE or item == "":
		return
	var pad := int((id as Dictionary).get("pad", 0))
	if game != null and game.ctx != null and game.ctx.intents != null:
		game.ctx.intents.send(SiegeIntents.buy(item, pad, via == "auto"))
