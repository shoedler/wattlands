class_name WlRides
extends Node
## Autoload `Rides` (BRIEF 3.8): creates ride recorders, keeps the Strava connection and the
## upload queue (Paths.upload_queue_path(), retried on the next launch). Owned by rides;
## public API frozen after W0. Secrets and tokens live only in strava.json and never reach
## logs, telemetry, the relay, crash reports or git.
## Network lock (BRIEF 1): while WATTLANDS_NO_NETWORK_INTEGRATIONS=1 the Strava client talks
## only to 127.0.0.1/localhost, never opens a browser, and logs "network integrations locked".
## --strava-base=<url> points both the API and OAuth bases at a mock.
##
## Upload states go to EventBus.upload_state_changed(ride_id, state, detail): "queued" (not
## connected yet; uploads after connect), "uploading", "processing", then "uploaded"
## (detail: the activity id), "duplicate" (counts as uploaded; detail: the activity id if
## known), "offline" (network down; kept in the queue however often it happens) or "failed"
## (detail: the reason; kept in the queue unless retrying can't help or it failed
## UploadQueue.MAX_ATTEMPTS times; offline attempts don't count). Connection states go to
## EventBus.strava_state_changed. A ride's summary JSON records its upload under "upload".
##
## Start-up (unless auto_start is false): loads strava.json and the queue; with
## --strava-client-id=<id> and --strava-client-secret=<secret> it connects through the
## loopback flow (scripted peers, e2e); once connected it retries the queue.
## Auto-upload (profile strava_auto_upload or --strava-auto-upload): every
## EventBus.ride_saved is uploaded without a prompt (queued until connected).
## (W4, RS-2) An upload is in rides/upload_queue.json from before its first request until it
## settles (last_state "uploading", the upload id stored as soon as Strava names it), so one cut
## short by the app quitting (a slow POST, a 429 backoff, processing polls) is retried, or
## polled, at the next launch. Strava's external_id (the ride id) makes a re-send a duplicate,
## which counts as uploaded.
## Every public Strava method is a coroutine; callers may await it.

## Emitted when an upload attempt reached its final state for now (tests, e2e report).
signal upload_finished(ride_id: String, state: String, detail: String)

## The ranges strava_import_athlete() accepts (W4r2, PROF): the profile editor's own (the FTP
## field 50-600 W, AppStyle.WEIGHT_MIN_KG..WEIGHT_MAX_KG 30-200 kg), so an import never sets
## what the rider couldn't type. A value outside is refused, not clamped.
const IMPORT_FTP_MIN_W := 50.0
const IMPORT_FTP_MAX_W := 600.0
const IMPORT_WEIGHT_MIN_KG := 30.0
const IMPORT_WEIGHT_MAX_KG := 200.0

## The summary keys the Strava name and description read besides the recorder's totals.
const RIDE_TEXT_KEYS: Array[String] = ["game_title", "content_title", "ride_tag", "ride_lines"]

## The Strava client (a child node).
var client: StravaClient = null
## The upload queue (rides/upload_queue.json).
var queue: UploadQueue = UploadQueue.new()
## The EventBus to report on (default: the EventBus autoload). Tests inject a private bus.
var events: WlEventBus = null
## Run the start-up work (cmdline connect, queue retry) when entering the tree.
var auto_start: bool = true
## Overrides auto_upload_enabled() when not null (tests).
var auto_upload_override: Variant = null

var _bases_pinned: bool = false
## The session's results until its ride is saved (the GameHost emits results_ready, then
## ride_saved): the game's ride_tag and ride_lines go into that ride's summary.
var _results: GameResults = null
var _in_flight: Dictionary = {}
var _queue_running: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if client == null:
		client = StravaClient.new()
		client.name = "StravaClient"
		add_child(client)
	if events == null:
		events = get_node_or_null("/root/EventBus") as WlEventBus
	if not client.state_changed.is_connected(_on_strava_state):
		client.state_changed.connect(_on_strava_state)
	if not client.upload_progress.is_connected(_on_upload_progress):
		client.upload_progress.connect(_on_upload_progress)
	if not client.upload_created.is_connected(_on_upload_created):
		client.upload_created.connect(_on_upload_created)
	if events != null and not events.ride_saved.is_connected(on_ride_saved):
		events.ride_saved.connect(on_ride_saved)
	if events != null and not events.results_ready.is_connected(_on_results_ready):
		events.results_ready.connect(_on_results_ready)
	reload()
	if auto_start:
		_startup.call_deferred()


## Re-reads strava.json and the upload queue (after a Paths override change).
func reload() -> void:
	_resolve_bases()
	client.load_store()
	queue.load_file()


## A new recorder for the local rider (RideRecorder).
func new_recorder() -> RideRecorderApi:
	var r := RideRecorder.new()
	var tz: Dictionary = Time.get_time_zone_from_system()
	r.utc_offset_s = int(tz.get("bias", 0)) * 60
	return r


## True once Strava tokens exist.
func strava_connected() -> bool:
	return client != null and client.has_tokens()


## Start the OAuth connect flow with the player's own API app credentials.
func strava_connect(client_id: String, client_secret: String) -> void:
	await _connect(client_id, client_secret, false)


func strava_disconnect() -> void:
	_resolve_bases()
	await client.disconnect_account()


## Upload a saved ride (FIT path + summary); queues it when offline or on failure.
## Progress arrives on EventBus.upload_state_changed(ride_id, state, detail).
## A summary without ride_id uses the JSON saved next to the FIT. A ride already on Strava
## is not sent again; its state ("uploaded" or "duplicate") is reported once more.
func upload(fit_path: String, summary: Dictionary) -> void:
	await _upload(fit_path, summary, false)


## Retry queued uploads (called at launch and after connect).
func process_queue() -> void:
	if _queue_running or not strava_connected():
		return
	_queue_running = true
	_resolve_bases()
	for ride_id in queue.ride_ids():
		var e := queue.get_entry(ride_id)
		if e.is_empty():
			continue
		var fit_path := str(e["fit_path"])
		if not FileAccess.file_exists(fit_path):
			push_warning("Rides: queued ride %s has no FIT file any more; dropped" % ride_id)
			queue.remove(ride_id)
			continue
		var summary := _read_summary(fit_path)
		if summary.is_empty():
			summary = {"ride_id": ride_id}
		await _upload(fit_path, summary, true)
		if not strava_connected():
			break
	_queue_running = false


func auto_upload_enabled() -> bool:
	if auto_upload_override != null:
		return bool(auto_upload_override)
	if CmdLine.get_bool("strava-auto-upload", false):
		return true
	var settings := get_node_or_null("/root/Settings") as WlSettings
	return settings != null and settings.profile != null and settings.profile.strava_auto_upload


## Saved rides, newest first: [{fit_path, summary, uploaded, activity_id}] (P1 history).
## Each entry also has "state" (the upload state, "queued" while in the queue, else "").
func rides() -> Array:
	var out: Array = []
	var dir := Paths.rides_dir()
	var queue_file := Paths.upload_queue_path().get_file()
	for f in DirAccess.get_files_at(dir):
		if f.get_extension().to_lower() != "json" or f == queue_file:
			continue
		var p := dir.path_join(f)
		var parsed: Variant = StravaClient.parse_json(FileAccess.get_file_as_string(p))
		if not (parsed is Dictionary) or not (parsed as Dictionary).has("ride_id"):
			continue
		var s: Dictionary = parsed
		var up: Dictionary = s["upload"] if s.get("upload", null) is Dictionary else {}
		var state := str(up.get("state", ""))
		if _in_flight.has(str(s["ride_id"])):
			state = "uploading"
		elif queue.has(str(s["ride_id"])):
			state = "queued"
		(
			out
			. append(
				{
					"fit_path": p.get_basename() + ".fit",
					"summary": s,
					"uploaded": state == "uploaded" or state == "duplicate",
					"activity_id": int(up.get("activity_id", 0)),
					"state": state,
				}
			)
		)
	out.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var ta := int((a["summary"] as Dictionary).get("utc_start_unix", 0))
			var tb := int((b["summary"] as Dictionary).get("utc_start_unix", 0))
			if ta != tb:
				return ta > tb
			return str(a["fit_path"]) > str(b["fit_path"])
	)
	return out


# --- Additive API --------------------------------------------------------------------


## Saves the recorder's ride (FIT + JSON) into `dir` (default Paths.rides_dir()) and emits
## ride_saved on the EventBus, which auto-uploads when enabled. Returns the FIT path or "".
func save_ride(recorder: RideRecorderApi, dir: String = "") -> String:
	var path := recorder.save(dir)
	if path != "" and events != null:
		events.ride_saved.emit(path, recorder.summary())
	return path


## EventBus.ride_saved handler: auto-upload (queued until connected) when enabled.
func on_ride_saved(fit_path: String, summary: Dictionary) -> void:
	var sum := _stamp_ride_text(fit_path, summary)
	if not auto_upload_enabled():
		return
	await upload(fit_path, sum)


## Re-upload a ride from the history by id (P1), even if it was marked uploaded (Strava
## then reports a duplicate, which counts as uploaded).
func reupload(ride_id: String) -> void:
	for r: Dictionary in rides():
		if str((r["summary"] as Dictionary).get("ride_id", "")) == ride_id:
			await _upload(str(r["fit_path"]), r["summary"], true)
			return
	push_warning("Rides: no saved ride %s" % ride_id)


## Cancels a running Strava connect (its loopback callback waits up to 5 minutes, BRIEF 3.8);
## it ends with strava state "error"/"cancelled". For a Cancel control while the strava state
## is "connecting" (the Settings page has none yet).
func strava_cancel_connect() -> void:
	if client != null:
		client.cancel_connect()


## True while uploads (or a queue run) are in progress, or while a connect is running that
## will retry a non-empty queue when it succeeds.
func uploads_busy() -> bool:
	if not _in_flight.is_empty() or _queue_running:
		return true
	return client != null and client.is_connecting() and queue.size() > 0


## Waits until no upload or queue run is in progress (scripted peers before they quit).
func wait_uploads_idle() -> void:
	while uploads_busy() and is_inside_tree():
		await get_tree().process_frame


## Connect with profile:read_all as well, for the FTP and weight import (P1).
func strava_connect_with_profile(client_id: String, client_secret: String) -> void:
	await _connect(client_id, client_secret, true)


## Opt-in import of FTP and weight from GET /athlete (P1, needs profile:read_all). Applies
## the chosen values to `profile` (FTP also sets cp_w and ftp_verified) and returns
## {ftp, weight, applied: [...]}, or {} when Strava gave nothing. The caller saves the
## profile.
## (W4r2) A chosen value outside the profile editor's range (IMPORT_FTP_MIN_W..MAX_W,
## IMPORT_WEIGHT_MIN_KG..MAX_KG) is refused with push_warning: it is not applied (an FTP typo on
## Strava must not become a verified FTP) and is listed in the additive `refused`:
## [{field ("ftp" or "weight"), value, min, max}].
func strava_import_athlete(
	profile: RiderProfile, import_ftp: bool, import_weight: bool
) -> Dictionary:
	if not strava_connected():
		return {}
	_resolve_bases()
	var a := await client.fetch_athlete()
	if a.is_empty():
		return {}
	var ftp := float(a["ftp"]) if a.get("ftp", null) != null else 0.0
	var weight := float(a["weight"]) if a.get("weight", null) != null else 0.0
	var applied: Array = []
	var refused: Array = []
	if import_ftp and ftp > 0.0:
		if _import_ok(refused, "ftp", ftp, IMPORT_FTP_MIN_W, IMPORT_FTP_MAX_W):
			profile.ftp_w = ftp
			profile.cp_w = ftp
			profile.ftp_verified = true
			applied.append("ftp")
	if import_weight and weight > 0.0:
		if _import_ok(refused, "weight", weight, IMPORT_WEIGHT_MIN_KG, IMPORT_WEIGHT_MAX_KG):
			profile.weight_kg = weight
			applied.append("weight")
	return {"ftp": ftp, "weight": weight, "applied": applied, "refused": refused}


## True when `value` is a finite number within [lo, hi]; otherwise records the refusal.
func _import_ok(refused: Array, field: String, value: float, lo: float, hi: float) -> bool:
	if is_finite(value) and value >= lo and value <= hi:
		return true
	push_warning(
		"Rides: Strava %s %s is outside %s-%s; not imported" % [field, str(value), str(lo), str(hi)]
	)
	refused.append({"field": field, "value": value, "min": lo, "max": hi})
	return false


func strava_state() -> String:
	return client.state() if client != null else StravaClient.STATE_DISCONNECTED


## Public connection facts (never the secret or tokens).
func strava_info() -> Dictionary:
	return client.info() if client != null else {}


func queue_size() -> int:
	return queue.size()


## Pins the API and OAuth bases (tests, harnesses), ignoring --strava-base and Settings.
func set_bases(api_base: String, oauth_base: String) -> void:
	client.api_base = api_base.trim_suffix("/")
	client.oauth_base = oauth_base.trim_suffix("/")
	_bases_pinned = true


## The Strava activity name for a ride summary: "WATTLANDS: <game title> - <ride tag>". The tag
## is the game's own (GameResults.ride_tag), else the content title; with neither, no " - ".
static func activity_name(summary: Dictionary) -> String:
	var game := str(summary.get("game_title", ""))
	if game == "":
		game = str(summary.get("game_id", "ride")).capitalize()
	var tag := str(summary.get("ride_tag", ""))
	if tag == "":
		tag = str(summary.get("content_title", ""))
	if tag == "":
		return _t("RIDES_ACTIVITY_NAME").format({"game": game})
	return _t("RIDES_ACTIVITY_NAME_TAG").format({"game": game, "tag": tag})


## The Strava description: the game's stat lines (GameResults.ride_lines), then moving time,
## distance, average and normalized power, average cadence and work, and "Recorded with
## WATTLANDS" last. No heart rate.
static func activity_description(summary: Dictionary) -> String:
	var lines: Array[String] = []
	var game_lines: Variant = summary.get("ride_lines", [])
	if game_lines is Array:
		for l: Variant in game_lines:
			if str(l) != "":
				lines.append(str(l))
	var timer_s := float(summary.get("timer_s", summary.get("duration_s", 0.0)))
	lines.append(_t("RIDES_DESC_MOVING").format([_clock_text(timer_s)]))
	var dist_m := float(summary.get("distance_m", 0.0))
	if dist_m > 0.0:
		lines.append(_t("RIDES_DESC_DISTANCE").format(["%.1f" % (dist_m / 1000.0)]))
	lines.append(
		_t("RIDES_DESC_AVG_POWER").format([roundi(float(summary.get("avg_power_w", 0.0)))])
	)
	var np_w := float(summary.get("np_w", 0.0))
	if np_w > 0.0:
		lines.append(_t("RIDES_DESC_NP").format([roundi(np_w)]))
	var cad := float(summary.get("avg_cadence_rpm", -1.0))
	if cad > 0.0:
		lines.append(_t("RIDES_DESC_CADENCE").format([roundi(cad)]))
	lines.append(_t("RIDES_DESC_KJ").format([roundi(float(summary.get("kj", 0.0)))]))
	lines.append(_t("RIDES_DESC_FOOTER"))
	return "\n".join(lines)


# --- Internals -------------------------------------------------------------------------


func _on_results_ready(r: GameResults) -> void:
	_results = r


## Adds what the Strava text needs to the saved ride's summary and its JSON (so a later
## re-upload from the history reads it): the game's title, the content title, and the session's
## ride_tag and ride_lines (GameResults). Returns the summary with them.
func _stamp_ride_text(fit_path: String, summary: Dictionary) -> Dictionary:
	var out := summary.duplicate(true)
	var game_id := str(out.get("game_id", ""))
	var content_id := str(out.get("content_id", ""))
	var registry := get_node_or_null("/root/GameRegistry") as WlGameRegistry
	if registry != null and registry.has_game(game_id):
		out["game_title"] = str(registry.manifest(game_id).get("title", ""))
	out["content_title"] = content_title(game_id, content_id)
	if _results != null:
		out["ride_tag"] = _results.ride_tag
		out["ride_lines"] = _results.own_ride_lines()
		_results = null
	_merge_summary(fit_path, out)
	return out


## The content's display title: its "<GAME>_CONTENT_<ID>" string when one exists, a rider's own
## .zwo file's name, else "" (a bare content id is no title).
static func content_title(game_id: String, content_id: String) -> String:
	if content_id.begins_with("zwo:"):
		return content_id.substr(4).replace("\\", "/").get_file().get_basename()
	var key := "%s_CONTENT_%s" % [game_id.to_upper(), content_id.to_upper()]
	var t := String(TranslationServer.translate(key))
	return "" if t == key else t


## Writes `fields` into the saved summary JSON next to `fit_path` (keeps its other keys).
func _merge_summary(fit_path: String, fields: Dictionary) -> void:
	var s := _read_summary(fit_path)
	if s.is_empty():
		return
	for k: String in RIDE_TEXT_KEYS:
		if fields.has(k):
			s[k] = fields[k]
	var f := FileAccess.open(fit_path.get_basename() + ".json", FileAccess.WRITE)
	if f == null:
		push_warning("Rides: can't update %s" % fit_path.get_basename())
		return
	f.store_string(JSON.stringify(s, "  "))
	f.close()


func _startup() -> void:
	var cid := CmdLine.get_str("strava-client-id", "")
	var secret := CmdLine.get_str("strava-client-secret", "")
	if cid != "" and secret != "" and not strava_connected():
		await strava_connect(cid, secret)
	elif strava_connected() and queue.size() > 0:
		await process_queue()


func _connect(client_id: String, client_secret: String, with_profile: bool) -> void:
	_resolve_bases()
	var ok := await client.connect_account(client_id, client_secret, with_profile)
	if ok:
		await process_queue()


func _upload(fit_path: String, summary: Dictionary, force: bool) -> void:
	var sum := summary
	if str(sum.get("ride_id", "")) == "":
		# No ride id given (an empty or partial summary): use the saved one next to the FIT.
		sum = _read_summary(fit_path)
	var ride_id := str(sum.get("ride_id", ""))
	if ride_id == "":
		push_warning("Rides: a ride summary without ride_id can't be uploaded")
		return
	sum = sum.duplicate(true)
	var saved := _read_summary(fit_path)
	for k: String in RIDE_TEXT_KEYS:
		if saved.has(k):
			sum[k] = saved[k]
	if _in_flight.has(ride_id):
		# Already uploading (auto-upload and the results screen, say): wait for that one, so a
		# caller that awaits upload() still returns only once the ride is settled.
		while _in_flight.has(ride_id) and is_inside_tree():
			await get_tree().process_frame
		return
	if not force:
		var up: Variant = _read_summary(fit_path).get("upload", {})
		if (
			up is Dictionary
			and str((up as Dictionary).get("state", "")) in ["uploaded", "duplicate"]
		):
			# Already on Strava: report its state again (no new attempt), so a results screen that
			# asks after an auto-upload still shows it.
			var act := int((up as Dictionary).get("activity_id", 0))
			_emit_upload(ride_id, str((up as Dictionary)["state"]), str(act) if act > 0 else "")
			return
	_in_flight[ride_id] = true
	_resolve_bases()
	var entry := queue.get_entry(ride_id)
	var name := str(entry.get("name", ""))
	if name == "":
		name = activity_name(sum)
	var desc := str(entry.get("description", ""))
	if desc == "":
		desc = activity_description(sum)
	var res: Dictionary
	if strava_connected():
		# RS-2: in the queue before the first request, so a quit mid-upload leaves it there.
		(
			queue
			. put(
				{
					"ride_id": ride_id,
					"fit_path": fit_path,
					"name": name,
					"description": desc,
					"attempts": int(entry.get("attempts", 0)),
					"last_state": "uploading",
					"last_error": str(entry.get("last_error", "")),
					"upload_id": int(entry.get("upload_id", 0)),
				}
			)
		)
	if not strava_connected():
		res = {"state": "queued", "detail": "not_connected", "upload_id": 0, "permanent": false}
	elif int(entry.get("upload_id", 0)) > 0:
		res = await client.poll_upload(ride_id, int(entry["upload_id"]))
		if (
			str(res.get("state", "")) == "failed"
			and str(res.get("detail", "")) == "upload_not_found"
		):
			res = await client.upload_fit(ride_id, fit_path, name, desc)
	else:
		res = await client.upload_fit(ride_id, fit_path, name, desc)
	_apply_result(ride_id, fit_path, name, desc, res)
	_in_flight.erase(ride_id)


func _apply_result(
	ride_id: String, fit_path: String, name: String, desc: String, res: Dictionary
) -> void:
	var state := str(res.get("state", "failed"))
	var detail := str(res.get("detail", ""))
	match state:
		"uploaded", "duplicate":
			queue.remove(ride_id)
			var act := int(res.get("activity_id", 0))
			_mark_summary(
				fit_path,
				{"state": state, "activity_id": act, "upload_id": int(res.get("upload_id", 0))}
			)
			if act > 0:
				detail = str(act)
		_:
			var prev := queue.get_entry(ride_id)
			# BRIEF 3.8: an offline upload stays queued for the next launch. Only a real failure
			# (an error response, a processing error or timeout) counts toward MAX_ATTEMPTS.
			var counts := UploadQueue.counts_as_attempt(state)
			var attempts := int(prev.get("attempts", 0)) + (1 if counts else 0)
			if (
				bool(res.get("permanent", false))
				or (counts and attempts >= UploadQueue.MAX_ATTEMPTS)
			):
				queue.remove(ride_id)
				_mark_summary(fit_path, {"state": "failed", "error": detail})
			else:
				(
					queue
					. put(
						{
							"ride_id": ride_id,
							"fit_path": fit_path,
							"name": name,
							"description": desc,
							"attempts": attempts,
							"last_state": state,
							"last_error": detail,
							"upload_id": int(res.get("upload_id", 0)),
						}
					)
				)
	_emit_upload(ride_id, state, detail)
	upload_finished.emit(ride_id, state, detail)


func _mark_summary(fit_path: String, upload_info: Dictionary) -> void:
	var json_path := fit_path.get_basename() + ".json"
	var s := _read_summary(fit_path)
	if s.is_empty():
		return
	s["upload"] = upload_info
	var f := FileAccess.open(json_path, FileAccess.WRITE)
	if f == null:
		push_warning("Rides: can't update %s" % json_path)
		return
	f.store_string(JSON.stringify(s, "  "))
	f.close()


func _read_summary(fit_path: String) -> Dictionary:
	var json_path := fit_path.get_basename() + ".json"
	if not FileAccess.file_exists(json_path):
		return {}
	var parsed: Variant = StravaClient.parse_json(FileAccess.get_file_as_string(json_path))
	return parsed if parsed is Dictionary else {}


func _resolve_bases() -> void:
	if _bases_pinned or client == null:
		return
	var root := CmdLine.get_str("strava-base", "")
	if root != "":
		var b := StravaClient.bases_from_root(root)
		client.api_base = str(b["api"])
		client.oauth_base = str(b["oauth"])
		return
	var settings := get_node_or_null("/root/Settings") as WlSettings
	if settings != null:
		client.api_base = settings.strava_api_base().trim_suffix("/")
		client.oauth_base = settings.strava_oauth_base().trim_suffix("/")


func _on_strava_state(state: String, detail: String) -> void:
	if events != null:
		events.strava_state_changed.emit(state, detail)


func _on_upload_progress(ride_id: String, state: String, detail: String) -> void:
	_emit_upload(ride_id, state, detail)


## RS-2: keep the upload id with the queued ride as soon as Strava names it.
func _on_upload_created(ride_id: String, upload_id: int) -> void:
	var e := queue.get_entry(ride_id)
	if e.is_empty() or upload_id <= 0:
		return
	e["upload_id"] = upload_id
	e["last_state"] = "processing"
	queue.put(e)


func _emit_upload(ride_id: String, state: String, detail: String) -> void:
	if events != null:
		events.upload_state_changed.emit(ride_id, state, detail)


static func _t(key: String) -> String:
	return String(TranslationServer.translate(key))


## h:mm:ss, or m:ss under an hour.
static func _clock_text(seconds: float) -> String:
	var total := maxi(roundi(seconds), 0)
	var h := total / 3600
	var m := (total % 3600) / 60
	var sec := total % 60
	return "%d:%02d:%02d" % [h, m, sec] if h > 0 else "%d:%02d" % [m, sec]
