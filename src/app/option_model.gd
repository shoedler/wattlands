class_name AppOptionModel
extends RefCounted
## One game.json option entry for the lobby (BRIEF 3.6): {id, type, default, label} where type
## is "toggle" (bool), "int" (min, max, step default 1) or "choice" (choices [{value, label}]).
## Labels are keys in the game's strings.csv and default to <ID>_OPT_<OPTION ID>; choice labels
## are keys too (shown as the raw value when the key is missing).

const TOGGLE := "toggle"
const INT := "int"
const CHOICE := "choice"
## An int option with more values than this is edited with a stepper instead of a value list.
const LIST_MAX := 12

var game_id: String = ""
var entry: Dictionary = {}


static func make(p_game_id: String, p_entry: Dictionary) -> AppOptionModel:
	var m := AppOptionModel.new()
	m.game_id = p_game_id
	m.entry = p_entry
	return m


func id() -> String:
	return str(entry.get("id", ""))


func type() -> String:
	return str(entry.get("type", ""))


func label_key() -> String:
	if entry.has("label"):
		return str(entry["label"])
	return "%s_OPT_%s" % [game_id.to_upper(), id().to_upper()]


## The translated label, or the option id when the key is missing.
func label_text() -> String:
	var key := label_key()
	var t := String(TranslationServer.translate(key))
	return id() if t == key else t


func default_value() -> Variant:
	return normalize(entry.get("default", null))


func int_min() -> int:
	return int(entry.get("min", 0))


func int_max() -> int:
	return int(entry.get("max", 0))


func int_step() -> int:
	return maxi(int(entry.get("step", 1)), 1)


## Every allowed value in order.
func values() -> Array:
	match type():
		TOGGLE:
			return [true, false]
		INT:
			var out: Array = []
			var v := int_min()
			while v <= int_max():
				out.append(v)
				v += int_step()
			return out
		CHOICE:
			var out: Array = []
			for c: Variant in entry.get("choices", []):
				if c is Dictionary:
					out.append((c as Dictionary).get("value"))
			return out
	return []


## True when the lobby shows a value list (else a stepper for long int ranges).
func uses_list() -> bool:
	return type() != INT or values().size() <= LIST_MAX


## A value from JSON or the lobby in this option's type (ints stay ints, toggles bools).
func normalize(value: Variant) -> Variant:
	match type():
		TOGGLE:
			if value == null:
				return false
			return bool(value)
		INT:
			if value == null:
				return int_min()
			return clampi(int(value), int_min(), int_max())
		CHOICE:
			for v: Variant in values():
				if str(v) == str(value):
					return v
			var vals := values()
			return vals[0] if not vals.is_empty() else value
	return value


## The value `steps` positions away (wrapping for toggles and choices, clamped for ints).
func step_value(value: Variant, steps: int) -> Variant:
	if type() == INT:
		return clampi(int(normalize(value)) + steps * int_step(), int_min(), int_max())
	var vals := values()
	if vals.is_empty():
		return value
	var i := index_of(value)
	return vals[posmod(maxi(i, 0) + steps, vals.size())]


func index_of(value: Variant) -> int:
	var vals := values()
	var n: Variant = normalize(value)
	for i in vals.size():
		if str(vals[i]) == str(n):
			return i
	return -1


## Display text for a value.
func value_text(value: Variant) -> String:
	match type():
		TOGGLE:
			return tr_key("APP_ON") if bool(value) else tr_key("APP_OFF")
		CHOICE:
			for c: Variant in entry.get("choices", []):
				if c is Dictionary and str((c as Dictionary).get("value")) == str(value):
					var key := str((c as Dictionary).get("label", str(value)))
					var t := String(TranslationServer.translate(key))
					return str(value) if t == key and key.contains("_") else t
			return str(value)
		INT:
			return str(int(value))
	return str(value)


static func tr_key(key: String) -> String:
	return String(TranslationServer.translate(key))


## Every option of `entries` with its default value: {id: value}.
static func defaults(p_game_id: String, entries: Array) -> Dictionary:
	var out: Dictionary = {}
	for e: Variant in entries:
		if e is Dictionary:
			var m := make(p_game_id, e as Dictionary)
			out[m.id()] = m.default_value()
	return out
