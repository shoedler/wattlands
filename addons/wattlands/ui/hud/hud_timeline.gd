class_name HudTimeline
extends HudWidget
## Kit widget `timeline` (BRIEF 3.9; HudSpec.TIMELINE): the current phase's label and time,
## a block strip of the local rider's plan with a progress marker, and a preview of the next
## phase. Labels go through the string table (plain text passes through). Fixed phases show
## the time left; open-ended phases show the time elapsed and their min_s-max_s range, and
## take their nominal duration_s (or the middle of min_s-max_s when it is 0) as their block
## width. base_size 640 x 150; min_rect 380 x 100.

var _phase_text: String = ""
var _time_text: String = ""
var _range_text: String = ""
var _next_text: String = ""

var _label: Label = null
var _time: Label = null
var _range: Label = null
var _strip: HudPhaseStrip = null
var _next: Label = null


func _init() -> void:
	_ensure_base()
	widget_id = HudSpec.TIMELINE
	var top := _hbox("Top", 12)
	_content.add_child(top)
	_label = _make_label("Phase", WlTheme.BODY_PX, WlTheme.TEXT, false, true)
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(_label)
	_range = _make_label("Range", WlTheme.SMALL_PX, WlTheme.TEXT_DIM)
	top.add_child(_range)
	_range.visible = false
	_time = _make_label("Time", 40, WlTheme.TEXT, false, true)
	_time.text = "0:00"
	top.add_child(_time)
	_strip = HudPhaseStrip.new()
	_strip.name = "Strip"
	_content.add_child(_strip)
	_scale_box(_strip, 0.0, 40.0)
	_next = _make_label("Next", WlTheme.LABEL_PX, WlTheme.TEXT_DIM)
	_next.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_next.visible = false
	_content.add_child(_next)
	set_ui_scale(1.0)


func base_size() -> Vector2:
	return Vector2(640, 150)


func min_rect() -> Vector2:
	return Vector2(380, 100)


func set_phase(phase: PhaseState, plan: EffortPlan) -> void:
	if phase == null:
		return
	var p: PlanPhase = plan.phase(phase.index) if plan != null else null
	var label := phase.label
	if label.is_empty() and p != null:
		label = p.label
	_phase_text = _t(label) if not label.is_empty() else _t("UI_KIND_" + phase.kind)
	if phase.open_ended:
		_time_text = clock_text(phase.elapsed_s)
		_range_text = _t("UI_HUD_OPEN_RANGE", [clock_text(phase.min_s), clock_text(phase.max_s)])
	else:
		_time_text = clock_text(phase.remaining_s)
		_range_text = ""
	_next_text = _preview(plan.phase(phase.index + 1) if plan != null else null, plan != null)
	var blocks: Array[Dictionary] = []
	var progress := 0.0
	if plan != null and plan.size() > 0:
		for pp in plan.phases:
			blocks.append({"len": block_length(pp), "kind": pp.kind, "mode": pp.mode, "pct": pp.peak_pct()})
	else:
		blocks.append({"len": maxf(1.0, phase.duration_s), "kind": phase.kind, "mode": phase.mode, "pct": phase.planned_pct})
	var cur := clampi(phase.index, 0, blocks.size() - 1) if plan != null else 0
	var cur_len := float(blocks[cur]["len"])
	if cur_len > 0.0:
		progress = phase.elapsed_s / cur_len
	_strip.set_blocks(blocks, cur, progress)
	_label.text = _phase_text
	_time.text = _time_text
	_range.text = _range_text
	_range.visible = not _range_text.is_empty()
	_next.text = _next_text
	_next.visible = not _next_text.is_empty()


## The width a phase takes on the strip, in seconds.
static func block_length(p: PlanPhase) -> float:
	if p.duration_s > 0.0:
		return p.duration_s
	if p.open_ended:
		return maxf(1.0, (p.min_s + p.max_s) * 0.5)
	return 1.0


func phase_text() -> String:
	return _phase_text


func time_text() -> String:
	return _time_text


func range_text() -> String:
	return _range_text


func next_text() -> String:
	return _next_text


func strip() -> HudPhaseStrip:
	return _strip


func _preview(p: PlanPhase, have_plan: bool) -> String:
	if p == null:
		return _t("UI_HUD_LAST_PHASE") if have_plan else ""
	var label := _t(p.label) if not p.label.is_empty() else _t("UI_KIND_" + p.kind)
	var dur := clock_text(p.duration_s)
	if p.open_ended:
		dur = _t("UI_HUD_OPEN_RANGE", [clock_text(p.min_s), clock_text(p.max_s)])
	if p.mode == Wl.SIM:
		return _t("UI_HUD_NEXT_SIM", [label, dur])
	if p.has_ramp():
		return _t("UI_HUD_NEXT_RAMP", [label, roundi(p.target_pct), roundi(p.ramp_to_pct), dur])
	return _t("UI_HUD_NEXT_ERG", [label, roundi(p.target_pct), dur])
