extends RefCounted
class_name AssetGeneratorRuntime

const OUT_DIR := "res://assets/textures/generated/"

func generate_all() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/textures/"))
	_generate_player_sprites()
	_generate_tileset()
	_generate_enemies()
	_generate_tokens()
	_generate_ui_elements()
	_generate_icon()
	print("Assets generated.")

func _generate_player_sprites() -> void:
	var frames := ["idle", "walk1", "walk2", "interact", "hurt", "celebrate"]
	for i in frames.size():
		_save_image(_draw_player_frame(i), "player_%s.png" % frames[i])

func _draw_player_frame(frame: int) -> Image:
	var img := Image.create(32, 48, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var hoodie := Color(0.16, 0.22, 0.32)
	var hoodie_dark := Color(0.11, 0.15, 0.22)
	var skin := Color(0.82, 0.68, 0.58)
	var glow := Color(0.28, 0.92, 0.82, 1.0)
	var jeans := Color(0.14, 0.16, 0.24)
	var shoe := Color(0.18, 0.18, 0.22)
	var bob := 1 if frame == 1 else 0
	var leg_l := 0
	var leg_r := 0
	var arm_raise := 0
	match frame:
		1: bob = 1
		2: leg_l = 2; leg_r = -1
		3: leg_l = -1; leg_r = 2
		5: arm_raise = -6
	# Hood silhouette — readable coder shape at zoom
	_fill_arc(img, 16, 11 + bob, 10, hoodie)
	_fill_rect(img, 7, 12 + bob, 18, 6, hoodie)
	_fill_circle(img, 16, 12 + bob, 6, skin)
	img.set_pixel(14, 11 + bob, Color(0.12, 0.14, 0.18))
	img.set_pixel(18, 11 + bob, Color(0.12, 0.14, 0.18))
	_fill_rect(img, 13, 13 + bob, 6, 1, Color(0.55, 0.45, 0.4, 0.6))
	_fill_rect(img, 8, 17 + bob, 16, 16, hoodie)
	_fill_rect(img, 9, 18 + bob, 14, 3, hoodie_dark)
	# Headphones band
	_fill_rect(img, 10, 8 + bob, 12, 2, Color(0.22, 0.24, 0.28))
	img.set_pixel(9, 10 + bob, Color(0.3, 0.85, 0.75))
	img.set_pixel(22, 10 + bob, Color(0.3, 0.85, 0.75))
	# Laptop glow on chest
	_fill_rect(img, 11, 24 + bob, 10, 7, Color(0.05, 0.08, 0.1))
	for x in range(12, 20):
		for y in range(25 + bob, 30 + bob):
			if (x * 5 + y * 11 + frame) % 4 == 0:
				img.set_pixel(x, y, glow)
	img.set_pixel(15, 26 + bob, Color(0.95, 0.95, 0.35))
	# Arms
	_fill_rect(img, 5, 20 + bob + arm_raise, 4, 10, hoodie)
	_fill_rect(img, 23, 20 + bob, 4, 10, hoodie)
	if frame == 5:
		_fill_rect(img, 4, 14 + bob, 4, 8, hoodie)
		_fill_rect(img, 24, 14 + bob, 4, 8, hoodie)
		_fill_rect(img, 24, 22, 4, 7, Color(0.75, 0.28, 0.12))
	# Legs + sneakers
	_fill_rect(img, 10 + leg_l, 33 + bob, 5, 11, jeans)
	_fill_rect(img, 17 + leg_r, 33 + bob, 5, 11, jeans)
	_fill_rect(img, 9 + leg_l, 42 + bob, 7, 3, shoe)
	_fill_rect(img, 16 + leg_r, 42 + bob, 7, 3, shoe)
	# player_hurt.png — red flash overlay
	if frame == 4:
		for y in 48:
			for x in 32:
				var p := img.get_pixel(x, y)
				if p.a > 0:
					img.set_pixel(x, y, p.lerp(Color(0.9, 0.25, 0.3), 0.35))
	return img

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
		if ename == "legacy_monolith":
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
