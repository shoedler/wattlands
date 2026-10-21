class_name AppGameCard
extends PanelContainer
## One game in the picker (BRIEF 3.6): its picker_image (a 16:9 card) or, when the game has
## none or the file is missing or unreadable, a generated title card; plus title, summary and
## player counts. A missing image never hides the game (the registry logs the warning).

const IMAGE_SIZE := Vector2(400, 225)

var game_id: String = ""
var image: TextureRect = null
var generated: Control = null
var title_label: Label = null
var summary_label: Label = null
var players_label: Label = null
var _style: StyleBoxFlat = null


static func make(manifest: Dictionary) -> AppGameCard:
	var c := AppGameCard.new()
	c._build(manifest)
	return c


func _build(manifest: Dictionary) -> void:
	game_id = str(manifest.get("id", ""))
	name = "Card_" + game_id
	_style = StyleBoxFlat.new()
	_style.bg_color = AppStyle.PANEL
	_style.set_corner_radius_all(14)
	_style.set_content_margin_all(16)
	_style.border_color = AppStyle.ACCENT
	add_theme_stylebox_override("panel", _style)
	var box := AppStyle.vbox(10)
	add_child(box)
	var tex := load_picker_image(str(manifest.get("picker_image", "")))
	if tex != null:
		image = TextureRect.new()
		image.name = "PickerImage"
		image.texture = tex
		image.custom_minimum_size = IMAGE_SIZE
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		box.add_child(image)
	else:
		generated = make_title_card(str(manifest.get("title", game_id)), game_id)
		box.add_child(generated)
	title_label = AppStyle.label(str(manifest.get("title", game_id)), AppStyle.FONT_HEADING)
	box.add_child(title_label)
	summary_label = AppStyle.paragraph(str(manifest.get("summary", "")), AppStyle.FONT_SMALL)
	summary_label.custom_minimum_size = Vector2(IMAGE_SIZE.x, 0)
	box.add_child(summary_label)
	players_label = AppStyle.label(AppLobbyModel.player_count_text(manifest), AppStyle.FONT_BODY, AppStyle.ACCENT)
	box.add_child(players_label)


## The picker image, or null when the path is empty, missing or not a texture.
static func load_picker_image(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	var res: Resource = ResourceLoader.load(path)
	return res as Texture2D if res is Texture2D else null


## A generated 16:9 title card: the game's colour and its title in large letters.
static func make_title_card(title: String, id: String) -> Control:
	var card := ColorRect.new()
	card.name = "GeneratedCard"
	card.color = AppStyle.color_for_id(id)
	card.custom_minimum_size = IMAGE_SIZE
	var l := AppStyle.label(title.to_upper(), AppStyle.FONT_HEADING, Color.WHITE)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(l)
	return card


func set_selected(on: bool) -> void:
	_style.border_width_left = 6 if on else 0
	_style.border_width_right = 6 if on else 0
	_style.border_width_top = 6 if on else 0
	_style.border_width_bottom = 6 if on else 0
	_style.bg_color = AppStyle.PANEL_HI if on else AppStyle.PANEL
