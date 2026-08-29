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

## One-time caches, mirroring RegionBuilder's (duplicated on purpose: this file
## is preloaded BY region_builder.gd, so leaning on its class_name from here
## would be a cyclic reference for two functions' worth of code).
static var _radial_cache: Texture2D
static var _shadow_cache: Texture2D
static var _neon_cache: Dictionary = {}
static var _screen_cache: Dictionary = {}
static var _mat_cache: Dictionary = {}
static var _add_mat_cache: CanvasItemMaterial

static func build(parent: Node2D) -> Dictionary:
	parent.y_sort_enabled = true
	var size := Vector2(ROOM_W * TILE, ROOM_H * TILE)
	var spawn := Vector2(720, 640)
	_build_floor(parent)
	_build_rug(parent)
	_build_walls(parent)
	_build_grounding(parent)
	_build_battlestation(parent)
	_build_gpu_rig(parent)
	_build_server_corner(parent)
	_build_kitchen(parent)
	_build_bedroom(parent)
	_build_clutter(parent)
	_build_lighting(parent)
	_build_atmosphere(parent)
	_build_signs(parent)
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
	for i in 8:
		var s := Sprite2D.new()
		s.texture = load(names[rng.randi() % names.size()])
		s.position = Vector2(rng.randf_range(100, w - 100), rng.randf_range(120, h - 90))
		s.rotation = float(rng.randi() % 4) * PI * 0.5
		s.scale = Vector2.ONE * rng.randf_range(0.8, 1.5)
		s.modulate = Color(1, 1, 1, rng.randf_range(0.35, 0.6))
		s.z_index = -95
		z.add_child(s)

# -------------------------------------------------------------- floor -------

static func _build_floor(parent: Node2D) -> void:
	var floor := Node2D.new()
	floor.name = "Floor"
	parent.add_child(floor)
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	for gx in ROOM_W:
		for gy in ROOM_H:
			var v := (gx * 7 + gy * 13) % 3
			# Per-tile brightness jitter + occasional grime breaks the grid so
			# tiling never reads as a stamped pattern.
			var j := rng.randf_range(-0.06, 0.05)
			var mod := Color(1.0 + j, 1.0 + j, 1.0 + j * 0.8)
			if rng.randf() < 0.06:
				mod = mod.darkened(0.18)  # coffee stain / grime
			_put(floor, "int_floor_%d" % v, Vector2(gx * TILE + TILE / 2, gy * TILE + TILE / 2), -100, 1.0, mod)

static func _build_rug(parent: Node2D) -> void:
	_put(parent, "int_rug", Vector2(560, 600), -90)

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
	# Window (night city) over the desk, and an apartment door.
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
	_add_monitor(z, Vector2(430, 300), Color(0.15, 0.85, 0.95), "TOKEN BALANCE\n>>> 70", Color(0.2, 0.95, 0.9))
	_add_monitor(z, Vector2(540, 296), Color(0.95, 0.65, 0.2), "AI SUBSCRIPTIONS\nactive: 8", Color(1.0, 0.7, 0.3))
	_add_monitor(z, Vector2(650, 300), Color(0.95, 0.35, 0.35), "SAVINGS FROM AI\n-€713 / mo", Color(1.0, 0.45, 0.45))
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
	var lbl := Label.new()
	lbl.text = text
	lbl.position = pos - Vector2(36, 26)
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", text_col)
	lbl.z_index = mz + 2
	parent.add_child(lbl)
	# Screen glow spill (cool cyan against the lamp's amber; the bible's duel)
	_add_light(parent, pos - Vector2(0, 10), screen_col, 0.75, 1.6, flicker)

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
	# empty energy-drink cans on the floor
	for i in 5:
		var can := ColorRect.new()
		can.size = Vector2(10, 16)
		can.position = Vector2(180 + i * 22, 300 + (i % 2) * 14)
		can.color = [Color(0.2, 0.85, 0.35), Color(0.9, 0.3, 0.3), Color(0.3, 0.6, 0.95)][i % 3]
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
	# pizza boxes
	for p in [Vector2(880, 800), Vector2(930, 820), Vector2(700, 880)]:
		var box := ColorRect.new()
		box.size = Vector2(46, 40)
		box.position = p
		box.color = Color(0.7, 0.5, 0.25)
		box.z_index = _depth(p.y, 20)
		z.add_child(box)
	# A sad couch nobody sleeps on (drawn from rects)
	_couch(z, Vector2(760, 760))
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
	# Wall posters (side walls) for depth + jokes
	_poster(z, Vector2(30, 420), Color(0.2, 0.3, 0.5), "IT\nWORKS\nLOCALLY", Color(0.4, 0.65, 1.0))
	_poster(z, Vector2(30, 620), Color(0.4, 0.2, 0.3), "MOVE\nFAST", Color(1.0, 0.35, 0.5))
	_poster(z, Vector2(ROOM_W * TILE - 62, 500), Color(0.25, 0.4, 0.35), "SHIP\nOR\nDIE", Color(0.3, 1.0, 0.6))

static func _couch(parent: Node2D, pos: Vector2) -> void:
	var z := _depth(pos.y, 34)
	_drop_shadow(parent, pos + Vector2(0, 44), 180.0, z - 1)
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

static func _cable(parent: Node2D, points: Array, color: Color) -> void:
	var line := Line2D.new()
	line.width = 4.0
	line.default_color = color
	line.z_index = -80
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	for p in points:
		line.add_point(p)
	parent.add_child(line)

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
	var frame := ColorRect.new()
	frame.size = Vector2(44, 60)
	frame.position = pos
	frame.color = color
	frame.z_index = -52
	parent.add_child(frame)
	var lbl := Label.new()
	lbl.text = text
	lbl.position = pos + Vector2(5, 6)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	lbl.z_index = -51
	parent.add_child(lbl)

# ------------------------------------------------------------ lighting ------

## Hero lighting pass. This room is the player's first three seconds with the
## game, so it gets the full treatment: warm amber key from the one lamp this
## person owns, cool cyan monitor spill fighting it across the desk, a pool of
## 3AM city light under the window, and small accents everywhere something hums.
static func _build_lighting(parent: Node2D) -> void:
	var z := Node2D.new()
	z.name = "Lighting"
	parent.add_child(z)
	# Warm amber key, breathing slightly (cheap bulb, obviously).
	_add_light(z, Vector2(300, 250), Color(1.0, 0.72, 0.4), 0.9, 5.0, true)
	# Cool cyan spill unifying the battlestation's three screens.
	_add_light(z, Vector2(545, 335), Color(0.14, 0.94, 0.86), 0.55, 3.2)
	# City light through the window, pooling on the floor below it.
	_add_light(z, Vector2(560, 140), Color(0.45, 0.66, 1.0), 0.7, 2.6)
	var pool := Sprite2D.new()
	pool.texture = _light_tex()
	pool.material = _additive_mat()
	pool.position = Vector2(560, 178)
	var ptw := maxf(1.0, float(pool.texture.get_width()))
	pool.scale = Vector2(340.0 / ptw, 180.0 / ptw)
	pool.modulate = Color(0.5, 0.7, 1.0, 0.32)
	pool.z_index = -87
	z.add_child(pool)
	# Kitchen counter warmth: the fridge glow of a balanced diet.
	_add_light(z, Vector2(175, 205), Color(1.0, 0.7, 0.35), 0.6, 2.4)
	# The unslept bed, lit cool and judgmental.
	_add_light(z, Vector2(1320, 795), Color(0.55, 0.62, 0.95), 0.35, 2.8)
	# SHIP OR DIE poster insists, in magenta.
	_add_light(z, Vector2(1548, 528), Color("#FF2D95"), 0.4, 1.9)
	# Exit-door neon: acid green, aimed at the Dependency District.
	var tube := Sprite2D.new()
	tube.texture = _neon_tex(Color("#A8FF3E"))
	var nmat := _shader_mat("neon_flicker", {"seed": 7.7, "base_boost": 1.6})
	if nmat:
		tube.material = nmat
	tube.position = Vector2(1408, 428)
	tube.scale = Vector2(2.2, 1.5)
	tube.z_index = 399
	z.add_child(tube)
	_add_light(z, Vector2(1408, 434), Color("#A8FF3E"), 0.55, 2.0)

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

static func _build_signs(parent: Node2D) -> void:
	var z := Node2D.new()
	z.name = "Signs"
	parent.add_child(z)
	_sign(z, Vector2(1360, 120), "SERVER RACK\n(do NOT reboot)", Color(0.5, 1.0, 0.6))
	_sign(z, Vector2(70, 150), "FRIDGE\n(energy drinks only)", Color(0.6, 0.9, 1.0))
	_sign(z, Vector2(200, 200), "COFFEE: MISSION CRITICAL", Color(1.0, 0.78, 0.4))
	_sign(z, Vector2(90, 760), "PLANT\nstatus: deprecated", Color(0.6, 0.8, 0.5))
	_sign(z, Vector2(150, 900), "node_modules\n(trash)", Color(0.7, 0.6, 0.5))
	_sign(z, Vector2(1250, 920), "BED\n'sleep? during a hackathon?'", Color(0.7, 0.75, 0.95))
	_sign(z, Vector2(880, 120), "DNS\nProbably not the problem.", Color(0.55, 0.85, 1.0))
	_sign(z, Vector2(1090, 585), "'FREE' TOKENS \u2192", Color(0.4, 0.95, 0.5))
	_sign(z, Vector2(250, 525), "\u2190 deploy an AI agent\n(what could go wrong)", Color(0.7, 0.6, 0.95))
	_sign(z, Vector2(1050, 690), "/checkout is DOWN \u2192", Color(1.0, 0.4, 0.35))
	# In-bounds now: at x=1660 this sign lived beyond the camera clamp (1600),
	# advertising the exit to absolutely nobody.
	_sign(z, Vector2(1352, 440), "EXIT \u2192\nDependency District", Color(0.5, 0.95, 0.8))

static func _sign(parent: Node2D, pos: Vector2, text: String, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.position = pos
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.z_index = 400
	parent.add_child(lbl)

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
	for pos in [Vector2(1360, 540), Vector2(1440, 760)]:
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
		p.position = Vector2(ROOM_W * TILE - 90, ROOM_H * TILE * 0.5)
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
