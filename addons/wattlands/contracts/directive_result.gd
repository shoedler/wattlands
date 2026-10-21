class_name DirectiveResult
extends RefCounted
## What DirectiveSink.request returns synchronously (contract, frozen after W0).
## `accepted` covers the host-side checks only; the rider's governor still clamps,
## and its applied record arrives through EventBus.directive_applied(peer, record).

var accepted: bool = false
## Directive id assigned by the sink (0 if refused before an id was assigned).
var id: int = 0
## Refusal reason (a Wl.REFUSE_* constant) or "".
var reason: String = ""


static func ok(p_id: int) -> DirectiveResult:
	var r := DirectiveResult.new()
	r.accepted = true
	r.id = p_id
	return r


static func refused(p_reason: String, p_id: int = 0) -> DirectiveResult:
	var r := DirectiveResult.new()
	r.accepted = false
	r.reason = p_reason
	r.id = p_id
	return r


func to_dict() -> Dictionary:
	return {"accepted": accepted, "id": id, "reason": reason}
