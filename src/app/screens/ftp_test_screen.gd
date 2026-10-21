class_name AppFtpTestScreen
extends AppScreen
## The FTP test (BRIEF 3.2, P1; Settings -> FTP test). Runs AppFtpTest's plan on the app's local
## rider: the governor's ramp_test profile, the plan validated with PlanValidator.finalize(plan,
## {"ramp_test": true}) (which appends the 3-minute cool-down), phases advanced every 60 s, the
## end rules fed with the rider's telemetry. After the cool-down the new FTP (0.75 x best
## 1-minute power) is saved after a 10 s countdown unless `back`. The ride is recorded like any
## other. Panic works as in a session.

const DT := Wl.SIM_DT

var test: AppFtpTest = null
var plan: EffortPlan = null
var rider: LocalRider = null
## "intro", "running", "cooldown", "result", "saved", "error".
var stage: String = "intro"
var phase_index: int = -1
var phase_elapsed: float = 0.0
var platform_t: float = 0.0
var countdown: float = 0.0
var _acc: float = 0.0
var _own_rider: bool = false
var big_label: Label = null
var detail_label: Label = null
## (plan, opts) -> EffortPlan or null: PlanValidator.finalize (tests inject one).
var plan_finalizer: Callable = func(p: EffortPlan, o: Dictionary) -> EffortPlan: return PlanValidator.finalize(p, o)


func _build() -> void:
	var page := make_page(t("APP_FTP_TITLE"))
	var left: VBoxContainer = page["left"]
	big_label = AppStyle.label("", AppStyle.FONT_TITLE, AppStyle.ACCENT)
	big_label.name = "Big"
	left.add_child(big_label)
	detail_label = AppStyle.paragraph(t("APP_FTP_INTRO"), AppStyle.FONT_BODY, AppStyle.TEXT)
	detail_label.name = "Detail"
	left.add_child(detail_label)
	push_menu([{"id": "start", "text": t("APP_FTP_START")}, {"id": "back", "text": t("APP_BACK")}], _on_pick, _on_back)


func _on_leave() -> void:
	_release()


func _on_pick(_index: int, id: Variant, _auto: bool) -> void:
	match str(id):
		"start":
			start_test()
		"back":
			_on_back()
		"stop":
			stop_test()
		"keep":
			finish_result(false)
		"save":
			finish_result(true)
		"panic":
			panic()


func _on_back() -> void:
	match stage:
		"running", "cooldown":
			stop_test()
		"result":
			finish_result(false)
		_:
			goto("settings")


## Build the plan, configure the rider for ramp_test and start the ramp-in.
func start_test() -> void:
	var device: TrainerDevice = services.trainer.device() if services.trainer != null else null
	if device == null:
		_error(t("APP_ERR_NO_TRAINER"))
		return
	var p := services.profile()
	test = AppFtpTest.create(p.ftp_w, float(device.power_range().get("max_w", 1800)))
	var finalized := plan_finalizer.call(test.build_plan(), {"ramp_test": true}) as EffortPlan
	if finalized == null:
		_error(t("APP_FTP_PLAN_REJECTED"))
		return
	plan = finalized
	rider = services.trainer.local_rider()
	if rider == null:
		rider = services.make_rider()
		_own_rider = true
	var slot := p.to_slot(Wl.HOST_PEER, Wl.FAIR_FTP)
	slot.apply_look(0)
	rider.setup(Wl.HOST_PEER, p, slot, device, {"multiplayer": false, "scaling_mode": Wl.FAIR_FTP, "record": true,
		"game_id": "ftp_test", "content_id": "ramp", "utc_start_unix": services.utc_now(), "seed": 0,
		"skip_warmup": false})
	if rider.governor != null:
		rider.governor.configure({
			"ftp_w": p.ftp_w, "ftp_verified": p.ftp_verified, "difficulty_pct": p.difficulty_pct,
			"grade_min_pct": p.grade_min_pct, "grade_max_pct": p.grade_max_pct, "haptics_on": p.haptics_on,
			"haptic_intensity": p.haptic_intensity_pct / 100.0, "skip_warmup": false, "multiplayer": false,
			"profile": "ramp_test",
		})
	services.set_menu_ticking(false)
	rider.set_plan(plan)
	stage = "running"
	_start_phase(0)
	clear_menus()
	push_menu([{"id": "stop", "text": t("APP_FTP_STOP")}, {"id": "panic", "text": t("APP_PANIC")}], _on_pick, _on_back)


func _start_phase(i: int) -> void:
	phase_index = i
	phase_elapsed = 0.0
	if rider != null:
		rider.start_phase(i)


## End the test now (back, or the stop item): straight to the cool-down.
func stop_test() -> void:
	if stage == "running" and test != null:
		test.on_coast(platform_t)
		_enter_cooldown()
	elif stage == "cooldown":
		_enter_result()


func _enter_cooldown() -> void:
	stage = "cooldown"
	var ci := plan.cooldown_index() if plan != null else -1
	if ci >= 0:
		_start_phase(ci)


func _enter_result() -> void:
	stage = "result"
	countdown = AppFtpTest.SAVE_COUNTDOWN_S
	if rider != null:
		rider.finish_ride()
	clear_menus()
	push_menu([{"id": "save", "text": t("APP_FTP_SAVE")}, {"id": "keep", "text": t("APP_FTP_KEEP")}], _on_pick, _on_back)
	_refresh()


## Save (or keep the old FTP) and return to settings.
func finish_result(save: bool) -> void:
	if stage != "result":
		return
	var ftp := test.result_ftp_w() if test != null else 0.0
	if save and ftp > 0.0:
		var p := services.profile()
		p.ftp_w = ftp
		p.cp_w = ftp
		p.ftp_verified = true
		if services.settings != null:
			services.settings.save_profile()
		if services.bus != null:
			services.bus.profile_changed.emit()
		stage = "saved"
	else:
		stage = "intro"
	_release()
	goto("settings")


func _error(text: String) -> void:
	stage = "error"
	detail_label.text = text


func _tick(dt: float) -> void:
	if stage == "result":
		countdown -= dt
		_refresh()
		if countdown <= 0.0:
			finish_result(true)
		return
	if stage != "running" and stage != "cooldown":
		return
	_acc += dt
	while _acc >= DT:
		_acc -= DT
		step_fixed()


## One fixed 0.05 s step of the test (headless tests call it directly).
func step_fixed() -> void:
	if stage != "running" and stage != "cooldown":
		return
	platform_t += DT
	phase_elapsed += DT
	if rider != null:
		rider.tick(DT)
		var tm := rider.telemetry()
		if stage == "running" and test != null:
			if test.feed(platform_t, tm.power_w, tm.cadence_rpm, float(tm.applied_target_w), tm.rescue) != "":
				_enter_cooldown()
	if plan == null:
		return
	var ph := plan.phase(phase_index)
	if ph != null and phase_elapsed >= ph.duration_s:
		if stage == "cooldown":
			_enter_result()
			return
		if phase_index + 1 < plan.size() and plan.phase(phase_index + 1).kind != Wl.COOLDOWN:
			_start_phase(phase_index + 1)
		else:
			test.on_plan_end(platform_t)
			_enter_cooldown()
	_refresh()


## The panic action (Backspace held, View+Menu) works here as in a session (BRIEF 4.6.5): the
## rider's governor goes safe at once, whatever the menu shows.
func _handle_action(action: StringName) -> bool:
	if action == &"panic":
		panic()
		return true
	return false


func panic() -> void:
	if services.bus != null:
		services.bus.panic_requested.emit()
	if rider != null and (stage == "running" or stage == "cooldown"):
		rider.panic()


func _handle_gesture(gesture: StringName) -> bool:
	if gesture == Wl.G_COAST and stage == "running" and test != null:
		test.on_coast(platform_t)
		_enter_cooldown()
		return true
	return false


func _refresh() -> void:
	match stage:
		"running":
			var ph := plan.phase(phase_index) if plan != null else null
			var target := ph.planned_pct_at(phase_elapsed) * test.ftp_w / 100.0 if ph != null else 0.0
			big_label.text = "%d W" % int(round(target))
			detail_label.text = t("APP_FTP_RUNNING").format([ph.label if ph != null else "", int(round(test.best_1m_w))])
		"cooldown":
			big_label.text = t("APP_FTP_COOLDOWN")
			detail_label.text = t("APP_FTP_ENDED").format([t("APP_FTP_END_" + test.end_reason.to_upper())])
		"result":
			big_label.text = "FTP %d W" % int(test.result_ftp_w())
			detail_label.text = t("APP_FTP_RESULT").format([int(round(test.best_1m_w)), int(ceil(maxf(countdown, 0.0)))])


func _release() -> void:
	if services != null:
		services.set_menu_ticking(true)
	if _own_rider and rider != null and is_instance_valid(rider) and rider.get_parent() == null:
		rider.free()
	rider = null
	_own_rider = false
