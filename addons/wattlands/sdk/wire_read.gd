class_name WireRead
extends RefCounted
## Reads the values of a snapshot or an event from the wire, on a client. A peer is not trusted
## to send what the schema says: a number may arrive as an array, a list as a number (`for x in 5`
## would loop five times, `for x in 99999999` would eat the machine), a row as a string. A game's
## apply_snapshot and apply_event read every wire value through these, so a bad message sets a
## default instead of raising a script error or leaving a half-applied state. They never log:
## a game that wants to refuse a whole message checks its shape first and push_warnings itself.

## Whole numbers beyond this (as floats) are clamped, so int arithmetic on them cannot wrap.
const MAX_ABS := 9.0e15


## An int, a whole or fractional float (truncated like int()), a bool (0 or 1) or a numeric
## String as an int; `fallback` for anything else, NaN and infinities included. Huge values clamp
## to +-MAX_ABS.
static func int_of(v: Variant, fallback: int = 0) -> int:
	if v is int:
		return clampi(v, -int(MAX_ABS), int(MAX_ABS))
	if v is float:
		return int(clampf(v, -MAX_ABS, MAX_ABS)) if is_finite(v) else fallback
	if v is bool:
		return 1 if v else 0
	if v is String and _plain_number(v):
		var f := (v as String).to_float()
		return int(clampf(f, -MAX_ABS, MAX_ABS)) if is_finite(f) else fallback
	return fallback


## A finite float from an int, a float, a bool or a numeric String; `fallback` otherwise.
static func float_of(v: Variant, fallback: float = 0.0) -> float:
	if v is int or v is float:
		return clampf(float(v), -MAX_ABS, MAX_ABS) if is_finite(float(v)) else fallback
	if v is bool:
		return 1.0 if v else 0.0
	if v is String and _plain_number(v):
		var f := (v as String).to_float()
		return clampf(f, -MAX_ABS, MAX_ABS) if is_finite(f) else fallback
	return fallback


## A short numeric String without an exponent (String.to_float logs a warning for "1e999").
static func _plain_number(s: String) -> bool:
	return s.length() <= 24 and s.is_valid_float() and not s.contains("e") and not s.contains("E")


## `v` when it is an Array, else an empty one.
static func array_of(v: Variant) -> Array:
	return v if v is Array else []


## `v` when it is a Dictionary, else an empty one.
static func dict_of(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}


## `v` when it is an Array of at least `min_len` elements, else an empty one: a fixed-layout
## row whose columns the caller then indexes.
static func row_of(v: Variant, min_len: int) -> Array:
	return v if v is Array and (v as Array).size() >= min_len else []


## True when `v` is a number (an int or a float; a bool is not one).
static func is_number(v: Variant) -> bool:
	return v is int or v is float


## True when `v` is an Array whose elements are all numbers (a flat row of a snapshot).
static func is_flat_numbers(v: Variant) -> bool:
	if not (v is Array):
		return false
	for e: Variant in v:
		if not is_number(e):
			return false
	return true


## True when `v` nests no deeper than `max_depth` Arrays and Dictionaries (a number or string is
## depth 0). A deeper value is hostile: duplicate(true) on it raises an engine error.
static func within_depth(v: Variant, max_depth: int) -> bool:
	if v is Array:
		if max_depth <= 0:
			return false
		for e: Variant in v:
			if not within_depth(e, max_depth - 1):
				return false
	elif v is Dictionary:
		if max_depth <= 0:
			return false
		for k: Variant in (v as Dictionary).keys():
			if not within_depth(v[k], max_depth - 1):
				return false
	return true


## Why `d` fails `paths` (see bad_int_path): "missing <key>" or "<path> is not numbers"; "" when
## it passes.
static func int_path_problem(d: Dictionary, paths: Array) -> String:
	var bad := bad_int_path(d, paths)
	if bad == "":
		return ""
	var key := bad.replace("[]", "")
	return "missing %s" % key if not d.has(key) else "%s is not numbers" % bad


## The first of `paths` (a game's int_fields() entries for an event type: "key", "key[]" or
## "key[][]") that `d` does not hold as numbers, or "" when every path is a number, or an Array
## (an Array of Arrays) of numbers. A missing key is a bad path.
static func bad_int_path(d: Dictionary, paths: Array) -> String:
	for p: Variant in paths:
		var key := str(p)
		var depth := 0
		while key.ends_with("[]"):
			key = key.substr(0, key.length() - 2)
			depth += 1
		if not d.has(key) or not _nested_numbers(d[key], depth):
			return str(p)
	return ""


static func _nested_numbers(v: Variant, depth: int) -> bool:
	if depth == 0:
		return is_number(v)
	if not (v is Array):
		return false
	for e: Variant in v:
		if not _nested_numbers(e, depth - 1):
			return false
	return true
