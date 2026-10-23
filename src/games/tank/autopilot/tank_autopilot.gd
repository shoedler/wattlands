class_name TankAutopilot
extends RefCounted
## Autopilot (brief 2.5): the game choices a bot, an Autopilot human or a human still on the
## fallback makes. Owner: module.
##
## The defaults already play every station with no input (the diesel drives on watts and digs in,
## auto-aim aims and fires, the boiler latches a heavy shell at 100%, the auto-lever runs the
## Bulwark); intents() adds only rear traverses and obstacle shots when no enemy is in range. It
## never latches early, never moves the lever by hand, never Rams, dodges or Overpressures and
## never changes effort (BRIEF 3.5). Every intent it returns is tagged "auto": 1
## (TankIntents.auto) so it never ends a human's fallback.
##
## G0 stub: returns no intents (the rules' defaults play on their own). G1 (module) fills it.


## This tick's Autopilot intents for the rider `peer` (wire form, before normalize()).
static func intents(_state: TankState, _peer: int) -> Array:
	return []
