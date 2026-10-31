class_name TankBots
extends RefCounted
## v4: the bots' seat choices (stub until builder E, SPEC_TANK 3.7): a bot stays on its seat, asks
## for nothing, and when evicted takes the first empty seat.


static func seat_wanted(_state: TankState, rider: TankRiderState) -> String:
	return rider.engine


static func intent(_state: TankState, _rider: TankRiderState) -> Dictionary:
	return {}


static func next_seat(state: TankState, _bot: TankRiderState) -> String:
	var empty := TankSeats.empty_seats(state)
	return empty[0] if not empty.is_empty() else ""
