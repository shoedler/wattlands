class_name AppTextField
extends VBoxContainer
## A text field usable with a keyboard, a controller and pedal-scan (BRIEF 3.5): a caption, a
## large display of the value, and a LineEdit for typing. The on-screen keyboard (AppKeyboard)
## appends characters through append_char(). In "code" mode it follows the room-code rules
## (AppCodeInput: case-insensitive, dashes and spaces ignored, O -> 0, I/L -> 1, 6 characters,
## shown as K7Q-X2M at >= 48 px). Secret fields never show their value.

signal changed(text: String)
signal submitted(text: String)

const MODE_CODE := "code"
const MODE_TEXT := "text"

## Rows for the on-screen keyboard in text mode.
const ROWS_DIGITS: Array[String] = ["01234", "56789"]
const ROWS_HEX: Array[String] = ["01234567", "89abcdef"]
const ROWS_URL: Array[String] = ["abcdefgh", "ijklmnop", "qrstuvwx", "yz012345", "6789:/.-", "_?=&"]
const ROWS_NAME: Array[String] = ["ABCDEFGH", "IJKLMNOP", "QRSTUVWX", "YZ 01234", "56789-'."]

var mode: String = MODE_TEXT
var secret: bool = false
var max_length: int = 64
## Keyboard rows (code mode uses the Crockford alphabet).
var rows: Array[String] = []
var caption: Label = null
var display: Label = null
var line_edit: LineEdit = null
var _value: String = ""


static func make_code(caption_text: String) -> AppTextField:
	var f := AppTextField.new()
	f.mode = MODE_CODE
	f.max_length = NetMessages.CODE_LENGTH
	f.rows = AppCodeInput.keyboard_rows()
	f._build(caption_text, AppStyle.FONT_CODE)
	return f


static func make_text(caption_text: String, p_rows: Array[String], p_max_length: int = 64, p_secret: bool = false) -> AppTextField:
	var f := AppTextField.new()
	f.mode = MODE_TEXT
	f.rows = p_rows
	f.max_length = p_max_length
	f.secret = p_secret
	f._build(caption_text, AppStyle.FONT_NUMBER)
	return f


func _build(caption_text: String, display_size: int) -> void:
	add_theme_constant_override("separation", 8)
	caption = AppStyle.label(caption_text, AppStyle.FONT_BODY, AppStyle.TEXT_DIM)
	caption.name = "Caption"
	add_child(caption)
	display = AppStyle.label("", display_size, AppStyle.ACCENT)
	display.name = "Display"
	add_child(display)
	line_edit = LineEdit.new()
	line_edit.name = "Typing"
	line_edit.add_theme_font_size_override("font_size", AppStyle.FONT_BODY)
	line_edit.secret = secret
	line_edit.placeholder_text = String(TranslationServer.translate("APP_TYPE_HERE"))
	line_edit.custom_minimum_size = Vector2(480, 0)
	add_child(line_edit)
	line_edit.text_changed.connect(_on_typed)
	line_edit.text_submitted.connect(_on_submitted)
	_refresh()


func value() -> String:
	return _value


func set_value(text: String) -> void:
	_value = _clean(text)
	if line_edit != null and line_edit.text != _value:
		line_edit.text = _value
		line_edit.caret_column = _value.length()
	_refresh()
	changed.emit(_value)


func append_char(ch: String) -> void:
	if mode == MODE_CODE:
		set_value(AppCodeInput.append(_value, ch))
	elif _value.length() < max_length:
		set_value(_value + ch)


func backspace() -> void:
	set_value(_value.substr(0, maxi(_value.length() - 1, 0)))


func clear() -> void:
	set_value("")


## True when the value can be submitted (a complete code in code mode, non-empty otherwise).
func is_complete() -> bool:
	if mode == MODE_CODE:
		return AppCodeInput.is_complete(_value)
	return _value.strip_edges() != ""


## The text shown in the display (never the secret itself).
func display_text() -> String:
	if mode == MODE_CODE:
		return AppCodeInput.display(_value, true)
	if secret:
		return "•".repeat(mini(_value.length(), 24)) if _value != "" else "—"
	return _value if _value != "" else "—"


func _clean(text: String) -> String:
	if mode == MODE_CODE:
		return AppCodeInput.filter(text)
	var out := ""
	for ch in text:
		if ch == "\n" or ch == "\r" or ch == "\t":
			continue
		out += ch
	return out.substr(0, max_length)


func _refresh() -> void:
	if display != null:
		display.text = display_text()


func _on_typed(text: String) -> void:
	var cleaned := _clean(text)
	_value = cleaned
	if line_edit.text != cleaned:
		line_edit.text = cleaned
		line_edit.caret_column = cleaned.length()
	_refresh()
	changed.emit(_value)


func _on_submitted(_text: String) -> void:
	if is_complete():
		submitted.emit(_value)
