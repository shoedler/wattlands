class_name TeamVote
extends RefCounted
## A team vote on one proposal (a shop item, a route, a rematch): pure and deterministic, so the
## host decides it inside sim_step and a snapshot carries it as plain ints.
##
## `voters` are peer ids in slot order. Every voter starts at yes; a voter who says no can go back
## to yes. The proposal is rejected when "no" outnumbers "yes" or the two are tied, and kept
## otherwise. With no voters there is nothing to count and nothing is rejected.

## Peer ids allowed to vote, in slot order.
var voters: Array[int] = []
## Peer id -> false for a voter who said no. A voter missing here votes yes (the default).
var votes: Dictionary = {}


func _init(p_voters: Array = []) -> void:
	set_voters(p_voters)


## Replaces the voter list (a rider joined or left). Keeps the votes of voters still in it, in the
## order given; ignores anything that is not a whole number and repeats.
func set_voters(p_voters: Array) -> void:
	voters.clear()
	for v: Variant in p_voters:
		if IntentValue.whole(v) and not voters.has(int(v)):
			voters.append(int(v))
	for k: Variant in votes.keys():
		if not voters.has(int(k)):
			votes.erase(k)


## Sets one voter's vote. False (and nothing changes) for a peer who is not a voter.
func vote(voter: int, yes: bool) -> bool:
	if not voters.has(voter):
		return false
	if yes:
		votes.erase(voter)
	else:
		votes[voter] = false
	return true


## Flips one voter's vote and returns the new one (true = yes). A non-voter stays out: false.
func toggle(voter: int) -> bool:
	if not voters.has(voter):
		return false
	var now_yes := not is_yes(voter)
	vote(voter, now_yes)
	return now_yes


## The voter's current vote; true (the default) for a voter who has not said no.
func is_yes(voter: int) -> bool:
	return not votes.has(voter)


func yes_count() -> int:
	return voters.size() - no_count()


func no_count() -> int:
	var n := 0
	for v in voters:
		if votes.has(v):
			n += 1
	return n


## True when "no" outnumbers "yes" or the two are tied (with at least one voter).
func rejected() -> bool:
	return TeamVote.decide(yes_count(), no_count())


## The voters who said no, in slot order: the wire form of the votes.
func no_voters() -> Array[int]:
	var out: Array[int] = []
	for v in voters:
		if votes.has(v):
			out.append(v)
	return out


## Rebuilds a vote from its voters and the no list a snapshot carried (no_voters()).
static func from_wire(p_voters: Array, p_no: Array) -> TeamVote:
	var tv := TeamVote.new(p_voters)
	for v: Variant in p_no:
		if IntentValue.whole(v):
			tv.vote(int(v), false)
	return tv


## The rule on its own: rejected when no > yes or a tie, never with no votes cast at all.
static func decide(yes: int, no: int) -> bool:
	if yes + no <= 0:
		return false
	return no >= yes
