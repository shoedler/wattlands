extends GutTest
## BRIEF 7.4 (P1): the FTP test's estimate against MockTrainer's rider model, run through a
## real LocalRider, SafetyGovernor ("ramp_test" profile) and MockTrainer "erg".
##   - within 3% of 0.75 x the mock rider's analytic best 1-minute power under the protocol;
##   - with the mock's FTP set to its CP, within 10% of CP for CP 150-350 W and W' 15-25 kJ
##     wherever W' <= 100 s x CP.
## The analytic rider follows the protocol's targets exactly and fails when Skiba's W'
## balance (BRIEF 3.4) reaches 0; its best minute is the 60 s ending there.
## Needs the W1 SafetyGovernor (trainer-control) and MockTrainer's W' fatigue (trainer-core):
## against the W0 stubs every test is marked pending. Not part of platform's W1 command.

const DT := Wl.SIM_DT
## Upper bound on a run: the ramp-in, 40 steps and the end rules.
const MAX_TEST_S := 300.0 + 40.0 * 60.0 + 30.0


## True once the governor in a set-up rider reports a status (the W0 stub returns {}).
func _governor_is_real() -> bool:
	var m := MockTrainer.from_spec("erg", 200.0)
	autofree(m)
	var r := LocalRider.new()
	add_child_autofree(r)
	var bus := WlEventBus.new()
	autofree(bus)
	r.setup(1, RiderProfile.new(), null, m, {"bus": bus})
	r.tick(DT)
	return not r.governor.status().is_empty()


## The protocol's ERG target (W) at `t` seconds into the test.
static func _target_w(ftp: float, t: float) -> float:
	if t < FtpTest.RAMP_IN_S:
		return ftp / 100.0 * lerpf(FtpTest.RAMP_FROM_PCT, FtpTest.RAMP_TO_PCT, t / FtpTest.RAMP_IN_S)
	var n := int(floor((t - FtpTest.RAMP_IN_S) / FtpTest.STEP_S)) + 1
	return ftp / 100.0 * FtpTest.step_pct(n)


## The analytic best 1-minute power: the 60 s of protocol targets ending where W'bal hits 0.
static func _analytic_best_1min(ftp: float, cp: float, wprime: float) -> float:
	var wb := WBalance.create(cp, wprime)
	var t := 0.0
	while t < MAX_TEST_S:
		wb.step(_target_w(ftp, t), DT)
		t += DT
		if wb.wbal_j <= 0.0:
			break
	var e := 0.0
	var s := maxf(t - 60.0, 0.0)
	while s < t - 1e-9:
		e += _target_w(ftp, s) * DT
		s += DT
	return e / 60.0


func _run(ftp: float, cp: float, wprime: float) -> Dictionary:
	var m := MockTrainer.from_spec("erg", ftp, {"cp_w": cp, "wprime_j": wprime, "seed": 11,
		"preferred_cadence_rpm": 90.0})
	autofree(m)
	var p := RiderProfile.new()
	p.ftp_w = ftp
	p.cp_w = cp
	p.wprime_j = wprime
	p.created = true
	var bus := WlEventBus.new()
	autofree(bus)
	var r := LocalRider.new()
	add_child_autofree(r)
	r.setup(1, p, null, m, {"bus": bus})
	var settings := WlSettings.new()
	autofree(settings)
	settings.autosave = false
	var service := WlTrainerService.new()
	autofree(service)
	var test := FtpTest.new()
	test.run_on(r, settings, service)
	var ticks := 0
	while test.state != FtpTest.COOLDOWN and test.state != FtpTest.DONE and ticks * DT < MAX_TEST_S:
		r.tick(DT)
		ticks += 1
	var res := test.result()
	test.stop()
	return res


func test_the_plan_passes_the_validator_as_ramp_test() -> void:
	var v := PlanValidator.validate(FtpTest.build_plan(250.0), {"ramp_test": true})
	if v.get("errors", []) == ["not implemented"]:
		pending("needs the W1 PlanValidator (sdk-runtime)")
		return
	assert_true(v["ok"], str(v["errors"]))
	assert_eq(v["warnings"], [])


func test_estimate_within_3_percent_of_the_analytic_best_minute() -> void:
	if not _governor_is_real():
		pending("needs the W1 SafetyGovernor (trainer-control) and MockTrainer fatigue (trainer-core)")
		return
	for case: Array in [[250.0, 250.0, 20000.0], [200.0, 250.0, 20000.0], [300.0, 280.0, 18000.0]]:
		var ftp: float = case[0]
		var cp: float = case[1]
		var wp: float = case[2]
		var res := _run(ftp, cp, wp)
		var expected := FtpTest.FTP_FACTOR * _analytic_best_1min(ftp, cp, wp)
		assert_ne(res.get("end_reason"), FtpTest.END_COMPLETE, "the mock rider must fail eventually (W' fatigue)")
		assert_true(bool(res.get("valid", false)), str(res))
		var got := float(res.get("ftp_w", 0.0))
		assert_almost_eq(got, expected, 0.03 * expected,
			"FTP %d, CP %d, W' %d: estimate %.1f vs 0.75 x analytic best %.1f (%s)" % [ftp, cp, wp, got, expected, res.get("end_reason")])


func test_estimate_within_10_percent_of_cp() -> void:
	if not _governor_is_real():
		pending("needs the W1 SafetyGovernor (trainer-control) and MockTrainer fatigue (trainer-core)")
		return
	for cp: float in [150.0, 250.0, 350.0]:
		for wp: float in [15000.0, 20000.0, 25000.0]:
			if wp > 100.0 * cp:
				continue
			var res := _run(cp, cp, wp)
			var got := float(res.get("ftp_w", 0.0))
			assert_almost_eq(got, cp, 0.10 * cp, "CP %d, W' %d: estimate %.1f (%s)" % [cp, wp, got, res.get("end_reason")])


func test_analytic_reference_matches_hand_numbers() -> void:
	# CP = FTP = 250, W' 20 kJ: W' runs out half a second into step 14, so the best minute is
	# step 13 at 137% (342.5 W) and the estimate 0.75 x 342.5 = 256.9 W (BRIEF's 10% band).
	assert_almost_eq(_analytic_best_1min(250.0, 250.0, 20000.0), 342.5, 1.0)
	# CP 150, W' 15 kJ: fails 47 s into step 14 (214.5 W) after step 13 (205.5 W).
	assert_almost_eq(_analytic_best_1min(150.0, 150.0, 15000.0), (13.0 * 205.5 + 47.0 * 214.5) / 60.0, 1.0)
