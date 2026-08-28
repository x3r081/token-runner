extends RefCounted
class_name InteriorGenerator
## Procedurally generates purpose-built interior art for the Localhost apartment:
## warm wood flooring, a rug, interior walls with a window, and hand-drawn
## furniture (desk, monitors, server rack, bed, fridge, coffee machine, plant,
## node_modules trash pile, bookshelf, mini-fridge). Everything is drawn as
## pixel art so the "3AM coder apartment" reads as a designed, inhabited space
## instead of a stamped outdoor tile field.

const OUT_DIR := "res://assets/textures/generated/"

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
	print("Interior assets generated.")

# ---------------------------------------------------------------- floor -----

func _floor_tiles() -> void:
	# Three low-contrast warm-wood plank variants so tiling never reads as a grid.
	var bases := [Color(0.29, 0.22, 0.17), Color(0.27, 0.205, 0.155), Color(0.31, 0.235, 0.18)]
	for v in bases.size():
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		var base: Color = bases[v]
		var plank_h := 16
		var offset := (v * 24) % 64
		for y in 64:
			for x in 64:
				var grain := (_hash(x * 3 + v * 101, y) % 12) / 260.0
				var c := Color(base.r + grain, base.g + grain, base.b + grain * 0.8, 1.0)
				# plank seams (horizontal) with staggered vertical joints
				var row := (y + offset) / plank_h
				var in_seam := (y + offset) % plank_h == 0
				if in_seam:
					c = c.darkened(0.32)
				var joint := (x + row * 29) % 64
				if joint == 0:
					c = c.darkened(0.28)
				# faint lengthwise grain streaks (linear, so tiling reads as planks)
				if (x * 5 + y) % 37 == 0:
					c = c.darkened(0.06)
				img.set_pixel(x, y, c)
		_save(img, "int_floor_%d.png" % v)

func _knot(img: Image, cx: int, cy: int, c: Color) -> void:
	for x in img.get_width():
		for y in img.get_height():
			var d := Vector2(x - cx, y - cy).length()
			if d < 4.0:
				img.set_pixel(x, y, c.darkened(0.1 * (4.0 - d)))
			elif d < 5.5:
				img.set_pixel(x, y, c)

func _rug() -> void:
	# A worn dark-teal rug that anchors the battlestation zone.
	var w := 320
	var h := 224
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var field := Color(0.16, 0.19, 0.26)
	var border := Color(0.24, 0.3, 0.4)
	var accent := Color(0.3, 0.55, 0.6)
	for y in h:
		for x in w:
			var edge: int = min(min(x, w - 1 - x), min(y, h - 1 - y))
			if edge < 4:
				continue
			var c := field
			if edge < 14:
				c = border
			elif edge < 18:
				c = accent.darkened(0.2)
			else:
				# subtle diamond weave
				if ((x / 16) + (y / 16)) % 2 == 0:
					c = field.lightened(0.05)
				var n := (_hash(x, y) % 8) / 300.0
				c = Color(c.r + n, c.g + n, c.b + n, 1.0)
			img.set_pixel(x, y, c)
	_save(img, "int_rug.png")

# ---------------------------------------------------------------- walls -----

func _wall_tiles() -> void:
	# Upper wall face (dark, industrial) with a lit crown strip and shadowed base.
	var img := Image.create(64, 96, false, Image.FORMAT_RGBA8)
	var wall := Color(0.15, 0.145, 0.2)
	for y in 96:
		for x in 64:
			var c := wall
			if y < 6:
				c = wall.lightened(0.22)      # crown highlight
			elif y < 10:
				c = wall.lightened(0.08)
			elif y > 86:
				c = wall.darkened(0.35)       # base shadow onto floor
			else:
				# faint vertical panel seams + noise
				if x % 32 == 0:
					c = wall.darkened(0.18)
				var n := (_hash(x, y * 2) % 6) / 340.0
				c = Color(c.r + n, c.g + n, c.b + n, 1.0)
			img.set_pixel(x, y, c)
	_save(img, "int_wall.png")

	# Side wall column (for left/right room edges)
	var side := Image.create(40, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 40:
			var c := wall.darkened(0.05)
			if x < 5:
				c = wall.lightened(0.14)
			elif x > 34:
				c = wall.darkened(0.3)
			var n := (_hash(x * 5, y) % 6) / 340.0
			c = Color(c.r + n, c.g + n, c.b + n, 1.0)
			side.set_pixel(x, y, c)
	_save(side, "int_wall_side.png")

func _window() -> void:
	# Night-city view: dark frame + gradient sky + scattered warm window lights.
	var w := 160
	var h := 120
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var frame := Color(0.1, 0.1, 0.14)
	for y in h:
		for x in w:
			var c: Color
			var edge: int = min(min(x, w - 1 - x), min(y, h - 1 - y))
			if edge < 8:
				c = frame
			else:
				var t := float(y) / float(h)
				c = Color(0.05, 0.06, 0.12).lerp(Color(0.12, 0.1, 0.2), t)
				# distant skyline silhouette
				var b := (_hash(x / 10, 7) % 40)
				if y > h - 34 - b / 3:
					c = Color(0.03, 0.035, 0.06)
					if _hash(x, y) % 23 == 0:
						c = Color(0.95, 0.8, 0.4)  # lit window
			img.set_pixel(x, y, c)
	# mullions
	for y in h:
		if y >= 8 and y < h - 8:
			img.set_pixel(w / 2, y, frame.lightened(0.1))
	for x in w:
		if x >= 8 and x < w - 8:
			img.set_pixel(x, h / 2, frame.lightened(0.1))
	_save(img, "int_window.png")

# ------------------------------------------------------------ furniture -----

func _desk() -> void:
	var w := 240
	var h := 96
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var top := Color(0.22, 0.2, 0.26)
	var top_hi := Color(0.3, 0.28, 0.36)
	var legc := Color(0.12, 0.11, 0.15)
	# legs
	_rect(img, 8, 40, 12, 52, legc)
	_rect(img, w - 20, 40, 12, 52, legc)
	# desktop slab with front edge
	_rect(img, 0, 24, w, 26, top)
	_rect(img, 0, 24, w, 5, top_hi)
	_rect(img, 0, 46, w, 4, top.darkened(0.4))
	# cable tray shadow underneath
	_rect(img, 20, 50, w - 40, 4, Color(0, 0, 0, 0.3))
	# keyboard + mouse + mug clutter on top
	_rect(img, 60, 30, 70, 12, Color(0.1, 0.11, 0.14))
	for kx in range(64, 128, 6):
		_rect(img, kx, 32, 4, 3, Color(0.2, 0.22, 0.26))
		_rect(img, kx, 37, 4, 3, Color(0.2, 0.22, 0.26))
	_rect(img, 140, 34, 10, 8, Color(0.12, 0.13, 0.16))
	_rect(img, 170, 28, 12, 14, Color(0.7, 0.28, 0.16)) # mug
	_rect(img, 168, 26, 16, 4, Color(0.8, 0.36, 0.2))
	_save(img, "furn_desk.png")

func _monitor() -> void:
	# Bezel + stand; screen left dark so the builder overlays a bright animated screen.
	var w := 96
	var h := 84
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var bez := Color(0.08, 0.08, 0.1)
	_rect(img, 0, 0, w, 62, bez)
	_rect(img, 4, 4, w - 8, 54, Color(0.03, 0.04, 0.05)) # screen well
	# stand
	_rect(img, w / 2 - 6, 62, 12, 12, bez.lightened(0.1))
	_rect(img, w / 2 - 20, 74, 40, 8, bez)
	_save(img, "furn_monitor.png")

func _server_rack() -> void:
	var w := 96
	var h := 168
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cab := Color(0.13, 0.14, 0.17)
	var cab_hi := Color(0.2, 0.22, 0.26)
	_rect(img, 0, 0, w, h, cab)
	_rect(img, 0, 0, 5, h, cab_hi)
	_rect(img, w - 5, 0, 5, h, cab.darkened(0.3))
	# rack units with blinking LEDs
	for u in range(8, h - 8, 20):
		_rect(img, 10, u, w - 20, 15, Color(0.06, 0.07, 0.09))
		var col := [Color(0.3, 0.9, 0.4), Color(0.9, 0.7, 0.2), Color(0.3, 0.9, 0.4), Color(0.9, 0.25, 0.2)]
		for i in 4:
			var on: bool = _rng.randf() > 0.35
			var c: Color = col[i] if on else col[i].darkened(0.7)
			_rect(img, 16 + i * 8, u + 4, 4, 4, c)
		# vent slits
		for sx in range(56, w - 12, 4):
			_rect(img, sx, u + 3, 2, 9, cab.darkened(0.4))
	_save(img, "furn_server.png")

func _bed() -> void:
	var w := 168
	var h := 108
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var frame := Color(0.16, 0.13, 0.12)
	var sheet := Color(0.28, 0.3, 0.4)
	var blanket := Color(0.2, 0.24, 0.34)
	_rect(img, 0, 8, w, h - 12, frame)          # frame
	_rect(img, 6, 14, w - 12, h - 26, sheet)     # mattress
	_rect(img, 6, 60, w - 12, h - 72, blanket)   # rumpled blanket
	for i in range(10, w - 12, 14):
		_rect(img, i, 62, 6, h - 78, blanket.darkened(0.12))
	_rect(img, 12, 18, 44, 26, Color(0.85, 0.86, 0.9)) # pillow
	# laptop left open on the bed (of course)
	_rect(img, w - 60, 24, 34, 20, Color(0.1, 0.11, 0.14))
	_rect(img, w - 57, 26, 28, 14, Color(0.2, 0.7, 0.75))
	_save(img, "furn_bed.png")

func _fridge() -> void:
	var w := 84
	var h := 132
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var body := Color(0.32, 0.35, 0.4)
	_rect(img, 0, 0, w, h, body)
	_rect(img, 0, 0, 6, h, body.lightened(0.2))
	_rect(img, w - 6, 0, 6, h, body.darkened(0.25))
	_rect(img, 6, h / 2 - 2, w - 12, 4, body.darkened(0.4)) # door split
	_rect(img, w - 20, 18, 6, 30, Color(0.7, 0.72, 0.78))   # handle
	_rect(img, w - 20, h / 2 + 10, 6, 30, Color(0.7, 0.72, 0.78))
	# energy-drink magnets
	_rect(img, 14, 20, 10, 16, Color(0.2, 0.85, 0.35))
	_rect(img, 30, 24, 10, 16, Color(0.9, 0.3, 0.3))
	_rect(img, 46, 22, 10, 16, Color(0.3, 0.6, 0.95))
	_save(img, "furn_fridge.png")

func _coffee() -> void:
	var w := 68
	var h := 92
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var body := Color(0.12, 0.12, 0.15)
	_rect(img, 8, 0, w - 16, h, body)
	_rect(img, 8, 0, w - 16, 8, body.lightened(0.2))
	_rect(img, 16, 30, w - 32, 24, Color(0.05, 0.05, 0.07)) # dispenser cavity
	_rect(img, 24, 40, w - 48, 14, Color(0.4, 0.25, 0.15))  # mug
	# status light (mission critical)
	_rect(img, w - 22, 12, 6, 6, Color(0.3, 0.95, 0.4))
	_save(img, "furn_coffee.png")

func _plant() -> void:
	var w := 64
	var h := 96
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# pot
	_rect(img, 18, h - 30, 28, 28, Color(0.4, 0.28, 0.2))
	_rect(img, 16, h - 32, 32, 6, Color(0.48, 0.34, 0.24))
	# drooping, deprecated leaves (dull, wilting)
	var leaf := Color(0.34, 0.42, 0.26)
	for i in 5:
		var bx := 24 + i * 4
		for j in range(0, 30, 2):
			var yy := h - 34 - j
			var xx := bx + int(sin(j * 0.3 + i) * 6) + int(j * 0.4)  # drooping curve
			if yy >= 0 and xx >= 0 and xx < w:
				img.set_pixel(xx, yy, leaf.darkened(0.05 * (i % 3)))
				if xx + 1 < w:
					img.set_pixel(xx + 1, yy, leaf.darkened(0.1))
	_save(img, "furn_plant.png")

func _node_modules() -> void:
	# A dumpster-tier pile of cardboard boxes = node_modules.
	var w := 140
	var h := 104
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var boxes := [
		[6, 60, 60, 44, Color(0.5, 0.38, 0.24)],
		[54, 44, 56, 60, Color(0.56, 0.42, 0.27)],
		[96, 64, 40, 40, Color(0.46, 0.34, 0.22)],
		[30, 20, 46, 40, Color(0.6, 0.46, 0.3)],
	]
	for b in boxes:
		_rect(img, b[0], b[1], b[2], b[3], b[4])
		_rect(img, b[0], b[1], b[2], 4, (b[4] as Color).lightened(0.15))
		_rect(img, b[0], b[1], 4, b[3], (b[4] as Color).lightened(0.1))
		# tape
		_rect(img, b[0] + b[2] / 2 - 2, b[1], 4, b[3], (b[4] as Color).darkened(0.2))
	_save(img, "furn_boxes.png")

func _bookshelf() -> void:
	var w := 140
	var h := 120
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var wood := Color(0.2, 0.16, 0.14)
	_rect(img, 0, 0, w, h, wood)
	var shelf_cols := [Color(0.7, 0.3, 0.3), Color(0.3, 0.5, 0.7), Color(0.4, 0.6, 0.4), Color(0.8, 0.7, 0.3), Color(0.5, 0.4, 0.6)]
	for s in range(6, h - 6, 34):
		_rect(img, 4, s, w - 8, 28, Color(0.09, 0.08, 0.09))
		var x := 8
		while x < w - 14:
			var bw: int = 6 + (_hash(x, s) % 6)
			var bh: int = 20 + (_hash(x * 2, s) % 6)
			var col: Color = shelf_cols[_hash(x, s) % shelf_cols.size()]
			_rect(img, x, s + (28 - bh), bw, bh, col.darkened(0.1))
			x += bw + 2
		_rect(img, 4, s + 28, w - 8, 4, wood.lightened(0.1)) # shelf board
	_save(img, "furn_shelf.png")

func _chair() -> void:
	var w := 64
	var h := 88
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Color(0.14, 0.15, 0.2)
	_rect(img, 12, 6, 40, 40, c)          # backrest
	_rect(img, 12, 6, 40, 6, c.lightened(0.15))
	_rect(img, 8, 44, 48, 16, c.darkened(0.1)) # seat
	_rect(img, w / 2 - 3, 60, 6, 20, c.darkened(0.3)) # post
	for a in [-18, 0, 18]:
		_rect(img, w / 2 - 2 + a, 80, 4, 8, c.darkened(0.3)) # wheels legs
	_save(img, "furn_chair.png")

func _whiteboard() -> void:
	var w := 176
	var h := 112
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var board := Color(0.9, 0.91, 0.88)
	_rect(img, 0, 0, w, h, Color(0.3, 0.3, 0.34)) # frame
	_rect(img, 5, 5, w - 10, h - 10, board)
	# chaotic architecture arrows (blue/red/black scribbles)
	var cols := [Color(0.2, 0.3, 0.7), Color(0.7, 0.2, 0.2), Color(0.15, 0.15, 0.2)]
	for i in 40:
		var x0 := 12 + _rng.randi_range(0, w - 40)
		var y0 := 12 + _rng.randi_range(0, h - 30)
		var x1 := x0 + _rng.randi_range(-24, 24)
		var y1 := y0 + _rng.randi_range(-16, 16)
		_line(img, x0, y0, x1, y1, cols[i % cols.size()])
		# little node box
		if i % 3 == 0:
			_rect(img, x0 - 4, y0 - 3, 9, 7, Color(0.8, 0.85, 0.95))
	_save(img, "furn_whiteboard.png")

func _door() -> void:
	var w := 96
	var h := 140
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var d := Color(0.18, 0.14, 0.12)
	_rect(img, 0, 0, w, h, Color(0.1, 0.09, 0.11))       # frame
	_rect(img, 8, 6, w - 16, h - 6, d)                    # door
	_rect(img, 12, 12, w - 24, 40, d.lightened(0.08))     # panel
	_rect(img, 12, 60, w - 24, 70, d.lightened(0.05))     # panel
	_rect(img, w - 22, h / 2 - 4, 8, 10, Color(0.8, 0.75, 0.4)) # handle
	_save(img, "furn_door.png")

# --------------------------------------------------------------- helpers ----

func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for ix in range(x, x + w):
		for iy in range(y, y + h):
			if ix >= 0 and iy >= 0 and ix < img.get_width() and iy < img.get_height():
				if c.a >= 1.0:
					img.set_pixel(ix, iy, c)
				else:
					img.set_pixel(ix, iy, img.get_pixel(ix, iy).blend(c))

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
			img.set_pixel(x, y, c)
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
