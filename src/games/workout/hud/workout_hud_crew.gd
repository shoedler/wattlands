class_name WorkoutHudCrew
extends WorkoutHudCtl
## The crew, bottom centre (416 x 66 art px): one small card per rider, filling from the bottom row in
## slot order, so 1-4 riders is one row and 8 fit. Each card: the slot's chip (colour and shape, hollow
## for slots 4-7) and name, then raw W, %FTP, the in-band lamp and time in band, or RESCUE, AFK or LINK
## in its place. The local rider's card has the amber frame (BRIEF 3.7's compliance: lamp and TIB).

var cards: Array[Dictionary] = []


func refresh() -> void:
	cards = WorkoutHudModel.crew(game)


func paint() -> void:
	for i in cards.size():
		_card(cards[i], Rect2(WorkoutHudModel.card_rect(i)))


func _card(c: Dictionary, r: Rect2) -> void:
	D.plate(self, r, D.FRAME_HI if bool(c["local"]) else D.FRAME, false)
	var x := r.position.x + 4.0
	var y := r.position.y
	var flag := str(c["flag"])
	D.chip(self, int(c["slot"]), Vector2(x, y + 5))
	D.tall(self, x + 8, y + 3, D.fit_tall(str(c["name"]), r.size.x - 16.0), D.TEXT)
	var w := D.tall(self, x, y + 18, str(c["line"]), D.DIM if flag != "" else D.NUM)
	var right := r.end.x - 4.0
	if flag != "":
		# a flagged rider is out of band (BRIEF 4.6.3's stagger): the flag says it instead of a lamp
		D.tall_r(self, right, y + 18, flag, D.OVER if bool(c["flag_over"]) else D.DIM)
		return
	D.lamp(self, Vector2(x + w + 3.0, y + 20), bool(c["in_band"]), D.GOOD)
	D.tall_r(self, right, y + 18, str(c["tib"]), D.TEXT)
