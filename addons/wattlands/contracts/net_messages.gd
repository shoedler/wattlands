class_name NetMessages
extends RefCounted
## Message schemas (BRIEF 5.3 relay envelope, 5.5 game messages). Contract, frozen after
## W0; additive changes only. `Protocol` (addons/wattlands/net/protocol.gd) encodes,
## decodes and validates with these tables.
##
## Godot's JSON parser returns every number as a float, so Protocol.decode() converts the
## int fields listed here (and peer, host, from, to, seq, proto, max and every key ending
## in "_id" anywhere in a message, only when the value is a number: game_id, content_id and
## session_id are strings) back to int, converts Dictionary keys that are peer ids
## (fields named in PEER_KEYED) to int, and rejects a message that lacks a required field
## or whose "v" differs from VERSION. Dotted paths use "[]" for every array element and
## "{}" for every dictionary value, e.g. "players[].slot_index", "riders{}.raw_w".

## Version of the game-message schemas (field "v" in every game message).
const VERSION := 1

# Relay envelope ("t" field), BRIEF 5.3.
const RELAY: Dictionary = {
	"hello": {"req": ["proto", "game", "build"], "ints": []},
	"create": {"req": ["max"], "ints": []},
	"created": {"req": ["code", "peer", "token"], "ints": []},
	"join": {"req": ["code"], "ints": []},
	"joined": {"req": ["peer", "host", "token"], "ints": []},
	"error": {"req": ["code"], "ints": []},
	"msg": {"req": ["d"], "ints": []},
	"peer_joined": {"req": ["peer"], "ints": []},
	"peer_left": {"req": ["peer"], "ints": []},
	"host_left": {"req": [], "ints": []},
	"leave": {"req": [], "ints": []},
	"ping": {"req": ["ts"], "ints": []},
	"pong": {"req": ["ts"], "ints": []},
}

# Game messages inside the relay's "d" ("type" field), BRIEF 5.5.
const GAME: Dictionary = {
	# client -> host
	"player_info": {"req": ["name", "ftp", "ftp_verified", "p_eff_per_w", "preferred_cadence_rpm",
		"haptics_on", "autopilot", "player_options", "games"], "ints": []},
	"ready": {"req": ["ready"], "ints": []},
	"telemetry": {"req": ["tm"], "ints": ["tm.peer", "tm.applied_target_w", "tm.gear",
		"tm.phase_index", "tm.acks[].id"]},
	"clock_ping": {"req": ["t0"], "ints": []},
	# host -> all
	"lobby_state": {"req": ["players", "game_id", "game_version", "content_id", "scaling",
		"settings"], "ints": ["players[].slot_index", "players[].ftp", "settings.bot_ftp",
		"settings.max_players", "settings.min_players"]},
	"session_start": {"req": ["game_id", "game_version", "content_id", "seed", "players",
		"options", "scaling", "start_tick"], "ints": ["seed", "start_tick", "players[].slot_index"]},
	"snapshot": {"req": ["game_id", "seq", "state"], "ints": ["tick"]},
	"event": {"req": ["seq", "events"], "ints": []},
	"roster": {"req": ["riders"], "ints": ["riders{}.slot_index"]},
	"results": {"req": ["results"], "ints": ["results.rows[].xp", "results.rows[].slot_index"]},
	"session_end": {"req": ["reason"], "ints": []},
	"refused": {"req": ["reason"], "ints": []},
	# host -> one client
	"plan": {"req": ["plan"], "ints": []},
	"phase": {"req": ["index", "start_tick", "ended_by"], "ints": ["index", "start_tick"]},
	"directive": {"req": ["kind"], "ints": ["id"]},
	"hud": {"req": ["kind", "key"], "ints": []},
	"clock_pong": {"req": ["t0", "th"], "ints": []},
}

## Optional fields beyond `req` (documented in docs/PROTOCOL.md): the relay adds created.max,
## joined.rejoin, joined.peers (ids, cast them), peer_joined.rejoin, host_left.reason
## ("left", "timeout", "expired"), error.detail, error.re and error.proto, and create may
## carry a previous code (P1). The GameHost adds session_start.session_id,
## content_overrides and the suffix-free copies game, content and session; plan.peer;
## phase.peer; snapshot.tick; directive.peer, directive.directive (the EffortDirective dict
## for kind request), grade_pct, lo_rpm/hi_rpm and lo_w/hi_w; hud.args and hud.seconds.
## `refused` may carry scope: "ready" (with game_id and game_version) for a refused ready-up
## that does not end the session, and is accepted on any schema version. Event types that
## start with "wl." are platform events (wl.phase_started, wl.lap_marker, wl.finished).

## Fields whose Dictionary keys are int peer ids after decoding.
const PEER_KEYED: Array[String] = ["riders", "player_options", "ready_flags", "trainers"]

## Directive kinds (BRIEF 5.5 `directive.kind`).
const DIRECTIVE_REQUEST := "request"
const DIRECTIVE_COURSE_GRADE := "course_grade"
const DIRECTIVE_CADENCE_BAND := "cadence_band"
const DIRECTIVE_POWER_BAND := "power_band"
## Host-side end of a rider's phase (applied by the client through its `phase` message).
const DIRECTIVE_KINDS: Array[String] = [DIRECTIVE_REQUEST, DIRECTIVE_COURSE_GRADE,
	DIRECTIVE_CADENCE_BAND, DIRECTIVE_POWER_BAND]

## Relay limits (BRIEF 5.3).
const MAX_PEERS := 8
const MAX_MESSAGE_BYTES := 16384
const MAX_MSGS_PER_S := 60
const BURST_MSGS := 120
const IDLE_TIMEOUT_S := 60
const CLIENT_PING_S := 15
const RECONNECT_TOKEN_S := 120
const ROOM_LIFETIME_S := 4 * 3600

## Crockford Base32 alphabet for room codes (BRIEF 5.2).
const CODE_ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
const CODE_LENGTH := 6


static func is_relay_type(t: String) -> bool:
	return RELAY.has(t)


static func is_game_type(type: String) -> bool:
	return GAME.has(type)
