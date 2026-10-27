extends SceneTree
# Tiny crewmen as pixel grids (11-13 px tall at 960x540). Writes crew_frames/*.png and crew_sheet.png.

var F = load("res://build/v2/font.gd")
const CW := 16
const CH := 14
const OUT := "res://assets/tank/v2/"

const PAL := {
	"H": Color8(52, 56, 40), "h": Color8(110, 106, 72), "F": Color8(236, 174, 110), "f": Color8(128, 82, 54),
	"U": Color8(46, 52, 36), "u": Color8(92, 98, 64), "B": Color8(22, 20, 16), "K": Color8(218, 160, 100),
	"w": Color8(116, 80, 46), "S": Color8(172, 172, 162), "s": Color8(92, 92, 86), "C": Color8(18, 18, 18),
	"c": Color8(74, 70, 64), "Y": Color8(226, 182, 86), "y": Color8(150, 112, 48), "R": Color8(156, 152, 142),
	"M": Color8(40, 38, 34), "m": Color8(80, 74, 64), "L": Color8(255, 246, 196), "l": Color8(255, 204, 116),
	"P": Color8(74, 76, 66), "p": Color8(50, 52, 46), "G": Color8(96, 255, 128), "r": Color8(255, 84, 64),
	"A": Color8(255, 200, 72), "O": Color8(255, 150, 60),
}

# Each frame: up to 14 rows (top to bottom), feet on row 13, facing right. Short rows are padded with '.'.
const POSES := {
	"stoker": [
		[
			"", "", "", "",
			"..hh",
			".HHHH",
			".HHHHH",
			"..fF",
			".uUUUK",
			".uUUUUKw",
			".uUUU...ww",
			"..BB......wSS",
			"..UUU.....SSSC",
			"..B..B....cCCC",
		],
		[
			"", "",
			"..hh",
			".HHHH",
			".HHHHH",
			"..fF",
			"..UU",
			".uUUU",
			".uUUUKwwwSSc",
			".uUUK....SS",
			"..BB",
			"..UU",
			"..U.U",
			"..B.B......cCC",
		],
		[
			"..........c",
			"...........C",
			"..hh.....SSc",
			".HHHH...wSS",
			".HHHHH.w",
			"..fF.Kw",
			"..UUK",
			".uUUU",
			".uUUU",
			".uUUU",
			"..BB",
			"..UU",
			"..U..U",
			"..B...B....cCC",
		],
		[
			"", "",
			"..hh",
			".HHHH",
			".HHHHH",
			"..fF",
			"..UU",
			".uUUUK",
			".uUUU.Kw",
			".uUUU...ww",
			"..BB......wSS",
			"..UU.......SS",
			"..U.U",
			"..B.B......cCC",
		],
	],
	"loader": [
		[
			"", "",
			"..hh",
			".HHHH",
			".HHHHH",
			"..fF",
			"..UU",
			".uUyYYYYR",
			".uUyyyyy",
			".uUUK",
			"..BB",
			"..UUU",
			".u...U",
			".B....B",
		],
		[
			"",
			"..hh",
			".HHHH",
			".HHHHH",
			"..fF",
			"..UU",
			".uUyYYYYR",
			".uUyyyyy",
			".uUUK",
			"..BB",
			"..UU",
			"..UU",
			"..Uu",
			"..BB",
		],
		[
			"", "",
			"..hh",
			".HHHH",
			".HHHHH",
			"..fF",
			"..UU",
			".uUyYYYYR",
			".uUyyyyy",
			".uUUK",
			"..BB",
			"..UUU",
			".U...u",
			".B....B",
		],
		[
			"",
			"..hh",
			".HHHH",
			".HHHHH",
			"..fF",
			"..UU",
			".uUyYYYYR",
			".uUyyyyy",
			".uUUK",
			"..BB",
			"..UU",
			"..UU",
			"..uU",
			"..BB",
		],
	],
	"loader_climb": [
		[
			"",
			".....s...s",
			"..hh.sYR.s",
			".HHHHsYYss",
			".HHHHHyK.s",
			"..fF.sKs.s",
			"..UUKs...s",
			".uUUUsssss",
			".uUUUs...s",
			".uUUUs...s",
			"..BBUsssss",
			"..U..UB..s",
			"..B..s...s",
			".....sssss",
		],
		[
			".....sYR.s",
			"..hh.sYY.s",
			".HHHHsyKss",
			".HHHHHsK.s",
			"..fF.s...s",
			"..UUKsssss",
			".uUUUs...s",
			".uUUUs...s",
			".uUUUsssss",
			"..BB.s...s",
			"..UUUs...s",
			"..U..UBsss",
			"..B..s...s",
			".....sssss",
		],
	],
	"engineer": [
		[
			"", "",
			"..hh..S",
			".HHHH.SS",
			".HHHHHS",
			"..fF.K",
			"..UUK",
			".uUUU",
			".uUUU",
			".uUUU",
			"..BB",
			"..UU",
			"..U.U",
			"..B.B",
		],
		[
			"", "",
			"..hh",
			".HHHH",
			".HHHHH...S",
			"..fF.KSSS",
			"..UUK....S",
			".uUUU",
			".uUUU",
			".uUUU",
			"..BB",
			"..UU",
			"..U.U",
			"..B.B",
		],
		[
			"", "",
			"..hh",
			".HHHH",
			".HHHHH",
			"..fF",
			"..UUKK",
			".uUUU.S.A",
			".uUUU.SS",
			".uUUU.S",
			"..BB",
			"..UU",
			"..U.U",
			"..B.B",
		],
	],
	"gunner": [
		[
			"", "",
			"..hh...s",
			".HHHH..s",
			".HHHHHKs",
			"..fF.K",
			"..UUK...MMMMMMMM",
			".uUUU...MyymmmmM",
			".uUUU...MyyMMMMM",
			".uUUU...MMMMMMMM",
			"..BB......mM",
			"..UU......mM",
			"..U.U.....mM",
			"..B.B....MMMM",
		],
		[
			"", "", "",
			"..hh",
			".HHHH",
			".HHHHH.ss",
			"..fF.KKs",
			"..UUK...MMMMMMMM",
			".uUUU...MyymmmmM",
			".uUUU...MyyMMMMM",
			"..BB....MMMMMMMM",
			"..UUU.....mM",
			".U...U....mM",
			".B....B..MMMM",
		],
		[
			"", "", "",
			"..hh",
			".HHHH",
			".HHHHH",
			"..fF",
			"..UU....MMMMMMMM",
			".uUUUKKsMyymmmmM",
			".uUUU...MyyMMMMM",
			"..BB....MMMMMMMM",
			"..UU......mM",
			"..U.U.....mM",
			"..B.B....MMMM",
		],
	],
	"commander": [
		[
			"", "",
			"..hh",
			".HHHH",
			".HHHHH.mMMM",
			"..fF.KKMMMMLl",
			"..UUK..mMMM",
			".uUUU...s",
			".uUUU...s",
			".uUUU...s",
			"..BB....s",
			"..UU....s",
			"..U.U..sss",
			"..B.B..sss",
		],
		[
			"", "",
			"..hh.......l",
			".HHHH....MLl",
			".HHHHH.mMMM",
			"..fF.KKMMM",
			"..UUK..mM",
			".uUUU...s",
			".uUUU...s",
			".uUUU...s",
			"..BB....s",
			"..UU....s",
			"..U.U..sss",
			"..B.B..sss",
		],
		[
			"", "",
			"..hh",
			".HHHH",
			".HHHHH",
			"..fF.KKmMM",
			"..UUK..MMMM",
			".uUUU..mMMMLl",
			".uUUU...s..l",
			".uUUU...s",
			"..BB....s",
			"..UU....s",
			"..U.U..sss",
			"..B.B..sss",
		],
	],
	"tech": [
		[
			"",
			".......PPPPPP",
			"..hh...PpGpAP",
			".HHHH..PppppP",
			".HHHHH.PpSpSP",
			"..fF...PpppPP",
			"..UU..KPprpGP",
			".uUUUK.PpppPP",
			".uUUU..PPPPPP",
			".uUUU....pp",
			"..BB.....pp",
			"..UU.....pp",
			"..U.U....pp",
			"..B.B...pppp",
		],
		[
			"",
			".......PPPPPP",
			"..hh..KPpApGP",
			".HHHH.KPppppP",
			".HHHHHKPpSpSP",
			"..fF.K.PpppPP",
			"..UUK..PpGprP",
			".uUUU..PpppPP",
			".uUUU..PPPPPP",
			".uUUU....pp",
			"..BB.....pp",
			"..UU.....pp",
			"..U.U....pp",
			"..B.B...pppp",
		],
		[
			"",
			".......PPPPPP",
			"..hh...PpGpGP",
			".HHHH..PppppP",
			".HHHHH.PpSKSP",
			"..fF..KKpppPP",
			"..UUKK.PprpAP",
			".uUUU..PpppPP",
			".uUUU..PPPPPP",
			".uUUU....pp",
			"..BB.....pp",
			"..UU.....pp",
			"..U.U....pp",
			"..B.B...pppp",
		],
	],
}


func frame_img(rows: Array) -> Image:
	var img := Image.create(CW, CH, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# rows are bottom-aligned: a frame with fewer than CH rows starts lower
	var off := CH - rows.size()
	for y in rows.size():
		var row: String = rows[y]
		for x in mini(row.length(), CW):
			var ch := row[x]
			if ch != "." and PAL.has(ch):
				img.set_pixel(x, y + off, PAL[ch])
	return img


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "crew_frames"))
	var names: Array = POSES.keys()
	var sc := 6
	var lab_w := 110
	var small_w := 4 * (CW + 6) + 10
	var big_w := 4 * (CW * sc + 10)
	var row_h := CH * sc + 16
	var sheet := Image.create(lab_w + small_w * 2 + big_w + 10, names.size() * row_h + 44, false, Image.FORMAT_RGBA8)
	sheet.fill(Color8(18, 16, 14))
	var wall := Color8(120, 88, 54)
	var dark := Color8(34, 28, 22)
	F.draw(sheet, 6, 8, "CREW: 16X14 CELLS, FIGURES 11-13 PX TALL AT 960X540, FACING RIGHT (MIRROR FOR LEFT)", Color8(200, 190, 170))
	F.draw(sheet, 6, 18, "PER ROW: FRAMES AT 1X ON LIT WALL, 1X ON DARK, THEN 6X. FRAME ORDER LEFT TO RIGHT", Color8(150, 140, 120))
	for pi in names.size():
		var nm: String = names[pi]
		var frames: Array = POSES[nm]
		var y0 := 40 + pi * row_h
		F.draw(sheet, 6, y0 + 4, nm.replace("_", " "), Color8(230, 210, 160), 2)
		F.draw(sheet, 6, y0 + 20, "%d FRAMES" % frames.size(), Color8(150, 140, 120))
		for fi in frames.size():
			var img := frame_img(frames[fi])
			img.save_png(OUT + "crew_frames/%s_%d.png" % [nm, fi])
			var sx := lab_w + fi * (CW + 6)
			sheet.fill_rect(Rect2i(sx - 3, y0 + 1, CW + 6, CH + 6), wall)
			sheet.blend_rect(img, Rect2i(0, 0, CW, CH), Vector2i(sx, y0 + 4))
			var sx2 := lab_w + small_w + fi * (CW + 6)
			sheet.fill_rect(Rect2i(sx2 - 3, y0 + 1, CW + 6, CH + 6), dark)
			sheet.blend_rect(img, Rect2i(0, 0, CW, CH), Vector2i(sx2, y0 + 4))
			var big := img.duplicate()
			big.resize(CW * sc, CH * sc, Image.INTERPOLATE_NEAREST)
			var bx := lab_w + small_w * 2 + fi * (CW * sc + 10)
			sheet.fill_rect(Rect2i(bx, y0, CW * sc, CH * sc), wall.darkened(0.3))
			sheet.blend_rect(big, Rect2i(0, 0, CW * sc, CH * sc), Vector2i(bx, y0))
			F.draw(sheet, bx + 2, y0 + CH * sc + 3, str(fi), Color8(150, 140, 120))
	sheet.save_png(OUT + "crew_sheet.png")
	print("crew poses: ", names)
	quit()
