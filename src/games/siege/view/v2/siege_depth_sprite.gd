class_name SiegeDepthSprite
extends SiegeDepthBatch
## One baked frame at a world anchor, depth-tested against the baked world (a SiegeDepthBatch
## of one entry). For many sprites use a SiegeDepthBatch (or SiegeV2Machines, SiegeV2Crowd)
## instead: each SiegeDepthSprite is its own canvas item.

var part: String = "":
	set(v):
		part = v
		_dirty = true
var index: int = 0:
	set(v):
		index = v
		_dirty = true
## The world point the frame hangs on; parts baked in place default to their own anchor.
var anchor: Vector3 = Vector3.ZERO:
	set(v):
		anchor = v
		_has_anchor = true
		_dirty = true
## The driving rider's slot (its hue), or -1 for the part's idle material.
var slot: int = -1:
	set(v):
		slot = v
		_dirty = true
var shade: float = 1.0:
	set(v):
		shade = v
		_dirty = true

var _dirty: bool = true
var _has_anchor: bool = false


func _process(_delta: float) -> void:
	if _dirty:
		refresh()


func refresh() -> void:
	_dirty = false
	if bank == null or not bank.has_part(part):
		begin()
		commit()
		return
	var at := anchor if _has_anchor else bank.anchor(part)
	begin()
	add(part, index, at, bank.ramp_row_for(part, slot), shade)
	commit()
