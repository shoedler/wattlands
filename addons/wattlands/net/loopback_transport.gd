class_name LoopbackTransport
extends Transport
## In-process transport for tests and headless multi-peer simulations (BRIEF 5.4, P0).
## Owned by net-client; public API frozen after W0. Transports created from one
## LoopbackHub share rooms that behave like the relay (codes, peer ids from 1, to: 0
## broadcast excluding the sender, non-hosts send only to the host, peer_left/host_left,
## reconnect tokens). Messages go through JSON.stringify/parse_string so tests see the
## same float/int behaviour as the network; delivery happens in poll(), in order.
## Optional fault injection: drop(peer), latency_ticks.


## A new hub; create one transport per simulated peer with hub_transport(hub).
static func create_hub() -> RefCounted:
	return RefCounted.new()


static func hub_transport(_hub: RefCounted) -> LoopbackTransport:
	return LoopbackTransport.new()


## Simulate this peer's socket dropping (the hub sends peer_left with reason "dropped").
func simulate_drop() -> void:
	pass
