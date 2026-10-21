extends GutTest
## W3 SAF-3: a GameHost ignores sim_speed (keeps 1) when a local rider rides a real trainer,
## because every governor rule runs on platform time. MockTrainer sessions keep the speed.


func _setup_host(device: TrainerDevice, speed: float) -> GameHost:
	var host := GameHost.new()
	add_child_autofree(host)
	var rider := LocalRider.new()
	add_child_autofree(rider)
	rider.device = device
	(
		host
		. setup(
			{
				"game_id": "workout",
				"content_id": "e2e",
				"seed": 1,
				"role": Wl.SOLO,
				"players": [],
				"local_riders": {1: rider},
				"local_peer": 1,
				"sim_speed": speed,
				"headless": true,
				"record_rides": false,
			}
		)
	)
	return host


func test_sim_speed_is_ignored_with_a_real_trainer() -> void:
	var dev := TrainerDevice.new()
	autofree(dev)
	var host := _setup_host(dev, 4.0)
	assert_not_null(host.clock, "the clock exists after setup")
	assert_eq(host.clock.sim_speed, 1.0, "a real trainer forces sim speed 1")


func test_sim_speed_is_kept_with_mock_trainers() -> void:
	var dev := MockTrainer.from_spec("erg", 200.0)
	autofree(dev)
	var host := _setup_host(dev, 4.0)
	assert_eq(host.clock.sim_speed, 4.0, "mock sessions may run faster")
