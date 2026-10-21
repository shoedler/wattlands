extends GameModule
## Test double of a GameModule: a session preview per content and a snapshot.

var preview_title: String = "Preview"
var preview_total_s: float = 1680.0
var snap: Dictionary = {"tick": 7}


func session_preview(content_id: String) -> Dictionary:
	return {"title": "%s %s" % [preview_title, content_id], "total_s": preview_total_s,
		"lines": ["line for " + content_id]}


func snapshot() -> Dictionary:
	return snap.duplicate(true)
