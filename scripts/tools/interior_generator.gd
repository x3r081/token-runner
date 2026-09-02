extends RefCounted
class_name InteriorGenerator
## Procedurally generates purpose-built interior art for the Localhost apartment
## plus the shared structure props that dress every region.
##
## VISUAL_BIBLE_V2. Three tones per material lit from the top-left, a 1px
## outline, and ONE white-hot core pixel per genuine light source. No rim light
## (that is the player's alone), no baked glow halos, no dithering below 24px,
## and no per-pixel noise on anything the floor stamps three hundred times.
## Also emits the shared fx/decal manifest (light cookie, grime, wall-base AO).

const OUT_DIR := "res://assets/textures/generated/"

# Bible palette (see docs/VISUAL_BIBLE_V2.md). Outline is #0A0C16 at 90%.
const OUTLINE := Color(0.039, 0.047, 0.086, 0.90)
const WHITE_HOT := Color(0.957, 0.976, 1.0)
const CYAN := Color(0.141, 0.941, 0.863)
const CYAN_HOT := Color(0.49, 1.0, 0.941)
const AMBER := Color(1.0, 0.69, 0.125)
const RED := Color(1.0, 0.278, 0.341)
## Kept only so every _finish() call site still reads. _finish ignores them now:
## LAW 7 gives the fourth "rim" tone to the player and to nobody else.
const RIM_WARM := Color(1.0, 0.85, 0.62)
const RIM_COOL := Color(0.94, 0.95, 1.0)
## 4x4 ordered-dither thresholds. Used on exactly one surface: the 76px
## containment sphere, which is well above LAW 7's 24px dither floor and would
## band visibly in four flat tones.
const BAYER4 := [0.0, 0.5, 0.125, 0.625,
	0.75, 0.25, 0.875, 0.375,
	0.1875, 0.6875, 0.0625, 0.5625,
	0.9375, 0.4375, 0.8125, 0.3125]

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
	_window_hero()
	_poster_art()
	_pizza_props()
	_power_strip()
	_sticky_strip()
	_can()
	_couch_tex()
	_tech_floor()
	_struct_slab()
	_struct_crate()
	_struct_console()
	_struct_tower()
	_struct_orb()
	_struct_arch()
	_dress_awning()
	_dress_stall()
	_dress_monolith()
	_dress_cooling_tower()
	_dress_ore_cart()
	_dress_whiteboard()
	_dress_filing_cabinet()
	_dress_cubicle()
	_dress_laser_emitter()
	_dress_noodle_cup()
	_dress_cable_spool()
	_dress_pipe_stack()
	_fx_radial()
	_decal_grime()
	_decal_ao_edge()
	_decal_floor_set()
	print("Interior assets generated.")

# ------------------------------------------- themed region primitives -------
# These are drawn near-grayscale so region palettes can tint them via modulate.
# Emissive details keep their own hue (or sit near-white so the tint owns them).

func _tech_floor() -> void:
	# The neutral deck under every region, and the single texture that decides
	# whether the world reads as GROUND or as a spreadsheet. It fills roughly
	# four cells in ten of every floor.
	#
	# LAW 6: a floor tile is a clean 32px material with three tones — base, seam,
	# lit lip — and nothing else. Deleted here: two octaves of wrapped value
	# noise, per-pixel grit, a two-octave "wear field", a 16px diagonal tread
	# lattice, quartz flecks, dark pits, eleven hairline scratches at assorted
	# angles and two coolant weep stains. Every one of those is a feature at a
	# FIXED offset in a texture that is stamped three hundred times per region,
	# so all of them became lattice contrast — which is the definition of a noise
	# floor. The mean value is unchanged at ~0.50, so no region re-lights.
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var mx := x & 31
			var my := y & 31
			var v := 0.500
			if mx == 0 or my == 0:
				v = 0.412            # the cast seam between panels
			elif mx == 1 or my == 1:
				v = 0.548            # near lip, catching the top-left light
			img.set_pixel(x, y, Color(v, v * 1.015, v * 1.115, 1.0))
	_save(img, "tech_floor.png")

func _struct_slab() -> void:
	# Monolith. A rectangle is not a silhouette, so this one tapers as it rises,
	# wears a bolted collar that overhangs the body, has one corner sheared off
	# at an angle, and carries a stub mast with a bead hot enough to bloom. Drawn
	# near-greyscale: every region multiplies it by its own tint (0.44-0.78), so
	# a mid-grey body lands as a near-black shape on a dark floor.
	var img := Image.create(80, 120, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var g := Color(0.66, 0.67, 0.72)
	_shadow(img, 40, 113, 35, 6, 0.34)
	# plinth: wider than the shaft, with a chamfered cap and a shadowed toe
	_rect(img, 6, 100, 68, 12, g.darkened(0.14))
	_rect(img, 6, 100, 68, 2, g.lightened(0.22))
	_rect(img, 6, 100, 3, 12, g.lightened(0.10))
	_rect(img, 71, 100, 3, 12, g.darkened(0.34))
	_rect(img, 6, 109, 68, 3, g.darkened(0.44))
	# shaft: tapers 4px per side over its height, so the outline is never
	# parallel to the frame. Drawn row by row with its own vertical falloff.
	for y in range(6, 101):
		var t := float(y - 6) / 94.0
		var inset := int(round(4.0 * (1.0 - t)))
		var x0 := 10 + inset
		var xw := 60 - inset * 2
		var body := g.lightened(0.09).lerp(g.darkened(0.20), t)
		# 2x2 dither so the tall face never bands
		for ix in range(x0, x0 + xw):
			var d := 0.02 if (((ix >> 1) + (y >> 1)) & 1) == 0 else -0.02
			_px(img, ix, y, Color(body.r + d, body.g + d, body.b + d, 1.0))
		_rect(img, x0, y, 3, 1, body.lightened(0.17))          # lit left face
		_rect(img, x0 + xw - 3, y, 3, 1, body.darkened(0.30))  # shadowed right
	_rect(img, 14, 6, 52, 3, g.lightened(0.30))                # lit top cap
	# sheared top-left corner: a diagonal bite, not a clean rectangle
	for oy in 13:
		_clear(img, 14, 6 + oy, 13 - oy, 1)
	for oy in 13:
		_px(img, 14 + (12 - oy), 6 + oy, g.lightened(0.26))    # fresh cut edge
		_px(img, 15 + (12 - oy), 6 + oy, g.darkened(0.10))
	# fluting: shallow vertical grooves down the shaft, shadow then caught light
	for fx: int in [22, 34, 46, 58]:
		for y in range(14, 99):
			var t := float(y - 6) / 94.0
			var inset := int(round(4.0 * (1.0 - t)))
			if fx <= 11 + inset or fx >= 68 - inset:
				continue
			_px(img, fx, y, img.get_pixel(fx, y).darkened(0.22))
			_px(img, fx + 1, y, img.get_pixel(fx + 1, y).lightened(0.09))
	# bolted collar: overhangs both sides, which is where the silhouette earns
	# its keep. Bolt heads catch the top-left light.
	_rect(img, 7, 44, 66, 13, g.darkened(0.08))
	_rect(img, 7, 44, 66, 2, g.lightened(0.28))
	_rect(img, 7, 55, 66, 2, g.darkened(0.40))
	for bx in range(11, 70, 9):
		_bolt(img, bx, 48, g)
	# inset service panel below the collar, status column near-white so the
	# region tint owns the hue and the HDR pass owns the bloom
	_rect(img, 28, 62, 24, 30, g.darkened(0.34))
	_rect(img, 29, 63, 22, 28, g.darkened(0.10))
	_rect(img, 29, 63, 22, 1, g.darkened(0.46))
	_rect(img, 33, 67, 14, 1, Color(0.82, 0.85, 0.88))
	_rect(img, 33, 70, 9, 1, Color(0.72, 0.75, 0.79))
	_rect(img, 33, 76, 14, 1, Color(0.62, 0.64, 0.68))
	_rect(img, 33, 82, 9, 1, Color(0.52, 0.54, 0.58))
	_glow(img, 40, 88, Color(0.90, 0.93, 0.97))   # one lit indicator
	# stub mast with a bead: 6px of extra height reads as intent from across the
	# room, which is the whole job of a landmark prop
	_rect(img, 38, 0, 2, 7, g.darkened(0.18))
	_px(img, 38, 0, g.lightened(0.30))
	_glow(img, 39, 1, Color(0.92, 0.95, 1.0))
	# weathering: chipped edges and two cracks that follow the taper
	_line(img, 22, 16, 27, 38, g.darkened(0.32))
	_line(img, 23, 16, 28, 38, g.lightened(0.06))
	_line(img, 60, 68, 54, 96, g.darkened(0.32))
	for ch in 5:
		var cy := 20 + _hash(ch, 17) % 70
		var t2 := float(cy - 6) / 94.0
		var edge: int = 69 - int(round(4.0 * (1.0 - t2)))
		_clear(img, edge, cy, 2, 1 + _hash(ch, 19) % 3)
	_finish(img, RIM_COOL, 0.45)
	_save(img, "struct_slab.png")

func _struct_crate() -> void:
	# Shipping crate, pried open once and re-closed badly. A second, smaller crate
	# sits offset on the lid so the silhouette has a step in it instead of being
	# one honest rectangle. Contents unknown, which in this economy is a mercy.
	var img := Image.create(76, 66, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var g := Color(0.70, 0.63, 0.55)
	var steel := Color(0.72, 0.73, 0.77)
	_shadow(img, 38, 60, 35, 5, 0.32)
	# --- main crate body ---
	_bevel(img, 3, 16, 70, 42, g)
	# vertical plank seams: shadow + caught-light edge
	for px in range(13, 70, 10):
		_rect(img, px, 18, 1, 38, g.darkened(0.24))
		_rect(img, px + 1, 18, 1, 38, g.lightened(0.09))
	# grain dashes and knots so the wood is never a flat fill
	for gy in range(19, 56, 4):
		for gx in range(6, 68, 8):
			if _hash(gx, gy) % 3 == 0:
				_rect(img, gx, gy, 4, 1, g.darkened(0.11))
			elif _hash(gx, gy) % 19 == 0:
				_rect(img, gx + 1, gy, 2, 2, g.darkened(0.26))
	# diagonal braces, upper edge catching the light
	_line(img, 5, 18, 70, 55, g.darkened(0.32))
	_line(img, 5, 17, 70, 54, g.lightened(0.13))
	_line(img, 70, 18, 5, 55, g.darkened(0.32))
	_line(img, 70, 17, 5, 54, g.lightened(0.13))
	# steel strapping bands with buckles — the reason it is still one object
	for sy: int in [26, 46]:
		_rect(img, 3, sy, 70, 3, steel.darkened(0.26))
		_rect(img, 3, sy, 70, 1, steel.lightened(0.10))
		_rect(img, 48, sy - 1, 7, 5, steel.darkened(0.10))
		_rect(img, 48, sy - 1, 7, 1, steel.lightened(0.28))
		_px(img, 49, sy, Color(0.94, 0.95, 0.97))
	# corner brackets with bolt glints
	for bc: Vector2i in [Vector2i(3, 16), Vector2i(67, 16), Vector2i(3, 52), Vector2i(67, 52)]:
		_rect(img, bc.x, bc.y, 6, 6, steel.darkened(0.22))
		_rect(img, bc.x, bc.y, 6, 2, steel)
		_px(img, bc.x + 2, bc.y + 3, Color(0.92, 0.93, 0.95))
	# stencilled shipping marks: a code nobody scanned, on a crate nobody opened
	_rect(img, 24, 34, 16, 2, g.darkened(0.38))
	_rect(img, 24, 38, 11, 2, g.darkened(0.38))
	_rect(img, 44, 34, 8, 2, g.darkened(0.34))
	_rect(img, 44, 38, 5, 2, g.darkened(0.34))
	# --- the smaller crate, stacked offset on top ---
	_bevel(img, 26, 2, 40, 16, g.lightened(0.05))
	_rect(img, 26, 17, 40, 2, g.darkened(0.42))       # AO where it sits down
	for px2 in range(34, 64, 9):
		_rect(img, px2, 4, 1, 12, g.darkened(0.22))
		_rect(img, px2 + 1, 4, 1, 12, g.lightened(0.08))
	_rect(img, 26, 8, 40, 2, steel.darkened(0.30))    # its own strap
	_rect(img, 26, 8, 40, 1, steel.lightened(0.08))
	_bolt(img, 28, 4, steel)
	_bolt(img, 62, 4, steel)
	# the lid was levered up once and never sat flat again
	_rect(img, 26, 2, 40, 2, g.lightened(0.24))
	_line(img, 27, 3, 44, 1, g.lightened(0.34))
	_px(img, 44, 1, g.lightened(0.40))
	_finish(img, Color(0.95, 0.94, 0.90), 0.40)
	_save(img, "struct_crate.png")

func _struct_console() -> void:
	# Terminal kiosk. The cursor has been blinking since before you were born.
	var img := Image.create(88, 96, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var body := Color(0.50, 0.52, 0.58)
	# The hood is the point: an overhanging visor throws the screen into shade,
	# which gives the prop a real profile and lets the CRT stay bright without
	# blowing out. Grab rails on both flanks widen the silhouette.
	_shadow(img, 44, 91, 32, 5, 0.34)
	# splayed base plinth + a cable that leaves the frame
	_rect(img, 22, 80, 44, 10, body.darkened(0.36))
	_rect(img, 22, 80, 44, 2, body.darkened(0.14))
	_rect(img, 22, 88, 44, 2, body.darkened(0.52))
	_rect(img, 30, 66, 28, 16, body.darkened(0.30))          # pedestal neck
	_rect(img, 30, 66, 3, 16, body.darkened(0.14))
	_rect(img, 55, 66, 3, 16, body.darkened(0.44))
	_line(img, 62, 86, 80, 92, Color(0.15, 0.16, 0.19))
	_line(img, 62, 85, 80, 91, Color(0.24, 0.25, 0.28))
	# cabinet
	_bevel(img, 8, 10, 72, 58, body)
	# side grab rails — 4px of overhang each way, and the reason this reads as a
	# machine somebody services rather than a box somebody rendered
	for k: int in [0, 1]:
		var rx := 4 if k == 0 else 80
		_rect(img, rx, 30, 4, 22, body.darkened(0.22))
		_rect(img, rx, 30, 4, 2, body.lightened(0.18))
		_rect(img, rx, 50, 4, 2, body.darkened(0.44))
	# the hood: overhangs the bezel and casts AO on the glass below
	_rect(img, 5, 4, 78, 7, body.lightened(0.06))
	_rect(img, 5, 4, 78, 2, body.lightened(0.30))
	_rect(img, 5, 10, 78, 2, body.darkened(0.48))
	_rect(img, 5, 4, 3, 7, body.lightened(0.14))
	_rect(img, 80, 4, 3, 7, body.darkened(0.34))
	# recessed screen (stays cyan): bezel AO ring, scanlines, hot cursor
	_rect(img, 13, 14, 62, 40, Color(0.03, 0.10, 0.12))
	_rect(img, 14, 15, 60, 38, Color(0.10, 0.62, 0.66))
	_rect(img, 14, 15, 60, 4, Color(0.05, 0.30, 0.34))       # hood shadow on glass
	_rect(img, 14, 19, 60, 1, Color(0.08, 0.46, 0.50))
	for ly in range(16, 52, 3):
		_rect(img, 16, ly, 56, 1, Color(0.05, 0.34, 0.38, 0.55))
	# output lines of varying importance, indented like a real log
	_rect(img, 18, 22, 26, 2, Color(0.55, 0.97, 0.95))
	_rect(img, 22, 27, 34, 2, Color(0.40, 0.90, 0.90))
	_rect(img, 22, 32, 16, 2, Color(0.40, 0.90, 0.90))
	_rect(img, 18, 37, 30, 2, Color(0.55, 0.97, 0.95))
	_rect(img, 18, 42, 12, 2, Color(0.40, 0.90, 0.90))
	_glow(img, 34, 43, CYAN_HOT)                              # the eternal cursor
	# glass glare, top-right, under the hood line
	_line(img, 60, 21, 72, 33, Color(1, 1, 1, 0.14))
	_line(img, 56, 21, 73, 38, Color(1, 1, 1, 0.09))
	# key deck: two rows, a spacebar, a trackball worn shiny
	_rect(img, 20, 56, 48, 11, body.darkened(0.26))
	_rect(img, 20, 56, 48, 1, body.lightened(0.16))
	for kx in range(23, 55, 5):
		_rect(img, kx, 58, 3, 3, body.lightened(0.16))
		_rect(img, kx, 58, 3, 1, body.lightened(0.30))
		_rect(img, kx, 62, 3, 3, body.lightened(0.06))
	_rect(img, 24, 62, 24, 1, body.darkened(0.30))
	_disc(img, 62, 61, 3.6, body.darkened(0.10))
	_disc(img, 61, 60, 2.0, body.lightened(0.24))
	_px(img, 61, 59, Color(0.93, 0.94, 0.96))
	# speaker grille + status LEDs on the cabinet cheek
	for vy in range(58, 66, 2):
		_rect(img, 70, vy, 8, 1, body.darkened(0.40))
	_glow(img, 72, 52, Color(0.90, 0.93, 0.97))
	_finish(img, RIM_COOL, 0.42)
	_save(img, "struct_console.png")

func _struct_tower() -> void:
	# Full-height equipment tower: fan intake, bays of blinking LEDs, vents.
	var img := Image.create(72, 150, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cab := Color(0.49, 0.51, 0.56)
	_shadow(img, 36, 144, 32, 5, 0.34)
	# anti-vibration feet + a plinth wider than the cabinet
	_rect(img, 4, 132, 64, 10, cab.darkened(0.34))
	_rect(img, 4, 132, 64, 2, cab.lightened(0.10))
	_rect(img, 4, 140, 64, 2, cab.darkened(0.52))
	for fx: int in [7, 57]:
		_rect(img, fx, 142, 8, 4, cab.darkened(0.46))
		_rect(img, fx, 142, 8, 1, cab.darkened(0.20))
	# cabinet body, chamfered at the top corners so the profile is not a slab
	_vgrad(img, 6, 12, 60, 122, cab.lightened(0.08), cab.darkened(0.24))
	_rect(img, 6, 12, 3, 122, cab.lightened(0.14))
	_rect(img, 63, 12, 3, 122, cab.darkened(0.30))
	for oy in 5:
		_clear(img, 6, 12 + oy, 5 - oy, 1)
		_clear(img, 61 + oy, 12 + oy, 5 - oy, 1)
		_px(img, 6 + (4 - oy), 12 + oy, cab.lightened(0.24))
		_px(img, 65 - (4 - oy), 12 + oy, cab.darkened(0.20))
	# crown: capping plate, a lifting eye, and a warning beacon that blooms
	_rect(img, 8, 6, 56, 7, cab.lightened(0.10))
	_rect(img, 8, 6, 56, 2, cab.lightened(0.32))
	_rect(img, 8, 12, 56, 1, cab.darkened(0.44))
	_rect(img, 26, 2, 6, 5, cab.darkened(0.16))
	_clear(img, 27, 3, 4, 3)                              # the lifting eye's hole
	_rect(img, 46, 0, 5, 7, cab.darkened(0.22))
	_rect(img, 45, 0, 7, 2, Color(0.88, 0.90, 0.94))
	_glow(img, 48, 1, Color(0.95, 0.80, 0.35))
	# fan intake behind a wire guard: dark ring, hub, blades frozen mid-thought
	for a in 44:
		var ang := TAU * float(a) / 44.0
		_px(img, 36 + int(cos(ang) * 10.0), 26 + int(sin(ang) * 10.0), cab.darkened(0.48))
		_px(img, 36 + int(cos(ang) * 7.0), 26 + int(sin(ang) * 7.0), cab.darkened(0.30))
	for a in 5:
		var ang := TAU * float(a) / 5.0 + 0.5
		_line(img, 36, 26, 36 + int(cos(ang) * 9.0), 26 + int(sin(ang) * 9.0), cab.darkened(0.34))
		_line(img, 36, 25, 36 + int(cos(ang) * 9.0), 25 + int(sin(ang) * 9.0), cab.lightened(0.06))
	_disc(img, 36, 26, 2.4, cab.darkened(0.18))
	_px(img, 35, 25, cab.lightened(0.30))
	# side exhaust duct: 6px of overhang at mid-height, louvred, casting AO
	_rect(img, 66, 62, 6, 26, cab.darkened(0.22))
	_rect(img, 66, 62, 6, 2, cab.lightened(0.14))
	_rect(img, 66, 86, 6, 2, cab.darkened(0.48))
	for ly in range(66, 86, 4):
		_rect(img, 67, ly, 5, 2, cab.darkened(0.44))
		_rect(img, 67, ly, 5, 1, cab.darkened(0.16))
	_rect(img, 63, 62, 3, 26, cab.darkened(0.40))
	# equipment bays with LEDs that report nothing useful
	# ONE lit indicator per bay, near-white so the region tint owns its hue.
	# It used to be three saturated LEDs per bay, randomly on, each with a
	# nine-pixel halo — on a prop that is dressed into every region in the game.
	var led_on := Color(0.72, 0.76, 0.80)
	var led_off := Color(0.13, 0.14, 0.17)
	for u in range(38, 130, 19):
		_rect(img, 11, u, 50, 14, Color(0.07, 0.08, 0.10))
		_rect(img, 11, u, 50, 1, Color(0.03, 0.04, 0.05))
		_rect(img, 11, u + 13, 50, 1, cab.lightened(0.10))
		# a handle on every bay — the greeble that makes it read as rack-mount
		_rect(img, 13, u + 4, 2, 6, cab.lightened(0.12))
		_rect(img, 13, u + 4, 2, 1, cab.lightened(0.30))
		for i in 3:
			_rect(img, 19 + i * 7, u + 5, 3, 3, led_on if i == 0 else led_off)
		for vx in range(42, 58, 4):
			_rect(img, vx, u + 3, 2, 8, cab.darkened(0.42))
			_rect(img, vx, u + 3, 1, 8, cab.darkened(0.25))
	# one bay has been pulled halfway out and never pushed back
	_rect(img, 9, 95, 54, 14, Color(0.09, 0.10, 0.12))
	_rect(img, 9, 95, 54, 1, cab.lightened(0.18))
	_rect(img, 9, 108, 54, 1, Color(0.02, 0.03, 0.04))
	# cable loom leaving the bottom-right, held by a strap that is not enough
	_line(img, 60, 128, 70, 140, Color(0.16, 0.17, 0.20))
	_line(img, 59, 128, 69, 139, Color(0.24, 0.25, 0.28))
	_line(img, 56, 130, 68, 146, Color(0.15, 0.16, 0.19))
	_rect(img, 62, 133, 5, 2, cab.darkened(0.30))
	_finish(img, RIM_COOL, 0.42)
	_save(img, "struct_tower.png")

func _struct_orb() -> void:
	# Containment sphere in a gimbal cradle. A bare ball is a circle, not a prop:
	# the tripod, the equatorial band and the bracket arms are what give it a
	# read at forty metres. Near-greyscale so every region can tint it; the seam
	# and the specular sit near-white so the HDR pass owns the bloom.
	var img := Image.create(112, 112, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx := 56
	var cy := 46
	var rad := 38.0
	var steel := Color(0.60, 0.62, 0.68)
	_shadow(img, 56, 105, 34, 5, 0.36)
	# --- cradle, drawn first so the sphere sits inside it ---
	# base ring
	_ellipse(img, 56, 100, 26.0, 8.0, steel.darkened(0.28))
	_ellipse(img, 56, 99, 22.0, 6.0, steel.darkened(0.06))
	_ellipse(img, 56, 99, 15.0, 4.0, steel.darkened(0.42))
	_rect(img, 30, 100, 52, 3, steel.darkened(0.44))
	# --- the sphere ---
	for y in 112:
		for x in 112:
			var dx := float(x - cx) / rad
			var dy := float(y - cy) / rad
			var d := sqrt(dx * dx + dy * dy)
			if d <= 1.0:
				# lambert-ish from the top-left + darkened limb
				var lam := clampf(0.62 - 0.42 * (dx + dy) * 0.707, 0.08, 1.05)
				lam *= 1.0 - 0.35 * d * d
				# reflected bounce light along the lower rim
				if d > 0.82 and dy > 0.3:
					lam += 0.10
				# Quantize to 4 tones and ORDERED-dither the band boundaries. A
				# 2x2 checker put a coarse chessboard across half the sphere;
				# a 4x4 Bayer threshold spreads the same information at twice
				# the frequency and reads as a surface instead of a pattern.
				var q := floorf(lam * 4.0) / 4.0
				var bd: float = BAYER4[(y & 3) * 4 + (x & 3)]
				if fmod(lam * 4.0, 1.0) > bd:
					q += 0.25
				var b := clampf(0.24 + q * 0.76, 0.0, 1.0)
				img.set_pixel(x, y, Color(b, b, minf(b * 1.04, 1.0), 1.0))
	# panel seams: two meridians and one equator, curved with the surface
	for a in 180:
		var t := PI * float(a) / 180.0 - PI * 0.5
		var ex := cx + int(cos(t) * rad * 0.98)
		var ey := cy + int(sin(t) * rad * 0.22)
		_px(img, ex, ey, Color(0.86, 0.88, 0.93))
		_px(img, ex, ey + 1, Color(0.20, 0.21, 0.24, 0.6))
		var mx := cx + int(sin(t) * rad * 0.30)
		var my := cy + int(cos(t) * rad * 0.98)
		_px(img, mx, my, img.get_pixel(mx, my).darkened(0.26))
		var m2 := cx + int(sin(t) * rad * 0.72)
		_px(img, m2, my, img.get_pixel(m2, my).darkened(0.20))
	# hot specular blob, top-left, with a soft falloff shoulder
	for yy in range(24, 38):
		for xx in range(28, 44):
			var sd := Vector2(xx - 36, yy - 30).length()
			if sd < 3.4:
				img.set_pixel(xx, yy, Color(0.93, 0.94, 0.97))
			elif sd < 6.2:
				_px(img, xx, yy, Color(0.90, 0.92, 0.98, (6.2 - sd) * 0.10))
	_glow(img, 36, 29, Color(0.92, 0.95, 1.0))
	# --- cradle hardware, drawn over the sphere so it reads as holding it ---
	# three struts rising from the base ring, the centre one behind and dimmer
	for k: float in [-1.0, 0.0, 1.0]:
		var bx: int = 56 + int(k * 25.0)
		var tx: int = 56 + int(k * 33.0)
		var dim := 0.36 if is_zero_approx(k) else 0.10
		_line(img, bx, 98, tx, 54, steel.darkened(dim))
		_line(img, bx + 1, 98, tx + 1, 54, steel.lightened(0.16 - dim * 0.3))
		_line(img, bx + 2, 98, tx + 2, 54, steel.darkened(dim + 0.22))
	# bracket arms cupping the equator, bolted through
	for k: float in [-1.0, 1.0]:
		var ax: int = 56 + int(k * 33.0)
		_rect(img, ax - 3, 40, 7, 16, steel.darkened(0.14))
		_rect(img, ax - 3, 40, 7, 2, steel.lightened(0.24))
		_rect(img, ax - 3, 54, 7, 2, steel.darkened(0.46))
		_rect(img, ax - 3, 40, 2, 16, steel.lightened(0.10))
		_bolt(img, ax - 1, 45, steel)
		_bolt(img, ax - 1, 50, steel)
	# the equatorial containment band, in front of the sphere
	for a in 240:
		var ang := TAU * float(a) / 240.0
		var bx2 := cx + int(cos(ang) * (rad + 2.0))
		var by2 := cy + int(sin(ang) * (rad + 2.0) * 0.26)
		var front := sin(ang) > 0.0
		_px(img, bx2, by2, Color(0.74, 0.76, 0.82, 0.95 if front else 0.30))
		_px(img, bx2, by2 - 1, Color(0.90, 0.92, 0.96, 0.80 if front else 0.22))
		_px(img, bx2, by2 + 2, Color(0.28, 0.30, 0.34, 0.75 if front else 0.18))
	# one wide orbit ring, tilted the other way, with a white-hot bead on it
	for a in 260:
		var ang2 := TAU * float(a) / 260.0
		var px2 := cx + int(cos(ang2) * 52.0)
		var py2 := cy + int(sin(ang2) * 52.0 * 0.34) + 10
		var front2 := sin(ang2) > 0.0
		_px(img, px2, py2, Color(0.92, 0.93, 0.97, 0.80 if front2 else 0.24))
	_glow(img, cx + int(cos(1.9) * 52.0), cy + int(sin(1.9) * 52.0 * 0.34) + 10, Color(0.9, 0.93, 1.0))
	_finish(img, RIM_COOL, 0.30)
	_save(img, "struct_orb.png")

func _struct_arch() -> void:
	# Ruined stone arch: coursed masonry, cracks, a bite missing from the
	# lintel, rubble underneath, and carved glyphs that still glow. Legacy code.
	var img := Image.create(150, 128, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var stone := Color(0.64, 0.62, 0.58)
	_shadow(img, 25, 122, 21, 5, 0.32)
	_shadow(img, 125, 122, 21, 5, 0.32)
	# two pillars of coursed blocks with staggered joints + value jitter. The
	# left one carries a plinth and stands straight; the right one has lost its
	# outer face and leans a pixel. Symmetry is what made this read as a doorway
	# asset rather than a ruin.
	for pi in 2:
		var px0: int = 10 if pi == 0 else 110
		for y in range(20, 122):
			var course := (y - 20) / 17
			var shift := (course % 2) * 8
			var lean: int = 0 if pi == 0 else (121 - y) / 40
			for x in range(px0 + lean, px0 + 30 + lean):
				var block := (x - px0 - lean + shift) / 15
				var j := float(_hash(block + px0, course) % 9 - 4) / 80.0
				var c := Color(stone.r + j, stone.g + j, stone.b + j, 1.0)
				# per-block weathering speckle: pitted limestone, not poured grey
				if _hash(x * 3, y * 5) % 11 == 0:
					c = c.darkened(0.07)
				elif _hash(x * 7, y * 3) % 23 == 0:
					c = c.lightened(0.09)
				if (y - 20) % 17 == 0:
					c = c.darkened(0.32)                     # mortar course
				elif (y - 20) % 17 == 1:
					c = c.lightened(0.09)                    # lit block top
				elif (x - px0 - lean + shift) % 15 == 0:
					c = c.darkened(0.28)                     # vertical joint
				if x < px0 + lean + 3:
					c = c.lightened(0.13)
				elif x > px0 + lean + 26:
					c = c.darkened(0.26)
				img.set_pixel(x, y, c)
		# spalled corners: bite blocks out of the outer silhouette so the edge
		# stops being a ruler line
		for sp in 7:
			var sy: int = 24 + _hash(sp + pi * 31, 13) % 92
			var sw: int = 2 + _hash(sp + pi * 31, 17) % 4
			var sh: int = 2 + _hash(sp + pi * 31, 19) % 5
			var outer: bool = _hash(sp + pi * 7, 23) % 2 == 0
			var sx: int = (px0 + 30 - sw) if outer else px0
			_clear(img, sx, sy, sw, sh)
			_rect(img, sx, sy + sh, sw, 1, stone.darkened(0.40))
		# cracks + carved glowing glyph column (near-white: region tint owns it)
		_line(img, px0 + 6, 40, px0 + 12, 70, stone.darkened(0.36))
		_line(img, px0 + 7, 40, px0 + 13, 70, stone.lightened(0.06))
		_line(img, px0 + 20, 78, px0 + 14, 108, stone.darkened(0.30))
		_rect(img, px0 + 13, 30, 5, 1, Color(0.58, 0.58, 0.55))
		_rect(img, px0 + 13, 37, 5, 1, Color(0.52, 0.52, 0.50))
		_glow(img, px0 + 15, 44, Color(0.90, 0.92, 0.88))
		# damp streaks running down from the lintel joint
		for st in 4:
			var stx: int = px0 + 4 + _hash(st + pi * 11, 29) % 22
			var stl: int = 14 + _hash(st + pi * 11, 31) % 26
			for sy2 in range(22, 22 + stl):
				_px(img, stx, sy2, Color(0.10, 0.11, 0.12, 0.10))
	# plinth under the left pillar; the right one's has already gone
	_rect(img, 6, 112, 38, 10, stone.darkened(0.10))
	_rect(img, 6, 112, 38, 2, stone.lightened(0.18))
	_rect(img, 6, 120, 38, 2, stone.darkened(0.44))
	# lintel with lit top face and a shadowed underside
	_rect(img, 4, 6, 142, 26, stone)
	_rect(img, 4, 6, 142, 3, stone.lightened(0.17))
	_rect(img, 4, 29, 142, 3, stone.darkened(0.36))
	for lx in range(16, 140, 19):
		_rect(img, lx, 9, 1, 20, stone.darkened(0.24))
		_rect(img, lx + 1, 9, 1, 20, stone.lightened(0.06))
	# keystone, dropped a couple of pixels and cracked through
	_rect(img, 66, 4, 20, 30, stone.lightened(0.05))
	_rect(img, 66, 4, 20, 2, stone.lightened(0.26))
	_rect(img, 66, 4, 2, 30, stone.lightened(0.12))
	_rect(img, 84, 4, 2, 30, stone.darkened(0.30))
	_line(img, 76, 6, 72, 32, stone.darkened(0.42))
	# jagged missing chunk out of the lintel, left of the keystone
	for gx in range(38, 66):
		var depth: int = 22 - absi(gx - 52) + (_hash(gx, 1) % 5)
		for gy in range(4, 4 + maxi(depth, 0)):
			if gy < 34:
				img.set_pixel(gx, gy, Color(0, 0, 0, 0))
	for gx2 in range(38, 66):
		var d2: int = 22 - absi(gx2 - 52) + (_hash(gx2, 1) % 5)
		if d2 > 0 and 4 + d2 < 34:
			img.set_pixel(gx2, 4 + d2, stone.lightened(0.22))
	# a chain still hanging from the lintel underside; whatever it held is gone
	for cy2 in range(32, 56):
		var wob: int = (cy2 >> 1) & 1
		_px(img, 100 + wob, cy2, stone.darkened(0.38))
		_px(img, 101 + wob, cy2, stone.lightened(0.14))
	_px(img, 100, 56, stone.darkened(0.20))
	_px(img, 101, 56, stone.darkened(0.20))
	# a fallen slab leaning against the right pillar
	for sy3 in 26:
		var off: int = sy3 / 3
		_rect(img, 138 - off, 96 + sy3, 10, 1, stone.darkened(0.06 + 0.004 * float(sy3)))
		_px(img, 138 - off, 96 + sy3, stone.lightened(0.16))
	# rubble where the chunk landed
	for r in 13:
		var rx := 40 + _hash(r, 5) % 66
		var ry := 114 + _hash(r, 9) % 9
		var rw := 2 + _hash(r, 11) % 3
		_rect(img, rx, ry, rw + 1, 2, stone.darkened(0.10 + 0.02 * float(r % 4)))
		_px(img, rx, ry, stone.lightened(0.12))
	_finish(img, RIM_COOL, 0.40)
	_save(img, "struct_arch.png")

# ---------------------------------------------------------------- floor -----

func _floor_tiles() -> void:
	# Warm plank flooring: 16px boards, a seam, a lit board edge, one staggered
	# butt joint per variant. Three variants that differ by 4% of VALUE and by
	# where their joint falls — nothing else. Per LAW 6 the variants must sit
	# within 6% of each other, or a mixed floor reads as patchwork.
	#
	# Deleted: two grain waves, per-plank value jitter, per-pixel noise, a knot
	# in two of three variants, a scuffed traffic streak, a sun-bleached patch
	# and a coaster ring. At a 64px stamp every one of those repeated on a grid.
	var base := Color(0.318, 0.234, 0.166)
	var joints: Array[int] = [12, 34, 52]
	for v in 3:
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		var k: float = 1.0 - 0.04 * float(v)
		var body := Color(base.r * k, base.g * k, base.b * k, 1.0)
		var seam := body.darkened(0.34)
		var lip := body.lightened(0.14)
		var joint: int = joints[v]
		for y in 64:
			var ry := y & 15
			var row := y >> 4
			var c := body
			if ry == 0:
				c = seam
			elif ry == 1:
				c = lip
			elif ry == 15:
				c = body.darkened(0.14)
			for x in 64:
				var cc := c
				# one butt joint, on one course only, so the boards have a
				# direction without the floor turning into masonry
				if row == 1 and ry > 0:
					if x == joint:
						cc = seam
					elif x == joint + 1:
						cc = lip
				img.set_pixel(x, y, cc)
		# LAW 6's "one subtle inset detail on ~10% of tiles": exactly one knot,
		# in exactly one of the three variants.
		if v == 2:
			_knot(img, 44, 55, body)
		_save(img, "int_floor_%d.png" % v)

func _knot(img: Image, cx: int, cy: int, c: Color) -> void:
	# Wood knot: dark heart, growth ring, faint highlight toward the light.
	# Deliberately low contrast — it is a feature that repeats on every third
	# tile, so it has to whisper.
	for y in img.get_height():
		for x in img.get_width():
			var d := Vector2(x - cx, y - cy).length()
			if d < 1.5:
				img.set_pixel(x, y, c.darkened(0.30))
			elif d < 3.0:
				img.set_pixel(x, y, c.darkened(0.13))
			elif d < 4.2:
				img.set_pixel(x, y, c.darkened(0.21))
	_px(img, cx - 3, cy - 3, c.lightened(0.06))

func _rug() -> void:
	# A woven rug that anchors the battlestation zone: field, two guard bands,
	# one accent band, a simple medallion and an end fringe.
	#
	# LAW 2: it used to carry indigo, teal, rust, gold thread AND a fringe
	# colour — five hues in one prop, in a region that is allowed three. It is
	# now the region's cool BASE plus ONE accent band, in three values.
	var w := 320
	var h := 224
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var field := Color(0.150, 0.180, 0.250)
	var guard := Color(0.105, 0.125, 0.180)
	var band := Color(0.220, 0.400, 0.440)      # the one accent, already muted
	var fringe_col := Color(0.400, 0.380, 0.340)
	var cx := w / 2
	var cy := h / 2
	# baked drop shadow so the rug sits ON the floor instead of hovering
	_rect(img, 8, 12, w - 9, h - 13, Color(0.01, 0.015, 0.04, 0.24))
	for y in h:
		for x in w:
			var edge: int = min(min(x, w - 1 - x), min(y, h - 1 - y))
			# End fringe: short tassels beyond the woven body (top/bottom).
			if y < 6 or y >= h - 6:
				if (x % 6) < 3 and x > 10 and x < w - 10:
					img.set_pixel(x, y, fringe_col)
				continue
			if edge < 4:
				continue
			var c := field
			if edge < 9:
				c = guard                        # outer guard band
			elif edge < 13:
				c = band                         # the accent frame
			elif edge < 17:
				c = guard
			else:
				# Field with a single concentric medallion in two values.
				var dman: int = int(absf(x - cx) * 0.7) + int(absf(y - cy))
				if dman < 62 and dman >= 56:
					c = band.darkened(0.20)
				elif dman < 18 and dman >= 12:
					c = band.darkened(0.20)
				elif dman < 6:
					c = guard
			img.set_pixel(x, y, c)
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
				# field: gentle top-to-bottom falloff plus panel seams. The
				# dither speckle, the per-pixel noise and the random scuffs are
				# gone — a wall is a large flat surface and it should read as one.
				var t := float(y - 9) / 66.0
				c = wall.lightened(0.07 * (1.0 - t)).darkened(0.12 * t)
				if x % 32 == 0:
					c = c.darkened(0.26)                 # panel seam
				elif x % 32 == 1:
					c = c.lightened(0.11)                # seam edge catches light
				if y == 52:
					c = trim.lightened(0.20)             # wainscot rail
				elif y == 53:
					c = c.darkened(0.30)
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
	# Skirting light: ONE dim, even warm strip in the channel above the
	# baseboard. It is the localhost WARM, and it is here because it separates
	# wall from floor in a single value step. The sine-modulated brightness ramp
	# and the hot LED are gone: a strip light is a strip, not a chase sequence.
	for lx in 64:
		img.set_pixel(lx, 75, Color(0.26, 0.17, 0.09).lerp(AMBER.darkened(0.42), 0.55))
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
			side.set_pixel(x, y, c)
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
				# stars, none of them overbright
				if t < 0.55 and _hash(x * 7, y * 13) % 601 == 0:
					c = Color(0.62, 0.66, 0.80)
				# far skyline (hazy blue towers)
				var fh: int = 20 + _hash(x >> 4, 3) % 22
				if y > h - 12 - fh:
					c = Color(0.075, 0.082, 0.155)
				# near skyline (near-black) with a window grid
				var nh: int = 12 + _hash((x * 7) >> 6, 7) % 36
				if y > h - 10 - nh:
					c = Color(0.028, 0.032, 0.058)
					# LAW 8's skyline rule, applied to the view as well as the
					# menu: a few lit windows in WARM and ACCENT, not confetti.
					# The density was 1-in-7 with white-hot outliers; it is now
					# 1-in-23 with no overbright pixels at all.
					if (x % 4) != 0 and (y % 5) < 2 and _hash(x >> 2, (y * 13) >> 6) % 23 == 0:
						c = Color(0.72, 0.54, 0.26) if _hash(x, y) % 3 != 0 else Color(0.26, 0.58, 0.62)
			img.set_pixel(x, y, c)
	# The moon: a crisp disc in two tones with one crater tone (LAW 8). The soft
	# halo ring and the white-hot crescent are gone — a moon is a shape, and a
	# blurred bright ring around it is the exact "everything blooms" tell.
	for yy in range(24, 42):
		for xx in range(110, 128):
			var d := Vector2(xx - 118, yy - 32).length()
			if d < 7.0:
				img.set_pixel(xx, yy, Color(0.82, 0.84, 0.90) if (xx - 118) + (yy - 32) < 0 else Color(0.70, 0.72, 0.80))
	_px(img, 120, 34, Color(0.58, 0.60, 0.68))   # one crater tone
	_px(img, 121, 35, Color(0.58, 0.60, 0.68))
	_px(img, 118, 36, Color(0.58, 0.60, 0.68))
	# neon sign on one near tower (magenta, hot cores every few px). The key
	# for the tower-height hash matches the columns the sign sits on.
	# ONE neon sign, one pixel wide, in the region WARM. The magenta core with
	# two white-hot pips was a third hue and two bloom sources in a background.
	var sign_top: int = h - 10 - (12 + _hash((39 * 7) >> 6, 7) % 36) + 4
	var sign_bot: int = mini(sign_top + 16, h - 10)
	for sy in range(sign_top, sign_bot):
		_px(img, 39, sy, Color(0.72, 0.46, 0.22))
	# glass: two faint diagonal reflections + warm interior spill low down
	for y in range(8, h - 8):
		for x in range(8, w - 8):
			var dg := x - y
			if absi(dg - 20) < 3 or absi(dg - 34) < 2:
				_px(img, x, y, Color(0.80, 0.90, 1.0, 0.05))
			if y > h - 30:
				var a := float(y - (h - 30)) / 22.0 * 0.08
				_px(img, x, y, Color(1.0, 0.80, 0.50, a))
	# The condensation runnels and the 34 fog speckles are gone. They were
	# scattered marks at fixed offsets over a background nobody looks at, and
	# LAW 4 is blunt about scatter: the answer is zero.
	# fairy lights taped along the inside of the top rail. They were for the
	# holidays. It is not the holidays. One warm pixel each, no hot cores: at
	# twelve bulbs a string, white-hot was twelve bloom sources on one prop.
	for lx in range(14, w - 14, 12):
		var ly: int = 11 + (1 if (lx / 12) % 2 == 0 else 0)
		_px(img, lx, ly, Color(0.86, 0.64, 0.34))
	for cx2 in range(9, w - 9):
		_px(img, cx2, 10 + int(sin(float(cx2) * 0.26) * 1.0), Color(0.20, 0.20, 0.24, 0.55))
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
	# Round-4 exposure lift: captured frames put the old 0.235 top BELOW the
	# floor's in-game value, so the whole battlestation read as a black cutout.
	# The slab now sits a step above the boards, and the legs a step below it —
	# three honest values before the rim light even lands.
	# LAW 7: desaturated toward the region BASE. The old slab was violet-brown,
	# which put a fourth hue under the whole battlestation.
	var top := Color(0.285, 0.258, 0.250)
	var legc := Color(0.125, 0.122, 0.140)
	_shadow(img, 120, 89, 108, 6, 0.32)
	# legs with feet
	_bevel(img, 10, 46, 12, 44, legc)
	_bevel(img, 218, 46, 12, 44, legc)
	_rect(img, 8, 88, 16, 3, legc.darkened(0.30))
	_rect(img, 216, 88, 16, 3, legc.darkened(0.30))
	# under-desk cable tray with cables that were "temporary" two years ago
	_rect(img, 26, 52, 188, 5, Color(0.07, 0.07, 0.10))
	_line(img, 30, 54, 120, 56, Color(0.17, 0.18, 0.22))
	_line(img, 60, 54, 200, 55, Color(0.13, 0.14, 0.17))
	# drawer pedestal: three drawers, one of which does not close any more
	var ped := Color(0.155, 0.140, 0.185)
	_bevel(img, 166, 50, 48, 38, ped)
	for di in 3:
		var dy := 53 + di * 12
		var dxo: int = 3 if di == 1 else 0        # the middle one sticks out
		_rect(img, 169 - dxo, dy, 42, 10, ped.lightened(0.10))
		_rect(img, 169 - dxo, dy, 42, 1, ped.lightened(0.28))
		_rect(img, 169 - dxo, dy + 9, 42, 1, ped.darkened(0.34))
		_rect(img, 182 - dxo, dy + 4, 16, 2, ped.darkened(0.30))
		_rect(img, 182 - dxo, dy + 4, 16, 1, ped.lightened(0.22))
	# desktop slab: lit top face with lengthwise grain, shadowed front edge
	_rect(img, 2, 22, 236, 24, top)
	for gy in range(25, 45, 4):
		for gx in range(6, 232, 13):
			if _hash(gx, gy) % 3 == 0:
				_rect(img, gx, gy, 7, 1, top.darkened(0.08))
	_rect(img, 2, 22, 236, 1, Color(0.56, 0.50, 0.58))   # rim edge, catches light
	_rect(img, 2, 23, 236, 2, top.lightened(0.10))
	_rect(img, 2, 22, 2, 24, top.lightened(0.08))
	_rect(img, 2, 46, 236, 4, top.darkened(0.35))        # front edge board
	_rect(img, 2, 50, 236, 1, top.darkened(0.55))
	# cable grommet cut through the desktop, loom dropping into the tray
	_ellipse(img, 100, 28, 7.0, 3.4, top.darkened(0.42))
	_ellipse(img, 100, 28, 5.6, 2.4, Color(0.045, 0.048, 0.070))
	_rect(img, 95, 26, 11, 1, top.lightened(0.16))
	_line(img, 97, 28, 94, 25, Color(0.17, 0.18, 0.22))
	_line(img, 104, 28, 108, 24, Color(0.13, 0.14, 0.17))
	# monitor riser: a low plinth the screen stands on, plus the books under it
	_rect(img, 20, 18, 44, 6, top.darkened(0.18))
	_rect(img, 20, 18, 44, 1, top.lightened(0.22))
	_rect(img, 20, 23, 44, 1, top.darkened(0.44))
	_rect(img, 24, 24, 36, 3, Color(0.30, 0.22, 0.24))
	_rect(img, 24, 24, 36, 1, Color(0.42, 0.32, 0.32))
	# headphone stand: post, hook, and the cans hanging where they always are
	_rect(img, 40, 6, 4, 17, Color(0.13, 0.14, 0.18))
	_rect(img, 40, 6, 1, 17, Color(0.24, 0.26, 0.32))
	_rect(img, 34, 4, 16, 3, Color(0.15, 0.16, 0.21))
	_rect(img, 34, 4, 16, 1, Color(0.28, 0.30, 0.36))
	for a in 26:
		var ang := PI + PI * float(a) / 25.0
		_px(img, 42 + int(cos(ang) * 9.0), 12 + int(sin(ang) * 9.0), Color(0.11, 0.12, 0.16))
		_px(img, 42 + int(cos(ang) * 8.0), 12 + int(sin(ang) * 8.0), Color(0.20, 0.22, 0.28))
	_rect(img, 31, 11, 5, 8, Color(0.13, 0.14, 0.18))
	_rect(img, 31, 11, 5, 2, Color(0.22, 0.24, 0.30))
	_rect(img, 48, 11, 5, 8, Color(0.10, 0.11, 0.15))
	# keyboard, backlit because obviously, with a wrist rest nobody uses right
	_rect(img, 56, 44, 78, 2, Color(0.10, 0.10, 0.14))
	_rect(img, 56, 44, 78, 1, Color(0.21, 0.22, 0.27))
	_rect(img, 58, 30, 74, 14, Color(0.065, 0.07, 0.09))
	_rect(img, 58, 30, 74, 1, Color(0.14, 0.15, 0.19))
	for kx in range(62, 126, 6):
		_rect(img, kx, 33, 4, 3, Color(0.22, 0.24, 0.30))
		_rect(img, kx, 33, 4, 1, Color(0.30, 0.32, 0.38))
		_px(img, kx + 1, 34, Color(0.44, 0.46, 0.54))          # keycap legend
		_rect(img, kx, 38, 4, 3, Color(0.22, 0.24, 0.30))
		_rect(img, kx, 38, 4, 1, Color(0.30, 0.32, 0.38))
		_px(img, kx + 1, 39, Color(0.40, 0.42, 0.50))
	# THE ONE lit surface on this prop: the keyboard underglow, in the region
	# ACCENT, on the surface it actually falls on. Removed: the caps-lock glow,
	# the magenta mouse LED and the cyan headphone-stand LED — three separate
	# emissive points on one desk, in three different hues.
	_rect(img, 61, 37, 68, 1, Color(CYAN.r, CYAN.g, CYAN.b, 0.26))  # key glow leak
	_rect(img, 61, 44, 68, 1, Color(CYAN.r, CYAN.g, CYAN.b, 0.14))  # underglow spill
	# mouse
	_rect(img, 146, 34, 11, 8, Color(0.10, 0.11, 0.15))
	_rect(img, 146, 34, 11, 2, Color(0.20, 0.22, 0.28))
	# mug of coffee, load-bearing, desaturated to the room
	_rect(img, 172, 26, 14, 16, Color(0.42, 0.28, 0.22))
	_rect(img, 172, 26, 3, 16, Color(0.52, 0.36, 0.28))
	_rect(img, 186, 30, 3, 8, Color(0.35, 0.23, 0.18))   # handle
	_rect(img, 173, 27, 12, 2, Color(0.14, 0.10, 0.08))  # coffee surface
	# ONE sticky note. There were two, in two different hues, saying the same word.
	_rect(img, 200, 27, 9, 9, Color(0.72, 0.62, 0.34))
	_px(img, 208, 35, Color(0.52, 0.44, 0.22))
	_line(img, 202, 30, 206, 30, Color(0.32, 0.26, 0.13))
	_line(img, 202, 33, 205, 33, Color(0.32, 0.26, 0.13))
	# a cable escaping off the right end of the desk
	_line(img, 132, 44, 226, 48, Color(0.10, 0.10, 0.14))
	_finish(img, RIM_WARM, 0.55)
	_save(img, "furn_desk.png")

func _monitor() -> void:
	# Bezel + stand; the screen well stays dark so the builder can overlay a
	# bright animated screen. Standby LED included, for ambience and guilt.
	var w := 96
	var h := 84
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var bez := Color(0.105, 0.110, 0.140)
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
	# webcam bump on the top edge: a lens, a ring, and a tally light that is on
	# rather more often than anyone in this apartment realises
	_rect(img, 42, 0, 12, 3, bez.lightened(0.06))
	_rect(img, 42, 0, 12, 1, bez.lightened(0.26))
	_disc(img, 48, 1, 1.6, Color(0.03, 0.04, 0.06))
	_px(img, 47, 1, Color(0.30, 0.40, 0.52))
	_px(img, 53, 1, Color(0.34, 0.20, 0.21))
	# chin vents + brand notch
	for vx in range(30, 66, 3):
		_rect(img, vx, 58, 2, 2, bez.darkened(0.34))
		_rect(img, vx, 58, 2, 1, bez.lightened(0.10))
	_rect(img, 45, 60, 6, 1, bez.lightened(0.20))
	# stand arm: a proper cantilever with a hinge, not a post
	_rect(img, w / 2 - 3, 62, 6, 6, bez.lightened(0.16))
	_disc(img, w / 2, 68, 3.2, bez.lightened(0.08))
	_px(img, w / 2 - 1, 66, bez.lightened(0.34))
	_rect(img, w / 2 - 12, 71, 24, 3, bez.lightened(0.04))
	_rect(img, w / 2 - 12, 71, 24, 1, bez.lightened(0.22))
	# cable looping off the back-right
	_line(img, 74, 60, 88, 72, Color(0.09, 0.10, 0.13))
	_line(img, 74, 59, 88, 71, Color(0.16, 0.17, 0.21))
	# standby LED
	_glow(img, 88, 59, CYAN)
	_finish(img, Color(0.75, 0.95, 1.0), 0.45)
	_save(img, "furn_monitor.png")

func _server_rack() -> void:
	# Home server rack: dithered cabinet, recessed bays, LEDs hot enough to
	# bloom, one tiny status screen, cables performing an escape.
	var w := 96
	var h := 168
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cab := Color(0.175, 0.185, 0.235)
	_shadow(img, w / 2, 164, 42, 3, 0.34)
	_vgrad(img, 2, 2, 92, 158, cab.lightened(0.10), cab.darkened(0.22))
	_rect(img, 2, 2, 92, 2, cab.lightened(0.30))
	_rect(img, 2, 2, 4, 158, cab.lightened(0.16))
	_rect(img, 90, 2, 4, 158, cab.darkened(0.30))
	# feet
	_rect(img, 8, 160, 10, 4, cab.darkened(0.35))
	_rect(img, 78, 160, 10, 4, cab.darkened(0.35))
	# rack units
	# LAW 2/LAW 3: the rack used to run four saturated LED hues across seven
	# bays — up to twenty-eight lights, each with a nine-pixel halo, on one
	# prop. It is now ONE lit indicator per bay in the region ACCENT, and the
	# rest of the bay reads as dark hardware.
	var led_on := CYAN.darkened(0.30)
	var led_off := Color(0.10, 0.13, 0.15)
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
				var on: bool = i == 0
				_rect(img, 16 + i * 8, u + 4, 4, 4, led_on if on else led_off)
				if on:
					_px(img, 17 + i * 8, u + 5, WHITE_HOT)
		# vent slits with a lit edge
		for sx in range(56, w - 12, 4):
			_rect(img, sx, u + 3, 2, 9, cab.darkened(0.42))
			_rect(img, sx, u + 3, 1, 9, cab.darkened(0.20))
		# corner screws
		_px(img, 12, u + 2, cab.lightened(0.30))
		_px(img, w - 13, u + 2, cab.lightened(0.30))
	# patch panel: 24 ports, six of them lit, none of them labelled correctly
	_rect(img, 10, 150, w - 20, 10, Color(0.06, 0.07, 0.09))
	_rect(img, 10, 150, w - 20, 1, Color(0.02, 0.03, 0.04))
	for pi in 12:
		var px := 13 + pi * 6
		_rect(img, px, 153, 4, 4, Color(0.12, 0.13, 0.16))
		_rect(img, px, 153, 4, 1, Color(0.03, 0.04, 0.05))
		if pi % 4 == 0:
			_px(img, px + 1, 155, CYAN.darkened(0.45))
	# a dymo label strip that says something wrong, confidently
	_rect(img, 14, 6, 34, 4, Color(0.66, 0.66, 0.62))
	_rect(img, 14, 6, 34, 1, Color(0.80, 0.80, 0.76))
	for lx in range(16, 46, 3):
		_rect(img, lx, 8, 2, 1, Color(0.16, 0.16, 0.18))
	# casters, because it was going to be moved "next week", in 2019
	for cx: int in [10, 76]:
		_disc(img, cx + 5, 165, 3.4, cab.darkened(0.44))
		_disc(img, cx + 5, 164, 2.0, cab.lightened(0.10))
		_px(img, cx + 4, 163, cab.lightened(0.32))
	# cable spaghetti exiting stage left
	_line(img, 20, 160, 8, 166, Color(0.15, 0.16, 0.20))
	_line(img, 26, 160, 12, 167, Color(0.12, 0.13, 0.16))
	_line(img, 32, 160, 18, 167, Color(0.16, 0.17, 0.22))
	_finish(img, Color(0.70, 0.95, 1.0), 0.50)
	_save(img, "furn_server.png")

func _bed() -> void:
	# Decorative sleep surface. The laptop lives here now; the human does not.
	var w := 168
	var h := 108
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var frame := Color(0.200, 0.170, 0.152)
	var sheet := Color(0.290, 0.300, 0.335)
	var blanket := Color(0.230, 0.245, 0.290)
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
	# Three tones, and none of them near-white: a pillow that reads brighter than
	# the player is a pillow the eye goes to first.
	_rect(img, 14, 20, 44, 26, Color(0.60, 0.62, 0.68))
	_rect(img, 14, 20, 44, 3, Color(0.70, 0.72, 0.78))
	_rect(img, 14, 20, 3, 26, Color(0.66, 0.68, 0.74))
	_rect(img, 14, 43, 44, 3, Color(0.46, 0.48, 0.54))
	_rect(img, 55, 20, 3, 26, Color(0.50, 0.52, 0.58))
	# the laptop, open, mid-build, judging you
	_rect(img, 108, 24, 36, 22, Color(0.085, 0.095, 0.125))
	_rect(img, 108, 24, 36, 1, Color(0.18, 0.20, 0.25))
	# The laptop screen is the ONE motivated light on this prop (LAW 3), so it
	# keeps its accent and its single hot pixel; everything else on the bed is
	# cloth.
	_rect(img, 111, 26, 30, 15, Color(0.065, 0.22, 0.24))
	_rect(img, 113, 28, 18, 1, Color(0.30, 0.70, 0.68))
	_rect(img, 113, 31, 24, 1, Color(0.24, 0.56, 0.55))
	_rect(img, 113, 34, 12, 1, Color(0.30, 0.70, 0.68))
	_px(img, 128, 37, WHITE_HOT)
	# charger brick and the cable that reaches exactly nowhere useful
	_rect(img, 148, 62, 9, 7, Color(0.62, 0.63, 0.66))
	_rect(img, 148, 62, 9, 2, Color(0.72, 0.73, 0.76))
	_rect(img, 148, 68, 9, 1, Color(0.42, 0.43, 0.46))
	_line(img, 148, 65, 132, 58, Color(0.56, 0.57, 0.60))
	_line(img, 132, 58, 126, 48, Color(0.56, 0.57, 0.60))
	# phone, face down, because that is how boundaries are set
	_rect(img, 76, 66, 9, 16, Color(0.09, 0.10, 0.13))
	_rect(img, 76, 66, 9, 1, Color(0.18, 0.20, 0.25))
	_rect(img, 78, 68, 3, 3, Color(0.14, 0.15, 0.19))
	# a paperback, spine cracked, left open at page 12 since March
	_rect(img, 24, 66, 26, 14, Color(0.62, 0.58, 0.50))
	_rect(img, 24, 66, 26, 2, Color(0.78, 0.74, 0.66))
	_rect(img, 36, 66, 2, 14, Color(0.44, 0.40, 0.34))
	_rect(img, 24, 79, 26, 1, Color(0.36, 0.33, 0.28))
	_finish(img, RIM_WARM, 0.42)
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
		_rect(img, 64, hy, 5, 32, Color(0.55, 0.57, 0.62))
		_rect(img, 68, hy, 1, 32, Color(0.36, 0.38, 0.43))
		_rect(img, 64, hy, 5, 2, Color(0.66, 0.68, 0.72))
	# temperature display: it reads an error code, like everything else here
	_rect(img, 12, 10, 22, 11, Color(0.045, 0.055, 0.075))
	_rect(img, 12, 10, 22, 1, Color(0.02, 0.025, 0.035))
	_rect(img, 15, 13, 4, 5, CYAN.darkened(0.30))
	_rect(img, 21, 13, 4, 5, CYAN.darkened(0.30))
	_px(img, 27, 17, CYAN.darkened(0.30))
	_px(img, 17, 13, WHITE_HOT)
	# Energy-drink magnets in three VALUES of one muted tone. They used to be
	# green, red and blue — three saturated hues on a door, in a region allowed
	# three hues in total.
	for m in [Vector3i(14, 28, 0), Vector3i(30, 32, 1), Vector3i(46, 30, 2)]:
		var mc: Color = [Color(0.36, 0.40, 0.38), Color(0.42, 0.36, 0.35), Color(0.33, 0.36, 0.42)][m.z]
		_rect(img, m.x, m.y, 10, 16, mc.darkened(0.15))
		_rect(img, m.x, m.y, 10, 3, mc.lightened(0.20))
		_rect(img, m.x, m.y + 14, 10, 2, mc.darkened(0.40))
		_px(img, m.x + 1, m.y + 1, mc.lightened(0.45))
	# grocery list sticky note: it just says "sleep". aspirational.
	_rect(img, 40, 78, 13, 11, Color(0.66, 0.62, 0.48))
	_px(img, 52, 88, Color(0.48, 0.44, 0.32))
	_line(img, 42, 81, 49, 81, Color(0.35, 0.32, 0.20))
	_line(img, 42, 84, 46, 84, Color(0.35, 0.32, 0.20))
	# takeaway menu, held by a magnet, curled at one corner from being consulted
	_rect(img, 14, 46, 14, 12, Color(0.62, 0.61, 0.57))
	_rect(img, 14, 46, 14, 1, Color(0.70, 0.69, 0.66))
	_rect(img, 16, 49, 9, 1, Color(0.42, 0.26, 0.24))
	_rect(img, 16, 52, 7, 1, Color(0.36, 0.34, 0.32))
	_rect(img, 16, 54, 8, 1, Color(0.36, 0.34, 0.32))
	_px(img, 27, 57, Color(0.66, 0.64, 0.58))
	_px(img, 26, 57, Color(0.74, 0.72, 0.66))
	_disc(img, 21, 45, 2.0, Color(0.26, 0.32, 0.40))
	_px(img, 20, 44, Color(0.38, 0.44, 0.52))
	# a dent in the lower door: something was slammed, once, memorably
	for dy in 7:
		var dw: int = 7 - absi(dy - 3)
		_rect(img, 40 - dw / 2, 96 + dy, dw, 1, body.darkened(0.20 + 0.03 * float(dy)))
	_rect(img, 37, 95, 7, 1, body.lightened(0.16))
	# door-seal light leak: the lower door has never quite closed
	for sy in 12:
		_px(img, 7, 68 + sy, Color(0.95, 0.96, 0.90, 0.16 - 0.01 * float(sy)))
	# kick vent + scuffs
	_rect(img, 8, 116, 68, 8, body.darkened(0.35))
	for sx in range(10, 74, 6):
		_rect(img, sx, 118, 3, 4, body.darkened(0.50))
		_rect(img, sx, 118, 3, 1, body.darkened(0.22))
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
	_rect(img, 18, 15, 3, 4, AMBER.darkened(0.40))
	_rect(img, 23, 15, 3, 4, AMBER.darkened(0.40))
	_rect(img, 28, 15, 2, 4, AMBER.darkened(0.40))
	# buttons. The sacred green light is gone: acid green in the localhost
	# apartment was a fourth hue spent on a two-pixel indicator.
	_rect(img, 38, 15, 3, 3, body.lightened(0.25))
	_rect(img, 43, 15, 3, 3, body.lightened(0.25))
	# dispenser cavity with an amber back-glow
	_rect(img, 16, 30, 36, 26, Color(0.030, 0.035, 0.050))
	_rect(img, 16, 30, 36, 1, Color(0.012, 0.015, 0.022))
	for yy in range(32, 55):
		for xx in range(18, 50):
			var d := Vector2(float(xx - 34) * 0.7, float(yy - 44)).length() / 12.0
			if d < 1.0:
				_px(img, xx, yy, Color(1.0, 0.62, 0.20, 0.10 * (1.0 - d)))
	# pour stream: amber, with ONE hot pixel where it catches the cavity light
	_rect(img, 33, 31, 2, 12, AMBER.darkened(0.14))
	_px(img, 33, 34, WHITE_HOT)
	# the mug, receiving
	_rect(img, 26, 42, 16, 13, Color(0.32, 0.25, 0.20))
	_rect(img, 26, 42, 3, 13, Color(0.41, 0.32, 0.26))
	_rect(img, 27, 43, 14, 2, Color(0.48, 0.36, 0.22))
	_rect(img, 42, 45, 3, 7, Color(0.26, 0.20, 0.16))
	# group head + portafilter: the bit that makes it look like a machine and
	# not a vending cabinet
	_rect(img, 28, 26, 12, 5, body.lightened(0.14))
	_rect(img, 28, 26, 12, 1, body.lightened(0.34))
	_rect(img, 40, 27, 10, 3, Color(0.32, 0.26, 0.16))
	_rect(img, 40, 27, 10, 1, Color(0.48, 0.40, 0.24))
	# water tank down the right flank, with a level you can read at a glance
	_rect(img, 52, 18, 8, 34, Color(0.20, 0.24, 0.30, 0.85))
	_rect(img, 52, 18, 8, 1, Color(0.34, 0.38, 0.46))
	_rect(img, 53, 34, 6, 17, Color(0.30, 0.52, 0.62, 0.75))
	_rect(img, 53, 34, 6, 1, Color(0.55, 0.80, 0.88))
	_rect(img, 52, 18, 1, 34, Color(0.42, 0.46, 0.54, 0.5))
	_px(img, 54, 24, Color(0.80, 0.88, 0.94, 0.5))
	# scale under the mug, reading a number nobody has ever acted on
	_rect(img, 22, 55, 24, 4, body.lightened(0.10))
	_rect(img, 22, 55, 24, 1, body.lightened(0.26))
	_rect(img, 26, 56, 8, 2, Color(0.05, 0.08, 0.10))
	_px(img, 28, 57, CYAN.darkened(0.45))
	_px(img, 31, 57, CYAN.darkened(0.45))
	# drip tray with a grate and the ring of every cup before this one
	_rect(img, 16, 60, 36, 5, body.darkened(0.30))
	_rect(img, 16, 60, 36, 1, body.lightened(0.15))
	for gx in range(18, 50, 3):
		_rect(img, gx, 62, 2, 2, body.darkened(0.48))
	_ellipse(img, 40, 62, 4.0, 1.4, Color(0.35, 0.20, 0.10, 0.45))
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
	_shadow(img, 32, 93, 24, 4, 0.32)
	# saucer, with the tide mark of the one time it was overwatered
	_ellipse(img, 32, 90, 19.0, 5.0, Color(0.30, 0.20, 0.15))
	_ellipse(img, 32, 89, 16.0, 3.6, Color(0.38, 0.26, 0.18))
	_ellipse(img, 32, 89, 11.0, 2.4, Color(0.24, 0.16, 0.12))
	# pot: terracotta, tapered, with a lit lip and AO under it
	for py in range(66, 90):
		var t := float(py - 66) / 23.0
		var inset := int(round(3.0 * t))
		var pc := Color(0.44, 0.29, 0.205).lerp(Color(0.33, 0.21, 0.15), t)
		_rect(img, 18 + inset, py, 28 - inset * 2, 1, pc)
		_rect(img, 18 + inset, py, 3, 1, pc.lightened(0.18))
		_rect(img, 43 - inset, py, 3, 1, pc.darkened(0.24))
	_rect(img, 15, 60, 34, 6, Color(0.50, 0.335, 0.235))
	_rect(img, 15, 60, 34, 1, Color(0.62, 0.44, 0.30))
	_rect(img, 15, 65, 34, 1, Color(0.30, 0.19, 0.14))
	_rect(img, 16, 66, 32, 2, Color(0.28, 0.18, 0.13))
	# a hairline crack down the pot; it survived one repotting
	_line(img, 26, 68, 24, 84, Color(0.24, 0.15, 0.11))
	# soil, with a couple of leca pebbles on top for the aesthetic
	_rect(img, 19, 62, 26, 3, Color(0.115, 0.085, 0.065))
	_px(img, 23, 62, Color(0.30, 0.24, 0.18))
	_px(img, 34, 63, Color(0.28, 0.22, 0.17))
	_px(img, 40, 62, Color(0.26, 0.21, 0.16))
	# bamboo stake with a tie; the plant is being held upright against its will
	_rect(img, 38, 24, 1, 38, Color(0.44, 0.38, 0.22))
	_rect(img, 39, 24, 1, 38, Color(0.28, 0.24, 0.14))
	_rect(img, 36, 40, 5, 1, Color(0.62, 0.58, 0.36))
	# stems + drooping leaves; two fronds have gone amber (end-of-life notice)
	var leaf := Color(0.225, 0.290, 0.200)
	for i in 6:
		var bx := 22 + i * 4
		var dying := i == 1 or i == 4
		# the end-of-life fronds read by VALUE, not by a second hue
		var lc := Color(0.400, 0.360, 0.230) if dying else leaf
		_line(img, 32, 62, bx, 46, Color(0.16, 0.22, 0.13))
		_line(img, 33, 62, bx + 1, 46, Color(0.22, 0.29, 0.17))
		for j in range(0, 32, 4):
			var yy := 58 - j
			var xx := bx + int(sin(float(j) * 0.3 + float(i)) * 7.0) + int(float(j) * 0.35)
			if yy < 5 or xx < 3 or xx >= w - 4:
				continue
			# a real leaf blade rather than a pixel: three cells, lit on the
			# top-left, with a darker midrib
			_ellipse(img, xx, yy, 3.4, 2.0, lc)
			_ellipse(img, xx - 1, yy - 1, 2.0, 1.2, lc.lightened(0.20))
			_px(img, xx + 2, yy + 1, lc.darkened(0.26))
			_px(img, xx, yy, lc.darkened(0.14))
	# one fallen leaf; no one has swept
	_ellipse(img, 52, 88, 3.0, 1.6, Color(0.38, 0.34, 0.22))
	_px(img, 51, 87, Color(0.46, 0.41, 0.28))
	_px(img, 53, 89, Color(0.28, 0.25, 0.16))
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
	var ca := Color(0.40, 0.34, 0.27)
	var cb := Color(0.45, 0.38, 0.30)
	var cc := Color(0.47, 0.40, 0.32)
	var cd := Color(0.36, 0.31, 0.25)
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
	_rect(img, 110, 38, 8, 8, Color(0.62, 0.52, 0.24))
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
	# Seven spilling packages in TWO muted tones instead of five saturated ones.
	_package(img, 40, 38, Color(0.42, 0.34, 0.30))
	_package(img, 50, 42, Color(0.32, 0.35, 0.42))
	_package(img, 44, 52, Color(0.42, 0.34, 0.30))
	_package(img, 58, 60, Color(0.32, 0.35, 0.42))
	_package(img, 14, 88, Color(0.42, 0.34, 0.30))
	_package(img, 98, 92, Color(0.32, 0.35, 0.42))
	_package(img, 66, 94, Color(0.42, 0.34, 0.30))
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
	var wood := Color(0.270, 0.212, 0.172)
	_bevel(img, 2, 2, 136, 116, wood)
	# Three muted spine tones, not six saturated ones. A wall of books is a
	# TEXTURE: it earns its read from the vertical rhythm of the spines, not
	# from being a colour wheel.
	var shelf_cols := [Color(0.36, 0.30, 0.28), Color(0.28, 0.31, 0.37), Color(0.33, 0.34, 0.30)]
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
				_rect(img, x, by, bw, bh, Color(0.10, 0.45, 0.42))
				_rect(img, x + 1, by + 2, bw - 2, 1, CYAN.darkened(0.25))
				_px(img, x + bw / 2, by + 10, WHITE_HOT)
			x += bw + 2
		if shelf_i == 1:
			# one book gave up and leans against the frame (relatable)
			for iy in 22:
				_rect(img, 98 + (iy >> 2), s + 5 + iy, 7, 1, Color(0.38, 0.31, 0.28).darkened(0.012 * float(iy)))
			# rubber duck, senior debugging consultant
			# The duck stays; the duck stops glowing. One warm tone, two values,
			# and no white-hot glint in a five-pixel eye.
			_rect(img, 116, s + 18, 9, 7, Color(0.66, 0.55, 0.26))
			_rect(img, 116, s + 18, 9, 2, Color(0.76, 0.64, 0.32))
			_rect(img, 122, s + 14, 5, 6, Color(0.66, 0.55, 0.26))
			_rect(img, 126, s + 16, 3, 2, Color(0.56, 0.34, 0.18))  # beak
			_px(img, 124, s + 15, Color(0.15, 0.12, 0.08))          # eye
		if shelf_i == 2:
			# horizontal stack: books demoted to being a monitor stand someday
			for st in 3:
				var sc: Color = shelf_cols[(st + 2) % shelf_cols.size()]
				_rect(img, 100, s + 13 + st * 5, 30, 5, sc.darkened(0.12))
				_rect(img, 100, s + 13 + st * 5, 30, 1, sc.lightened(0.20))
		# shelf board with a lit front edge, and dust along it
		_rect(img, 4, s + 28, 132, 4, wood.lightened(0.10))
		_rect(img, 4, s + 28, 132, 1, wood.lightened(0.28))
		for dx in range(8, 132, 3):
			if _hash(dx, s) % 3 == 0:
				_px(img, dx, s + 29, wood.lightened(0.34))
		shelf_i += 1
	# framed photo of a team that has since been reorganised twice
	_rect(img, 88, 12, 20, 20, Color(0.28, 0.23, 0.18))
	_rect(img, 88, 12, 20, 1, Color(0.40, 0.34, 0.26))
	_rect(img, 90, 14, 16, 16, Color(0.14, 0.16, 0.22))
	_rect(img, 92, 22, 12, 6, Color(0.24, 0.27, 0.34))
	_disc(img, 95, 20, 2.0, Color(0.48, 0.42, 0.37))
	_disc(img, 101, 20, 2.0, Color(0.44, 0.38, 0.34))
	# an unopened box of something bought during a productivity phase
	_rect(img, 8, 106, 26, 10, Color(0.46, 0.36, 0.24))
	_rect(img, 8, 106, 26, 2, Color(0.58, 0.46, 0.30))
	_rect(img, 18, 106, 3, 10, Color(0.38, 0.30, 0.20))
	_rect(img, 12, 110, 12, 2, Color(0.30, 0.24, 0.16))
	_finish(img, RIM_WARM, 0.48)
	_save(img, "furn_shelf.png")

func _chair() -> void:
	# Gaming chair, racing stripes included. Top speed: reverse, slowly, at 3AM.
	var w := 64
	var h := 88
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Color(0.180, 0.185, 0.215)
	_shadow(img, 32, 84, 22, 3, 0.30)
	# star base + wheels first (they sit behind everything)
	for wp in [Vector2i(10, 82), Vector2i(54, 82), Vector2i(20, 85), Vector2i(44, 85), Vector2i(32, 86)]:
		_line(img, 32, 78, wp.x, wp.y, c.darkened(0.25))
		_rect(img, wp.x - 2, wp.y, 4, 3, c.darkened(0.40))
		_px(img, wp.x - 2, wp.y, c.lightened(0.15))
	# gas lift with a piston highlight
	_rect(img, 29, 62, 6, 17, c.darkened(0.30))
	_rect(img, 29, 62, 2, 17, c.lightened(0.10))
	# seat: bolstered edges and a cushion that has taken the shape of a person
	# who has not stood up since Tuesday
	_bevel(img, 10, 46, 44, 15, c.darkened(0.05))
	_rect(img, 10, 46, 7, 15, c.lightened(0.10))          # left bolster
	_rect(img, 47, 46, 7, 15, c.darkened(0.16))           # right bolster
	_rect(img, 18, 48, 28, 11, c.darkened(0.14))          # compressed centre
	_rect(img, 18, 48, 28, 1, c.darkened(0.28))
	_line(img, 22, 53, 42, 53, c.darkened(0.10))
	# armrests with padded tops and a post each
	_rect(img, 5, 38, 7, 5, c.darkened(0.14))
	_rect(img, 5, 38, 7, 2, c.lightened(0.16))
	_rect(img, 7, 43, 3, 9, c.darkened(0.32))
	_rect(img, 52, 38, 7, 5, c.darkened(0.24))
	_rect(img, 52, 38, 7, 2, c.lightened(0.06))
	_rect(img, 54, 43, 3, 9, c.darkened(0.38))
	# backrest: mesh panel inside a frame, magenta racing stripes (+0 WPM)
	_bevel(img, 14, 12, 36, 35, c)
	_rect(img, 18, 16, 28, 27, c.darkened(0.30))
	for my in range(17, 43, 2):
		_rect(img, 19, my, 26, 1, c.darkened(0.12))
	for mx in range(19, 45, 2):
		_rect(img, mx, 17, 1, 25, c.darkened(0.06))
	_rect(img, 18, 16, 28, 1, c.darkened(0.46))           # AO under the frame lip
	# Racing stripes in a muted rust: at full magenta this chair carried a hue
	# that nothing else in localhost uses, on a prop nobody ever looks at.
	_rect(img, 20, 14, 2, 31, Color(0.34, 0.22, 0.26))
	_rect(img, 42, 14, 2, 31, Color(0.34, 0.22, 0.26))
	_rect(img, 16, 28, 32, 4, c.lightened(0.04))          # lumbar support bar
	_rect(img, 16, 28, 32, 1, c.lightened(0.20))
	_rect(img, 16, 31, 32, 1, c.darkened(0.34))
	# headrest pillow with stitches, mounted on two visible stalks
	_rect(img, 22, 10, 3, 4, c.darkened(0.30))
	_rect(img, 39, 10, 3, 4, c.darkened(0.30))
	_bevel(img, 19, 3, 26, 9, c.lightened(0.06))
	_line(img, 22, 7, 42, 7, c.darkened(0.18))
	_px(img, 24, 6, Color(0.34, 0.22, 0.26))
	_px(img, 39, 6, Color(0.34, 0.22, 0.26))
	# a hoodie left over the backrest, because of course it is
	_rect(img, 44, 18, 9, 20, Color(0.21, 0.24, 0.31))
	_rect(img, 44, 18, 9, 2, Color(0.29, 0.32, 0.40))
	_rect(img, 44, 18, 2, 20, Color(0.26, 0.29, 0.36))
	_rect(img, 45, 36, 7, 2, Color(0.13, 0.15, 0.20))
	_finish(img, RIM_COOL, 0.0)
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
	# Two inks: the dark one and the one thing circled in red. A whiteboard with
	# three marker hues is three hues spent on a background prop.
	var cols := [Color(0.20, 0.21, 0.26), Color(0.55, 0.20, 0.20), Color(0.20, 0.21, 0.26)]
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
		_px(img, 122 + int(cos(ang) * 24.0), 38 + int(sin(ang) * 14.0), Color(0.60, 0.22, 0.22))
	# the crossed-out plan (it was the good one)
	_line(img, 24, 78, 58, 96, Color(0.60, 0.22, 0.22))
	_line(img, 58, 78, 24, 96, Color(0.60, 0.22, 0.22))
	# DO NOT ERASE, underlined twice, in the hand of somebody who meant it
	_rect(img, 108, 12, 44, 3, Color(0.16, 0.16, 0.20))
	_rect(img, 108, 17, 44, 1, Color(0.60, 0.22, 0.22))
	_rect(img, 108, 19, 38, 1, Color(0.60, 0.22, 0.22))
	# sticky-note cluster: four estimates, none of them survived contact
	for si in 4:
		var sx: int = 14 + (si % 2) * 13
		var sy: int = 14 + (si / 2) * 13
		# one paper colour in two values, not four hues
		var sc: Color = Color(0.74, 0.66, 0.42) if si % 2 == 0 else Color(0.68, 0.60, 0.38)
		_rect(img, sx, sy, 11, 11, sc)
		_rect(img, sx, sy, 11, 1, sc.lightened(0.24))
		_rect(img, sx, sy + 10, 11, 1, sc.darkened(0.26))
		_line(img, sx + 2, sy + 3, sx + 8, sy + 3, sc.darkened(0.50))
		_line(img, sx + 2, sy + 6, sx + 6, sy + 6, sc.darkened(0.50))
	# magnet holding a printout that contradicts the diagram
	_rect(img, 132, 62, 26, 30, Color(0.94, 0.94, 0.92))
	_rect(img, 132, 62, 26, 1, Color(1.0, 1.0, 0.98))
	for py in range(66, 88, 3):
		_line(img, 135, py, 154, py, Color(0.52, 0.53, 0.56))
	_disc(img, 145, 63, 2.2, Color(0.20, 0.22, 0.28))
	_px(img, 144, 62, Color(0.42, 0.44, 0.52))
	# marker tray with the tools of chaos
	_rect(img, 30, 104, 116, 6, alu.lightened(0.10))
	_rect(img, 30, 104, 116, 1, alu.lightened(0.30))
	_rect(img, 40, 105, 12, 3, Color(0.55, 0.20, 0.20))
	_rect(img, 58, 105, 12, 3, Color(0.20, 0.21, 0.26))
	_rect(img, 76, 105, 12, 3, Color(0.20, 0.21, 0.26))
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
	_px(img, 66, 46, WHITE_HOT)
	# peephole: brass ring, dark glass, one caught highlight
	_disc(img, 48, 12, 3.4, Color(0.34, 0.27, 0.15))
	_disc(img, 48, 12, 2.2, Color(0.05, 0.05, 0.07))
	_px(img, 47, 11, Color(0.86, 0.74, 0.40))
	# a delivery note taped on at eye height. It says they tried.
	_rect(img, 24, 24, 22, 16, Color(0.90, 0.88, 0.82))
	_rect(img, 24, 24, 22, 1, Color(0.98, 0.96, 0.92))
	_rect(img, 24, 39, 22, 1, Color(0.66, 0.64, 0.58))
	for ny in range(28, 38, 3):
		_line(img, 27, ny, 42, ny, Color(0.44, 0.42, 0.40))
	_rect(img, 31, 21, 9, 4, Color(0.86, 0.88, 0.90, 0.45))
	# kick scuffs
	_line(img, 20, 124, 34, 126, d.darkened(0.30))
	_line(img, 52, 128, 62, 127, d.darkened(0.25))
	_line(img, 22, 120, 30, 122, d.darkened(0.20))
	# hallway light under the door (there is a world out there, allegedly)
	_rect(img, 11, 134, 74, 2, Color(0.03, 0.025, 0.03))
	for sy in 4:
		_rect(img, 13, 136 + sy, 70, 1, Color(1.0, 0.75, 0.42, 0.22 - 0.05 * float(sy)))
	_finish(img, RIM_WARM, 0.30)
	_save(img, "furn_door.png")

# ------------------------------------------- localhost fidelity pass --------
# Round-4 additions for the apartment: a hero window, real poster art, and
# textures for the props that were still ColorRects. Everything here is
# _hash-deterministic (no _rng), so adding these functions cannot shift a
# single pixel in any texture generated before them.

func _window_hero() -> void:
	# THE window: floor-to-ceiling night city behind the battlestation. Ties the
	# room to the menu's identity (starfield, neon, indigo dark) and is the one
	# place the world outside is allowed to look better than the world inside.
	# Bottom rows bake their own sill + feathered contact shadow, because in the
	# builder this hangs below the wall band and has to meet the boards cleanly.
	var w := 460
	var h := 300
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var frame := Color(0.105, 0.105, 0.155)
	var sky_top := Color(0.030, 0.038, 0.088)
	var sky_low := Color(0.130, 0.085, 0.190)
	var glass_top := 10
	var glass_bot := h - 24
	var glass_l := 10
	var glass_r := w - 10
	# sky: dithered indigo-to-violet with a city-glow haze at the horizon
	for y in range(glass_top, glass_bot):
		for x in range(glass_l, glass_r):
			var t := float(y - glass_top) / float(glass_bot - glass_top)
			var tt := t + (0.030 if (((x >> 1) + (y >> 1)) & 1) == 0 else 0.0)
			var c := sky_top.lerp(sky_low, clampf(tt, 0.0, 1.0))
			c = c.lerp(Color(0.205, 0.105, 0.235), clampf((t - 0.52) * 1.1, 0.0, 0.40))
			# stars — the menu's starfield, seen from indoors. None overbright.
			if t < 0.55 and _hash(x * 7, y * 13) % 701 == 0:
				c = Color(0.60, 0.64, 0.80)
			img.set_pixel(x, y, c)
	# The moon: a crisp disc, two tones, one crater tone (LAW 8). No halo ring,
	# no white-hot crescent.
	for yy in range(44, 78):
		for xx in range(324, 358):
			var d := Vector2(float(xx - 340), float(yy - 60)).length()
			if d < 15.0:
				img.set_pixel(xx, yy, Color(0.80, 0.82, 0.88) if (xx - 340) + (yy - 60) < 0 else Color(0.66, 0.68, 0.76))
	for mc: Vector2i in [Vector2i(344, 62), Vector2i(336, 56), Vector2i(341, 68)]:
		_px(img, mc.x, mc.y, Color(0.56, 0.58, 0.66))
	# far skyline: hazy indigo towers, one value step above the sky
	for x in range(glass_l, glass_r):
		var fh := 46 + _hash((x - glass_l) / 24, 3) % 42
		for y in range(glass_bot - fh, glass_bot):
			var c := Color(0.080, 0.088, 0.162)
			if y == glass_bot - fh:
				c = Color(0.105, 0.115, 0.200)
			img.set_pixel(x, y, c)
	# near skyline: near-black towers, parapets catching the sky, and window
	# grids lit in the palette's amber/cyan — the other people still awake
	for x in range(glass_l, glass_r):
		var band := (x - glass_l) / 34
		var nh := 26 + _hash(band * 13, 7) % 92
		var top := glass_bot - nh
		for y in range(top, glass_bot):
			var c := Color(0.028, 0.032, 0.058)
			if y == top:
				c = Color(0.052, 0.058, 0.096)
			elif (x - glass_l) % 5 != 0 and (y - top) % 7 >= 2 and (y - top) % 7 <= 4:
				# LAW 8's skyline rule: a few lit windows in WARM and ACCENT,
				# counted rather than sprayed. 1-in-19 instead of 1-in-7, and
				# nothing overbright.
				var wx := (x - glass_l) / 5
				var wy := (y - top) / 7
				if _hash(wx * 3 + band * 17, wy * 11) % 19 == 0:
					c = Color(0.72, 0.53, 0.25) if _hash(wx, wy * 5) % 3 != 0 else Color(0.24, 0.58, 0.62)
			img.set_pixel(x, y, c)
	# ONE piece of signage in the whole view, in the region ACCENT, at a value
	# that reads as "lit sign a mile away" rather than "light source in the
	# room". Gone: every aviation beacon (each one a red glow cross), a magenta
	# neon strip with white-hot pips, and a second cyan sign with two more.
	var sign_h := 26 + _hash(6 * 13, 7) % 92
	var sign_top := glass_bot - sign_h
	var sign_x := glass_l + 6 * 34 + 6
	_rect(img, sign_x, sign_top + 10, 22, 9, Color(0.04, 0.08, 0.10))
	_rect(img, sign_x + 2, sign_top + 12, 18, 2, CYAN.darkened(0.42))
	_rect(img, sign_x + 2, sign_top + 16, 12, 1, Color(0.08, 0.34, 0.32))
	# glass: two faint diagonal reflections + the room's warm spill low down
	for y in range(glass_top, glass_bot):
		for x in range(glass_l, glass_r):
			var dg := x - y
			if absi(dg - 60) < 4 or absi(dg - 96) < 2:
				_px(img, x, y, Color(0.80, 0.90, 1.0, 0.045))
	for y2 in range(glass_bot - 34, glass_bot):
		var wa := float(y2 - (glass_bot - 34)) / 34.0 * 0.085
		for x2 in range(glass_l, glass_r):
			_px(img, x2, y2, Color(1.0, 0.80, 0.52, wa))
	# (the twelve condensation runnels are gone — scatter, per LAW 4)
	# mullions: two verticals + a transom, lit on their left/top edges
	for my in range(glass_top, glass_bot):
		for mx: int in [glass_l + 146, glass_l + 292]:
			_px(img, mx - 1, my, frame.lightened(0.22))
			_px(img, mx, my, frame.lightened(0.05))
			_px(img, mx + 1, my, frame.darkened(0.28))
	for mx2 in range(glass_l, glass_r):
		_px(img, mx2, 96, frame.lightened(0.22))
		_px(img, mx2, 97, frame.lightened(0.05))
		_px(img, mx2, 98, frame.darkened(0.28))
	# fairy lights taped along the top rail. Still not the holidays.
	for cx in range(glass_l + 4, glass_r - 4):
		_px(img, cx, 15 + int(sin(float(cx) * 0.11) * 2.0), Color(0.20, 0.20, 0.24, 0.55))
	for lx in range(glass_l + 10, glass_r - 10, 26):
		var ly := 16 + int(sin(float(lx) * 0.11) * 2.0)
		_px(img, lx, ly, Color(0.86, 0.64, 0.34))
	# a sticky note stuck to the glass at eye height, overlapping the skyline so
	# it reads as ON the pane, not in the sky. It says TODO. Same TODO.
	_rect(img, 262, 210, 12, 12, Color(0.92, 0.78, 0.36))
	_rect(img, 262, 210, 12, 1, Color(0.98, 0.86, 0.46))
	_line(img, 264, 213, 271, 213, Color(0.35, 0.28, 0.12))
	_line(img, 264, 216, 269, 216, Color(0.35, 0.28, 0.12))
	_px(img, 273, 222, Color(0.05, 0.05, 0.08, 0.5))
	# frame: chunky bevel lit from the top-left, drawn over the glass edges
	_rect(img, 0, 0, w, 2, Color(0.045, 0.05, 0.08))
	_rect(img, 0, 0, 2, h - 10, Color(0.045, 0.05, 0.08))
	_rect(img, w - 2, 0, 2, h - 10, Color(0.045, 0.05, 0.08))
	_rect(img, 2, 2, w - 4, 8, frame.lightened(0.18))
	_rect(img, 2, 2, w - 4, 2, frame.lightened(0.34))
	_rect(img, 2, 9, w - 4, 1, frame.darkened(0.40))
	_rect(img, 2, 2, 8, h - 26, frame.lightened(0.09))
	_rect(img, 2, 2, 2, h - 26, frame.lightened(0.20))
	_rect(img, 9, 10, 1, h - 34, frame.darkened(0.35))
	_rect(img, w - 10, 2, 8, h - 26, frame.darkened(0.16))
	_rect(img, w - 10, 10, 1, h - 34, frame.darkened(0.40))
	_rect(img, w - 4, 2, 2, h - 26, frame.darkened(0.30))
	# sill: warm-lit ledge, shadowed front board, then a feathered contact
	# shadow with REAL alpha so the boards below read through it
	var sill := Color(0.335, 0.270, 0.210)
	_rect(img, 0, h - 24, w, 8, sill)
	_rect(img, 0, h - 24, w, 2, sill.lightened(0.30))
	_rect(img, 0, h - 16, w, 6, sill.darkened(0.35))
	_rect(img, 0, h - 10, w, 2, sill.darkened(0.55))
	# two dead tins on the sill, keeping watch over the city
	# Two dead tins on the sill, desaturated to the room and no longer carrying a
	# white-hot glint each (LAW 7: props are not light sources).
	for k: int in [0, 1]:
		var cx2 := 64 + k * 22
		var tin := Color(0.34, 0.40, 0.36) if k == 0 else Color(0.42, 0.35, 0.33)
		_rect(img, cx2, h - 36, 8, 12, tin.darkened(0.12))
		_rect(img, cx2, h - 36, 2, 12, tin.lightened(0.24))
		_ellipse(img, cx2 + 4, h - 36, 4.0, 1.5, tin.darkened(0.45))
	for y3 in range(h - 8, h):
		var fa := clampf((1.0 - float(y3 - (h - 8)) / 7.0) * 0.80, 0.0, 1.0)
		_rect(img, 0, y3, w, 1, Color(0.012, 0.014, 0.035, fa))
	_finish(img, RIM_COOL, 0.30)
	_save(img, "int_window_big.png")

func _poster_art() -> void:
	# Motivational poster, bright near-greyscale so the builder tints one
	# texture into every creed on the wall. The art is a sunburst over a
	# horizon: hype, radiating from nothing. The WorldLabel carries the words.
	var img := Image.create(44, 60, false, Image.FORMAT_RGBA8)
	var paper := Color(0.560, 0.575, 0.640)
	_rect(img, 0, 0, 44, 60, Color(0.085, 0.09, 0.12))
	_rect(img, 0, 0, 44, 1, Color(0.16, 0.17, 0.22))
	_rect(img, 0, 0, 1, 60, Color(0.13, 0.14, 0.18))
	_rect(img, 2, 2, 40, 56, paper.darkened(0.16))
	_vgrad(img, 3, 3, 38, 54, paper, paper.darkened(0.30))
	for r in 9:
		var ang := PI + PI * (float(r) + 0.5) / 9.0
		_line(img, 22, 40, 22 + int(cos(ang) * 26.0), 40 + int(sin(ang) * 26.0), paper.lightened(0.22))
	_disc(img, 22, 40, 4.0, paper.lightened(0.34))
	_px(img, 21, 39, Color(0.92, 0.94, 0.99))
	# slogan bars, unreadable on purpose; the label rides alongside
	_rect(img, 6, 44, 32, 2, paper.darkened(0.42))
	_rect(img, 10, 49, 24, 2, paper.darkened(0.38))
	_rect(img, 14, 53, 16, 1, paper.darkened(0.34))
	# tape at the top corners, one curling corner at the bottom
	for tc: Vector2i in [Vector2i(2, 2), Vector2i(36, 2)]:
		_rect(img, tc.x, tc.y, 6, 4, Color(0.80, 0.82, 0.86, 0.5))
	_line(img, 39, 55, 42, 52, paper.lightened(0.30))
	_px(img, 41, 54, paper.darkened(0.40))
	_finish(img, RIM_COOL, 0.25)
	_save(img, "int_poster.png")

func _pizza_props() -> void:
	# The strata. A leaning tower of closed boxes — deeper layers darker and
	# greasier, per the archaeology — plus one open single with the last slice.
	var img := Image.create(64, 58, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var card := Color(0.585, 0.435, 0.240)
	_shadow(img, 32, 53, 27, 4, 0.32)
	var offs: Array[Vector2i] = [Vector2i(6, 42), Vector2i(2, 31), Vector2i(9, 20), Vector2i(5, 9)]
	for i in offs.size():
		var o: Vector2i = offs[i]
		var tone := card.darkened(0.16 - 0.05 * float(i))
		_rect(img, o.x, o.y, 46, 12, tone)
		_rect(img, o.x, o.y, 46, 3, tone.lightened(0.22))
		_rect(img, o.x, o.y + 10, 46, 2, tone.darkened(0.34))
		_rect(img, o.x + 44, o.y, 2, 12, tone.darkened(0.24))
		# printed lid circle + steam slot
		for a in 20:
			var ang := TAU * float(a) / 20.0
			_px(img, o.x + 23 + int(cos(ang) * 6.0), o.y + 6 + int(sin(ang) * 3.0), tone.darkened(0.30))
		_rect(img, o.x + 8, o.y + 5, 6, 1, tone.darkened(0.38))
		# the grease is the stratigraphy
		var gx := o.x + 28 + (_hash(i, 3) % 10)
		_ellipse(img, gx, o.y + 7, 4.0 + float(_hash(i, 5) % 3), 2.4, Color(0.30, 0.20, 0.09, 0.55))
	_finish(img, RIM_WARM, 0.34)
	_save(img, "int_pizza_stack.png")
	# the open single: one slice left, which is a supply-chain miracle
	var sg := Image.create(50, 40, false, Image.FORMAT_RGBA8)
	sg.fill(Color(0, 0, 0, 0))
	_shadow(sg, 25, 36, 21, 3, 0.30)
	_rect(sg, 3, 2, 44, 12, card.darkened(0.06))
	_rect(sg, 3, 2, 44, 2, card.lightened(0.22))
	_rect(sg, 3, 12, 44, 2, card.darkened(0.30))
	_rect(sg, 3, 15, 44, 20, card.darkened(0.28))
	_rect(sg, 5, 17, 40, 16, Color(0.34, 0.25, 0.13))
	for g in 7:
		_px(sg, 8 + _hash(g, 7) % 34, 19 + _hash(g, 11) % 12, Color(0.22, 0.15, 0.07))
	_rect(sg, 12, 19, 12, 2, Color(0.62, 0.28, 0.16))
	for sy in 10:
		var sw := 12 - sy
		_rect(sg, 12, 21 + sy, maxi(sw, 1), 1, Color(0.83, 0.60, 0.22))
	_px(sg, 15, 23, Color(0.55, 0.16, 0.12))
	_px(sg, 18, 26, Color(0.55, 0.16, 0.12))
	_finish(sg, RIM_WARM, 0.32)
	_save(sg, "int_pizza_box.png")

func _power_strip() -> void:
	# Six sockets, more wall-warts than sockets, one confident LED.
	var img := Image.create(56, 22, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var body := Color(0.70, 0.71, 0.75)
	_shadow(img, 28, 18, 25, 3, 0.30)
	_rect(img, 2, 6, 52, 10, body.darkened(0.10))
	_rect(img, 2, 6, 52, 2, body.lightened(0.16))
	_rect(img, 2, 14, 52, 2, body.darkened(0.36))
	for s in 6:
		var sx := 6 + s * 8
		_rect(img, sx, 8, 5, 6, body.darkened(0.34))
		if s != 4:
			# a wall-wart squatting over its socket and half the next one
			var pc := Color(0.16 + 0.05 * float(s % 3), 0.16, 0.20)
			_rect(img, sx - 1, 4, 7, 8, pc)
			_rect(img, sx - 1, 4, 7, 2, pc.lightened(0.30))
			_line(img, sx + 2, 4, sx + 2 + (s % 3) * 3 - 3, 0, Color(0.10, 0.10, 0.13))
		else:
			# the one free socket, guarded like a parking spot
			_px(img, sx + 2, 10, Color(0.06, 0.06, 0.08))
	_px(img, 51, 8, RED.darkened(0.35))
	_finish(img, RIM_WARM, 0.32)
	_save(img, "int_power_strip.png")

func _sticky_strip() -> void:
	# Six estimates on a desk edge. The scribbles are load-bearing.
	var img := Image.create(96, 26, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# Six notes, ONE paper colour in three values. Six hues on a 96px prop was
	# more of the palette than the room the prop sits in is allowed.
	var cols: Array[Color] = [
		Color(0.72, 0.62, 0.34), Color(0.66, 0.57, 0.32), Color(0.76, 0.66, 0.38),
		Color(0.66, 0.57, 0.32), Color(0.72, 0.62, 0.34), Color(0.76, 0.66, 0.38),
	]
	for i in cols.size():
		var nx := 2 + i * 15
		var ny := 2 + (_hash(i, 3) % 4)
		var c: Color = cols[i]
		_rect(img, nx, ny, 12, 12, c)
		_rect(img, nx, ny, 12, 1, c.lightened(0.22))
		_rect(img, nx, ny + 11, 12, 1, c.darkened(0.28))
		_px(img, nx + 11, ny + 12, Color(0.05, 0.05, 0.08, 0.4))
		_line(img, nx + 2, ny + 3, nx + 8, ny + 3, c.darkened(0.55))
		_line(img, nx + 2, ny + 6, nx + 6 + _hash(i, 7) % 3, ny + 6, c.darkened(0.55))
		if i % 2 == 0:
			_line(img, nx + 2, ny + 9, nx + 9, ny + 9, c.darkened(0.45))
		if i == 3:
			# one note peeling at the corner; it will fall during a demo
			_clear(img, nx + 8, ny + 8, 4, 4)
			for f in 4:
				_px(img, nx + 8 + f, ny + 11 - f, c.lightened(0.30))
				_px(img, nx + 8 + f, ny + 12 - f, c.darkened(0.20))
	# the one that already fell, at an angle nobody will fix
	_rect(img, 82, 14, 11, 10, Color(0.66, 0.57, 0.32))
	_line(img, 84, 17, 90, 17, Color(0.35, 0.28, 0.12))
	_line(img, 84, 20, 88, 20, Color(0.35, 0.28, 0.12))
	_finish(img, RIM_WARM, 0.0)
	_save(img, "int_sticky_strip.png")

func _can() -> void:
	# One empty energy tin, near-white so the builder tints each flavour of
	# regret. The tab is up because every one was opened one-handed, mid-build.
	var img := Image.create(10, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var tin := Color(0.78, 0.79, 0.82)
	for y in range(3, 15):
		var t := float(y - 3) / 11.0
		_rect(img, 1, y, 8, 1, tin.lerp(tin.darkened(0.30), t))
	_rect(img, 1, 3, 8, 1, tin.lightened(0.16))
	_rect(img, 2, 4, 1, 10, Color(0.97, 0.98, 1.0, 0.85))
	_rect(img, 7, 4, 1, 10, tin.darkened(0.42))
	_rect(img, 2, 8, 6, 3, tin.darkened(0.16))
	_rect(img, 3, 9, 4, 1, tin.darkened(0.38))
	_rect(img, 1, 14, 8, 1, tin.darkened(0.52))
	_ellipse(img, 5, 3, 4.0, 1.6, tin.darkened(0.48))
	_px(img, 4, 2, tin.lightened(0.30))
	_px(img, 5, 2, tin.darkened(0.20))
	_finish(img, RIM_WARM, 0.0)
	_save(img, "int_can.png")

func _couch_tex() -> void:
	# The couch: bought for a social life that never shipped. Cushions read in
	# three values, the blanket in two, the crumbs in confession.
	var w := 172
	var h := 84
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var base := Color(0.285, 0.272, 0.300)
	_shadow(img, 86, 78, 76, 5, 0.32)
	# backrest with cushion seams
	_bevel(img, 10, 6, 152, 30, base.darkened(0.10))
	_rect(img, 10, 6, 152, 3, base.lightened(0.20))
	for bx in range(60, 162, 50):
		_rect(img, bx, 9, 2, 24, base.darkened(0.30))
		_rect(img, bx + 2, 9, 1, 24, base.lightened(0.08))
	# arms, overhanging the seat
	for k: int in [0, 1]:
		var ax := 2 if k == 0 else 148
		_bevel(img, ax, 14, 22, 52, base.lightened(0.04) if k == 0 else base.darkened(0.06))
		_rect(img, ax, 14, 22, 4, base.lightened(0.26))
		_rect(img, ax, 62, 22, 4, base.darkened(0.36))
	# seat cushions: lit top, one compressed dent per cushion, seam AO
	for ci in 3:
		var cx := 26 + ci * 42
		var cush := base.lightened(0.14 - 0.03 * float(ci % 2))
		_rect(img, cx, 34, 40, 26, cush)
		_rect(img, cx, 34, 40, 4, cush.lightened(0.20))
		_rect(img, cx, 56, 40, 4, cush.darkened(0.26))
		_rect(img, cx + 38, 34, 2, 26, cush.darkened(0.30))
		_ellipse(img, cx + 20, 46, 14.0, 7.0, cush.darkened(0.10))
		_line(img, cx + 8, 46, cx + 32, 46, cush.darkened(0.18))
	# skirt + feet
	_rect(img, 10, 64, 152, 10, base.darkened(0.30))
	_rect(img, 10, 64, 152, 1, base.darkened(0.06))
	for fx: int in [16, 82, 148]:
		_rect(img, fx, 74, 8, 5, Color(0.10, 0.08, 0.09))
		_rect(img, fx, 74, 8, 1, Color(0.18, 0.15, 0.16))
	# the blanket, folded over the right arm, one corner reaching the seat
	var bl := Color(0.38, 0.29, 0.30)
	_rect(img, 140, 10, 26, 34, bl)
	_rect(img, 140, 10, 26, 3, bl.lightened(0.22))
	_rect(img, 140, 41, 26, 3, bl.darkened(0.30))
	for by in range(14, 40, 5):
		_rect(img, 142, by, 22, 1, bl.darkened(0.16))
	_rect(img, 134, 30, 8, 18, bl.darkened(0.10))
	_rect(img, 134, 46, 8, 2, bl.darkened(0.34))
	# remote, unreachable from the dent by exactly one cushion
	_rect(img, 34, 40, 6, 12, Color(0.09, 0.10, 0.13))
	_rect(img, 34, 40, 6, 1, Color(0.20, 0.22, 0.27))
	_px(img, 36, 42, Color(0.42, 0.26, 0.24))
	_px(img, 36, 45, Color(0.24, 0.30, 0.26))
	_finish(img, RIM_WARM, 0.40)
	_save(img, "int_couch.png")

# --------------------------------------------- set-piece dressing props -----
# New vocabulary for the hand-composed focal points. Same rules as the shared
# structs: near-greyscale bodies so a region can multiply its own accent over
# them, emissive details left near-white so the tint owns the hue and the HDR
# pass owns the bloom, light from the top-left, 1px outline via _finish().
# Every one of these is optional downstream — consumers exists()-guard them.

func _dress_awning() -> void:
	# Market awning: sagging striped canopy, scalloped valance, guy ropes and a
	# string of bulbs. Stripes are drawn as VALUE, not hue, so a magenta bazaar
	# and a gold vault get their own stripes for free.
	var img := Image.create(160, 72, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var g := Color(0.74, 0.73, 0.71)
	# poles first: the canopy overlaps their tops
	for k: int in [0, 1]:
		var px: int = 12 if k == 0 else 142
		_cyl(img, px, 18, 7, 50, g.darkened(0.46))
		_rect(img, px - 4, 66, 15, 4, g.darkened(0.56))
		_rect(img, px - 4, 66, 15, 1, g.darkened(0.30))
		_rect(img, px - 1, 24, 9, 2, g.darkened(0.34))       # collar
		_rect(img, px - 1, 24, 9, 1, g.lightened(0.10))
	# guy ropes to the ground, taut on the left, less so on the right
	_line(img, 14, 22, 2, 64, g.darkened(0.50))
	_line(img, 152, 22, 158, 64, g.darkened(0.50))
	# canopy: sags in the middle, banded into stripes across its width
	for x in range(4, 156):
		var t := float(x - 4) / 151.0
		var sag: int = int(sin(t * PI) * 5.0)
		var top: int = 4 + sag
		var bot: int = 34 + sag
		var lit: bool = ((x / 14) % 2) == 0
		var base: Color = g if lit else g.darkened(0.34)
		for y in range(top, bot):
			var v := float(y - top) / float(bot - top)
			_px(img, x, y, base.lightened(0.18 * (1.0 - v)).darkened(0.26 * v))
		_px(img, x, top, base.lightened(0.38))               # lit leading edge
		_px(img, x, bot - 1, base.darkened(0.46))
		# scalloped valance hanging off the front edge
		var lobe: int = (x - 4) % 20
		var dd := 100.0 - float((lobe - 10) * (lobe - 10))
		var depth: int = int(sqrt(maxf(dd, 0.0)) * 0.85)
		for y2 in range(bot, bot + depth):
			_px(img, x, y2, base.darkened(0.20 + 0.006 * float(y2 - bot)))
		_px(img, x, bot, base.darkened(0.02))
		if depth > 0:
			_px(img, x, bot + depth - 1, base.darkened(0.52))
	# seam stitching where the panels join
	for sx in range(18, 156, 14):
		for sy in range(4, 34):
			var t2 := float(sx - 4) / 151.0
			_px(img, sx, sy + int(sin(t2 * PI) * 5.0), g.darkened(0.44))
	# bulb string slung under the canopy, cores hot enough to bloom
	for x2 in range(18, 144):
		var u := float(x2 - 18) / 126.0
		var by: int = 44 + int(sin(u * PI) * 7.0)
		_px(img, x2, by, Color(0.24, 0.24, 0.27))
	for b in 4:
		var bx: int = 30 + b * 30
		var u2 := float(bx - 18) / 126.0
		var by2: int = 45 + int(sin(u2 * PI) * 7.0)
		_rect(img, bx, by2, 3, 4, Color(0.86, 0.80, 0.62))
		_glow(img, bx + 1, by2 + 2, Color(1.0, 0.86, 0.55))
	_finish(img, RIM_COOL, 0.34)
	_save(img, "dress_awning.png")

func _dress_stall() -> void:
	# Market stall: plank counter, crates of stock underneath, a hand-written
	# price board and one backlit display that disagrees with it.
	var img := Image.create(128, 88, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var wood := Color(0.66, 0.60, 0.52)
	var g := Color(0.62, 0.62, 0.66)
	_shadow(img, 64, 82, 58, 6, 0.32)
	# under-counter: crates and a drape, in shadow
	_rect(img, 12, 44, 104, 34, wood.darkened(0.52))
	for cx in range(16, 108, 22):
		_rect(img, cx, 50, 18, 24, wood.darkened(0.36))
		_rect(img, cx, 50, 18, 1, wood.darkened(0.16))
		_rect(img, cx, 61, 18, 1, wood.darkened(0.50))
		_rect(img, cx + 8, 50, 2, 24, wood.darkened(0.48))
	# counter slab: lit top face, plank seams, shadowed front board
	_rect(img, 4, 34, 120, 10, wood)
	_rect(img, 4, 34, 120, 2, wood.lightened(0.24))
	_rect(img, 4, 42, 120, 2, wood.darkened(0.34))
	_rect(img, 4, 44, 120, 2, wood.darkened(0.52))
	for px in range(16, 120, 17):
		_rect(img, px, 36, 1, 7, wood.darkened(0.22))
		_rect(img, px + 1, 36, 1, 7, wood.lightened(0.08))
	# wares laid out on the counter: bottles, boxes, a bowl of small parts
	for i in 5:
		var wx: int = 12 + i * 13
		var wh: int = 10 + _hash(i, 3) % 8
		_rect(img, wx, 34 - wh, 8, wh, g.darkened(0.10 + 0.04 * float(i % 3)))
		_rect(img, wx, 34 - wh, 8, 2, g.lightened(0.20))
		_rect(img, wx + 6, 34 - wh, 2, wh, g.darkened(0.34))
		if i % 2 == 0:
			_rect(img, wx + 2, 34 - wh + 4, 4, 2, g.darkened(0.40))
	_ellipse(img, 86, 30, 11.0, 4.0, g.darkened(0.22))
	_ellipse(img, 86, 29, 9.0, 3.0, g.darkened(0.04))
	for p in 9:
		_px(img, 79 + _hash(p, 7) % 15, 27 + _hash(p, 11) % 3, g.lightened(0.24))
	# price board leaning against the counter, hand-lettered, aspirational
	_rect(img, 96, 14, 28, 22, Color(0.20, 0.20, 0.23))
	_rect(img, 96, 14, 28, 1, Color(0.34, 0.34, 0.38))
	for ry in range(18, 33, 4):
		_rect(img, 100, ry, 14, 1, Color(0.78, 0.78, 0.74))
		_rect(img, 116, ry, 5, 1, Color(0.86, 0.80, 0.56))
	# backlit price display, near-white so the region tint claims it
	_rect(img, 10, 16, 26, 12, Color(0.06, 0.07, 0.09))
	_rect(img, 10, 16, 26, 1, Color(0.02, 0.03, 0.04))
	_rect(img, 13, 20, 8, 4, Color(0.88, 0.92, 0.96))
	_rect(img, 23, 20, 4, 4, Color(0.88, 0.92, 0.96))
	_rect(img, 29, 24, 4, 1, Color(0.70, 0.76, 0.82))
	_glow(img, 34, 18, Color(0.92, 0.95, 1.0))
	_finish(img, RIM_COOL, 0.36)
	_save(img, "dress_stall.png")

func _dress_monolith() -> void:
	# Broken monolith: snapped two thirds up, jagged fracture, carved glyph band
	# still lit. Whatever it documented, the link is dead.
	var img := Image.create(64, 140, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var st := Color(0.62, 0.61, 0.63)
	_shadow(img, 32, 132, 24, 5, 0.34)
	# shaft, tapering and leaning a couple of pixels off true. Wide enough to
	# read as masonry: a narrow one just looks like a post.
	for y in range(28, 132):
		var t := float(y - 28) / 103.0
		var half: int = 15 + int(round(7.0 * t))
		var lean: int = int(round(3.0 * (1.0 - t)))
		var cx: int = 32 + lean
		var body := st.lightened(0.10).lerp(st.darkened(0.26), t)
		for x in range(cx - half, cx + half):
			var n := float(_hash(x * 3, y) % 7 - 3) / 130.0
			var c := Color(body.r + n, body.g + n, body.b + n, 1.0)
			# coursed banding every 13px: shadow then caught light
			if (y - 28) % 13 == 0:
				c = c.darkened(0.26)
			elif (y - 28) % 13 == 1:
				c = c.lightened(0.10)
			img.set_pixel(x, y, c)
		_rect(img, cx - half, y, 3, 1, body.lightened(0.18))
		_rect(img, cx + half - 3, y, 3, 1, body.darkened(0.32))
	# The fracture: a shallow ragged bite across the top with a bright fresh
	# edge. Bounded to the shaft's own width at y=28 (cx 35, half 15) — running
	# it wider paints lit pixels into empty space, which reads as grass.
	for x in range(20, 50):
		# The profile has to be CONTINUOUS: hash noise on its own makes adjacent
		# columns differ by five or six pixels, and the leftover 1px columns read
		# as hairs growing out of the stone.
		var d: int = 4 + int(round(2.6 * sin(float(x) * 0.52) + 1.6 * sin(float(x) * 0.21 + 1.0))) + _hash(x, 5) % 2
		d = clampi(d, 0, 9)
		_clear(img, x, 28, 1, d)
		_px(img, x, 28 + d, st.lightened(0.30))
		_px(img, x, 29 + d, st.lightened(0.10))
	# carved glyph band, glyphs near-white so the region owns their colour
	_rect(img, 24, 62, 22, 16, st.darkened(0.30))
	_rect(img, 25, 63, 20, 14, st.darkened(0.10))
	_rect(img, 25, 63, 20, 1, st.darkened(0.44))
	_rect(img, 30, 70, 5, 1, Color(0.56, 0.56, 0.58))
	_rect(img, 30, 73, 3, 1, Color(0.50, 0.50, 0.52))
	_glow(img, 42, 70, Color(0.90, 0.92, 0.96))
	# cracks running out of the fracture
	_line(img, 26, 34, 22, 58, st.darkened(0.34))
	_line(img, 27, 34, 23, 58, st.lightened(0.07))
	_line(img, 40, 40, 44, 74, st.darkened(0.30))
	_line(img, 33, 88, 29, 118, st.darkened(0.26))
	# spalled edges + rubble at the foot
	for sp in 8:
		var sy: int = 34 + _hash(sp, 13) % 90
		var t3 := float(sy - 28) / 103.0
		var half2: int = 15 + int(round(7.0 * t3))
		var lean2: int = int(round(3.0 * (1.0 - t3)))
		var outer: bool = _hash(sp, 17) % 2 == 0
		var sx: int = (32 + lean2 + half2 - 2) if outer else (32 + lean2 - half2)
		_clear(img, sx, sy, 2, 2 + _hash(sp, 19) % 3)
	for r in 8:
		var rx := 12 + _hash(r, 23) % 40
		var ry := 126 + _hash(r, 29) % 8
		_rect(img, rx, ry, 2 + _hash(r, 31) % 3, 2, st.darkened(0.14 + 0.02 * float(r % 4)))
		_px(img, rx, ry, st.lightened(0.12))
	_finish(img, RIM_COOL, 0.40)
	_save(img, "dress_monolith.png")

func _dress_cooling_tower() -> void:
	# Hyperboloid cooling tower. The waist is the whole silhouette argument: a
	# straight cylinder reads as a bin, this reads as infrastructure.
	var img := Image.create(96, 150, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var g := Color(0.60, 0.60, 0.63)
	_shadow(img, 48, 142, 38, 6, 0.34)
	for y in range(14, 140):
		var t := float(y - 14) / 125.0
		var r: float = 17.0 + 25.0 * pow(absf(t - 0.30), 1.35)
		var ri: int = int(r)
		var shade := g.lightened(0.06).lerp(g.darkened(0.20), t)
		for x in range(48 - ri, 48 + ri):
			# cylinder shading across the width, light from the top-left
			var u := float(x - (48 - ri)) / maxf(1.0, float(ri * 2 - 1))
			var c: Color = shade.lerp(shade.lightened(0.28), 1.0 - u / 0.34) if u < 0.34 else shade.lerp(shade.darkened(0.34), (u - 0.34) / 0.66)
			var n := float(_hash(x, y * 3) % 6) / 340.0
			c = Color(c.r + n, c.g + n, c.b + n, 1.0)
			# concrete ribs every 11px
			if (y - 14) % 11 == 0:
				c = c.darkened(0.24)
			elif (y - 14) % 11 == 1:
				c = c.lightened(0.10)
			img.set_pixel(x, y, c)
		# streaked staining down the shell, worse near the base
		if _hash(y, 7) % 5 == 0:
			var sx: int = 48 - ri + 4 + _hash(y, 11) % maxi(ri * 2 - 8, 1)
			_px(img, sx, y, Color(0.10, 0.10, 0.12, 0.10 + 0.08 * t))
	# top rim: a lit lip and the dark mouth behind it
	_ellipse(img, 48, 14, 23.0, 6.0, g.lightened(0.16))
	_ellipse(img, 48, 15, 20.0, 4.6, Color(0.08, 0.09, 0.11))
	_ellipse(img, 48, 14, 20.0, 4.6, Color(0.14, 0.15, 0.18))
	# steam lifting out of it, thinning as it goes
	for p in 26:
		var px: int = 34 + _hash(p, 41) % 28
		var py: int = 2 + _hash(p, 43) % 11
		var rr := 2.0 + float(_hash(p, 47) % 4)
		_ellipse(img, px, py, rr, rr * 0.7, Color(0.86, 0.88, 0.94, 0.09))
	# service ladder up the left flank, with its safety hoops
	for ly in range(30, 132, 5):
		var t4 := float(ly - 14) / 125.0
		var r4: int = int(17.0 + 25.0 * pow(absf(t4 - 0.30), 1.35))
		_rect(img, 48 - r4 + 4, ly, 6, 1, g.darkened(0.38))
	for ly2 in range(30, 132):
		var t5 := float(ly2 - 14) / 125.0
		var r5: int = int(17.0 + 25.0 * pow(absf(t5 - 0.30), 1.35))
		_px(img, 48 - r5 + 4, ly2, g.darkened(0.30))
		_px(img, 48 - r5 + 9, ly2, g.darkened(0.42))
	# base skirt: angled struts (kept inside the shell's footprint) and a door
	for k in 5:
		var bx: int = 24 + k * 12
		_line(img, bx, 138, bx + 5, 126, g.darkened(0.40))
		_line(img, bx + 1, 138, bx + 6, 126, g.darkened(0.18))
	_rect(img, 6, 136, 84, 6, g.darkened(0.34))
	_rect(img, 6, 136, 84, 1, g.lightened(0.10))
	_rect(img, 40, 124, 14, 16, g.darkened(0.46))
	_rect(img, 41, 125, 12, 14, g.darkened(0.28))
	_glow(img, 52, 127, Color(0.95, 0.80, 0.35))
	_finish(img, RIM_COOL, 0.36)
	_save(img, "dress_cooling_tower.png")

func _dress_ore_cart() -> void:
	# Ore cart on a stub of rail, heaped with something that is still warm. The
	# ore cores are near-white: gpu_mines will make them ember, the vault gold.
	var img := Image.create(96, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var st := Color(0.56, 0.56, 0.60)
	_shadow(img, 48, 61, 42, 3, 0.34)
	# sleepers and rail
	for sx in range(4, 92, 26):
		_rect(img, sx, 56, 18, 5, Color(0.34, 0.29, 0.24))
		_rect(img, sx, 56, 18, 1, Color(0.44, 0.38, 0.31))
	_rect(img, 2, 53, 92, 3, st.darkened(0.30))
	_rect(img, 2, 53, 92, 1, st.lightened(0.18))
	# tub: wider at the rim than at the floor, riveted, banded
	for y in range(14, 45):
		var t := float(y - 14) / 30.0
		var half: int = 38 - int(round(9.0 * t))
		var body := st.lightened(0.08).lerp(st.darkened(0.26), t)
		for x in range(48 - half, 48 + half):
			var n := float(_hash(x, y * 5) % 6) / 320.0
			img.set_pixel(x, y, Color(body.r + n, body.g + n, body.b + n, 1.0))
		_rect(img, 48 - half, y, 3, 1, body.lightened(0.18))
		_rect(img, 48 + half - 3, y, 3, 1, body.darkened(0.34))
		# reinforcing bands, spaced INSIDE the taper so none of them float off
		# the silhouette at the narrow end
		if y > 17:
			for bi in 4:
				var bx: int = 48 - half + 4 + int(float(bi) * float(half * 2 - 9) / 3.0)
				_px(img, bx, y, body.darkened(0.32))
				_px(img, bx + 1, y, body.darkened(0.32))
				_px(img, bx + 2, y, body.lightened(0.12))
				if y == 22 or y == 40:
					_px(img, bx, y, st.lightened(0.32))
					_px(img, bx + 1, y, st.darkened(0.42))
	_rect(img, 10, 14, 76, 3, st.lightened(0.24))         # rolled rim, catching light
	_rect(img, 10, 17, 76, 1, st.darkened(0.40))          # AO under the rim
	# axle beam and wheels, IN FRONT of the tub — a mine cart whose wheels are
	# hidden behind the tub reads as a skip somebody left on the tracks
	_rect(img, 20, 45, 56, 3, st.darkened(0.46))
	for wx: int in [26, 70]:
		_disc(img, wx, 50, 7.0, st.darkened(0.50))
		_disc(img, wx, 50, 5.2, st.darkened(0.22))
		_disc(img, wx, 50, 2.0, st.darkened(0.54))
		for sa in 6:
			var aa := TAU * float(sa) / 6.0 + 0.3
			_px(img, wx + int(cos(aa) * 3.6), 50 + int(sin(aa) * 3.6), st.darkened(0.40))
		_px(img, wx - 3, 47, st.lightened(0.26))
	# coupling: a drawbar and a hook loop off the right end
	_rect(img, 84, 36, 9, 3, st.darkened(0.26))
	_rect(img, 84, 36, 9, 1, st.lightened(0.16))
	for a2 in 26:
		var ha := PI * 0.35 + TAU * 0.72 * float(a2) / 26.0
		_px(img, 92 + int(cos(ha) * 3.0), 34 + int(sin(ha) * 3.0), st.darkened(0.20))
	_px(img, 90, 32, st.lightened(0.28))
	# the heap: lumps proud of the rim, each with a hot core
	for o in 11:
		var ox: int = 16 + _hash(o, 53) % 64
		var oy: int = 10 + _hash(o, 59) % 8
		var orr := 3.0 + float(_hash(o, 61) % 4)
		_ellipse(img, ox, oy, orr, orr * 0.8, Color(0.34, 0.33, 0.34))
		_ellipse(img, ox - 1, oy - 1, orr * 0.55, orr * 0.45, Color(0.54, 0.53, 0.54))
		if o == 4:
			_glow(img, ox, oy, Color(0.94, 0.90, 0.86))   # one lump still warm
	_finish(img, RIM_COOL, 0.38)
	_save(img, "dress_ore_cart.png")

func _dress_whiteboard() -> void:
	# Freestanding whiteboard on castors. The chart goes up and to the right,
	# which is the wrong direction for a burndown, and nobody has said anything.
	var img := Image.create(120, 120, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var alu := Color(0.56, 0.58, 0.63)
	_shadow(img, 60, 114, 40, 5, 0.32)
	# A-frame legs and crossbar, drawn first
	for k: float in [-1.0, 1.0]:
		var bx: int = 60 + int(k * 40.0)
		var tx: int = 60 + int(k * 30.0)
		_line(img, bx, 110, tx, 82, alu.darkened(0.30))
		_line(img, bx + 1, 110, tx + 1, 82, alu.lightened(0.16))
		_line(img, bx + 2, 110, tx + 2, 82, alu.darkened(0.44))
		_disc(img, bx, 112, 3.4, alu.darkened(0.46))
		_disc(img, bx, 111, 2.0, alu.darkened(0.16))
		_px(img, bx - 1, 110, alu.lightened(0.26))
	_rect(img, 28, 96, 64, 3, alu.darkened(0.26))
	_rect(img, 28, 96, 64, 1, alu.lightened(0.16))
	# frame + board face
	_bevel(img, 12, 8, 96, 78, alu)
	_vgrad(img, 17, 13, 86, 68, Color(0.905, 0.910, 0.885), Color(0.840, 0.845, 0.820))
	# eraser ghosts of the last three plans
	for gp: Vector3i in [Vector3i(40, 60, 12), Vector3i(78, 34, 9)]:
		for yy in range(gp.y - 5, gp.y + 6):
			for xx in range(gp.x - gp.z, gp.x + gp.z + 1):
				if _hash(xx, yy) % 4 != 0:
					_px(img, xx, yy, Color(0.55, 0.56, 0.58, 0.06))
	# axes and the line that should be falling
	_rect(img, 24, 20, 1, 54, Color(0.16, 0.16, 0.20))
	_rect(img, 24, 73, 74, 1, Color(0.16, 0.16, 0.20))
	var py := 60
	for x in range(26, 98, 4):
		var ny: int = maxi(py - 2 - _hash(x, 3) % 4, 20)
		_line(img, x, py, x + 4, ny, Color(0.55, 0.20, 0.20))
		py = ny
	# the ideal line, dashed, going the other way, ignored
	for dx in range(26, 98, 6):
		_rect(img, dx, 26 + (dx - 26) / 2, 3, 1, Color(0.20, 0.21, 0.26))
	# marker tray with three markers, two of them dry
	_rect(img, 24, 86, 72, 5, alu.lightened(0.10))
	_rect(img, 24, 86, 72, 1, alu.lightened(0.30))
	_rect(img, 32, 87, 12, 3, Color(0.55, 0.20, 0.20))
	_rect(img, 48, 87, 12, 3, Color(0.20, 0.21, 0.26))
	_rect(img, 64, 87, 12, 3, Color(0.20, 0.21, 0.26))
	_rect(img, 80, 86, 12, 4, Color(0.55, 0.56, 0.60))
	_finish(img, Color(0.95, 0.96, 1.0), 0.24)
	_save(img, "dress_whiteboard.png")

func _dress_filing_cabinet() -> void:
	# Four drawers of paper that outlived the system it documented. One drawer is
	# open because it has never once closed on the first attempt.
	var img := Image.create(64, 110, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var st := Color(0.54, 0.55, 0.60)
	_shadow(img, 32, 104, 26, 4, 0.34)
	_vgrad(img, 4, 14, 56, 90, st.lightened(0.10), st.darkened(0.20))
	_rect(img, 4, 14, 56, 2, st.lightened(0.28))
	_rect(img, 4, 14, 4, 90, st.lightened(0.16))
	_rect(img, 56, 14, 4, 90, st.darkened(0.30))
	_rect(img, 4, 100, 56, 4, st.darkened(0.44))          # plinth
	for di in 4:
		var dy: int = 18 + di * 21
		var out: int = 5 if di == 2 else 0                # the one that sticks
		_rect(img, 7 - out, dy, 50, 18, st.lightened(0.04))
		_rect(img, 7 - out, dy, 50, 1, st.lightened(0.26))
		_rect(img, 7 - out, dy + 17, 50, 1, st.darkened(0.40))
		_rect(img, 7 - out, dy, 1, 18, st.lightened(0.14))
		# handle + label holder
		_rect(img, 22 - out, dy + 10, 18, 3, st.darkened(0.26))
		_rect(img, 22 - out, dy + 10, 18, 1, st.lightened(0.24))
		_rect(img, 22 - out, dy + 4, 18, 4, st.darkened(0.36))
		_rect(img, 23 - out, dy + 5, 16, 2, Color(0.84, 0.83, 0.78))
		_rect(img, 25 - out, dy + 6, 9, 1, Color(0.32, 0.31, 0.30))
		if di == 2:
			# folder tabs standing proud of the open drawer
			for f in 5:
				var fx: int = 6 + f * 9
				_rect(img, fx, dy - 6, 8, 8, Color(0.72, 0.66, 0.50))
				_rect(img, fx, dy - 6, 8, 1, Color(0.82, 0.76, 0.60))
				_rect(img, fx + 1, dy - 4, 5, 1, Color(0.44, 0.40, 0.30))
			_rect(img, 2, dy + 17, 55, 2, Color(0.05, 0.06, 0.08, 0.5))
	# a stack of ring binders on top, and the dent from something dropped
	_rect(img, 12, 4, 34, 10, Color(0.40, 0.30, 0.30))
	_rect(img, 12, 4, 34, 2, Color(0.52, 0.40, 0.38))
	_rect(img, 12, 8, 34, 1, Color(0.28, 0.21, 0.21))
	_rect(img, 14, 0, 30, 5, Color(0.30, 0.36, 0.46))
	_rect(img, 14, 0, 30, 1, Color(0.42, 0.48, 0.58))
	for dy2 in 6:
		var dw: int = 6 - absi(dy2 - 2)
		_rect(img, 50 - dw / 2, 74 + dy2, dw, 1, st.darkened(0.22 + 0.03 * float(dy2)))
	_finish(img, RIM_COOL, 0.36)
	_save(img, "dress_filing_cabinet.png")

func _dress_cubicle() -> void:
	# Two fabric panels meeting at a post. The pinned printout is a process
	# diagram; the coat on the hook has been there since the reorg.
	var img := Image.create(150, 96, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var fab := Color(0.50, 0.51, 0.55)
	var alu := Color(0.62, 0.63, 0.68)
	_shadow(img, 75, 90, 66, 5, 0.30)
	# right panel first: it recedes, so it is shorter and a stop darker
	for y in range(14, 84):
		for x in range(76, 148):
			var t := float(y - 14) / 69.0
			var c := fab.darkened(0.10).lerp(fab.darkened(0.32), t)
			if _hash(x * 2, y * 3) % 3 == 0:
				c = c.lightened(0.05)
			elif _hash(x * 5, y) % 5 == 0:
				c = c.darkened(0.06)
			img.set_pixel(x, y, c)
	_rect(img, 76, 10, 72, 5, alu.darkened(0.22))
	_rect(img, 76, 10, 72, 2, alu.darkened(0.04))
	_rect(img, 76, 46, 72, 2, alu.darkened(0.30))         # mid rail
	_rect(img, 76, 46, 72, 1, alu.darkened(0.08))
	_rect(img, 76, 84, 72, 4, alu.darkened(0.44))
	# left panel: front-facing, lighter, woven
	for y in range(8, 88):
		for x in range(4, 76):
			var t2 := float(y - 8) / 79.0
			var c2 := fab.lightened(0.08).lerp(fab.darkened(0.18), t2)
			if _hash(x * 2 + 1, y * 3) % 3 == 0:
				c2 = c2.lightened(0.05)
			elif _hash(x * 5 + 1, y) % 5 == 0:
				c2 = c2.darkened(0.06)
			img.set_pixel(x, y, c2)
	_rect(img, 4, 4, 72, 6, alu)
	_rect(img, 4, 4, 72, 2, alu.lightened(0.26))
	_rect(img, 4, 9, 72, 1, alu.darkened(0.40))
	_rect(img, 4, 88, 72, 4, alu.darkened(0.42))
	_rect(img, 4, 88, 72, 1, alu.darkened(0.20))
	# the corner post, catching light on its left face
	_rect(img, 72, 2, 8, 90, alu.darkened(0.14))
	_rect(img, 72, 2, 3, 90, alu.lightened(0.18))
	_rect(img, 78, 2, 2, 90, alu.darkened(0.40))
	_rect(img, 72, 2, 8, 2, alu.lightened(0.30))
	# pinned printout: a process with more boxes than steps
	_rect(img, 14, 20, 40, 30, Color(0.90, 0.90, 0.87))
	_rect(img, 14, 20, 40, 1, Color(0.97, 0.97, 0.94))
	_rect(img, 14, 49, 40, 1, Color(0.66, 0.66, 0.62))
	for bi in 4:
		var bx: int = 18 + (bi % 2) * 20
		var by: int = 25 + (bi / 2) * 12
		_rect(img, bx, by, 14, 8, Color(0.96, 0.96, 0.94))
		_rect(img, bx, by, 14, 1, Color(0.24, 0.30, 0.52))
		_rect(img, bx, by + 7, 14, 1, Color(0.24, 0.30, 0.52))
		_rect(img, bx + 3, by + 3, 8, 1, Color(0.46, 0.50, 0.62))
	_disc(img, 34, 21, 1.8, Color(0.62, 0.18, 0.20))
	_px(img, 33, 20, Color(0.88, 0.42, 0.40))
	# coat hook and a lanyard that expired with the badge on it
	_rect(img, 60, 22, 3, 5, alu.darkened(0.28))
	_rect(img, 60, 22, 3, 1, alu.lightened(0.20))
	for ly in range(26, 46):
		_px(img, 61 + ((ly >> 2) & 1), ly, Color(0.28, 0.30, 0.36))
	_rect(img, 58, 46, 8, 11, Color(0.80, 0.80, 0.84))
	_rect(img, 58, 46, 8, 1, Color(0.90, 0.90, 0.94))
	_rect(img, 60, 50, 4, 1, Color(0.40, 0.42, 0.48))
	_rect(img, 60, 53, 3, 1, Color(0.40, 0.42, 0.48))
	_finish(img, RIM_COOL, 0.30)
	_save(img, "dress_cubicle.png")

func _dress_laser_emitter() -> void:
	# Security laser emitter. It is armed. It has always been armed. The ticket
	# to disarm it is assigned to somebody who left.
	var img := Image.create(48, 96, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var st := Color(0.58, 0.58, 0.62)
	_shadow(img, 24, 90, 17, 4, 0.34)
	# floor plate with bolts
	_ellipse(img, 24, 86, 15.0, 5.0, st.darkened(0.34))
	_ellipse(img, 24, 85, 12.0, 3.6, st.darkened(0.10))
	for k: float in [-1.0, 1.0]:
		_bolt(img, 24 + int(k * 9.0) - 1, 84, st)
	# tapered post
	for y in range(30, 86):
		var t := float(y - 30) / 55.0
		var half: int = 4 + int(round(3.0 * t))
		var body := st.lightened(0.06).lerp(st.darkened(0.24), t)
		_rect(img, 24 - half, y, half * 2, 1, body)
		_rect(img, 24 - half, y, 2, 1, body.lightened(0.22))
		_rect(img, 24 + half - 2, y, 2, 1, body.darkened(0.34))
	# hazard chevron band on the post, in value so any region tint reads it
	for y2 in range(58, 70):
		for x2 in range(18, 30):
			if ((x2 + y2) / 3) % 2 == 0:
				_px(img, x2, y2, st.lightened(0.30))
			else:
				_px(img, x2, y2, st.darkened(0.46))
	_rect(img, 17, 57, 14, 1, st.lightened(0.26))
	_rect(img, 17, 70, 14, 1, st.darkened(0.50))
	# head: a hooded housing with the lens set back inside it
	_rect(img, 10, 18, 28, 16, st.darkened(0.10))
	_rect(img, 10, 18, 28, 2, st.lightened(0.28))
	_rect(img, 10, 32, 28, 2, st.darkened(0.46))
	_rect(img, 10, 18, 3, 16, st.lightened(0.14))
	_rect(img, 8, 14, 32, 5, st.darkened(0.04))           # the hood, overhanging
	_rect(img, 8, 14, 32, 2, st.lightened(0.32))
	_rect(img, 8, 18, 32, 1, st.darkened(0.52))
	_rect(img, 14, 23, 20, 8, Color(0.06, 0.07, 0.09))
	_rect(img, 14, 23, 20, 1, Color(0.02, 0.03, 0.04))
	# emitter core + the first two pixels of a beam nobody should walk into
	_disc(img, 24, 27, 3.0, Color(0.62, 0.64, 0.70))
	_glow(img, 24, 27, Color(0.98, 0.94, 0.92))
	_rect(img, 22, 34, 4, 3, Color(0.92, 0.90, 0.90, 0.45))
	_rect(img, 23, 37, 2, 3, Color(0.92, 0.90, 0.90, 0.22))
	# The status LED on the housing cheek is gone: the emitter core is the
	# motivated light on this prop and a second one halves its read.
	_finish(img, RIM_COOL, 0.36)
	_save(img, "dress_laser_emitter.png")

func _dress_noodle_cup() -> void:
	# Instant noodles. The open-source maintainer's entire compensation package.
	var img := Image.create(40, 44, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cup := Color(0.84, 0.82, 0.78)
	_shadow(img, 20, 41, 12, 3, 0.32)
	# chopsticks first: they go into the cup, so the rim overlaps them
	for k: int in [0, 1]:
		var ox: int = k * 4
		_line(img, 18 + ox, 20, 27 + ox, 1, Color(0.76, 0.66, 0.46))
		_line(img, 19 + ox, 20, 28 + ox, 1, Color(0.50, 0.42, 0.28))
	# tapered cup body
	for y in range(12, 40):
		var t := float(y - 12) / 27.0
		var half: int = 13 - int(round(4.0 * t))
		var body := cup.lerp(cup.darkened(0.24), t)
		_rect(img, 20 - half, y, half * 2, 1, body)
		_rect(img, 20 - half, y, 3, 1, body.lightened(0.16))
		_rect(img, 20 + half - 3, y, 3, 1, body.darkened(0.28))
	# printed band: two dark lines of a language the buyer did not read
	_rect(img, 8, 22, 24, 8, cup.darkened(0.42))
	_rect(img, 8, 22, 24, 1, cup.darkened(0.20))
	_rect(img, 11, 24, 14, 2, Color(0.88, 0.86, 0.82))
	_rect(img, 11, 27, 9, 1, Color(0.76, 0.74, 0.70))
	_rect(img, 26, 24, 3, 5, Color(0.86, 0.52, 0.24))
	# rim + the broth, and a foil lid peeled half back
	_ellipse(img, 20, 12, 13.0, 4.0, cup.lightened(0.20))
	_ellipse(img, 20, 12, 10.5, 2.8, Color(0.42, 0.30, 0.16))
	for n in 7:
		_px(img, 13 + _hash(n, 3) % 14, 11 + _hash(n, 5) % 3, Color(0.82, 0.72, 0.42))
	_px(img, 18, 11, Color(0.92, 0.86, 0.62))
	# foil lid, peeled back and creased over on itself
	for fy in 6:
		var fw: int = 11 - fy
		_rect(img, 26 - fy, 10 - fy, fw, 1, Color(0.74, 0.75, 0.79))
		_px(img, 26 - fy, 10 - fy, Color(0.92, 0.93, 0.96))
		_px(img, 26 - fy + fw - 1, 10 - fy, Color(0.48, 0.49, 0.53))
	_rect(img, 24, 10, 9, 1, Color(0.56, 0.57, 0.61))
	# steam
	_px(img, 17, 8, Color(0.82, 0.84, 0.90, 0.22))
	_px(img, 19, 5, Color(0.82, 0.84, 0.90, 0.15))
	_px(img, 16, 2, Color(0.82, 0.84, 0.90, 0.09))
	_finish(img, RIM_WARM, 0.30)
	_save(img, "dress_noodle_cup.png")

func _dress_cable_spool() -> void:
	# Cable drum standing on edge. Half the cable is gone and nobody knows where
	# it went, which is also true of the budget.
	var img := Image.create(88, 84, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var wood := Color(0.64, 0.58, 0.48)
	_shadow(img, 38, 76, 30, 5, 0.34)
	# rear flange, set up and to the right, then the wound cable between the two.
	# The front flange covers most of it: what stays visible is the crescent of
	# turns, which is the only part that has to read.
	_disc(img, 56, 32, 24.0, wood.darkened(0.54))
	for y in range(8, 56, 3):
		var dy := float(y - 32) / 24.0
		if absf(dy) >= 1.0:
			continue
		var hw := sqrt(1.0 - dy * dy) * 24.0
		var x0: int = 56 - int(hw)
		var wdt: int = maxi(int(hw * 2.0), 1)
		_rect(img, x0, y, wdt, 2, Color(0.14, 0.15, 0.18))
		_rect(img, x0, y, wdt, 1, Color(0.25, 0.26, 0.30))
	# front flange: planked disc with a hub, a bolt ring and a stencil
	for y3 in range(13, 76):
		for x3 in range(3, 66):
			if Vector2(x3 - 34, y3 - 44).length() > 30.0:
				continue
			var c := wood
			# plank seams across the face, plus grain
			if (x3 + 2) % 11 == 0:
				c = wood.darkened(0.26)
			elif (x3 + 3) % 11 == 0:
				c = wood.lightened(0.10)
			var n := float(_hash(x3, y3 * 3) % 7) / 300.0
			c = Color(c.r + n, c.g + n, c.b + n, 1.0)
			# raking light so the disc is not a flat coin
			var lam := 1.0 - (float(x3 - 34) + float(y3 - 44)) * 0.0055
			c = Color(clampf(c.r * lam, 0.0, 1.0), clampf(c.g * lam, 0.0, 1.0), clampf(c.b * lam, 0.0, 1.0), 1.0)
			img.set_pixel(x3, y3, c)
	for a in 220:
		var ang := TAU * float(a) / 220.0
		_px(img, 34 + int(cos(ang) * 30.0), 44 + int(sin(ang) * 30.0), wood.darkened(0.38))
		_px(img, 34 + int(cos(ang) * 28.0), 44 + int(sin(ang) * 28.0), wood.lightened(0.12))
	_disc(img, 34, 44, 7.0, wood.darkened(0.32))
	_disc(img, 34, 44, 4.0, Color(0.10, 0.11, 0.14))
	_px(img, 32, 42, wood.lightened(0.24))
	for b in 6:
		var ang2 := TAU * float(b) / 6.0
		_bolt(img, 34 + int(cos(ang2) * 20.0) - 1, 44 + int(sin(ang2) * 20.0) - 1, wood)
	# stencilled drum number, and the loose end trailing off to the right
	_rect(img, 26, 58, 12, 2, wood.darkened(0.42))
	_rect(img, 26, 62, 8, 2, wood.darkened(0.42))
	_line(img, 58, 58, 72, 72, Color(0.18, 0.19, 0.23))
	_line(img, 58, 57, 72, 71, Color(0.28, 0.29, 0.34))
	_line(img, 72, 72, 85, 66, Color(0.18, 0.19, 0.23))
	_line(img, 72, 71, 85, 65, Color(0.28, 0.29, 0.34))
	_finish(img, Color(0.95, 0.94, 0.90), 0.34)
	_save(img, "dress_cable_spool.png")

func _dress_pipe_stack() -> void:
	# Stacked conduit, ends toward the camera, chocked at the base. Ordered for a
	# project that was cancelled; still on the invoice.
	var img := Image.create(120, 72, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var st := Color(0.58, 0.57, 0.58)
	_shadow(img, 60, 68, 52, 5, 0.32)
	var rows := [Vector3i(22, 46, 0), Vector3i(58, 46, 1), Vector3i(94, 46, 2), Vector3i(40, 22, 3), Vector3i(76, 22, 4)]
	for pv: Vector3i in rows:
		var cx: int = pv.x
		var cy: int = pv.y
		var idx: int = pv.z
		# the body receding up and to the right
		for k in 15:
			_disc(img, cx + k, cy - k, 17.0, st.darkened(0.24 + 0.012 * float(k)))
		_disc(img, cx + 15, cy - 15, 17.0, st.darkened(0.34))
		# the near end: lit annulus wall, dark bore, bounce on the lower bore
		_disc(img, cx, cy, 17.0, st.darkened(0.06))
		for y in range(cy - 18, cy + 19):
			for x in range(cx - 18, cx + 19):
				var d := Vector2(x - cx, y - cy).length()
				if d > 17.0:
					continue
				var lam := 1.0 - (float(x - cx) + float(y - cy)) * 0.010
				var c := st
				if d < 11.0:
					c = Color(0.10, 0.10, 0.12)
					if d > 9.0 and y > cy:
						c = Color(0.24, 0.24, 0.27)      # bounce light in the bore
					elif d > 9.0 and y < cy:
						c = Color(0.05, 0.05, 0.07)      # AO at the top of the bore
				else:
					var n := float(_hash(x + idx * 31, y) % 7) / 300.0
					c = Color(clampf(st.r * lam + n, 0.0, 1.0), clampf(st.g * lam + n, 0.0, 1.0), clampf(st.b * lam + n, 0.0, 1.0), 1.0)
				img.set_pixel(x, y, c)
		# rim highlight along the top-left of the wall (screen y grows downward,
		# so the lit arc runs from pi to 1.5pi)
		for a in 120:
			var ang := PI * 0.92 + PI * 0.66 * float(a) / 120.0
			_px(img, cx + int(cos(ang) * 16.0), cy + int(sin(ang) * 16.0), st.lightened(0.26))
			_px(img, cx + int(cos(ang) * 14.0), cy + int(sin(ang) * 14.0), st.lightened(0.12))
		# a rust weep down each pipe face
		if idx % 2 == 0:
			for wy in range(cy + 2, cy + 16):
				_px(img, cx - 12 + (wy - cy) / 6, wy, Color(0.30, 0.20, 0.13, 0.20))
	# chocks under the bottom row and a strap across the stack
	for chx: int in [8, 108]:
		_rect(img, chx - 4, 58, 10, 8, Color(0.34, 0.28, 0.22))
		_rect(img, chx - 4, 58, 10, 1, Color(0.44, 0.37, 0.28))
	_line(img, 6, 42, 114, 34, Color(0.28, 0.29, 0.33))
	_line(img, 6, 43, 114, 35, Color(0.42, 0.43, 0.48))
	_finish(img, RIM_COOL, 0.34)
	_save(img, "dress_pipe_stack.png")

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
	# LAW 4 is blunt about floor overlays: mottle, wear fields, blotches, drag
	# marks and grime scatter are the noise floor, and the budget for them is
	# ZERO. These three files still exist because consumers exists()-guard them
	# by name, but each is now ONE soft, almost-invisible pool at a third of its
	# old alpha, with no ragged edge modulation, no pinholes and no speckles.
	# If a region wants a mark on the ground it should be hand-placed, and LAW 4
	# allows three of them.
	var tints := [Color(0.040, 0.045, 0.070), Color(0.070, 0.050, 0.030), Color(0.040, 0.055, 0.035)]
	for i in 3:
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var tint: Color = tints[i]
		var rx := 20.0 + float(i) * 3.0
		var ry := 15.0 + float(i) * 2.0
		for y in 64:
			for x in 64:
				var dx := float(x - 32) / rx
				var dy := float(y - 32) / ry
				var d := sqrt(dx * dx + dy * dy)
				if d >= 1.0:
					continue
				img.set_pixel(x, y, Color(tint.r, tint.g, tint.b, (1.0 - d) * 0.11))
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

func _decal_floor_set() -> void:
	# The hand-placeable floor marks. LAW 4 allows at most THREE decals in a
	# region, so each one has to be worth its place — and worth it means a
	# readable shape, not a texture. The random-walk crack spawns, the branching
	# spurs, the forty ash flecks and the puddle's sky reflection are gone; what
	# is left is one crack in two lengths, one scorch and one puddle, each a
	# single quiet silhouette.
	for i in 2:
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var span: int = 40 + i * 14
		var x := 12.0
		var y := 22.0 + float(i) * 12.0
		var a := 0.35 + float(i) * 0.5
		for st in span:
			a += sin(float(st) * 0.21 + float(i)) * 0.10
			x += cos(a)
			y += sin(a)
			if x < 2.0 or y < 2.0 or x > 61.0 or y > 61.0:
				break
			var fade := 1.0 - float(st) / float(span)
			_px(img, int(x), int(y), Color(0.02, 0.025, 0.05, 0.34 * fade))
			_px(img, int(x), int(y) - 1, Color(0.55, 0.57, 0.62, 0.07 * fade))
		_save(img, "decal_crack_%d.png" % i)
	# Scorch: something ran hot here for longer than the datasheet allowed.
	var sc := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	sc.fill(Color(0, 0, 0, 0))
	for y in 96:
		for x in 96:
			var ang := atan2(float(y - 48), float(x - 48))
			var wob := 1.0 + 0.14 * sin(ang * 3.0 + 0.7)
			var d := Vector2(float(x - 48), float(y - 48) * 1.16).length() / (42.0 * wob)
			if d >= 1.0:
				continue
			sc.set_pixel(x, y, Color(0.02, 0.02, 0.03, pow(1.0 - d, 1.7) * 0.42))
	_save(sc, "decal_scorch.png")
	# Puddle: coolant, or rain that found a way in, or neither. Nobody looked.
	var pd := Image.create(80, 56, false, Image.FORMAT_RGBA8)
	pd.fill(Color(0, 0, 0, 0))
	for y in 56:
		for x in 80:
			var wob2 := 1.0 + 0.16 * sin(atan2(float(y - 28), float(x - 40)) * 3.0 + 1.1)
			var d2 := Vector2(float(x - 40) / 36.0, float(y - 28) / 22.0).length() / wob2
			if d2 >= 1.0:
				continue
			pd.set_pixel(x, y, Color(0.015, 0.020, 0.040, 0.28 * clampf((1.0 - d2) * 3.0, 0.0, 1.0)))
	_save(pd, "decal_puddle.png")

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
	# LAW 7: ONE white-hot core pixel per genuine light source. This used to
	# stamp a nine-pixel halo cross, and it is called on every LED, every screen
	# corner, every status light and every lamp in the game — which is precisely
	# how a room full of furniture ends up glowing. The accent is now a single
	# pixel of falloff directly below the core, where a real light would spill
	# onto the surface it is mounted on, and nowhere else.
	_px(img, x, y, WHITE_HOT)
	_px(img, x, y + 1, Color(halo.r, halo.g, halo.b, 0.55))

func _finish(img: Image, _rim: Color, _rim_amt: float = 0.5) -> void:
	# Silhouette pass: a 1px outline into the surrounding empty space, and
	# nothing else.
	#
	# The rim light is GONE (LAW 7: a fourth "rim" tone belongs to the player and
	# to no other sprite). Every prop, every struct and every piece of furniture
	# in the game was being edge-lit near-white or warm on its top-left, which is
	# most of why the QA frames read as a room where everything is emitting.
	# Props already draw their own lit top and left faces through _bevel; light
	# from the top-left was never the missing information.
	#
	# The two parameters stay so every caller keeps working unchanged.
	var w := img.get_width()
	var h := img.get_height()
	var solid := PackedByteArray()
	solid.resize(w * h)
	for y in h:
		for x in w:
			solid[y * w + x] = 1 if img.get_pixel(x, y).a >= 0.55 else 0
	for y in h:
		for x in w:
			if solid[y * w + x] == 0:
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

func _clear(img: Image, x: int, y: int, w: int, h: int) -> void:
	# Punches transparency. _px/_rect BLEND, so passing them a zero-alpha colour
	# is a no-op — chipped corners and cut-outs have to go through here.
	for ix in range(x, x + w):
		for iy in range(y, y + h):
			if ix >= 0 and iy >= 0 and ix < img.get_width() and iy < img.get_height():
				img.set_pixel(ix, iy, Color(0, 0, 0, 0))

func _disc(img: Image, cx: int, cy: int, r: float, c: Color) -> void:
	for y in range(int(cy - r) - 1, int(cy + r) + 2):
		for x in range(int(cx - r) - 1, int(cx + r) + 2):
			if Vector2(float(x - cx), float(y - cy)).length() <= r:
				_px(img, x, y, c)

func _ellipse(img: Image, cx: int, cy: int, rx: float, ry: float, c: Color) -> void:
	for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
		for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
			var dx := float(x - cx) / maxf(rx, 0.001)
			var dy := float(y - cy) / maxf(ry, 0.001)
			if dx * dx + dy * dy <= 1.0:
				_px(img, x, y, c)

func _cyl(img: Image, x: int, y: int, w: int, h: int, base: Color, hi: float = 0.30, sh: float = 0.34) -> void:
	# Vertical cylinder: specular band left of centre, terminator to the right.
	for ix in range(x, x + w):
		var t := float(ix - x) / maxf(1.0, float(w - 1))
		var c: Color = base.lerp(base.lightened(hi), 1.0 - t / 0.34) if t < 0.34 else base.lerp(base.darkened(sh), (t - 0.34) / 0.66)
		_rect(img, ix, y, 1, h, c)

func _bolt(img: Image, x: int, y: int, c: Color) -> void:
	# 2x2 fastener with a top-left glint. The cheapest greeble in the business.
	_rect(img, x, y, 2, 2, c.darkened(0.36))
	_px(img, x, y, c.lightened(0.34))

func _hash(a: int, b: int) -> int:
	var h := (a * 73856093) ^ (b * 19349663)
	return abs(h)

func _save(img: Image, filename: String) -> void:
	img.save_png(ProjectSettings.globalize_path(OUT_DIR + filename))
