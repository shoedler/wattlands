class_name AppLobbyCard
extends PanelContainer
## One rider's card in the lobby (BRIEF 3.6): slot look chip, name (bots "Bot n"), FTP, ready
## state, trainer status and their player_options values. The local rider's card is marked and
## edited through the lobby menu ("My <option>" entries).

var peer_id: int = 0
var is_local: bool = false
var name_label: Label = null
var detail_label: Label = null
var ready_label: Label = null
var trainer_label: Label = null
var options_label: Label = null


static func make(slot: PlayerSlot, local: bool) -> AppLobbyCard:
	var c := AppLobbyCard.new()
	c._build(slot, local)
	return c


func _build(slot: PlayerSlot, local: bool) -> void:
	peer_id = slot.peer_id
	is_local = local
	name = "Card_%d" % slot.peer_id
	var sb := StyleBoxFlat.new()
	sb.bg_color = AppStyle.PANEL_HI if local else AppStyle.PANEL
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(14)
	add_theme_stylebox_override("panel", sb)
	var row := AppStyle.hbox(20)
	add_child(row)
	row.add_child(AppSlotChip.for_slot(slot.slot_index, 64.0))
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(520, 0)
	var col := AppStyle.vbox(4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var title := slot.name
	if local:
		title = AppScreen.t("APP_LOBBY_YOU").format([slot.name])
	name_label = AppStyle.label(title, AppStyle.FONT_BODY)
	col.add_child(name_label)
	detail_label = AppStyle.label("", AppStyle.FONT_SMALL, AppStyle.TEXT_DIM)
	col.add_child(detail_label)
	options_label = AppStyle.label("", AppStyle.FONT_SMALL, AppStyle.TEXT_DIM)
	col.add_child(options_label)
	var right := AppStyle.vbox(4)
	row.add_child(right)
	ready_label = AppStyle.label("", AppStyle.FONT_BODY)
	right.add_child(ready_label)
	trainer_label = AppStyle.label("", AppStyle.FONT_SMALL, AppStyle.TEXT_DIM)
	right.add_child(trainer_label)
	var ftp_text := "%d W" % int(round(slot.ftp))
	if slot.is_bot:
		detail_label.text = AppScreen.t("APP_LOBBY_BOT_DETAIL").format([ftp_text])
	else:
		var verified := "" if slot.ftp_verified else AppScreen.t("APP_UNVERIFIED")
		detail_label.text = ("FTP %s %s" % [ftp_text, verified]).strip_edges()


## ready: shown as Ready / Not ready (bots are always ready); trainer: TrainerDevice status.
func update(ready: bool, trainer: String, options_text: String, is_bot: bool) -> void:
	if is_bot:
		ready_label.text = AppScreen.t("APP_LOBBY_READY")
		ready_label.add_theme_color_override("font_color", AppStyle.GOOD)
		trainer_label.text = AppScreen.t("APP_LOBBY_BOT_TRAINER")
	else:
		ready_label.text = AppScreen.t("APP_LOBBY_READY") if ready else AppScreen.t("APP_LOBBY_NOT_READY")
		ready_label.add_theme_color_override("font_color", AppStyle.GOOD if ready else AppStyle.WARN)
		trainer_label.text = AppScreen.t("APP_TITLE_TRAINER").format([trainer_text(trainer)])
	options_label.text = options_text
	options_label.visible = options_text != ""


static func trainer_text(status: String) -> String:
	match status:
		TrainerDevice.STATUS_READY, TrainerDevice.STATUS_CONNECTED:
			return AppScreen.t("APP_TRAINER_OK")
		TrainerDevice.STATUS_SCANNING, TrainerDevice.STATUS_CONNECTING:
			return AppScreen.t("APP_TRAINER_CONNECTING")
		TrainerDevice.STATUS_CONTROL_LOST:
			return AppScreen.t("APP_TRAINER_CONTROL_LOST")
		TrainerDevice.STATUS_ERROR:
			return AppScreen.t("APP_TRAINER_ERROR")
		"":
			return AppScreen.t("APP_TRAINER_UNKNOWN")
	return AppScreen.t("APP_TRAINER_NONE")
