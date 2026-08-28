extends RefCounted
class_name AssetGeneratorRuntime

const OUT_DIR := "res://assets/textures/generated/"

func generate_all() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/textures/"))
	_generate_player_spritesheet()
	_generate_shadow()
	_generate_tileset()
	_generate_enemies()
	_generate_tokens()
	_generate_ui_elements()
	_generate_icon()
	var interior = preload("res://scripts/tools/interior_generator.gd").new()
	interior.generate()
	print("Assets generated.")

func _generate_player_spritesheet() -> void:
	const FRAME := 64
	const COLS := 6
	const ROWS := 4
	var sheet := Image.create(FRAME * COLS, FRAME * ROWS, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0, 0, 0, 0))
	var dirs := ["down", "up", "side"]
	for row in dirs.size():
		for col in COLS:
			var pose: String = "walk" if col > 0 and col < 5 else ("idle" if col == 0 else "blink")
			_blit_frame(sheet, col * FRAME, row * FRAME, FRAME, _draw_vibe_coder(dirs[row], pose, col))
	# Special row overlays on row 3
	var specials := ["hurt", "celebrate", "phone", "laptop", "coffee", "panic"]
	for i in specials.size():
		_blit_frame(sheet, i * FRAME, 3 * FRAME, FRAME, _draw_vibe_coder("down", specials[i], i))
	sheet.save_png(ProjectSettings.globalize_path(OUT_DIR + "player_spritesheet.png"))
	# Legacy single frames for fallback
	var legacy := {"idle": 0, "walk1": 1, "walk2": 2, "interact": 3, "hurt": 0, "celebrate": 0}
	for fname in legacy:
		var pose: String = "walk" if fname.begins_with("walk") else fname
		if fname == "interact":
			pose = "laptop"
		_save_image(_draw_vibe_coder("down", pose, legacy[fname]), "player_%s.png" % fname)

func _generate_shadow() -> void:
	var img := Image.create(48, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in 48:
		for y in 20:
			var dx := float(x - 24) / 24.0
			var dy := float(y - 10) / 10.0
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0.35 * (1.0 - dy * 0.3)))
	_save_image(img, "player_shadow.png")

func _blit_frame(sheet: Image, ox: int, oy: int, size: int, frame: Image) -> void:
	for x in size:
		for y in size:
			sheet.set_pixel(ox + x, oy + y, frame.get_pixel(x, y))

func _draw_vibe_coder(direction: String, pose: String, frame_idx: int) -> Image:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var hoodie := Color(0.14, 0.2, 0.34)
	var hoodie_hi := Color(0.2, 0.28, 0.42)
	var skin := Color(0.86, 0.72, 0.6)
	var glow := Color(0.35, 0.95, 0.85)
	var jeans := Color(0.12, 0.14, 0.22)
	var bob := int(sin(float(frame_idx) * 1.2) * 1.5)
	var leg_l := 0
	var leg_r := 0
	if pose == "walk":
		leg_l = 2 if frame_idx % 2 == 0 else -2
		leg_r = -leg_l
	var facing_up := direction == "up"
	var facing_side := direction == "side"
	var cx := 32
	var cy := 28 + bob
	# Hood + head
	if not facing_up:
		_fill_arc(img, cx, cy - 6, 14, hoodie)
		_fill_circle(img, cx, cy - 8, 9, skin)
		img.set_pixel(cx - 3, cy - 9, Color(0.1, 0.12, 0.16))
		img.set_pixel(cx + 3, cy - 9, Color(0.1, 0.12, 0.16))
		_fill_rect(img, cx - 8, cy - 16, 16, 3, Color(0.22, 0.24, 0.3))
		img.set_pixel(cx - 9, cy - 13, Color(0.35, 0.9, 0.8))
		img.set_pixel(cx + 8, cy - 13, Color(0.35, 0.9, 0.8))
	else:
		_fill_arc(img, cx, cy - 4, 14, hoodie.darkened(0.1))
		_fill_rect(img, cx - 10, cy - 18, 20, 8, hoodie)
	# Torso
	_fill_rect(img, cx - 12, cy, 24, 22, hoodie)
	_fill_rect(img, cx - 10, cy + 2, 20, 4, hoodie_hi)
	# Laptop glow
	if pose != "phone" and pose != "panic":
		_fill_rect(img, cx - 9, cy + 8, 18, 12, Color(0.04, 0.07, 0.1))
		for x in range(cx - 7, cx + 8):
			for y in range(cy + 10, cy + 18):
				if (x * 3 + y * 7 + frame_idx) % 5 == 0:
					img.set_pixel(x, y, glow)
	if pose == "laptop":
		_fill_rect(img, cx - 11, cy + 6, 22, 14, Color(0.08, 0.1, 0.14))
		img.set_pixel(cx, cy + 10, Color(0.95, 0.3, 0.3))
	if pose == "phone":
		_fill_rect(img, cx + 6, cy - 2, 6, 10, Color(0.15, 0.15, 0.2))
		img.set_pixel(cx + 8, cy + 2, Color(0.3, 0.95, 0.85))
	if pose == "panic":
		for i in 4:
			img.set_pixel(cx - 8 + i * 5, cy - 18, Color(0.9, 0.2, 0.2))
	if pose == "celebrate" or pose == "coffee":
		_fill_rect(img, cx + 10, cy + 4, 5, 8, Color(0.75, 0.28, 0.12))
	# Arms
	if facing_side:
		_fill_rect(img, cx + (10 if frame_idx % 2 == 0 else 8), cy + 4, 6, 14, hoodie)
		_fill_rect(img, cx - 16, cy + 6, 6, 12, hoodie)
	else:
		_fill_rect(img, cx - 16, cy + 4, 6, 14, hoodie)
		_fill_rect(img, cx + 10, cy + 4, 6, 14, hoodie)
	# Legs
	_fill_rect(img, cx - 9 + leg_l, cy + 22, 7, 16, jeans)
	_fill_rect(img, cx + 2 + leg_r, cy + 22, 7, 16, jeans)
	_fill_rect(img, cx - 10 + leg_l, cy + 36, 9, 4, Color(0.2, 0.2, 0.24))
	_fill_rect(img, cx + 1 + leg_r, cy + 36, 9, 4, Color(0.2, 0.2, 0.24))
	if pose == "hurt":
		for y in 64:
			for x in 64:
				var p := img.get_pixel(x, y)
				if p.a > 0:
					img.set_pixel(x, y, p.lerp(Color(0.95, 0.25, 0.3), 0.4))
	return img

func _generate_player_sprites() -> void:
	pass

func _generate_tileset() -> void:
	var regions := {
		"localhost": Color(0.12, 0.1, 0.18),
		"dependency": Color(0.15, 0.08, 0.1),
		"stackoverflow": Color(0.18, 0.15, 0.1),
		"api_bazaar": Color(0.08, 0.15, 0.18),
		"cloud": Color(0.1, 0.12, 0.22),
		"opensource": Color(0.08, 0.18, 0.1),
		"corporate": Color(0.15, 0.15, 0.2),
		"gpu": Color(0.2, 0.1, 0.08),
		"production": Color(0.22, 0.05, 0.05),
		"vault": Color(0.15, 0.12, 0.05),
	}
	for rname in regions:
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		var base: Color = regions[rname]
		for x in 64:
			for y in 64:
				var n := float((x * 17 + y * 31) % 20) / 250.0
				var c := Color(base.r + n, base.g + n, base.b + n, 1.0)
				if (x + y) % 8 == 0:
					c = c.lightened(0.05)
				img.set_pixel(x, y, c)
		for i in range(0, 64, 16):
			for j in 64:
				img.set_pixel(i, j, base.lightened(0.15))
				img.set_pixel(j, i, base.lightened(0.15))
		_save_image(img, "tile_%s.png" % rname)

func _generate_enemies() -> void:
	var enemies := {
		"bug": Color(0.9, 0.2, 0.3),
		"null_reference": Color(0.6, 0.1, 0.8),
		"rate_limiter": Color(0.9, 0.7, 0.1),
		"scope_creep": Color(0.3, 0.8, 0.3),
		"dependency_demon": Color(0.8, 0.2, 0.5),
		"legacy_system": Color(0.5, 0.45, 0.4),
		"memory_leak": Color(0.2, 0.5, 0.9),
		"hallucination": Color(0.9, 0.5, 0.9),
		"merge_conflict": Color(0.9, 0.4, 0.1),
		"cloud_bill": Color(0.1, 0.8, 0.3),
		"enterprise_architect": Color(0.3, 0.3, 0.5),
		"legacy_monolith": Color(0.4, 0.35, 0.3),
		"infinite_context": Color(0.5, 0.2, 0.9),
	}
	for ename in enemies:
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var c: Color = enemies[ename]
		if ename == "bug":
			_draw_bug(img, c)
		elif ename == "legacy_monolith":
			_fill_rect(img, 4, 4, 24, 24, c)
			for i in range(6, 26, 4):
				_fill_rect(img, i, 6, 2, 20, c.darkened(0.2))
		elif ename == "infinite_context":
			for r in range(3, 14, 2):
				_draw_circle_outline(img, 16, 16, r, c)
		else:
			_fill_circle(img, 16, 16, 12, c)
			_fill_circle(img, 12, 13, 3, Color.WHITE)
			_fill_circle(img, 20, 13, 3, Color.WHITE)
			_fill_circle(img, 12, 13, 1, Color.BLACK)
			_fill_circle(img, 20, 13, 1, Color.BLACK)
		_save_image(img, "enemy_%s.png" % ename)

## A software "bug" that actually reads as a beetle: dark carapace, red shell
## segments, six legs, antennae, mandibles and glowing eyes.
func _draw_bug(img: Image, c: Color) -> void:
	var shell := Color(0.5, 0.12, 0.16)
	var carapace := Color(0.16, 0.1, 0.12)
	var leg := Color(0.08, 0.06, 0.07)
	# legs (three each side)
	for sy in [12, 17, 22]:
		_draw_line_img(img, 12, sy, 3, sy - 3, leg)
		_draw_line_img(img, 12, sy, 3, sy + 3, leg)
		_draw_line_img(img, 20, sy, 29, sy - 3, leg)
		_draw_line_img(img, 20, sy, 29, sy + 3, leg)
	# abdomen / shell
	_fill_ellipse(img, 16, 18, 9, 11, shell)
	_fill_ellipse(img, 16, 18, 9, 11, shell, 1)
	# wing split down the middle + segment ridges
	for y in range(9, 29):
		img.set_pixel(16, y, carapace)
	for ry in [13, 17, 21, 25]:
		for x in range(8, 25):
			if Vector2(x - 16, ry - 18).length() < 10:
				img.set_pixel(x, ry, shell.darkened(0.25))
	# head
	_fill_circle(img, 16, 7, 5, carapace)
	# mandibles
	_draw_line_img(img, 13, 4, 11, 1, leg)
	_draw_line_img(img, 19, 4, 21, 1, leg)
	# antennae
	_draw_line_img(img, 14, 4, 10, 0, leg)
	_draw_line_img(img, 18, 4, 22, 0, leg)
	# glowing eyes
	img.set_pixel(14, 7, Color(1.0, 0.85, 0.2))
	img.set_pixel(18, 7, Color(1.0, 0.85, 0.2))

func _fill_ellipse(img: Image, cx: int, cy: int, rx: int, ry: int, c: Color, inset: int = 0) -> void:
	for x in img.get_width():
		for y in img.get_height():
			var dx := float(x - cx) / float(rx - inset)
			var dy := float(y - cy) / float(ry - inset)
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, c if inset == 0 else c.lightened(0.08))

func _draw_line_img(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	var dx: int = abs(x1 - x0)
	var dy: int = -abs(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err := dx + dy
	var x := x0
	var y := y0
	for _i in 80:
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

func _generate_tokens() -> void:
	var types := {
		"common": Color(0.3, 0.8, 1.0),
		"cached": Color(0.5, 0.9, 0.6),
		"premium": Color(1.0, 0.8, 0.2),
		"golden": Color(1.0, 0.85, 0.0),
		"frontier": Color(0.9, 0.3, 1.0),
		"compute": Color(0.2, 0.9, 0.7),
	}
	for tname in types:
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var c: Color = types[tname]
		_draw_hex(img, 8, 8, 7, c)
		_draw_hex(img, 8, 8, 4, c.lightened(0.3))
		_save_image(img, "token_%s.png" % tname)

func _generate_ui_elements() -> void:
	var panel := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	panel.fill(Color(0.08, 0.06, 0.14, 0.92))
	for i in 64:
		panel.set_pixel(i, 0, Color(0.3, 0.9, 0.8, 0.6))
		panel.set_pixel(i, 63, Color(0.3, 0.9, 0.8, 0.3))
		panel.set_pixel(0, i, Color(0.3, 0.9, 0.8, 0.6))
		panel.set_pixel(63, i, Color(0.3, 0.9, 0.8, 0.3))
	_save_image(panel, "ui_panel.png")

func _generate_icon() -> void:
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.06, 0.04, 0.12))
	_draw_hex(img, 64, 64, 40, Color(0.2, 0.85, 0.75))
	_draw_hex(img, 64, 64, 25, Color(0.15, 0.65, 0.55))
	_fill_rect(img, 40, 70, 48, 8, Color(0.9, 0.85, 0.2))
	img.save_png(ProjectSettings.globalize_path("res://assets/textures/icon.png"))

func _save_image(img: Image, filename: String) -> void:
	img.save_png(ProjectSettings.globalize_path(OUT_DIR + filename))

func _fill_rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for ix in range(x, x + w):
		for iy in range(y, y + h):
			if ix >= 0 and iy >= 0 and ix < img.get_width() and iy < img.get_height():
				img.set_pixel(ix, iy, c)

func _fill_circle(img: Image, cx: int, cy: int, r: int, c: Color) -> void:
	for x in img.get_width():
		for y in img.get_height():
			if Vector2(x, y).distance_to(Vector2(cx, cy)) <= r:
				img.set_pixel(x, y, c)

func _draw_circle_outline(img: Image, cx: int, cy: int, r: int, c: Color) -> void:
	for x in img.get_width():
		for y in img.get_height():
			if abs(Vector2(x, y).distance_to(Vector2(cx, cy)) - r) < 1.2:
				img.set_pixel(x, y, c)

func _fill_arc(img: Image, cx: int, cy: int, r: int, c: Color) -> void:
	for x in img.get_width():
		for y in img.get_height():
			if Vector2(x, y).distance_to(Vector2(cx, cy)) <= r and y < cy + 4:
				img.set_pixel(x, y, c)

func _draw_hex(img: Image, cx: int, cy: int, r: int, c: Color) -> void:
	for x in img.get_width():
		for y in img.get_height():
			if float(abs(x - cx)) / r + float(abs(y - cy)) / r * 1.15 <= 1.0:
				img.set_pixel(x, y, c)
