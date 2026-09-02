extends RefCounted
class_name AssetGeneratorRuntime

const OUT_DIR := "res://assets/textures/generated/"

## VISUAL_BIBLE_V2 constants — every sprite in the game agrees on these.
## LAW 7: one outline for everything, 1px, #0A0C16 at 90%. There is no second,
## harder outline for enemies any more: an enemy reads as hostile by SILHOUETTE
## and by its one red tell, not by being drawn in a louder ink than its
## neighbours.
const OUTLINE_COLOR := Color(0.039, 0.047, 0.086, 0.90)  # #0A0C16 @ 90%
const WHITE_HOT := Color(0.957, 0.976, 1.0)              # emissive core, ONE per light
const OUTLINE_ENEMY := Color(0.039, 0.047, 0.086, 0.90)
## LAW 2 globals. GOLD is tokens/currency ONLY; HOSTILE is the enemy tell ONLY.
const GOLD := Color(1.0, 0.827, 0.302)                   # #FFD34D
const HOSTILE := Color(1.0, 0.278, 0.341)                # #FF4757
## LAW 7: every enemy body is repainted into these four desaturated stops.
## Thirteen creatures used to mean thirteen palettes and eight hues a frame;
## now the cast shares one material and separates on SHAPE. Value order is what
## carries the read, so the ramp is deliberately wide and deliberately grey.
const ENEMY_RAMP := [
	Color(0.078, 0.086, 0.118),
	Color(0.161, 0.176, 0.227),
	Color(0.278, 0.302, 0.373),
	Color(0.451, 0.482, 0.565),
]
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
##
## LAW 2/LAW 7, round 6: the cast used to wear eleven saturated garments — an
## orange foreman, a teal roommate, a pale-blue cloud rep — which is most of why
## a frame carried eight hues. Every BODY is now desaturated (chroma under ~0.12
## on the garment ramp), and each character keeps exactly ONE accent detail in
## its region's ACCENT: a badge, a glasses glint, a headlamp. They are still
## told apart in silhouette, which is where the work belonged all along.
func _generate_npcs() -> void:
	var kinds := {
		"claude": {
			"hoodie": Color(0.22, 0.25, 0.27), "hoodie_hi": Color(0.33, 0.37, 0.39),
			"hoodie_sh": Color(0.12, 0.14, 0.16), "hair": Color(0.15, 0.13, 0.12),
			"skin": Color(0.72, 0.62, 0.53), "accent": Color(0.141, 0.941, 0.863),
			"legs": Color(0.15, 0.17, 0.20), "headphones": true, "accessory": "circuit",
		},
		"suit": {
			"hoodie": Color(0.19, 0.20, 0.25), "hoodie_hi": Color(0.29, 0.31, 0.37),
			"hoodie_sh": Color(0.10, 0.11, 0.14), "hair": Color(0.20, 0.16, 0.12),
			"skin": Color(0.70, 0.61, 0.52), "accent": Color(0.302, 0.486, 1.0),
			"legs": Color(0.13, 0.14, 0.18), "shoe": Color(0.16, 0.15, 0.15),
			"headphones": false, "accessory": "tie", "garment": "suit",
			"headwear": "slick", "build": "broad", "props": ["lanyard"],
		},
		"maintainer": {
			"hoodie": Color(0.28, 0.29, 0.28), "hoodie_hi": Color(0.39, 0.40, 0.39),
			"hoodie_sh": Color(0.15, 0.16, 0.16), "hair": Color(0.42, 0.42, 0.43),
			"skin": Color(0.68, 0.58, 0.49), "accent": Color(0.345, 0.878, 0.486),
			"legs": Color(0.21, 0.21, 0.23), "shoe": Color(0.44, 0.43, 0.41),
			"headphones": false, "accessory": "glasses", "build": "hunched",
			"drop": 2, "props": ["noodles"],
		},
		"foreman": {
			"hoodie": Color(0.34, 0.30, 0.26), "hoodie_hi": Color(0.46, 0.41, 0.35),
			"hoodie_sh": Color(0.19, 0.16, 0.14), "hair": Color(0.15, 0.12, 0.10),
			"skin": Color(0.66, 0.57, 0.48), "accent": Color(1.0, 0.42, 0.176),
			"legs": Color(0.21, 0.19, 0.18), "shoe": Color(0.25, 0.22, 0.19),
			"headphones": false, "accessory": "hardhat", "garment": "hivis",
			"build": "broad", "props": ["thermal_gun"],
		},
		"svp": {
			"hoodie": Color(0.21, 0.22, 0.27), "hoodie_hi": Color(0.31, 0.33, 0.39),
			"hoodie_sh": Color(0.11, 0.12, 0.15), "hair": Color(0.22, 0.18, 0.14),
			"skin": Color(0.71, 0.61, 0.52), "accent": Color(0.302, 0.486, 1.0),
			"legs": Color(0.14, 0.15, 0.19), "shoe": Color(0.14, 0.13, 0.13),
			"headphones": false, "accessory": "tie", "garment": "suit",
			"headwear": "slick", "build": "broad", "drop": -2,
			"props": ["lanyard"],
		},
		"junior": {
			"hoodie": Color(0.24, 0.28, 0.28), "hoodie_hi": Color(0.35, 0.40, 0.39),
			"hoodie_sh": Color(0.13, 0.15, 0.16), "hair": Color(0.32, 0.23, 0.15),
			"skin": Color(0.73, 0.63, 0.53), "accent": Color(0.345, 0.878, 0.486),
			"legs": Color(0.18, 0.20, 0.24), "headphones": false, "build": "small",
			"drop": 5, "back": "backpack", "props": ["thumbs_up"],
		},
		"hermit": {
			"hoodie": Color(0.31, 0.29, 0.25), "hoodie_hi": Color(0.42, 0.39, 0.34),
			"hoodie_sh": Color(0.17, 0.16, 0.13), "hair": Color(0.46, 0.45, 0.43),
			"skin": Color(0.65, 0.56, 0.47), "accent": Color(0.910, 0.769, 0.420),
			"headphones": false, "garment": "robe", "headwear": "hood",
			"beard": true, "props": ["tablet"],
		},
		"oncall": {
			"hoodie": Color(0.27, 0.24, 0.25), "hoodie_hi": Color(0.37, 0.34, 0.35),
			"hoodie_sh": Color(0.15, 0.13, 0.14), "hair": Color(0.28, 0.22, 0.19),
			"skin": Color(0.69, 0.59, 0.50), "accent": Color(1.0, 0.690, 0.125),
			"legs": Color(0.19, 0.19, 0.22), "shoe": Color(0.40, 0.39, 0.38),
			"headphones": false, "garment": "coat", "build": "hunched", "drop": 1,
			"props": ["mug", "wild_hair"],
		},
		"reseller": {
			"hoodie": Color(0.20, 0.19, 0.22), "hoodie_hi": Color(0.30, 0.28, 0.32),
			"hoodie_sh": Color(0.11, 0.10, 0.12), "hair": Color(0.13, 0.11, 0.10),
			"skin": Color(0.68, 0.58, 0.49), "accent": Color(1.0, 0.176, 0.584),
			"legs": Color(0.14, 0.13, 0.16), "shoe": Color(0.17, 0.16, 0.16),
			"headphones": false, "garment": "coat", "headwear": "cap",
			"accessory": "shades", "props": ["keys"],
		},
		"cloud": {
			"hoodie": Color(0.33, 0.35, 0.38), "hoodie_hi": Color(0.45, 0.47, 0.51),
			"hoodie_sh": Color(0.18, 0.19, 0.22), "hair": Color(0.34, 0.27, 0.19),
			"skin": Color(0.73, 0.63, 0.54), "accent": Color(0.420, 0.780, 1.0),
			"legs": Color(0.24, 0.26, 0.30), "shoe": Color(0.66, 0.68, 0.71),
			"headphones": false, "accessory": "tie", "garment": "blazer",
			"headwear": "slick", "props": ["cloud_balloon"],
		},
	}
	for k in kinds:
		# No halo pass on anyone. The roommate reads as the roommate because he is
		# the only character standing at the desk, not because he is backlit.
		_save_image(_draw_vibe_coder("down", "idle", 0, kinds[k]), "npc_%s.png" % k)

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
	# An empty palette means the vibe coder himself. He is the only figure in the
	# game that gets a rim tone, an accent-lit prop or a bright shoe (LAW 3: the
	# player is one of the five things allowed to be bright).
	var is_player: bool = palette.is_empty()
	# --- material ramps (shadow / base / light) ---
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

	# There is no fourth garment tone any more (LAW 7). "rim" is simply the light
	# stop, kept as a name so the limb helpers still read.
	var hoodie_rim := hoodie_hi
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
		shoe, shoe_hi, sole, garment)

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
		hoodie, hoodie_hi, hoodie_sh, hoodie_rim)

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
	# LAW 7: three tones per material, lit from the top-left, and a FOURTH "rim"
	# tone only on the player. Round 5 gave every character a bright accent key
	# rim AND a warm bottom-right bounce rim; eleven NPCs edge-lit in eleven hues
	# is a large part of why nothing in a frame read as more important than
	# anything else. The player keeps one quiet near-white rim — he is the one
	# thing on screen that is allowed to be found instantly.
	if is_player:
		_edge_light(img, Color(0.88, 0.92, 1.0), 0.26, true, true)
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
		sole: Color, garment: String) -> void:
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
		# Three tones and a sole. The neon swoosh is gone: four accent pixels at
		# ankle height on every character in the game bought nothing except hue count.
		_fill_round_rect(img, sx, sy, 8, 4, shoe)
		_fill_rect(img, sx + 1, sy, 6, 1, shoe_hi)              # lit toe box
		_fill_rect(img, sx, sy + 3, 8, 1, sole)                 # gum sole
		_fill_rect(img, sx + 7, sy + 1, 1, 2, shoe.darkened(0.28))

## The torso, drawn row by row from the profile so the shoulders slope and the
## waist comes in. Then the garment-specific dressing on top.
func _vc_torso(img: Image, cx: int, ty: int, tilt: int, build: String, side: bool,
		up: bool, garment: String, hoodie: Color, hoodie_hi: Color, hoodie_sh: Color,
		hoodie_rim: Color) -> void:
	for i in TORSO_ROWS:
		var hw := _torso_hw(i, build, side)
		var y := ty + i
		# the lean shears the torso: the higher the row, the further it travels
		var sx := cx + int(round(float(tilt) * (1.0 - float(i) / float(TORSO_ROWS))))
		# Three tones, hard-edged. The old ramp was six stops with two checkerboard
		# dither bands inside a 22px torso — at 2x that is not cloth, it is static.
		for x in range(sx - hw, sx + hw + 1):
			var u := x - (sx - hw)
			var span := hw * 2
			var c := hoodie
			if u <= 1:
				c = hoodie_hi
			elif u >= span - 1:
				c = hoodie_sh
			if i == 0:
				c = c.lerp(hoodie_rim, 0.45)   # the shoulder catches the key
			_px(img, x, y, c)
	var sx0 := cx + tilt
	if garment == "hivis":
		# One retroreflective band, not two, and no white-hot pip on the zip: a
		# hi-vis vest is a silhouette cue, not a light source.
		var hw_a := _torso_hw(6, build, side)
		_fill_rect(img, sx0 - hw_a, ty + 8, hw_a * 2 + 1, 2, Color(0.78, 0.79, 0.82))
		_fill_rect(img, sx0 - hw_a, ty + 8, hw_a * 2 + 1, 1, Color(0.88, 0.89, 0.92))
		_fill_rect(img, sx0 - hw_a, ty + 10, hw_a * 2 + 1, 1, hoodie_sh)
		_fill_rect(img, sx0 - 1, ty, 2, TORSO_ROWS - 2, hoodie_sh)
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
	# kangaroo pocket: a shadowed cavity with a lit seam. No dither inside an 11px
	# rectangle (LAW 7), and one fold instead of three.
	_fill_rect(img, sx0 - 5, ty + 11, 11, 5, hoodie_sh)
	_fill_rect(img, sx0 - 5, ty + 10, 11, 1, hoodie_sh.darkened(0.34))
	_fill_rect(img, sx0 - 5, ty + 11, 11, 1, hoodie_hi.darkened(0.20))
	_draw_line_img(img, sx0 - 9, ty + 6, sx0 - 5, ty + 9, hoodie_sh)
	# drawstrings. Cloth, not fibre optics: the aglets used to be white-hot, which
	# put two bloom sources on the chest of every character in the cast.
	for k: int in [-3, 3]:
		_fill_rect(img, sx0 + k, ty + 1, 1, 5, hoodie_sh.darkened(0.15))
		_px(img, sx0 + k, ty + 6, hoodie_hi)

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
		# 3am stubble along the jaw: one flat shadow tone. It used to be two
		# dithered 5x3 patches on a 16px head — checkerboard noise, not beard.
		_fill_rect(img, cx - 7, hy + 5, 5, 2, skin_sh)
		_fill_rect(img, cx + 3, hy + 5, 5, 2, skin_sh)
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
	_fill_rect(img, cx + 4, hy - 8 + hair_lag, 4, 3, hair_sh)
	_vc_hair_spikes(img, cx, hy - 11 + hair_lag, hair, hair_hi, hair_lag)

## Silhouette breakers. A smooth dome reads as a helmet; spikes read as hair.
func _vc_hair_spikes(img: Image, cx: int, top: int, hair: Color, hair_hi: Color, hair_lag: int) -> void:
	var sx_off: Array[int] = [-7, -5, -2, 1, 4, 7]
	var sh_len: Array[int] = [1, 2, 1, 3, 2, 1]
	for i in 6:
		var sx := cx + sx_off[i] + (1 if hair_lag > 0 else 0)
		for k in sh_len[i]:
			_px(img, sx, top - k, hair if k < sh_len[i] - 1 else hair_hi.darkened(0.2))

## The face. Tired but determined: heavy brows angled inward and the eye bags
## that paid for the ambition. Three tones of skin, no emissive pixels.
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
		if i == 0:
			_draw_line_img(img, ex, hy - 3, ex + 2, hy - 2, brow)
		else:
			_draw_line_img(img, ex + 2, hy - 3, ex, hy - 2, brow)
		# Eye bags in one flat tone. The white-hot catch-light is gone: an eye is
		# not a light source, and two bloom pixels per face across a cast of
		# eleven is exactly the "everything is emissive" read LAW 3 forbids.
		_fill_rect(img, ex, hy + 2, 3, 1, skin_sh.darkened(0.18))
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
## that is exactly one white-hot pixel with one pixel of accent spill on the
## cup below it — a light, not a sticker, and not a lamp.
func _vc_headphones(img: Image, cx: int, hy: int, side: bool,
		cup: Color, cup_hi: Color, glow: Color) -> void:
	_arc_band(img, cx, hy + 1, 11, cup, cup_hi, hy - 4)
	if side:
		_fill_round_rect(img, cx - 6, hy - 3, 5, 9, cup)
		_fill_rect(img, cx - 6, hy - 2, 1, 7, cup_hi)
		_fill_round_rect(img, cx - 5, hy - 2, 3, 7, cup.lightened(0.12))
		_px(img, cx - 6, hy, WHITE_HOT)   # the one genuine light on the head
		_px(img, cx - 6, hy + 1, glow.darkened(0.35))   # its spill, on the cup
		return
	for k: int in [-1, 1]:
		var x0: int = cx - 10 if k < 0 else cx + 7
		_fill_round_rect(img, x0, hy - 4, 4, 9, cup)
		_fill_rect(img, x0, hy - 3, 1, 7, cup_hi)
		_fill_round_rect(img, x0 + 1, hy - 3, 2, 7, cup.lightened(0.14))
		# ONE white-hot pixel per cup. The LED used to be a three-pixel vertical
		# gradient, which at 2x is a lamp, not an indicator.
		var lx0: int = x0 if k < 0 else x0 + 3
		_px(img, lx0, hy, WHITE_HOT)
		_px(img, lx0, hy + 1, glow.darkened(0.35))

## One emissive accent each, per the bible.
func _vc_accessory(img: Image, cx: int, ty: int, hy: int, head_dx: int,
		accessory: String, up: bool, glow: Color, skin_hi: Color) -> void:
	var cxx := cx + head_dx
	if accessory == "tie" and not up:
		# A tie in three desaturated stops. It used to be pillarbox red with an
		# accent lamp floating beside it — two saturated hues on one shirt.
		for tyy in range(ty + 3, ty + 15):
			var tw: int = 2 if tyy < ty + 6 else 3
			_fill_rect(img, cx - tw / 2, tyy, tw, 1, Color(0.30, 0.18, 0.20))
		_px(img, cx, ty + 4, Color(0.42, 0.28, 0.30))
	elif accessory == "glasses" and not up:
		_fill_rect(img, cxx - 6, hy - 1, 5, 4, Color(0.10, 0.11, 0.14))
		_fill_rect(img, cxx + 2, hy - 1, 5, 4, Color(0.10, 0.11, 0.14))
		_fill_rect(img, cxx - 5, hy, 3, 2, Color(0.16, 0.20, 0.26))
		_fill_rect(img, cxx + 3, hy, 3, 2, Color(0.16, 0.20, 0.26))
		_fill_rect(img, cxx - 2, hy, 4, 1, Color(0.10, 0.11, 0.14))
		_px(img, cxx - 5, hy, glow)          # THE accent detail: one lens glint
	elif accessory == "shades" and not up:
		# sunglasses at 3am. Nobody has ever asked why.
		_fill_rect(img, cxx - 8, hy - 1, 17, 4, Color(0.06, 0.06, 0.09))
		_fill_rect(img, cxx - 8, hy - 1, 17, 1, Color(0.20, 0.21, 0.27))
		_fill_rect(img, cxx - 1, hy, 3, 2, Color(0.12, 0.12, 0.16))
		_px(img, cxx - 6, hy, glow)          # THE accent detail
	elif accessory == "hardhat":
		# The hat is the accent (it is the foreman's whole silhouette read) and
		# the headlamp is the one genuine light source on him.
		_fill_ellipse(img, cxx, hy - 5, 9, 5, glow.darkened(0.18))
		_fill_rect(img, cxx - 11, hy - 4, 22, 2, glow.darkened(0.18))
		_fill_rect(img, cxx - 11, hy - 4, 22, 1, glow)
		_fill_rect(img, cxx - 11, hy - 2, 22, 1, glow.darkened(0.55))
		_px(img, cxx, hy - 6, WHITE_HOT)
	elif accessory == "circuit" and not up:
		# one short trace and one lit node, instead of three traces and a lamp
		_draw_line_img(img, cx + 2, ty + 8, cx + 7, ty + 8, glow.darkened(0.55))
		_draw_line_img(img, cx + 7, ty + 8, cx + 7, ty + 5, glow.darkened(0.55))
		_px(img, cx + 7, ty + 4, glow)
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
			_px(img, cx + 12, ty + 15, glow)  # a notification he will not answer
			_fill_rect(img, cx + 3 + head_dx, hy + 3, 4, 1, skin_hi.lerp(glow, 0.35))
		"laptop":
			_fill_rect(img, cx - 12, ty + 7, 24, 14, Color(0.06, 0.08, 0.12))
			_fill_rect(img, cx - 12, ty + 7, 24, 1, Color(0.20, 0.25, 0.34))
			_fill_rect(img, cx - 12, ty + 7, 1, 14, Color(0.20, 0.25, 0.34))
			_fill_rect(img, cx - 11, ty + 8, 22, 12, Color(0.04, 0.06, 0.09))
			# code that is definitely fine
			# One hue on the screen, two values. The second (violet) line colour
			# was a whole extra hue living inside a 22px prop.
			for lrow in 5:
				var ly := ty + 9 + lrow * 2
				var lw := 4 + ((lrow * 7 + frame_idx * 3) % 12)
				var lcol := glow.darkened(0.28) if lrow % 2 == 0 else glow.darkened(0.58)
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
			for i in 4:
				_px(img, cx + 14 + (i % 2), ty + 2 - i * 2, Color(0.85, 0.90, 1.0, 0.45 - float(i) * 0.09))
		"celebrate":
			# Confetti in ONE hue (gold, the currency colour), seven bits instead
			# of eleven, and no glow cores. Four hues of confetti plus two lamps
			# was more colour in one pose than the rest of the frame put together.
			for i in 7:
				var px := cx - 14 + ((i * 47) % 29)
				var py := hy - 14 + ((i * 31) % 9)
				_px(img, px, py, GOLD if i % 2 == 0 else GOLD.darkened(0.30))
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
			# the release: accent ring, ONE white-hot core, three shard rays
			_fill_circle(img, cx + 19, ty + 6, 4, Color(glow.r, glow.g, glow.b, 0.40))
			_fill_circle(img, cx + 19, ty + 6, 2, glow)
			_px(img, cx + 19, ty + 6, WHITE_HOT)
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
		# a bag rated for a laptop and the confidence of a first sprint.
		# Desaturated, with one accent pixel on the buckle.
		_fill_round_rect(img, cx - 15, ty + 2, 11, 16, Color(0.24, 0.22, 0.28))
		_fill_rect(img, cx - 15, ty + 3, 1, 14, Color(0.34, 0.32, 0.39))
		_fill_rect(img, cx - 14, ty + 7, 9, 1, Color(0.15, 0.14, 0.18))
		_fill_round_rect(img, cx - 14, ty + 9, 7, 5, Color(0.20, 0.18, 0.23))
		_px(img, cx - 11, ty + 11, glow)
		_fill_round_rect(img, cx + 5, ty + 2, 10, 15, Color(0.21, 0.19, 0.25))
	elif back == "cape":
		_fill_ellipse(img, cx, ty + 9, 14, 11, sh.darkened(0.30))
		_fill_ellipse(img, cx, ty + 8, 13, 10, sh)

## The one stupid object each archetype refuses to put down. LAW 7: every prop
## is desaturated toward the body, and the ONE saturated pixel it is allowed is
## the character's region accent. The props nobody carries any more (pager,
## antenna, buzzword bubbles) are gone rather than kept as dead branches.
func _vc_npc_prop(img: Image, cx: int, ty: int, hy: int, head_dx: int, prop: String,
		glow: Color, skin: Color, skin_sh: Color) -> void:
	match prop:
		"noodles":
			# instant noodles: the load-bearing dependency of open source
			_fill_round_rect(img, cx + 8, ty + 7, 9, 7, Color(0.68, 0.66, 0.62))
			_fill_rect(img, cx + 8, ty + 7, 9, 1, Color(0.79, 0.77, 0.73))
			_fill_rect(img, cx + 8, ty + 10, 9, 1, Color(0.44, 0.40, 0.38))
			_fill_rect(img, cx + 9, ty + 6, 7, 1, Color(0.60, 0.55, 0.44))
			_draw_line_img(img, cx + 11, ty + 6, cx + 15, ty + 1, Color(0.52, 0.46, 0.36))
			_draw_line_img(img, cx + 12, ty + 6, cx + 17, ty + 2, Color(0.52, 0.46, 0.36))
		"mug":
			# a mug sized for someone who has stopped counting
			_fill_round_rect(img, cx + 8, ty + 5, 10, 12, Color(0.22, 0.23, 0.28))
			_fill_rect(img, cx + 8, ty + 5, 10, 2, Color(0.33, 0.35, 0.41))
			_fill_rect(img, cx + 9, ty + 7, 8, 1, Color(0.20, 0.14, 0.10))
			_fill_rect(img, cx + 18, ty + 8, 2, 5, Color(0.27, 0.29, 0.34))
			_fill_rect(img, cx + 10, ty + 10, 6, 4, Color(0.15, 0.16, 0.20))
			for i in 3:
				_px(img, cx + 12 + (i % 2), ty + 3 - i * 2, Color(0.78, 0.80, 0.86, 0.30 - float(i) * 0.09))
		"tablet":
			# a stone tablet. The answer is correct. The answer is from 2011.
			_fill_rect(img, cx + 6, ty + 3, 13, 17, Color(0.38, 0.37, 0.33))
			_fill_rect(img, cx + 6, ty + 3, 13, 1, Color(0.50, 0.49, 0.44))
			_fill_rect(img, cx + 6, ty + 3, 1, 17, Color(0.50, 0.49, 0.44))
			_fill_rect(img, cx + 18, ty + 4, 1, 16, Color(0.24, 0.23, 0.21))
			for i in 4:
				_fill_rect(img, cx + 8, ty + 7 + i * 3, 4 + (i * 3) % 7, 1, Color(0.28, 0.27, 0.24))
			_px(img, cx + 13, ty + 13, glow)   # THE accent detail: one lit glyph
		"keys":
			# a coat lining of API keys, each one limited-time
			_fill_rect(img, cx - 11, ty + 5, 22, 12, Color(0.10, 0.09, 0.12))
			_fill_rect(img, cx - 11, ty + 5, 22, 1, Color(0.22, 0.20, 0.26))
			for i in 4:
				var kx := cx - 10 + i * 6
				_fill_rect(img, kx, ty + 7, 4, 8, Color(0.14, 0.14, 0.18))
				_fill_rect(img, kx, ty + 7, 4, 1, Color(0.24, 0.24, 0.30))
				_fill_rect(img, kx + 1, ty + 9, 2, 4, Color(0.20, 0.20, 0.25))
			_px(img, cx - 9, ty + 10, glow)    # exactly one key is still valid
		"lanyard":
			# the badge that opens every door and explains nothing
			_draw_line_img(img, cx - 3, ty + 1, cx + 5, ty + 9, Color(0.18, 0.19, 0.22))
			_draw_line_img(img, cx + 5, ty + 1, cx + 7, ty + 9, Color(0.18, 0.19, 0.22))
			_fill_rect(img, cx + 3, ty + 9, 8, 7, Color(0.70, 0.71, 0.74))
			_fill_rect(img, cx + 3, ty + 9, 8, 2, glow.darkened(0.30))
			_fill_rect(img, cx + 4, ty + 12, 6, 1, Color(0.35, 0.38, 0.44))
			_fill_rect(img, cx + 4, ty + 14, 4, 1, Color(0.35, 0.38, 0.44))
		"cloud_balloon":
			# elastic, on-demand, and tethered to nothing in particular
			_draw_line_img(img, cx + 11, ty + 8, cx + 15, hy - 6, Color(0.44, 0.46, 0.50))
			_fill_circle(img, cx + 13, hy - 11, 4, Color(0.40, 0.43, 0.48))
			_fill_circle(img, cx + 18, hy - 10, 5, Color(0.40, 0.43, 0.48))
			_fill_circle(img, cx + 13, hy - 12, 4, Color(0.60, 0.63, 0.68))
			_fill_circle(img, cx + 18, hy - 11, 4, Color(0.55, 0.58, 0.63))
			_fill_rect(img, cx + 9, hy - 10, 13, 3, Color(0.57, 0.60, 0.65))
			_fill_rect(img, cx + 9, hy - 8, 13, 1, Color(0.35, 0.38, 0.43))
		"thermal_gun":
			_fill_rect(img, cx + 8, ty + 8, 9, 3, Color(0.36, 0.33, 0.29))
			_fill_rect(img, cx + 8, ty + 8, 9, 1, Color(0.48, 0.44, 0.39))
			_fill_rect(img, cx + 10, ty + 11, 3, 5, Color(0.26, 0.24, 0.21))
			_px(img, cx + 17, ty + 9, glow)    # THE accent detail: the muzzle
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

## ===================== LAW 6 — FLOORS ARE READABLE GROUND =====================
##
## Pass 2 measured every non-Localhost floor at 32-41/255 and called the world
## "nine rooms of black void". The cause was one wrong assumption repeated ten
## times: LAW 2's BASE colour (#0A120C and its siblings) is the WALL-SHADOW and
## out-of-bounds tone, and it had been used as the floor tone. A floor is a
## separate, mid-value MATERIAL. Localhost's planks are the reference, and they
## read as ground because they have STRUCTURE and three visible tones — not
## because they are bright.
##
## So these numbers are the law, and they are MEASURED on the way out rather
## than trusted: every floor PNG this file writes goes through
## _save_floor_tile, which push_error()s if the finished tile's mean luminance
## leaves the window.
##
##   base tone 64-84 · seam/joint 36-48 · highlight 96-116
##   A/B variant <= 6% apart · per-tile jitter <= 3% · structure mandatory at 32px
##
## The second half of the finding was that ten regions shipped FOUR floors:
## _generate_floor_structures aliased every region onto one of four families,
## so api_bazaar stood on Localhost's floorboards and dependency, corporate and
## production all shared one deck — which is most of "one shared square-tile
## floor tinted per region". Every region now draws its OWN material, and the
## four family filenames survive as copies of a representative region so no
## exists()-guarded lookup on the composition side can miss.
## LAW 6's three windows, and they are windows rather than one ratio on
## purpose: a floor at the bottom of the base window needs a hi/base ratio of
## 1.45 to reach 96, and one at the top needs 1.43 or less to stay under 116.
## So each region's tones are derived from ITS OWN base tone and then clamped
## into the windows, which is also how the table below stops being decoration
## and starts being the specification.
const FLOOR_BASE_MIN := 69.0
const FLOOR_BASE_MAX := 80.0
const FLOOR_SEAM_RATIO := 0.58
const FLOOR_HI_RATIO := 1.42
const FLOOR_SEAM_MIN := 36.0
const FLOOR_SEAM_MAX := 48.0
const FLOOR_HI_MIN := 99.0
const FLOOR_HI_MAX := 116.0
## The B variant is the same material 2% down. It is small because
## region_builder already lifts its alt cell by 6%: the two multiply out to a
## ~4% A/B step on screen, inside LAW 6's 6% ceiling, and a B tile authored any
## darker would cancel the builder's step and flatten the floor completely.
const FLOOR_AB_STEP := 0.98
const FLOOR_MEAN_MIN := 64.0
const FLOOR_MEAN_MAX := 84.0
## A floor is not one of LAW 3's five bright things and not one of LAW 2's three
## hues, so every material hue is pulled a third of the way to its own grey
## before anything is drawn. What separates two regions underfoot is the
## MATERIAL, not the tint — that was the whole mistake being corrected here.
const FLOOR_DESAT := 0.30
## LAW 6's jitter ceiling. Grain, aggregate, carpet pile and brushed metal all
## live inside +/-3% of the base tone and nothing on a floor exceeds it.
const FLOOR_JITTER := 0.03

## region key -> [LAW 6 base tone, LAW 6 material]. Ten regions, ten materials,
## and the material is the thing a player actually reads.
const FLOOR_REGIONS := {
	"localhost": ["#5A3F2A", "planks"],
	"dependency": ["#3E4A36", "sludge"],
	"stackoverflow": ["#5C503C", "sandstone"],
	"api_bazaar": ["#4C3244", "weave"],
	"cloud": ["#404854", "grating"],
	"opensource": ["#404C32", "loam"],
	"corporate": ["#383E4E", "carpet"],
	"gpu": ["#4E3C34", "scorched"],
	"production": ["#46464A", "concrete"],
	"vault": ["#605028", "gold"],
}

## The three tones of LAW 6 plus the two half-steps every material needs (a
## shaded flank, a lit crown), and a nine-stop grain ramp that cannot leave the
## 3% jitter ceiling because it is built from it.
class FloorTones extends RefCounted:
	var base: Color
	var seam: Color
	var hi: Color
	var mid: Color
	var lip: Color
	var grain: Array[Color] = []

	## k in [-1, 1] -> the base tone +/- FLOOR_JITTER.
	func g(k: float) -> Color:
		return grain[clampi(int(round((k + 1.0) * 4.0)), 0, 8)]

## Rec.709 luminance on the 0-255 scale LAW 6 is written in.
func _luma255(c: Color) -> float:
	return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) * 255.0

## The same colour at a given luminance. Hue and chroma ratio survive; only
## value moves — which is how a whole material can be pinned to a number.
func _at_luma(c: Color, target: float) -> Color:
	var l := _luma255(c)
	if l <= 0.01:
		var g := clampf(target / 255.0, 0.0, 1.0)
		return Color(g, g, g, 1.0)
	var k := target / l
	return Color(minf(c.r * k, 1.0), minf(c.g * k, 1.0), minf(c.b * k, 1.0), 1.0)

func _floor_tones(hex: String, alt: bool) -> FloorTones:
	var raw := Color(hex)
	var grey := _luma255(raw) / 255.0
	var c := Color(lerpf(raw.r, grey, FLOOR_DESAT), lerpf(raw.g, grey, FLOOR_DESAT),
		lerpf(raw.b, grey, FLOOR_DESAT), 1.0)
	# The LAW 6 table's own hex IS the base tone. Three of the ten sit under the
	# window (api_bazaar at 57, corporate at 62, gpu at 63) and are lifted to its
	# floor; the rest keep their natural value, which is why sandstone and gold
	# read as lighter ground than a rug or a carpet tile, as they should.
	var b := clampf(_luma255(raw), FLOOR_BASE_MIN, FLOOR_BASE_MAX)
	if alt:
		b *= FLOOR_AB_STEP
	var sm := clampf(b * FLOOR_SEAM_RATIO, FLOOR_SEAM_MIN, FLOOR_SEAM_MAX)
	var hl := clampf(b * FLOOR_HI_RATIO, FLOOR_HI_MIN, FLOOR_HI_MAX)
	var t := FloorTones.new()
	t.base = _at_luma(c, b)
	t.seam = _at_luma(c, sm)
	t.hi = _at_luma(c, hl)
	t.mid = _at_luma(c, (b + hl) * 0.5)
	t.lip = _at_luma(c, (b + sm) * 0.5)
	for i in 9:
		t.grain.append(_at_luma(c, b * (1.0 + FLOOR_JITTER * ((float(i) / 4.0) - 1.0))))
	return t

## Per-region floor tiles (LAW 6). Ten materials, each one recognisable at 32px
## and none of them a tinted copy of another: plank grain, sludge slabs,
## cracked sandstone, flagstone under rug runners, a steel grille, loam, carpet
## pile, riveted plate, poured concrete and laid gold. Each pair is measured
## twice on the way out — for luminance, and for quiet.
func _generate_tileset() -> void:
	for rname: String in FLOOR_REGIONS:
		var a := _make_floor_tile(rname, false)
		var b := _make_floor_tile(rname, true)
		_save_floor_tile(a, "tile_%s.png" % rname)
		_save_floor_tile(b, "tile_%s_b.png" % rname)
		_report_floor_quiet(rname, a, b)

## One seamless 64x64 floor texture. `alt` is the B variant: the same material
## two percent down, with its one small inset detail.
func _make_floor_tile(rname: String, alt: bool) -> Image:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var spec: Array = FLOOR_REGIONS.get(rname, ["#46464A", "concrete"])
	_floor_material(img, String(spec[1]), _floor_tones(String(spec[0]), alt), alt)
	return img

## Uniform value scale over a finished tile. Relative contrast is preserved
## exactly; only where the material sits on the value axis moves.
func _dim_tile(img: Image, k: float) -> void:
	if is_equal_approx(k, 1.0):
		return
	for x in img.get_width():
		for y in img.get_height():
			var c := img.get_pixel(x, y)
			_px(img, x, y, Color(minf(c.r * k, 1.0), minf(c.g * k, 1.0), minf(c.b * k, 1.0), c.a))

func _floor_mean_luma(img: Image) -> float:
	var total := 0.0
	for x in img.get_width():
		for y in img.get_height():
			total += _luma255(img.get_pixel(x, y))
	return total / float(img.get_width() * img.get_height())

## The LAW 6 gate. Every floor this file writes goes through here, so a
## material that drifts out of the window fails loudly at generation time
## instead of shipping as another black room.
func _save_floor_tile(img: Image, filename: String) -> void:
	var m := _floor_mean_luma(img)
	if m < FLOOR_MEAN_MIN or m > FLOOR_MEAN_MAX:
		push_error("LAW 6 floor luminance: %s mean %.1f is outside %.0f-%.0f" % [
			filename, m, FLOOR_MEAN_MIN, FLOOR_MEAN_MAX])
	_save_image(img, filename)

## ---- The second gate: QUIET. -------------------------------------------
## The luminance gate above answers "is this floor visible". It cannot answer
## "is this floor calm", and round 12 found a floor that passed the first and
## failed the second badly: the API Bazaar weave was in the window at every
## pixel and still turned the frame into static, because it changed tone every
## two pixels across all 4096 of them. Only 16.7% of that frame was quiet
## against 67-77% in every other region.
##
## So quiet becomes a number too. Lay the A/B pair down as a 4x4 checkerboard
## — the worst case, since the builder's cell hash only ever asks for the B
## variant 38% of the time — cut the render into 32px blocks, and count the
## blocks whose internal luminance range is at most FLOOR_QUIET_RANGE. A block
## that spans nothing but stone is quiet; a block a rug runner crosses is not,
## and that is the point. The ratio is how much of the ground a stall can
## stand on without competing with it.
const FLOOR_QUIET_BLOCK := 32
const FLOOR_QUIET_RANGE := 12.0
const FLOOR_QUIET_MIN := 0.65
## Only the material this window was written for is GATED. The other nine
## floors are the critic's keep list — sandstone's mortar joints and the
## grating's load bars are meant to be read, and measuring them as "loud" is
## correct and irrelevant. They are printed as data and never failed.
const FLOOR_QUIET_GATED := "api_bazaar"

## Rec.709 luma of every pixel, once, so the block loop below never touches
## get_pixel again (it would otherwise read 65536 pixels per region).
func _tile_luma(img: Image) -> PackedFloat32Array:
	var w := img.get_width()
	var h := img.get_height()
	var out := PackedFloat32Array()
	out.resize(w * h)
	for y in h:
		for x in w:
			out[y * w + x] = _luma255(img.get_pixel(x, y))
	return out

@warning_ignore("integer_division")
func _floor_quiet_fraction(a: Image, b: Image) -> float:
	var tw := a.get_width()
	var th := a.get_height()
	var cols := (tw * 4) / FLOOR_QUIET_BLOCK
	var rows := (th * 4) / FLOOR_QUIET_BLOCK
	if cols <= 0 or rows <= 0:
		return 1.0
	var la := _tile_luma(a)
	var lb := _tile_luma(b)
	var quiet := 0
	for by in rows:
		for bx in cols:
			var lo := 1024.0
			var hi := -1024.0
			for iy in FLOOR_QUIET_BLOCK:
				var gy := by * FLOOR_QUIET_BLOCK + iy
				for ix in FLOOR_QUIET_BLOCK:
					var gx := bx * FLOOR_QUIET_BLOCK + ix
					var src := lb if (((gx / tw) + (gy / th)) & 1) == 1 else la
					var l := src[(gy % th) * tw + (gx % tw)]
					lo = minf(lo, l)
					hi = maxf(hi, l)
			if hi - lo <= FLOOR_QUIET_RANGE:
				quiet += 1
	return float(quiet) / float(rows * cols)

func _report_floor_quiet(rname: String, a: Image, b: Image) -> void:
	var q := _floor_quiet_fraction(a, b)
	print("LAW 6 quiet: %-14s %3d%% of 32px blocks within %d/255" % [
		rname, int(round(q * 100.0)), int(FLOOR_QUIET_RANGE)])
	if rname == FLOOR_QUIET_GATED and q < FLOOR_QUIET_MIN:
		push_error("LAW 6 quiet: %s floor at %.2f is under the %.2f minimum" % [
			rname, q, FLOOR_QUIET_MIN])

## Every region material, in one place. Light is from the top-left everywhere,
## so a seam is followed by a lit lip and never the other way round, and `alt`
## adds the single inset detail and nothing else — except the bazaar, whose
## alt carries the rug runner that the field no longer wears all over.
func _floor_material(img: Image, mat: String, t: FloorTones, alt: bool) -> void:
	match mat:
		"planks":
			_floor_planks(img, t, alt)
		"sludge":
			_floor_sludge(img, t, alt)
		"sandstone", "ruin":
			_floor_sandstone(img, t, alt)
		"weave", "rug":
			_floor_weave(img, t, alt)
		"grating":
			_floor_grating(img, t, alt)
		"loam", "forest":
			_floor_loam(img, t, alt)
		"carpet":
			_floor_carpet(img, t, alt)
		"scorched":
			_floor_scorched(img, t, alt)
		"gold":
			_floor_gold(img, t, alt)
		_:
			_floor_concrete(img, t, alt)

## LOCALHOST — wood planks, and the reference every other material is measured
## against. 16px board run, recessed seam, lit board edge, longitudinal grain
## and three staggered butt joints so the boards have a direction.
func _floor_planks(img: Image, t: FloorTones, alt: bool) -> void:
	for y in 64:
		var ry := y & 15
		var row := y >> 4
		for x in 64:
			var c: Color = t.base
			if ry == 0:
				c = t.seam
			elif ry == 1:
				c = t.hi
			else:
				var s := ((x * 7 + row * 23) >> 3) & 3
				var k := 0.0
				if (ry + s) % 7 == 3:
					k = 1.0
				elif (ry * 3 + s) % 11 == 5:
					k = -1.0
				c = t.g(k)
			_px(img, x, y, c)
	for j: Vector2i in [Vector2i(41, 0), Vector2i(12, 2), Vector2i(55, 3)]:
		for jy in range(1, 16):
			_px(img, j.x, j.y * 16 + jy, t.seam)
			_px(img, j.x + 1, j.y * 16 + jy, t.hi)
	if alt:
		_floor_blot(img, 44, 39, 3, t.lip)
		_floor_blot(img, 44, 39, 1, t.seam)

## DEPENDENCY DISTRICT — node_modules sludge slabs. 32px slabs with a 1px
## joint and a lit lip; inside them the ooze that got poured over this floor
## and set, as a wide soft swell inside the 3% jitter, plus four low spots
## where it pooled deepest. No cell-sized radial basin: that tiled into polka
## dots, which is what the round-6 frame was actually showing.
func _floor_sludge(img: Image, t: FloorTones, alt: bool) -> void:
	for y in 64:
		for x in 64:
			var sx := x & 31
			var sy := y & 31
			var c: Color = t.base
			if sx == 0 or sy == 0:
				c = t.seam
			elif sx == 1 or sy == 1:
				c = t.hi
			else:
				var n := sin(float(sx) * PI / 16.0 + 0.6) * sin(float(sy) * PI / 16.0 + 1.9)
				n += 0.45 * sin(float(sx) * PI / 5.0) * sin(float(sy) * PI / 6.0 + 2.2)
				c = t.g(clampf(n, -1.0, 1.0))
			_px(img, x, y, c)
	for p: Vector2i in [Vector2i(11, 21), Vector2i(26, 8), Vector2i(46, 41), Vector2i(58, 55)]:
		_floor_blot(img, p.x, p.y, 3, t.lip)
		_px(img, p.x - 1, p.y - 1, t.hi)
	if alt:
		_floor_square(img, 41, 25, 5, t.hi, t.lip)

## The joint layout of the ruins. Two courses of flagstones, deliberately
## different widths, and a wobble table that walks every joint a pixel either
## side so no line in this floor is straight — which is the whole difference
## between "cracked sandstone" and "a grid".
const RUIN_JOINTS_A: Array[int] = [13, 41]
const RUIN_JOINTS_B: Array[int] = [6, 30, 52]
const RUIN_WOBBLE: Array[int] = [0, 0, 1, 1, 1, 0, 0, -1, -1, 0, 1, 1, 0, 0, -1, -1]

## STACKOVERFLOW RUINS — cracked sandstone. Sand grain over the whole field,
## irregular flags, mortar joints with a lit near lip, and two hairline cracks
## running across the stones rather than along the joints.
func _floor_sandstone(img: Image, t: FloorTones, alt: bool) -> void:
	for y in 64:
		for x in 64:
			_px(img, x, y, t.g(float((x * 5 + y * 3) % 7 - 3) / 6.0))
	for band: int in [0, 32]:
		var xs: Array[int] = RUIN_JOINTS_A if band == 0 else RUIN_JOINTS_B
		for x in 64:
			var w: int = RUIN_WOBBLE[((x >> 2) + band) % 16]
			_px(img, x, (band + w + 64) % 64, t.seam)
			_px(img, x, (band + w + 65) % 64, t.hi)
		for jx: int in xs:
			for dy in range(2, 32):
				var w2: int = RUIN_WOBBLE[((dy >> 2) + jx) % 16]
				_px(img, (jx + w2 + 64) % 64, band + dy, t.seam)
				_px(img, (jx + w2 + 65) % 64, band + dy, t.hi)
	for p: Vector2i in [Vector2i(20, 12), Vector2i(21, 13), Vector2i(22, 14),
			Vector2i(22, 15), Vector2i(23, 16), Vector2i(24, 17),
			Vector2i(48, 40), Vector2i(49, 41), Vector2i(49, 42),
			Vector2i(50, 43), Vector2i(51, 44)]:
		_px(img, p.x, p.y, t.lip)
	if alt:
		for i in 9:
			_px(img, 36 + i, 20 + (i >> 1), t.seam)

## API BAZAAR — flagstone, with the weave kept as rug runners.
##
## ROUND 12, finding #4: the basket weave that used to live here alternated
## t.hi and t.lip every two pixels across all 4096, and three hundred of those
## tiles is not a material — it is visual static. LAW 6 asks for STRUCTURE, and
## structure is not texture: a floor earns it with a few long readable lines,
## not with a tone change every other pixel. The market's stalls, tokens and
## NPCs were competing with the ground they stand on.
##
## The field is now flagstone. Four 32px stones per tile in a running bond, two
## stone tones 5.6% apart, one 1px joint and the 1px lit lip that follows it.
## Every pixel of the field lives inside a single WEAVE_QUIET_RANGE window, so
## a 32px block that lands anywhere on the stone measures quiet.
##
## The weave is not deleted, it is placed: it survives at FULL material
## contrast (LAW 6's seam AND its highlight both appear in it, which the field
## no longer spends) as one 8px-pitch runner band along the bottom border of
## the B tile only. The builder asks for B on 38% of cells, so the market keeps
## rugs underfoot on about a third of its ground and the rest is quiet stone.
## _report_floor_quiet measures the result at 75%.
##
## Values are fractions of the LAW 6 base tone. The joint is not a ratio but a
## subtraction: it sits exactly WEAVE_QUIET_RANGE below the brightest pixel in
## the field, which spends the whole quiet budget on the one line that has to
## read and leaves the 12/255 gate its margin for 8-bit rounding.
const WEAVE_LIP := 1.060
const WEAVE_STONE_HI := 1.030
const WEAVE_STONE_LO := 0.975
const WEAVE_GRAIN := 0.015
const WEAVE_QUIET_RANGE := 10.5
## The runner: a lit leading edge, twelve rows of 4px basket weave (so the
## motif's pitch is 8px, four times the static it replaces), and the contact
## shadow where the far edge lies back down on the stone. It stays wholly
## inside the tile's lower half, which is what holds the quiet fraction at
## 0.75: the two upper 32px blocks of a B tile never see it.
const WEAVE_BAND_Y := 50

func _floor_weave(img: Image, t: FloorTones, alt: bool) -> void:
	var b := _luma255(t.base)
	# Named apart from t.lip / t.seam on purpose: these two are the FIELD's
	# quiet pair, and the runner below still wants the material's loud one.
	var stone_lip := _at_luma(t.base, b * WEAVE_LIP)
	var stone_joint := _at_luma(t.base, maxf(b * WEAVE_LIP - WEAVE_QUIET_RANGE, 1.0))
	var stone: Array[Color] = [
		_at_luma(t.base, b * WEAVE_STONE_HI),
		_at_luma(t.base, b * WEAVE_STONE_LO),
	]
	var grain_lo: Array[Color] = []
	var grain_hi: Array[Color] = []
	for s: Color in stone:
		var sl := _luma255(s)
		grain_lo.append(_at_luma(s, sl * (1.0 - WEAVE_GRAIN)))
		grain_hi.append(_at_luma(s, sl * (1.0 + WEAVE_GRAIN)))
	for y in 64:
		# Running bond: the lower course steps half a stone, so no vertical
		# joint ever runs the full height of the floor.
		var course := y >> 5
		var sy := y & 31
		for x in 64:
			var ox := (x + course * 16) & 63
			var sx := ox & 31
			var i := ((ox >> 5) + course) & 1
			var c: Color = stone[i]
			if sx == 0 or sy == 0:
				c = stone_joint
			elif sx == 1 or sy == 1:
				c = stone_lip
			else:
				# Cut-stone grain: 4px blocks at +/-1.5%, well inside LAW 6's
				# 3% jitter and far too small to read as a second pattern.
				var g := ((sx * 3 + sy * 5) >> 2) % 5
				if g == 0:
					c = grain_lo[i]
				elif g == 3:
					c = grain_hi[i]
			_px(img, x, y, c)
	if not alt:
		return
	for x in 64:
		_px(img, x, WEAVE_BAND_Y, t.hi)
		_px(img, x, 63, t.seam)
	for y in range(WEAVE_BAND_Y + 1, 63):
		var r := y - WEAVE_BAND_Y - 1
		for x in 64:
			var over := (((x >> 2) + (r >> 2)) & 1) == 0
			var c: Color = t.lip
			if over:
				c = t.hi if (r & 3) == 0 else t.mid
			_px(img, x, y, c)

## CLOUD DISTRICT — steel grating. A 16px lattice of load bars lit on their
## top-left, a pan recessed between them, and one square drain hole per cell
## with a lit near lip: the dotted grille of LAW 6. The old 8px rib run was a
## 16-screen-pixel stripe field over the whole floor — corduroy, not ground.
func _floor_grating(img: Image, t: FloorTones, alt: bool) -> void:
	for y in 64:
		for x in 64:
			var bx := x & 15
			var by := y & 15
			var c: Color = t.g(-1.0)
			if bx < 3 or by < 3:
				c = t.hi if (bx == 0 or by == 0) else t.g(0.7)
			_px(img, x, y, c)
	for gy in range(0, 64, 16):
		for gx in range(0, 64, 16):
			for oy in range(6, 12):
				for ox in range(6, 12):
					_px(img, gx + ox, gy + oy, t.seam)
			for i in range(5, 12):
				_px(img, gx + i, gy + 5, t.lip)
				_px(img, gx + 5, gy + i, t.lip)
	if alt:
		for i in 4:
			_px(img, 44 + i, 27, t.hi)
			_px(img, 44 + i, 28, t.lip)

## OPEN SOURCE WILDLANDS — loam and moss, and the point of it is that soil has
## no module: no grid, no bevel, no seam. The structure is CLODDING, built from
## a wrapped three-octave field cut where its slope turns over — a hollow
## between clods takes the seam tone, a lit crown takes the highlight, and the
## field itself never leaves the 3% jitter. Leaf litter on top, seven specks.
func _floor_loam(img: Image, t: FloorTones, alt: bool) -> void:
	var fld := PackedFloat32Array()
	fld.resize(4096)
	for y in 64:
		for x in 64:
			var u := TAU * float(x) / 64.0
			var v := TAU * float(y) / 64.0
			var a := sin(2.0 * u + 1.3) + sin(3.0 * v + 0.2)
			var b := sin(5.0 * u + 2.1) + sin(4.0 * v + 0.7)
			var d := sin(7.0 * u + 0.4) * sin(6.0 * v + 2.4)
			fld[y * 64 + x] = 0.7 * a + 0.45 * b + 0.5 * d
	for y in 64:
		for x in 64:
			var f0 := fld[y * 64 + x]
			var e := fld[y * 64 + ((x + 1) & 63)] - f0 + fld[((y + 1) & 63) * 64 + x] - f0
			var c: Color = t.g(clampf(f0 * 0.8, -1.0, 1.0))
			if e > 0.62:
				c = t.seam
			elif e < -0.66:
				c = t.hi
			_px(img, x, y, c)
	for sp: Vector2i in [Vector2i(9, 12), Vector2i(37, 6), Vector2i(22, 41),
			Vector2i(53, 30), Vector2i(44, 55), Vector2i(17, 58), Vector2i(60, 18)]:
		_px(img, sp.x, sp.y, t.hi)
		_px(img, (sp.x + 1) % 64, sp.y, t.mid)
	for st: Vector2i in [Vector2i(31, 20), Vector2i(12, 50), Vector2i(49, 9)]:
		_px(img, st.x, st.y, t.seam)
	if alt:
		for i in 4:
			_px(img, 24 + i, 30, t.seam)
		_px(img, 27, 31, t.seam)

## CORPORATE ENTERPRISE — contract carpet tile, quarter-turned, with the loop
## pile running with the turn. The whole material is a seam, a lit lip and a
## 3% checker; it is meant to be forgettable, and that is what makes the room
## on top of it readable.
func _floor_carpet(img: Image, t: FloorTones, alt: bool) -> void:
	for y in 64:
		for x in 64:
			var cx := x & 31
			var cy := y & 31
			var c: Color = t.base
			if cx == 0 or cy == 0:
				c = t.seam
			elif cx == 1 or cy == 1:
				c = t.hi
			else:
				var turned := (((x >> 5) + (y >> 5)) & 1) == 1
				var u: int = cx if turned else cy
				var w: int = cy if turned else cx
				c = t.g(1.0 if (((u >> 1) + (w >> 2)) & 1) == 0 else -1.0)
			_px(img, x, y, c)
	if alt:
		_floor_blot(img, 46, 46, 3, t.lip)

## GPU MINES — scorched deck plate. 32px plates, a hard seam, a lit near bevel,
## four rivet heads per plate and a brushed grain running with the roll. The B
## tile carries one burn where a rig cooked; r=7 put a 15px scorch in a 64px
## tile, which is a repeating dark spot once it is stamped across an aisle.
func _floor_scorched(img: Image, t: FloorTones, alt: bool) -> void:
	for y in 64:
		for x in 64:
			var px2 := x & 31
			var py2 := y & 31
			var c: Color = t.base
			if px2 == 0 or py2 == 0:
				c = t.seam
			elif px2 == 1 or py2 == 1:
				c = t.hi
			else:
				c = t.g(0.35 if ((x + y * 2) & 15) < 5 else -0.25)
			_px(img, x, y, c)
	for sy: int in [0, 32]:
		for sx: int in [0, 32]:
			for r: Vector2i in [Vector2i(4, 4), Vector2i(27, 4), Vector2i(4, 27), Vector2i(27, 27)]:
				_px(img, sx + r.x, sy + r.y, t.hi)
				_px(img, sx + r.x + 1, sy + r.y, t.mid)
				_px(img, sx + r.x, sy + r.y + 1, t.mid)
				_px(img, sx + r.x + 1, sy + r.y + 1, t.lip)
	if alt:
		_floor_blot(img, 21, 45, 4, t.lip)
		_floor_blot(img, 21, 45, 2, t.seam)

## TOKEN VAULT — laid gold plate. 32px plates, a 1px seam and lit lip, four
## rivet heads and one shallow engraved chevron per plate. The B tile used to
## inlay an accent line across its full width, so every second tile carried a
## stripe and the vault floor read as banded rather than as plate.
func _floor_gold(img: Image, t: FloorTones, alt: bool) -> void:
	for y in 64:
		for x in 64:
			var gx := x & 31
			var gy := y & 31
			var c: Color = t.base
			if gx == 0 or gy == 0:
				c = t.seam
			elif gx == 1 or gy == 1:
				c = t.hi
			else:
				c = t.g(0.8 if (gy & 15) == 8 else 0.0)
			_px(img, x, y, c)
	for sy: int in [0, 32]:
		for sx: int in [0, 32]:
			for r: Vector2i in [Vector2i(5, 5), Vector2i(26, 5), Vector2i(5, 26), Vector2i(26, 26)]:
				_px(img, sx + r.x, sy + r.y, t.hi)
				_px(img, sx + r.x + 1, sy + r.y + 1, t.lip)
			for i in 7:
				_px(img, sx + 12 + i, sy + 16 - absi(i - 3), t.lip)
	if alt:
		for i in 7:
			_px(img, 12 + i, 22 - absi(i - 3), t.seam)

## PRODUCTION — poured concrete with sawn expansion joints on a 32px grid. A
## 2px joint (that is what a saw cut looks like), a lit near lip and aggregate
## speckle inside the jitter ceiling. The B tile carries one patch repair.
func _floor_concrete(img: Image, t: FloorTones, alt: bool) -> void:
	for y in 64:
		for x in 64:
			var jx := x & 31
			var jy := y & 31
			var c: Color = t.base
			if jx <= 1 or jy <= 1:
				c = t.seam
			elif jx == 2 or jy == 2:
				c = t.hi
			else:
				var h: int = (((x * 73856093) ^ (y * 19349663)) >> 5) & 15
				var k := 0.0
				if h < 2:
					k = 1.0
				elif h > 13:
					k = -1.0
				elif h == 7:
					k = 0.35
				c = t.g(k)
			_px(img, x, y, c)
	if alt:
		for i in 8:
			_px(img, 38 + i, 38, t.lip)
			_px(img, 38, 38 + i, t.lip)
			_px(img, 45, 38 + i, t.lip)
			_px(img, 38 + i, 45, t.lip)

## One soft round mark, wrapped so it never straddles the tile seam. The whole
## vocabulary of "inset detail" is this and a rectangle.
func _floor_blot(img: Image, cx: int, cy: int, r: int, c: Color) -> void:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > r * r:
				continue
			_px(img, (cx + dx + 64) % 64, (cy + dy + 64) % 64, c)

## A small object sitting in the floor: lit top edge, body, shadowed foot.
func _floor_square(img: Image, x: int, y: int, size: int, hi: Color, sh: Color) -> void:
	for oy in size:
		for ox in size:
			var c: Color = sh
			if oy == 0:
				c = hi
			_px(img, (x + ox) % 64, (y + oy) % 64, c)

## THE ENEMY CAST — one drawing language, thirteen silhouettes (LAW 7).
##
## Round 6 deleted the thing that made every earlier round louder. An enemy used
## to be: its own saturated hue, plus a chroma boost, plus a value expansion,
## plus a near-white rim on every top-left edge, plus a TWO-RING emissive halo,
## plus (for bosses) a spiked aureole behind it. Six passes whose combined job
## was "make sure this is seen" — which is what a silhouette is for. The QA
## frames show the result: creatures that read as blue and red LAMPS on a dark
## floor, indistinguishable from the tokens, the portals and the signage, and
## eight hues in a frame that was allowed three.
##
## What replaces all of it:
##   1. every body is repainted into ONE desaturated four-stop ramp,
##   2. each type gets exactly ONE red tell (#FF4757) at its eyes or core,
##   3. a 1px outline and a contact shadow, which is what makes a dark shape
##      legible on a dark floor — the same treatment the player and the props get.
## The colour in this table is now only a VALUE hint for the body drawing; the
## repaint owns the final hue. Nothing here is saturated any more.
func _generate_enemies() -> void:
	var enemies := {
		"bug": Color(0.42, 0.36, 0.36),
		"null_reference": Color(0.38, 0.36, 0.42),
		"rate_limiter": Color(0.44, 0.42, 0.36),
		"scope_creep": Color(0.38, 0.42, 0.38),
		"dependency_demon": Color(0.42, 0.37, 0.40),
		"legacy_system": Color(0.44, 0.42, 0.38),
		"memory_leak": Color(0.36, 0.39, 0.44),
		"hallucination": Color(0.42, 0.38, 0.42),
		"merge_conflict": Color(0.44, 0.40, 0.36),
		"cloud_bill": Color(0.38, 0.42, 0.40),
		"enterprise_architect": Color(0.38, 0.40, 0.44),
		"legacy_monolith": Color(0.42, 0.40, 0.36),
		"infinite_context": Color(0.39, 0.37, 0.43),
	}
	# The five types region_builder can spawn with boss=true. They get a second,
	# larger-featured texture under an ADDITIVE filename; the base file is
	# untouched, so nothing breaks if no consumer ever asks for it.
	var boss_kinds: Array[String] = ["merge_conflict", "cloud_bill",
		"enterprise_architect", "legacy_monolith", "infinite_context"]
	for ename in enemies:
		var c: Color = enemies[ename]
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		_draw_enemy(img, str(ename), c)
		_finish_enemy(img, str(ename), false)
		_save_image(img, "enemy_%s.png" % ename)
		if boss_kinds.has(str(ename)):
			var bimg := Image.create(32, 32, false, Image.FORMAT_RGBA8)
			bimg.fill(Color(0, 0, 0, 0))
			_draw_boss(bimg, str(ename), c)
			_finish_enemy(bimg, str(ename), true)
			_save_image(bimg, "enemy_%s_boss.png" % ename)

## Where each creature's single red tell lives, as flat x,y pairs. A pair of
## eyes counts as one tell; three eyes count as one tell on the thing whose
## entire joke is having too many of them.
const ENEMY_TELLS := {
	"bug": [13, 5, 19, 5],
	"rate_limiter": [16, 4],
	"memory_leak": [12, 11, 20, 11],
	"merge_conflict": [11, 14, 21, 14],
	"scope_creep": [12, 15, 20, 15],
	"dependency_demon": [13, 14, 19, 14],
	"hallucination": [11, 12, 21, 12, 16, 19],
	"legacy_monolith": [16, 13],
	"infinite_context": [16, 16],
	"enterprise_architect": [13, 8, 19, 8],
	"null_reference": [16, 12],
	"legacy_system": [10, 27],
	"cloud_bill": [12, 10, 19, 10],
}
## Boss bodies are redrawn, so a few tells move with them.
const BOSS_TELLS := {
	"merge_conflict": [10, 15, 22, 15],
	"cloud_bill": [10, 7, 20, 7],
	"enterprise_architect": [13, 8, 20, 8],
	"legacy_monolith": [16, 13],
	"infinite_context": [16, 16],
}

## The whole finishing chain, and it is now three passes instead of seven.
## Order matters: repaint first (so the ramp owns every body pixel), then the
## tell (so nothing can repaint over it), then the outline, then the shadow into
## whatever is still empty — and last, the scrub that guarantees an enemy is a
## silhouette and not a rectangle.
func _finish_enemy(img: Image, kind: String, boss: bool) -> void:
	_enemy_repaint(img, boss)
	_enemy_tell(img, kind, boss)
	_underside_ao(img, 3, 0.30)
	_outline_silhouette(img, OUTLINE_ENEMY)
	_contact_shadow(img)
	_clear_offshape(img)

## Anything this faint is not a shadow, it is a film. Below it a pixel is
## cleared to fully transparent BLACK rather than left as near-black at 2/255.
const GHOST_ALPHA_FLOOR := 0.06

## CRITIQUE #10 — the ghost box. An enemy has to BE a silhouette: every pixel
## that is not the creature or its contact shadow must be alpha 0, RGB included,
## because a 32x32 frame carrying a faint dark film reads on a dark floor as a
## rectangle stamped under the creature. Two things produced one: the contact
## shadow's outermost ring, which trails off through alphas of 1-14/255 in a
## rectangle of iteration, and _draw_legacy_monolith, which filled the entire
## frame edge to edge with masonry (see its own note). This pass fixes the first
## and asserts the second: after it, the only non-transparent pixels in an enemy
## PNG are the body, its outline and the visible core of its shadow.
func _clear_offshape(img: Image) -> void:
	for x in img.get_width():
		for y in img.get_height():
			var p := img.get_pixel(x, y)
			if p.a <= 0.0 or p.a >= GHOST_ALPHA_FLOOR:
				continue
			_px(img, x, y, Color(0.0, 0.0, 0.0, 0.0))

## Repaint every opaque pixel into ENEMY_RAMP by luminance. This is a removal,
## not an effect: it throws away hue and keeps value order, which is the only
## channel that survives a coloured region ambient anyway. Thirteen palettes
## become one material, and the creatures separate on shape — which is what a
## reader actually uses. Bosses get a small lift so they sit a stop brighter
## than their minions without needing to be backlit.
##
## Round 7 changed two things here, both of them removals.
##
## The alpha gate was 0.5, so anything drawn TRANSLUCENT walked straight past the
## repaint: the Enterprise Architect's governance brackets and the Cloud Bill's
## raining decimals kept full saturation, which is most of the "enemies carry
## their own rainbow" finding. The gate is now "anything you can see".
##
## And a pixel that is ALREADY one of the four stops is left exactly alone, so a
## body may be authored directly in the final palette and survive this pass
## byte-for-byte. That is what lets the boss bodies below place their own value
## structure instead of having it re-quantised into one flat bright mass.
func _enemy_repaint(img: Image, boss: bool) -> void:
	var lift: float = 0.07 if boss else 0.0
	for x in img.get_width():
		for y in img.get_height():
			var p := img.get_pixel(x, y)
			if p.a <= 0.02:
				continue
			if _is_ramp_tone(p):
				continue
			var l: float = p.r * 0.299 + p.g * 0.587 + p.b * 0.114 + lift
			var idx := 0
			if l > 0.62:
				idx = 3
			elif l > 0.38:
				idx = 2
			elif l > 0.16:
				idx = 1
			var c: Color = ENEMY_RAMP[idx]
			_px(img, x, y, Color(c.r, c.g, c.b, p.a))

## Is this pixel already one of the four stops? 8-bit quantisation means an exact
## comparison would miss by a thousandth, so the test is a tolerance.
func _is_ramp_tone(p: Color) -> bool:
	for c: Color in ENEMY_RAMP:
		if absf(p.r - c.r) < 0.006 and absf(p.g - c.g) < 0.006 and absf(p.b - c.b) < 0.006:
			return true
	return false

## The one red thing. Two pixels wide so it survives the outline pass, with a
## single hot core — no halo, no ring, no aureole. On a grey creature on a dark
## floor this is the only saturated colour for several hundred pixels, which is
## exactly why the eye finds it first.
##
## LAW 7 allows ONE white-hot pixel per light source, and a pair of eyes is one
## light: the specular now lands on the first tell point only. Three of these
## creatures have two or three tell points, and stamping a hot core into each of
## them is how a face turns into a string of lamps.
func _enemy_tell(img: Image, kind: String, boss: bool) -> void:
	var table: Dictionary = ENEMY_TELLS
	if boss and BOSS_TELLS.has(kind):
		table = BOSS_TELLS
	if not table.has(kind):
		return
	var pts: Array = table[kind]
	var i := 0
	while i + 1 < pts.size():
		var tx: int = int(pts[i])
		var ty: int = int(pts[i + 1])
		for dy in 2:
			for dx in 2:
				_over_px(img, tx + dx - 1, ty + dy - 1, HOSTILE)
		if i == 0:
			_over_px(img, tx - 1, ty - 1, HOSTILE.lerp(WHITE_HOT, 0.55))
		i += 2

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
			# Any boss kind without a bespoke body is simply the base creature;
			# _finish_enemy lifts it a value stop so it still reads as the big one.
			_draw_enemy(img, kind, c)

## Four stops, dark to light — and since round 7 they are THE ENEMY STOPS, not a
## private ramp mixed from the creature's own hue.
##
## The old version boosted the input's chroma and spread it over four values, and
## then `_enemy_repaint` immediately re-quantised the result by luminance. Two
## quantisations in a row is how the Infinite Context ended up with 316 of its
## 500 body pixels on a single stop: a flat bright disc, which under the runtime
## halo is the "smooth-gradient cyan blob" the critic named. Handing the body the
## final palette up front means the repaint has nothing left to flatten and the
## value structure drawn below is the value structure that ships.
func _boss_ramp(_c: Color) -> Array[Color]:
	var out: Array[Color] = []
	for c: Color in ENEMY_RAMP:
		out.append(c)
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

## THE INFINITE CONTEXT (boss): one unblinking lens in an ovoid shell, with three
## memory nodes grown out of its crown.
##
## Round 7 rebuilt this one body, because it was the sprite the critic pointed
## at. What it used to do: fill the shell, sculpt it, then paint an eight-pixel
## near-WHITE ellipse over the middle, a second whiter ellipse over that, a
## chroma-boosted disc over that, four white specular pixels, and three lamps on
## the crown. After the repaint quantised all of it, 316 of the sprite's ~500
## body pixels sat on the single brightest stop — one flat luminous disc with no
## interior structure at all, which is precisely what "smooth-gradient blob"
## describes once the runtime halo adds its bloom.
##
## The rebuild is three flat regions and one ring:
##   * the shell in the mid stop, with a lit crown and a far rim — no gradient,
##     three hard-edged areas;
##   * ONE bright feature, the iris annulus, and it is the only place on the
##     sprite the top stop appears;
##   * a dark pupil, so the red tell reads as an eye rather than as a dot.
## The "it remembers everything" gag survives as three short context runs along
## the lower rim, drawn in the shell's own darkest tone.
func _draw_boss_infinite_context(img: Image, c: Color) -> void:
	var ramp := _boss_ramp(c)
	_flat_ellipse(img, 16, 17, 12.0, 11.0, ramp[1])
	# Memory nodes, drawn after the shell so they read as growths ON it.
	for nx: int in [8, 16, 24]:
		_fill_rect(img, nx - 2, 2, 4, 7, ramp[1])
	# Lit crown / far rim. Two thresholds on one term: flat regions, not a ramp.
	for x in 32:
		for y in 32:
			if img.get_pixel(x, y).a <= 0.5:
				continue
			var lit := -((float(x) - 16.0) / 13.0 + (float(y) - 17.0) / 12.0)
			if lit > 0.45:
				_px(img, x, y, ramp[2])
			elif lit < -1.05:
				_px(img, x, y, ramp[0])
	# The lens. Socket, one bright iris annulus, pupil, and a well for the red
	# tell to sit in. Nothing else on this sprite is allowed the top stop.
	_flat_ellipse(img, 16, 16, 9.0, 9.0, ramp[0])
	_flat_ellipse(img, 16, 16, 8.0, 8.0, ramp[3])
	_flat_ellipse(img, 16, 16, 6.0, 6.0, ramp[1])
	_flat_ellipse(img, 16, 16, 3.0, 3.0, ramp[0])
	# Context spilling out of the bottom of it, bounded to three short runs.
	_over_line(img, 10, 26, 16, 26, ramp[0])
	_over_line(img, 19, 27, 24, 27, ramp[0])
	_over_line(img, 12, 29, 18, 29, ramp[0])

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
	# _outline_silhouette boxes it, and at the 2x a
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
	_dither_rect(img, 9, 24, 11, 4, shell_sh, shell_sh, true)  # flat: no dither under 24px
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
	_dither_rect(img, 8, 16, 16, 4, sh, sh, true)
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
	_dither_rect(img, 11, 19, 11, 4, sh, sh, true)
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

## THE LEGACY MONOLITH: a towering brick slab, cracked through, mossy on its
## lit shoulder, with COBOL runes that still glow.
##
## Its crown, one entry per column of the shaft: where that column's masonry
## starts. A ruin does not have a flat top, and a monolith is battered — wider
## at the foot than at the head — so the two end pairs start well down and the
## middle is eaten away unevenly. This is the whole silhouette in twenty ints.
const MONOLITH_CROWN: Array[int] = [10, 7, 5, 4, 4, 5, 7, 6, 4, 4, 4, 5, 5, 8, 7, 5, 4, 4, 7, 10]

func _draw_legacy_monolith(img: Image, _c: Color) -> void:
	# CRITIQUE #10 — this sprite WAS the ghost box. It filled the frame edge to
	# edge with brick (a 26x27 slab, a full-width plinth under it and a
	# crenellation strip over it, all of which the outline pass then joined up),
	# so at 32x32 on a dark floor the creature came with a faint rectangular
	# background attached. A monolith is a SLAB, not a wallpaper: the masonry now
	# lives inside a silhouette — a battered shaft with a broken crown standing
	# on a plinth wider than itself — and every pixel outside it stays alpha 0.
	var brick := Color(0.50, 0.44, 0.39)
	var mortar := brick.darkened(0.68)
	var left := 6
	var right := 26                      # exclusive
	for x in range(left, right):
		var top: int = MONOLITH_CROWN[x - left]
		_fill_rect(img, x, top, 1, 27 - top, brick)
		_px(img, x, top, brick.lightened(0.24))
	# one chunk gone from the right flank: two parallel edges are a wall, and a
	# wall is the thing this sprite is not allowed to look like
	for i in 3:
		_px(img, right - 1, 15 + i, Color(0.0, 0.0, 0.0, 0.0))
	_px(img, right - 2, 16, Color(0.0, 0.0, 0.0, 0.0))
	# the plinth it has been sinking into since 1974
	_fill_rect(img, 3, 27, 26, 3, brick.darkened(0.30))
	_fill_rect(img, 3, 27, 26, 1, brick.lightened(0.10))
	# Courses in ONE tone with a lit top edge, painted only where the shaft
	# already is. The per-brick value jitter was the confetti that made this read
	# as static at game zoom.
	for row in range(8, 27, 5):
		var off: int = 0 if ((row - 8) / 5) % 2 == 0 else 4
		for bx in range(left - 8 + off, right, 8):
			_over_rect(img, bx + 1, row + 1, 7, 1, brick.lightened(0.20))
			_over_rect(img, bx + 1, row + 4, 7, 1, brick.darkened(0.28))
		_over_rect(img, left, row, right - left, 1, mortar)
		for bx2 in range(left + off, right, 8):
			_over_rect(img, bx2, row, 1, 5, mortar)
	# structural despair, with a dogleg
	var crack := Color(0.05, 0.045, 0.04)
	for dx: int in [0, 1]:
		_over_line(img, 10 + dx, 7, 12 + dx, 16, crack)
		_over_line(img, 12 + dx, 16, 13 + dx, 26, crack)
		_over_line(img, 21 + dx, 8, 19 + dx, 17, crack)
		_over_line(img, 19 + dx, 17, 18 + dx, 26, crack)
	# glowing COBOL runes
	var rune := Color(0.42, 0.98, 0.52)
	_over_rect(img, 12, 13, 8, 2, rune.darkened(0.30))
	_over_rect(img, 13, 19, 6, 2, rune.darkened(0.30))
	_over_rect(img, 15, 11, 2, 10, rune)
	_over_px(img, 16, 15, WHITE_HOT)
	_over_rect(img, 9, 23, 2, 4, rune.darkened(0.35))
	_over_rect(img, 9, 25, 4, 1, rune.darkened(0.35))
	# moss clings to the lit shoulder, and only where there is a shoulder
	_dither_rect(img, left, 4, right - left, 3,
		Color(0.23, 0.42, 0.26), Color(0.23, 0.42, 0.26), true)
	# a lit left edge and a shaded right one: the shaft has two faces
	_over_rect(img, left, 4, 1, 23, brick.lightened(0.30))
	_over_rect(img, right - 1, 4, 1, 23, brick.darkened(0.42))

## THE INFINITE CONTEXT: an eye that has read everything you ever typed,
## including the deleted parts. The eye is a LENS, not a marble, and it owns the
## middle of the frame — an eye drawn small is a dot, and a dot is not a threat.
##
## The minion carries the same disease its boss did and it is cured the same
## way: a bright outer ring, a near-white lens, a chroma-boosted core and four
## rim lamps all quantised into one luminous disc, so all four are gone. Three
## flat regions and one bright annulus, one size down from the boss and with no
## crown, so the two read as one creature at two scales instead of as two blobs.
func _draw_infinite_context(img: Image, c: Color) -> void:
	var ramp := _boss_ramp(c)
	_flat_ellipse(img, 16, 16, 11.0, 10.0, ramp[1])
	for x in 32:
		for y in 32:
			if img.get_pixel(x, y).a <= 0.5:
				continue
			var lit := -((float(x) - 16.0) / 12.0 + (float(y) - 16.0) / 11.0)
			if lit > 0.48:
				_px(img, x, y, ramp[2])
			elif lit < -1.08:
				_px(img, x, y, ramp[0])
	_flat_ellipse(img, 16, 16, 8.0, 8.0, ramp[0])
	_flat_ellipse(img, 16, 16, 7.0, 7.0, ramp[3])
	_flat_ellipse(img, 16, 16, 5.0, 5.0, ramp[1])
	_flat_ellipse(img, 16, 16, 2.0, 2.0, ramp[0])
	_over_line(img, 11, 25, 16, 25, ramp[0])
	_over_line(img, 18, 27, 22, 27, ramp[0])

## THE ENTERPRISE ARCHITECT: a tailored suit, a power tie, an access badge, and
## an aura of governance that fades with distance (unlike the meetings).
##
## The aura is gone. It was four blue corner brackets floating in the empty
## pixels around the sprite at 42% alpha — outside the silhouette, so
## `_outline_silhouette` traced each of them, and under the old 0.5 alpha gate
## `_enemy_repaint` never touched them, which made this creature the only one in
## the cast still shipping a saturated colour that was not its red tell. LAW 7 is
## explicit that an enemy reads by SILHOUETTE; a HUD frame drawn around it is the
## opposite of a silhouette.
func _draw_enterprise_architect(img: Image, _c: Color) -> void:
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
	_dither_rect(img, 10, 3, 14, 2, Color(0.66, 0.63, 0.57), Color(0.66, 0.63, 0.57))
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

## A disc drawn the way a pixel artist draws one. An exact circle test puts ONE
## pixel on its topmost row, and `_outline_silhouette` then traces that pixel
## into a spike — four of them, at the compass points, which is how a lens turns
## into a gunsight. Carrying the usual half pixel in the radius gives the flat
## top and flat sides a hand-drawn circle has, at every radius, for free.
func _flat_ellipse(img: Image, cx: int, cy: int, rx: float, ry: float, c: Color) -> void:
	for x in img.get_width():
		for y in img.get_height():
			var dx := float(x - cx) / (rx + 0.5)
			var dy := float(y - cy) / (ry + 0.5)
			if dx * dx + dy * dy <= 1.0:
				_px(img, x, y, c)

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

## TOKENS (LAW 2, LAW 4). Six denominations, ONE colour, and since round 7 ONE
## SHAPE.
##
## The previous pass got the colour right — GOLD, no halos — and then spent the
## saving on six different silhouettes: a hex, a chip, a prism, and a "brilliant"
## cut whose flat table over tapering shoulders reads, at 16px on a dark floor,
## as a DOWN ARROW. The QA frames show it exactly that way, sitting next to
## diamonds, three per screen; a player scanning for pickups was being asked to
## learn six shapes for one verb.
##
## A denomination is a quantity, so it is expressed as a quantity: same rhombus,
## three sizes (10 / 12 / 14px), and one faint brightness step inside each size.
## Nothing else changes between them — not the hue, not the outline, not the
## number of tones, not the specular.
const TOKEN_GRADE := {
	"common": Vector2(5.0, 0.00),
	"cached": Vector2(5.0, 0.06),
	"compute": Vector2(6.0, 0.00),
	"premium": Vector2(6.0, 0.06),
	"frontier": Vector2(7.0, 0.00),
	"golden": Vector2(7.0, 0.06),
}

func _generate_tokens() -> void:
	for tname in TOKEN_GRADE:
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		_draw_gem(img, GOLD, str(tname))
		_save_image(img, "token_%s.png" % tname)

## Half-width in pixels (x) and brightness step (y) for a denomination. The
## widths are deliberately whole numbers: |dx| and |dy| are both half-integers
## on a 16px canvas, so only 5 / 6 / 7 produce distinct silhouettes — 5.5 draws
## the same diamond as 5, which is how a "size ladder" becomes six identical
## sprites without anyone noticing.
func _gem_grade(cut: String) -> Vector2:
	if TOKEN_GRADE.has(cut):
		var g: Vector2 = TOKEN_GRADE[cut]
		return g
	return Vector2(7.0, 0.06)

## Inside-the-stone test. One rhombus, sized by denomination, bounded so the
## outline pass still has a clear row on every side of the frame.
func _gem_mask(x: int, y: int, cut: String) -> bool:
	var r := _gem_grade(cut).x
	return absf(float(x) - 7.5) + absf(float(y) - 7.5) <= r

## A cut stone in three tones lit from the top-left, one white-hot specular, and
## a 1px outline. That is the entire recipe. What is gone, deliberately: the
## five-stop facet ramp, the girdle and crown seams, the refracted caustic, the
## four-pixel specular cluster, and both halo rings.
func _draw_gem(img: Image, c: Color, cut: String = "radiant") -> void:
	var grade := _gem_grade(cut)
	# The brightness step is a lift toward a paler gold, never toward another
	# hue: a rare token is a brighter gold, not a different colour (LAW 2).
	var body: Color = c.lerp(Color(1.0, 0.93, 0.74), grade.y)
	var light := body.lightened(0.30)
	var shadow := body.darkened(0.38)
	for x in 16:
		for y in 16:
			if not _gem_mask(x, y, cut):
				continue
			var lit := -((float(x) - 7.5) + (float(y) - 7.5)) * 0.5
			var col := body
			if lit > 1.4:
				col = light
			elif lit < -1.4:
				col = shadow
			_px(img, x, y, col)
	# The one pixel that makes it precious, kept on the lit facet at every size.
	var sp: int = 7 - int(grade.x * 0.35)
	_over_px(img, sp, sp, WHITE_HOT)
	_outline_silhouette(img, OUTLINE_COLOR)

## ONE panel style (LAW 8): BASE at 96%, a 1px LINE border, radius 0. No
## gradient, no inner sheen, no cyan corner ticks, no white-hot corners "for a
## hint of bloom". A modal is a place to read words in; it is not a light.
func _generate_ui_elements() -> void:
	var panel := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var base := Color(0.043, 0.055, 0.11, 0.96)   # BASE #0B0E1C @ 96%
	var line := Color(0.165, 0.208, 0.345, 1.0)   # LINE #2A3558
	for x in 64:
		for y in 64:
			_px(panel, x, y, base)
	for i in 64:
		_px(panel, i, 0, line)
		_px(panel, i, 63, line)
		_px(panel, 0, i, line)
		_px(panel, 63, i, line)
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

## The icon: one gold gem on the void. The old one was a poster — halo rings, a
## starfield, a reflection pool, scanlines and a cyan stripe — six ideas fighting
## over 128 pixels. A mark should be one idea, and the idea is "token".
func _generate_icon() -> void:
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var void_c := Color(0.02, 0.024, 0.055)  # VOID #05060E
	for x in 128:
		for y in 128:
			_px(img, x, y, void_c)
	# the gem: a faceted diamond in three tones, lit from the top-left
	var light := GOLD.lightened(0.30)
	var shadow := GOLD.darkened(0.38)
	for x in 128:
		for y in 128:
			var ddx := absf(float(x) - 64.0)
			var ddy := absf(float(y) - 62.0) * 1.15
			if ddx / 34.0 + ddy / 34.0 > 1.0:
				continue
			var col := GOLD
			if x < 64 and y < 62:
				col = light
			elif x >= 64 and y >= 62:
				col = shadow
			_px(img, x, y, col)
	# one facet seam and one specular. That is the whole drawing.
	for x2 in range(30, 99):
		_over_px(img, x2, 62, GOLD.darkened(0.52))
	_fill_rect(img, 50, 44, 2, 2, WHITE_HOT)
	img.save_png(ProjectSettings.globalize_path("res://assets/textures/icon.png"))

## ========== The region ground set + set-dressing fidelity ==========
## Rule 1: structure before noise — a floor set with readable construction
## (plank runs, slabs, flags, weave, grille, loam, pile, plate) authored to the
## LAW 6 window above, so it reads as GROUND and props still sit a clear value
## step off it. The "author it dark, ~0.11-0.14 mean" instruction that used to
## live on this line is what produced nine black rooms and is gone. Rule 2: the
## silhouette law — the dress_/furn_ set gets a post-pass so every labeled prop
## reads without its label. The composition side consumes these exists()-guarded;
## the filenames are contract.

func _generate_floor_structures() -> void:
	# region_builder resolves this set by REGION_TILE_MAP suffix ("gpu",
	# "cloud", ...), never by family name — so each region needs a floor_<suffix>
	# pair on disk, or every floor_* lookup misses and the whole set is
	# authored-but-unreachable (the round-3 lesson, again).
	#
	# ROUND 9 — those files used to be ALIASES: ten regions were served by four
	# shared family textures, so api_bazaar's market stood on Localhost's
	# floorboards and dependency, corporate and production shared one deck.
	# That is precisely the "one shared square-tile floor tinted per region"
	# the critique names. Each region now writes its OWN LAW 6 material, and the
	# four canonical family filenames survive as copies of a representative
	# region so nothing that looks them up can miss.
	for alt: bool in [false, true]:
		var suffix := "_alt" if alt else "_base"
		var no_alias: Array[String] = []
		for rname: String in FLOOR_REGIONS:
			_save_floor(_make_floor_tile(rname, alt), rname, no_alias, suffix)
		_save_floor(_floor_interior(alt), "interior", no_alias, suffix)
		_save_floor(_floor_industrial(alt), "industrial", no_alias, suffix)
		_save_floor(_floor_outdoor(alt), "outdoor", no_alias, suffix)
		_save_floor(_floor_ethereal(alt), "ethereal", no_alias, suffix)
	_save_image(_make_path_tile(), "path_tile.png")
	_save_image(_make_path_tile_edge(), "path_tile_edge.png")

## One floor family under its canonical name plus one alias per region that
## asks for it. Everything written here passes the LAW 6 luminance gate first.
func _save_floor(img: Image, family: String, regions: Array[String], suffix: String) -> void:
	_save_floor_tile(img, "floor_%s%s.png" % [family, suffix])
	for rk: String in regions:
		_save_floor_tile(img, "floor_%s%s.png" % [rk, suffix])

## The four canonical family names, each now a copy of the region whose
## material defines it. They are kept because the filenames are contract; the
## per-region files above are what the game actually stands on.

## Plank run in dark warm wood — Localhost's material.
func _floor_interior(alt: bool) -> Image:
	return _make_floor_tile("localhost", alt)

## Poured slab with sawn expansion joints — Production's material.
func _floor_industrial(alt: bool) -> Image:
	return _make_floor_tile("production", alt)

## Cracked sandstone flags — the Ruins' material.
func _floor_outdoor(alt: bool) -> Image:
	return _make_floor_tile("stackoverflow", alt)

## Steel grating — the Cloud District's material.
func _floor_ethereal(alt: bool) -> Image:
	return _make_floor_tile("cloud", alt)

## One running-bond paver pixel. Shared by path_tile and path_tile_edge so an
## edge tile placed against a path tile continues the same bond exactly. Three
## tones, no noise, no chipped-paver lottery.
func _paver_px(x: int, y: int) -> Color:
	var row := y >> 3
	var ry := y & 7
	var off := 8 if row % 2 == 1 else 0
	var rx := (x + off) % 16
	var base := Color(0.44, 0.41, 0.36)
	if ry == 0 or rx == 0:
		return base.darkened(0.30)      # joint
	if ry == 1 or rx == 1:
		return base.lightened(0.12)     # lit bevel (top-left light)
	return base

## Walkable path: running-bond pavers, authored a step BRIGHTER than every
## region floor so "walk here" reads in a one-second glance at a static frame.
## This value relationship is the game's wayfinding and it is deliberately the
## loudest thing the floor is allowed to do — which means it has to move with
## the floors. LAW 6 puts a floor at 64-84; the path sits just over it at ~96,
## the same distance above ground it always was.
const PATH_DIM := 0.90
func _make_path_tile() -> Image:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			_px(img, x, y, _paver_px(x, y))
	_dim_tile(img, PATH_DIM)
	return img

## Path edge: pavers on top, a lit curb row, then a short clean falloff to
## TRANSPARENT so the composition side can border a path against any region
## floor. Rotate the sprite to orient the edge; the paver half matches
## path_tile row-for-row.
func _make_path_tile_edge() -> Image:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var soil := Color(0.14, 0.15, 0.20)
	for y in 64:
		for x in 64:
			if y < 48:
				_px(img, x, y, _paver_px(x, y))
			elif y == 48:
				_px(img, x, y, Color(0.62, 0.58, 0.50))   # curb catches the light
			elif y <= 51:
				_px(img, x, y, Color(0.26, 0.24, 0.21).darkened(0.14 * float(y - 49)))
			else:
				var a := maxf(0.0, 0.80 * (1.0 - float(y - 52) / 11.0))
				_px(img, x, y, Color(soil.r, soil.g, soil.b, a))
	_dim_tile(img, PATH_DIM)
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
	# What is left of this pass: weight. The chroma boost is gone (it was pushing
	# saturation INTO props that LAW 7 wants desaturated) and so is the near-white
	# rim (LAW 7 gives a rim tone to the player and to nobody else). A prop is
	# grounded by a dark underside and a contact shadow, not by being lit.
	_underside_ao(img, 3, 0.26)
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

## ---------- shared raster helpers (bible quality bar) ----------

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

## ONE white-hot core with one pixel of accent spill below it. It used to stamp
## a four-neighbour accent cross around every core, which is a five-pixel lamp,
## and it ran on accessories, props and pose effects alike. Its last consumer is
## the player's charging prompt — a genuine light, held in a hand.
func _glow_core(img: Image, x: int, y: int, accent: Color) -> void:
	_px(img, x, y, WHITE_HOT)
	_px(img, x, y + 1, accent)

## A lamp: two tones and ONE white-hot core pixel (LAW 7). The dim bleed ring
## this used to paint around every lamp was a halo under another name, and it
## ran on every LED of every creature and every prop in the game.
func _glow_lamp(img: Image, x: int, y: int, accent: Color, r: int = 2) -> void:
	_fill_circle(img, x, y, r, accent.darkened(0.30))
	_fill_circle(img, x, y, r - 1, accent)
	_px(img, x, y, WHITE_HOT)

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

## Full value on the same hue. Only the boss bodies still use it, to pick one
## readable stop out of a muted input before _enemy_repaint flattens the lot.
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

## Fill a circle with a clean 3-tone top-left-lit ramp — instant "sphere" for
## heads and domes. The dithered terminator band is gone: LAW 7 bans dithering
## under 24px, and every head in this game is sixteen pixels across.
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

## A 3-tone limb (arm, leg, sleeve): lit edge, base, core shadow. Light is
## top-left, so the lit edge is the left one. No dither — a sleeve is 4px wide.
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
			_px(img, ix, iy, c)

## Rim light on ONE diagonal silhouette edge. The player, and only the player,
## gets a single call to this (LAW 7's fourth tone). Every other sprite in the
## game is finished with three tones and an outline.
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

## _fill_rect that respects the silhouette. Course lines, runes and edge
## lighting all want this: they belong TO a shape and must never widen it.
func _over_rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for iy in range(y, y + h):
		for ix in range(x, x + w):
			_over_px(img, ix, iy, c)

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
