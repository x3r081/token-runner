extends RefCounted
class_name AssetGeneratorRuntime

const OUT_DIR := "res://assets/textures/generated/"

## Bible constants — every sprite in the game agrees on these.
const OUTLINE_COLOR := Color(0.039, 0.047, 0.086, 0.85)  # #0A0C16 @ ~85%
const WHITE_HOT := Color(0.957, 0.976, 1.0)              # hottest emissive core
## Enemies get a harder, fully-opaque version of the same outline: they must
## separate from a near-black floor at a glance, which is a playability
## requirement, not a taste one.
const OUTLINE_ENEMY := Color(0.031, 0.036, 0.070, 0.97)
## Torso rows shared by every humanoid. One profile, many silhouettes.
const TORSO_ROWS := 19

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
	_polish_interior_props()
	_generate_floor_structures()
	print("Assets generated.")

## Every speaking character in this world is the same species of sleep-deprived
## professional, so they share one body renderer. What separates them is build,
## garment, headwear and the single stupid object they refuse to put down.
func _generate_npcs() -> void:
	var kinds := {
		"claude": {
			"hoodie": Color(0.16, 0.40, 0.40), "hoodie_hi": Color(0.27, 0.60, 0.57),
			"hoodie_sh": Color(0.08, 0.23, 0.24), "hair": Color(0.15, 0.13, 0.12),
			"skin": Color(0.88, 0.74, 0.62), "accent": Color(0.20, 0.98, 0.88),
			"legs": Color(0.13, 0.22, 0.26), "headphones": true, "accessory": "circuit",
		},
		"suit": {
			"hoodie": Color(0.17, 0.19, 0.30), "hoodie_hi": Color(0.29, 0.32, 0.46),
			"hoodie_sh": Color(0.08, 0.09, 0.16), "hair": Color(0.20, 0.16, 0.12),
			"skin": Color(0.86, 0.72, 0.60), "accent": Color(0.35, 0.65, 1.0),
			"legs": Color(0.12, 0.13, 0.21), "shoe": Color(0.16, 0.14, 0.14),
			"headphones": false, "accessory": "tie", "garment": "suit",
			"headwear": "slick", "build": "broad", "props": ["lanyard"],
		},
		"maintainer": {
			"hoodie": Color(0.31, 0.34, 0.33), "hoodie_hi": Color(0.44, 0.47, 0.45),
			"hoodie_sh": Color(0.17, 0.19, 0.19), "hair": Color(0.46, 0.46, 0.48),
			"skin": Color(0.82, 0.68, 0.56), "accent": Color(0.52, 0.92, 0.46),
			"legs": Color(0.23, 0.23, 0.26), "shoe": Color(0.60, 0.58, 0.54),
			"headphones": false, "accessory": "glasses", "build": "hunched",
			"drop": 2, "props": ["noodles"],
		},
		"foreman": {
			"hoodie": Color(0.85, 0.53, 0.14), "hoodie_hi": Color(0.99, 0.74, 0.28),
			"hoodie_sh": Color(0.53, 0.31, 0.07), "hair": Color(0.15, 0.12, 0.10),
			"skin": Color(0.80, 0.66, 0.54), "accent": Color(1.0, 0.76, 0.26),
			"legs": Color(0.22, 0.20, 0.20), "shoe": Color(0.28, 0.24, 0.20),
			"headphones": false, "accessory": "hardhat", "garment": "hivis",
			"build": "broad", "props": ["thermal_gun"],
		},
		"svp": {
			"hoodie": Color(0.20, 0.23, 0.37), "hoodie_hi": Color(0.35, 0.40, 0.58),
			"hoodie_sh": Color(0.09, 0.11, 0.19), "hair": Color(0.22, 0.18, 0.14),
			"skin": Color(0.88, 0.74, 0.62), "accent": Color(0.30, 0.55, 1.0),
			"legs": Color(0.13, 0.15, 0.24), "shoe": Color(0.14, 0.12, 0.12),
			"headphones": false, "accessory": "tie", "garment": "suit",
			"headwear": "slick", "build": "broad", "drop": -2,
			"props": ["lanyard", "buzzwords"],
		},
		"junior": {
			"hoodie": Color(0.24, 0.46, 0.42), "hoodie_hi": Color(0.38, 0.66, 0.58),
			"hoodie_sh": Color(0.12, 0.26, 0.25), "hair": Color(0.34, 0.22, 0.13),
			"skin": Color(0.90, 0.76, 0.63), "accent": Color(0.62, 1.0, 0.55),
			"legs": Color(0.19, 0.22, 0.30), "headphones": false, "build": "small",
			"drop": 5, "back": "backpack", "props": ["antenna", "thumbs_up"],
		},
		"hermit": {
			"hoodie": Color(0.42, 0.38, 0.30), "hoodie_hi": Color(0.57, 0.52, 0.41),
			"hoodie_sh": Color(0.24, 0.21, 0.16), "hair": Color(0.52, 0.50, 0.48),
			"skin": Color(0.78, 0.64, 0.52), "accent": Color(0.91, 0.77, 0.42),
			"headphones": false, "garment": "robe", "headwear": "hood",
			"beard": true, "props": ["tablet"],
		},
		"oncall": {
			"hoodie": Color(0.38, 0.22, 0.27), "hoodie_hi": Color(0.53, 0.33, 0.37),
			"hoodie_sh": Color(0.21, 0.11, 0.14), "hair": Color(0.28, 0.22, 0.19),
			"skin": Color(0.84, 0.69, 0.57), "accent": Color(1.0, 0.36, 0.33),
			"legs": Color(0.20, 0.21, 0.28), "shoe": Color(0.52, 0.50, 0.48),
			"headphones": false, "garment": "coat", "build": "hunched", "drop": 1,
			"props": ["mug", "pager", "wild_hair"],
		},
		"reseller": {
			"hoodie": Color(0.19, 0.17, 0.25), "hoodie_hi": Color(0.31, 0.28, 0.40),
			"hoodie_sh": Color(0.09, 0.08, 0.13), "hair": Color(0.13, 0.11, 0.10),
			"skin": Color(0.83, 0.68, 0.55), "accent": Color(1.0, 0.26, 0.62),
			"legs": Color(0.13, 0.12, 0.18), "shoe": Color(0.18, 0.15, 0.16),
			"headphones": false, "garment": "coat", "headwear": "cap",
			"accessory": "shades", "props": ["keys"],
		},
		"cloud": {
			"hoodie": Color(0.60, 0.68, 0.82), "hoodie_hi": Color(0.80, 0.87, 0.98),
			"hoodie_sh": Color(0.36, 0.43, 0.56), "hair": Color(0.36, 0.28, 0.18),
			"skin": Color(0.90, 0.77, 0.65), "accent": Color(0.42, 0.78, 1.0),
			"legs": Color(0.28, 0.34, 0.45), "shoe": Color(0.90, 0.92, 0.96),
			"headphones": false, "accessory": "tie", "garment": "blazer",
			"headwear": "slick", "props": ["cloud_balloon"],
		},
	}
	for k in kinds:
		var img := _draw_vibe_coder("down", "idle", 0, kinds[k])
		if k == "claude":
			# The roommate AI runs warm. A faint accent halo is the only tell.
			var a: Color = kinds[k]["accent"]
			_halo_pass(img, Color(a.r, a.g, a.b, 0.20))
		_save_image(img, "npc_%s.png" % k)

## Sheet layout (64px frames, 6 columns). Rows 0-2 are down/up/side with
## idle + a 4-frame walk + a blink; row 3 holds the special idles; rows 4-5 are
## the combat poses. Indices 0-23 are FROZEN — player.gd maps them by hand.
func _generate_player_spritesheet() -> void:
	const FRAME := 64
	const COLS := 6
	const ROWS := 6
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
	# Row 4 (24-29): the dash and the cast wind-up, per facing.
	var row4 := [["down", "dash"], ["up", "dash"], ["side", "dash"],
		["down", "cast"], ["up", "cast"], ["side", "cast"]]
	for i in row4.size():
		var e: Array = row4[i]
		_blit_frame(sheet, i * FRAME, 4 * FRAME, FRAME, _draw_vibe_coder(str(e[0]), str(e[1]), i))
	# Row 5 (30-35): the cast release (follow-through), then hurt/celebrate
	# for the facings row 3 doesn't cover.
	var row5 := [["down", "cast_release"], ["up", "cast_release"], ["side", "cast_release"],
		["up", "hurt"], ["side", "hurt"], ["side", "celebrate"]]
	for i in row5.size():
		var e2: Array = row5[i]
		_blit_frame(sheet, i * FRAME, 5 * FRAME, FRAME, _draw_vibe_coder(str(e2[0]), str(e2[1]), i))
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
				_px(img, x, y, Color(0, 0, 0, 0.34 * pow(1.0 - d, 1.5)))
	_save_image(img, "player_shadow.png")

func _blit_frame(sheet: Image, ox: int, oy: int, size: int, frame: Image) -> void:
	for x in size:
		for y in size:
			_px(sheet, ox + x, oy + y, frame.get_pixel(x, y))

## Half-width of the torso at row `i`. The profile is what stops every character
## reading as a rectangle: sloped shoulders, a taken-in waist, a flared hem.
func _torso_hw(i: int, build: String, side: bool) -> int:
	var front: Array[int] = [6, 9, 11, 11, 11, 11, 10, 10, 10, 10, 9, 9, 9, 9, 9, 10, 10, 10, 9]
	var prof: Array[int] = [5, 7, 8, 8, 8, 8, 8, 7, 7, 7, 7, 7, 7, 7, 7, 8, 8, 8, 7]
	var base: int = prof[i] if side else front[i]
	match build:
		"broad":
			base += 3 if i < 6 else (2 if i < 10 else 1)
		"small":
			base -= 2 if i > 2 else 1
		"hunched":
			base += 1 if i >= 2 and i <= 7 else 0
	return maxi(base, 3)

## THE VIBE CODER — hoodie, headphones, white sneakers, and the thousand-yard
## stare of someone whose tests pass locally. Full bible treatment: 4-tone ramps
## lit from the top-left, folds, a two-point rim (accent key + warm floor
## bounce), a 1px outline, and LED cores hot enough to bloom.
##
## `palette` turns him into anyone else in the game: build, garment, headwear,
## a back item and any number of held props.
func _draw_vibe_coder(direction: String, pose: String, frame_idx: int, palette: Dictionary = {}) -> Image:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# --- material ramps (shadow / base / light / rim) ---
	var hoodie: Color = palette.get("hoodie", Color(0.30, 0.38, 0.61))
	var hoodie_hi: Color = palette.get("hoodie_hi", Color(0.50, 0.63, 0.90))
	var hoodie_sh: Color = palette.get("hoodie_sh", Color(0.13, 0.17, 0.31))
	var skin: Color = palette.get("skin", Color(0.93, 0.78, 0.64))
	var hair: Color = palette.get("hair", Color(0.22, 0.16, 0.13))
	var glow: Color = palette.get("accent", Color(0.14, 0.94, 0.86))
	var show_phones: bool = palette.get("headphones", true)
	var accessory: String = palette.get("accessory", "")
	var build: String = palette.get("build", "normal")
	var garment: String = palette.get("garment", "hoodie")
	var headwear: String = palette.get("headwear", "hair")
	var props: Array = palette.get("props", [])
	var beard: bool = palette.get("beard", false)
	var jeans: Color = palette.get("legs", Color(0.17, 0.20, 0.33))
	var shoe: Color = palette.get("shoe", Color(0.88, 0.90, 0.96))
	var drop: int = int(palette.get("drop", 0))
	var back: String = palette.get("back", "")

	var hoodie_rim := hoodie_hi.lightened(0.34)
	var skin_sh := skin.darkened(0.20)
	var skin_hi := skin.lightened(0.12)
	var hair_sh := hair.darkened(0.38)
	var hair_hi := hair.lightened(0.34)
	var jeans_sh := jeans.darkened(0.36)
	var shoe_hi := shoe.lightened(0.45)
	var sole := Color(0.40, 0.37, 0.34)
	var cup := Color(0.08, 0.09, 0.13)
	var cup_hi := Color(0.22, 0.24, 0.32)
	var eye := Color(0.07, 0.06, 0.09)

	# --- kinematics: 4-frame gait = contact / passing / contact / passing.
	# The bob rides on the body while the feet stay planted, arms counter-swing,
	# and the hair lags a frame behind (secondary motion is most of the life).
	var bob := 0
	var stride := 0
	var arm_swing := 0
	var hair_lag := 0
	if pose == "walk":
		var cyc := (frame_idx - 1) % 4  # sheet walk columns are 1..4
		var seq_stride: Array[int] = [4, 0, -4, 0]
		var seq_bob: Array[int] = [0, -2, 0, -2]
		var seq_arm: Array[int] = [-3, 0, 3, 0]
		var seq_hair: Array[int] = [1, -1, 1, -1]
		stride = seq_stride[cyc]
		bob = seq_bob[cyc]
		arm_swing = seq_arm[cyc]
		hair_lag = seq_hair[cyc]
	var lean := 0
	match pose:
		"dash":
			lean = 5
			hair_lag = 3
			bob = 2
		"cast":
			lean = 1
		"cast_release":
			lean = 2
			hair_lag = 1
		"hurt":
			lean = -2
			bob = 1
			hair_lag = -2
		"celebrate":
			bob = -2
			hair_lag = 1

	var side := direction == "side"
	var up := direction == "up"
	var cx := 32
	var hy := 16 + bob + drop   # head centre
	var ty := 27 + bob + drop   # torso top
	var leg_y := 45 + bob + drop
	var foot_y := 54            # the feet stay planted; the bounce lives in the legs
	var tilt := lean if side else 0
	var head_dx := int(round(float(tilt) * 0.6)) + (1 if side else 0)

	# ---- legs + sneakers (drawn first; the hem overlaps the hips) ----
	_vc_legs(img, cx, leg_y, foot_y, stride, pose, side, jeans, jeans_sh,
		shoe, shoe_hi, sole, glow, garment)

	# things worn on the back go down before the body does
	if back != "":
		_vc_back_prop(img, cx, ty, back, hoodie, hoodie_hi, hoodie_sh, glow)

	# ---- neck (behind the hood, or the collar paints over it) ----
	if not up:
		_fill_rect(img, cx - 2 + head_dx, hy + 6, 5, 4, skin_sh)
		_fill_rect(img, cx - 2 + head_dx, hy + 6, 1, 4, skin.darkened(0.08))
		_fill_rect(img, cx - 2 + head_dx, hy + 6, 5, 1, skin_sh.darkened(0.34))

	# ---- the hood bunched behind the neck ----
	# The single biggest silhouette read: without it the head sits on the
	# shoulders like a ball balanced on a wall.
	if garment == "hoodie" or garment == "robe" or garment == "coat":
		var hx := cx + int(float(tilt) * 0.5)
		_fill_ellipse(img, hx, ty, 9, 5, hoodie_sh.darkened(0.20))
		_fill_ellipse(img, hx, ty - 1, 8, 4, hoodie_sh)
		_fill_rect(img, hx - 7, ty - 4, 14, 1, hoodie.darkened(0.06))

	_vc_torso(img, cx, ty, tilt, build, side, up, garment,
		hoodie, hoodie_hi, hoodie_sh, hoodie_rim, glow)

	if garment == "robe" or garment == "coat":
		_vc_skirt(img, cx, ty + TORSO_ROWS - 1, foot_y + (3 if garment == "robe" else -1),
			hoodie, hoodie_hi, hoodie_sh, garment == "coat")

	_vc_arms(img, cx, ty, tilt, arm_swing, pose, side, build,
		hoodie, hoodie_sh, hoodie_rim, skin, skin_sh)

	_vc_head(img, cx + head_dx, hy, hair_lag, direction, pose, headwear,
		skin, skin_sh, skin_hi, hair, hair_sh, hair_hi, eye, glow,
		cup, cup_hi, show_phones, hoodie_sh, hoodie_hi, beard)

	_vc_accessory(img, cx, ty, hy, head_dx, accessory, up, glow, skin_hi)
	_vc_pose_props(img, cx, ty, hy, head_dx, pose, frame_idx, glow, skin, skin_hi)
	for pi in props.size():
		_vc_npc_prop(img, cx, ty, hy, head_dx, str(props[pi]), glow, skin, skin_sh)

	# ---- lighting finish ----
	# Key rim: the top-left silhouette edge in the character's accent (bible rule).
	# Round 5: pushed most of the way to white and eased off in strength. At the
	# old settings a 3px sleeve was almost entirely rim, so the arms read as
	# glowing cyan slabs instead of lit cloth — a rim is light, not paint.
	_edge_light(img, glow.lerp(WHITE_HOT, 0.55), 0.44, true, true)
	# Bounce rim: bottom-right, warm and dim, as if the floor were lit. Two-point
	# lighting is most of what separates "a sprite" from "a character".
	_edge_light(img, Color(1.0, 0.70, 0.40), 0.20, false, false)
	_outline_silhouette(img, OUTLINE_COLOR)
	if pose == "hurt":
		# Tint toward red but protect the highlights, so the pose still reads.
		_impact_tint(img, Color(1.0, 0.24, 0.28), 0.34)
	return img

## Legs, knees and the sneakers that anchor the whole figure. The shoes are
## near-white on purpose: the eye needs one bright thing at the bottom of the
## silhouette or the character floats.
func _vc_legs(img: Image, cx: int, leg_y: int, foot_y: int, stride: int, pose: String,
		side: bool, jeans: Color, jeans_sh: Color, shoe: Color, shoe_hi: Color,
		sole: Color, glow: Color, garment: String) -> void:
	if garment == "robe":
		return  # the robe reaches the floor; _vc_skirt draws it
	var lo := stride
	var ro := -stride
	var l_lift := -2 if stride >= 3 else 0
	var r_lift := -2 if stride <= -3 else 0
	match pose:
		"dash":
			lo = 7
			ro = -6
			l_lift = -3
			r_lift = -1
		"hurt":
			lo = -2
			ro = 2
			l_lift = 2
			r_lift = 2
		"celebrate":
			lo = -1
			ro = 1
	# A profile walk gets a real stride; a front-on walk only needs the stance to
	# open a pixel or two, or the legs cross over each other.
	var swing := 0.7 if side else 0.32
	var leg_x: Array[int] = [cx - 6 + int(round(float(lo) * swing)), cx + 1 + int(round(float(ro) * swing))]
	var leg_off: Array[int] = [l_lift, r_lift]
	for i in 2:
		var lx: int = leg_x[i]
		var off: int = leg_off[i]
		var col := jeans if i == 0 else jeans.darkened(0.12)
		_shade_limb(img, lx, leg_y + off, 5, foot_y - leg_y - off + 1, col)
		# knee crease + a cuff fold, so denim reads as cloth and not as pipe
		_fill_rect(img, lx, leg_y + off + 3, 5, 1, jeans_sh)
		_fill_rect(img, lx + 1, leg_y + off + 4, 3, 1, col.lightened(0.06))
		_fill_rect(img, lx, foot_y + off - 2, 5, 1, jeans_sh.darkened(0.20))
	for i in 2:
		var lx2: int = leg_x[i]
		var off2: int = leg_off[i]
		var sx: int = lx2 - 2 if i == 0 else lx2 - 1
		var sy: int = foot_y + mini(off2, 0)
		_fill_round_rect(img, sx, sy, 8, 4, shoe)
		_fill_rect(img, sx + 1, sy, 6, 1, shoe_hi)              # rim-lit toe box
		_fill_rect(img, sx, sy + 3, 8, 1, sole)                 # gum sole
		_fill_rect(img, sx + 7, sy + 1, 1, 2, shoe.darkened(0.28))
		_px(img, sx + (1 if i == 0 else 6), sy + 1, glow)  # one unlicensed swoosh
		_px(img, sx + (2 if i == 0 else 5), sy + 2, glow.darkened(0.35))

## The torso, drawn row by row from the profile so the shoulders slope and the
## waist comes in. Then the garment-specific dressing on top.
func _vc_torso(img: Image, cx: int, ty: int, tilt: int, build: String, side: bool,
		up: bool, garment: String, hoodie: Color, hoodie_hi: Color, hoodie_sh: Color,
		hoodie_rim: Color, glow: Color) -> void:
	for i in TORSO_ROWS:
		var hw := _torso_hw(i, build, side)
		var y := ty + i
		# the lean shears the torso: the higher the row, the further it travels
		var sx := cx + int(round(float(tilt) * (1.0 - float(i) / float(TORSO_ROWS))))
		for x in range(sx - hw, sx + hw + 1):
			var u := x - (sx - hw)
			var span := hw * 2
			var c := hoodie
			if u == 0:
				c = hoodie_rim
			elif u == 1:
				c = hoodie_hi
			elif u <= 3:
				c = hoodie.lightened(0.10) if ((x / 2 + y / 2) % 2 == 0) else hoodie
			elif u >= span:
				c = hoodie_sh.darkened(0.22)
			elif u >= span - 2:
				c = hoodie_sh
			elif u >= span - 4:
				c = hoodie if ((x / 2 + y / 2) % 2 == 0) else hoodie.darkened(0.11)
			if i == 0:
				c = c.lerp(hoodie_rim, 0.5)
			_px(img, x, y, c)
	var sx0 := cx + tilt
	if garment == "hivis":
		# hi-vis without retroreflective banding is just a very loud shirt
		var hw_a := _torso_hw(6, build, side)
		for band_y: int in [ty + 6, ty + 12]:
			_fill_rect(img, sx0 - hw_a, band_y, hw_a * 2 + 1, 2, Color(0.90, 0.92, 0.96))
			_fill_rect(img, sx0 - hw_a, band_y, hw_a * 2 + 1, 1, Color(0.99, 1.0, 1.0))
			_fill_rect(img, sx0 - hw_a, band_y + 2, hw_a * 2 + 1, 1, hoodie_sh)
		_fill_rect(img, sx0 - 1, ty, 2, TORSO_ROWS - 2, hoodie_sh)
		_px(img, sx0, ty + 2, WHITE_HOT)
	var hw_hem := _torso_hw(TORSO_ROWS - 1, build, side)
	_fill_rect(img, sx0 - hw_hem, ty + TORSO_ROWS - 1, hw_hem * 2 + 1, 1, hoodie_sh.darkened(0.30))
	_fill_rect(img, sx0 - hw_hem, ty + TORSO_ROWS - 2, hw_hem * 2 + 1, 1, hoodie_sh)
	if garment == "suit" or garment == "blazer":
		# collar, lapel V and a buttoned front seam
		_fill_rect(img, cx - 4, ty, 9, 3, Color(0.93, 0.94, 0.97))
		_draw_line_img(img, cx - 5, ty + 1, cx - 1, ty + 9, hoodie_sh)
		_draw_line_img(img, cx + 5, ty + 1, cx + 1, ty + 9, hoodie_sh)
		_draw_line_img(img, cx - 5, ty + 1, cx - 7, ty + 8, hoodie_hi)
		_draw_line_img(img, cx + 5, ty + 1, cx + 7, ty + 8, hoodie_sh)
		for by in range(ty + 10, ty + 18, 4):
			_px(img, cx + 1, by, hoodie_hi)
		return
	if up:
		# the hood hangs down the back, creased down the middle
		_fill_ellipse(img, cx, ty + 6, 9, 8, hoodie_sh)
		_fill_ellipse(img, cx - 1, ty + 5, 8, 7, hoodie_sh.lightened(0.10))
		_draw_line_img(img, cx, ty + 1, cx, ty + 12, hoodie_sh.darkened(0.30))
		_fill_rect(img, cx - 9, ty + 1, 18, 1, hoodie.lightened(0.06))
		# the seam where the sleeves are set into the shoulders
		_draw_line_img(img, cx - 11, ty + 2, cx - 9, ty + 7, hoodie_sh)
		_draw_line_img(img, cx + 11, ty + 2, cx + 9, ty + 7, hoodie_sh)
		return
	# kangaroo pocket: a shadowed cavity with a lit seam and a dark mouth
	_fill_rect(img, sx0 - 5, ty + 11, 11, 5, hoodie_sh)
	_dither_rect(img, sx0 - 5, ty + 12, 11, 3, hoodie_sh, hoodie.darkened(0.16), true)
	_fill_rect(img, sx0 - 5, ty + 10, 11, 1, hoodie_sh.darkened(0.34))
	_fill_rect(img, sx0 - 5, ty + 11, 11, 1, hoodie_hi.darkened(0.20))
	_px(img, sx0 - 6, ty + 12, hoodie_sh.darkened(0.20))
	_px(img, sx0 + 6, ty + 12, hoodie_sh.darkened(0.20))
	# fabric folds where the hoodie bunches over the pocket
	_draw_line_img(img, sx0 - 9, ty + 6, sx0 - 5, ty + 9, hoodie_sh)
	_draw_line_img(img, sx0 + 5, ty + 9, sx0 + 9, ty + 6, hoodie_sh)
	_draw_line_img(img, sx0 - 8, ty + 17, sx0 - 6, ty + 18, hoodie_sh)
	# neon drawstrings with white-hot aglets (they bloom; he knows)
	for k: int in [-3, 3]:
		_fill_rect(img, sx0 + k, ty + 1, 1, 5, hoodie_sh.darkened(0.15))
		_px(img, sx0 + k, ty + 5, glow.darkened(0.20))
		_px(img, sx0 + k, ty + 6, WHITE_HOT)

## One sleeve: lit shoulder cap, 4-tone tube, ribbed cuff, a hand, and a dark
## seam against the torso so the arm never melts into the chest.
func _vc_arm(img: Image, x: int, y: int, length: int, w: int, col: Color,
		rim: Color, sh: Color, skin: Color, skin_sh: Color,
		hand: bool = true, seam: bool = true) -> void:
	_shade_limb(img, x, y, w, length, col)
	_fill_rect(img, x, y, w, 1, rim)
	_fill_rect(img, x, y + length - 3, w, 2, col.darkened(0.30))
	_fill_rect(img, x, y + length - 3, w, 1, col.lightened(0.14))
	if hand:
		_fill_round_rect(img, x, y + length - 1, w, 4, skin)
		_fill_rect(img, x, y + length + 1, w, 1, skin_sh)
		_fill_rect(img, x + w - 1, y + length, 1, 2, skin_sh)
	if seam:
		_fill_rect(img, x + w, y + 1, 1, length - 2, sh)

func _vc_arms(img: Image, cx: int, ty: int, tilt: int, arm_swing: int, pose: String,
		side: bool, build: String, hoodie: Color, hoodie_sh: Color,
		hoodie_rim: Color, skin: Color, skin_sh: Color) -> void:
	var sleeve := hoodie.darkened(0.06)
	var far := hoodie.darkened(0.20)
	var w := 4
	var hwt := _torso_hw(2, build, side)
	var lx := cx + tilt - hwt - 3
	var rx := cx + tilt + hwt
	var ay := ty + 3
	match pose:
		"celebrate":
			_vc_arm(img, lx - 1, ty - 9, 12, w, sleeve, hoodie_rim, hoodie_sh, skin, skin_sh)
			_vc_arm(img, rx + 1, ty - 9, 12, w, sleeve, hoodie_rim, hoodie_sh, skin, skin_sh)
			return
		"panic":
			_vc_arm(img, lx - 2, ty - 8, 11, w, sleeve, hoodie_rim, hoodie_sh, skin, skin_sh)
			_vc_arm(img, rx + 2, ty - 8, 11, w, sleeve, hoodie_rim, hoodie_sh, skin, skin_sh)
			return
		"cast":
			# wind-up: the casting arm cocks back, the other braces
			_vc_arm(img, lx, ay + 2, 11, w, sleeve, hoodie_rim, hoodie_sh, skin, skin_sh)
			_vc_arm(img, rx + 3, ay - 3, 10, w, sleeve, hoodie_rim, hoodie_sh, skin, skin_sh)
			return
		"cast_release":
			# release: the arm punches forward, the shoulder follows through
			_vc_arm(img, lx + 2, ay + 5, 9, w, sleeve, hoodie_rim, hoodie_sh, skin, skin_sh)
			_shade_limb(img, rx + 1, ay + 4, 11, w, sleeve)
			_fill_rect(img, rx + 1, ay + 4, 11, 1, hoodie_rim)
			_fill_round_rect(img, rx + 11, ay + 4, 4, w, skin)
			return
		"dash":
			# both arms swept back; the trailing hand is mostly cuff
			_vc_arm(img, lx - 2, ay + 6, 10, w, sleeve, hoodie_rim, hoodie_sh, skin, skin_sh)
			_vc_arm(img, rx - 1, ay + 1, 10, w, far, hoodie_rim, hoodie_sh, skin, skin_sh)
			return
		"hurt":
			_vc_arm(img, lx - 3, ay - 1, 10, w, sleeve, hoodie_rim, hoodie_sh, skin, skin_sh)
			_vc_arm(img, rx + 2, ay + 1, 10, w, far, hoodie_rim, hoodie_sh, skin, skin_sh)
			return
	if side:
		# one arm reads in profile; the far arm peeks out behind the torso
		_shade_limb(img, cx + tilt + 2, ay + 1 - arm_swing, w, 12, far)
		_vc_arm(img, cx + tilt + hwt - 3, ay + arm_swing, 12, w, sleeve,
			hoodie_rim, hoodie_sh, skin, skin_sh, true, false)
		return
	_vc_arm(img, lx, ay + arm_swing, 11, w, sleeve, hoodie_rim, hoodie_sh, skin, skin_sh)
	_vc_arm(img, rx, ay - arm_swing, 11, w, far, hoodie_rim, hoodie_sh, skin, skin_sh)

func _vc_head(img: Image, cx: int, hy: int, hair_lag: int, direction: String, pose: String,
		headwear: String, skin: Color, skin_sh: Color, skin_hi: Color, hair: Color,
		hair_sh: Color, hair_hi: Color, eye: Color, glow: Color, cup: Color, cup_hi: Color,
		show_phones: bool, hoodie_sh: Color, hoodie_hi: Color, beard: bool = false) -> void:
	var side := direction == "side"
	var up := direction == "up"
	if up:
		_shade_sphere(img, cx, hy, 8, hair)
		# the crown whorl and the part line
		_draw_line_img(img, cx + 2, hy - 6, cx + 4, hy + 3, hair_sh)
		_px(img, cx - 3, hy - 5, hair_hi)
		_px(img, cx - 4, hy - 4, hair_hi)
		_px(img, cx - 2, hy - 6, hair_hi)
		_vc_hair_spikes(img, cx, hy - 8, hair, hair_hi, hair_lag)
	else:
		_shade_sphere(img, cx, hy, 8, skin)
		# narrow the bottom of the face — a jaw, not a ball
		for dy in range(5, 9):
			for dx in range(-8, 9):
				if absi(dx) > 8 - (dy - 4) and img.get_pixel(cx + dx, hy + dy).a > 0.0:
					_px(img, cx + dx, hy + dy, Color(0, 0, 0, 0))
		# 3am stubble along the jaw, dithered so it stays a suggestion
		_dither_rect(img, cx - 7, hy + 4, 5, 3, skin_sh.darkened(0.08), skin_sh, true)
		_dither_rect(img, cx + 3, hy + 4, 5, 3, skin_sh.darkened(0.08), skin_sh, true)
		match headwear:
			"hair":
				_vc_hair(img, cx, hy, hair, hair_sh, hair_hi, hair_lag)
			"slick":
				_fill_ellipse(img, cx, hy - 5, 8, 5, hair)
				_fill_rect(img, cx - 8, hy - 3, 16, 1, hair_sh)
				for i in 4:
					_px(img, cx - 6 + i * 4, hy - 8, hair_hi)
				_draw_line_img(img, cx - 7, hy - 6, cx + 6, hy - 7, hair_hi)
			"hood":
				_fill_ellipse(img, cx, hy - 1, 10, 10, hoodie_sh)
				_fill_ellipse(img, cx, hy - 3, 9, 8, hoodie_sh.darkened(0.25))
				_fill_ellipse(img, cx, hy + 1, 6, 6, Color(0, 0, 0, 0))
				_fill_ellipse(img, cx - 1, hy + 1, 6, 6, skin.darkened(0.28))
				_fill_rect(img, cx - 10, hy - 4, 3, 1, hoodie_hi)
			"cap":
				_fill_ellipse(img, cx, hy - 5, 8, 4, hair)
				_fill_rect(img, cx - 10, hy - 3, 15, 2, hair.darkened(0.25))
				_fill_rect(img, cx - 10, hy - 3, 15, 1, hair.lightened(0.20))
		_vc_face(img, cx, hy, pose, side, skin, skin_sh, skin_hi, eye, hair_sh)
		if beard:
			# a beard measured in unanswered issues
			_fill_ellipse(img, cx, hy + 8, 6, 6, hair.darkened(0.10))
			_fill_ellipse(img, cx - 1, hy + 7, 5, 5, hair.lightened(0.22))
			_fill_rect(img, cx - 7, hy + 3, 2, 4, hair.lightened(0.14))
			_fill_rect(img, cx + 6, hy + 3, 2, 4, hair.darkened(0.14))
			_fill_rect(img, cx - 2, hy + 5, 5, 1, Color(0.24, 0.15, 0.15))
			_fill_rect(img, cx - 3, hy + 11, 6, 2, hair.darkened(0.06))
			_px(img, cx - 3, hy + 13, hair.darkened(0.18))
			_px(img, cx + 1, hy + 13, hair.darkened(0.18))
	if show_phones:
		_vc_headphones(img, cx, hy, side, cup, cup_hi, glow)

func _vc_hair(img: Image, cx: int, hy: int, hair: Color, hair_sh: Color,
		hair_hi: Color, hair_lag: int) -> void:
	# a messy cap that sits ON the skull rather than a helmet bolted to it
	for x in range(cx - 9, cx + 10):
		for y in range(hy - 11 + hair_lag, hy - 4):
			var hdx := float(x - cx) / 9.2
			var hdy := float(y - (hy + hair_lag)) / 10.4
			if hdx * hdx + hdy * hdy <= 1.0:
				_px(img, x, y, hair)
	# an uneven fringe: a few locks hang lower, none of them over the eyes
	var fringe: Array[int] = [1, 0, 2, 0, 1, 2, 0, 1, 2, 0, 2, 0, 1]
	for i in 13:
		var fx := cx - 6 + i
		if img.get_pixel(fx, hy - 5).a > 0.0:
			for fy in fringe[i]:
				_px(img, fx, hy - 4 + fy + hair_lag, hair)
	# lit streaks catching the top-left key
	_draw_line_img(img, cx - 7, hy - 6 + hair_lag, cx - 4, hy - 10 + hair_lag, hair_hi)
	_px(img, cx - 3, hy - 10 + hair_lag, hair_hi)
	_px(img, cx + 1, hy - 11 + hair_lag, hair_hi.darkened(0.25))
	_dither_rect(img, cx + 3, hy - 9 + hair_lag, 6, 5, hair_sh, hair, true)
	_vc_hair_spikes(img, cx, hy - 11 + hair_lag, hair, hair_hi, hair_lag)

## Silhouette breakers. A smooth dome reads as a helmet; spikes read as hair.
func _vc_hair_spikes(img: Image, cx: int, top: int, hair: Color, hair_hi: Color, hair_lag: int) -> void:
	var sx_off: Array[int] = [-7, -5, -2, 1, 4, 7]
	var sh_len: Array[int] = [1, 2, 1, 3, 2, 1]
	for i in 6:
		var sx := cx + sx_off[i] + (1 if hair_lag > 0 else 0)
		for k in sh_len[i]:
			_px(img, sx, top - k, hair if k < sh_len[i] - 1 else hair_hi.darkened(0.2))

## The face. Tired but determined: heavy brows angled inward, a white-hot
## catch-light in each eye, and the eye bags that paid for the ambition.
func _vc_face(img: Image, cx: int, hy: int, pose: String, side: bool,
		skin: Color, skin_sh: Color, skin_hi: Color, eye: Color, brow: Color) -> void:
	var ex_l := cx - 6
	var ex_r := cx + 3
	if side:
		ex_l = cx + 2
		ex_r = cx + 2
		# a nose and a lip you can read in profile
		_px(img, cx + 8, hy + 1, skin_sh)
		_px(img, cx + 9, hy + 2, skin_sh)
		_px(img, cx + 8, hy + 3, skin.darkened(0.08))
		_px(img, cx + 7, hy + 5, skin_sh.darkened(0.15))
	var sclera := Color(0.95, 0.96, 1.0)
	var closed := pose == "blink" or pose == "hurt" or pose == "celebrate"
	var wide := pose == "panic" or pose == "dash" or pose == "cast_release"
	var count := 1 if side else 2
	for i in count:
		var ex: int = ex_l if i == 0 else ex_r
		if closed:
			if pose == "celebrate":
				# shut in a grin: an upward arc
				_px(img, ex, hy + 1, eye)
				_px(img, ex + 1, hy, eye)
				_px(img, ex + 2, hy + 1, eye)
			else:
				_fill_rect(img, ex, hy, 3, 1, eye)
		else:
			_fill_rect(img, ex, hy, 3, 2, sclera)
			# the pupil drifts to the inner corner: he is looking at the problem.
			# One pixel wide, not two — at two it swallowed the sclera and the
			# eye read as a dark block, which is a face with no gaze in it.
			_fill_rect(img, ex + (2 if i == 0 else 0), hy, 1, 2, eye)
			_px(img, ex + 1, hy + 1, eye.lerp(sclera, 0.45))
			if wide:
				_fill_rect(img, ex, hy - 1, 3, 1, sclera)
			_px(img, ex + (0 if i == 0 else 2), hy, WHITE_HOT)
		if i == 0:
			_draw_line_img(img, ex, hy - 3, ex + 2, hy - 2, brow)
		else:
			_draw_line_img(img, ex + 2, hy - 3, ex, hy - 2, brow)
		_fill_rect(img, ex, hy + 2, 3, 1, skin_sh.darkened(0.18))
		_dither_rect(img, ex, hy + 3, 3, 1, skin_sh, skin, true)
	var mx := cx + (3 if side else 0)
	if not side:
		_px(img, cx, hy + 3, skin_sh)
		_px(img, cx, hy + 4, skin_sh.darkened(0.10))
	if pose == "celebrate":
		_fill_rect(img, mx - 3, hy + 5, 7, 2, Color(0.30, 0.12, 0.16))
		_fill_rect(img, mx - 3, hy + 5, 7, 1, Color(0.95, 0.95, 1.0))
	elif pose == "panic" or pose == "hurt":
		_fill_rect(img, mx - 2, hy + 5, 4, 3, Color(0.26, 0.10, 0.13))
		_fill_rect(img, mx - 2, hy + 5, 4, 1, Color(0.55, 0.30, 0.30))
	elif pose == "cast" or pose == "cast_release" or pose == "dash":
		_fill_rect(img, mx - 2, hy + 5, 5, 1, skin_sh.darkened(0.30))
		_px(img, mx + 3, hy + 4, skin_sh.darkened(0.20))
	else:
		# a flat line of quiet determination, with a lit lower lip under it
		_fill_rect(img, mx - 2, hy + 5, 4, 1, skin_sh.darkened(0.45))
		_px(img, mx + 2, hy + 5, skin_sh.darkened(0.28))
		_fill_rect(img, mx - 1, hy + 6, 3, 1, skin.lightened(0.06))
	_px(img, cx - 7, hy + 2, skin_hi)   # cheek catch
	_px(img, cx - 7, hy - 2, skin_hi)

## Over-ear cups with a band that arcs across the top of the hair, and an LED
## small enough to read as a light instead of a sticker.
func _vc_headphones(img: Image, cx: int, hy: int, side: bool,
		cup: Color, cup_hi: Color, glow: Color) -> void:
	_arc_band(img, cx, hy + 1, 11, cup, cup_hi, hy - 4)
	if side:
		_fill_round_rect(img, cx - 6, hy - 3, 5, 9, cup)
		_fill_rect(img, cx - 6, hy - 2, 1, 7, cup_hi)
		_fill_round_rect(img, cx - 5, hy - 2, 3, 7, cup.lightened(0.12))
		_px(img, cx - 6, hy, WHITE_HOT)
		_px(img, cx - 6, hy + 1, glow)
		return
	for k: int in [-1, 1]:
		var x0: int = cx - 10 if k < 0 else cx + 7
		_fill_round_rect(img, x0, hy - 4, 4, 9, cup)
		_fill_rect(img, x0, hy - 3, 1, 7, cup_hi)
		_fill_round_rect(img, x0 + 1, hy - 3, 2, 7, cup.lightened(0.14))
		# the LED that says the noise cancelling is doing what it can
		var lx0: int = x0 if k < 0 else x0 + 3
		_px(img, lx0, hy, WHITE_HOT)
		_px(img, lx0, hy + 1, glow)
		_px(img, lx0, hy - 1, glow.darkened(0.40))

## One emissive accent each, per the bible.
func _vc_accessory(img: Image, cx: int, ty: int, hy: int, head_dx: int,
		accessory: String, up: bool, glow: Color, skin_hi: Color) -> void:
	var cxx := cx + head_dx
	if accessory == "tie" and not up:
		for tyy in range(ty + 3, ty + 15):
			var tw: int = 2 if tyy < ty + 6 else 3
			_fill_rect(img, cx - tw / 2, tyy, tw, 1, Color(0.72, 0.13, 0.18))
		_px(img, cx, ty + 4, Color(0.92, 0.32, 0.36))
		_glow_core(img, cx + 7, ty + 6, glow)
	elif accessory == "glasses" and not up:
		_fill_rect(img, cxx - 6, hy - 1, 5, 4, Color(0.10, 0.11, 0.14))
		_fill_rect(img, cxx + 2, hy - 1, 5, 4, Color(0.10, 0.11, 0.14))
		_fill_rect(img, cxx - 5, hy, 3, 2, Color(0.16, 0.20, 0.26))
		_fill_rect(img, cxx + 3, hy, 3, 2, Color(0.16, 0.20, 0.26))
		_fill_rect(img, cxx - 2, hy, 4, 1, Color(0.10, 0.11, 0.14))
		_px(img, cxx - 5, hy, glow)          # monitor glare, permanent
		_px(img, cxx + 3, hy, WHITE_HOT)
	elif accessory == "shades" and not up:
		# sunglasses at 3am. Nobody has ever asked why.
		_fill_rect(img, cxx - 8, hy - 1, 17, 4, Color(0.06, 0.06, 0.09))
		_fill_rect(img, cxx - 8, hy - 1, 17, 1, Color(0.20, 0.21, 0.27))
		_fill_rect(img, cxx - 1, hy, 3, 2, Color(0.12, 0.12, 0.16))
		_px(img, cxx - 6, hy, WHITE_HOT)
		_px(img, cxx - 5, hy + 1, glow)
		_px(img, cxx + 4, hy, glow.darkened(0.40))
	elif accessory == "hardhat":
		_fill_ellipse(img, cxx, hy - 5, 9, 5, Color(0.95, 0.62, 0.12))
		_fill_rect(img, cxx - 11, hy - 4, 22, 2, Color(0.95, 0.62, 0.12))
		_fill_rect(img, cxx - 11, hy - 4, 22, 1, Color(1.0, 0.80, 0.32))
		_fill_rect(img, cxx - 11, hy - 2, 22, 1, Color(0.55, 0.34, 0.07))
		_draw_line_img(img, cxx, hy - 10, cxx, hy - 5, Color(0.70, 0.44, 0.09))
		_glow_core(img, cxx, hy - 6, Color(1.0, 0.88, 0.45))
	elif accessory == "circuit" and not up:
		# a faint circuit trace across the hoodie, softly alive
		_draw_line_img(img, cx + 2, ty + 8, cx + 7, ty + 8, glow.darkened(0.42))
		_draw_line_img(img, cx + 7, ty + 8, cx + 7, ty + 5, glow.darkened(0.42))
		_draw_line_img(img, cx - 6, ty + 4, cx - 6, ty + 8, glow.darkened(0.55))
		_glow_core(img, cx + 7, ty + 4, glow)
	if accessory == "glasses" or accessory == "shades":
		_px(img, cxx - 7, hy - 2, skin_hi)

func _vc_pose_props(img: Image, cx: int, ty: int, hy: int, head_dx: int, pose: String,
		frame_idx: int, glow: Color, skin: Color, skin_hi: Color) -> void:
	match pose:
		"phone":
			_fill_round_rect(img, cx + 8, ty + 6, 7, 11, Color(0.08, 0.08, 0.12))
			_fill_rect(img, cx + 9, ty + 7, 5, 8, glow.darkened(0.60))
			_fill_rect(img, cx + 9, ty + 8, 5, 1, glow.darkened(0.20))
			_fill_rect(img, cx + 9, ty + 10, 4, 1, glow.darkened(0.20))
			_fill_rect(img, cx + 9, ty + 12, 5, 1, glow.darkened(0.35))
			_glow_core(img, cx + 12, ty + 15, glow)  # a notification he will not answer
			_fill_rect(img, cx + 3 + head_dx, hy + 3, 4, 1, skin_hi.lerp(glow, 0.35))
		"laptop":
			_fill_rect(img, cx - 12, ty + 7, 24, 14, Color(0.06, 0.08, 0.12))
			_fill_rect(img, cx - 12, ty + 7, 24, 1, Color(0.20, 0.25, 0.34))
			_fill_rect(img, cx - 12, ty + 7, 1, 14, Color(0.20, 0.25, 0.34))
			_fill_rect(img, cx - 11, ty + 8, 22, 12, Color(0.04, 0.06, 0.09))
			# code that is definitely fine
			for lrow in 5:
				var ly := ty + 9 + lrow * 2
				var lw := 4 + ((lrow * 7 + frame_idx * 3) % 12)
				var lcol := glow.darkened(0.28) if lrow % 2 == 0 else Color(0.55, 0.36, 0.95)
				_fill_rect(img, cx - 10, ly, lw, 1, lcol)
			_px(img, cx + 7, ty + 18, WHITE_HOT)  # cursor, blinking in spirit
			_fill_rect(img, cx - 12, ty + 21, 24, 1, Color(0.14, 0.17, 0.24))
			# screen bounce on the chin — the only light he gets
			_fill_rect(img, cx - 4 + head_dx, hy + 5, 8, 1, skin_hi.lerp(glow, 0.30))
			_fill_rect(img, cx - 6 + head_dx, hy + 4, 2, 1, skin_hi.lerp(glow, 0.18))
		"coffee":
			_fill_round_rect(img, cx + 12, ty + 5, 7, 9, Color(0.86, 0.38, 0.16))
			_fill_rect(img, cx + 12, ty + 5, 7, 1, Color(0.98, 0.55, 0.26))
			_fill_rect(img, cx + 12, ty + 5, 1, 9, Color(0.98, 0.55, 0.26))
			_fill_rect(img, cx + 13, ty + 8, 5, 1, Color(0.62, 0.24, 0.09))
			_fill_rect(img, cx + 19, ty + 7, 2, 4, Color(0.60, 0.25, 0.09))
			_fill_round_rect(img, cx + 10, ty + 8, 4, 4, skin)   # the hand that holds it
			_fill_rect(img, cx + 10, ty + 11, 4, 1, skin.darkened(0.24))
			_px(img, cx + 13, ty + 5, WHITE_HOT)
			for i in 4:
				_px(img, cx + 14 + (i % 2), ty + 2 - i * 2, Color(0.85, 0.90, 1.0, 0.45 - float(i) * 0.09))
		"celebrate":
			var confetti: Array[Color] = [Color(1, 0.83, 0.3), Color(0.14, 0.94, 0.86),
				Color(1, 0.18, 0.58), Color(0.6, 0.4, 1.0)]
			for i in 11:
				var px := cx - 16 + ((i * 47) % 33)
				var py := hy - 15 + ((i * 31) % 11)
				_px(img, px, py, confetti[i % 4])
				if i % 3 == 0:
					_px(img, px, py + 1, confetti[i % 4].darkened(0.35))
			_glow_core(img, cx - 12, hy - 12, Color(1.0, 0.85, 0.35))
			_glow_core(img, cx + 13, hy - 10, Color(0.35, 1.0, 0.9))
		"panic":
			for i in 3:
				_px(img, cx - 11 + i * 10, hy - 13, Color(0.45, 0.75, 1.0, 0.45))
				_px(img, cx - 13 + i * 11, hy - 11, Color(0.45, 0.75, 1.0, 0.30))
		"dash":
			# speed streaks, deliberately under the outline's alpha threshold
			for i in 4:
				var sy := ty + 2 + i * 5
				_streak(img, cx - 14 - i, sy, cx - 26 - i * 2, sy, Color(glow.r, glow.g, glow.b, 0.42))
			_streak(img, cx - 12, hy - 6, cx - 24, hy - 8, Color(glow.r, glow.g, glow.b, 0.34))
		"cast":
			# a prompt charging in the cocked hand
			_fill_circle(img, cx + 15, ty + 1, 2, Color(glow.r, glow.g, glow.b, 0.55))
			_glow_core(img, cx + 15, ty + 1, glow)
		"cast_release":
			# the release: white-hot core, accent ring, three shard rays
			_fill_circle(img, cx + 19, ty + 6, 4, Color(glow.r, glow.g, glow.b, 0.40))
			_fill_circle(img, cx + 19, ty + 6, 2, glow)
			_glow_core(img, cx + 19, ty + 6, WHITE_HOT)
			for d: int in [-1, 0, 1]:
				_streak(img, cx + 22, ty + 6 + d * 2, cx + 28, ty + 6 + d * 5,
					Color(glow.r, glow.g, glow.b, 0.45))
			# follow-through: the hem snaps back a frame behind the arm
			_streak(img, cx - 12, ty + 16, cx - 18, ty + 19, Color(glow.r, glow.g, glow.b, 0.28))

## A robe or coat that falls to the floor: it widens, gathers, and (for a coat)
## hangs open over whatever it is selling.
func _vc_skirt(img: Image, cx: int, y0: int, y1: int, base: Color, hi: Color,
		sh: Color, open_front: bool = false) -> void:
	var rows := y1 - y0
	for i in rows + 1:
		var y := y0 + i
		var hw := 9 + int(float(i) * 0.42)
		for x in range(cx - hw, cx + hw + 1):
			var u := x - (cx - hw)
			var c := base
			if u == 0:
				c = hi
			elif u <= 2:
				c = base.lightened(0.08) if ((x / 2 + y / 2) % 2 == 0) else base
			elif u >= hw * 2:
				c = sh.darkened(0.25)
			elif u >= hw * 2 - 2:
				c = sh
			_px(img, x, y, c)
		# vertical gathers: a robe without folds is a traffic cone
		for k: int in [-6, -1, 4]:
			_px(img, cx + k + int(float(i) * 0.2), y, sh)
		if open_front and i < rows - 1:
			_fill_rect(img, cx - 4, y, 8, 1, sh.darkened(0.45))
			_px(img, cx - 5, y, hi.darkened(0.20))
			_px(img, cx + 4, y, sh)
	var hw_end := 9 + int(float(rows) * 0.42)
	_fill_rect(img, cx - hw_end, y1, hw_end * 2 + 1, 1, sh.darkened(0.35))

func _vc_back_prop(img: Image, cx: int, ty: int, back: String,
		base: Color, hi: Color, sh: Color, glow: Color) -> void:
	if back == "backpack":
		# a bag rated for a laptop and the confidence of a first sprint
		_fill_round_rect(img, cx - 15, ty + 2, 11, 16, Color(0.32, 0.24, 0.42))
		_fill_rect(img, cx - 15, ty + 3, 1, 14, Color(0.46, 0.36, 0.58))
		_fill_rect(img, cx - 14, ty + 7, 9, 1, Color(0.20, 0.15, 0.28))
		_fill_round_rect(img, cx - 14, ty + 9, 7, 5, Color(0.26, 0.19, 0.35))
		_glow_core(img, cx - 11, ty + 11, glow)
		_fill_round_rect(img, cx + 5, ty + 2, 10, 15, Color(0.28, 0.21, 0.38))
	elif back == "cape":
		_fill_ellipse(img, cx, ty + 9, 14, 11, sh.darkened(0.30))
		_fill_ellipse(img, cx, ty + 8, 13, 10, sh)

## The one stupid object each archetype refuses to put down.
func _vc_npc_prop(img: Image, cx: int, ty: int, hy: int, head_dx: int, prop: String,
		glow: Color, skin: Color, skin_sh: Color) -> void:
	match prop:
		"noodles":
			# instant noodles: the load-bearing dependency of open source
			_fill_round_rect(img, cx + 8, ty + 7, 9, 7, Color(0.92, 0.90, 0.84))
			_fill_rect(img, cx + 8, ty + 7, 9, 1, Color(1.0, 0.99, 0.95))
			_fill_rect(img, cx + 8, ty + 9, 9, 1, Color(0.86, 0.24, 0.22))
			_fill_rect(img, cx + 8, ty + 11, 9, 1, Color(0.86, 0.24, 0.22))
			_fill_rect(img, cx + 9, ty + 6, 7, 1, Color(0.95, 0.78, 0.35))
			_draw_line_img(img, cx + 11, ty + 6, cx + 15, ty + 1, Color(0.72, 0.62, 0.45))
			_draw_line_img(img, cx + 12, ty + 6, cx + 17, ty + 2, Color(0.72, 0.62, 0.45))
			for i in 3:
				_px(img, cx + 10 + i, ty + 3 - i * 2, Color(0.85, 0.90, 1.0, 0.40 - float(i) * 0.10))
		"mug":
			# a mug sized for someone who has stopped counting
			_fill_round_rect(img, cx + 8, ty + 5, 10, 12, Color(0.20, 0.23, 0.32))
			_fill_rect(img, cx + 8, ty + 5, 10, 2, Color(0.32, 0.36, 0.47))
			_fill_rect(img, cx + 9, ty + 7, 8, 1, Color(0.28, 0.16, 0.09))
			_fill_rect(img, cx + 18, ty + 8, 2, 5, Color(0.26, 0.29, 0.38))
			_fill_rect(img, cx + 10, ty + 10, 6, 4, Color(0.14, 0.16, 0.23))
			_px(img, cx + 12, ty + 12, Color(0.95, 0.35, 0.30))
			for i in 3:
				_px(img, cx + 12 + (i % 2), ty + 3 - i * 2, Color(0.85, 0.90, 1.0, 0.42 - float(i) * 0.11))
		"pager":
			_fill_round_rect(img, cx - 13, ty + 12, 7, 5, Color(0.14, 0.15, 0.20))
			_fill_rect(img, cx - 12, ty + 13, 5, 3, Color(0.55, 0.08, 0.10))
			_glow_core(img, cx - 10, ty + 14, Color(1.0, 0.28, 0.28))
		"tablet":
			# a stone tablet. The answer is correct. The answer is from 2011.
			_fill_rect(img, cx + 6, ty + 3, 13, 17, Color(0.44, 0.42, 0.36))
			_fill_rect(img, cx + 6, ty + 3, 13, 1, Color(0.58, 0.56, 0.48))
			_fill_rect(img, cx + 6, ty + 3, 1, 17, Color(0.58, 0.56, 0.48))
			_fill_rect(img, cx + 18, ty + 4, 1, 16, Color(0.28, 0.27, 0.23))
			for i in 4:
				_fill_rect(img, cx + 8, ty + 7 + i * 3, 4 + (i * 3) % 7, 1, Color(0.30, 0.29, 0.25))
			_draw_line_img(img, cx + 9, ty + 15, cx + 11, ty + 17, Color(0.35, 0.95, 0.5))
			_draw_line_img(img, cx + 11, ty + 17, cx + 16, ty + 10, Color(0.35, 0.95, 0.5))
			_glow_core(img, cx + 13, ty + 13, Color(0.45, 1.0, 0.6))
		"keys":
			# a coat lining of API keys, each one limited-time
			_fill_rect(img, cx - 11, ty + 5, 22, 12, Color(0.09, 0.08, 0.12))
			_fill_rect(img, cx - 11, ty + 5, 22, 1, Color(0.22, 0.19, 0.28))
			for i in 4:
				var kx := cx - 10 + i * 6
				_fill_rect(img, kx, ty + 7, 4, 8, Color(0.12, 0.13, 0.18))
				_fill_rect(img, kx, ty + 7, 4, 1, Color(0.24, 0.25, 0.32))
				_fill_rect(img, kx + 1, ty + 9, 2, 4, glow.darkened(0.35))
				_px(img, kx + 1, ty + 10, WHITE_HOT)
		"lanyard":
			# the badge that opens every door and explains nothing
			_draw_line_img(img, cx - 3, ty + 1, cx + 5, ty + 9, Color(0.10, 0.42, 0.30))
			_draw_line_img(img, cx + 5, ty + 1, cx + 7, ty + 9, Color(0.10, 0.42, 0.30))
			_fill_rect(img, cx + 3, ty + 9, 8, 7, Color(0.90, 0.92, 0.97))
			_fill_rect(img, cx + 3, ty + 9, 8, 2, glow.darkened(0.25))
			_fill_rect(img, cx + 4, ty + 12, 6, 1, Color(0.35, 0.38, 0.46))
			_fill_rect(img, cx + 4, ty + 14, 4, 1, Color(0.35, 0.38, 0.46))
			_glow_core(img, cx + 9, ty + 14, glow)
		"cloud_balloon":
			# elastic, on-demand, and tethered to nothing in particular
			_draw_line_img(img, cx + 11, ty + 8, cx + 15, hy - 6, Color(0.62, 0.68, 0.80))
			_fill_circle(img, cx + 13, hy - 11, 4, Color(0.55, 0.66, 0.82))
			_fill_circle(img, cx + 18, hy - 10, 5, Color(0.55, 0.66, 0.82))
			_fill_circle(img, cx + 13, hy - 12, 4, Color(0.82, 0.90, 1.0))
			_fill_circle(img, cx + 18, hy - 11, 4, Color(0.75, 0.85, 0.99))
			_fill_rect(img, cx + 9, hy - 10, 13, 3, Color(0.78, 0.87, 0.99))
			_fill_rect(img, cx + 9, hy - 8, 13, 1, Color(0.52, 0.62, 0.78))
			_px(img, cx + 11, hy - 13, WHITE_HOT)
		"thermal_gun":
			_fill_rect(img, cx + 8, ty + 8, 9, 3, Color(0.86, 0.56, 0.14))
			_fill_rect(img, cx + 8, ty + 8, 9, 1, Color(1.0, 0.74, 0.28))
			_fill_rect(img, cx + 10, ty + 11, 3, 5, Color(0.62, 0.38, 0.09))
			_glow_core(img, cx + 17, ty + 9, Color(1.0, 0.42, 0.20))
			for i in 3:
				_px(img, cx + 19 + i * 2, ty + 9, Color(1.0, 0.42, 0.20, 0.55 - float(i) * 0.16))
		"antenna":
			# an antenna it did not need, blinking on a frequency nobody assigned
			_draw_line_img(img, cx + 3 + head_dx, hy - 11, cx + 6 + head_dx, hy - 17, Color(0.30, 0.32, 0.40))
			_glow_core(img, cx + 6 + head_dx, hy - 18, glow)
		"buzzwords":
			# three thought bubbles, none of them containing a noun
			for i in 3:
				var bx := cx - 14 - i * 3
				var by := hy - 8 - i * 4
				_fill_circle(img, bx, by, 2 - (1 if i == 2 else 0), Color(glow.r, glow.g, glow.b, 0.40))
				_px(img, bx, by, WHITE_HOT)
		"wild_hair":
			# hair that has been slept on, then paged, then slept on again
			for i in 6:
				var hx := cx - 8 + i * 3 + head_dx
				_draw_line_img(img, hx, hy - 8, hx + (2 if i % 2 == 0 else -2),
					hy - 12 - (i % 2) * 2, Color(0.26, 0.21, 0.18))
		"thumbs_up":
			_fill_round_rect(img, cx + 9, ty + 4, 5, 6, skin)
			_fill_rect(img, cx + 10, ty + 1, 2, 4, skin)
			_px(img, cx + 10, ty + 1, skin.lightened(0.20))
			_fill_rect(img, cx + 9, ty + 9, 5, 1, skin_sh)

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
				_px(img, x, y, color)

func _generate_player_sprites() -> void:
	pass

## Per-region floor tiles. Each region gets its own MATERIAL, not just its own
## tint — you should be able to name the region from a 64px crop of its floor.
##
## BRIGHTNESS CONTRACT: region_builder draws these with modulate ≈ k * tile_mul
## (tile_mul is 1.9–2.5 per region, and the "_b" variant gets a further x1.3).
## So each tile is authored at a comfortable working value and then scaled by
## "dim" = (0.30 / tile_mul) / the material's own mean luminance, so the
## builder's multiply lands the floor back at ~0.30 luminance, right next to the
## tech-deck fallback, with no channel clipping. Scaling the finished
## image (rather than the base colour) keeps every material's relative contrast
## intact; darkening the base instead would make every lightened() highlight
## explode once the builder multiplied it back up. If tile_mul changes, "dim"
## changes with it.
func _generate_tileset() -> void:
	var regions := {
		"localhost": {"base": Color(0.42, 0.33, 0.25), "accent": Color(1.0, 0.72, 0.29), "mat": "planks", "dim": 0.39},
		"dependency": {"base": Color(0.30, 0.40, 0.26), "accent": Color(0.66, 1.0, 0.24), "mat": "sludge", "dim": 0.38},
		"stackoverflow": {"base": Color(0.50, 0.47, 0.40), "accent": Color(0.91, 0.77, 0.42), "mat": "flagstone", "dim": 0.31},
		"api_bazaar": {"base": Color(0.40, 0.30, 0.40), "accent": Color(1.0, 0.18, 0.58), "mat": "rug", "dim": 0.38},
		"cloud": {"base": Color(0.52, 0.57, 0.64), "accent": Color(0.42, 0.78, 1.0), "mat": "raised", "dim": 0.28},
		"opensource": {"base": Color(0.32, 0.38, 0.26), "accent": Color(0.35, 0.88, 0.49), "mat": "forest", "dim": 0.45},
		"corporate": {"base": Color(0.40, 0.42, 0.48), "accent": Color(0.30, 0.49, 1.0), "mat": "carpet", "dim": 0.39},
		"gpu": {"base": Color(0.44, 0.33, 0.29), "accent": Color(1.0, 0.42, 0.18), "mat": "grating", "dim": 0.37},
		"production": {"base": Color(0.42, 0.36, 0.36), "accent": Color(1.0, 0.28, 0.34), "mat": "concrete", "dim": 0.33},
		"vault": {"base": Color(0.46, 0.40, 0.28), "accent": Color(1.0, 0.83, 0.30), "mat": "vault", "dim": 0.35},
	}
	for rname in regions:
		var data: Dictionary = regions[rname]
		_save_image(_make_floor_tile(rname, data, 0), "tile_%s.png" % rname)
		_save_image(_make_floor_tile(rname, data, 7), "tile_%s_b.png" % rname)

## One seamless 64x64 floor texture. Dispatches to the region's material; the
## default is the old machined-plate treatment, kept for any region that has no
## material of its own yet.
func _make_floor_tile(rname: String, data: Dictionary, salt: int) -> Image:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var base: Color = data["base"]
	var accent: Color = data["accent"]
	var tseed: int = abs(rname.hash() % 100000) + salt * 977
	match String(data.get("mat", "plate")):
		"planks":
			_mat_planks(img, base, accent, tseed)
		"sludge":
			_mat_sludge(img, base, accent, tseed)
		"flagstone":
			_mat_flagstone(img, base, accent, tseed)
		"rug":
			_mat_rug(img, base, accent, tseed)
		"raised":
			_mat_raised(img, base, accent, tseed)
		"forest":
			_mat_forest(img, base, accent, tseed)
		"carpet":
			_mat_carpet(img, base, accent, tseed)
		"grating":
			_mat_grating(img, base, accent, tseed)
		"concrete":
			# Only the "_b" variant carries painted floor markings — a hazard
			# stripe on EVERY tile would band the whole region.
			_mat_concrete(img, base, accent, tseed, salt != 0)
		"vault":
			_mat_vault(img, base, accent, tseed)
		_:
			_mat_plate(img, base, accent, tseed)
	_dim_tile(img, float(data.get("dim", 1.0)))
	return img

## Uniform value scale over a finished tile — see the brightness contract on
## _generate_tileset. Relative contrast is preserved exactly.
func _dim_tile(img: Image, k: float) -> void:
	if is_equal_approx(k, 1.0):
		return
	for x in img.get_width():
		for y in img.get_height():
			var c := img.get_pixel(x, y)
			_px(img, x, y, Color(c.r * k, c.g * k, c.b * k, c.a))

## Machined deck plating: hash noise (tiles by construction), per-plate value
## jitter, beveled 32px seams, hairline scratches, a rare plate detail.
func _mat_plate(img: Image, base: Color, accent: Color, tseed: int) -> void:
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
			_px(img, x, y, c)
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
				_px(img, px, py, img.get_pixel(px, py).darkened(0.25))
	# occasional plate detail (vent / crack / faded glyph). Subtle: it repeats.
	for cy in 2:
		for cx in 2:
			if _hash01(cx * 31 + cy * 57, 13, tseed) > 0.30:
				continue
			_tile_detail(img, cx * 32, cy * 32, accent, base, _hash01(cx, cy + 19, tseed))

## LOCALHOST — warm plank boards. Four 16px boards per tile, staggered butt
## joints, grain, one knot. Home, such as it is.
func _mat_planks(img: Image, base: Color, accent: Color, s: int) -> void:
	for y in 64:
		var row := y >> 4
		var ry := y & 15
		var pj := (_hash01(row, 3, s) - 0.5) * 0.10
		for x in 64:
			var c := base.lightened(pj) if pj > 0.0 else base.darkened(-pj)
			# Grain runs ALONG the board (streaks parallel to the plank, waving
			# down its length) — grain that varies with x alone draws vertical
			# stripes across horizontal boards and reads as brickwork.
			var g := sin(float(ry) * 1.35 + float(row) * 2.1 + sin(float(x) * 0.19635) * 1.8)
			if g > 0.72:
				c = c.darkened(0.13)
			elif g < -0.78:
				c = c.lightened(0.08)
			c = _pixel_noise(c, x, y, s, 0.035)
			if ry == 0:
				c = c.darkened(0.42)            # board seam
			elif ry == 1:
				c = c.lightened(0.14)           # lit edge (light from the top-left)
			elif ry == 15:
				c = c.darkened(0.18)
			# butt joints on every other course only, or it reads as masonry
			var joint := (x + row * 29) % 64
			if row % 2 == 0 and ry > 0:
				if joint == 0:
					c = c.darkened(0.32)
				elif joint == 1:
					c = c.lightened(0.09)
			_px(img, x, y, c)
	var kx := 12 + int(_hash01(1, 2, s) * 38.0)
	var ky := 12 + int(_hash01(3, 4, s) * 38.0)
	for ky2 in range(ky - 5, ky + 6):
		for kx2 in range(kx - 5, kx + 6):
			if kx2 < 1 or ky2 < 1 or kx2 > 62 or ky2 > 62:
				continue
			var d := Vector2(kx2 - kx, ky2 - ky).length()
			var kc := img.get_pixel(kx2, ky2)
			if d < 1.6:
				_px(img, kx2, ky2, kc.darkened(0.50))
			elif d < 3.0:
				_px(img, kx2, ky2, kc.darkened(0.24))
			elif d < 4.2:
				_px(img, kx2, ky2, kc.darkened(0.34))
	# one board edge catches the warm spill of an always-on monitor
	var ay := (int(_hash01(7, 8, s) * 4.0) << 4) + 1
	for lx in 64:
		_px(img, lx, ay, img.get_pixel(lx, ay).lerp(accent, 0.10))

## DEPENDENCY DISTRICT — node_modules. A viscous green mass with half-sunk
## package cubes in it. Nobody has ever reached the bottom.
func _mat_sludge(img: Image, base: Color, accent: Color, s: int) -> void:
	var blobs: Array[Vector3] = []
	for i in 7:
		blobs.append(Vector3(_hash01(i, 11, s) * 64.0, _hash01(i, 13, s) * 64.0, 9.0 + _hash01(i, 17, s) * 9.0))
	var lo := base.darkened(0.24)
	var hi := base.lightened(0.18)
	for y in 64:
		for x in 64:
			var field := 0.0
			for b: Vector3 in blobs:
				var dx := _wrap_d(x, int(b.x), 64)
				var dy := _wrap_d(y, int(b.y), 64)
				field += maxf(0.0, 1.0 - sqrt(dx * dx + dy * dy) / b.z)
			var c := lo.lerp(hi, clampf(field, 0.0, 1.0))
			if field > 0.90 and field < 1.04:
				c = c.lerp(accent, 0.18)     # meniscus where the ooze crests
			c = _pixel_noise(c, x, y, s, 0.05)
			_px(img, x, y, c)
	for i in 3:
		var px := int(_hash01(i, 23, s) * 64.0)
		var py := int(_hash01(i, 29, s) * 64.0)
		var sz := 6 + int(_hash01(i, 31, s) * 4.0)
		for oy in sz:
			for ox in sz:
				var cc := base.darkened(0.06)
				if oy == 0:
					cc = base.lightened(0.30)           # lit top face
				elif ox == sz - 1 or oy == sz - 1:
					cc = base.darkened(0.36)
				_px(img, (px + ox) % 64, (py + oy) % 64, cc)
		_px(img, (px + 1) % 64, (py + 1) % 64, accent.lerp(WHITE_HOT, 0.30))

## STACKOVERFLOW RUINS — cracked stone flags, wobbling joints, drifting dust.
func _mat_flagstone(img: Image, base: Color, accent: Color, s: int) -> void:
	for y in 64:
		for x in 64:
			var jv := (_hash01((x >> 5) * 7 + (y >> 5) * 13, 3, s) - 0.5) * 0.14
			var c := base.lightened(jv) if jv > 0.0 else base.darkened(-jv)
			c = _pixel_noise(c, x, y, s, 0.05)
			if _hash01(x * 3, y * 5, s) > 0.955:
				c = c.lightened(0.16)                 # aggregate speck
			var wobx := int(_hash01(y, 41, s) * 2.0)
			var woby := int(_hash01(x, 43, s) * 2.0)
			if (x & 31) == wobx or (y & 31) == woby:
				c = base.darkened(0.46)               # mortar joint
			elif (x & 31) == wobx + 1 or (y & 31) == woby + 1:
				c = c.lightened(0.12)
			elif (x & 31) == 31 or (y & 31) == 31:
				c = c.darkened(0.16)
			_px(img, x, y, c)
	# a fissure wandering down the tile, steered back to its start so it wraps
	var fx0 := 6 + int(_hash01(5, 7, s) * 50.0)
	var fx := float(fx0)
	for y in 64:
		var ix := (int(fx) % 64 + 64) % 64
		_px(img, ix, y, img.get_pixel(ix, y).darkened(0.45))
		if y > 51:
			fx += (float(fx0) - fx) * 0.28
		else:
			fx += (_hash01(ix, y, s) - 0.5) * 1.1
	for i in 10:
		var dx2 := int(_hash01(i, 51, s) * 62.0) + 1
		var dy2 := int(_hash01(i, 53, s) * 62.0) + 1
		_px(img, dx2, dy2, img.get_pixel(dx2, dy2).lerp(accent, 0.16))

## API BAZAAR — a kilim of hooked diamonds in magenta and gold. Everything
## here is for sale, the floor included.
func _mat_rug(img: Image, base: Color, accent: Color, s: int) -> void:
	var gold := Color(1.0, 0.83, 0.30)
	for y in 64:
		for x in 64:
			var mx := x & 31
			var my := y & 31
			var c := base if ((x + y) & 3) < 2 else base.darkened(0.10)
			c = _pixel_noise(c, x, y, s, 0.045)
			var dman: int = absi(mx - 16) + absi(my - 16)
			if dman == 15 or dman == 14:
				c = base.darkened(0.34)                 # diamond outline
			elif dman == 12 or dman == 11:
				c = base.lerp(accent, 0.40)             # magenta ring
			elif dman == 8:
				c = base.lerp(gold, 0.32)               # gold ring
			elif dman < 4:
				c = base.lerp(accent, 0.24) if ((mx + my) & 1) == 0 else base.lerp(gold, 0.24)
			if mx == 0 or my == 0:
				c = base.darkened(0.40)                 # guard stripe
			elif mx == 1 or my == 1:
				c = base.lerp(gold, 0.14)
			_px(img, x, y, c)
	for i in 30:
		var tx := int(_hash01(i, 61, s) * 64.0)
		var ty := int(_hash01(i, 67, s) * 64.0)
		_px(img, tx, ty, img.get_pixel(tx, ty).darkened(0.18))

## CLOUD DISTRICT — data-centre raised access floor: perforated panels on a
## pedestal grid. Cool, clean, billing by the hour.
func _mat_raised(img: Image, base: Color, accent: Color, s: int) -> void:
	for y in 64:
		for x in 64:
			var mx := x & 31
			var my := y & 31
			var pj := (_hash01(x >> 5, (y >> 5) + 3, s) - 0.5) * 0.07
			var c := base.lightened(pj) if pj > 0.0 else base.darkened(-pj)
			c = _pixel_noise(c, x, y, s, 0.03)
			if mx >= 6 and mx <= 25 and my >= 6 and my <= 25:
				if (mx & 3) == 0 and (my & 3) == 0:
					c = base.darkened(0.52)             # perforation
				elif (mx & 3) == 0 and (my & 3) == 3:
					c = base.lightened(0.14)            # lit lip below it
			if mx == 0 or my == 0:
				c = base.darkened(0.36)                 # panel gap
			elif mx == 1 or my == 1:
				c = base.lightened(0.20)                # lifted lip
			elif mx == 31 or my == 31:
				c = base.darkened(0.18)
			_px(img, x, y, c)
	for py: int in [0, 32]:
		for px: int in [0, 32]:
			for oy in 3:
				for ox in 3:
					_px(img, px + 2 + ox, py + 2 + oy, base.darkened(0.30))
			_px(img, px + 2, py + 2, base.lightened(0.34))
	_px(img, 3, 3, accent)
	_px(img, 35, 35, accent.lerp(WHITE_HOT, 0.40))

## OPEN SOURCE WILDLANDS — loam, leaf litter and moss. Maintained by one
## volunteer and a lot of weather.
func _mat_forest(img: Image, base: Color, accent: Color, s: int) -> void:
	var soil := base.darkened(0.22)
	for y in 64:
		for x in 64:
			var c := soil
			var n := _hash01(x, y, s)
			if n > 0.86:
				c = c.lightened(0.14)
			elif n < 0.12:
				c = c.darkened(0.20)
			var mfield := 0.0
			for i in 4:
				var dx := _wrap_d(x, int(_hash01(i, 71, s) * 64.0), 64)
				var dy := _wrap_d(y, int(_hash01(i, 73, s) * 64.0), 64)
				mfield += maxf(0.0, 1.0 - sqrt(dx * dx + dy * dy) / 15.0)
			if mfield > 0.55:
				c = c.lerp(accent.darkened(0.42), clampf((mfield - 0.55) * 1.6, 0.0, 0.55))
				if _hash01(x * 5, y * 3, s) > 0.90:
					c = c.lerp(accent, 0.28)            # a lit moss tip
			_px(img, x, y, c)
	for i in 22:
		var lx := int(_hash01(i, 79, s) * 64.0)
		var ly := int(_hash01(i, 83, s) * 64.0)
		var ln := 2 + int(_hash01(i, 89, s) * 3.0)
		var horiz := _hash01(i, 97, s) > 0.5
		var leaf := soil.lightened(0.22).lerp(accent, 0.12 + 0.20 * _hash01(i, 101, s))
		for j in ln:
			_px(img, (lx + (j if horiz else 0)) % 64, (ly + (0 if horiz else j)) % 64, leaf)
		_px(img, lx % 64, ly % 64, leaf.lightened(0.18))

## CORPORATE ENTERPRISE — contract carpet tile, laid quarter-turned like every
## office on earth. Flecked, forgettable, rated for ten years of nobody looking.
func _mat_carpet(img: Image, base: Color, accent: Color, s: int) -> void:
	for y in 64:
		for x in 64:
			var turned := (((x >> 5) + (y >> 5)) & 1) == 1
			var u := y if turned else x                 # pile runs per tile
			var c := base.darkened(0.06)
			if (u % 3) == 0:
				c = c.lightened(0.06)
			elif (u % 3) == 2:
				c = c.darkened(0.06)
			c = _pixel_noise(c, x, y, s, 0.05)
			var n := _hash01(x * 7, y * 11, s)
			if n > 0.955:
				c = c.lightened(0.26)                   # the procurement fleck
			elif n < 0.035:
				c = c.lerp(accent, 0.22)
			if (x & 31) == 0 or (y & 31) == 0:
				c = c.darkened(0.20)                    # tile seam, barely there
			_px(img, x, y, c)

## GPU MINES — ribbed steel deck over the heat. The slots glow because whatever
## is under them has been at 94 degrees since March.
func _mat_grating(img: Image, base: Color, accent: Color, s: int) -> void:
	for y in 64:
		var r := y & 7
		for x in 64:
			var c := base
			if r == 0:
				c = base.darkened(0.55).lerp(accent, 0.30 + 0.25 * _hash01(x, y, s))
			elif r == 1:
				c = base.lightened(0.24)                # lit lip of the rib
			elif r == 7:
				c = base.darkened(0.28)
			else:
				c = _pixel_noise(base, x, y, s, 0.045)
				if (x & 15) == 0:
					c = c.darkened(0.22)                # cross-tie
				elif (x & 15) == 1:
					c = c.lightened(0.10)
			_px(img, x, y, c)
	for i in 5:
		var ex := int(_hash01(i, 103, s) * 64.0)
		var ey := int(_hash01(i, 107, s) * 8.0) * 8
		for ox in range(-3, 4):
			var tx := (ex + ox + 64) % 64
			_px(img, tx, ey, img.get_pixel(tx, ey).lerp(accent, 0.55 - 0.12 * absf(float(ox))))
		_px(img, ex % 64, ey, accent.lerp(WHITE_HOT, 0.45))
	for i in 6:
		var sx := int(_hash01(i, 109, s) * 64.0)
		var sy := int(_hash01(i, 113, s) * 64.0)
		_px(img, sx, sy, img.get_pixel(sx, sy).darkened(0.30))

## PRODUCTION — poured slab under an alarm light: patch repairs, map cracks,
## and a hazard stripe someone painted the week before the incident.
func _mat_concrete(img: Image, base: Color, accent: Color, s: int, marked: bool) -> void:
	for y in 64:
		for x in 64:
			var c := _pixel_noise(base, x, y, s, 0.055)
			if _hash01(x * 5, y * 7, s) > 0.965:
				c = c.lightened(0.14)                   # aggregate
			var pf := 0.0
			for i in 3:
				var dx := _wrap_d(x, int(_hash01(i, 127, s) * 64.0), 64)
				var dy := _wrap_d(y, int(_hash01(i, 131, s) * 64.0), 64)
				pf = maxf(pf, 1.0 - sqrt(dx * dx + dy * dy) / 17.0)
			if pf > 0.0:
				c = c.lerp(base.darkened(0.16), clampf(pf, 0.0, 0.70))
			var band := 1.0 - absf(float(y) - 40.0) / 22.0
			if band > 0.0:
				c = c.lerp(accent, 0.07 * band)         # the alarm stains everything
			# sawn control joints on a 32px grid — poured slabs always have them
			if (x & 31) == 0 or (y & 31) == 0:
				c = c.darkened(0.30)
			elif (x & 31) == 1 or (y & 31) == 1:
				c = c.lightened(0.07)
			_px(img, x, y, c)
	if marked:
		# Faded hazard stripe. Someone painted this the week before the incident.
		for hx in 64:
			for hy in range(11, 16):
				var stripe := (((hx + hy * 2) >> 2) & 1) == 0
				var c := accent.darkened(0.42) if stripe else base.darkened(0.34)
				if hy == 11:
					c = c.lightened(0.12)
				elif hy == 15:
					c = c.darkened(0.20)
				# worn through in patches: the paint lost
				if _hash01(hx * 3, hy, s) > 0.62:
					c = c.lerp(base, 0.55)
				_px(img, hx, hy, c)
	for i in 4:
		var ax := 6.0 + _hash01(i, 137, s) * 52.0
		var ay := 26.0 + _hash01(i, 139, s) * 34.0
		var ang := _hash01(i, 149, s) * TAU
		for j in 12:
			var tx := (int(ax + cos(ang) * float(j)) % 64 + 64) % 64
			var ty := (int(ay + sin(ang) * float(j)) % 64 + 64) % 64
			_px(img, tx, ty, img.get_pixel(tx, ty).darkened(0.34))
			ang += (_hash01(j, i, s) - 0.5) * 0.5

## TOKEN VAULT — dark marble, gold veining, inlaid coins. The only region where
## the floor is itself an asset class.
func _mat_vault(img: Image, base: Color, accent: Color, s: int) -> void:
	for y in 64:
		for x in 64:
			var c := _pixel_noise(base.darkened(0.18), x, y, s, 0.05)
			var v := sin(float(x) * 0.11 + sin(float(y) * 0.09) * 2.4) + sin(float(y) * 0.13)
			if v > 1.1:
				c = c.lightened(0.10)
			elif v < -1.2:
				c = c.darkened(0.12)
			if (x & 31) == 0 or (y & 31) == 0:
				c = base.darkened(0.44)
			elif (x & 31) == 1 or (y & 31) == 1:
				c = c.lightened(0.14)
			_px(img, x, y, c)
	# gold veins, steered back to their start so they wrap cleanly. Two of them,
	# hairline: this is marble with gold IN it, not gold with marble in it.
	for i in 2:
		var vy0 := 10.0 + _hash01(i, 151, s) * 44.0
		var vy := vy0
		for x in 64:
			var iy := (int(vy) % 64 + 64) % 64
			_px(img, x, iy, base.lerp(accent, 0.44))
			if (x & 3) == 0:
				_px(img, x, (iy + 1) % 64, base.lerp(accent, 0.18))
			if x > 51:
				vy += (vy0 - vy) * 0.28
			else:
				vy += (_hash01(x, i * 17, s) - 0.5) * 1.0
	# Two inlaid coins per tile, on opposite 32px cells so the repeat reads as
	# scattered rather than as a grid of coins.
	for cn: int in [0, 1]:
		var cx: int = 8 if cn == 0 else 40
		var cy: int = 40 if cn == 0 else 8
		var ox := cx + int(_hash01(cx, cy, s) * 12.0)
		var oy := cy + int(_hash01(cy, cx, s) * 12.0)
		for dy in range(-4, 5):
			for dx in range(-4, 5):
				if Vector2(dx, dy).length() > 4.2:
					continue
				var col := base.lerp(accent, 0.55)
				if dx + dy < -2:
					col = base.lerp(accent, 0.82)       # lit top-left
				elif dx + dy > 2:
					col = base.lerp(accent, 0.30)
				_px(img, (ox + dx + 64) % 64, (oy + dy + 64) % 64, col)
		_px(img, (ox - 2 + 64) % 64, (oy - 2 + 64) % 64, WHITE_HOT)

## Toroidal distance on one axis — the reason blobs and clumps above can sit
## anywhere in the tile and still tile seamlessly against themselves.
func _wrap_d(a: int, b: int, period: int) -> float:
	var d: int = absi(a - b)
	return float(mini(d, period - d))

## Deterministic +-amt value jitter on a single pixel. Tiles by construction.
func _pixel_noise(c: Color, x: int, y: int, s: int, amt: float) -> Color:
	var n := (_hash01(x, y, s) - 0.5) * amt * 2.0
	return c.lightened(n) if n > 0.0 else c.darkened(-n)

func _tile_detail(img: Image, ox: int, oy: int, accent: Color, base: Color, roll: float) -> void:
	var dxp := ox + 8 + int(roll * 14.0)
	var dyp := oy + 8 + int(roll * 11.0)
	if roll < 0.34:
		# vent: three dark slits, each with a faint lit lip
		for i in 3:
			_fill_rect(img, dxp, dyp + i * 2, 8, 1, base.darkened(0.5))
			_px(img, dxp, dyp + i * 2, base.lightened(0.10))
	elif roll < 0.67:
		# hairline crack wandering down-right
		var px := dxp
		var py := dyp
		for i in 7:
			_px(img, mini(px, 63), mini(py, 63), base.darkened(0.45))
			if _hash01(px, py, i) > 0.4:
				px += 1
			py += 1
	else:
		# a faded accent glyph — a maintenance mark nobody remembers painting
		var dim := base.lerp(accent, 0.22)
		_fill_rect(img, dxp, dyp, 5, 1, dim)
		_fill_rect(img, dxp, dyp, 1, 4, dim)
		_px(img, dxp + 4, dyp + 3, base.lerp(accent, 0.35))

## Enemy threat colours. Deliberately hot and saturated: an enemy is the one
## thing on screen that MUST NOT be missed, and the regions it walks through are
## near-black. Each sprite is finished with the readability chain below —
## value expansion, midtone lift, hot rim, hard outline, threat halo, contact
## shadow — so it reads as DANGER before the player has consciously identified
## what it is.
##
## Round 5, from the QA frames: the round-4 enemies were legible in isolation and
## mush at game zoom. Three causes, all fixed here. (1) Every region's
## CanvasModulate multiplies the whole canvas toward the floor's value, so a
## sprite with a narrow internal value range collapses into one flat blob —
## hence `_value_expand`, which widens the range in BOTH directions before
## anything else runs. (2) Hue contrast does not survive a coloured ambient (a
## red beetle in the red-lit GPU Mines is a red smudge on a red floor) but a
## near-white pixel does, so every type now carries a white-hot "tell" and a
## near-white rim. (3) One-pixel appendages came back from the outline+halo
## passes as dithered noise, so limbs are two pixels minimum (`_thick_line`).
func _generate_enemies() -> void:
	var enemies := {
		"bug": Color(1.0, 0.26, 0.34),
		"null_reference": Color(0.74, 0.24, 1.0),
		"rate_limiter": Color(1.0, 0.78, 0.16),
		"scope_creep": Color(0.44, 0.96, 0.44),
		"dependency_demon": Color(1.0, 0.28, 0.62),
		"legacy_system": Color(0.80, 0.72, 0.52),
		"memory_leak": Color(0.28, 0.64, 1.0),
		"hallucination": Color(1.0, 0.58, 1.0),
		"merge_conflict": Color(1.0, 0.46, 0.14),
		"cloud_bill": Color(0.22, 0.95, 0.44),
		"enterprise_architect": Color(0.44, 0.56, 1.0),
		"legacy_monolith": Color(0.72, 0.64, 0.48),
		"infinite_context": Color(0.62, 0.30, 1.0),
	}
	# The five types region_builder can spawn with boss=true. They get a second,
	# richer texture under an ADDITIVE filename; the base file is untouched, so
	# nothing breaks if no consumer ever asks for it.
	var boss_kinds: Array[String] = ["merge_conflict", "cloud_bill",
		"enterprise_architect", "legacy_monolith", "infinite_context"]
	for ename in enemies:
		var c: Color = enemies[ename]
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		_draw_enemy(img, str(ename), c)
		_finish_enemy(img, c, false)
		_save_image(img, "enemy_%s.png" % ename)
		if boss_kinds.has(str(ename)):
			var bimg := Image.create(32, 32, false, Image.FORMAT_RGBA8)
			bimg.fill(Color(0, 0, 0, 0))
			_draw_boss(bimg, str(ename), c)
			_finish_enemy(bimg, c, true)
			_save_image(bimg, "enemy_%s_boss.png" % ename)

## One dispatch, so the boss pass can re-draw the same body without duplicating
## the table.
func _draw_enemy(img: Image, ename: String, c: Color) -> void:
	match ename:
		"bug":
			_draw_bug(img, c)
		"rate_limiter":
			_draw_rate_limiter(img, c)
		"memory_leak":
			_draw_memory_leak(img, c)
		"merge_conflict":
			_draw_merge_conflict(img, c)
		"scope_creep":
			_draw_scope_creep(img, c)
		"dependency_demon":
			_draw_dependency_demon(img, c)
		"hallucination":
			_draw_hallucination(img, c)
		"legacy_monolith":
			_draw_legacy_monolith(img, c)
		"infinite_context":
			_draw_infinite_context(img, c)
		"enterprise_architect":
			_draw_enterprise_architect(img, c)
		"null_reference":
			_draw_null_reference(img, c)
		"legacy_system":
			_draw_legacy_system(img, c)
		"cloud_bill":
			_draw_cloud_bill(img, c)
		_:
			_draw_glow_blob(img, c)

## The readability chain. Order matters: widen the value range and lift the
## muddy midtones BEFORE the outline goes down (so the outline stays the darkest
## thing on the sprite), sink the underside so the creature has weight, and
## stamp the ground shadow last, into whatever is still empty, so it never eats
## the halo.
func _finish_enemy(img: Image, c: Color, boss: bool) -> void:
	var threat: Color = _vivid_color(c)
	_value_expand(img, 0.34, 0.48 if boss else 0.42)
	_readability_pass(img, 0.32, 0.36, 0.30 if boss else 0.26)
	_underside_ao(img, 4, 0.48 if boss else 0.44)
	_rim_light_pass(img, threat.lerp(WHITE_HOT, 0.55), 0.66 if boss else 0.62)
	_outline_silhouette(img, OUTLINE_ENEMY)
	_threat_halo(img, threat)
	if boss:
		_boss_aureole(img, threat)
	_contact_shadow(img)

## A broken ring of light BEHIND a boss, stamped only where nothing solid lives,
## so it can never disturb the outline or the silhouette. Bosses are backlit;
## normal enemies are not. At the 4x a boss renders at, that difference is
## visible from across the arena, which is the whole point of it.
##
## The threshold is 0.7, not 0.05: this runs after _threat_halo, whose two rings
## occupy exactly the band the aureole wants (alpha 0.55 and 0.19). Skipping
## anything already painted would have left the aureole as a few stray pixels.
## 0.7 clears both halo rings while still protecting the opaque body (>= 0.94
## even on the translucent types) and the OUTLINE_ENEMY edge (0.97).
func _boss_aureole(img: Image, accent: Color) -> void:
	var glow := accent.lerp(WHITE_HOT, 0.45)
	for x in 32:
		for y in 32:
			if img.get_pixel(x, y).a > 0.7:
				continue
			var d := Vector2(x - 16, y - 16).length()
			if d < 12.0:
				continue
			var ang := atan2(float(y - 16), float(x - 16))
			var spike: bool = cos(ang * 8.0) > 0.5
			var lim: float = 15.4 if spike else 13.6
			if d > lim:
				continue
			_px(img, x, y, Color(glow.r, glow.g, glow.b, 0.62 if spike else 0.34))

## What makes each boss its own creature rather than the same one at 200%. Every
## extra is drawn INSIDE the 32px canvas the base sprite already uses, so the
## boss texture is a drop-in swap: same size, same scale, same collider.
func _boss_extras(img: Image, kind: String, c: Color) -> void:
	var hot := Color(1.0, 0.90, 0.56)
	match kind:
		"merge_conflict":
			# a third faction. Somebody force-pushed.
			for x in 32:
				for y in 32:
					if img.get_pixel(x, y).a <= 0.5:
						continue
					if y > 22 and absi(x - 16) < (y - 22) * 3:
						_px(img, x, y, Color(0.22, 0.62, 0.26) if (x + y) % 2 == 0 else Color(0.10, 0.36, 0.16))
			for y2 in 32:
				var seam := 16 + int(sin(float(y2) * 0.6) * 1.6)
				_over_px(img, seam - 1, y2, Color(1.0, 0.62, 0.20) if y2 % 3 == 0 else Color(0.03, 0.03, 0.06))
			_glow_lamp(img, 16, 4, hot, 1)
			_glow_lamp(img, 15, 28, hot, 1)
		"cloud_bill":
			# a thundercloud. The invoice is now weather.
			var storm := Color(0.17, 0.21, 0.36)
			for x2 in 32:
				for y3 in 18:
					var p := img.get_pixel(x2, y3)
					if p.a > 0.5:
						_px(img, x2, y3, Color(p.r + (storm.r - p.r) * 0.62,
							p.g + (storm.g - p.g) * 0.62,
							p.b + (storm.b - p.b) * 0.55, p.a))
			for ex: int in [11, 18]:
				_fill_rect(img, ex, 9, 5, 3, Color(0.90, 0.93, 1.0))
				_fill_rect(img, ex + 1, 10, 2, 2, Color(0.04, 0.05, 0.10))
			for bi in 2:
				var bx: int = 5 if bi == 0 else 27
				var sgn: int = -1 if bi == 0 else 1
				_thick_line(img, bx, 16, bx + sgn * 2, 21, Color(1.0, 0.94, 0.62))
				_draw_line_img(img, bx, 16, bx + sgn * 2, 21, WHITE_HOT)
				_thick_line(img, bx + sgn * 2, 21, bx - sgn, 27, Color(1.0, 0.94, 0.62))
				_draw_line_img(img, bx + sgn * 2, 21, bx - sgn, 27, WHITE_HOT)
		"enterprise_architect":
			# a crown. He did not ask for it. He will not be giving it back.
			var gold := Color(1.0, 0.82, 0.28)
			_fill_rect(img, 10, 2, 13, 3, gold.darkened(0.32))
			_fill_rect(img, 10, 4, 13, 1, gold.darkened(0.55))
			for px0: int in [10, 13, 16, 19, 22]:
				_fill_rect(img, px0, 0, 2, 3, gold)
				_px(img, px0, 0, WHITE_HOT)
			_fill_rect(img, 10, 2, 13, 1, gold.lightened(0.30))
			_glow_core(img, 16, 3, Color(1.0, 0.35, 0.40))
		"legacy_monolith":
			var rune := Color(0.46, 1.0, 0.56)
			for ex2: int in [10, 22]:
				_fill_rect(img, ex2 - 4, 4, 9, 7, Color(0.02, 0.03, 0.02))
				_fill_rect(img, ex2 - 4, 4, 9, 1, Color(0.20, 0.19, 0.16))
				_fill_rect(img, ex2 - 2, 7, 5, 2, rune.darkened(0.10))
				_glow_lamp(img, ex2, 8, rune, 1)
		"infinite_context":
			for a in 4:
				var rad := deg_to_rad(45.0 + float(a) * 90.0)
				var sx := 16 + int(cos(rad) * 13.0)
				var sy := 16 + int(sin(rad) * 13.0)
				_fill_circle(img, sx, sy, 3, Color(0.04, 0.03, 0.10))
				_fill_circle(img, sx, sy, 2, Color(0.94, 0.96, 1.0))
				_px(img, sx, sy, c.darkened(0.4))
				_px(img, sx, sy + 1, c.darkened(0.4))
				_px(img, sx - 1, sy - 1, WHITE_HOT)

## ---------- boss bodies ----------
##
## Round 6, from the QA frames: the boss variants read as digital noise. The
## cause was structural, not cosmetic. A boss was drawn as "the base enemy, plus
## decorations" — and the decorations were per-pixel: hue swaps applied across
## the whole body, checkerboard dithers, alternating concentric rings. At the 2x
## a boss renders at, under a coloured ambient and HDR bloom, per-pixel variety
## aliases into static: no silhouette, no focal point, no readable shape.
##
## The three rules these bodies are built on, in order of importance:
##
## 1. SILHOUETTE FIRST. One dominant mass with a defined outline. Everything
##    else is drawn INSIDE it. Nothing dangles off it as a one-pixel appendage.
## 2. ONE FOCAL FEATURE. A single place the eye lands — a lens, a rune, an
##    invoice, a glint. Measured as: the brightest pixels must form ONE large
##    cluster, not fifteen scattered specks.
## 3. BOUNDED CHAOS. Noise may decorate the shape; it may never BE the shape.
##    Every corrupting effect here is confined to a named region (a lower rim,
##    a seam, one flank), never applied per-pixel across the body.
##
## The palette discipline that makes it work is `_sculpt`: whatever silhouette a
## body starts with, `_sculpt` repaints every opaque pixel with a FOUR-TONE ramp
## on ONE hue. That trades per-pixel variety for large flat value regions, which
## is the whole difference between a creature and confetti. Details are drawn
## AFTER the sculpt, so they survive it.
func _draw_boss(img: Image, kind: String, c: Color) -> void:
	match kind:
		"infinite_context":
			_draw_boss_infinite_context(img, c)
		"merge_conflict":
			_draw_boss_merge_conflict(img, c)
		"cloud_bill":
			_draw_boss_cloud_bill(img, c)
		"enterprise_architect":
			_draw_boss_enterprise_architect(img, c)
		"legacy_monolith":
			_draw_boss_legacy_monolith(img, c)
		_:
			# Any boss kind without a bespoke body still gets the old path.
			_draw_enemy(img, kind, c)
			_boss_extras(img, kind, c)

## Four stops on ONE hue, dark to light. Deliberately only four: a fifth stop
## buys nothing at 32px and costs the flat regions that make the shape read.
func _boss_ramp(c: Color) -> Array[Color]:
	var h := _vivid_color(c, 1.10)
	var out: Array[Color] = [
		h.darkened(0.66),
		h.darkened(0.42),
		h.darkened(0.10),
		h.lightened(0.38),
	]
	return out

## How lit a pixel is, for a form centred at (cx, cy) with radii (rx, ry). Light
## from the top-left, plus a mild edge-darkening term so the mass turns away at
## its rim. Returns roughly 0..1.
func _boss_lit(x: int, y: int, cx: float, cy: float, rx: float, ry: float) -> float:
	var nx := (float(x) - cx) / rx
	var ny := (float(y) - cy) / ry
	var d: float = minf(sqrt(nx * nx + ny * ny), 1.0)
	return 0.50 - (nx + ny) * 0.26 - d * 0.12

## Ramp stop for a lit value. The thresholds are NOT evenly spaced: the darkest
## stop is reserved for the far rim only (lit <= 0.12). Even bands put the whole
## lower half of a sprite in the darkest tone, and `_underside_ao` then darkens
## it again, which is how a body turns into a black hole with a face on top.
func _ramp_index(lit: float) -> int:
	if lit > 0.66:
		return 3
	if lit > 0.42:
		return 2
	if lit > 0.12:
		return 1
	return 0

## The anti-noise pass. Repaint every opaque pixel with the ramp. Call it right
## after the silhouette is filled and before any detail is drawn.
func _sculpt(img: Image, cx: float, cy: float, rx: float, ry: float, ramp: Array[Color]) -> void:
	for x in img.get_width():
		for y in img.get_height():
			if img.get_pixel(x, y).a <= 0.5:
				continue
			_px(img, x, y, ramp[_ramp_index(_boss_lit(x, y, cx, cy, rx, ry))])

## THE INFINITE CONTEXT (boss): one enormous unblinking lens in an ovoid shell,
## with three memory nodes grown out of its crown. The lens IS the sprite — it
## owns the middle third of the frame, which is why the eye lands on it before
## the player has consciously identified anything else. The "it remembers
## everything" gag lives in a context spill along the lower rim: bounded to five
## short runs, in the body's own two tones, so it decorates the mass instead of
## dissolving it.
func _draw_boss_infinite_context(img: Image, c: Color) -> void:
	var ink := Color(0.030, 0.028, 0.055)
	var ramp := _boss_ramp(c)
	_fill_ellipse(img, 16, 17, 13, 12, ramp[1])
	_fill_ellipse(img, 16, 10, 11, 7, ramp[1])
	for nx: int in [8, 16, 24]:
		_fill_circle(img, nx, 4, 2, ramp[1])
		_fill_rect(img, nx - 1, 4, 3, 4, ramp[1])
	_sculpt(img, 16.0, 17.0, 13.0, 12.0, ramp)
	_fill_ellipse(img, 16, 16, 9, 7, ink)
	_fill_ellipse(img, 16, 16, 8, 6, Color(0.86, 0.88, 0.96))
	_fill_ellipse(img, 15, 15, 6, 4, Color(0.97, 0.98, 1.0))
	_fill_circle(img, 16, 16, 5, ramp[2])
	_fill_circle(img, 16, 16, 4, _vivid_color(c, 1.3))
	_fill_circle(img, 16, 16, 2, ink)
	_px(img, 16, 16, Color(0.02, 0.02, 0.04))
	_px(img, 14, 14, WHITE_HOT)
	_px(img, 15, 14, Color(0.90, 0.94, 1.0))
	_px(img, 14, 15, Color(0.90, 0.94, 1.0))
	_px(img, 18, 18, Color(0.74, 0.80, 0.98))
	_over_line(img, 10, 25, 17, 25, ink)
	_over_line(img, 19, 25, 24, 25, ramp[3])
	_over_line(img, 9, 27, 13, 27, ink)
	_over_line(img, 15, 27, 24, 27, ramp[3])
	_over_line(img, 12, 29, 18, 29, ink)
	for nx2: int in [8, 16, 24]:
		_glow_lamp(img, nx2, 4, ramp[3], 1)

## THE MERGE CONFLICT (boss): one sphere, two factions, two branch nubs on
## stalks. Warm on the left, cool on the right — two hues, four stops each, and
## a near-black spine down the middle with a molten core bounded to y 9..23. The
## third faction (somebody force-pushed) is ONE solid wedge in the lower left
## with a lit leading edge, not the per-pixel green rash it used to be.
func _draw_boss_merge_conflict(img: Image, _c: Color) -> void:
	var ink := Color(0.030, 0.028, 0.055)
	var warm: Array[Color] = [
		Color(0.36, 0.09, 0.04), Color(0.66, 0.20, 0.07),
		Color(0.95, 0.42, 0.14), Color(1.0, 0.72, 0.40)]
	var cool: Array[Color] = [
		Color(0.05, 0.09, 0.26), Color(0.11, 0.20, 0.50),
		Color(0.24, 0.42, 0.86), Color(0.56, 0.76, 1.0)]
	_fill_circle(img, 16, 17, 13, warm[1])
	_thick_line(img, 10, 8, 6, 3, warm[1])
	_fill_circle(img, 6, 3, 2, warm[1])
	_thick_line(img, 22, 8, 26, 3, cool[1])
	_fill_circle(img, 26, 3, 2, cool[1])
	for x in 32:
		for y in 32:
			if img.get_pixel(x, y).a <= 0.5:
				continue
			var idx := _ramp_index(_boss_lit(x, y, 16.0, 17.0, 13.0, 13.0))
			_px(img, x, y, warm[idx] if x < 16 else cool[idx])
	for x2 in 32:
		for y2 in 32:
			if img.get_pixel(x2, y2).a <= 0.5 or y2 < 20:
				continue
			if float(y2 - 19) * 1.9 < float(x2 - 3):
				continue
			_px(img, x2, y2, Color(0.17, 0.50, 0.23) if (x2 + y2) % 7 > 2 else Color(0.10, 0.33, 0.15))
	for y3 in range(20, 31):
		var ex := 3 + int(float(y3 - 19) * 1.9)
		_over_px(img, ex, y3, Color(0.42, 0.94, 0.50))
		_over_px(img, ex - 1, y3, Color(0.30, 0.72, 0.36))
	for y4 in 32:
		var sm := 16 + int(sin(float(y4) * 0.55) * 1.5)
		_over_px(img, sm - 1, y4, ink)
		_over_px(img, sm, y4, ink)
		_over_px(img, sm + 1, y4, ink)
		if y4 >= 9 and y4 <= 23:
			_over_px(img, sm, y4, Color(1.0, 0.74, 0.28))
		if y4 >= 12 and y4 <= 20:
			_over_px(img, sm, y4, Color(1.0, 0.88, 0.52))
	for ei in 2:
		var ex2: int = 10 if ei == 0 else 22
		var pup: Color = Color(0.26, 0.04, 0.03) if ei == 0 else Color(0.03, 0.05, 0.26)
		_fill_ellipse(img, ex2, 15, 4, 4, ink)
		_fill_ellipse(img, ex2, 15, 3, 3, Color(0.96, 0.97, 1.0))
		_fill_circle(img, ex2, 16, 1, pup)
		_px(img, ex2 - 1, 13, WHITE_HOT)
	_fill_circle(img, 6, 3, 1, Color(1.0, 0.66, 0.26))
	_fill_circle(img, 26, 3, 1, Color(0.46, 0.72, 1.0))

## THE CLOUD BILL (boss): a thunderhead. Four puffs fused over one solid anvil,
## sculpted in a single slate ramp — the only second hue on the sprite is the
## money, and the money is the focal feature: an invoice glowing out of the
## belly, fully enclosed by the body. The bolt is struck down the FLANK, inside
## the silhouette, because a bolt hanging off the underside reads as a tail.
func _draw_boss_cloud_bill(img: Image, c: Color) -> void:
	var ink := Color(0.030, 0.028, 0.055)
	var slate: Array[Color] = [
		Color(0.09, 0.11, 0.21), Color(0.17, 0.22, 0.38),
		Color(0.30, 0.38, 0.60), Color(0.64, 0.72, 0.92)]
	_fill_circle(img, 9, 10, 6, slate[1])
	_fill_circle(img, 16, 7, 7, slate[1])
	_fill_circle(img, 23, 10, 6, slate[1])
	_fill_circle(img, 16, 14, 9, slate[1])
	_fill_round_rect(img, 4, 12, 25, 14, slate[1])
	_sculpt(img, 16.0, 14.0, 14.0, 13.0, slate)
	for ex: int in [9, 19]:
		_fill_round_rect(img, ex, 6, 5, 4, Color(0.93, 0.95, 1.0))
		_fill_rect(img, ex + 1, 7, 2, 2, ink)
		_fill_rect(img, ex, 5, 5, 1, slate[0])
	_fill_rect(img, 14, 11, 5, 1, slate[0])
	var money := _vivid_color(c, 1.25)
	_fill_round_rect(img, 10, 13, 13, 12, Color(0.03, 0.09, 0.05))
	_fill_rect(img, 12, 15, 9, 2, money)
	_fill_rect(img, 11, 16, 2, 3, money)
	_fill_rect(img, 12, 18, 9, 2, money)
	_fill_rect(img, 20, 19, 2, 3, money)
	_fill_rect(img, 12, 21, 9, 2, money)
	_fill_rect(img, 16, 13, 2, 11, money.lightened(0.35))
	_glow_lamp(img, 16, 18, money.lightened(0.18), 1)
	var bolt := Color(1.0, 0.90, 0.44)
	var bx0: Array[int] = [26, 23, 26]
	var by0: Array[int] = [13, 18, 20]
	var bx1: Array[int] = [23, 26, 23]
	var by1: Array[int] = [18, 20, 25]
	for bi in 3:
		_over_px(img, bx0[bi], by0[bi], bolt)
		_draw_line_img(img, bx0[bi], by0[bi], bx1[bi], by1[bi], bolt)
		_draw_line_img(img, bx0[bi] - 1, by0[bi], bx1[bi] - 1, by1[bi], bolt.darkened(0.34))
	_px(img, 25, 14, WHITE_HOT)
	# Rain, hanging off the anvil. All three drops START at y 26 — the body's
	# last solid row is 25, so a drop that begins at 27 is a DETACHED 2x2 block:
	# _outline_silhouette boxes it, _threat_halo rings it twice, and at the 2x a
	# boss renders at it reads as a floating speck under the cloud, which is the
	# exact defect this pass exists to remove. The middle drop still hangs
	# lower — it is one row TALLER, not one row further down.
	var rxs: Array[int] = [8, 13, 19]
	var rhs: Array[int] = [2, 3, 2]
	for ri in 3:
		_fill_rect(img, rxs[ri], 26, 2, rhs[ri], slate[3])
		_fill_rect(img, rxs[ri], 26, 2, 1, Color(0.86, 0.92, 1.0))

## THE ENTERPRISE ARCHITECT (boss): one trapezoid of shoulders, a head set into
## it, and a crown he awarded himself. The focal feature is the glasses glint —
## a continuous hot band across both lenses rather than a scatter of sparkles,
## so the brightest thing on the sprite is one shape and it is on his face.
func _draw_boss_enterprise_architect(img: Image, _c: Color) -> void:
	var ink := Color(0.030, 0.028, 0.055)
	var suit: Array[Color] = [
		Color(0.07, 0.08, 0.15), Color(0.13, 0.16, 0.28),
		Color(0.22, 0.27, 0.44), Color(0.46, 0.54, 0.76)]
	for y in range(13, 31):
		var half: int = mini(6 + int(float(y - 13) * 0.62), 13)
		_fill_rect(img, 16 - half, y, half * 2 + 1, 1, suit[1])
	_sculpt(img, 16.0, 20.0, 14.0, 14.0, suit)
	var skin := Color(0.86, 0.71, 0.58)
	_shade_sphere(img, 16, 8, 6, skin)
	_fill_rect(img, 10, 1, 13, 4, Color(0.13, 0.13, 0.18))
	_fill_rect(img, 10, 1, 13, 1, Color(0.34, 0.34, 0.42))
	var gold := Color(1.0, 0.82, 0.28)
	_fill_rect(img, 9, 1, 15, 2, gold.darkened(0.34))
	_fill_rect(img, 9, 1, 15, 1, gold.lightened(0.24))
	for px0: int in [9, 15, 21]:
		_fill_rect(img, px0, 0, 3, 2, gold)
		_px(img, px0 + 1, 0, WHITE_HOT)
	_fill_rect(img, 10, 6, 13, 1, Color(0.10, 0.10, 0.14))
	_fill_rect(img, 10, 7, 6, 4, Color(0.80, 0.88, 0.98))
	_fill_rect(img, 17, 7, 6, 4, Color(0.62, 0.70, 0.86))
	_fill_rect(img, 16, 8, 1, 1, Color(0.22, 0.26, 0.34))
	_fill_rect(img, 12, 8, 2, 2, ink)
	_fill_rect(img, 19, 8, 2, 2, ink)
	_fill_rect(img, 10, 10, 6, 1, Color(0.30, 0.36, 0.48))
	_fill_rect(img, 17, 10, 6, 1, Color(0.24, 0.29, 0.40))
	_fill_rect(img, 10, 7, 6, 1, WHITE_HOT)
	_fill_rect(img, 17, 7, 6, 1, Color(0.90, 0.94, 1.0))
	_fill_rect(img, 14, 12, 5, 1, skin.darkened(0.46))
	_fill_rect(img, 13, 13, 7, 2, Color(0.95, 0.96, 0.99))
	_fill_rect(img, 13, 13, 7, 1, WHITE_HOT)
	for ty in range(14, 28):
		var w: int = 1 + (ty - 14) / 5
		var tie: Color = Color(0.50, 0.07, 0.11) if ty % 5 == 0 else Color(0.74, 0.12, 0.17)
		_fill_rect(img, 16 - w / 2, ty, maxi(1, w), 1, tie)
	_fill_circle(img, 7, 20, 1, Color(0.44, 0.62, 0.92))
	_fill_circle(img, 25, 20, 1, Color(0.32, 0.46, 0.74))

## THE LEGACY MONOLITH (boss): a standing slab, tapered, with a capstone and a
## plinth — NOT the full-frame brick wall it used to be, which had no silhouette
## at all because it touched every edge of the canvas. One stone ramp, courses
## drawn as dark mortar only (the old per-brick value jitter was the confetti),
## and one rune slot lit from inside as the focal feature.
func _draw_boss_legacy_monolith(img: Image, _c: Color) -> void:
	var stone: Array[Color] = [
		Color(0.16, 0.14, 0.12), Color(0.29, 0.26, 0.22),
		Color(0.47, 0.42, 0.36), Color(0.74, 0.68, 0.60)]
	for y in range(2, 29):
		var half := 6 + int(float(y - 2) * 0.19)
		_fill_rect(img, 16 - half, y, half * 2 + 1, 1, stone[1])
	_fill_rect(img, 4, 29, 25, 3, stone[1])
	_fill_rect(img, 11, 0, 11, 3, stone[1])
	_sculpt(img, 16.0, 16.0, 13.0, 15.0, stone)
	for row in range(6, 29, 6):
		_over_line(img, 2, row, 29, row, stone[0])
		var off: int = 0 if (row / 6) % 2 == 0 else 5
		for bx in range(3 + off, 29, 10):
			for dy in range(1, 6):
				_over_px(img, bx, row + dy, stone[0])
	_over_line(img, 11, 18, 13, 28, stone[0])
	_over_line(img, 21, 20, 19, 28, stone[0])
	var rune := Color(0.36, 1.0, 0.48)
	_fill_rect(img, 10, 10, 13, 7, stone[0])
	_fill_rect(img, 11, 11, 11, 5, Color(0.03, 0.06, 0.03))
	_fill_rect(img, 13, 12, 7, 1, rune.darkened(0.15))
	_fill_rect(img, 13, 14, 7, 1, rune.darkened(0.15))
	_fill_rect(img, 16, 12, 1, 4, rune)
	_glow_lamp(img, 16, 13, rune, 1)
	_fill_rect(img, 9, 9, 15, 1, stone[3])

## A software "bug" that actually reads as a beetle: three masses (head,
## pronotum, abdomen) separated by hard near-black seams, six two-pixel jointed
## legs, a cracked elytron, and eyes that bloom amber.
func _draw_bug(img: Image, _c: Color) -> void:
	var shell := Color(0.82, 0.20, 0.20)
	var shell_hi := Color(1.0, 0.40, 0.24)
	var shell_sp := Color(1.0, 0.76, 0.52)
	var shell_sh := Color(0.40, 0.06, 0.10)
	var carapace := Color(0.10, 0.04, 0.06)
	var leg := Color(0.19, 0.07, 0.09)
	var leg_hi := Color(0.46, 0.15, 0.14)
	var amber := Color(1.0, 0.74, 0.16)
	# six jointed legs, two pixels thick so they survive the outline and the halo
	for sy: int in [14, 19, 24]:
		_thick_line(img, 12, sy, 6, sy - 4, leg)
		_thick_line(img, 6, sy - 4, 4, sy - 1, leg)
		_thick_line(img, 20, sy, 26, sy - 4, leg)
		_thick_line(img, 26, sy - 4, 28, sy - 1, leg)
		_draw_line_img(img, 12, sy, 6, sy - 4, leg_hi)
		_draw_line_img(img, 20, sy, 26, sy - 4, leg_hi)
	# abdomen: offset-layered ellipses build the top-left ramp
	_fill_ellipse(img, 16, 20, 10, 11, shell_sh)
	_fill_ellipse(img, 15, 19, 9, 10, shell)
	_fill_ellipse(img, 13, 16, 4, 5, shell_hi)
	_dither_rect(img, 9, 24, 11, 4, shell, shell_sh, true)
	# a specular streak on the lit shoulder of the shell
	_over_line(img, 10, 15, 13, 13, shell_sp)
	_over_px(img, 11, 14, WHITE_HOT)
	# the elytra split: 2px of near-black, the hardest internal edge on the sprite
	_fill_rect(img, 15, 12, 2, 18, carapace)
	for ry: int in [17, 21, 25]:
		for x in range(7, 26):
			if Vector2(x - 16, ry - 20).length() < 10.2 and img.get_pixel(x, ry).a > 0.0:
				_px(img, x, ry, shell_sh)
	_over_line(img, 20, 16, 22, 20, carapace)  # a crack — it has seen some sprints
	# pronotum (thorax plate) — its own mass, one value step up
	_fill_ellipse(img, 16, 11, 8, 5, shell_sh)
	_fill_ellipse(img, 16, 10, 7, 4, shell.lightened(0.14))
	_fill_ellipse(img, 13, 9, 3, 2, shell_hi)
	_fill_rect(img, 8, 13, 17, 1, carapace)   # hard shadow under the plate
	# head, set into the pronotum
	_fill_circle(img, 16, 6, 4, carapace)
	_fill_circle(img, 15, 5, 3, Color(0.30, 0.15, 0.16))
	_thick_line(img, 14, 9, 12, 11, carapace)   # mandibles, open
	_thick_line(img, 18, 9, 20, 11, carapace)
	_thick_line(img, 13, 3, 9, 0, leg)          # antennae
	_thick_line(img, 19, 3, 23, 0, leg)
	_px(img, 9, 0, amber)
	_px(img, 23, 0, amber)   # the antenna ends at 23, not 24 — tips stay mirrored
	# the tell: two amber lamps with white-hot cores
	_glow_lamp(img, 13, 5, amber, 1)
	_glow_lamp(img, 19, 5, amber, 1)

## A rate limiter: a hazard-striped gate with a STOP light mid-tantrum. The
## stripes are near-white against near-black on purpose — a gate that reads as
## "wall" is a gate that works.
func _draw_rate_limiter(img: Image, c: Color) -> void:
	var post := Color(0.19, 0.20, 0.25)
	var post_hi := Color(0.46, 0.49, 0.58)
	var post_sh := Color(0.07, 0.08, 0.11)
	var hot := Color(1.0, 0.82, 0.26)
	for px: int in [4, 24]:
		_fill_rect(img, px, 6, 5, 23, post)
		_fill_rect(img, px, 6, 1, 23, post_hi)
		_fill_rect(img, px + 4, 6, 1, 23, post_sh)
		_fill_rect(img, px - 1, 28, 7, 3, post_sh)
		_fill_rect(img, px - 1, 28, 7, 1, post.lightened(0.10))
	for i in 3:
		var by := 10 + i * 6
		for x in range(9, 24):
			for y in range(by, by + 5):
				var stripe: bool = int(floor(float(x - y) / 3.0)) % 2 == 0
				var col: Color = hot if stripe else Color(0.07, 0.07, 0.10)
				if y == by:
					col = col.lightened(0.34)
				elif y == by + 4:
					col = col.darkened(0.45)
				_px(img, x, y, col)
		_fill_rect(img, 9, by, 15, 1, Color(0.05, 0.05, 0.08))
	# status LEDs down the shadow post — currently all yelling
	for i2 in 3:
		_glow_lamp(img, 26, 11 + i2 * 7, Color(1.0, 0.30, 0.26), 1)
	# the STOP beacon
	_fill_circle(img, 16, 4, 4, Color(0.30, 0.05, 0.07))
	_fill_circle(img, 16, 4, 3, Color(0.90, 0.16, 0.18))
	_glow_lamp(img, 15, 3, Color(1.0, 0.34, 0.30), 2)
	# The beacon disc bottoms out at y=8 and the first barrier arm starts at
	# y=10, so a one-row bracket left row 9 empty and the head came out as a
	# separate island with its own outline and its own halo. Two rows joins it.
	_fill_rect(img, 12, 8, 9, 2, Color(0.06, 0.06, 0.09))

## A memory leak: a gel dome, top-left lit, with a hard base line and drips it
## has no intention of freeing.
func _draw_memory_leak(img: Image, c: Color) -> void:
	var hi := c.lightened(0.34)
	var sp := c.lightened(0.66)
	var sh := c.darkened(0.42)
	var sh2 := c.darkened(0.62)
	_fill_ellipse(img, 16, 13, 11, 10, sh2)
	_fill_ellipse(img, 16, 12, 10, 9, sh)
	_fill_ellipse(img, 15, 11, 9, 8, c)
	_fill_ellipse(img, 12, 8, 5, 4, hi)
	_fill_ellipse(img, 11, 7, 2, 2, sp)
	_px(img, 11, 7, WHITE_HOT)
	_dither_rect(img, 8, 16, 16, 4, c, sh, true)
	_fill_rect(img, 7, 20, 18, 1, sh2)   # a hard base line: it has a bottom
	# suspended allocations nobody freed
	var blobs: Array[Vector3i] = [Vector3i(20, 14, 2), Vector3i(10, 15, 1), Vector3i(17, 8, 1)]
	for b in blobs:
		_fill_circle(img, b.x, b.y, b.z, sh)
		_over_px(img, b.x - 1, b.y - 1, hi)
	# drips, three pixels wide with a lit edge and a hot bead
	var drip_x: Array[int] = [10, 16, 22]
	var drip_h: Array[int] = [7, 10, 5]
	for i in 3:
		_fill_rect(img, drip_x[i] - 1, 20, 3, drip_h[i], c.darkened(0.16))
		_fill_rect(img, drip_x[i] - 1, 20, 1, drip_h[i], hi)
		_fill_rect(img, drip_x[i] + 1, 20, 1, drip_h[i], sh2)
		_fill_circle(img, drip_x[i], 20 + drip_h[i], 2, sh)
		_fill_circle(img, drip_x[i], 20 + drip_h[i], 1, c)
		_px(img, drip_x[i] - 1, 20 + drip_h[i] - 1, sp)
	# eyes: it knows what it did
	for ex: int in [12, 20]:
		_fill_circle(img, ex, 11, 3, Color(0.03, 0.04, 0.09))
		_fill_circle(img, ex, 11, 2, Color(0.94, 0.96, 1.0))
		_fill_circle(img, ex, 12, 1, Color(0.04, 0.06, 0.13))
		_px(img, ex - 1, 10, WHITE_HOT)
	_fill_rect(img, 10, 7, 4, 1, sh2)
	_fill_rect(img, 18, 7, 4, 1, sh2)
	_fill_rect(img, 14, 16, 5, 1, Color(0.04, 0.05, 0.11))  # a small guilty mouth

## A merge conflict: two halves that refuse to rebase, split by hue AND by
## value, with white-hot friction sparks down the seam and a chevron each way.
func _draw_merge_conflict(img: Image, _c: Color) -> void:
	var lb := Color(0.88, 0.30, 0.16)
	var lhi := Color(1.0, 0.62, 0.34)
	var lsh := Color(0.40, 0.09, 0.07)
	var rb := Color(0.15, 0.28, 0.62)
	var rhi := Color(0.38, 0.58, 0.96)
	var rsh := Color(0.04, 0.08, 0.24)
	var dark := Color(0.04, 0.04, 0.07)
	for x in 32:
		for y in 32:
			if Vector2(x - 16, y - 16).length() > 12.4:
				continue
			var seam := 16 + int(sin(float(y) * 0.6) * 1.6)
			var lit := -(float(x - 15) / 12.0 + float(y - 15) / 12.0) * 0.707
			var col := lb
			if x <= seam:
				if lit > 0.40:
					col = lhi
				elif lit < -0.28:
					col = lsh
				elif lit < -0.05:
					col = lsh if ((x + y) % 2 == 0) else lb
			else:
				col = rb
				if lit > 0.40:
					col = rhi
				elif lit < -0.28:
					col = rsh
				elif lit < -0.05:
					col = rsh if ((x + y) % 2 == 0) else rb
			_px(img, x, y, col)
	_over_px(img, 9, 9, Color(1.0, 0.86, 0.66))
	_over_px(img, 10, 8, WHITE_HOT)
	# the seam: 2px of near-black, jagged, unresolvable
	for y2 in 32:
		var seam2 := 16 + int(sin(float(y2) * 0.6) * 1.6)
		_over_px(img, seam2, y2, dark)
		_over_px(img, seam2 + 1, y2, dark)
	# <<<< on the left, >>>> on the right
	for i in 3:
		var cy := 9 + i * 7
		_over_line(img, 11, cy, 8, cy + 2, dark)
		_over_line(img, 8, cy + 2, 11, cy + 4, dark)
		_over_line(img, 21, cy, 24, cy + 2, dark)
		_over_line(img, 24, cy + 2, 21, cy + 4, dark)
	_glow_lamp(img, 16, 8, Color(1.0, 0.78, 0.30), 2)
	_glow_lamp(img, 16, 22, Color(1.0, 0.78, 0.30), 2)
	# one eye per faction, glaring inward
	for ei in 2:
		var ex: int = 11 if ei == 0 else 21
		var pup: Color = Color(0.20, 0.03, 0.03) if ei == 0 else Color(0.03, 0.05, 0.22)
		_fill_circle(img, ex, 14, 3, dark)
		_fill_circle(img, ex, 14, 2, Color(0.95, 0.96, 1.0))
		_px(img, ex, 14, pup)
		_px(img, ex, 15, pup)

## Scope creep: a lit amoeba whose pseudopods are already reaching for the next
## sprint. Tips glow — that's where the new requirements grow.
func _draw_scope_creep(img: Image, c: Color) -> void:
	var hi := c.lightened(0.34)
	var sp := c.lightened(0.68)
	var sh := c.darkened(0.40)
	var sh2 := c.darkened(0.60)
	var dirs: Array[Vector2] = [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0),
		Vector2(1, 0), Vector2(0.7, -0.7), Vector2(-0.7, 0.7)]
	for a in dirs:
		var tipx := 16 + int(a.x * 13.0)
		var tipy := 16 + int(a.y * 13.0)
		_thick_line(img, 16 + int(a.x * 5.0), 16 + int(a.y * 5.0), tipx, tipy, sh)
		_draw_line_img(img, 16 + int(a.x * 5.0), 16 + int(a.y * 5.0), tipx, tipy, c)
		_fill_circle(img, tipx, tipy, 2, sh)
		_fill_circle(img, tipx, tipy, 1, c)
		_px(img, tipx - 1, tipy - 1, sp)
	_fill_circle(img, 16, 16, 9, sh2)
	_fill_circle(img, 16, 16, 8, sh)
	_fill_circle(img, 15, 15, 7, c)
	_fill_circle(img, 13, 13, 4, hi)
	_fill_circle(img, 12, 12, 1, sp)
	_px(img, 12, 12, WHITE_HOT)
	_dither_rect(img, 11, 19, 11, 4, c, sh, true)
	# organelles (absorbed tickets)
	var orgs: Array[Vector2i] = [Vector2i(19, 19), Vector2i(12, 20), Vector2i(19, 12)]
	for o in orgs:
		_fill_circle(img, o.x, o.y, 1, sh2)
		_over_px(img, o.x - 1, o.y - 1, hi)
	for ex: int in [12, 20]:
		_fill_circle(img, ex, 15, 3, Color(0.03, 0.06, 0.03))
		_fill_circle(img, ex, 15, 2, Color(0.94, 1.0, 0.94))
		_px(img, ex, 15, Color(0.03, 0.10, 0.03))
		_px(img, ex, 16, Color(0.03, 0.10, 0.03))
		_px(img, ex - 1, 14, WHITE_HOT)
	# a grin that is already thinking about phase two
	for gx in range(13, 20, 2):
		_over_px(img, gx, 20, Color(0.03, 0.07, 0.03))
		_over_px(img, gx + 1, 21, Color(0.03, 0.07, 0.03))

## Dependency demon: a horned knot whose strands kink like the real graph. Six
## strands, not eight — the real graph is worse, but the real graph does not
## have to read at 32 pixels.
func _draw_dependency_demon(img: Image, c: Color) -> void:
	var sh := c.darkened(0.46)
	var sh2 := c.darkened(0.68)
	var hi := c.lightened(0.30)
	var sp := c.lightened(0.66)
	var amber := Color(1.0, 0.84, 0.22)
	for i in 6:
		var ang := TAU * float(i) / 6.0 + 0.35
		var d := Vector2(cos(ang), sin(ang))
		var tipx := 16 + int(d.x * 11.0)
		var tipy := 16 + int(d.y * 11.0)
		var midx := 16 + int(d.x * 7.0 - d.y * 2.0)
		var midy := 16 + int(d.y * 7.0 + d.x * 2.0)
		_thick_line(img, 16, 16, midx, midy, sh2)
		_thick_line(img, midx, midy, tipx, tipy, sh2)
		_draw_line_img(img, 16, 16, midx, midy, sh)
		_draw_line_img(img, midx, midy, tipx, tipy, sh)
		_fill_circle(img, tipx, tipy, 2, sh2)
		_fill_circle(img, tipx, tipy, 1, c)
		_px(img, tipx - 1, tipy - 1, sp)
	# the knot itself owns the middle of the frame
	_fill_circle(img, 16, 16, 9, sh2)
	_fill_circle(img, 16, 16, 8, sh)
	_fill_circle(img, 15, 15, 7, c)
	_fill_circle(img, 13, 13, 4, hi)
	_px(img, 12, 12, sp)
	_px(img, 11, 12, WHITE_HOT)
	for sgn: int in [-1, 1]:
		_thick_line(img, 16 + sgn * 5, 10, 16 + sgn * 8, 3, sh2)
		_draw_line_img(img, 16 + sgn * 5, 10, 16 + sgn * 8, 3, hi)
		_px(img, 16 + sgn * 8, 2, sp)
	# version-mismatch eyes
	_glow_lamp(img, 13, 14, amber, 2)
	_glow_lamp(img, 19, 14, amber, 2)
	_fill_rect(img, 12, 19, 9, 2, Color(0.04, 0.02, 0.04))
	for gx in range(13, 21, 2):
		_over_px(img, gx, 19, Color(0.92, 0.94, 0.98))
		_over_px(img, gx + 1, 20, Color(0.92, 0.94, 0.98))

## Hallucination: a confident ghost with too many eyes, glitching at the edges.
## The glitch bands are a real row displacement with a chromatic fringe, not a
## painted stripe — it reads as a rendering fault, which is the joke.
func _draw_hallucination(img: Image, c: Color) -> void:
	var body := Color(c.r, c.g, c.b, 0.94)
	var body_sh := Color(c.r * 0.46, c.g * 0.32, c.b * 0.54, 0.94)
	var body_sh2 := Color(c.r * 0.20, c.g * 0.13, c.b * 0.26, 0.94)
	var body_hi := Color(minf(c.r * 1.15, 1.0), minf(c.g * 1.25, 1.0), minf(c.b * 1.12, 1.0), 0.96)
	_fill_ellipse(img, 16, 14, 11, 11, body_sh2)
	_fill_ellipse(img, 16, 13, 10, 10, body_sh)
	_fill_ellipse(img, 15, 12, 9, 9, body)
	_fill_ellipse(img, 12, 9, 4, 4, body_hi)
	_px(img, 11, 8, Color(1.0, 1.0, 1.0, 0.96))
	_fill_rect(img, 5, 14, 22, 12, body)
	_fill_rect(img, 5, 14, 2, 12, body_hi)
	_fill_rect(img, 24, 14, 3, 12, body_sh)
	_fill_rect(img, 5, 24, 22, 2, body_sh2)
	# a hem of three lobes, so the bottom of the silhouette has a shape
	for i in 3:
		_fill_circle(img, 8 + i * 8, 26, 3, Color(0, 0, 0, 0))
		_fill_ellipse(img, 12 + i * 8, 26, 3, 2, body_sh)
	_fill_rect(img, 5, 14, 22, 1, body_hi)
	# too many eyes, all sincere
	var eyes: Array[Vector2i] = [Vector2i(11, 12), Vector2i(21, 12), Vector2i(16, 19)]
	for e in eyes:
		_fill_circle(img, e.x, e.y, 3, Color(0.10, 0.03, 0.14, 0.96))
		_fill_circle(img, e.x, e.y, 2, Color(0.97, 0.94, 1.0))
		_px(img, e.x, e.y, Color(0.30, 0.06, 0.38))
		_px(img, e.x, e.y + 1, Color(0.30, 0.06, 0.38))
		_px(img, e.x - 1, e.y - 1, WHITE_HOT)
	var bands: Array[int] = [9, 22]
	var band_tint: Array[Color] = [Color(0.26, 1.0, 0.90), Color(1.0, 0.34, 0.90)]
	for bi in 2:
		var band_y: int = bands[bi]
		var row: Array[Color] = []
		for x in 32:
			row.append(img.get_pixel(x, band_y))
		for x2 in 32:
			var src: Color = row[(x2 - 3 + 32) % 32]
			if src.a > 0.05:
				_px(img, x2, band_y, src)
		var t: Color = band_tint[bi]
		_over_line(img, 3, band_y, 28, band_y, Color(t.r, t.g, t.b, 0.95))
		_fill_rect(img, 3 if band_y < 16 else 19, band_y + 1, 10, 1, Color(0.96, 0.98, 1.0, 0.55))

## THE LEGACY MONOLITH: a towering brick slab with per-brick value jitter,
## structural cracks, dithered moss, a crenellated top and COBOL runes that
## still glow.
func _draw_legacy_monolith(img: Image, _c: Color) -> void:
	var brick := Color(0.50, 0.44, 0.39)
	var mortar := brick.darkened(0.68)
	_fill_rect(img, 3, 2, 26, 27, brick)
	for row in range(2, 30, 5):
		var off: int = 0 if ((row - 2) / 5) % 2 == 0 else 4
		for bx in range(off - 5, 29, 8):
			var jit := _hash01(bx + 40, row) - 0.5
			var bcol: Color = brick.lightened(jit * 0.30) if jit > 0.0 else brick.darkened(-jit * 0.30)
			_fill_rect(img, maxi(bx + 1, 3), row + 1, 7, 4, bcol)
			_fill_rect(img, maxi(bx + 1, 3), row + 1, 7, 1, bcol.lightened(0.20))
			_fill_rect(img, maxi(bx + 1, 3), row + 4, 7, 1, bcol.darkened(0.28))
		_fill_rect(img, 3, row, 26, 1, mortar)
		for bx2 in range(3 + off, 29, 8):
			_fill_rect(img, bx2, row, 1, 5, mortar)
	# structural despair, with a dogleg
	var crack := Color(0.05, 0.045, 0.04)
	_thick_line(img, 10, 3, 12, 14, crack)
	_thick_line(img, 12, 14, 14, 28, crack)
	_thick_line(img, 22, 5, 20, 16, crack)
	_thick_line(img, 20, 16, 18, 27, crack)
	# glowing COBOL runes
	var rune := Color(0.42, 0.98, 0.52)
	_fill_rect(img, 12, 11, 8, 2, rune.darkened(0.30))
	_fill_rect(img, 13, 17, 6, 2, rune.darkened(0.30))
	_fill_rect(img, 15, 9, 2, 10, rune)
	_glow_core(img, 16, 13, rune.lightened(0.30))
	_fill_rect(img, 7, 22, 2, 5, rune.darkened(0.35))
	_fill_rect(img, 7, 24, 4, 1, rune.darkened(0.35))
	_glow_core(img, 8, 24, rune)
	# moss clings to the lit shoulder
	_dither_rect(img, 3, 2, 26, 2, Color(0.28, 0.50, 0.30), Color(0.18, 0.34, 0.22))
	_dither_rect(img, 3, 4, 10, 1, Color(0.28, 0.50, 0.30), brick)
	# crenellations, a lit left edge and a plinth: not a box
	for cx0 in range(3, 29, 6):
		_fill_rect(img, cx0, 0, 4, 2, brick.darkened(0.18))
		_fill_rect(img, cx0, 0, 4, 1, brick.lightened(0.24))
	_fill_rect(img, 3, 2, 1, 27, brick.lightened(0.30))
	_fill_rect(img, 28, 2, 1, 27, brick.darkened(0.42))
	_fill_rect(img, 1, 29, 30, 3, brick.darkened(0.30))
	_fill_rect(img, 1, 29, 30, 1, brick.lightened(0.10))

## THE INFINITE CONTEXT: one orbital ring around an eye that has read everything
## you ever typed, including the deleted parts. The eye is a LENS, not a marble,
## and it owns the middle of the frame — an eye drawn small is a dot, and a dot
## is not a threat.
##
## Round 6: this used to be two pairs of concentric ring outlines over a
## two-lobed field, which at game zoom aliased into pure static — the same
## defect that made its boss unreadable. It is now one solid sculpted mass
## inside a single two-value ring, so the base creature and the boss are visibly
## the same species: an orbiting shell around one enormous lens.
func _draw_infinite_context(img: Image, c: Color) -> void:
	var ink := Color(0.030, 0.028, 0.055)
	var ramp := _boss_ramp(c)
	_draw_circle_outline(img, 16, 16, 14, ramp[0])
	_draw_circle_outline(img, 16, 16, 13, ramp[2])
	for a in range(0, 360, 90):
		var rad := deg_to_rad(float(a) + 45.0)
		_fill_circle(img, 16 + int(cos(rad) * 13.0), 16 + int(sin(rad) * 13.0), 2, ramp[1])
	_fill_ellipse(img, 16, 16, 10, 10, ramp[1])
	_sculpt(img, 16.0, 16.0, 10.0, 10.0, ramp)
	_fill_ellipse(img, 16, 16, 7, 5, ink)
	_fill_ellipse(img, 16, 16, 6, 4, Color(0.88, 0.90, 0.97))
	_fill_ellipse(img, 15, 15, 4, 3, Color(0.97, 0.98, 1.0))
	_fill_circle(img, 16, 16, 3, _vivid_color(c, 1.3))
	_fill_circle(img, 16, 16, 1, ink)
	_px(img, 14, 14, WHITE_HOT)
	for a2 in range(0, 360, 90):
		var rad2 := deg_to_rad(float(a2) + 45.0)
		_glow_lamp(img, 16 + int(cos(rad2) * 13.0), 16 + int(sin(rad2) * 13.0), ramp[3], 1)

## THE ENTERPRISE ARCHITECT: a tailored suit, a power tie, an access badge, and
## an aura of governance that fades with distance (unlike the meetings).
func _draw_enterprise_architect(img: Image, c: Color) -> void:
	var gov := Color(c.r, c.g, minf(c.b + 0.2, 1.0), 0.42)
	var bxs: Array[int] = [1, 30]
	var bys: Array[int] = [1, 30]
	for bi in 2:
		for bj in 2:
			var dx: int = 1 if bi == 0 else -1
			var dy: int = 1 if bj == 0 else -1
			for i in 5:
				_px(img, bxs[bi] + dx * i, bys[bj], gov)
				_px(img, bxs[bi], bys[bj] + dy * i, gov)
	var suit := Color(0.15, 0.17, 0.29)
	var suit_hi := Color(0.36, 0.42, 0.60)
	var suit_sh := Color(0.06, 0.07, 0.14)
	var skin := Color(0.88, 0.74, 0.62)
	_shade_sphere(img, 16, 8, 5, skin)
	_fill_rect(img, 11, 2, 11, 4, Color(0.16, 0.16, 0.20))
	_fill_rect(img, 11, 2, 11, 1, Color(0.40, 0.40, 0.48))   # gel highlight
	_fill_rect(img, 11, 5, 11, 1, Color(0.08, 0.08, 0.11))
	# rimless glasses, because he "just wants to understand the architecture"
	_fill_rect(img, 11, 7, 5, 3, Color(0.80, 0.88, 0.98))
	_fill_rect(img, 17, 7, 5, 3, Color(0.66, 0.74, 0.88))
	_fill_rect(img, 16, 8, 1, 1, Color(0.24, 0.28, 0.36))
	_fill_rect(img, 12, 8, 3, 1, Color(0.04, 0.04, 0.06))
	_fill_rect(img, 18, 8, 3, 1, Color(0.04, 0.04, 0.06))
	_px(img, 11, 7, WHITE_HOT)
	_px(img, 12, 7, Color(0.92, 0.96, 1.0))
	_fill_rect(img, 14, 11, 4, 1, skin.darkened(0.42))       # a mouth mid-sentence
	_fill_rect(img, 12, 12, 9, 1, Color(0.05, 0.05, 0.09))   # jaw shadow
	_fill_rect(img, 8, 13, 16, 16, suit)
	_fill_rect(img, 8, 13, 2, 16, suit_hi)
	_fill_rect(img, 22, 13, 2, 16, suit_sh)
	_fill_rect(img, 8, 13, 16, 1, suit_hi.lightened(0.20))
	_draw_line_img(img, 13, 13, 16, 19, suit_sh)             # lapel V
	_draw_line_img(img, 19, 13, 16, 19, suit_sh)
	_fill_rect(img, 14, 13, 5, 3, Color(0.95, 0.96, 0.99))   # collar
	_fill_rect(img, 14, 13, 5, 1, WHITE_HOT)
	for tyy in range(15, 28):
		var w := 1 + (tyy - 15) / 5
		var tie: Color = Color(0.86, 0.14, 0.20) if tyy % 4 != 0 else Color(0.56, 0.08, 0.14)
		_fill_rect(img, 16 - w / 2, tyy, maxi(1, w), 1, tie)
	_px(img, 16, 15, Color(1.0, 0.46, 0.48))
	_fill_rect(img, 6, 14, 3, 12, suit)
	_fill_rect(img, 6, 14, 1, 12, suit_hi)
	_fill_rect(img, 23, 14, 3, 12, suit_sh)
	# the deck, held where you cannot avoid it. The line only ever goes up.
	_fill_rect(img, 22, 17, 9, 8, Color(0.94, 0.95, 0.99))
	_fill_rect(img, 22, 17, 9, 1, WHITE_HOT)
	_fill_rect(img, 22, 24, 9, 1, Color(0.42, 0.45, 0.54))
	_draw_line_img(img, 23, 23, 29, 18, Color(0.14, 0.58, 0.30))
	_glow_lamp(img, 29, 18, Color(0.34, 0.98, 0.50), 1)
	_fill_rect(img, 23, 19, 4, 1, Color(0.55, 0.58, 0.66))
	_fill_rect(img, 23, 21, 3, 1, Color(0.55, 0.58, 0.66))
	_glow_lamp(img, 11, 18, Color(0.36, 0.68, 1.0), 1)  # clearance level: yes

## NULL REFERENCE: the ghost of a value that was promised and never delivered.
## The face is the darkest hole in the whole cast and the question mark inside it
## is the brightest thing on the sprite. That contrast IS the character.
func _draw_null_reference(img: Image, c: Color) -> void:
	var body := Color(c.r * 0.72, c.g * 0.60, c.b * 0.80, 0.96)
	var body_sh := body.darkened(0.44)
	var body_sh2 := body.darkened(0.66)
	var body_hi := Color(minf(c.r * 1.25, 1.0), minf(c.g * 1.15, 1.0), minf(c.b * 1.2, 1.0), 0.98)
	_fill_ellipse(img, 16, 13, 11, 11, body_sh2)
	_fill_ellipse(img, 16, 12, 10, 10, body_sh)
	_fill_ellipse(img, 15, 11, 9, 9, body)
	_fill_ellipse(img, 12, 8, 4, 4, body_hi)
	_px(img, 11, 7, Color(1.0, 1.0, 1.0, 0.98))
	# a tapering tail with real lobes
	var wob: Array[int] = [0, -2, 1, -1]
	for i in 4:
		_fill_ellipse(img, 16 + wob[i], 21 + i * 3, 8 - i * 2, 3, body_sh if i % 2 == 0 else body)
		_fill_rect(img, 16 + wob[i] - (7 - i * 2), 21 + i * 3 - 2, (7 - i * 2) * 2, 1, body_sh2)
	# the void where a face should be
	_fill_ellipse(img, 16, 13, 7, 7, Color(0.012, 0.012, 0.035))
	_fill_ellipse(img, 16, 12, 6, 6, Color(0.008, 0.008, 0.024))
	# the question, 2px strokes so it survives everything downstream
	var q := Color(0.80, 0.58, 1.0)
	_fill_rect(img, 13, 8, 6, 2, q)
	_fill_rect(img, 18, 9, 2, 3, q)
	_fill_rect(img, 15, 11, 4, 2, q)
	_fill_rect(img, 15, 13, 2, 2, q)
	_over_px(img, 14, 8, WHITE_HOT)
	_over_px(img, 15, 8, WHITE_HOT)
	_over_px(img, 15, 11, WHITE_HOT)
	_glow_lamp(img, 16, 17, q, 1)

## LEGACY SYSTEM: a beige tower PC that predates several of your coworkers.
## Still on. Nobody knows what it runs. Nobody dares turn it off.
func _draw_legacy_system(img: Image, _c: Color) -> void:
	var beige := Color(0.52, 0.49, 0.41)
	var beige_hi := Color(0.84, 0.80, 0.70)
	var beige_sh := Color(0.24, 0.22, 0.18)
	_fill_rect(img, 8, 2, 17, 28, beige)
	_fill_rect(img, 8, 2, 2, 28, beige_hi)
	_fill_rect(img, 23, 2, 2, 28, beige_sh)
	_fill_rect(img, 8, 2, 17, 1, beige_hi.lightened(0.35))
	_fill_rect(img, 8, 29, 17, 1, beige_sh.darkened(0.40))
	# dust on top — untouched since the last reorg
	_dither_rect(img, 10, 3, 14, 2, Color(0.66, 0.63, 0.57), beige)
	# CRT-green status screen, recessed
	_fill_rect(img, 11, 6, 11, 10, beige_sh.darkened(0.30))
	_fill_rect(img, 12, 7, 9, 8, Color(0.02, 0.05, 0.03))
	for lrow in 3:
		_fill_rect(img, 13, 9 + lrow * 2, 4 + (lrow * 3) % 5, 1, Color(0.30, 0.94, 0.42))
	_glow_lamp(img, 14, 9, Color(0.46, 1.0, 0.52), 1)   # the blinking cursor of doom
	_fill_rect(img, 11, 6, 11, 1, beige_hi)
	# floppy slot + eject button
	_fill_rect(img, 11, 18, 11, 3, beige_sh)
	_fill_rect(img, 11, 18, 11, 1, Color(0.05, 0.05, 0.06))
	_fill_rect(img, 20, 19, 2, 1, Color(0.82, 0.79, 0.72))
	for vy in range(23, 29, 2):
		_fill_rect(img, 11, vy, 11, 1, beige_sh.darkened(0.35))
		_fill_rect(img, 11, vy + 1, 11, 1, beige.lightened(0.12))
	# TURBO. Nobody has ever pressed it. Nobody ever will.
	_fill_rect(img, 17, 21, 5, 2, Color(0.40, 0.38, 0.32))
	_fill_rect(img, 17, 21, 5, 1, Color(0.72, 0.69, 0.60))
	_glow_lamp(img, 10, 27, Color(1.0, 0.68, 0.14), 1)  # power LED: amber, eternal
	_draw_line_img(img, 24, 12, 24, 18, Color(0.42, 0.24, 0.12))
	# A taped note. It says DO NOT TURN OFF. It is older than the team.
	_fill_rect(img, 1, 15, 9, 8, Color(0.94, 0.88, 0.44))
	_fill_rect(img, 1, 15, 9, 1, Color(1.0, 0.97, 0.68))
	_fill_rect(img, 1, 22, 9, 1, Color(0.58, 0.52, 0.22))
	_fill_rect(img, 2, 17, 7, 1, Color(0.30, 0.25, 0.10))
	_fill_rect(img, 2, 19, 5, 1, Color(0.30, 0.25, 0.10))
	_fill_rect(img, 3, 14, 5, 1, Color(0.86, 0.86, 0.84, 0.80))

## CLOUD BILL: a serene little cumulus delivering a number with too many digits.
## It knows you auto-renewed.
func _draw_cloud_bill(img: Image, c: Color) -> void:
	var cl := Color(0.86, 0.90, 0.98)
	var cl_sh := Color(0.44, 0.50, 0.68)
	var cl_sh2 := Color(0.22, 0.26, 0.42)
	var cl_hi := Color(0.99, 1.0, 1.0)
	_fill_circle(img, 11, 12, 7, cl_sh2)
	_fill_circle(img, 21, 12, 8, cl_sh2)
	_fill_circle(img, 15, 8, 7, cl_sh2)
	_fill_circle(img, 11, 11, 6, cl_sh)
	_fill_circle(img, 20, 11, 7, cl_sh)
	_fill_circle(img, 15, 7, 6, cl_sh)
	_fill_circle(img, 10, 10, 5, cl)
	_fill_circle(img, 19, 10, 5, cl)
	_fill_circle(img, 14, 6, 5, cl)
	_fill_circle(img, 12, 5, 3, cl_hi)
	_px(img, 11, 4, WHITE_HOT)
	_fill_rect(img, 5, 13, 23, 4, cl)
	_fill_rect(img, 5, 16, 23, 2, cl_sh)
	_fill_rect(img, 5, 17, 23, 1, cl_sh2)   # a hard underside: not a white blob
	# serene eyes with lids. It is not angry with you. It is simply itemised.
	for ex: int in [11, 18]:
		_fill_rect(img, ex, 9, 5, 3, Color(0.97, 0.98, 1.0))
		_fill_rect(img, ex + 1, 10, 2, 2, Color(0.05, 0.07, 0.14))
		_fill_rect(img, ex, 8, 5, 1, cl_sh2)
	_fill_rect(img, 14, 14, 4, 1, cl_sh2)   # a small, sympathetic mouth
	# the number. Drawn twice — a near-black body one pixel proud, then the
	# strokes on top — so it reads against a white cloud and a dark floor alike.
	var d := c.lightened(0.24)
	var d_hi := c.lightened(0.62)
	var d_sh := c.darkened(0.50)
	var ink := Color(0.04, 0.05, 0.09)
	for pass_i in 2:
		var col: Color = ink if pass_i == 0 else d
		var o: int = 1 if pass_i == 0 else 0
		_fill_rect(img, 12 - o, 19 - o, 8 + o * 2, 2 + o * 2, col)
		_fill_rect(img, 11 - o, 20 - o, 2 + o * 2, 4 + o * 2, col)
		_fill_rect(img, 12 - o, 23 - o, 8 + o * 2, 2 + o * 2, col)
		_fill_rect(img, 18 - o, 24 - o, 2 + o * 2, 4 + o * 2, col)
		_fill_rect(img, 11 - o, 27 - o, 8 + o * 2, 2 + o * 2, col)
		_fill_rect(img, 15 - o, 18 - o, 2 + o * 2, 12 + o * 2, col)
	_fill_rect(img, 15, 18, 1, 12, d_hi)
	_fill_rect(img, 12, 21, 8, 1, d_sh)
	_fill_rect(img, 12, 25, 8, 1, d_sh)
	_glow_lamp(img, 16, 23, d_hi, 1)
	# the decimals, raining, in the colour finance reserves for bad news
	for i in 4:
		var rx := 9 + ((i * 7) % 14)
		var ry := 20 + ((i * 5) % 8)
		_px(img, rx, ry, Color(1.0, 0.28, 0.28, 0.88 - float(i) * 0.14))
		_px(img, rx, ry + 1, Color(1.0, 0.28, 0.28, 0.42))

## Fallback for enemy types without bespoke art: a shaded blob with attitude.
func _draw_glow_blob(img: Image, c: Color) -> void:
	_fill_circle(img, 16, 16, 12, c.darkened(0.45))
	_fill_circle(img, 15, 15, 11, c)
	_fill_circle(img, 12, 12, 5, c.lightened(0.30))
	_px(img, 11, 11, WHITE_HOT)
	for ex: int in [12, 20]:
		_fill_circle(img, ex, 13, 3, Color(0.03, 0.03, 0.06))
		_fill_circle(img, ex, 13, 2, Color.WHITE)
		_px(img, ex, 13, Color.BLACK)
		_px(img, ex, 14, Color.BLACK)
		_px(img, ex - 1, 12, WHITE_HOT)

func _draw_rect_outline(img: Image, x: int, y: int, w: int, h: int, col: Color) -> void:
	for i in range(x, x + w):
		if i >= 0 and i < img.get_width():
			if y >= 0 and y < img.get_height():
				_px(img, i, y, col)
			if y + h - 1 >= 0 and y + h - 1 < img.get_height():
				_px(img, i, y + h - 1, col)
	for j in range(y, y + h):
		if j >= 0 and j < img.get_height():
			if x >= 0 and x < img.get_width():
				_px(img, x, j, col)
			if x + w - 1 >= 0 and x + w - 1 < img.get_width():
				_px(img, x + w - 1, j, col)

func _fill_ellipse(img: Image, cx: int, cy: int, rx: int, ry: int, c: Color, inset: int = 0) -> void:
	for x in img.get_width():
		for y in img.get_height():
			var dx := float(x - cx) / float(rx - inset)
			var dy := float(y - cy) / float(ry - inset)
			if dx * dx + dy * dy <= 1.0:
				_px(img, x, y, c if inset == 0 else c.lightened(0.08))

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
			_px(img, x, y, c)
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
	# Each denomination gets its own CUT as well as its own colour, so a token
	# is identifiable from its silhouette alone in a crowded pickup burst.
	var types := {
		"common": [Color(0.30, 0.80, 1.0), "round"],
		"cached": [Color(0.50, 0.90, 0.60), "hex"],
		"premium": [Color(1.0, 0.80, 0.20), "brilliant"],
		"golden": [Color(1.0, 0.85, 0.0), "radiant"],
		"frontier": [Color(0.90, 0.30, 1.0), "prism"],
		"compute": [Color(0.20, 0.90, 0.70), "chip"],
	}
	for tname in types:
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var spec: Array = types[tname]
		_draw_gem(img, spec[0], str(spec[1]))
		_save_image(img, "token_%s.png" % tname)

## Inside-the-stone test. One function owns every token silhouette.
func _gem_mask(x: int, y: int, cut: String) -> bool:
	var dx := absf(float(x) - 7.5)
	var dy := absf(float(y) - 7.5)
	match cut:
		"round":
			return Vector2(x, y).distance_to(Vector2(7.5, 7.5)) <= 6.2
		"hex":
			return dx <= 5.6 and dx + maxf(0.0, dy - 2.2) <= 6.4
		"brilliant":
			# a flat table, a broad crown, a pavilion tapering to a point
			if y <= 4:
				return dx <= 3.6
			if y <= 7:
				return dx <= 6.2
			return dx <= 6.2 - float(y - 7) * 0.85
		"prism":
			return dx / 4.8 + dy / 7.0 <= 1.0
		"chip":
			return dx <= 5.6 and dy <= 5.6 and dx + dy <= 9.0
	return dx / 6.4 + dy / 6.8 <= 1.0  # radiant

## A cut stone, not a coloured lozenge: a 5-tone facet ramp lit from the
## top-left, a girdle, seams radiating from the table, a refracted caustic
## escaping the bottom-right facet, a white-hot specular, and two halo rings so
## it still glows when it is lying on a near-black floor.
func _draw_gem(img: Image, c: Color, cut: String = "radiant") -> void:
	var light := c.lightened(0.34)
	var hot := c.lightened(0.66)
	var mid := c.darkened(0.16)
	var dark := c.darkened(0.34)
	var deep := c.darkened(0.56)
	var seam := c.darkened(0.66)
	for x in 16:
		for y in 16:
			if not _gem_mask(x, y, cut):
				continue
			var lit := -((float(x) - 7.5) + (float(y) - 7.5)) * 0.5
			var col := c
			if lit > 3.2:
				col = hot
			elif lit > 1.0:
				col = light
			elif lit > -0.8:
				col = c
			elif lit > -2.0:
				col = mid
			elif lit > -3.6:
				col = dark
			else:
				col = deep
			_px(img, x, y, col)
	_over_line(img, 0, 7, 15, 7, seam)                       # the girdle
	_over_line(img, 7, 0, 7, 15, seam.lightened(0.10))
	for k: int in [-1, 1]:
		_over_line(img, 7, 7, 7 + k * 5, 2, seam.lightened(0.18))
	_over_px(img, 7, 7, light)
	_over_px(img, 8, 7, mid)
	# the caustic: light refracted out through the shadow-side facet
	_over_px(img, 9, 10, light)
	_over_px(img, 10, 11, hot)
	_over_px(img, 11, 12, light)
	# the pixels that make it precious
	_over_px(img, 5, 4, WHITE_HOT)
	_over_px(img, 6, 3, hot)
	_over_px(img, 4, 5, hot)
	_over_px(img, 6, 5, light.lightened(0.25))
	_outline_silhouette(img, OUTLINE_COLOR)
	_halo_pass(img, Color(c.r, c.g, c.b, 0.32))
	_halo_pass(img, Color(c.r, c.g, c.b, 0.13))

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
			_px(panel, x, y, Color(base.r * v + 0.01, base.g * v + 0.01, base.b * v + 0.02, 0.92))
	for i in 64:
		_px(panel, i, 0, line)
		_px(panel, i, 63, line.darkened(0.3))
		_px(panel, 0, i, line)
		_px(panel, 63, i, line.darkened(0.3))
	for i in range(1, 63):
		_px(panel, i, 1, Color(0.22, 0.28, 0.45, 0.5))  # room light on the top edge
	for i in 7:
		_px(panel, i, 0, cyan)
		_px(panel, 0, i, cyan)
		_px(panel, 63 - i, 0, cyan)
		_px(panel, 63, i, cyan)
		_px(panel, i, 63, cyan)
		_px(panel, 0, 63 - i, cyan)
		_px(panel, 63 - i, 63, cyan)
		_px(panel, 63, 63 - i, cyan)
	_px(panel, 0, 0, WHITE_HOT)   # hot corners for a hint of bloom
	_px(panel, 63, 0, WHITE_HOT)
	_px(panel, 0, 63, WHITE_HOT)
	_px(panel, 63, 63, WHITE_HOT)
	_save_image(panel, "ui_panel.png")

func _generate_fx() -> void:
	# fx_glow_dot: 16x16 soft radial dot for particles and pickup bursts.
	# White, so consumers can modulate any accent over it.
	var dot := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	dot.fill(Color(0, 0, 0, 0))
	# A small solid plateau in the middle so additive users get a genuinely hot
	# core (it crosses the glow threshold) instead of a soft grey smudge.
	for x in 16:
		for y in 16:
			var d := Vector2(x - 7.5, y - 7.5).length() / 8.0
			if d >= 1.0:
				continue
			var a := 1.0 if d < 0.22 else pow((1.0 - d) / 0.78, 2.0)
			_px(dot, x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	_save_image(dot, "fx_glow_dot.png")
	# fx_spark: 8x8 four-point star with a white-hot 2x2 core.
	var spark := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	spark.fill(Color(0, 0, 0, 0))
	for i in 8:
		var fall := 1.0 - absf(i - 3.5) / 4.0
		_px(spark, i, 3, Color(1, 1, 1, fall))
		_px(spark, i, 4, Color(1, 1, 1, fall))
		_px(spark, 3, i, Color(1, 1, 1, fall))
		_px(spark, 4, i, Color(1, 1, 1, fall))
	for dpos in [Vector2i(2, 2), Vector2i(5, 2), Vector2i(2, 5), Vector2i(5, 5)]:
		_px(spark, dpos.x, dpos.y, Color(1, 1, 1, 0.35))
	for x in range(3, 5):
		for y in range(3, 5):
			_px(spark, x, y, WHITE_HOT)
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
			_px(img, x, y, Color(void_c.r * vig, void_c.g * vig, void_c.b * vig + 0.012 * vig, 1.0))
	# starfield specks, kept clear of the gem
	for i in 40:
		var sx := int(_hash01(i, 1, 55) * 127.0)
		var sy := int(_hash01(i, 2, 55) * 127.0)
		if Vector2(sx - 64, sy - 58).length() > 40.0:
			var b := 0.25 + _hash01(i, 3, 55) * 0.5
			_px(img, sx, sy, Color(b, b, minf(b * 1.1, 1.0), 1.0))
	# gold halo rings behind the gem
	var gold := Color(1.0, 0.83, 0.30)
	for x in 128:
		for y in 128:
			var d := Vector2(x - 64, y - 58).length()
			if d > 30.0 and d < 52.0:
				var a := (1.0 - (d - 30.0) / 22.0) * 0.20
				_px(img, x, y, img.get_pixel(x, y).lerp(gold, a))
	# the gem: big faceted diamond with an edge bevel and a 1px outline
	for x in 128:
		for y in 128:
			var ddx := absf(x - 64.0)
			var ddy := absf(y - 58.0) * 1.15
			var m := ddx / 30.0 + ddy / 30.0
			if m > 1.08:
				continue
			if m > 1.0:
				_px(img, x, y, Color(0.02, 0.02, 0.04))
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
			_px(img, x, y, col)
	# facet seams
	for x in range(35, 94):
		_px(img, x, 58, Color(0.55, 0.38, 0.08))
	for y in range(33, 84):
		_px(img, 64, y, Color(0.55, 0.38, 0.08))
	# internal sparkle + white-hot specular cluster
	_draw_line_img(img, 50, 44, 58, 52, Color(1.0, 0.95, 0.7))
	_fill_rect(img, 51, 42, 3, 3, WHITE_HOT)
	_px(img, 55, 46, WHITE_HOT)
	# reflection pool beneath
	for x in 128:
		for y in range(98, 114):
			var rdx := (x - 64.0) / 36.0
			var rdy := (y - 106.0) / 8.0
			var rd := rdx * rdx + rdy * rdy
			if rd <= 1.0:
				_px(img, x, y, img.get_pixel(x, y).lerp(gold, (1.0 - rd) * 0.12))
	# scanlines: the world is watched through a monitor
	for y in range(0, 128, 4):
		for x in 128:
			_px(img, x, y, img.get_pixel(x, y).darkened(0.12))
	# runner stripe
	_fill_rect(img, 34, 104, 60, 2, Color(0.14, 0.94, 0.86))
	_fill_rect(img, 34, 104, 60, 1, Color(0.55, 1.0, 0.95))
	img.save_png(ProjectSettings.globalize_path("res://assets/textures/icon.png"))

## ========== Round 4: structured floors + set-dressing fidelity ==========
## VISUAL_BIBLE Round 4 addendum. Rule 1: structure before noise — a floor set
## with readable construction (plank runs / panel grids / rock strata / pavers)
## authored DARK (mean luminance ~0.11-0.14, path ~0.17) so props and characters
## sit a full value step above the ground. Rule 2: the silhouette law — the
## dress_/furn_ set gets a post-pass so every labeled prop reads without its
## label. The composition side consumes these exists()-guarded; the filenames
## are contract.

func _generate_floor_structures() -> void:
	# region_builder resolves this set by REGION_TILE_MAP suffix ("gpu",
	# "cloud", ...), never by family name — so each region gets an alias copy
	# of its family, or every floor_* lookup misses and the whole set is
	# authored-but-unreachable (the round-3 lesson, again). The family files
	# stay as the canonical documented set.
	var interior_regions: Array[String] = ["localhost", "api_bazaar"]
	var industrial_regions: Array[String] = ["dependency", "corporate", "production"]
	var outdoor_regions: Array[String] = ["stackoverflow", "opensource", "gpu"]
	var ethereal_regions: Array[String] = ["cloud", "vault"]
	for alt: bool in [false, true]:
		var suffix := "_alt" if alt else "_base"
		_save_floor(_floor_interior(alt), "interior", interior_regions, suffix)
		_save_floor(_floor_industrial(alt), "industrial", industrial_regions, suffix)
		_save_floor(_floor_outdoor(alt), "outdoor", outdoor_regions, suffix)
		_save_floor(_floor_ethereal(alt), "ethereal", ethereal_regions, suffix)
	_save_image(_make_path_tile(), "path_tile.png")
	_save_image(_make_path_tile_edge(), "path_tile_edge.png")

## One floor family under its canonical name plus one alias per region that
## uses it (see _generate_floor_structures for why the aliases must exist).
func _save_floor(img: Image, family: String, regions: Array[String], suffix: String) -> void:
	_save_image(img, "floor_%s%s.png" % [family, suffix])
	for rk: String in regions:
		_save_image(img, "floor_%s%s.png" % [rk, suffix])

## Plank run in dark warm wood: 16px boards, staggered butt joints, grain that
## runs ALONG the board (see _mat_planks for why), nail heads. The alt variant
## stains a board and adds a knot. Seamless: every feature is modular in 64,
## and 0.19635 = TAU/32 so the grain wave wraps exactly.
func _floor_interior(alt: bool) -> Image:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var s: int = 4101 + (977 if alt else 0)
	var base := Color(0.34, 0.27, 0.21)
	var stain := Color(0.30, 0.20, 0.13)
	for y in 64:
		var row := y >> 4
		var ry := y & 15
		var pj := (_hash01(row, 3, s) - 0.5) * 0.12
		var stained: bool = alt and _hash01(row, 41, s) > 0.72
		var jx := int(_hash01(row, 7, s) * 64.0) % 64  # _hash01 can hit 1.0 exactly
		for x in 64:
			var c := base.lightened(pj) if pj > 0.0 else base.darkened(-pj)
			if stained:
				c = c.darkened(0.26).lerp(stain, 0.25)
			var g := sin(float(ry) * 1.35 + float(row) * 2.1 + sin(float(x) * 0.19635) * 1.8)
			if g > 0.72:
				c = c.darkened(0.14)
			elif g < -0.78:
				c = c.lightened(0.08)
			c = _pixel_noise(c, x, y, s, 0.03)
			if ry == 0:
				c = c.darkened(0.42)      # board seam
			elif ry == 1:
				c = c.lightened(0.09)     # lit board edge (light is top-left)
			elif ry == 15:
				c = c.darkened(0.16)
			if x == jx and ry > 0:
				c = c.darkened(0.36)      # butt joint, staggered per board
			elif x == (jx + 1) % 64 and ry > 0:
				c = c.lightened(0.07)
			_px(img, x, y, c)
	# a couple of nail heads per board
	for row in 4:
		for k in 2:
			# _hash01 can land exactly on 1.0, so 64-wide picks need the mini().
			var nx := mini(int(_hash01(row * 7 + k, 11, s) * 64.0), 63)
			var ny := row * 16 + 3 + int(_hash01(row, 13 + k, s) * 10.0)
			_px(img, nx, ny, img.get_pixel(nx, ny).darkened(0.34))
	if alt:
		var kx := int(_hash01(2, 37, s) * 56.0) + 4
		var ky := 16 * int(_hash01(3, 37, s) * 4.0) + 8
		for dy: int in range(-2, 3):
			for dx: int in range(-2, 3):
				var dd := dx * dx + dy * dy
				if dd <= 4:
					var px := (kx + dx + 64) % 64
					var py := (ky + dy + 64) % 64
					_px(img, px, py, img.get_pixel(px, py).darkened(0.48 if dd <= 1 else 0.30))
	_dim_tile(img, 0.42)
	return img

## Server-room deck: 32px machined panels, recessed seams with a lit near bevel,
## corner rivets, brushed-metal streaks. The alt variant vents one panel and
## wears a faded hazard chevron into another.
func _floor_industrial(alt: bool) -> Image:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var s: int = 8213 + (977 if alt else 0)
	var base := Color(0.34, 0.36, 0.44)
	var accent := Color(1.0, 0.69, 0.125)
	for y in 64:
		for x in 64:
			var cell := (x / 32) + (y / 32) * 2
			var cj := (_hash01(cell, 11, s) - 0.5) * 0.10
			var c := base.lightened(cj) if cj > 0.0 else base.darkened(-cj)
			if _hash01(0, y * 3 + cell, s) > 0.80:
				c = c.lightened(0.05)     # brushed-metal streak
			c = _pixel_noise(c, x, y, s, 0.025)
			var mx := x % 32
			var my := y % 32
			if mx == 0 or my == 0:
				c = c.darkened(0.44)      # panel seam
			elif mx == 1 or my == 1:
				c = c.lightened(0.09)     # bevel catches the light
			elif mx == 31 or my == 31:
				c = c.darkened(0.16)      # far bevel in shadow
			_px(img, x, y, c)
	for cy in 2:
		for cx in 2:
			for rv: Vector2i in [Vector2i(4, 4), Vector2i(27, 4), Vector2i(4, 27), Vector2i(27, 27)]:
				var px := cx * 32 + rv.x
				var py := cy * 32 + rv.y
				_px(img, px, py, img.get_pixel(px, py).darkened(0.55))
				_px(img, px - 1, py - 1, img.get_pixel(px - 1, py - 1).lightened(0.24))
	if alt:
		for i in 4:
			var yy := 40 + i * 4
			for xx: int in range(38, 58):
				_px(img, xx, yy, img.get_pixel(xx, yy).darkened(0.45))
				_px(img, xx, yy + 1, img.get_pixel(xx, yy + 1).lightened(0.08))
		for i in 10:
			for t in 3:
				var hx := 6 + i + t
				var hy := 6 + i
				if hx < 30 and hy < 30:
					_px(img, hx, hy, img.get_pixel(hx, hy).lerp(accent, 0.30))
	_dim_tile(img, 0.38)
	return img

## Rock strata: wavy horizontal beds with a dark crevice and a lit lip between
## them, per-bed value jitter, pebbles. The alt variant grows moss clumps.
## The wave uses TAU/32 so every edge wraps seamlessly.
func _floor_outdoor(alt: bool) -> Image:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var s: int = 6427 + (977 if alt else 0)
	var base := Color(0.33, 0.30, 0.24)
	var moss := Color(0.22, 0.46, 0.28)
	var edges: Array[int] = [0, 11, 21, 34, 45, 55]
	# per-column strata edge rows, offset by a wrapped wave
	var col_edges: Array[PackedInt32Array] = []
	for x in 64:
		var es := PackedInt32Array()
		for e: int in edges:
			es.append((e + int(roundf(2.2 * sin(float(x) * 0.19635 + float(e) * 1.3))) + 64) % 64)
		col_edges.append(es)
	for y in 64:
		for x in 64:
			var es: PackedInt32Array = col_edges[x]
			# the pixel belongs to the bed whose edge it most recently crossed
			var band := 0
			var best := 999
			for i in es.size():
				var d := posmod(y - es[i], 64)
				if d < best:
					best = d
					band = i
			var bj := (_hash01(band, 5, s) - 0.5) * 0.20
			var c := base.lightened(bj) if bj > 0.0 else base.darkened(-bj)
			var wv := sin(float(x) * 0.19635 + float(band) * 1.7)
			if wv > 0.55:
				c = c.lightened(0.06)
			elif wv < -0.6:
				c = c.darkened(0.07)
			c = _pixel_noise(c, x, y, s, 0.04)
			if best == 0:
				c = c.darkened(0.46)      # crevice between beds
			elif best == 1:
				c = c.lightened(0.13)     # lit lip under the crevice
			if alt and _hash01(x / 4, y / 4, s + 7) > 0.80:
				c = c.lerp(moss, 0.45)
			_px(img, x, y, c)
	# pebbles, wrapped so none straddles a seam
	for p in 9:
		var px := int(_hash01(p, 17, s) * 64.0) % 64
		var py := int(_hash01(p, 19, s) * 64.0) % 64
		var sh := base.darkened(0.34)
		var hi := base.lightened(0.26)
		_px(img, px, py, hi)
		_px(img, (px + 1) % 64, py, sh)
		_px(img, px, (py + 1) % 64, sh)
		_px(img, (px + 1) % 64, (py + 1) % 64, sh.darkened(0.12))
	_dim_tile(img, 0.42)
	return img

## Ethereal glass deck for the cloud/vault mood: 32px panes with faintly glowing
## violet seams, a dithered diagonal sheen (period 64 — wraps), glyph dots at
## some intersections. The alt variant runs a faint circuit trace along a seam.
func _floor_ethereal(alt: bool) -> Image:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var s: int = 9311 + (977 if alt else 0)
	var base := Color(0.30, 0.33, 0.48)
	var violet := Color(0.545, 0.36, 0.965)
	for y in 64:
		for x in 64:
			var cell := (x / 32) + (y / 32) * 2
			var cj := (_hash01(cell, 23, s) - 0.5) * 0.08
			var c := base.lightened(cj) if cj > 0.0 else base.darkened(-cj)
			var d := (x + y) % 64
			if d >= 20 and d < 30 and (x + y) % 2 == 0:
				c = c.lightened(0.10)     # dithered diagonal sheen
			c = _pixel_noise(c, x, y, s, 0.02)
			var mx := x % 32
			var my := y % 32
			if mx == 0 or my == 0:
				c = c.darkened(0.30).lerp(violet, 0.22)  # seams glow faintly
			elif mx == 1 or my == 1:
				c = c.lightened(0.07)
			_px(img, x, y, c)
	for cy in 2:
		for cx in 2:
			if _hash01(cx, cy, s + 3) > 0.5:
				var gx := cx * 32 + 16
				var gy := cy * 32 + 16
				_px(img, gx, gy, base.lerp(violet, 0.55).lightened(0.2))
				_px(img, gx - 1, gy, base.lerp(violet, 0.3))
				_px(img, gx + 1, gy, base.lerp(violet, 0.3))
	if alt:
		for x: int in range(8, 56):
			_px(img, x, 33, img.get_pixel(x, 33).lerp(violet, 0.18))
			if x % 12 == 0:
				_px(img, x, 34, img.get_pixel(x, 34).lerp(violet, 0.30))
	_dim_tile(img, 0.36)
	return img

## One running-bond paver pixel. Shared by path_tile and path_tile_edge so an
## edge tile placed against a path tile continues the same bond exactly.
func _paver_px(x: int, y: int, s: int) -> Color:
	var row := y >> 3
	var ry := y & 7
	var off := 8 if row % 2 == 1 else 0
	var col := ((x + off) % 64) >> 4
	var rx := (x + off) % 16
	var base := Color(0.44, 0.41, 0.36)
	var pj := (_hash01(col * 7 + row, 29, s) - 0.5) * 0.13
	var c := base.lightened(pj) if pj > 0.0 else base.darkened(-pj)
	c = _pixel_noise(c, x, y, s, 0.03)
	if ry == 0 or rx == 0:
		c = c.darkened(0.38)      # joint
	elif ry == 1 or rx == 1:
		c = c.lightened(0.10)     # lit bevel (top-left light)
	elif ry == 7 or rx == 15:
		c = c.darkened(0.14)      # far bevel
	if _hash01(col * 13 + row, 31, s) > 0.8 and rx == 12 and ry == 3:
		c = c.darkened(0.30)      # chipped paver
	return c

## Walkable path: running-bond pavers, authored a step BRIGHTER than every
## region floor (mean ~0.17 vs ~0.12) so "walk here" reads in a 1-second glance
## at a static frame — Round 4 rule 1.
func _make_path_tile() -> Image:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			_px(img, x, y, _paver_px(x, y, 7717))
	_dim_tile(img, 0.42)
	return img

## Path edge: pavers on top, a lit curb row, then a dithered feather down to
## TRANSPARENT so the composition side can border a path against any region
## floor. Rotate the sprite to orient the edge; the paver half matches
## path_tile row-for-row (same seed, same bond).
func _make_path_tile_edge() -> Image:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var s := 7717
	var soil := Color(0.14, 0.15, 0.20)
	for y in 64:
		for x in 64:
			if y < 48:
				_px(img, x, y, _paver_px(x, y, s))
			elif y == 48:
				_px(img, x, y, Color(0.62, 0.58, 0.50))   # curb catches the light
			elif y <= 51:
				_px(img, x, y, Color(0.26, 0.24, 0.21).darkened(0.14 * float(y - 49)))
			else:
				var t := float(y - 52) / 11.0
				var a := maxf(0.0, 0.85 * (1.0 - t))
				if _hash01(x, y, s) < t * 0.8:
					a = 0.0                                # ragged dithered feather
				var c := _pixel_noise(soil, x, y, s, 0.03)
				_px(img, x, y, Color(c.r, c.g, c.b, a))
	_dim_tile(img, 0.42)
	return img

## ---------- Round 4 rule 2: the silhouette law, applied to the dressing ----------
## interior_generator draws the dress_/furn_ set with its own rim + outline, but
## the round-3 QA frames still show them as dark smudges at game zoom: their
## midtones crush once the region ambient (0.6-0.8) and the builders' prop
## modulates multiply in. This post-pass reloads each finished PNG and widens it
## to >= 3 clear value steps, re-asserts the lit-side rim, sinks the base, and
## bakes a contact shadow — in place, same filename, same canvas, so every
## consumer keeps positioning by size. Floor decals (decal_*) are deliberately
## NOT run through this chain: they are translucent overlay marks that already
## carry a dark core / mid ring / lit lip, and an outline or shadow would turn
## grime into an object (and break Round 4 rule 1's "noise on top at low
## opacity").
func _polish_interior_props() -> void:
	var grounded: Array[String] = [
		"dress_stall", "dress_monolith", "dress_cooling_tower", "dress_ore_cart",
		"dress_whiteboard", "dress_filing_cabinet", "dress_cubicle",
		"dress_laser_emitter", "dress_noodle_cup", "dress_cable_spool",
		"dress_pipe_stack",
		"furn_desk", "furn_monitor", "furn_server", "furn_bed", "furn_fridge",
		"furn_coffee", "furn_plant", "furn_boxes", "furn_shelf", "furn_chair",
	]
	# Hung or wall-mounted: everything except the ground shadow.
	var mounted: Array[String] = ["dress_awning", "furn_door", "furn_whiteboard"]
	for fname: String in grounded:
		_polish_prop(fname, true)
	for fname: String in mounted:
		_polish_prop(fname, false)

func _polish_prop(fname: String, grounded: bool) -> void:
	var img := _load_generated(fname + ".png")
	if img == null:
		return
	# Same order as the enemy readability chain: widen the interior BEFORE any
	# edge work so the existing outline stays the darkest thing on the sprite.
	_readability_pass(img, 0.30, 0.30, 0.10)
	_underside_ao(img, 4, 0.30)
	# The lit-side rim lands on the top-left outline pixels (sel-out). Near-white
	# survives any region tint, where a coloured rim would just be tinted away.
	_rim_light_pass(img, Color(0.94, 0.95, 1.0), 0.38)
	if grounded:
		_contact_shadow(img)
	_save_image(img, fname + ".png")

## Reload a PNG this run already wrote. Returns null when a prop doesn't exist
## (the interior set can evolve independently); the caller skips it.
func _load_generated(filename: String) -> Image:
	var path := ProjectSettings.globalize_path(OUT_DIR + filename)
	if not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	if img.load(path) != OK:
		return null
	return img

func _save_image(img: Image, filename: String) -> void:
	img.save_png(ProjectSettings.globalize_path(OUT_DIR + filename))

## Bounds-guarded pixel write. Raw Image.set_pixel spams engine errors (and
## drops the write) when a pose or prop pushes a decoration past the frame
## edge; every low-level helper in this file already clamps, so this makes the
## direct writes behave the same way.
func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	img.set_pixel(x, y, c)

func _fill_rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for ix in range(x, x + w):
		for iy in range(y, y + h):
			if ix >= 0 and iy >= 0 and ix < img.get_width() and iy < img.get_height():
				_px(img, ix, iy, c)

func _fill_circle(img: Image, cx: int, cy: int, r: int, c: Color) -> void:
	for x in img.get_width():
		for y in img.get_height():
			if Vector2(x, y).distance_to(Vector2(cx, cy)) <= r:
				_px(img, x, y, c)

func _draw_circle_outline(img: Image, cx: int, cy: int, r: int, c: Color) -> void:
	for x in img.get_width():
		for y in img.get_height():
			if abs(Vector2(x, y).distance_to(Vector2(cx, cy)) - r) < 1.2:
				_px(img, x, y, c)

func _fill_arc(img: Image, cx: int, cy: int, r: int, c: Color) -> void:
	for x in img.get_width():
		for y in img.get_height():
			if Vector2(x, y).distance_to(Vector2(cx, cy)) <= r and y < cy + 4:
				_px(img, x, y, c)

func _draw_hex(img: Image, cx: int, cy: int, r: int, c: Color) -> void:
	for x in img.get_width():
		for y in img.get_height():
			if float(abs(x - cx)) / r + float(abs(y - cy)) / r * 1.15 <= 1.0:
				_px(img, x, y, c)

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
			_px(img, ix, iy, a if ((ix / 2 + iy / 2) % 2 == 0) else b)

## WHITE_HOT core + accent halo — the bible's recipe for emissive pixels.
## HDR bloom picks the core up on its own; the halo sells the falloff.
func _glow_core(img: Image, x: int, y: int, accent: Color) -> void:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = x + d.x
		var ny: int = y + d.y
		if nx >= 0 and ny >= 0 and nx < img.get_width() and ny < img.get_height():
			_px(img, nx, ny, accent)
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		_px(img, x, y, WHITE_HOT)

## A bigger emissive tell than _glow_core: an accent disc, a hot inner disc, a
## WHITE_HOT core, and a dim bleed ring painted only onto pixels that already
## exist (so a lamp never grows the silhouette). Every region multiplies the
## whole canvas by its ambient tint, and a near-white core is the only thing
## that survives that multiply in EVERY region — which is why the tell is built
## out of one.
func _glow_lamp(img: Image, x: int, y: int, accent: Color, r: int = 2) -> void:
	var hot := accent.lerp(WHITE_HOT, 0.55)
	_fill_circle(img, x, y, r, accent)
	_fill_circle(img, x, y, r - 1, hot)
	_px(img, x, y, WHITE_HOT)
	var bleed := accent.darkened(0.30)
	var rr := float((r + 1) * (r + 1))
	for dx in range(-r - 1, r + 2):
		for dy in range(-r - 1, r + 2):
			var d := float(dx * dx + dy * dy)
			if d > float(r * r) and d <= rr:
				_over_px(img, x + dx, y + dy, bleed)

## A two-pixel line. One-pixel appendages (beetle legs, pseudopods, dependency
## strands) survive neither the outline pass nor the threat halo at game zoom —
## they come back as dithered noise. Two pixels is the floor for anything that
## has to read as a limb.
func _thick_line(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	_draw_line_img(img, x0, y0, x1, y1, c)
	if absi(x1 - x0) >= absi(y1 - y0):
		_draw_line_img(img, x0, y0 + 1, x1, y1 + 1, c)
	else:
		_draw_line_img(img, x0 + 1, y0, x1 + 1, y1, c)

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
				_px(img, x, y, p.lerp(Color(rim.r, rim.g, rim.b, p.a), strength))

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
				_px(img, x, y, halo)

## ---------- enemy readability (a playability pass, not decoration) ----------

## Full value + boosted chroma, same hue. Several enemy accents are muted
## (legacy beige, architect blue-grey); halos drawn in the raw colour are
## invisible against a dark floor, which defeats the point of drawing them.
func _vivid_color(c: Color, chroma: float = 1.4) -> Color:
	var mx: float = maxf(c.r, maxf(c.g, c.b))
	if mx <= 0.001:
		return c
	var n := Color(c.r / mx, c.g / mx, c.b / mx, c.a)
	var lum: float = n.r * 0.299 + n.g * 0.587 + n.b * 0.114
	return Color(
		clampf(lum + (n.r - lum) * chroma, 0.0, 1.0),
		clampf(lum + (n.g - lum) * chroma, 0.0, 1.0),
		clampf(lum + (n.b - lum) * chroma, 0.0, 1.0),
		c.a)

## Lift muddy midtones and boost chroma across a sprite body. Near-black detail
## (pupils, seams, chevrons) is deliberately left alone — that internal contrast
## is what makes the shape legible — and highlights are left alone too, so the
## 4-tone ramp survives.
func _readability_pass(img: Image, min_luma: float, lift: float, sat: float) -> void:
	for x in img.get_width():
		for y in img.get_height():
			var p := img.get_pixel(x, y)
			if p.a <= 0.5:
				continue
			var l: float = p.r * 0.299 + p.g * 0.587 + p.b * 0.114
			var c := p
			if sat > 0.0:
				c = Color(
					clampf(l + (p.r - l) * (1.0 + sat), 0.0, 1.0),
					clampf(l + (p.g - l) * (1.0 + sat), 0.0, 1.0),
					clampf(l + (p.b - l) * (1.0 + sat), 0.0, 1.0),
					p.a)
			if l > 0.075 and l < min_luma:
				c = c.lightened(lift * (min_luma - l) / min_luma)
			c.a = p.a
			_px(img, x, y, c)

## Widen a sprite's internal value range around a pivot: lights go lighter,
## darks go darker, hue untouched. Every region's CanvasModulate multiplies the
## whole canvas toward the floor's value, and a narrow range collapses into one
## flat blob under that multiply. This is the single pass that stopped enemies
## reading as smudges — it costs nothing and it survives every ambient tint,
## because it trades on VALUE rather than hue.
func _value_expand(img: Image, pivot: float, amount: float) -> void:
	for x in img.get_width():
		for y in img.get_height():
			var p := img.get_pixel(x, y)
			if p.a <= 0.5:
				continue
			var l: float = p.r * 0.299 + p.g * 0.587 + p.b * 0.114
			var k: float = (l - pivot) * amount
			_px(img, x, y, Color(clampf(p.r + k, 0.0, 1.0), clampf(p.g + k, 0.0, 1.0),
				clampf(p.b + k, 0.0, 1.0), p.a))

## Two-ring emissive halo hugging the outline. Ring one is opaque enough to
## count as "solid" so ring two can grow outside it; together they read as a
## 4px threat glow at the 2x scale enemies render at. This is the single change
## that makes a dark creature pop off a dark floor without repainting it.
func _threat_halo(img: Image, hue: Color) -> void:
	# Ring one MUST land above 0.5 alpha: _halo_pass only grows from pixels whose
	# alpha is > 0.5, so at the old 0.48 the second call found nothing adjacent
	# to a "solid" pixel that was not already painted and the two-ring halo this
	# comment describes was silently a single one-pixel ring. 0.55 quantises to
	# 140/255 = 0.549 in RGBA8, which clears the test with room to spare.
	_halo_pass(img, Color(hue.r, hue.g, hue.b, 0.55))
	_halo_pass(img, Color(hue.r, hue.g, hue.b, 0.19))

## Soft elliptical contact shadow under the silhouette, stamped into empty
## pixels only. Grounds hovering enemies and darkens the floor right behind
## them — half of why they read at a glance.
func _contact_shadow(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var min_x := w
	var max_x := -1
	var max_y := -1
	for x in w:
		for y in h:
			if img.get_pixel(x, y).a > 0.5:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	if max_x < 0:
		return
	var cx := float(min_x + max_x) * 0.5
	var cy := float(mini(max_y, h - 3))
	var rx: float = maxf(float(max_x - min_x) * 0.46, 4.0)
	var ry := 3.5
	for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
		for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
			if x < 0 or y < 0 or x >= w or y >= h:
				continue
			if img.get_pixel(x, y).a > 0.03:
				continue
			var dx := (float(x) - cx) / rx
			var dy := (float(y) - cy) / ry
			var d := dx * dx + dy * dy
			if d > 1.0:
				continue
			_px(img, x, y, Color(0.008, 0.010, 0.028, 0.34 * (1.0 - d)))

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
			_px(img, x, y, c)


## Rect with the four corner pixels dropped — the cheapest way to stop small
## props reading as dice.
func _fill_round_rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for ix in range(x, x + w):
		for iy in range(y, y + h):
			if ix < 0 or iy < 0 or ix >= img.get_width() or iy >= img.get_height():
				continue
			if (ix == x or ix == x + w - 1) and (iy == y or iy == y + h - 1):
				continue
			_px(img, ix, iy, c)

## A 4-tone limb (arm, leg, sleeve): lit edge, base, dithered terminator, core
## shadow. Light is top-left, so the lit edge is the left one.
func _shade_limb(img: Image, x: int, y: int, w: int, h: int, base: Color) -> void:
	var hi := base.lightened(0.22)
	var sh := base.darkened(0.30)
	var sh2 := base.darkened(0.48)
	for iy in range(y, y + h):
		for ix in range(x, x + w):
			if ix < 0 or iy < 0 or ix >= img.get_width() or iy >= img.get_height():
				continue
			var u := ix - x
			var c := base
			if u == 0:
				c = hi
			elif u == 1:
				c = base.lightened(0.08)
			elif u >= w - 1:
				c = sh2
			elif u >= w - 2:
				c = sh
			elif u == w - 3 and w > 4:
				c = sh if ((ix + iy) % 2 == 0) else base
			_px(img, ix, iy, c)

## Rim light on ONE diagonal silhouette edge. `_rim_light_pass` is the top-left
## special case; this one also lets a warm floor bounce hit the bottom-right,
## which is what gives characters two-point lighting instead of one.
func _edge_light(img: Image, rim: Color, strength: float, from_left: bool, from_top: bool) -> void:
	var src: Image = img.duplicate()
	var w := img.get_width()
	var h := img.get_height()
	for x in w:
		for y in h:
			var p := src.get_pixel(x, y)
			if p.a <= 0.5:
				continue
			var ny: int = y - 1 if from_top else y + 1
			var nx: int = x - 1 if from_left else x + 1
			var open_v := ny < 0 or ny >= h or src.get_pixel(x, ny).a <= 0.5
			var open_h := nx < 0 or nx >= w or src.get_pixel(nx, y).a <= 0.5
			if open_v or open_h:
				_px(img, x, y, p.lerp(Color(rim.r, rim.g, rim.b, p.a), strength))

## Lerp a whole sprite toward a tint while protecting its highlights, so a hurt
## frame still reads as a POSE and not as a red rectangle.
func _impact_tint(img: Image, tint: Color, amount: float) -> void:
	for x in img.get_width():
		for y in img.get_height():
			var p := img.get_pixel(x, y)
			if p.a <= 0.02:
				continue
			var l: float = p.r * 0.299 + p.g * 0.587 + p.b * 0.114
			var c := p.lerp(Color(tint.r, tint.g, tint.b, p.a), amount * (1.0 - l * 0.55))
			c.a = p.a
			_px(img, x, y, c)

## A motion streak drawn only into empty pixels, at an alpha deliberately below
## the outline pass's solidity threshold so it stays soft and un-outlined.
func _streak(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	var steps := maxi(absi(x1 - x0), absi(y1 - y0))
	if steps <= 0:
		return
	for i in steps + 1:
		var t := float(i) / float(steps)
		var px := int(round(float(x0) + float(x1 - x0) * t))
		var py := int(round(float(y0) + float(y1 - y0) * t))
		if px < 0 or py < 0 or px >= img.get_width() or py >= img.get_height():
			continue
		if img.get_pixel(px, py).a > 0.05:
			continue
		_px(img, px, py, Color(c.r, c.g, c.b, c.a * (1.0 - t * 0.8)))

## The 2px arc that turns two ear cups into an actual pair of headphones.
func _arc_band(img: Image, cx: int, cy: int, r: int, c: Color, hi: Color, y_limit: int) -> void:
	for x in img.get_width():
		for y in img.get_height():
			if y > y_limit:
				continue
			var d := Vector2(x, y).distance_to(Vector2(cx, cy))
			if d > float(r) + 1.2 or d < float(r) - 0.8:
				continue
			var lit := x < cx and y < cy and d > float(r) + 0.2
			_px(img, x, y, hi if lit else c)

## Darken the inside of a sprite's lower edge. Enemies float without it; with
## it they sit in the floor, and their value range widens for free.
func _underside_ao(img: Image, depth: int = 3, amount: float = 0.42) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for x in w:
		var run := 0
		for y in range(h - 1, -1, -1):
			var p := img.get_pixel(x, y)
			if p.a <= 0.5:
				run = 0
				continue
			run += 1
			if run <= depth:
				var k: float = amount * (1.0 - float(run - 1) / float(depth))
				_px(img, x, y, Color(p.r * (1.0 - k), p.g * (1.0 - k), p.b * (1.0 - k), p.a))

## Paint only where the sprite already is — facet detail must never escape the
## stone it belongs to (or the outline pass will trace the escape).
func _over_px(img: Image, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	if img.get_pixel(x, y).a <= 0.05:
		return
	_px(img, x, y, c)

func _over_line(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	var dx: int = absi(x1 - x0)
	var dy: int = -absi(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err := dx + dy
	var x := x0
	var y := y0
	for _i in 64:
		_over_px(img, x, y, c)
		if x == x1 and y == y1:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy
