class_name WlSettings
extends Node
## Autoload `Settings`: the rider profile (profile.json) and app settings (settings.json)
## under Paths.user_dir() (BRIEF 3.2, 6). Owned by platform; public API frozen after W0.
## Strava credentials and tokens are NOT here (rides keeps them in strava.json).
##
## App setting keys and defaults:
##   relay_url "ws://localhost:8787/v1", strava_api_base "https://www.strava.com/api/v3",
##   strava_oauth_base "https://www.strava.com/oauth", scaling_mode "FAIR_FTP",
##   last_game "", last_content "", last_device {}, recent_rooms [], locale "en",
##   master_volume_db 0.0, fullscreen false.
## --relay=<url> and --strava-base=<url> override the stored values for this run.

signal changed(key: String)

var profile: RiderProfile = RiderProfile.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Load profile.json and settings.json (missing files leave defaults). Called at startup
## and whenever Paths' override changes (tests).
func load_all() -> void:
	pass


func save_profile() -> bool:
	return false


func save_settings() -> bool:
	return false


## True once a profile was created (first run creates "Rider", FTP 200, unverified).
func has_profile() -> bool:
	return profile.created


func get_value(_key: String, default: Variant = null) -> Variant:
	return default


func set_value(_key: String, _value: Variant) -> void:
	pass


func relay_url() -> String:
	return "ws://localhost:8787/v1"


func strava_api_base() -> String:
	return "https://www.strava.com/api/v3"


func strava_oauth_base() -> String:
	return "https://www.strava.com/oauth"
