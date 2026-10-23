class_name SiegeViewUtil
extends RefCounted
## Helpers for the view tests: a SiegeView built headless from a fixture state.


## A view bound to `state` and added under `parent`, with the rig's push-in finished and every
## automatic process turned off, then refreshed once.
static func make_view(parent: Node, state: SiegeState) -> SiegeView:
	var view := SiegeView.new()
	view.auto_process = false
	view.bind(state, state.content.map)
	parent.add_child(view)
	view.rig.auto_process = false
	view.rig.push_in(1.0, 0.0)
	view.refresh(0.05)
	return view


## Advances the state one tick and the view `frames` frames of 1/60 s.
static func run(view: SiegeView, frames: int, ticks: int = 1) -> void:
	view.state.tick += ticks
	for i in frames:
		view.refresh(1.0 / 60.0)
