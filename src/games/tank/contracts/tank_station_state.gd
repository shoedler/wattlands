class_name TankStationState
extends TankRecord
## One engine room, v3: one seat (G0 contract): what every station has in common. Subclasses add
## each engine's own model: TankDieselState (Drive), TankDynamoState (Gun), TankSteamState
## (Loader), TankArcState (Lights) and TankFeedState (v3, Secondaries). TankState.stations lists
## the tank's rooms rear to front (tanks.json engines: diesel, steam, dynamo, arc, feed).
## v3: the tank has five seats and at most four riders, so at least one seat is always empty
## (`slot` -1, is_empty()); a rider moves seats with the seat intent (TankRiderState.engine,
## seat_target, seat_lock_s). A manned room whose rider is dropped or AFK runs on reserve (brief
## 2.2).

## [snap] TankIds.ENGINE_*.
var engine: String = ""
## [snap] The slot index of the rider on this seat; -1 when the seat is empty (the snapshot's st
## row carries -1).
var slot: int = -1
var peer: int = 0
## This tick's P_eff driving the room (the reserve's reserve_p_eff_w when on reserve; 0 when
## nothing has power: every rider AFK, a gearbox move, or the station's rescue rule).
var p_eff_w: float = 0.0
## [snap] The rider is in band by the engine's rule (brief 2.3 "In band"); never on reserve.
var in_band: bool = false
## [snap] The rider is dropped or AFK: the room runs as if P_eff 60 W under Autopilot.
var reserve: bool = false
## The room gets no power this tick.
var unpowered: bool = false


## A fresh station for `p_engine`, of the right subclass.
static func make(p_engine: String) -> TankStationState:
	var s: TankStationState
	match p_engine:
		TankIds.ENGINE_DIESEL:
			s = TankDieselState.new()
		TankIds.ENGINE_DYNAMO:
			s = TankDynamoState.new()
		TankIds.ENGINE_STEAM:
			s = TankSteamState.new()
		TankIds.ENGINE_ARC:
			s = TankArcState.new()
		TankIds.ENGINE_FEED:
			s = TankFeedState.new()
		_:
			s = TankStationState.new()
	s.engine = p_engine
	return s


## v3: true while nobody sits on this seat (slot -1).
func is_empty() -> bool:
	return slot < 0
