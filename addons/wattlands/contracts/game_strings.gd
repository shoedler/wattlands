class_name GameStrings
extends RefCounted
## String lookup for games (`ctx.strings`, BRIEF 3.6, 6). Contract, frozen after W0.
## Keys live in content/<id>/strings.csv (prefixed with the upper-case game id) and are
## registered with the TranslationServer by the GameRegistry at startup.


## Translated text for `key`, with {0}/{name} placeholders filled from `args`
## (Array or Dictionary). A missing key returns the key itself.
func t(key: String, args: Variant = []) -> String:
	var text := String(TranslationServer.translate(key))
	if args is Array and not (args as Array).is_empty():
		return text.format(args)
	if args is Dictionary and not (args as Dictionary).is_empty():
		return text.format(args)
	return text


## True if a translation exists for `key` in the current locale.
func has(key: String) -> bool:
	return String(TranslationServer.translate(key)) != key
