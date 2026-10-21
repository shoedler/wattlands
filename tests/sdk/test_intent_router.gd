extends GutTest
## IntentRouter, ctx.intents (BRIEF 3.6; docs/OWNERSHIP.md CTX11, 3.1 C11, C14): intents keep
## their order, arrive once, are never edited, and one larger than 1 KB of JSON is dropped.


func test_send_and_take_keep_order_once() -> void:
	var r := IntentRouter.new()
	r.send({"k": "a"})
	r.send({"k": "b", "auto": 1})
	assert_eq(r.pending(), 2)
	assert_eq(r.take(), [{"k": "a"}, {"k": "b", "auto": 1}], "in order, unedited")
	assert_eq(r.take(), [], "each intent once")


func test_the_queue_holds_a_copy() -> void:
	var r := IntentRouter.new()
	var intent := {"k": "buy", "items": ["x"]}
	r.send(intent)
	(intent["items"] as Array).append("y")
	assert_eq(
		r.take(),
		[{"k": "buy", "items": ["x"]}],
		"a later change by the game never edits a sent intent"
	)


func test_an_intent_over_1_kb_is_dropped_with_a_warning() -> void:
	var r := IntentRouter.new()
	r.send({"k": "big", "blob": "x".repeat(IntentRouter.MAX_INTENT_BYTES)})
	assert_push_warning("dropped (max 1024)")
	r.send({"k": "fits", "blob": "x".repeat(IntentRouter.MAX_INTENT_BYTES - 40)})
	assert_eq(r.pending(), 1)
	assert_eq(str((r.take()[0] as Dictionary)["k"]), "fits")
