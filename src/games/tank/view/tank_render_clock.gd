class_name TankRenderClock
extends SnapRenderClock
## The clock the view draws the world at (SnapRenderClock). The smallest delay starts at one tick:
## the host and SOLO see every 0.05 s tick. TankView sets CLIENT_DELAY_S on a client.


func _init() -> void:
	min_delay_s = HOST_DELAY_S
