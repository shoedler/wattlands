class_name TestGdLex
extends RefCounted
## The lexer the games' static suites scan source with, so a doc comment that mentions "Time." or a
## toast key never trips them. Those scans are the games' no-trainer-bypass check, and each suite
## proves this code on bad snippets. tests/arch/test_no_bypass.gd keeps its own copy: it is pinned.


## {"code": the text with comments removed and every string reduced to its quotes,
## "strings": the contents of every string literal}.
static func lex(text: String) -> Dictionary:
	var code := PackedStringArray()
	var strings: Array[String] = []
	var n := text.length()
	var i := 0
	while i < n:
		var c := text[i]
		if c == "#":
			while i < n and text[i] != "\n":
				i += 1
			continue
		if c == '"' or c == "'":
			var triple := text.substr(i, 3) == c.repeat(3)
			var close := c.repeat(3) if triple else c
			var raw := i > 0 and text[i - 1] == "r"
			i += 3 if triple else 1
			var start := i
			while i < n:
				if text[i] == "\\" and not raw:
					i += 2
					continue
				if text.substr(i, close.length()) == close:
					break
				if text[i] == "\n" and not triple:
					break
				i += 1
			strings.append(text.substr(start, i - start))
			code.append('""')
			i += close.length()
			continue
		code.append(c)
		i += 1
	return {"code": "".join(code), "strings": strings}
