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

## The two global constants VISUAL_BIBLE_V2 LAW 2 allows outside a region's own
## three hues. TEXT_DIM is what ambient dust and every non-wayfinding caption is
## drawn in; WARM_KEY is the one warm, almost-white key an NPC stands in, so a
## person reads as a person in a room lit by its own neon.
const TEXT_DIM := Color("#7C8BB0")
const WARM_KEY := Color(1.0, 0.86, 0.62)

## LAW 4: at most six PointLight2Ds are alive in a region. Counted here rather
## than trusted to forty call sites — this file has, at various times, lit every
## crate, every sign, every stall and every prop halo, and the frames show
## exactly that: nothing dark, therefore no hierarchy. Reset at the top of every
## build (`_use_layout`), because regions rebuild on every travel.
const LIGHT_BUDGET := 6
static var _lights_used := 0

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
	_build_region_signs(parent, region_id, theme)
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

## LAW 2 and LAW 3, applied once instead of at ninety call sites. Every prop tint
## in this file was authored as a saturated hue at full value — acid-green
## crates, pink stalls, red rigs, gold shelves — which is how a frame ends up
## with eight hues in it and nothing to look at. A prop is desaturated toward its
## own luminance and capped at 66% value; the region's ACCENT and WARM are then
## spent where LAW 3 allows them: the player, the objective, tokens, two lights,
## enemy tells.
static func _dull(c: Color, amount: float = 0.55, cap: float = 0.66) -> Color:
	var lum := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
	var out := c.lerp(Color(lum, lum, lum, c.a), amount)
	var peak := maxf(out.r, maxf(out.g, out.b))
	if peak > cap:
		var k := cap / peak
		out = Color(out.r * k, out.g * k, out.b * k, c.a)
	return out

## Set-dressing sprite with a grounded drop shadow and y-sorted depth, measured
## from the real texture so tall props (towers) and flat ones (crates) both sit
## ON the floor instead of hovering next to it. Positions snap to even integers
## (LAW 1: one pixel grid) and the tint is desaturated on the way in (_dull).
static func _prop(parent: Node2D, tex_name: String, pos: Vector2, sc: float = 1.0, mod: Color = Color.WHITE, rot: float = 0.0, shadow: float = 1.0) -> Sprite2D:
	pos = Vector2(round(pos.x * 0.5) * 2.0, round(pos.y * 0.5) * 2.0)
	mod = _dull(mod)
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

## Additive rect — for anything that should read as EMITTING rather than being
## lit. Every request is halved on the way in: this file called it ~90 times a
## region (kerb reflectors, bollard caps, crate chips, rack vents, cordon rails,
## laser motes, LED chips) and additive ink over a dark floor never subtracts, so
## the sum of ninety "faint" glows is a room where everything emits. LAW 3 allows
## five bright things; this is the tax on everything that is not one of them.
static func _glow_rect(parent: Node2D, center: Vector2, size: Vector2, col: Color, z: int, rot: float = 0.0) -> ColorRect:
	var r := _rect(parent, center, size, Color(col.r, col.g, col.b, col.a * 0.5), z, rot)
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
	# Every build starts with the full light budget. Called from build() for both
	# branches, so Localhost resets it too.
	_lights_used = 0

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

## ROUND 7 — SUBTRACTION. The wear field, the mottle shader, the blotches, the
## seams, the curb trim and the per-cell hue drift are all GONE. VISUAL_BIBLE_V2
## LAW 6: a floor is readable ground, which means the tile art, an A/B variant
## no more than 6% apart in value, and nothing else. Everything that used to be
## piled on top of it was texture noise pretending to be history, and it is the
## single loudest thing in the captured frames.
##
## What survives, and only because it is NAVIGATION rather than texture: the
## three-zone value ramp (plaza brighter, perimeter darker) so the player can see
## where the room's "somewhere" is, and the walkway artery in its own material.
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
	for x in REGION_SIZE.x:
		for y in REGION_SIZE.y:
			var hv := _cell_hash(x, y)
			var p := Vector2(x * TILE_SIZE + TILE_SIZE * 0.5, y * TILE_SIZE + TILE_SIZE * 0.5)
			# Zone value only. No wear field, no per-tile jitter: LAW 6 caps the
			# A/B step at 6%, and a jitter on top of that is the noise itself.
			var k := _floor_zone(p, float(w), float(h), seed_v)
			var tex_name := "tech_floor"
			var m := Color(tint.r * k, tint.g * k, tint.b * k)
			# STRUCTURE, NOT NOISE: the material a tile is made of is decided by
			# WHERE it is — walkway band, landing plaza, perimeter, open field.
			var zn := _tile_zone(p, float(w), float(h), seed_v, hv)
			# The A/B break. 6% and no more (LAW 6) — the old 12-16% steps plus a
			# hue drift are what made the ground read as three materials shuffled.
			var ab := 1.0 if (hv % 100) < 62 else 1.06
			match zn:
				1:  # walkway band: one clean deck material end to end
					if has_path_tile:
						tex_name = "path_tile"
						m = Color(k * 1.06, k * 1.06, k * 1.08)
					elif has_b:
						tex_name = "tile_" + suffix + "_b"
						var wv := k * tile_mul * 1.06
						m = Color(wv, wv, wv)
					else:
						m = Color(tint.r * k * 1.10, tint.g * k * 1.10, tint.b * k * 1.12)
				2:  # landing plaza: the region's own showcase material
					if has_a:
						var pv := k * tile_mul * 1.04
						tex_name = "tile_" + suffix
						m = Color(pv, pv, pv)
					else:
						m = Color(tint.r * k * 1.08, tint.g * k * 1.08, tint.b * k * 1.08)
				3:  # perimeter: the darkest material — edges recede
					if has_base:
						tex_name = "floor_" + suffix + "_base"
						m = Color(k, k, k)
					m = m.darkened(0.24)
				_:  # open field, A/B alternated by cell hash
					if has_base:
						tex_name = "floor_" + suffix + "_base"
						if has_alt and (hv % 100) >= 62:
							tex_name = "floor_" + suffix + "_alt"
						m = Color(k * ab, k * ab, k * ab)
					elif has_a and (hv % 100) < 62:
						tex_name = "tile_" + suffix
						m = Color(k * tile_mul, k * tile_mul, k * tile_mul)
					elif has_b:
						var b := k * tile_mul * ab
						tex_name = "tile_" + suffix + "_b"
						m = Color(b, b, b)
					else:
						m = Color(tint.r * k * ab, tint.g * k * ab, tint.b * k * ab)
			_put(floor_node, tex_name, p, -100, 1.0, m)
	# What is left on top of the tiles, in full: the paved spurs to the doors, one
	# pair of quiet lines marking the artery, the wayfinding chevrons, and at most
	# three hand-placed decals. That is the whole floor.
	_paint_paths(floor_node, region_id, theme, w, h, seed_v)
	_paint_lane(floor_node, theme, w, h, seed_v)
	var glow: Color = theme.get("glow", Color.WHITE)
	_paint_wayfinding(floor_node, region_id, w, h, glow)
	_floor_decals(floor_node, region_id, w, h)

## The artery, marked. This used to paint hazard dashes, a 44-segment plaza kerb
## with reflectors and bolted posts, a landing cross and four corner ticks — an
## airport apron drawn on top of a floor that already changes material at exactly
## those lines. LAW 4 puts floor overlays at zero; what is left is the one thing
## the overlay was ever FOR: two quiet lines saying "the walkable route is
## between these". No accent hue, no glow, no dashes — the lane is dark line-work
## on ground, and the region ACCENT is spent on the objective instead.
static func _paint_lane(parent: Node2D, _theme: Dictionary, w: int, h: int, seed_v: int) -> void:
	var steps := 26
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
			_rect(parent, mid, Vector2(seg.length() + 3.0, 2.0), Color(0, 0, 0, 0.30), -93, seg.angle())

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
		# QUIETER, NEVER WEAKER. The chevrons are the floor's half of the guidance
		# system and they stay; what goes is the brightness ramp that made the last
		# one 0.34 alpha in the region accent. A flat, low, cool mark reads as a
		# painted direction arrow rather than as another glowing thing.
		var steps := int((dist - 190.0) / 108.0)
		for i in steps:
			var t := 190.0 + float(i) * 108.0
			_chevron(parent, center + dir * t, Color(col.r, col.g, col.b, 0.15), ang, -92)

static func _chevron(parent: Node2D, pos: Vector2, col: Color, ang: float, z: int) -> void:
	var n := Vector2(cos(ang), sin(ang))
	var side := Vector2(-n.y, n.x)
	_rect(parent, pos + side * -5.0, Vector2(22.0, 4.0), col, z, ang + 0.46)
	_rect(parent, pos + side * 5.0, Vector2(22.0, 4.0), col, z, ang - 0.46)

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

## Axis-aligned paved segment. Round 6 gave every spur a poured underlay, a deck,
## path_tile sprites, edge sprites, region-tinted edge lines, grate ticks at a
## 48px rhythm, twelve shed chips and a five-piece ragged terminus: forty-odd
## primitives per branch, on a floor that has three of them. LAW 4 — floor
## overlays are zero, and a road only has to say WALK HERE. That is a dark
## underlay one value below the field and a hairline edge either side of it.
static func _path_segment(parent: Node2D, a: Vector2, b: Vector2, _col: Color, wpx: float = 90.0) -> void:
	var d := b - a
	var seg_len := d.length()
	if seg_len < 40.0:
		return
	var horiz := absf(d.x) > absf(d.y)
	var mid := (a + b) * 0.5
	var size := Vector2(seg_len + wpx * 0.6, wpx) if horiz else Vector2(wpx, seg_len + wpx * 0.6)
	_rect(parent, mid, size, Color(0.016, 0.02, 0.04, 0.34), -93)
	_rect(parent, mid, size - Vector2(12, 12), Color(0.72, 0.78, 0.9, 0.06), -93)
	var side := Vector2(0, 1) if horiz else Vector2(1, 0)
	var esz := Vector2(size.x, 2.0) if horiz else Vector2(2.0, size.y)
	for k: float in [1.0, -1.0]:
		_rect(parent, mid + side * (k * wpx * 0.5), esz, Color(0, 0, 0, 0.34), -93)

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
	# THREE. Not nine, not seventy-eight bolts and sixteen drag marks on top of
	# them (LAW 4: <= 3 decals per region). A floor mark is a hand-placed piece of
	# history; a field of them is the noise the brief called slop.
	var placed := 0
	for i in 14:
		if placed >= 3:
			return
		var name_i: String = str(pool[rng.randi() % pool.size()])
		var pos := Vector2(rng.randf_range(180, float(w) - 180), rng.randf_range(200, float(h) - 160))
		pos = Vector2(round(pos.x * 0.5) * 2.0, round(pos.y * 0.5) * 2.0)
		# Off the walkway band: a maintained deck with a crack across it stops
		# reading as maintained.
		if absf(pos.y - _band_y(pos.x, float(w), float(h), seed_v)) < _band_half(pos.x, float(w), seed_v) + 20.0:
			continue
		var spr := _put(parent, name_i, pos, -91, 1.0, Color(1, 1, 1, 0.34), rng.randf_range(-PI, PI))
		if spr == null:
			return  # generator has not been run; nothing to scatter
		placed += 1

static func _build_walls_themed(parent: Node2D, theme: Dictionary, w: int, h: int) -> void:
	var walls := Node2D.new()
	walls.name = "Walls"
	parent.add_child(walls)
	var wall_tint: Color = theme.get("wall", Color(0.7, 0.7, 0.8))
	# No per-column value jitter any more: a wall built of twenty slightly
	# different greys is the same defect as a floor built of them (LAW 6).
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
	# One unlit conduit along the top wall. The seven junction boxes each with a
	# glowing chip are gone: signs do not glow, props do not glow, and a service
	# run is not one of LAW 3's five bright things.
	_rect(walls, Vector2(w * 0.5, 52.0), Vector2(w - 80.0, 4.0), Color(0.03, 0.035, 0.06, 0.8), -56)

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
	# ONE band. The second, closer band (seven larger silhouettes drawn in front
	# of the haze, each with a 40-50% chance of its own additive glow dot) was
	# depth bought with clutter; depth now comes from the lighting, per LAW 3.
	for i in 9:
		var px := 90.0 + float(i) * (w - 180.0) / 8.0 + rng.randf_range(-22, 22)
		var py := rng.randf_range(108, 152)
		var sc := rng.randf_range(0.5, 0.85)
		var v := rng.randf_range(0.20, 0.30)
		_put(z, str(vocab[rng.randi() % vocab.size()]), Vector2(px, py), -50, sc, Color(v, v, v * 1.12))
	# Atmospheric haze band so the far end of the room recedes.
	_rect(z, Vector2(w * 0.5, 130.0), Vector2(w - 60.0, 110.0), Color(glow.r * 0.3, glow.g * 0.3, glow.b * 0.36, 0.06), -48)

## Foreground layer. A ceiling beam across the very top, two full-height
## stanchions the player walks behind, and a dark sill along the bottom: the room
## is looked INTO rather than down at.
##
## ROUND 7 removed everything else that used to live here — two overhead cable
## trays with twenty-four hangers, three drooping ceiling cables, four hanging
## growths with glowing tips, four in-world corner vignettes and two side jambs.
## Every one of them was a dark shape drawn over the play field, and stacked they
## were most of why the top and edges of every frame read as busy. Depth comes
## from the lighting now (LAW 3), not from things put in front of the camera.
static func _build_foreground(parent: Node2D, theme: Dictionary, w: int, h: int) -> void:
	var z := Node2D.new()
	z.name = "Foreground"
	parent.add_child(z)
	var glow: Color = theme.get("glow", Color(0.6, 0.7, 0.9))
	# Ceiling beam across the very top (above anywhere the player can stand).
	_rect(z, Vector2(w * 0.5, 30.0), Vector2(w + 40.0, 30.0), Color(0.02, 0.025, 0.045, 0.95), 500)
	_rect(z, Vector2(w * 0.5, 45.0), Vector2(w + 40.0, 2.0), Color(glow.r, glow.g, glow.b, 0.10), 501)
	for i in 5:
		var bx := 140.0 + float(i) * (w - 280.0) / 4.0
		_rect(z, Vector2(bx, 40.0), Vector2(14, 46), Color(0.02, 0.025, 0.045, 0.9), 500)
	# TRUE foreground occluders: two full-height stanchions just inside the side
	# walls that the player walks BEHIND. z 1000 clears the tallest possible
	# y-sorted sprite (the bottom wall is at 944) and still sits under world text.
	for k: float in [0.0, 1.0]:
		var sx := 56.0 + k * (float(w) - 112.0)
		_rect(z, Vector2(sx, h * 0.5), Vector2(28.0, float(h) + 20.0), Color(0.010, 0.012, 0.026, 0.72), 1000)
	# Bottom sill: the near edge of the room. Under 29px tall on purpose — the
	# lowest thing the game ever places is a staged enemy at y 894.
	_rect(z, Vector2(w * 0.5, h - 4.0), Vector2(w + 40.0, 26.0), Color(0.015, 0.018, 0.035, 0.92), 600)

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
	# LAW 3: props do not glow. Structures used to claim up to three PointLight2Ds
	# between them, a backing halo each, blinking LEDs on every tower and a lit
	# pool under everything. They now get ONE faint floor pool apiece — enough to
	# sit them on the ground — and consoles keep their screen, because a screen is
	# a motivated light source and a halo is not.
	for s in theme.get("structs", []):
		var sc: float = float(s.get("s", 1.0))
		var sp: Vector2 = s.p
		var sm: Color = s.get("m", Color.WHITE)
		var spr := _prop(z, str(s.t), sp, sc, sm)
		if not spr:
			continue
		if s.t == "struct_console":
			_screen(z, sp + Vector2(0, -20.0 * sc), glow, Vector2(1.1, 1.0) * sc, spr.z_index + 1)
		_light_pool(z, sp + Vector2(0, 14.0 * sc), 120.0 * sc, glow, 0.09)

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

	# Soft shadow band under the top wall for depth.
	_rect(z, Vector2(w * 0.5, 47.0), Vector2(w - 40.0, 26.0), Color(0, 0, 0, 0.28), -59)

	var vocab := _vocab(theme)
	if vocab.is_empty():
		return
	# FOUR, not eleven, and the three glowing pipe runs across the top are gone.
	# LAW 4 allows one focal set-piece plus <= 8 secondary props per region, and
	# the set-piece pass has already spent most of that budget.
	var center := Vector2(w * 0.5, h * 0.5)
	var placed := 0
	for i in 14:
		if placed >= 4:
			break
		var p := Vector2(rng.randf_range(100, w - 100), rng.randf_range(140, h - 90))
		p = Vector2(round(p.x * 0.5) * 2.0, round(p.y * 0.5) * 2.0)
		if p.distance_to(center) < 240.0:
			continue
		if _plaza_field(p, float(w), float(h), _layout_seed) < 40.0:
			continue
		if absf(p.y - _band_y(p.x, float(w), float(h), _layout_seed)) < 110.0:
			continue
		_prop(z, str(vocab[rng.randi() % vocab.size()]), p, rng.randf_range(0.3, 0.48), wall_c, 0.0, 0.8)
		placed += 1

## Two landmark-scale silhouettes in the quadrants the composition leaves empty,
## so the eye has a scale ladder to climb.
##
## ROUND 7 deleted the other half of this pass: forty-six procedural "signature
## marks" per region — pallets, rubble, mats, ducts, growth, carpet, spall,
## hazard tape, spilt coins — each of them three to twenty rects on a wear bed,
## scattered across the whole field. That is roughly four hundred primitives of
## floor dressing per room, and it is exactly the noise LAW 6 forbids: the ground
## stopped being ground and became a texture. The floor is the tile art now.
static func _build_signature(parent: Node2D, region_id: String, theme: Dictionary, w: int, h: int) -> void:
	var z := Node2D.new()
	z.name = "Signature"
	parent.add_child(z)
	var glow: Color = theme.get("glow", Color(0.6, 0.7, 0.9))
	var accent: Color = theme.get("accent", glow)
	var seed_v := _region_seed(region_id)
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
		_prop(z, str(vocab[hv2 % vocab.size()]), lp, 1.45 + float(hv2 % 25) / 100.0,
			Color(0.30, 0.32, 0.38), (float(hv2 % 13) - 6.0) * 0.012)
		_light_pool(z, lp + Vector2(0, 40), 250.0, accent, 0.12)
		placed += 1

## ONE ambient emitter. LAW 4 allows two per region: this slow dust layer and one
## at the region's set-piece (the wildlands campfire, the mines' coolant plume).
##
## What went: the themed layer (embers / sparks / packets / spores / dust /
## sparkle, 36 particles, saturated at 0.9 alpha and a second hue on top of the
## region's three), a separate 20-particle foreground dust layer, and two
## point-of-interest accent emitters. Four emitters, four hundred moving lit
## pixels, none of which the player was ever meant to look at. Dust is TEXT_DIM
## at 25% alpha because dust is not one of LAW 3's five bright things.
static func _build_region_ambient(parent: Node2D, _theme: Dictionary, w: int, h: int) -> void:
	var dust := CPUParticles2D.new()
	dust.name = "Ambient"
	dust.position = Vector2(w * 0.5, h * 0.5)
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	dust.emission_rect_extents = Vector2(w * 0.5 - 60, h * 0.5 - 60)
	dust.z_index = -40
	dust.amount = 16
	dust.lifetime = 9.0
	dust.gravity = Vector2(0, -5)
	dust.initial_velocity_min = 2.0
	dust.initial_velocity_max = 8.0
	dust.spread = 180.0
	dust.scale_amount_min = 1.2
	dust.scale_amount_max = 2.2
	dust.color = Color(TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, 0.25)
	var dot := _glow_dot()
	if dot:
		dust.texture = dot
	parent.add_child(dust)

## Motivated light, LAW 3 and LAW 4. TWO ceiling fixtures — a housing on the
## wall, a tube, and the pool it throws — and that is the whole ambient rig.
##
## What went: four fixtures (two of them real lights), a real anchor lamp for
## every entry in the theme's `lights` table, and four corner fill pools. Between
## them, structures and set-pieces this room used to carry a dozen PointLight2Ds
## and thirty additive pools; nothing in the frame was ever darker than anything
## else, which is the definition of no hierarchy. The anchors keep their pools —
## a pool is a puddle on the floor, not a light — and the corners are allowed to
## simply be dark, because edges recede.
static func _build_region_lights(parent: Node2D, theme: Dictionary, w: int, _h: int) -> void:
	var z := Node2D.new()
	z.name = "Lighting"
	parent.add_child(z)
	var glow: Color = theme.get("glow", Color(0.6, 0.8, 1.0))
	for i in 2:
		var fx := 330.0 + float(i) * (w - 660.0)
		_rect(z, Vector2(fx, 66.0), Vector2(58, 12), Color(0.05, 0.055, 0.085, 0.95), -54)
		var tube := Sprite2D.new()
		tube.texture = _neon_tex(glow)
		var mat := _shader_mat("neon_flicker", {"seed": 2.3 + float(i) * 5.1, "base_boost": 1.0})
		if mat:
			tube.material = mat
		tube.position = Vector2(fx, 68.0)
		tube.scale = Vector2(1.1, 1.0)
		tube.z_index = -53
		z.add_child(tube)
		_light_pool(z, Vector2(fx, 150.0), 360.0, glow, 0.13)
		_add_light(z, Vector2(fx, 96.0), glow, 0.5, 3.4, false)
	# The theme's anchor points keep a pool each and no light.
	for lp in theme.get("lights", []):
		_light_pool(z, lp, 280.0, glow, 0.10)

## A quiet puddle under the one person in the room. An NPC you can talk to is
## LAW 3's "current objective" more often than not, so the NPC keeps a real key
## light — but the twelve-rect ring of dashes that used to be drawn around their
## feet is gone (it read as a summoning circle, not as lighting), and so are the
## per-flavour-prop accent pools that lit nine more things to the same value.
static func _build_poi_pools(parent: Node2D, region_id: String, _theme: Dictionary) -> void:
	var z := Node2D.new()
	z.name = "PoiPools"
	parent.add_child(z)
	for npc_data in _region_npcs(region_id):
		var np: Vector2 = npc_data.pos
		_add_light(z, np + Vector2(0, -6), WARM_KEY, 0.55, 3.0)
		_light_pool(z, np + Vector2(0, 22), 230.0, WARM_KEY, 0.24)

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

## LAW 4 lives here: energy is clamped to 0.4-0.9, the radius is floored at a
## genuinely soft one (a tight bright cookie is a spot-halo on a prop, which the
## law forbids by name), and past LIGHT_BUDGET the request simply returns null.
## Callers already treat a missing light as "the pool carries it", so exhausting
## the budget degrades to a darker room rather than to a broken one.
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

## A lamp is a POOL. It only becomes a real PointLight2D when the caller asked
## for focal energy (>= 1.0), which across this file is true of exactly one lamp
## per region: the one over the set-piece.
##
## That single threshold is what took the light count from roughly fifteen a room
## to four. Every other _lamp call in this file — the anchors, the stalls, the
## shrine, the shack, the ore carts, the arcane circles, the depot, the install
## bay, the lockfile — asked for 0.35..0.8, i.e. "please also be bright", and
## between them they lit the entire room to one flat value. They all still cast
## their puddle, which is the part that was ever doing the work.
static func _lamp(parent: Node2D, pos: Vector2, col: Color, energy: float, scale: float, flicker: bool = false, pool: float = 240.0) -> PointLight2D:
	var l: PointLight2D = null
	if energy >= 1.0:
		l = _add_light(parent, pos, col, energy, scale, flicker)
	if pool > 0.0:
		_light_pool(parent, pos + Vector2(0, 26), pool, col, 0.20)
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

## Status LED. LAW 7 allows exactly one emissive pixel per light source on a
## sprite, and LAW 9 says nothing but the player, the tokens and the waypoint
## moves at rest — so this is now a single static chip, not a tween that blinks
## a rack of five of them out of phase forever. `phase` is kept in the signature
## and ignored: every caller passes one, and the parameter is cheaper to keep
## than nine call sites are to edit.
static func _led(parent: Node2D, pos: Vector2, color: Color, _phase: float, z: int) -> void:
	_glow_rect(parent, pos, Vector2(3, 2), color, z)

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
	# 1.15, down from 1.35. A screen IS a motivated light source (LAW 3, item 4),
	# so it keeps its bloom — but a region with six consoles in it was pushing six
	# overbright rectangles past the bloom threshold, and then nothing was focal.
	var crt := _shader_mat("crt_monitor", {"glow_boost": 1.15})
	if crt:
		scr.material = crt
	scr.position = pos
	scr.scale = sc
	scr.z_index = z
	parent.add_child(scr)
	return scr

## ONE ambient-occlusion strip where the walls meet the floor, exactly as LAW 6
## specifies. The forty-four rotated grime decals and the four 620px corner
## darkening patches that used to come with it are gone: grime scattered over a
## floor is texture noise, and an in-world corner vignette is the post-processing
## vignette drawn twice.
static func _build_region_grounding(parent: Node2D, w: int, h: int) -> void:
	var z := Node2D.new()
	z.name = "Grounding"
	parent.add_child(z)
	_ao_edges(z, w, h)

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

## One region sign. There is no fixture any more.
##
## Round 6 mounted a neon tube on a backboard with two brackets, a cast shadow, a
## floor pool and a real PointLight2D on top of every headline plate — a lit
## light-box for a caption. The plate itself is gone too (world_label.gd draws
## plain aliased text with a drop shadow now, per LAW 4), so there is nothing
## left to bolt a fixture to and nothing left that needs one: text on a dark
## floor is legible, and the sign is not one of the five things allowed to glow.
static func _sign(parent: Node2D, pos: Vector2, text: String, col: Color, font_size: int = 12, wayfinding: bool = false, _idx: int = 0) -> void:
	WorldLabel.add(parent, pos, text, col, {
		"size": font_size,
		"style": "headline" if wayfinding else "plate",
		"priority": 3 if wayfinding else _sign_prio,
	})

## AT MOST FOUR world labels per region (LAW 4), and wayfinding comes first.
##
## This used to draw the theme's four flavour signs, on top of the four to six
## captions each set-piece placed itself: twenty-one to thirty-four plates in a
## room, all of them jokes, all of them competing with the one line that says
## where to go. LAW 10 is explicit about where the jokes went — into prop
## interactions and dialogue, which the player CHOOSES to read — and every string
## removed this round has been handed to the reactive-comedy owner rather than
## deleted.
##
## What is left, per region: the set-piece caption (placed by _sp_*), one EXIT
## toward the onward door, and one hint pointing at the person you can talk to.
static func _build_region_signs(parent: Node2D, region_id: String, theme: Dictionary) -> void:
	var z := Node2D.new()
	z.name = "Signs"
	parent.add_child(z)
	var accent: Color = theme.get("glow", Color(0.9, 0.9, 1.0))
	# EXIT: the onward door is the LAST portal in the table (the first is the way
	# back to the region you came from), so the arrow points at progress.
	var doors := _region_portals(region_id)
	if not doors.is_empty():
		var pd: Dictionary = doors[doors.size() - 1]
		var dp: Vector2 = pd.pos
		var w := float(REGION_SIZE.x * TILE_SIZE)
		# Hung on the room side of the door, so the arrow reads into the doorway
		# rather than off the edge of the world.
		var side := -1.0 if dp.x > w * 0.5 else 1.0
		var at := Vector2(dp.x + side * 150.0, dp.y - 96.0)
		_sign(z, Vector2(round(at.x * 0.5) * 2.0, round(at.y * 0.5) * 2.0),
			"EXIT \u2192" if side < 0.0 else "\u2190 EXIT", accent, 13, true)
	# One NPC hint. The person is the region's other objective, and the waypoint
	# already knows where they are — this is the floor-level confirmation.
	for npc_data in _region_npcs(region_id):
		var np: Vector2 = npc_data.pos
		var hp := np + Vector2(-190.0, 34.0)
		_sign(z, Vector2(round(hp.x * 0.5) * 2.0, round(hp.y * 0.5) * 2.0),
			"talk \u2192", accent, 12, true)
		break

## Region-specific atmosphere. LAW 5 allows ONE region to keep one atmosphere
## shader "if it is subtle enough that a viewer would not name it" — the vault's
## gold code-rain at 0.14 alpha is that one. Production's red LogSpew column and
## the vault's two violet corner lamps are gone: a second scrolling shader and a
## fourth hue are exactly what the law is written against.
static func _build_region_fx(parent: Node2D, region_id: String, _theme: Dictionary, w: int, h: int) -> void:
	match region_id:
		"gpu_mines":
			# The heat shimmer lives in postfx_layer.gd, not here. This is the
			# mines' focal light: the heat pit, and the one bright thing in the
			# room (LAW 3, item 4 — a motivated source).
			_add_light(parent, Vector2(w * 0.5, h * 0.76), Color("#FF6B2D"), 0.9, 6.0, true)
		"token_vault":
			var rain := _shader_mat("code_rain", {"tint": Color(1.0, 0.83, 0.3, 1.0), "alpha_max": 0.10, "columns": 42.0, "speed": 0.8})
			if rain:
				var rect := ColorRect.new()
				rect.name = "DataRain"
				rect.material = rain
				rect.position = Vector2(40, 60)
				rect.size = Vector2(w - 80, h - 120)
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

## Framed doorway around a portal: an arch behind it, a faint threshold stain on
## the floor and two unlit bollards. The 280px additive pool and the 300px accent
## floor wash that used to sit here are gone — region_portal.gd already carries
## the portal's own light, and LAW 4 wants the door FINDABLE, not dominant.
static func _gate(parent: Node2D, pos: Vector2, col: Color, w: int, h: int) -> void:
	var inward := signf(float(w) * 0.5 - pos.x)
	_put(parent, "struct_arch", pos + Vector2(0, -10), -20, 1.15, Color(0.34, 0.36, 0.44))
	_floor_patch(parent, pos + Vector2(0, 30), 260.0, col, 0.07, -94)
	for k: float in [1.0, -1.0]:
		var bp := pos + Vector2(inward * 78.0, k * 74.0)
		if pos.y < float(h) * 0.25:
			bp = pos + Vector2(k * 78.0, 66.0)
		_rect(parent, bp, Vector2(10, 26), Color(0.05, 0.055, 0.09, 0.95), _depth(bp.y, 13.0))
		_glow_rect(parent, bp + Vector2(0, -14), Vector2(6, 4), Color(col.r, col.g, col.b, 0.55), _depth(bp.y, 14.0))

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
	_light_pool(parent, pos + Vector2(0, 60), 200.0, Color(0.58, 0.65, 0.78), 0.10)

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
	## The region's ONE set-piece caption (LAW 4: <= 4 world labels).
	_sign(z, Vector2(200, 150), "node_modules", glow, 12)
	# node_modules: a crate heap collapsing into its own gravity well. THE focal
	# (round-4 rule 3): the one brightest thing in the district, backlit so the
	# heap's silhouette reads from the far door without its caption.
	_floor_patch(z, Vector2(296, 292), 340.0, Color(0.01, 0.03, 0.01), 0.55, -94)
	_heap(z, Vector2(296, 286), accent, 8, 1.0, 4201)
	_lamp(z, Vector2(296, 214), glow, 1.1, 3.0, true, 340.0)
	# The install bay: a terminal that has been at 47% for a while. Mid-ground:
	# one step below the heap.
	_prop(z, "struct_console", Vector2(1010, 254), 1.0, Color(0.66, 0.8, 0.5))
	_screen(z, Vector2(1010, 232), glow, Vector2(1.3, 1.1), _depth(254, 60))
	_rect(z, Vector2(1010, 296), Vector2(120, 8), Color(0.06, 0.1, 0.05), _depth(296, 8))
	_glow_rect(z, Vector2(982, 296), Vector2(56, 6), Color(glow.r, glow.g, glow.b, 0.8), _depth(296, 9))
	_lamp(z, Vector2(1010, 224), glow, 0.5, 1.9, false, 210.0)
	# The lockfile shrine. Merged by hand. We do not speak of it.
	_prop(z, "struct_slab", Vector2(560, 796), 0.6, Color(0.5, 0.62, 0.44))
	for k: float in [1.0, -1.0]:
		_lamp(z, Vector2(560 + k * 46.0, 780), Color(1.0, 0.78, 0.4), 0.35, 1.0, k > 0.0, 90.0)
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
	## The region's ONE set-piece caption (LAW 4: <= 4 world labels).
	_sign(z, Vector2(556, 300), "ACCEPTED ANSWER", glow, 12)
	# A field of toppled answer-monoliths. All correct in 2013.
	_monolith(z, Vector2(238, 300), 1.15, Color(0.72, 0.64, 0.5), 0.9, 11)
	_monolith(z, Vector2(392, 348), -0.42, Color(0.66, 0.58, 0.46), 0.75, 12)
	_monolith(z, Vector2(1096, 318), -1.25, Color(0.7, 0.62, 0.48), 0.85, 13)
	_monolith(z, Vector2(936, 372), 0.35, Color(0.62, 0.55, 0.44), 0.7, 14)
	# The Accepted Answer, still lit, still wrong. THE focal: brightest thing in
	# the ruins, haloed so the slab reads before its caption does.
	_prop(z, "struct_slab", Vector2(640, 214), 1.0, Color(0.86, 0.76, 0.55))
	_glow_rect(z, Vector2(640, 190), Vector2(30, 30), Color(glow.r, glow.g, glow.b, 0.5), _depth(214, 62))
	_lamp(z, Vector2(640, 178), glow, 1.15, 2.8, true, 340.0)
	_floor_patch(z, Vector2(640, 292), 300.0, glow, 0.14, -94)
	# Cairn of duplicates, stacked by a hermit with a lot of time.
	for i in 5:
		_prop(z, "struct_slab", Vector2(524.0 + float(i % 2) * 8.0, 838.0 - float(i) * 26.0), 0.34 - float(i) * 0.03, Color(0.6, 0.54, 0.44), float(i) * 0.4)
	# The pilgrim shrine. You bring your question here. The question has been
	# asked. The answer is four versions out of date and marked as duplicate.
	_shrine(z, Vector2(324, 716), glow)
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
	## The region's ONE set-piece caption (LAW 4: <= 4 world labels).
	_sign(z, Vector2(556, 300), "NIGHT MARKET", glow, 12)
	# Three stalls along the top: everything's for sale, per request. The centre
	# stall is THE focal — one headline lamp over it, so the market has a main
	# attraction instead of three equally-lit pitches.
	_stall(z, Vector2(276, 236), glow, accent, 91)
	_stall(z, Vector2(640, 218), accent, glow, 92)
	_stall(z, Vector2(1004, 236), glow, accent, 93)
	_lamp(z, Vector2(640, 146), glow, 1.1, 2.8, false, 360.0)
	# The haggling pit: a ring of crates around a low table nobody wins at.
	_floor_patch(z, Vector2(604, 800), 380.0, accent, 0.1, -94)
	for i in 7:
		var a := TAU * float(i) / 7.0
		_prop(z, "struct_crate", Vector2(604, 800) + Vector2(cos(a) * 150.0, sin(a) * 92.0), 0.55, Color(0.72, 0.56, 0.4), a * 0.2)
	_drop_shadow(z, Vector2(604, 812), 110.0, _depth(800, 16) - 1, 0.36)
	_rect(z, Vector2(604, 800), Vector2(96, 30), Color(0.3, 0.2, 0.3), _depth(800, 16))
	_lamp(z, Vector2(604, 762), accent, 0.6, 2.0, true, 240.0)
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
	## The region's ONE set-piece caption (LAW 4: <= 4 world labels).
	_sign(z, Vector2(556, 288), "THE CLOUD", glow, 12)
	# The server cathedral: a nave of racks, an arch for an apse.
	for i in 3:
		var y := 176.0 + float(i) * 96.0
		_rack(z, Vector2(430, y), Color(0.6, 0.7, 0.86), glow, 0.85, 0.2 + float(i) * 0.3)
		_rack(z, Vector2(850, y), Color(0.56, 0.66, 0.82), glow, 0.85, 0.5 + float(i) * 0.3)
	_prop(z, "struct_arch", Vector2(640, 172), 1.15, Color(0.72, 0.82, 0.96))
	_floor_patch(z, Vector2(640, 268), 380.0, glow, 0.16, -94)
	# THE focal: the cathedral arch owns the frame; everything else steps down.
	_lamp(z, Vector2(640, 196), glow, 1.2, 3.2, true, 380.0)
	# The invoice altar. Numbers go up. Nobody knows which numbers.
	_prop(z, "struct_slab", Vector2(640, 802), 0.75, Color(0.66, 0.76, 0.9))
	_screen(z, Vector2(640, 774), accent, Vector2(1.5, 1.1), _depth(802, 48))
	_lamp(z, Vector2(640, 762), accent, 0.5, 1.9, false, 220.0)
	# The cooling pond. Still, lit, expensive, and cooling nothing anybody here
	# can name. Reflections are two glow bars and a lot of confidence.
	_pond(z, Vector2(404, 764), Vector2(252, 118), glow)
	# The sales booth. It is elastic. Do not ask what that means.
	_prop(z, "struct_console", Vector2(1128, 782), 0.9, Color(0.7, 0.8, 0.95))
	_screen(z, Vector2(1128, 762), glow, Vector2(1.1, 0.9), _depth(782, 54))
	_lamp(z, Vector2(1128, 746), glow, 0.6, 1.7, false, 190.0)

	# The plant that keeps the cathedral cold, and the conduit waiting on a
	# change window that has been rescheduled four times.
	_prop(z, "dress_cooling_tower", Vector2(1146, 262), 1.0, Color(0.78, 0.86, 0.98))
	_prop(z, "dress_pipe_stack", Vector2(1122, 856), 0.95, Color(0.74, 0.82, 0.94))

static func _sp_opensource(z: Node2D, glow: Color, accent: Color) -> void:
	## The region's ONE set-piece caption (LAW 4: <= 4 world labels).
	_sign(z, Vector2(916, 862), "MAINTAINER", glow, 12)
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
	# The issue graveyard. Open since 2019. Reacted to with hearts.
	for i in 8:
		var gp := Vector2(220.0 + float(i % 4) * 78.0, 758.0 + float(i / 4) * 74.0)
		_prop(z, "struct_slab", gp, 0.28, Color(0.44, 0.62, 0.46), (float(i) - 3.5) * 0.05)
	# The README monument. Accurate six months ago.
	_prop(z, "struct_slab", Vector2(292, 274), 0.85, Color(0.56, 0.76, 0.54))
	_screen(z, Vector2(292, 250), glow, Vector2(1.2, 0.9), _depth(274, 52))
	_lamp(z, Vector2(292, 236), glow, 0.55, 1.8, false, 210.0)
	for i in 4:
		_rect(z, Vector2(238.0 + float(i) * 36.0, 322.0), Vector2(26, 6), Color(accent.r * 0.8, accent.g * 0.8, accent.b * 0.8, 0.7), _depth(322, 4))
	# The overgrown arch: still merged, still load-bearing.
	_floor_patch(z, Vector2(640, 246), 300.0, glow, 0.12, -94)
	for i in 6:
		_rect(z, Vector2(566.0 + float(i) * 30.0, 214.0 + float(i % 3) * 12.0), Vector2(6, 44), Color(accent.r * 0.7, accent.g * 0.7, accent.b * 0.7, 0.8), -46, 0.2 * float(i % 3))
	_lamp(z, Vector2(640, 224), glow, 0.5, 2.2, true, 260.0)

	# Dinner by the camp, and the spool the whole ecosystem is strung from.
	_prop(z, "dress_noodle_cup", Vector2(996, 890), 1.0, Color(0.82, 0.96, 0.8))
	_prop(z, "dress_cable_spool", Vector2(452, 302), 0.9, Color(0.7, 0.9, 0.7))

static func _sp_corporate(z: Node2D, glow: Color, accent: Color) -> void:
	## The region's ONE set-piece caption (LAW 4: <= 4 world labels).
	_sign(z, Vector2(896, 872), "ALL-HANDS STAGE", glow, 12)
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
	# The all-hands stage, permanently set up. THE focal: the big screen gets
	# the one headline lamp; the flanking pair steps down under it.
	_drop_shadow(z, Vector2(1000, 846), 270.0, _depth(812, 30) - 1, 0.4)
	_rect(z, Vector2(1000, 812), Vector2(250, 60), Color(0.18, 0.2, 0.28), _depth(812, 30))
	_rect(z, Vector2(1000, 786), Vector2(250, 5), Color(0.32, 0.36, 0.5), _depth(812, 32))
	_rect(z, Vector2(930, 780), Vector2(30, 42), Color(0.24, 0.26, 0.36), _depth(796, 22))
	_screen(z, Vector2(1000, 742), glow, Vector2(2.6, 1.7), _depth(812, 34))
	_lamp(z, Vector2(1000, 722), glow, 1.05, 2.6, false, 320.0)
	for k: float in [1.0, -1.0]:
		_lamp(z, Vector2(1000 + k * 96.0, 744), glow, 0.5, 1.8, false, 200.0)
	# Reception: a desk, a ticket queue, and no receptionist.
	_drop_shadow(z, Vector2(258, 660), 165.0, _depth(640, 18) - 1, 0.36)
	_rect(z, Vector2(258, 640), Vector2(150, 34), Color(0.2, 0.23, 0.32), _depth(640, 18))
	_screen(z, Vector2(258, 620), accent, Vector2(1.1, 0.8), _depth(640, 20))
	_lamp(z, Vector2(258, 604), accent, 0.5, 1.6, false, 180.0)

	# Records nobody can delete, a board nobody erased, and one more partition.
	_prop(z, "dress_filing_cabinet", Vector2(1178, 296), 1.0, Color(0.74, 0.8, 0.94))
	_prop(z, "dress_filing_cabinet", Vector2(1178, 402), 0.95, Color(0.7, 0.76, 0.9))
	_prop(z, "dress_whiteboard", Vector2(618, 892), 0.95, Color(0.8, 0.85, 0.96))
	_prop(z, "dress_cubicle", Vector2(1178, 668), 0.9, Color(0.68, 0.74, 0.88))

static func _sp_gpu(z: Node2D, glow: Color, accent: Color) -> void:
	## The region's ONE set-piece caption (LAW 4: <= 4 world labels).
	_sign(z, Vector2(548, 872), "HEAT PIT", glow, 12)
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
	# Cooling towers, losing.
	for k: float in [1.0, -1.0]:
		var cp := Vector2(640.0 - k * 456.0, 792.0)
		_prop(z, "struct_tower", cp, 1.25, Color(0.62, 0.56, 0.56))
		_glow_rect(z, cp + Vector2(0, -78), Vector2(30, 4), Color(0.62, 0.64, 0.66, 0.4), _depth(cp.y, 80.0))
		_lamp(z, cp + Vector2(0, -84), Color(0.58, 0.60, 0.62), 0.5, 1.8, false, 200.0)
		# ONE plume. LAW 4 allows two emitters a region and the ambient dust layer
		# has already spent one; a matched pair on both towers was symmetry for
		# its own sake anyway.
		if k < 0.0:
			continue
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
		steam.color = Color(0.72, 0.74, 0.76, 0.18)
		var dot := _glow_dot()
		if dot:
			steam.texture = dot
		z.add_child(steam)
	# Ore carts on rails, hauling allocated-but-undelivered compute from one end
	# of the mine to the other end of the mine.
	_rails(z, 668.0, 260.0, 1010.0, glow)
	_cart(z, Vector2(388, 656), glow, -0.03)
	_cart(z, Vector2(646, 660), accent, 0.02)
	_cart(z, Vector2(898, 654), glow, -0.05)
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
	# The foreman's shack.
	_prop(z, "struct_console", Vector2(1136, 716), 0.9, Color(0.74, 0.54, 0.44))
	_screen(z, Vector2(1136, 696), accent, Vector2(1.1, 0.9), _depth(716, 54))
	_lamp(z, Vector2(1136, 682), accent, 0.6, 1.7, true, 190.0)

	# Conduit staged for an upgrade that was approved two quarters ago, and a
	# cart that came off the rails and stayed off them.
	_prop(z, "dress_pipe_stack", Vector2(1176, 352), 0.95, Color(0.88, 0.7, 0.62))
	_prop(z, "dress_ore_cart", Vector2(1112, 886), 0.95, Color(0.9, 0.68, 0.56), 0.11)

static func _sp_production(z: Node2D, glow: Color, accent: Color) -> void:
	## The region's ONE set-piece caption (LAW 4: <= 4 world labels).
	_sign(z, Vector2(524, 344), "WAR ROOM", glow, 12)
	# The incident war room. Permanently staffed by nobody. THE focal: the
	# brightest thing in production is the room where production is discussed.
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
	_screen(z, Vector2(272, 248), accent, Vector2(1.9, 1.2), _depth(276, 56))
	_lamp(z, Vector2(272, 234), accent, 0.5, 1.9, false, 240.0)
	for i in 5:
		_led(z, Vector2(220.0 + float(i) * 26.0, 296.0), accent, 0.2 + float(i) * 0.21, _depth(296, 8))
	# THE BUTTON. Red. Domed. Guarded by a sign nobody reads.
	_prop(z, "struct_slab", Vector2(268, 800), 0.55, Color(0.58, 0.4, 0.42))
	_glow_rect(z, Vector2(268, 758), Vector2(28, 16), Color(1.0, 0.25, 0.25, 0.9), _depth(800, 62))
	_lamp(z, Vector2(268, 754), Color(1.0, 0.28, 0.28), 0.7, 1.6, true, 200.0)
	# The postmortem graveyard: action items, all still open.
	for i in 6:
		_prop(z, "struct_slab", Vector2(940.0 + float(i % 3) * 74.0, 784.0 + float(i / 3) * 66.0), 0.26, Color(0.52, 0.4, 0.42), (float(i) - 2.5) * 0.06)

	# Perimeter emitters installed after the last incident, which was not a
	# perimeter problem.
	_prop(z, "dress_laser_emitter", Vector2(1170, 300), 1.0, Color(0.86, 0.66, 0.68))
	_prop(z, "dress_laser_emitter", Vector2(1170, 664), 1.0, Color(0.86, 0.66, 0.68))

static func _sp_vault(z: Node2D, glow: Color, accent: Color) -> void:
	## The region's ONE set-piece caption (LAW 4: <= 4 world labels).
	_sign(z, Vector2(556, 320), "THE RESERVES", glow, 12)
	# Shelving rows of reserves, stacked to the ceiling and counted by nobody.
	for i in 4:
		var sp := Vector2(276.0 + float(i % 2) * 728.0, 250.0 + float(i / 2) * 104.0)
		_prop(z, "struct_slab", sp, 0.8, Color(0.86, 0.74, 0.44))
		for b in 4:
			_glow_rect(z, sp + Vector2(-26.0 + float(b) * 17.0, -22.0), Vector2(13, 7), Color(glow.r, glow.g, glow.b, 0.75), _depth(sp.y, 50.0))
		_light_pool(z, sp + Vector2(0, 46), 190.0, glow, 0.2)
	# The reserve pedestal: an orb of tokens under an arcane ring. THE focal.
	_prop(z, "struct_orb", Vector2(640, 244), 0.85, Color(1.0, 0.85, 0.34))
	for i in 20:
		var a := TAU * float(i) / 20.0
		_glow_rect(z, Vector2(640, 300) + Vector2(cos(a) * 128.0, sin(a) * 78.0), Vector2(11, 4), Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.5), -90, a)
	_lamp(z, Vector2(640, 226), glow, 1.25, 3.0, true, 380.0)
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
	# TWO beams, not seven. Six crossed lasers plus a violet centre line is a
	# lattice of overbright lines across the floor in a THIRD hue — HOSTILE red is
	# reserved for enemy tells (LAW 2), and the vault's hues are gold and violet.
	for k: float in [0.0, 1.0]:
		var bx := 236.0 + k * 416.0
		_laser(z, Vector2(bx, 662), Vector2(bx + 372.0, 662), VIOLET)
	# The balance console. It says "yes".
	_prop(z, "struct_console", Vector2(640, 800), 0.95, Color(0.9, 0.78, 0.46))
	_screen(z, Vector2(640, 778), accent, Vector2(1.4, 1.0), _depth(800, 56))

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

## Per-region theme. THREE HUES, and not one more (VISUAL_BIBLE_V2 LAW 2).
##
## "glow" is the region ACCENT — its one neon — and "accent" its WARM, the
## complementary source. Everything else in a region is desaturated toward grey:
## the floor and wall tints below are now near-neutral with a small cast, where
## before they were fully saturated hues at 0.6-0.78 that the tile textures were
## then multiplied by. That single change is most of what made the captured
## frames read as "eight hues per frame" — the GROUND was one of the hues.
##
## "signs" is empty in every region on purpose. LAW 4 caps world labels at four
## and LAW 10 sends the jokes into prop interactions; _build_region_signs draws
## the two wayfinding lines and each set-piece draws its own one caption. The
## thirty-one flavour strings this table and the set-pieces used to carry have
## been handed to the reactive-comedy owner, not deleted.
static func _region_theme(region_id: String) -> Dictionary:
	match region_id:
		"dependency_district":
			# ACCENT acid #A8FF3E, WARM crate orange #E08A3C.
			var structs := _clu(190, 620, "struct_crate", 3, 0.95, Color(0.62, 0.52, 0.40), 55)
			structs += _clu(1120, 604, "struct_crate", 3, 0.95, Color(0.60, 0.50, 0.38), 55)
			structs += _clu(206, 424, "struct_crate", 3, 0.9, Color(0.61, 0.51, 0.39), 50)
			structs += [{"t": "struct_tower", "p": Vector2(1160, 430), "s": 0.9, "m": Color(0.50, 0.55, 0.46)}]
			return {
				"floor": Color(0.50, 0.54, 0.48), "wall": Color(0.40, 0.44, 0.38), "tile_mul": 1.9,
				"glow": Color("#A8FF3E"), "accent": Color("#E08A3C"),
				"focal": Vector2(296, 286),  # the node_modules heap
				"lights": [Vector2(220, 620), Vector2(1120, 600)], "structs": structs, "signs": [],
			}
		"stackoverflow_ruins":
			# ACCENT dusty gold #E8C46B, WARM copper #C97B4A.
			var structs: Array = [
				{"t": "struct_arch", "p": Vector2(272, 604), "s": 1.0, "m": Color(0.58, 0.55, 0.48)},
				{"t": "struct_arch", "p": Vector2(1012, 620), "s": 0.95, "m": Color(0.54, 0.51, 0.45)},
			]
			structs += _clu(196, 792, "struct_slab", 2, 0.75, Color(0.55, 0.52, 0.46), 60)
			structs += _clu(1156, 780, "struct_slab", 2, 0.7, Color(0.51, 0.48, 0.43), 60)
			return {
				"floor": Color(0.56, 0.53, 0.46), "wall": Color(0.46, 0.43, 0.37), "tile_mul": 1.8,
				"glow": Color("#E8C46B"), "accent": Color("#C97B4A"),
				"focal": Vector2(640, 214),  # the Accepted Answer
				"lights": [Vector2(272, 600), Vector2(1012, 616)], "structs": structs, "signs": [],
			}
		"api_bazaar":
			# ACCENT magenta #FF2D95, WARM gold #FFD34D.
			var structs := _clu(200, 470, "struct_console", 2, 0.85, Color(0.56, 0.50, 0.55), 60)
			structs += _clu(1104, 462, "struct_console", 2, 0.85, Color(0.55, 0.49, 0.54), 60)
			structs += _clu(206, 636, "struct_crate", 3, 0.85, Color(0.58, 0.53, 0.42), 55)
			return {
				"floor": Color(0.50, 0.46, 0.50), "wall": Color(0.42, 0.37, 0.42), "tile_mul": 1.9,
				"glow": Color("#FF2D95"), "accent": Color("#FFD34D"),
				"focal": Vector2(640, 218),  # the centre stall
				"lights": [Vector2(200, 470), Vector2(1104, 462)], "structs": structs, "signs": [],
			}
		"cloud_district":
			# ACCENT sky #6BC7FF, WARM near-white #E8F4FF.
			var structs := _clu(196, 604, "struct_orb", 2, 0.7, Color(0.50, 0.55, 0.62), 60)
			structs += _clu(1116, 612, "struct_orb", 2, 0.65, Color(0.53, 0.57, 0.63), 60)
			structs += _clu(214, 800, "struct_tower", 2, 0.75, Color(0.47, 0.51, 0.58), 55)
			return {
				"floor": Color(0.48, 0.51, 0.57), "wall": Color(0.42, 0.45, 0.52), "tile_mul": 1.7,
				"glow": Color("#6BC7FF"), "accent": Color("#E8F4FF"),
				"focal": Vector2(640, 172),  # the server cathedral arch
				"lights": [Vector2(196, 604), Vector2(1116, 612)], "structs": structs, "signs": [],
			}
		"open_source_wildlands":
			# ACCENT leaf #58E07C, WARM lantern #C9A24A (v2 table: the old #3E9E5C
			# was a second green, i.e. one hue doing two jobs and neither of them
			# complementary).
			var structs := _clu(196, 604, "struct_crate", 3, 0.85, Color(0.46, 0.52, 0.44), 50)
			structs += _clu(1122, 610, "struct_slab", 2, 0.8, Color(0.44, 0.50, 0.44), 55)
			structs += _clu(1140, 300, "struct_crate", 2, 0.8, Color(0.45, 0.51, 0.43), 50)
			return {
				"floor": Color(0.46, 0.52, 0.46), "wall": Color(0.38, 0.44, 0.39), "tile_mul": 1.9,
				"glow": Color("#58E07C"), "accent": Color("#C9A24A"),
				"focal": Vector2(1058, 812),  # the maintainer's campfire
				"lights": [Vector2(196, 600), Vector2(1122, 606)], "structs": structs, "signs": [],
			}
		"corporate_enterprise":
			# ACCENT corp blue #4D7CFF, WARM glass grey #93A7C8.
			var structs: Array = []
			for gx in 2:
				structs.append({"t": "struct_slab", "p": Vector2(180.0 + float(gx) * 920.0, 470.0), "s": 0.75, "m": Color(0.48, 0.51, 0.57)})
				structs.append({"t": "struct_slab", "p": Vector2(180.0 + float(gx) * 920.0, 600.0), "s": 0.7, "m": Color(0.45, 0.48, 0.54)})
			return {
				"floor": Color(0.49, 0.51, 0.56), "wall": Color(0.42, 0.44, 0.50), "tile_mul": 1.7,
				"glow": Color("#4D7CFF"), "accent": Color("#93A7C8"),
				"focal": Vector2(1000, 742),  # the all-hands stage screen
				"lights": [Vector2(180, 470), Vector2(1100, 470)], "structs": structs, "signs": [],
			}
		"gpu_mines":
			# ACCENT ember #FF6B2D, WARM heat #FF3D2D.
			var structs := _clu(190, 604, "struct_tower", 2, 0.8, Color(0.54, 0.47, 0.44), 55)
			structs += _clu(1130, 596, "struct_tower", 2, 0.8, Color(0.52, 0.45, 0.42), 55)
			structs += _clu(196, 452, "struct_crate", 3, 0.8, Color(0.55, 0.48, 0.44), 50)
			return {
				"floor": Color(0.52, 0.46, 0.44), "wall": Color(0.44, 0.38, 0.36), "tile_mul": 1.8,
				"glow": Color("#FF6B2D"), "accent": Color("#FF3D2D"),
				"focal": Vector2(640, 812),  # the heat pit
				"lights": [Vector2(190, 600), Vector2(1130, 592)], "structs": structs, "signs": [],
			}
		"production":
			# ACCENT red #FF4757, WARM amber #FFB020.
			var structs: Array = [
				{"t": "struct_tower", "p": Vector2(186, 470), "s": 0.85, "m": Color(0.50, 0.44, 0.45)},
				{"t": "struct_tower", "p": Vector2(1104, 470), "s": 0.85, "m": Color(0.50, 0.44, 0.45)},
			]
			structs += _clu(206, 636, "struct_crate", 3, 0.85, Color(0.55, 0.49, 0.42), 55)
			return {
				"floor": Color(0.52, 0.46, 0.47), "wall": Color(0.44, 0.38, 0.39), "tile_mul": 1.9,
				"glow": Color("#FF4757"), "accent": Color("#FFB020"),
				"focal": Vector2(640, 262),  # the war room
				"lights": [Vector2(186, 466), Vector2(1104, 466)], "structs": structs, "signs": [],
			}
		"token_vault":
			# ACCENT gold #FFD34D, WARM violet #8B5CF6.
			var structs := _clu(192, 604, "struct_orb", 2, 0.6, Color(0.58, 0.53, 0.42), 55)
			structs += _clu(1124, 600, "struct_orb", 2, 0.6, Color(0.57, 0.52, 0.41), 55)
			structs += _clu(196, 442, "struct_orb", 1, 0.55, Color(0.58, 0.54, 0.44), 30)
			return {
				"floor": Color(0.53, 0.50, 0.44), "wall": Color(0.46, 0.43, 0.37), "tile_mul": 1.9,
				"glow": Color("#FFD34D"), "accent": VIOLET,
				"focal": Vector2(640, 244),  # the reserve pedestal
				"lights": [Vector2(192, 600), Vector2(1124, 596)], "structs": structs, "signs": [],
			}
		_:
			return {
				"floor": Color(0.50, 0.52, 0.54), "wall": Color(0.44, 0.46, 0.49), "tile_mul": 1.8,
				"glow": Color("#24F0DC"), "accent": Color("#FFB74A"),
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

## Boss arena: a swept pad with a poured rail around it. Deliberately
## NON-colliding — the space is the point, and a solid pillar where a boss spawns
## is a depenetration bug waiting to happen.
##
## ROUND 7 removed the twenty-six hatch marks, the stencilled cross with its four
## corner ticks, the ten kerb reflectors, the six bollards with lit caps and
## contact shadows, and the four approach chevrons: a hundred-odd primitives
## drawn on a floor to say "fight here", when a darker swept disc with one edge
## on it says the same thing and lets the boss be the thing you look at.
static func _arena(parent: Node2D, pos: Vector2, accent: Color, glow: Color) -> void:
	_floor_patch(parent, pos, 500.0, Color(accent.r, accent.g, accent.b), 0.07, -94)
	_floor_patch(parent, pos, 330.0, Color(0.014, 0.016, 0.03), 0.30, -93)
	var n := 30
	var pts: Array[Vector2] = []
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(pos + Vector2(cos(a) * 180.0, sin(a) * 108.0))
	for i in n:
		var a0: Vector2 = pts[i]
		var b0: Vector2 = pts[(i + 1) % n]
		var sg := b0 - a0
		var mid := (a0 + b0) * 0.5
		_rect(parent, mid, Vector2(sg.length() + 4.0, 4.0), Color(0, 0, 0, 0.40), -92, sg.angle())
	_light_pool(parent, pos, 400.0, glow, 0.10)

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

	# EIGHT tokens, PLACED. Not twenty-five scattered by an RNG that had already
	# given up and dropped them on the landing plaza (LAW 4: 6-10, intentional).
	#
	# Twenty-five coins is not twenty-five rewards, it is a carpet: the frames
	# show them lying in the walkway, inside the set-pieces, three deep next to
	# each other, each one bobbing and lit. Placed instead as a reading order — a
	# line the player follows along the artery, a small cluster at the set-piece
	# that is worth the detour, and a pair by the person you are meant to talk to.
	# Node type and group are untouched, so the waypoint and the tests find them.
	var token_types := _region_token_types(region_id)
	var spots := _token_spots(region_id, spawn)
	for i in spots.size():
		var t = token_scene.instantiate()
		t.token_type = token_types[i % token_types.size()]
		t.position = spots[i]
		# Same depth convention as the player and the NPCs. token_pickup.tscn
		# ships z_index 0, so a coin near set dressing drew UNDER it — and
		# "collect N tokens" is an objective, not decoration.
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

## Where a region's eight tokens lie. Deterministic (walk back in and the room is
## the room), on even integers (LAW 1), and composed rather than scattered:
##
##   * four strung along the walkway artery between the two doors, so following
##     the money and following the road are the same act,
##   * three clustered at the focal set-piece — the reward for the detour the
##     lighting is already inviting,
##   * one beside the region's NPC.
##
## Anything that lands inside solid cover, on top of the arrival plaza, or off
## the walkable interior is nudged rather than dropped: eight is a small enough
## number that losing one is a visible hole.
static func _token_spots(region_id: String, spawn: Vector2) -> Array[Vector2]:
	var w := float(REGION_SIZE.x * TILE_SIZE)
	var h := float(REGION_SIZE.y * TILE_SIZE)
	var seed_v := _region_seed(region_id)
	var theme := _region_theme(region_id)
	var focal: Vector2 = theme.get("focal", Vector2(w * 0.5, h * 0.35))
	var want: Array[Vector2] = []
	# The line along the road.
	for i in 4:
		var t := 0.22 + 0.18 * float(i)
		var x := 150.0 + (w - 300.0) * t
		var lift := 34.0 if i % 2 == 0 else -34.0
		want.append(Vector2(x, _band_y(x, w, h, seed_v) + lift))
	# The cluster at the set-piece, offset downhill of it so the coins sit on
	# floor rather than inside the prop's own silhouette.
	for i in 3:
		var a := TAU * (float(i) + 0.5) / 3.0
		want.append(focal + Vector2(cos(a) * 96.0, sin(a) * 54.0 + 96.0))
	# One by the person.
	var npcs := _region_npcs(region_id)
	if npcs.is_empty():
		want.append(Vector2(w * 0.5, h - 220.0))
	else:
		var np: Vector2 = npcs[0].pos
		want.append(np + Vector2(-110.0, 62.0))
	var out: Array[Vector2] = []
	for p: Vector2 in want:
		var q := Vector2(clampf(p.x, 140.0, w - 140.0), clampf(p.y, 170.0, h - 120.0))
		# Nudge off cover and off the player's own landing spot, on a short spiral
		# so the composed position is kept wherever it was already fine.
		for step in 12:
			if not _in_cover(q) and q.distance_to(spawn) > 96.0:
				break
			var a2 := float(step) * 1.9
			q += Vector2(cos(a2), sin(a2)) * 34.0
			q = Vector2(clampf(q.x, 140.0, w - 140.0), clampf(q.y, 170.0, h - 120.0))
		out.append(Vector2(round(q.x * 0.5) * 2.0, round(q.y * 0.5) * 2.0))
	return out

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
	#
	# LAW 2: this marker used to be a hardcoded pale cyan in EVERY region, which
	# put a fourth hue on the floor of nine rooms that do not own cyan — an acid
	# room, an ember room and a magenta room each got the same sky-blue chip. It
	# is the region's own ACCENT now (theme "glow" IS the LAW 2 accent column;
	# theme "accent" is the WARM), so a marker can never be an off-palette hue.
	var accent: Color = _region_theme(region_id).get("glow", Color(0.42, 0.82, 0.88))
	for entry in REGION_FLAVOR.get(region_id, []):
		var pr = _add_prop(props, interact_scene, entry[0], entry[1], entry[2])
		pr.one_shot = false
		var rect := pr.get_node_or_null("ColorRect")
		if rect:
			rect.color = Color(accent.r, accent.g, accent.b, 0.26)
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
