class_name AppSessionInput
extends Node
## The session screen's view of the InputRouter for its GameHost (GameHost config.input_router).
## The screen owns pause and its overlay menu (BRIEF 3.5, 4.6.5); the GameHost would otherwise
## also toggle pause on the same `pause` action (and resume on `confirm`), undoing the screen's
## pause on its next tick or picking a menu item and resuming at once.
## - take_actions(): the router's actions without `pause` (the screen pauses and resumes) and,
##   while `screen_owns_input` says so (the overlay is open), without anything but `panic`.
##   `panic` always passes: the rider's governor goes safe however the screen is set.
## - take_gestures(): the router's gestures, unchanged (pedal gestures reach the game).
## - attach_rider()/detach_rider(): forwarded; after a detach (the session ended) the menu rider
##   (`menu_rider`, TrainerService's) is attached again, so menus after the session still get
##   pedal gestures.

var router: WlInputRouter = null
## () -> bool: true while the screen's menu owns the input (overlay visible).
var screen_owns_input: Callable = Callable()
## () -> LocalRider: the rider menus follow once the session lets go (null: none).
var menu_rider: Callable = Callable()


static func create(p_router: WlInputRouter, owns: Callable = Callable(), p_menu_rider: Callable = Callable()) -> AppSessionInput:
	var s := AppSessionInput.new()
	s.name = "SessionInput"
	s.router = p_router
	s.screen_owns_input = owns
	s.menu_rider = p_menu_rider
	return s


func take_actions() -> Array[StringName]:
	var out: Array[StringName] = []
	if router == null:
		return out
	var owned := screen_owns_input.is_valid() and bool(screen_owns_input.call())
	for a in router.take_actions():
		if a == &"panic":
			out.append(a)
		elif a == &"pause" or owned:
			continue
		else:
			out.append(a)
	return out


func take_gestures() -> Array[StringName]:
	var out: Array[StringName] = []
	if router != null:
		out.assign(router.take_gestures())
	return out


func attach_rider(rider: LocalRider) -> void:
	if router != null:
		router.attach_rider(rider)


func detach_rider() -> void:
	if router == null:
		return
	router.detach_rider()
	var r: Variant = menu_rider.call() if menu_rider.is_valid() else null
	if r is LocalRider and is_instance_valid(r):
		router.attach_rider(r as LocalRider)
