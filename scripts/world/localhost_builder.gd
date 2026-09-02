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
static var _screen_cache: Dictionary = {}
static var _mat_cache: Dictionary = {}
static var _add_mat_cache: CanvasItemMaterial

## Where the portal to the Dependency District stands. The EXIT sign, the exit
## neon and the reserved label boxes all key off this one constant so they can
## never drift apart again (they had: the EXIT sign used to draw straight
## through the portal's own destination plate).
##
## ROUND 8, critique #9: it stood at x 1510, 90 units off a 1600-wide room, and
## region_portal.gd centres its own destination label on the portal with the text
## overflowing a 160-unit box — so "→ Dependency District" ran off the right edge
## of the world and the frame caught it as "→ Depen".
##
## ROUND 10: 170 units in cleared the WALL but not the CAMERA. The room is 1600
## wide and the view is ~1490, so at the spawn the camera is clamped hard left
## and the right-hand edge of the frame lands around x 1490 — with the door at
## 1430 its two-line destination plate was cut in half by the viewport instead of
## by the masonry ("→ Dependency / District"). 80 units further in puts the whole
## plate, at its widest, inside the first frame the player ever sees.
const PORTAL_POS := Vector2(ROOM_W * TILE - 250, ROOM_H * TILE * 0.5)

## VISUAL_BIBLE_V2 LAW 2, the localhost row: BASE #0E0C14, ACCENT #24F0DC cyan,
## WARM #FFB74A amber. Three hues, and the round-6 apartment had eleven — five
## monitor colours, three LED colours, three poster creeds, six point-of-interest
## pools, a magenta poster light and an acid-green exit tube. Everything that is
## not the cyan of a screen or the amber of the one lamp this person owns is now
## drawn in neutral greys.
const ACCENT := Color("#24F0DC")
const WARM := Color("#FFB74A")
const TEXT_DIM := Color("#7C8BB0")

## LAW 4: at most six PointLight2Ds alive at once. This room used to carry
## sixteen — one per monitor, one per appliance, one per poster. Reset at the top
## of build().
const LIGHT_BUDGET := 6
static var _lights_used := 0

static func build(parent: Node2D) -> Dictionary:
	parent.y_sort_enabled = true
	_lights_used = 0
	var size := Vector2(ROOM_W * TILE, ROOM_H * TILE)
	var spawn := Vector2(720, 640)
	_reserve_labels()
	_build_floor(parent)
	_build_rug(parent)
	_build_floor_zones(parent)
	_build_walls(parent)
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

## LAW 3 and LAW 4 in one place: energy clamped to 0.4-0.9, radius floored at a
## genuinely soft one, position on the pixel grid, and past LIGHT_BUDGET the
## request returns null. Callers treat a missing light as "the pool carries it".
static func _add_light(parent: Node2D, pos: Vector2, color: Color, energy: float, scale: float, flicker: bool = false) -> PointLight2D:
	if _lights_used >= LIGHT_BUDGET:
		return null
	_lights_used += 1
	var light := PointLight2D.new()
	var tex := _light_tex()
	light.texture = tex
	light.energy = clampf(energy, 0.4, 0.9)
	light.color = color
	# Normalize so authored scales mean the same world size whether the 128px
	# fx_radial_soft cookie exists or the 64px procedural fallback is in play.
	light.texture_scale = maxf(scale, 3.0) * (64.0 / maxf(1.0, float(tex.get_width())))
	light.position = Vector2(round(pos.x * 0.5) * 2.0, round(pos.y * 0.5) * 2.0)
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

## The neon-tube texture is gone with the exit tube it drew (critique #9): the
## flat has no emitting signage left, so nothing in this file needs a baked
## overbright core row any more.

## Small emissive screen face (gradient + faint code lines) for crt_monitor —
## color baked into the texture because the crt shader replaces vertex COLOR.
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

## Status LED: ONE static emissive chip (LAW 7), not a tween that blinks a rack
## of six of them out of phase forever (LAW 9 — nothing moves at rest but the
## player, the tokens and the waypoint). `phase` is kept and ignored.
static func _led(parent: Node2D, pos: Vector2, color: Color, _phase: float, z: int) -> void:
	var led := ColorRect.new()
	led.size = Vector2(3, 2)
	led.position = pos
	led.color = Color(color.r, color.g, color.b, 0.6)
	led.material = _additive_mat()
	led.mouse_filter = Control.MOUSE_FILTER_IGNORE
	led.z_index = z
	parent.add_child(led)

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

## Ceiling on every puddle in the flat. Round-8 critique #7, "props outshine the
## player": capped on the way IN, so no number of call sites can add up to a room
## with nothing dark in it. 0.22 is the two motivated sources' own value, and
## nothing in the room may exceed the lamp and the monitor bank.
const POOL_MAX := 0.22

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
	s.modulate = Color(col.r, col.g, col.b, minf(alpha, POOL_MAX))
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
	# ONE box, 260x220, centred on the door (round-8 critique #9). The old pair —
	# a plate box and a body box, both hung ABOVE centre — left the portal's own
	# destination label (region_portal.gd draws it BELOW the disc, at +64..+90)
	# and the guidance chevron's column unprotected.
	WorldLabel.reserve(Rect2(PORTAL_POS + Vector2(-130, -110), Vector2(260, 220)))
	# Claude's nameplate AND the column his idle barks rise through: npc.gd
	# puts the plate at y -106..-86 and stacks bubbles up to about -175, so a
	# sign anywhere in that box would be spoken over.
	# 360x150 since round 8: the frames show the name tag clipping captions at
	# both ends of a 340px box.
	WorldLabel.reserve(Rect2(Vector2(820, 560) + Vector2(-180, -210), Vector2(360, 150)))
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

## The AO STRIP IS GONE; _floor_ao above is the flat's only ambient occlusion.
## Two passes were doing the same job and the sum was three quarters of a stop of
## darkening in the 46px nearest each wall — the "void" edge the pass-2
## measurements found in every room, plus four rotated sprites (LAW 1).

# -------------------------------------------------------------- floor -------

## Deterministic per-cell hash (duplicated from RegionBuilder on purpose: this
## file is preloaded BY that one, so reaching back into it would be cyclic).
static func _cell_hash(x: int, y: int) -> int:
	var v := (x * 374761393 + y * 668265263) & 0x7FFFFFFF
	v = ((v ^ (v >> 13)) * 1274126177) & 0x7FFFFFFF
	return (v ^ (v >> 16)) & 0x7FFFFFFF

## The boards, and nothing on top of them.
##
## ROUND 7 removed, in order: the wear field (coarse blotches multiplied into
## every tile), the +/-11% per-tile exposure jitter, one in seventeen tiles
## darkened for a "coffee stain", eighteen soft stains, fourteen rotated scuff
## marks, and a full-floor ground_mottle shader pass. Six layers of noise on a
## floor whose whole job is to be legible ground (LAW 6). What is left is the
## plank art, A/B alternated by cell hash at a 6% value step.
## Wall AO — the LAW 6 rule, applied to the flat as a smooth per-tile ramp: at
## most 26% of darkening, and only within 150px of a wall. It replaces the four
## stretched decal_ao_edge sprites that used to be laid along the skirting at
## 0.6 alpha, which took the boards down by 60% in a 46px band. That is a black
## frame drawn around a room, not ambient occlusion — and a rotated sprite
## besides (LAW 1).
const AO_DEPTH := 150.0
const AO_MAX := 0.26

static func _floor_ao(p: Vector2, w: float, h: float) -> float:
	var e := minf(minf(p.x, w - p.x), minf(p.y - 46.0, h - p.y))
	if e >= AO_DEPTH:
		return 1.0
	var t := clampf(e / AO_DEPTH, 0.0, 1.0)
	return 1.0 - AO_MAX * (1.0 - t * t * (3.0 - 2.0 * t))

## The boards, the A/B course break, and the wall AO. Nothing else.
static func _build_floor(parent: Node2D) -> void:
	var floor := Node2D.new()
	floor.name = "Floor"
	parent.add_child(floor)
	var w := float(ROOM_W * TILE)
	var h := float(ROOM_H * TILE)
	for gx in ROOM_W:
		for gy in ROOM_H:
			var hv := _cell_hash(gx, gy)
			# Board variant per 2x1 BLOCK, so planks run in short courses.
			var v := _cell_hash(gx >> 1, gy) % 3
			var p := Vector2(gx * TILE + TILE / 2, gy * TILE + TILE / 2)
			# LAW 6, the numbers the region builder now uses too: the A/B step is
			# 6% and NOTHING modulates a floor below 0.92 except the wall AO. The
			# old pair (1.22 / 1.29, scaled by 0.85) was a brightener compensating
			# for a capture bug that has since been fixed, and the 0.96 on blue was
			# a tint on the ground — the planks carry their own colour.
			var e := (1.0 if (hv % 100) < 62 else 1.06) * _floor_ao(p, w, h)
			_put(floor, "int_floor_%d" % v, p, -100, 1.0, Color(e, e, e))

static func _build_rug(parent: Node2D) -> void:
	_put(parent, "int_rug", Vector2(560, 600), -90)

## ONE hand-placed floor shadow, and that is the entire floor overlay budget.
##
## ROUND 8 removed the twenty-seven-patch "worn track" that ran from the chair
## through the middle of the room to Claude and on to the door. It was defended
## as wayfinding, but it is a drag mark drawn on the ground — LAW 4 puts floor
## overlays at zero and names drag marks specifically — and the round-8 critique
## reads exactly this shape, a line arcing from the player to the portal, as one
## of the signatures that makes every room look like the same room. The waypoint
## chevron is the wayfinding. What survives is the dark under the desk, which is
## an object casting a shadow rather than a path drawn on a floor.
static func _build_floor_zones(parent: Node2D) -> void:
	var z := Node2D.new()
	z.name = "FloorZones"
	parent.add_child(z)
	# Under the desk: a dark cave of cables and abandoned socks.
	_floor_patch(z, Vector2(540, 420), 340.0, Color(0.02, 0.02, 0.04), 0.30, -94)

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
		_put(walls, "int_wall", Vector2(x, 16), -60, 1.0, Color(0.85, 0.85, 0.85))
		_add_collider(walls, Vector2(x, 24), Vector2(TILE, 56))
	# Side + bottom borders (thin dark strips + colliders)
	for gy in ROOM_H:
		var y := gy * TILE + TILE / 2
		_put(walls, "int_wall_side", Vector2(20, y), -58, 1.0, Color(0.68, 0.68, 0.77))
		_put(walls, "int_wall_side", Vector2(right - 20, y), -58, 1.0, Color(0.60, 0.60, 0.68))
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
	# Three monitors, ONE hue. The round-6 bank was cyan, orange and red side by
	# side, with two more (red, green) on the second desk: five saturated screens
	# and five point lights in a room whose palette is two colours. Only the
	# centre screen carries a readout now — LAW 4 counts these as world labels,
	# and five of them plus three poster creeds plus twenty-one signs is the wall
	# of text the brief was looking at.
	# TWO of the five faces in the flat are on, and they are these (critique #9).
	# They are also the only cyan in the room that emits, which is what makes the
	# bank the motivated source _build_lighting points a light at.
	_add_monitor(z, Vector2(430, 300), ACCENT, "", ACCENT)
	_add_monitor(z, Vector2(540, 296), ACCENT, "TOKENS\n>>> 70", ACCENT)
	_add_monitor(z, Vector2(650, 300), ACCENT, "", ACCENT, false, false)
	# Gaming chair, slightly askew
	var chair_z := _depth(470, 44)
	_drop_shadow(z, Vector2(560, 505), 84.0, chair_z - 1)
	_put(z, "furn_chair", Vector2(560, 470), chair_z, 1.0, Color(0.72, 0.72, 0.80))

## A monitor: the prop, its emissive screen, the pool it casts on the desk, and
## a readout only when one was asked for.
##
## It no longer creates a PointLight2D of its own. Five monitors meant five
## lights, which is the entire LAW 4 budget spent on furniture; the bank is lit
## as ONE source by _build_lighting instead, which is also what it physically is.
static func _add_monitor(parent: Node2D, pos: Vector2, screen_col: Color, text: String, text_col: Color, _flicker_it: bool = false, lit: bool = true) -> void:
	var mz := _depth(pos.y, 42)
	_put(parent, "furn_monitor", pos, mz)
	if not lit:
		# DARK GLASS (critique #9: "5 monitors + cyan tube" lit at rest in a room
		# LAW 3 allows two motivated sources). A monitor that is off is still a
		# monitor — it is the shape, not the glow, that says workstation.
		_rect(parent, pos - Vector2(0, 6), Vector2(80, 48), Color(0.05, 0.055, 0.075, 0.96), mz + 1)
		_rect(parent, pos - Vector2(0, 19), Vector2(58, 2), Color(0.20, 0.22, 0.28, 0.5), mz + 2)
		return
	# Emissive screen: scanlined by crt_monitor. The color is baked into a
	# generated texture because the crt shader replaces vertex COLOR, so a
	# modulate/ColorRect tint would not survive it — and it is baked at 60% value
	# with the shader's boost at 1.0, so the bank reads as the light SOURCE for
	# the room rather than as the brightest object in the frame (LAW 3).
	var scr := Sprite2D.new()
	scr.texture = _screen_tex(Color(screen_col.r * 0.6, screen_col.g * 0.6, screen_col.b * 0.6))
	var crt := _shader_mat("crt_monitor", {"glow_boost": 1.0})
	if crt:
		scr.material = crt
	scr.position = pos - Vector2(0, 6)
	scr.scale = Vector2(2.0, 1.85)
	scr.z_index = mz + 1
	parent.add_child(scr)
	if not text.is_empty():
		# Readout style "tag": no plate (a plate would cover the screen art),
		# pinned to the monitor's own z so it travels with the prop.
		WorldLabel.add(parent, pos - Vector2(34, 24), text, text_col, {
			"size": 10, "style": "tag", "color": text_col,
			"z": mz + 2, "claim": false, "fade": false,
		})
	# NO spill halo. This was an additive puddle drawn at z (mz + 50) — i.e. ON
	# TOP of the desk and the monitor rather than on the floor — five of them
	# across the two workstations, and round-8 critique #7 names it: the props
	# out-shine the player. The bank is lit as one source by _build_lighting, and
	# THAT pool lands on the floor, where a pool belongs (LAW 4).

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
	# Both rig faces are DARK (critique #9). Five lit screens in a two-hue room is
	# four motivated sources too many, and the amber pair was the room's second
	# light bank sitting three metres from its first; the rig's thermal pool below
	# still says the machine is running. Neither carries a readout either: the
	# joke about 94 degrees belongs behind [E] on the terminal prop, per LAW 10.
	_add_monitor(z, Vector2(1060, 318), WARM, "", WARM, false, false)
	_add_monitor(z, Vector2(1170, 320), WARM, "", WARM, false, false)
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
	# The racks get a pool, not a light: LAW 3 allows two motivated sources in a
	# frame and this room has already spent them on the lamp and the screens. The
	# green third hue goes with it — the racks read as hardware in cyan.
	_light_pool(z, Vector2(1424, 300), 300.0, ACCENT, 0.12)
	# One status chip per rack face. Six blinking LEDs in three colours was the
	# rack advertising itself; a rack has a light on it, singular.
	_led(z, Vector2(1454, 172), ACCENT, 0.0, rack_z + 1)
	_led(z, Vector2(1364, 198), ACCENT, 0.0, rack2_z + 1)

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
	# One can colour, desaturated. Three saturated flavours of regret on the floor
	# was three more hues than LAW 2 allows the room.
	var can_cols: Array[Color] = [Color(0.46, 0.48, 0.44), Color(0.50, 0.46, 0.42), Color(0.44, 0.47, 0.50)]
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
	# The four additive catch-lights that used to sit on the cable bends are gone.
	# A specular dot on a cable is not one of LAW 3's five bright things, and four
	# of them in three different hues is the rainbow the law exists to stop.
	# The strip every one of those cables was always heading for: six sockets,
	# more wall-warts than sockets, one confidently red LED. It lies mid-room so
	# the player literally steps over the infrastructure, and two more looms
	# converge on it from both desks (extra cables only when the strip exists,
	# so no run ever ends at empty floor).
	if _put(z, "int_power_strip", Vector2(706, 436), -76):
		_cable(z, [Vector2(1120, 430), Vector2(960, 466), Vector2(812, 452), Vector2(716, 438)], Color(0.11, 0.10, 0.13))
		_cable(z, [Vector2(696, 436), Vector2(602, 452), Vector2(508, 438), Vector2(452, 458)], Color(0.10, 0.11, 0.14))
	# Sticky notes along both desk fronts. Estimates. All of them say TODO.
	_put(z, "int_sticky_strip", Vector2(476, 349), _depth(340.0, 48.0) + 1)
	_put(z, "int_sticky_strip", Vector2(1086, 372), _depth(360.0, 48.0) + 1, 0.8)
	# Wall posters (side walls) for depth + jokes
	# Two of the three posters lose their text. Printed matter is artwork, and
	# three more blocks of glowing world type in a room capped at four labels is
	# exactly the "no quiet" the brief named. The creeds still exist — they are
	# the poster art, and the jokes live behind [E].
	_poster(z, Vector2(30, 420), Color(0.2, 0.3, 0.5), "", ACCENT)
	_poster(z, Vector2(30, 620), Color(0.4, 0.2, 0.3), "", WARM)
	# SHIP OR DIE used to hang at y=500 — i.e. directly behind the portal's vortex,
	# where its own ideology was permanently eclipsed by the way out. Moved up the
	# right wall into clear air between the server racks and the doorway glow.
	# Its text goes too. LAW 4 caps the flat at four world labels and the three
	# wayfinding signs plus the one monitor readout are exactly four; a fifth
	# block of type is a fifth block of type however good the joke is.
	_poster(z, Vector2(ROOM_W * TILE - 62, 300), Color(0.25, 0.4, 0.35), "", TEXT_DIM)

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

## A poster on the wall. The additive halo that used to radiate its ideology
## behind the frame is gone: LAW 3 says signs do not glow, and a poster is a
## sign. `glow_col` is kept in the signature (callers pass one) and is now simply
## the text colour when there is text.
static func _poster(parent: Node2D, pos: Vector2, color: Color, text: String, glow_col: Color = Color(0.5, 0.7, 1.0)) -> void:
	# Printed poster art (generated, bright greyscale) tinted toward the creed's
	# accent; the flat ColorRect remains the ungenerated-checkout fallback.
	if not _put(parent, "int_poster", pos + Vector2(22, 30), -52, 1.0,
			Color(minf(color.r + 0.30, 0.66), minf(color.g + 0.30, 0.66), minf(color.b + 0.30, 0.66))):
		var frame := ColorRect.new()
		frame.size = Vector2(44, 60)
		frame.position = pos
		frame.color = color
		frame.z_index = -52
		parent.add_child(frame)
	if text.is_empty():
		return
	# Printed matter: no plate (the frame IS the plate), no float, no fade, and
	# the poster's own z so it stays flat on the wall.
	WorldLabel.add(parent, pos + Vector2(5, 6), text, glow_col, {
		"size": 10, "style": "plaque", "color": glow_col, "z": -51,
	})

# ------------------------------------------------------------ lighting ------

## Hero lighting. FOUR sources, and they are all things you can point at in the
## picture: the one lamp this person owns, the monitor bank, the city through the
## window, and the exit neon. Claude's key light is the fifth, in _build_poi_pools.
##
## ROUND 7 removed eleven more: a light per monitor (five), the fridge, the bed,
## the server racks, the SHIP OR DIE poster, the doorway wash and the portal
## spill. LAW 3 allows at most two motivated sources per frame plus the player,
## the objective and the tokens; sixteen lights in one apartment is why the
## captured frame has no dark anywhere and therefore nothing to look at. What
## every removed light leaves behind is its POOL — the puddle was always the part
## doing the work.
static func _build_lighting(parent: Node2D) -> void:
	var z := Node2D.new()
	z.name = "Lighting"
	parent.add_child(z)
	# 1. Warm amber key, breathing slightly (cheap bulb, obviously). The pool is
	# tighter and one step stronger than round 7's: a 520px wash at 0.18 lit half
	# the flat to one value, which is the flatness critique #7 is looking at. A
	# lamp POOLS — it has a centre and an edge.
	_add_light(z, Vector2(300, 250), WARM, 0.9, 5.0, true)
	_light_pool(z, Vector2(300, 322), 400.0, WARM, 0.22)
	# 2. The monitor bank, lit as ONE source across all three screens, pooling on
	# the floor in front of the desk.
	_add_light(z, Vector2(545, 335), ACCENT, 0.6, 3.4)
	_light_pool(z, Vector2(545, 410), 360.0, ACCENT, 0.22)
	# 3. City light through the big window — a cool FILL behind the desk, not a
	# third key. LAW 3 allows two motivated sources and this room's two are the
	# lamp and the monitor bank; at 0.7 energy and a 0.22 wash the window was
	# quietly making a third, which is most of why the flat reads evenly lit.
	_add_light(z, Vector2(545, 170), Color(0.48, 0.60, 0.88), 0.5, 4.2)
	var pool := Sprite2D.new()
	pool.texture = _light_tex()
	pool.material = _additive_mat()
	pool.position = Vector2(545, 322)
	var ptw := maxf(1.0, float(pool.texture.get_width()))
	pool.scale = Vector2(500.0 / ptw, 230.0 / ptw)
	pool.modulate = Color(0.50, 0.62, 0.92, 0.14)
	pool.z_index = -87
	z.add_child(pool)
	# Everything else in the room gets a puddle and no light — and round 8 cuts
	# that list from five to two. The 540px pool "around the desk" and the 460px
	# one "around the rig" were unmotivated fill: they sat under the two pools
	# that DO have a source, doubled their footprint, and turned two lights with
	# an edge into one continuous wash across the middle of the flat.
	_light_pool(z, Vector2(1320, 872), 300.0, Color(0.42, 0.48, 0.66), 0.10)  # the unslept bed
	_light_pool(z, Vector2(1120, 424), 300.0, WARM, 0.14)         # the rig's thermals
	# 4. The exit fixture, DARK (critique #9: "5 monitors + cyan tube" alight in a
	# room LAW 3 gives two motivated sources). A flickering overbright tube on the
	# ceiling was the brightest thing in the right half of the frame — brighter
	# than the doorway it was advertising, and a third light bank besides. What is
	# left is the housing, which is hardware whether or not it is switched on, and
	# the puddle the doorway itself throws. region_portal.gd lights its own gate;
	# the EXIT sign is the wayfinding. The tube used to be pinned just under the
	# world text (z 1149) so nothing could cover the one LIT thing pointing at the
	# door; an UNLIT housing has no such claim, and left up there it would be a
	# black bar drawn over the player's head. It y-sorts like the furniture it is.
	_rect(z, Vector2(PORTAL_POS.x, 366.0), Vector2(106, 12), Color(0.05, 0.055, 0.075, 0.95), _depth(366.0, 6.0))
	_rect(z, Vector2(PORTAL_POS.x, 371.0), Vector2(94, 3), Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.16), _depth(366.0, 7.0))
	_light_pool(z, PORTAL_POS + Vector2(-20, 10), 380.0, ACCENT, 0.15)

## Claude, standing in the one honest spotlight in the apartment, plus a quiet
## puddle on each of the two things the opening actually asks you to touch.
##
## The twelve-rect ring of dashes around Claude's feet is gone (it read as a
## summoning circle, not as lighting), and so are four of the six coloured
## point-of-interest pools — a blue one, a cyan one, an orange one, a green one,
## a violet one and a red one, six hues in a three-hue room, all at the same
## value, which is the definition of no reading order. The waypoint chevron and
## the [E] prompt are the real affordance; these two are the confirmation.
static func _build_poi_pools(parent: Node2D) -> void:
	var z := Node2D.new()
	z.name = "PoiPools"
	parent.add_child(z)
	_add_light(z, Vector2(820, 552), Color(1.0, 0.87, 0.62), 0.55, 3.0)
	_light_pool(z, Vector2(820, 586), 240.0, Color(1.0, 0.85, 0.58), 0.26)
	_light_pool(z, Vector2(650, 384), 150.0, ACCENT, 0.18)   # dream app terminal
	_light_pool(z, Vector2(760, 404), 150.0, WARM, 0.18)     # deploy button

## Foreground framing: a ceiling beam at the top edge and a skirting board at the
## bottom, neither of them anywhere the player can stand.
##
## ROUND 7 removed the two drooping ceiling cables with their mount plates and
## warm speculars, the four in-world corner vignettes and the two side jambs.
## The corner vignettes were the post-processing vignette drawn a second time in
## world space, and the jambs narrowed a room that is already framed by its own
## walls. Depth comes from the lighting (LAW 3).
static func _build_framing(parent: Node2D) -> void:
	var z := Node2D.new()
	z.name = "Framing"
	parent.add_child(z)
	var w := ROOM_W * TILE
	var h := ROOM_H * TILE
	_rect(z, Vector2(w * 0.5, 26.0), Vector2(w + 40.0, 26.0), Color(0.02, 0.02, 0.04, 0.94), 500)
	_rect(z, Vector2(w * 0.5, 39.0), Vector2(w + 40.0, 2.0), Color(WARM.r, WARM.g, WARM.b, 0.10), 501)
	for i in 5:
		var bx := 180.0 + float(i) * (w - 360.0) / 4.0
		_rect(z, Vector2(bx, 34.0), Vector2(12, 40), Color(0.02, 0.02, 0.04, 0.9), 500)
	# Skirting board along the near edge of the room.
	_rect(z, Vector2(w * 0.5, h - 6.0), Vector2(w + 40.0, 24.0), Color(0.015, 0.015, 0.03, 0.92), 600)

# ---------------------------------------------------------- atmosphere ------

## TWO emitters (LAW 4): the ambient dust layer, and one at the set-piece — the
## coffee machine, which is the load-bearing appliance in this person's life.
## The server-exhaust plume is gone with the racks' light; dust drops from 26
## particles to 16 and from warm white to TEXT_DIM at 25%, because dust is not
## one of the five things allowed to be bright.
static func _build_atmosphere(parent: Node2D) -> void:
	var dot := _glow_dot()
	var dust := CPUParticles2D.new()
	dust.name = "DustMotes"
	dust.position = Vector2(ROOM_W * TILE * 0.5, ROOM_H * TILE * 0.5)
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	dust.emission_rect_extents = Vector2(ROOM_W * TILE * 0.5 - 60, ROOM_H * TILE * 0.5 - 60)
	dust.z_index = 350
	dust.amount = 16
	dust.lifetime = 9.0
	dust.gravity = Vector2(0, -4)
	dust.initial_velocity_min = 2.0
	dust.initial_velocity_max = 8.0
	dust.spread = 180.0
	dust.scale_amount_min = 1.2
	dust.scale_amount_max = 2.2
	dust.color = Color(TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, 0.25)
	if dot:
		dust.texture = dot
	parent.add_child(dust)
	# Coffee steam. Load-bearing appliance, gets the region's one set-piece emitter.
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
	steam.color = Color(0.85, 0.87, 0.90, 0.22)
	if dot:
		steam.texture = dot
	parent.add_child(steam)

# -------------------------------------------------------------- signs -------

## TWO signs. LAW 4 allows four PER ROOM, and the room's other two are drawn by
## nodes this file does not own (Claude's name tag, the portal's destination
## plate). LAW 10 says the jokes leave ambient signage,
## and this apartment used to carry twenty-one of them: six wayfinding, seven
## furniture stories, four flavour gags, plus five monitor readouts and three
## poster creeds. The captured localhost frame is that list, drawn all at once,
## and it is the single clearest picture of what the brief meant by slop.
##
## What survives is what answers "what do I do next, and where":
##   1. EXIT, up the wall by the door where an exit sign actually lives,
##   2. the one line that points at the person you must talk to first.
##
## Every removed string is still in the game — SERVER RACK (do NOT reboot),
## FRIDGE (energy drinks only), COFFEE: MISSION CRITICAL, PLANT status:
## deprecated, node_modules (trash), BED, DNS, COUCH, PIZZA ARCHAEOLOGY, WINDOW,
## RIG — every one of those props already carries a generic_interactable with a
## flavour popup behind [E]. They are listed in this round's contracts so the
## reactive-comedy owner can fold the sign text into the popup bodies.
static func _build_signs(parent: Node2D) -> void:
	var z := Node2D.new()
	z.name = "Signs"
	parent.add_child(z)
	# Above the door and clear of both the rig's monitor faces (reserved to y 350)
	# and the portal's own 260x220 box (which starts at y 402). It travels with
	# PORTAL_POS: the door moved 80 units in this round and a fixed arrow would
	# have ended up inside the box it is supposed to point at.
	_sign(z, Vector2(PORTAL_POS.x - 154.0, 366), "EXIT \u2192", ACCENT, 3, "headline")
	# On Claude's FAR side and at the height of his FEET, never above him
	# (round-8 critique #9): his name tag owns the whole column above his head and
	# the frames show this line landing in it. His silhouette is reserved to
	# y 584, the player's lane to x 866; the arrow points back at him.
	_sign(z, Vector2(892, 570), "\u2190 talk to Claude first", ACCENT, 3, "headline")
	# THE TERMINAL SIGN IS GONE (critique #6: "5-7 world labels per room, budget
	# <= 4"). The flat's readable text is now EXIT, the one line that starts the
	# game, the monitor's own readout, Claude's name tag and the portal's
	# destination plate — and this caption was the sixth. The terminal keeps its
	# [E] prompt and the waypoint chevron points at it the moment the quest that
	# needs it is active, which is the only moment it matters.

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
	# EIGHT, placed on the worn track the player is already being invited to walk
	# (LAW 4: 6-10, intentional; LAW 1: even integers). Fourteen coins spread over
	# the whole flat is a carpet, not a reward — and six of them used to sit in
	# the corners nobody walks through, doing nothing but bobbing and glowing.
	var token_types := ["common", "common", "cached", "common", "cached"]
	var token_positions := [
		Vector2(560, 700), Vector2(660, 660), Vector2(700, 760),
		Vector2(900, 620), Vector2(1030, 580),
		Vector2(1160, 540), Vector2(1300, 520),
		Vector2(500, 560),
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
	# Moved out of the doorway when PORTAL_POS came in off the wall: a bug
	# standing in the portal's mouth is a fight the player did not choose.
	for pos: Vector2 in [Vector2(1330, 706), Vector2(1490, 820)]:
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
	# Comedy storyline triggers (repeatable). No colour coding and no marker:
	# three saturated chips on the boards were three hues this room does not
	# own, and the [E] prompt says "something is here" better than any of them.
	var ad := _add_interact(props, interact_scene, "free_tokens_ad", Vector2(1160, 620), "Suspicious pop-up ad")
	ad.one_shot = false
	var agent := _add_interact(props, interact_scene, "agent_terminal", Vector2(300, 560), "Autonomous Agent terminal")
	agent.one_shot = false
	var svc := _add_interact(props, interact_scene, "broken_service", Vector2(1120, 650), "Investigate the outage")
	svc.one_shot = false

	# Environmental comedy props: readable flavour on the furniture, rewarding
	# exploration. The floating [E] prompt does the pointing.
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

	if GameManager.is_region_unlocked("dependency_district"):
		var portal_scene := preload("res://scenes/world/region_portal.tscn")
		var p = portal_scene.instantiate()
		p.target_region = "dependency_district"
		p.portal_label = "Dependency District"
		p.position = PORTAL_POS
		portals.add_child(p)
		# No spill light here. region_portal.gd lights its own gate, and a 1.0-energy
		# violet wash from the builder on top of it is both a fourth hue and the
		# "portal filling a third of the screen" the brief called out.

static func _add_interact(parent: Node2D, scene: PackedScene, id: String, pos: Vector2, text: String) -> Node:
	var node = scene.instantiate()
	node.interact_id = id
	node.interact_text = text
	node.position = pos
	# NO MARKER (critique #4, "~40px amber squares"). generic_interactable.tscn
	# ships a 32x32 ColorRect at Color(0.9, 0.7, 0.2, 0.8) and this flat placed
	# sixteen interactables, so sixteen flat filled quads lay on the boards with
	# nothing under them. The floating [E] prompt that appears in range is the
	# affordance; the furniture is the art. This also retires _dim() and _tint(),
	# which existed only to make those chips quieter.
	var rect := node.get_node_or_null("ColorRect")
	if rect:
		rect.visible = false
	parent.add_child(node)
	return node

