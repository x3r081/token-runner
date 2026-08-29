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

## Caption priority for the phase currently being built. Set-piece captions name
## the LANDMARKS ("WAR ROOM", "THE RESERVES") and are placed first at priority 2;
## the theme's flavour signs follow at 1, so a crowded room drops a gag before it
## drops the caption that tells you what you are looking at.
static var _sign_prio := 1

static func _build_region_static(parent: Node2D, region_id: String) -> Dictionary:
	parent.y_sort_enabled = true
	var theme := _region_theme(region_id)
	var w := REGION_SIZE.x * TILE_SIZE
	var h := REGION_SIZE.y * TILE_SIZE
	var spawn_pos := Vector2(w * 0.5, h * 0.5)

	_reserve_labels(region_id, w, h)
	_build_floor_themed(parent, theme, w, h, region_id)
	_build_walls_themed(parent, theme, w, h)
	_build_region_grounding(parent, w, h)
	_build_midground(parent, theme, w, h)
	_build_structures(parent, theme)
	_sign_prio = 2
	_build_setpieces(parent, region_id, theme, w, h)
	_sign_prio = 1
	_build_region_detail(parent, theme, w, h)
	_build_region_ambient(parent, theme, w, h)
	_build_region_lights(parent, theme, w, h)
	_build_region_signs(parent, theme)
	_build_poi_pools(parent, region_id, theme)
	_build_region_fx(parent, region_id, theme, w, h)
	_build_foreground(parent, theme, w, h)

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

static func _put(parent: Node2D, tex_name: String, pos: Vector2, z: int, scale: float = 1.0, mod: Color = Color.WHITE, rot: float = 0.0) -> Sprite2D:
	var t := _tex(tex_name)
	if not t:
		return null
	var s := Sprite2D.new()
	s.texture = t
	s.position = pos
	s.z_index = z
	s.scale = Vector2(scale, scale)
	s.rotation = rot
	s.modulate = mod
	parent.add_child(s)
	return s

static func _depth(pos_y: float, half_h: float) -> int:
	return int(pos_y + half_h)

## Set-dressing sprite with a grounded drop shadow and y-sorted depth, measured
## from the real texture so tall props (towers) and flat ones (crates) both sit
## ON the floor instead of hovering next to it.
static func _prop(parent: Node2D, tex_name: String, pos: Vector2, sc: float = 1.0, mod: Color = Color.WHITE, rot: float = 0.0, shadow: float = 1.0) -> Sprite2D:
	var spr := _put(parent, tex_name, pos, _depth(pos.y, 40.0 * sc), sc, mod, rot)
	if not spr:
		return null
	var half := float(spr.texture.get_height()) * 0.5 * sc
	spr.z_index = _depth(pos.y, half * 0.92)
	if shadow > 0.0:
		_drop_shadow(parent, pos + Vector2(0, half * 0.86), float(spr.texture.get_width()) * sc * 1.1, spr.z_index - 1, 0.32 * shadow)
	return spr

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

## Additive rect — for anything that should read as EMITTING rather than being lit.
static func _glow_rect(parent: Node2D, center: Vector2, size: Vector2, col: Color, z: int, rot: float = 0.0) -> ColorRect:
	var r := _rect(parent, center, size, col, z, rot)
	r.material = _additive_mat()
	return r

## Deterministic per-cell hash. Floor variation must be byte-identical every time
## a region rebuilds (you re-enter regions constantly), so this replaces the old
## sequential RNG whose pattern shifted whenever draw order changed.
static func _cell_hash(x: int, y: int) -> int:
	var v := (x * 374761393 + y * 668265263) & 0x7FFFFFFF
	v = ((v ^ (v >> 13)) * 1274126177) & 0x7FFFFFFF
	return (v ^ (v >> 16)) & 0x7FFFFFFF

## Floor zoning. A room at one flat value is a void with props in it. The spawn
## gets a bright landing plaza, the portal-to-portal artery gets a worn traffic
## lane, and the perimeter falls off — so the eye immediately knows where the
## room's "somewhere" is, and the ground reads as ground.
static func _floor_zone(p: Vector2, w: float, h: float) -> float:
	var k := 1.0
	var lane := absf(p.y - h * 0.5)
	if lane < 96.0 and p.x > 130.0 and p.x < w - 130.0:
		k += 0.22 * (1.0 - lane / 96.0)
	var d := p.distance_to(Vector2(w * 0.5, h * 0.5))
	if d < 220.0:
		k += 0.18 * (1.0 - d / 220.0)
	var e := minf(minf(p.x, w - p.x), minf(p.y - 46.0, h - p.y))
	if e < 156.0:
		k -= 0.28 * (1.0 - maxf(e, 0.0) / 156.0)
	return k

## Smooth low-frequency wear field: coarse 4-tile cells hashed to a value, then
## bilinearly blended. Multiplied into per-tile brightness it produces broad
## soiled/scrubbed BLOTCHES across the room — which is what actually kills the
## read of a 64px lattice. Per-tile jitter alone only makes the lattice noisy;
## the eye still locks onto the grid because every cell differs from every
## neighbour by the same amount. Blotches give it something larger to look at.
static func _floor_wear(x: int, y: int) -> float:
	var cx := x >> 2
	var cy := y >> 2
	var fx := float(x & 3) / 4.0
	var fy := float(y & 3) / 4.0
	var v00 := float(_cell_hash(cx, cy) % 1000) / 1000.0
	var v10 := float(_cell_hash(cx + 1, cy) % 1000) / 1000.0
	var v01 := float(_cell_hash(cx, cy + 1) % 1000) / 1000.0
	var v11 := float(_cell_hash(cx + 1, cy + 1) % 1000) / 1000.0
	return 0.88 + lerpf(lerpf(v00, v10, fx), lerpf(v01, v11, fx), fy) * 0.22

## Three floor families per region — the neutral tech deck plus the two
## region-authored tile variants. The family is picked per 2x2 BLOCK, not per
## tile: the floor then reads as poured slabs of one material rather than a
## three-colour checkerboard, and ~14% of tiles break their block on purpose so
## the blocks themselves don't become the new visible grid.
static func _build_floor_themed(parent: Node2D, theme: Dictionary, w: int, h: int, region_id: String) -> void:
	var floor_node := Node2D.new()
	floor_node.name = "Floor"
	parent.add_child(floor_node)
	var tint: Color = theme.get("floor", Color(0.62, 0.62, 0.68))
	var suffix: String = REGION_TILE_MAP.get(region_id, "")
	var has_a := suffix != "" and ResourceLoader.exists(GEN + "tile_" + suffix + ".png")
	var has_b := suffix != "" and ResourceLoader.exists(GEN + "tile_" + suffix + "_b.png")
	var tile_mul: float = float(theme.get("tile_mul", 2.2))
	for x in REGION_SIZE.x:
		for y in REGION_SIZE.y:
			var hv := _cell_hash(x, y)
			var p := Vector2(x * TILE_SIZE + TILE_SIZE * 0.5, y * TILE_SIZE + TILE_SIZE * 0.5)
			var k := _floor_zone(p, float(w), float(h)) \
				* _floor_wear(x, y) \
				* (1.0 + (float(hv % 61) / 61.0 - 0.5) * 0.13)
			var fam := _cell_hash(x >> 1, (y >> 1) + 7919) % 10
			if hv % 100 < 14:
				fam = (hv >> 7) % 10  # one tile that does not match its slab
			var tex_name := "tech_floor"
			# Per-cell hue drift as well as value drift: identical texture, three
			# slightly different ages of grout.
			var warm := (float((hv >> 11) % 41) / 41.0 - 0.5) * 0.05
			var m := Color(tint.r * k * (1.0 + warm), tint.g * k, tint.b * k * (1.0 - warm))
			if has_a and fam < 3:
				tex_name = "tile_" + suffix
				m = Color(k * tile_mul * (1.0 + warm), k * tile_mul, k * tile_mul * (1.0 - warm))
			elif has_b and fam < 6:
				# 1.12, not 1.3. A ~30% value step between neighbouring cells
				# reads as a checkerboard no matter how good the tile art is;
				# _floor_zone / _floor_wear carry the large-scale variation.
				var b := k * tile_mul * 1.12
				tex_name = "tile_" + suffix + "_b"
				m = Color(b * (1.0 + warm), b, b * (1.0 - warm))
			if (hv >> 5) % 29 == 0:
				m = m.darkened(0.26)  # a cell something bad happened on
			_put(floor_node, tex_name, p, -100, 1.0, m)
	_floor_seams(floor_node, w, h)
	_floor_blotches(floor_node, theme, w, h)
	_floor_mottle(floor_node, theme, w, h, region_id)
	_paint_lane(floor_node, theme, w, h)
	var glow: Color = theme.get("glow", Color.WHITE)
	_paint_wayfinding(floor_node, region_id, w, h, glow)
	_floor_litter(floor_node, theme, w, h, region_id)

## Expansion joints: multi-tile grout lines that do NOT follow the 64px lattice
## everywhere, so the floor reads as slabs of irregular size. Deterministic (the
## room must rebuild identically every time you walk back into it).
static func _floor_seams(parent: Node2D, w: int, h: int) -> void:
	for i in 14:
		var sh := _cell_hash(i, 913)
		var horiz := (sh % 2) == 0
		var span := 2.0 + float((sh >> 3) % 4)
		var gx := float((sh >> 6) % REGION_SIZE.x) * float(TILE_SIZE)
		var gy := 128.0 + float((sh >> 12) % (REGION_SIZE.y - 3)) * float(TILE_SIZE)
		var len_px := span * float(TILE_SIZE)
		if horiz:
			_rect(parent, Vector2(gx + len_px * 0.5, gy), Vector2(len_px, 3.0), Color(0, 0, 0, 0.30), -98)
			_rect(parent, Vector2(gx + len_px * 0.5, gy + 2.0), Vector2(len_px, 1.0), Color(1, 1, 1, 0.045), -97)
		else:
			_rect(parent, Vector2(gx, gy + len_px * 0.5), Vector2(3.0, len_px), Color(0, 0, 0, 0.30), -98)
			_rect(parent, Vector2(gx + 2.0, gy + len_px * 0.5), Vector2(1.0, len_px), Color(1, 1, 1, 0.045), -97)

## One full-floor pass of ground_mottle.gdshader (blend_mul): slow, non-repeating
## darkening at a frequency far below the 64px tile pitch, plus an off-axis grit
## octave that competes with the lattice directly. The blotches and seams are
## hard-edged history; this is the dirt underneath all of it.
##
## z -93, not the shader header's suggested -90: the painted lane (-93, drawn
## after), the wayfinding chevrons (-92) and the floor litter (-91) are the
## navigation line-work and must not be dimmed by 30% of anything. Everything
## below — tiles, seams, blotches, grime — wears. exists()-guarded, so a missing
## shader just leaves the hand-authored wear in place.
static func _floor_mottle(parent: Node2D, theme: Dictionary, w: int, h: int, region_id: String) -> void:
	var tint: Color = theme.get("floor", Color(0.7, 0.7, 0.75))
	var mat := _shader_mat("ground_mottle", {
		"amount": 0.27,
		"darkest": 0.63,
		"floor_scale": 2.4,
		"detail_scale": 7.0,
		"streak": 0.42,
		"grit": 0.55,
		"grit_scale": 27.0,
		"grit_rot": 0.55,
		"aspect": Vector2(float(w) / float(h), 1.0),
		"seed": float(absi(region_id.hash()) % 977) * 0.01,
		"tint": Vector3(lerpf(1.0, tint.r, 0.3), lerpf(1.0, tint.g, 0.3), lerpf(1.0, tint.b, 0.3)),
	})
	if not mat:
		return
	var rect := ColorRect.new()
	rect.name = "Mottle"
	rect.material = mat
	rect.position = Vector2.ZERO
	rect.size = Vector2(float(w), float(h))
	rect.z_index = -93
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)

## Big soft stains at non-grid positions and non-grid sizes. Nothing here lines
## up with a tile edge, which is exactly the point: overlapping ellipses read as
## an aged deck and hide the lattice underneath them.
static func _floor_blotches(parent: Node2D, theme: Dictionary, w: int, h: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 606061
	var glow: Color = theme.get("glow", Color(0.6, 0.7, 0.9))
	for i in 22:
		var p := Vector2(rng.randf_range(70, w - 70), rng.randf_range(96, h - 50))
		var width := rng.randf_range(150.0, 460.0)
		if rng.randf() < 0.72:
			_floor_patch(parent, p, width, Color(0.012, 0.014, 0.03), rng.randf_range(0.10, 0.26), -97)
		else:
			# Scrubbed patches: somebody cleaned exactly this much and gave up.
			_floor_patch(parent, p, width * 0.7, Color(glow.r, glow.g, glow.b), rng.randf_range(0.03, 0.07), -97)

## Painted markings on the traffic lane and the landing plaza. Cheap, flat, and
## the single biggest readability win: the floor now has line-work on it.
static func _paint_lane(parent: Node2D, theme: Dictionary, w: int, h: int) -> void:
	var accent: Color = theme.get("accent", Color(0.8, 0.8, 0.9))
	var glow: Color = theme.get("glow", Color.WHITE)
	var cy := h * 0.5
	for k: float in [1.0, -1.0]:
		_rect(parent, Vector2(w * 0.5, cy + k * 100.0), Vector2(w - 320.0, 3.0), Color(accent.r, accent.g, accent.b, 0.13), -93)
		# hazard dashes just inside the painted edge
		for i in 13:
			var dx := 190.0 + float(i) * 76.0
			_rect(parent, Vector2(dx, cy + k * 92.0), Vector2(30.0, 6.0), Color(accent.r, accent.g, accent.b, 0.07), -93, 0.5 * k)
	# Landing plaza ring at the spawn: "you are here".
	_floor_patch(parent, Vector2(w * 0.5, cy), 430.0, glow, 0.055, -95)
	for i in 26:
		var a := TAU * float(i) / 26.0
		_rect(parent, Vector2(w * 0.5, cy) + Vector2(cos(a) * 168.0, sin(a) * 104.0), Vector2(13.0, 4.0), Color(accent.r, accent.g, accent.b, 0.11), -93, a)

## Chevron trails painted from the plaza toward every portal this region owns.
## The player asked "what now, and WHERE" — this is the floor answering.
static func _paint_wayfinding(parent: Node2D, region_id: String, w: int, h: int, col: Color) -> void:
	var center := Vector2(w * 0.5, h * 0.5)
	for pd in _region_portals(region_id):
		var pp: Vector2 = pd.pos
		var to := pp - center
		var dist := to.length()
		if dist < 150.0:
			continue
		var dir := to / dist
		var ang := dir.angle()
		var steps := int((dist - 190.0) / 84.0)
		for i in steps:
			var t := 190.0 + float(i) * 84.0
			var a := 0.20 + 0.02 * float(i)
			_chevron(parent, center + dir * t, Color(col.r, col.g, col.b, a), ang, -92)

static func _chevron(parent: Node2D, pos: Vector2, col: Color, ang: float, z: int) -> void:
	var n := Vector2(cos(ang), sin(ang))
	var side := Vector2(-n.y, n.x)
	_rect(parent, pos + side * -6.0, Vector2(26.0, 5.0), col, z, ang + 0.46)
	_rect(parent, pos + side * 6.0, Vector2(26.0, 5.0), col, z, ang - 0.46)

## Small hard-edged floor litter: bolts, hairline cracks, spilled coolant chips,
## drain grates. Reads as texture underfoot at a glance, as story up close.
## Tile-independent floor marks. The grid you can see is half a tile problem and
## half an "everything lands on a 64px boundary" problem; these are alpha-only
## PNGs dropped at arbitrary positions, rotations and scales, so they inherit
## whatever floor is under them and cut across the lattice instead of agreeing
## with it. Deterministic per region — walk back in and the room is the room.
const DECAL_HOMES := {
	"gpu_mines": ["decal_scorch", "decal_crack_0", "decal_crack_1"],
	"production": ["decal_scorch", "decal_scorch", "decal_crack_1"],
	"cloud_district": ["decal_puddle", "decal_puddle", "decal_crack_0"],
	"open_source_wildlands": ["decal_puddle", "decal_crack_0", "decal_crack_1"],
	"stackoverflow_ruins": ["decal_crack_0", "decal_crack_1", "decal_crack_1"],
}

static func _floor_decals(parent: Node2D, region_id: String, w: int, h: int) -> void:
	var pool: Array = DECAL_HOMES.get(region_id, ["decal_crack_0", "decal_crack_1"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 918273 + int(region_id.hash() & 0xFFFF)
	for i in 9:
		var name_i: String = str(pool[rng.randi() % pool.size()])
		var pos := Vector2(rng.randf_range(150, float(w) - 150), rng.randf_range(170, float(h) - 120))
		var spr := _put(parent, name_i, pos, -91, rng.randf_range(0.75, 1.7),
			Color(1, 1, 1, rng.randf_range(0.35, 0.72)), rng.randf_range(-PI, PI))
		if spr == null:
			return  # generator has not been run; nothing to scatter

static func _floor_litter(parent: Node2D, theme: Dictionary, w: int, h: int, region_id: String = "") -> void:
	_floor_decals(parent, region_id, w, h)
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var glow: Color = theme.get("glow", Color(0.6, 0.7, 0.9))
	# Drag marks: long, thin, arbitrarily angled. Something heavy was moved here
	# by someone who did not lift it, and no tile edge is involved.
	for i in 16:
		var sp := Vector2(rng.randf_range(120, w - 120), rng.randf_range(140, h - 90))
		var ang := rng.randf_range(-PI, PI)
		var seg := rng.randf_range(60.0, 190.0)
		for k: float in [1.0, -1.0]:
			_rect(parent, sp + Vector2(-sin(ang), cos(ang)) * k * 5.0, Vector2(seg, 2.0), Color(0, 0, 0, 0.20), -91, ang)
	for i in 78:
		var dp := Vector2(rng.randf_range(80, w - 80), rng.randf_range(96, h - 64))
		match rng.randi() % 5:
			0:
				_rect(parent, dp, Vector2(rng.randf_range(3, 7), rng.randf_range(3, 7)), Color(0, 0, 0, rng.randf_range(0.14, 0.3)), -91)
			1:
				_rect(parent, dp, Vector2(rng.randf_range(12, 30), 2.0), Color(0, 0, 0, 0.24), -91, rng.randf_range(-1.2, 1.2))
			2:
				_rect(parent, dp, Vector2(rng.randf_range(3, 6), rng.randf_range(3, 6)), Color(glow.r, glow.g, glow.b, 0.18), -91)
			3:  # bolt head with a top-left highlight, per the bible's light rule
				_rect(parent, dp, Vector2(5, 5), Color(0, 0, 0, 0.35), -91)
				_rect(parent, dp - Vector2(1, 1), Vector2(2, 2), Color(1, 1, 1, 0.12), -90)
			_:  # drain grate / vent slats
				for s in 3:
					_rect(parent, dp + Vector2(0, float(s) * 4.0), Vector2(18, 2), Color(0, 0, 0, 0.3), -91)

static func _build_walls_themed(parent: Node2D, theme: Dictionary, w: int, h: int) -> void:
	var walls := Node2D.new()
	walls.name = "Walls"
	parent.add_child(walls)
	var wall_tint: Color = theme.get("wall", Color(0.7, 0.7, 0.8))
	var glow: Color = theme.get("glow", Color(0.6, 0.8, 1.0))
	for x in REGION_SIZE.x:
		var px := x * TILE_SIZE + TILE_SIZE / 2
		var jitter := (float(_cell_hash(x, 3) % 41) / 41.0 - 0.5) * 0.12
		_put(walls, "int_wall", Vector2(px, 16), -60, 1.0, Color(wall_tint.r + jitter, wall_tint.g + jitter, wall_tint.b + jitter))
		_add_collider(walls, Vector2(px, 24), Vector2(TILE_SIZE, 56))
		_add_collider(walls, Vector2(px, h - 6), Vector2(TILE_SIZE, 20))
	for y in REGION_SIZE.y:
		var py := y * TILE_SIZE + TILE_SIZE / 2
		_put(walls, "int_wall_side", Vector2(20, py), -58, 1.0, wall_tint)
		_put(walls, "int_wall_side", Vector2(w - 20, py), -58, 1.0, wall_tint.darkened(0.15))
		_add_collider(walls, Vector2(6, py), Vector2(20, TILE_SIZE))
		_add_collider(walls, Vector2(w - 6, py), Vector2(20, TILE_SIZE))
	# Service run along the top wall: conduit, junction boxes, drip streaks.
	_rect(walls, Vector2(w * 0.5, 52.0), Vector2(w - 80.0, 5.0), Color(0.03, 0.035, 0.06, 0.8), -56)
	for i in 7:
		var bx := 120.0 + float(i) * (w - 240.0) / 6.0
		_rect(walls, Vector2(bx, 50.0), Vector2(22, 16), Color(0.06, 0.07, 0.1, 0.9), -55)
		_glow_rect(walls, Vector2(bx + 6.0, 50.0), Vector2(3, 3), Color(glow.r, glow.g, glow.b, 0.5), -54)
		_rect(walls, Vector2(bx - 30.0, 34.0), Vector2(3.0, 30.0), Color(0, 0, 0, 0.22), -55)

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

## Distant silhouettes between the wall and the play area — the same structure
## vocabulary, drawn small and nearly black, so the room has a background layer
## instead of a hard cut from wall to floor.
static func _build_midground(parent: Node2D, theme: Dictionary, w: int, _h: int) -> void:
	var z := Node2D.new()
	z.name = "Midground"
	parent.add_child(z)
	var vocab := _vocab(theme)
	if vocab.is_empty():
		return
	var glow: Color = theme.get("glow", Color(0.6, 0.7, 0.9))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	for i in 9:
		var px := 90.0 + float(i) * (w - 180.0) / 8.0 + rng.randf_range(-22, 22)
		var py := rng.randf_range(108, 152)
		var sc := rng.randf_range(0.5, 0.85)
		var v := rng.randf_range(0.22, 0.34)
		_put(z, str(vocab[rng.randi() % vocab.size()]), Vector2(px, py), -50, sc, Color(v, v, v * 1.15))
		if rng.randf() < 0.4:
			_glow_rect(z, Vector2(px + rng.randf_range(-10, 10), py - rng.randf_range(4, 18)), Vector2(3, 3), Color(glow.r, glow.g, glow.b, 0.4), -49)
	# Atmospheric haze band so the far end of the room recedes.
	_rect(z, Vector2(w * 0.5, 130.0), Vector2(w - 60.0, 110.0), Color(glow.r * 0.35, glow.g * 0.35, glow.b * 0.4, 0.07), -48)
	# Second, CLOSER silhouette band drawn in front of the haze: bigger, darker,
	# overlapping the far band. Two planes of depth instead of one row of dots —
	# this is what stops the top of every room reading as a painted backdrop.
	for i in 7:
		var px2 := 150.0 + float(i) * (w - 300.0) / 6.0 + rng.randf_range(-32, 32)
		var py2 := rng.randf_range(160, 190)
		var sc2 := rng.randf_range(0.68, 1.05)
		var v2 := rng.randf_range(0.13, 0.21)
		_put(z, str(vocab[rng.randi() % vocab.size()]), Vector2(px2, py2), -47, sc2, Color(v2, v2, v2 * 1.2))
		if rng.randf() < 0.5:
			_glow_rect(z, Vector2(px2 + rng.randf_range(-14, 14), py2 - rng.randf_range(6, 26)), Vector2(4, 4), Color(glow.r, glow.g, glow.b, 0.3), -46)

## Foreground layer. Overhead conduit and slack cable across the top of the frame
## and a dark sill along the bottom: the room is now looked INTO, not down at.
static func _build_foreground(parent: Node2D, theme: Dictionary, w: int, h: int) -> void:
	var z := Node2D.new()
	z.name = "Foreground"
	parent.add_child(z)
	var glow: Color = theme.get("glow", Color(0.6, 0.7, 0.9))
	# Ceiling beam across the very top (above anywhere the player can stand).
	_rect(z, Vector2(w * 0.5, 30.0), Vector2(w + 40.0, 30.0), Color(0.02, 0.025, 0.045, 0.95), 500)
	_rect(z, Vector2(w * 0.5, 45.0), Vector2(w + 40.0, 2.0), Color(glow.r, glow.g, glow.b, 0.16), 501)
	for i in 5:
		var bx := 140.0 + float(i) * (w - 280.0) / 4.0
		_rect(z, Vector2(bx, 40.0), Vector2(14, 46), Color(0.02, 0.025, 0.045, 0.9), 500)
	# Slack cable drooping out of the ceiling — thin enough to never hide play.
	for i in 3:
		var line := Line2D.new()
		var x0 := 200.0 + float(i) * (w - 400.0) / 2.0
		line.width = 3.0
		line.default_color = Color(0.02, 0.02, 0.035, 0.85)
		line.z_index = 502
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.add_point(Vector2(x0 - 120.0, 44.0))
		line.add_point(Vector2(x0 - 40.0, 96.0 + float(i % 2) * 26.0))
		line.add_point(Vector2(x0 + 60.0, 52.0))
		z.add_child(line)
	# Overhead cable trays crossing the frame IN FRONT of everything. They cost a
	# handful of rects, block nothing the player can stand on, and give the room
	# a "looked into" depth a flat top-down field never has.
	for i in 2:
		var ty := 80.0 + float(i) * 28.0
		_rect(z, Vector2(w * 0.5, ty), Vector2(w - 110.0, 9.0), Color(0.015, 0.018, 0.032, 0.88), 504)
		for j in 12:
			_rect(z, Vector2(90.0 + float(j) * (w - 180.0) / 11.0, ty), Vector2(5, 16), Color(0.008, 0.01, 0.022, 0.9), 505)
		_rect(z, Vector2(w * 0.5, ty + 5.0), Vector2(w - 110.0, 1.0), Color(glow.r, glow.g, glow.b, 0.10), 506)
	# In-world vignette: darkness pooled into the four corners IN FRONT of the
	# scenery, so the frame closes in instead of simply ending at a wall.
	for c: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		_floor_patch(z, Vector2(c.x * float(w), 70.0 + c.y * (float(h) - 70.0)), 540.0, Color(0.008, 0.01, 0.024), 0.40, 520)
	# Side jambs: the room is seen through a doorway of its own.
	for k: float in [0.0, 1.0]:
		_rect(z, Vector2(k * float(w) + (1.0 - k * 2.0) * 9.0, h * 0.5), Vector2(30.0, float(h)), Color(0.012, 0.014, 0.028, 0.82), 540)
	# Bottom sill: the near edge of the room, framing the frame.
	_rect(z, Vector2(w * 0.5, h - 4.0), Vector2(w + 40.0, 26.0), Color(0.015, 0.018, 0.035, 0.92), 600)
	_rect(z, Vector2(w * 0.5, h - 17.0), Vector2(w + 40.0, 2.0), Color(glow.r, glow.g, glow.b, 0.12), 601)

static func _vocab(theme: Dictionary) -> Array:
	var out: Array = []
	for s in theme.get("structs", []):
		if s.get("t", "") != "" and s.t not in out:
			out.append(s.t)
	return out

static func _build_structures(parent: Node2D, theme: Dictionary) -> void:
	var z := Node2D.new()
	z.name = "Structures"
	parent.add_child(z)
	var glow: Color = theme.get("glow", Color(0.6, 0.8, 1.0))
	var accent: Color = theme.get("accent", glow)
	var lights_added := 0
	for s in theme.get("structs", []):
		var sc: float = float(s.get("s", 1.0))
		var sp: Vector2 = s.p
		var sm: Color = s.get("m", Color.WHITE)
		var spr := _prop(z, str(s.t), sp, sc, sm)
		if not spr:
			continue
		var zi := spr.z_index
		# Emissive props earn a real light (bible lighting rules), capped so a
		# dense cluster doesn't blow the light budget; the rest get free pools.
		match s.t:
			"struct_orb":
				if lights_added < 3:
					_lamp(z, s.p + Vector2(0, -10.0 * sc), glow, 0.95, 2.4, lights_added == 0, 190.0 * sc)
					lights_added += 1
				else:
					_light_pool(z, s.p + Vector2(0, 14.0 * sc), 150.0 * sc, glow, 0.20)
			"struct_console":
				_screen(z, s.p + Vector2(0, -20.0 * sc), glow, Vector2(1.1, 1.0) * sc, zi + 1)
				if lights_added < 3:
					_lamp(z, s.p + Vector2(0, -16.0 * sc), glow, 0.7, 1.6, false, 150.0 * sc)
					lights_added += 1
				else:
					_light_pool(z, s.p + Vector2(0, 16.0 * sc), 130.0 * sc, glow, 0.20)
			"struct_tower":
				_led(z, s.p + Vector2(-6.0 * sc, -30.0 * sc), accent, 0.4, zi + 1)
				_led(z, s.p + Vector2(6.0 * sc, -18.0 * sc), glow, 0.9, zi + 1)
				if lights_added < 3:
					_lamp(z, s.p + Vector2(0, -26.0 * sc), accent, 0.6, 1.3, lights_added == 0, 140.0 * sc)
					lights_added += 1
				else:
					_light_pool(z, s.p + Vector2(0, 30.0 * sc), 130.0 * sc, accent, 0.18)
			_:
				_light_pool(z, s.p + Vector2(0, 12.0 * sc), 120.0 * sc, glow, 0.12)

## Ambient clutter + depth so regions don't read as a bare floor with props in the
## corners. The heavy lifting now belongs to the hand-composed set-pieces, so this
## stays sparse and hugs the perimeter, out of the traffic lane.
static func _build_region_detail(parent: Node2D, theme: Dictionary, w: int, h: int) -> void:
	var z := Node2D.new()
	z.name = "Detail"
	parent.add_child(z)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var wall_c: Color = theme.get("wall", Color(0.6, 0.6, 0.7))
	var glow: Color = theme.get("glow", Color(0.6, 0.7, 0.9))

	# Soft shadow band under the top wall for depth.
	_rect(z, Vector2(w * 0.5, 47.0), Vector2(w - 40.0, 26.0), Color(0, 0, 0, 0.28), -59)

	# Cable/pipe runs along the top, threading between the wall lights.
	for i in 3:
		_rect(z, Vector2(rng.randf_range(240, w - 240), rng.randf_range(74, 98)), Vector2(rng.randf_range(160, 320), 4.0), Color(glow.r * 0.5, glow.g * 0.5, glow.b * 0.5, 0.5), -57)

	var vocab := _vocab(theme)
	if vocab.is_empty():
		return
	var center := Vector2(w * 0.5, h * 0.5)
	for i in 11:
		var p := Vector2(rng.randf_range(100, w - 100), rng.randf_range(140, h - 90))
		if p.distance_to(center) < 270.0 or absf(p.y - center.y) < 110.0:
			continue
		var sc := rng.randf_range(0.3, 0.48)
		var shade := rng.randf_range(-0.12, 0.08)
		var m := Color(clampf(wall_c.r + shade, 0, 1), clampf(wall_c.g + shade, 0, 1), clampf(wall_c.b + shade, 0, 1))
		_prop(z, str(vocab[rng.randi() % vocab.size()]), p, sc, m, rng.randf_range(-0.12, 0.12), 0.8)

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

## Motivated light. Ceiling fixtures march down the room (each one an actual
## housing with an actual pool under it), plus the theme's own anchor lights.
static func _build_region_lights(parent: Node2D, theme: Dictionary, w: int, h: int) -> void:
	var z := Node2D.new()
	z.name = "Lighting"
	parent.add_child(z)
	var glow: Color = theme.get("glow", Color(0.6, 0.8, 1.0))
	var accent: Color = theme.get("accent", glow)
	# Ceiling strip fixtures: housing on the wall, tube, pool of light on the
	# floor beneath. Three real lights; the rest of the wash is free additive.
	for i in 4:
		var fx := 190.0 + float(i) * (w - 380.0) / 3.0
		var col: Color = glow if i % 2 == 0 else accent
		_rect(z, Vector2(fx, 66.0), Vector2(58, 12), Color(0.05, 0.055, 0.085, 0.95), -54)
		var tube := Sprite2D.new()
		tube.texture = _neon_tex(col)
		var mat := _shader_mat("neon_flicker", {"seed": 2.3 + float(i) * 5.1, "base_boost": 1.35})
		if mat:
			tube.material = mat
		tube.position = Vector2(fx, 68.0)
		tube.scale = Vector2(1.1, 1.0)
		tube.z_index = -53
		z.add_child(tube)
		_light_pool(z, Vector2(fx, 150.0), 330.0, col, 0.17)
		# Only two of the four fixtures pay for a real light; the other two are
		# carried by their pools. Light budget spent where it changes the frame.
		if i < 2:
			_add_light(z, Vector2(fx, 96.0), col, 0.45, 2.4, i == 1)
	var i2 := 0
	for lp in theme.get("lights", []):
		# First anchor light in each region hums (bible: 2-4 flickers/region,
		# together with the struct + sign flickers).
		_lamp(z, lp, glow, 0.75, 4.0, i2 == 0, 300.0)
		i2 += 1
	# Corner fill so the four corners are shaped darkness, not dead space.
	for c: Vector2 in [Vector2(0.13, 0.2), Vector2(0.87, 0.2), Vector2(0.13, 0.84), Vector2(0.87, 0.84)]:
		_light_pool(z, Vector2(w * c.x, h * c.y), 300.0, accent, 0.09)

## A warm puddle under everything worth walking to. The player complaint was
## "I don't know where to go" — lit things read as destinations from across the
## room, unlit things read as floor.
static func _build_poi_pools(parent: Node2D, region_id: String, theme: Dictionary) -> void:
	var z := Node2D.new()
	z.name = "PoiPools"
	parent.add_child(z)
	var accent: Color = theme.get("accent", Color(1.0, 0.8, 0.4))
	for npc_data in _region_npcs(region_id):
		# NPCs get a real (small) key light — a person you can talk to is the
		# single most important thing in any room.
		var np: Vector2 = npc_data.pos
		_add_light(z, np + Vector2(0, -6), Color(1.0, 0.86, 0.6), 0.55, 1.9)
		_light_pool(z, np + Vector2(0, 22), 210.0, Color(1.0, 0.84, 0.55), 0.3)
		for i in 12:
			var a := TAU * float(i) / 12.0
			_rect(z, np + Vector2(cos(a) * 62.0, sin(a) * 38.0 + 20.0), Vector2(9, 3), Color(1.0, 0.86, 0.6, 0.14), -92, a)
	for entry in REGION_FLAVOR.get(region_id, []):
		var ep: Vector2 = entry[1]
		_light_pool(z, ep + Vector2(0, 16), 130.0, accent, 0.22)

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

## A light plus the puddle it casts. Real PointLight2Ds are budgeted; the pool is
## one additive sprite, and it is what makes a lamp look like it is LIGHTING
## something instead of merely being bright.
static func _lamp(parent: Node2D, pos: Vector2, col: Color, energy: float, scale: float, flicker: bool = false, pool: float = 240.0) -> PointLight2D:
	var l := _add_light(parent, pos, col, energy, scale, flicker)
	if pool > 0.0:
		_light_pool(parent, pos + Vector2(0, 26), pool, col, 0.26)
	return l

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

## Soft coloured stain on the floor — pits, spills, painted plazas, scorch.
static func _floor_patch(parent: Node2D, pos: Vector2, width: float, col: Color, alpha: float, z: int = -94) -> void:
	var s := Sprite2D.new()
	s.texture = _shadow_tex()
	s.position = pos
	# The ellipse is 48x24, so the two axes divide by different numbers to end up
	# with an actual width x 0.62*width footprint on the floor.
	s.scale = Vector2(width / 48.0, width * 0.62 / 24.0)
	s.modulate = Color(col.r, col.g, col.b, alpha)
	s.z_index = z
	parent.add_child(s)

## Gentle mains-hum flicker (about ±10% energy) — tween-driven, no per-frame
## script, dies with its light. The asymmetric halves keep it from metronoming.
static func _flicker(light: PointLight2D, amount: float = 0.10, period: float = 1.7) -> void:
	if not light.is_inside_tree():
		return
	var base := light.energy
	var tw := light.create_tween().set_loops()
	tw.tween_property(light, "energy", base * (1.0 + amount), period * 0.41).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(light, "energy", base * (1.0 - amount), period * 0.59).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## Blinking status LED (additive, tween-driven). Green means fine, amber means
## fine-ish, nobody has checked either in weeks.
static func _led(parent: Node2D, pos: Vector2, color: Color, phase: float, z: int) -> void:
	var led := _glow_rect(parent, pos, Vector2(4, 3), color, z)
	if not led.is_inside_tree():
		return
	var tw := led.create_tween().set_loops()
	tw.tween_interval(phase)
	tw.tween_property(led, "modulate:a", 0.2, 0.06)
	tw.tween_interval(0.22 + phase * 0.5)
	tw.tween_property(led, "modulate:a", 1.0, 0.06)
	tw.tween_interval(0.7)

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

static func _screen(parent: Node2D, pos: Vector2, col: Color, sc: Vector2, z: int) -> Sprite2D:
	var scr := Sprite2D.new()
	scr.texture = _screen_tex(col)
	var crt := _shader_mat("crt_monitor", {"glow_boost": 1.35})
	if crt:
		scr.material = crt
	scr.position = pos
	scr.scale = sc
	scr.z_index = z
	parent.add_child(scr)
	return scr

## Ambient occlusion + grime: rooms stop looking pasted when the walls actually
## meet the floor. Everything exists()-guarded — art agents supply the decals.
static func _build_region_grounding(parent: Node2D, w: int, h: int) -> void:
	var z := Node2D.new()
	z.name = "Grounding"
	parent.add_child(z)
	_ao_edges(z, w, h)
	# Grime count nearly doubled this pass: hand-authored decals at arbitrary
	# rotations are the cheapest way to stop a tiled floor reading as tiles.
	_grime(z, w, h, 44, 424243)
	# Corner darkening: the room's own vignette, in world space.
	for c: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		_floor_patch(z, Vector2(c.x * w, 60.0 + c.y * (h - 60.0)), 620.0, Color(0.01, 0.012, 0.03), 0.4, -93)

static func _ao_edges(parent: Node2D, w: int, h: int) -> void:
	var path := GEN + "decal_ao_edge.png"
	if not ResourceLoader.exists(path):
		return
	var tex: Texture2D = load(path)
	# [position, rotation, scale] — the 32px gradient is stretched along each
	# wall (it is uniform across, so stretching == tiling without 140 sprites).
	var edges := [
		[Vector2(w * 0.5, 68.0), 0.0, Vector2(w / 32.0, 1.5)],
		[Vector2(w * 0.5, h - 16.0), PI, Vector2(w / 32.0, 1.0)],
		[Vector2(46.0, h * 0.5), -PI * 0.5, Vector2(h / 32.0, 1.1)],
		[Vector2(w - 46.0, h * 0.5), PI * 0.5, Vector2(h / 32.0, 1.1)],
	]
	for e in edges:
		var s := Sprite2D.new()
		s.texture = tex
		s.position = e[0]
		s.rotation = e[1]
		s.scale = e[2]
		s.modulate = Color(1, 1, 1, 0.6)
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
		s.position = Vector2(rng.randf_range(70, w - 70), rng.randf_range(100, h - 60))
		s.rotation = float(rng.randi() % 4) * PI * 0.5
		s.scale = Vector2.ONE * rng.randf_range(0.8, 1.9)
		s.modulate = Color(1, 1, 1, rng.randf_range(0.35, 0.7))
		s.z_index = -95
		parent.add_child(s)

# --- label placement ------------------------------------------------------

## Boxes owned by nodes this builder does not draw the text for: the portal's
## destination plate and its vortex, the NPC name tag and the NPC's own body,
## and the arrival plaza. Reserved before any sign is placed, so signs get out of
## THEIR way rather than the other way round.
static func _reserve_labels(region_id: String, w: int, h: int) -> void:
	WorldLabel.begin(Rect2(0.0, 0.0, float(w), float(h)))
	for pd in _region_portals(region_id):
		var pp: Vector2 = pd.pos
		WorldLabel.reserve(Rect2(pp + Vector2(-88, -70), Vector2(176, 44)))
		WorldLabel.reserve(Rect2(pp + Vector2(-100, -100), Vector2(200, 200)))
	for npc_data in _region_npcs(region_id):
		var np: Vector2 = npc_data.pos
		# The nameplate box AND the bark bubbles stacked above it. npc.gd
		# measures its own font and places the plate at y -106..-86, with idle
		# barks rising from -114 to about -175 and up to ~330px wide; a sign
		# landing anywhere in that column would be talked over all night.
		WorldLabel.reserve(Rect2(np + Vector2(-170, -200), Vector2(340, 140)))
		# The NPC's actual silhouette (2.2x a 32px sprite, drawn 18px high of
		# centre). Tight on purpose — a person is a landmark, and captions should
		# sit BESIDE them, not be exiled to the next quadrant.
		WorldLabel.reserve(Rect2(np + Vector2(-42, -62), Vector2(84, 86)))
	# The arrival plaza. Landing inside a wall of captions is not an arrival.
	WorldLabel.reserve(Rect2(float(w) * 0.5 - 156.0, float(h) * 0.5 - 100.0, 312.0, 200.0))

## One region sign: a WorldLabel plate (auto-sized, collision-avoided, drawn
## above the scenery instead of under it) plus, for the headline signs, a neon
## tube fixture mounted on the plate and the light it throws on the floor.
static func _sign(parent: Node2D, pos: Vector2, text: String, col: Color, font_size: int = 12, neon: bool = false, idx: int = 0) -> void:
	var lbl := WorldLabel.add(parent, pos, text, col, {
		"size": font_size,
		"style": "headline" if neon else "plate",
		"priority": 3 if neon else _sign_prio,
	})
	if not neon or not lbl.visible:
		return
	# Unique flicker seed per sign so the whole district never stutters in unison
	# like a rendering bug. The fixture is mounted on TOP of its own plate.
	var mount := lbl.box.position + Vector2(lbl.box.size.x * 0.5, -13.0)
	var tube := Sprite2D.new()
	tube.texture = _neon_tex(col)
	var mat := _shader_mat("neon_flicker", {"seed": float(idx) * 3.7 + mount.x * 0.013, "base_boost": 1.6})
	if mat:
		tube.material = mat
	tube.position = mount
	tube.scale = Vector2(minf(2.6, lbl.box.size.x / 48.0), 1.4)
	tube.z_index = WorldLabel.Z_PLATE - 1
	parent.add_child(tube)
	# Two brackets so the fixture is bolted to something.
	for k: float in [1.0, -1.0]:
		_rect(parent, mount + Vector2(k * lbl.box.size.x * 0.36, 5.0), Vector2(3, 14), Color(0.05, 0.055, 0.09, 0.95), WorldLabel.Z_PLATE - 2)
	_light_pool(parent, mount + Vector2(0, 46), 220.0, col, 0.22)
	if idx < 1:
		_add_light(parent, mount + Vector2(0, 8), col, 0.6, 1.8, true)

static func _build_region_signs(parent: Node2D, theme: Dictionary) -> void:
	var z := Node2D.new()
	z.name = "Signs"
	parent.add_child(z)
	var idx := 0
	for sg in theme.get("signs", []):
		var sp: Vector2 = sg.p
		var sc: Color = sg.get("c", Color(0.9, 0.9, 1.0))
		_sign(z, sp, str(sg.t), sc, int(sg.get("s", 13)), idx < 2, idx)
		idx += 1

## Region-specific screen-space dressing: heat shimmer over the GPU Mines' hot
## zone, data rain in the vault and down one production alley.
static func _build_region_fx(parent: Node2D, region_id: String, _theme: Dictionary, w: int, h: int) -> void:
	match region_id:
		"gpu_mines":
			# The heat shimmer lives in postfx_layer.gd, NOT here. It used to be
			# stacked twice — an in-world quad at z 820 plus the screen-space
			# one — which doubled the distortion and, worse, read the screen
			# from inside the world canvas where it fought the postfx grade's
			# own BackBufferCopy. The screen-space one wins: it composes with
			# the grade correctly and costs nothing in the other nine regions.
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
			_lamp(parent, Vector2(160, 160), VIOLET, 0.5, 3.0, false, 260.0)
			_lamp(parent, Vector2(w - 160, 160), VIOLET, 0.5, 3.0, false, 260.0)
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

# --- hand-composed set-pieces ---------------------------------------------

## The old regions scattered props evenly, so every direction looked equally
## (un)interesting and the player wandered. Each region now gets built LANDMARKS
## the way Localhost has a battlestation and a kitchen — clustered, lit, and
## captioned — so the room reads as places to go instead of a field of stuff.
static func _build_setpieces(parent: Node2D, region_id: String, theme: Dictionary, w: int, h: int) -> void:
	var z := Node2D.new()
	z.name = "SetPieces"
	parent.add_child(z)
	var glow: Color = theme.get("glow", Color(0.6, 0.8, 1.0))
	var accent: Color = theme.get("accent", glow)
	# Every portal gets a lit gate frame, so the way out is a DOORWAY instead of
	# a floating swirl you identify by walking into it.
	for pd in _region_portals(region_id):
		var pp: Vector2 = pd.pos
		_gate(z, pp, glow, w, h)
	match region_id:
		"dependency_district": _sp_dependency(z, glow, accent)
		"stackoverflow_ruins": _sp_stackoverflow(z, glow, accent)
		"api_bazaar": _sp_bazaar(z, glow, accent)
		"cloud_district": _sp_cloud(z, glow, accent)
		"open_source_wildlands": _sp_opensource(z, glow, accent)
		"corporate_enterprise": _sp_corporate(z, glow, accent)
		"gpu_mines": _sp_gpu(z, glow, accent)
		"production": _sp_production(z, glow, accent)
		"token_vault": _sp_vault(z, glow, accent)

## Framed doorway around a portal: arch behind, threshold plate on the floor,
## two bollard lights, a pool. Visible from the far wall.
static func _gate(parent: Node2D, pos: Vector2, col: Color, w: int, h: int) -> void:
	var inward := signf(float(w) * 0.5 - pos.x)
	_put(parent, "struct_arch", pos + Vector2(0, -10), -20, 1.15, Color(0.42, 0.44, 0.55))
	_floor_patch(parent, pos + Vector2(0, 30), 300.0, col, 0.12, -94)
	_light_pool(parent, pos + Vector2(0, 20), 280.0, col, 0.3)
	for k: float in [1.0, -1.0]:
		var bp := pos + Vector2(inward * 78.0, k * 74.0)
		if pos.y < float(h) * 0.25:
			bp = pos + Vector2(k * 78.0, 66.0)
		_rect(parent, bp, Vector2(10, 26), Color(0.05, 0.055, 0.09, 0.95), _depth(bp.y, 13.0))
		_glow_rect(parent, bp + Vector2(0, -14), Vector2(8, 5), Color(col.r, col.g, col.b, 0.85), _depth(bp.y, 14.0))
	# No PointLight2D here on purpose: region_portal.gd carries its own
	# destination-hued room light and halo, and the gate reads from the pool +
	# emissive bollards alone.

## Stacked crate heap with a collapsing silhouette.
static func _heap(parent: Node2D, pos: Vector2, col: Color, n: int, sc: float, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	for i in n:
		var t := float(i) / maxf(1.0, float(n - 1))
		var p := pos + Vector2(rng.randf_range(-1.0, 1.0) * 70.0 * (1.0 - t * 0.6), -t * 62.0 + rng.randf_range(-6, 6))
		var s := sc * (1.0 - t * 0.28)
		var v := 1.0 - t * 0.22
		_prop(parent, "struct_crate", p, s, Color(col.r * v, col.g * v, col.b * v), rng.randf_range(-0.16, 0.16))

## Market stall: awning, counter, goods, hanging bulb. The API Bazaar's unit.
static func _stall(parent: Node2D, pos: Vector2, awning: Color, goods: Color, seed_v: int) -> void:
	var zi := _depth(pos.y, 46.0)
	_light_pool(parent, pos + Vector2(0, 34), 230.0, awning, 0.26)
	_prop(parent, "struct_crate", pos + Vector2(-46, 10), 0.85, Color(0.62, 0.5, 0.42))
	_prop(parent, "struct_crate", pos + Vector2(46, 10), 0.85, Color(0.58, 0.46, 0.4))
	_rect(parent, pos, Vector2(150, 16), Color(0.24, 0.2, 0.26), zi)          # counter top
	_rect(parent, pos + Vector2(0, -7), Vector2(150, 3), Color(0.4, 0.36, 0.44), zi + 1)
	# striped awning above the counter
	for i in 6:
		var c: Color = awning if i % 2 == 0 else goods
		_rect(parent, pos + Vector2(-62.5 + float(i) * 25.0, -54), Vector2(25, 22), Color(c.r * 0.7, c.g * 0.7, c.b * 0.7, 0.95), zi + 2)
	_rect(parent, pos + Vector2(0, -42), Vector2(154, 4), Color(0.1, 0.09, 0.13), zi + 3)
	# goods on the counter: little emissive crates of API keys
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	for i in 5:
		var gp := pos + Vector2(-58.0 + float(i) * 29.0, -16.0 + rng.randf_range(-3, 3))
		_rect(parent, gp, Vector2(13, 13), Color(goods.r * 0.5, goods.g * 0.5, goods.b * 0.5), zi + 2)
		_glow_rect(parent, gp + Vector2(0, -4), Vector2(7, 3), Color(goods.r, goods.g, goods.b, 0.9), zi + 3)
	_lamp(parent, pos + Vector2(0, -62), awning, 0.7, 1.9, seed_v % 3 == 0, 200.0)

## Toppled monolith: a slab lying at an angle with rubble shed around it.
static func _monolith(parent: Node2D, pos: Vector2, rot: float, col: Color, sc: float, seed_v: int) -> void:
	_prop(parent, "struct_slab", pos, sc, col, rot)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	for i in 7:
		var rp := pos + Vector2(rng.randf_range(-80, 80), rng.randf_range(20, 62))
		_rect(parent, rp, Vector2(rng.randf_range(5, 13), rng.randf_range(4, 9)), Color(col.r * 0.55, col.g * 0.55, col.b * 0.55), _depth(rp.y, 4.0), rng.randf_range(-1.0, 1.0))

## Rack of blinking hardware with a vent glow at its feet.
static func _rack(parent: Node2D, pos: Vector2, col: Color, hot: Color, sc: float, phase: float) -> void:
	var spr := _prop(parent, "struct_tower", pos, sc, col)
	var zi := spr.z_index if spr else _depth(pos.y, 60.0)
	for i in 5:
		_led(parent, pos + Vector2(-10.0 + float(i % 2) * 20.0, -54.0 + float(i) * 18.0), hot if i % 2 == 0 else col, phase + float(i) * 0.19, zi + 1)
	_glow_rect(parent, pos + Vector2(0, 52.0 * sc), Vector2(40.0 * sc, 5), Color(hot.r, hot.g, hot.b, 0.55), zi + 1)
	_light_pool(parent, pos + Vector2(0, 62.0 * sc), 150.0 * sc, hot, 0.2)

## Cubicle: two glass partitions, a desk, and a monitor nobody is behind.
static func _cubicle(parent: Node2D, pos: Vector2, col: Color, screen_col: Color) -> void:
	var zi := _depth(pos.y, 40.0)
	_prop(parent, "struct_slab", pos + Vector2(-56, -8), 0.55, col, 0.0, 0.6)
	_prop(parent, "struct_slab", pos + Vector2(0, -40), 0.55, Color(col.r * 0.9, col.g * 0.9, col.b * 0.95), 0.0, 0.6)
	_rect(parent, pos + Vector2(8, 18), Vector2(84, 26), Color(0.2, 0.22, 0.3), zi)
	_rect(parent, pos + Vector2(8, 7), Vector2(84, 3), Color(0.34, 0.37, 0.48), zi + 1)
	_screen(parent, pos + Vector2(8, 4), screen_col, Vector2(0.8, 0.7), zi + 2)
	_light_pool(parent, pos + Vector2(8, 30), 140.0, screen_col, 0.16)

## Pilgrim shrine: a kneeling stone in a ring of guttering candles. People come
## here to ask a question that was answered in 2011 and closed in 2012.
static func _shrine(parent: Node2D, pos: Vector2, col: Color) -> void:
	_floor_patch(parent, pos, 270.0, col, 0.13, -94)
	_prop(parent, "struct_slab", pos + Vector2(0, -10), 0.42, Color(0.66, 0.6, 0.5))
	for i in 9:
		var a := TAU * float(i) / 9.0
		var cp := pos + Vector2(cos(a) * 106.0, sin(a) * 62.0)
		_rect(parent, cp, Vector2(6, 13), Color(0.84, 0.8, 0.68), _depth(cp.y, 7.0))
		_glow_rect(parent, cp + Vector2(0, -10), Vector2(4, 6), Color(1.0, 0.72, 0.3, 0.9), _depth(cp.y, 9.0))
	_light_pool(parent, pos + Vector2(0, 16), 250.0, Color(1.0, 0.72, 0.34), 0.26)
	_lamp(parent, pos + Vector2(0, -22), Color(1.0, 0.7, 0.32), 0.5, 1.6, true, 0.0)

## Cooling pond: still water with a lit coping. Costs four figures an hour and
## cools nothing anybody present can name.
static func _pond(parent: Node2D, pos: Vector2, size: Vector2, col: Color) -> void:
	_rect(parent, pos, size + Vector2(14, 14), Color(0.03, 0.05, 0.09, 0.85), -93)
	_rect(parent, pos, size, Color(col.r * 0.10, col.g * 0.17, col.b * 0.28, 0.94), -92)
	for i in 7:
		var t := (float(i) + 0.5) / 7.0
		var ry := pos.y - size.y * 0.5 + size.y * t
		_glow_rect(parent, Vector2(pos.x + sin(t * 9.0) * 18.0, ry), Vector2(size.x * (0.30 + 0.5 * sin(t * PI)), 2.0), Color(col.r, col.g, col.b, 0.20), -91)
	for k: float in [1.0, -1.0]:
		_rect(parent, pos + Vector2(0, k * size.y * 0.5), Vector2(size.x + 18.0, 8.0), Color(0.16, 0.2, 0.28), -90)
		_glow_rect(parent, pos + Vector2(0, k * size.y * 0.5 - 3.0), Vector2(size.x + 18.0, 2.0), Color(col.r, col.g, col.b, 0.45), -89)
	_light_pool(parent, pos, size.x * 1.15, col, 0.20)

## Mine rails. They go from one end of the room to the other end of the room.
static func _rails(parent: Node2D, y: float, x0: float, x1: float, col: Color) -> void:
	for k: float in [1.0, -1.0]:
		_rect(parent, Vector2((x0 + x1) * 0.5, y + k * 10.0), Vector2(x1 - x0, 3.0), Color(0.36, 0.31, 0.28, 0.9), -90)
	for i in int((x1 - x0) / 34.0):
		_rect(parent, Vector2(x0 + float(i) * 34.0 + 17.0, y), Vector2(9.0, 28.0), Color(0.1, 0.08, 0.07, 0.85), -91)
	_light_pool(parent, Vector2((x0 + x1) * 0.5, y), (x1 - x0) * 0.55, col, 0.07)

## Ore cart, loaded with glowing compute nobody has been allocated.
static func _cart(parent: Node2D, pos: Vector2, hot: Color, tilt: float) -> void:
	var zi := _depth(pos.y, 26.0)
	_drop_shadow(parent, pos + Vector2(0, 20), 88.0, zi - 1, 0.42)
	_rect(parent, pos, Vector2(76, 42), Color(0.24, 0.2, 0.2), zi, tilt)
	_rect(parent, pos + Vector2(0, -19), Vector2(76, 6), Color(0.42, 0.35, 0.32), zi + 1, tilt)
	for i in 5:
		_glow_rect(parent, pos + Vector2(-26.0 + float(i) * 13.0, -22.0), Vector2(9, 6), Color(hot.r, hot.g, hot.b, 0.75), zi + 2, tilt)
	for k: float in [1.0, -1.0]:
		_rect(parent, pos + Vector2(k * 27.0, 21.0), Vector2(15, 15), Color(0.12, 0.1, 0.1), zi + 1)
	_light_pool(parent, pos + Vector2(0, 12), 140.0, hot, 0.18)

## Incident whiteboard: a board, a tray, and the same four boxes and arrows every
## incident produces before anybody has looked at a log.
static func _whiteboard(parent: Node2D, pos: Vector2, accent: Color, rot: float) -> void:
	var zi := _depth(pos.y, 46.0)
	_drop_shadow(parent, pos + Vector2(0, 46), 156.0, zi - 2, 0.4)
	_rect(parent, pos, Vector2(152, 94), Color(0.13, 0.14, 0.19), zi - 1, rot)
	_rect(parent, pos, Vector2(146, 88), Color(0.74, 0.77, 0.84), zi, rot)
	for i in 3:
		_rect(parent, pos + Vector2(-44.0 + float(i) * 44.0, -18.0), Vector2(30, 18), Color(0.2, 0.24, 0.36, 0.85), zi + 1, rot)
		if i < 2:
			_rect(parent, pos + Vector2(-22.0 + float(i) * 44.0, -18.0), Vector2(16, 2), Color(0.75, 0.2, 0.24, 0.9), zi + 1, rot)
	for i in 4:
		_rect(parent, pos + Vector2(-30.0 + float(i % 2) * 46.0, 12.0 + float(i / 2) * 13.0), Vector2(56, 3), Color(0.28, 0.3, 0.4, 0.7), zi + 1, rot)
	_rect(parent, pos + Vector2(0, 47), Vector2(150, 7), Color(0.2, 0.22, 0.3), zi + 1, rot)
	_glow_rect(parent, pos + Vector2(-52, 47), Vector2(16, 3), Color(accent.r, accent.g, accent.b, 0.7), zi + 2, rot)
	_light_pool(parent, pos + Vector2(0, 60), 200.0, Color(0.82, 0.86, 1.0), 0.14)

## Security laser: a thin overbright beam between two emitters. Nothing behind it
## is protected; it is entirely for the atmosphere of consequence.
static func _laser(parent: Node2D, a: Vector2, b: Vector2, col: Color) -> void:
	var d := b - a
	_glow_rect(parent, (a + b) * 0.5, Vector2(d.length(), 2.0), Color(col.r * 1.6, col.g * 1.6, col.b * 1.6, 0.5), -88, d.angle())
	for e: Vector2 in [a, b]:
		_rect(parent, e, Vector2(10, 10), Color(0.07, 0.06, 0.1, 0.95), _depth(e.y, 6.0))
		_glow_rect(parent, e, Vector2(5, 5), Color(col.r, col.g, col.b, 0.9), _depth(e.y, 7.0))

## Glass office partition. The maze is the product.
static func _partition(parent: Node2D, pos: Vector2, size: Vector2, col: Color) -> void:
	var zi := _depth(pos.y, size.y * 0.5)
	_drop_shadow(parent, pos + Vector2(0, size.y * 0.5 + 3.0), size.x * 0.86, zi - 1, 0.24)
	_rect(parent, pos, size, Color(col.r * 0.26, col.g * 0.3, col.b * 0.42, 0.88), zi)
	_rect(parent, pos, Vector2(size.x, size.y * 0.4), Color(col.r, col.g, col.b, 0.09), zi + 1)
	_rect(parent, pos + Vector2(0, -size.y * 0.5 + 2.0), Vector2(size.x, 3.0), Color(col.r, col.g, col.b, 0.36), zi + 1)

## Bunting on a slack line — the market's ceiling, and a real foreground layer
## the player walks UNDER rather than past.
static func _bunting(parent: Node2D, from: Vector2, to: Vector2, a: Color, b: Color) -> void:
	var mid := (from + to) * 0.5 + Vector2(0, 30)
	var line := Line2D.new()
	line.width = 2.0
	line.default_color = Color(0.04, 0.03, 0.05, 0.9)
	line.z_index = 505
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	for i in 9:
		var t := float(i) / 8.0
		line.add_point(from.lerp(mid, t).lerp(mid.lerp(to, t), t))
	parent.add_child(line)
	for i in 8:
		var t2 := (float(i) + 0.5) / 8.0
		var p := from.lerp(mid, t2).lerp(mid.lerp(to, t2), t2)
		var c: Color = a if i % 2 == 0 else b
		_rect(parent, p + Vector2(0, 9), Vector2(11, 15), Color(c.r * 0.7, c.g * 0.7, c.b * 0.7, 0.95), 506)
		_glow_rect(parent, p + Vector2(0, 5), Vector2(7, 3), Color(c.r, c.g, c.b, 0.5), 507)

## Corrugated shack under one noodle-warm bulb. Home of the person maintaining
## something your build depends on, for free, since 2014.
static func _shack(parent: Node2D, pos: Vector2, col: Color) -> void:
	var zi := _depth(pos.y, 58.0)
	_drop_shadow(parent, pos + Vector2(0, 56), 220.0, zi - 2, 0.45)
	_rect(parent, pos + Vector2(0, 8), Vector2(184, 96), Color(col.r * 0.34, col.g * 0.38, col.b * 0.34), zi)
	for i in 9:
		_rect(parent, pos + Vector2(-80.0 + float(i) * 20.0, 8.0), Vector2(3, 96), Color(0, 0, 0, 0.22), zi + 1)
	_rect(parent, pos + Vector2(0, -46), Vector2(208, 17), Color(0.16, 0.19, 0.16), zi + 2)
	_rect(parent, pos + Vector2(0, -54), Vector2(208, 3), Color(0.42, 0.48, 0.42), zi + 3)
	_rect(parent, pos + Vector2(0, 24), Vector2(54, 64), Color(0.02, 0.02, 0.03), zi + 2)
	_glow_rect(parent, pos + Vector2(0, 24), Vector2(48, 58), Color(1.0, 0.72, 0.34, 0.28), zi + 3)
	_lamp(parent, pos + Vector2(0, -36), Color(1.0, 0.74, 0.36), 0.8, 2.2, true, 270.0)

static func _sp_dependency(z: Node2D, glow: Color, accent: Color) -> void:
	# node_modules: a crate heap collapsing into its own gravity well.
	_floor_patch(z, Vector2(296, 292), 340.0, Color(0.01, 0.03, 0.01), 0.55, -94)
	_heap(z, Vector2(296, 286), accent, 8, 1.0, 4201)
	_lamp(z, Vector2(296, 214), glow, 0.6, 2.3, true, 280.0)
	_sign(z, Vector2(196, 148), "node_modules\n4.2 GB of someone else's problems", glow, 12)
	# The install bay: a terminal that has been at 47% for a while.
	_prop(z, "struct_console", Vector2(1010, 254), 1.0, Color(0.66, 0.8, 0.5))
	_screen(z, Vector2(1010, 232), glow, Vector2(1.3, 1.1), _depth(254, 60))
	_rect(z, Vector2(1010, 296), Vector2(120, 8), Color(0.06, 0.1, 0.05), _depth(296, 8))
	_glow_rect(z, Vector2(982, 296), Vector2(56, 6), Color(glow.r, glow.g, glow.b, 0.8), _depth(296, 9))
	_lamp(z, Vector2(1010, 224), glow, 0.65, 1.9, false, 210.0)
	_sign(z, Vector2(922, 336), "installing... 47%\n(it has said 47% for an hour)", accent, 11)
	# The lockfile shrine. Merged by hand. We do not speak of it.
	_prop(z, "struct_slab", Vector2(560, 796), 0.6, Color(0.5, 0.62, 0.44))
	for k: float in [1.0, -1.0]:
		_lamp(z, Vector2(560 + k * 46.0, 780), Color(1.0, 0.78, 0.4), 0.35, 1.0, k > 0.0, 90.0)
	_sign(z, Vector2(470, 856), "package-lock.json\nresolved by hand. Do not ask.", Color("#FFB020"), 11)
	# The conveyor feeding the heap. It only runs one way, it has run since before
	# anybody currently here joined, and nobody has located the off switch.
	var belt_y := 210.0
	_rect(z, Vector2(560, belt_y), Vector2(330, 40), Color(0.11, 0.14, 0.1), _depth(belt_y, 20.0))
	_rect(z, Vector2(560, belt_y - 17.0), Vector2(330, 4), Color(0.3, 0.38, 0.26), _depth(belt_y, 22.0))
	for i in 11:
		_rect(z, Vector2(400.0 + float(i) * 32.0, belt_y), Vector2(4, 34), Color(0, 0, 0, 0.3), _depth(belt_y, 23.0))
	for i in 3:
		_prop(z, "struct_crate", Vector2(440.0 + float(i) * 118.0, belt_y - 22.0), 0.5, accent, 0.06 * float(i), 0.5)
	_glow_rect(z, Vector2(400, belt_y), Vector2(6, 40), Color(glow.r, glow.g, glow.b, 0.6), _depth(belt_y, 24.0))
	_light_pool(z, Vector2(560, belt_y + 30.0), 300.0, glow, 0.15)
	_sign(z, Vector2(430, 258), "transitive dependencies\nin: 1,402   out: 0", accent, 11)
	# The maintainer's depot — crates, a lamp, one folding chair.
	_prop(z, "struct_crate", Vector2(1002, 800), 0.9, accent)
	_prop(z, "struct_crate", Vector2(1150, 806), 0.85, Color(accent.r * 0.85, accent.g * 0.85, accent.b * 0.85))
	_rect(z, Vector2(1076, 796), Vector2(130, 14), Color(0.26, 0.22, 0.18), _depth(796, 8))
	_lamp(z, Vector2(1076, 744), Color(1.0, 0.82, 0.46), 0.6, 1.9, false, 220.0)

	# Somebody's evening, left where it ended: a cold cup by the depot and the
	# drum the conveyor was fed from, still half wound.
	_prop(z, "dress_noodle_cup", Vector2(196, 812), 1.0, Color(0.86, 0.94, 0.8))
	_prop(z, "dress_cable_spool", Vector2(168, 646), 0.9, Color(0.72, 0.86, 0.66))

static func _sp_stackoverflow(z: Node2D, glow: Color, accent: Color) -> void:
	# A field of toppled answer-monoliths. All correct in 2013.
	_monolith(z, Vector2(238, 300), 1.15, Color(0.72, 0.64, 0.5), 0.9, 11)
	_monolith(z, Vector2(392, 348), -0.42, Color(0.66, 0.58, 0.46), 0.75, 12)
	_monolith(z, Vector2(1096, 318), -1.25, Color(0.7, 0.62, 0.48), 0.85, 13)
	_monolith(z, Vector2(936, 372), 0.35, Color(0.62, 0.55, 0.44), 0.7, 14)
	# The Accepted Answer, still lit, still wrong.
	_prop(z, "struct_slab", Vector2(640, 214), 1.0, Color(0.86, 0.76, 0.55))
	_glow_rect(z, Vector2(640, 190), Vector2(30, 30), Color(glow.r, glow.g, glow.b, 0.5), _depth(214, 62))
	_lamp(z, Vector2(640, 178), glow, 0.85, 2.6, true, 300.0)
	_floor_patch(z, Vector2(640, 292), 300.0, glow, 0.14, -94)
	_sign(z, Vector2(560, 300), "ACCEPTED ANSWER\n(deprecated in 2016)", glow, 12)
	# Cairn of duplicates, stacked by a hermit with a lot of time.
	for i in 5:
		_prop(z, "struct_slab", Vector2(524.0 + float(i % 2) * 8.0, 838.0 - float(i) * 26.0), 0.34 - float(i) * 0.03, Color(0.6, 0.54, 0.44), float(i) * 0.4)
	_sign(z, Vector2(430, 866), "cairn of duplicates\n(marked as duplicate)", accent, 11)
	# The pilgrim shrine. You bring your question here. The question has been
	# asked. The answer is four versions out of date and marked as duplicate.
	_shrine(z, Vector2(324, 716), glow)
	_sign(z, Vector2(212, 792), "SHRINE OF THE ASKED\n\"possible duplicate of\"", accent, 11)
	# The hermit's fire, burning documentation for warmth.
	_light_pool(z, Vector2(1000, 730), 240.0, Color(1.0, 0.66, 0.3), 0.3)
	_lamp(z, Vector2(1000, 716), Color(1.0, 0.62, 0.26), 0.7, 1.8, true, 0.0)
	for k: float in [1.0, -1.0]:
		_prop(z, "struct_slab", Vector2(1000 + k * 92.0, 740), 0.3, Color(0.56, 0.5, 0.42), k * 0.2)

	# One more answer-stone, snapped, still lit. Nobody remembers the question.
	_prop(z, "dress_monolith", Vector2(190, 646), 1.0, Color(0.78, 0.7, 0.54))
	_prop(z, "dress_monolith", Vector2(1188, 846), 0.85, Color(0.7, 0.63, 0.5), 0.09)

static func _sp_bazaar(z: Node2D, glow: Color, accent: Color) -> void:
	# Three stalls along the top: everything's for sale, per request.
	_stall(z, Vector2(276, 236), glow, accent, 91)
	_stall(z, Vector2(640, 218), accent, glow, 92)
	_stall(z, Vector2(1004, 236), glow, accent, 93)
	_sign(z, Vector2(190, 300), "API keys\ncash, crypto, or kidney", glow, 11)
	_sign(z, Vector2(930, 300), "Free tier: 14 seconds\n(measured generously)", accent, 11)
	# The haggling pit: a ring of crates around a low table nobody wins at.
	_floor_patch(z, Vector2(604, 800), 380.0, accent, 0.1, -94)
	for i in 7:
		var a := TAU * float(i) / 7.0
		_prop(z, "struct_crate", Vector2(604, 800) + Vector2(cos(a) * 150.0, sin(a) * 92.0), 0.55, Color(0.72, 0.56, 0.4), a * 0.2)
	_rect(z, Vector2(604, 800), Vector2(96, 30), Color(0.3, 0.2, 0.3), _depth(800, 16))
	_lamp(z, Vector2(604, 762), accent, 0.6, 2.0, true, 240.0)
	_sign(z, Vector2(516, 862), "HAGGLING PIT\nprices go up while you think", accent, 11)
	# The reseller's own stall, bigger, pinker, less trustworthy.
	_stall(z, Vector2(1088, 806), glow, accent, 94)
	# Bunting strung over the market street. It is always Friday here, so the
	# decorations are always up for something that expires today.
	_bunting(z, Vector2(150, 150), Vector2(600, 148), glow, accent)
	_bunting(z, Vector2(690, 148), Vector2(1140, 152), accent, glow)
	_bunting(z, Vector2(400, 690), Vector2(830, 694), glow, accent)

	# Canopies over the stalls — the market is a roof and a rumour. Awnings hang
	# ABOVE the counters, so they are drawn from the stall's own y, not their own.
	for ax: float in [276.0, 640.0, 1004.0]:
		_put(z, "dress_awning", Vector2(ax, 168.0), _depth(236.0, 96.0), 1.0,
			Color(glow.r * 0.9 + 0.1, glow.g * 0.9 + 0.1, glow.b * 0.9 + 0.1))
	# A fourth pitch nobody licensed, wedged in where the aisle widens.
	_prop(z, "dress_stall", Vector2(830, 874), 0.95, Color(0.94, 0.8, 0.9))

static func _sp_cloud(z: Node2D, glow: Color, accent: Color) -> void:
	# The server cathedral: a nave of racks, an arch for an apse.
	for i in 3:
		var y := 176.0 + float(i) * 96.0
		_rack(z, Vector2(430, y), Color(0.6, 0.7, 0.86), glow, 0.85, 0.2 + float(i) * 0.3)
		_rack(z, Vector2(850, y), Color(0.56, 0.66, 0.82), glow, 0.85, 0.5 + float(i) * 0.3)
	_prop(z, "struct_arch", Vector2(640, 172), 1.15, Color(0.72, 0.82, 0.96))
	_floor_patch(z, Vector2(640, 268), 380.0, glow, 0.16, -94)
	_lamp(z, Vector2(640, 196), glow, 0.9, 3.0, true, 340.0)
	_sign(z, Vector2(556, 288), "THE CLOUD\nsomeone else's computer, uphill", glow, 12)
	# The invoice altar. Numbers go up. Nobody knows which numbers.
	_prop(z, "struct_slab", Vector2(640, 802), 0.75, Color(0.66, 0.76, 0.9))
	_screen(z, Vector2(640, 774), accent, Vector2(1.5, 1.1), _depth(802, 48))
	_lamp(z, Vector2(640, 762), accent, 0.6, 1.9, false, 220.0)
	_sign(z, Vector2(548, 852), "THIS MONTH: €41,802\nLine items: 2,304. Understood: 0.", accent, 11)
	# The cooling pond. Still, lit, expensive, and cooling nothing anybody here
	# can name. Reflections are two glow bars and a lot of confidence.
	_pond(z, Vector2(404, 764), Vector2(252, 118), glow)
	_sign(z, Vector2(292, 838), "COOLING POND\nbilled per litre, per region", accent, 11)
	# The sales booth. It is elastic. Do not ask what that means.
	_prop(z, "struct_console", Vector2(1128, 782), 0.9, Color(0.7, 0.8, 0.95))
	_screen(z, Vector2(1128, 762), glow, Vector2(1.1, 0.9), _depth(782, 54))
	_lamp(z, Vector2(1128, 746), glow, 0.6, 1.7, false, 190.0)

	# The plant that keeps the cathedral cold, and the conduit waiting on a
	# change window that has been rescheduled four times.
	_prop(z, "dress_cooling_tower", Vector2(1146, 262), 1.0, Color(0.78, 0.86, 0.98))
	_prop(z, "dress_pipe_stack", Vector2(1122, 856), 0.95, Color(0.74, 0.82, 0.94))

static func _sp_opensource(z: Node2D, glow: Color, accent: Color) -> void:
	# The maintainer's camp: one tent, one fire, one person, 4,000 dependents.
	_light_pool(z, Vector2(1058, 826), 300.0, Color(1.0, 0.7, 0.34), 0.34)
	_lamp(z, Vector2(1058, 812), Color(1.0, 0.64, 0.28), 0.8, 2.0, true, 0.0)
	for i in 5:
		var a := TAU * float(i) / 5.0
		_rect(z, Vector2(1058, 812) + Vector2(cos(a) * 34.0, sin(a) * 20.0), Vector2(9, 9), Color(0.18, 0.16, 0.14), _depth(812, 6), a)
	_prop(z, "struct_crate", Vector2(970, 848), 0.6, Color(0.5, 0.68, 0.46))
	_prop(z, "struct_crate", Vector2(1146, 852), 0.6, Color(0.46, 0.64, 0.44))
	var fire := CPUParticles2D.new()
	fire.name = "Campfire"
	fire.position = Vector2(1058, 808)
	fire.z_index = 300
	fire.amount = 16
	fire.lifetime = 1.5
	fire.direction = Vector2(0, -1)
	fire.spread = 16.0
	fire.gravity = Vector2(0, -34)
	fire.initial_velocity_min = 16.0
	fire.initial_velocity_max = 34.0
	fire.scale_amount_min = 1.4
	fire.scale_amount_max = 2.8
	fire.color = Color(1.0, 0.6, 0.22, 0.55)
	var dot := _glow_dot()
	if dot:
		fire.texture = dot
	z.add_child(fire)
	# The shack the camp belongs to: corrugated, one bulb, door open because the
	# issue tracker never closes.
	_shack(z, Vector2(886, 742), accent)
	_sign(z, Vector2(918, 862), "MAINTAINER (1)\nDependents: 4M. Sponsors: 3.", Color("#FFB020"), 11)
	# The issue graveyard. Open since 2019. Reacted to with hearts.
	for i in 8:
		var gp := Vector2(220.0 + float(i % 4) * 78.0, 758.0 + float(i / 4) * 74.0)
		_prop(z, "struct_slab", gp, 0.28, Color(0.44, 0.62, 0.46), (float(i) - 3.5) * 0.05)
	_sign(z, Vector2(206, 866), "ISSUE #4092\nopen since 2019. 340 reactions. 0 fixes.", glow, 11)
	# The README monument. Accurate six months ago.
	_prop(z, "struct_slab", Vector2(292, 274), 0.85, Color(0.56, 0.76, 0.54))
	_screen(z, Vector2(292, 250), glow, Vector2(1.2, 0.9), _depth(274, 52))
	_lamp(z, Vector2(292, 236), glow, 0.55, 1.8, false, 210.0)
	for i in 4:
		_rect(z, Vector2(238.0 + float(i) * 36.0, 322.0), Vector2(26, 6), Color(accent.r * 0.8, accent.g * 0.8, accent.b * 0.8, 0.7), _depth(322, 4))
	_sign(z, Vector2(206, 344), "README.md\nAccurate as of six months ago.", glow, 11)
	# The overgrown arch: still merged, still load-bearing.
	_floor_patch(z, Vector2(640, 246), 300.0, glow, 0.12, -94)
	for i in 6:
		_rect(z, Vector2(566.0 + float(i) * 30.0, 214.0 + float(i % 3) * 12.0), Vector2(6, 44), Color(accent.r * 0.7, accent.g * 0.7, accent.b * 0.7, 0.8), -46, 0.2 * float(i % 3))
	_lamp(z, Vector2(640, 224), glow, 0.6, 2.2, true, 260.0)

	# Dinner by the camp, and the spool the whole ecosystem is strung from.
	_prop(z, "dress_noodle_cup", Vector2(996, 890), 1.0, Color(0.82, 0.96, 0.8))
	_prop(z, "dress_cable_spool", Vector2(452, 302), 0.9, Color(0.7, 0.9, 0.7))

static func _sp_corporate(z: Node2D, glow: Color, accent: Color) -> void:
	# The cubicle farm. Two banks, so the traffic lane stays a corridor.
	for i in 4:
		_cubicle(z, Vector2(250.0 + float(i) * 260.0, 232.0), Color(0.6, 0.66, 0.8), glow)
	for i in 3:
		_cubicle(z, Vector2(316.0 + float(i) * 260.0, 726.0), Color(0.56, 0.62, 0.78), accent)
	# The maze itself: glass runs and stub walls that turn an open plan into a
	# corridor with corners, without ever colliding with anything.
	for i in 3:
		_partition(z, Vector2(316.0 + float(i) * 260.0, 320.0), Vector2(208.0, 12.0), glow)
		_partition(z, Vector2(316.0 + float(i) * 260.0, 664.0), Vector2(208.0, 12.0), accent)
	for i in 4:
		_partition(z, Vector2(250.0 + float(i) * 260.0, 286.0), Vector2(12.0, 82.0), glow)
	_sign(z, Vector2(210, 158), "OPEN PLAN\nfor collaboration (headphones mandatory)", accent, 11)
	# The all-hands stage, permanently set up.
	_rect(z, Vector2(1000, 812), Vector2(250, 60), Color(0.18, 0.2, 0.28), _depth(812, 30))
	_rect(z, Vector2(1000, 786), Vector2(250, 5), Color(0.32, 0.36, 0.5), _depth(812, 32))
	_rect(z, Vector2(930, 780), Vector2(30, 42), Color(0.24, 0.26, 0.36), _depth(796, 22))
	_screen(z, Vector2(1000, 742), glow, Vector2(2.6, 1.7), _depth(812, 34))
	for k: float in [1.0, -1.0]:
		_lamp(z, Vector2(1000 + k * 96.0, 744), glow, 0.55, 1.8, false, 200.0)
	_sign(z, Vector2(896, 872), "ALL-HANDS: AI STRATEGY\nby Friday. Of an unspecified year.", glow, 11)
	# Reception: a desk, a ticket queue, and no receptionist.
	_rect(z, Vector2(258, 640), Vector2(150, 34), Color(0.2, 0.23, 0.32), _depth(640, 18))
	_screen(z, Vector2(258, 620), accent, Vector2(1.1, 0.8), _depth(640, 20))
	_lamp(z, Vector2(258, 604), accent, 0.5, 1.6, false, 180.0)
	_sign(z, Vector2(170, 676), "Please raise a ticket\nabout the ticket system.", accent, 11)

	# Records nobody can delete, a board nobody erased, and one more partition.
	_prop(z, "dress_filing_cabinet", Vector2(1178, 296), 1.0, Color(0.74, 0.8, 0.94))
	_prop(z, "dress_filing_cabinet", Vector2(1178, 402), 0.95, Color(0.7, 0.76, 0.9))
	_prop(z, "dress_whiteboard", Vector2(618, 892), 0.95, Color(0.8, 0.85, 0.96))
	_prop(z, "dress_cubicle", Vector2(1178, 668), 0.9, Color(0.68, 0.74, 0.88))

static func _sp_gpu(z: Node2D, glow: Color, accent: Color) -> void:
	# Two rig banks, thermally throttled, spiritually throttled.
	for i in 3:
		_rack(z, Vector2(214.0 + float(i) * 104.0, 240.0), Color(0.72, 0.5, 0.42), glow, 0.9, 0.15 + float(i) * 0.27)
		_rack(z, Vector2(866.0 + float(i) * 104.0, 240.0), Color(0.7, 0.48, 0.4), accent, 0.9, 0.4 + float(i) * 0.27)
	for i in 2:
		var cx := 214.0 + float(i) * 208.0
		var line := Line2D.new()
		line.width = 4.0
		line.default_color = Color(0.05, 0.04, 0.05, 0.9)
		line.z_index = -46
		line.add_point(Vector2(cx, 190))
		line.add_point(Vector2(cx + 52.0, 214))
		line.add_point(Vector2(cx + 104.0, 190))
		z.add_child(line)
	_sign(z, Vector2(196, 330), "RIG BANK A\nCUDA out of memory (always)", glow, 11)
	_sign(z, Vector2(858, 330), "RIG BANK B\nFan curve: prayer", accent, 11)
	# Cooling towers, losing.
	for k: float in [1.0, -1.0]:
		var cp := Vector2(640.0 - k * 456.0, 792.0)
		_prop(z, "struct_tower", cp, 1.25, Color(0.62, 0.56, 0.56))
		_glow_rect(z, cp + Vector2(0, -78), Vector2(34, 6), Color(0.7, 0.9, 1.0, 0.5), _depth(cp.y, 80.0))
		_lamp(z, cp + Vector2(0, -84), Color(0.6, 0.85, 1.0), 0.5, 1.8, k > 0.0, 200.0)
		var steam := CPUParticles2D.new()
		steam.name = "Coolant%d" % int(k)
		steam.position = cp + Vector2(0, -86)
		steam.z_index = 300
		steam.amount = 12
		steam.lifetime = 2.2
		steam.direction = Vector2(0, -1)
		steam.spread = 18.0
		steam.gravity = Vector2(0, -20)
		steam.initial_velocity_min = 14.0
		steam.initial_velocity_max = 30.0
		steam.scale_amount_min = 1.8
		steam.scale_amount_max = 3.6
		steam.color = Color(0.8, 0.92, 1.0, 0.2)
		var dot := _glow_dot()
		if dot:
			steam.texture = dot
		z.add_child(steam)
	_sign(z, Vector2(112, 872), "COOLING\noperating at 6% of hope", Color("#6BC7FF"), 11)
	# Ore carts on rails, hauling allocated-but-undelivered compute from one end
	# of the mine to the other end of the mine.
	_rails(z, 668.0, 260.0, 1010.0, glow)
	_cart(z, Vector2(388, 656), glow, -0.03)
	_cart(z, Vector2(646, 660), accent, 0.02)
	_cart(z, Vector2(898, 654), glow, -0.05)
	_sign(z, Vector2(272, 606), "ORE LINE 3\nzip-tied, load-bearing, fine", glow, 11)
	# The heat pit: cracked floor, glowing from underneath.
	_floor_patch(z, Vector2(640, 812), 460.0, Color(1.0, 0.35, 0.1), 0.24, -93)
	for i in 9:
		var a := TAU * float(i) / 9.0
		_glow_rect(z, Vector2(640, 812) + Vector2(cos(a) * 96.0, sin(a) * 58.0), Vector2(46, 4), Color(1.0, 0.42, 0.14, 0.6), -90, a)
	_sign(z, Vector2(548, 872), "AMBIENT: 94°C\nEst. delivery: Q4 of some year", accent, 11)
	# The foreman's shack.
	_prop(z, "struct_console", Vector2(1136, 716), 0.9, Color(0.74, 0.54, 0.44))
	_screen(z, Vector2(1136, 696), accent, Vector2(1.1, 0.9), _depth(716, 54))
	_lamp(z, Vector2(1136, 682), accent, 0.6, 1.7, true, 190.0)

	# Conduit staged for an upgrade that was approved two quarters ago, and a
	# cart that came off the rails and stayed off them.
	_prop(z, "dress_pipe_stack", Vector2(1176, 352), 0.95, Color(0.88, 0.7, 0.62))
	_prop(z, "dress_ore_cart", Vector2(1112, 886), 0.95, Color(0.9, 0.68, 0.56), 0.11)

static func _sp_production(z: Node2D, glow: Color, accent: Color) -> void:
	# The incident war room. Permanently staffed by nobody.
	_prop(z, "struct_slab", Vector2(640, 208), 1.7, Color(0.6, 0.42, 0.44))
	for i in 3:
		_screen(z, Vector2(556.0 + float(i) * 84.0, 196.0), glow, Vector2(1.7, 1.3), _depth(208, 104))
	_rect(z, Vector2(640, 300), Vector2(230, 40), Color(0.22, 0.17, 0.19), _depth(300, 20))
	_rect(z, Vector2(640, 284), Vector2(230, 4), Color(0.36, 0.28, 0.3), _depth(300, 22))
	for k: float in [1.0, -1.0]:
		_rect(z, Vector2(640 + k * 132.0, 306), Vector2(34, 34), Color(0.18, 0.15, 0.18), _depth(306, 18))
	_lamp(z, Vector2(640, 262), glow, 1.0, 2.6, true, 340.0)
	_floor_patch(z, Vector2(640, 330), 420.0, glow, 0.16, -94)
	_sign(z, Vector2(524, 344), "WAR ROOM\nSeverity: yes. Owner: unassigned.", glow, 12)
	# Whiteboards flanking the war room: four boxes, three arrows, one theory
	# somebody will disprove in nine minutes.
	_whiteboard(z, Vector2(444, 240), accent, -0.04)
	_whiteboard(z, Vector2(842, 238), glow, 0.05)
	# Rotating beacons along the top wall. Everything is fine.
	for i in 4:
		var bx := 200.0 + float(i) * 280.0
		_rect(z, Vector2(bx, 90.0), Vector2(20, 14), Color(0.1, 0.05, 0.06, 0.95), -45)
		_glow_rect(z, Vector2(bx, 84.0), Vector2(14, 6), Color(glow.r, glow.g, glow.b, 0.9), -44)
		_light_pool(z, Vector2(bx, 168.0), 260.0, glow, 0.16)
	# The status page. Fully green. Load-bearing lie.
	_prop(z, "struct_slab", Vector2(272, 276), 0.9, Color(0.6, 0.44, 0.46))
	_screen(z, Vector2(272, 248), Color(0.3, 0.95, 0.45), Vector2(1.9, 1.2), _depth(276, 56))
	_lamp(z, Vector2(272, 234), Color(0.3, 0.95, 0.45), 0.6, 1.9, false, 240.0)
	for i in 5:
		_led(z, Vector2(220.0 + float(i) * 26.0, 296.0), Color(0.3, 1.0, 0.5), 0.2 + float(i) * 0.21, _depth(296, 8))
	_sign(z, Vector2(190, 322), "STATUS PAGE\nAll systems operational.", Color(0.4, 1.0, 0.55), 11)
	# THE BUTTON. Red. Domed. Guarded by a sign nobody reads.
	_prop(z, "struct_slab", Vector2(268, 800), 0.55, Color(0.58, 0.4, 0.42))
	_glow_rect(z, Vector2(268, 758), Vector2(28, 16), Color(1.0, 0.25, 0.25, 0.9), _depth(800, 62))
	_lamp(z, Vector2(268, 754), Color(1.0, 0.28, 0.28), 0.7, 1.6, true, 200.0)
	_sign(z, Vector2(176, 856), "ROLLBACK\nthere is no rollback plan", glow, 11)
	# The postmortem graveyard: action items, all still open.
	for i in 6:
		_prop(z, "struct_slab", Vector2(940.0 + float(i % 3) * 74.0, 784.0 + float(i / 3) * 66.0), 0.26, Color(0.52, 0.4, 0.42), (float(i) - 2.5) * 0.06)
	_sign(z, Vector2(918, 880), "POSTMORTEMS (blameless)\nAction items: 61 open", accent, 11)

	# Perimeter emitters installed after the last incident, which was not a
	# perimeter problem.
	_prop(z, "dress_laser_emitter", Vector2(1170, 300), 1.0, Color(0.86, 0.66, 0.68))
	_prop(z, "dress_laser_emitter", Vector2(1170, 664), 1.0, Color(0.86, 0.66, 0.68))

static func _sp_vault(z: Node2D, glow: Color, accent: Color) -> void:
	# Shelving rows of reserves, stacked to the ceiling and counted by nobody.
	for i in 4:
		var sp := Vector2(276.0 + float(i % 2) * 728.0, 250.0 + float(i / 2) * 104.0)
		_prop(z, "struct_slab", sp, 0.8, Color(0.86, 0.74, 0.44))
		for b in 4:
			_glow_rect(z, sp + Vector2(-26.0 + float(b) * 17.0, -22.0), Vector2(13, 7), Color(glow.r, glow.g, glow.b, 0.75), _depth(sp.y, 50.0))
		_light_pool(z, sp + Vector2(0, 46), 190.0, glow, 0.2)
	# The reserve pedestal: an orb of tokens under an arcane ring.
	_prop(z, "struct_orb", Vector2(640, 244), 0.85, Color(1.0, 0.85, 0.34))
	for i in 20:
		var a := TAU * float(i) / 20.0
		_glow_rect(z, Vector2(640, 300) + Vector2(cos(a) * 128.0, sin(a) * 78.0), Vector2(11, 4), Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.5), -90, a)
	_lamp(z, Vector2(640, 226), glow, 1.0, 2.8, true, 340.0)
	_sign(z, Vector2(556, 320), "THE RESERVES\nWithdrawals require a written excuse.", glow, 12)
	# Two arcane circles: the price oracle, and whatever the other one does.
	for k: float in [1.0, -1.0]:
		var cp := Vector2(640.0 - k * 366.0, 790.0)
		_floor_patch(z, cp, 300.0, VIOLET, 0.2, -94)
		for i in 14:
			var a2 := TAU * float(i) / 14.0
			_glow_rect(z, cp + Vector2(cos(a2) * 104.0, sin(a2) * 62.0), Vector2(9, 4), Color(VIOLET.r * 1.3, VIOLET.g * 1.3, VIOLET.b * 1.3, 0.55), -90, a2)
		_lamp(z, cp, VIOLET, 0.55, 2.2, k > 0.0, 0.0)
	# The vault floor: a lattice of security lasers between the reserves and the
	# door, plus two guarding the pedestal. Nothing is protected. It is a mood.
	_laser(z, Vector2(206, 630), Vector2(1074, 694), Color("#FF4757"))
	_laser(z, Vector2(1074, 630), Vector2(206, 694), Color("#FF4757"))
	_laser(z, Vector2(206, 662), Vector2(1074, 662), VIOLET)
	for k: float in [1.0, -1.0]:
		_laser(z, Vector2(640.0 + k * 172.0, 196.0), Vector2(640.0 + k * 172.0, 336.0), Color("#FF4757"))
	_sign(z, Vector2(196, 862), "PRICE ORACLE\nprices rise after every gain", Color("#B794FF"), 11)
	# The balance console. It says "yes".
	_prop(z, "struct_console", Vector2(640, 800), 0.95, Color(0.9, 0.78, 0.46))
	_screen(z, Vector2(640, 778), accent, Vector2(1.4, 1.0), _depth(800, 56))
	_sign(z, Vector2(566, 858), "BALANCE: yes\nRate limit: spiritual", accent, 11)

## Small cluster helper for composing themed set-dressing.
	# The posts the lattice actually comes out of, and a cart of reserves left
	# where the last audit abandoned it.
	_prop(z, "dress_laser_emitter", Vector2(186, 640), 1.0, Color(1.0, 0.78, 0.6))
	_prop(z, "dress_laser_emitter", Vector2(1094, 704), 1.0, Color(1.0, 0.78, 0.6))
	_prop(z, "dress_ore_cart", Vector2(884, 894), 0.9, Color(1.0, 0.86, 0.5), -0.06)

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
## primary neon, "accent" its secondary. Floor tints were raised roughly 1.6x in
## this pass — measured against captured frames the old floors sat at ~0.03-0.05
## luminance, i.e. a black screen with props on it. "tile_mul" brightens the
## region's own (very dark) tile_* variants toward the same value.
static func _region_theme(region_id: String) -> Dictionary:
	match region_id:
		"dependency_district":
			# ACID #A8FF3E over crate-orange #E08A3C.
			var structs := _clu(190, 620, "struct_crate", 3, 0.95, Color(0.88, 0.54, 0.24), 55)
			structs += _clu(1120, 604, "struct_crate", 3, 0.95, Color(0.82, 0.5, 0.22), 55)
			structs += _clu(206, 424, "struct_crate", 3, 0.9, Color(0.86, 0.52, 0.24), 50)
			structs += [{"t": "struct_tower", "p": Vector2(1160, 430), "s": 0.9, "m": Color(0.62, 0.78, 0.48)}]
			return {
				"floor": Color(0.62, 0.76, 0.55), "wall": Color(0.5, 0.64, 0.42), "tile_mul": 2.3,
				"glow": Color("#A8FF3E"), "accent": Color("#E08A3C"),
				"lights": [Vector2(220, 620), Vector2(1120, 600)], "structs": structs,
				"signs": [
					# Dropped clear of the crate stack it labels — at y=668 the sign was
					# buried inside the pile's own y-sorted sprites.
					{"p": Vector2(146, 716), "t": "npm install\n(attempt #47)", "c": Color("#E08A3C")},
					# Moved off the maintainer's corner: NPC nameplates and bark
					# bubbles reserve a 340x140 column above every NPC now, and at
					# (1092,656) this caption lost the eviction ladder and was
					# hidden outright — the joke stopped existing.
					{"p": Vector2(660, 700), "t": "Dependencies: 1,402\nDirect: 3", "c": Color("#A8FF3E")},
					{"p": Vector2(560, 604), "t": "left-pad memorial\n11 lines. Global outage.", "c": Color("#E08A3C"), "s": 11},
					# Same story one crate cluster up: nudged below the stack's footprint.
					{"p": Vector2(206, 532), "t": "\"it works after a reinstall\"\n(the reinstall is the fix)", "c": Color("#A8FF3E"), "s": 11},
				],
			}
		"stackoverflow_ruins":
			# Dusty gold #E8C46B and copper #C97B4A: monument to answers past.
			var structs: Array = [
				{"t": "struct_arch", "p": Vector2(272, 604), "s": 1.0, "m": Color(0.74, 0.68, 0.54)},
				{"t": "struct_arch", "p": Vector2(1012, 620), "s": 0.95, "m": Color(0.68, 0.62, 0.5)},
			]
			structs += _clu(196, 792, "struct_slab", 2, 0.75, Color(0.68, 0.62, 0.52), 60)
			structs += _clu(1156, 780, "struct_slab", 2, 0.7, Color(0.62, 0.56, 0.48), 60)
			return {
				"floor": Color(0.76, 0.68, 0.53), "wall": Color(0.64, 0.57, 0.44), "tile_mul": 2.1,
				"glow": Color("#E8C46B"), "accent": Color("#C97B4A"), "ambient": "dust",
				"lights": [Vector2(272, 600), Vector2(1012, 616)], "structs": structs,
				"signs": [
					{"p": Vector2(170, 664), "t": "Marked as duplicate.", "c": Color("#E8C46B")},
					{"p": Vector2(1000, 676), "t": "Works in jQuery 1.4", "c": Color("#C97B4A")},
					{"p": Vector2(544, 660), "t": "\"just use the other library\"\n(the other library is gone)", "c": Color("#E8C46B"), "s": 11},
					{"p": Vector2(214, 200), "t": "Closed: not enough\nresearch effort shown", "c": Color("#C97B4A"), "s": 11},
				],
			}
		"api_bazaar":
			# Pink night market: MAGENTA #FF2D95 signage, GOLD #FFD34D goods.
			var structs := _clu(200, 470, "struct_console", 2, 0.85, Color(0.92, 0.72, 0.86), 60)
			structs += _clu(1104, 462, "struct_console", 2, 0.85, Color(0.9, 0.68, 0.84), 60)
			structs += _clu(206, 636, "struct_crate", 3, 0.85, Color(0.86, 0.7, 0.36), 55)
			return {
				"floor": Color(0.7, 0.55, 0.7), "wall": Color(0.6, 0.44, 0.6), "tile_mul": 2.4,
				"glow": Color("#FF2D95"), "accent": Color("#FFD34D"),
				"lights": [Vector2(200, 470), Vector2(1104, 462)], "structs": structs,
				"signs": [
					{"p": Vector2(146, 700), "t": "API keys — cash only", "c": Color("#FF2D95")},
					{"p": Vector2(1064, 700), "t": "429: come back later", "c": Color("#FFD34D")},
					{"p": Vector2(540, 660), "t": "SLA: 99.9%\n(of the good days)", "c": Color("#FF2D95"), "s": 11},
					{"p": Vector2(1052, 372), "t": "Priced per token.\nWhich token? Yes.", "c": Color("#FFD34D"), "s": 11},
				],
			}
		"cloud_district":
			# Sky #6BC7FF against near-white #E8F4FF: expensive weather.
			var structs := _clu(196, 604, "struct_orb", 2, 0.7, Color(0.62, 0.82, 1.0), 60)
			structs += _clu(1116, 612, "struct_orb", 2, 0.65, Color(0.76, 0.88, 1.0), 60)
			structs += _clu(214, 800, "struct_tower", 2, 0.75, Color(0.6, 0.68, 0.84), 55)
			return {
				"floor": Color(0.66, 0.76, 0.92), "wall": Color(0.6, 0.7, 0.88), "tile_mul": 2.0,
				"glow": Color("#6BC7FF"), "accent": Color("#E8F4FF"), "ambient": "packets",
				"lights": [Vector2(196, 604), Vector2(1116, 612)], "structs": structs,
				"signs": [
					{"p": Vector2(150, 664), "t": "Elastic. Ask us how.\n(we cannot explain)", "c": Color("#6BC7FF")},
					# Was at (1016,668): inside the orb cluster AND the salesperson's
					# name-tag box, which is why the captured frame read "Egress f…
					# to leavi… nking." Re-hung just under the exit gate, where the
					# joke about being charged for leaving stands next to the leaving.
					# ...and then out of the salesperson's bark column, which now
					# reaches 200px above her head. Still on the walk out to the
					# gate, which is the whole point of the line.
					{"p": Vector2(660, 690), "t": "Egress fees apply\nto leaving. And to thinking.", "c": Color("#E8F4FF"), "s": 11},
					{"p": Vector2(534, 620), "t": "Migration: 4% complete\nBudget: 210% complete", "c": Color("#6BC7FF"), "s": 11},
					{"p": Vector2(206, 872), "t": "Multi-cloud:\ndown in two places at once", "c": Color("#E8F4FF"), "s": 11},
				],
			}
		"open_source_wildlands":
			# Leaf #58E07C over moss #3E9E5C: verdant, mostly unmerged.
			var structs := _clu(196, 604, "struct_crate", 3, 0.85, Color(0.5, 0.7, 0.46), 50)
			structs += _clu(1122, 610, "struct_slab", 2, 0.8, Color(0.44, 0.66, 0.46), 55)
			structs += _clu(1140, 300, "struct_crate", 2, 0.8, Color(0.46, 0.66, 0.42), 50)
			return {
				"floor": Color(0.58, 0.76, 0.6), "wall": Color(0.48, 0.66, 0.5), "tile_mul": 2.3,
				"glow": Color("#58E07C"), "accent": Color("#3E9E5C"), "ambient": "spores",
				"lights": [Vector2(196, 600), Vector2(1122, 606)], "structs": structs,
				"signs": [
					{"p": Vector2(146, 664), "t": "PRs welcome (ignored)", "c": Color("#58E07C")},
					{"p": Vector2(1030, 664), "t": "Maintained by 1 human\nand a lot of guilt", "c": Color("#3E9E5C"), "s": 11},
					{"p": Vector2(536, 640), "t": "License: MIT\n(nobody read it)", "c": Color("#58E07C"), "s": 11},
					{"p": Vector2(1042, 214), "t": "Sponsor tiers:\n$1 — eternal gratitude", "c": Color("#3E9E5C"), "s": 11},
				],
			}
		"corporate_enterprise":
			# Corp blue #4D7CFF behind glass #93A7C8: sterile on purpose.
			var structs: Array = []
			for gx in 2:
				structs.append({"t": "struct_slab", "p": Vector2(180.0 + float(gx) * 920.0, 470.0), "s": 0.75, "m": Color(0.58, 0.63, 0.76)})
				structs.append({"t": "struct_slab", "p": Vector2(180.0 + float(gx) * 920.0, 600.0), "s": 0.7, "m": Color(0.54, 0.59, 0.72)})
			return {
				"floor": Color(0.68, 0.72, 0.86), "wall": Color(0.58, 0.63, 0.78), "tile_mul": 1.9,
				"glow": Color("#4D7CFF"), "accent": Color("#93A7C8"),
				"lights": [Vector2(180, 470), Vector2(1100, 470)], "structs": structs,
				"signs": [
					{"p": Vector2(120, 664), "t": "Synergy Zone", "c": Color("#4D7CFF")},
					{"p": Vector2(1062, 664), "t": "Q3 OKR: \"leverage AI\"\nStatus: leveraged", "c": Color("#93A7C8")},
					{"p": Vector2(540, 630), "t": "Room \"Innovation\"\nbooked until 2031", "c": Color("#4D7CFF"), "s": 11},
					{"p": Vector2(214, 880), "t": "Headcount freeze.\nAI headcount: unlimited.", "c": Color("#93A7C8"), "s": 11},
				],
			}
		"gpu_mines":
			# Ember #FF6B2D and heat #FF3D2D: everything here is thermal-throttled.
			var structs := _clu(190, 604, "struct_tower", 2, 0.8, Color(0.72, 0.5, 0.42), 55)
			structs += _clu(1130, 596, "struct_tower", 2, 0.8, Color(0.7, 0.46, 0.38), 55)
			structs += _clu(196, 452, "struct_crate", 3, 0.8, Color(0.74, 0.52, 0.4), 50)
			return {
				"floor": Color(0.72, 0.54, 0.46), "wall": Color(0.66, 0.46, 0.4), "tile_mul": 2.2,
				"glow": Color("#FF6B2D"), "accent": Color("#FF3D2D"), "ambient": "embers",
				"lights": [Vector2(190, 600), Vector2(1130, 592)], "structs": structs,
				"signs": [
					{"p": Vector2(136, 668), "t": "GPU go brrr", "c": Color("#FF6B2D")},
					{"p": Vector2(1036, 590), "t": "Allocation approved!\nDelivery: eventually.", "c": Color("#FF3D2D"), "s": 11},
					{"p": Vector2(540, 640), "t": "Training run: 71%\nETA drifts 2h per hour", "c": Color("#FF6B2D"), "s": 11},
					{"p": Vector2(198, 200), "t": "Do not open. Heat.\n(someone opened it)", "c": Color("#FF3D2D"), "s": 11},
				],
			}
		"production":
			# RED #FF4757 alarms over AMBER #FFB020 warnings. Everything is fine.
			var structs: Array = [
				{"t": "struct_tower", "p": Vector2(186, 470), "s": 0.85, "m": Color(0.64, 0.44, 0.44)},
				{"t": "struct_tower", "p": Vector2(1104, 470), "s": 0.85, "m": Color(0.64, 0.44, 0.44)},
			]
			structs += _clu(206, 636, "struct_crate", 3, 0.85, Color(0.78, 0.58, 0.3), 55)
			return {
				"floor": Color(0.74, 0.54, 0.56), "wall": Color(0.66, 0.44, 0.46), "tile_mul": 2.5,
				"glow": Color("#FF4757"), "accent": Color("#FFB020"), "ambient": "sparks",
				"lights": [Vector2(186, 466), Vector2(1104, 466)], "structs": structs,
				"signs": [
					{"p": Vector2(120, 660), "t": "PRODUCTION — DO NOT TOUCH", "c": Color("#FF4757")},
					{"p": Vector2(1052, 660), "t": "Observability: vibes", "c": Color("#FFB020")},
					{"p": Vector2(526, 626), "t": "Uptime 99.98%.\nThe 0.02% is happening now.", "c": Color("#FF4757"), "s": 11},
					{"p": Vector2(200, 214), "t": "Last deploy: 4 min ago\nDeployed by: nobody. Ask anyone.", "c": Color("#FFB020"), "s": 11},
				],
			}
		"token_vault":
			# GOLD #FFD34D hoard with VIOLET #8B5CF6 arcana in the corners.
			var structs := _clu(192, 604, "struct_orb", 2, 0.6, Color(1.0, 0.83, 0.3), 55)
			structs += _clu(1124, 600, "struct_orb", 2, 0.6, Color(1.0, 0.8, 0.28), 55)
			structs += _clu(196, 442, "struct_orb", 1, 0.55, Color(1.0, 0.86, 0.36), 30)
			return {
				"floor": Color(0.78, 0.68, 0.5), "wall": Color(0.72, 0.62, 0.42), "tile_mul": 2.4,
				"glow": Color("#FFD34D"), "accent": VIOLET, "ambient": "sparkle",
				"lights": [Vector2(192, 600), Vector2(1124, 596)], "structs": structs,
				"signs": [
					{"p": Vector2(130, 664), "t": "TOKEN RESERVES", "c": Color("#FFD34D")},
					{"p": Vector2(1076, 660), "t": "Do not spend it all\nat once. Or at all.", "c": Color("#B794FF")},
					{"p": Vector2(540, 636), "t": "Context window:\nsold separately", "c": Color("#FFD34D"), "s": 11},
					{"p": Vector2(214, 214), "t": "Vault policy: you may look\nat the tokens.", "c": Color("#B794FF"), "s": 11},
				],
			}
		_:
			return {
				"floor": Color(0.72, 0.72, 0.8), "wall": Color(0.68, 0.68, 0.78), "tile_mul": 2.2,
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
			# No spill light here. region_portal.gd lights its own gate in the
			# DESTINATION's hue (energy 0.58, texture_scale 2.4) plus a wide dim
			# halo. The 410px full-energy VIOLET wash that used to sit here was
			# the single biggest reason portals read as flat coloured blobs, and
			# it was violet no matter where the door went — fighting the
			# per-destination hue the swirl works so hard to establish.

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

## NPC anchors. These sit INSIDE their region's set-piece (the reseller behind his
## stall, the foreman in his shack) so a person is always standing in a lit place
## worth walking to. The room is 1280x960 with walls, so nothing may exceed
## x 1220 / y 900 — the API reseller used to stand at x=1300, i.e. inside the wall,
## half off-camera, which is a large part of why the Bazaar felt empty.
static func _region_npcs(region_id: String) -> Array:
	match region_id:
		"localhost":
			return [{"id": "roommate_ai", "pos": Vector2(1200, 900), "quests": ["hello_localhost", "tiny_change", "ship_dream_app"]}]
		"dependency_district":
			return [{"id": "maintainer", "pos": Vector2(1076, 786), "quests": ["install_node", "fix_without_touching"]}]
		"stackoverflow_ruins":
			return [{"id": "stackoverflow_hermit", "pos": Vector2(1000, 704), "quests": ["stackoverflow_pilgrimage", "merge_conflict_hell"]}]
		"api_bazaar":
			return [{"id": "api_reseller", "pos": Vector2(1088, 782), "quests": ["one_more_api_call", "junior_agent"]}, {"id": "junior_agent", "pos": Vector2(800, 620), "quests": ["junior_agent"]}]
		"cloud_district":
			return [{"id": "cloud_salesperson", "pos": Vector2(1128, 748), "quests": ["cloud_migration", "context_window_full"]}]
		"open_source_wildlands":
			return [{"id": "oss_maintainer", "pos": Vector2(1058, 852), "quests": ["license_puzzle"]}]
		"corporate_enterprise":
			return [{"id": "svp_ai", "pos": Vector2(1000, 786), "quests": ["enterprise_ready"]}]
		"gpu_mines":
			return [{"id": "gpu_foreman", "pos": Vector2(1136, 692), "quests": ["gpu_rush"]}]
		"production":
			return [{"id": "oncall_engineer", "pos": Vector2(1090, 848), "quests": ["production_down"]}]
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
## Each one now sits inside a set-piece and carries its own floor pool, so they
## read as objects in a place rather than markers on a plain.
const REGION_FLAVOR := {
	"dependency_district": [
		["prop_node_modules", Vector2(300, 300), "node_modules"],
		["prop_leftpad", Vector2(1010, 300), "left-pad"],
		["prop_lockfile", Vector2(560, 762), "package-lock.json"],
	],
	"api_bazaar": [
		["prop_api_stall", Vector2(276, 214), "API reseller stall"],
		["prop_status_page", Vector2(1004, 214), "Status page"],
		["prop_pricing", Vector2(604, 786), "Pricing board"],
	],
	"stackoverflow_ruins": [
		["prop_gravestone", Vector2(238, 300), "Question gravestone"],
		["prop_accepted", Vector2(640, 236), "Accepted answer"],
	],
	"cloud_district": [
		["prop_invoice", Vector2(640, 786), "Cloud invoice"],
		["prop_dashboard", Vector2(1128, 764), "Cloud dashboard"],
	],
	"gpu_mines": [
		["prop_rig", Vector2(318, 262), "Mining rig"],
		["prop_fan", Vector2(1096, 786), "Cooling fan"],
	],
	"open_source_wildlands": [
		["prop_sponsor", Vector2(1058, 796), "Sponsor button"],
		["prop_issue", Vector2(296, 760), "Open issue #4092"],
	],
	"corporate_enterprise": [
		["prop_mission", Vector2(258, 616), "Mission statement"],
		["prop_kanban", Vector2(770, 232), "Kanban board"],
	],
	"production": [
		["prop_pager", Vector2(640, 296), "On-call pager"],
		["prop_runbook", Vector2(268, 774), "Incident runbook"],
	],
	"token_vault": [
		["prop_vault", Vector2(640, 296), "Token vault"],
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
