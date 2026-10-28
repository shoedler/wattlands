class_name TankHudSeatPicker
extends RefCounted
## The local rider's seat picker (v3 brief "Seat choice and switching"; the seat panel shows its
## highlight). TankGame.local_intents() hands it the local rider's actions every tick before its own
## mapping (feed()); it turns them into the seat intent and names the actions it used, so a confirm
## that sits never also fires, latches or turns. It keeps only this peer's local UI state; it never
## writes the game state.
##
## Keys, only while the rider's seat lock is open (seat_lock_s 0), no move is pending (seat_target
## "") and outside the cool-down:
##  - left / right open the picker on the nearest empty seat that way (TankIds.SEATS order,
##    wrapping) and then step it through the empty seats; on the Gun, left / right keep cycling
##    targets (LR_OPENS), so the gunner opens the picker with swap (which opens it on every seat);
##  - confirm while it is open sends {"k": "seat", "to": <the picked seat>} and closes it;
##  - back closes it;
## and it closes by itself after IDLE_S without a key, or once nothing can be picked any more (the
## lock closed, a move is pending, the picked seat filled). Autopilot riders and bots get no picker:
## the automatic seating places them.

## The picker closes after this long without a key (s).
const IDLE_S := 6.0
## The tick the module calls feed() on (the platform's fixed step).
const DT := 0.05
## Seats whose left / right open the picker (the Gun's cycle targets: it opens with swap).
const LR_OPENS := {
	TankIds.ENGINE_DIESEL: true,
	TankIds.ENGINE_DYNAMO: false,
	TankIds.ENGINE_STEAM: true,
	TankIds.ENGINE_ARC: true,
	TankIds.ENGINE_FEED: true,
}
const OPEN_KEY := &"swap"

## The seat highlighted ("" while the picker is closed).
var pick: String = ""
## Seconds since the last key while open.
var idle_s: float = 0.0


## True while the picker is open.
func is_open() -> bool:
	return pick != ""


## True when `r` may pick a seat now: a human (no Autopilot, no bot) whose lock is open, with no
## move pending, outside the cool-down, and an empty seat to go to.
static func usable(state: TankState, r: TankRiderState) -> bool:
	if state == null or r == null or r.autopilot or r.is_bot or r.engine == "":
		return false
	if r.seat_lock_s > 0.0 or r.seat_target != "" or state.in_cooldown():
		return false
	return not empty_seats(state, r).is_empty()


## The empty seats `r` could move to, in TankIds.SEATS order.
static func empty_seats(state: TankState, r: TankRiderState) -> Array[String]:
	var out: Array[String] = []
	for engine in TankIds.SEATS:
		var st := state.station(engine)
		if engine != r.engine and st != null and st.is_empty() and not _claimed(state, engine, r):
			out.append(engine)
	return out


## True when another rider is already moving into `engine`.
static func _claimed(state: TankState, engine: String, r: TankRiderState) -> bool:
	for o in state.riders:
		if o != r and o.seat_target == engine:
			return true
	return false


## The next empty seat `dir` (+1 right, -1 left) from `from` in TankIds.SEATS order, wrapping;
## "" when there is none.
static func next_empty(state: TankState, r: TankRiderState, from: String, dir: int) -> String:
	var free := empty_seats(state, r)
	if free.is_empty():
		return ""
	var at := TankIds.SEATS.find(from)
	for i in range(1, TankIds.SEATS.size() + 1):
		var cand := TankIds.SEATS[posmod(at + dir * i, TankIds.SEATS.size())]
		if free.has(cand):
			return cand
	return ""


## Feeds this tick's `actions` of the local rider `r`: {"intents": the seat intent or nothing,
## "taken": the actions the picker used (the module drops them from its own mapping)}.
func feed(state: TankState, r: TankRiderState, actions: Array[StringName]) -> Dictionary:
	var taken: Array[StringName] = []
	var out := {"intents": [], "taken": taken}
	if not usable(state, r):
		close()
		return out
	var dir := 0
	if actions.has(&"left"):
		dir = -1
	elif actions.has(&"right"):
		dir = 1
	var lr := is_open() or bool(LR_OPENS.get(r.engine, true))
	if not is_open():
		if actions.has(OPEN_KEY):
			taken.append(OPEN_KEY)
			pick = next_empty(state, r, r.engine, 1 if dir == 0 else dir)
			idle_s = 0.0
			return out
		if dir != 0 and lr:
			taken.append(&"left" if dir < 0 else &"right")
			pick = next_empty(state, r, r.engine, dir)
			idle_s = 0.0
		return out
	if not empty_seats(state, r).has(pick):
		pick = next_empty(state, r, pick, 1)
	if dir != 0:
		taken.append(&"left" if dir < 0 else &"right")
		pick = next_empty(state, r, pick, dir)
		idle_s = 0.0
	if actions.has(OPEN_KEY):
		taken.append(OPEN_KEY)
		pick = next_empty(state, r, pick, 1)
		idle_s = 0.0
	if actions.has(&"back"):
		taken.append(&"back")
		close()
		return out
	if actions.has(&"confirm") and pick != "":
		taken.append(&"confirm")
		(out["intents"] as Array).append(TankIntents.seat(pick))
		close()
		return out
	idle_s += DT
	if idle_s >= IDLE_S:
		close()
	return out


func close() -> void:
	pick = ""
	idle_s = 0.0


## `actions` without the ones in `taken` (order kept).
static func without(actions: Array[StringName], taken: Array[StringName]) -> Array[StringName]:
	var out: Array[StringName] = []
	for a in actions:
		if not taken.has(a):
			out.append(a)
	return out
