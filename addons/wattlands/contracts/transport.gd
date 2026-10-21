class_name Transport
extends Node
## A multiplayer transport (BRIEF 5.4). Contract, frozen after W0.
## Implementations: RelayTransport (WebSocketPeer to server/relay), LoopbackTransport
## (in-process, tests), LanTransport (P1).
##
## Peers are relay peer ids (host = 1). `data` is the game-message Dictionary carried in
## the relay's `d` field (BRIEF 5.5); the relay never looks inside it. Transports run with
## process_mode = PROCESS_MODE_ALWAYS and do their I/O in poll().

## Room created (host) or joined (client); room_code, local_peer, host_peer and
## reconnect_token are set.
signal connected
## Lost or closed: "closed", "dropped", "host_left", "room_not_found", "room_full",
## "version_mismatch", "rate_limited", "bad_request", "timeout", "error".
signal disconnected(reason: String)
signal peer_joined(id: int)
signal peer_left(id: int)
signal message(from: int, data: Dictionary)

## Room code without the dash, e.g. "K7QX2M".
var room_code: String = ""
var local_peer: int = 0
var host_peer: int = Wl.HOST_PEER
## Relay reconnect token (valid 120 s after a drop; keeps the peer id).
var reconnect_token: String = ""
## Reason given with the latest peer_left (relay "reason"), for logs and UI.
var last_peer_left_reason: String = ""


## Create a room; `connected` fires with the new room_code.
func host(_max_peers: int = 8) -> void:
	pass


## Join a room by code (dashes, spaces, case and O/I/L confusions are tolerated);
## pass a saved token to reclaim a dropped peer id.
func join(_code: String, _token: String = "") -> void:
	pass


## Send to a peer id, the host id, or Wl.ALL_PEERS (0: everyone except the sender).
## Non-hosts may only send to the host.
func send(_to: int, _data: Dictionary) -> void:
	pass


## Pump I/O; call every frame (or every sim step in headless runs).
func poll() -> void:
	pass


## Leave the room explicitly (the relay sends host_left when the host leaves).
func leave() -> void:
	pass


func is_host() -> bool:
	return local_peer != 0 and local_peer == host_peer


func is_open() -> bool:
	return local_peer != 0
