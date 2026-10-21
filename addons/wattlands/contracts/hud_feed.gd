class_name HudFeed
extends RefCounted
## How a game feeds the HUD kit (`ctx.hud`, BRIEF 3.6). Contract, frozen after W0; the
## ui-hud and sdk-runtime agents implement it.
##
## Calls made on the host or in SOLO are routed: power_band goes to that rider's peer as
## a 5.5 `directive` of kind `power_band` (its power gauge and MockTrainer use it; 0, 0
## clears it), teammate_status reaches every peer through the roster, and toast and banner
## reach the peers they name (`peer` = Wl.ALL_PEERS for every rider). A call made on a
## CLIENT draws only on that client's HUD. Keys are string-table keys (the game's
## strings.csv); `args` (Array or Dictionary) fill {0}/{name} placeholders.


## The power gauge's target band for `peer` in SIM phases (in ERG it shows the applied
## target). lo_w = hi_w = 0 clears it.
func power_band(_peer: int, _lo_w: float, _hi_w: float) -> void:
	pass


## A rider's status chip in the teammate strip: {"in_band": bool, "icon": String,
## "text": String}. Reaches every peer through the roster (2 Hz).
func teammate_status(_peer: int, _status: Dictionary) -> void:
	pass


## Short message. peer = Wl.ALL_PEERS (0) for every rider.
func toast(_key: String, _args: Variant = [], _peer: int = 0) -> void:
	pass


## Large message for `seconds`. peer = Wl.ALL_PEERS (0) for every rider.
func banner(_key: String, _args: Variant = [], _seconds: float = 3.0, _peer: int = 0) -> void:
	pass


## Local only: the text of a custom big readout declared in hud_spec() with
## {"source": "custom", "id": id}. Never routed over the network.
func readout(_id: String, _text: String) -> void:
	pass
