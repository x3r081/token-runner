extends RefCounted
class_name AssetGeneratorRuntime

const OUT_DIR := "res://assets/textures/generated/"

## Bible constants — every sprite in the game agrees on these.
const OUTLINE_COLOR := Color(0.039, 0.047, 0.086, 0.85)  # #0A0C16 @ ~85%
const WHITE_HOT := Color(0.957, 0.976, 1.0)              # hottest emissive core

func generate_all() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/textures/"))
	_generate_player_spritesheet()
	_generate_shadow()
	_generate_tileset()
	_generate_enemies()
	_generate_tokens()
	_generate_ui_elements()
	_generate_fx()
	_generate_icon()
	_generate_npcs()
	var interior = preload("res://scripts/tools/interior_generator.gd").new()
	interior.generate()
	print("Assets generated.")

func _generate_npcs() -> void:
	# Same base body as the player so the world reads as one species of
	# sleep-deprived professional. The accessory does the characterization,
	# and each of them gets exactly one emissive accent (bible rules).
	var kinds := {
		"claude": {"hoodie": Color(0.16, 0.36, 0.36), "hoodie_hi": Color(0.24, 0.52, 0.5), "hoodie_sh": Color(0.1, 0.26, 0.26), "hair": Color(0.15, 0.13, 0.12), "skin": Color(0.88, 0.74, 0.62), "accent": Color(0.35, 0.95, 0.85), "headphones": true, "accessory": "circuit"},
		"suit": {"hoodie": Color(0.16, 0.18, 0.27), "hoodie_hi": Color(0.24, 0.26, 0.37), "hoodie_sh": Color(0.1, 0.11, 0.18), "hair": Color(0.2, 0.16, 0.12), "skin": Color(0.86, 0.72, 0.6), "accent": Color(0.35, 0.65, 1.0), "headphones": false, "accessory": "tie"},
		"maintainer": {"hoodie": Color(0.3, 0.32, 0.34), "hoodie_hi": Color(0.4, 0.42, 0.44), "hoodie_sh": Color(0.2, 0.22, 0.24), "hair": Color(0.42, 0.42, 0.44), "skin": Color(0.82, 0.68, 0.56), "accent": Color(0.5, 0.85, 0.55), "headphones": false, "accessory": "glasses"},
		"foreman": {"hoodie": Color(0.85, 0.55, 0.15), "hoodie_hi": Color(0.95, 0.7, 0.25), "hoodie_sh": Color(0.6, 0.38, 0.1), "hair": Color(0.15, 0.12, 0.1), "skin": Color(0.8, 0.66, 0.54), "accent": Color(1.0, 0.75, 0.25), "headphones": false, "accessory": "hardhat"},
	}
	for k in kinds:
		_save_image(_draw_vibe_coder("down", "idle", 0, kinds[k]), "npc_%s.png" % k)

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
	# Soft radial falloff instead of a hard-edged puck — reads as contact
	# shadow instead of a hole in the floor.
	var img := Image.create(48, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in 48:
		for y in 20:
			var dx := float(x - 24) / 24.0
			var dy := float(y - 10) / 10.0
			var d := dx * dx + dy * dy
			if d <= 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0.34 * pow(1.0 - d, 1.5)))
	_save_image(img, "player_shadow.png")

func _blit_frame(sheet: Image, ox: int, oy: int, size: int, frame: Image) -> void:
	for x in size:
		for y in size:
			sheet.set_pixel(ox + x, oy + y, frame.get_pixel(x, y))

## The vibe coder: hoodie, headphones, white sneakers, and the thousand-yard
## stare of someone whose tests pass locally. Full bible treatment: 4-tone
## ramps lit from the top-left, folds, rim light, a 1px outline, and LED
## cores hot enough to bloom.
func _draw_vibe_coder(direction: String, pose: String, frame_idx: int, palette: Dictionary = {}) -> Image:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# --- material ramps (shadow / base / light / rim) ---
	var hoodie := Color(0.22, 0.30, 0.47)
	var hoodie_hi := Color(0.31, 0.41, 0.60)
	var hoodie_sh := Color(0.14, 0.20, 0.34)
	var skin := Color(0.91, 0.76, 0.63)
	var hair := Color(0.19, 0.14, 0.11)
	var glow := Color(0.14, 0.94, 0.86)  # CYAN accent
	var show_phones := true
	var accessory := ""
	if not palette.is_empty():
		hoodie = palette.get("hoodie", hoodie)
		hoodie_hi = palette.get("hoodie_hi", hoodie_hi)
		hoodie_sh = palette.get("hoodie_sh", hoodie_sh)
		hair = palette.get("hair", hair)
		skin = palette.get("skin", skin)
		glow = palette.get("accent", glow)
		show_phones = palette.get("headphones", true)
		accessory = palette.get("accessory", "")
	var hoodie_rim := hoodie_hi.lightened(0.30)
	var skin_sh := skin.darkened(0.18)
	var skin_hi := skin.lightened(0.10)
	var hair_sh := hair.darkened(0.35)
	var hair_hi := hair.lightened(0.35)
	var jeans := Color(0.16, 0.19, 0.30)
	var jeans_sh := jeans.darkened(0.35)
	var jeans_hi := jeans.lightened(0.18)
	var shoe := Color(0.86, 0.87, 0.93)
	var shoe_hi := Color(0.95, 0.96, 1.0)   # near-white rim — blooms slightly
	var sole := Color(0.44, 0.40, 0.35)
	var cup := Color(0.09, 0.09, 0.13)
	var cup_hi := Color(0.20, 0.21, 0.28)
	var eye := Color(0.09, 0.07, 0.08)

	# --- gait: 4-frame walk = contact / passing / contact / passing.
	# 2px bounce on the passing frames; legs and arms counter-swing.
	var walk := pose == "walk"
	var bob := 0
	var stride := 0
	var arm_swing := 0
	if walk:
		var cyc := (frame_idx - 1) % 4  # sheet walk columns are 1..4
		var seq_stride: Array[int] = [3, 1, -3, -1]
		var seq_bob: Array[int] = [0, 2, 0, 2]
		var seq_arm: Array[int] = [3, 0, -3, 0]
		stride = seq_stride[cyc]
		bob = seq_bob[cyc]
		arm_swing = seq_arm[cyc]
	# the swinging leg lifts 1px on contact frames so the gait reads
	var lyo := -1 if stride >= 3 else 0
	var ryo := -1 if stride <= -3 else 0
	var facing_up := direction == "up"
	var facing_side := direction == "side"
	var cx := 32
	var hy := 15 + bob  # head center y
	var ty := 25 + bob  # torso top y

	# --- legs + sneakers (drawn first; torso overlaps the hips) ---
	var lx := cx - 7 + stride
	var rx := cx + 1 - stride
	_fill_rect(img, lx, 42 + lyo, 6, 12, jeans)
	_fill_rect(img, lx, 42 + lyo, 1, 12, jeans_hi)    # lit outer edge
	_fill_rect(img, lx + 4, 42 + lyo, 2, 12, jeans_sh)
	_fill_rect(img, lx, 47 + lyo, 6, 1, jeans_sh)     # knee crease
	_fill_rect(img, rx, 42 + ryo, 6, 12, jeans.darkened(0.10))
	_fill_rect(img, rx, 42 + ryo, 1, 12, jeans)
	_fill_rect(img, rx + 4, 42 + ryo, 2, 12, jeans_sh)
	_fill_rect(img, rx, 47 + ryo, 6, 1, jeans_sh)
	# white sneakers: rim-lit top, gum sole, one unlicensed swoosh pixel
	_fill_rect(img, lx - 1, 53 + lyo, 8, 3, shoe)
	_fill_rect(img, lx - 1, 53 + lyo, 8, 1, shoe_hi)
	_fill_rect(img, lx - 1, 56 + lyo, 8, 1, sole)
	img.set_pixel(lx, 54 + lyo, glow)
	_fill_rect(img, rx - 1, 53 + ryo, 8, 3, shoe)
	_fill_rect(img, rx - 1, 53 + ryo, 8, 1, shoe_hi)
	_fill_rect(img, rx - 1, 56 + ryo, 8, 1, sole)
	img.set_pixel(rx + 5, 54 + ryo, glow)

	# --- torso: hoodie with fold shading. Light hits the LEFT edge. ---
	_fill_rect(img, cx - 11, ty, 22, 19, hoodie)
	_fill_rect(img, cx - 11, ty, 3, 19, hoodie_hi)
	_fill_rect(img, cx + 8, ty, 3, 19, hoodie_sh)
	_dither_rect(img, cx - 8, ty + 2, 3, 16, hoodie_hi, hoodie)  # lit falloff
	_dither_rect(img, cx + 5, ty + 2, 3, 16, hoodie, hoodie_sh)  # shadow falloff
	_fill_rect(img, cx - 11, ty, 22, 1, hoodie_rim)              # top rim catch
	# fold creases where the fabric bunches above the pocket
	_draw_line_img(img, cx - 9, ty + 8, cx - 5, ty + 11, hoodie_sh)
	_draw_line_img(img, cx + 4, ty + 11, cx + 8, ty + 8, hoodie_sh)
	# kangaroo pocket: shadowed cavity with a lit top seam
	_fill_rect(img, cx - 6, ty + 11, 12, 6, hoodie_sh)
	_fill_rect(img, cx - 6, ty + 11, 12, 1, hoodie_hi)
	_fill_rect(img, cx - 6, ty + 16, 12, 1, hoodie_sh.darkened(0.3))
	# hood collar bunched behind the neck
	_fill_rect(img, cx - 7, ty - 2, 14, 4, hoodie_sh)
	_fill_rect(img, cx - 7, ty - 2, 14, 1, hoodie)
	if facing_up:
		# the hood hangs down the back, creased in the middle
		_fill_rect(img, cx - 6, ty + 1, 12, 7, hoodie_sh)
		_fill_rect(img, cx - 6, ty + 1, 12, 1, hoodie)
		_draw_line_img(img, cx, ty + 2, cx, ty + 7, hoodie_sh.darkened(0.25))
	else:
		# neon drawstrings with white-hot aglets (they bloom; he knows)
		img.set_pixel(cx - 2, ty + 2, glow)
		img.set_pixel(cx - 2, ty + 4, glow)
		img.set_pixel(cx - 2, ty + 6, WHITE_HOT)
		img.set_pixel(cx + 2, ty + 2, glow)
		img.set_pixel(cx + 2, ty + 4, glow)
		img.set_pixel(cx + 2, ty + 6, WHITE_HOT)

	# --- arms: sleeves with lit tops, ribbed cuffs, skin hands ---
	if facing_side:
		var ay := ty + 3 + arm_swing
		_fill_rect(img, cx + 6, ay, 5, 12, hoodie)
		_fill_rect(img, cx + 6, ay, 5, 1, hoodie_hi)
		_fill_rect(img, cx + 6, ay, 1, 12, hoodie_hi)
		_fill_rect(img, cx + 6, ay + 10, 5, 2, hoodie_sh)
		_fill_rect(img, cx + 6, ay + 12, 5, 3, skin)
		_fill_rect(img, cx + 6, ay + 14, 5, 1, skin_sh)
	else:
		var la := ty + 3 + arm_swing
		var ra := ty + 3 - arm_swing
		_fill_rect(img, cx - 14, la, 5, 12, hoodie)
		_fill_rect(img, cx - 14, la, 1, 12, hoodie_hi)
		_fill_rect(img, cx - 14, la, 5, 1, hoodie_rim)
		_fill_rect(img, cx - 14, la + 10, 5, 2, hoodie_sh)
		_fill_rect(img, cx - 14, la + 12, 5, 3, skin)
		_fill_rect(img, cx - 14, la + 14, 5, 1, skin_sh)
		_fill_rect(img, cx + 9, ra, 5, 12, hoodie.darkened(0.08))
		_fill_rect(img, cx + 9, ra, 5, 1, hoodie_hi)
		_fill_rect(img, cx + 9, ra + 10, 5, 2, hoodie_sh)
		_fill_rect(img, cx + 9, ra + 12, 5, 3, skin)
		_fill_rect(img, cx + 9, ra + 14, 5, 1, skin_sh)

	# --- head ---
	if facing_up:
		# back of the head: shaded hair dome + part line + band over it
		_shade_sphere(img, cx, hy, 8, hair)
		_draw_line_img(img, cx + 2, hy - 6, cx + 4, hy + 2, hair_sh)
		img.set_pixel(cx - 3, hy - 5, hair_hi)
		img.set_pixel(cx - 4, hy - 4, hair_hi)
		if show_phones:
			_fill_rect(img, cx - 10, hy - 2, 20, 3, cup)
			_fill_rect(img, cx - 10, hy - 2, 20, 1, cup_hi)
			_fill_circle(img, cx - 9, hy + 1, 3, cup)
			_fill_circle(img, cx + 9, hy + 1, 3, cup)
			_glow_core(img, cx - 9, hy + 2, glow)
			_glow_core(img, cx + 9, hy + 2, glow)
	else:
		_shade_sphere(img, cx, hy, 8, skin)
		# messy hair cap with an uneven fringe and lit streaks
		for x in range(cx - 9, cx + 10):
			for y in range(hy - 9, hy - 1):
				var hdx := float(x - cx) / 9.0
				var hdy := float(y - hy) / 9.0
				if hdx * hdx + hdy * hdy <= 1.0:
					img.set_pixel(x, y, hair)
		var fringe: Array[int] = [1, 0, 2, 0, 1, 2, 0, 1, 2, 0, 1, 0, 2]
		for i in 13:
			var fx := cx - 6 + i
			if img.get_pixel(fx, hy - 3).a > 0.0:
				for fy in fringe[i] + 1:
					img.set_pixel(fx, hy - 2 + fy, hair)
		img.set_pixel(cx - 5, hy - 8, hair_hi)
		img.set_pixel(cx - 6, hy - 7, hair_hi)
		img.set_pixel(cx - 3, hy - 9, hair_hi)
		img.set_pixel(cx - 7, hy - 5, hair_sh)
		# --- the face: tired but determined ---
		var ex_l := cx - 5
		var ex_r := cx + 2
		if facing_side:
			ex_l = cx + 1
			ex_r = cx + 1  # one visible eye in profile
			img.set_pixel(cx + 7, hy + 1, skin_sh)  # nose hint
		if pose == "blink" or pose == "hurt":
			_fill_rect(img, ex_l, hy, 3, 1, eye)
			if not facing_side:
				_fill_rect(img, ex_r, hy, 3, 1, eye)
		else:
			_fill_rect(img, ex_l, hy - 1, 3, 2, eye)
			img.set_pixel(ex_l, hy - 1, WHITE_HOT)               # catch-light
			_fill_rect(img, ex_l, hy - 2, 3, 1, hair_sh)         # heavy brow
			_fill_rect(img, ex_l, hy + 1, 3, 1, skin_sh.darkened(0.12))  # eye bag
			if not facing_side:
				_fill_rect(img, ex_r, hy - 1, 3, 2, eye)
				img.set_pixel(ex_r, hy - 1, WHITE_HOT)
				_fill_rect(img, ex_r, hy - 2, 3, 1, hair_sh)
				_fill_rect(img, ex_r, hy + 1, 3, 1, skin_sh.darkened(0.12))
		# a flat line of quiet determination
		_fill_rect(img, cx - 1 + (3 if facing_side else 0), hy + 4, 3, 1, skin_sh.darkened(0.2))
		img.set_pixel(cx - 6, hy + 2, skin_hi)  # cheek catch
		# headphones over the ears, LEDs blooming
		if show_phones:
			_fill_rect(img, cx - 10, hy - 6, 20, 2, cup)
			_fill_rect(img, cx - 10, hy - 6, 20, 1, cup_hi)
			_fill_circle(img, cx - 8, hy + 1, 3, cup)
			_fill_circle(img, cx + 8, hy + 1, 3, cup)
			img.set_pixel(cx - 9, hy - 1, cup_hi)
			img.set_pixel(cx + 7, hy - 1, cup_hi)
			_glow_core(img, cx - 8, hy + 1, glow)
			_glow_core(img, cx + 8, hy + 1, glow)

	# --- NPC accessories: one emissive accent each, per the bible ---
	if accessory == "tie" and not facing_up:
		for tyy in range(ty + 1, ty + 11):
			var tw := 2 if tyy < ty + 3 else 3
			_fill_rect(img, cx - tw / 2, tyy, tw, 1, Color(0.72, 0.13, 0.18))
		img.set_pixel(cx, ty + 2, Color(0.9, 0.3, 0.35))  # knot sheen
		_glow_core(img, cx + 6, ty + 3, glow)             # badge: clearance yes
	elif accessory == "glasses" and not facing_up:
		_fill_rect(img, cx - 6, hy - 1, 4, 3, Color(0.12, 0.13, 0.16))
		_fill_rect(img, cx + 2, hy - 1, 4, 3, Color(0.12, 0.13, 0.16))
		_fill_rect(img, cx - 2, hy, 4, 1, Color(0.12, 0.13, 0.16))
		img.set_pixel(cx - 5, hy, glow)        # monitor glare, permanent
		img.set_pixel(cx + 3, hy, WHITE_HOT)
	elif accessory == "hardhat":
		_fill_rect(img, cx - 9, hy - 8, 18, 4, Color(0.95, 0.62, 0.12))
		_fill_rect(img, cx - 7, hy - 10, 14, 2, Color(0.95, 0.62, 0.12))
		_fill_rect(img, cx - 9, hy - 5, 18, 1, Color(0.6, 0.38, 0.08))
		_fill_rect(img, cx - 7, hy - 10, 14, 1, Color(1.0, 0.78, 0.3))
		_glow_core(img, cx, hy - 9, Color(1.0, 0.85, 0.4))  # headlamp
	elif accessory == "circuit" and not facing_up:
		# a faint circuit trace across the hoodie, softly alive
		_draw_line_img(img, cx + 2, ty + 9, cx + 6, ty + 9, glow.darkened(0.4))
		_draw_line_img(img, cx + 6, ty + 9, cx + 6, ty + 7, glow.darkened(0.4))
		_glow_core(img, cx + 6, ty + 6, glow)

	# --- pose props ---
	if pose == "phone":
		_fill_rect(img, cx + 6, ty + 5, 6, 10, Color(0.10, 0.10, 0.15))
		_fill_rect(img, cx + 7, ty + 6, 4, 7, glow.darkened(0.55))
		_fill_rect(img, cx + 7, ty + 7, 4, 1, glow.darkened(0.25))  # doomscroll
		_fill_rect(img, cx + 7, ty + 9, 3, 1, glow.darkened(0.25))
		_glow_core(img, cx + 9, ty + 12, glow)  # a notification he will not answer
	elif pose == "laptop":
		_fill_rect(img, cx - 10, ty + 6, 20, 13, Color(0.07, 0.09, 0.13))
		_fill_rect(img, cx - 10, ty + 6, 20, 1, Color(0.18, 0.22, 0.30))
		_fill_rect(img, cx - 9, ty + 7, 18, 11, Color(0.05, 0.07, 0.10))
		# code that is definitely fine
		for lrow in 5:
			var ly := ty + 8 + lrow * 2
			var lw := 4 + ((lrow * 7 + frame_idx * 3) % 10)
			var lcol := glow.darkened(0.30) if lrow % 2 == 0 else Color(0.55, 0.36, 0.95)
			_fill_rect(img, cx - 8, ly, lw, 1, lcol)
		img.set_pixel(cx + 5, ty + 16, WHITE_HOT)  # cursor, blinking in spirit
		if not facing_up:
			_fill_rect(img, cx - 3, hy + 3, 7, 1, skin_hi.lerp(glow, 0.25))  # screen light on the face
	elif pose == "panic":
		# hands up; the deploy was on a Friday
		_fill_rect(img, cx - 14, ty - 4, 4, 8, hoodie)
		_fill_rect(img, cx + 10, ty - 4, 4, 8, hoodie)
		_fill_rect(img, cx - 14, ty - 7, 4, 3, skin)
		_fill_rect(img, cx + 10, ty - 7, 4, 3, skin)
		for i in 3:
			img.set_pixel(cx - 10 + i * 9, hy - 12, Color(0.45, 0.75, 1.0, 0.45))
			img.set_pixel(cx - 12 + i * 10, hy - 10, Color(0.45, 0.75, 1.0, 0.3))
		_fill_rect(img, cx - 1, hy + 3, 3, 3, Color(0.25, 0.1, 0.1))  # mouth agape
	elif pose == "celebrate":
		# fist up + confetti nobody will sweep
		_fill_rect(img, cx + 10, ty - 8, 4, 12, hoodie)
		_fill_rect(img, cx + 10, ty - 8, 1, 12, hoodie_hi)
		_fill_rect(img, cx + 10, ty - 11, 4, 4, skin)
		var confetti: Array[Color] = [Color(1, 0.83, 0.3), Color(0.14, 0.94, 0.86), Color(1, 0.18, 0.58)]
		for i in 6:
			img.set_pixel(cx - 12 + ((i * 47) % 26), hy - 14 + ((i * 31) % 7), confetti[i % 3])
	elif pose == "coffee":
		_fill_rect(img, cx + 11, ty + 5, 6, 8, Color(0.82, 0.35, 0.14))
		_fill_rect(img, cx + 11, ty + 5, 6, 1, Color(0.95, 0.5, 0.24))
		_fill_rect(img, cx + 16, ty + 7, 2, 3, Color(0.62, 0.26, 0.10))  # handle
		img.set_pixel(cx + 12, ty + 5, WHITE_HOT)  # rim glint
		img.set_pixel(cx + 13, ty + 2, Color(0.85, 0.9, 1.0, 0.45))  # steam
		img.set_pixel(cx + 14, ty, Color(0.85, 0.9, 1.0, 0.3))
		img.set_pixel(cx + 13, ty - 2, Color(0.85, 0.9, 1.0, 0.18))

	# rim light along the top-left silhouette in the accent color, then the
	# 1px dark outline that makes it all read at gameplay zoom
	_rim_light_pass(img, glow, 0.45)
	_outline_silhouette(img, OUTLINE_COLOR)

	if pose == "hurt":
		for y in 64:
			for x in 64:
				var p := img.get_pixel(x, y)
				if p.a > 0:
					img.set_pixel(x, y, p.lerp(Color(0.95, 0.25, 0.3), 0.45))
	return img

## Add a 1px dark outline around the whole silhouette — the single biggest
## readability upgrade for small pixel-art characters. Semi-transparent
## pixels (halos, auras, steam) don't get outlined; they stay soft.
func _outline_silhouette(img: Image, color: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var src: Image = img.duplicate()
	for x in w:
		for y in h:
			if src.get_pixel(x, y).a > 0.05:
				continue
			var touching := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + int(d.x)
				var ny: int = y + int(d.y)
				if nx >= 0 and ny >= 0 and nx < w and ny < h and src.get_pixel(nx, ny).a > 0.5:
					touching = true
					break
			if touching:
				img.set_pixel(x, y, color)

func _generate_player_sprites() -> void:
	pass

func _generate_tileset() -> void:
	# 64x64 canvas = a 2x2 block of 32px floor plates, seamless at the edges.
	# Base values sit near bible BASE/SURFACE tinted per region; the accent is
	# the region neon. "_b" variants exist so builders can break repetition.
	var regions := {
		"localhost": {"base": Color(0.075, 0.07, 0.12), "accent": Color(1.0, 0.72, 0.29)},
		"dependency": {"base": Color(0.07, 0.09, 0.07), "accent": Color(0.66, 1.0, 0.24)},
		"stackoverflow": {"base": Color(0.10, 0.09, 0.07), "accent": Color(0.91, 0.77, 0.42)},
		"api_bazaar": {"base": Color(0.09, 0.06, 0.10), "accent": Color(1.0, 0.18, 0.58)},
		"cloud": {"base": Color(0.07, 0.09, 0.14), "accent": Color(0.42, 0.78, 1.0)},
		"opensource": {"base": Color(0.06, 0.10, 0.07), "accent": Color(0.35, 0.88, 0.49)},
		"corporate": {"base": Color(0.08, 0.09, 0.13), "accent": Color(0.30, 0.49, 1.0)},
		"gpu": {"base": Color(0.11, 0.07, 0.06), "accent": Color(1.0, 0.42, 0.18)},
		"production": {"base": Color(0.11, 0.05, 0.06), "accent": Color(1.0, 0.28, 0.34)},
		"vault": {"base": Color(0.10, 0.08, 0.05), "accent": Color(1.0, 0.83, 0.30)},
	}
	for rname in regions:
		var data: Dictionary = regions[rname]
		_save_image(_make_floor_tile(rname, data, 0), "tile_%s.png" % rname)
		_save_image(_make_floor_tile(rname, data, 7), "tile_%s_b.png" % rname)

## One seamless floor texture: hash noise (tiles by construction), per-plate
## value jitter, beveled 32px seams, hairline scratches, and a rare subtle
## detail per plate. Low contrast on purpose — this repeats everywhere.
func _make_floor_tile(rname: String, data: Dictionary, salt: int) -> Image:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var base: Color = data["base"]
	var accent: Color = data["accent"]
	var tseed: int = abs(rname.hash() % 100000) + salt * 977
	for x in 64:
		for y in 64:
			var n := (_hash01(x, y, tseed) - 0.5) * 0.05
			var cell := (x / 32) + (y / 32) * 2
			var cj := (_hash01(cell, 11, tseed) - 0.5) * 0.08  # bible: +-4% per plate
			var t := n + cj
			var c := base.lightened(t) if t > 0.0 else base.darkened(-t)
			var mx := x % 32
			var my := y % 32
			if mx == 0 or my == 0:
				c = c.darkened(0.35)      # plate seam
			elif mx == 1 or my == 1:
				c = c.lightened(0.06)     # bevel catches the light (top-left)
			elif mx == 31 or my == 31:
				c = c.darkened(0.12)      # far bevel falls into shadow
			img.set_pixel(x, y, c)
	# hairline scratches, kept inside plates so seams stay clean
	for i in 6:
		var sx := int(_hash01(i, 3, tseed) * 56.0) + 3
		var sy := int(_hash01(i, 5, tseed) * 56.0) + 3
		var slen := 4 + int(_hash01(i, 7, tseed) * 8.0)
		var horiz := _hash01(i, 9, tseed) > 0.5
		for j in slen:
			var px := sx + (j if horiz else j / 3)
			var py := sy + (j / 3 if horiz else j)
			if px < 63 and py < 63 and px % 32 != 0 and py % 32 != 0:
				img.set_pixel(px, py, img.get_pixel(px, py).darkened(0.25))
	# occasional plate detail (vent / crack / faded glyph). Subtle: it repeats.
	for cy in 2:
		for cx in 2:
			if _hash01(cx * 31 + cy * 57, 13, tseed) > 0.30:
				continue
			_tile_detail(img, cx * 32, cy * 32, accent, base, _hash01(cx, cy + 19, tseed))
	return img

func _tile_detail(img: Image, ox: int, oy: int, accent: Color, base: Color, roll: float) -> void:
	var dxp := ox + 8 + int(roll * 14.0)
	var dyp := oy + 8 + int(roll * 11.0)
	if roll < 0.34:
		# vent: three dark slits, each with a faint lit lip
		for i in 3:
			_fill_rect(img, dxp, dyp + i * 2, 8, 1, base.darkened(0.5))
			img.set_pixel(dxp, dyp + i * 2, base.lightened(0.10))
	elif roll < 0.67:
		# hairline crack wandering down-right
		var px := dxp
		var py := dyp
		for i in 7:
			img.set_pixel(mini(px, 63), mini(py, 63), base.darkened(0.45))
			if _hash01(px, py, i) > 0.4:
				px += 1
			py += 1
	else:
		# a faded accent glyph — a maintenance mark nobody remembers painting
		var dim := base.lerp(accent, 0.22)
		_fill_rect(img, dxp, dyp, 5, 1, dim)
		_fill_rect(img, dxp, dyp, 1, 4, dim)
		img.set_pixel(dxp + 4, dyp + 3, base.lerp(accent, 0.35))

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
		elif ename == "rate_limiter":
			_draw_rate_limiter(img, c)
		elif ename == "memory_leak":
			_draw_memory_leak(img, c)
		elif ename == "merge_conflict":
			_draw_merge_conflict(img, c)
		elif ename == "scope_creep":
			_draw_scope_creep(img, c)
		elif ename == "dependency_demon":
			_draw_dependency_demon(img, c)
		elif ename == "hallucination":
			_draw_hallucination(img, c)
		elif ename == "legacy_monolith":
			_draw_legacy_monolith(img, c)
		elif ename == "infinite_context":
			_draw_infinite_context(img, c)
		elif ename == "enterprise_architect":
			_draw_enterprise_architect(img, c)
		elif ename == "null_reference":
			_draw_null_reference(img, c)
		elif ename == "legacy_system":
			_draw_legacy_system(img, c)
		elif ename == "cloud_bill":
			_draw_cloud_bill(img, c)
		else:
			_draw_glow_blob(img, c)
		# every enemy gets the bible finish: accent rim light + 1px outline
		_rim_light_pass(img, c.lightened(0.45), 0.4)
		_outline_silhouette(img, OUTLINE_COLOR)
		_save_image(img, "enemy_%s.png" % ename)

## A software "bug" that actually reads as a beetle: 4-tone shell lit from the
## top-left, jointed legs, a cracked elytron, and eyes that bloom amber.
func _draw_bug(img: Image, _c: Color) -> void:
	var shell := Color(0.52, 0.13, 0.17)
	var shell_hi := Color(0.72, 0.24, 0.26)
	var shell_sh := Color(0.32, 0.07, 0.11)
	var carapace := Color(0.15, 0.09, 0.12)
	var leg := Color(0.07, 0.05, 0.07)
	# legs first (body overlaps their roots), with knee joints
	for sy in [12, 17, 22]:
		_draw_line_img(img, 12, sy, 5, sy - 4, leg)
		_draw_line_img(img, 5, sy - 4, 3, sy - 2, leg)
		_draw_line_img(img, 20, sy, 27, sy - 4, leg)
		_draw_line_img(img, 27, sy - 4, 29, sy - 2, leg)
	# abdomen: offset-layered ellipses build the top-left ramp
	_fill_ellipse(img, 16, 18, 9, 11, shell_sh)
	_fill_ellipse(img, 15, 17, 8, 10, shell)
	_fill_ellipse(img, 13, 15, 5, 6, shell_hi)
	_dither_rect(img, 10, 20, 8, 4, shell, shell_sh, true)
	# elytra split + segment ridges following the shell curve
	for y in range(8, 29):
		img.set_pixel(16, y, carapace)
	for ry in [13, 17, 21, 25]:
		for x in range(8, 25):
			if Vector2(x - 16, ry - 18).length() < 9.5 and img.get_pixel(x, ry).a > 0.0:
				img.set_pixel(x, ry, shell_sh)
	# a crack in the shell — it has seen some sprints
	_draw_line_img(img, 20, 14, 23, 18, carapace)
	# head, mandibles, antennae
	_fill_circle(img, 16, 7, 5, carapace)
	_fill_circle(img, 14, 6, 2, Color(0.26, 0.17, 0.20))
	_draw_line_img(img, 13, 3, 11, 1, leg)
	_draw_line_img(img, 19, 3, 21, 1, leg)
	_draw_line_img(img, 14, 3, 10, 0, leg)
	_draw_line_img(img, 18, 3, 22, 0, leg)
	img.set_pixel(10, 0, Color(1.0, 0.85, 0.2))
	img.set_pixel(22, 0, Color(1.0, 0.85, 0.2))
	# glowing eyes: white-hot cores in amber halos
	_glow_core(img, 13, 7, Color(1.0, 0.72, 0.15))
	_glow_core(img, 19, 7, Color(1.0, 0.72, 0.15))

## A rate limiter: a hazard-striped gate with a STOP light mid-tantrum.
func _draw_rate_limiter(img: Image, c: Color) -> void:
	var post := Color(0.20, 0.21, 0.26)
	var post_hi := Color(0.33, 0.35, 0.42)
	var post_sh := Color(0.11, 0.12, 0.16)
	for px in [5, 23]:
		_fill_rect(img, px, 5, 4, 23, post)
		_fill_rect(img, px, 5, 1, 23, post_hi)
		_fill_rect(img, px + 3, 5, 1, 23, post_sh)
		_fill_rect(img, px - 1, 27, 6, 2, post_sh)
	# barrier arms: diagonal amber/dark stripes, beveled top and bottom
	for i in 3:
		var by := 9 + i * 6
		for x in range(9, 23):
			for y in range(by, by + 4):
				var stripe := int(floor(float(x - y) / 3.0)) % 2 == 0
				var col := c if stripe else Color(0.13, 0.13, 0.16)
				if y == by:
					col = col.lightened(0.2)
				elif y == by + 3:
					col = col.darkened(0.3)
				img.set_pixel(x, y, col)
	# status LEDs down one post — currently all yelling
	for i in 3:
		img.set_pixel(24, 8 + i * 7, Color(1.0, 0.35, 0.3))
	# the STOP light
	_fill_circle(img, 16, 4, 3, Color(0.55, 0.10, 0.12))
	_fill_circle(img, 16, 4, 2, Color(0.95, 0.2, 0.2))
	_glow_core(img, 15, 3, Color(1.0, 0.45, 0.4))

## A memory leak: a gel blob, top-left lit, dripping with quiet guilt.
func _draw_memory_leak(img: Image, c: Color) -> void:
	var hi := c.lightened(0.30)
	var sh := c.darkened(0.35)
	_fill_circle(img, 16, 12, 9, sh)
	_fill_circle(img, 15, 11, 8, c)
	_fill_circle(img, 13, 9, 4, hi)
	_dither_rect(img, 10, 14, 12, 4, c, sh, true)
	# drips with a lit streak and gravity ambitions
	var drip_x: Array[int] = [10, 16, 22]
	var drip_h: Array[int] = [7, 10, 5]
	for i in 3:
		_fill_rect(img, drip_x[i] - 1, 18, 3, drip_h[i], c.darkened(0.12))
		_fill_rect(img, drip_x[i] - 1, 18, 1, drip_h[i], c.lightened(0.10))
		_fill_circle(img, drip_x[i], 18 + drip_h[i], 2, sh)
		img.set_pixel(drip_x[i], 18 + drip_h[i], hi)  # hot bead at the tip
	# eyes: it knows what it did
	_fill_circle(img, 13, 10, 2, Color.WHITE)
	_fill_circle(img, 19, 10, 2, Color.WHITE)
	_fill_circle(img, 13, 11, 1, Color(0.05, 0.08, 0.15))
	_fill_circle(img, 19, 11, 1, Color(0.05, 0.08, 0.15))
	img.set_pixel(12, 9, WHITE_HOT)
	img.set_pixel(18, 9, WHITE_HOT)

## A merge conflict: two shaded halves that refuse to rebase, with white-hot
## friction sparks along the seam.
func _draw_merge_conflict(img: Image, _c: Color) -> void:
	var left := Color(0.85, 0.30, 0.25)
	var right := Color(0.30, 0.50, 0.85)
	_fill_circle(img, 16, 16, 12, left.darkened(0.3))
	_fill_circle(img, 15, 15, 11, left)
	_fill_circle(img, 12, 12, 4, left.lightened(0.25))
	for x in 32:
		for y in 32:
			var seam := 16 + int(sin(y * 0.6) * 1.5)
			if x > seam and Vector2(x - 16, y - 16).length() <= 12.0:
				var col := right
				if x > seam + 6 or y > 22:
					col = right.darkened(0.3)
				elif y < 10:
					col = right.lightened(0.15)
				img.set_pixel(x, y, col)
	# chevrons down the seam
	for y in range(6, 27, 5):
		img.set_pixel(15, y, Color(0.08, 0.08, 0.1))
		img.set_pixel(17, y, Color(0.08, 0.08, 0.1))
	_glow_core(img, 16, 10, Color(1.0, 0.75, 0.3))
	_glow_core(img, 16, 20, Color(1.0, 0.75, 0.3))
	# one eye per faction, glaring inward
	_fill_circle(img, 11, 14, 2, Color.WHITE)
	_fill_circle(img, 21, 14, 2, Color.WHITE)
	img.set_pixel(12, 14, Color(0.1, 0.05, 0.05))
	img.set_pixel(20, 14, Color(0.05, 0.05, 0.1))

## Scope creep: a lit amoeba whose pseudopods are already reaching for the
## next sprint. Tips glow — that's where the new requirements grow.
func _draw_scope_creep(img: Image, c: Color) -> void:
	var hi := c.lightened(0.3)
	var sh := c.darkened(0.35)
	var dirs: Array[Vector2] = [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0), Vector2(0.7, -0.7), Vector2(-0.7, 0.7)]
	for a in dirs:
		var tip := Vector2(16, 16) + a * 14.0
		_draw_line_img(img, 16 + int(a.x * 6.0), 16 + int(a.y * 6.0), int(tip.x), int(tip.y), c.darkened(0.15))
		_fill_circle(img, int(tip.x), int(tip.y), 2, c)
		img.set_pixel(int(tip.x), int(tip.y), hi)
	_fill_circle(img, 16, 16, 8, sh)
	_fill_circle(img, 15, 15, 7, c)
	_fill_circle(img, 13, 13, 3, hi)
	_dither_rect(img, 12, 18, 9, 4, c, sh, true)
	# organelles (absorbed tickets)
	img.set_pixel(19, 18, sh)
	img.set_pixel(12, 19, sh)
	img.set_pixel(18, 12, sh)
	# nucleus eyes
	_fill_circle(img, 13, 15, 2, Color.WHITE)
	_fill_circle(img, 19, 15, 2, Color.WHITE)
	img.set_pixel(13, 15, Color(0.05, 0.15, 0.05))
	img.set_pixel(19, 15, Color(0.05, 0.15, 0.05))

## Dependency demon: a horned knot whose strands kink like the real graph.
## Every node at the tips is Someone Else's Package.
func _draw_dependency_demon(img: Image, c: Color) -> void:
	var sh := c.darkened(0.4)
	var hi := c.lightened(0.25)
	for i in 8:
		var ang := TAU * float(i) / 8.0 + 0.2
		var d := Vector2(cos(ang), sin(ang))
		var tip := Vector2(16, 16) + d * 14.0
		var mid := Vector2(16, 16) + d * 9.0 + Vector2(-d.y, d.x) * 2.0
		_draw_line_img(img, 16, 16, int(mid.x), int(mid.y), sh)
		_draw_line_img(img, int(mid.x), int(mid.y), int(tip.x), int(tip.y), sh)
		_fill_circle(img, int(tip.x), int(tip.y), 2, c.darkened(0.15))
		img.set_pixel(int(tip.x), int(tip.y), hi)
	_fill_circle(img, 16, 16, 7, sh)
	_fill_circle(img, 15, 15, 6, c)
	_fill_circle(img, 13, 13, 3, hi)
	# horns
	_draw_line_img(img, 12, 10, 10, 6, sh)
	_draw_line_img(img, 20, 10, 22, 6, sh)
	# version-mismatch amber eyes, white-hot cores
	_glow_core(img, 13, 14, Color(1.0, 0.85, 0.25))
	_glow_core(img, 19, 14, Color(1.0, 0.85, 0.25))
	# jagged grin
	for gx in range(13, 20, 2):
		img.set_pixel(gx, 19, Color(0.05, 0.02, 0.04))
		img.set_pixel(gx + 1, 18, Color(0.05, 0.02, 0.04))

## Hallucination: a confident ghost with too many eyes, glitching at the
## edges. Semi-transparent so the world shows through its certainty.
func _draw_hallucination(img: Image, c: Color) -> void:
	var body := Color(c.r, c.g, c.b, 0.88)
	var body_sh := Color(c.r * 0.7, c.g * 0.6, c.b * 0.8, 0.88)
	var body_hi := Color(minf(c.r * 1.15, 1.0), minf(c.g * 1.2, 1.0), minf(c.b * 1.1, 1.0), 0.92)
	_fill_circle(img, 16, 14, 10, body_sh)
	_fill_circle(img, 15, 13, 9, body)
	_fill_circle(img, 13, 10, 4, body_hi)
	_fill_rect(img, 6, 14, 20, 12, body)
	_fill_rect(img, 6, 14, 2, 12, body_hi)
	_fill_rect(img, 24, 14, 2, 12, body_sh)
	# wavy hem
	for x in range(6, 26, 4):
		_fill_circle(img, x + 2, 26, 2, Color(0, 0, 0, 0))
	# too many eyes, all sincere
	var eyes: Array[Vector2i] = [Vector2i(12, 12), Vector2i(20, 12), Vector2i(16, 18)]
	for e in eyes:
		_fill_circle(img, e.x, e.y, 2, Color(0.95, 0.92, 1.0))
		img.set_pixel(e.x, e.y, Color(0.35, 0.1, 0.4))
		img.set_pixel(e.x - 1, e.y - 1, WHITE_HOT)
	# glitch tears: neon slice + white-hot sliver offset below it
	_fill_rect(img, 4, 9, 24, 1, Color(0.30, 1.0, 0.9, 0.75))
	_fill_rect(img, 3, 10, 10, 1, Color(0.95, 0.97, 1.0, 0.45))
	_fill_rect(img, 4, 20, 24, 1, Color(1.0, 0.4, 0.9, 0.75))
	_fill_rect(img, 19, 21, 9, 1, Color(0.95, 0.97, 1.0, 0.45))

## THE LEGACY MONOLITH: a towering brick slab with per-brick value jitter,
## structural cracks, dithered moss, and COBOL runes that still glow.
func _draw_legacy_monolith(img: Image, _c: Color) -> void:
	var brick := Color(0.34, 0.30, 0.28)
	var mortar := brick.darkened(0.45)
	_fill_rect(img, 3, 2, 26, 28, brick)
	# offset brick rows, each brick hashed a little lighter or darker
	for row in range(2, 30, 5):
		var off := 0 if ((row - 2) / 5) % 2 == 0 else 4
		for bx in range(off - 5, 29, 8):
			var jit := _hash01(bx + 40, row) - 0.5
			var bcol := brick.lightened(jit * 0.16) if jit > 0.0 else brick.darkened(-jit * 0.16)
			_fill_rect(img, maxi(bx + 1, 3), row + 1, 7, 4, bcol)
			_fill_rect(img, maxi(bx + 1, 3), row + 1, 7, 1, bcol.lightened(0.10))  # lit brick top
		_fill_rect(img, 3, row, 26, 1, mortar)
		for bx2 in range(3 + off, 29, 8):
			_fill_rect(img, bx2, row, 1, 5, mortar)
	# cracks with a dogleg, like real structural despair
	_draw_line_img(img, 10, 3, 12, 14, Color(0.10, 0.09, 0.08))
	_draw_line_img(img, 12, 14, 14, 28, Color(0.10, 0.09, 0.08))
	_draw_line_img(img, 22, 5, 20, 16, Color(0.10, 0.09, 0.08))
	_draw_line_img(img, 20, 16, 18, 27, Color(0.10, 0.09, 0.08))
	# glowing COBOL runes: acid green with white-hot hearts
	var rune := Color(0.4, 0.95, 0.5)
	_fill_rect(img, 13, 12, 6, 2, rune)
	_fill_rect(img, 15, 10, 2, 8, rune)
	_glow_core(img, 16, 13, rune)
	_fill_rect(img, 8, 22, 2, 4, rune.darkened(0.2))  # second rune, dimmer
	img.set_pixel(8, 23, WHITE_HOT)
	# moss clings to the top, dithered, creeping down the lit side
	_dither_rect(img, 3, 2, 26, 2, Color(0.30, 0.50, 0.30), Color(0.22, 0.38, 0.24))
	_dither_rect(img, 3, 4, 10, 1, Color(0.30, 0.50, 0.30), brick)
	# the left edge catches the light
	_fill_rect(img, 3, 2, 1, 28, brick.lightened(0.18))

## THE INFINITE CONTEXT: hue-drifting rings around an eye that has read
## everything you ever typed, including the deleted parts.
func _draw_infinite_context(img: Image, c: Color) -> void:
	for r in range(14, 3, -3):
		var t := float(r) / 14.0
		var ring := c.lerp(Color(0.3, 0.7, 1.0), 1.0 - t).darkened(0.15 * t)
		_draw_circle_outline(img, 16, 16, r, ring)
	# swirl arms with offset roots, spiraling inward
	for a in range(0, 360, 60):
		var rad := deg_to_rad(a)
		var tip := Vector2(16, 16) + Vector2(cos(rad), sin(rad)) * 13.0
		var midp := Vector2(16, 16) + Vector2(cos(rad + 0.5), sin(rad + 0.5)) * 8.0
		_draw_line_img(img, int(midp.x), int(midp.y), int(tip.x), int(tip.y), c.darkened(0.25))
	# the eye
	_fill_circle(img, 16, 16, 5, Color(0.90, 0.92, 1.0))
	_fill_circle(img, 16, 16, 3, c)
	_fill_circle(img, 17, 17, 2, c.darkened(0.35))
	_fill_circle(img, 16, 16, 1, Color(0.02, 0.02, 0.05))
	img.set_pixel(14, 14, WHITE_HOT)

## THE ENTERPRISE ARCHITECT: a tailored suit, a power tie, an access badge,
## and an aura of governance that fades with distance (unlike the meetings).
func _draw_enterprise_architect(img: Image, c: Color) -> void:
	# governance aura: concentric compliance at low alpha (stays un-outlined)
	_draw_rect_outline(img, 2, 2, 28, 28, Color(c.r, c.g, minf(c.b + 0.2, 1.0), 0.30))
	_draw_rect_outline(img, 5, 5, 22, 22, Color(c.r, c.g, minf(c.b + 0.2, 1.0), 0.45))
	var suit := Color(0.15, 0.17, 0.27)
	var suit_hi := Color(0.23, 0.26, 0.38)
	var suit_sh := Color(0.09, 0.10, 0.17)
	var skin := Color(0.86, 0.72, 0.60)
	# head, with a haircut that costs more than your GPU
	_shade_sphere(img, 16, 8, 5, skin)
	_fill_rect(img, 11, 3, 10, 3, Color(0.24, 0.24, 0.28))
	_fill_rect(img, 11, 3, 10, 1, Color(0.34, 0.34, 0.40))  # gel highlight
	img.set_pixel(14, 8, Color(0.08, 0.08, 0.10))
	img.set_pixel(18, 8, Color(0.08, 0.08, 0.10))
	# suit torso: lit left lapel, shadowed right
	_fill_rect(img, 9, 13, 14, 16, suit)
	_fill_rect(img, 9, 13, 2, 16, suit_hi)
	_fill_rect(img, 21, 13, 2, 16, suit_sh)
	_draw_line_img(img, 13, 13, 16, 18, suit_sh)  # lapel V
	_draw_line_img(img, 19, 13, 16, 18, suit_sh)
	_fill_rect(img, 14, 13, 4, 2, Color(0.93, 0.94, 0.97))  # collar
	# the power tie, silk sheen included
	for tyy in range(14, 27):
		var w := 1 + (tyy - 14) / 6
		var tie := Color(0.78, 0.14, 0.20) if tyy % 4 != 0 else Color(0.60, 0.10, 0.16)
		_fill_rect(img, 16 - w / 2, tyy, maxi(1, w), 1, tie)
	img.set_pixel(16, 14, Color(0.95, 0.35, 0.4))
	# arms
	_fill_rect(img, 6, 14, 3, 11, suit)
	_fill_rect(img, 6, 14, 1, 11, suit_hi)
	_fill_rect(img, 23, 14, 3, 11, suit_sh)
	# access badge — clearance level: yes
	_glow_core(img, 12, 17, Color(0.35, 0.65, 1.0))

## NULL REFERENCE: the ghost of a value that was promised and never
## delivered. Hollow where the face should be; asks one question, forever.
func _draw_null_reference(img: Image, c: Color) -> void:
	var body := Color(c.r, c.g, c.b, 0.9)
	var body_sh := body.darkened(0.35)
	var body_hi := body.lightened(0.25)
	# hooded wisp with a tapering tail
	_fill_circle(img, 16, 13, 9, body_sh)
	_fill_circle(img, 15, 12, 8, body)
	_fill_circle(img, 13, 10, 3, body_hi)
	var wob: Array[int] = [0, -2, 1, -1, 0]
	for i in 5:
		_fill_circle(img, 16 + wob[i], 22 + i * 2, 5 - i, body_sh if i % 2 == 0 else body)
	# the void where a face should be
	_fill_circle(img, 16, 12, 5, Color(0.02, 0.02, 0.05))
	# a question mark, glowing violet, white-hot dot
	var q := Color(0.75, 0.55, 1.0)
	_fill_rect(img, 14, 9, 3, 1, q)
	img.set_pixel(17, 10, q)
	img.set_pixel(16, 11, q)
	img.set_pixel(16, 12, q)
	_glow_core(img, 16, 15, q)

## LEGACY SYSTEM: a beige tower PC that predates several of your coworkers.
## Still on. Nobody knows what it runs. Nobody dares turn it off.
func _draw_legacy_system(img: Image, _c: Color) -> void:
	var beige := Color(0.55, 0.52, 0.44)
	var beige_hi := Color(0.68, 0.65, 0.56)
	var beige_sh := Color(0.38, 0.36, 0.30)
	_fill_rect(img, 8, 3, 16, 27, beige)
	_fill_rect(img, 8, 3, 2, 27, beige_hi)
	_fill_rect(img, 22, 3, 2, 27, beige_sh)
	_fill_rect(img, 8, 3, 16, 1, beige_hi.lightened(0.15))
	# dust on top — untouched since the last reorg
	_dither_rect(img, 9, 4, 14, 2, Color(0.62, 0.60, 0.55), beige)
	# CRT-green status screen with scanline text
	_fill_rect(img, 11, 7, 10, 8, Color(0.04, 0.08, 0.05))
	for lrow in 3:
		_fill_rect(img, 12, 9 + lrow * 2, 4 + (lrow * 3) % 5, 1, Color(0.35, 0.9, 0.45))
	_glow_core(img, 13, 9, Color(0.5, 1.0, 0.55))  # the blinking cursor of doom
	# floppy slot + eject button
	_fill_rect(img, 11, 18, 10, 2, beige_sh)
	_fill_rect(img, 11, 18, 10, 1, Color(0.1, 0.1, 0.1))
	img.set_pixel(20, 19, Color(0.75, 0.72, 0.65))
	# vents
	for vy in range(22, 28, 2):
		_fill_rect(img, 11, vy, 10, 1, beige_sh.darkened(0.2))
	# power LED: amber, eternal
	_glow_core(img, 10, 26, Color(1.0, 0.7, 0.15))
	# rust drip below the case seam
	_draw_line_img(img, 23, 12, 23, 17, Color(0.45, 0.28, 0.15))

## CLOUD BILL: a serene little cumulus delivering a number with too many
## digits. It knows you auto-renewed.
func _draw_cloud_bill(img: Image, c: Color) -> void:
	var cl := Color(0.88, 0.92, 0.98)
	var cl_sh := Color(0.62, 0.68, 0.82)
	var cl_hi := Color(0.97, 0.98, 1.0)
	# lumpy cumulus, lit top-left
	_fill_circle(img, 11, 12, 6, cl_sh)
	_fill_circle(img, 20, 12, 7, cl_sh)
	_fill_circle(img, 15, 8, 6, cl_sh)
	_fill_circle(img, 10, 11, 5, cl)
	_fill_circle(img, 19, 11, 6, cl)
	_fill_circle(img, 14, 7, 5, cl)
	_fill_circle(img, 12, 6, 3, cl_hi)
	_fill_rect(img, 6, 13, 21, 4, cl)
	_fill_rect(img, 6, 16, 21, 1, cl_sh)
	# serene eyes
	img.set_pixel(13, 11, Color(0.1, 0.12, 0.2))
	img.set_pixel(19, 11, Color(0.1, 0.12, 0.2))
	# the dollar sign, dependency green, glowing
	var d := c
	_fill_rect(img, 14, 19, 5, 1, d)
	_fill_rect(img, 13, 20, 1, 2, d)
	_fill_rect(img, 14, 22, 5, 1, d)
	_fill_rect(img, 19, 23, 1, 2, d)
	_fill_rect(img, 14, 25, 5, 1, d)
	_fill_rect(img, 16, 18, 1, 9, d.lightened(0.2))
	_glow_core(img, 16, 22, d.lightened(0.3))
	# tiny red decimals, raining
	img.set_pixel(9, 20, Color(1.0, 0.3, 0.3, 0.8))
	img.set_pixel(24, 21, Color(1.0, 0.3, 0.3, 0.8))
	img.set_pixel(11, 26, Color(1.0, 0.3, 0.3, 0.6))

## Fallback for enemy types without bespoke art: a shaded blob with attitude.
func _draw_glow_blob(img: Image, c: Color) -> void:
	_fill_circle(img, 16, 16, 12, c.darkened(0.35))
	_fill_circle(img, 15, 15, 11, c)
	_fill_circle(img, 12, 12, 5, c.lightened(0.25))
	_fill_circle(img, 12, 13, 3, Color.WHITE)
	_fill_circle(img, 20, 13, 3, Color.WHITE)
	_fill_circle(img, 12, 13, 1, Color.BLACK)
	_fill_circle(img, 20, 13, 1, Color.BLACK)
	img.set_pixel(11, 12, WHITE_HOT)
	img.set_pixel(19, 12, WHITE_HOT)

func _draw_rect_outline(img: Image, x: int, y: int, w: int, h: int, col: Color) -> void:
	for i in range(x, x + w):
		if i >= 0 and i < img.get_width():
			if y >= 0 and y < img.get_height():
				img.set_pixel(i, y, col)
			if y + h - 1 >= 0 and y + h - 1 < img.get_height():
				img.set_pixel(i, y + h - 1, col)
	for j in range(y, y + h):
		if j >= 0 and j < img.get_height():
			if x >= 0 and x < img.get_width():
				img.set_pixel(x, j, col)
			if x + w - 1 >= 0 and x + w - 1 < img.get_width():
				img.set_pixel(x + w - 1, j, col)

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
		_draw_gem(img, types[tname])
		_save_image(img, "token_%s.png" % tname)

## Faceted gem: three facet tones split by seams, a dark outline, a single
## white-hot specular pixel, and a thin accent halo so it glows on the floor.
func _draw_gem(img: Image, c: Color) -> void:
	var light := c.lightened(0.30)
	var dark := c.darkened(0.35)
	var seam := c.darkened(0.55)
	for x in 16:
		for y in 16:
			var dx := absf(x - 8.0)
			var dy := absf(y - 8.0) * 1.15
			if dx / 6.0 + dy / 6.0 > 1.0:
				continue
			var col := c
			if x < 8 and y < 8:
				col = light          # top-left facet takes the light
			elif x >= 8 and y >= 8:
				col = dark           # bottom-right facet holds the shadow
			elif x < 8:
				col = c.darkened(0.15)
			img.set_pixel(x, y, col)
	# facet seams meet at a slightly lit junction
	for x in range(2, 15):
		img.set_pixel(x, 8, seam)
	for y in range(3, 14):
		img.set_pixel(8, y, seam)
	img.set_pixel(8, 8, c.lightened(0.15))
	# the pixel that makes it precious
	img.set_pixel(6, 5, WHITE_HOT)
	img.set_pixel(5, 6, light.lightened(0.2))
	_outline_silhouette(img, OUTLINE_COLOR)
	_halo_pass(img, Color(c.r, c.g, c.b, 0.30))

func _generate_ui_elements() -> void:
	# Panel per the UI tokens: BASE bg @92%, LINE border, subtle vertical
	# falloff, an inner top highlight, and cyan corner ticks with hot tips.
	var panel := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var base := Color(0.043, 0.055, 0.11)     # BASE #0B0E1C
	var line := Color(0.165, 0.208, 0.345)    # LINE #2A3558
	var cyan := Color(0.14, 0.94, 0.86, 0.85)
	for x in 64:
		for y in 64:
			var v := 1.0 - float(y) / 64.0 * 0.18
			panel.set_pixel(x, y, Color(base.r * v + 0.01, base.g * v + 0.01, base.b * v + 0.02, 0.92))
	for i in 64:
		panel.set_pixel(i, 0, line)
		panel.set_pixel(i, 63, line.darkened(0.3))
		panel.set_pixel(0, i, line)
		panel.set_pixel(63, i, line.darkened(0.3))
	for i in range(1, 63):
		panel.set_pixel(i, 1, Color(0.22, 0.28, 0.45, 0.5))  # room light on the top edge
	for i in 7:
		panel.set_pixel(i, 0, cyan)
		panel.set_pixel(0, i, cyan)
		panel.set_pixel(63 - i, 0, cyan)
		panel.set_pixel(63, i, cyan)
		panel.set_pixel(i, 63, cyan)
		panel.set_pixel(0, 63 - i, cyan)
		panel.set_pixel(63 - i, 63, cyan)
		panel.set_pixel(63, 63 - i, cyan)
	panel.set_pixel(0, 0, WHITE_HOT)   # hot corners for a hint of bloom
	panel.set_pixel(63, 0, WHITE_HOT)
	panel.set_pixel(0, 63, WHITE_HOT)
	panel.set_pixel(63, 63, WHITE_HOT)
	_save_image(panel, "ui_panel.png")

func _generate_fx() -> void:
	# fx_glow_dot: 16x16 soft radial dot for particles and pickup bursts.
	# White, so consumers can modulate any accent over it.
	var dot := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	dot.fill(Color(0, 0, 0, 0))
	for x in 16:
		for y in 16:
			var d := Vector2(x - 7.5, y - 7.5).length() / 8.0
			if d < 1.0:
				dot.set_pixel(x, y, Color(1, 1, 1, pow(1.0 - d, 2.2)))
	_save_image(dot, "fx_glow_dot.png")
	# fx_spark: 8x8 four-point star with a white-hot 2x2 core.
	var spark := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	spark.fill(Color(0, 0, 0, 0))
	for i in 8:
		var fall := 1.0 - absf(i - 3.5) / 4.0
		spark.set_pixel(i, 3, Color(1, 1, 1, fall))
		spark.set_pixel(i, 4, Color(1, 1, 1, fall))
		spark.set_pixel(3, i, Color(1, 1, 1, fall))
		spark.set_pixel(4, i, Color(1, 1, 1, fall))
	for dpos in [Vector2i(2, 2), Vector2i(5, 2), Vector2i(2, 5), Vector2i(5, 5)]:
		spark.set_pixel(dpos.x, dpos.y, Color(1, 1, 1, 0.35))
	for x in range(3, 5):
		for y in range(3, 5):
			spark.set_pixel(x, y, WHITE_HOT)
	_save_image(spark, "fx_spark.png")

func _generate_icon() -> void:
	# Poster treatment: a gold token gem floating in the VOID — vignette,
	# stars, halo rings, a reflection pool, scanlines, and one cyan stripe.
	# It's the first thing anyone sees. Look expensive.
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var void_c := Color(0.02, 0.024, 0.055)  # VOID #05060E
	for x in 128:
		for y in 128:
			var dx := (x - 64.0) / 64.0
			var dy := (y - 64.0) / 64.0
			var vig := clampf(1.0 - sqrt(dx * dx + dy * dy) * 0.85, 0.15, 1.0)
			img.set_pixel(x, y, Color(void_c.r * vig, void_c.g * vig, void_c.b * vig + 0.012 * vig, 1.0))
	# starfield specks, kept clear of the gem
	for i in 40:
		var sx := int(_hash01(i, 1, 55) * 127.0)
		var sy := int(_hash01(i, 2, 55) * 127.0)
		if Vector2(sx - 64, sy - 58).length() > 40.0:
			var b := 0.25 + _hash01(i, 3, 55) * 0.5
			img.set_pixel(sx, sy, Color(b, b, minf(b * 1.1, 1.0), 1.0))
	# gold halo rings behind the gem
	var gold := Color(1.0, 0.83, 0.30)
	for x in 128:
		for y in 128:
			var d := Vector2(x - 64, y - 58).length()
			if d > 30.0 and d < 52.0:
				var a := (1.0 - (d - 30.0) / 22.0) * 0.20
				img.set_pixel(x, y, img.get_pixel(x, y).lerp(gold, a))
	# the gem: big faceted diamond with an edge bevel and a 1px outline
	for x in 128:
		for y in 128:
			var ddx := absf(x - 64.0)
			var ddy := absf(y - 58.0) * 1.15
			var m := ddx / 30.0 + ddy / 30.0
			if m > 1.08:
				continue
			if m > 1.0:
				img.set_pixel(x, y, Color(0.02, 0.02, 0.04))
				continue
			var col := gold
			if x < 64 and y < 58:
				col = Color(1.0, 0.92, 0.55)
			elif x >= 64 and y >= 58:
				col = Color(0.72, 0.52, 0.12)
			elif x < 64:
				col = Color(0.88, 0.68, 0.20)
			if m > 0.93:
				col = col.darkened(0.35)
			img.set_pixel(x, y, col)
	# facet seams
	for x in range(35, 94):
		img.set_pixel(x, 58, Color(0.55, 0.38, 0.08))
	for y in range(33, 84):
		img.set_pixel(64, y, Color(0.55, 0.38, 0.08))
	# internal sparkle + white-hot specular cluster
	_draw_line_img(img, 50, 44, 58, 52, Color(1.0, 0.95, 0.7))
	_fill_rect(img, 51, 42, 3, 3, WHITE_HOT)
	img.set_pixel(55, 46, WHITE_HOT)
	# reflection pool beneath
	for x in 128:
		for y in range(98, 114):
			var rdx := (x - 64.0) / 36.0
			var rdy := (y - 106.0) / 8.0
			var rd := rdx * rdx + rdy * rdy
			if rd <= 1.0:
				img.set_pixel(x, y, img.get_pixel(x, y).lerp(gold, (1.0 - rd) * 0.12))
	# scanlines: the world is watched through a monitor
	for y in range(0, 128, 4):
		for x in 128:
			img.set_pixel(x, y, img.get_pixel(x, y).darkened(0.12))
	# runner stripe
	_fill_rect(img, 34, 104, 60, 2, Color(0.14, 0.94, 0.86))
	_fill_rect(img, 34, 104, 60, 1, Color(0.55, 1.0, 0.95))
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

## ---------- shared raster helpers (bible quality bar) ----------

## Deterministic 0..1 hash — stable value noise without RNG state.
func _hash01(x: int, y: int, s: int = 0) -> float:
	var n: int = x * 374761393 + y * 668265263 + s * 1274126177
	n = ((n ^ (n >> 13)) & 0x7FFFFFFF) * 1103515245
	return float((n ^ (n >> 16)) & 0xFFFF) / 65535.0

## 2x2-checker dither between two colors — the bible's answer to flat fills.
## over_only limits it to already-drawn pixels so silhouettes keep their shape.
func _dither_rect(img: Image, x: int, y: int, w: int, h: int, a: Color, b: Color, over_only := false) -> void:
	for ix in range(x, x + w):
		for iy in range(y, y + h):
			if ix < 0 or iy < 0 or ix >= img.get_width() or iy >= img.get_height():
				continue
			if over_only and img.get_pixel(ix, iy).a <= 0.05:
				continue
			img.set_pixel(ix, iy, a if ((ix / 2 + iy / 2) % 2 == 0) else b)

## WHITE_HOT core + accent halo — the bible's recipe for emissive pixels.
## HDR bloom picks the core up on its own; the halo sells the falloff.
func _glow_core(img: Image, x: int, y: int, accent: Color) -> void:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = x + d.x
		var ny: int = y + d.y
		if nx >= 0 and ny >= 0 and nx < img.get_width() and ny < img.get_height():
			img.set_pixel(nx, ny, accent)
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, WHITE_HOT)

## Tint the top-left silhouette edge toward a rim color (bible rim light).
## Only fully-opaque pixels count as edges; soft halos stay soft.
func _rim_light_pass(img: Image, rim: Color, strength := 0.6) -> void:
	var src: Image = img.duplicate()
	var w := img.get_width()
	var h := img.get_height()
	for x in w:
		for y in h:
			var p := src.get_pixel(x, y)
			if p.a <= 0.5:
				continue
			var open_up := y == 0 or src.get_pixel(x, y - 1).a <= 0.5
			var open_left := x == 0 or src.get_pixel(x - 1, y).a <= 0.5
			if open_up or open_left:
				img.set_pixel(x, y, p.lerp(Color(rim.r, rim.g, rim.b, p.a), strength))

## Thin colored halo hugging the outside of a finished silhouette.
func _halo_pass(img: Image, halo: Color) -> void:
	var src: Image = img.duplicate()
	var w := img.get_width()
	var h := img.get_height()
	for x in w:
		for y in h:
			if src.get_pixel(x, y).a > 0.05:
				continue
			var touching := false
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					var nx := x + dx
					var ny := y + dy
					if nx >= 0 and ny >= 0 and nx < w and ny < h and src.get_pixel(nx, ny).a > 0.5:
						touching = true
						break
				if touching:
					break
			if touching:
				img.set_pixel(x, y, halo)

## Fill a circle with a 4-tone top-left-lit ramp and a dithered transition
## band — instant "sphere" for heads and domes.
func _shade_sphere(img: Image, cx: int, cy: int, r: int, base: Color) -> void:
	var sh := base.darkened(0.22)
	var sh2 := base.darkened(0.40)
	var hi := base.lightened(0.14)
	for x in range(cx - r, cx + r + 1):
		for y in range(cy - r, cy + r + 1):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var dx := float(x - cx) / float(r)
			var dy := float(y - cy) / float(r)
			var d2 := dx * dx + dy * dy
			if d2 > 1.0:
				continue
			var lit := -(dx + dy) * 0.707  # positive toward the top-left light
			var c := base
			if lit > 0.42:
				c = hi
			elif lit < -0.55 or (d2 > 0.82 and lit < 0.0):
				c = sh2 if lit < -0.72 else sh
			elif lit < -0.18:
				c = sh if ((x + y) % 2 == 0) else base  # dithered terminator
			img.set_pixel(x, y, c)
