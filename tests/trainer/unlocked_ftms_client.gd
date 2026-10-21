extends FtmsClient
## Test-only FtmsClient whose hardware lock can be switched per instance, so the control
## flow can run against the fake KICKR (fake_kickr_transport.gd) and nothing else. The
## process keeps WATTLANDS_NO_HW_CONTROL=1 throughout (tools/godot.sh sets it); the
## production FtmsClient always reads the environment, and test_ftms_client.gd's lock tests
## use the real class. No class_name: tests load it by path.

## The lock this instance sees (off by default; tests turn it on to check the read-only path).
var lock_on: bool = false


func _is_hw_locked() -> bool:
	return lock_on
