extends SceneTree
# Cuts the picker card and the content cards (320 x 180, 16:9) from in-engine renders of the view at
# 960 x 540 (cards.sh shoots them with tools/screenshot --scene and the view's fixture scene, no HUD).
# args: <render dir>; reads <dir>/<name>/view_fixture_scene.png for picker, mission, ambush, drill and roam
# (TankFixturesV4: the tank, the seam and the enemy across the valley).

const OUT := "res://assets/tank/cards/"
## name -> [the crop of the 960 x 540 render (x, y, w, h; 16:9), the card's file].
const CARDS := {
	"picker": [Rect2i(60, 0, 900, 486), "picker_card.png"],
	"mission": [Rect2i(200, 50, 760, 428), "card_mission.png"],
	"ambush": [Rect2i(250, 110, 660, 370), "card_ambush.png"],
	"drill": [Rect2i(20, 150, 480, 270), "card_drill.png"],
	"roam": [Rect2i(0, 0, 864, 486), "card_roam.png"],
}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0] if args.size() > 0 else "build/tank_cards/renders"
	for name: String in CARDS:
		var src := Image.load_from_file(dir.path_join(name).path_join("view_fixture_scene.png"))
		if src == null or src.is_empty():
			push_error("cards.gd: no render for %s in %s" % [name, dir])
			quit(1)
			return
		if src.get_width() != 960:
			src.resize(960, 540, Image.INTERPOLATE_NEAREST)
		var spec: Array = CARDS[name]
		var crop := src.get_region(spec[0])
		crop.resize(320, 180, Image.INTERPOLATE_LANCZOS)
		crop.convert(Image.FORMAT_RGB8)
		crop.save_png(OUT + str(spec[1]))
		print("cards: ", spec[1])
	quit()
