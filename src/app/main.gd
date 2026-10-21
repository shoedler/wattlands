extends Control
## The app's main scene (BRIEF 3.9 app shell). Owned by app-shell, which replaces this W0
## stub: it shows the screen for App.state (title, first run, profile, settings, game
## picker, lobby with code entry, session, results) and drives the zero-input flows.


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
