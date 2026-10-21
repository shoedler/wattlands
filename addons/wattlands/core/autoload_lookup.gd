class_name AutoloadLookup
extends RefCounted
## Finds the platform autoloads at run time without naming them as globals, so platform
## classes work outside the app (GUT, tools, in-process simulations) and tests can inject
## private instances instead. Every getter returns null when that autoload isn't there.
## Owned by platform.


static func root() -> Window:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root
	return null


static func find(autoload_name: String) -> Node:
	var r := root()
	if r == null:
		return null
	return r.get_node_or_null(NodePath(autoload_name))


static func bus() -> WlEventBus:
	return find("EventBus") as WlEventBus


static func settings() -> WlSettings:
	return find("Settings") as WlSettings


static func trainer_service() -> WlTrainerService:
	return find("TrainerService") as WlTrainerService


static func rides() -> WlRides:
	return find("Rides") as WlRides


static func input_router() -> WlInputRouter:
	return find("InputRouter") as WlInputRouter


static func app() -> WlApp:
	return find("App") as WlApp
