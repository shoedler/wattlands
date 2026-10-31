extends SiegeV2Demo
## The frame of Castellum Rotae's picker card (tools/picker_cards): the demo's mock pose, every
## treadwheel routed, with no tar poured, so the arch and the bridge read.


func pose_as_mock() -> void:
	super()
	machines.curtain_stage = 0
	machines.coat_stage = 0
	machines.rebuild()
