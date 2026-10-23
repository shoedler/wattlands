class_name TankStationState
extends TankRecord
## One engine room (G0 contract): what every station has in common. Subclasses add each
## engine's own model: TankDieselState, TankDynamoState, TankSteamState, TankGearboxState (the
## Bulwark). TankState.stations lists the tank's rooms rear to front (tanks.json engines).
## Which rider works a room changes at checkpoints with rotation; a room without a connected,
## pedalling rider runs on reserve (brief 2.2).

## [snap] TankIds.ENGINE_*.
var engine: String = ""
## [snap] The slot index of the rider on this station this segment; -1 none.
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
		TankIds.ENGINE_BULWARK:
			s = TankGearboxState.new()
		_:
			s = TankStationState.new()
	s.engine = p_engine
	return s
