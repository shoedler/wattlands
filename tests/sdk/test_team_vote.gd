extends GutTest
## TeamVote: one proposal, voters in slot order, default yes; a majority no or a tie rejects.


func test_everyone_starts_at_yes() -> void:
	var tv := TeamVote.new([1, 2, 3])
	assert_eq(tv.yes_count(), 3)
	assert_eq(tv.no_count(), 0)
	assert_false(tv.rejected())
	for v in [1, 2, 3]:
		assert_true(tv.is_yes(v))


func test_a_minority_no_keeps_it() -> void:
	var tv := TeamVote.new([1, 2, 3])
	assert_true(tv.vote(2, false))
	assert_eq(tv.no_count(), 1)
	assert_eq(tv.yes_count(), 2)
	assert_false(tv.rejected())


func test_a_majority_no_rejects() -> void:
	var tv := TeamVote.new([1, 2, 3])
	tv.vote(2, false)
	tv.vote(3, false)
	assert_true(tv.rejected())


func test_a_tie_rejects() -> void:
	var tv := TeamVote.new([1, 2, -1, -2])
	tv.vote(-1, false)
	assert_false(tv.rejected(), "1 no of 4 keeps it")
	tv.vote(2, false)
	assert_eq(tv.yes_count(), 2)
	assert_eq(tv.no_count(), 2)
	assert_true(tv.rejected(), "2-2 is a tie")


func test_two_riders_one_no_is_a_tie() -> void:
	var tv := TeamVote.new([1, 2])
	tv.vote(2, false)
	assert_true(tv.rejected())


func test_a_lone_voter_rejects_their_own_by_saying_no() -> void:
	var tv := TeamVote.new([1])
	assert_false(tv.rejected())
	tv.vote(1, false)
	assert_true(tv.rejected())


func test_no_voters_rejects_nothing() -> void:
	var tv := TeamVote.new([])
	assert_false(tv.rejected())
	assert_false(TeamVote.decide(0, 0))


func test_saying_yes_again_takes_the_no_back() -> void:
	var tv := TeamVote.new([1, 2])
	assert_false(tv.toggle(2), "toggle to no")
	assert_true(tv.rejected())
	assert_true(tv.toggle(2), "toggle back to yes")
	assert_false(tv.rejected())
	assert_true(tv.vote(1, true), "yes on a yes is fine")
	assert_eq(tv.no_count(), 0)


func test_a_non_voter_cannot_vote() -> void:
	var tv := TeamVote.new([1, 2])
	assert_false(tv.vote(7, false))
	assert_false(tv.toggle(7))
	assert_eq(tv.no_count(), 0)
	assert_eq(tv.votes, {})


func test_no_voters_come_out_in_slot_order_whatever_the_vote_order() -> void:
	var tv := TeamVote.new([3, 1, -1, 2])
	tv.vote(2, false)
	tv.vote(-1, false)
	tv.vote(3, false)
	assert_eq(tv.no_voters(), [3, -1, 2] as Array[int])


func test_set_voters_keeps_remaining_votes_and_drops_leavers() -> void:
	var tv := TeamVote.new([1, 2, 3])
	tv.vote(2, false)
	tv.vote(3, false)
	assert_true(tv.rejected())
	tv.set_voters([1, 2])
	assert_eq(tv.no_voters(), [2] as Array[int])
	assert_true(tv.rejected(), "1-1 is still a tie")
	tv.set_voters([1, 2, 4])
	assert_false(tv.rejected(), "a joiner votes yes")


func test_set_voters_ignores_junk_and_repeats() -> void:
	var tv := TeamVote.new([1, 1.0, "2", null, 3.5, 4])
	assert_eq(tv.voters, [1, 4] as Array[int])


func test_wire_round_trip() -> void:
	var tv := TeamVote.new([1, 2, 3, 4])
	tv.vote(4, false)
	tv.vote(1, false)
	var back := TeamVote.from_wire([1, 2, 3, 4], tv.no_voters())
	assert_eq(back.no_voters(), [1, 4] as Array[int])
	assert_eq(back.rejected(), tv.rejected())
	var junk := TeamVote.from_wire([1, 2], [9, "1", 2.0])
	assert_eq(junk.no_voters(), [2] as Array[int], "only voters, whole numbers")


func test_decide_matches_the_rule() -> void:
	assert_false(TeamVote.decide(3, 1))
	assert_false(TeamVote.decide(2, 1))
	assert_true(TeamVote.decide(2, 2))
	assert_true(TeamVote.decide(1, 3))
	assert_true(TeamVote.decide(0, 1))
	assert_false(TeamVote.decide(1, 0))


func test_same_inputs_same_result() -> void:
	var a := TeamVote.new([2, 1, 3])
	var b := TeamVote.new([2, 1, 3])
	for step: Array in [[3, false], [1, false], [3, true]]:
		a.vote(step[0], step[1])
		b.vote(step[0], step[1])
	assert_eq(a.no_voters(), b.no_voters())
	assert_eq(a.rejected(), b.rejected())
