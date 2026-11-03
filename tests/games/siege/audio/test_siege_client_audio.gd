extends GutTest
## What a network client hears of a real wave, against what the host hears of it: the same seeded session as a host and
## a client, each with its own view and real players on the Dummy driver. A client has no simulation, only the `shot`
## events and the snapshots, and replays each landing from them (SiegeShotSounds). A Probe stands in for each view's
## replay and notes every impact the view hears and the frame it came on, so a host's arrow is matched with the
## client's by where it comes down. The owner asked for a hit for every arrow; that was measured on the host.
##
## Measured, 150 s of a real wave with two humans and two bots, events and snapshots a tick late: 599 arrows land on
## the host and every one on the client, each volley of 12 whole on both, each a frame-exact 0.2 s later on the client
## (0.1 s of render delay, the picture's own, and 0.1 s of network), and 98% on the same surface. With snapshots at
## 2 Hz the delay is 0.55 s and 96% agree, at 1 Hz 1.05 s and 93%: the sound stays with the picture, and which body an
## arrow falls on drifts with the delay, since the replay reads the bodies of the newest snapshot.

const F := preload("res://tests/games/siege/siege_fakes.gd")
const SECONDS := 150.0
const ARROW_FILES := ["arrow_flesh", "arrow_wood", "arrow_shield", "arrow_dirt", "arrow_water"]
## A client's render delay at 10 Hz plus the network, with room for a frame.
const MAX_OFFSET_S := 0.4
## Volleys still in the air this close to the end of the run have their landings cut off.
const TAIL_S := 1.0

var _host: Listener = null
var _client: Listener = null
var _shots: Array[Dictionary] = []
var _batch: Array[Dictionary] = []


## The replay of a view, noting each impact and the sim time of the frame that handed it over.
class Probe:
	extends SiegeShotSounds
	var frame_t: float = 0.0
	var heard: Array[Dictionary] = []

	func step(now_s: float, enemies: Array[SiegeEnemyState]) -> Array[Dictionary]:
		var out := super(now_s, enemies)
		for imp in out:
			var rec := imp.duplicate()
			rec["frame_t"] = frame_t
			heard.append(rec)
		return out


## One listener: a module, its view and everything the view's kit played.
class Listener:
	extends RefCounted
	var game: SiegeGame
	var view: SiegeView
	var probe: Probe
	var played: Dictionary = {}
	var since: Dictionary = {}

	func landing_cues() -> int:
		var n := 0
		for id: String in ARROW_FILES:
			n += int(played.get(id, 0))
		return n

	func impacts(weapon: String) -> Array:
		return probe.heard.filter(func(r: Dictionary) -> bool: return r["weapon"] == weapon)


func after_each() -> void:
	for l: Listener in [_host, _client]:
		if l != null:
			l.view.audio.kit.stop_all()
			F.free_game(l.game)
	_host = null
	_client = null
	_shots.clear()
	_batch.clear()


func _listener(ctx: GameContext) -> Listener:
	var l := Listener.new()
	l.game = F.make_game(ctx)
	l.view = l.game.make_view() as SiegeView
	add_child_autofree(l.view)
	l.probe = Probe.new()
	l.view.audio._shots = l.probe
	var kit := l.view.audio.kit
	kit.force_audio = true
	kit.setup(SiegeAudio.BANK_PATH, 3)
	return l


## Ends each crowd voice when its sound has run its length on the sim clock: this steps far faster than the mixer
## plays, so on the mixer's clock nothing would finish and a pool of any size would fill.
func _finish_crowd_on_sim_clock(l: Listener, t: float) -> void:
	for v: GameAudioKit.Voice in l.view.audio.kit._pools[GameAudioKit.CROWD]:
		if not v.player.playing:
			l.since.erase(v)
			continue
		var started: float = l.since.get_or_add(v, t)
		if t - started >= v.player.stream.get_length() / v.player.pitch_scale:
			v.player.stop()
			l.since.erase(v)


func _count_played(l: Listener) -> void:
	var kit := l.view.audio.kit
	for id in kit.played:
		l.played[id] = int(l.played.get(id, 0)) + 1
	kit.clear_played()


static func _wire(d: Dictionary, paths: Array) -> Dictionary:
	return Protocol.apply_int_fields(JSON.parse_string(JSON.stringify(d)), paths)


func _on_host_event(e: Dictionary) -> void:
	_batch.append(e)


func _on_host_cue(kind: String, data: Dictionary) -> void:
	if kind == SiegeIds.EV_SHOT:
		_shots.append(data)


## A host (peer 1) and a client (peer 2) of one seeded session. Every event batch and every `every`th tick's snapshot
## reaches the client `lag` ticks after the host sent it, as the platform sends them.
func _session(seconds: float, lag: int, every: int = 2) -> void:
	_host = _listener(F.make_ctx(2, 2, "short", Wl.HOST, 1, 3))
	_client = _listener(F.make_ctx(2, 2, "short", Wl.CLIENT, 2, 3))
	var plans := F.plans_of(_host.game)
	_host.game.plans = plans
	_host.game.game_event.connect(_on_host_event)
	_host.game.cue.connect(_on_host_cue)
	var inbox: Array = []  # [due tick, "event" or "snapshot", payload]
	for tick in roundi(seconds / Wl.SIM_DT):
		var t := tick * Wl.SIM_DT
		var f := F.frame(_host.game.ctx, plans, tick, 100.0)
		_batch.clear()
		_host.game.sim_step(Wl.SIM_DT, f)
		if not _batch.is_empty():
			inbox.append([tick + lag, "event", _batch.duplicate()])
		if tick % every == 0:
			inbox.append([tick + lag, "snapshot", _host.game.snapshot()])
		inbox = _deliver(inbox, tick)
		_client.game.client_predict(Wl.SIM_DT, f.players[2])
		for l: Listener in [_host, _client]:
			l.probe.frame_t = t
			l.view.update(Wl.SIM_DT)
			_finish_crowd_on_sim_clock(l, t)
			_count_played(l)


## Hands the client what is due at `tick`; returns what is still on its way.
func _deliver(inbox: Array, tick: int) -> Array:
	var rest: Array = []
	for m: Array in inbox:
		if int(m[0]) > tick:
			rest.append(m)
		elif m[1] == "event":
			for e: Dictionary in m[2]:
				var paths: Array = _client.game.int_fields().get(str(e["type"]), [])
				_client.game.apply_event(_wire(e, paths))
		else:
			_client.game.apply_snapshot(_wire(m[2], _client.game.int_fields()["snapshot"]))
	return rest


## An arrow is known by where it comes down: the same on every peer, whatever it lands on.
static func _key(imp: Dictionary) -> String:
	return "%s|%s" % [imp["weapon"], imp["at"]]


static func _by_key(list: Array) -> Dictionary:
	var out := {}
	for r: Dictionary in list:
		out[_key(r)] = r
	return out


## The arrow volleys the host fired: {keys: {landing key: true}, end: when the last lands, n}.
func _volleys() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var st: SiegeState = _host.game.state
	for ev in _shots:
		if int(ev["kind"]) != SiegeIds.SHOT_ARROW:
			continue
		var r := SiegeV2ShotReplay.from_event(ev, st.path, st.content)
		var keys := {}
		var last := 0.0
		for j in r.n:
			keys["arrow|%s" % r.landing(j)] = true
			last = maxf(last, r.land_t[j])
		out.append({"keys": keys, "end": int(ev["tk"]) * Wl.SIM_DT + last, "n": r.n})
	return out


## Every whole volley of the run is heard whole by both, each arrow a moment later by the client and no earlier;
## returns {landings, same, struck_host, struck_client, whole}.
func _compare_arrows() -> Dictionary:
	var host_arrows := _by_key(_host.impacts("arrow"))
	var client_arrows := _by_key(_client.impacts("arrow"))
	var out := {"landings": 0, "same": 0, "struck_host": 0, "struck_client": 0, "whole": 0}
	for v: Dictionary in _volleys():
		if float(v["end"]) > SECONDS - TAIL_S:
			continue
		var h := 0
		var c := 0
		for k: String in v["keys"]:
			var hr: Variant = host_arrows.get(k)
			var cr: Variant = client_arrows.get(k)
			h += 1 if hr != null else 0
			c += 1 if cr != null else 0
			if hr == null or cr == null:
				continue
			out["landings"] += 1
			out["same"] += 1 if hr["surface"] == cr["surface"] else 0
			out["struck_host"] += 1 if hr["surface"] != SiegeShotSounds.SURFACE_DIRT else 0
			out["struck_client"] += 1 if cr["surface"] != SiegeShotSounds.SURFACE_DIRT else 0
			var off := float(cr["frame_t"]) - float(hr["frame_t"])
			assert_between(off, 0.0, MAX_OFFSET_S, "no arrow is early or later than the picture")
		assert_eq(h, int(v["n"]), "the host hears the whole volley")
		assert_eq(c, int(v["n"]), "the client hears the whole volley")
		out["whole"] += 1 if h == c and c == int(v["n"]) else 0
	return out


func _assert_a_voice_for_every_arrow() -> void:
	var host_n := _host.impacts("arrow").size()
	var client_n := _client.impacts("arrow").size()
	assert_gt(host_n, 500, "a real wave lands hundreds of arrows")
	# A client is a moment behind: at most the volleys in the air when the run ends are missing.
	assert_lte(
		host_n - client_n, 24, "%d arrows on the host, %d on the client" % [host_n, client_n]
	)
	assert_eq(_host.landing_cues(), host_n, "one sound per arrow on the host")
	assert_eq(_client.landing_cues(), client_n, "one sound per arrow on the client")
	for l: Listener in [_host, _client]:
		assert_eq(l.view.audio.kit.crowd_voiceless, 0, "no arrow lost to a full crowd pool")
		for tally: String in l.view.audio.kit.stolen:
			assert_false(tally.begins_with("Crowd:"), "no crowd voice cut off: %s" % tally)


func _assert_the_other_weapons_match() -> void:
	for weapon in ["bolt", "scorpion", "stone"]:
		var h := _host.impacts(weapon).size()
		var c := _client.impacts(weapon).size()
		assert_gt(h, 3, "the host hears %s" % weapon)
		assert_lte(absi(h - c), maxi(2, h / 5), "%s: %d host, %d client" % [weapon, h, c])


## Peer 1 drives the arrows and peer 2 another station: each hears its own station at full level and the rest at the
## cue's other_db, so the host's volleys are 2 to 3 dB lower on the client.
func _assert_whose_volleys_are_whose() -> void:
	var host_lead := 0
	var client_lead := 0
	for r: Dictionary in _host.impacts("arrow"):
		host_lead += 1 if bool(r["lead"]) else 0
	for r: Dictionary in _client.impacts("arrow"):
		client_lead += 1 if bool(r["lead"]) else 0
	assert_gt(host_lead, 100, "the host drives the arrows for most of the wave")
	assert_eq(client_lead, 0, "the client drives another station")


func test_a_client_hears_every_arrow_the_host_hears_a_moment_later() -> void:
	_session(SECONDS, 2)
	var r := _compare_arrows()
	assert_gt(int(r["whole"]), 40, "volleys counted whole: %s" % [r])
	assert_gt(int(r["landings"]), 500)
	assert_gte(float(r["same"]) / float(r["landings"]), 0.95, "same surface: %s" % [r])
	var slack := maxi(3, int(r["struck_host"]) / 5)
	assert_lte(
		absi(int(r["struck_host"]) - int(r["struck_client"])), slack, "bodies struck: %s" % [r]
	)
	_assert_a_voice_for_every_arrow()
	_assert_the_other_weapons_match()
	_assert_whose_volleys_are_whose()
