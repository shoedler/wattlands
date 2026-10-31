extends "res://tests/games/tank/view/fixture_scene.gd"
## The fixture scene with the help overlay open (F1), for reading the help frame with tools/screenshot
## (SPEC_TANK section 6). Not a test. Options: TANK_FIXTURE, as in fixture_scene.gd.

## The overlay's own auto-hide does not run out inside a screenshot's frames.
const HELP_S := 60.0


func _ready() -> void:
	super()
	if hud != null:
		hud.show_help(HELP_S)
