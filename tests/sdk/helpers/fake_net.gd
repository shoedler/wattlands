extends WlNetSession
## Test double for WlNetSession (a W0 stub in the sdk-runtime worktree): an in-process star
## through a FakeNetHub. Every message goes through JSON.stringify/parse_string like the real
## transport (numbers come back as floats, dictionary keys as strings), and is delivered in
## send order on the receiver's poll(). W2 runs the same flows over the real NetSession and
## LoopbackTransport in tests/sdk/integration/.

var hub: RefCounted = null
var inbox: Array = []
var sent: Array = []


func send_to(peer_id: int, data: Dictionary) -> void:
	sent.append([peer_id, str(data.get("type", ""))])
	hub.call("deliver", local_peer, peer_id, data)


func send_to_host(data: Dictionary) -> void:
	send_to(host_peer, data)


func broadcast(data: Dictionary) -> void:
	for p: int in hub.call("peer_ids"):
		if p != local_peer:
			send_to(p, data)


func poll() -> void:
	var q := inbox
	inbox = []
	for m: Array in q:
		game_message.emit(int(m[0]), m[1])


func peers() -> Array[int]:
	var out: Array[int] = []
	out.assign(hub.call("peer_ids"))
	return out


func mark_started() -> void:
	session_started = true


## Types of the messages sent to `peer` so far.
func sent_types(peer: int) -> Array[String]:
	var out: Array[String] = []
	for s: Array in sent:
		if int(s[0]) == peer:
			out.append(str(s[1]))
	return out
