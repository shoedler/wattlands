class_name SiegeReceiptModel
extends RefCounted
## The shared receipt as the HUD shows it (docs/games/siege.md 2.4 "Shop", 3 HUD): every item picked
## in this break and not yet bought, in the order they were added, with who picked it and the vote
## on it, the total, when it is bought and the two rules. Pure: SiegeReceiptPanel draws it.
##
## face() is {"title", "bought", "rows", "hidden", "more", "total", "total_label", "empty", "rules"}; a row
## is {"name", "cost", "by", "yes", "no", "mine" (the local rider's own item), "my_no" (the local
## rider voted no on it)}. At most MAX_ROWS rows show; "hidden" counts the rest (the total still
## counts them).

## Rows the plate has room for.
const MAX_ROWS := 4


static func face(game: SiegeGame) -> Dictionary:
	var s := game.state
	var tx := SiegeHudModel.strings_of(game)
	var me := SiegeHudModel.own_rider(game)
	var rows: Array[Dictionary] = []
	for line in s.receipt:
		var tv := s.vote_on(line)
		var picker := s.rider_at(line.slot)
		(
			rows
			. append(
				{
					"name": SiegeShopModel.text_of(s, tx, line.item, line.at),
					"cost": line.cost,
					"by": SiegeHudModel.rider_name(game, picker) if picker != null else "",
					"yes": tv.yes_count(),
					"no": tv.no_count(),
					"mine": me != null and line.slot == me.slot,
					"my_no": me != null and line.no.has(me.slot),
				}
			)
		)
	var shown := rows.slice(0, MAX_ROWS) if rows.size() <= MAX_ROWS else rows.slice(0, MAX_ROWS - 1)
	return {
		"title": tx.t("SIEGE_RECEIPT_TITLE"),
		"bought":
		tx.t("SIEGE_RECEIPT_BOUGHT", [HudWidget.clock_text(SiegeHudModel.phase_remaining_s(s))]),
		"rows": shown,
		"hidden": rows.size() - shown.size(),
		"more": tx.t("SIEGE_RECEIPT_MORE", [rows.size() - shown.size()]),
		"total": s.receipt_total(),
		"total_label": tx.t("SIEGE_RECEIPT_TOTAL"),
		"empty": tx.t("SIEGE_RECEIPT_EMPTY") if rows.is_empty() else "",
		"rules": [tx.t("SIEGE_RECEIPT_RULE_1"), tx.t("SIEGE_RECEIPT_RULE_2")],
	}
