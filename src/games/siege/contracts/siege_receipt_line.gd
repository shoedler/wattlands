class_name SiegeReceiptLine
extends SiegeRecord
## One item on the shared receipt (SiegeState.receipt, in the order the items were added). The
## picker's gold for it is held until the break ends; the line leaves the receipt when its picker
## takes it back or when the vote rejects it (TeamVote over the connected riders, the picker
## counting yes).

## SiegeIds.ITEMS.
var item: String = ""
## The station (upgrade) or the pad (scorpion, pad_upgrade) the item is for, else 0.
var at: int = 0
## What it costs, fixed when it was added.
var cost: int = 0
## The picker's slot.
var slot: int = 0
## The slots that voted no, in slot order (TeamVote.no_voters).
var no: Array[int] = []


## "<item>/<at>": the receipt holds one line per key.
func key() -> String:
	return SiegeReceiptLine.key_of(item, at)


static func key_of(p_item: String, p_at: int) -> String:
	return "%s/%d" % [p_item, p_at]
