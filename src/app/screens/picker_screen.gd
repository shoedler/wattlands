class_name AppPickerScreen
extends AppScreen
## Game picker (BRIEF 3.6, 3.9): one card per valid game from the GameRegistry (picker_image or
## a generated title card, summary, player counts), on pedal-scan. params.mode: "solo" (an
## offline lobby) or "host" (a relay room); the pick opens the lobby for that game.

var mode: String = "solo"
var cards: Dictionary = {}
var game_ids: Array[String] = []
var _grid: GridContainer = null


func _build() -> void:
	mode = str(params.get("mode", "solo"))
	var page := make_page(t("APP_PICKER_TITLE_HOST") if mode == "host" else t("APP_PICKER_TITLE_SOLO"))
	var left: VBoxContainer = page["left"]
	_grid = GridContainer.new()
	_grid.name = "Cards"
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 24)
	_grid.add_theme_constant_override("v_separation", 24)
	left.add_child(_grid)
	var items: Array = []
	var highlight := 0
	var last := str(services.settings.get_value("last_game", "")) if services.settings != null else ""
	var games: Array[Dictionary] = services.registry.games() if services.registry != null else []
	for m: Dictionary in games:
		var id := str(m.get("id", ""))
		if id == "":
			continue
		var card := AppGameCard.make(m)
		_grid.add_child(card)
		cards[id] = card
		if id == last:
			highlight = game_ids.size()
		game_ids.append(id)
		items.append({"id": id, "text": str(m.get("title", id)), "detail": AppLobbyModel.player_count_text(m)})
	if games.is_empty():
		left.add_child(AppStyle.paragraph(t("APP_NO_GAMES"), AppStyle.FONT_HEADING, AppStyle.WARN))
	items.append({"id": "back", "text": t("APP_BACK")})
	var list := push_menu(items, _on_pick, _on_back, highlight if not games.is_empty() else -1)
	list.highlight_changed.connect(_on_highlight)
	_on_highlight(list.highlighted())


func _on_highlight(index: int) -> void:
	for i in game_ids.size():
		(cards[game_ids[i]] as AppGameCard).set_selected(i == index)


func _on_pick(_index: int, id: Variant, _auto: bool) -> void:
	var sid := str(id)
	if sid == "back":
		_on_back()
		return
	goto("lobby", {"mode": mode, "game_id": sid})


func _on_back() -> void:
	goto("title")
