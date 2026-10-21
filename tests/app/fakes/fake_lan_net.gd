extends "res://tests/app/fakes/fake_net.gd"
## FakeNet plus the LAN discovery API the app shell asks net-client for (P1, BRIEF 5.4):
## lan_rooms() -> [{code, name, game_id, address}], signal lan_rooms_changed (inherited from
## WlNetSession), join_lan(room).

var rooms: Array[Dictionary] = []
var lan_joins: Array = []


func lan_rooms() -> Array[Dictionary]:
	return rooms.duplicate(true)


func join_lan(room: Dictionary) -> void:
	lan_joins.append(room.duplicate(true))
	record("join_lan", [str(room.get("code", ""))])


func announce(new_rooms: Array) -> void:
	rooms.assign(new_rooms)
	lan_rooms_changed.emit(rooms)
