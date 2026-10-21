class_name AppFtpTestScreen
extends AppScreen
## The FTP test page (BRIEF 3.2, P1; Settings -> FTP test). The platform's FtpTest
## (addons/wattlands/core/ftp_test.gd) is the one implementation: its plan, end rules, best
## 1-minute power, cool-down and save countdown run the test, and FtpTest.run_on() drives the
## app's rider (the governor's ramp_test profile, the plan, every phase, the save through
## Settings: FTP, CP = FTP, ftp_verified). This page:
##   - sets the rider up as a recorded ride (game id "ftp_test"), after checking the plan with
##     the PlanValidator ({ramp_test: true});
##   - ticks the rider in fixed 0.05 s steps while the test and its cool-down run
##     (AppServices.set_menu_ticking(false), so TrainerService doesn't tick it too);
##   - shows the target, the best minute, the end reason, the result and the save countdown;
##   - saves the ride when the cool-down ends or the rider ends it, then hands the rider back.
## Stages: "intro" (Start, Back), "running" (Cancel, Panic), "cooldown" (while the 10 s
## countdown runs: Save, Keep my old FTP, Panic; then End the cool-down, Panic), "done" (Back),
## "error".
## Input: `back` cancels a running test (no new FTP), keeps the old FTP during the countdown,
## ends the cool-down after it, and leaves the page otherwise. While the test runs the menu does
## not scan and pedal gestures pick nothing: a hard effort in ERG can look like a surge. A rider
## ends the test by stopping pedaling (FtpTest's coasting rule) or by failing the target.
## A test that ends before one one-minute step was completed gives no FTP. Panic works as in a
## session: the governor goes safe at once.

const DT := Wl.SIM_DT
const GAME_ID := "ftp_test"
const CONTENT_ID := "ramp"

var test: FtpTest = null
## The plan FtpTest gave the rider (ramp-in, the steps, the cool-down).
var plan: EffortPlan = null
var rider: LocalRider = null
## "intro", "running", "cooldown", "done", "error".
var stage: String = "intro"
## The test's result once it ended (FtpTest.result()).
var result: Dictionary = {}
## The FIT the page saved ("" until then).
var fit_path: String = ""
var big_label: Label = null
var detail_label: Label = null
## (plan, opts) -> EffortPlan or null: the plan check before the test starts (tests inject one).
var plan_finalizer: Callable = func(p: EffortPlan, o: Dictionary) -> EffortPlan:
	return PlanValidator.finalize(p, o)
var _acc: float = 0.0
var _own_rider: bool = false
## True while this page ticks the rider (menu ticking handed over).
var _ticking: bool = false
## The menu shape last pushed for the cool-down ("countdown" or "after").
var _cooldown_menu: String = ""
## The ride of the current test was saved (finish_ride called once).
var _ride_done: bool = false


func _build() -> void:
	var page := make_page(t("APP_FTP_TITLE"))
	var left: VBoxContainer = page["left"]
	big_label = AppStyle.label("", AppStyle.FONT_TITLE, AppStyle.ACCENT)
	big_label.name = "Big"
	left.add_child(big_label)
	detail_label = AppStyle.paragraph(t("APP_FTP_INTRO"), AppStyle.FONT_BODY, AppStyle.TEXT)
	detail_label.name = "Detail"
	left.add_child(detail_label)
	push_menu(
		[{"id": "start", "text": t("APP_FTP_START")}, {"id": "back", "text": t("APP_BACK")}],
		_on_pick,
		_on_back
	)


func _on_leave() -> void:
	if test != null and stage in ["running", "cooldown"]:
		test.stop()
	_finish_ride()
	_release()


func _on_pick(_index: int, id: Variant, _auto: bool) -> void:
	match str(id):
		"start":
			start_test()
		"back":
			_on_back()
		"stop":
			cancel_test()
		"save":
			save_now()
		"keep":
			keep_old_ftp()
		"end_cooldown":
			end_cooldown()
		"panic":
			panic()


func _on_back() -> void:
	match stage:
		"running":
			cancel_test()
		"cooldown":
			if test != null and test.countdown_left() > 0.0:
				keep_old_ftp()
			else:
				end_cooldown()
		_:
			goto("settings")


## Check the plan, set the rider up as a recorded ride and start FtpTest on it.
func start_test() -> void:
	if stage == "running" or stage == "cooldown":
		return
	var device: TrainerDevice = services.trainer.device() if services.trainer != null else null
	if device == null:
		_error(t("APP_ERR_NO_TRAINER"))
		return
	var p := services.profile()
	var max_w := float(device.power_range().get("max_w", 1800))
	var checked := (
		plan_finalizer.call(FtpTest.build_plan(maxf(p.ftp_w, 1.0), max_w), {"ramp_test": true})
		as EffortPlan
	)
	if checked == null:
		_error(t("APP_FTP_PLAN_REJECTED"))
		return
	rider = services.trainer.local_rider()
	if rider == null:
		rider = services.make_rider()
		_own_rider = true
	var slot := p.to_slot(Wl.HOST_PEER, Wl.FAIR_FTP)
	slot.apply_look(0)
	rider.setup(
		Wl.HOST_PEER,
		p,
		slot,
		device,
		{
			"multiplayer": false,
			"scaling_mode": Wl.FAIR_FTP,
			"record": true,
			"game_id": GAME_ID,
			"content_id": CONTENT_ID,
			"utc_start_unix": services.utc_now(),
			"seed": 0,
			"skip_warmup": false
		}
	)
	services.set_menu_ticking(false)
	_ticking = true
	_acc = 0.0
	result = {}
	fit_path = ""
	_ride_done = false
	test = FtpTest.new()
	test.ended.connect(_on_test_ended)
	test.saved.connect(_on_saved)
	plan = test.run_on(rider, services.settings, services.trainer)
	stage = "running"
	clear_menus()
	var m := push_menu(
		[{"id": "stop", "text": t("APP_FTP_STOP")}, {"id": "panic", "text": t("APP_PANIC")}],
		_on_pick,
		_on_back
	)
	m.scanning = false
	_refresh()


## Stop the running test without a new FTP (`back`, the Cancel item); the cool-down follows.
func cancel_test() -> void:
	if stage == "running" and test != null:
		test.back()


## Save the result now (during the countdown).
func save_now() -> void:
	if stage == "cooldown" and test != null:
		test.save_now()
		_cooldown_menus()
		_refresh()


## Keep the old FTP (during the countdown).
func keep_old_ftp() -> void:
	if stage == "cooldown" and test != null and test.countdown_left() > 0.0:
		test.back()
		_cooldown_menus()
		_refresh()


## End the cool-down early (or after it ended by itself): save the ride, hand the rider back.
func end_cooldown() -> void:
	if stage != "cooldown":
		return
	if test != null and test.state != FtpTest.DONE:
		test.stop()
	_complete()


func _on_test_ended(r: Dictionary) -> void:
	result = r.duplicate(true)
	stage = "cooldown"
	_cooldown_menu = ""
	_cooldown_menus()
	_refresh()


func _on_saved(_ftp_w: float) -> void:
	if test != null:
		result = test.result()
	if stage == "cooldown":
		_cooldown_menus()


## The cool-down's menu: Save / Keep while the countdown runs, then End the cool-down.
func _cooldown_menus() -> void:
	var shape := "countdown" if test != null and test.countdown_left() > 0.0 else "after"
	if shape == _cooldown_menu:
		return
	_cooldown_menu = shape
	clear_menus()
	var items: Array = []
	if shape == "countdown":
		items = [
			{"id": "save", "text": t("APP_FTP_SAVE")}, {"id": "keep", "text": t("APP_FTP_KEEP")}
		]
	else:
		items = [{"id": "end_cooldown", "text": t("APP_FTP_END_COOLDOWN")}]
	items.append({"id": "panic", "text": t("APP_PANIC")})
	push_menu(items, _on_pick, _on_back)


func _complete() -> void:
	if stage == "done":
		return
	if test != null:
		result = test.result()
	stage = "done"
	_finish_ride()
	_release()
	clear_menus()
	push_menu([{"id": "back", "text": t("APP_BACK")}], _on_pick, _on_back)
	_refresh()


func _finish_ride() -> void:
	if rider != null and is_instance_valid(rider) and test != null and not _ride_done:
		_ride_done = true
		fit_path = rider.finish_ride()


func _error(text: String) -> void:
	stage = "error"
	detail_label.text = text


func _tick(dt: float) -> void:
	if not _ticking:
		return
	_acc += dt
	while _acc >= DT and _ticking:
		_acc -= DT
		step_fixed()


## One fixed 0.05 s step: tick the rider (FtpTest follows its telemetry). Headless tests call
## it directly.
func step_fixed() -> void:
	if not _ticking or rider == null or not is_instance_valid(rider):
		return
	rider.tick(DT)
	if test != null and test.state == FtpTest.DONE and stage == "cooldown":
		_complete()
		return
	if stage == "cooldown":
		_cooldown_menus()
	_refresh()


## The panic action (Backspace held, View+Menu) works here as in a session (BRIEF 4.6.5): the
## rider's governor goes safe at once, whatever the menu shows.
func _handle_action(action: StringName) -> bool:
	if action == &"panic":
		panic()
		return true
	return false


## While the test runs, pedal gestures pick nothing (a hard ERG effort can read as a surge; a
## stop is FtpTest's coasting rule, which keeps the result).
func _handle_gesture(gesture: StringName) -> bool:
	return stage == "running" and (gesture == Wl.G_SURGE or gesture == Wl.G_COAST)


func panic() -> void:
	if services.bus != null:
		services.bus.panic_requested.emit()
	if rider != null and is_instance_valid(rider) and (stage == "running" or stage == "cooldown"):
		rider.panic()


func _refresh() -> void:
	if big_label == null:
		return
	match stage:
		"running":
			var ph := plan.phase(test.phase_index) if plan != null and test != null else null
			var target := (
				floorf(ph.planned_pct_at(test.phase_elapsed_s) * test.ftp_w / 100.0)
				if ph != null
				else 0.0
			)
			big_label.text = "%d W" % int(target)
			detail_label.text = t("APP_FTP_RUNNING").format(
				[t(ph.label) if ph != null else "", int(round(test.best_1min_w))]
			)
		"cooldown":
			big_label.text = _result_title()
			var lines: Array[String] = [_end_text(), _save_text()]
			var left := PlanValidator.COOLDOWN_S - test.phase_elapsed_s if test != null else 0.0
			lines.append(
				t("APP_FTP_COOLDOWN_LEFT").format([AppStyle.duration_text(maxf(left, 0.0))])
			)
			detail_label.text = "\n".join(lines)
		"done":
			big_label.text = "FTP %d W" % int(round(services.profile().ftp_w))
			detail_label.text = "\n".join([_end_text(), _save_text(), t("APP_FTP_COOLDOWN_DONE")])


func _result_title() -> String:
	if bool(result.get("valid", false)):
		return "FTP %d W" % int(result.get("ftp_w", 0.0))
	return t("APP_FTP_COOLDOWN")


func _end_text() -> String:
	var reason := str(result.get("end_reason", ""))
	return t(FtpTest.end_reason_key(reason)) if reason != "" else ""


func _save_text() -> String:
	if not bool(result.get("valid", false)):
		if str(result.get("end_reason", "")) == FtpTest.END_BACK:
			return t("CORE_FTP_NOT_SAVED")
		return t("APP_FTP_NO_RESULT")
	var lead := t("CORE_FTP_RESULT").format(
		{
			"ftp": int(result.get("ftp_w", 0.0)),
			"best": int(round(float(result.get("best_1min_w", 0.0))))
		}
	)
	if test != null and test.countdown_left() > 0.0:
		return (
			"%s\n%s"
			% [lead, t("CORE_FTP_SAVING").format({"s": ceili(test.countdown_left() - 1e-9)})]
		)
	if bool(result.get("saved", false)):
		return "%s\n%s" % [lead, t("CORE_FTP_SAVED")]
	return "%s\n%s" % [lead, t("CORE_FTP_NOT_SAVED")]


## Hand the rider back to TrainerService (after the ride was saved: its menu reset waits for
## that) and free a rider this page made.
func _release() -> void:
	if _ticking and services != null:
		services.set_menu_ticking(true)
	_ticking = false
	if _own_rider and rider != null and is_instance_valid(rider) and rider.get_parent() == null:
		rider.free()
	if _own_rider:
		rider = null
	_own_rider = false
