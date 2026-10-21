extends RefCounted
## In-process star for FakeNet sessions (see fake_net.gd). Host is peer 1, clients 2.. in
## creation order. drop(peer) makes the host's session emit peer_left(peer, "dropped") and
## discards messages to and from that peer until rejoin(peer), which emits rejoin_requested.

const FakeNet := preload("res://tests/sdk/helpers/fake_net.gd")

var sessions: Dictionary = {}
var dropped: Dictionary = {}
var delivered: int = 0


## A new session for `peer` (1 = host). The caller frees it (or adds it to a tree).
func add(peer: int) -> WlNetSession:
	var s: WlNetSession = FakeNet.new()
	s.set("hub", self)
	s.local_peer = peer
	s.host_peer = Wl.HOST_PEER
	s.role = Wl.HOST if peer == Wl.HOST_PEER else Wl.CLIENT
	sessions[peer] = s
	return s


func peer_ids() -> Array[int]:
	var out: Array[int] = []
	for k: int in sessions.keys():
		out.append(k)
	out.sort()
	return out


func deliver(from: int, to: int, data: Dictionary) -> void:
	if dropped.has(from) or dropped.has(to) or not sessions.has(to):
		return
	var wire: Variant = JSON.parse_string(JSON.stringify(data))
	(sessions[to].get("inbox") as Array).append([from, wire])
	delivered += 1


func drop(peer: int) -> void:
	dropped[peer] = true
	var h: WlNetSession = sessions.get(Wl.HOST_PEER)
	if h != null:
		h.peer_left.emit(peer, "dropped")


func rejoin(peer: int) -> void:
	dropped.erase(peer)
	var h: WlNetSession = sessions.get(Wl.HOST_PEER)
	if h != null:
		h.rejoin_requested.emit(peer)


## An Array of sessions for GameSimRunner's net_factory: host first, then `count - 1` clients.
func factory(count: int) -> Variant:
	var out: Array = []
	for i in count:
		out.append(add(i + 1))
	return out
