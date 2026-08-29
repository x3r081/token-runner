extends Node2D
class_name RegionBuilder

const _LocalhostBuilder = preload("res://scripts/world/localhost_builder.gd")

## Procedurally builds a region from data at runtime.

const REGION_TILE_MAP := {
	"localhost": "localhost",
	"dependency_district": "dependency",
	"stackoverflow_ruins": "stackoverflow",
	"api_bazaar": "api_bazaar",
	"cloud_district": "cloud",
	"open_source_wildlands": "opensource",
	"corporate_enterprise": "corporate",
	"gpu_mines": "gpu",
	"production": "production",
	"token_vault": "vault",
}

const REGION_SIZE := Vector2i(20, 15)
const TILE_SIZE := 64

static func build(parent: Node2D, region_id: String) -> Dictionary:
	if region_id == "localhost":
		return _LocalhostBuilder.build(parent)
	return _build_region_static(parent, region_id)

const GEN := "res://assets/textures/generated/"
const SHADERS := "res://assets/shaders/"
## Arcane/AI accent (VISUAL_BIBLE master palette) — portals, vault secondaries.
const VIOLET := Color("#8B5CF6")

## One-time caches. Regions rebuild on every travel; textures are generated once
## and ShaderMaterials are shared wherever params are identical (bible rule) —
## except neon signs, whose unique seeds naturally get their own instances.
static var _radial_cache: Texture2D
static var _shadow_cache: Texture2D
static var _neon_cache: Dictionary = {}
static var _screen_cache: Dictionary = {}
static var _mat_cache: Dictionary = {}
static var _add_mat_cache: CanvasItemMaterial

static func _build_region_static(parent: Node2D, region_id: String) -> Dictionary:
	parent.y_sort_enabled = true
	var theme := _region_theme(region_id)
	var w := REGION_SIZE.x * TILE_SIZE
	var h := REGION_SIZE.y * TILE_SIZE
	var spawn_pos := Vector2(w * 0.5, h * 0.5)

	_build_floor_themed(parent, theme, w, h)
	_build_walls_themed(parent, theme, w, h)
	_build_region_grounding(parent, w, h)
	_build_structures(parent, theme)
	_build_region_detail(parent, theme, w, h)
	_build_region_ambient(parent, theme, w, h)
	_build_region_lights(parent, theme)
	_build_region_signs(parent, theme)
	_build_region_fx(parent, region_id, theme, w, h)

	var props := Node2D.new()
	props.name = "Props"
	parent.add_child(props)
	var enemies := Node2D.new()
	enemies.name = "Enemies"
	parent.add_child(enemies)
	var tokens := Node2D.new()
	tokens.name = "Tokens"
	parent.add_child(tokens)
	var npcs := Node2D.new()
	npcs.name = "NPCs"
	parent.add_child(npcs)
	var portals := Node2D.new()
	portals.name = "Portals"
	parent.add_child(portals)

	_populate_region(region_id, props, enemies, tokens, npcs, portals, spawn_pos)

	return {"spawn": spawn_pos, "size": Vector2(w, h)}

# --- themed visual construction ------------------------------------------

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

static func _depth(pos_y: float, half_h: float) -> int:
	return int(pos_y + half_h)

static func _build_floor_themed(parent: Node2D, theme: Dictionary, w: int, h: int) -> void:
	var floor := Node2D.new()
	floor.name = "Floor"
	parent.add_child(floor)
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var tint: Color = theme.get("floor", Color(0.5, 0.5, 0.55))
	for x in REGION_SIZE.x:
		for y in REGION_SIZE.y:
			var j := rng.randf_range(-0.06, 0.05)
			var m := Color(tint.r + j, tint.g + j, tint.b + j)
			# Occasional grime/scorch tiles break the grid so it never reads as a
			# stamped pattern (matches Localhost's de-tiling).
			if rng.randf() < 0.08:
				m = m.darkened(0.2)
			elif rng.randf() < 0.05:
				m = m.lightened(0.08)
			_put(floor, "tech_floor", Vector2(x * TILE_SIZE + TILE_SIZE / 2, y * TILE_SIZE + TILE_SIZE / 2), -100, 1.0, m)
	# Scattered floor debris/cracks (subtle, low z) for texture underfoot.
	var glow: Color = theme.get("glow", Color(0.6, 0.7, 0.9))
	for i in 46:
		var dp := Vector2(rng.randf_range(80, w - 80), rng.randf_range(90, h - 70))
		var kind := rng.randi() % 3
		var dec := ColorRect.new()
		if kind == 0:  # dark speck / stain
			dec.size = Vector2(rng.randf_range(3, 7), rng.randf_range(3, 7))
			dec.color = Color(0, 0, 0, rng.randf_range(0.14, 0.28))
		elif kind == 1:  # hairline crack
			dec.size = Vector2(rng.randf_range(10, 26), 2)
			dec.rotation = rng.randf_range(-1.0, 1.0)
			dec.color = Color(0, 0, 0, 0.22)
		else:  # faint themed glow-chip (spilled coolant / pixels)
			dec.size = Vector2(rng.randf_range(3, 6), rng.randf_range(3, 6))
			dec.color = Color(glow.r, glow.g, glow.b, 0.16)
		dec.position = dp
		dec.z_index = -96
		floor.add_child(dec)

static func _build_walls_themed(parent: Node2D, theme: Dictionary, w: int, h: int) -> void:
	var walls := Node2D.new()
	walls.name = "Walls"
	parent.add_child(walls)
	var wall_tint: Color = theme.get("wall", Color(0.7, 0.7, 0.8))
	for x in REGION_SIZE.x:
		var px := x * TILE_SIZE + TILE_SIZE / 2
		_put(walls, "int_wall", Vector2(px, 16), -60, 1.0, wall_tint)
		_add_collider(walls, Vector2(px, 24), Vector2(TILE_SIZE, 56))
		_add_collider(walls, Vector2(px, h - 6), Vector2(TILE_SIZE, 20))
	for y in REGION_SIZE.y:
		var py := y * TILE_SIZE + TILE_SIZE / 2
		_put(walls, "int_wall_side", Vector2(20, py), -58, 1.0, wall_tint)
		_put(walls, "int_wall_side", Vector2(w - 20, py), -58, 1.0, wall_tint.darkened(0.15))
		_add_collider(walls, Vector2(6, py), Vector2(20, TILE_SIZE))
		_add_collider(walls, Vector2(w - 6, py), Vector2(20, TILE_SIZE))

static func _add_collider(parent: Node2D, pos: Vector2, sz: Vector2) -> void:
	var wall := StaticBody2D.new()
	wall.collision_layer = 32
	wall.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = sz
	shape.shape = rect
	shape.position = pos
	wall.add_child(shape)
	parent.add_child(wall)

static func _build_structures(parent: Node2D, theme: Dictionary) -> void:
	var z := Node2D.new()
	z.name = "Structures"
	parent.add_child(z)
	var glow: Color = theme.get("glow", Color(0.6, 0.8, 1.0))
	var accent: Color = theme.get("accent", glow)
	var crt := _shader_mat("crt_monitor", {"glow_boost": 1.35})
	var lights_added := 0
	for s in theme.get("structs", []):
		var sc: float = float(s.get("s", 1.0))
		var half: float = 40.0 * sc
		var zi := _depth(s.p.y, half)
		var spr := _put(z, s.t, s.p, zi, sc, s.get("m", Color.WHITE))
		if spr:
			_drop_shadow(z, s.p + Vector2(0, half * 0.8), 96.0 * sc, zi - 1)
		# Emissive props earn a real light (bible lighting rules), capped so a
		# dense cluster doesn't blow the light budget.
		match s.t:
			"struct_orb":
				if lights_added < 6:
					_add_light(z, s.p + Vector2(0, -10.0 * sc), glow, 1.0, 2.6, lights_added == 0)
					lights_added += 1
			"struct_console":
				if spr and crt:
					var scr := Sprite2D.new()
					scr.texture = _screen_tex(glow)
					scr.material = crt
					scr.position = s.p + Vector2(0, -20.0 * sc)
					scr.scale = Vector2(1.1, 1.0) * sc
					scr.z_index = zi + 1
					z.add_child(scr)
				if lights_added < 6:
					_add_light(z, s.p + Vector2(0, -16.0 * sc), glow, 0.7, 1.6)
					lights_added += 1
			"struct_tower":
				if lights_added < 6:
					_add_light(z, s.p + Vector2(0, -26.0 * sc), accent, 0.55, 1.3, lights_added == 0)
					lights_added += 1

## Ambient clutter + depth so regions don't read as a bare floor with props in the
## corners: a wall-base shadow band, scattered small crates/barrels/cables, and
## faint pipe runs. All non-colliding decoration, kept out of the central lane.
static func _build_region_detail(parent: Node2D, theme: Dictionary, w: int, h: int) -> void:
	var z := Node2D.new()
	z.name = "Detail"
	parent.add_child(z)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var wall_c: Color = theme.get("wall", Color(0.6, 0.6, 0.7))
	var glow: Color = theme.get("glow", Color(0.6, 0.7, 0.9))

	# Soft shadow band under the top wall for depth.
	var band := ColorRect.new()
	band.size = Vector2(w - 40, 26)
	band.position = Vector2(20, 34)
	band.color = Color(0, 0, 0, 0.28)
	band.z_index = -59
	z.add_child(band)

	# Cable/pipe runs along the top, threading between the wall lights.
	for i in 3:
		var cable := ColorRect.new()
		cable.size = Vector2(rng.randf_range(160, 320), 4)
		cable.position = Vector2(rng.randf_range(120, w - 460), rng.randf_range(70, 96))
		cable.color = Color(glow.r * 0.5, glow.g * 0.5, glow.b * 0.5, 0.5)
		cable.z_index = -57
		z.add_child(cable)

	# Small clutter using the region's OWN pixel-art structure vocabulary (scaled
	# down), scattered around the perimeter away from the central spawn lane so it
	# reads as intentional set-dressing, never programmer-art squares.
	var structs: Array = theme.get("structs", [])
	if structs.is_empty():
		return
	var vocab: Array = []
	for s in structs:
		if s.get("t", "") != "" and s.t not in vocab:
			vocab.append(s.t)
	var center := Vector2(w * 0.5, h * 0.5)
	for i in 14:
		var p := Vector2(rng.randf_range(100, w - 100), rng.randf_range(130, h - 100))
		if p.distance_to(center) < 250.0:
			continue
		var tex_name: String = vocab[rng.randi() % vocab.size()]
		var sc := rng.randf_range(0.32, 0.5)
		var shade := rng.randf_range(-0.12, 0.08)
		var m := Color(clampf(wall_c.r + shade, 0, 1), clampf(wall_c.g + shade, 0, 1), clampf(wall_c.b + shade, 0, 1))
		var zi := _depth(p.y, 20.0 * sc)
		var spr := _put(z, tex_name, p, zi, sc, m)
		if spr:
			_drop_shadow(z, p + Vector2(0, 16.0 * sc), 80.0 * sc, zi - 1, 0.26)

## Thematic ambient particles for atmosphere/depth, three layers per the bible:
## (a) region-themed ambient (embers/spores/packets/sparks/data motes),
## (b) a subtle foreground dust layer drifting through the lights,
## (c) point-of-interest accent emitters. Budget: <=12 emitters, <=40 each.
static func _build_region_ambient(parent: Node2D, theme: Dictionary, w: int, h: int) -> void:
	var glow: Color = theme.get("glow", Color(0.6, 0.7, 0.9))
	var style: String = theme.get("ambient", "motes")
	var dot := _glow_dot()
	var p := CPUParticles2D.new()
	p.name = "Ambient"
	p.position = Vector2(w * 0.5, h * 0.5)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(w * 0.5 - 40, h * 0.5 - 40)
	p.z_index = -40
	p.amount = 36
	if dot:
		p.texture = dot
	match style:
		"embers":
			# Rise from the floor upward (negative Y is up). Emit low so the rise
			# is unmistakable, and keep them a strong saturated orange.
			p.lifetime = 3.0
			p.position.y += h * 0.28
			p.emission_rect_extents = Vector2(w * 0.5 - 40, h * 0.22)
			p.gravity = Vector2(0, -70)
			p.initial_velocity_min = 30.0
			p.initial_velocity_max = 70.0
			p.direction = Vector2(0, -1)
			p.spread = 18.0
			p.scale_amount_min = 2.5
			p.scale_amount_max = 4.5
			p.color = Color(1.0, 0.45, 0.12, 0.9)
		"sparks":
			# Alarm sparks shedding from the ceiling gantries. Production is fine.
			p.lifetime = 0.9
			p.position.y = 190
			p.emission_rect_extents = Vector2(w * 0.5 - 60, 40)
			p.gravity = Vector2(0, 260)
			p.initial_velocity_min = 60.0
			p.initial_velocity_max = 140.0
			p.direction = Vector2(0, 1)
			p.spread = 40.0
			p.scale_amount_min = 1.4
			p.scale_amount_max = 2.4
			p.color = Color(1.0, 0.55, 0.2, 0.9)
		"packets":
			# Data packets in transit, left to right. Latency not pictured.
			p.lifetime = 7.0
			p.gravity = Vector2.ZERO
			p.direction = Vector2(1, 0)
			p.spread = 4.0
			p.initial_velocity_min = 50.0
			p.initial_velocity_max = 90.0
			p.scale_amount_min = 1.6
			p.scale_amount_max = 2.6
			p.color = Color(0.42, 0.78, 1.0, 0.5)
		"spores":
			# Slow green spores: the only ecosystem still receiving maintenance.
			p.lifetime = 7.0
			p.gravity = Vector2(0, 9)
			p.initial_velocity_min = 3.0
			p.initial_velocity_max = 10.0
			p.spread = 180.0
			p.scale_amount_min = 1.8
			p.scale_amount_max = 3.4
			p.color = Color(0.35, 0.88, 0.49, 0.4)
		"dust":
			# Settling ruin dust, sepia like everything else from 2013.
			p.lifetime = 6.5
			p.gravity = Vector2(0, 12)
			p.initial_velocity_min = 2.0
			p.initial_velocity_max = 7.0
			p.spread = 180.0
			p.scale_amount_min = 1.5
			p.scale_amount_max = 3.0
			p.color = Color(0.91, 0.77, 0.42, 0.28)
		"sparkle":
			# Gold data motes drifting up off the reserves.
			p.lifetime = 2.6
			p.gravity = Vector2(0, -14)
			p.initial_velocity_min = 4.0
			p.initial_velocity_max = 16.0
			p.scale_amount_min = 1.5
			p.scale_amount_max = 3.5
			p.color = Color(1.0, 0.85, 0.35, 0.75)
		_:  # gentle drifting motes
			p.lifetime = 6.0
			p.gravity = Vector2(0, -6)
			p.initial_velocity_min = 3.0
			p.initial_velocity_max = 12.0
			p.spread = 180.0
			p.scale_amount_min = 1.5
			p.scale_amount_max = 3.0
			p.color = Color(glow.r, glow.g, glow.b, 0.35)
	parent.add_child(p)

	# (b) foreground dust motes — near-invisible until they cross a light.
	var dust := CPUParticles2D.new()
	dust.name = "ForegroundDust"
	dust.position = Vector2(w * 0.5, h * 0.5)
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	dust.emission_rect_extents = Vector2(w * 0.5 - 60, h * 0.5 - 60)
	dust.z_index = 350
	dust.amount = 20
	dust.lifetime = 9.0
	dust.gravity = Vector2(0, -4)
	dust.initial_velocity_min = 2.0
	dust.initial_velocity_max = 9.0
	dust.spread = 180.0
	dust.scale_amount_min = 1.2
	dust.scale_amount_max = 2.4
	dust.color = Color(1.0, 0.97, 0.9, 0.18)
	if dot:
		dust.texture = dot
	parent.add_child(dust)

	# (c) accent emitters at the first two points of interest.
	var pois: Array = theme.get("lights", [])
	for i in mini(2, pois.size()):
		var acc := CPUParticles2D.new()
		acc.name = "Accent%d" % i
		acc.position = pois[i]
		acc.z_index = 340
		acc.amount = 10
		acc.lifetime = 2.2
		acc.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		acc.emission_sphere_radius = 26.0
		acc.gravity = Vector2(0, -22)
		acc.initial_velocity_min = 6.0
		acc.initial_velocity_max = 18.0
		acc.spread = 180.0
		acc.scale_amount_min = 1.4
		acc.scale_amount_max = 2.6
		acc.color = Color(glow.r, glow.g, glow.b, 0.55)
		if dot:
			acc.texture = dot
		parent.add_child(acc)

static func _build_region_lights(parent: Node2D, theme: Dictionary) -> void:
	var i := 0
	for lp in theme.get("lights", []):
		# First anchor light in each region hums (bible: 2-4 flickers/region,
		# together with the struct + sign flickers).
		_add_light(parent, lp, theme.get("glow", Color(0.6, 0.8, 1.0)), 0.75, 4.0, i == 0)
		i += 1

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

## Ambient occlusion + grime: rooms stop looking pasted when the walls actually
## meet the floor. Everything exists()-guarded — art agents supply the decals.
static func _build_region_grounding(parent: Node2D, w: int, h: int) -> void:
	var z := Node2D.new()
	z.name = "Grounding"
	parent.add_child(z)
	_ao_edges(z, w, h)
	_grime(z, w, h, 9, 424243)

static func _ao_edges(parent: Node2D, w: int, h: int) -> void:
	var path := GEN + "decal_ao_edge.png"
	if not ResourceLoader.exists(path):
		return
	var tex: Texture2D = load(path)
	# [position, rotation, scale] — the 32px gradient is stretched along each
	# wall (it is uniform across, so stretching == tiling without 140 sprites).
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
		parent.add_child(s)

static func _grime(parent: Node2D, w: int, h: int, count: int, seed_v: int) -> void:
	var names: Array = []
	for i in 3:
		if ResourceLoader.exists(GEN + "decal_grime_%d.png" % i):
			names.append(GEN + "decal_grime_%d.png" % i)
	if names.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	for i in count:
		var s := Sprite2D.new()
		s.texture = load(names[rng.randi() % names.size()])
		s.position = Vector2(rng.randf_range(90, w - 90), rng.randf_range(110, h - 80))
		s.rotation = float(rng.randi() % 4) * PI * 0.5
		s.scale = Vector2.ONE * rng.randf_range(0.8, 1.5)
		s.modulate = Color(1, 1, 1, rng.randf_range(0.35, 0.6))
		s.z_index = -95
		parent.add_child(s)

static func _build_region_signs(parent: Node2D, theme: Dictionary) -> void:
	var z := Node2D.new()
	z.name = "Signs"
	parent.add_child(z)
	var idx := 0
	for sg in theme.get("signs", []):
		var col: Color = sg.get("c", Color(0.9, 0.9, 1.0))
		var lbl := Label.new()
		lbl.text = sg.t
		lbl.position = sg.p
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", col)
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		lbl.add_theme_constant_override("outline_size", 4)
		lbl.z_index = 400
		z.add_child(lbl)
		# Neon tube fixture over the text — unique flicker seed per sign so the
		# whole district never stutters in unison like a rendering bug.
		var tube := Sprite2D.new()
		tube.texture = _neon_tex(col)
		var mat := _shader_mat("neon_flicker", {"seed": float(idx) * 3.7 + sg.p.x * 0.013, "base_boost": 1.6})
		if mat:
			tube.material = mat
		tube.position = sg.p + Vector2(52, -10)
		tube.scale = Vector2(2.0, 1.4)
		tube.z_index = 399
		z.add_child(tube)
		_add_light(z, sg.p + Vector2(52, -4), col, 0.6, 1.8, idx == 0)
		idx += 1

## Region-specific screen-space dressing: heat shimmer over the GPU Mines' hot
## zone, data rain in the vault and down one production alley.
static func _build_region_fx(parent: Node2D, region_id: String, _theme: Dictionary, w: int, h: int) -> void:
	match region_id:
		"gpu_mines":
			var haze := _shader_mat("heat_haze", {"strength": 0.0026, "speed": 2.4})
			if haze:
				var rect := ColorRect.new()
				rect.name = "HeatHaze"
				rect.material = haze
				rect.position = Vector2(80, h * 0.42)
				rect.size = Vector2(w - 160, h * 0.52)
				rect.z_index = 820
				rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
				parent.add_child(rect)
			# Lava-glow pool under the shimmer so the hot zone reads HOT.
			_add_light(parent, Vector2(w * 0.5, h * 0.76), Color(1.0, 0.42, 0.18), 0.8, 6.0, true)
		"token_vault":
			var rain := _shader_mat("code_rain", {"tint": Color(1.0, 0.83, 0.3, 1.0), "alpha_max": 0.14, "columns": 42.0, "speed": 0.8})
			if rain:
				var rect := ColorRect.new()
				rect.name = "DataRain"
				rect.material = rain
				rect.position = Vector2(40, 60)
				rect.size = Vector2(w - 80, h - 120)
				rect.z_index = -35
				rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
				parent.add_child(rect)
			# Violet secondary accents in the dark corners (bible: GOLD/VIOLET).
			_add_light(parent, Vector2(160, 160), VIOLET, 0.5, 3.0)
			_add_light(parent, Vector2(w - 160, 160), VIOLET, 0.5, 3.0)
		"production":
			var rain := _shader_mat("code_rain", {"tint": Color(1.0, 0.28, 0.34, 1.0), "alpha_max": 0.12, "columns": 14.0, "speed": 1.6})
			if rain:
				var rect := ColorRect.new()
				rect.name = "LogSpew"  # one alley of scrolling stack traces
				rect.material = rain
				rect.position = Vector2(830, 130)
				rect.size = Vector2(180, h - 260)
				rect.z_index = -35
				rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
				parent.add_child(rect)

## Small cluster helper for composing themed set-dressing.
static func _clu(cx: float, cy: float, t: String, n: int, s: float, m: Color, spread: float) -> Array:
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = int(cx * 13.0 + cy * 7.0 + t.length())
	for i in n:
		out.append({
			"t": t,
			"p": Vector2(cx + rng.randf_range(-spread, spread), cy + rng.randf_range(-spread, spread)),
			"s": s * rng.randf_range(0.85, 1.12),
			"m": m,
		})
	return out

## Per-region theme: floor/glow palette, set-dressing structures, lights, signs.
## Structures are composed to frame the play space and fill dead corners while
## leaving the central spawn and the left/right portal lane walkable.
## Palettes follow the VISUAL_BIBLE per-region table: "glow" is the region's
## primary neon, "accent" its secondary; floors/walls are darker hue-matched
## tints (they multiply tech_floor / int_wall) so the neon has darkness to cut.
static func _region_theme(region_id: String) -> Dictionary:
	match region_id:
		"dependency_district":
			# ACID #A8FF3E over crate-orange #E08A3C.
			var structs := _clu(220, 200, "struct_crate", 4, 1.0, Color(0.88, 0.54, 0.24), 55)
			structs += _clu(1060, 220, "struct_crate", 4, 1.0, Color(0.82, 0.5, 0.22), 55)
			structs += _clu(230, 770, "struct_crate", 5, 1.1, Color(0.86, 0.52, 0.24), 70)
			structs += _clu(1060, 760, "struct_crate", 4, 1.0, Color(0.78, 0.46, 0.2), 60)
			structs += [{"t": "struct_tower", "p": Vector2(1140, 640), "s": 0.9, "m": Color(0.62, 0.78, 0.48)}]
			return {
				"floor": Color(0.38, 0.48, 0.34), "wall": Color(0.5, 0.64, 0.42),
				"glow": Color("#A8FF3E"), "accent": Color("#E08A3C"),
				"lights": [Vector2(220, 760), Vector2(1080, 240)], "structs": structs,
				"signs": [
					{"p": Vector2(150, 150), "t": "node_modules\n(event horizon)", "c": Color("#A8FF3E")},
					{"p": Vector2(900, 150), "t": "npm install\n(attempt #47)", "c": Color("#E08A3C")},
				],
			}
		"stackoverflow_ruins":
			# Dusty gold #E8C46B and copper #C97B4A: monument to answers past.
			var structs := [
				{"t": "struct_arch", "p": Vector2(300, 240), "s": 1.1, "m": Color(0.74, 0.68, 0.54)},
				{"t": "struct_arch", "p": Vector2(980, 250), "s": 1.0, "m": Color(0.68, 0.62, 0.5)},
			]
			structs += _clu(240, 760, "struct_slab", 3, 0.9, Color(0.68, 0.62, 0.52), 70)
			structs += _clu(1050, 740, "struct_slab", 3, 0.85, Color(0.62, 0.56, 0.48), 70)
			return {
				"floor": Color(0.5, 0.45, 0.35), "wall": Color(0.64, 0.57, 0.44),
				"glow": Color("#E8C46B"), "accent": Color("#C97B4A"), "ambient": "dust",
				"lights": [Vector2(300, 260), Vector2(980, 260)], "structs": structs,
				"signs": [
					{"p": Vector2(520, 150), "t": "Marked as duplicate.", "c": Color("#E8C46B")},
					{"p": Vector2(430, 820), "t": "Accepted Answer \u2014 2013", "c": Color("#C97B4A")},
				],
			}
		"api_bazaar":
			# Pink night market: MAGENTA #FF2D95 signage, GOLD #FFD34D goods.
			var structs := _clu(300, 200, "struct_console", 3, 0.9, Color(0.92, 0.72, 0.86), 90)
			structs += _clu(950, 210, "struct_console", 3, 0.9, Color(0.9, 0.68, 0.84), 90)
			structs += _clu(250, 770, "struct_crate", 4, 0.9, Color(0.86, 0.7, 0.36), 60)
			return {
				"floor": Color(0.44, 0.34, 0.44), "wall": Color(0.6, 0.44, 0.6),
				"glow": Color("#FF2D95"), "accent": Color("#FFD34D"),
				"lights": [Vector2(300, 210), Vector2(950, 210)], "structs": structs,
				"signs": [
					{"p": Vector2(560, 150), "t": "API keys \u2014 cash only", "c": Color("#FF2D95")},
					{"p": Vector2(560, 820), "t": "429: come back later", "c": Color("#FFD34D")},
				],
			}
		"cloud_district":
			# Sky #6BC7FF against near-white #E8F4FF: expensive weather.
			var structs := _clu(260, 220, "struct_orb", 2, 0.8, Color(0.62, 0.82, 1.0), 70)
			structs += _clu(1040, 230, "struct_orb", 2, 0.7, Color(0.76, 0.88, 1.0), 70)
			structs += _clu(250, 760, "struct_tower", 2, 0.8, Color(0.6, 0.68, 0.84), 60)
			structs += _clu(1050, 760, "struct_tower", 2, 0.8, Color(0.55, 0.63, 0.8), 60)
			return {
				"floor": Color(0.44, 0.52, 0.66), "wall": Color(0.6, 0.7, 0.88),
				"glow": Color("#6BC7FF"), "accent": Color("#E8F4FF"), "ambient": "packets",
				"lights": [Vector2(260, 220), Vector2(1040, 230), Vector2(640, 200)], "structs": structs,
				"signs": [
					{"p": Vector2(500, 150), "t": "The Cloud\n(it's just servers)", "c": Color("#6BC7FF")},
					{"p": Vector2(560, 820), "t": "Invoice: pending", "c": Color("#E8F4FF")},
				],
			}
		"open_source_wildlands":
			# Leaf #58E07C over moss #3E9E5C: verdant, mostly unmerged.
			var structs := [{"t": "struct_arch", "p": Vector2(640, 180), "s": 1.0, "m": Color(0.5, 0.76, 0.52)}]
			structs += _clu(240, 240, "struct_crate", 3, 0.9, Color(0.5, 0.7, 0.46), 55)
			structs += _clu(1050, 760, "struct_slab", 2, 0.85, Color(0.44, 0.66, 0.46), 60)
			structs += _clu(240, 770, "struct_crate", 3, 0.9, Color(0.46, 0.66, 0.42), 55)
			return {
				"floor": Color(0.36, 0.5, 0.38), "wall": Color(0.48, 0.66, 0.5),
				"glow": Color("#58E07C"), "accent": Color("#3E9E5C"), "ambient": "spores",
				"lights": [Vector2(640, 220), Vector2(240, 760)], "structs": structs,
				"signs": [
					{"p": Vector2(430, 320), "t": "Maintained by 1 volunteer", "c": Color("#58E07C")},
					{"p": Vector2(560, 820), "t": "PRs welcome (ignored)", "c": Color("#3E9E5C")},
				],
			}
		"corporate_enterprise":
			# Corp blue #4D7CFF behind glass #93A7C8: sterile on purpose.
			var structs: Array = []
			for gx in 3:
				for gy in 2:
					structs.append({"t": "struct_slab", "p": Vector2(320 + gx * 330, 220 + gy * 520), "s": 0.8, "m": Color(0.58, 0.63, 0.76)})
			return {
				"floor": Color(0.44, 0.48, 0.6), "wall": Color(0.58, 0.63, 0.78),
				"glow": Color("#4D7CFF"), "accent": Color("#93A7C8"),
				"lights": [Vector2(320, 220), Vector2(980, 740)], "structs": structs,
				"signs": [
					{"p": Vector2(540, 150), "t": "Synergy Zone", "c": Color("#4D7CFF")},
					{"p": Vector2(520, 830), "t": "Please raise a ticket.", "c": Color("#93A7C8")},
				],
			}
		"gpu_mines":
			# Ember #FF6B2D and heat #FF3D2D: everything here is thermal-throttled.
			var structs := _clu(240, 240, "struct_tower", 3, 0.9, Color(0.72, 0.5, 0.42), 70)
			structs += _clu(1050, 250, "struct_tower", 3, 0.9, Color(0.7, 0.46, 0.38), 70)
			structs += _clu(300, 770, "struct_crate", 4, 0.9, Color(0.74, 0.52, 0.4), 70)
			return {
				"floor": Color(0.5, 0.36, 0.3), "wall": Color(0.66, 0.46, 0.4),
				"glow": Color("#FF6B2D"), "accent": Color("#FF3D2D"), "ambient": "embers",
				"lights": [Vector2(240, 240), Vector2(1050, 250)], "structs": structs,
				"signs": [
					{"p": Vector2(560, 150), "t": "GPU go brrr", "c": Color("#FF6B2D")},
					{"p": Vector2(540, 830), "t": "Ambient temp: 94\u00b0C", "c": Color("#FF3D2D")},
				],
			}
		"production":
			# RED #FF4757 alarms over AMBER #FFB020 warnings. Everything is fine.
			var structs := [
				{"t": "struct_slab", "p": Vector2(640, 210), "s": 1.6, "m": Color(0.56, 0.4, 0.42)},
				{"t": "struct_tower", "p": Vector2(260, 260), "s": 0.9, "m": Color(0.64, 0.44, 0.44)},
				{"t": "struct_tower", "p": Vector2(1040, 260), "s": 0.9, "m": Color(0.64, 0.44, 0.44)},
			]
			structs += _clu(260, 770, "struct_crate", 3, 0.9, Color(0.78, 0.58, 0.3), 60)
			return {
				"floor": Color(0.5, 0.36, 0.38), "wall": Color(0.66, 0.44, 0.46),
				"glow": Color("#FF4757"), "accent": Color("#FFB020"), "ambient": "sparks",
				"lights": [Vector2(640, 260), Vector2(260, 260), Vector2(1040, 260)], "structs": structs,
				"signs": [
					{"p": Vector2(470, 150), "t": "PRODUCTION \u2014 DO NOT TOUCH", "c": Color("#FF4757")},
					{"p": Vector2(540, 830), "t": "Observability: vibes", "c": Color("#FFB020")},
				],
			}
		"token_vault":
			# GOLD #FFD34D hoard with VIOLET #8B5CF6 arcana in the corners.
			var structs := _clu(260, 240, "struct_orb", 2, 0.7, Color(1.0, 0.83, 0.3), 60)
			structs += _clu(1040, 240, "struct_orb", 2, 0.7, Color(1.0, 0.8, 0.28), 60)
			structs += _clu(260, 760, "struct_orb", 2, 0.6, Color(1.0, 0.86, 0.36), 60)
			structs += _clu(1040, 760, "struct_orb", 2, 0.6, Color(1.0, 0.82, 0.32), 60)
			return {
				"floor": Color(0.55, 0.47, 0.34), "wall": Color(0.72, 0.62, 0.42),
				"glow": Color("#FFD34D"), "accent": VIOLET, "ambient": "sparkle",
				"lights": [Vector2(260, 240), Vector2(1040, 240), Vector2(640, 500)], "structs": structs,
				"signs": [
					{"p": Vector2(540, 150), "t": "TOKEN RESERVES", "c": Color("#FFD34D")},
					{"p": Vector2(560, 830), "t": "Balance: yes", "c": Color("#B794FF")},
				],
			}
		_:
			return {
				"floor": Color(0.5, 0.5, 0.55), "wall": Color(0.68, 0.68, 0.78),
				"glow": Color("#24F0DC"), "accent": Color("#7DFFF0"),
				"lights": [Vector2(640, 480)], "structs": [], "signs": [],
			}

static func _populate_region(region_id: String, props: Node2D, enemies: Node2D, tokens: Node2D, npcs: Node2D, portals: Node2D, spawn: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var token_scene := preload("res://scenes/world/token_pickup.tscn")
	var enemy_scene := preload("res://scenes/combat/enemy.tscn")
	var npc_scene := preload("res://scenes/world/npc.tscn")
	var portal_scene := preload("res://scenes/world/region_portal.tscn")
	
	# Scatter tokens
	var token_count := 25
	var token_types := _region_token_types(region_id)
	for i in token_count:
		var t = token_scene.instantiate()
		t.token_type = token_types[rng.randi() % token_types.size()]
		t.position = _random_pos(rng, spawn)
		tokens.add_child(t)
	
	# Scatter enemies
	var enemy_types := _region_enemies(region_id)
	for e in enemy_types:
		var count: int = e.get("count", 2)
		for i in count:
			var en = enemy_scene.instantiate()
			en.enemy_type = e.type
			en.max_hp = e.get("hp", 30)
			en.is_boss = e.get("boss", false)
			# Place enemies beyond the enemy aggro radius (340) from the spawn so a
			# player arriving (or respawning) gets a moment to orient and then
			# CHOOSES to walk into combat — no fast-travel-into-a-swarm.
			en.position = _random_pos(rng, spawn, 420)
			enemies.add_child(en)
	
	# NPCs
	for npc_data in _region_npcs(region_id):
		var n = npc_scene.instantiate()
		n.npc_id = npc_data.id
		var qids: Array[String] = []
		for q in npc_data.get("quests", []):
			qids.append(str(q))
		n.quest_ids = qids
		n.position = npc_data.pos
		npcs.add_child(n)
	
	# Region-specific interactables
	_add_interactables(region_id, props, spawn)
	
	# Portals to connected regions
	for portal_data in _region_portals(region_id):
		if GameManager.is_region_unlocked(portal_data.to) or portal_data.get("always_open", false):
			var p = portal_scene.instantiate()
			p.target_region = portal_data.to
			p.portal_label = portal_data.get("label", portal_data.to)
			p.position = portal_data.pos
			portals.add_child(p)
			# Arcane spill so portals read as light sources from across the room.
			_add_light(props, portal_data.pos + Vector2(0, -8), VIOLET, 1.0, 3.2)

static func _random_pos(rng: RandomNumberGenerator, center: Vector2, min_dist: float = 80.0) -> Vector2:
	for attempt in 50:
		var pos := Vector2(
			rng.randf_range(TILE_SIZE * 2, (REGION_SIZE.x - 2) * TILE_SIZE),
			rng.randf_range(TILE_SIZE * 2, (REGION_SIZE.y - 2) * TILE_SIZE)
		)
		if pos.distance_to(center) > min_dist:
			return pos
	return center + Vector2(rng.randf_range(-300, 300), rng.randf_range(-300, 300))

static func _region_token_types(region_id: String) -> Array:
	match region_id:
		"localhost": return ["common", "common", "cached"]
		"stackoverflow_ruins": return ["cached", "cached", "common"]
		"api_bazaar": return ["premium", "common", "premium"]
		"gpu_mines": return ["compute", "compute", "common"]
		"token_vault": return ["golden", "frontier", "premium"]
		"cloud_district": return ["premium", "compute", "common"]
		_: return ["common", "cached"]

static func _region_enemies(region_id: String) -> Array:
	match region_id:
		"localhost":
			return [{"type": "bug", "count": 3, "hp": 20}]
		"dependency_district":
			# First combat region: a fair, winnable introduction (Localhost has 2).
			# 7 here was a difficulty spike a new player couldn't clear before the
			# swarm wore them down. Later regions ramp back up.
			return [{"type": "dependency_demon", "count": 2}, {"type": "null_reference", "count": 2}]
		"stackoverflow_ruins":
			return [{"type": "bug", "count": 3}, {"type": "merge_conflict", "count": 1, "hp": 80, "boss": true}]
		"api_bazaar":
			return [{"type": "rate_limiter", "count": 3}, {"type": "bug", "count": 2}]
		"cloud_district":
			return [{"type": "cloud_bill", "count": 1, "hp": 100, "boss": true}, {"type": "memory_leak", "count": 2}]
		"open_source_wildlands":
			return [{"type": "legacy_system", "count": 2}, {"type": "bug", "count": 3}]
		"corporate_enterprise":
			return [{"type": "enterprise_architect", "count": 1, "hp": 120, "boss": true}, {"type": "scope_creep", "count": 3}]
		"gpu_mines":
			return [{"type": "memory_leak", "count": 5}, {"type": "bug", "count": 2}]
		"production":
			return [{"type": "legacy_monolith", "count": 1, "hp": 200, "boss": true}, {"type": "hallucination", "count": 3}]
		"token_vault":
			return [{"type": "rate_limiter", "count": 2}, {"type": "infinite_context", "count": 1, "hp": 150, "boss": true}]
		_: return [{"type": "bug", "count": 2}]

static func _region_npcs(region_id: String) -> Array:
	match region_id:
		"localhost":
			return [{"id": "roommate_ai", "pos": Vector2(1200, 900), "quests": ["hello_localhost", "tiny_change", "ship_dream_app"]}]
		"dependency_district":
			return [{"id": "maintainer", "pos": Vector2(1100, 800), "quests": ["install_node", "fix_without_touching"]}]
		"stackoverflow_ruins":
			return [{"id": "stackoverflow_hermit", "pos": Vector2(1000, 700), "quests": ["stackoverflow_pilgrimage", "merge_conflict_hell"]}]
		"api_bazaar":
			return [{"id": "api_reseller", "pos": Vector2(1300, 850), "quests": ["one_more_api_call", "junior_agent"]}, {"id": "junior_agent", "pos": Vector2(800, 600), "quests": ["junior_agent"]}]
		"cloud_district":
			return [{"id": "cloud_salesperson", "pos": Vector2(1200, 750), "quests": ["cloud_migration", "context_window_full"]}]
		"open_source_wildlands":
			return [{"id": "oss_maintainer", "pos": Vector2(1100, 900), "quests": ["license_puzzle"]}]
		"corporate_enterprise":
			return [{"id": "svp_ai", "pos": Vector2(1000, 800), "quests": ["enterprise_ready"]}]
		"gpu_mines":
			return [{"id": "gpu_foreman", "pos": Vector2(1200, 700), "quests": ["gpu_rush"]}]
		"production":
			return [{"id": "oncall_engineer", "pos": Vector2(1100, 850), "quests": ["production_down"]}]
		_: return []

static func _region_portals(region_id: String) -> Array:
	var cx := REGION_SIZE.x * TILE_SIZE * 0.5
	var cy := REGION_SIZE.y * TILE_SIZE * 0.5
	match region_id:
		"localhost":
			return [{"to": "dependency_district", "pos": Vector2(cx + 400, cy), "label": "Dependency District"}]
		"dependency_district":
			return [
				{"to": "localhost", "pos": Vector2(cx - 400, cy), "label": "Localhost"},
				{"to": "stackoverflow_ruins", "pos": Vector2(cx + 400, cy), "label": "Stack Overflow Ruins"},
			]
		"stackoverflow_ruins":
			return [
				{"to": "dependency_district", "pos": Vector2(cx - 400, cy), "label": "Dependency District"},
				{"to": "api_bazaar", "pos": Vector2(cx + 400, cy), "label": "API Bazaar"},
			]
		"api_bazaar":
			return [
				{"to": "stackoverflow_ruins", "pos": Vector2(cx - 400, cy), "label": "Stack Overflow Ruins"},
				{"to": "cloud_district", "pos": Vector2(cx + 400, cy), "label": "Cloud District"},
			]
		"cloud_district":
			return [
				{"to": "api_bazaar", "pos": Vector2(cx - 400, cy), "label": "API Bazaar"},
				{"to": "open_source_wildlands", "pos": Vector2(cx + 400, cy), "label": "Open Source Wildlands"},
			]
		"open_source_wildlands":
			return [
				{"to": "cloud_district", "pos": Vector2(cx - 400, cy), "label": "Cloud District"},
				{"to": "corporate_enterprise", "pos": Vector2(cx + 400, cy), "label": "Corporate Enterprise"},
			]
		"corporate_enterprise":
			return [
				{"to": "open_source_wildlands", "pos": Vector2(cx - 400, cy), "label": "Open Source Wildlands"},
				{"to": "gpu_mines", "pos": Vector2(cx + 400, cy), "label": "GPU Mines"},
			]
		"gpu_mines":
			return [
				{"to": "corporate_enterprise", "pos": Vector2(cx - 400, cy), "label": "Corporate Enterprise"},
				{"to": "production", "pos": Vector2(cx + 400, cy), "label": "Production"},
			]
		"production":
			return [
				{"to": "gpu_mines", "pos": Vector2(cx - 400, cy), "label": "GPU Mines"},
				{"to": "token_vault", "pos": Vector2(cx + 400, cy), "label": "Token Vault"},
			]
		"token_vault":
			return [
				{"to": "production", "pos": Vector2(cx - 400, cy), "label": "Production"},
				{"to": "localhost", "pos": Vector2(cx, cy - 400), "label": "Return to Localhost"},
			]
		_: return []

## Theme-specific environmental comedy props per region (reward exploration
## everywhere, not just Localhost). Positions live in the walkable interior
## (~128..1152 x, 128..832 y; only walls collide) and away from the central spawn.
const REGION_FLAVOR := {
	"dependency_district": [
		["prop_node_modules", Vector2(300, 300), "node_modules"],
		["prop_leftpad", Vector2(980, 320), "left-pad"],
		["prop_lockfile", Vector2(520, 780), "package-lock.json"],
	],
	"api_bazaar": [
		["prop_api_stall", Vector2(300, 320), "API reseller stall"],
		["prop_status_page", Vector2(980, 340), "Status page"],
		["prop_pricing", Vector2(560, 780), "Pricing board"],
	],
	"stackoverflow_ruins": [
		["prop_gravestone", Vector2(320, 320), "Question gravestone"],
		["prop_accepted", Vector2(960, 340), "Accepted answer"],
	],
	"cloud_district": [
		["prop_invoice", Vector2(320, 320), "Cloud invoice"],
		["prop_dashboard", Vector2(980, 340), "Cloud dashboard"],
	],
	"gpu_mines": [
		["prop_rig", Vector2(320, 320), "Mining rig"],
		["prop_fan", Vector2(980, 340), "Cooling fan"],
	],
	"open_source_wildlands": [
		["prop_sponsor", Vector2(320, 320), "Sponsor button"],
		["prop_issue", Vector2(980, 340), "Open issue #4092"],
	],
	"corporate_enterprise": [
		["prop_mission", Vector2(320, 320), "Mission statement"],
		["prop_kanban", Vector2(980, 340), "Kanban board"],
	],
	"production": [
		["prop_pager", Vector2(320, 320), "On-call pager"],
		["prop_runbook", Vector2(980, 340), "Incident runbook"],
	],
	"token_vault": [
		["prop_vault", Vector2(360, 340), "Token vault"],
	],
}

static func _add_interactables(region_id: String, props: Node2D, _spawn: Vector2) -> void:
	var interact_scene := preload("res://scenes/world/generic_interactable.tscn")
	match region_id:
		"dependency_district":
			_add_prop(props, interact_scene, "abandoned_package", Vector2(700, 620), "Recover package")
		"api_bazaar":
			_add_prop(props, interact_scene, "backup_server", Vector2(760, 640), "Backup Server")
	# Region flavor props (subtle markers; the floating [E] prompt points them out).
	for entry in REGION_FLAVOR.get(region_id, []):
		var pr = _add_prop(props, interact_scene, entry[0], entry[1], entry[2])
		pr.one_shot = false
		var rect := pr.get_node_or_null("ColorRect")
		if rect:
			rect.color = Color(0.42, 0.82, 0.88, 0.30)
			rect.offset_left = -7.0
			rect.offset_top = -7.0
			rect.offset_right = 7.0
			rect.offset_bottom = 7.0

static func _add_prop(parent: Node2D, scene: PackedScene, id: String, pos: Vector2, text: String) -> Node:
	var node = scene.instantiate()
	node.interact_id = id
	node.interact_text = text
	node.position = pos
	parent.add_child(node)
	return node
