class_name HudLocalFeed
extends HudFeed
## A HudFeed that draws on one HudLayer only (HudLayer.local_feed()). The GameHost wraps it
## with network routing (BRIEF 3.6): on the host it decides which peer a call is for, on a
## client every call draws here whatever `peer` says. This feed itself ignores `peer` for
## toasts and banners and applies power_band only to gauges that show that peer.

var _layer: WeakRef = null


func _init(layer: HudLayer = null) -> void:
	if layer != null:
		_layer = weakref(layer)


func layer() -> HudLayer:
	if _layer == null:
		return null
	return _layer.get_ref() as HudLayer


func power_band(peer: int, lo_w: float, hi_w: float) -> void:
	var l := layer()
	if l != null:
		l.apply_power_band(peer, lo_w, hi_w)


func teammate_status(peer: int, status: Dictionary) -> void:
	var l := layer()
	if l != null:
		l.apply_teammate_status(peer, status)


func toast(key: String, args: Variant = [], _peer: int = 0) -> void:
	var l := layer()
	if l != null:
		l.show_toast(key, args)


func banner(key: String, args: Variant = [], seconds: float = 3.0, _peer: int = 0) -> void:
	var l := layer()
	if l != null:
		l.show_banner(key, args, seconds)


func readout(id: String, text: String) -> void:
	var l := layer()
	if l != null:
		l.set_readout(id, text)
