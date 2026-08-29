extends RefCounted
class_name InteriorGenerator
## Procedurally generates purpose-built interior art for the Localhost apartment
## plus the shared structure props that dress every region. Everything follows
## the Visual Bible: 4-tone shading lit from the top-left, 1px outlines, rim
## light on silhouettes, dithered gradients instead of flat fills, and
## WHITE_HOT cores inside anything emissive so the HDR bloom picks it up.
## Also emits the shared fx/decal manifest (light cookie, grime, wall-base AO).

const OUT_DIR := "res://assets/textures/generated/"

# Bible palette (see docs/VISUAL_BIBLE.md). Outline is #0A0C16 at 85%.
const OUTLINE := Color(0.039, 0.047, 0.086, 0.85)
const WHITE_HOT := Color(0.957, 0.976, 1.0)
const CYAN := Color(0.141, 0.941, 0.863)
const CYAN_HOT := Color(0.49, 1.0, 0.941)
const AMBER := Color(1.0, 0.69, 0.125)
const ACID := Color(0.659, 1.0, 0.243)
const MAGENTA := Color(1.0, 0.176, 0.584)
const GOLD := Color(1.0, 0.827, 0.302)
const RED := Color(1.0, 0.278, 0.341)
const RIM_WARM := Color(1.0, 0.85, 0.62)     # localhost furniture rim (amber-ish)
const RIM_COOL := Color(0.94, 0.95, 1.0)     # near-white rim for tintable structs

var _rng := RandomNumberGenerator.new()

func generate() -> void:
	_rng.seed = 133742
	_floor_tiles()
	_rug()
	_wall_tiles()
	_window()
	_desk()
	_monitor()
	_server_rack()
	_bed()
	_fridge()
	_coffee()
	_plant()
	_node_modules()
	_bookshelf()
	_chair()
	_whiteboard()
	_door()
	_tech_floor()
	_struct_slab()
	_struct_crate()
	_struct_console()
	_struct_tower()
	_struct_orb()
	_struct_arch()
	_fx_radial()
	_decal_grime()
	_decal_ao_edge()
	print("Interior assets generated.")

# ------------------------------------------- themed region primitives -------
# These are drawn near-grayscale so region palettes can tint them via modulate.
# Emissive details keep their own hue (or sit near-white so the tint owns them).

func _tech_floor() -> void:
	# Machined deck plating: two 32px panels per axis, each with a beveled lip,
	# brushed grain, corner rivets and per-panel value jitter so the grid never
	# reads as a stamped checkerboard. Tiles seamlessly against itself.
	# Every region multiplies this one texture by its own tint, so its STRUCTURE
	# has to survive being scaled down to a fifth of its value. Deep seams and a
	# bright bevel lip do that; a flat mid-grey does not, which is how nine
	# regions ended up sharing one muddy floor.
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	# Base value is left where region_builder calibrated its floor tints against
	# (0.50); only the STRUCTURE gets stronger here.
	var base := Color(0.50, 0.51, 0.56)
	for y in 64:
		for x in 64:
			var px := x & 31
			var py := y & 31
			var c := base
			# per-panel value jitter (each 32px quadrant a hair different)
			var pj := float(_hash(x >> 5, (y >> 5) + 3) % 7 - 3) / 90.0
			c = Color(c.r + pj, c.g + pj, c.b + pj, 1.0)
			# brushed diagonal grain + subtle 2x2 dither on the broad face
			var n := float(_hash(x, y) % 8) / 300.0
			if (((x + y) >> 1) & 3) == 0:
				n += 0.014
			c = Color(c.r + n, c.g + n, c.b + n, 1.0)
			# machined bevel: dark seam, lit lip below it, shadowed far edge
			if px == 0 or py == 0:
				c = base.darkened(0.46)
			elif px == 1 or py == 1:
				c = base.lightened(0.24)
			elif px == 31 or py == 31:
				c = base.darkened(0.26)
			img.set_pixel(x, y, c)
	# wear: scuffed traffic marks inside the panels, never across the seams
	for sc in 7:
		var sx := 4 + _hash(sc, 61) % 24
		var sy := 4 + _hash(sc, 67) % 24
		var quad := _hash(sc, 71) % 4
		var ox := (quad & 1) * 32
		var oy := ((quad >> 1) & 1) * 32
		for j in 3 + _hash(sc, 73) % 6:
			var tx: int = ox + mini(sx + j, 30)
			var ty: int = oy + mini(sy + j / 3, 30)
			img.set_pixel(tx, ty, img.get_pixel(tx, ty).darkened(0.14))
	# corner rivets with a top-left glint
	for pan in [Vector2i(0, 0), Vector2i(32, 0), Vector2i(0, 32), Vector2i(32, 32)]:
		for rp in [Vector2i(5, 5), Vector2i(26, 5), Vector2i(5, 26), Vector2i(26, 26)]:
			var rx: int = pan.x + rp.x
			var ry: int = pan.y + rp.y
			_rect(img, rx, ry, 2, 2, base.darkened(0.42))
			img.set_pixel(rx, ry, base.lightened(0.30))
	# one vent slot per tile to break repetition (still tiles cleanly)
	for vx in range(40, 56, 3):
		_rect(img, vx, 44, 2, 6, base.darkened(0.38))
		_rect(img, vx, 43, 2, 1, base.lightened(0.10))
	_save(img, "tech_floor.png")

func _struct_slab() -> void:
	# Monolith slab. Grayscale body, machined grooves, and a service panel with
	# near-white status glyphs that inherit the region tint and bloom.
	var img := Image.create(80, 120, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# Structures are drawn near-grayscale and then MULTIPLIED by a region tint
	# (0.44-0.78), so a mid-grey body lands as a near-black silhouette on a dark
	# floor. Every shared struct sits a notch brighter than it used to.
	var g := Color(0.66, 0.67, 0.72)
	_shadow(img, 40, 112, 34, 5, 0.32)
	_vgrad(img, 8, 4, 64, 104, g.lightened(0.10), g.darkened(0.22))
	_rect(img, 8, 4, 64, 3, g.lightened(0.26))       # lit top cap
	_rect(img, 8, 4, 4, 104, g.lightened(0.16))      # lit left face
	_rect(img, 68, 4, 4, 104, g.darkened(0.30))      # shadowed right face
	_rect(img, 8, 105, 64, 3, g.darkened(0.40))      # ground contact
	# segment grooves: shadow line + lit lip below (light comes from above)
	for sy in range(16, 100, 22):
		_rect(img, 12, sy, 56, 2, g.darkened(0.34))
		_rect(img, 12, sy + 2, 56, 1, g.lightened(0.10))
	# inset service panel with a glowing status column
	_rect(img, 30, 42, 20, 30, g.darkened(0.30))
	_rect(img, 31, 43, 18, 28, g.darkened(0.12))
	_rect(img, 31, 43, 18, 1, g.darkened(0.42))      # AO under the panel lip
	for gy in range(48, 68, 7):
		_glow(img, 40, gy, Color(0.90, 0.93, 0.97))
	# weathering cracks
	_line(img, 20, 8, 26, 30, g.darkened(0.30))
	_line(img, 58, 78, 52, 102, g.darkened(0.30))
	_finish(img, RIM_COOL, 0.45)
	_save(img, "struct_slab.png")

func _struct_crate() -> void:
	# Plank crate with cross braces and steel corner brackets. Contents unknown,
	# which in this economy is probably for the best.
	var img := Image.create(76, 66, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var g := Color(0.70, 0.63, 0.55)
	_shadow(img, 38, 59, 34, 4, 0.30)
	_bevel(img, 3, 4, 70, 54, g)
	# vertical plank seams: shadow + caught-light edge
	for px in range(13, 70, 10):
		_rect(img, px, 6, 1, 50, g.darkened(0.22))
		_rect(img, px + 1, 6, 1, 50, g.lightened(0.08))
	# short grain dashes so the wood is not a flat fill
	for gy in range(9, 55, 5):
		for gx in range(7, 66, 9):
			if _hash(gx, gy) % 3 == 0:
				_rect(img, gx, gy, 4, 1, g.darkened(0.10))
	# diagonal braces, upper edge catching the light
	_line(img, 5, 6, 70, 55, g.darkened(0.30))
	_line(img, 5, 5, 70, 54, g.lightened(0.12))
	_line(img, 70, 6, 5, 55, g.darkened(0.30))
	_line(img, 70, 5, 5, 54, g.lightened(0.12))
	# steel corner brackets with bolt glints
	var steel := Color(0.72, 0.73, 0.77)
	for bc in [Vector2i(3, 4), Vector2i(67, 4), Vector2i(3, 52), Vector2i(67, 52)]:
		_rect(img, bc.x, bc.y, 6, 6, steel.darkened(0.20))
		_rect(img, bc.x, bc.y, 6, 2, steel)
		_px(img, bc.x + 2, bc.y + 3, Color(0.92, 0.93, 0.95))
	# stencil mark
	_rect(img, 30, 24, 14, 2, g.darkened(0.35))
	_rect(img, 30, 28, 10, 2, g.darkened(0.35))
	_finish(img, Color(0.95, 0.94, 0.90), 0.40)
	_save(img, "struct_crate.png")

func _struct_console() -> void:
	# Terminal kiosk. The cursor has been blinking since before you were born.
	var img := Image.create(88, 96, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var body := Color(0.50, 0.52, 0.58)
	_shadow(img, 44, 90, 30, 4, 0.32)
	_bevel(img, 30, 68, 28, 22, body.darkened(0.32))     # stand
	_bevel(img, 6, 4, 76, 64, body)
	# recessed screen (stays cyan): bezel AO ring, scanlines, hot cursor
	_rect(img, 13, 11, 62, 42, Color(0.03, 0.10, 0.12))
	_rect(img, 14, 12, 60, 40, Color(0.10, 0.62, 0.66))
	for ly in range(14, 50, 3):
		_rect(img, 16, ly, 56, 1, Color(0.05, 0.34, 0.38, 0.55))
	# output lines of varying importance
	_rect(img, 18, 16, 26, 2, Color(0.55, 0.97, 0.95))
	_rect(img, 18, 22, 38, 2, Color(0.40, 0.90, 0.90))
	_rect(img, 18, 28, 18, 2, Color(0.55, 0.97, 0.95))
	_rect(img, 18, 34, 30, 2, Color(0.40, 0.90, 0.90))
	_glow(img, 50, 41, CYAN_HOT)                          # the eternal cursor
	# glass glare, top-right
	_line(img, 60, 13, 72, 25, Color(1, 1, 1, 0.16))
	_line(img, 56, 13, 73, 30, Color(1, 1, 1, 0.10))
	# key deck + status LED
	_rect(img, 28, 56, 32, 9, body.darkened(0.24))
	for kx in range(30, 58, 5):
		_rect(img, kx, 58, 3, 2, body.lightened(0.14))
		_rect(img, kx, 61, 3, 2, body.lightened(0.06))
	_glow(img, 70, 58, Color(0.95, 0.75, 0.30))
	_finish(img, RIM_COOL, 0.42)
	_save(img, "struct_console.png")

func _struct_tower() -> void:
	# Full-height equipment tower: fan intake, bays of blinking LEDs, vents.
	var img := Image.create(72, 150, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cab := Color(0.49, 0.51, 0.56)
	_shadow(img, 36, 143, 30, 4, 0.32)
	_vgrad(img, 6, 4, 60, 138, cab.lightened(0.08), cab.darkened(0.24))
	_rect(img, 6, 4, 60, 2, cab.lightened(0.24))
	_rect(img, 6, 4, 3, 138, cab.lightened(0.14))
	_rect(img, 63, 4, 3, 138, cab.darkened(0.30))
	# fan intake up top: dark ring, hub, spinner blades frozen mid-thought
	for a in 40:
		var ang := TAU * float(a) / 40.0
		_px(img, 36 + int(cos(ang) * 9.0), 19 + int(sin(ang) * 9.0), cab.darkened(0.45))
	for a in 4:
		var ang := TAU * float(a) / 4.0 + 0.5
		_line(img, 36, 19, 36 + int(cos(ang) * 7.0), 19 + int(sin(ang) * 7.0), cab.darkened(0.30))
	_px(img, 36, 19, cab.lightened(0.25))
	# equipment bays with LEDs that report nothing useful
	var leds := [Color(0.30, 0.95, 0.40), Color(0.95, 0.75, 0.20), Color(0.95, 0.30, 0.25)]
	for u in range(34, 134, 20):
		_rect(img, 12, u, 48, 14, Color(0.07, 0.08, 0.10))
		_rect(img, 12, u, 48, 1, Color(0.03, 0.04, 0.05))
		_rect(img, 12, u + 13, 48, 1, cab.lightened(0.10))
		for i in 3:
			var on: bool = _rng.randf() > 0.45
			var col: Color = leds[i]
			_rect(img, 16 + i * 8, u + 5, 3, 3, col.darkened(0.25) if on else col.darkened(0.72))
			if on:
				_glow(img, 17 + i * 8, u + 6, col)
		for vx in range(44, 58, 4):
			_rect(img, vx, u + 3, 2, 8, cab.darkened(0.42))
			_rect(img, vx, u + 3, 1, 8, cab.darkened(0.25))
	# a cable that gave up on cable management
	_line(img, 58, 138, 50, 146, Color(0.16, 0.17, 0.20))
	_line(img, 57, 138, 49, 145, Color(0.24, 0.25, 0.28))
	_finish(img, RIM_COOL, 0.42)
	_save(img, "struct_tower.png")

func _struct_orb() -> void:
	# Levitating sphere: 4-tone dithered shading, hot specular, orbit rings.
	var img := Image.create(112, 112, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx := 56
	var cy := 54
	_shadow(img, 56, 104, 34, 5, 0.34)
	for y in 112:
		for x in 112:
			var dx := float(x - cx) / 52.0
			var dy := float(y - cy) / 52.0
			var d := sqrt(dx * dx + dy * dy)
			if d <= 1.0:
				# lambert-ish from the top-left + darkened limb
				var lam := clampf(0.62 - 0.42 * (dx + dy) * 0.707, 0.08, 1.05)
				lam *= 1.0 - 0.35 * d * d
				# reflected bounce light along the lower rim
				if d > 0.82 and dy > 0.3:
					lam += 0.10
				# quantize to 4 tones, checker-dither the band boundaries
				var q := floorf(lam * 4.0) / 4.0
				if fmod(lam * 4.0, 1.0) > 0.5 and (((x >> 1) + (y >> 1)) & 1) == 0:
					q += 0.25
				var b := clampf(0.24 + q * 0.76, 0.0, 1.0)
				img.set_pixel(x, y, Color(b, b, minf(b * 1.04, 1.0), 1.0))
	# hot specular blob, top-left
	for yy in range(31, 41):
		for xx in range(32, 43):
			var sd := Vector2(xx - 37, yy - 36).length()
			if sd < 3.6:
				img.set_pixel(xx, yy, Color(0.93, 0.94, 0.97))
	_glow(img, 37, 35, Color(0.92, 0.95, 1.0))
	# orbit rings: bright in front, faint behind, one white-hot bead
	for rr in [44, 51]:
		for a in 220:
			var ang := TAU * float(a) / 220.0
			var px := cx + int(cos(ang) * rr)
			var py := cy + int(sin(ang) * rr * 0.38) + 8
			var front := sin(ang) > 0.0
			_px(img, px, py, Color(0.92, 0.93, 0.97, 0.85 if front else 0.28))
	_glow(img, cx + int(cos(1.9) * 51.0), cy + int(sin(1.9) * 51.0 * 0.38) + 8, Color(0.9, 0.93, 1.0))
	_finish(img, RIM_COOL, 0.30)
	_save(img, "struct_orb.png")

func _struct_arch() -> void:
	# Ruined stone arch: coursed masonry, cracks, a bite missing from the
	# lintel, rubble underneath, and carved glyphs that still glow. Legacy code.
	var img := Image.create(150, 128, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var stone := Color(0.64, 0.62, 0.58)
	_shadow(img, 25, 122, 20, 4, 0.30)
	_shadow(img, 125, 122, 20, 4, 0.30)
	# two pillars of coursed blocks with staggered joints + value jitter
	for px0: int in [10, 110]:
		for y in range(20, 122):
			var course := (y - 20) / 17
			var shift := (course % 2) * 8
			for x in range(px0, px0 + 30):
				var block := (x - px0 + shift) / 15
				var j := float(_hash(block + px0, course) % 9 - 4) / 80.0
				var c := Color(stone.r + j, stone.g + j, stone.b + j, 1.0)
				if (y - 20) % 17 == 0:
					c = c.darkened(0.30)                     # mortar course
				elif (y - 20) % 17 == 1:
					c = c.lightened(0.08)                    # lit block top
				elif (x - px0 + shift) % 15 == 0:
					c = c.darkened(0.26)                     # vertical joint
				if x < px0 + 3:
					c = c.lightened(0.12)
				elif x > px0 + 26:
					c = c.darkened(0.24)
				img.set_pixel(x, y, c)
		# cracks + carved glowing glyph column (near-white: region tint owns it)
		_line(img, px0 + 6, 40, px0 + 12, 70, stone.darkened(0.34))
		for gy in range(30, 46, 7):
			_glow(img, px0 + 15, gy, Color(0.90, 0.92, 0.88))
	# lintel with lit top face and a shadowed underside
	_rect(img, 4, 6, 142, 26, stone)
	_rect(img, 4, 6, 142, 3, stone.lightened(0.16))
	_rect(img, 4, 29, 142, 3, stone.darkened(0.34))
	for lx in range(16, 140, 19):
		_rect(img, lx, 9, 1, 20, stone.darkened(0.22))
	# jagged missing chunk (a V-shaped bite, not a clean rectangle)
	for gx in range(66, 92):
		var depth: int = 26 - absi(gx - 79) + (_hash(gx, 1) % 4)
		for gy in range(6, 6 + maxi(depth, 0)):
			if gy < 34:
				img.set_pixel(gx, gy, Color(0, 0, 0, 0))
	# rubble where the chunk landed
	for r in 9:
		var rx := 62 + _hash(r, 5) % 30
		var ry := 116 + _hash(r, 9) % 6
		_rect(img, rx, ry, 3, 2, stone.darkened(0.10 + 0.02 * (r % 4)))
		_px(img, rx, ry, stone.lightened(0.10))
	_finish(img, RIM_COOL, 0.40)
	_save(img, "struct_arch.png")

# ---------------------------------------------------------------- floor -----

func _floor_tiles() -> void:
	# Warm plank flooring, three tone variants that share one plank phase so
	# any tile sits next to any other without a visible seam. Grain runs along
	# the boards; each board gets its own value jitter, lit top edge and AO.
	# Warmer and a step brighter than they used to be: the wall above is now
	# cool indigo, so the floor has to own the warm half of the frame or the
	# two collapse back into one brown mass.
	var bases := [Color(0.318, 0.234, 0.166), Color(0.292, 0.216, 0.152), Color(0.338, 0.252, 0.178)]
	for v in bases.size():
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		var base: Color = bases[v]
		for y in 64:
			var row := y >> 4          # 16px planks, same phase in every variant
			var ry := y & 15
			for x in 64:
				# per-plank tone jitter (±4%) so boards read as separate cuts
				var pj := float(_hash(row * 31 + v * 7, 5) % 9 - 4) / 100.0
				var c := Color(base.r + pj, base.g + pj, base.b + pj * 0.8, 1.0)
				# Grain that actually runs ALONG the board: streaks parallel to the
				# plank, waving gently down its length (two full waves per tile, so
				# it still tiles). The old version varied with x alone, which drew
				# vertical stripes across horizontal boards and was the real reason
				# this floor read as brickwork.
				var g := sin(float(ry) * 1.35 + float(row) * 2.1 + sin(float(x) * 0.19635) * 1.8)
				if g > 0.72:
					c = c.darkened(0.13)
				elif g < -0.78:
					c = c.lightened(0.08)
				# fine per-pixel noise
				var n := float(_hash(x * 3 + v * 101, y) % 10) / 300.0
				c = Color(c.r + n, c.g + n, c.b + n * 0.8, 1.0)
				# 4-tone plank profile: seam shadow, lit edge, AO before the seam
				if ry == 0:
					c = c.darkened(0.46)
				elif ry == 1:
					c = c.lightened(0.17)
				elif ry == 15:
					c = c.darkened(0.20)
				# Staggered butt joints, on every other course only: one joint per
				# board per tile was reading as masonry rather than floorboards.
				var joint := (x + row * 29 + v * 11) % 64
				if (row + v) % 2 == 0 and ry > 0:
					if joint == 0:
						c = c.darkened(0.32)
					elif joint == 1:
						c = c.lightened(0.10)
				img.set_pixel(x, y, c)
		# the odd knot, kept away from tile edges so tiling stays clean
		if v == 0:
			_knot(img, 18, 24, base)
		elif v == 2:
			_knot(img, 44, 56, base)
		_save(img, "int_floor_%d.png" % v)

func _knot(img: Image, cx: int, cy: int, c: Color) -> void:
	# Wood knot: dark heart, growth ring, faint highlight toward the light.
	for y in img.get_height():
		for x in img.get_width():
			var d := Vector2(x - cx, y - cy).length()
			if d < 1.6:
				img.set_pixel(x, y, c.darkened(0.45))
			elif d < 3.2:
				img.set_pixel(x, y, c.darkened(0.20))
			elif d < 4.4:
				img.set_pixel(x, y, c.darkened(0.32))
	_px(img, cx - 3, cy - 3, c.lightened(0.08))

func _rug() -> void:
	# A proper woven rug (banded borders + central medallion + end fringe) that
	# anchors the battlestation zone. Deliberately NOT a checkerboard.
	var w := 320
	var h := 224
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var field := Color(0.15, 0.18, 0.25)        # deep indigo weave
	var field2 := Color(0.17, 0.21, 0.29)
	var band_dark := Color(0.11, 0.13, 0.19)
	var band_teal := Color(0.28, 0.52, 0.58)
	var band_rust := Color(0.64, 0.40, 0.22)    # warm amber-rust accent thread
	var fringe_col := Color(0.72, 0.68, 0.58)
	var cx := w / 2
	var cy := h / 2
	# baked drop shadow so the rug sits ON the floor instead of hovering
	_rect(img, 8, 12, w - 9, h - 13, Color(0.01, 0.015, 0.04, 0.24))
	for y in h:
		for x in w:
			var edge: int = min(min(x, w - 1 - x), min(y, h - 1 - y))
			# End fringe: short vertical tassels beyond the woven body (top/bottom).
			if y < 6 or y >= h - 6:
				if (x % 6) < 3 and x > 10 and x < w - 10:
					img.set_pixel(x, y, fringe_col.darkened(0.1 + 0.2 * ((x / 6) % 2)))
				continue
			if edge < 4:
				continue
			var c: Color
			if edge < 9:
				c = band_dark                       # outer guard band
			elif edge < 13:
				c = band_teal                       # bright teal frame
			elif edge < 17:
				c = band_dark
			elif edge < 22:
				# repeating rust "hook" motif in the inner border
				c = band_rust if ((x + y) / 6) % 2 == 0 else band_rust.darkened(0.25)
			else:
				# Field: soft diagonal weave (very low contrast) + subtle grain.
				var weave: float = 0.03 * sin((x + y) * 0.20)
				c = field2 if ((x - y) & 12) == 0 else field
				var n := (_hash(x, y) % 6) / 340.0
				c = Color(c.r + n + weave, c.g + n + weave, c.b + n + weave, 1.0)
				# Central diamond medallion (concentric rings + gold thread).
				var dman: int = int(absf(x - cx) * 0.7) + int(absf(y - cy))
				if dman < 66 and dman >= 60:
					c = band_teal.darkened(0.1)
				elif dman < 60 and dman >= 54:
					c = band_rust.darkened(0.15)
				elif dman == 53 and (x + y) % 3 == 0:
					c = Color(0.78, 0.64, 0.32)     # glinting gold thread
				elif dman < 20 and dman >= 14:
					c = band_teal.darkened(0.2)
				elif dman < 8:
					c = band_rust.darkened(0.1)
					if dman < 2 and (x + y) % 2 == 0:
						c = Color(0.80, 0.66, 0.34)
			img.set_pixel(x, y, c)
	# threadbare patches where the chair rolls: the rug is also crunching
	for p in [Vector3i(150, 122, 26), Vector3i(214, 96, 17)]:
		for y in range(p.y - p.z, p.y + p.z + 1):
			for x in range(p.x - p.z * 2, p.x + p.z * 2 + 1):
				var d := Vector2(float(x - p.x) * 0.5, float(y - p.y)).length() / float(p.z)
				if d < 1.0 and _hash(x, y) % 3 != 0:
					_px(img, x, y, Color(0.55, 0.55, 0.60, 0.07 * (1.0 - d)))
	_save(img, "int_rug.png")

# ---------------------------------------------------------------- walls -----

func _wall_tiles() -> void:
	# Upper wall face. The wall must never be mistaken for the floor: it is
	# COOL indigo where the plank floor is warm brown, it is deeper in value,
	# its crown and wainscot catch the light, and its base ends in a heavy
	# baseboard, a warm skirting light, and an ALPHA-feathered contact shadow
	# that falls ONTO the real floor instead of painting a fake band over it.
	var img := Image.create(64, 96, false, Image.FORMAT_RGBA8)
	var wall := Color(0.105, 0.115, 0.185)
	var trim := Color(0.16, 0.18, 0.28)
	for y in 96:
		for x in 64:
			var c := wall
			if y < 2:
				c = wall.darkened(0.55)                  # ceiling shadow line
			elif y < 4:
				c = trim.lightened(0.34)                 # crown trim, lit
			elif y < 8:
				c = trim.lightened(0.10)
			elif y == 8:
				c = wall.darkened(0.40)                  # trim shadow
			elif y < 75:
				# field: gentle top-to-bottom falloff, dithered, plus seams
				var t := float(y - 9) / 66.0
				c = wall.lightened(0.07 * (1.0 - t)).darkened(0.12 * t)
				if (((x >> 1) + (y >> 1)) & 7) == 0:
					c = c.lightened(0.025)
				if x % 32 == 0:
					c = c.darkened(0.26)                 # panel seam
				elif x % 32 == 1:
					c = c.lightened(0.11)                # seam edge catches light
				if y == 52:
					c = trim.lightened(0.20)             # wainscot rail
				elif y == 53:
					c = c.darkened(0.30)
				var n := float(_hash(x, y * 2) % 6) / 340.0
				c = Color(c.r + n, c.g + n, c.b + n, 1.0)
				# the occasional scuff down low; furniture happened here
				if y > 62 and _hash(x >> 2, y >> 1) % 37 == 0:
					c = c.darkened(0.14)
			elif y == 75:
				c = Color(0.24, 0.17, 0.10)              # skirting channel
			elif y == 76:
				c = Color(0.30, 0.26, 0.21)              # baseboard cap, warm-lit
			elif y == 77:
				c = Color(0.17, 0.16, 0.15)
			elif y < 88:
				c = wall.darkened(0.44)                  # baseboard body, deep
			elif y == 88:
				c = wall.darkened(0.66)                  # its own contact line
			else:
				# Feathered contact shadow with REAL alpha, so the floor reads
				# through it and the two surfaces stop being one brown mass.
				var fa: float = clampf((1.0 - float(y - 89) / 7.0) * 0.82, 0.0, 1.0)
				c = Color(0.012, 0.014, 0.035, fa)
			img.set_pixel(x, y, c)
	# Skirting light: a dim amber strip in the channel above the baseboard with
	# one hot LED per tile. Cheap trick, enormous wall/floor separation, and
	# entirely in character for someone who lit their flat from Amazon.
	for lx in 64:
		var a := 0.5 + 0.5 * sin(float(lx) * 0.098)
		img.set_pixel(lx, 75, Color(0.26, 0.17, 0.09).lerp(AMBER.darkened(0.30), a * 0.65))
	_glow(img, 32, 75, AMBER)
	_save(img, "int_wall.png")

	# Side wall column (for left/right room edges): lit inner face, dark outer.
	var side := Image.create(40, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 40:
			var c := wall.darkened(0.05)
			if x < 2:
				c = wall.lightened(0.20)
			elif x < 5:
				c = wall.lightened(0.10)
			elif x > 36:
				c = wall.darkened(0.34)
			elif x > 32:
				c = wall.darkened(0.18)
			if y % 32 == 0:
				c = c.darkened(0.20)                     # panel joint
			elif y % 32 == 1:
				c = c.lightened(0.07)
			var n := float(_hash(x * 5, y) % 6) / 340.0
			c = Color(c.r + n, c.g + n, c.b + n, 1.0)
			side.set_pixel(x, y, c)
	# a bolt head per panel
	_px(side, 20, 12, wall.lightened(0.25))
	_px(side, 20, 44, wall.lightened(0.25))
	_save(side, "int_wall_side.png")

func _window() -> void:
	# The one view of the outside: a night city that is doing fine without you.
	# Dithered sky, moon with a halo, two skyline layers, lit windows, a neon
	# sign, and warm room-light reflected in the bottom of the glass.
	var w := 160
	var h := 120
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var frame := Color(0.10, 0.10, 0.145)
	var sky_top := Color(0.040, 0.048, 0.105)
	var sky_low := Color(0.125, 0.085, 0.185)
	for y in h:
		for x in w:
			var edge: int = min(min(x, w - 1 - x), min(y, h - 1 - y))
			var c: Color
			if edge < 8:
				# beveled frame lit from the top-left, AO lip against the glass
				if edge < 2:
					c = Color(0.045, 0.05, 0.08)
				elif edge == 7:
					c = frame.darkened(0.40)
				elif y < 8:
					c = frame.lightened(0.18)
				elif x < 8:
					c = frame.lightened(0.09)
				elif y >= h - 8:
					c = frame.lightened(0.06) if y == h - 8 else frame.darkened(0.12)
				else:
					c = frame.darkened(0.08)
			else:
				var t := float(y - 8) / float(h - 16)
				var tt := t + (0.03 if (((x >> 1) + (y >> 1)) & 1) == 0 else 0.0)
				c = sky_top.lerp(sky_low, clampf(tt, 0.0, 1.0))
				# city glow haze near the horizon
				c = c.lerp(Color(0.19, 0.10, 0.22), clampf((t - 0.55) * 0.9, 0.0, 0.35))
				# stars, a few of them hot enough to bloom
				if t < 0.55 and _hash(x * 7, y * 13) % 331 == 0:
					c = WHITE_HOT if _hash(x, y) % 5 == 0 else Color(0.62, 0.66, 0.80)
				# far skyline (hazy blue towers)
				var fh: int = 20 + _hash(x >> 4, 3) % 22
				if y > h - 12 - fh:
					c = Color(0.075, 0.082, 0.155)
				# near skyline (near-black) with a window grid
				var nh: int = 12 + _hash((x * 7) >> 6, 7) % 36
				if y > h - 10 - nh:
					c = Color(0.028, 0.032, 0.058)
					if (x % 4) != 0 and (y % 5) < 2 and _hash(x >> 2, (y * 13) >> 6) % 7 == 0:
						c = Color(0.95, 0.72, 0.34) if _hash(x, y) % 3 != 0 else Color(0.38, 0.85, 0.90)
						if _hash(x * 5, y * 3) % 41 == 0:
							c = WHITE_HOT
			img.set_pixel(x, y, c)
	# moon with soft halo and a hot crescent core
	for yy in range(20, 46):
		for xx in range(106, 132):
			var d := Vector2(xx - 118, yy - 32).length()
			if d < 7.0:
				var b := clampf(0.80 - float(xx - 118 + yy - 32) * 0.012, 0.62, 0.94)
				img.set_pixel(xx, yy, Color(b, b + 0.02, b + 0.06))
			elif d < 11.0:
				_px(img, xx, yy, Color(0.85, 0.88, 1.0, (11.0 - d) * 0.016))
	_px(img, 116, 30, WHITE_HOT)
	_px(img, 117, 30, WHITE_HOT)
	_px(img, 116, 31, WHITE_HOT)
	_px(img, 120, 34, Color(0.60, 0.62, 0.72))   # crater
	_px(img, 118, 36, Color(0.64, 0.66, 0.76))
	# neon sign on one near tower (magenta, hot cores every few px). The key
	# for the tower-height hash matches the columns the sign sits on.
	var sign_top: int = h - 10 - (12 + _hash((39 * 7) >> 6, 7) % 36) + 4
	var sign_bot: int = mini(sign_top + 16, h - 10)
	for sy in range(sign_top, sign_bot):
		_px(img, 38, sy, Color(0.62, 0.10, 0.38))
		_px(img, 39, sy, MAGENTA)
		_px(img, 40, sy, Color(0.62, 0.10, 0.38))
	if sign_top + 11 < sign_bot:
		_px(img, 39, sign_top + 5, WHITE_HOT)
		_px(img, 39, sign_top + 11, WHITE_HOT)
	# aviation beacon on the tallest-looking tower
	var b_top: int = h - 10 - (12 + _hash((76 * 7) >> 6, 7) % 36)
	_glow(img, 76, maxi(b_top - 1, 12), RED)
	# glass: two faint diagonal reflections + warm interior spill low down
	for y in range(8, h - 8):
		for x in range(8, w - 8):
			var dg := x - y
			if absi(dg - 20) < 3 or absi(dg - 34) < 2:
				_px(img, x, y, Color(0.80, 0.90, 1.0, 0.05))
			if y > h - 30:
				var a := float(y - (h - 30)) / 22.0 * 0.08
				_px(img, x, y, Color(1.0, 0.80, 0.50, a))
	# mullions with lit left/top edge
	for y in range(8, h - 8):
		_px(img, w / 2 - 1, y, frame.lightened(0.20))
		_px(img, w / 2, y, frame.lightened(0.06))
		_px(img, w / 2 + 1, y, frame.darkened(0.25))
	for x in range(8, w - 8):
		_px(img, x, h / 2 - 1, frame.lightened(0.20))
		_px(img, x, h / 2, frame.lightened(0.06))
		_px(img, x, h / 2 + 1, frame.darkened(0.25))
	_save(img, "int_window.png")

# ------------------------------------------------------------ furniture -----

func _desk() -> void:
	# The battlestation: wood-top desk, backlit keyboard, mouse, coffee, sticky
	# notes making promises nobody will keep.
	var w := 240
	var h := 96
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var top := Color(0.235, 0.205, 0.265)
	var legc := Color(0.115, 0.105, 0.145)
	_shadow(img, 120, 89, 108, 6, 0.32)
	# legs with feet
	_bevel(img, 10, 46, 12, 44, legc)
	_bevel(img, 218, 46, 12, 44, legc)
	_rect(img, 8, 88, 16, 3, legc.darkened(0.30))
	_rect(img, 216, 88, 16, 3, legc.darkened(0.30))
	# under-desk cable tray with cables that were "temporary" two years ago
	_rect(img, 26, 52, 188, 5, Color(0.07, 0.07, 0.10))
	_line(img, 30, 54, 120, 56, Color(0.16, 0.30, 0.34))
	_line(img, 60, 54, 200, 55, Color(0.36, 0.14, 0.24))
	# desktop slab: lit top face with lengthwise grain, shadowed front edge
	_rect(img, 2, 22, 236, 24, top)
	for gy in range(25, 45, 4):
		for gx in range(6, 232, 13):
			if _hash(gx, gy) % 3 == 0:
				_rect(img, gx, gy, 7, 1, top.darkened(0.08))
	_rect(img, 2, 22, 236, 1, Color(0.42, 0.37, 0.46))   # rim edge, catches light
	_rect(img, 2, 23, 236, 2, top.lightened(0.10))
	_rect(img, 2, 22, 2, 24, top.lightened(0.08))
	_rect(img, 2, 46, 236, 4, top.darkened(0.35))        # front edge board
	_rect(img, 2, 50, 236, 1, top.darkened(0.55))
	# keyboard, backlit because obviously
	_rect(img, 58, 30, 74, 14, Color(0.065, 0.07, 0.09))
	_rect(img, 58, 30, 74, 1, Color(0.14, 0.15, 0.19))
	for kx in range(62, 126, 6):
		_rect(img, kx, 33, 4, 3, Color(0.22, 0.24, 0.30))
		_rect(img, kx, 33, 4, 1, Color(0.30, 0.32, 0.38))
		_rect(img, kx, 38, 4, 3, Color(0.22, 0.24, 0.30))
		_rect(img, kx, 38, 4, 1, Color(0.30, 0.32, 0.38))
	_rect(img, 61, 37, 68, 1, Color(CYAN.r, CYAN.g, CYAN.b, 0.30))  # key glow leak
	_glow(img, 129, 32, CYAN)                                        # caps lock, on, always
	# mouse with an RGB scroll wheel
	_rect(img, 146, 34, 11, 8, Color(0.10, 0.11, 0.15))
	_rect(img, 146, 34, 11, 2, Color(0.20, 0.22, 0.28))
	_glow(img, 151, 35, MAGENTA)
	# mug of coffee, load-bearing
	_rect(img, 172, 26, 14, 16, Color(0.62, 0.26, 0.15))
	_rect(img, 172, 26, 3, 16, Color(0.74, 0.36, 0.20))
	_rect(img, 186, 30, 3, 8, Color(0.52, 0.22, 0.13))   # handle
	_rect(img, 173, 27, 12, 2, Color(0.16, 0.10, 0.06))  # coffee surface
	_px(img, 176, 20, Color(0.75, 0.78, 0.85, 0.22))     # steam
	_px(img, 178, 16, Color(0.75, 0.78, 0.85, 0.16))
	_px(img, 175, 12, Color(0.75, 0.78, 0.85, 0.10))
	# sticky notes: TODO (amber) and TODO (acid). Both say TODO.
	_rect(img, 200, 27, 9, 9, Color(0.92, 0.78, 0.36))
	_px(img, 208, 35, Color(0.70, 0.56, 0.22))
	_line(img, 202, 30, 206, 30, Color(0.35, 0.28, 0.12))
	_line(img, 202, 33, 205, 33, Color(0.35, 0.28, 0.12))
	_rect(img, 213, 31, 8, 8, Color(0.72, 0.86, 0.40))
	_px(img, 220, 38, Color(0.52, 0.64, 0.26))
	_line(img, 215, 34, 218, 34, Color(0.30, 0.38, 0.14))
	# a cable escaping off the right end of the desk
	_line(img, 132, 44, 226, 48, Color(0.10, 0.10, 0.14))
	_finish(img, RIM_WARM, 0.40)
	_save(img, "furn_desk.png")

func _monitor() -> void:
	# Bezel + stand; the screen well stays dark so the builder can overlay a
	# bright animated screen. Standby LED included, for ambience and guilt.
	var w := 96
	var h := 84
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var bez := Color(0.075, 0.078, 0.10)
	_shadow(img, w / 2, 80, 26, 4, 0.30)
	# stand: neck + base with a lit top edge
	_bevel(img, w / 2 - 6, 62, 12, 12, bez.lightened(0.10))
	_rect(img, w / 2 - 20, 74, 40, 8, bez)
	_rect(img, w / 2 - 20, 74, 40, 2, bez.lightened(0.22))
	_rect(img, w / 2 - 20, 80, 40, 2, bez.darkened(0.35))
	# bezel with 4-tone edges
	_rect(img, 0, 0, w, 62, bez)
	_rect(img, 0, 0, w, 2, bez.lightened(0.24))
	_rect(img, 0, 0, 2, 62, bez.lightened(0.12))
	_rect(img, 0, 60, w, 2, bez.darkened(0.30))
	_rect(img, w - 2, 0, 2, 62, bez.darkened(0.22))
	# screen well (kept dark for the overlay) + inner AO ring + faint sheen
	_rect(img, 4, 4, w - 8, 54, Color(0.028, 0.032, 0.045))
	_rect(img, 4, 4, w - 8, 1, Color(0.012, 0.015, 0.022))
	_rect(img, 4, 4, 1, 54, Color(0.012, 0.015, 0.022))
	_line(img, 70, 6, 88, 24, Color(1, 1, 1, 0.05))
	# rounded bezel corners
	for cnr in [Vector2i(0, 0), Vector2i(w - 1, 0), Vector2i(0, 61), Vector2i(w - 1, 61)]:
		img.set_pixel(cnr.x, cnr.y, Color(0, 0, 0, 0))
		img.set_pixel(absi(cnr.x - 1), cnr.y, Color(0, 0, 0, 0))
		img.set_pixel(cnr.x, absi(cnr.y - 1) if cnr.y == 0 else cnr.y - 1, Color(0, 0, 0, 0))
	# standby LED + logo notch
	_glow(img, 88, 59, CYAN)
	_rect(img, 45, 60, 6, 1, bez.lightened(0.20))
	_finish(img, Color(0.75, 0.95, 1.0), 0.30)
	_save(img, "furn_monitor.png")

func _server_rack() -> void:
	# Home server rack: dithered cabinet, recessed bays, LEDs hot enough to
	# bloom, one tiny status screen, cables performing an escape.
	var w := 96
	var h := 168
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cab := Color(0.13, 0.14, 0.18)
	_shadow(img, w / 2, 164, 42, 3, 0.34)
	_vgrad(img, 2, 2, 92, 158, cab.lightened(0.10), cab.darkened(0.22))
	_rect(img, 2, 2, 92, 2, cab.lightened(0.30))
	_rect(img, 2, 2, 4, 158, cab.lightened(0.16))
	_rect(img, 90, 2, 4, 158, cab.darkened(0.30))
	# feet
	_rect(img, 8, 160, 10, 4, cab.darkened(0.35))
	_rect(img, 78, 160, 10, 4, cab.darkened(0.35))
	# rack units
	var col := [Color(0.30, 0.90, 0.40), Color(0.90, 0.70, 0.20), Color(0.30, 0.90, 0.40), Color(0.90, 0.25, 0.20)]
	for u in range(10, 150, 20):
		_rect(img, 10, u, w - 20, 15, Color(0.055, 0.065, 0.085))
		_rect(img, 10, u, w - 20, 1, Color(0.02, 0.025, 0.035))     # recess AO
		_rect(img, 10, u + 14, w - 20, 1, cab.lightened(0.14))      # lit lip below
		if u == 70:
			# one bay is a status screen; it reports "fine", it is lying
			_rect(img, 14, u + 3, 34, 9, Color(0.04, 0.16, 0.18))
			_rect(img, 16, u + 5, 20, 1, Color(0.30, 0.80, 0.78))
			_rect(img, 16, u + 8, 14, 1, Color(0.22, 0.62, 0.60))
			_glow(img, 38, u + 8, CYAN_HOT)
		else:
			for i in 4:
				var on: bool = _rng.randf() > 0.35
				var c: Color = col[i]
				_rect(img, 16 + i * 8, u + 4, 4, 4, c.darkened(0.25) if on else c.darkened(0.72))
				if on:
					_glow(img, 17 + i * 8, u + 5, c)
		# vent slits with a lit edge
		for sx in range(56, w - 12, 4):
			_rect(img, sx, u + 3, 2, 9, cab.darkened(0.42))
			_rect(img, sx, u + 3, 1, 9, cab.darkened(0.20))
		# corner screws
		_px(img, 12, u + 2, cab.lightened(0.30))
		_px(img, w - 13, u + 2, cab.lightened(0.30))
	# cable spaghetti exiting stage left
	_line(img, 20, 152, 10, 160, Color(0.14, 0.26, 0.30))
	_line(img, 26, 152, 14, 162, Color(0.34, 0.12, 0.22))
	_line(img, 32, 152, 20, 163, Color(0.16, 0.17, 0.22))
	_finish(img, Color(0.70, 0.95, 1.0), 0.38)
	_save(img, "furn_server.png")

func _bed() -> void:
	# Decorative sleep surface. The laptop lives here now; the human does not.
	var w := 168
	var h := 108
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var frame := Color(0.165, 0.130, 0.115)
	var sheet := Color(0.285, 0.305, 0.410)
	var blanket := Color(0.185, 0.225, 0.330)
	_shadow(img, w / 2, 102, 78, 5, 0.30)
	# frame with a lit headboard edge (head of bed is at the top)
	_bevel(img, 3, 10, 162, 90, frame)
	_rect(img, 3, 6, 162, 6, frame.lightened(0.08))
	_rect(img, 3, 6, 162, 1, frame.lightened(0.24))
	# mattress + sheet with dithered falloff toward the foot; the frame keeps
	# a visible footboard below it
	_vgrad(img, 9, 16, 150, 78, sheet.lightened(0.06), sheet.darkened(0.14))
	_line(img, 20, 34, 60, 30, sheet.darkened(0.14))     # wrinkles
	_line(img, 70, 50, 120, 46, sheet.darkened(0.12))
	_line(img, 30, 44, 58, 48, sheet.lightened(0.08))
	# laptop light pool on the sheets (painted before the laptop itself)
	for yy in range(30, 56):
		for xx in range(100, 156):
			var d := Vector2(float(xx - 128) * 0.6, float(yy - 42)).length() / 16.0
			if d < 1.0:
				_px(img, xx, yy, Color(CYAN.r, CYAN.g, CYAN.b, 0.10 * (1.0 - d)))
	# blanket, rumpled, with fold shadows + caught-light ridges
	_rect(img, 9, 58, 150, 36, blanket)
	for i in range(13, w - 12, 14):
		_rect(img, i, 60, 6, 32, blanket.darkened(0.14))
		_rect(img, i - 1, 60, 1, 32, blanket.lightened(0.10))
	_rect(img, 9, 58, 150, 2, blanket.lightened(0.14))   # folded hem, lit
	_rect(img, 9, 91, 150, 3, blanket.darkened(0.26))    # drape shadow
	_rect(img, 3, 94, 162, 1, frame.lightened(0.18))     # footboard lit edge
	# pillow: 4-tone with a center crease. Untouched. Pristine. Sad.
	_rect(img, 14, 20, 44, 26, Color(0.80, 0.82, 0.88))
	_rect(img, 14, 20, 44, 3, Color(0.92, 0.93, 0.97))
	_rect(img, 14, 20, 3, 26, Color(0.87, 0.88, 0.93))
	_rect(img, 14, 43, 44, 3, Color(0.62, 0.64, 0.72))
	_rect(img, 55, 20, 3, 26, Color(0.68, 0.70, 0.78))
	_line(img, 22, 32, 50, 33, Color(0.66, 0.68, 0.76))
	# the laptop, open, mid-build, judging you
	_rect(img, 108, 24, 36, 22, Color(0.085, 0.095, 0.125))
	_rect(img, 108, 24, 36, 1, Color(0.18, 0.20, 0.25))
	_rect(img, 111, 26, 30, 15, Color(0.075, 0.28, 0.30))
	_rect(img, 113, 28, 18, 1, Color(0.35, 0.85, 0.82))
	_rect(img, 113, 31, 24, 1, Color(0.28, 0.70, 0.68))
	_rect(img, 113, 34, 12, 1, Color(0.35, 0.85, 0.82))
	_glow(img, 128, 37, CYAN_HOT)
	_finish(img, RIM_WARM, 0.32)
	_save(img, "furn_bed.png")

func _fridge() -> void:
	# Fridge. Contents: energy drinks and one condiment of unknown vintage.
	var w := 84
	var h := 132
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var body := Color(0.315, 0.345, 0.400)
	_shadow(img, w / 2, 128, 36, 4, 0.32)
	_vgrad(img, 2, 2, 80, 124, body.lightened(0.14), body.darkened(0.16))
	_rect(img, 2, 2, 80, 2, body.lightened(0.30))
	_rect(img, 2, 2, 5, 124, body.lightened(0.18))
	_rect(img, 77, 2, 5, 124, body.darkened(0.28))
	# door split: shadow + lit lower-door edge
	_rect(img, 6, 62, 72, 2, body.darkened(0.42))
	_rect(img, 6, 64, 72, 1, body.lightened(0.12))
	# handles with a hot glint
	for hy in [16, 72]:
		_rect(img, 64, hy, 5, 32, Color(0.72, 0.75, 0.82))
		_rect(img, 68, hy, 1, 32, Color(0.45, 0.48, 0.55))
		_rect(img, 64, hy, 5, 2, Color(0.86, 0.88, 0.94))
		_px(img, 65, hy, WHITE_HOT)
	# temperature display: it reads an error code, like everything else here
	_rect(img, 12, 10, 22, 11, Color(0.045, 0.055, 0.075))
	_rect(img, 12, 10, 22, 1, Color(0.02, 0.025, 0.035))
	_rect(img, 15, 13, 4, 5, Color(0.25, 0.85, 0.80))
	_rect(img, 21, 13, 4, 5, Color(0.25, 0.85, 0.80))
	_px(img, 27, 17, Color(0.25, 0.85, 0.80))
	_glow(img, 30, 14, CYAN)
	# energy-drink magnets, each with a shaded lip
	for m in [Vector3i(14, 28, 0), Vector3i(30, 32, 1), Vector3i(46, 30, 2)]:
		var mc: Color = [Color(0.20, 0.75, 0.32), Color(0.85, 0.28, 0.28), Color(0.28, 0.55, 0.88)][m.z]
		_rect(img, m.x, m.y, 10, 16, mc.darkened(0.15))
		_rect(img, m.x, m.y, 10, 3, mc.lightened(0.20))
		_rect(img, m.x, m.y + 14, 10, 2, mc.darkened(0.40))
		_px(img, m.x + 1, m.y + 1, mc.lightened(0.45))
	# grocery list sticky note: it just says "sleep". aspirational.
	_rect(img, 40, 78, 13, 11, Color(0.90, 0.85, 0.62))
	_px(img, 52, 88, Color(0.66, 0.60, 0.40))
	_line(img, 42, 81, 49, 81, Color(0.35, 0.32, 0.20))
	_line(img, 42, 84, 46, 84, Color(0.35, 0.32, 0.20))
	# kick vent + scuffs
	_rect(img, 8, 116, 68, 8, body.darkened(0.35))
	for sx in range(10, 74, 6):
		_rect(img, sx, 118, 3, 4, body.darkened(0.50))
	_line(img, 12, 112, 22, 113, body.darkened(0.30))
	_finish(img, RIM_WARM, 0.35)
	_save(img, "furn_fridge.png")

func _coffee() -> void:
	# The most important machine in the apartment. Uptime: excellent.
	var w := 68
	var h := 92
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var body := Color(0.115, 0.120, 0.155)
	_shadow(img, 34, 88, 26, 3, 0.32)
	_bevel(img, 10, 2, 48, 86, body)
	_rect(img, 10, 2, 48, 8, body.lightened(0.20))
	_rect(img, 10, 2, 48, 1, body.lightened(0.42))
	# tiny status screen: reads ERR, brews anyway
	_rect(img, 16, 13, 16, 8, Color(0.045, 0.05, 0.07))
	_rect(img, 18, 15, 3, 4, Color(0.95, 0.65, 0.25))
	_rect(img, 23, 15, 3, 4, Color(0.95, 0.65, 0.25))
	_rect(img, 28, 15, 2, 4, Color(0.95, 0.65, 0.25))
	# buttons + the sacred green light
	_rect(img, 38, 15, 3, 3, body.lightened(0.25))
	_rect(img, 43, 15, 3, 3, body.lightened(0.25))
	_glow(img, 50, 16, ACID)
	# dispenser cavity with an amber back-glow
	_rect(img, 16, 30, 36, 26, Color(0.030, 0.035, 0.050))
	_rect(img, 16, 30, 36, 1, Color(0.012, 0.015, 0.022))
	for yy in range(32, 55):
		for xx in range(18, 50):
			var d := Vector2(float(xx - 34) * 0.7, float(yy - 44)).length() / 12.0
			if d < 1.0:
				_px(img, xx, yy, Color(1.0, 0.62, 0.20, 0.10 * (1.0 - d)))
	# pour stream: amber with white-hot droplets (it blooms; it has earned it)
	_rect(img, 33, 31, 2, 12, Color(0.95, 0.62, 0.18))
	_px(img, 33, 34, WHITE_HOT)
	_px(img, 34, 39, WHITE_HOT)
	# the mug, receiving
	_rect(img, 26, 42, 16, 13, Color(0.36, 0.23, 0.14))
	_rect(img, 26, 42, 3, 13, Color(0.46, 0.30, 0.18))
	_rect(img, 27, 43, 14, 2, Color(0.62, 0.40, 0.16))
	_rect(img, 42, 45, 3, 7, Color(0.30, 0.19, 0.12))
	# drip tray
	_rect(img, 16, 58, 36, 4, body.darkened(0.30))
	_rect(img, 16, 58, 36, 1, body.lightened(0.15))
	# steam
	_px(img, 32, 27, Color(0.80, 0.82, 0.88, 0.20))
	_px(img, 35, 24, Color(0.80, 0.82, 0.88, 0.14))
	_finish(img, RIM_WARM, 0.38)
	_save(img, "furn_coffee.png")

func _plant() -> void:
	# The plant. Deprecated since v0.2 but still technically a dependency.
	var w := 64
	var h := 96
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_shadow(img, 32, 92, 22, 3, 0.30)
	# pot: terracotta with a lit lip and AO under it
	_bevel(img, 18, 66, 28, 24, Color(0.42, 0.275, 0.195))
	_rect(img, 15, 60, 34, 6, Color(0.50, 0.335, 0.235))
	_rect(img, 15, 60, 34, 1, Color(0.62, 0.44, 0.30))
	_rect(img, 16, 66, 32, 2, Color(0.28, 0.18, 0.13))
	# soil
	_rect(img, 19, 62, 26, 3, Color(0.115, 0.085, 0.065))
	# stems + drooping 3-tone leaves; two have gone amber (end-of-life notice)
	var leaf := Color(0.235, 0.335, 0.195)
	for i in 5:
		var bx := 24 + i * 4
		var dying := i == 1 or i == 4
		var lc := Color(0.55, 0.47, 0.20) if dying else leaf
		_line(img, 32, 62, bx, 46, Color(0.16, 0.22, 0.13))
		for j in range(0, 30, 2):
			var yy := 60 - j
			var xx := bx + int(sin(j * 0.3 + i) * 6.0) + int(j * 0.4)
			if yy >= 4 and xx >= 2 and xx < w - 3:
				_px(img, xx, yy, lc)
				_px(img, xx + 1, yy, lc.darkened(0.18))
				_px(img, xx - 1, yy - 1, lc.lightened(0.18))
	# one fallen leaf; no one has swept
	_px(img, 51, 88, Color(0.52, 0.44, 0.20))
	_px(img, 52, 88, Color(0.44, 0.36, 0.16))
	_px(img, 52, 89, Color(0.36, 0.30, 0.14))
	_finish(img, Color(0.75, 0.95, 0.65), 0.32)
	_save(img, "furn_plant.png")

func _node_modules() -> void:
	# node_modules, physically manifested: a pile of boxes with more boxes
	# inside them, actively spilling smaller packages. 340MB of cardboard.
	var w := 140
	var h := 104
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_shadow(img, 70, 97, 62, 6, 0.32)
	var ca := Color(0.52, 0.40, 0.26)
	var cb := Color(0.58, 0.44, 0.28)
	var cc := Color(0.60, 0.46, 0.30)
	var cd := Color(0.47, 0.36, 0.24)
	# back-left box
	_bevel(img, 10, 34, 52, 42, ca)
	_rect(img, 34, 36, 4, 38, ca.darkened(0.20))          # tape
	_rect(img, 33, 36, 1, 38, ca.lightened(0.10))
	# back-right box, leaning slightly; structural integrity is a suggestion
	for iy in 38:
		var lean := iy >> 4
		_rect(img, 80 - lean, 28 + iy, 46, 1, cb.lightened(0.12 - 0.004 * float(iy)))
	_rect(img, 79, 28, 46, 2, cb.lightened(0.24))
	_rect(img, 100, 30, 4, 34, cb.darkened(0.20))
	_line(img, 80, 65, 124, 65, cb.darkened(0.32))
	# warning label nobody read
	_rect(img, 110, 38, 8, 8, Color(0.92, 0.72, 0.24))
	_px(img, 113, 40, Color(0.20, 0.15, 0.05))
	_px(img, 114, 40, Color(0.20, 0.15, 0.05))
	_px(img, 113, 42, Color(0.20, 0.15, 0.05))
	_px(img, 113, 44, Color(0.20, 0.15, 0.05))
	# front-left box, flaps open, contents escaping
	_bevel(img, 24, 58, 48, 40, cc)
	_rect(img, 30, 58, 36, 5, Color(0.145, 0.105, 0.075))     # dark interior
	_rect(img, 18, 53, 12, 6, cc.lightened(0.16))              # left flap
	_rect(img, 18, 58, 12, 1, cc.darkened(0.30))
	_rect(img, 66, 54, 12, 5, cc.lightened(0.10))              # right flap
	_rect(img, 66, 58, 12, 1, cc.darkened(0.30))
	# front-right box
	_bevel(img, 80, 62, 44, 36, cd)
	_rect(img, 100, 64, 4, 32, cd.darkened(0.20))
	_rect(img, 99, 64, 1, 32, cd.lightened(0.10))
	# small open box on top, the source of the spill
	_bevel(img, 34, 40, 26, 20, cb.lightened(0.05))
	_rect(img, 38, 40, 18, 4, Color(0.13, 0.095, 0.07))
	# spilling packages (each one is a dependency of the one next to it)
	_package(img, 40, 38, Color(0.62, 0.30, 0.28))
	_package(img, 50, 42, Color(0.30, 0.44, 0.62))
	_package(img, 44, 52, Color(0.36, 0.55, 0.34))
	_package(img, 58, 60, Color(0.62, 0.52, 0.28))
	_package(img, 14, 88, Color(0.46, 0.36, 0.56))
	_package(img, 98, 92, Color(0.30, 0.44, 0.62))
	_package(img, 66, 94, Color(0.62, 0.30, 0.28))
	# one loose cable, for flavor
	_line(img, 72, 74, 88, 84, Color(0.12, 0.12, 0.16))
	_finish(img, RIM_WARM, 0.35)
	_save(img, "furn_boxes.png")

func _package(img: Image, x: int, y: int, c: Color) -> void:
	# 6x5 shipping cube: lit top, shadowed base, tiny label. Contains left-pad.
	_rect(img, x, y, 6, 5, c)
	_rect(img, x, y, 6, 1, c.lightened(0.28))
	_rect(img, x, y + 4, 6, 1, c.darkened(0.30))
	_px(img, x + 2, y + 2, Color(0.92, 0.92, 0.90))

func _bookshelf() -> void:
	# Bookshelf: three shelves of books bought during different self-improvement
	# phases, one glowing spine (the only accurate docs), and a rubber duck.
	var w := 140
	var h := 120
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var wood := Color(0.205, 0.160, 0.135)
	_bevel(img, 2, 2, 136, 116, wood)
	var shelf_cols := [Color(0.55, 0.28, 0.28), Color(0.28, 0.40, 0.55), Color(0.34, 0.48, 0.34), Color(0.60, 0.52, 0.30), Color(0.42, 0.34, 0.50), Color(0.30, 0.30, 0.36)]
	var shelf_i := 0
	for s: int in [6, 40, 74]:
		# cavity with AO at the top (the shelf above casts it)
		_rect(img, 6, s, 128, 28, Color(0.055, 0.048, 0.055))
		_rect(img, 6, s, 128, 2, Color(0.030, 0.026, 0.032))
		_rect(img, 6, s + 24, 128, 4, Color(0.075, 0.066, 0.072))
		var x := 10
		while x < w - 18:
			if shelf_i == 1 and x > 92:
				break                                   # leave room for the leaner
			var bw: int = 6 + (_hash(x, s) % 6)
			var bh: int = 20 + (_hash(x * 2, s) % 6)
			var col: Color = shelf_cols[_hash(x, s) % shelf_cols.size()]
			var by := s + (28 - bh)
			_rect(img, x, by, bw, bh, col.darkened(0.10))
			_rect(img, x, by, 1, bh, col.lightened(0.20))       # lit spine edge
			_rect(img, x + bw - 1, by, 1, bh, col.darkened(0.35))
			_rect(img, x, by, bw, 1, col.lightened(0.30))       # lit top
			_rect(img, x + 1, by + 4, bw - 2, 2, col.lightened(0.14))  # title band
			if shelf_i == 0 and x == 10:
				# the glowing spine: documentation that is actually up to date
				_rect(img, x, by, bw, bh, Color(0.10, 0.55, 0.50))
				_rect(img, x + 1, by + 2, bw - 2, 1, CYAN)
				_glow(img, x + bw / 2, by + 10, CYAN)
			x += bw + 2
		if shelf_i == 1:
			# one book gave up and leans against the frame (relatable)
			for iy in 22:
				_rect(img, 98 + (iy >> 2), s + 5 + iy, 7, 1, Color(0.55, 0.36, 0.30).darkened(0.012 * float(iy)))
			# rubber duck, senior debugging consultant
			_rect(img, 116, s + 18, 9, 7, Color(0.95, 0.75, 0.22))
			_rect(img, 116, s + 18, 9, 2, Color(1.0, 0.85, 0.35))
			_rect(img, 122, s + 14, 5, 6, Color(0.95, 0.75, 0.22))
			_rect(img, 126, s + 16, 3, 2, Color(0.90, 0.45, 0.15))  # beak
			_px(img, 124, s + 15, Color(0.15, 0.12, 0.08))          # eye
			_px(img, 123, s + 14, WHITE_HOT)                        # eye glint
		if shelf_i == 2:
			# horizontal stack: books demoted to being a monitor stand someday
			for st in 3:
				var sc: Color = shelf_cols[(st + 2) % shelf_cols.size()]
				_rect(img, 100, s + 13 + st * 5, 30, 5, sc.darkened(0.12))
				_rect(img, 100, s + 13 + st * 5, 30, 1, sc.lightened(0.20))
		# shelf board with a lit front edge
		_rect(img, 4, s + 28, 132, 4, wood.lightened(0.10))
		_rect(img, 4, s + 28, 132, 1, wood.lightened(0.28))
		shelf_i += 1
	_finish(img, RIM_WARM, 0.32)
	_save(img, "furn_shelf.png")

func _chair() -> void:
	# Gaming chair, racing stripes included. Top speed: reverse, slowly, at 3AM.
	var w := 64
	var h := 88
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Color(0.135, 0.145, 0.200)
	_shadow(img, 32, 84, 22, 3, 0.30)
	# star base + wheels first (they sit behind everything)
	for wp in [Vector2i(10, 82), Vector2i(54, 82), Vector2i(20, 85), Vector2i(44, 85), Vector2i(32, 86)]:
		_line(img, 32, 78, wp.x, wp.y, c.darkened(0.25))
		_rect(img, wp.x - 2, wp.y, 4, 3, c.darkened(0.40))
		_px(img, wp.x - 2, wp.y, c.lightened(0.15))
	# gas lift with a piston highlight
	_rect(img, 29, 62, 6, 17, c.darkened(0.30))
	_rect(img, 29, 62, 2, 17, c.lightened(0.10))
	# seat
	_bevel(img, 10, 46, 44, 15, c.darkened(0.05))
	# armrests
	_rect(img, 5, 38, 6, 13, c.darkened(0.22))
	_rect(img, 5, 38, 6, 2, c.lightened(0.12))
	_rect(img, 53, 38, 6, 13, c.darkened(0.28))
	_rect(img, 53, 38, 6, 2, c.lightened(0.08))
	# backrest with magenta racing stripes (they add +0 WPM)
	_bevel(img, 14, 12, 36, 35, c)
	_rect(img, 20, 14, 2, 31, Color(0.55, 0.14, 0.34))
	_rect(img, 42, 14, 2, 31, Color(0.55, 0.14, 0.34))
	_line(img, 18, 30, 46, 30, c.darkened(0.20))          # lumbar seam
	# headrest pillow with stitches
	_bevel(img, 20, 4, 24, 10, c.lightened(0.06))
	_px(img, 24, 8, Color(0.55, 0.14, 0.34))
	_px(img, 39, 8, Color(0.55, 0.14, 0.34))
	_finish(img, Color(1.0, 0.60, 0.80), 0.28)
	_save(img, "furn_chair.png")

func _whiteboard() -> void:
	# Architecture whiteboard: boxes, arrows, one thing circled in red, one
	# thing crossed out. Both are the same thing.
	var w := 176
	var h := 112
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var alu := Color(0.34, 0.36, 0.42)
	_bevel(img, 2, 2, 172, 102, alu)
	# board face with a soft top-left sheen and old marker ghosts
	_vgrad(img, 7, 7, 162, 92, Color(0.910, 0.915, 0.885), Color(0.845, 0.850, 0.825))
	for gp in [Vector3i(40, 70, 14), Vector3i(120, 82, 10)]:
		for yy in range(gp.y - 6, gp.y + 7):
			for xx in range(gp.x - gp.z, gp.x + gp.z + 1):
				if _hash(xx, yy) % 4 != 0:
					_px(img, xx, yy, Color(0.55, 0.56, 0.58, 0.06))   # eraser smear
	# diagram: node boxes chained by arrows, drawn with total confidence
	var cols := [Color(0.17, 0.25, 0.55), Color(0.63, 0.17, 0.17), Color(0.14, 0.14, 0.18)]
	var nodes := []
	for i in 7:
		nodes.append(Vector2i(18 + _rng.randi_range(0, w - 60), 14 + _rng.randi_range(0, h - 52)))
	for i in nodes.size():
		var n: Vector2i = nodes[i]
		var col: Color = cols[i % cols.size()]
		_rect(img, n.x, n.y, 14, 9, Color(0.96, 0.96, 0.94))
		_rect(img, n.x, n.y, 14, 1, col)
		_rect(img, n.x, n.y + 8, 14, 1, col)
		_rect(img, n.x, n.y, 1, 9, col)
		_rect(img, n.x + 13, n.y, 1, 9, col)
		_line(img, n.x + 3, n.y + 4, n.x + 10, n.y + 4, col.lightened(0.30))
		if i > 0:
			var p: Vector2i = nodes[i - 1]
			var x0 := p.x + 7
			var y0 := p.y + 4
			var x1 := n.x + 7
			var y1 := n.y + 4
			_line(img, x0, y0, x1, y1, cols[(i + 1) % cols.size()])
			var dirv := Vector2(x1 - x0, y1 - y0).normalized()
			var pv := Vector2(-dirv.y, dirv.x)
			for k: float in [1.0, -1.0]:
				var wpt := Vector2(x1, y1) - dirv * 4.0 + pv * 3.0 * k
				_line(img, x1, y1, int(wpt.x), int(wpt.y), cols[(i + 1) % cols.size()])
	# the red circle of concern
	for a in 64:
		var ang := TAU * float(a) / 64.0
		_px(img, 122 + int(cos(ang) * 24.0), 38 + int(sin(ang) * 14.0), Color(0.75, 0.16, 0.16))
	# the crossed-out plan (it was the good one)
	_line(img, 24, 78, 58, 96, Color(0.75, 0.16, 0.16))
	_line(img, 58, 78, 24, 96, Color(0.75, 0.16, 0.16))
	# marker tray with the tools of chaos
	_rect(img, 30, 104, 116, 6, alu.lightened(0.10))
	_rect(img, 30, 104, 116, 1, alu.lightened(0.30))
	_rect(img, 40, 105, 12, 3, Color(0.63, 0.17, 0.17))
	_rect(img, 58, 105, 12, 3, Color(0.17, 0.25, 0.55))
	_rect(img, 76, 105, 12, 3, Color(0.14, 0.14, 0.18))
	_rect(img, 100, 104, 16, 4, Color(0.55, 0.56, 0.60))
	_rect(img, 100, 104, 16, 1, Color(0.70, 0.71, 0.75))
	_finish(img, Color(0.95, 0.96, 1.0), 0.22)
	_save(img, "furn_whiteboard.png")

func _door() -> void:
	# Front door: recessed panels, keypad with a judgmental green LED, and warm
	# hallway light leaking underneath. The outside world remains theoretical.
	var w := 96
	var h := 140
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var d := Color(0.185, 0.140, 0.125)
	var fr := Color(0.095, 0.085, 0.105)
	# frame with a lit inner lip
	_rect(img, 2, 0, 92, 138, fr)
	_rect(img, 2, 0, 92, 2, fr.lightened(0.22))
	_rect(img, 2, 0, 2, 138, fr.lightened(0.12))
	_rect(img, 92, 0, 2, 138, fr.darkened(0.25))
	_rect(img, 8, 6, 2, 130, fr.lightened(0.18))
	_rect(img, 10, 6, 1, 130, fr.darkened(0.35))
	# door slab with vertical falloff
	_vgrad(img, 11, 8, 74, 126, d.lightened(0.08), d.darkened(0.16))
	# recessed panels: dark inset ring, AO at the top, lighter inner face
	for pn in [Vector2i(18, 18), Vector2i(18, 76)]:
		var ph := 46 if pn.y == 18 else 48
		_rect(img, pn.x, pn.y, 60, ph, d.darkened(0.38))
		_rect(img, pn.x + 2, pn.y + 2, 56, ph - 4, d.lightened(0.05))
		_rect(img, pn.x + 2, pn.y + 2, 56, 2, d.darkened(0.24))    # panel AO
		_rect(img, pn.x + 2, pn.y + 2, 1, ph - 4, d.lightened(0.14))
		_rect(img, pn.x + 2, pn.y + ph - 3, 56, 1, d.lightened(0.10))
	# handle: brass, one hot glint
	_rect(img, 72, 66, 10, 4, Color(0.30, 0.24, 0.14))
	_rect(img, 73, 64, 8, 7, Color(0.72, 0.58, 0.28))
	_rect(img, 73, 64, 8, 2, Color(0.85, 0.72, 0.38))
	_px(img, 74, 64, WHITE_HOT)
	# keypad: the lock is smarter than the tenant
	_rect(img, 60, 44, 13, 16, Color(0.075, 0.080, 0.100))
	_rect(img, 60, 44, 13, 1, Color(0.16, 0.17, 0.20))
	for ky in 3:
		for kx2 in 2:
			_rect(img, 63 + kx2 * 5, 50 + ky * 3, 3, 2, Color(0.22, 0.23, 0.28))
	_glow(img, 66, 46, ACID)
	# kick scuffs
	_line(img, 20, 124, 34, 126, d.darkened(0.30))
	_line(img, 52, 128, 62, 127, d.darkened(0.25))
	# hallway light under the door (there is a world out there, allegedly)
	_rect(img, 11, 134, 74, 2, Color(0.03, 0.025, 0.03))
	for sy in 4:
		_rect(img, 13, 136 + sy, 70, 1, Color(1.0, 0.75, 0.42, 0.22 - 0.05 * float(sy)))
	_finish(img, RIM_WARM, 0.30)
	_save(img, "furn_door.png")

# ------------------------------------------------- shared fx + decals -------

func _fx_radial() -> void:
	# 128x128 soft radial falloff: light cookie for every PointLight2D in town.
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for y in 128:
		for x in 128:
			var t := clampf(Vector2(x - 63.5, y - 63.5).length() / 62.0, 0.0, 1.0)
			var a := smoothstep(1.0, 0.0, t)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a * a))
	_save(img, "fx_radial_soft.png")

func _decal_grime() -> void:
	# Translucent floor grime splats (alpha <= 0.35): irregular blob clusters
	# with ragged edges, pinholes and stray speckles. Three moods of filth.
	var tints := [Color(0.040, 0.045, 0.070), Color(0.070, 0.050, 0.030), Color(0.040, 0.055, 0.035)]
	for i in 3:
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		var rng := RandomNumberGenerator.new()
		rng.seed = 777 + i * 131
		var blobs := []
		for b in 5 + i:
			blobs.append(Vector3(rng.randf_range(18.0, 46.0), rng.randf_range(18.0, 46.0), rng.randf_range(5.0, 15.0)))
		var tint: Color = tints[i]
		for y in 64:
			for x in 64:
				var field := 0.0
				for bl in blobs:
					var v: Vector3 = bl
					var dist := Vector2(x - v.x, y - v.y).length()
					dist *= 0.8 + 0.45 * float(_hash(x + i * 977, y) % 97) / 97.0
					field += maxf(0.0, 1.0 - dist / v.z)
				if field <= 0.02:
					continue
				var a := clampf(field * 0.5, 0.0, 1.0) * 0.32
				if _hash(x * 3, y + i) % 17 == 0:
					a *= 0.4
				img.set_pixel(x, y, Color(tint.r, tint.g, tint.b, a))
		for s in 26:
			var sx := rng.randi_range(4, 59)
			var sy := rng.randi_range(4, 59)
			if img.get_pixel(sx, sy).a < 0.05:
				img.set_pixel(sx, sy, Color(tint.r, tint.g, tint.b, 0.22))
		_save(img, "decal_grime_%d.png" % i)

func _decal_ao_edge() -> void:
	# 32x32 vertical gradient, opaque black top -> transparent bottom.
	# Stamped along wall bases so rooms stop looking like paper dioramas.
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		var a := pow(1.0 - float(y) / 31.0, 1.6)
		for x in 32:
			img.set_pixel(x, y, Color(0, 0, 0, a))
	_save(img, "decal_ao_edge.png")

# --------------------------------------------------------------- helpers ----

func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	if c.a >= 1.0:
		img.set_pixel(x, y, c)
	else:
		img.set_pixel(x, y, img.get_pixel(x, y).blend(c))

func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for ix in range(x, x + w):
		for iy in range(y, y + h):
			if ix >= 0 and iy >= 0 and ix < img.get_width() and iy < img.get_height():
				if c.a >= 1.0:
					img.set_pixel(ix, iy, c)
				else:
					img.set_pixel(ix, iy, img.get_pixel(ix, iy).blend(c))

func _bevel(img: Image, x: int, y: int, w: int, h: int, base: Color, hi: float = 0.18, sh: float = 0.30) -> void:
	# 4-tone box lit from the top-left: shadow / base / light / rim corner.
	_rect(img, x, y, w, h, base)
	_rect(img, x, y + h - 2, w, 2, base.darkened(sh))
	_rect(img, x + w - 2, y, 2, h, base.darkened(sh * 0.8))
	_rect(img, x, y, w, 2, base.lightened(hi))
	_rect(img, x, y, 2, h, base.lightened(hi * 0.6))
	_px(img, x, y, base.lightened(hi * 1.6))

func _vgrad(img: Image, x: int, y: int, w: int, h: int, top: Color, bottom: Color) -> void:
	# Vertical gradient with a 2x2 checker dither so large faces never band.
	for iy in range(y, y + h):
		var t := float(iy - y) / maxf(1.0, float(h - 1))
		for ix in range(x, x + w):
			var tt := t + (0.045 if (((ix >> 1) + (iy >> 1)) & 1) == 0 else -0.045)
			_px(img, ix, iy, top.lerp(bottom, clampf(tt, 0.0, 1.0)))

func _shadow(img: Image, cx: int, cy: int, rx: int, ry: int, amt: float = 0.34) -> void:
	# Baked soft contact shadow: quadratic-falloff ellipse. Draw before the body.
	for y in range(cy - ry, cy + ry + 1):
		for x in range(cx - rx, cx + rx + 1):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var dd := Vector2(float(x - cx) / float(rx), float(y - cy) / float(ry)).length()
			if dd <= 1.0:
				img.set_pixel(x, y, img.get_pixel(x, y).blend(Color(0.01, 0.015, 0.04, amt * (1.0 - dd * dd))))

func _glow(img: Image, x: int, y: int, halo: Color) -> void:
	# WHITE_HOT core + accent halo cross: bright enough for HDR bloom to catch.
	_px(img, x, y, WHITE_HOT)
	for o in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		_px(img, x + o.x, y + o.y, Color(halo.r, halo.g, halo.b, 0.85))
	for o in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
		_px(img, x + o.x, y + o.y, Color(halo.r, halo.g, halo.b, 0.38))

func _finish(img: Image, rim: Color, rim_amt: float = 0.5) -> void:
	# Silhouette pass: rim light on top-left edges, then a 1px outline into the
	# surrounding empty space. Solidity is sampled once so the passes don't
	# cascade into each other.
	var w := img.get_width()
	var h := img.get_height()
	var solid := PackedByteArray()
	solid.resize(w * h)
	for y in h:
		for x in w:
			solid[y * w + x] = 1 if img.get_pixel(x, y).a >= 0.55 else 0
	for y in h:
		for x in w:
			if solid[y * w + x] == 1:
				if rim_amt <= 0.0:
					continue
				var open_up := y == 0 or solid[(y - 1) * w + x] == 0
				var open_left := x == 0 or solid[y * w + x - 1] == 0
				if open_up or open_left:
					img.set_pixel(x, y, img.get_pixel(x, y).lerp(rim, rim_amt))
			else:
				var edge := false
				if x > 0 and solid[y * w + x - 1] == 1:
					edge = true
				elif x < w - 1 and solid[y * w + x + 1] == 1:
					edge = true
				elif y > 0 and solid[(y - 1) * w + x] == 1:
					edge = true
				elif y < h - 1 and solid[(y + 1) * w + x] == 1:
					edge = true
				if edge:
					img.set_pixel(x, y, img.get_pixel(x, y).blend(OUTLINE))

func _line(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	var dx: int = abs(x1 - x0)
	var dy: int = -abs(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err := dx + dy
	var x := x0
	var y := y0
	for _i in 200:
		if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
			if c.a >= 1.0:
				img.set_pixel(x, y, c)
			else:
				img.set_pixel(x, y, img.get_pixel(x, y).blend(c))
		if x == x1 and y == y1:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy

func _hash(a: int, b: int) -> int:
	var h := (a * 73856093) ^ (b * 19349663)
	return abs(h)

func _save(img: Image, filename: String) -> void:
	img.save_png(ProjectSettings.globalize_path(OUT_DIR + filename))
