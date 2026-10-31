class_name IntentValue
extends RefCounted
## Reads the loosely typed values of a game's intents. An intent is a Dictionary from the wire, so a
## number may arrive as a float or a flag as a number; a game's normalize() reads them through this.


## An intent's flag as a bool: a bool as is, a number when it is not zero, anything else false.
static func truthy(v: Variant) -> bool:
	if v is bool:
		return v
	if v is int or v is float:
		return float(v) != 0.0
	return false


## True for an int, or a finite float with a whole value (JSON numbers arrive as floats).
static func whole(v: Variant) -> bool:
	return (v is int) or (v is float and is_finite(v) and float(v) == floorf(v))
