extends RefCounted
class_name LocalhostBuilder
## Hand-composed 3AM coder apartment. A deliberately designed, zoned interior —
## battlestation on a rug, server corner, kitchen with only energy drinks, an
## unslept-in bed, a node_modules trash heap, a deprecated plant — so the space
## reads instantly as "this person has destroyed their life shipping an app,"
## not as a stamped tile field.

const GEN := "res://assets/textures/generated/"
const SHADERS := "res://assets/shaders/"
const TILE := 64
const ROOM_W := 25   # tiles -> 1600 px
const ROOM_H := 16   # tiles -> 1024 px
const WALL_LAYER := 32

## Where a cable run sits in the depth stack: above the boards, their grime and
## the light pools (-100..-86), below the walls (-60..-55) and below every prop
## (props sort to positive depth-z). Cables are what the room was built ON, so
## nothing in the room is ever drawn behind them.
const CABLE_Z := -80

## One-time caches, mirroring RegionBuilder's (duplicated on purpose: this file
## is preloaded BY region_builder.gd, so leaning on its class_name from here
## would be a cyclic reference for two functions' worth of code).
static var _radial_cache: Texture2D
static var _shadow_cache: Texture2D
static var _neon_cache: Dictionary = {}
static var _screen_cache: Dictionary = {}
static var _mat_cache: Dictionary = {}
static var _add_mat_cache: CanvasItemMaterial

## Where the portal to the Dependency District stands. The EXIT sign, the exit
## neon and the reserved label boxes all key off this one constant so they can
## never drift apart again (they had: the EXIT sign used to draw straight
## through the portal's own destination plate).
const PORTAL_POS := Vector2(ROOM_W * TILE - 90, ROOM_H * TILE * 0.5)

static func build(parent: Node2D) -> Dictionary:
	parent.y_sort_enabled = true
	var size := Vector2(ROOM_W * TILE, ROOM_H * TILE)
	var spawn := Vector2(720, 640)
	_reserve_labels()
	_build_floor(parent)
	_build_rug(parent)
	_build_floor_zones(parent)
	_build_walls(parent)
	_build_grounding(parent)
	_build_battlestation(parent)
	_build_gpu_rig(parent)
	_build_server_corner(parent)
	_build_kitchen(parent)
	_build_bedroom(parent)
	_build_clutter(parent)
	_build_lighting(parent)
	_build_poi_pools(parent)
	_build_atmosphere(parent)
	_build_signs(parent)
	_build_framing(parent)
	_populate_gameplay(parent, spawn)
	return {"spawn": spawn, "size": size}

# ------------------------------------------------------------- helpers ------

static func _tex(name: String) -> Texture2D:
	var path := GEN + name + ".png"
	return load(path) if ResourceLoader.exists(path) else null

static func _put(parent: Node2D, tex_name: String, pos: Vector2, z: int, scale: float = 1.0, mod: Color = Color.WHITE) -> Sprite2D:
	var t := _tex(tex_name)
	if not t:
		return null
	var s := Sprite2D.new()
	s.texture = t
	s.position = pos
	s.z_index = z
	s.scale = Vector2(scale, scale)
	s.modulate = mod
	parent.add_child(s)
	return s

## Furniture depth: z tracks the sprite's base Y so it sorts against the player
## (which sets z_index = int(global_position.y)). Objects lower on screen draw
## in front, giving real top-down occlusion.
static func _depth(pos_y: float, half_h: float) -> int:
	return int(pos_y + half_h)

# ------------------------------------------------- lighting/fx helpers ------

static func _radial() -> Texture2D:
	if _radial_cache:
		return _radial_cache
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for x in 64:
		for y in 64:
			var d := Vector2(x - 32, y - 32).length() / 32.0
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	_radial_cache = ImageTexture.create_from_image(img)
	return _radial_cache

## Preferred soft light cookie (pixel-art agents supply it); procedural fallback.
static func _light_tex() -> Texture2D:
	var path := GEN + "fx_radial_soft.png"
	if ResourceLoader.exists(path):
		return load(path)
	return _radial()

static func _glow_dot() -> Texture2D:
	var path := GEN + "fx_glow_dot.png"
	return load(path) if ResourceLoader.exists(path) else null

static func _additive_mat() -> CanvasItemMaterial:
	if not _add_mat_cache:
		_add_mat_cache = CanvasItemMaterial.new()
		_add_mat_cache.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _add_mat_cache

## Shared ShaderMaterial factory: one instance per shader+params combo, or null
## when the shader file is missing (callers then simply skip the dressing).
static func _shader_mat(shader_name: String, params: Dictionary = {}) -> ShaderMaterial:
	var path := SHADERS + shader_name + ".gdshader"
	if not ResourceLoader.exists(path):
		return null
	var key := shader_name + str(params)
	if _mat_cache.has(key):
		return _mat_cache[key]
	var mat := ShaderMaterial.new()
	mat.shader = load(path)
	for k in params:
		mat.set_shader_parameter(k, params[k])
	_mat_cache[key] = mat
	return mat

static func _add_light(parent: Node2D, pos: Vector2, color: Color, energy: float, scale: float, flicker: bool = false) -> PointLight2D:
	var light := PointLight2D.new()
	var tex := _light_tex()
	light.texture = tex
	light.energy = energy
	light.color = color
	# Normalize so authored scales mean the same world size whether the 128px
	# fx_radial_soft cookie exists or the 64px procedural fallback is in play.
	light.texture_scale = scale * (64.0 / maxf(1.0, float(tex.get_width())))
	light.position = pos
	parent.add_child(light)
	if flicker:
		_flicker(light)
	return light

## Gentle mains-hum flicker (about ±10% energy) — tween-driven, no per-frame
## script, dies with its light. The asymmetric halves keep it from metronoming.
static func _flicker(light: PointLight2D, amount: float = 0.10, period: float = 1.7) -> void:
	if not light.is_inside_tree():
		return
	var base := light.energy
	var tw := light.create_tween().set_loops()
	tw.tween_property(light, "energy", base * (1.0 + amount), period * 0.41).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(light, "energy", base * (1.0 - amount), period * 0.59).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## Soft dark ellipse so raised props sit ON the floor instead of hovering near it.
static func _shadow_tex() -> Texture2D:
	if _shadow_cache:
		return _shadow_cache
	var img := Image.create(48, 24, false, Image.FORMAT_RGBA8)
	for x in 48:
		for y in 24:
			var v := Vector2((x - 24.0) / 24.0, (y - 12.0) / 12.0).length()
			var a := clampf(1.0 - v, 0.0, 1.0)
			img.set_pixel(x, y, Color(0, 0, 0, a * a))
	_shadow_cache = ImageTexture.create_from_image(img)
	return _shadow_cache

static func _drop_shadow(parent: Node2D, pos: Vector2, width: float, z: int, alpha: float = 0.34) -> void:
	var s := Sprite2D.new()
	s.texture = _shadow_tex()
	s.position = pos
	s.scale = Vector2(width / 48.0, width / 108.0)
	s.modulate = Color(1, 1, 1, alpha)
	s.z_index = z
	parent.add_child(s)

## Tiny neon tube (rounded bar, WHITE_HOT core row) — the texture carries the
## color because neon_flicker.gdshader replaces vertex COLOR (modulate is lost).
static func _neon_tex(col: Color) -> Texture2D:
	var key := col.to_html(false)
	if _neon_cache.has(key):
		return _neon_cache[key]
	var img := Image.create(48, 6, false, Image.FORMAT_RGBA8)
	var core := Color(minf(col.r + 0.75, 1.0), minf(col.g + 0.75, 1.0), minf(col.b + 0.75, 1.0))
	for x in 48:
		var end_fade := 1.0
		if x < 2 or x > 45:
			end_fade = 0.35
		for y in 6:
			var c: Color
			if y == 2 or y == 3:
				c = core
			elif y == 1 or y == 4:
				c = col
			else:
				c = Color(col.r, col.g, col.b, 0.35)
			c.a *= end_fade
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	_neon_cache[key] = tex
	return tex

## Small emissive screen face (gradient + faint code lines) for crt_monitor —
## color baked into the texture for the same modulate-drop reason as _neon_tex.
static func _screen_tex(col: Color) -> Texture2D:
	var key := col.to_html(false)
	if _screen_cache.has(key):
		return _screen_cache[key]
	var img := Image.create(40, 26, false, Image.FORMAT_RGBA8)
	for x in 40:
		for y in 26:
			var v := 1.0 - 0.35 * (float(y) / 25.0)
			var c := Color(col.r * v, col.g * v, col.b * v, 1.0)
			if x == 0 or y == 0 or x == 39 or y == 25:
				c = c.darkened(0.55)
			elif (y % 5) == 2 and x > 3 and x < 30 + (y * 7) % 9:
				c = c.lightened(0.25)
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	_screen_cache[key] = tex
	return tex

## Blinking status LED (additive, tween-driven). Green means fine, amber means
## fine-ish, nobody has checked either in weeks.
static func _led(parent: Node2D, pos: Vector2, color: Color, phase: float, z: int) -> void:
	var led := ColorRect.new()
	led.size = Vector2(4, 3)
	led.position = pos
	led.color = color
	led.material = _additive_mat()
	led.mouse_filter = Control.MOUSE_FILTER_IGNORE
	led.z_index = z
	parent.add_child(led)
	if not led.is_inside_tree():
		return
	var tw := led.create_tween().set_loops()
	tw.tween_interval(phase)
	tw.tween_property(led, "modulate:a", 0.2, 0.06)
	tw.tween_interval(0.22 + phase * 0.5)
	tw.tween_property(led, "modulate:a", 1.0, 0.06)
	tw.tween_interval(0.7)

## Tiny specular glint where cable bundles catch the lamplight.
static func _catch_light(parent: Node2D, pos: Vector2, col: Color) -> void:
	var dot := _glow_dot()
	if dot:
		var s := Sprite2D.new()
		s.texture = dot
		s.position = pos
		s.scale = Vector2(0.5, 0.5)
		s.material = _additive_mat()
		s.modulate = Color(col.r, col.g, col.b, 0.55)
		s.z_index = -79
		parent.add_child(s)
	else:
		var r := ColorRect.new()
		r.size = Vector2(2, 2)
		r.position = pos
		r.color = Color(col.r, col.g, col.b, 0.55)
		r.material = _additive_mat()
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.z_index = -79
		parent.add_child(r)

## Rotatable filled rectangle centred on `center` (Control rects anchor from the
## top-left, which is never what a composition wants).
static func _rect(parent: Node2D, center: Vector2, size: Vector2, col: Color, z: int, rot: float = 0.0) -> ColorRect:
	var r := ColorRect.new()
	r.size = size
	r.pivot_offset = size * 0.5
	r.position = center - size * 0.5
	r.rotation = rot
	r.color = col
	r.z_index = z
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r

## An additive puddle of light ON the floor. Real PointLight2Ds are budgeted; a
## pool costs one sprite, and it is what makes a lamp look like it is LIGHTING
## something instead of merely being bright.
static func _light_pool(parent: Node2D, pos: Vector2, width: float, col: Color, alpha: float = 0.26, z: int = -86) -> void:
	var s := Sprite2D.new()
	s.texture = _light_tex()
	s.material = _additive_mat()
	s.position = pos
	var tw := maxf(1.0, float(s.texture.get_width()))
	s.scale = Vector2(width / tw, width * 0.6 / tw)
	s.modulate = Color(col.r, col.g, col.b, alpha)
	s.z_index = z
	parent.add_child(s)

## Soft coloured stain on the floorboards — worn tracks, spills, shadowed zones.
static func _floor_patch(parent: Node2D, pos: Vector2, width: float, col: Color, alpha: float, z: int = -94) -> void:
	var s := Sprite2D.new()
	s.texture = _shadow_tex()
	s.position = pos
	# The ellipse is 48x24, so the axes divide by different numbers to land on an
	# actual width x 0.62*width footprint.
	s.scale = Vector2(width / 48.0, width * 0.62 / 24.0)
	s.modulate = Color(col.r, col.g, col.b, alpha)
	s.z_index = z
	parent.add_child(s)

# ------------------------------------------------------- label placement ----

## Boxes owned by nodes this builder does not draw the text for: the portal's
## destination plate and the vortex disc under it, Claude's name tag and Claude
## himself, and the five monitor faces that carry their own baked-in readouts.
## Reserved before any sign is placed, so signs move out of THEIR way.
static func _reserve_labels() -> void:
	WorldLabel.begin(Rect2(0.0, 0.0, float(ROOM_W * TILE), float(ROOM_H * TILE)))
	WorldLabel.reserve(Rect2(PORTAL_POS + Vector2(-88, -70), Vector2(176, 44)))
	WorldLabel.reserve(Rect2(PORTAL_POS + Vector2(-104, -104), Vector2(208, 208)))
	# Claude's nameplate AND the column his idle barks rise through: npc.gd
	# puts the plate at y -106..-86 and stacks bubbles up to about -175, so a
	# sign anywhere in that box would be spoken over.
	WorldLabel.reserve(Rect2(Vector2(820, 560) + Vector2(-170, -200), Vector2(340, 140)))
	# Claude's actual silhouette (npc sprite is 2.2x a 32px texture, drawn 18px
	# high of centre) — deliberately tight, because "← talk to Claude first" has
	# to stay right next to him to mean anything.
	WorldLabel.reserve(Rect2(Vector2(820, 560) + Vector2(-42, -62), Vector2(84, 86)))
	# The player himself: his spawn footprint at (720,640) and the lane he walks
	# up to reach Claude. This is the one box in the room a caption may never
	# have, and it had one — see the note on the "talk to Claude first" sign in
	# _build_signs.
	#
	# The footprint is world_label.gd's own PLAYER_BODY, Rect2(-46,-84,92,110),
	# which puts the character at 674..766 x 556..666 when he spawns at
	# (720,640); this box adds a margin and the strip of floor between him and
	# Claude. It stops at y 500 on purpose, so it does not also swallow the band
	# the battlestation captions live in — the "↑ Dream App terminal" sign is
	# already fighting Claude's bark column for that air and must not lose the
	# rest of it. Verified against the ladder: no apartment sign's HOME slot
	# touches this box, so nothing is displaced by adding it and nothing hides.
	WorldLabel.reserve(Rect2(Vector2(672, 500), Vector2(194, 186)))
	for m: Vector2 in [Vector2(430, 300), Vector2(540, 296), Vector2(650, 300), Vector2(1060, 318), Vector2(1170, 320)]:
		WorldLabel.reserve(Rect2(m - Vector2(44, 34), Vector2(108, 64)))

# ---------------------------------------------------------- grounding -------

## Ambient occlusion + grime so the apartment stops looking pasted onto the
## floor. Everything exists()-guarded — the art agents supply the decals.
static func _build_grounding(parent: Node2D) -> void:
	var z := Node2D.new()
	z.name = "Grounding"
	parent.add_child(z)
	var w := ROOM_W * TILE
	var h := ROOM_H * TILE
	var ao_path := GEN + "decal_ao_edge.png"
	if ResourceLoader.exists(ao_path):
		var tex: Texture2D = load(ao_path)
		# [position, rotation, scale] — the 32px gradient is uniform across, so
		# stretching along each wall == tiling, minus ~140 sprites.
		var edges := [
			[Vector2(w * 0.5, 68.0), 0.0, Vector2(w / 32.0, 1.2)],
			[Vector2(w * 0.5, h - 16.0), PI, Vector2(w / 32.0, 0.8)],
			[Vector2(46.0, h * 0.5), -PI * 0.5, Vector2(h / 32.0, 0.9)],
			[Vector2(w - 46.0, h * 0.5), PI * 0.5, Vector2(h / 32.0, 0.9)],
		]
		for e in edges:
			var s := Sprite2D.new()
			s.texture = tex
			s.position = e[0]
			s.rotation = e[1]
			s.scale = e[2]
			s.modulate = Color(1, 1, 1, 0.55)
			s.z_index = -57
			z.add_child(s)
	# Floor grime. This floor has seen things. Mostly pizza.
	var names: Array = []
	for i in 3:
		if ResourceLoader.exists(GEN + "decal_grime_%d.png" % i):
			names.append(GEN + "decal_grime_%d.png" % i)
	if names.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	for i in 18:
		var s := Sprite2D.new()
		s.texture = load(names[rng.randi() % names.size()])
		s.position = Vector2(rng.randf_range(90, w - 90), rng.randf_range(110, h - 80))
		s.rotation = float(rng.randi() % 4) * PI * 0.5
		s.scale = Vector2.ONE * rng.randf_range(0.8, 1.8)
		s.modulate = Color(1, 1, 1, rng.randf_range(0.35, 0.68))
		s.z_index = -95
		z.add_child(s)

# -------------------------------------------------------------- floor -------

## Deterministic per-cell hash (duplicated from RegionBuilder on purpose: this
## file is preloaded BY that one, so reaching back into it would be cyclic).
static func _cell_hash(x: int, y: int) -> int:
	var v := (x * 374761393 + y * 668265263) & 0x7FFFFFFF
	v = ((v ^ (v >> 13)) * 1274126177) & 0x7FFFFFFF
	return (v ^ (v >> 16)) & 0x7FFFFFFF

## Smooth low-frequency wear: coarse 4-tile cells hashed, then bilinearly
## blended, so the boards darken and lighten in BLOTCHES the size of furniture
## rather than per plank. Per-tile jitter alone leaves the lattice visible.
static func _floor_wear(x: int, y: int) -> float:
	var cx := x >> 2
	var cy := y >> 2
	var fx := float(x & 3) / 4.0
	var fy := float(y & 3) / 4.0
	var v00 := float(_cell_hash(cx, cy) % 1000) / 1000.0
	var v10 := float(_cell_hash(cx + 1, cy) % 1000) / 1000.0
	var v01 := float(_cell_hash(cx, cy + 1) % 1000) / 1000.0
	var v11 := float(_cell_hash(cx + 1, cy + 1) % 1000) / 1000.0
	return 0.89 + lerpf(lerpf(v00, v10, fx), lerpf(v01, v11, fx), fy) * 0.20

static func _build_floor(parent: Node2D) -> void:
	var floor := Node2D.new()
	floor.name = "Floor"
	parent.add_child(floor)
	for gx in ROOM_W:
		for gy in ROOM_H:
			var hv := _cell_hash(gx, gy)
			# Board variant per 2x1 BLOCK, so planks run in short courses instead
			# of the old (gx*7 + gy*13) % 3 diagonal, which repeated every three
			# tiles in a stripe you could count across the room.
			var v := _cell_hash(gx >> 1, gy) % 3
			if hv % 100 < 16:
				v = (hv >> 7) % 3
			# The 1.22 base exposure is measured, not guessed: captured frames put
			# this floor at ~0.06 luminance, dark enough that the boards read as
			# one black field.
			var e := (1.22 + (float(hv % 53) / 53.0 - 0.5) * 0.11) * _floor_wear(gx, gy)
			var mod := Color(e, e, e * 0.96)
			if (hv >> 9) % 17 == 0:
				mod = mod.darkened(0.18)  # coffee stain / grime
			_put(floor, "int_floor_%d" % v, Vector2(gx * TILE + TILE / 2, gy * TILE + TILE / 2), -100, 1.0, mod)
	_floor_blotches(floor)
	_floor_mottle(floor)

## One full-floor pass of ground_mottle.gdshader (blend_mul) at z -93, under the
## rug and under every prop: slow, non-repeating darkening far below the 64px
## plank pitch, plus an off-axis grit octave that fights the lattice directly.
## Gentler than the regions' — this room is warm, hand-composed and small enough
## that the eye reads furniture before it reads floor. exists()-guarded.
static func _floor_mottle(parent: Node2D) -> void:
	var mat := _shader_mat("ground_mottle", {
		"amount": 0.22,
		"darkest": 0.68,
		"floor_scale": 2.0,
		"detail_scale": 6.0,
		"streak": 0.5,
		"grit": 0.45,
		"grit_scale": 24.0,
		"grit_rot": 0.62,
		"aspect": Vector2(float(ROOM_W) / float(ROOM_H), 1.0),
		"seed": 7.3,
		"tint": Vector3(1.0, 0.97, 0.92),
	})
	if not mat:
		return
	var rect := ColorRect.new()
	rect.name = "Mottle"
	rect.material = mat
	rect.position = Vector2.ZERO
	rect.size = Vector2(float(ROOM_W * TILE), float(ROOM_H * TILE))
	rect.z_index = -93
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)

## Big soft stains at non-grid positions and non-grid sizes. Nothing here lines
## up with a plank edge, which is the point: overlapping ellipses read as a floor
## with a decade of history and hide the lattice underneath them.
static func _floor_blotches(parent: Node2D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var w := ROOM_W * TILE
	var h := ROOM_H * TILE
	for i in 18:
		var p := Vector2(rng.randf_range(70, w - 70), rng.randf_range(100, h - 50))
		var width := rng.randf_range(140.0, 420.0)
		if rng.randf() < 0.74:
			_floor_patch(parent, p, width, Color(0.02, 0.015, 0.012), rng.randf_range(0.10, 0.24), -97)
		else:
			_floor_patch(parent, p, width * 0.66, Color(1.0, 0.82, 0.6), rng.randf_range(0.02, 0.05), -97)
	# Scuff marks: a chair has been rolled over these boards a great many times.
	for i in 14:
		var sp := Vector2(rng.randf_range(140, w - 140), rng.randf_range(150, h - 90))
		var ang := rng.randf_range(-PI, PI)
		_rect(parent, sp, Vector2(rng.randf_range(50.0, 160.0), 2.0), Color(0, 0, 0, 0.18), -96, ang)

static func _build_rug(parent: Node2D) -> void:
	_put(parent, "int_rug", Vector2(560, 600), -90)

## The worn track this person walks forty times a day: chair -> the middle of the
## room -> Claude -> the door. It is a lived-in floor AND the quietest possible
## answer to "where am I supposed to go" — you follow the path someone wore.
static func _build_floor_zones(parent: Node2D) -> void:
	var z := Node2D.new()
	z.name = "FloorZones"
	parent.add_child(z)
	var track: Array[Vector2] = [
		Vector2(560, 520), Vector2(660, 600), Vector2(720, 648), Vector2(810, 606),
		Vector2(900, 590), Vector2(1030, 566), Vector2(1160, 548), Vector2(1290, 534),
		Vector2(1420, 520), Vector2(1500, 514),
	]
	for i in track.size() - 1:
		var a: Vector2 = track[i]
		var b: Vector2 = track[i + 1]
		for s in 4:
			var p := a.lerp(b, float(s) / 4.0)
			_floor_patch(z, p, 128.0, Color(0.03, 0.025, 0.02), 0.2, -96)
			_floor_patch(z, p, 78.0, Color(1.0, 0.86, 0.66), 0.045, -95)
	# Kitchen corner: sticky. Bedroom corner: colder, bluer, unvisited.
	_floor_patch(z, Vector2(200, 300), 420.0, Color(1.0, 0.74, 0.4), 0.06, -95)
	_floor_patch(z, Vector2(1330, 860), 420.0, Color(0.4, 0.48, 0.9), 0.05, -95)
	# Under the desk: a dark cave of cables and abandoned socks.
	_floor_patch(z, Vector2(540, 420), 340.0, Color(0.02, 0.02, 0.04), 0.34, -94)

# -------------------------------------------------------------- walls -------

static func _build_walls(parent: Node2D) -> void:
	var walls := Node2D.new()
	walls.name = "Walls"
	parent.add_child(walls)
	var right := ROOM_W * TILE
	var bottom := ROOM_H * TILE
	# Top wall band (behind everything), with a window and a door cut in.
	for gx in ROOM_W:
		var x := gx * TILE + TILE / 2
		_put(walls, "int_wall", Vector2(x, 16), -60)
		_add_collider(walls, Vector2(x, 24), Vector2(TILE, 56))
	# Side + bottom borders (thin dark strips + colliders)
	for gy in ROOM_H:
		var y := gy * TILE + TILE / 2
		_put(walls, "int_wall_side", Vector2(20, y), -58, 1.0, Color(0.8, 0.8, 0.9))
		_put(walls, "int_wall_side", Vector2(right - 20, y), -58, 1.0, Color(0.7, 0.7, 0.8))
		_add_collider(walls, Vector2(6, y), Vector2(20, TILE))
		_add_collider(walls, Vector2(right - 6, y), Vector2(20, TILE))
	for gx in ROOM_W:
		var x2 := gx * TILE + TILE / 2
		_add_collider(walls, Vector2(x2, bottom - 6), Vector2(TILE, 20))
	# Floor-to-ceiling window (night city) behind the battlestation — the hero
	# wall piece that ties the flat to the menu's skyline. It hangs well below
	# the 64px wall band, and that is the trick: everything in the room draws
	# in front of it (z -55 vs furniture depth-z, player z = int(y)), so the
	# desk and its monitors back onto the glass instead of floating under a
	# porthole. The texture bakes its own sill + feathered contact shadow so
	# it meets the boards cleanly. Old casement stays as the fallback for a
	# checkout where the hero texture has not been generated yet.
	if not _put(walls, "int_window_big", Vector2(545, 150), -55):
		_put(walls, "int_window", Vector2(560, 40), -55)
	_put(walls, "furn_door", Vector2(1360, 46), -55)
	# Whiteboard of doom on the wall
	_put(walls, "furn_whiteboard", Vector2(950, 60), -50)

static func _add_collider(parent: Node2D, pos: Vector2, sz: Vector2) -> void:
	var wall := StaticBody2D.new()
	wall.collision_layer = WALL_LAYER
	wall.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = sz
	shape.shape = rect
	shape.position = pos
	wall.add_child(shape)
	parent.add_child(wall)

# --------------------------------------------------------- battlestation ----

static func _build_battlestation(parent: Node2D) -> void:
	var z := Node2D.new()
	z.name = "Battlestation"
	parent.add_child(z)
	# Desk against the window wall
	var desk_y := 340.0
	var desk_z := _depth(desk_y, 48)
	_drop_shadow(z, Vector2(520, desk_y + 42), 230.0, desk_z - 1)
	_put(z, "furn_desk", Vector2(520, desk_y), desk_z)
	# Three comedy monitors on the desk
	# Readouts kept SHORT on purpose: the monitors are 110px apart and a readout
	# is measured from the real font, so "AI SUBSCRIPTIONS" (151px wide) ran
	# straight through both its neighbours. Same three jokes, inside the bezels.
	_add_monitor(z, Vector2(430, 300), Color(0.15, 0.85, 0.95), "TOKENS\n>>> 70", Color(0.2, 0.95, 0.9))
	_add_monitor(z, Vector2(540, 296), Color(0.95, 0.65, 0.2), "SUBS\n8 active", Color(1.0, 0.7, 0.3))
	_add_monitor(z, Vector2(650, 300), Color(0.95, 0.35, 0.35), "AI SAVED\n-€713/mo", Color(1.0, 0.45, 0.45))
	# Gaming chair, slightly askew
	var chair_z := _depth(470, 44)
	_drop_shadow(z, Vector2(560, 505), 84.0, chair_z - 1)
	_put(z, "furn_chair", Vector2(560, 470), chair_z, 1.0, Color(0.9, 0.9, 1.0))

static func _add_monitor(parent: Node2D, pos: Vector2, screen_col: Color, text: String, text_col: Color, flicker: bool = false) -> void:
	var mz := _depth(pos.y, 42)
	_put(parent, "furn_monitor", pos, mz)
	# Emissive screen: scanlined + boosted into bloom by crt_monitor. The color
	# is baked into a generated texture because the crt shader replaces vertex
	# COLOR, so a modulate/ColorRect tint would not survive it.
	var scr := Sprite2D.new()
	scr.texture = _screen_tex(screen_col)
	var crt := _shader_mat("crt_monitor", {"glow_boost": 1.4})
	if crt:
		scr.material = crt
	scr.position = pos - Vector2(0, 6)
	scr.scale = Vector2(2.0, 1.85)
	scr.z_index = mz + 1
	parent.add_child(scr)
	# Readout style "tag": outlined text, no plate (a plate would cover the screen
	# art), pinned to the monitor's own z so it travels with the prop. Without the
	# outline it washes out against its own bloomed screen.
	WorldLabel.add(parent, pos - Vector2(34, 24), text, text_col, {
		"size": 10, "style": "tag", "color": text_col,
		"z": mz + 2, "claim": false, "fade": false,
	})
	# Screen glow spill (cool cyan against the lamp's amber; the bible's duel),
	# plus the screen's own cast pooled on the desk in front of it — a monitor
	# that doesn't light the surface it stands on reads as a sticker, not a lamp.
	# mz + 50 clears both desk slabs (388 and 408) without reaching the chairs.
	_add_light(parent, pos - Vector2(0, 10), screen_col, 0.95, 1.6, flicker)
	_light_pool(parent, pos + Vector2(0, 54), 180.0, screen_col, 0.20, mz + 50)

# ------------------------------------------------------------ gpu rig -------

static func _build_gpu_rig(parent: Node2D) -> void:
	# A second workstation on the right balances the composition and fills the
	# room: a jury-rigged GPU mining/inference rig made of stacked crates.
	var z := Node2D.new()
	z.name = "GpuRig"
	parent.add_child(z)
	var desk_y := 360.0
	var desk_z := _depth(desk_y, 48)
	_drop_shadow(z, Vector2(1120, desk_y + 40), 208.0, desk_z - 1)
	_put(z, "furn_desk", Vector2(1120, desk_y), desk_z, 0.9)
	# The thermals monitor flickers with its light: 94 degrees is a lifestyle.
	_add_monitor(z, Vector2(1060, 318), Color(0.95, 0.35, 0.25), "GPU TEMP\n94\u00b0C  \ud83d\udd25", Color(1.0, 0.5, 0.35), true)
	_add_monitor(z, Vector2(1170, 320), Color(0.4, 0.9, 0.5), "npm audit\n847 vulns\n0 fixed", Color(0.5, 1.0, 0.6))
	# stacked GPU crates
	var box_z := _depth(470, 52)
	_drop_shadow(z, Vector2(1200, 512), 118.0, box_z - 1)
	_put(z, "furn_boxes", Vector2(1200, 470), box_z, 0.8, Color(0.7, 0.85, 1.0))
	var chair_z := _depth(470, 44)
	_drop_shadow(z, Vector2(1110, 505), 84.0, chair_z - 1)
	_put(z, "furn_chair", Vector2(1110, 470), chair_z, 1.0, Color(0.85, 0.85, 1.0))

# --------------------------------------------------------- server corner ----

static func _build_server_corner(parent: Node2D) -> void:
	var z := Node2D.new()
	z.name = "ServerCorner"
	parent.add_child(z)
	var rack_z := _depth(200, 84)
	_drop_shadow(z, Vector2(1470, 276), 104.0, rack_z - 1)
	_put(z, "furn_server", Vector2(1470, 200), rack_z)
	var rack2_z := _depth(220, 84)
	_drop_shadow(z, Vector2(1380, 296), 104.0, rack2_z - 1)
	_put(z, "furn_server", Vector2(1380, 220), rack2_z, 1.0, Color(0.9, 0.9, 0.95))
	# Cooling glow, humming along with the fans.
	_add_light(z, Vector2(1420, 240), Color(0.3, 0.9, 0.5), 0.7, 3.2, true)
	# Blinkenlights on both rack faces, out of phase.
	var led_cols := [Color(0.3, 1.0, 0.5), Color(1.0, 0.75, 0.25), Color(0.35, 0.9, 1.0)]
	for i in 6:
		var on_first := i < 3
		var pos := Vector2(1454.0 if on_first else 1364.0, (152.0 if on_first else 178.0) + float(i % 3) * 20.0)
		_led(z, pos, led_cols[i % 3], 0.3 + float(i) * 0.23, (rack_z if on_first else rack2_z) + 1)

# ------------------------------------------------------------- kitchen ------

static func _build_kitchen(parent: Node2D) -> void:
	var z := Node2D.new()
	z.name = "Kitchen"
	parent.add_child(z)
	var fridge_z := _depth(210, 66)
	_drop_shadow(z, Vector2(120, 272), 92.0, fridge_z - 1)
	_put(z, "furn_fridge", Vector2(120, 210), fridge_z)
	var coffee_z := _depth(230, 46)
	_drop_shadow(z, Vector2(230, 268), 66.0, coffee_z - 1)
	_put(z, "furn_coffee", Vector2(230, 230), coffee_z)
	# empty energy-drink cans on the floor — proper tins once the generator has
	# run (one near-white texture, tinted per flavour of regret); the old
	# ColorRects stay as the fallback so a fresh checkout still has its litter
	var can_cols: Array[Color] = [Color(0.2, 0.85, 0.35), Color(0.9, 0.3, 0.3), Color(0.3, 0.6, 0.95)]
	for i in 5:
		var cpos := Vector2(185 + i * 22, 308 + (i % 2) * 14)
		var col: Color = can_cols[i % 3]
		if _put(z, "int_can", cpos, _depth(cpos.y, 8), 1.0, col):
			continue
		var can := ColorRect.new()
		can.size = Vector2(10, 16)
		can.position = cpos - Vector2(5, 8)
		can.color = col
		can.z_index = _depth(can.position.y, 8)
		z.add_child(can)

# ------------------------------------------------------------- bedroom ------

static func _build_bedroom(parent: Node2D) -> void:
	var z := Node2D.new()
	z.name = "Bedroom"
	parent.add_child(z)
	var bed_z := _depth(840, 54)
	_drop_shadow(z, Vector2(1320, 888), 156.0, bed_z - 1)
	_put(z, "furn_bed", Vector2(1320, 840), bed_z)
	var shelf_z := _depth(640, 60)
	_drop_shadow(z, Vector2(1500, 694), 96.0, shelf_z - 1)
	_put(z, "furn_shelf", Vector2(1500, 640), shelf_z)
	var plant_z := _depth(800, 48)
	_drop_shadow(z, Vector2(110, 842), 64.0, plant_z - 1)
	_put(z, "furn_plant", Vector2(110, 800), plant_z)

# ------------------------------------------------------------- clutter ------

static func _build_clutter(parent: Node2D) -> void:
	var z := Node2D.new()
	z.name = "Clutter"
	parent.add_child(z)
	var boxes_z := _depth(850, 52)
	_drop_shadow(z, Vector2(210, 894), 130.0, boxes_z - 1)
	_put(z, "furn_boxes", Vector2(210, 850), boxes_z)
	var boxes2_z := _depth(900, 52)
	_drop_shadow(z, Vector2(300, 932), 96.0, boxes2_z - 1)
	_put(z, "furn_boxes", Vector2(300, 900), boxes2_z, 0.7)
	# Pizza-box strata, beside the sign that calls it archaeology: a leaning
	# tower of closed boxes (deeper layers greasier) plus one open single with
	# the last slice preserved in situ. The flat rects stay as the fallback.
	if _put(z, "int_pizza_stack", Vector2(905, 812), _depth(812.0, 27.0)):
		_put(z, "int_pizza_box", Vector2(723, 896), _depth(896.0, 16.0))
	else:
		for p: Vector2 in [Vector2(880, 800), Vector2(930, 820), Vector2(700, 880)]:
			var box := ColorRect.new()
			box.size = Vector2(46, 40)
			box.position = p
			box.color = Color(0.7, 0.5, 0.25)
			box.z_index = _depth(p.y, 20)
			z.add_child(box)
	# A sad couch nobody sleeps on (textured when generated; rect fallback)
	_couch(z, Vector2(760, 760))
	# Dinner, and the drum the cable spaghetti was cut from. Both exists()-guarded
	# by _put, so a missing generator pass just skips them.
	var cup_z := _depth(838.0, 22.0)
	_drop_shadow(z, Vector2(626, 856), 34.0, cup_z - 1, 0.26)
	_put(z, "dress_noodle_cup", Vector2(626, 838), cup_z)
	var spool_z := _depth(300.0, 42.0)
	_drop_shadow(z, Vector2(1462, 336), 84.0, spool_z - 1, 0.30)
	_put(z, "dress_cable_spool", Vector2(1462, 300), spool_z, 0.85, Color(0.86, 0.88, 0.96))
	# Cable spaghetti from the battlestation to the server corner
	_cable(z, [Vector2(520, 400), Vector2(700, 430), Vector2(950, 380), Vector2(1300, 300)], Color(0.1, 0.1, 0.12))
	_cable(z, [Vector2(1120, 430), Vector2(1250, 380), Vector2(1400, 320)], Color(0.12, 0.11, 0.13))
	_cable(z, [Vector2(300, 300), Vector2(360, 420), Vector2(430, 470)], Color(0.09, 0.09, 0.11))
	# Catch-lights where the bundles pass under a lamp or screen — cheap
	# specular sells "vinyl-wrapped cable" better than any extra geometry.
	_catch_light(z, Vector2(700, 430), Color(0.2, 0.9, 0.85))
	_catch_light(z, Vector2(950, 380), Color(1.0, 0.75, 0.4))
	_catch_light(z, Vector2(1250, 380), Color(0.95, 0.4, 0.3))
	_catch_light(z, Vector2(360, 420), Color(1.0, 0.72, 0.4))
	# The strip every one of those cables was always heading for: six sockets,
	# more wall-warts than sockets, one confidently red LED. It lies mid-room so
	# the player literally steps over the infrastructure, and two more looms
	# converge on it from both desks (extra cables only when the strip exists,
	# so no run ever ends at empty floor).
	if _put(z, "int_power_strip", Vector2(706, 436), -76):
		_cable(z, [Vector2(1120, 430), Vector2(960, 466), Vector2(812, 452), Vector2(716, 438)], Color(0.11, 0.10, 0.13))
		_cable(z, [Vector2(696, 436), Vector2(602, 452), Vector2(508, 438), Vector2(452, 458)], Color(0.10, 0.11, 0.14))
		_catch_light(z, Vector2(960, 466), Color(1.0, 0.62, 0.35))
		_catch_light(z, Vector2(602, 452), Color(0.22, 0.9, 0.85))
	# Sticky notes along both desk fronts. Estimates. All of them say TODO.
	_put(z, "int_sticky_strip", Vector2(476, 349), _depth(340.0, 48.0) + 1)
	_put(z, "int_sticky_strip", Vector2(1086, 372), _depth(360.0, 48.0) + 1, 0.8)
	# Wall posters (side walls) for depth + jokes
	_poster(z, Vector2(30, 420), Color(0.2, 0.3, 0.5), "IT\nWORKS\nLOCALLY", Color(0.4, 0.65, 1.0))
	_poster(z, Vector2(30, 620), Color(0.4, 0.2, 0.3), "MOVE\nFAST", Color(1.0, 0.35, 0.5))
	# SHIP OR DIE used to hang at y=500 — i.e. directly behind the portal's vortex,
	# where its own ideology was permanently eclipsed by the way out. Moved up the
	# right wall into clear air between the server racks and the doorway glow.
	_poster(z, Vector2(ROOM_W * TILE - 62, 300), Color(0.25, 0.4, 0.35), "SHIP\nOR\nDIE", Color(0.3, 1.0, 0.6))

static func _couch(parent: Node2D, pos: Vector2) -> void:
	var z := _depth(pos.y, 34)
	_drop_shadow(parent, pos + Vector2(0, 44), 180.0, z - 1)
	# Real upholstery once the generator has run — the old rect couch was the
	# darkest object in the most-seen square metre of the game. Rects remain
	# as the fallback below.
	if _put(parent, "int_couch", pos + Vector2(0, 4), z):
		return
	var base := Color(0.22, 0.2, 0.3)
	var body := ColorRect.new()
	body.size = Vector2(150, 60)
	body.position = pos - Vector2(75, 20)
	body.color = base
	body.z_index = z
	parent.add_child(body)
	for i in 3:
		var cushion := ColorRect.new()
		cushion.size = Vector2(44, 30)
		cushion.position = pos - Vector2(72 - i * 48, 14)
		cushion.color = base.lightened(0.08)
		cushion.z_index = z + 1
		parent.add_child(cushion)
	# a discarded blanket
	var bl := ColorRect.new()
	bl.size = Vector2(50, 24)
	bl.position = pos - Vector2(10, 6)
	bl.color = Color(0.5, 0.3, 0.35)
	bl.z_index = z + 2
	parent.add_child(bl)

## Resample an authored polyline into a SLACK cable: Catmull-Rom through the
## anchors so the corners round off instead of kinking, plus a gravity droop that
## is zero at every anchor and peaks mid-span — a cable is pinned where it is
## clipped and lazy everywhere else.
##
## The round-5 frames are the reason this exists. The runs were 4px pure-black
## straight polylines: no sag, no highlight, no endpoints, uniform width. At game
## zoom they did not read as cable at all, they read as stray primitives ruled
## across the floor. `sag` is the droop at a 180px span and scales with the span,
## so a short jumper between two desks stays taut and a haul to the server corner
## dips.
static func _cable_path(points: Array, sag: float) -> PackedVector2Array:
	var src: Array[Vector2] = []
	for p: Vector2 in points:
		src.append(p)
	var out := PackedVector2Array()
	if src.size() < 2:
		for q: Vector2 in src:
			out.append(q)
		return out
	var steps := 7
	for i in src.size() - 1:
		var p0: Vector2 = src[maxi(i - 1, 0)]
		var p1: Vector2 = src[i]
		var p2: Vector2 = src[i + 1]
		var p3: Vector2 = src[mini(i + 2, src.size() - 1)]
		var droop := sag * clampf(p1.distance_to(p2) / 180.0, 0.30, 1.35)
		for s in steps:
			var t := float(s) / float(steps)
			var pt: Vector2 = p1.cubic_interpolate(p2, p0, p3, t)
			out.append(pt + Vector2(0.0, sin(PI * t) * droop))
	out.append(src[src.size() - 1])
	return out

## One pass of a cable run. Rounded caps as well as rounded joints: a square cap
## on a 4px line is a visible chisel end, and half of what made these read as
## drawn-on rather than laid-down.
static func _cable_line(parent: Node2D, path: PackedVector2Array, width: float, col: Color, z: int, offset: Vector2 = Vector2.ZERO) -> void:
	if path.size() < 2:
		return
	var line := Line2D.new()
	line.width = width
	line.default_color = col
	line.z_index = z
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	for p: Vector2 in path:
		line.add_point(p + offset)
	parent.add_child(line)

## The fixture a run is actually screwed down to: a shadowed plate, a lit top
## edge and two screw heads. Every cable now ENDS in one, so a bundle terminates
## at hardware instead of simply stopping in mid-floor with no explanation.
static func _cable_clip(parent: Node2D, pos: Vector2, z: int) -> void:
	_rect(parent, pos + Vector2(1.0, 2.0), Vector2(14.0, 9.0), Color(0.0, 0.0, 0.0, 0.30), z - 1)
	_rect(parent, pos, Vector2(13.0, 8.0), Color(0.06, 0.06, 0.09, 0.96), z)
	_rect(parent, pos - Vector2(0.0, 3.5), Vector2(13.0, 1.0), Color(1.0, 0.80, 0.52, 0.30), z + 1)
	for k: float in [-1.0, 1.0]:
		_rect(parent, pos + Vector2(k * 4.5, 0.5), Vector2(2.0, 2.0), Color(0.58, 0.62, 0.74, 0.68), z + 1)

## A tie-wrap at an interior anchor — the reason the run turns there. Drawn
## ACROSS the bundle, on the bearing of the two anchors either side of it, with
## the same top-left key light as the clips.
##
## Two things went wrong in the round-5 frames and the sag curve only fixes one
## of them. The other is that a run held the same 4px stroke for seven hundred
## units and changed direction for no visible reason: nothing in the picture said
## why the bundle bent at (360,420). A tie is the cheapest possible answer, and
## it breaks the uniform stroke at exactly the places the eye already stops.
static func _cable_tie(parent: Node2D, pos: Vector2, ang: float) -> void:
	# _rect's long axis is its local +Y, which rotation carries to
	# (-sin r, cos r); that is perpendicular to a run bearing `ang` exactly when
	# r == ang. (Adding a right angle here — the obvious-looking thing — lays the
	# tie ALONG the bundle instead of across it, which just reads as a bright
	# dash in the middle of the cable.)
	_rect(parent, pos, Vector2(3.0, 9.0), Color(0.05, 0.05, 0.08, 0.92), CABLE_Z + 1, ang)
	_rect(parent, pos - Vector2(0.6, 0.9), Vector2(1.0, 9.0), Color(1.0, 0.82, 0.55, 0.26), CABLE_Z + 1, ang)

## A cable run with the craft the frames were missing: a contact shadow beneath
## it, the bundle itself, a warm specular along the top-left edge (the bible's
## light direction, consistent with every other surface in the room), a tie at
## every corner and a screwed-down clip at each end — all drawn as one slack
## curve.
##
## The specular is doing most of the work. A black line with a warm rim reads as
## vinyl sheathing catching the lamp; the same line without one reads as a hole.
## It is 1.6 units wide rather than 1: the room is played at ~1.16x zoom, and a
## 1-unit rim at 0.5 alpha over near-black is a sub-pixel that the capture proved
## invisible — which is the same as not having drawn it. It is still dimmer than
## the floorboards it lies on, so the cables gain craft without gaining weight
## they have not earned; set dressing must never out-shout the wayfinding.
static func _cable(parent: Node2D, points: Array, color: Color, sag: float = 9.0) -> void:
	var path := _cable_path(points, sag)
	if path.size() < 2:
		return
	# Contact shadow, offset down-and-right because the key light is up-and-left.
	_cable_line(parent, path, 6.0, Color(0.0, 0.0, 0.0, 0.32), CABLE_Z - 2, Vector2(2.0, 3.0))
	_cable_line(parent, path, 4.0, Color(color.r, color.g, color.b, 1.0), CABLE_Z)
	var lit := color.lerp(Color(1.0, 0.82, 0.55), 0.46)
	_cable_line(parent, path, 1.6, Color(lit.r, lit.g, lit.b, 0.6), CABLE_Z + 1, Vector2(-1.0, -1.5))
	_cable_clip(parent, path[0], CABLE_Z)
	_cable_clip(parent, path[path.size() - 1], CABLE_Z)
	# Interior AUTHORED anchors only: the spline's resampled points are not
	# corners, and the two endpoints already carry a clip.
	for i in maxi(points.size() - 2, 0):
		var before: Vector2 = points[i]
		var corner: Vector2 = points[i + 1]
		var after: Vector2 = points[i + 2]
		_cable_tie(parent, corner, (after - before).angle())

static func _poster(parent: Node2D, pos: Vector2, color: Color, text: String, glow_col: Color = Color(0.5, 0.7, 1.0)) -> void:
	# Additive halo behind the frame: the poster's ideology, radiating gently.
	var halo := ColorRect.new()
	halo.size = Vector2(52, 68)
	halo.position = pos - Vector2(4, 4)
	halo.color = Color(glow_col.r, glow_col.g, glow_col.b, 0.16)
	halo.material = _additive_mat()
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	halo.z_index = -53
	parent.add_child(halo)
	# Printed poster art (generated, bright greyscale) tinted toward the creed's
	# accent; the flat ColorRect remains the ungenerated-checkout fallback.
	if not _put(parent, "int_poster", pos + Vector2(22, 30), -52, 1.0,
			Color(minf(color.r + 0.45, 1.0), minf(color.g + 0.45, 1.0), minf(color.b + 0.45, 1.0))):
		var frame := ColorRect.new()
		frame.size = Vector2(44, 60)
		frame.position = pos
		frame.color = color
		frame.z_index = -52
		parent.add_child(frame)
	# Printed matter: no plate (the frame IS the plate), no float, no fade, and
	# the poster's own z so it stays flat on the wall.
	WorldLabel.add(parent, pos + Vector2(5, 6), text, glow_col, {
		"size": 10, "style": "plaque", "color": Color(0.95, 0.95, 1.0), "z": -51,
	})

# ------------------------------------------------------------ lighting ------

## Hero lighting pass. This room is the player's first three seconds with the
## game, so it gets the full treatment: warm amber key from the one lamp this
## person owns, cool cyan monitor spill fighting it across the desk, a pool of
## 3AM city light under the window, and small accents everywhere something hums.
static func _build_lighting(parent: Node2D) -> void:
	var z := Node2D.new()
	z.name = "Lighting"
	parent.add_child(z)
	# Warm amber key, breathing slightly (cheap bulb, obviously). The pool is what
	# makes it read as a lamp lighting a floor rather than a bright dot.
	_add_light(z, Vector2(300, 250), Color(1.0, 0.72, 0.4), 0.9, 5.0, true)
	_light_pool(z, Vector2(300, 320), 520.0, Color(1.0, 0.74, 0.42), 0.2)
	# Cool cyan spill unifying the battlestation's three screens.
	_add_light(z, Vector2(545, 335), Color(0.14, 0.94, 0.86), 0.55, 3.2)
	_light_pool(z, Vector2(545, 404), 400.0, Color(0.2, 0.9, 0.86), 0.18)
	# City light through the big window, washing the boards under the glass —
	# sized to the hero window's full span so the skyline reads as a SOURCE.
	_add_light(z, Vector2(545, 170), Color(0.48, 0.64, 1.0), 0.85, 4.2)
	var pool := Sprite2D.new()
	pool.texture = _light_tex()
	pool.material = _additive_mat()
	pool.position = Vector2(545, 322)
	var ptw := maxf(1.0, float(pool.texture.get_width()))
	pool.scale = Vector2(500.0 / ptw, 230.0 / ptw)
	pool.modulate = Color(0.52, 0.68, 1.0, 0.30)
	pool.z_index = -87
	z.add_child(pool)
	# Kitchen counter warmth: the fridge glow of a balanced diet.
	_add_light(z, Vector2(175, 205), Color(1.0, 0.7, 0.35), 0.6, 2.4)
	_light_pool(z, Vector2(180, 288), 300.0, Color(1.0, 0.72, 0.36), 0.2)
	# The unslept bed, lit cool and judgmental.
	_add_light(z, Vector2(1320, 795), Color(0.55, 0.62, 0.95), 0.35, 2.8)
	_light_pool(z, Vector2(1320, 872), 340.0, Color(0.55, 0.62, 0.95), 0.16)
	# The GPU rig's own thermal glow, pooling under the second desk.
	_light_pool(z, Vector2(1120, 430), 360.0, Color(1.0, 0.5, 0.32), 0.16)
	# Warm lamplight pooled AROUND both work zones. The round-3 frames put the
	# desks as silhouettes on a silhouette floor; furniture only reads at this
	# exposure when there is light behind and beside it, not just on top of it.
	_light_pool(z, Vector2(545, 468), 540.0, Color(1.0, 0.74, 0.44), 0.15)
	_light_pool(z, Vector2(1118, 498), 460.0, Color(1.0, 0.68, 0.40), 0.13)
	# The server corner exhales green onto the boards.
	_light_pool(z, Vector2(1424, 300), 300.0, Color(0.32, 0.95, 0.55), 0.16)
	# SHIP OR DIE poster insists, in magenta (follows the poster up the wall).
	_add_light(z, Vector2(1548, 328), Color("#FF2D95"), 0.4, 1.9)
	_light_pool(z, Vector2(1520, 358), 240.0, Color("#FF2D95"), 0.16)
	# Exit-door neon: acid green, aimed at the Dependency District.
	var tube := Sprite2D.new()
	tube.texture = _neon_tex(Color("#A8FF3E"))
	var nmat := _shader_mat("neon_flicker", {"seed": 7.7, "base_boost": 1.6})
	if nmat:
		tube.material = nmat
	tube.position = Vector2(1402, 368)
	tube.scale = Vector2(2.2, 1.5)
	# A ceiling fixture, so it belongs with the world text rather than with the
	# furniture — at z 399 the bed and the boxes were drawing over the one light
	# that says "the door is this way".
	tube.z_index = WorldLabel.Z_PLATE - 1
	z.add_child(tube)
	_add_light(z, Vector2(1402, 374), Color("#A8FF3E"), 0.55, 2.0)
	# The doorway itself throws light across the last third of the room, so the
	# way out is the brightest thing on the right-hand side of the frame.
	_light_pool(z, Vector2(1490, 520), 460.0, Color("#A8FF3E"), 0.2)

## A warm puddle under everything worth walking to. The player complaint was not
## "which key do I press", it was "I don't know WHERE" — lit things read as
## destinations from across the room, unlit things read as furniture.
static func _build_poi_pools(parent: Node2D) -> void:
	var z := Node2D.new()
	z.name = "PoiPools"
	parent.add_child(z)
	# Claude, standing in the one honest spotlight in the apartment.
	_add_light(z, Vector2(820, 552), Color(1.0, 0.87, 0.62), 0.55, 2.0)
	_light_pool(z, Vector2(820, 586), 240.0, Color(1.0, 0.85, 0.58), 0.32)
	for i in 12:
		var a := TAU * float(i) / 12.0
		_rect(z, Vector2(820, 584) + Vector2(cos(a) * 64.0, sin(a) * 40.0), Vector2(9, 3), Color(1.0, 0.86, 0.6, 0.16), -92, a)
	# The things you can actually DO, each with its own colour of invitation.
	_light_pool(z, Vector2(430, 384), 150.0, Color(0.4, 0.8, 1.0), 0.24)     # client email
	_light_pool(z, Vector2(650, 384), 150.0, Color(0.3, 0.95, 0.9), 0.24)    # dream app terminal
	_light_pool(z, Vector2(760, 404), 150.0, Color(1.0, 0.6, 0.3), 0.24)     # deploy button
	_light_pool(z, Vector2(1160, 644), 170.0, Color(0.35, 0.95, 0.45), 0.26) # 'free' tokens ad
	_light_pool(z, Vector2(300, 584), 170.0, Color(0.62, 0.5, 0.98), 0.26)   # agent terminal
	_light_pool(z, Vector2(1120, 674), 170.0, Color(1.0, 0.33, 0.28), 0.26)  # the outage

## Foreground/mid-ground framing. A ceiling beam and skirting board at the very
## edges of the room turn a top-down field into a space you are looking INTO —
## and neither sits anywhere the player can stand.
static func _build_framing(parent: Node2D) -> void:
	var z := Node2D.new()
	z.name = "Framing"
	parent.add_child(z)
	var w := ROOM_W * TILE
	var h := ROOM_H * TILE
	_rect(z, Vector2(w * 0.5, 26.0), Vector2(w + 40.0, 26.0), Color(0.02, 0.02, 0.04, 0.94), 500)
	_rect(z, Vector2(w * 0.5, 39.0), Vector2(w + 40.0, 2.0), Color(1.0, 0.78, 0.45, 0.14), 501)
	for i in 5:
		var bx := 180.0 + float(i) * (w - 360.0) / 4.0
		_rect(z, Vector2(bx, 34.0), Vector2(12, 40), Color(0.02, 0.02, 0.04, 0.9), 500)
	# Slack cable looping down out of the ceiling. This flat has opinions about
	# cable management, and they are all wrong. Same treatment as the floor runs —
	# smoothed curve, warm specular along the lit edge, a mount plate at each end
	# — because at 3px of flat black with bare ends these read as scratches on
	# the lens rather than as something hanging off a ceiling. (The plates sit
	# where the cable ends, NOT on the joists above: the beams land on 180/490/
	# 800/1110/1420 and only one of the four ends is near one. A surface-mounted
	# clip between joists is what a flat like this actually has, and claiming
	# otherwise in a comment is how the next agent moves the wrong thing.)
	# No contact shadow: they are in mid-air, with nothing under them to cast on.
	for i in 2:
		var x0 := 420.0 + float(i) * 640.0
		var head := Vector2(x0 - 110.0, 38.0)
		var tail := Vector2(x0 + 70.0, 44.0)
		var drop := _cable_path([head, Vector2(x0 - 30.0, 92.0 + float(i) * 22.0), tail], 4.0)
		_cable_line(z, drop, 3.0, Color(0.02, 0.02, 0.03, 0.9), 502)
		# 1.4, not 1.0, for the reason spelled out in _cable: at this zoom a
		# 1-unit rim is a sub-pixel and does not survive the capture.
		_cable_line(z, drop, 1.4, Color(0.40, 0.34, 0.26, 0.5), 503, Vector2(-1.0, -1.0))
		for e: Vector2 in [head, tail]:
			_rect(z, e, Vector2(11.0, 5.0), Color(0.015, 0.015, 0.03, 0.95), 503)
			_rect(z, e - Vector2(0.0, 2.0), Vector2(11.0, 1.0), Color(1.0, 0.80, 0.50, 0.22), 504)
	# In-world vignette: darkness pooled into the corners IN FRONT of the
	# furniture, so the flat closes in around the desk instead of ending at a
	# wall. Four sprites; the single cheapest "this is a photograph" trick there
	# is at this resolution.
	for c: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		_floor_patch(z, Vector2(c.x * w, 70.0 + c.y * (h - 70.0)), 560.0, Color(0.008, 0.008, 0.02), 0.38, 520)
	# Door jambs down both sides: the flat is looked INTO, through its own frame.
	for k: float in [0.0, 1.0]:
		_rect(z, Vector2(k * w + (1.0 - k * 2.0) * 9.0, h * 0.5), Vector2(30.0, h), Color(0.012, 0.012, 0.026, 0.8), 540)
	# Skirting board along the near edge of the room.
	_rect(z, Vector2(w * 0.5, h - 6.0), Vector2(w + 40.0, 24.0), Color(0.015, 0.015, 0.03, 0.92), 600)
	_rect(z, Vector2(w * 0.5, h - 18.0), Vector2(w + 40.0, 2.0), Color(1.0, 0.8, 0.5, 0.1), 601)

# ---------------------------------------------------------- atmosphere ------

## Particles (3 emitters, well under the bible's 12): dust motes for the light
## shafts, steam for the coffee machine, exhaust shimmer for the server corner.
static func _build_atmosphere(parent: Node2D) -> void:
	var dot := _glow_dot()
	# Foreground dust motes — invisible until they drift through a light.
	var dust := CPUParticles2D.new()
	dust.name = "DustMotes"
	dust.position = Vector2(ROOM_W * TILE * 0.5, ROOM_H * TILE * 0.5)
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	dust.emission_rect_extents = Vector2(ROOM_W * TILE * 0.5 - 60, ROOM_H * TILE * 0.5 - 60)
	dust.z_index = 350
	dust.amount = 26
	dust.lifetime = 8.0
	dust.gravity = Vector2(0, -4)
	dust.initial_velocity_min = 2.0
	dust.initial_velocity_max = 8.0
	dust.spread = 180.0
	dust.scale_amount_min = 1.2
	dust.scale_amount_max = 2.2
	dust.color = Color(1.0, 0.9, 0.75, 0.16)
	if dot:
		dust.texture = dot
	parent.add_child(dust)
	# Coffee steam. Load-bearing appliance, gets its own emitter.
	var steam := CPUParticles2D.new()
	steam.name = "CoffeeSteam"
	steam.position = Vector2(230, 198)
	steam.z_index = 300
	steam.amount = 8
	steam.lifetime = 2.0
	steam.direction = Vector2(0, -1)
	steam.spread = 12.0
	steam.gravity = Vector2(0, -8)
	steam.initial_velocity_min = 10.0
	steam.initial_velocity_max = 18.0
	steam.scale_amount_min = 1.6
	steam.scale_amount_max = 3.0
	steam.color = Color(0.95, 0.97, 1.0, 0.3)
	if dot:
		steam.texture = dot
	parent.add_child(steam)
	# Server exhaust shimmer: the racks exhale so their owner doesn't have to.
	var vent := CPUParticles2D.new()
	vent.name = "ServerExhaust"
	vent.position = Vector2(1425, 130)
	vent.z_index = 300
	vent.amount = 9
	vent.lifetime = 1.6
	vent.direction = Vector2(0, -1)
	vent.spread = 20.0
	vent.gravity = Vector2(0, -12)
	vent.initial_velocity_min = 14.0
	vent.initial_velocity_max = 26.0
	vent.scale_amount_min = 1.4
	vent.scale_amount_max = 2.6
	vent.color = Color(0.5, 1.0, 0.6, 0.18)
	if dot:
		vent.texture = dot
	parent.add_child(vent)

# -------------------------------------------------------------- signs -------

## Signs are placed in priority order: the ones that answer "what do I do and
## where" go down FIRST at priority 3 and get the good spot; furniture stories
## follow at 2; flavour gags settle around them at 1 and yield (or hide) when the
## room runs out of clear wall.
static func _build_signs(parent: Node2D) -> void:
	var z := Node2D.new()
	z.name = "Signs"
	parent.add_child(z)
	# 1. Wayfinding. EXIT used to sit on the portal's own destination plate \u2014
	# it is now mounted well clear of the doorway, up the wall where an exit sign
	# actually lives, and it is the only headline-weight sign on this side.
	_sign(z, Vector2(1276, 356), "EXIT \u2192", Color(0.5, 0.95, 0.8), 3, "headline")
	# The opening caption, and the one the QA frame caught being drawn through the
	# player's chest.
	#
	# The trap: a WorldLabel anchor is the plate's TOP-LEFT, not its centre. This
	# sign was authored at (636,598), which measures out — checked against the
	# capture, where the accent bar lands at world x 636 to the pixel — as a
	# ~190x36 plate occupying 636..826 x 598..634, straight across the player,
	# who occupies 674..766 x 556..666 at the (720,640) spawn. And because a
	# headline is _bolted, world_label's player-clearance pass has no slide
	# available and fades it to nothing instead: the one caption that answers
	# "what do I do next" was being DELETED at the exact moment it was needed.
	# Silence, not merely clutter.
	#
	# It now sits on Claude's FAR side, clear of the spawn footprint, the walk
	# lane, Claude's silhouette and his bark column (all reserved in
	# _reserve_labels; every margin >= 14 units against the 6-unit collider
	# grow), so it takes its home slot and stays lit while the player reads it.
	# The arrow turns round to keep pointing at its subject: Claude is the next
	# thing to the left, about thirty units from the plate edge, under his own
	# name plate and his own quest marker. Further right it would still be clear,
	# and would stop reading as HIS caption.
	_sign(z, Vector2(886, 520), "\u2190 talk to Claude first", Color(1.0, 0.85, 0.55), 3, "headline")
	_sign(z, Vector2(1090, 585), "'FREE' TOKENS \u2192", Color(0.4, 0.95, 0.5), 3)
	_sign(z, Vector2(250, 525), "\u2190 deploy an AI agent\n(what could go wrong)", Color(0.7, 0.6, 0.95), 3)
	_sign(z, Vector2(1050, 690), "/checkout is DOWN \u2192", Color(1.0, 0.4, 0.35), 3)
	_sign(z, Vector2(600, 424), "\u2191 Dream App terminal\n\u2191 Deploy button (be brave)", Color(0.3, 0.95, 0.9), 3)
	# 2. Furniture that has a story.
	_sign(z, Vector2(1360, 120), "SERVER RACK\n(do NOT reboot)", Color(0.5, 1.0, 0.6), 2)
	_sign(z, Vector2(70, 150), "FRIDGE\n(energy drinks only)", Color(0.6, 0.9, 1.0), 2)
	_sign(z, Vector2(200, 200), "COFFEE: MISSION CRITICAL", Color(1.0, 0.78, 0.4), 2)
	_sign(z, Vector2(90, 760), "PLANT\nstatus: deprecated", Color(0.6, 0.8, 0.5), 2)
	_sign(z, Vector2(150, 900), "node_modules\n(trash)", Color(0.7, 0.6, 0.5), 2)
	_sign(z, Vector2(1236, 936), "BED\n'sleep? during a hackathon?'", Color(0.7, 0.75, 0.95), 2)
	_sign(z, Vector2(880, 120), "DNS\nProbably not the problem.", Color(0.55, 0.85, 1.0), 2)
	# 3. Flavour. Dry, true, and placed last so they yield to everything above.
	_sign(z, Vector2(660, 916), "COUCH\nslept on: 0 nights\nsat on: 0 nights", Color(0.66, 0.62, 0.8))
	_sign(z, Vector2(846, 848), "PIZZA ARCHAEOLOGY\nstrata: Tuesday, Tuesday, Sunday", Color(0.85, 0.66, 0.4))
	_sign(z, Vector2(470, 172), "WINDOW\nOutside: still there. Allegedly.", Color(0.5, 0.7, 1.0))
	_sign(z, Vector2(1024, 250), "RIG\n\"it's a business expense\"", Color(1.0, 0.55, 0.35))

static func _sign(parent: Node2D, pos: Vector2, text: String, color: Color, prio: int = 1, style: String = "plate") -> void:
	WorldLabel.add(parent, pos, text, color, {"size": 12, "style": style, "priority": prio})

# ------------------------------------------------------------ gameplay ------

static func _populate_gameplay(parent: Node2D, spawn: Vector2) -> void:
	var tokens := Node2D.new()
	tokens.name = "Tokens"
	parent.add_child(tokens)
	var enemies := Node2D.new()
	enemies.name = "Enemies"
	parent.add_child(enemies)
	var npcs := Node2D.new()
	npcs.name = "NPCs"
	parent.add_child(npcs)
	var portals := Node2D.new()
	portals.name = "Portals"
	parent.add_child(portals)
	var props := Node2D.new()
	props.name = "Interactables"
	parent.add_child(props)

	var token_scene := preload("res://scenes/world/token_pickup.tscn")
	var token_types := ["common", "common", "cached", "common", "cached"]
	var token_positions := [
		Vector2(420, 640), Vector2(560, 700), Vector2(700, 760),
		Vector2(840, 640), Vector2(980, 700), Vector2(1120, 620),
		Vector2(500, 560), Vector2(760, 520), Vector2(1040, 500),
		Vector2(640, 860), Vector2(900, 900), Vector2(1180, 800),
		Vector2(380, 720), Vector2(1000, 860),
	]
	for i in token_positions.size():
		var t = token_scene.instantiate()
		t.token_type = token_types[i % token_types.size()]
		t.position = token_positions[i]
		tokens.add_child(t)

	# Keep the opening gentle: bugs live on the FAR-RIGHT (toward the exit), away
	# from the spawn (720,640), Claude (820,560) and the token-collection path, so
	# a new player can explore/collect/talk before combat is encountered by heading
	# for the door. (Respawns return to the spawn point, never into this cluster.)
	var enemy_scene := preload("res://scenes/combat/enemy.tscn")
	for pos: Vector2 in [Vector2(1360, 540), Vector2(1440, 760)]:
		var en = enemy_scene.instantiate()
		en.enemy_type = "bug"
		en.max_hp = 20
		en.position = pos
		enemies.add_child(en)

	var npc_scene := preload("res://scenes/world/npc.tscn")
	var claude = npc_scene.instantiate()
	claude.npc_id = "roommate_ai"
	var claude_quests: Array[String] = ["hello_localhost", "tiny_change", "ship_dream_app"]
	claude.quest_ids = claude_quests
	claude.position = Vector2(820, 560)
	npcs.add_child(claude)

	var interact_scene := preload("res://scenes/world/generic_interactable.tscn")
	var email := _add_interact(props, interact_scene, "client_email", Vector2(430, 360), "Check client email")
	email.one_shot = false  # re-checkable inbox running gag
	_add_interact(props, interact_scene, "dream_app_terminal", Vector2(650, 360), "Dream App Terminal")
	_add_interact(props, interact_scene, "deploy_button", Vector2(760, 380), "Deploy To Production")
	# Comedy storyline triggers (repeatable), color-coded and signposted.
	var ad := _add_interact(props, interact_scene, "free_tokens_ad", Vector2(1160, 620), "Suspicious pop-up ad")
	ad.one_shot = false
	_tint(ad, Color(0.3, 0.9, 0.4))
	var agent := _add_interact(props, interact_scene, "agent_terminal", Vector2(300, 560), "Autonomous Agent terminal")
	agent.one_shot = false
	_tint(agent, Color(0.6, 0.5, 0.95))
	var svc := _add_interact(props, interact_scene, "broken_service", Vector2(1120, 650), "Investigate the outage")
	svc.one_shot = false
	_tint(svc, Color(0.95, 0.3, 0.25))

	# Environmental comedy props: readable flavor on the furniture, rewarding
	# exploration. Subtle markers; the floating [E] prompt does the pointing.
	var flavor := {
		"prop_fridge": [Vector2(150, 275), "Fridge"],
		"prop_coffee": [Vector2(245, 288), "Coffee machine"],
		"prop_plant": [Vector2(135, 852), "Deprecated plant"],
		"prop_bed": [Vector2(1300, 772), "Bed"],
		"prop_server": [Vector2(1452, 272), "Server rack"],
		"prop_whiteboard": [Vector2(950, 138), "Whiteboard"],
		"prop_terminal": [Vector2(1120, 416), "Terminal"],
		"prop_router": [Vector2(1352, 300), "Router"],
		"prop_monitors": [Vector2(600, 300), "Battlestation monitors"],
		"prop_sticker": [Vector2(470, 430), "Sticker-covered laptop"],
	}
	for id in flavor:
		var pr := _add_interact(props, interact_scene, id, flavor[id][0], flavor[id][1])
		pr.one_shot = false
		_dim(pr)

	if GameManager.is_region_unlocked("dependency_district"):
		var portal_scene := preload("res://scenes/world/region_portal.tscn")
		var p = portal_scene.instantiate()
		p.target_region = "dependency_district"
		p.portal_label = "Dependency District"
		p.position = PORTAL_POS
		portals.add_child(p)
		# Arcane spill so the way out reads as a light source across the room.
		_add_light(props, p.position + Vector2(0, -8), Color("#8B5CF6"), 1.0, 3.2)

static func _add_interact(parent: Node2D, scene: PackedScene, id: String, pos: Vector2, text: String) -> Node:
	var node = scene.instantiate()
	node.interact_id = id
	node.interact_text = text
	node.position = pos
	parent.add_child(node)
	return node

## Subtle marker for flavor props: a small dim glyph that blends with the
## furniture (the floating [E] prompt is the real affordance on approach).
static func _dim(interactable: Node) -> void:
	var rect := interactable.get_node_or_null("ColorRect")
	if rect:
		rect.color = Color(0.42, 0.82, 0.88, 0.30)
		rect.offset_left = -7.0
		rect.offset_top = -7.0
		rect.offset_right = 7.0
		rect.offset_bottom = 7.0

static func _tint(interactable: Node, color: Color) -> void:
	var rect := interactable.get_node_or_null("ColorRect")
	if rect:
		rect.color = Color(color.r, color.g, color.b, 0.85)
