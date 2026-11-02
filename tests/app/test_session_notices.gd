extends "res://tests/app/app_test_base.gd"
## The session screen's network notice and its menu's ERG hint (W3 NET-6, ZIH-6):
## - BRIEF 5.5 (host leaves: end gracefully): a client shows NET_HOST_DROPPED from the host's
##   peer_left until the host is back (peer_joined) or gone (host_left), and
##   NET_STATE_RECONNECTING while its own NetSession reconnects.
## - BRIEF 3.5: in ERG coast never means back, so the ride menu's hint says "keep pedaling"
##   (UI_SCAN_HINT_ERG) and a coast doesn't close it; out of ERG the normal hint is back.


func _client_session() -> AppSessionScreen:
	fx.give_profile(220.0, "Bea")
	var net := fx.fake_net()
	net.local_peer = 2
	net.host_peer = 1
	var a := PlayerSlot.new()
	a.peer_id = 1
	a.apply_look(0)
	var b := PlayerSlot.new()
	b.peer_id = 2
	b.apply_look(1)
	var start := {
		"type": "session_start",
		"v": 1,
		"game_id": "workout",
		"game_version": "1.0.0",
		"content_id": "e2e",
		"seed": 1,
		"players": [a.to_dict(), b.to_dict()],
		"options": {},
		"scaling": Wl.FAIR_FTP,
		"start_tick": 0
	}
	return (
		open_screen(AppSessionScreen.new(), {"role": Wl.CLIENT, "session_start": start})
		as AppSessionScreen
	)


func test_client_shows_the_host_dropped_notice_until_the_host_is_back() -> void:
	var s := _client_session()
	assert_false(s.net_notice.visible, "nothing to say at the start")
	fx.net.peer_left.emit(2, "dropped")
	assert_false(s.net_notice.visible, "another rider dropping is not the host")
	fx.net.peer_left.emit(1, "dropped")
	assert_true(s.net_notice.visible)
	assert_eq(s.net_notice.text, AppScreen.t("NET_HOST_DROPPED"))
	assert_ne(s.net_notice.text, "NET_HOST_DROPPED", "the net strings are loaded")
	fx.net.peer_joined.emit(1)
	assert_false(s.net_notice.visible, "the host is back")


func test_a_lost_room_says_so_and_the_results_repeat_it() -> void:
	var s := _client_session()
	fx.fake_net().refuse("dropped")
	assert_true(s.net_lost)
	assert_true(s.net_notice.visible)
	assert_eq(s.net_notice.text, AppScreen.t("NET_ROOM_LOST_CLIENT"))
	assert_false(s.host_left, "the host didn't choose this")
	s._finish(null)
	assert_eq(fx.app.state, "results")
	assert_true(bool(fx.app.params.get("net_lost", false)))


func test_host_left_clears_the_notice_and_ends_the_session() -> void:
	var s := _client_session()
	fx.net.peer_left.emit(1, "dropped")
	assert_true(s.net_notice.visible)
	fx.fake_net().refuse("host_left")
	assert_eq(s.net_notice_text(), "", "host_left: no more waiting")
	assert_true(s.host_left)
	assert_eq(fx.app.state, "results")


func test_reconnecting_notice_follows_the_net_state() -> void:
	var s := _client_session()
	fx.net.state_changed.emit(WlNetSession.STATE_RECONNECTING, "")
	assert_true(s.net_notice.visible)
	assert_eq(s.net_notice.text, AppScreen.t("NET_STATE_RECONNECTING"))
	fx.net.state_changed.emit(WlNetSession.STATE_JOINED, "")
	assert_false(s.net_notice.visible)


func test_the_notice_draws_above_the_hud() -> void:
	var s := _client_session()
	assert_same(s.net_notice.get_parent(), s.top_root)
	assert_gt(s.top_layer.layer, HudLayer.LAYER)


func test_a_solo_session_never_shows_the_host_notice() -> void:
	fx.give_profile()
	var s := (
		open_screen(
			AppSessionScreen.new(), {"role": Wl.SOLO, "game_id": "workout", "content_id": "e2e"}
		)
		as AppSessionScreen
	)
	fx.net.peer_left.emit(1, "dropped")
	assert_false(s.net_notice.visible)


# --- ERG hint (ZIH-6) ----------------------------------------------------------------------------


func _hint(m: PedalScanList) -> String:
	var h := m.find_child("Hint", true, false) as Label
	return h.text if h != null else ""


func test_ride_menu_in_erg_says_keep_pedaling_and_ignores_coast() -> void:
	fx.give_profile()
	var rider := fx.fake_trainer().rider as FakeRider
	rider.tm.mode = Wl.ERG
	var s := (
		open_screen(
			AppSessionScreen.new(), {"role": Wl.SOLO, "game_id": "workout", "content_id": "e2e"}
		)
		as AppSessionScreen
	)
	s.open_menu()
	s.tick(0.05)
	var m := s.active_menu()
	assert_not_null(m)
	assert_eq(
		_hint(m),
		TranslationServer.translate("UI_SCAN_HINT_ERG"),
		"in ERG the hint says keep pedaling"
	)
	assert_false(m.erg_auto_confirm, "the ride menu never auto-picks")
	s.feed_gesture(Wl.G_COAST)
	assert_true(
		s.overlay.visible, "a coast in ERG doesn't close the menu (coast never means back in ERG)"
	)
	rider.tm.mode = Wl.SIM
	s.tick(0.05)
	assert_eq(
		_hint(m),
		TranslationServer.translate("UI_SCAN_HINT"),
		"out of ERG: stop pedaling to go back"
	)
	s.feed_gesture(Wl.G_COAST)
	assert_false(s.overlay.visible, "and a coast backs out again")


func test_menus_follow_the_attached_riders_mode() -> void:
	fx.give_profile()
	var s := open_screen(AppSettingsScreen.new()) as AppSettingsScreen
	assert_eq(s.local_trainer_mode(), fx.input.local_mode())
	s.tick(0.05)
	assert_eq(
		_hint(s.active_menu()), TranslationServer.translate("UI_SCAN_HINT"), "menus ride SIM flat"
	)
