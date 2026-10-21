class_name AppCodeInput
extends RefCounted
## Room-code entry rules for the join screen (BRIEF 3.5, 5.2). Input is case-insensitive,
## ignores dashes and spaces, maps O to 0 and I or L to 1, and keeps only characters of the
## Crockford alphabet; a complete code has 6 characters and is shown as K7Q-X2M.
## RoomCode (net) holds the canonical normalize/format; this class adds the incremental rules
## an on-screen keyboard and a typed LineEdit need.


## Typed or pasted text -> the code characters so far (at most 6, canonical upper case).
## Dashes, spaces and characters outside the alphabet are dropped.
static func filter(text: String) -> String:
	var out := ""
	for ch in text.to_upper():
		var c := map_char(ch)
		if c == "":
			continue
		out += c
		if out.length() >= NetMessages.CODE_LENGTH:
			break
	return out


## One character -> its canonical code character, or "" when it is ignored or invalid.
static func map_char(ch: String) -> String:
	var c := ch.to_upper()
	if c == "O":
		c = "0"
	elif c == "I" or c == "L":
		c = "1"
	if c.length() != 1 or NetMessages.CODE_ALPHABET.find(c) < 0:
		return ""
	return c


## Appends `ch` to `code` (ignoring it when invalid or when the code is full).
static func append(code: String, ch: String) -> String:
	var c := map_char(ch)
	if c == "" or code.length() >= NetMessages.CODE_LENGTH:
		return code
	return code + c


static func backspace(code: String) -> String:
	return code.substr(0, maxi(code.length() - 1, 0))


static func is_complete(code: String) -> bool:
	var f := filter(code)
	return f.length() == NetMessages.CODE_LENGTH and RoomCode.is_valid(f)


## "K7QX" -> "K7Q-X__" (pad) or "K7Q-X" (no pad); a complete code -> "K7Q-X2M".
static func display(code: String, pad: bool = true) -> String:
	var c := filter(code)
	if pad:
		while c.length() < NetMessages.CODE_LENGTH:
			c += "_"
	if c.length() <= 3:
		return c
	return c.substr(0, 3) + "-" + c.substr(3)


## The on-screen keyboard's rows (row-column scanning: pick a row, then a character).
static func keyboard_rows() -> Array[String]:
	var rows: Array[String] = []
	var alpha := NetMessages.CODE_ALPHABET
	var i := 0
	while i < alpha.length():
		rows.append(alpha.substr(i, 8))
		i += 8
	return rows
