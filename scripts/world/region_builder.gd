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
	# Cleared here, not only in _build_region_static: travelling to Localhost
	# takes the other branch, and a cover list left over from the region you
	# just walked out of would then reject token positions in the apartment.
	_cover_rects.clear()
	# Same reason: the layout template is module-level state, and Localhost takes
	# the other branch, so adopt it here too rather than leaving the last region's
	# plaza and artery hanging around on the static.
	_use_layout(region_id)
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
	# Regions rebuild on every travel; the cover list belongs to THIS build.
	_cover_rects.clear()
	# Adopt this region's layout template BEFORE anything measures the floor:
	# every zoning, paint and scatter pass below reads the plaza and the artery
	# out of _layout, and a stale one would build the previous room's footprint.
	_use_layout(region_id)
	var theme := _region_theme(region_id)
	var w := REGION_SIZE.x * TILE_SIZE
	var h := REGION_SIZE.y * TILE_SIZE
	var spawn_pos := Vector2(w * 0.5, h * 0.5)

	_reserve_labels(region_id, w, h)
	_build_floor_themed(parent, theme, w, h, region_id)
	_build_walls_themed(parent, theme, w, h)
	_build_region_grounding(parent, w, h)
	_build_backdrop(parent, region_id, theme, w, h)
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
	# Before the containers: _populate_region reads _cover_rects when it scatters
	# tokens, so the cover has to exist by then.
	_build_encounters(parent, region_id, theme, w, h)
	# After the cover, before the containers: the signature scatter dodges cover
	# and the tokens dodge both.
	_build_signature(parent, region_id, theme, w, h)
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

## Stable per-region seed for every geometry function below. The room must
## rebuild byte-identically each time you walk back into it, so nothing here is
## allowed to touch an RNG.
static func _region_seed(region_id: String) -> int:
	return absi(region_id.hash()) % 97

## Per-region LAYOUT TEMPLATE — the fix for "all nine non-Localhost regions share
## one composition". Round 5 put an identical octagonal landing plaza at the
## exact centre of every room and ran the traffic artery dead straight across
## the middle of all of them, so the captured frames differed in hue and in
## nothing else: same slab, same player-dead-centre, same portal on the same
## left third. Each region now owns its plaza's PLACE, SHAPE and SIZE and its
## own artery baseline, and every pass that draws either of them — tile zoning,
## curb trim, lane paint, blotches, litter, decals, spurs, the signature
## scatter — reads the same numbers from here, so the material edge and the
## painted edge can never disagree with each other.
##
## Keys:
##   c      plaza centre, as an offset from the room centre
##   r      plaza radii (x, y) in pixels
##   form   0 octagon, 1 court (round), 2 dock (long and chamfered),
##          3 annex (a main lobe with a smaller one budded off it)
##   rot    plaza rotation, radians
##   annex  the second lobe's centre, in the plaza's own normalised units
##   band   artery baseline, as an offset from the room's mid-height
##   tilt   how far the artery climbs (or falls) from the west wall to the east
##   wave   amplitude of the artery's meander
##
## HARD RULE for anyone editing this table: the plaza must still CONTAIN the
## spawn (640, 480) with at least ~50px to spare. The landing plaza is the
## floor saying "you are here", and a player who arrives standing on the dark
## open field has lost the one piece of orientation the ground owes them.
const LAYOUT_DEFAULT := {
	"c": Vector2.ZERO, "r": Vector2(206.0, 145.0), "form": 0, "rot": 0.0,
	"annex": Vector2(120.0, 140.0), "band": 0.0, "tilt": 0.0, "wave": 0.0,
}

const REGION_LAYOUT := {
	# A long west dock in front of the node_modules heap; the artery sags south.
	"dependency_district": {"c": Vector2(-104.0, 36.0), "r": Vector2(268.0, 124.0),
		"form": 2, "rot": 0.0, "annex": Vector2.ZERO,
		"band": 58.0, "tilt": -50.0, "wave": 20.0},
	# A round clearing swept out of the rubble, south-east, artery climbing.
	"stackoverflow_ruins": {"c": Vector2(64.0, 74.0), "r": Vector2(210.0, 178.0),
		"form": 1, "rot": 0.0, "annex": Vector2.ZERO,
		"band": -66.0, "tilt": 38.0, "wave": 26.0},
	# A market square with a second, smaller pitch budded off it to the south-east.
	"api_bazaar": {"c": Vector2(-40.0, -58.0), "r": Vector2(214.0, 146.0),
		"form": 3, "rot": 0.0, "annex": Vector2(118.0, 152.0),
		"band": 42.0, "tilt": -30.0, "wave": 30.0},
	# A very wide, very shallow apron under the cathedral: the nave's floor.
	"cloud_district": {"c": Vector2(56.0, -56.0), "r": Vector2(292.0, 138.0),
		"form": 2, "rot": 0.0, "annex": Vector2.ZERO,
		"band": -54.0, "tilt": 52.0, "wave": 18.0},
	# A trodden forest clearing, west of centre, with the widest meander of the
	# nine — nothing in the wildlands runs straight.
	"open_source_wildlands": {"c": Vector2(-80.0, 58.0), "r": Vector2(228.0, 172.0),
		"form": 1, "rot": 0.0, "annex": Vector2.ZERO,
		"band": 30.0, "tilt": 44.0, "wave": 34.0},
	# A skewed lobby slab: the only plaza in the game somebody drew on a plan.
	"corporate_enterprise": {"c": Vector2(84.0, -24.0), "r": Vector2(238.0, 156.0),
		"form": 0, "rot": 0.42, "annex": Vector2.ZERO,
		"band": -22.0, "tilt": -56.0, "wave": 14.0},
	# A cut bench with a spoil apron dropping away to the south-west.
	"gpu_mines": {"c": Vector2(-54.0, -54.0), "r": Vector2(230.0, 146.0),
		"form": 3, "rot": 0.0, "annex": Vector2(-96.0, 164.0),
		"band": 62.0, "tilt": 30.0, "wave": 24.0},
	# A muster slab canted off the room's axis, north-east, under the war room.
	"production": {"c": Vector2(78.0, -36.0), "r": Vector2(244.0, 146.0),
		"form": 0, "rot": -0.34, "annex": Vector2.ZERO,
		"band": -70.0, "tilt": 24.0, "wave": 28.0},
	# A wide counting floor, south of centre, under the reserve pedestal.
	"token_vault": {"c": Vector2(-24.0, 52.0), "r": Vector2(276.0, 140.0),
		"form": 2, "rot": 0.0, "annex": Vector2.ZERO,
		"band": -40.0, "tilt": -40.0, "wave": 20.0},
}

## The layout the CURRENT build is using. A module-level static for the same
## reason `_cover_rects` and `_sign_prio` are: the geometry functions below are
## consumed from a dozen call sites that have no region_id to hand, and
## threading one through eleven signatures to reach _plaza_field would be worse
## than one value set once at the top of _build_region_static. Defaults to the
## round-5 template so a stray call before a build still returns a sane room.
static var _layout: Dictionary = LAYOUT_DEFAULT
## The current region's geometry seed, kept beside the layout for the two passes
## that have to dodge the plaza and the artery but were never handed a region_id
## (_build_region_detail is one).
static var _layout_seed := 0

static func _use_layout(region_id: String) -> void:
	_layout = REGION_LAYOUT.get(region_id, LAYOUT_DEFAULT)
	_layout_seed = _region_seed(region_id)

static func _plaza_center(w: float, h: float) -> Vector2:
	var c: Vector2 = _layout.get("c", Vector2.ZERO)
	return Vector2(w * 0.5, h * 0.5) + c

static func _plaza_radii() -> Vector2:
	var r: Vector2 = _layout.get("r", Vector2(206.0, 145.0))
	return r

## Centre-line of the walkway artery at a given x. Round 5 hard-coded this to
## h*0.5 in nine separate places, which is most of why every region read as the
## same room: one horizontal bright stripe through the middle of the frame. It
## now drops or lifts, tilts across the room and meanders, per region.
static func _band_y(x: float, w: float, h: float, seed_v: int) -> float:
	var t := x / maxf(1.0, w)
	var base := float(_layout.get("band", 0.0))
	var tilt := float(_layout.get("tilt", 0.0))
	var wave := float(_layout.get("wave", 0.0))
	return h * 0.5 + base + tilt * (t - 0.5) * 2.0 \
		+ sin(t * 5.7 + float(seed_v % 17) * 0.37) * wave

## Deterministic low-frequency wobble in [-1,1]: coarse 160px cells hashed and
## smoothstep-blended. Every zone boundary consumes this, so a seam MEANDERS
## instead of running an axis-aligned ruler across open floor. Round 4 shipped
## the material zones as clean rectangles and the captured frames read them
## exactly as what they were — texture patches pasted onto the ground.
static func _zone_wobble(p: Vector2, seed_v: int) -> float:
	var cell := 160.0
	var cx := int(floor(p.x / cell))
	var cy := int(floor(p.y / cell))
	var fx := p.x / cell - float(cx)
	var fy := p.y / cell - float(cy)
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var v00 := float(_cell_hash(cx + seed_v, cy) % 2001) / 1000.0 - 1.0
	var v10 := float(_cell_hash(cx + 1 + seed_v, cy) % 2001) / 1000.0 - 1.0
	var v01 := float(_cell_hash(cx + seed_v, cy + 1) % 2001) / 1000.0 - 1.0
	var v11 := float(_cell_hash(cx + 1 + seed_v, cy + 1) % 2001) / 1000.0 - 1.0
	return lerpf(lerpf(v00, v10, fx), lerpf(v01, v11, fx), fy)

## Half-width of the walkway artery at a given x. The band swells, pinches twice
## and drifts the whole way across the room, phase-shifted per region, so its
## edge never draws the unbroken straight line that made it read as a lighter
## stripe of the same floor rather than a different material.
static func _band_half(x: float, w: float, seed_v: int) -> float:
	var t := x / maxf(1.0, w)
	var ph := float(seed_v % 29) * 0.21
	return 92.0 + sin(t * 7.3 + ph) * 15.0 + sin(t * 16.9 + ph * 1.7) * 8.0 + cos(t * 3.1 + ph) * 6.0

## Signed field for the landing plaza: negative inside. Never a circle — a
## circle quantised to 64px tiles produced the blocky slab visible in
## region_gpu_mines.png and region_token_vault.png — and, since round 6, never
## the SAME shape twice: the plaza's place, radii, rotation and outline family
## all come out of REGION_LAYOUT, so a player can name the room from the shape
## of its floor with every label switched off. Everything is measured in a
## normalised 206-unit space so the wobble, the threshold and the ring painter
## keep working whatever radii a region asks for.
static func _plaza_field(p: Vector2, w: float, h: float, seed_v: int) -> float:
	var r := _plaza_radii()
	var d := (p - _plaza_center(w, h)).rotated(-float(_layout.get("rot", 0.0)))
	d = Vector2(d.x * 206.0 / maxf(1.0, r.x), d.y * 206.0 / maxf(1.0, r.y))
	var f := 0.0
	match int(_layout.get("form", 0)):
		1:  # court — a swept round clearing
			f = d.length()
		2:  # dock — long, shallow, chamfered at the ends
			f = maxf(maxf(absf(d.x), absf(d.y)), (absf(d.x) + absf(d.y)) * 0.66)
		3:  # annex — a main lobe with a smaller one budded off it
			var a: Vector2 = _layout.get("annex", Vector2(120.0, 140.0))
			f = minf(d.length(), (d - a).length() * 1.28)
		_:  # octagon
			f = maxf(maxf(absf(d.x), absf(d.y)), (absf(d.x) + absf(d.y)) * 0.735)
	return f - (206.0 + _zone_wobble(p, seed_v + 23) * 30.0)

## A point ON the plaza outline along the bearing `a`. Marched outward rather
## than bisected: the annex form is a UNION of two lobes, so a ray can leave one
## and re-enter the other, and a bisection would happily settle in the notch
## between them. Taking the last inside sample gives the true silhouette for
## every form. Build-time only, ~60 field probes per bearing.
static func _plaza_edge(a: float, w: float, h: float, seed_v: int) -> Vector2:
	var c := _plaza_center(w, h)
	var r := _plaza_radii()
	var dir := Vector2(cos(a) * r.x, sin(a) * r.y).normalized()
	var last := 48.0
	for i in 62:
		var rr := 48.0 + float(i) * 9.0
		if _plaza_field(c + dir * rr, w, h, seed_v) < 0.0:
			last = rr
	return c + dir * last

## Perimeter falloff depth at a point — wobbled, so the ring the room ends in is
## a shoreline and not a picture frame.
static func _edge_depth(p: Vector2, w: float, h: float, seed_v: int) -> float:
	return minf(minf(p.x, w - p.x), minf(p.y - 46.0, h - p.y)) \
		- _zone_wobble(p, seed_v + 51) * 34.0

## Floor zoning. A room at one flat value is a void with props in it. The spawn
## gets a bright landing plaza, the portal-to-portal artery gets a worn traffic
## lane, and the perimeter falls off — so the eye immediately knows where the
## room's "somewhere" is, and the ground reads as ground. Brightness reads off
## the SAME wobbled fields as the material zoning below; when the two disagreed
## the value step and the material step landed a tile apart and advertised both.
static func _floor_zone(p: Vector2, w: float, h: float, seed_v: int) -> float:
	var k := 1.0
	var bh := _band_half(p.x, w, seed_v)
	var lane := absf(p.y - _band_y(p.x, w, h, seed_v))
	if lane < bh and p.x > 130.0 and p.x < w - 130.0:
		k += 0.22 * (1.0 - lane / bh)
	var pf := _plaza_field(p, w, h, seed_v)
	if pf < 0.0:
		k += 0.18 * minf(1.0, -pf / 200.0)
	var e := _edge_depth(p, w, h, seed_v)
	if e < 156.0:
		# Round-4 rule 3: edges darkest. Was -0.28; the perimeter now falls off
		# hard enough to read as the room ending rather than the wash fading.
		k -= 0.34 * (1.0 - maxf(e, 0.0) / 156.0)
	return k

## Ground-MATERIAL zone for a tile centre (round-4 rule 1). _floor_zone answers
## "how bright is this cell"; this answers "what is this cell MADE of":
## 0 open field, 1 walkway band (the portal-to-portal artery), 2 landing plaza,
## 3 perimeter. Checked in priority order so the plaza wins over the band where
## they overlap at the spawn.
##
## `hv` is the tile's own hash and buys the transition: a +/-34px slop on every
## threshold makes the last row of tiles either side of a seam INTERLOCK — a
## one-tile dithered blend. Combined with the wobbled outlines above, no zone
## ends in a clean edge anywhere in the room.
static func _tile_zone(p: Vector2, w: float, h: float, seed_v: int, hv: int) -> int:
	var dither := (float(hv % 89) / 89.0 - 0.5) * 68.0
	if _edge_depth(p, w, h, seed_v) < 106.0 + dither:
		return 3
	if _plaza_field(p, w, h, seed_v) + dither < 0.0:
		return 2
	if absf(p.y - _band_y(p.x, w, h, seed_v)) < _band_half(p.x, w, seed_v) + dither:
		return 1
	return 0

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
	# Round-4 material set (art agents supply these; everything exists()-guarded
	# with today's tiles as the fallback): floor_<family>_base/alt are the
	# region's ground proper, path_tile the maintained walkway deck.
	var has_base := suffix != "" and ResourceLoader.exists(GEN + "floor_" + suffix + "_base.png")
	var has_alt := suffix != "" and ResourceLoader.exists(GEN + "floor_" + suffix + "_alt.png")
	var has_path_tile := ResourceLoader.exists(GEN + "path_tile.png")
	var tile_mul: float = float(theme.get("tile_mul", 2.2))
	var seed_v := _region_seed(region_id)
	# The zone map is computed once and kept: the trim pass below needs to know
	# which tile edges are material SEAMS, and recomputing the fields per edge
	# would be four noise lookups per tile for no reason.
	var zones: Array[int] = []
	zones.resize(REGION_SIZE.x * REGION_SIZE.y)
	for x in REGION_SIZE.x:
		for y in REGION_SIZE.y:
			var hv := _cell_hash(x, y)
			var p := Vector2(x * TILE_SIZE + TILE_SIZE * 0.5, y * TILE_SIZE + TILE_SIZE * 0.5)
			var k := _floor_zone(p, float(w), float(h), seed_v) \
				* _floor_wear(x, y) \
				* (1.0 + (float(hv % 61) / 61.0 - 0.5) * 0.13)
			var tex_name := "tech_floor"
			# Per-cell hue drift as well as value drift: identical texture, three
			# slightly different ages of grout.
			var warm := (float((hv >> 11) % 41) / 41.0 - 0.5) * 0.05
			var m := Color(tint.r * k * (1.0 + warm), tint.g * k, tint.b * k * (1.0 - warm))
			# STRUCTURE BEFORE NOISE (round-4 rule 1): the material a tile is made
			# of is decided by WHERE it is — walkway band, landing plaza, perimeter,
			# open field — so the ground reads as designed zones, not one noise wash.
			var zn := _tile_zone(p, float(w), float(h), seed_v, hv)
			zones[x * REGION_SIZE.y + y] = zn
			match zn:
				1:  # walkway band: one clean deck material end to end
					if has_path_tile:
						tex_name = "path_tile"
						m = Color(k * 1.05, k * 1.05, k * 1.08)
					elif has_b:
						tex_name = "tile_" + suffix + "_b"
						var wv := k * tile_mul * 1.16
						m = Color(wv, wv, wv * 1.04)
					else:
						m = Color(tint.r * k * 1.18, tint.g * k * 1.18, tint.b * k * 1.22)
				2:  # landing plaza: the region's own showcase material
					if has_a:
						var pv := k * tile_mul * 1.08
						tex_name = "tile_" + suffix
						m = Color(pv * (1.0 + warm), pv, pv * (1.0 - warm))
					else:
						m = Color(tint.r * k * 1.16, tint.g * k * 1.16, tint.b * k * 1.16)
				3:  # perimeter: the darkest material — edges recede (rule 3)
					if has_base:
						tex_name = "floor_" + suffix + "_base"
						m = Color(k * (1.0 + warm), k, k * (1.0 - warm))
					m = m.darkened(0.26)
					if (hv >> 5) % 29 == 0:
						m = m.darkened(0.26)  # a cell something bad happened on
				_:  # open field
					if has_base:
						tex_name = "floor_" + suffix + "_base"
						if has_alt and hv % 100 < 26:
							tex_name = "floor_" + suffix + "_alt"
						m = Color(k * (1.0 + warm), k, k * (1.0 - warm))
					else:
						var fam := _cell_hash(x >> 1, (y >> 1) + 7919) % 10
						if hv % 100 < 14:
							fam = (hv >> 7) % 10  # one tile that does not match its slab
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
	_zone_trim(floor_node, zones, theme, w, h, seed_v)
	_floor_blotches(floor_node, theme, w, h, seed_v)
	_floor_mottle(floor_node, theme, w, h, region_id)
	_paint_paths(floor_node, region_id, theme, w, h, seed_v)
	_floor_region_structure(floor_node, region_id, theme, w, h, seed_v)
	_paint_lane(floor_node, theme, w, h, seed_v)
	var glow: Color = theme.get("glow", Color.WHITE)
	_paint_wayfinding(floor_node, region_id, w, h, glow)
	_floor_litter(floor_node, theme, w, h, region_id)

## Is this zone one somebody maintains? The walkway artery and the landing
## plaza are; the open field and the perimeter falloff are not.
static func _zone_kept(z: int) -> bool:
	return z == 1 or z == 2

## Is this tile a lone dither speckle — a tile whose zone matches none of its
## four orthogonal neighbours? Measured across all 97 region seeds this happens
## about 0.7 times per room, and curbing all four edges of one draws a tidy 64px
## box around a single tile: a pasted patch at tile scale, which is the exact
## defect the wobble and the dither exist to remove. Cheap to skip, so skip it.
static func _zone_speck(zones: Array[int], x: int, y: int) -> bool:
	var z0: int = zones[x * REGION_SIZE.y + y]
	for o: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var ax := x + o.x
		var ay := y + o.y
		if ax < 0 or ay < 0 or ax >= REGION_SIZE.x or ay >= REGION_SIZE.y:
			continue
		if zones[ax * REGION_SIZE.y + ay] == z0:
			return false
	return true

## Real transitions at every material seam. Round 4 laid one fill against
## another and stopped; the frames showed the pink plaza in the bazaar and the
## gold slab in the vault as decals sitting ON the floor rather than part of it.
## Every tile edge where the material changes now gets a poured curb — a dark
## groove with a lit lip on the brighter side — one in three gets debris shed
## across it, and one in nine gets a low kerb post. Because the outlines above
## are wobbled and dithered, this line-work is itself ragged, which is the whole
## point: a built edge with wear on it, not a cut.
static func _zone_trim(parent: Node2D, zones: Array[int], theme: Dictionary, _w: int, _h: int, seed_v: int) -> void:
	var accent: Color = theme.get("accent", Color(0.8, 0.8, 0.9))
	var glow: Color = theme.get("glow", Color(0.7, 0.8, 0.95))
	var ts := float(TILE_SIZE)
	for x in REGION_SIZE.x:
		for y in REGION_SIZE.y:
			var z0: int = zones[x * REGION_SIZE.y + y]
			for d in 2:
				var nx: int = (x + 1) if d == 0 else x
				var ny: int = y if d == 0 else (y + 1)
				if nx >= REGION_SIZE.x or ny >= REGION_SIZE.y:
					continue
				var z1: int = zones[nx * REGION_SIZE.y + ny]
				if z0 == z1:
					continue
				# A lone speckle keeps its material change but gets no curb —
				# four curbs around one tile is a drawn 64px box, i.e. the
				# pasted-patch defect at tile scale. See _zone_speck.
				if _zone_speck(zones, x, y) or _zone_speck(zones, nx, ny):
					continue
				var hv := _cell_hash(x * 7 + d * 3671, y * 13 + seed_v)
				# Seam centre, nudged off the lattice so the curb does not itself
				# redraw the 64px grid the whole floor pass works to hide.
				var jit := float(hv % 15) - 7.0
				var horiz := d == 1
				var sp := Vector2(
					float(x) * ts + (ts if d == 0 else ts * 0.5 + jit),
					float(y) * ts + (ts * 0.5 + jit if d == 0 else ts))
				var groove := Vector2(6.0, ts + 3.0) if not horiz else Vector2(ts + 3.0, 6.0)
				var lip := Vector2(2.0, ts + 3.0) if not horiz else Vector2(ts + 3.0, 2.0)
				# The lip sits on the MAINTAINED side — walkway (1) and plaza (2)
				# are the materials somebody would have bothered to edge. Picking
				# the lower zone index instead put the lit lip out on the open
				# field at every plaza seam, i.e. on the side with no kerb in the
				# fiction. Field-vs-perimeter has no maintained side, so it
				# tie-breaks on index as before. -1 is the z0 tile, +1 the z1 one.
				var toward := 1.0
				if _zone_kept(z0) != _zone_kept(z1):
					if _zone_kept(z0):
						toward = -1.0
				elif z0 < z1:
					toward = -1.0
				var off := Vector2(toward * 4.0, 0.0) if not horiz else Vector2(0.0, toward * 4.0)
				# Groove at -96 so the mottle pass wears it; the lit lip at -92,
				# ABOVE the mottle, because a curb is navigation line-work and
				# the same rule that keeps the lane paint crisp applies here.
				_rect(parent, sp, groove, Color(0, 0, 0, 0.44), -96)
				var trim_col: Color = accent if mini(z0, z1) < 2 else glow
				_rect(parent, sp + off, lip, Color(trim_col.r, trim_col.g, trim_col.b, 0.24), -92)
				if (hv >> 5) % 3 == 0:
					# Debris shed across the edge: the seam is where things collect.
					var dp := sp + Vector2(float((hv >> 9) % 21) - 10.0, float((hv >> 14) % 21) - 10.0)
					_rect(parent, dp, Vector2(float((hv >> 17) % 9) + 4.0, 3.0),
						Color(0, 0, 0, 0.26), -91, float(hv % 628) * 0.01)
				if (hv >> 7) % 9 == 0:
					# Kerb post. Small, dark, one emissive chip — reads as a marker
					# at a glance and as somebody's maintenance up close.
					_rect(parent, sp, Vector2(6, 11), Color(0.05, 0.055, 0.09, 0.95), _depth(sp.y, 6.0))
					_glow_rect(parent, sp + Vector2(0, -5), Vector2(4, 3),
						Color(trim_col.r, trim_col.g, trim_col.b, 0.7), _depth(sp.y, 7.0))

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
static func _floor_blotches(parent: Node2D, theme: Dictionary, w: int, h: int, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 606061
	var glow: Color = theme.get("glow", Color(0.6, 0.7, 0.9))
	for i in 22:
		var p := Vector2(rng.randf_range(70, w - 70), rng.randf_range(96, h - 50))
		var width := rng.randf_range(150.0, 460.0)
		if rng.randf() < 0.72:
			# Dark stains stay OFF the walkway band (round-4 rule 1, the same law
			# as the decal/litter skips): one 460px shadow across the maintained
			# deck reads as dirt the sweeping missed. The alpha draw still happens
			# so the scatter downstream keeps its deterministic layout.
			var stain_a := rng.randf_range(0.10, 0.26)
			if absf(p.y - _band_y(p.x, float(w), float(h), seed_v)) >= _band_half(p.x, float(w), seed_v) - 6.0:
				_floor_patch(parent, p, width, Color(0.012, 0.014, 0.03), stain_a, -97)
		else:
			# Scrubbed patches: somebody cleaned exactly this much and gave up.
			_floor_patch(parent, p, width * 0.7, Color(glow.r, glow.g, glow.b), rng.randf_range(0.03, 0.07), -97)

## Painted markings on the traffic lane and the landing plaza. Cheap, flat, and
## the single biggest readability win: the floor now has line-work on it.
static func _paint_lane(parent: Node2D, theme: Dictionary, w: int, h: int, seed_v: int) -> void:
	var accent: Color = theme.get("accent", Color(0.8, 0.8, 0.9))
	var glow: Color = theme.get("glow", Color.WHITE)
	# The band edge is a chain of short segments walking the SAME curve the tile
	# materials use, so the painted line and the material change agree and the
	# artery bends around the room instead of ruling a line across it. One long
	# rect per side was the tell that made this read as a stripe, not a road.
	# Both the centre-line and the half-width come from the region's layout now,
	# so no two rooms carry the artery at the same height or on the same slope.
	var steps := 30
	var x0 := 150.0
	var x1 := float(w) - 150.0
	for k: float in [1.0, -1.0]:
		for i in steps:
			var xa := x0 + (x1 - x0) * float(i) / float(steps)
			var xb := x0 + (x1 - x0) * float(i + 1) / float(steps)
			var ya := _band_y(xa, float(w), float(h), seed_v) + k * _band_half(xa, float(w), seed_v)
			var yb := _band_y(xb, float(w), float(h), seed_v) + k * _band_half(xb, float(w), seed_v)
			var seg := Vector2(xb - xa, yb - ya)
			var mid := Vector2((xa + xb) * 0.5, (ya + yb) * 0.5)
			var ln := seg.length() + 3.0
			var ang := seg.angle()
			_rect(parent, mid, Vector2(ln, 3.0), Color(0, 0, 0, 0.34), -93, ang)
			_rect(parent, mid - Vector2(0.0, k * 3.0), Vector2(ln, 2.0), Color(accent.r, accent.g, accent.b, 0.22), -93, ang)
			# hazard dashes just inside the painted edge, on every other segment
			if i % 2 == 0:
				_rect(parent, mid - Vector2(0.0, k * 11.0), Vector2(30.0, 6.0), Color(accent.r, accent.g, accent.b, 0.12), -93, ang + 0.5 * k)
	# Landing plaza kerb: "you are here". Round 5 drew this as 26 free-floating
	# dashes on a circle argued against an octagonal material outline, which is
	# the "dashed arc over the floor with nothing in it" the round-6 critique
	# filed — a decal, not a kerb. It is now a CONTINUOUS chain solved off the
	# same signed field the tiles use (so it traces whatever shape this region's
	# plaza actually is), it has a poured groove and a lit lip like every other
	# material edge in the room, and it encloses a real marked landing pad.
	var pc := _plaza_center(float(w), float(h))
	var pr := _plaza_radii()
	_floor_patch(parent, pc, pr.x * 2.1, glow, 0.055, -95)
	var ring: Array[Vector2] = []
	var ring_n := 44
	for i in ring_n:
		ring.append(_plaza_edge(TAU * float(i) / float(ring_n), float(w), float(h), seed_v))
	for i in ring_n:
		var a0: Vector2 = ring[i]
		var b0: Vector2 = ring[(i + 1) % ring_n]
		var rseg := b0 - a0
		var rln := rseg.length() + 4.0
		var rang := rseg.angle()
		var rmid := (a0 + b0) * 0.5
		var rin := (pc - rmid).normalized()
		# Groove, then the lit lip on the INSIDE — the maintained side, the same
		# rule _zone_trim follows at every other material seam in the room.
		_rect(parent, rmid, Vector2(rln, 5.0), Color(0, 0, 0, 0.38), -93, rang)
		_rect(parent, rmid + rin * 3.0, Vector2(rln, 2.0), Color(accent.r, accent.g, accent.b, 0.20), -93, rang)
		if i % 3 == 0:
			# Kerb reflectors: the dashes are ON the kerb now, not instead of it.
			_glow_rect(parent, rmid + rin * 7.0, Vector2(11.0, 3.0), Color(accent.r, accent.g, accent.b, 0.22), -92, rang)
		if i % 11 == 0:
			# Bolted kerb post with a lit chip, so the ring is fixed to something.
			_drop_shadow(parent, rmid + Vector2(0, 6), 26.0, _depth(rmid.y, 8.0) - 1, 0.30)
			_rect(parent, rmid, Vector2(7, 12), Color(0.05, 0.055, 0.09, 0.95), _depth(rmid.y, 7.0))
			_glow_rect(parent, rmid + Vector2(0, -6), Vector2(5, 3), Color(glow.r, glow.g, glow.b, 0.7), _depth(rmid.y, 8.0))
	# The pad the kerb encloses, painted at the spawn itself: a stencilled
	# landing cross with corner ticks. Somebody marked this spot on purpose,
	# which is the whole difference between a marking and a stray primitive.
	var sp := Vector2(float(w) * 0.5, float(h) * 0.5)
	_floor_patch(parent, sp, 250.0, glow, 0.05, -94)
	_rect(parent, sp, Vector2(96.0, 5.0), Color(0, 0, 0, 0.30), -93)
	_rect(parent, sp, Vector2(5.0, 62.0), Color(0, 0, 0, 0.30), -93)
	_rect(parent, sp, Vector2(92.0, 2.0), Color(accent.r, accent.g, accent.b, 0.24), -93)
	_rect(parent, sp, Vector2(2.0, 58.0), Color(accent.r, accent.g, accent.b, 0.24), -93)
	for c: Vector2 in [Vector2(-1.0, -1.0), Vector2(1.0, -1.0), Vector2(-1.0, 1.0), Vector2(1.0, 1.0)]:
		var cp := sp + Vector2(c.x * 78.0, c.y * 52.0)
		_rect(parent, cp + Vector2(c.x * -11.0, 0.0), Vector2(24.0, 4.0), Color(0, 0, 0, 0.28), -93)
		_rect(parent, cp + Vector2(0.0, c.y * -8.0), Vector2(4.0, 18.0), Color(0, 0, 0, 0.28), -93)
		_rect(parent, cp + Vector2(c.x * -11.0, -1.0), Vector2(22.0, 2.0), Color(glow.r, glow.g, glow.b, 0.16), -93)

## Region-specific GROUND STRUCTURE. The zoning pass gives every room a plaza,
## an artery and a perimeter; this is the layer that gives a REGION its own
## BUILT ground — the things somebody would have laid down here and nowhere
## else. It exists because of the standing note against the Wildlands: "a
## plus-shaped blob of high-frequency green salt-noise with no path, no material
## zones and no discernible structure". Noise cannot be fixed with more noise;
## it is fixed with hard edges, shading and contact shadows on top of it.
static func _floor_region_structure(parent: Node2D, region_id: String, theme: Dictionary, w: int, _h: int, seed_v: int) -> void:
	var glow: Color = theme.get("glow", Color(0.7, 0.8, 0.9))
	var accent: Color = theme.get("accent", glow)
	match region_id:
		"open_source_wildlands":
			# The boggy hollow the trail has to get across, and the boardwalk one
			# contributor built in 2016 and nobody has maintained since.
			_floor_patch(parent, Vector2(474, 664), 300.0, Color(0.02, 0.05, 0.035), 0.5, -94)
			_mat_zone(parent, Vector2(474, 664), Vector2(210.0, 116.0), Color(accent.r * 0.5, accent.g * 0.62, accent.b * 0.44), seed_v + 3)
			# Two trodden trails: the routes the traffic actually takes, worn
			# through the undergrowth, with the stones kicked to their edges.
			var t1: Array[Vector2] = [Vector2(566, 520), Vector2(452, 412), Vector2(346, 336)]
			var t2: Array[Vector2] = [Vector2(566, 566), Vector2(474, 664), Vector2(368, 736)]
			var t3: Array[Vector2] = [Vector2(714, 568), Vector2(834, 646), Vector2(902, 700)]
			_trail(parent, t1, Color(0.34, 0.27, 0.17), 62.0)
			_trail(parent, t2, Color(0.34, 0.27, 0.17), 68.0)
			_trail(parent, t3, Color(0.32, 0.26, 0.17), 58.0)
			_boardwalk(parent, Vector2(540, 596), Vector2(418, 700), Color(0.62, 0.48, 0.30))
			# Two moss mats and a gravel apron: three MATERIALS on the ground, each
			# with an outline the eye can find, which is the whole ask.
			_mat_zone(parent, Vector2(268, 486), Vector2(190.0, 118.0), Color(glow.r * 0.34, glow.g * 0.46, glow.b * 0.32), seed_v + 11)
			_mat_zone(parent, Vector2(986, 566), Vector2(216.0, 128.0), Color(glow.r * 0.30, glow.g * 0.42, glow.b * 0.30), seed_v + 19)
			_mat_zone(parent, Vector2(1050, 800), Vector2(240.0, 132.0), Color(0.30, 0.28, 0.24), seed_v + 27)
		"gpu_mines":
			# The ballast bed the ore line is actually laid on, and two spoil heaps
			# from the bench above — cut rock, not another wash of red noise.
			_mat_zone(parent, Vector2(636, 670), Vector2(700.0, 84.0), Color(0.26, 0.22, 0.20), seed_v + 5)
			_mat_zone(parent, Vector2(300, 596), Vector2(214.0, 116.0), Color(0.24, 0.17, 0.15), seed_v + 13)
			_mat_zone(parent, Vector2(1000, 560), Vector2(226.0, 120.0), Color(0.25, 0.18, 0.15), seed_v + 21)
			# The cut face, stepping down either side of the bench the plaza is
			# levelled into. Separate blocks with their own lit top edges: one
			# full-width rect would be another dead-straight line across the frame,
			# which is the defect this round is closing, not the fix for it.
			for i in 10:
				var hv := _cell_hash(seed_v + i * 71, 3307)
				var lx := 150.0 + float(i % 5) * 38.0 + (float(w) - 430.0) * float(i / 5)
				var ly := 336.0 + float(hv % 26)
				var lw := 46.0 + float((hv >> 6) % 34)
				_rect(parent, Vector2(lx, ly + 5.0), Vector2(lw + 7.0, 21.0), Color(0, 0, 0, 0.40), -92)
				_rect(parent, Vector2(lx, ly), Vector2(lw, 17.0), Color(0.20, 0.13, 0.11, 0.85), -92)
				_rect(parent, Vector2(lx, ly - 7.0), Vector2(lw, 3.0), Color(0.46, 0.31, 0.25, 0.55), -92)
		_:
			pass

## A plank run: a real surface laid ON the ground — a poured contact shadow,
## deck boards each with their own value, a lit end grain on the top-left side
## (the bible's light direction), and the gap between every pair of boards.
static func _boardwalk(parent: Node2D, from: Vector2, to: Vector2, col: Color) -> void:
	var d := to - from
	var ln := d.length()
	if ln < 40.0:
		return
	var ang := d.angle()
	var mid := (from + to) * 0.5
	var side := Vector2(-sin(ang), cos(ang))
	_rect(parent, mid + Vector2(0.0, 6.0), Vector2(ln + 16.0, 76.0), Color(0, 0, 0, 0.36), -92, ang)
	_rect(parent, mid, Vector2(ln + 8.0, 66.0), Color(col.r * 0.30, col.g * 0.26, col.b * 0.18, 0.94), -91, ang)
	var n := maxi(3, int(ln / 22.0))
	for i in n:
		var t := (float(i) + 0.5) / float(n)
		var bp := from + d * t
		var v := 0.80 + float(_cell_hash(int(bp.x), int(bp.y)) % 34) / 100.0
		_rect(parent, bp, Vector2(15.0, 62.0), Color(col.r * v, col.g * v * 0.9, col.b * v * 0.78, 0.95), -91, ang)
		_rect(parent, bp - side * 29.0, Vector2(15.0, 4.0), Color(col.r * 1.25, col.g * 1.12, col.b * 0.9, 0.55), -90, ang)
		_rect(parent, bp + Vector2(8.0, 0.0).rotated(ang), Vector2(2.0, 62.0), Color(0, 0, 0, 0.36), -90, ang)
	for k: float in [1.0, -1.0]:
		_rect(parent, mid + side * (k * 33.0), Vector2(ln + 8.0, 5.0), Color(0, 0, 0, 0.44), -90, ang)
		_rect(parent, mid + side * (k * 29.0), Vector2(ln + 8.0, 2.0), Color(col.r * 1.1, col.g, col.b * 0.8, 0.30), -90, ang)

## A trodden trail: bare earth worn through whatever grows here, with the stones
## kicked out to its edges. Deliberately NOT _path_segment — that one is a
## poured road with grate ticks and a kerb. This is the line people walk when
## nobody ever built them one, which is the only kind of road the Wildlands has.
static func _trail(parent: Node2D, pts: Array[Vector2], col: Color, wpx: float) -> void:
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var d := b - a
		var ln := d.length()
		if ln < 12.0:
			continue
		var ang := d.angle()
		var mid := (a + b) * 0.5
		var side := Vector2(-sin(ang), cos(ang))
		_rect(parent, mid, Vector2(ln + wpx * 0.5, wpx), Color(0.05, 0.04, 0.028, 0.50), -93, ang)
		_rect(parent, mid, Vector2(ln + wpx * 0.5, wpx - 14.0), Color(col.r, col.g, col.b, 0.22), -93, ang)
		var n := maxi(2, int(ln / 26.0))
		for j in n:
			var t := (float(j) + 0.5) / float(n)
			var tp := a + d * t
			for k: float in [1.0, -1.0]:
				var hv := _cell_hash(int(tp.x) + j, int(tp.y) + int(k) * 17)
				var sp := tp + side * (k * (wpx * 0.5 + float(hv % 9) - 4.0))
				var r := 4.0 + float((hv >> 5) % 6)
				_rect(parent, sp + Vector2(1.0, 2.0), Vector2(r + 3.0, r * 0.7 + 2.0), Color(0, 0, 0, 0.36), -92)
				_rect(parent, sp, Vector2(r + 2.0, r * 0.7), Color(0.30, 0.31, 0.28, 0.88), -91)
				_rect(parent, sp - Vector2(0.0, 1.0), Vector2(r, 2.0), Color(0.52, 0.54, 0.48, 0.72), -91)

## A hard-edged MATERIAL zone — a mat of moss, ballast, spoil or gravel with a
## ragged but genuinely DRAWN outline and a lit rim on its top edge. A soft
## _floor_patch cannot do this job: it has no edge, and an edge is precisely
## what "the ground has material zones" means to somebody looking at a frame.
static func _mat_zone(parent: Node2D, pos: Vector2, size: Vector2, col: Color, seed_v: int) -> void:
	for i in 9:
		var hv := _cell_hash(seed_v + i * 37, int(pos.x) + i * 13)
		var o := Vector2((float(hv % 101) - 50.0) * size.x / 190.0,
			(float((hv >> 7) % 61) - 30.0) * size.y / 150.0)
		var sz := size * (0.40 + float((hv >> 13) % 42) / 100.0)
		var rot := float(hv % 628) * 0.01
		_rect(parent, pos + o + Vector2(2.0, 3.0), sz, Color(0, 0, 0, 0.26), -93, rot)
		_rect(parent, pos + o, sz, Color(col.r, col.g, col.b, 0.55), -92, rot)
		_rect(parent, pos + o - Vector2(0.0, sz.y * 0.42), Vector2(sz.x * 0.9, 3.0),
			Color(col.r * 1.5, col.g * 1.4, col.b * 1.2, 0.32), -92, rot)

## Chevron trails painted from the plaza toward every portal this region owns.
## The player asked "what now, and WHERE" — this is the floor answering.
static func _paint_wayfinding(parent: Node2D, region_id: String, w: int, h: int, col: Color) -> void:
	# From the PLAZA, not the room's geometric centre: the plaza moved per region
	# and the trails have to leave from where the player actually lands, which is
	# also what stops all nine regions painting the same two horizontal runs.
	var center := _plaza_center(float(w), float(h))
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

## The drawn road network (round-4 rule 1). The walkway band (zone 1 in
## _build_floor_themed) already carries the east-west artery in its own
## material; this adds the perpendicular SPURS — one to every off-lane portal,
## one to every NPC, one to the focal set-piece — so the objective graph
## (spawn -> focal -> NPC -> portals) is literally paved onto the ground.
## Drawn after the mottle pass: navigation line-work must not be dimmed.
static func _paint_paths(parent: Node2D, region_id: String, theme: Dictionary, w: int, h: int, seed_v: int) -> void:
	var glow: Color = theme.get("glow", Color(0.7, 0.8, 0.9))
	var focal: Vector2 = theme.get("focal", Vector2.ZERO)
	# The artery is no longer a horizontal at h*0.5, so every spur has to leave
	# the band at the height the band actually has under ITS column.
	for pd in _region_portals(region_id):
		var pp: Vector2 = pd.pos
		var cy := _band_y(pp.x, float(w), float(h), seed_v)
		if absf(pp.y - cy) > 60.0:
			var stop_y := pp.y
			# When the focal set-piece stands ON this column between the band and
			# the door, stop the road at the set-piece instead of paving under
			# it — the piece and the portal's own gate pool carry the line the
			# rest of the way. (The vault used to be the case that needed this,
			# with its pedestal at y 244 directly under a north door at x 640;
			# that door has since moved off the pedestal's column.)
			if absf(pp.x - focal.x) < 80.0 and (focal.y - cy) * (pp.y - cy) > 0.0 \
					and absf(focal.y - cy) < absf(pp.y - cy):
				stop_y = focal.y
			_spur(parent, pp.x, stop_y, cy, glow, 96.0, _band_half(pp.x, float(w), seed_v))
	for npc_data in _region_npcs(region_id):
		var np: Vector2 = npc_data.pos
		_spur(parent, np.x, np.y, _band_y(np.x, float(w), float(h), seed_v), glow, 90.0, _band_half(np.x, float(w), seed_v))
	if focal != Vector2.ZERO:
		# Skip the focal spur when an NPC or portal spur already runs down the
		# same column (the wildlands camp, the corporate stage, the vault's
		# north door) — two overlaid paths read as a rendering mistake.
		var dup := false
		for npc_data in _region_npcs(region_id):
			var np2: Vector2 = npc_data.pos
			if absf(np2.x - focal.x) < 80.0:
				dup = true
		for pd2 in _region_portals(region_id):
			var pp2: Vector2 = pd2.pos
			if absf(pp2.y - _band_y(pp2.x, float(w), float(h), seed_v)) > 60.0 and absf(pp2.x - focal.x) < 80.0:
				dup = true
		if not dup:
			_spur(parent, focal.x, focal.y, _band_y(focal.x, float(w), float(h), seed_v), glow, 96.0, _band_half(focal.x, float(w), seed_v))

## One vertical branch from the artery band edge toward a destination, stopping
## a respectful margin short of it. Degenerate spurs (target close to the band)
## are skipped — the band itself already delivers the player there.
static func _spur(parent: Node2D, x: float, target_y: float, cy: float, col: Color, wpx: float, band: float) -> void:
	var k := signf(target_y - cy)
	if k == 0.0:
		return
	# Start ON the (now wobbling) band edge rather than at a fixed 92px, or the
	# spur either floats off the artery or overshoots into it.
	var a := Vector2(x, cy + k * (band - 4.0))
	var b := Vector2(x, target_y - k * 96.0)
	if (b.y - a.y) * k < 40.0:
		return
	_path_segment(parent, a, b, col, wpx)

## Axis-aligned paved segment: dark poured underlay (cuts the ground noise), a
## lighter deck, crisp region-tinted edge lines, and grate ticks at a 48px
## rhythm the 64px floor lattice cannot sync with. Consumes the round-4
## path_tile / path_tile_edge textures when the art agents have produced them;
## the procedural deck underneath is the graceful fallback either way.
static func _path_segment(parent: Node2D, a: Vector2, b: Vector2, col: Color, wpx: float = 90.0) -> void:
	var d := b - a
	var seg_len := d.length()
	if seg_len < 40.0:
		return
	var horiz := absf(d.x) > absf(d.y)
	var mid := (a + b) * 0.5
	var dirn := d / seg_len
	var size := Vector2(seg_len + wpx * 0.6, wpx) if horiz else Vector2(wpx, seg_len + wpx * 0.6)
	# Poured underlay: its own material, not another tint on the wash.
	_rect(parent, mid, size, Color(0.016, 0.02, 0.04, 0.42), -93)
	# Deck: one value step up from the field, cool maintenance-grey everywhere
	# so the region hue stays with the region and the road reads as ROAD.
	_rect(parent, mid, size - Vector2(14, 14), Color(0.72, 0.78, 0.9, 0.085), -93)
	if ResourceLoader.exists(GEN + "path_tile.png"):
		for i in int(seg_len / 64.0) + 1:
			_put(parent, "path_tile", a + dirn * minf(float(i) * 64.0, seg_len), -93, 1.0, Color(1, 1, 1, 0.92))
	# Crisp edges: the strongest "walk here" cue a static frame can give.
	var side := Vector2(0, 1) if horiz else Vector2(1, 0)
	var esz := Vector2(size.x, 2.0) if horiz else Vector2(2.0, size.y)
	var half := wpx * 0.5
	for k: float in [1.0, -1.0]:
		var ep := mid + side * (k * half)
		_rect(parent, ep, esz, Color(0, 0, 0, 0.38), -93)
		_rect(parent, ep - side * (k * 2.0), esz, Color(col.r, col.g, col.b, 0.16), -93)
	if ResourceLoader.exists(GEN + "path_tile_edge.png"):
		for i in int(seg_len / 64.0) + 1:
			var pp := a + dirn * minf(float(i) * 64.0, seg_len)
			for k: float in [1.0, -1.0]:
				var rot := (PI if k > 0.0 else 0.0) if horiz else (PI * 0.5 if k > 0.0 else -PI * 0.5)
				_put(parent, "path_tile_edge", pp + side * (k * half), -93, 1.0, Color(1, 1, 1, 0.9), rot)
	# Grate ticks across the deck — the walkway's own surface texture.
	for i in int(seg_len / 48.0):
		var tp := a + dirn * (24.0 + float(i) * 48.0)
		_rect(parent, tp, Vector2(3.0, wpx - 18.0) if horiz else Vector2(wpx - 18.0, 3.0), Color(0, 0, 0, 0.16), -93)
	# Broken shoulder: chips of deck shed along both edges and a ragged terminus
	# at the far end. Without these a spur stops mid-floor in a perfect straight
	# line, which is the same defect as the zone rectangles one scale down.
	var hb := int(a.x * 3.0 + a.y * 7.0 + b.y * 11.0) & 0x7FFFFFFF
	for i in 12:
		var hh := _cell_hash(hb + i, int(seg_len))
		var t := float(hh % 1000) / 1000.0
		var sgn := 1.0 if (hh >> 11) % 2 == 0 else -1.0
		var cp := a + dirn * (t * seg_len) + side * (sgn * (half + float((hh >> 3) % 9) - 3.0))
		_rect(parent, cp, Vector2(float((hh >> 6) % 13) + 5.0, 4.0), Color(0, 0, 0, 0.30), -92, float(hh % 628) * 0.01)
	for i in 5:
		var he := _cell_hash(hb + 991, i)
		var ep2 := b + dirn * float((he % 26)) + side * (float(he % 61) - 30.0) * (wpx / 90.0)
		_rect(parent, ep2, Vector2(float((he >> 7) % 17) + 8.0, 5.0), Color(0.72, 0.78, 0.9, 0.05), -93, float(he % 314) * 0.01)

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
	var seed_v := _region_seed(region_id)
	for i in 9:
		var name_i: String = str(pool[rng.randi() % pool.size()])
		var pos := Vector2(rng.randf_range(150, float(w) - 150), rng.randf_range(170, float(h) - 120))
		# Keep the big decals off the walkway band: a maintained deck with a
		# 0.7-alpha crack across it stops reading as maintained (rule 1: noise
		# stays OFF the structure).
		if absf(pos.y - _band_y(pos.x, float(w), float(h), seed_v)) < _band_half(pos.x, float(w), seed_v) - 6.0:
			continue
		var spr := _put(parent, name_i, pos, -91, rng.randf_range(0.75, 1.7),
			Color(1, 1, 1, rng.randf_range(0.35, 0.72)), rng.randf_range(-PI, PI))
		if spr == null:
			return  # generator has not been run; nothing to scatter

static func _floor_litter(parent: Node2D, theme: Dictionary, w: int, h: int, region_id: String = "") -> void:
	_floor_decals(parent, region_id, w, h)
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var seed_v := _region_seed(region_id)
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
		# Thin the scatter on the walkway band — most of it, not all: a swept
		# deck with the odd bolt reads maintained; an untouched one reads fake.
		if absf(dp.y - _band_y(dp.x, float(w), float(h), seed_v)) < _band_half(dp.x, float(w), seed_v) - 10.0 and rng.randf() < 0.65:
			continue
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

## Which horizon a region owns. Identity in one second: you should be able to
## name the district from the shape of its far edge with every label switched
## off. (VISUAL_BIBLE per-region palettes; the shapes are drawn from the
## region's own fiction, not a generic skyline.)
static func _backdrop_kind(region_id: String) -> String:
	match region_id:
		"dependency_district": return "stacks"
		"stackoverflow_ruins": return "strata"
		"api_bazaar": return "roofline"
		"cloud_district": return "nave"
		"open_source_wildlands": return "canopy"
		"corporate_enterprise": return "skyline"
		"gpu_mines": return "strata"
		"production": return "skyline"
		"token_vault": return "nave"
		_: return "skyline"

## The FAR plane. Round 4 gave the rooms a midground; the top of every frame
## still cut straight from wall to floor, so the world had two depths and read
## flat. This is the layer behind that one: a region-specific horizon drawn
## tiny and nearly black under a haze gradient, plus a second, slightly nearer
## copy at a step more value. With the existing midground bands and the
## foreground trays, a region now reads back-to-front across five planes.
static func _build_backdrop(parent: Node2D, region_id: String, theme: Dictionary, w: int, h: int) -> void:
	var z := Node2D.new()
	z.name = "Backdrop"
	parent.add_child(z)
	var glow: Color = theme.get("glow", Color(0.6, 0.7, 0.9))
	var accent: Color = theme.get("accent", glow)
	var kind := _backdrop_kind(region_id)
	var seed_v := _region_seed(region_id)
	# Sky/void behind everything so the horizon has something to be a shape
	# against instead of being a shape against the wall. The lower edge is a
	# RAMP, not a cut: one 0.92-alpha rect ending on a tile row would draw a
	# dead-straight full-width line across the floor at y 169 — the exact defect
	# this whole pass exists to remove, one plane further back.
	_rect(z, Vector2(w * 0.5, 88.0), Vector2(float(w) + 40.0, 98.0), Color(0.012, 0.014, 0.03, 0.92), -59)
	for i in 7:
		var fy := 141.0 + float(i) * 9.0
		_rect(z, Vector2(w * 0.5, fy), Vector2(float(w) + 40.0, 10.0),
			Color(0.012, 0.014, 0.03, 0.80 - float(i) * 0.11), -59)
	_rect(z, Vector2(w * 0.5, 150.0), Vector2(float(w) + 40.0, 46.0), Color(glow.r * 0.3, glow.g * 0.3, glow.b * 0.36, 0.10), -58)
	# Two planes: far (smaller, darker, denser) then near (taller, one value up).
	# Every shape in this vocabulary is <= 110 units tall at sc 1.0, and the
	# scales below are chosen so nothing reaches y 60 — the horizon must never
	# climb over the top wall it is supposed to be standing behind.
	for plane in 2:
		var base_y := 126.0 if plane == 0 else 152.0
		var sc_max := 0.60 if plane == 0 else 0.83
		var v := 0.055 + float(plane) * 0.055
		var n := 22 if plane == 0 else 13
		var zi := -57 + plane * 2
		for i in n:
			var hv := _cell_hash(i * 31 + plane * 977, seed_v)
			var px := 40.0 + float(i) * (float(w) - 80.0) / float(n - 1) + float(hv % 29) - 14.0
			var sc := sc_max * (0.55 + float((hv >> 5) % 46) / 100.0)
			_backdrop_shape(z, kind, Vector2(px, base_y), sc, Color(v, v, v * 1.22, 0.95), zi, hv)
			# One lit window / vent / bioluminescent node in every third shape.
			if (hv >> 13) % 3 == 0:
				var lc: Color = glow if (hv >> 17) % 2 == 0 else accent
				_glow_rect(z, Vector2(px + float((hv >> 19) % 17) - 8.0, base_y - 22.0 * sc),
					Vector2(3, 3), Color(lc.r, lc.g, lc.b, 0.32 + 0.16 * float(plane)), zi + 1)
	# Aerial perspective: the haze that makes the far plane read as FAR rather
	# than as small props somebody left by the wall.
	_rect(z, Vector2(w * 0.5, 126.0), Vector2(float(w) - 20.0, 128.0), Color(glow.r * 0.4, glow.g * 0.4, glow.b * 0.46, 0.09), -52)

## One silhouette from the region's horizon vocabulary, drawn in rects so it
## costs nothing and can never depend on a texture the generator has not made.
static func _backdrop_shape(parent: Node2D, kind: String, pos: Vector2, sc: float, col: Color, z: int, hv: int) -> void:
	match kind:
		"skyline":  # towers with setbacks, an antenna on the tall ones
			var th := (32.0 + float(hv % 40)) * sc
			var tw := (22.0 + float((hv >> 7) % 20)) * sc
			_rect(parent, pos + Vector2(0, -th * 0.5), Vector2(tw, th), col, z)
			_rect(parent, pos + Vector2(0, -th - 8.0 * sc), Vector2(tw * 0.55, 18.0 * sc), col, z)
			if hv % 3 == 0:
				_rect(parent, pos + Vector2(0, -th - 26.0 * sc), Vector2(2.0, 20.0 * sc), col, z)
		"stacks":  # crate/pallet ziggurats, the district's only architecture
			for s in 3:
				var bw := (54.0 - float(s) * 14.0) * sc
				_rect(parent, pos + Vector2(float((hv >> (s * 3)) % 9) - 4.0, -float(s) * 17.0 * sc - 8.0 * sc),
					Vector2(bw, 16.0 * sc), col, z)
		"roofline":  # market awnings and tent poles, pitched, never level
			var rw := (58.0 + float(hv % 34)) * sc
			_rect(parent, pos + Vector2(0, -18.0 * sc), Vector2(rw, 13.0 * sc), col, z, (float(hv % 21) - 10.0) * 0.012)
			_rect(parent, pos + Vector2(-rw * 0.4, -6.0 * sc), Vector2(3.0 * sc, 26.0 * sc), col, z)
			_rect(parent, pos + Vector2(rw * 0.4, -6.0 * sc), Vector2(3.0 * sc, 26.0 * sc), col, z)
		"nave":  # rack columns under an arcade — a cathedral of other people's computers
			var ch := (44.0 + float(hv % 30)) * sc
			_rect(parent, pos + Vector2(0, -ch * 0.5), Vector2(26.0 * sc, ch), col, z)
			for s in 4:
				_rect(parent, pos + Vector2(0, -ch * (0.16 + float(s) * 0.21)), Vector2(30.0 * sc, 2.0), col, z)
			_rect(parent, pos + Vector2(0, -ch - 5.0 * sc), Vector2(36.0 * sc, 9.0 * sc), col, z)
		"canopy":  # trunks under overlapping crowns
			_rect(parent, pos + Vector2(0, -24.0 * sc), Vector2(7.0 * sc, 54.0 * sc), col, z)
			for s in 3:
				var a := (float(s) - 1.0) * 22.0 * sc
				_floor_patch(parent, pos + Vector2(a, -58.0 * sc - float((hv >> (s * 4)) % 13) * sc),
					(58.0 + float((hv >> s) % 30)) * sc, Color(col.r, col.g, col.b), 0.9, z)
		_:  # "strata" — cut rock benches, the mine face and the ruin cliff alike
			for s in 3:
				var sw := (72.0 + float((hv >> (s * 5)) % 46)) * sc
				_rect(parent, pos + Vector2(float((hv >> (s * 2)) % 19) - 9.0, -float(s) * 15.0 * sc),
					Vector2(sw, 15.0 * sc), col, z, (float(hv % 17) - 8.0) * 0.006)

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
	# TRUE foreground occluders: two full-height stanchions just inside the side
	# walls that the player walks BEHIND. They cost eight rects, sit over the
	# dead 40px strip against the wall where nothing is ever placed, and are the
	# cheapest possible proof that this room has a near plane — the frames so far
	# had a background and a play field and nothing in front of the camera.
	# z 1000-1002, not 545: everything alive in this world y-sorts by
	# z_index = int(y), so a 545 "near plane" only stood in front of the bottom
	# half of the room and behind the player for the top half — a foreground
	# occluder that occludes half the time reads as a rendering bug. 1000 clears
	# the tallest possible y (the bottom wall is at 944) and still sits under
	# world sign plates (1150), damage text and the HUD.
	for k: float in [0.0, 1.0]:
		var sx := 56.0 + k * (float(w) - 112.0)
		# 0.72, not opaque: the player CAN stand behind one of these, and a
		# silhouette you cannot find is a readability bug, not depth. Lowered
		# from 0.78 now that the column occludes over the WHOLE room.
		_rect(z, Vector2(sx, h * 0.5), Vector2(28.0, float(h) + 20.0), Color(0.010, 0.012, 0.026, 0.72), 1000)
		_rect(z, Vector2(sx + (8.0 if k < 0.5 else -8.0), h * 0.5), Vector2(3.0, float(h) + 20.0), Color(glow.r, glow.g, glow.b, 0.13), 1001)
		for i in 6:
			var by := 90.0 + float(i) * (float(h) - 180.0) / 5.0
			_rect(z, Vector2(sx, by), Vector2(42.0, 13.0), Color(0.008, 0.009, 0.02, 0.78), 1002)
	# Slack cable and hanging growth crossing the near plane at three points, so
	# the top of the frame is looked THROUGH rather than merely capped.
	for i in 4:
		var hx := 250.0 + float(i) * (float(w) - 500.0) / 3.0
		var drop := 140.0 + float(_cell_hash(i, 7717) % 90)
		_rect(z, Vector2(hx, drop * 0.5 + 40.0), Vector2(4.0, drop), Color(0.010, 0.012, 0.024, 0.9), 508)
		_rect(z, Vector2(hx, drop + 40.0), Vector2(15.0, 15.0), Color(0.014, 0.016, 0.03, 0.92), 509)
		_glow_rect(z, Vector2(hx, drop + 40.0), Vector2(5, 5), Color(glow.r, glow.g, glow.b, 0.35), 510)
	# Bottom sill: the near edge of the room, framing the frame. Now with a
	# silhouetted near ledge on it — the last thing between camera and world.
	_rect(z, Vector2(w * 0.5, h - 4.0), Vector2(w + 40.0, 26.0), Color(0.015, 0.018, 0.035, 0.92), 600)
	# Kept under 29px tall on purpose: the lowest thing the game ever places is a
	# staged enemy at y 894, and a near ledge that eats an enemy is a bug.
	for i in 9:
		var lx := 120.0 + float(i) * (float(w) - 240.0) / 8.0
		var lh := 14.0 + float(_cell_hash(i, 3391) % 16)
		_rect(z, Vector2(lx, float(h) - 5.0 - lh * 0.5), Vector2(46.0 + float(_cell_hash(i, 11) % 30), lh), Color(0.012, 0.014, 0.028, 0.94), 599)
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
		# Silhouette support (round-4 rule 2): every themed structure gets a
		# faint backing halo so it reads as a shape against the ground, not a
		# smudge the caption has to explain.
		_backglow(z, sp + Vector2(0, -6.0 * sc), 140.0 * sc, glow, 0.09)
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
	# Keep the clutter off the arrival plaza AND off the artery. Both moved per
	# region this round, so a fixed "270px from the room's centre, 110px either
	# side of h*0.5" would now drop crates on the walkway in half the rooms.
	var center := Vector2(w * 0.5, h * 0.5)
	for i in 11:
		var p := Vector2(rng.randf_range(100, w - 100), rng.randf_range(140, h - 90))
		if p.distance_to(center) < 240.0:
			continue
		if _plaza_field(p, float(w), float(h), _layout_seed) < 40.0:
			continue
		if absf(p.y - _band_y(p.x, float(w), float(h), _layout_seed)) < 110.0:
			continue
		var sc := rng.randf_range(0.3, 0.48)
		var shade := rng.randf_range(-0.12, 0.08)
		var m := Color(clampf(wall_c.r + shade, 0, 1), clampf(wall_c.g + shade, 0, 1), clampf(wall_c.b + shade, 0, 1))
		_prop(z, str(vocab[rng.randi() % vocab.size()]), p, sc, m, rng.randf_range(-0.12, 0.12), 0.8)

## Ground-level signature clutter. The round-4 verdict was that regions read as
## "a floor with lit props on it"; what a place actually has is a hundred small
## things nobody placed on purpose, all of them from the same world. These are
## rect motifs — no texture dependency, ~4 rects each — scattered across the
## field and perimeter, plus two oversized landmark silhouettes so the eye has a
## scale ladder to climb (a few big things, many small ones).
static func _build_signature(parent: Node2D, region_id: String, theme: Dictionary, w: int, h: int) -> void:
	var z := Node2D.new()
	z.name = "Signature"
	parent.add_child(z)
	var glow: Color = theme.get("glow", Color(0.6, 0.7, 0.9))
	var accent: Color = theme.get("accent", glow)
	var kind := _signature_kind(region_id)
	var seed_v := _region_seed(region_id)
	for i in 46:
		var hv := _cell_hash(i * 53 + 101, seed_v + 7)
		var p := Vector2(
			96.0 + float(hv % (w - 192)),
			132.0 + float((hv >> 9) % (h - 232)))
		# Keep the artery swept: a maintained deck covered in the region's own
		# debris stops reading as maintained (the same law as the litter skips).
		if absf(p.y - _band_y(p.x, float(w), float(h), seed_v)) < _band_half(p.x, float(w), seed_v) + 14.0 and (hv >> 21) % 4 != 0:
			continue
		if _in_cover(p):
			continue
		_signature_mark(z, kind, p, 0.7 + float((hv >> 5) % 70) / 100.0, glow, accent, hv)
	# Two landmark-scale silhouettes in the quadrants the composition leaves
	# empty. Same vocabulary as the set-pieces, three times the size.
	var vocab := _vocab(theme)
	if vocab.is_empty():
		return
	# Edges and corners, and only the ones this region has actually left empty.
	# A 1.45x silhouette dropped on top of anything the player NEEDS would hide
	# it: props carry a y-sorted z_index, so a landmark out-draws an enemy, and
	# it will happily stand in front of the one quest-giver in the room. The
	# bottom-right corner in particular is where eight of the nine regions put
	# their NPC, so the keep-outs below are not optional.
	var spots: Array[Vector2] = [
		Vector2(126.0, float(h) - 190.0), Vector2(float(w) - 126.0, 214.0),
		Vector2(126.0, 214.0), Vector2(float(w) - 126.0, float(h) - 190.0),
		Vector2(350.0, float(h) - 76.0), Vector2(float(w) - 350.0, float(h) - 76.0),
		Vector2(350.0, 200.0), Vector2(float(w) - 350.0, 200.0),
	]
	var posts := _region_enemy_posts(region_id)
	var focal: Vector2 = theme.get("focal", Vector2.ZERO)
	var placed := 0
	for i in spots.size():
		if placed >= 2:
			break
		var lp: Vector2 = spots[i]
		if _in_cover(lp):
			continue
		var clear := true
		for pp: Vector2 in posts:
			if lp.distance_to(pp) < 170.0:
				clear = false
		for nd in _region_npcs(region_id):
			var np: Vector2 = nd.pos
			if lp.distance_to(np) < 230.0:
				clear = false
		for pd in _region_portals(region_id):
			var pv: Vector2 = pd.pos
			if lp.distance_to(pv) < 210.0:
				clear = false
		if focal != Vector2.ZERO and lp.distance_to(focal) < 210.0:
			clear = false
		for sd in theme.get("structs", []):
			var sv: Vector2 = sd.p
			if lp.distance_to(sv) < 150.0:
				clear = false
		if not clear:
			continue
		var hv2 := _cell_hash(i * 617, seed_v + 29)
		_backglow(z, lp + Vector2(0, -30), 300.0, glow, 0.09)
		_prop(z, str(vocab[hv2 % vocab.size()]), lp, 1.45 + float(hv2 % 25) / 100.0,
			Color(0.30, 0.32, 0.38), (float(hv2 % 13) - 6.0) * 0.012)
		_light_pool(z, lp + Vector2(0, 40), 250.0, accent, 0.12)
		placed += 1

static func _signature_kind(region_id: String) -> String:
	match region_id:
		"dependency_district": return "pallets"
		"stackoverflow_ruins": return "rubble"
		"api_bazaar": return "mats"
		"cloud_district": return "ducts"
		"open_source_wildlands": return "growth"
		"corporate_enterprise": return "carpet"
		"gpu_mines": return "spall"
		"production": return "hazard"
		"token_vault": return "spill"
		_: return "rubble"

## One signature mark. Everything here is flat floor dressing at z -92..-90 — it
## must never compete with a prop silhouette, only with the emptiness.
##
## ROUND-6 LAW, learned from region_production.png: nothing in a frame may read
## as a missing texture, a debug gizmo or a stray primitive. So every variant
## below now obeys three rules. (1) It sits on a wear bed, so it is ON the floor
## rather than drawn over it. (2) It carries at least three value steps of its
## own material, lit from the top-left like everything else in this game.
## (3) Anything emissive gets a DARK GROOVE behind it — a glow with no cut under
## it is a bright line lying on the ground, which is precisely how twenty-five
## flat red crosses came to read as "the art failed to load".
static func _signature_mark(parent: Node2D, kind: String, p: Vector2, sc: float, glow: Color, accent: Color, hv: int) -> void:
	var rot := float(hv % 628) * 0.01
	# The wear bed. Cheap, and it is the single thing that separates a mark
	# somebody made from a shape somebody forgot to delete.
	_floor_patch(parent, p + Vector2(0.0, 3.0 * sc), 66.0 * sc, Color(0.012, 0.013, 0.026), 0.26, -92)
	match kind:
		"pallets":  # slatted pallets and the tarps thrown over them
			_rect(parent, p, Vector2(46.0 * sc, 32.0 * sc), Color(0.16, 0.13, 0.09, 0.5), -91, rot)
			for s in 3:
				_rect(parent, p + Vector2(0, (float(s) - 1.0) * 10.0 * sc).rotated(rot), Vector2(46.0 * sc, 3.0), Color(0.44, 0.34, 0.2, 0.45), -90, rot)
			if hv % 5 == 0:
				_rect(parent, p + Vector2(6.0, -4.0), Vector2(40.0 * sc, 22.0 * sc), Color(accent.r * 0.5, accent.g * 0.5, accent.b * 0.5, 0.34), -90, rot + 0.2)
		"rubble":  # shattered answer-stone, weathered into gravel
			for s in 5:
				var o := Vector2(float((hv >> (s * 3)) % 41) - 20.0, float((hv >> (s * 2 + 1)) % 29) - 14.0) * sc
				_rect(parent, p + o, Vector2(float((hv >> s) % 11) * sc + 4.0, 5.0 * sc), Color(0.30, 0.26, 0.19, 0.5), -91, rot + float(s))
		"mats":  # market rugs and the stakes their price tags are nailed to
			_rect(parent, p, Vector2(62.0 * sc, 40.0 * sc), Color(glow.r * 0.28, glow.g * 0.22, glow.b * 0.3, 0.42), -91, rot)
			_rect(parent, p, Vector2(56.0 * sc, 34.0 * sc), Color(accent.r * 0.3, accent.g * 0.26, accent.b * 0.2, 0.36), -90, rot)
			if hv % 4 == 0:
				_rect(parent, p + Vector2(26.0 * sc, -10.0), Vector2(3, 24.0 * sc), Color(0.06, 0.05, 0.07, 0.85), -90)
				_glow_rect(parent, p + Vector2(26.0 * sc, -22.0 * sc), Vector2(10, 6), Color(accent.r, accent.g, accent.b, 0.5), -89)
		"ducts":  # floor ducting with a directional chevron painted on it
			_rect(parent, p, Vector2(76.0 * sc, 22.0 * sc), Color(0.16, 0.2, 0.26, 0.46), -91, rot)
			for s in 4:
				_rect(parent, p + Vector2((float(s) - 1.5) * 18.0 * sc, 0.0).rotated(rot), Vector2(3.0, 22.0 * sc), Color(0, 0, 0, 0.3), -90, rot)
			if hv % 3 == 0:
				_chevron(parent, p, Color(glow.r, glow.g, glow.b, 0.22), rot, -90)
		"growth":  # tufts, log rounds, moss taking the floor back
			_floor_patch(parent, p, 60.0 * sc, Color(accent.r * 0.5, accent.g * 0.6, accent.b * 0.45), 0.30, -91)
			for s in 5:
				var a := rot + float(s) * 1.2
				_rect(parent, p + Vector2(cos(a), sin(a)) * 14.0 * sc, Vector2(3.0, 17.0 * sc), Color(glow.r * 0.42, glow.g * 0.55, glow.b * 0.4, 0.6), -90, a * 0.3)
		"carpet":  # carpet tiles, cable covers, and tape where a desk used to be
			_rect(parent, p, Vector2(64.0 * sc, 64.0 * sc), Color(0.2, 0.22, 0.28, 0.34), -91)
			_rect(parent, p, Vector2(60.0 * sc, 60.0 * sc), Color(0.24, 0.26, 0.33, 0.24), -90)
			if hv % 4 == 0:
				_rect(parent, p, Vector2(86.0 * sc, 9.0), Color(accent.r * 0.7, accent.g * 0.65, accent.b * 0.3, 0.35), -90, rot)
		"spall":  # rock spall, cable bundles, and a vent nobody vents
			for s in 4:
				var o2 := Vector2(float((hv >> (s * 3)) % 45) - 22.0, float((hv >> (s + 2)) % 31) - 15.0) * sc
				_rect(parent, p + o2, Vector2(float((hv >> s) % 13) * sc + 5.0, 6.0 * sc), Color(0.24, 0.15, 0.12, 0.55), -91, rot + float(s) * 0.9)
			if hv % 3 == 0:
				# A fissure with heat still in it. The round-5 version was ONE
				# additive bar and nothing else, which is where "~15 bright 1px red
				# lines radiating at random angles" in region_gpu_mines.png came
				# from. The cut goes in first, the crust catches the light, and the
				# glow lives INSIDE the cut.
				_floor_patch(parent, p, 58.0 * sc, Color(0.05, 0.016, 0.008), 0.34, -92)
				_rect(parent, p, Vector2(34.0 * sc, 9.0), Color(0, 0, 0, 0.62), -91, rot)
				_rect(parent, p - Vector2(0.0, 3.0), Vector2(32.0 * sc, 2.0), Color(0.42, 0.25, 0.18, 0.55), -90, rot)
				_glow_rect(parent, p, Vector2(26.0 * sc, 3.0), Color(glow.r, glow.g * 0.5, glow.b * 0.2, 0.30), -90, rot)
				_glow_rect(parent, p, Vector2(9.0 * sc, 2.0), Color(1.0, 0.74, 0.46, 0.42), -90, rot)
		"hazard":  # incident dressing: cordoned ground, knocked cones, scorch
			# Was: two flat crossed rects, 25 of them, no shading, no shadow, no
			# glow — an X on the floor, which at game zoom is the universal symbol
			# for a texture that did not load. Three authored variants instead, each
			# of which is an OBJECT with a reason to be lying there.
			match hv % 3:
				0:  # ground taped off around a burn, pinned at two corners
					var hw := 34.0 * sc
					_floor_patch(parent, p, 92.0 * sc, Color(0.02, 0.012, 0.012), 0.48, -92)
					_floor_patch(parent, p, 40.0 * sc, Color(0.0, 0.0, 0.0), 0.42, -91)
					for e in 4:
						var ea := rot + TAU * float(e) / 4.0
						var en := Vector2(cos(ea), sin(ea))
						var et := Vector2(-en.y, en.x)
						var em := p + en * hw
						var eang := et.angle()
						# The tape's own contact shadow, then its body, then the
						# diagonal stripes that make it TAPE and not a drawn line,
						# then the lit top edge (light source is top-left, always).
						_rect(parent, em + Vector2(0.0, 3.0), Vector2(hw * 2.1, 9.0), Color(0, 0, 0, 0.44), -91, eang)
						_rect(parent, em, Vector2(hw * 2.1, 8.0), Color(accent.r * 0.66, accent.g * 0.52, accent.b * 0.14, 0.80), -90, eang)
						for st in 4:
							_rect(parent, em + et * ((float(st) - 1.5) * hw * 0.52), Vector2(7.0, 9.0), Color(0.05, 0.04, 0.05, 0.88), -90, eang + 0.55)
						_rect(parent, em - Vector2(0.0, 3.0), Vector2(hw * 2.1, 2.0), Color(minf(accent.r * 1.5, 1.0), accent.g, accent.b * 0.3, 0.5), -90, eang)
						if e % 2 == 0:
							var pin := p + (en + et) * hw
							_drop_shadow(parent, pin + Vector2(0.0, 8.0), 24.0, _depth(pin.y, 8.0) - 1, 0.34)
							_rect(parent, pin, Vector2(6, 15), Color(0.06, 0.05, 0.05, 0.96), _depth(pin.y, 8.0))
							_glow_rect(parent, pin + Vector2(0.0, -7.0), Vector2(4, 3), Color(glow.r, glow.g, glow.b, 0.7), _depth(pin.y, 9.0))
				1:  # a cone somebody knocked over on the way past and left there
					var cd := Vector2(cos(rot), sin(rot))
					_drop_shadow(parent, p + Vector2(5.0, 8.0) * sc, 54.0 * sc, -91, 0.36)
					_rect(parent, p, Vector2(46.0 * sc, 22.0 * sc), Color(0.09, 0.045, 0.05, 0.94), -90, rot)
					_rect(parent, p - Vector2(0.0, 2.0 * sc), Vector2(43.0 * sc, 16.0 * sc), Color(accent.r * 0.74, accent.g * 0.34, accent.b * 0.16, 0.95), -90, rot)
					_rect(parent, p - Vector2(0.0, 6.0 * sc), Vector2(39.0 * sc, 5.0 * sc), Color(minf(accent.r * 1.3, 1.0), accent.g * 0.62, accent.b * 0.3, 0.9), -90, rot)
					# The retro-reflective band is the only part allowed to glow.
					_glow_rect(parent, p + cd * 5.0 * sc, Vector2(7.0 * sc, 18.0 * sc), Color(0.9, 0.9, 1.0, 0.28), -90, rot)
					_rect(parent, p - cd * 21.0 * sc, Vector2(15.0 * sc, 25.0 * sc), Color(0.07, 0.05, 0.06, 0.96), -90, rot)
				_:  # the burn itself, still cooling, with the cracks it opened
					_floor_patch(parent, p, 88.0 * sc, Color(0.02, 0.012, 0.012), 0.55, -92)
					_floor_patch(parent, p, 44.0 * sc, Color(0.0, 0.0, 0.0), 0.5, -91)
					# FIVE cracks at jittered bearings and jittered lengths, not four
					# at 92.8 degrees. Four evenly spaced spokes of equal length IS
					# a cross — the exact silhouette this whole variant exists to
					# stop the production floor drawing twenty-five times.
					for cq in 5:
						var cj := _cell_hash(hv + cq * 61, 4409)
						var ca := rot + float(cq) * 1.257 + (float(cj % 61) - 30.0) * 0.011
						var cl := (20.0 + float((cj >> 7) % 17)) * sc
						var cp2 := p + Vector2(cos(ca), sin(ca)) * (cl * 0.56)
						_rect(parent, cp2, Vector2(cl, 5.0), Color(0, 0, 0, 0.58), -91, ca)
						_rect(parent, cp2 - Vector2(0.0, 1.5), Vector2(cl * 0.88, 2.0), Color(glow.r * 0.85, glow.g * 0.34, glow.b * 0.2, 0.34), -90, ca)
					_glow_rect(parent, p, Vector2(10.0 * sc, 6.0 * sc), Color(minf(glow.r * 1.3, 1.0), glow.g * 0.4, glow.b * 0.25, 0.45), -90)
		_:  # "spill" — loose reserves nobody has counted, and the rope around them
			for s in 6:
				var o3 := Vector2(float((hv >> (s * 3)) % 51) - 25.0, float((hv >> (s + 1)) % 33) - 16.0) * sc
				# Coin, then its shadow, then its hot edge: a bare additive dot is a
				# particle that got stuck, not a token lying on a vault floor.
				_rect(parent, p + o3 + Vector2(1.0, 2.0), Vector2(8.0 * sc, 5.0 * sc), Color(0, 0, 0, 0.40), -91)
				_rect(parent, p + o3, Vector2(7.0 * sc, 4.5 * sc), Color(accent.r * 0.5, accent.g * 0.44, accent.b * 0.24, 0.85), -90)
				_glow_rect(parent, p + o3 - Vector2(0.0, 1.0), Vector2(6.0 * sc, 2.0 * sc), Color(glow.r, glow.g, glow.b, 0.34), -90)
			if hv % 5 == 0:
				# A cordon with a stanchion at each end. Round 5 drew this as a bare
				# 84px accent line lying on the floor with nothing holding it up —
				# one of the "two perfectly straight cross-screen lines" the vault
				# frame was pulled up on.
				var rd := Vector2(cos(rot), sin(rot)) * 42.0 * sc
				_rect(parent, p + Vector2(0.0, 4.0), Vector2(84.0 * sc, 5.0), Color(0, 0, 0, 0.38), -91, rot)
				_rect(parent, p, Vector2(84.0 * sc, 4.0), Color(accent.r * 0.55, accent.g * 0.5, accent.b * 0.62, 0.7), -90, rot)
				_rect(parent, p - Vector2(0.0, 1.5), Vector2(80.0 * sc, 1.5), Color(minf(accent.r * 1.3, 1.0), accent.g, accent.b, 0.4), -90, rot)
				for k: float in [1.0, -1.0]:
					var sp2 := p + rd * k
					_drop_shadow(parent, sp2 + Vector2(0.0, 9.0), 26.0, _depth(sp2.y, 9.0) - 1, 0.34)
					_rect(parent, sp2, Vector2(7, 18), Color(0.06, 0.055, 0.05, 0.96), _depth(sp2.y, 9.0))
					_glow_rect(parent, sp2 + Vector2(0.0, -9.0), Vector2(5, 3), Color(glow.r, glow.g, glow.b, 0.75), _depth(sp2.y, 10.0))

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
		# together with the struct + sign flickers). 0.62, down from 0.75:
		# anchors are mid-ground, one step below the focal (round-4 rule 3).
		_lamp(z, lp, glow, 0.62, 4.0, i2 == 0, 300.0)
		i2 += 1
	# Corner fill so the four corners are shaped darkness, not dead space —
	# faint on purpose: the contrast hierarchy keeps its edges darkest.
	for c: Vector2 in [Vector2(0.13, 0.2), Vector2(0.87, 0.2), Vector2(0.13, 0.84), Vector2(0.87, 0.84)]:
		_light_pool(z, Vector2(w * c.x, h * c.y), 300.0, accent, 0.06)

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

## Soft additive halo BEHIND a prop (round-4 rule 2, silhouette support): drawn
## above the ground layers but below every y-sorted sprite, so the prop is
## backlit out of the floor instead of dissolving into it. Deliberately faint —
## it separates the silhouette; the focal lamp still owns the brightness.
static func _backglow(parent: Node2D, pos: Vector2, width: float, col: Color, alpha: float = 0.10) -> void:
	var s := Sprite2D.new()
	s.texture = _light_tex()
	s.material = _additive_mat()
	s.position = pos
	var tw := maxf(1.0, float(s.texture.get_width()))
	s.scale = Vector2(width / tw, width * 0.8 / tw)
	s.modulate = Color(col.r, col.g, col.b, alpha)
	s.z_index = -44
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
	# The fixture is parented to the LABEL, not to the sign layer. world_label
	# resolves collisions as LATER captions arrive, and an eviction sets the
	# plate's `visible` to false long after _sign has already checked it — which
	# is how the round-5 frames ended up with a lit tube, two brackets and a
	# floor pool hanging over bare floor with no sign under them ("short floating
	# horizontal bars in the region accent colour"). As a child of the plate the
	# whole fixture switches off with it. z_as_relative is cleared so the label's
	# own z 1150 cannot push the fixture on top of the world, and the offset
	# lets everything below keep using the parent-space coordinates it always did.
	var fx := Node2D.new()
	fx.name = "SignFixture"
	fx.position = -lbl.box.position
	fx.z_as_relative = false
	fx.z_index = 0
	lbl.add_child(fx)
	var tube_w := minf(2.6, lbl.box.size.x / 48.0) * 48.0
	# A backboard the tube is bolted to, the shadow it casts down onto the plate,
	# and brackets long enough to actually REACH the plate. Round 5 hung the tube
	# 13px clear of its own sign on two 3x14 pins that were invisible against a
	# dark floor, so the frames read the tube as a bar floating over nothing.
	_rect(fx, mount + Vector2(0.0, 2.0), Vector2(tube_w + 18.0, 16.0), Color(0, 0, 0, 0.34), WorldLabel.Z_PLATE - 3)
	_rect(fx, mount, Vector2(tube_w + 12.0, 12.0), Color(0.055, 0.06, 0.095, 0.96), WorldLabel.Z_PLATE - 2)
	_rect(fx, mount + Vector2(0.0, -5.0), Vector2(tube_w + 12.0, 2.0), Color(0.20, 0.22, 0.30, 0.9), WorldLabel.Z_PLATE - 2)
	for k: float in [1.0, -1.0]:
		var bx := mount + Vector2(k * (tube_w * 0.5 + 4.0), 0.0)
		_rect(fx, bx + Vector2(0.0, 9.0), Vector2(4, 22), Color(0.05, 0.055, 0.09, 0.95), WorldLabel.Z_PLATE - 2)
		_rect(fx, bx, Vector2(8, 7), Color(0.14, 0.15, 0.20, 0.95), WorldLabel.Z_PLATE - 2)
	var tube := Sprite2D.new()
	tube.texture = _neon_tex(col)
	var mat := _shader_mat("neon_flicker", {"seed": float(idx) * 3.7 + mount.x * 0.013, "base_boost": 1.6})
	if mat:
		tube.material = mat
	tube.position = mount
	tube.scale = Vector2(minf(2.6, lbl.box.size.x / 48.0), 1.4)
	tube.z_index = WorldLabel.Z_PLATE - 1
	fx.add_child(tube)
	_light_pool(fx, mount + Vector2(0, 46), 220.0, col, 0.22)
	if idx < 1:
		_add_light(fx, mount + Vector2(0, 8), col, 0.6, 1.8, true)

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
			# Lava-glow pool under the shimmer so the hot zone reads HOT. This is
			# the mines' focal (round-4 rule 3): the one brightest thing.
			_add_light(parent, Vector2(w * 0.5, h * 0.76), Color(1.0, 0.42, 0.18), 1.2, 6.0, true)
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
	_backglow(parent, pos + Vector2(0, -26), 220.0, awning, 0.10)
	_prop(parent, "struct_crate", pos + Vector2(-46, 10), 0.85, Color(0.62, 0.5, 0.42))
	_prop(parent, "struct_crate", pos + Vector2(46, 10), 0.85, Color(0.58, 0.46, 0.4))
	_drop_shadow(parent, pos + Vector2(0, 14), 165.0, zi - 1, 0.38)
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
	_backglow(parent, pos, 130.0 * sc, Color(col.r, col.g, col.b * 0.9), 0.08)
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
	_backglow(parent, pos + Vector2(0, -12.0 * sc), 150.0 * sc, hot, 0.09)
	for i in 5:
		_led(parent, pos + Vector2(-10.0 + float(i % 2) * 20.0, -54.0 + float(i) * 18.0), hot if i % 2 == 0 else col, phase + float(i) * 0.19, zi + 1)
	_glow_rect(parent, pos + Vector2(0, 52.0 * sc), Vector2(40.0 * sc, 5), Color(hot.r, hot.g, hot.b, 0.55), zi + 1)
	_light_pool(parent, pos + Vector2(0, 62.0 * sc), 150.0 * sc, hot, 0.2)

## Cubicle: two glass partitions, a desk, and a monitor nobody is behind.
static func _cubicle(parent: Node2D, pos: Vector2, col: Color, screen_col: Color) -> void:
	var zi := _depth(pos.y, 40.0)
	_prop(parent, "struct_slab", pos + Vector2(-56, -8), 0.55, col, 0.0, 0.6)
	_prop(parent, "struct_slab", pos + Vector2(0, -40), 0.55, Color(col.r * 0.9, col.g * 0.9, col.b * 0.95), 0.0, 0.6)
	_drop_shadow(parent, pos + Vector2(8, 32), 96.0, zi - 1, 0.34)
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
	var ln := d.length()
	if ln < 8.0:
		return
	var ang := d.angle()
	var mid := (a + b) * 0.5
	# Haze first. A 2px overbright rect on its own is a drawn line — which is
	# exactly how the vault's lattice read in the round-5 frame ("two perfectly
	# straight cross-screen lines"). A beam is a thread inside a glow, and it
	# has motes hanging in it.
	_glow_rect(parent, mid, Vector2(ln, 13.0), Color(col.r * 0.5, col.g * 0.5, col.b * 0.5, 0.09), -89, ang)
	_glow_rect(parent, mid, Vector2(ln, 2.0), Color(col.r * 1.6, col.g * 1.6, col.b * 1.6, 0.5), -88, ang)
	var motes := maxi(3, int(ln / 96.0))
	for i in motes:
		var t := (float(i) + 0.5) / float(motes)
		_glow_rect(parent, a + d * t, Vector2(5, 5), Color(col.r * 1.4, col.g * 1.4, col.b * 1.4, 0.20), -88, ang + 0.7)
	# Emitter heads: a housing with a lit top edge, a lens, a contact shadow and
	# the puddle it throws — the beam visibly comes OUT of something at both ends.
	for e: Vector2 in [a, b]:
		var zi := _depth(e.y, 11.0)
		_drop_shadow(parent, e + Vector2(0, 11), 36.0, zi - 1, 0.38)
		_rect(parent, e, Vector2(16, 22), Color(0.06, 0.055, 0.09, 0.96), zi)
		_rect(parent, e + Vector2(0, -9), Vector2(16, 3), Color(0.24, 0.25, 0.33), zi + 1)
		_glow_rect(parent, e, Vector2(7, 7), Color(col.r, col.g, col.b, 0.9), zi + 1)
		_light_pool(parent, e + Vector2(0, 13), 90.0, col, 0.16)

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
	_backglow(parent, pos + Vector2(0, -20), 240.0, Color(1.0, 0.76, 0.4), 0.10)
	# ROUND-6 FIX, from region_open_source_wildlands.png: the wall was painted at
	# 0.34x the region accent — #3E9E5C x 0.34 is (0.08, 0.24, 0.12), which is
	# black on a black floor — while the ridge cap on top of it was (0.42, 0.48,
	# 0.42). The only part of the shack a frame could resolve was that cap, and
	# the capture read it as a 208px bar floating over nothing, one of the
	# "floating horizontal bars with nothing under them". A silhouette needs a
	# VALUE, not just a highlight, so the wall now carries three steps of its own
	# (lit left return, body, shaded right return) and the ridge sits on a roof
	# that is visible underneath it.
	_rect(parent, pos + Vector2(0, 8), Vector2(184, 96), Color(col.r * 0.60, col.g * 0.64, col.b * 0.56), zi)
	_rect(parent, pos + Vector2(-80.0, 8.0), Vector2(24, 96), Color(col.r * 0.86, col.g * 0.92, col.b * 0.80), zi + 1)
	_rect(parent, pos + Vector2(56.0, 8.0), Vector2(72, 96), Color(0, 0, 0, 0.26), zi + 1)
	for i in 9:
		_rect(parent, pos + Vector2(-80.0 + float(i) * 20.0, 8.0), Vector2(3, 96), Color(0, 0, 0, 0.26), zi + 1)
	# Eave shadow cast down the wall, then the roof, then a mid step, then the
	# lit ridge — so the brightest line in the piece is the TOP OF SOMETHING.
	_rect(parent, pos + Vector2(0, -32), Vector2(190, 12), Color(0, 0, 0, 0.42), zi + 2)
	_rect(parent, pos + Vector2(0, -46), Vector2(208, 17), Color(0.21, 0.25, 0.21), zi + 2)
	_rect(parent, pos + Vector2(0, -51), Vector2(208, 5), Color(0.30, 0.35, 0.30), zi + 3)
	_rect(parent, pos + Vector2(0, -54), Vector2(208, 3), Color(0.42, 0.48, 0.42), zi + 3)
	_rect(parent, pos + Vector2(0, 24), Vector2(54, 64), Color(0.02, 0.02, 0.03), zi + 2)
	_glow_rect(parent, pos + Vector2(0, 24), Vector2(48, 58), Color(1.0, 0.72, 0.34, 0.28), zi + 3)
	_lamp(parent, pos + Vector2(0, -36), Color(1.0, 0.74, 0.36), 0.8, 2.2, true, 270.0)

static func _sp_dependency(z: Node2D, glow: Color, accent: Color) -> void:
	# node_modules: a crate heap collapsing into its own gravity well. THE focal
	# (round-4 rule 3): the one brightest thing in the district, backlit so the
	# heap's silhouette reads from the far door without its caption.
	_floor_patch(z, Vector2(296, 292), 340.0, Color(0.01, 0.03, 0.01), 0.55, -94)
	_backglow(z, Vector2(296, 250), 300.0, glow, 0.14)
	_heap(z, Vector2(296, 286), accent, 8, 1.0, 4201)
	_lamp(z, Vector2(296, 214), glow, 1.1, 3.0, true, 340.0)
	_sign(z, Vector2(196, 148), "node_modules\n4.2 GB of someone else's problems", glow, 12)
	# The install bay: a terminal that has been at 47% for a while. Mid-ground:
	# one step below the heap.
	_prop(z, "struct_console", Vector2(1010, 254), 1.0, Color(0.66, 0.8, 0.5))
	_screen(z, Vector2(1010, 232), glow, Vector2(1.3, 1.1), _depth(254, 60))
	_rect(z, Vector2(1010, 296), Vector2(120, 8), Color(0.06, 0.1, 0.05), _depth(296, 8))
	_glow_rect(z, Vector2(982, 296), Vector2(56, 6), Color(glow.r, glow.g, glow.b, 0.8), _depth(296, 9))
	_lamp(z, Vector2(1010, 224), glow, 0.5, 1.9, false, 210.0)
	_sign(z, Vector2(922, 336), "installing... 47%\n(it has said 47% for an hour)", accent, 11)
	# The lockfile shrine. Merged by hand. We do not speak of it.
	_prop(z, "struct_slab", Vector2(560, 796), 0.6, Color(0.5, 0.62, 0.44))
	for k: float in [1.0, -1.0]:
		_lamp(z, Vector2(560 + k * 46.0, 780), Color(1.0, 0.78, 0.4), 0.35, 1.0, k > 0.0, 90.0)
	_sign(z, Vector2(470, 856), "package-lock.json\nresolved by hand. Do not ask.", Color("#FFB020"), 11)
	# The conveyor feeding the heap. It only runs one way, it has run since before
	# anybody currently here joined, and nobody has located the off switch.
	var belt_y := 210.0
	_drop_shadow(z, Vector2(560, belt_y + 22.0), 350.0, _depth(belt_y, 20.0) - 1, 0.4)
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
	# The Accepted Answer, still lit, still wrong. THE focal: brightest thing in
	# the ruins, haloed so the slab reads before its caption does.
	_backglow(z, Vector2(640, 200), 260.0, glow, 0.14)
	_prop(z, "struct_slab", Vector2(640, 214), 1.0, Color(0.86, 0.76, 0.55))
	_glow_rect(z, Vector2(640, 190), Vector2(30, 30), Color(glow.r, glow.g, glow.b, 0.5), _depth(214, 62))
	_lamp(z, Vector2(640, 178), glow, 1.15, 2.8, true, 340.0)
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
	# The hermit's fire, burning documentation for warmth. Mid-ground, a step
	# below the Accepted Answer.
	_light_pool(z, Vector2(1000, 730), 240.0, Color(1.0, 0.66, 0.3), 0.3)
	_lamp(z, Vector2(1000, 716), Color(1.0, 0.62, 0.26), 0.58, 1.8, true, 0.0)
	for k: float in [1.0, -1.0]:
		_prop(z, "struct_slab", Vector2(1000 + k * 92.0, 740), 0.3, Color(0.56, 0.5, 0.42), k * 0.2)

	# One more answer-stone, snapped, still lit. Nobody remembers the question.
	_prop(z, "dress_monolith", Vector2(190, 646), 1.0, Color(0.78, 0.7, 0.54))
	_prop(z, "dress_monolith", Vector2(1188, 846), 0.85, Color(0.7, 0.63, 0.5), 0.09)

static func _sp_bazaar(z: Node2D, glow: Color, accent: Color) -> void:
	# Three stalls along the top: everything's for sale, per request. The centre
	# stall is THE focal — one headline lamp over it, so the market has a main
	# attraction instead of three equally-lit pitches.
	_stall(z, Vector2(276, 236), glow, accent, 91)
	_stall(z, Vector2(640, 218), accent, glow, 92)
	_stall(z, Vector2(1004, 236), glow, accent, 93)
	_lamp(z, Vector2(640, 146), glow, 1.1, 2.8, false, 360.0)
	_sign(z, Vector2(190, 300), "API keys\ncash, crypto, or kidney", glow, 11)
	_sign(z, Vector2(930, 300), "Free tier: 14 seconds\n(measured generously)", accent, 11)
	# The haggling pit: a ring of crates around a low table nobody wins at.
	_floor_patch(z, Vector2(604, 800), 380.0, accent, 0.1, -94)
	for i in 7:
		var a := TAU * float(i) / 7.0
		_prop(z, "struct_crate", Vector2(604, 800) + Vector2(cos(a) * 150.0, sin(a) * 92.0), 0.55, Color(0.72, 0.56, 0.4), a * 0.2)
	_drop_shadow(z, Vector2(604, 812), 110.0, _depth(800, 16) - 1, 0.36)
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
	_backglow(z, Vector2(640, 190), 280.0, glow, 0.13)
	_prop(z, "struct_arch", Vector2(640, 172), 1.15, Color(0.72, 0.82, 0.96))
	_floor_patch(z, Vector2(640, 268), 380.0, glow, 0.16, -94)
	# THE focal: the cathedral arch owns the frame; everything else steps down.
	_lamp(z, Vector2(640, 196), glow, 1.2, 3.2, true, 380.0)
	_sign(z, Vector2(556, 288), "THE CLOUD\nsomeone else's computer, uphill", glow, 12)
	# The invoice altar. Numbers go up. Nobody knows which numbers.
	_prop(z, "struct_slab", Vector2(640, 802), 0.75, Color(0.66, 0.76, 0.9))
	_screen(z, Vector2(640, 774), accent, Vector2(1.5, 1.1), _depth(802, 48))
	_lamp(z, Vector2(640, 762), accent, 0.5, 1.9, false, 220.0)
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
	# THE focal — the warmest, brightest pool in the wildlands is the human.
	_light_pool(z, Vector2(1058, 826), 340.0, Color(1.0, 0.7, 0.34), 0.34)
	_lamp(z, Vector2(1058, 812), Color(1.0, 0.64, 0.28), 1.15, 2.4, true, 0.0)
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
	_lamp(z, Vector2(640, 224), glow, 0.5, 2.2, true, 260.0)

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
	# The all-hands stage, permanently set up. THE focal: the big screen gets
	# the one headline lamp; the flanking pair steps down under it.
	_drop_shadow(z, Vector2(1000, 846), 270.0, _depth(812, 30) - 1, 0.4)
	_backglow(z, Vector2(1000, 770), 300.0, glow, 0.12)
	_rect(z, Vector2(1000, 812), Vector2(250, 60), Color(0.18, 0.2, 0.28), _depth(812, 30))
	_rect(z, Vector2(1000, 786), Vector2(250, 5), Color(0.32, 0.36, 0.5), _depth(812, 32))
	_rect(z, Vector2(930, 780), Vector2(30, 42), Color(0.24, 0.26, 0.36), _depth(796, 22))
	_screen(z, Vector2(1000, 742), glow, Vector2(2.6, 1.7), _depth(812, 34))
	_lamp(z, Vector2(1000, 722), glow, 1.05, 2.6, false, 320.0)
	for k: float in [1.0, -1.0]:
		_lamp(z, Vector2(1000 + k * 96.0, 744), glow, 0.5, 1.8, false, 200.0)
	_sign(z, Vector2(896, 872), "ALL-HANDS: AI STRATEGY\nby Friday. Of an unspecified year.", glow, 11)
	# Reception: a desk, a ticket queue, and no receptionist.
	_drop_shadow(z, Vector2(258, 660), 165.0, _depth(640, 18) - 1, 0.36)
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
		_backglow(z, cp + Vector2(0, -30), 190.0, Color(0.6, 0.85, 1.0), 0.09)
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
	# The pit itself, so the ring of cracks encircles a HOLE rather than bare
	# floor, and every crack is a cut with heat in it rather than a bright line
	# lying across the ground at a random angle.
	_floor_patch(z, Vector2(640, 812), 200.0, Color(0.03, 0.012, 0.008), 0.55, -92)
	_glow_rect(z, Vector2(640, 812), Vector2(118, 38), Color(1.0, 0.46, 0.16, 0.28), -91)
	for i in 9:
		var a := TAU * float(i) / 9.0
		var ad := Vector2(cos(a), sin(a))
		var cp2 := Vector2(640, 812) + Vector2(ad.x * 96.0, ad.y * 58.0)
		_rect(z, cp2, Vector2(54, 12), Color(0, 0, 0, 0.62), -91, a)
		_rect(z, cp2 - Vector2(0, 4), Vector2(50, 3), Color(0.40, 0.22, 0.16, 0.6), -90, a)
		_glow_rect(z, cp2, Vector2(46, 4), Color(1.0, 0.42, 0.14, 0.6), -90, a)
		_glow_rect(z, cp2 + Vector2(ad.x * 23.0, ad.y * 14.0), Vector2(7, 3), Color(1.0, 0.8, 0.52, 0.5), -90, a)
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
	# The incident war room. Permanently staffed by nobody. THE focal: the
	# brightest thing in production is the room where production is discussed.
	_backglow(z, Vector2(640, 230), 320.0, glow, 0.13)
	_prop(z, "struct_slab", Vector2(640, 208), 1.7, Color(0.6, 0.42, 0.44))
	for i in 3:
		_screen(z, Vector2(556.0 + float(i) * 84.0, 196.0), glow, Vector2(1.7, 1.3), _depth(208, 104))
	_drop_shadow(z, Vector2(640, 324), 250.0, _depth(300, 20) - 1, 0.38)
	_rect(z, Vector2(640, 300), Vector2(230, 40), Color(0.22, 0.17, 0.19), _depth(300, 20))
	_rect(z, Vector2(640, 284), Vector2(230, 4), Color(0.36, 0.28, 0.3), _depth(300, 22))
	for k: float in [1.0, -1.0]:
		_rect(z, Vector2(640 + k * 132.0, 306), Vector2(34, 34), Color(0.18, 0.15, 0.18), _depth(306, 18))
	_lamp(z, Vector2(640, 262), glow, 1.25, 2.8, true, 380.0)
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
	# The status page. Fully green. Load-bearing lie. Mid-ground.
	_prop(z, "struct_slab", Vector2(272, 276), 0.9, Color(0.6, 0.44, 0.46))
	_screen(z, Vector2(272, 248), Color(0.3, 0.95, 0.45), Vector2(1.9, 1.2), _depth(276, 56))
	_lamp(z, Vector2(272, 234), Color(0.3, 0.95, 0.45), 0.5, 1.9, false, 240.0)
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
	# The reserve pedestal: an orb of tokens under an arcane ring. THE focal.
	_backglow(z, Vector2(640, 236), 260.0, glow, 0.15)
	_prop(z, "struct_orb", Vector2(640, 244), 0.85, Color(1.0, 0.85, 0.34))
	for i in 20:
		var a := TAU * float(i) / 20.0
		_glow_rect(z, Vector2(640, 300) + Vector2(cos(a) * 128.0, sin(a) * 78.0), Vector2(11, 4), Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.5), -90, a)
	_lamp(z, Vector2(640, 226), glow, 1.25, 3.0, true, 380.0)
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
	# Two SHORT bays rather than three beams spanning the whole room: an 868px
	# perfectly straight line across the frame reads as a stray primitive no
	# matter what is emitting it, and the bays give the lattice a rhythm.
	for k: float in [0.0, 1.0]:
		var bx := 236.0 + k * 416.0
		_laser(z, Vector2(bx, 630), Vector2(bx + 372.0, 694), Color("#FF4757"))
		_laser(z, Vector2(bx + 372.0, 630), Vector2(bx, 694), Color("#FF4757"))
		_laser(z, Vector2(bx, 662), Vector2(bx + 372.0, 662), VIOLET)
	for k: float in [1.0, -1.0]:
		_laser(z, Vector2(640.0 + k * 172.0, 196.0), Vector2(640.0 + k * 172.0, 336.0), Color("#FF4757"))
	_sign(z, Vector2(196, 862), "PRICE ORACLE\nprices rise after every gain", Color("#B794FF"), 11)
	# The balance console. It says "yes".
	_prop(z, "struct_console", Vector2(640, 800), 0.95, Color(0.9, 0.78, 0.46))
	_screen(z, Vector2(640, 778), accent, Vector2(1.4, 1.0), _depth(800, 56))
	_sign(z, Vector2(566, 858), "BALANCE: yes\nRate limit: spiritual", accent, 11)

	# The posts the lattice actually comes out of, and a cart of reserves left
	# where the last audit abandoned it.
	# ON the outer bay ends (x 236 and 1024), not 46px shy of them: an emitter
	# prop that no beam comes out of, standing beside a beam that comes out of
	# thin air, is the same "stray primitive" reading the shortened bays were
	# meant to close.
	_prop(z, "dress_laser_emitter", Vector2(236, 662), 1.0, Color(1.0, 0.78, 0.6))
	_prop(z, "dress_laser_emitter", Vector2(1024, 662), 1.0, Color(1.0, 0.78, 0.6))
	_prop(z, "dress_ore_cart", Vector2(884, 894), 0.9, Color(1.0, 0.86, 0.5), -0.06)

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
				"focal": Vector2(296, 286),  # the node_modules heap
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
				"focal": Vector2(640, 214),  # the Accepted Answer
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
				"focal": Vector2(640, 218),  # the centre stall
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
				"focal": Vector2(640, 172),  # the server cathedral arch
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
				"focal": Vector2(1058, 812),  # the maintainer's campfire
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
				"focal": Vector2(1000, 742),  # the all-hands stage screen
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
				"focal": Vector2(640, 812),  # the heat pit
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
				"focal": Vector2(640, 262),  # the war room
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
				"focal": Vector2(640, 244),  # the reserve pedestal
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

# --- encounter staging ----------------------------------------------------

## Solid cover placed this build, in world space. Filled by _build_encounters
## and read by _random_pos so a token can never be scattered inside a barrier
## the player cannot walk into. Cleared at the top of every region build —
## static state that survives a rebuild is a bug class this project has already
## paid for twice.
static var _cover_rects: Array[Rect2] = []

## Where each region's enemies STAND. Round 4 scattered them with a randomised
## RNG at >=420px from the arrival plaza, which meant the same room played
## differently every visit and never played deliberately: packs spawned inside
## set-pieces, on top of NPCs, or in a line across open floor.
##
## These are guard posts, ambush pockets and defended caches, authored against
## each region's own composition. The ORDER matches _region_enemies() exactly —
## entry N of that table consumes the next N positions here — so a boss lands in
## its arena and the trash lands on the approaches.
##
## Two invariants, both load-bearing:
##   * every post is >= 420px from the arrival plaza at (640,480), because
##     tests/region_arrival_test.gd asserts nothing spawns inside the 340px
##     aggro radius. _staged() re-checks at runtime.
##   * the first combat region keeps exactly 4 (tests/region_winnable_test.gd).
static func _region_enemy_posts(region_id: String) -> Array:
	match region_id:
		"dependency_district":
			# Two demons holding the node_modules heap, two null references
			# picketing the install bay. The artery between them stays clean.
			# BESIDE their landmarks, never inside them: _heap() spreads +/-70px
			# from (296,286) and the install bay console owns x 950..1070, so
			# posts tucked into those footprints were simply not visible.
			return [Vector2(176, 224), Vector2(352, 166), Vector2(1112, 222), Vector2(1084, 302)]
		"stackoverflow_ruins":
			# Bugs in the monolith fields; the merge conflict waits in the south
			# clearing, which is the only wide open floor in the ruins. The two
			# north posts stand clear of the toppled slabs at (238,300) and
			# (1096,318), and the south one clear of the shrine's sign plate.
			return [Vector2(156, 300), Vector2(1000, 196), Vector2(180, 706), Vector2(866, 868)]
		"api_bazaar":
			# Rate limiters posted at the market gates, bugs in the west aisle.
			# The west-gate bug stands outside the stall awning (x 199..353).
			return [Vector2(1120, 300), Vector2(900, 890), Vector2(250, 700), Vector2(250, 268), Vector2(172, 182)]
		"cloud_district":
			# The bill occupies the south floor; the leaks sit on the racks.
			return [Vector2(880, 862), Vector2(238, 296), Vector2(1082, 278)]
		"open_source_wildlands":
			# Legacy systems squatting on the issue graveyard — the thing worth
			# taking is the thing that is defended. Bugs patrol the perimeter.
			# The README bug stands west of the monument, not behind it.
			return [Vector2(246, 792), Vector2(404, 866), Vector2(186, 266), Vector2(1124, 268), Vector2(1148, 620)]
		"corporate_enterprise":
			# The architect owns the south-west floor; scope creep is everywhere
			# else, which is thematically the only correct arrangement. The
			# reception picket moved off the "raise a ticket" sign plate — a
			# world plate draws at z 1150 and hides anything standing under it.
			return [Vector2(286, 856), Vector2(250, 248), Vector2(152, 596), Vector2(1108, 236)]
		"gpu_mines":
			# Leaks on both rig banks and one down at the spoil heap; two bugs at
			# the mouth of the heat pit, which is where you want to be standing.
			# The two north posts sit in the GAPS between rigs (racks are on a
			# 104px pitch), so a leak reads against the floor, not against a rig.
			return [Vector2(228, 250), Vector2(366, 158), Vector2(1022, 166), Vector2(1114, 300),
				Vector2(250, 782), Vector2(750, 894), Vector2(1060, 894)]
		"production":
			# The monolith holds the south floor below the war room. The
			# hallucinations are gathered around the status page, agreeing —
			# west of it, clear of the slab and of the STATUS PAGE plate.
			return [Vector2(420, 880), Vector2(170, 262), Vector2(1092, 268), Vector2(1148, 560)]
		"token_vault":
			# Two rate limiters on the shelving rows, the infinite context in the
			# open south-east where there is room to run away from it.
			return [Vector2(250, 258), Vector2(1092, 258), Vector2(872, 860)]
		_: return []

## Boss arena anchor (visual only — the post table above is what actually
## places the boss). A boss with nowhere to circle is a damage race, not a
## fight, so each of these gets a marked-out clearing with bollards on its
## corners and every other piece of scenery kept out of it.
static func _region_boss_arena(region_id: String) -> Vector2:
	match region_id:
		"stackoverflow_ruins": return Vector2(866, 868)
		"cloud_district": return Vector2(880, 862)
		"corporate_enterprise": return Vector2(286, 856)
		"production": return Vector2(420, 880)
		"token_vault": return Vector2(872, 860)
		_: return Vector2.ZERO

## Solid cover, per region. Small isolated blocks only — never a wall, never two
## within 150px of each other, never within 88px of a post or 150px of a portal
## or NPC — so they can shape a fight without ever boxing the player, an enemy
## or a quest-giver in. Positions are hand-checked against every portal, NPC and
## interactable in the region.
static func _region_cover(region_id: String) -> Array:
	match region_id:
		"dependency_district":
			# Deliberately NOT between the heap and the install bay: that corridor
			# is the engagement line tests/region_winnable_test.gd walks, and the
			# first combat region is the last place to introduce geometry that
			# could make a chasing enemy hesitate.
			return [Vector2(150, 330), Vector2(150, 660), Vector2(924, 182), Vector2(1160, 372)]
		"stackoverflow_ruins":
			return [Vector2(150, 180), Vector2(1180, 380), Vector2(300, 830), Vector2(760, 800), Vector2(980, 880)]
		"api_bazaar":
			# (160,220) moved down: the west-gate post is the only spot at that
			# latitude that clears both the stall awning and the arrival radius.
			return [Vector2(700, 880), Vector2(150, 600), Vector2(170, 340), Vector2(430, 180)]
		"cloud_district":
			return [Vector2(780, 830), Vector2(1000, 900), Vector2(150, 240), Vector2(1170, 200)]
		"open_source_wildlands":
			return [Vector2(150, 700), Vector2(520, 820), Vector2(150, 180), Vector2(1170, 180), Vector2(1160, 740)]
		"corporate_enterprise":
			return [Vector2(180, 790), Vector2(400, 880), Vector2(150, 180), Vector2(160, 340), Vector2(1170, 340)]
		"gpu_mines":
			# (430,180) moved to the aisle mouth: the rig-gap post sits at x 366.
			return [Vector2(150, 180), Vector2(520, 196), Vector2(910, 180), Vector2(1180, 200),
				Vector2(150, 860), Vector2(860, 880), Vector2(1160, 900)]
		"production":
			# (150,200) moved south of the status page so the picket has floor.
			return [Vector2(300, 900), Vector2(560, 880), Vector2(150, 600), Vector2(1180, 180), Vector2(1180, 720)]
		"token_vault":
			return [Vector2(150, 180), Vector2(1180, 180), Vector2(740, 890), Vector2(1000, 900)]
		_: return []

static func _build_encounters(parent: Node2D, region_id: String, theme: Dictionary, w: int, h: int) -> void:
	var z := Node2D.new()
	z.name = "Encounters"
	parent.add_child(z)
	var glow: Color = theme.get("glow", Color(0.7, 0.8, 0.95))
	var accent: Color = theme.get("accent", glow)
	var arena := _region_boss_arena(region_id)
	if arena != Vector2.ZERO:
		# The clearing is drawn around the boss post but clamped inward, because
		# several posts sit close enough to a wall that an un-clamped ring would
		# be painted over the wall or off the map entirely.
		_arena(z, Vector2(clampf(arena.x, 260.0, float(w) - 260.0), clampf(arena.y, 250.0, float(h) - 140.0)), accent, glow)
	var idx := 0
	for cp: Vector2 in _region_cover(region_id):
		_cover(z, cp, glow, accent, idx)
		idx += 1
	# A faint marker under each post: a scuffed patch where something has been
	# standing for a while. Reads as staging, not as a spawn indicator.
	for pp: Vector2 in _region_enemy_posts(region_id):
		_floor_patch(z, pp + Vector2(0, 14), 120.0, Color(0.02, 0.02, 0.035), 0.30, -92)

## Boss arena: a marked-out clearing with a swept pad, a poured rail and six
## bollards standing on it. Deliberately NON-colliding — the space is the point, and a solid
## pillar sitting where a boss spawns is a depenetration bug waiting to happen.
## Solid cover is placed by _cover() at hand-checked positions instead.
static func _arena(parent: Node2D, pos: Vector2, accent: Color, glow: Color) -> void:
	_floor_patch(parent, pos, 500.0, Color(accent.r, accent.g, accent.b), 0.09, -94)
	# THE INSIDE FIRST. Round 5 drew thirty free dashes on an ellipse and nothing
	# else, so what the frames actually showed was a dashed arc floating over bare
	# floor — an editor gizmo, not a place. A marked-out clearing has a swept
	# surface, a keep-clear hatch and a stencil in the middle of it, and the ring
	# is then the EDGE of something instead of a decal on its own.
	_floor_patch(parent, pos, 330.0, Color(0.014, 0.016, 0.03), 0.32, -93)
	for i in 26:
		var ha := TAU * float(i) / 26.0
		var hr := 0.40 + float(i % 3) * 0.17
		_rect(parent, pos + Vector2(cos(ha) * 178.0 * hr, sin(ha) * 106.0 * hr),
			Vector2(24.0, 3.0), Color(0, 0, 0, 0.22), -93, 0.62)
	_rect(parent, pos, Vector2(122.0, 5.0), Color(0, 0, 0, 0.32), -93)
	_rect(parent, pos, Vector2(5.0, 78.0), Color(0, 0, 0, 0.32), -93)
	_rect(parent, pos, Vector2(118.0, 2.0), Color(accent.r, accent.g, accent.b, 0.20), -93)
	_rect(parent, pos, Vector2(2.0, 74.0), Color(accent.r, accent.g, accent.b, 0.20), -93)
	# The rail: a CONTINUOUS poured edge with the lit lip on the inside, exactly
	# like every other material seam in the room, with the reflectors sitting ON
	# the rail rather than replacing it.
	var n := 30
	var pts: Array[Vector2] = []
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(pos + Vector2(cos(a) * 180.0, sin(a) * 108.0))
	for i in n:
		var a0: Vector2 = pts[i]
		var b0: Vector2 = pts[(i + 1) % n]
		var sg := b0 - a0
		var ang := sg.angle()
		var mid := (a0 + b0) * 0.5
		var inward := (pos - mid).normalized()
		_rect(parent, mid, Vector2(sg.length() + 4.0, 6.0), Color(0, 0, 0, 0.42), -92, ang)
		_rect(parent, mid + inward * 3.0, Vector2(sg.length() + 4.0, 2.0), Color(glow.r, glow.g, glow.b, 0.18), -92, ang)
		if i % 3 == 0:
			_glow_rect(parent, mid + inward * 7.0, Vector2(12.0, 3.0), Color(glow.r, glow.g, glow.b, 0.22), -91, ang)
	# Bollards ON the rail, each with a cap that catches the light and a contact
	# shadow — the ring is bolted down, not painted on.
	for i in 6:
		var a2 := TAU * (float(i) + 0.5) / 6.0
		var pp := pos + Vector2(cos(a2) * 180.0, sin(a2) * 108.0)
		var zi := _depth(pp.y, 18.0)
		_drop_shadow(parent, pp + Vector2(0, 14), 50.0, zi - 1, 0.4)
		_rect(parent, pp, Vector2(14, 34), Color(0.09, 0.095, 0.14, 0.96), zi)
		_rect(parent, pp + Vector2(0, -13), Vector2(14, 4), Color(0.22, 0.24, 0.32), zi + 1)
		_glow_rect(parent, pp + Vector2(0, -16), Vector2(8, 4), Color(glow.r, glow.g, glow.b, 0.6), zi + 1)
	# Four approach chevrons pointing INTO the clearing: the ring now says "in
	# here", which is the only thing a ring on a floor is ever for. Every arena
	# in the game is clamped against the south wall, so any chevron that lands
	# under the bottom sill (where it would be half-drawn, i.e. exactly the stray
	# mark this pass is removing) is dropped rather than clamped.
	var rw := float(REGION_SIZE.x * TILE_SIZE)
	var rh := float(REGION_SIZE.y * TILE_SIZE)
	for i in 4:
		var a3 := TAU * (float(i) + 0.25) / 4.0
		var cvp := pos + Vector2(cos(a3) * 218.0, sin(a3) * 134.0)
		if cvp.x < 96.0 or cvp.x > rw - 96.0 or cvp.y < 116.0 or cvp.y > rh - 76.0:
			continue
		_chevron(parent, cvp, Color(accent.r, accent.g, accent.b, 0.20), a3 + PI, -92)
	_light_pool(parent, pos, 400.0, accent, 0.14)

## One piece of solid cover: a low barrier with a lit cap, a contact shadow and
## a collider. Enemies are CharacterBody2Ds and slide off these; player
## projectiles are Area2Ds on the enemy layer and pass straight through, so
## cover changes where you stand without ever eating your shots.
static func _cover(parent: Node2D, pos: Vector2, glow: Color, accent: Color, idx: int) -> void:
	var zi := _depth(pos.y, 24.0)
	var col: Color = glow if idx % 2 == 0 else accent
	_drop_shadow(parent, pos + Vector2(0, 22), 104.0, zi - 1, 0.42)
	_rect(parent, pos, Vector2(78, 46), Color(0.10, 0.105, 0.15, 0.96), zi)
	_rect(parent, pos + Vector2(0, -21), Vector2(78, 5), Color(0.24, 0.26, 0.34), zi + 1)
	for i in 3:
		_rect(parent, pos + Vector2(-24.0 + float(i) * 24.0, 4.0), Vector2(4, 34), Color(0, 0, 0, 0.32), zi + 1)
	_glow_rect(parent, pos + Vector2(-26, -20), Vector2(12, 4), Color(col.r, col.g, col.b, 0.7), zi + 2)
	_glow_rect(parent, pos + Vector2(26, -20), Vector2(12, 4), Color(col.r, col.g, col.b, 0.45), zi + 2)
	_light_pool(parent, pos + Vector2(0, 26), 150.0, col, 0.13)
	_add_cover_body(parent, pos, Vector2(76, 34))

static func _add_cover_body(parent: Node2D, pos: Vector2, sz: Vector2) -> void:
	_add_collider(parent, pos, sz)
	# Inflated by 34px: a token's own pickup shape is 14px and the magnet reaches
	# 100px, but a coin visually buried in a crate is still a coin the player
	# will spend a minute failing to walk onto.
	_cover_rects.append(Rect2(pos - sz * 0.5 - Vector2(34, 34), sz + Vector2(68, 68)))

static func _in_cover(p: Vector2) -> bool:
	for r in _cover_rects:
		if r.has_point(p):
			return true
	return false

## Staging guard-rail. tests/region_arrival_test.gd asserts no enemy spawns
## within the 340px aggro radius of the arrival plaza; this pushes any authored
## post that ever drifts inside it back out along its own bearing and clamps it
## into the walkable interior, so a future composition edit can never turn into
## a spawn-into-a-swarm regression. Falls back to the old scatter when a region
## has no post table or the clamp cannot satisfy the radius.
static func _staged(want: Vector2, spawn: Vector2, rng: RandomNumberGenerator) -> Vector2:
	var w := float(REGION_SIZE.x * TILE_SIZE)
	var h := float(REGION_SIZE.y * TILE_SIZE)
	if want == Vector2.ZERO:
		return _safe_scatter(rng, spawn, w, h)
	var p := Vector2(clampf(want.x, 130.0, w - 130.0), clampf(want.y, 150.0, h - 66.0))
	var d := p - spawn
	if d.length() < 415.0:
		if d.length() < 1.0:
			d = Vector2(1.0, 0.0)
		p = spawn + d.normalized() * 415.0
		p = Vector2(clampf(p.x, 130.0, w - 130.0), clampf(p.y, 150.0, h - 66.0))
	if p.distance_to(spawn) < 415.0:
		return _safe_scatter(rng, spawn, w, h)
	return p

## Scatter fallback that CANNOT violate the arrival radius. _random_pos gives up
## after 50 tries and returns a point near its centre — for a token that is a
## harmless nudge, but for an enemy it is a spawn inside the aggro ring and a
## tests/region_arrival_test.gd failure that would only show up on a bad seed.
## The corner anchors below are all >= 430px from a 640,480 spawn and inside the
## walkable interior, so the guarantee holds no matter what the RNG does.
static func _safe_scatter(rng: RandomNumberGenerator, spawn: Vector2, w: float, h: float) -> Vector2:
	var p := _random_pos(rng, spawn, 420.0)
	if p.distance_to(spawn) >= 420.0:
		return p
	var anchors: Array[Vector2] = [
		Vector2(200.0, 220.0), Vector2(w - 200.0, 220.0),
		Vector2(200.0, h - 100.0), Vector2(w - 200.0, h - 100.0),
	]
	return anchors[rng.randi() % anchors.size()]

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
		# Same depth convention as the player and the NPCs. token_pickup.tscn
		# ships z_index 0, so a coin scattered anywhere near set dressing drew
		# UNDER it — and "collect N tokens" is an objective, not decoration.
		t.z_index = int(t.position.y)
		tokens.add_child(t)

	# Stage enemies. Counts and types are UNCHANGED — this only decides where
	# they stand. Posts are consumed in _region_enemies() order, so the boss row
	# lands on the boss post; anything past the end of the table (or a region
	# with no table) falls back to the old scatter.
	#
	# Placement still respects the aggro radius (340): a player arriving or
	# respawning gets a moment to orient and then CHOOSES to walk into a fight —
	# no fast-travel-into-a-swarm. _staged() enforces that at 415px.
	var enemy_types := _region_enemies(region_id)
	var posts := _region_enemy_posts(region_id)
	var post_i := 0
	for e in enemy_types:
		var count: int = e.get("count", 2)
		for i in count:
			var en = enemy_scene.instantiate()
			en.enemy_type = e.type
			en.max_hp = e.get("hp", 30)
			en.is_boss = e.get("boss", false)
			var want := Vector2.ZERO
			if post_i < posts.size():
				var wp: Vector2 = posts[post_i]
				want = wp
				post_i += 1
			en.position = _staged(want, spawn, rng)
			# Depth, the same convention player.gd:327 and npc.gd:126 already
			# use. enemy.tscn ships z_index 0 and enemy_base never sets it, so
			# every builder prop (z = int(y + half)) drew IN FRONT of every
			# enemy no matter where it stood — a staged guard tucked against
			# its landmark was invisible. Seeding it here fixes the pose the
			# player arrives to; enemy_base still needs to refresh it as the
			# enemy walks (raised as a cross-file need).
			en.z_index = int(en.position.y)
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
			# Solid cover exists now. A token scattered inside a barrier is a
			# collection objective the player cannot finish, so reject those.
			if _in_cover(pos):
				continue
			return pos
	# Fallback lands on the landing plaza, which never holds cover.
	return center + Vector2(rng.randf_range(-240, 240), rng.randf_range(-150, 150))

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
			return [{"id": "maintainer", "pos": Vector2(1076, 786), "quests": ["install_node", "fix_without_touching", "pin_everything", "caret_gamble"]}]
		"stackoverflow_ruins":
			return [{"id": "stackoverflow_hermit", "pos": Vector2(1000, 704), "quests": ["stackoverflow_pilgrimage", "merge_conflict_hell"]}]
		"api_bazaar":
			return [{"id": "api_reseller", "pos": Vector2(1088, 782), "quests": ["one_more_api_call", "junior_agent"]}, {"id": "junior_agent", "pos": Vector2(800, 620), "quests": ["junior_agent"]}]
		"cloud_district":
			return [{"id": "cloud_salesperson", "pos": Vector2(1128, 748), "quests": ["cloud_migration", "context_window_full"]}]
		"open_source_wildlands":
			return [{"id": "oss_maintainer", "pos": Vector2(1058, 852), "quests": ["license_puzzle"]}]
		"corporate_enterprise":
			return [{"id": "svp_ai", "pos": Vector2(1000, 786), "quests": ["enterprise_ready", "mission_statement"]}]
		"gpu_mines":
			return [{"id": "gpu_foreman", "pos": Vector2(1136, 692), "quests": ["gpu_rush"]}]
		"production":
			return [{"id": "oncall_engineer", "pos": Vector2(1090, 848), "quests": ["production_down"]}]
		_: return []

## Portal placement. Round 5 put every door at exactly (cx +/- 400, cy), so the
## critique's "the portal at the same left-third position in all nine frames"
## was literally true — the doors were the third thing (after the centred plaza
## and the horizontal artery) making every region read as the same room. The
## positions below are hand-checked per region against that region's own cover
## blocks, enemy posts, NPC and set-pieces; all of them sit in open, reachable
## floor well inside the walls. The pairs are deliberately NOT at matching
## heights any more: an off-lane door earns a paved spur from _paint_paths and
## its own chevron trail from _paint_wayfinding, which is exactly the layout
## variety the frames were missing.
static func _region_portals(region_id: String) -> Array:
	var cx := REGION_SIZE.x * TILE_SIZE * 0.5
	var cy := REGION_SIZE.y * TILE_SIZE * 0.5
	match region_id:
		"localhost":
			return [{"to": "dependency_district", "pos": Vector2(cx + 400, cy), "label": "Dependency District"}]
		"dependency_district":
			# North-west of the heap; the onward door drops south past the depot.
			return [
				{"to": "localhost", "pos": Vector2(250, 392), "label": "Localhost"},
				{"to": "stackoverflow_ruins", "pos": Vector2(1052, 568), "label": "Stack Overflow Ruins"},
			]
		"stackoverflow_ruins":
			return [
				{"to": "dependency_district", "pos": Vector2(206, 520), "label": "Dependency District"},
				{"to": "api_bazaar", "pos": Vector2(1064, 506), "label": "API Bazaar"},
			]
		"api_bazaar":
			return [
				{"to": "stackoverflow_ruins", "pos": Vector2(250, 420), "label": "Stack Overflow Ruins"},
				{"to": "cloud_district", "pos": Vector2(1036, 586), "label": "Cloud District"},
			]
		"cloud_district":
			return [
				{"to": "api_bazaar", "pos": Vector2(216, 436), "label": "API Bazaar"},
				{"to": "open_source_wildlands", "pos": Vector2(1064, 566), "label": "Open Source Wildlands"},
			]
		"open_source_wildlands":
			# Both doors off the lane, on opposite diagonals: the wildlands is the
			# one region with no straight line through it.
			return [
				{"to": "cloud_district", "pos": Vector2(212, 542), "label": "Cloud District"},
				{"to": "corporate_enterprise", "pos": Vector2(1074, 414), "label": "Corporate Enterprise"},
			]
		"corporate_enterprise":
			return [
				{"to": "open_source_wildlands", "pos": Vector2(216, 452), "label": "Open Source Wildlands"},
				{"to": "gpu_mines", "pos": Vector2(1058, 568), "label": "GPU Mines"},
			]
		"gpu_mines":
			return [
				{"to": "corporate_enterprise", "pos": Vector2(228, 540), "label": "Corporate Enterprise"},
				{"to": "production", "pos": Vector2(1066, 414), "label": "Production"},
			]
		"production":
			return [
				{"to": "gpu_mines", "pos": Vector2(250, 420), "label": "GPU Mines"},
				{"to": "token_vault", "pos": Vector2(1024, 608), "label": "Token Vault"},
			]
		"token_vault":
			# The way home is a north door, off-axis from the reserve pedestal so
			# the pedestal stops standing in the doorway.
			return [
				{"to": "production", "pos": Vector2(216, 544), "label": "Production"},
				{"to": "localhost", "pos": Vector2(884, 96), "label": "Return to Localhost"},
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
