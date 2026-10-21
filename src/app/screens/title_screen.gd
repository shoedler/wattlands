class_name AppTitleScreen
extends AppScreen
## Title and main menu (BRIEF 3.5 zero-touch start, 3.9).
##   - With a saved profile: holding pedal_start for 5 s starts the last-played game solo with
##     its zero_input_content (the first-run game when nothing was played yet).
##   - First run with no input: 20 s of pedaling creates the profile "Rider" (FTP 200,
##     unverified) and starts GameRegistry.first_run_game() solo with its zero_input_content.
## While that countdown is armed the menu holds its first item, the same quick ride, so a surge
## also starts it. A keyboard or controller action, or a coast after pedaling, disarms the
## countdown for this visit; the menu then scans (pedal-scan with a saved profile) so a
## pedal-only rider can still host, join or open settings.

var zero: AppZeroTouch = AppZeroTouch.new()
var quick_game: String = ""
var quick_content: String = ""
var has_profile: bool = false
var started: bool = false
var hint_label: Label = null
var progress_bar: ProgressBar = null
var trainer_label: Label = null
var profile_label: Label = null
var _device: TrainerDevice = null


func _build() -> void:
	has_profile = services.settings != null and services.settings.has_profile()
	var page := make_page("")
	var title: Label = page["title"]
	title.text = t("APP_TITLE")
	title.add_theme_font_size_override("font_size", AppStyle.FONT_TITLE)
	title.add_theme_color_override("font_color", AppStyle.ACCENT)
	var left: VBoxContainer = page["left"]
	left.add_child(AppStyle.label(t("APP_TAGLINE"), AppStyle.FONT_HEADING, AppStyle.TEXT_DIM))
	profile_label = AppStyle.label("", AppStyle.FONT_BODY)
	profile_label.name = "ProfileLine"
	left.add_child(profile_label)
	trainer_label = AppStyle.label("", AppStyle.FONT_BODY)
	trainer_label.name = "TrainerLine"
	left.add_child(trainer_label)
	hint_label = AppStyle.paragraph("", AppStyle.FONT_HEADING, AppStyle.TEXT)
	hint_label.name = "ZeroTouchHint"
	left.add_child(hint_label)
	progress_bar = ProgressBar.new()
	progress_bar.name = "ZeroTouchProgress"
	progress_bar.max_value = 1.0
	progress_bar.step = 0.0
	progress_bar.show_percentage = false
	progress_bar.custom_minimum_size = Vector2(600, 28)
	left.add_child(progress_bar)
	_pick_quick_target()
	zero.configure(services.profile().ftp_w, not has_profile)
	if quick_game == "":
		zero.cancel()
	push_menu(_menu_items(), _on_pick, Callable(), 0)
	set_scanning(scanning_enabled())
	if services.trainer != null:
		services.trainer.device_changed.connect(_on_device_changed)
		services.trainer.status_changed.connect(_on_trainer_status)
		_attach_device(services.trainer.device())
	_refresh_labels()


func _on_leave() -> void:
	_attach_device(null)
	if services.trainer != null:
		if services.trainer.device_changed.is_connected(_on_device_changed):
			services.trainer.device_changed.disconnect(_on_device_changed)
		if services.trainer.status_changed.is_connected(_on_trainer_status):
			services.trainer.status_changed.disconnect(_on_trainer_status)


## The quick ride: the last-played game (if still installed) or the first-run game, with its
## zero_input_content. Without a profile it is always the first-run game.
func _pick_quick_target() -> void:
	quick_game = ""
	quick_content = ""
	var reg := services.registry
	if reg == null:
		return
	var last := str(services.settings.get_value("last_game", "")) if services.settings != null else ""
	if has_profile and last != "" and reg.has_game(last):
		quick_game = last
	else:
		quick_game = reg.first_run_game()
	if quick_game == "" or not reg.has_game(quick_game):
		quick_game = ""
		return
	quick_content = AppLobbyModel.zero_input_content(reg.manifest(quick_game))


func scanning_enabled() -> bool:
	if not has_profile:
		return false
	if zero.armed and not zero.fired and quick_game != "":
		return false
	return super.scanning_enabled()


func _menu_items() -> Array:
	var items: Array = []
	var quick_text := t("APP_NO_GAMES")
	if quick_game != "":
		var m := services.registry.manifest(quick_game)
		var ride_key := "APP_MENU_QUICK" if has_profile else "APP_MENU_RIDE_NOW"
		quick_text = t(ride_key).format([str(m.get("title", quick_game)), AppLobbyModel.content_label(quick_game, quick_content)])
	items.append({"id": "quick", "text": quick_text, "disabled": quick_game == ""})
	if has_profile:
		items.append({"id": "picker", "text": t("APP_MENU_CHOOSE_GAME")})
		items.append({"id": "host", "text": t("APP_MENU_HOST")})
		items.append({"id": "join", "text": t("APP_MENU_JOIN")})
		items.append({"id": "profile", "text": t("APP_MENU_PROFILE")})
		items.append({"id": "settings", "text": t("APP_MENU_SETTINGS")})
		items.append({"id": "rides", "text": t("APP_MENU_RIDES")})
	else:
		items.append({"id": "first_run", "text": t("APP_MENU_SETUP")})
		items.append({"id": "join", "text": t("APP_MENU_JOIN")})
		items.append({"id": "settings", "text": t("APP_MENU_SETTINGS")})
	items.append({"id": "quit", "text": t("APP_MENU_QUIT")})
	return items


func _on_pick(_index: int, id: Variant, _auto: bool) -> void:
	match str(id):
		"quick":
			quick_start()
		"picker":
			goto("picker", {"mode": "solo"})
		"host":
			goto("picker", {"mode": "host"})
		"join":
			goto("lobby", {"mode": "join"})
		"profile":
			goto("profile")
		"settings":
			goto("settings")
		"rides":
			goto("settings", {"page": "rides"})
		"first_run":
			goto("first_run")
		"quit":
			goto("quitting")


## Start the quick ride now (zero-touch hold, surge on the first item, or confirm).
func quick_start() -> void:
	if started or quick_game == "":
		return
	started = true
	zero.cancel()
	if not has_profile:
		create_first_run_profile(services)
	goto("session", {"role": Wl.SOLO, "game_id": quick_game, "content_id": quick_content, "quick": true})


## The first-run profile (BRIEF 3.5): "Rider", FTP 200, unverified, saved.
static func create_first_run_profile(s: AppServices) -> RiderProfile:
	var p := RiderProfile.new()
	p.display_name = "Rider"
	p.ftp_w = 200.0
	p.cp_w = 200.0
	p.ftp_verified = false
	p.created = true
	if s.settings != null:
		s.settings.profile = p
		s.settings.save_profile()
	if s.bus != null:
		s.bus.profile_changed.emit()
	return p


## A trainer sample (platform time) for the zero-touch countdown.
func feed_sample(sample: TrainerSample) -> void:
	if started:
		return
	if zero.feed(sample):
		quick_start()
		return
	_refresh_labels()


func _handle_action(_action: StringName) -> bool:
	if zero.armed and not started:
		_disarm()
	return false


func _handle_gesture(gesture: StringName) -> bool:
	if gesture == Wl.G_PEDAL_START:
		return true
	if gesture == Wl.G_COAST and zero.armed and zero.pedaled and not started:
		_disarm()
		return true
	return false


func _disarm() -> void:
	zero.cancel()
	set_scanning(scanning_enabled())
	_refresh_labels()


func _refresh_labels() -> void:
	var p := services.profile()
	if profile_label != null:
		if has_profile:
			var verified := "" if p.ftp_verified else " " + t("APP_UNVERIFIED")
			profile_label.text = t("APP_TITLE_PROFILE").format([p.display_name, int(round(p.ftp_w))]) + verified
		else:
			profile_label.text = t("APP_TITLE_NO_PROFILE")
	if trainer_label != null:
		var st := services.trainer.status() if services.trainer != null else ""
		trainer_label.text = t("APP_TITLE_TRAINER").format([AppLobbyCard.trainer_text(st)])
	if hint_label == null:
		return
	if quick_game == "" or not zero.armed:
		hint_label.text = ""
		progress_bar.visible = false
		return
	var game_title := str(services.registry.manifest(quick_game).get("title", quick_game))
	progress_bar.visible = true
	progress_bar.value = zero.progress()
	if zero.held_s > 0.0:
		hint_label.text = t("APP_ZERO_COUNTDOWN").format([game_title, zero.seconds_left()])
	elif has_profile:
		hint_label.text = t("APP_ZERO_HINT").format([game_title, int(zero.hold_s)])
	else:
		hint_label.text = t("APP_ZERO_FIRST_RUN").format([game_title, int(zero.hold_s)])


func _attach_device(device: TrainerDevice) -> void:
	if _device != null and is_instance_valid(_device) and _device.sample_received.is_connected(feed_sample):
		_device.sample_received.disconnect(feed_sample)
	_device = device
	if _device != null:
		_device.sample_received.connect(feed_sample)


func _on_device_changed(device: TrainerDevice) -> void:
	_attach_device(device)
	_refresh_labels()


func _on_trainer_status(_status: String, _detail: String) -> void:
	_refresh_labels()
