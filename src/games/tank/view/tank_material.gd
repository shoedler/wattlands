class_name TankMaterial
extends RefCounted
## The armour's soft shading at load (brief 3 "Not chunky pixel art"): large tonal patches, soot
## streaks and rust blotches over the generated plates, with the seams and rivets kept crisp. Used by
## TankPlaceholderArt.material_grade for the hulls, turrets, enemies and the Behemoth.

const G0 := Color("#07080a")
const G1 := Color("#0f1012")
const G2 := Color("#17181b")
const G3 := Color("#202124")
const G4 := Color("#2a2b2e")
const G5 := Color("#353739")
const G6 := Color("#424446")
const G7 := Color("#525456")
const G8 := Color("#666869")
const G9 := Color("#808182")
const G10 := Color("#a3a4a4")
const G11 := Color("#cfd0cf")
const O0 := Color("#59636c")
const O2 := Color("#4b5561")
const C0 := Color("#2e3944")
const R0 := Color("#3a2a24")

## Luminance gap from the local mean above which a pixel on a line (a seam, a lit plate edge, a rivet
## row) is kept as detail; fainter streaks and dust are averaged into the plate.
const DETAIL_LUM := 0.035


## Armour shading in large soft patches instead of per-pixel speckle (the round 2 scene critic):
## every grey or slate armour pixel takes the 11 x 11 mean of its plate, quantised to the five plate
## greys #0f1012..#353739 (never brighter, so no broad plate turns pale, the Bulwark's glacis
## included), except detail: a pixel standing DETAIL_LUM off the mean on a line of like pixels
## (along its row or its column: plate seams, lit plate edges) or in a rivet row keeps its tone
## (capped at #525456). Over that, soft soot streaks running down the plates (one tone darker), a
## slight light-to-dark grade from the upper plates to the lower and dark rust patches 4-10 px
## across on the lower hull, from a smooth hash noise, so the crew's tank, the
## enemies and the Behemoth share one material. Earth and rust pixels (the mud band) are left alone.
static func tonal_patches(img: Image, id: String) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var steel_keys := {}
	# Greys, slates and the olive greys are all plate; browns and rust (mud, rust) are left alone.
	var olives: Array[Color] = [Color("#2b2a24"), Color("#3d3c33"), Color("#545246")]
	for col: Color in [G0, G1, G2, G3, G4, G5, G6, G7, G8, G9, G10, G11, O0, O2, C0] + olives:
		steel_keys[col.to_rgba32()] = true
	var lum := PackedFloat32Array()
	lum.resize(w * h)
	var steel := PackedByteArray()
	steel.resize(w * h)
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			var i := y * w + x
			if c.a > 0.5 and steel_keys.has(c.to_rgba32()):
				steel[i] = 1
				lum[i] = c.get_luminance()
	# Integral images of luminance and count over the steel pixels.
	var sum := PackedFloat32Array()
	var cnt := PackedInt32Array()
	sum.resize((w + 1) * (h + 1))
	cnt.resize((w + 1) * (h + 1))
	for y in h:
		var row_s := 0.0
		var row_c := 0
		for x in w:
			var i := y * w + x
			if steel[i] == 1:
				row_s += lum[i]
				row_c += 1
			var o := (y + 1) * (w + 1) + x + 1
			sum[o] = sum[o - (w + 1)] + row_s
			cnt[o] = cnt[o - (w + 1)] + row_c
	var plate: Array[Color] = [G1, G2, G3, G4, G5]
	# The sprite's own mean plate tone: local means are pulled two thirds of the way toward it, so the plates read
	# as one material with soft variation, never as camouflage patches.
	var total := 0.0
	var count := 0
	for i in w * h:
		if steel[i] == 1:
			total += lum[i]
			count += 1
	var global_mean := total / maxf(float(count), 1.0)
	var rusty := id.begins_with("hull_") or id.begins_with("enemy_") or id == "boss_hull"
	var details: Array[Color] = [G0, G1, G2, G3, G4, G5, G6, G7]
	var seed_value := absi(id.hash()) % 7919
	var src := img.duplicate() as Image
	var rad := 5
	for y in h:
		for x in w:
			var i := y * w + x
			if steel[i] == 0:
				continue
			var x0 := maxi(x - rad, 0)
			var y0 := maxi(y - rad, 0)
			var x1 := mini(x + rad + 1, w)
			var y1 := mini(y + rad + 1, h)
			var n := (
				cnt[y1 * (w + 1) + x1]
				- cnt[y0 * (w + 1) + x1]
				- cnt[y1 * (w + 1) + x0]
				+ cnt[y0 * (w + 1) + x0]
			)
			var m := (
				(
					sum[y1 * (w + 1) + x1]
					- sum[y0 * (w + 1) + x1]
					- sum[y1 * (w + 1) + x0]
					+ sum[y0 * (w + 1) + x0]
				)
				/ maxf(float(n), 1.0)
			)
			var l := lum[i]
			if (
				absf(l - m) > DETAIL_LUM
				and (
					_line_pixel(lum, steel, w, h, x, y, m)
					or (
						_isolated(lum, w, h, x, y)
						and TankPlaceholderArt._rivet_row(lum, w, h, x, y)
					)
				)
			):
				img.set_pixel(x, y, _nearest_lum(details, l))
				continue
			# Soot runs down the plates in long soft streaks; the upper plates catch a little more
			# light than the lower ones.
			var soot := smooth_noise(x * 3, y, 14.0, seed_value)
			var t := (
				global_mean + (m - global_mean) * 0.35 + 0.025 * (1.0 - 2.0 * float(y) / float(h))
			)
			if soot > 0.7:
				t -= 0.04
			var rust := smooth_noise(x, y, 5.0, seed_value + 101)
			if rusty and rust > 0.88 and y > int(h * 0.55):
				img.set_pixel(x, y, R0)
				continue
			img.set_pixel(x, y, _nearest_lum(plate, t))
	# A plate edge left one pixel wide by the mean (a seam's lit lip) is kept from the source.
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			if steel[y * w + x] == 0:
				continue
			var c := src.get_pixel(x, y)
			if c == G0 and img.get_pixel(x, y) != G0:
				# Outline pixels (the silhouette's dark edge) stay dark.
				var edge := false
				for d: Vector2i in [
					Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
				]:
					if src.get_pixel(x + d.x, y + d.y).a < 0.5:
						edge = true
				if edge:
					img.set_pixel(x, y, G0)


## True when (x, y) lies on a thin run of at least four like pixels (within 0.03 of it and off the
## mean `m` the same way) along its row or its column, with unlike pixels across it: a seam or a lit
## plate edge, not a scratch, dust or the inside of a lighter patch.
static func _line_pixel(
	lum: PackedFloat32Array, steel: PackedByteArray, w: int, h: int, x: int, y: int, m: float
) -> bool:
	var l := lum[y * w + x]
	var sgn := signf(l - m)
	for axis in 2:
		var run := 1
		for side: int in [-1, 1]:
			for d in range(1, 4):
				var xx := x + side * d * (1 - axis)
				var yy := y + side * d * axis
				if xx < 0 or yy < 0 or xx >= w or yy >= h:
					break
				var j := yy * w + xx
				if steel[j] == 0 or absf(lum[j] - l) > 0.03 or signf(lum[j] - m) != sgn:
					break
				run += 1
		if run < 4:
			continue
		# A line is thin: across it (one pixel either side) the plate is back near the mean.
		var thin := true
		for side: int in [-1, 1]:
			var xx := x + side * axis
			var yy := y + side * (1 - axis)
			if xx < 0 or yy < 0 or xx >= w or yy >= h:
				continue
			var j := yy * w + xx
			if steel[j] == 1 and absf(lum[j] - l) <= 0.03:
				thin = false
		if thin:
			return true
	return false


## True when the pixel stands alone: its four neighbours all differ from it by more than 0.02 (a
## rivet head, not a pixel of a scratched or speckled patch).
static func _isolated(lum: PackedFloat32Array, w: int, h: int, x: int, y: int) -> bool:
	var l := lum[y * w + x]
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var xx := x + d.x
		var yy := y + d.y
		if xx < 0 or yy < 0 or xx >= w or yy >= h:
			continue
		if absf(lum[yy * w + xx] - l) <= 0.02:
			return false
	return true


## The colour of `ramp` nearest luminance `l`.
static func _nearest_lum(ramp: Array[Color], l: float) -> Color:
	var best := ramp[0]
	var bd := INF
	for c in ramp:
		var d := absf(c.get_luminance() - l)
		if d < bd:
			bd = d
			best = c
	return best


## A smooth 0 .. 1 value noise (bilinear between hashed lattice points `cell` px apart).
static func smooth_noise(x: int, y: int, cell: float, salt: int) -> float:
	var fx := float(x) / cell
	var fy := float(y) / cell
	var ix := int(floor(fx))
	var iy := int(floor(fy))
	var tx := fx - float(ix)
	var ty := fy - float(iy)
	tx = tx * tx * (3.0 - 2.0 * tx)
	ty = ty * ty * (3.0 - 2.0 * ty)
	var a := _lattice(ix, iy, salt)
	var b := _lattice(ix + 1, iy, salt)
	var c := _lattice(ix, iy + 1, salt)
	var d := _lattice(ix + 1, iy + 1, salt)
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)


static func _lattice(x: int, y: int, salt: int) -> float:
	var n := (x * 374761393 + y * 668265263 + salt * 1274126177) & 0x7FFFFFFF
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7FFFFFFF
	n = n ^ (n >> 16)
	return float(n & 0xFFFF) / 65536.0
