class_name SiegeV2Machines
extends SiegeDepthBatch
## Every machine of the fort from plain values, in one depth-tested batch: the four rotae
## turning (rider hue, or timber for an empty slot) with their walkers and output shafts, the
## junction's powered routes and station shafts, the five stations at their yaw and animation
## phase, the tar works, the gate's damage stage, the curtain and coat, and the four pads.
## Set the values with the set_* calls (phase B maps SiegeState onto them), then rebuild().
## Station ids as SiegeIds: 0 mine, 1 ballista, 2 onager, 3 arrows, 4 tar works.

const STATIONS := 5
const SLOTS := 4
const PADS := 4
## Draw layers (sort key = layer * LAYER + depth): ground rings and the coat first, then the
## wheels, their walkers, the junction (routes, station shafts), the wheels' output shafts that
## bridge over the lanes, and the stations.
const LAYER := 10000.0
const L_GROUND := 0
const L_WHEEL := 1
const L_WALKER := 2
const L_JUNCTION := 3
const L_OUTPUT := 4
const L_STATION := 5
const YAWS := 16

## Per slot: wheel angle (deg), whether a rider stands in the slot, walkers 0..3, walk phase.
var wheel_deg := PackedFloat32Array([0, 0, 0, 0])
var wheel_rider := PackedInt32Array([0, 0, 0, 0])
var walkers := PackedInt32Array([0, 0, 0, 0])
var walk_phase := PackedFloat32Array([0, 0, 0, 0])
## Per slot: whether its walkers stumble (the rider is in rescue) and how far they have sunk (0..1).
var stumble: Array[bool] = [false, false, false, false]
var stumble_dip := PackedFloat32Array([0, 0, 0, 0])
## How far (m) a stumbling walker sinks to its knees.
const STUMBLE_DROP_M := 0.7
## Per slot: the station its route is lit to (-1 none).
var route := PackedInt32Array([-1, -1, -1, -1])
## Per station: yaw (deg, atan2(dy, dx)) and the animation phase `arm` 0..1 (STATE_V2.md).
var station_yaw := PackedFloat32Array([0, 114, 135, 143, 0])
var station_arm := PackedFloat32Array([1, 1, 1, 1, 0])
## The arrow organ's loaded racks (bit k = rack k), the mine's and the pump's cycle phase 0..1.
var racks: int = 7
var mine_phase: float = 0.0
var pump_phase: float = 0.0
## Gate damage stage 0 whole, 1 (66%), 2 (33%), 3 breached; curtain and coat stages 0..3.
var gate_stage: int = 0
var curtain_stage: int = 0
var coat_stage: int = 0
## Per pad 1..4 (index pad - 1): weapon type (SiegeIds.PAD_*: 0 none, 1 scorpion), yaw (deg).
var pad_type := PackedInt32Array([1, 0, 0, 0])
var pad_yaw := PackedFloat32Array([90, 90, 90, 90])


func set_wheel(
	slot: int, angle_deg: float, rider: bool, walker_count: int = 0, phase: float = 0.0
) -> void:
	wheel_deg[slot] = angle_deg
	wheel_rider[slot] = 1 if rider else 0
	walkers[slot] = clampi(walker_count, 0, 3)
	walk_phase[slot] = phase


func set_route(slot: int, station: int) -> void:
	route[slot] = station if station >= 0 and station < STATIONS else -1


func set_station(id: int, yaw_deg: float, arm: float) -> void:
	station_yaw[id] = yaw_deg
	station_arm[id] = clampf(arm, 0.0, 1.0)


func set_pad(pad: int, type: int, yaw_deg: float) -> void:
	pad_type[pad - 1] = type
	pad_yaw[pad - 1] = yaw_deg


## The first slot whose route is lit to `station`, or -1.
func driver(station: int) -> int:
	for s in SLOTS:
		if route[s] == station:
			return s
	return -1


static func yaw_index(yaw_deg: float, count: int) -> int:
	return posmod(roundi(yaw_deg / (360.0 / count)), count)


## The nearest of a part's phase values (its layout's phase_values).
static func nearest_phase(values: Array, v: float) -> int:
	var best := 0
	for i in values.size():
		if absf(float(values[i]) - v) < absf(float(values[best]) - v):
			best = i
	return best


## The wheel frame for an angle: the frames cover one repeat of the wheel's pattern.
func wheel_frame(slot: int, angle_deg: float) -> int:
	var lay := bank.layout("wheel_%d" % slot)
	var period := float(lay.get("period_deg", 180.0))
	var step := float(lay.get("step_deg", 2.5714))
	var n := int(lay.get("frames", 1))
	return clampi(floori(fposmod(angle_deg, period) / step), 0, n - 1)


func rebuild() -> void:
	begin()
	_wheels()
	_junction()
	_stations()
	_gate_and_tar()
	_pads()
	commit()


func _put(part: String, index: int, layer: int, slot: int = -1, at: Variant = null) -> void:
	var a: Vector3 = at if at is Vector3 else bank.anchor(part)
	add(
		part,
		index,
		a,
		bank.ramp_row_for(part, slot),
		1.0,
		1.0,
		layer * LAYER + SiegeBakeBank.depth_of(a)
	)


func _wheels() -> void:
	for s in SLOTS:
		var rider := wheel_rider[s] == 1
		_put("wheel_%d" % s, wheel_frame(s, wheel_deg[s]), L_WHEEL, s if rider else -1)
		var lit := route[s] >= 0
		_put("wshaft_%d" % s, 1 if lit else 0, L_OUTPUT, s if lit else -1)
		var spots := bank.anchors("walker_%d" % s)
		var f := posmod(floori(walk_phase[s] * 4.0), 4)
		for k in mini(walkers[s], spots.size()):
			var at := spots[k]
			var frame := (f + k) % 4
			if stumble[s]:
				# a stagger: the walkers lurch down together and catch their stride again
				at -= Vector3(0, 0, STUMBLE_DROP_M * stumble_dip[s])
				frame = 1 if stumble_dip[s] > 0.3 else frame
			# each walker a little out of step with the one ahead
			_put("walker_%d" % s, k * 4 + frame, L_WALKER, -1, at)


func _junction() -> void:
	for s in SLOTS:
		if route[s] >= 0:
			_put("route_%d_%d" % [s, route[s]], 0, L_JUNCTION, s)
	for j in STATIONS:
		var d := driver(j)
		_put("sshaft_%d" % j, 1 if d >= 0 else 0, L_JUNCTION, d)
		_put("mark_%d" % j, 0, L_GROUND, d)


func _stations() -> void:
	var lay := bank.layout("ballista")
	var ph: Array = lay.get("phase_values", [0, 1])
	_put(
		"ballista",
		yaw_index(station_yaw[1], YAWS) * ph.size() + nearest_phase(ph, station_arm[1]),
		L_STATION,
		driver(1)
	)
	lay = bank.layout("onager")
	ph = lay.get("phase_values", [0, 1])
	_put(
		"onager",
		yaw_index(station_yaw[2], YAWS) * ph.size() + nearest_phase(ph, station_arm[2]),
		L_STATION,
		driver(2)
	)
	_put("arrows", yaw_index(station_yaw[3], YAWS) * 8 + (racks & 7), L_STATION, driver(3))
	var mine_n := bank.frame_count("mine")
	_put("mine", posmod(floori(mine_phase * mine_n), maxi(mine_n, 1)), L_STATION, driver(0))
	_put("tar_pots", 0, L_STATION, driver(4))
	var pump_n := bank.frame_count("tar_pump")
	_put("tar_pump", posmod(floori(pump_phase * pump_n), maxi(pump_n, 1)), L_STATION)


func _gate_and_tar() -> void:
	_put("gate", clampi(gate_stage, 0, 3), L_STATION)
	if curtain_stage > 0:
		_put("curtain", clampi(curtain_stage, 1, 3) - 1, L_STATION)
	if coat_stage > 0:
		_put("coat", clampi(coat_stage, 1, 3) - 1, L_GROUND)


func _pads() -> void:
	for k in PADS:
		if pad_type[k] == 1:
			_put("scorpion_%d" % (k + 1), yaw_index(pad_yaw[k], 8), L_STATION)
		else:
			_put("brazier_%d" % (k + 1), 0, L_STATION)
