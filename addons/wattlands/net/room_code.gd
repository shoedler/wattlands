class_name RoomCode
extends RefCounted
## Room codes (BRIEF 5.2): six characters from the Crockford Base32 alphabet
## 0123456789ABCDEFGHJKMNPQRSTVWXYZ, displayed as K7Q-X2M. Input is case-insensitive,
## ignores dashes and spaces, and maps O to 0 and I or L to 1. The relay generates codes.


## Canonical 6-character code from user input, or "" if it can't be one.
static func normalize(input: String) -> String:
	var out := ""
	for ch in input.to_upper():
		if ch == "-" or ch == " " or ch == "\t":
			continue
		var c := ch
		if c == "O":
			c = "0"
		elif c == "I" or c == "L":
			c = "1"
		if NetMessages.CODE_ALPHABET.find(c) < 0:
			return ""
		out += c
	return out if out.length() == NetMessages.CODE_LENGTH else ""


static func is_valid(input: String) -> bool:
	return normalize(input) != ""


## "K7QX2M" -> "K7Q-X2M".
static func format(code: String) -> String:
	var c := normalize(code)
	if c == "":
		return code
	return c.substr(0, 3) + "-" + c.substr(3, 3)


## A random code (tests and LAN mode; the relay generates real ones).
static func random(rng: RandomNumberGenerator) -> String:
	var out := ""
	for _i in NetMessages.CODE_LENGTH:
		out += NetMessages.CODE_ALPHABET[rng.randi_range(0, NetMessages.CODE_ALPHABET.length() - 1)]
	return out
