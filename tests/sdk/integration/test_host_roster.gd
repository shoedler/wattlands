extends GutTest
## W2 round 2 (qa W1 and core round 1 notes): a HOST GameSimRunner run with three human slots
## (fx_conform "tiny", riders erg, erg+band, erg, seed 5) over the real LocalRider,
## SafetyGovernor, MockTrainer, WlNetSession and LoopbackTransport. For two minutes every
## rider's row in the host's roster (and in each client's copy) shows that rider's own power,
## and every rider's phase on the host's tracker is the phase its own governor, LocalRider and
## GameHost are in. qa saw a loopback client at 0 W in the roster; core saw the second client
## never get its plan or phase messages.

const FIXTURES := "res://tests/fixtures/games"
const RIDE_TICKS := 2400
## The roster is built every 10th platform tick from the newest telemetry the host has: a
## client's power reaches it within one 5 Hz telemetry period (4 ticks) plus the tick the
## message takes.
const ROSTER_LAG_TICKS := 6
## A `phase` message reaches its client within the same runner tick (host steps first); one
## tick of slack.
const PHASE_LAG_TICKS := 1

var _reg: WlGameRegistry = null
var _runner: GameSimRunner = null
var _tmp: String = ""


func before_each() -> void:
	_tmp = Paths.make_temp_dir("wattlands_host_roster")
	Paths.set_override(_tmp)
	_reg = WlGameRegistry.new()
	_reg.scan_on_ready = false
	_reg.content_root = FIXTURES.path_join("_content")
	_reg.scan(FIXTURES.path_join("conform"))


func after_each() -> void:
	if _runner != null and is_instance_valid(_runner):
		_runner.cleanup()
		_runner.free()
	_runner = null
	_reg.clear()
	_reg.free()
	Paths.set_override("")
	_remove_tree(_tmp)


func test_three_human_slots_roster_power_and_phases_follow_each_riders_own_telemetry() -> void:
	_runner = GameSimRunner.new()
	assert_eq(_runner.setup({
		"game": "fx_conform", "content": "tiny", "players": 3, "riders": ["erg", "erg+band", "erg"],
		"seed": 5, "registry": _reg, "max_sim_seconds": 300.0,
	}), "")
	var r := _runner
	assert_eq(r.role, Wl.HOST)
	var peers: Array[int] = []
	for s in r.slots:
		peers.append(s.peer_id)
	assert_eq(peers.size(), 3)
	var by_peer := {}
	for c in r.clients:
		by_peer[c.local_peer()] = c
	assert_eq(by_peer.size(), 2, "two loopback clients")
	# Per rider: own power per tick (as its LocalRider reports it), for the lag window.
	var power_hist := {}
	for p in peers:
		power_hist[p] = []
	var roster_checks := 0
	var roster_misses: Array = []
	var client_roster_misses: Array = []
	var phase_misses: Array = []
	var phase_lag := {}
	var max_phase := {}
	for tick in RIDE_TICKS:
		r.step()
		for p in peers:
			(power_hist[p] as Array).append((r.riders[p] as LocalRider).telemetry().power_w)
		if r.host.clock.platform_tick % GameHost.ROSTER_EVERY == 1:
			# The roster built during this runner tick (the host's platform tick before step()).
			roster_checks += 1
			for p in peers:
				var row: Dictionary = r.host.ctx.roster.get(p, {})
				if row.is_empty() or not _seen_recently(power_hist[p], float(row.get("raw_w", -1.0)), ROSTER_LAG_TICKS):
					roster_misses.append([tick, p, row.get("raw_w"), (power_hist[p] as Array).slice(-ROSTER_LAG_TICKS)])
				for c in r.clients:
					var crow: Dictionary = c.ctx.roster.get(p, {}) if c.ctx != null else {}
					if crow.is_empty() or not _seen_recently(power_hist[p], float(crow.get("raw_w", -1.0)), ROSTER_LAG_TICKS + 1):
						client_roster_misses.append([tick, c.local_peer(), p, crow.get("raw_w")])
		for p in peers:
			var host_index := r.host.tracker.index_of(p)
			var own := (r.riders[p] as LocalRider).telemetry().phase_index
			var gh_index: int = r.host.local_phase_state().index if p == r.host.local_peer() else (by_peer[p] as GameHost).local_phase_state().index
			max_phase[p] = maxi(int(max_phase.get(p, -1)), own)
			if own != host_index or gh_index != host_index:
				var lag := int(phase_lag.get(p, 0)) + 1
				phase_lag[p] = lag
				if lag > PHASE_LAG_TICKS:
					phase_misses.append([tick, p, host_index, own, gh_index])
			else:
				phase_lag[p] = 0
	assert_gt(roster_checks, 200)
	assert_eq(roster_misses.slice(0, 5), [], "host roster raw_w is each rider's own recent power (%d misses)" % roster_misses.size())
	assert_eq(client_roster_misses.slice(0, 5), [], "every client's roster copy too (%d misses)" % client_roster_misses.size())
	assert_eq(phase_misses.slice(0, 5), [], "each rider's own phase is the host's (%d misses)" % phase_misses.size())
	for p in peers:
		assert_eq(int(max_phase[p]), 4, "peer %d reached the cool-down on its own governor" % p)
		var row: Dictionary = r.host.ctx.roster[p]
		assert_gt(float(row["raw_w"]), 50.0, "peer %d rides in the host's roster" % p)
		assert_true(bool(row["connected"]))
		assert_false(bool(row["afk"]))
	for c in r.clients:
		assert_true(c.plans.has(c.local_peer()), "client %d got its plan" % c.local_peer())
		assert_gt(c.local_phase_state().count, 0, "and knows its phases")


## True when `value` is one of the last `ticks` entries of `hist` (exact: the roster carries
## the very float the rider's telemetry reported).
static func _seen_recently(hist: Array, value: float, ticks: int) -> bool:
	var n := hist.size()
	for i in range(maxi(0, n - ticks), n):
		if is_equal_approx(float(hist[i]), value):
			return true
	return false


static func _remove_tree(dir: String) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	da.include_hidden = true
	for f in da.get_files():
		DirAccess.remove_absolute(dir.path_join(f))
	for sub in da.get_directories():
		_remove_tree(dir.path_join(sub))
	DirAccess.remove_absolute(dir)
