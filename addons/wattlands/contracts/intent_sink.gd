class_name IntentSink
extends RefCounted
## Where a game's own HUD widgets send intents (`ctx.intents.send`, BRIEF 3.6).
## Contract, frozen after W0; the sdk-runtime implements it.
##
## On a CLIENT the platform batches intents into Telemetry.intents at 5 Hz; in HOST and
## SOLO it puts them straight into the local rider's `frame.players[peer].intents` on the
## next sim step. An intent is a small JSON-safe Dictionary chosen by the game, for
## example {"k": "buy", "item": "ballista", "pad": 3}. The platform never edits intents:
## a game that needs to know how an intent was made tags it itself, for example "auto": 1 for
## a PedalScanList ERG auto-confirm (PedalScanList.item_picked reports via "auto") or
## "gesture": "surge" for an intent its local_intents() made from a gesture. Intents arrive
## once and in order (at most 32 per telemetry message, each <= 1 KB); games enforce their
## own rate limits.


func send(_intent: Dictionary) -> void:
	pass
