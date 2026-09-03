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

## The one global constant VISUAL_BIBLE_V2 LAW 2 allows outside a region's own
## three hues: TEXT_DIM, which ambient dust and every non-wayfinding caption is
## drawn in.
##
## WARM_KEY went with the NPC key light — round-11 critique (f), "portal disc +
## gate light pool + NPC pool + player pool = 4-5 sources". A region spends
## exactly ONE light of its own now (the set-piece's); the person in the room is
## found by their name tag and the waypoint chevron, not by a private spotlight.
const TEXT_DIM := Color("#7C8BB0")

## LAW 4: at most six PointLight2Ds are alive in a region. Counted here rather
## than trusted to forty call sites — this file has, at various times, lit every
## crate, every sign, every stall and every prop halo, and the frames show
## exactly that: nothing dark, therefore no hierarchy. Reset at the top of every
## build (`_use_layout`), because regions rebuild on every travel.
##
## ROUND 11 makes the real number ONE. The budget stays as the ceiling, but the
## only light this file may now spend is the focal lamp over the region's
## set-piece (see `_lamp`); the portal carries its own (region_portal.gd), the
## player carries his (player.gd) and the room's two wall fixtures are world.gd's.
const LIGHT_BUDGET := 6
static var _lights_used := 0

## One-time caches. Regions rebuild on every travel; textures are generated once
## and ShaderMaterials are shared wherever params are identical (bible rule) —
## except neon signs, whose unique seeds naturally get their own instances.
static var _radial_cache: Texture2D
static var _shadow_cache: Texture2D
static var _screen_cache: Dictionary = {}
static var _mat_cache: Dictionary = {}
static var _add_mat_cache: CanvasItemMaterial

## The GPU Mines' heat pit — the region's focal, its one motivated light and the
## anchor its token cluster is composed around, so it lives in one constant
## rather than in three files' worth of magic numbers. West of the spawn column
## on purpose (critique #3): at (640, 812) it sat under the ability bar.
##
## ROUND 13, critique #8: "a broad orange haze washing over the objective text at
## bottom-left". The orange RECT went in round 11; what the frame caught this time
## is the replacement — the pit's PointLight2D, at energy 0.9 and texture scale
## 6.0, which is a 192-unit radius of #FF6B2D centred at y 806. Measured on the
## capture, the floor at x 300..500 runs 50% brighter than the same tile at x 700,
## from y 700 all the way to the bottom wall, and the objective line is printed
## through the west edge of it.
##
## A light cannot be "small enough" while the thing it comes out of is standing in
## the bottom HUD band, so the pit leaves the band: at (420,570) with the light
## cut to energy 0.7 and scale 3.0 (a 96-unit radius) it reaches y 474..666 and
## stops 64 units short of the band. It is also, for the first time, IN the
## arrival frame — the mines' one motivated source is now a thing the player can
## see at the moment they land, which is what LAW 3 asks a focal light to be.
const GPU_PIT := Vector2(420, 570)

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

## LAW 1, enforced once instead of at ninety call sites: `rot` is ACCEPTED and
## IGNORED. Rotation breaks the pixel grid — a 2x sprite turned 0.2 rad is
## resampled, anti-aliased and stops being pixel art — and the frames are full of
## it: toppled monoliths, tilted crates, canted carts, spinning decals. Every
## caller still passes its angle (the parameter is cheaper to keep than forty
## edit sites) and every sprite now lands square on the grid.
static func _put(parent: Node2D, tex_name: String, pos: Vector2, z: int, scale: float = 1.0, mod: Color = Color.WHITE, _rot: float = 0.0) -> Sprite2D:
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
##
## THE BOTTOM KEEP-OUT LIVES HERE, once, for every decorative sprite in the file
## (round-13 critique #6). Twelve hand-composed props were legal by their anchor
## and illegal by their silhouette — a 0.6x slab at y 872 reaches 836, a 0.95x
## stall at 874 reaches 832, the wildlands graveyard's first row at 846 reaches
## 829 — and each of them was a shape read through the objective line. The height
## is known here and nowhere else, so this is the only place the rule can be
## enforced instead of re-derived at a hundred call sites.
static func _prop(parent: Node2D, tex_name: String, pos: Vector2, sc: float = 1.0, mod: Color = Color.WHITE, rot: float = 0.0, shadow: float = 1.0) -> Sprite2D:
	var t0 := _tex(tex_name)
	if t0:
		pos = _clear_low_band(pos, float(t0.get_height()) * 0.5 * sc)
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

## Filled rectangle centred on `center` (Control rects anchor from the top-left,
## which is never what a composition wants).
##
## `rot` is ACCEPTED and IGNORED, for the same reason as _put's: a rotated
## ColorRect is an anti-aliased quad sitting in a pixel-art world, and the
## captured frames read them exactly as what they are — "rotated, anti-aliased
## non-pixel quads in world space". Callers keep their angles; the composition
## stays on the grid.
static func _rect(parent: Node2D, center: Vector2, size: Vector2, col: Color, z: int, _rot: float = 0.0) -> ColorRect:
	var r := ColorRect.new()
	r.size = size
	r.pivot_offset = size * 0.5
	r.position = center - size * 0.5
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
## own artery baseline. Round 8 stopped DRAWING either of them (the value ramp,
## the material zoning, the lane lines, the chevron trails and the paved spurs
## are all gone); what the table now decides is where the arrival light pools and
## where the litter, the decals, the detail props and the tokens may fall — i.e.
## it composes the room rather than painting it.
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
## spawn (640, 480) with at least ~50px to spare. Round 8 stopped PAINTING it and
## made it the arrival light's footprint; round 11 deleted that light too
## (critique (f): the player carries his own), so what the plaza is now is a
## KEEP-OUT — the piece of floor the scatter passes leave clear so the player has
## room to stand up and look around. A plaza that does not contain the spawn
## drops him into a crate.
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
	# Same reason the layout and the cover list are adopted here: the portal
	# keep-out is module-level state, and a stale one would protect the doors of
	# the region you just walked out of.
	_use_portals(region_id)

## PORTAL KEEP-OUT — critique #7, "props placed inside the portal arch
## overlapping the swirl (a CRT, a crate, a filing cabinet, a rack, a globe)".
##
## A door is the one thing in a room the player must be able to read at a glance,
## and every region was scattering its perimeter cluster straight through one:
## the bazaar's consoles stand in the west arch, the vault's orbs in its own, the
## wildlands' crates in theirs. A 200x200 box centred on each door is off limits
## to set dressing; anything that lands in one is pushed out of it, and the
## scatter passes skip it outright.
const PORTAL_KEEP := 200.0
static var _portal_boxes: Array[Rect2] = []

static func _use_portals(region_id: String) -> void:
	_portal_boxes.clear()
	for pd in _region_portals(region_id):
		var pp: Vector2 = pd.pos
		_portal_boxes.append(Rect2(pp - Vector2(PORTAL_KEEP, PORTAL_KEEP) * 0.5,
			Vector2(PORTAL_KEEP, PORTAL_KEEP)))

static func _in_portal(p: Vector2) -> bool:
	for r in _portal_boxes:
		if r.has_point(p):
			return true
	return false

## Round-12 critique (f), "portal spill haloing onto crates (dependency)". The
## 200x200 box above is a keep-out for anything a PASS chooses — _build_structures
## runs every themed cluster through _clear_portal — but the hand-composed
## set-pieces place their crates by hand, and the node_modules heap spreads +/-70
## units from (296,286) straight into the Localhost door at (250,392). A crate is
## the worst possible neighbour for a portal: it is a flat lit box, so the door's
## own light (region_portal.gd, a file this one does not own) reads as a halo
## painted onto cargo rather than as a way out.
##
## 120 units, radial, because a door's light falls off radially and the box's
## corners are already 141 from its centre. Anything closer is simply not drawn:
## the heap is eight crates deep and losing the one nearest the door costs the
## composition nothing.
const PORTAL_CRATE_KEEP := 120.0

static func _crate_ok(p: Vector2) -> bool:
	for r in _portal_boxes:
		if p.distance_to(r.get_center()) < PORTAL_CRATE_KEEP:
			return false
	return true

## Push a position out of any portal box by the shortest move that still lands in
## the walkable interior — a door tucked against a side wall has only three ways
## out, and the naive "shortest axis" answer walks the prop into the masonry
## instead. Returns the position unchanged (snapped to the grid) when it is clear.
static func _clear_portal(p: Vector2) -> Vector2:
	var w := float(REGION_SIZE.x * TILE_SIZE)
	var h := float(REGION_SIZE.y * TILE_SIZE)
	var out := p
	for _pass in 2:
		var moved := false
		for r in _portal_boxes:
			if not r.has_point(out):
				continue
			var g := r.grow(26.0)
			var best := out
			var best_cost := 1.0e9
			for cand: Vector2 in [Vector2(g.position.x, out.y), Vector2(g.end.x, out.y),
					Vector2(out.x, g.position.y), Vector2(out.x, g.end.y)]:
				if cand.x < 120.0 or cand.x > w - 120.0 or cand.y < 150.0 or cand.y > h - 90.0:
					continue
				var cost := cand.distance_to(out)
				if cost < best_cost:
					best_cost = cost
					best = cand
			out = best
			moved = true
		if not moved:
			break
	return Vector2(round(out.x * 0.5) * 2.0, round(out.y * 0.5) * 2.0)

## THE ARRIVAL LANE — critique #3, "the region's focal prop spawns at the world
## position directly under the bottom-centre HUD at spawn".
##
## The player lands at (640,480) and the camera is already clamped there, so the
## ability bar, the toast lane and the controls footer permanently cover one
## strip of floor: roughly world x 524..756, y 690..960. Nine regions put their
## lit console, market table, heat pit or lockfile shrine in exactly that strip —
## the one piece of ground a player can never look at. Set-pieces are composed
## out of it (beside the spawn, never below it) and the scatters treat it as
## reserved.
const LANE := Rect2(524.0, 690.0, 232.0, 280.0)

static func _in_lane(p: Vector2) -> bool:
	return LANE.has_point(p)

## THE HUD KEEP-OUT — round-11 critiques #2, #6 and #9: "an enemy under the tk
## counter", "an enemy at the top touching the HP bars", "a flat dark-green bar
## with an acid cap under the region title", "four awnings across the entire top
## strip under all three HUD zones", "a flat navy box top-right".
##
## The arrival frame is not a matter of opinion: the player lands at (640,480),
## and since round 11 the camera is a zoom-0.5 Camera2D inside a 640x360 stage
## (pixel_stage.gd), i.e. 1280x720 WORLD units visible. The room is 1280x960, so
## the frame is exactly one room wide and the first frame of every visit shows
## world y 120..840 — and the HUD's three zones (token
## counter left, HP/Focus bars right, region name centre) are painted across the
## top ~70 world units of exactly that. Anything the builder puts up there is
## read THROUGH text for as long as the player stands still.
##
## One number, applied to every pass that CHOOSES a position (the detail scatter,
## the landmark spots, the floor decals and every enemy post). Hand-composed
## set-pieces are moved by hand, in their own functions. 244 rather than 212
## because a sprite is drawn centred on its point and an enemy body hangs about
## 32 units above its post.
const HUD_KEEP_Y := 244.0

## THE OTHER HALF OF IT — round-12 critique #3, systemic across nine of ten
## regions: "the spawn camera puts the bottom row of the room under the ability
## bar (Cloud ghost boss, SO Ruins beast, Vault eye turret, Corporate enemy, GPU
## bug + rack, Production crate + enemy, Wildlands maintainer, API reseller,
## Dependency maintainer)".
##
## The arrival frame is 720 world units tall and the player lands at h*0.5, so it
## shows y 120..840 of a 1280x960 room. Round 11 fixed the TOP of that band and
## left the bottom unowned — and the bottom is where MORE of the HUD lives: the
## objective line, the toast lane, the six ability slots and the controls footer
## are painted across the last 110 world units, y 730..840. Anything the builder
## puts there is read through text for as long as the player stands still, and a
## thing standing just BELOW the frame (a boss at y 862 is 128 units tall) shows
## the player its head and nothing else.
##
## So: the same rule, mirrored. spawn.y + 250 .. spawn.y + 360.
const HUD_KEEP_Y_LOW := 730.0
const HUD_KEEP_LOW_END := 840.0

## Where a position pushed out of the low band lands. UP is the default (the
## floor above the band is open in every region); DOWN is used when the position
## is already in the band's lower half, and it clears the band by enough that a
## 64-unit-tall body's head does not poke back into it.
const HUD_LOW_UP := 724.0
const HUD_LOW_DOWN := 856.0

## The two corner readouts, in world units: the token/credit counter top-left and
## the HP/Focus bars top-right, both inside the top 70 units of the arrival view.
## Subsumed by HUD_KEEP_Y (244 > 190) for a 1280x960 room, and written down
## anyway so the rule survives the next time somebody re-derives the strip.
const HUD_CORNER_Y := 190.0
const HUD_CORNER_W_L := 260.0
const HUD_CORNER_W_R := 300.0

static func _under_hud(p: Vector2) -> bool:
	return p.y < HUD_KEEP_Y

static func _below_hud(p: Vector2) -> bool:
	return p.y >= HUD_KEEP_Y_LOW and p.y <= HUD_KEEP_LOW_END

static func _in_hud_corner(p: Vector2) -> bool:
	if p.y > HUD_CORNER_Y:
		return false
	var w := float(REGION_SIZE.x * TILE_SIZE)
	return p.x <= HUD_CORNER_W_L or p.x >= w - HUD_CORNER_W_R

## The one predicate every CHOOSING pass asks. (_under_hud stays as its own
## function because a dozen call sites clamp against HUD_KEEP_Y directly.)
static func _in_hud_bands(p: Vector2) -> bool:
	return _under_hud(p) or _below_hud(p) or _in_hud_corner(p)

## Push a chosen position out of the arrival frame's HUD bands by the shortest
## VERTICAL move that stays in the walkable interior — vertical because both
## bands are full-width, so sliding sideways never leaves either of them.
static func _clear_hud_bands(p: Vector2) -> Vector2:
	var out := p
	if out.y < HUD_KEEP_Y:
		out.y = HUD_KEEP_Y
	elif out.y >= HUD_KEEP_Y_LOW and out.y <= HUD_KEEP_LOW_END:
		var h := float(REGION_SIZE.y * TILE_SIZE)
		var down_ok := HUD_LOW_DOWN <= h - 66.0
		var nearer_up := (out.y - HUD_KEEP_Y_LOW) <= (HUD_KEEP_LOW_END - out.y)
		out.y = HUD_LOW_UP if (nearer_up or not down_ok) else HUD_LOW_DOWN
	return Vector2(round(out.x * 0.5) * 2.0, round(out.y * 0.5) * 2.0)

## THE THIRD HALF OF IT — round-13 critique #6: "props and a boss arc clipped
## under the bottom HUD band at spawn (production red arc, corporate red-eyed
## robot, dependency AC units in both bottom corners)". Round 12's gate held for
## every ANCHOR in the file and the frames still showed art in the band, because
## an anchor is a point and a sprite is a box. The dependency/corporate AC units
## stand at y 884 — legally below the arrival frame — and are drawn at 1.45x from
## a 150px texture, so ninety units of them rise back into y 794..840.
##
## So the bottom rule is restated over a FOOTPRINT. `rise` is how far the art
## reaches ABOVE its anchor; the art occupies p.y - rise .. p.y, and none of that
## span may touch y 730..840.
static func _hits_low_band(p: Vector2, rise: float) -> bool:
	return p.y >= HUD_KEEP_Y_LOW and (p.y - rise) <= HUD_KEEP_LOW_END

## ...and the move that fixes it, for the passes that place rather than choose.
## DOWN by preference — everything this catches is already south of the plaza and
## belongs below the arrival frame — falling back to the band's north lip when a
## body that tall cannot fit between the band and the bottom wall.
static func _clear_low_band(p: Vector2, rise: float) -> Vector2:
	if not _hits_low_band(p, rise):
		return p
	var h := float(REGION_SIZE.y * TILE_SIZE)
	var down := HUD_KEEP_LOW_END + rise + 2.0
	var out := down if down <= h - 40.0 else HUD_LOW_UP
	return Vector2(p.x, round(out * 0.5) * 2.0)

## The four corner boxes of the arrival frame, as a footprint test. The top pair
## is the token counter (260x70) and the HP/Focus bars (300x70); the bottom pair
## is the objective line and the controls footer (320x110 each). `_in_hud_corner`
## already owns the top pair for anchors; this is the version a sprite asks.
const HUD_BOTTOM_CORNER_W := 320.0

static func _in_bottom_corner(p: Vector2, rise: float) -> bool:
	if not _hits_low_band(p, rise):
		return false
	var w := float(REGION_SIZE.x * TILE_SIZE)
	return p.x <= HUD_BOTTOM_CORNER_W or p.x >= w - HUD_BOTTOM_CORNER_W

## An NPC is the one thing that can only leave the low band UPWARD. npc.gd hangs
## the name tag at y-106..-86 and stacks idle barks above that, so a person moved
## BELOW the band prints their own label back inside it — which is exactly what
## the Wildlands maintainer (y 852, tag at 736) and the on-call engineer (y 848,
## tag at 732) do in the captured frames. y+17 is the heel of the sprite.
static func _npc_spot(p: Vector2) -> Vector2:
	var q := p
	if q.y < HUD_KEEP_Y + 40.0:
		q.y = HUD_KEEP_Y + 40.0
	elif q.y > HUD_KEEP_Y_LOW - 24.0:
		q.y = HUD_KEEP_Y_LOW - 24.0
	return Vector2(round(q.x * 0.5) * 2.0, round(q.y * 0.5) * 2.0)

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

## AMBIENT OCCLUSION along the walls, and the ONLY thing that varies a tile's
## value any more (round-8 critique #1).
##
## What was here: a three-zone brightness ramp that lifted the landing plaza by
## 18%, the walkway artery by 22% and dropped the perimeter by 34% — on top of a
## material zoning pass that gave the plaza a different, brighter TEXTURE again.
## Stacked, that stamped a hard-edged, stepped blob of floor roughly 40% brighter
## than its surroundings around the spawn of every region, in the same shape
## every time. It was the loudest thing in the frames and it was the ground
## shouting, which is the one thing LAW 6 says the ground may not do.
##
## The blob is gone; the light does the job instead (see the arrival pool in
## _build_region_lights). What is left here is the wall AO LAW 6 explicitly
## allows — a SMOOTH ramp, with no wobble and no dither, so it reads as the room
## getting darker toward its walls rather than as a shape drawn on the floor.
const AO_DEPTH := 150.0
const AO_MAX := 0.26

static func _floor_ao(p: Vector2, w: float, h: float) -> float:
	var e := minf(minf(p.x, w - p.x), minf(p.y - 46.0, h - p.y))
	if e >= AO_DEPTH:
		return 1.0
	var t := clampf(e / AO_DEPTH, 0.0, 1.0)
	return 1.0 - AO_MAX * (1.0 - t * t * (3.0 - 2.0 * t))

## ROUND 8 — the floor is ONE material again.
##
## LAW 6 is a sentence: a floor tile is a clean 32px material, the A/B variant
## differs by <= 6% in value, and the player must be able to read the ground at a
## glance. Round 7 kept a four-way MATERIAL zoning on top of that — plaza tiles,
## walkway deck tiles, perimeter tiles, field tiles — each with its own value
## multiplier, and the plaza's was tile_mul (1.7-1.9) against the field's 1.0.
## The result, in every single captured frame, was a stepped bright blob stamped
## around the player in the same shape from region to region.
##
## So: one material family per region, the A/B variant picked by CELL HASH ALONE
## at a 6% value step, a smooth wall AO, and nothing else. Where the room's
## "somewhere" is, is now said by the arrival light pool in _build_region_lights
## — which is what light is for, and what a floor is not.
##
## Deleted with the zoning: the chevron trails, the two lane lines and the paved
## spurs that used to be drawn from the plaza to every door (LAW 4 puts floor
## overlays at zero, and the critique reads a line from the portal to the player
## as the same "one room re-skinned" signature the zoning was). The waypoint
## chevron and the portal's own light are the wayfinding.
## ROUND 10 — the floor is the TILE ART, at the value the tile art was drawn at.
##
## What went with this edit, and why the frames measured 32-41/255 (void):
##   * the per-region FLOOR TINT. Every tile was multiplied by theme["floor"],
##     a 0.46-0.56 colour, i.e. the ground was globally darkened to half value
##     AND given a hue — two things LAW 6 forbids in one multiply. The tile art
##     now carries its own material and its own colour; the builder's job is to
##     put it down, not to grade it.
##   * `tile_mul` (1.7-2.2), the compensating BRIGHTENER on the legacy tile pair.
##     A darkener and a brightener stacked on the same pixel is how a floor ends
##     up with a value nobody authored.
##
## What is left is what LAW 6 asks for: the tile, an A/B variant 6% apart chosen
## by cell hash alone, and the wall AO. Nothing multiplies a floor tile below
## 0.92 except that AO, and the AO only reaches 150px from a wall.
static func _build_floor_themed(parent: Node2D, _theme: Dictionary, w: int, h: int, region_id: String) -> void:
	var floor_node := Node2D.new()
	floor_node.name = "Floor"
	parent.add_child(floor_node)
	floor_node.modulate = _floor_neutral(region_id)
	var suffix: String = REGION_TILE_MAP.get(region_id, "")
	# The region's ground proper (art agents supply these; everything is
	# exists()-guarded, with the older tile_<family> pair and then the neutral
	# tech_floor as the fallbacks, so a fresh checkout still gets a floor).
	var has_base := suffix != "" and ResourceLoader.exists(GEN + "floor_" + suffix + "_base.png")
	var has_alt := suffix != "" and ResourceLoader.exists(GEN + "floor_" + suffix + "_alt.png")
	var has_a := suffix != "" and ResourceLoader.exists(GEN + "tile_" + suffix + ".png")
	var has_b := suffix != "" and ResourceLoader.exists(GEN + "tile_" + suffix + "_b.png")
	for x in REGION_SIZE.x:
		for y in REGION_SIZE.y:
			var hv := _cell_hash(x, y)
			var p := Vector2(x * TILE_SIZE + TILE_SIZE * 0.5, y * TILE_SIZE + TILE_SIZE * 0.5)
			# Wall AO only. No zone ramp, no wear field, no per-tile jitter.
			var k := _floor_ao(p, float(w), float(h))
			# The A/B break: 6% and no more (LAW 6), chosen by the cell hash and
			# by nothing else — not by where the tile is in the room.
			var alt := (hv % 100) >= 62
			var ab := 1.06 if alt else 1.0
			var v := k * ab
			var tex_name := "tech_floor"
			if has_base:
				tex_name = "floor_" + suffix + "_base"
				if has_alt and alt:
					tex_name = "floor_" + suffix + "_alt"
			elif has_a or has_b:
				tex_name = "tile_" + suffix if has_a else "tile_" + suffix + "_b"
				if alt and has_b:
					tex_name = "tile_" + suffix + "_b"
			_put(floor_node, tex_name, p, -100, 1.0, Color(v, v, v))
	# What is left on top of the tiles, in full: at most three hand-placed decals.
	# That is the whole floor.
	_floor_decals(floor_node, region_id, w, h)

## THE VAULT'S FLOOR IS NOT MADE OF TOKENS — round-11 critique #7, "the floor
## uses the token GOLD hue so tokens lose contrast".
##
## GOLD #FFD34D is a GLOBAL constant (LAW 2): tokens and currency, and nothing
## else. LAW 6 then hands the Token Vault a gold-plate floor at #605028, so the
## one thing the region exists to make you pick up is drawn in the same hue as
## the ground it lies on, at a similar value. The tile art is the art agent's and
## it is a good tile; what is wrong is that this builder lays 300 of them down at
## full saturation.
##
## So the FLOOR CONTAINER is modulated toward neutral — 0.55 of its current
## saturation, i.e. its own tone lerped 45% toward its own grey. Derived once,
## by hand, from LAW 6's stated base tone so it is a constant and not a
## per-frame image read:
##
##   base   #605028                 -> (0.3765, 0.3137, 0.1569)
##   grey   0.299r + 0.587g + 0.114b ->  0.3146
##   target base.lerp(grey, 0.45)   -> (0.3486, 0.3141, 0.2279)
##   modul. target / base           -> (0.926,  1.001,  1.452)
##
## The blue channel is deliberately above 1.0: a multiply can only ever take
## colour away, and desaturating a warm tile means lifting its coldest channel
## rather than crushing its warmest. LAW 6's "never modulate a floor below 0.92"
## is respected on every channel.
static func _floor_neutral(region_id: String) -> Color:
	if region_id == "token_vault":
		return Color(0.926, 1.001, 1.452)
	return Color.WHITE

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
		var pos := Vector2(rng.randf_range(180, float(w) - 180), rng.randf_range(HUD_KEEP_Y, float(h) - 160))
		pos = Vector2(round(pos.x * 0.5) * 2.0, round(pos.y * 0.5) * 2.0)
		# Out of BOTH HUD bands (critique #3). A hairline crack under the ability
		# bar is a mark the player can never look at, and a decal is the one thing
		# in this file with no reason to be anywhere in particular.
		if _in_hud_bands(pos):
			continue
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
	# pool under everything. Round 7 cut that to one faint pool apiece; round 8
	# cuts the pool too. A console keeps its SCREEN, because a screen is a
	# motivated light source — nothing else here is.
	for s in theme.get("structs", []):
		var sc: float = float(s.get("s", 1.0))
		# Critique #7: the perimeter clusters are authored around the room's
		# corners and several of them land in a doorway. Nudged out, never
		# dropped — region_test.gd asserts every region still HAS structures.
		var sp: Vector2 = _clear_portal(s.p)
		var sm: Color = s.get("m", Color.WHITE)
		var spr := _prop(z, str(s.t), sp, sc, sm)
		if not spr:
			continue
		if s.t == "struct_console":
			_screen(z, sp + Vector2(0, -20.0 * sc), glow, Vector2(1.1, 1.0) * sc, spr.z_index + 1)
		# No pool. Round-8 critique #7: a puddle of light under EVERY structure is
		# a spot-halo on a prop by another name (LAW 4 forbids it in those words),
		# and eleven of them is the room lit to one flat value again. A structure
		# is grounded by its drop shadow; only motivated sources light the floor.

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
		# The y floor is the HUD keep-out, not the wall: a 0.48x prop dropped at
		# y 140 is a shape drawn behind the region title (critique #6). Since
		# round 12 the keep-out has a floor AND a ceiling (critique #3), so this
		# scatter can no longer drop a silhouette under the ability bar either.
		var p := Vector2(rng.randf_range(100, w - 100), rng.randf_range(HUD_KEEP_Y + 20.0, h - 90))
		p = Vector2(round(p.x * 0.5) * 2.0, round(p.y * 0.5) * 2.0)
		if p.distance_to(center) < 240.0:
			continue
		if _in_portal(p) or _in_lane(p) or _in_hud_bands(p):
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
static func _build_signature(parent: Node2D, region_id: String, theme: Dictionary, w: int, _h: int) -> void:
	var z := Node2D.new()
	z.name = "Signature"
	parent.add_child(z)
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
	#
	# THE FOUR TOP SPOTS ARE GONE (critique #6, "a flat navy box top-right"). At
	# y 200/214 a landmark is drawn at 1.45x in a near-black cool grey directly
	# under the HP bars — which is exactly what the capture read: not a building
	# on the horizon, a navy rectangle in the corner of the HUD. The remaining
	# pair sits at y 372, low enough that even a 150px texture at 1.7x clears the
	# strip.
	#
	# ROUND 12 retires the y 770 pair for the same reason one storey down
	# (critique #3): a 1.45x silhouette at h-190 stands in the bottom HUD band,
	# where the objective line and the ability bar are printed over it. The pair
	# at h-76 is BELOW the arrival frame entirely, which is where a landmark you
	# walk toward belongs.
	#
	# ROUND 13 retires that pair too, and this is the one pass where "below the
	# frame" was not enough. THIS IS critique #6's "AC units in both bottom
	# corners": (350, 884) and (930, 884) are legal POINTS, but what is put on
	# them is a 150px texture drawn at 1.45x, so ninety units of it rise back to
	# y 794 — inside the bottom band and inside its two corner boxes, in
	# dependency, corporate and production alike. No anchor in a 960-tall room
	# carries a silhouette that size clear of the band (it would need y >= 950,
	# i.e. inside the wall), so the answer is subtraction: the bottom pair is gone
	# and a mid pair at y 500 replaces it — open floor in every region, and clear
	# of both bands by 250 units either way.
	var spots: Array[Vector2] = [
		Vector2(126.0, 372.0), Vector2(float(w) - 126.0, 372.0),
		Vector2(126.0, 620.0), Vector2(float(w) - 126.0, 620.0),
		Vector2(126.0, 500.0), Vector2(float(w) - 126.0, 500.0),
	]
	var posts := _region_enemy_posts(region_id)
	var focal: Vector2 = theme.get("focal", Vector2.ZERO)
	var placed := 0
	for i in spots.size():
		if placed >= 2:
			break
		var lp: Vector2 = spots[i]
		# 110 is the tallest half-silhouette this pass can draw (a 150px texture
		# at 1.45x), so the footprint test is asked with that rather than with the
		# actual one: a spot that only works for the SHORT half of the vocabulary
		# is a spot that fails the day the seed picks the tower.
		if _in_cover(lp) or _in_hud_bands(lp) or _hits_low_band(lp, 110.0) \
				or _in_bottom_corner(lp, 110.0):
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
		# A 1.45x landmark in a doorway, or under the ability bar, is the same
		# defect as a crate there one scale up (critiques #3 and #7).
		if _in_lane(lp) or _in_portal(lp):
			clear = false
		for sd in theme.get("structs", []):
			var sv: Vector2 = sd.p
			if lp.distance_to(sv) < 150.0:
				clear = false
		if not clear:
			continue
		var hv2 := _cell_hash(i * 617, seed_v + 29)
		# No pool. A landmark is a SILHOUETTE — it is the shape against the far
		# wall that gives the eye a scale ladder, and a 250px accent puddle under
		# it is a light with nothing to be coming from (critique (f)).
		_prop(z, str(vocab[hv2 % vocab.size()]), lp, 1.45 + float(hv2 % 25) / 100.0,
			Color(0.30, 0.32, 0.38), (float(hv2 % 13) - 6.0) * 0.012)
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

## The ceiling fixtures, and NOTHING ELSE.
##
## ROUND 11, critique (f): "portal disc + gate light pool + NPC pool + player
## pool = 4-5 sources". A room has one reading order or it has none, and this
## function was the biggest single contributor to "none":
##
##   * THE ARRIVAL POOL — a 640px puddle plus a real PointLight2D parked on the
##     player's landing spot in every region. The player carries his own light
##     (player.gd), so this was a second, larger, brighter copy of it, and the
##     frames show it as the one unmissable feature of every arrival: a bright
##     oval with the character standing in the middle of it.
##   * TWO CEILING TUBES with a real light on one and a 360px pool under each,
##     lighting the top strip of the room where the HUD already is.
##   * A 280px POOL ON EVERY THEME ANCHOR — two per region, motivated by nothing
##     at all; they are coordinates in a table.
##
## What is left is the hardware: two dark housings with an unlit tube face, the
## same call the flat's exit fixture already makes (localhost_builder). A light
## fitting is part of a room whether or not it is switched on, and this one is
## not — the region's single light is the focal lamp over its set-piece.
static func _build_region_lights(parent: Node2D, theme: Dictionary, w: int, _h: int) -> void:
	var z := Node2D.new()
	z.name = "Lighting"
	parent.add_child(z)
	var glow: Color = theme.get("glow", Color(0.6, 0.8, 1.0))
	for i in 2:
		var fx := 330.0 + float(i) * (w - 660.0)
		_rect(z, Vector2(fx, 66.0), Vector2(58, 12), Color(0.05, 0.055, 0.085, 0.95), -54)
		# The tube face, dark: a dim reflection of the region's own neon in cold
		# glass, at 14% alpha. LAW 3 gives the frame five bright things and a
		# service fitting on the back wall is not one of them.
		_rect(z, Vector2(fx, 68.0), Vector2(46, 4), Color(glow.r, glow.g, glow.b, 0.14), -53)

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
## ROUND 8: that threshold is now a SELECTOR and nothing more. "One focal lamp is
## allowed past 1.0" is revoked — every light in the game is capped at 0.9 by
## _add_light — so a set-piece lamp asking for 1.25 gets a real light AT 0.9, the
## same energy as everything else. What still makes it focal is that it is the
## only real light in its half of the room, which is how focus is supposed to be
## bought.
##
## ROUND 11 finishes the job (critique (f)): a request BELOW focal energy now
## draws nothing at all — not even its puddle. Round 8 kept the puddles on the
## grounds that "the puddle was always the part doing the work", and the frames
## answered that: a room with fifteen puddles in it is a room lit to one flat
## value, exactly as a room with fifteen lights was. The stalls, the shrine, the
## shack, the ore carts, the arcane circles, the depot, the install bay, the
## lockfile and the cooling towers have all had their call deleted outright; this
## guard is what stops the next one being added back.
##
## The one lamp that survives per region is the one over its set-piece, and the
## region's other light sources belong to other files: the portal's own light,
## the player's carried light and world.gd's two wall fixtures.
static func _lamp(parent: Node2D, pos: Vector2, col: Color, energy: float, scale: float, flicker: bool = false, pool: float = 240.0) -> PointLight2D:
	if energy < 1.0:
		return null
	var l := _add_light(parent, pos, col, energy, scale, flicker)
	if pool > 0.0:
		_light_pool(parent, pos + Vector2(0, 26), pool, col, 0.20)
	return l

## Round-8 critique #7, "props outshine the player": every pool is capped on the
## way in. Forty call sites asking for 0.26-0.34 apiece, additively, over a dark
## floor, is how a room ends up with no value below "lit" in it — and the player
## is the one thing that then has nothing left to be brighter than.
const POOL_MAX := 0.22

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
##
## ROUND 12, critique #8: the chip's COLOUR is now capped too. Every caller
## passes the region's `glow` or `accent`, and in the GPU Mines those are ember
## #FF6B2D and heat #FF3D2D — so six racks and three ore carts were wearing
## twenty-one saturated red pips in a region whose enemies signal with exactly
## that hue (LAW 7: "exactly one red tell", and it belongs to the enemy). A status
## chip is desaturated toward its own grey and capped at 60% value, which is what
## LAW 3 allows anything that is not one of the frame's five bright things.
static func _led(parent: Node2D, pos: Vector2, color: Color, _phase: float, z: int) -> void:
	_glow_rect(parent, pos, Vector2(3, 2), _dull(color, 0.35, 0.60), z)

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

## THE NEON TUBE TEXTURE IS GONE, with the two lit ceiling fixtures that were
## this file's only callers (round-11 critique (f)). Nothing in a region emits
## from the back wall any more, so nothing needs an overbright core row baked
## into a texture to survive neon_flicker.gdshader's vertex-COLOR replacement.

## Small emissive screen face (gradient + faint code lines) for crt_monitor —
## color baked into the texture because the crt shader replaces vertex COLOR, so
## a modulate would not survive it.
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
				# The code lines lift the ROW; they may not lift the CEILING.
				# `lightened(0.25)` moved every channel a quarter of the way to
				# WHITE, so a screen the caller had carefully baked at 60% value
				# had its brightest pixel at 0.70 in a fully saturated hue — which
				# is precisely how the war room came to read as a lit red altar
				# under the region title (round-11 critique #10). Capped at the
				# colour it was handed: brighter than the field, never brighter
				# than the screen is allowed to be.
				c = Color(minf(c.r + 0.05, col.r), minf(c.g + 0.05, col.g), minf(c.b + 0.05, col.b), 1.0)
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	_screen_cache[key] = tex
	return tex

## A lit screen face. LAW 3: at rest, everything that is not one of the five
## bright things sits at or below 60% value — and the round-9 frames counted
## fifteen blue screens and bars in the corporate frame, three near-white red
## panels along the top of production, an amber podium and a 350px lit pond.
##
## So the value is baked in at `value` and glow_boost drops from 1.15 to 1.0: the
## shader's scanline/flicker/roll still play, but their product can no longer
## push a screen past the bloom threshold. A screen is a MOTIVATED SOURCE the
## room is lit by, not the brightest object in the frame — the lamp above the
## focal set-piece is what makes it focal.
##
## ROUND 11, critique #10 ("the SVP's saturated blue monitor glows at rest"): the
## default drops from 0.6 to 0.5 and 0.6 becomes the hard ceiling rather than the
## house style. Two things were stacking on top of the baked value — _screen_tex's
## code lines (fixed above) and sheer AREA, since the stage screen is 104x44 world
## units of one saturated hue. A big screen at 0.5 reads as a lit screen; a big
## screen at 0.6 reads as a light.
static func _screen(parent: Node2D, pos: Vector2, col: Color, sc: Vector2, z: int, value: float = 0.5) -> Sprite2D:
	var v := clampf(value, 0.0, 0.6)
	var scr := Sprite2D.new()
	scr.texture = _screen_tex(Color(col.r * v, col.g * v, col.b * v))
	var crt := _shader_mat("crt_monitor", {"glow_boost": 1.0})
	if crt:
		scr.material = crt
	scr.position = pos
	scr.scale = sc
	scr.z_index = z
	parent.add_child(scr)
	return scr

## The same face, switched OFF: dark glass with one dim reflection line. Critique
## #9 asks corporate for four lit screens and dark glass everywhere else, and a
## dead monitor is a shape a viewer reads instantly — it is what a screen looks
## like when nobody is at the desk, which is the joke the cubicle farm is making.
static func _dark_glass(parent: Node2D, pos: Vector2, sc: Vector2, z: int) -> void:
	var w := 40.0 * sc.x
	var h := 26.0 * sc.y
	_rect(parent, pos, Vector2(w, h), Color(0.055, 0.06, 0.085, 0.96), z)
	_rect(parent, pos + Vector2(0.0, -h * 0.28), Vector2(w * 0.72, 2.0), Color(0.20, 0.22, 0.28, 0.5), z + 1)

## THE WALL AO STRIP IS GONE, and _floor_ao is the only ambient occlusion left.
##
## LAW 6 caps wall AO at 26% within 150px of a wall. There were TWO passes doing
## it: the smooth per-tile ramp in _floor_ao (26% at the wall, fading out over
## 150px) and, on top of it, four stretched decal_ao_edge sprites at 0.6 alpha —
## which alone took the boards within ~46px of a wall down by 60%, and stacked
## with the ramp by nearly three quarters. That is the "void" the pass-2
## measurements found around the edge of every room, and it is also a rotated
## sprite (LAW 1). One AO, in one place, at the value the law names.

# --- label placement ------------------------------------------------------

## Boxes owned by nodes this builder does not draw the text for: the portal's
## destination plate and its vortex, the NPC name tag and the NPC's own body,
## and the arrival plaza. Reserved before any sign is placed, so signs get out of
## THEIR way rather than the other way round.
static func _reserve_labels(region_id: String, w: int, h: int) -> void:
	WorldLabel.begin(Rect2(0.0, 0.0, float(w), float(h)))
	for pd in _region_portals(region_id):
		var pp: Vector2 = pd.pos
		# ONE box, 260x220, centred on the door (round-8 critique #9). The old
		# pair — a 176x44 plate box plus a 200x200 body box, both hung ABOVE
		# centre — left the portal's own destination label (which region_portal.gd
		# draws BELOW the disc, at +64..+90) and the guidance chevron's column
		# unprotected, and the frames show captions landing on both.
		WorldLabel.reserve(Rect2(pp + Vector2(-130, -110), Vector2(260, 220)))
	for npc_data in _region_npcs(region_id):
		var np: Vector2 = npc_data.pos
		# The nameplate box AND the bark bubbles stacked above it. npc.gd
		# measures its own font and places the plate at y -106..-86, with idle
		# barks rising from -114 to about -175 and up to ~330px wide; a sign
		# landing anywhere in that column would be talked over all night.
		# 360x150 since round 8: the frames show the name tag clipping captions
		# at both ends of a 340px box.
		WorldLabel.reserve(Rect2(np + Vector2(-180, -210), Vector2(360, 150)))
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
## What is left, per region: the set-piece caption (placed by _sp_*) and one EXIT
## toward the onward door. TWO — because the room's other two slots are spent by
## nodes this builder does not draw: the NPC's name tag and the portal's
## destination plate (see the note at the foot of this function).
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
		# OUTSIDE the portal's reserved 260x220 box (critique #9): 150px to the side
		# and 96 up put the arrow INSIDE it, so the ladder had to displace the one
		# caption in the room that must never move. 210 and 150 clear the box on both
		# axes, with room for the 6px growth _colliders adds.
		# ...and BELOW a door cut into the top wall (the vault's way home is at
		# y 96), or the clamp drags the arrow up into the wall band instead.
		var lift := -150.0 if dp.y > 300.0 else 170.0
		var at := Vector2(dp.x + side * 210.0, dp.y + lift)
		_sign(z, Vector2(round(at.x * 0.5) * 2.0, round(at.y * 0.5) * 2.0),
			"EXIT \u2192" if side < 0.0 else "\u2190 EXIT", accent, 13, true)
	# THE "talk ->" HINT IS GONE (critique #6: "5-7 world labels per room, budget
	# <= 4"). Count what a player actually reads in one of these rooms: that hint,
	# the EXIT arrow, the set-piece caption, the NPC's own name tag, the portal's
	# destination plate and the guidance line. Six, for four slots — and this is
	# the one of them that says what two other elements already say, since the
	# person stands under their own name in the warmest pool of light in the room
	# and the waypoint chevron is pointing at them. The builder draws TWO labels a
	# region now (the door and the landmark), which leaves the room's budget to
	# the name tag and the destination plate.

## Region-specific atmosphere. LAW 5 allows ONE region to keep one atmosphere
## shader "if it is subtle enough that a viewer would not name it" — and after
## round 8, NO region spends it. The vault's gold code-rain was the last one, and
## a cold viewer named it immediately: forty-odd tan rectangles at random sizes
## and positions, scrolling over the floor. What is left in here is one light:
## the mines' heat pit, which is a motivated source and not a filter.
static func _build_region_fx(parent: Node2D, region_id: String, _theme: Dictionary, _w: int, _h: int) -> void:
	match region_id:
		"gpu_mines":
			# The heat shimmer lives in postfx_layer.gd, not here. This is the
			# mines' focal light: the heat pit, and the one bright thing in the
			# room (LAW 3, item 4 — a motivated source). It follows GPU_PIT, so
			# the light and the hole it comes out of can never drift apart.
			_add_light(parent, GPU_PIT, Color("#FF6B2D"), 0.7, 3.0, true)
		_:
			# The vault's gold code-rain is gone too. Under the corrected exposure
			# it is not the subtle wash LAW 5 permits one region to keep — it is
			# forty-odd tan rectangles at random sizes and positions scrolling over
			# the whole floor, which is precisely what critique #6 describes. The
			# vault keeps the single ambient dust layer every region has and
			# nothing else.
			pass

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

## Framed doorway around a portal: an arch behind it and two unlit bollards.
##
## ROUND 11, critique (f): the last piece of light here is gone too. region_portal.gd
## already draws the disc AND lights it in the destination's hue; a 260px accent
## wash on the floor underneath was a second, wider, unattributable source around
## every door in the game — two per region, and the critique counts them first
## ("portal disc + gate light pool"). The arch is what makes the door a DOORWAY.
static func _gate(parent: Node2D, pos: Vector2, col: Color, w: int, h: int) -> void:
	var inward := signf(float(w) * 0.5 - pos.x)
	_put(parent, "struct_arch", pos + Vector2(0, -10), -20, 1.15, Color(0.34, 0.36, 0.44))
	for k: float in [1.0, -1.0]:
		var bp := pos + Vector2(inward * 78.0, k * 74.0)
		if pos.y < float(h) * 0.25:
			bp = pos + Vector2(k * 78.0, 66.0)
		_rect(parent, bp, Vector2(10, 26), Color(0.05, 0.055, 0.09, 0.95), _depth(bp.y, 13.0))
		_glow_rect(parent, bp + Vector2(0, -14), Vector2(6, 4), Color(col.r, col.g, col.b, 0.55), _depth(bp.y, 14.0))

## Stacked crate heap with a collapsing silhouette. Any crate that lands inside a
## doorway's light is dropped rather than nudged (critique (f)) — the heap is
## eight deep and its silhouette does not depend on any one box.
static func _heap(parent: Node2D, pos: Vector2, col: Color, n: int, sc: float, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	for i in n:
		var t := float(i) / maxf(1.0, float(n - 1))
		var p := pos + Vector2(rng.randf_range(-1.0, 1.0) * 70.0 * (1.0 - t * 0.6), -t * 62.0 + rng.randf_range(-6, 6))
		if not _crate_ok(p):
			continue
		var s := sc * (1.0 - t * 0.28)
		var v := 1.0 - t * 0.22
		_prop(parent, "struct_crate", p, s, Color(col.r * v, col.g * v, col.b * v), rng.randf_range(-0.16, 0.16))

## Market stall: canopy, counter, goods. The API Bazaar's unit.
##
## ROUND 11, critique #2 — the worst frame in the set, at 3.5: "7.3% of the frame
## is saturated magenta: four full-value awnings across the entire top strip under
## all three HUD zones". Three things were true of the old stall and all three are
## fixed here:
##
##   * the awning was SIX FLAT RECTS in the region's two most saturated hues at
##     0.7 value and 0.95 alpha — 150 world units of pure magenta and gold per
##     stall, with four stalls in the room. It is the drawn `dress_awning` prop
##     now, tinted at 40% desaturation and capped at 60% value (_dull), which is
##     what LAW 3 allows anything that is not one of the five bright things. The
##     stripe idea survives: the prop is a scalloped, striped canopy. The rects
##     stay only as the ungenerated-checkout fallback, at the same dulled tint.
##   * it carried a 230px pool AND a lamp of its own (critique (f)),
##   * and the goods each carried an additive chip at 0.9 alpha; a counter of
##     five is five more emissive marks per stall, which is not what LAW 7's "one
##     emissive pixel per light source" means.
static func _stall(parent: Node2D, pos: Vector2, awning: Color, goods: Color, seed_v: int, canopied: bool = true) -> void:
	var zi := _depth(pos.y, 46.0)
	# The stock either side of the counter, dropped rather than nudged when the
	# pitch stands close to a doorway (critique (f)).
	var crate_l := pos + Vector2(-46.0, 10.0)
	var crate_r := pos + Vector2(46.0, 10.0)
	if _crate_ok(crate_l):
		_prop(parent, "struct_crate", crate_l, 0.85, Color(0.62, 0.5, 0.42))
	if _crate_ok(crate_r):
		_prop(parent, "struct_crate", crate_r, 0.85, Color(0.58, 0.46, 0.4))
	_drop_shadow(parent, pos + Vector2(0, 14), 165.0, zi - 1, 0.38)
	_rect(parent, pos, Vector2(150, 16), Color(0.24, 0.2, 0.26), zi)          # counter top
	_rect(parent, pos + Vector2(0, -7), Vector2(150, 3), Color(0.4, 0.36, 0.44), zi + 1)
	# The canopy: the drawn prop, desaturated 40% and capped at 60% value.
	#
	# `canopied` is false for the reseller's pitch, and for a reason the frame
	# shows plainly: the stallholder stands BEHIND his counter at (1088,782), the
	# canopy hangs at y 712..784 with the counter's y-sorted z, and so the shady
	# API reseller is permanently wearing his own awning. One canopy in the room,
	# over the one pitch nobody is standing in.
	if canopied:
		var canopy := _dull(awning, 0.40, 0.60)
		if not _put(parent, "dress_awning", pos + Vector2(0, -58), zi + 2, 1.0, canopy):
			var stripe := _dull(goods, 0.40, 0.60)
			for i in 6:
				var c: Color = canopy if i % 2 == 0 else stripe
				_rect(parent, pos + Vector2(-62.0 + float(i) * 25.0, -54), Vector2(25, 22), Color(c.r, c.g, c.b, 0.95), zi + 2)
			_rect(parent, pos + Vector2(0, -42), Vector2(154, 4), Color(0.1, 0.09, 0.13), zi + 3)
	# Goods on the counter: crates of API keys, lit BY the market, not lighting it.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	for i in 5:
		var gp := pos + Vector2(-58.0 + float(i) * 29.0, -16.0 + rng.randf_range(-3, 3))
		_rect(parent, gp, Vector2(13, 13), Color(goods.r * 0.5, goods.g * 0.5, goods.b * 0.5), zi + 2)

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
	# ONE status chip (LAW 7: one emissive pixel per light source on a sprite),
	# not five in two hues plus a vent bar plus the puddle it threw. Six racks in
	# a room made that thirty-six emissive marks and six halos.
	_led(parent, pos + Vector2(-10.0, -36.0), hot, phase, zi + 1)

## Cubicle: two glass partitions, a desk, and a monitor nobody is behind — dark,
## unless this is one of the region's few lit faces (critique #9).
static func _cubicle(parent: Node2D, pos: Vector2, col: Color, screen_col: Color, lit: bool = true) -> void:
	var zi := _depth(pos.y, 40.0)
	_prop(parent, "struct_slab", pos + Vector2(-56, -8), 0.55, col, 0.0, 0.6)
	_prop(parent, "struct_slab", pos + Vector2(0, -40), 0.55, Color(col.r * 0.9, col.g * 0.9, col.b * 0.95), 0.0, 0.6)
	_drop_shadow(parent, pos + Vector2(8, 32), 96.0, zi - 1, 0.34)
	_rect(parent, pos + Vector2(8, 18), Vector2(84, 26), Color(0.2, 0.22, 0.3), zi)
	_rect(parent, pos + Vector2(8, 7), Vector2(84, 3), Color(0.34, 0.37, 0.48), zi + 1)
	# The screen is the light. The 140px puddle it used to throw on the desk was
	# a monitor spill halo, seven of them per corporate frame (critique #7).
	if lit:
		_screen(parent, pos + Vector2(8, 4), screen_col, Vector2(0.8, 0.7), zi + 2)
	else:
		_dark_glass(parent, pos + Vector2(8, 4), Vector2(0.8, 0.7), zi + 2)

## Pilgrim shrine: a kneeling stone in a ring of guttering candles. People come
## here to ask a question that was answered in 2011 and closed in 2012.
static func _shrine(parent: Node2D, pos: Vector2, col: Color) -> void:
	_floor_patch(parent, pos, 270.0, col, 0.13, -94)
	_prop(parent, "struct_slab", pos + Vector2(0, -10), 0.42, Color(0.66, 0.6, 0.5))
	# SIX candles, and their wax is 60% value like every other prop (LAW 3). Nine
	# near-white sticks each with a 0.9-alpha additive flame is a ring of bright
	# marks that out-reads the person standing next to it (critique #7).
	for i in 6:
		var a := TAU * float(i) / 6.0
		var cp := pos + Vector2(cos(a) * 106.0, sin(a) * 62.0)
		_rect(parent, cp, Vector2(6, 13), Color(0.52, 0.49, 0.42), _depth(cp.y, 7.0))
		_glow_rect(parent, cp + Vector2(0, -10), Vector2(3, 4), Color(1.0, 0.72, 0.3, 0.55), _depth(cp.y, 9.0))
	# The 250px pool and the lamp are gone (critique (f)): six candle flames ARE
	# the shrine's light, and the ruins already spend their one lamp on the
	# Accepted Answer.

## THE COOLING POND IS GONE — round-11 critique #4, "a flat dark-blue quad with
## faint light lines (a placeholder pool/screen)".
##
## Round 9 halved every emissive in it; the cold read of the corrected frame is
## that halving was never the problem. A 252x118 rectangle of flat navy laid on
## the floor with seven horizontal bars across it does not read as WATER at any
## brightness — it reads as an unfinished asset, which is the single loudest
## "AI slop" signal a frame can carry. Water needs a material, and nobody has
## drawn one; the Cloud District has a cathedral, an altar, six racks and a
## cooling tower to say what it is.

## Mine rails. They go from one end of the room to the other end of the room.
static func _rails(parent: Node2D, y: float, x0: float, x1: float) -> void:
	for k: float in [1.0, -1.0]:
		_rect(parent, Vector2((x0 + x1) * 0.5, y + k * 10.0), Vector2(x1 - x0, 3.0), Color(0.36, 0.31, 0.28, 0.9), -90)
	for i in int((x1 - x0) / 34.0):
		_rect(parent, Vector2(x0 + float(i) * 34.0 + 17.0, y), Vector2(9.0, 28.0), Color(0.1, 0.08, 0.07, 0.85), -91)

## Ore cart, loaded with compute nobody has been allocated.
##
## ROUND 12, critique #8: "conveyor units carry five hostile-red LEDs each (15 red
## pips)". They did — a row of five 9x6 additive chips at 0.75 alpha in the
## region's hottest hue, on three carts, in the one region whose ACCENT and WARM
## are both red. Fifteen red marks in a frame is fifteen enemy tells that are not
## enemies, and LAW 7 gives a light source ONE emissive pixel.
##
## So: one chip, dulled by _led to <= 60% value, and the load itself is a dark
## mass with a lit top edge instead of a row of lamps. `hot` is still consumed —
## the cart is warm, it is just not signalling.
static func _cart(parent: Node2D, pos: Vector2, hot: Color, tilt: float) -> void:
	var zi := _depth(pos.y, 26.0)
	_drop_shadow(parent, pos + Vector2(0, 20), 88.0, zi - 1, 0.42)
	_rect(parent, pos, Vector2(76, 42), Color(0.24, 0.2, 0.2), zi, tilt)
	_rect(parent, pos + Vector2(0, -19), Vector2(76, 6), Color(0.42, 0.35, 0.32), zi + 1, tilt)
	# The load: unlit ore, three tones, sitting in the tub.
	_rect(parent, pos + Vector2(0, -22), Vector2(58, 8), Color(0.20, 0.17, 0.16), zi + 2, tilt)
	_rect(parent, pos + Vector2(0, -25), Vector2(50, 2), Color(0.30, 0.25, 0.23), zi + 3, tilt)
	# ONE status chip, on the cart's own body.
	_led(parent, pos + Vector2(-26.0, -22.0), hot, 0.0, zi + 4)
	for k: float in [1.0, -1.0]:
		_rect(parent, pos + Vector2(k * 27.0, 21.0), Vector2(15, 15), Color(0.12, 0.1, 0.1), zi + 1)

## Incident whiteboard: a board, a tray, and the same four boxes and arrows every
## incident produces before anybody has looked at a log.
static func _whiteboard(parent: Node2D, pos: Vector2, _accent: Color, rot: float) -> void:
	var zi := _depth(pos.y, 46.0)
	_drop_shadow(parent, pos + Vector2(0, 46), 156.0, zi - 2, 0.4)
	# LAW 3: everything that is not one of the five bright things is <= 60% value.
	# The board was painted at 0.74-0.84 — a near-white rectangle 146px across —
	# and the production frame has two of them flanking the war room, brighter
	# than the player standing in front of them (critique #7).
	_rect(parent, pos, Vector2(152, 94), Color(0.10, 0.11, 0.15), zi - 1, rot)
	# 0.32, down from 0.44 (critique #9, "2 pale boards"): a 146px near-grey
	# rectangle either side of the war room still out-read the player standing in
	# front of it. A whiteboard is lit BY the room; it does not light the room.
	_rect(parent, pos, Vector2(146, 88), Color(0.32, 0.34, 0.38), zi, rot)
	for i in 3:
		_rect(parent, pos + Vector2(-44.0 + float(i) * 44.0, -18.0), Vector2(30, 18), Color(0.16, 0.19, 0.28, 0.85), zi + 1, rot)
		if i < 2:
			_rect(parent, pos + Vector2(-22.0 + float(i) * 44.0, -18.0), Vector2(16, 2), Color(0.45, 0.16, 0.19, 0.9), zi + 1, rot)
	for i in 4:
		_rect(parent, pos + Vector2(-30.0 + float(i % 2) * 46.0, 12.0 + float(i / 2) * 13.0), Vector2(56, 3), Color(0.20, 0.22, 0.30, 0.7), zi + 1, rot)
	_rect(parent, pos + Vector2(0, 47), Vector2(150, 7), Color(0.15, 0.16, 0.22), zi + 1, rot)

## Glass office partition. The maze is the product.
##
## ROUND 10, critiques #4 and #9: these were the corporate frame's "flat
## untextured hard-edged saturated quads" and half of its fifteen blue bars — a
## 0.88-alpha pane in near-full corp blue with a 0.36-alpha lit rail on top,
## seven of them, drawing L-strips across the floor. Glass is now DESATURATED and
## capped at 30% value with one neutral rail: it reads as a low partition you
## walk around, not as a light source somebody left on.
static func _partition(parent: Node2D, pos: Vector2, size: Vector2, col: Color) -> void:
	var zi := _depth(pos.y, size.y * 0.5)
	_drop_shadow(parent, pos + Vector2(0, size.y * 0.5 + 3.0), size.x * 0.86, zi - 1, 0.24)
	var glass := _dull(col, 0.86, 0.30)
	_rect(parent, pos, size, Color(glass.r, glass.g, glass.b, 0.90), zi)
	_rect(parent, pos + Vector2(0, -size.y * 0.5 + 2.0), Vector2(size.x, 2.0), Color(0.30, 0.33, 0.40, 0.42), zi + 1)

## THE BUNTING IS GONE — round-11 critique #2, "~12 flat magenta/gold lantern
## rectangles", and it was three runs of eight, so twenty-four.
##
## Each flag was an 11x15 filled quad in a full-value region hue with an additive
## chip on top of it, strung on a Line2D bezier at z 505 — i.e. drawn OVER the
## whole room, including over the player, in the two most saturated colours the
## bazaar owns. Round 6 added it to give the market a ceiling; what it gave the
## market was a confetti layer, and the frame measures 7.3% saturated magenta
## with this at the top of the bill. Lanterns come back the day somebody draws a
## lantern PROP (raised as a contract); they do not come back as rectangles.

## THE MAINTAINER'S SHACK IS GONE — round-11 critique #3: "a translucent flat
## yellow quad with a black-outlined brown square and a translucent green 'roof'
## bar — an unresolved placeholder hut".
##
## Three rounds of patching a building out of eighteen ColorRects produced,
## every time, the same thing a cold viewer sees: flat quads with no material,
## no texture and a hard black rectangle for a door. A shack is a PROP or it is
## nothing, so the wildlands' camp now stands beside the drawn `dress_stall` —
## a counter with the maintainer's things on it, which is a better read of "one
## person, unpaid, in the woods, holding up your build" than a hut was.

static func _sp_dependency(z: Node2D, glow: Color, accent: Color) -> void:
	## The region's ONE set-piece caption (LAW 4: <= 4 world labels). East of the
	## heap, on the floor the conveyor used to cover: at (200,150) it was printed
	## through the region title, and anywhere west of x 380 it lands in the
	## Localhost door's reserved box and gets displaced by the ladder anyway.
	_sign(z, Vector2(448, 300), "node_modules", glow, 12)
	# node_modules: a crate heap collapsing into its own gravity well. THE focal,
	# and now the district's ONLY light (critique (f)) — the one lamp a region is
	# allowed, over the one thing it is named after.
	_floor_patch(z, Vector2(296, 292), 340.0, Color(0.01, 0.03, 0.01), 0.55, -94)
	_heap(z, Vector2(296, 286), accent, 8, 1.0, 4201)
	_lamp(z, Vector2(296, 292), glow, 1.1, 3.0, true, 340.0)
	# The install bay: a terminal that has been at 47% for a while. Mid-ground:
	# one step below the heap, lit by its own screen and nothing else.
	_prop(z, "struct_console", Vector2(1010, 254), 1.0, Color(0.66, 0.8, 0.5))
	_screen(z, Vector2(1010, 232), glow, Vector2(1.3, 1.1), _depth(254, 60))
	_rect(z, Vector2(1010, 296), Vector2(120, 8), Color(0.06, 0.1, 0.05), _depth(296, 8))
	# The lockfile shrine. Merged by hand. We do not speak of it. Its two candle
	# lamps went with every other sub-focal lamp in the file (critique (f)).
	# Dropped BELOW the arrival frame (critique #3): at y 806 it stood in the
	# bottom HUD band, i.e. behind the objective line, which is a strange place
	# for a thing nobody is supposed to look at directly.
	_prop(z, "struct_slab", Vector2(360, 872), 0.6, Color(0.5, 0.62, 0.44))
	# THE CONVEYOR IS GONE — round-11 critique #6, "a flat dark-green bar with an
	# acid cap under the region title". It was a 330x40 filled rect with a 330x4
	# lighter rect on top of it, eleven slat marks, a 6x40 additive acid-green
	# chip at its west end and a 300px pool, laid across x 395..725 at y 210 —
	# i.e. straight through the region name in the first frame of every visit.
	# Nothing about it read as a machine; it read as exactly what the critique
	# called it, a flat bar with a bright cap. The heap it fed is still there and
	# still the largest silhouette in the room.
	# The maintainer's depot — crates and one folding table, unlit. Lifted 90
	# units with the maintainer himself (critique #3): the whole pitch, person
	# included, stood in the bottom HUD band, so the one quest-giver in the region
	# was read through the ability bar and his name tag through the toast lane.
	_prop(z, "struct_crate", Vector2(1002, 712), 0.9, accent)
	_prop(z, "struct_crate", Vector2(1150, 716), 0.85, Color(accent.r * 0.85, accent.g * 0.85, accent.b * 0.85))
	_rect(z, Vector2(1076, 710), Vector2(130, 14), Color(0.26, 0.22, 0.18), _depth(710, 8))

	# Somebody's evening, left where it ended: a cold cup by the depot and the
	# drum the conveyor was fed from, still half wound.
	_prop(z, "dress_noodle_cup", Vector2(196, 872), 1.0, Color(0.86, 0.94, 0.8))
	_prop(z, "dress_cable_spool", Vector2(168, 646), 0.9, Color(0.72, 0.86, 0.66))

static func _sp_stackoverflow(z: Node2D, glow: Color, _accent: Color) -> void:
	## The region's ONE set-piece caption (LAW 4: <= 4 world labels).
	_sign(z, Vector2(556, 300), "ACCEPTED ANSWER", glow, 12)
	# A field of toppled answer-monoliths. All correct in 2013.
	_monolith(z, Vector2(238, 300), 1.15, Color(0.72, 0.64, 0.5), 0.9, 11)
	_monolith(z, Vector2(392, 348), -0.42, Color(0.66, 0.58, 0.46), 0.75, 12)
	_monolith(z, Vector2(1096, 318), -1.25, Color(0.7, 0.62, 0.48), 0.85, 13)
	_monolith(z, Vector2(936, 372), 0.35, Color(0.62, 0.55, 0.44), 0.7, 14)
	# The Accepted Answer, still lit, still wrong. THE focal: brightest thing in
	# the ruins, haloed so the slab reads before its caption does.
	# The slab is lit BY its lamp, it does not emit: the 30x30 additive square
	# that used to sit on its face was a glow pass on a prop (LAW 7 allows one
	# emissive pixel, LAW 3 allows props none at all).
	_prop(z, "struct_slab", Vector2(640, 214), 1.0, Color(0.86, 0.76, 0.55))
	_lamp(z, Vector2(640, 178), glow, 1.15, 2.8, true, 340.0)
	_floor_patch(z, Vector2(640, 292), 300.0, glow, 0.14, -94)
	# Cairn of duplicates, stacked by a hermit with a lot of time. West of the
	# spawn column since round 10 (critique #3) — at x 524 the top of the stack
	# sat in the toast lane. Round 12 lifts its BASE out of the bottom HUD band
	# too: at y 856 the pile's four lower stones were drawn straight through the
	# ability bar, so what the player saw of it was the top rock and nothing else.
	for i in 5:
		_prop(z, "struct_slab", Vector2(470.0 + float(i % 2) * 8.0, 726.0 - float(i) * 26.0), 0.34 - float(i) * 0.03, Color(0.6, 0.54, 0.44), float(i) * 0.4)
	# The pilgrim shrine. You bring your question here. The question has been
	# asked. The answer is four versions out of date and marked as duplicate.
	# 46 units up, which is what it takes for the ring's two southern candles to
	# clear the bottom HUD band (critique #3)... except that it wasn't: the ring
	# is 62 units deep and a candle is 13 tall, so the southern pair ran to y 738
	# and the last eight units of both of them were printed under the objective
	# line. 12 more, measured this time.
	_shrine(z, Vector2(324, 658), glow)
	# The hermit's fire, burning documentation for warmth. Mid-ground: two stones
	# and the dark between them. Its 240px pool and its lamp went with every other
	# second light in the file (critique (f)) — the ruins spend their one on the
	# Accepted Answer, which is the joke.
	for k: float in [1.0, -1.0]:
		_prop(z, "struct_slab", Vector2(1000 + k * 92.0, 700), 0.3, Color(0.56, 0.5, 0.42), k * 0.2)

	# One more answer-stone, snapped, still lit. Nobody remembers the question.
	_prop(z, "dress_monolith", Vector2(190, 646), 1.0, Color(0.78, 0.7, 0.54))
	_prop(z, "dress_monolith", Vector2(1188, 846), 0.85, Color(0.7, 0.63, 0.5), 0.09)

## ROUND 11, critique #2 — the worst frame in the set at 3.5/10, and the whole
## charge is composition: "7.3% of the frame is saturated magenta: four full-value
## awnings across the entire top strip under all three HUD zones, ~12 flat
## magenta/gold lantern rectangles".
##
## The market had FOUR stalls (three of them shoulder to shoulder along the top
## wall), THREE free-standing `dress_awning` sprites tinted at 0.9 of full
## magenta hung above those same three, and THREE bunting runs of eight flags —
## ten awnings and twenty-four flags, all in the region's two most saturated
## hues, all of it in the band the HUD writes over.
##
## What a night market actually needs is one pitch you can walk up to and one you
## are being sold at. So: TWO stalls; ONE canopy between them, drawn as the
## `dress_awning` prop at 60% value instead of six saturated rects; the main pitch
## moved a full stall-height clear of the region title; and no bunting at all.
static func _sp_bazaar(z: Node2D, glow: Color, accent: Color) -> void:
	## The region's ONE set-piece caption (LAW 4: <= 4 world labels).
	_sign(z, Vector2(408, 452), "NIGHT MARKET", glow, 12)
	# The main pitch: everything's for sale, per request. THE focal, and the one
	# lamp the bazaar gets. At y 342 its canopy tops out at 248 — below the title
	# strip, and low enough that the player lands looking AT the market instead of
	# under it.
	_stall(z, Vector2(640, 342), accent, glow, 92)
	_lamp(z, Vector2(640, 320), glow, 1.1, 2.6, false, 340.0)
	# The haggling pit: a ring of crates around a low table nobody wins at, west
	# of the spawn column and out of the toast lane (critique #3). Unlit.
	#
	# ROUND 12: the ring straddled the bottom HUD band — three of its seven crates
	# sat at y 756..808, under the objective line — so the pit is 38 units further
	# south and its ellipse is FLATTER (40, not 92). Same footprint on the x axis,
	# same read; every crate now lands below y 840, i.e. below the arrival frame,
	# which is where a place you walk down to belongs.
	var pit := Vector2(392, 886)
	_floor_patch(z, pit, 380.0, accent, 0.1, -94)
	for i in 7:
		var a := TAU * float(i) / 7.0
		_prop(z, "struct_crate", pit + Vector2(cos(a) * 150.0, sin(a) * 40.0), 0.55, Color(0.72, 0.56, 0.4), a * 0.2)
	_drop_shadow(z, pit + Vector2(0, 12), 110.0, _depth(pit.y, 16) - 1, 0.36)
	_rect(z, pit, Vector2(96, 30), Color(0.3, 0.2, 0.3), _depth(pit.y, 16))
	# The reseller's own stall: uncanopied, so the man standing behind it is not
	# drawn underneath his own awning. Moved 106 units north and 52 east with the
	# reseller (critique #3, "API reseller under the ability bar") — east because
	# the Cloud District door's reserved box reaches x 1136, and a man standing in
	# a doorway is the other half of that critique.
	_stall(z, Vector2(1140, 700), glow, accent, 94, false)
	# A pitch nobody licensed, wedged in where the aisle widens, and the shutters
	# of two that closed. Props, not quads.
	_prop(z, "dress_stall", Vector2(830, 874), 0.95, Color(0.94, 0.8, 0.9))
	_prop(z, "dress_stall", Vector2(266, 624), 0.9, Color(0.82, 0.72, 0.84))

static func _sp_cloud(z: Node2D, glow: Color, accent: Color) -> void:
	## The region's ONE set-piece caption (LAW 4: <= 4 world labels).
	_sign(z, Vector2(556, 288), "THE CLOUD", glow, 12)
	# The server cathedral: a nave of racks, an arch for an apse.
	for i in 3:
		var y := 176.0 + float(i) * 96.0
		_rack(z, Vector2(430, y), Color(0.6, 0.7, 0.86), glow, 0.85, 0.2 + float(i) * 0.3)
		_rack(z, Vector2(850, y), Color(0.56, 0.66, 0.82), glow, 0.85, 0.5 + float(i) * 0.3)
	# The apse: an arch at the head of the nave, DARK. Round-11 critique #4 — "a
	# bright blue light pool directly under the region title" — is this piece: a
	# 380px accent floor wash plus a 380px lamp pool, both centred at x 640 and
	# y 196..268, i.e. exactly where the HUD prints "Cloud District" the moment
	# the player arrives. The arch is a silhouette now; the racks flanking it and
	# the aisle between them are what say cathedral.
	_prop(z, "struct_arch", Vector2(640, 172), 1.15, Color(0.72, 0.82, 0.96))
	# The invoice altar. Numbers go up. Nobody knows which numbers. THE focal, and
	# the region's one lamp: 275 units from the spawn (the critique asks for 220
	# or more) and 400 clear of the title strip, so the thing the Cloud District
	# is actually about is the thing the light in the room is pointing at.
	_prop(z, "struct_slab", Vector2(884, 648), 0.75, Color(0.66, 0.76, 0.9))
	_screen(z, Vector2(884, 620), accent, Vector2(1.5, 1.1), _depth(648, 48))
	_floor_patch(z, Vector2(884, 700), 320.0, glow, 0.14, -94)
	_lamp(z, Vector2(884, 606), glow, 1.2, 3.0, true, 340.0)
	# The sales booth. It is elastic. Do not ask what that means. 70 units north
	# and 68 east with the salesperson (critique #3): the booth stood in the
	# bottom HUD band and its owner's name tag printed into the toast lane. East,
	# because the Wildlands door's reserved box reaches x 1164 and the whole point
	# of moving him is that he stops standing in front of something.
	_prop(z, "struct_console", Vector2(1196, 712), 0.9, Color(0.7, 0.8, 0.95))
	_screen(z, Vector2(1196, 692), glow, Vector2(1.1, 0.9), _depth(712, 54))

	# The plant that keeps the cathedral cold, and the conduit waiting on a
	# change window that has been rescheduled four times.
	_prop(z, "dress_cooling_tower", Vector2(1146, 262), 1.0, Color(0.78, 0.86, 0.98))
	_prop(z, "dress_pipe_stack", Vector2(1122, 856), 0.95, Color(0.74, 0.82, 0.94))

static func _sp_opensource(z: Node2D, glow: Color, _accent: Color) -> void:
	## The region's ONE set-piece caption (LAW 4: <= 4 world labels).
	# West of the camp: the generic NPC hint lands at (862,866) beside the
	# maintainer, and a caption at 916 shared pixels with it.
	_sign(z, Vector2(744, 716), "MAINTAINER", glow, 12)
	# The maintainer's camp: one fire, one person, 4,000 dependents.
	#
	# ROUND 12 lifted the whole camp 150 units (critique #3, "Wildlands maintainer"
	# under the ability bar). The camp is one composition — fire, stones, crates,
	# bench, person, caption — so it moved as one; the internal offsets are
	# untouched, and the maintainer still stands 40 units downhill of his own fire.
	#
	# ROUND 13, critique #7: "a bright amber spotlight cone on the Maintainer — the
	# brightest thing after the portal; the name label sits inside the glow". The
	# lamp is gone, and this file's own rule at the top of it says why: "the person
	# in the room is found by their name tag and the waypoint chevron, not by a
	# private spotlight". The wildlands were the one region that broke it — the
	# lamp stood 40 units above the maintainer's head, so the region's ONE light
	# was aimed at a human being, and the frame measures 89 luminance on him
	# against 51 at 180 units away. The fire's 16 particles are still there and
	# still warm; a campfire is a small bright thing, not a 340-unit pool with a
	# person standing in the middle of it. The wildlands now spend their two
	# motivated sources on their two doors, which is the same budget every other
	# region keeps.
	for i in 5:
		var a := TAU * float(i) / 5.0
		_rect(z, Vector2(1058, 662) + Vector2(cos(a) * 34.0, sin(a) * 20.0), Vector2(9, 9), Color(0.18, 0.16, 0.14), _depth(662, 6), a)
	_prop(z, "struct_crate", Vector2(970, 698), 0.6, Color(0.5, 0.68, 0.46))
	_prop(z, "struct_crate", Vector2(1146, 702), 0.6, Color(0.46, 0.64, 0.44))
	var fire := CPUParticles2D.new()
	fire.name = "Campfire"
	fire.position = Vector2(1058, 658)
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
	# What the camp is built around, now that the eighteen-rect shack is gone
	# (critique #3): the maintainer's bench, a drawn prop, with the crates and the
	# fire beside it. Everything in this corner is a texture with a material on
	# it; nothing here is a coloured quad any more.
	_prop(z, "dress_stall", Vector2(886, 598), 1.0, Color(0.62, 0.78, 0.58))
	_prop(z, "struct_crate", Vector2(792, 626), 0.7, Color(0.48, 0.66, 0.46))
	# The issue graveyard. Open since 2019. Reacted to with hearts. Both rows used
	# to sit inside the bottom HUD band (758 and 832); they are pushed BELOW the
	# arrival frame instead of above it, because the two legacy systems squatting
	# on them are staged down there and the joke is that they are squatting.
	for i in 8:
		var gp := Vector2(220.0 + float(i % 4) * 78.0, 846.0 + float(i / 4) * 54.0)
		_prop(z, "struct_slab", gp, 0.28, Color(0.44, 0.62, 0.46), (float(i) - 3.5) * 0.05)
	# The README monument. Accurate six months ago. Lit by its own screen; its
	# lamp went with every other second light (critique (f)).
	_prop(z, "struct_slab", Vector2(292, 274), 0.85, Color(0.56, 0.76, 0.54))
	_screen(z, Vector2(292, 250), glow, Vector2(1.2, 0.9), _depth(274, 52))
	# The overgrown arch: still merged, still load-bearing. A drawn arch with two
	# crates grown into it, square on the grid (LAW 1). The 300px accent wash and
	# the lamp under it are gone — a doorway in a wood is a shape, not a source.
	_prop(z, "struct_arch", Vector2(640, 226), 1.0, Color(0.44, 0.56, 0.42))
	_prop(z, "struct_crate", Vector2(566, 262), 0.6, Color(0.46, 0.58, 0.44))
	_prop(z, "struct_crate", Vector2(714, 258), 0.55, Color(0.44, 0.56, 0.42))

	# Dinner by the camp, and the spool the whole ecosystem is strung from.
	_prop(z, "dress_noodle_cup", Vector2(996, 890), 1.0, Color(0.82, 0.96, 0.8))
	_prop(z, "dress_cable_spool", Vector2(452, 302), 0.9, Color(0.7, 0.9, 0.7))

static func _sp_corporate(z: Node2D, glow: Color, accent: Color) -> void:
	## The region's ONE set-piece caption (LAW 4: <= 4 world labels).
	_sign(z, Vector2(896, 720), "ALL-HANDS STAGE", glow, 12)
	# The cubicle farm. Two banks, so the traffic lane stays a corridor. ONE lit
	# face per bank (critique #9 counted fifteen): the rest is dark glass, which
	# is what an open plan looks like at the hour this game is set, and it leaves
	# the region's four lit surfaces to the stage, reception and these two.
	for i in 4:
		_cubicle(z, Vector2(250.0 + float(i) * 260.0, 232.0), Color(0.6, 0.66, 0.8), glow, i == 1)
	# The south bank drops from three desks to two: the middle one stood at x 576,
	# directly under the ability bar in every arrival frame (critique #3). Both
	# step west in round 12 so the stage, which has moved north out of the bottom
	# HUD band, has the east third of the floor to itself.
	for i in 2:
		_cubicle(z, Vector2(300.0 + float(i) * 420.0, 700.0), Color(0.56, 0.62, 0.78), accent, i == 1)
	# The maze itself: glass runs and stub walls that turn an open plan into a
	# corridor with corners, without ever colliding with anything. The runs are
	# 220 apart rather than 260 for the same reason: the easternmost used to reach
	# x 940, i.e. into the stage's new footprint.
	for i in 3:
		_partition(z, Vector2(276.0 + float(i) * 220.0, 320.0), Vector2(208.0, 12.0), glow)
		_partition(z, Vector2(276.0 + float(i) * 220.0, 664.0), Vector2(208.0, 12.0), accent)
	for i in 4:
		_partition(z, Vector2(250.0 + float(i) * 260.0, 286.0), Vector2(12.0, 82.0), glow)
	# The all-hands stage, permanently set up. THE focal, and the region's one
	# lamp — the flanking pair is gone with every other second light (critique (f)).
	#
	# ROUND 11, critique #10, "the SVP's saturated blue monitor glows at rest":
	# the stage screen is 104x44 world units of pure #4D7CFF standing directly
	# behind the SVP, and it was baked at the 0.6 ceiling. At 0.42 it is still the
	# brightest surface in that corner and it no longer competes with the person
	# in front of it — which is the whole point of a stage.
	#
	# ROUND 12, critique #3: the platform ran y 782..846 and the SVP stood on it at
	# 786 — the whole set-piece, and the only person in the region, inside the
	# bottom HUD band. The stage moves 130 units north as one block (its internal
	# offsets are untouched), which puts the platform at 656..716, the screen clear
	# of the band, and the SVP's name tag in open air.
	_drop_shadow(z, Vector2(1000, 716), 270.0, _depth(682, 30) - 1, 0.4)
	_rect(z, Vector2(1000, 682), Vector2(250, 60), Color(0.18, 0.2, 0.28), _depth(682, 30))
	_rect(z, Vector2(1000, 656), Vector2(250, 5), Color(0.32, 0.36, 0.5), _depth(682, 32))
	_rect(z, Vector2(930, 650), Vector2(30, 42), Color(0.24, 0.26, 0.36), _depth(666, 22))
	_screen(z, Vector2(1000, 612), glow, Vector2(2.6, 1.7), _depth(682, 34), 0.42)
	# ROUND 13, critique #7's second case. The lamp stays — it is a STAGE light,
	# hung over a stage, and it is the region's one source — but it climbs 52 units
	# to sit above its own screen rather than level with it, and its floor puddle
	# is dropped. The SVP stands at (1000,656): with the lamp at 592 and a 320-unit
	# pool centred at 618, the puddle was painted directly under the one person in
	# the region, which is the same defect as the wildlands campfire one region
	# back. At 540 the light's 83-unit radius stops 33 units short of him.
	_lamp(z, Vector2(1000, 540), glow, 1.05, 2.6, false, 0.0)
	# Reception: a desk, a ticket queue, and no receptionist. Its screen is the
	# light; the 180px puddle it used to throw is not.
	_drop_shadow(z, Vector2(258, 660), 165.0, _depth(640, 18) - 1, 0.36)
	_rect(z, Vector2(258, 640), Vector2(150, 34), Color(0.2, 0.23, 0.32), _depth(640, 18))
	_screen(z, Vector2(258, 620), accent, Vector2(1.1, 0.8), _depth(640, 20))

	# Records nobody can delete, a board nobody erased, and one more partition.
	_prop(z, "dress_filing_cabinet", Vector2(1178, 296), 1.0, Color(0.74, 0.8, 0.94))
	_prop(z, "dress_filing_cabinet", Vector2(1178, 402), 0.95, Color(0.7, 0.76, 0.9))
	_prop(z, "dress_whiteboard", Vector2(618, 892), 0.95, Color(0.8, 0.85, 0.96))
	_prop(z, "dress_cubicle", Vector2(1178, 668), 0.9, Color(0.68, 0.74, 0.88))

static func _sp_gpu(z: Node2D, glow: Color, accent: Color) -> void:
	## The region's ONE set-piece caption (LAW 4: <= 4 world labels).
	_sign(z, Vector2(420, 464), "HEAT PIT", glow, 12)
	# Two rig banks, thermally throttled, spiritually throttled.
	for i in 3:
		_rack(z, Vector2(214.0 + float(i) * 104.0, 240.0), Color(0.72, 0.5, 0.42), glow, 0.9, 0.15 + float(i) * 0.27)
		_rack(z, Vector2(866.0 + float(i) * 104.0, 240.0), Color(0.7, 0.48, 0.4), accent, 0.9, 0.4 + float(i) * 0.27)
	# THE TWO CABLE SWAGS BETWEEN THE RIGS ARE GONE (LAW 1). They were 4px Line2Ds
	# run through (cx,190) -> (cx+52,214) -> (cx+104,190): a 2:1 slope, i.e. neither
	# axis-aligned nor 45 degrees, so every one of them was an anti-aliased diagonal
	# drawn across a pixel-art floor — the same defect critique #8 names in the
	# reference room, one region over and in the HUD's top strip besides.
	# Cooling towers, losing. Lifted out of the bottom HUD band (critique #3): at
	# y 792 the mine's two largest silhouettes were drawn behind the objective
	# line and the ability bar, so what read at the arrival was their tops. At 622
	# they stand among the rig banks' own towers, which is where a cooling plant
	# belongs anyway.
	for k: float in [1.0, -1.0]:
		var cp := Vector2(640.0 - k * 456.0, 622.0)
		_prop(z, "struct_tower", cp, 1.25, Color(0.62, 0.56, 0.56))
		_glow_rect(z, cp + Vector2(0, -78), Vector2(30, 4), Color(0.62, 0.64, 0.66, 0.4), _depth(cp.y, 80.0))
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
	_rails(z, 668.0, 260.0, 1010.0)
	_cart(z, Vector2(388, 656), glow, -0.03)
	_cart(z, Vector2(646, 660), accent, 0.02)
	_cart(z, Vector2(898, 654), glow, -0.05)
	# The heat pit: a hole in the floor, and the light coming out of it.
	#
	# ROUND 11, critique #9: "a flat orange lava quad under the objective text".
	# That was a 118x38 additive rect plus a 460px orange wash, both stamped on
	# the floor around the pit's mouth — a coloured shape pretending to be a
	# light, at the exact spot the objective line prints. The pit is a DARK HOLE
	# now, and the thing that makes it hot is the PointLight2D in _build_region_fx
	# (energy 0.9, flickering, on GPU_PIT), which is the region's one lamp and the
	# only source in the mines. A hole plus a real light is a pit; a hole plus an
	# orange rectangle is a placeholder.
	#
	# ROUND 13 moves the whole thing north out of the bottom HUD band (see
	# GPU_PIT) and takes 120 units off its light. The hole itself STAYS: it is
	# near-black, so it can only ever make the ground under a HUD glyph darker,
	# and a light with no hole under it is a source with nothing to come out of.
	# Its satellites are composed relative to GPU_PIT and travel with it — one of
	# them, now that the pit stands 90 units off the rail line, no longer has a
	# job: a fourth ore cart parked 88 units from the third one is the same prop
	# twice. The pipe stack keeps the pit company on the far side of the rails.
	_floor_patch(z, GPU_PIT, 200.0, Color(0.03, 0.012, 0.008), 0.55, -92)
	_prop(z, "dress_pipe_stack", GPU_PIT + Vector2(150, 110), 0.85, Color(0.82, 0.64, 0.56))
	# The foreman's post. Lit by its own screen.
	_prop(z, "struct_console", Vector2(1136, 716), 0.9, Color(0.74, 0.54, 0.44))
	_screen(z, Vector2(1136, 696), accent, Vector2(1.1, 0.9), _depth(716, 54))

	# Conduit staged for an upgrade that was approved two quarters ago, and a
	# cart that came off the rails and stayed off them.
	_prop(z, "dress_pipe_stack", Vector2(1176, 352), 0.95, Color(0.88, 0.7, 0.62))
	_prop(z, "dress_ore_cart", Vector2(1112, 886), 0.95, Color(0.9, 0.68, 0.56), 0.11)

## ROUND 11, critique #10: "the region title sits on a bright red altar rect".
##
## The war room stood at x 640 — the exact centre column — with its one lit panel
## at y 196, and the HUD prints "Production / Cycle 1 · 137s" across world
## y 155..195 in that same column. So the first thing every visit drew was the
## game's own title card on top of a saturated red screen. Two moves, both small:
## the whole set-piece steps 216 units EAST (clear of the title column, and still
## short of the HP bars at x 1044) and 44 units DOWN (clear of the strip
## outright), and the live panel is baked at 0.42 rather than 0.6.
static func _sp_production(z: Node2D, glow: Color, accent: Color) -> void:
	## The region's ONE set-piece caption (LAW 4: <= 4 world labels).
	_sign(z, Vector2(1004, 428), "WAR ROOM", glow, 12)
	# The incident war room. Permanently staffed by nobody. THE focal, and the
	# region's one lamp.
	_prop(z, "struct_slab", Vector2(856, 252), 1.7, Color(0.6, 0.42, 0.44))
	# ONE panel is live and two are dark (critique #9: "3 red panels" at
	# near-white value along the top wall). An incident room with every screen up
	# is three equal red rectangles; an incident room with one up has a subject.
	for i in 3:
		if i == 1:
			_screen(z, Vector2(772.0 + float(i) * 84.0, 240.0), glow, Vector2(1.7, 1.3), _depth(252, 104), 0.42)
		else:
			_dark_glass(z, Vector2(772.0 + float(i) * 84.0, 240.0), Vector2(1.7, 1.3), _depth(252, 104))
	_drop_shadow(z, Vector2(856, 368), 250.0, _depth(344, 20) - 1, 0.38)
	_rect(z, Vector2(856, 344), Vector2(230, 40), Color(0.22, 0.17, 0.19), _depth(344, 20))
	_rect(z, Vector2(856, 328), Vector2(230, 4), Color(0.36, 0.28, 0.3), _depth(344, 22))
	for k: float in [1.0, -1.0]:
		_rect(z, Vector2(856 + k * 132.0, 350), Vector2(34, 34), Color(0.18, 0.15, 0.18), _depth(350, 18))
	_lamp(z, Vector2(856, 306), glow, 1.25, 2.8, true, 380.0)
	_floor_patch(z, Vector2(856, 374), 420.0, glow, 0.16, -94)
	# Incident whiteboards: four boxes, three arrows, one theory somebody will
	# disprove in nine minutes. Re-hung either side of the war room's new place.
	_whiteboard(z, Vector2(444, 300), accent, -0.04)
	_whiteboard(z, Vector2(1040, 340), glow, 0.05)
	# THE ALARM PANELS ARE GONE. Six rects hung at y 84..97 — inside the backdrop
	# haze, below the top wall, and two of them additive in the region's hottest
	# hue. They are invisible at the spawn (the camera shows y 142 down) and read
	# as two red marks under the region title the moment the player walks north,
	# which is the whole of critique #10 restated one storey up. A war room that
	# is on fire does not also need alarm lamps on the wall behind it.
	# The status page. Fully green. Load-bearing lie. Mid-ground, lit by its own
	# screen (its 240px puddle went with critique (f)).
	_prop(z, "struct_slab", Vector2(272, 276), 0.9, Color(0.6, 0.44, 0.46))
	_screen(z, Vector2(272, 248), accent, Vector2(1.9, 1.2), _depth(276, 56))
	_led(z, Vector2(272.0, 296.0), accent, 0.2, _depth(296, 8))
	# THE BUTTON. Red. Domed. Guarded by a sign nobody reads. The dome is lit at
	# 60% rather than 90% (LAW 3): it is a button, not one of the five things in
	# the frame allowed to be bright — and it is no longer also a lamp.
	# 100 units north of where it stood (critique #3, "Production crate + enemy"
	# under the ability bar): the pedestal and its dome sat at y 758..800, i.e.
	# behind the objective line, which is the one strip of floor a red domed
	# button must never be hiding in.
	_prop(z, "struct_slab", Vector2(268, 700), 0.55, Color(0.58, 0.4, 0.42))
	_glow_rect(z, Vector2(268, 658), Vector2(24, 14), Color(0.60, 0.16, 0.16, 0.55), _depth(700, 62))
	# The postmortem graveyard: action items, all still open. Both rows pushed
	# BELOW the arrival frame rather than above it — the monolith is staged down
	# there, and an action item you have to walk south to read is the joke.
	for i in 6:
		_prop(z, "struct_slab", Vector2(940.0 + float(i % 3) * 74.0, 846.0 + float(i / 3) * 54.0), 0.26, Color(0.52, 0.4, 0.42), (float(i) - 2.5) * 0.06)

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
		# One chip per row, not four glowing bars and a puddle. Sixteen emissive
		# gold bars on four shelves is the shelving out-shining the reserves it is
		# holding (LAW 7: one emissive pixel per light source).
		_glow_rect(z, sp + Vector2(0.0, -22.0), Vector2(9, 4), Color(glow.r, glow.g, glow.b, 0.5), _depth(sp.y, 50.0))
	# The reserve pedestal: an orb of tokens under an arcane ring. THE focal.
	# The twenty violet dashes that used to ring the pedestal are gone, and so are
	# the twenty-eight more around the two circles below: forty-eight rotated
	# streaks scattered over the vault floor, which is exactly what critique #6
	# read them as ("40+ violet diagonal streak particles"). The orb under its own
	# lamp is the focal; a halo of marks around it is not lighting.
	_prop(z, "struct_orb", Vector2(640, 244), 0.85, Color(1.0, 0.85, 0.34))
	_lamp(z, Vector2(640, 226), glow, 1.25, 3.0, true, 380.0)
	# Two arcane circles: the price oracle, and whatever the other one does. A
	# stain on the floor and nothing else — their lamps went with every other
	# second light in the file (critique (f)).
	for k: float in [1.0, -1.0]:
		_floor_patch(z, Vector2(640.0 - k * 366.0, 690.0), 300.0, VIOLET, 0.14, -94)
	# The security lattice is GONE. Two 372px overbright violet bays laid end to
	# end still drew one near-continuous horizontal beam across the whole frame at
	# y 662 — critique #6, "a violet horizontal beam" — and a perfectly straight
	# overbright line across a floor reads as a stray primitive no matter how well
	# motivated it is. The emitter heads stay as unlit props: hardware that is
	# switched off is still hardware, and the vault is a mood either way.
	# The balance console. It says "yes". Moved off the spawn column (critique
	# #3): its lit face at (640,778) was the "sign board under the toast" — the
	# vault's arrival frame drew it directly behind the reward line.
	# ...and 64 units further north again in round 12: at y 764 its lit face was
	# back in the bottom HUD band, behind the objective line this time instead of
	# behind the toast (critique #3).
	_prop(z, "struct_console", Vector2(444, 700), 0.95, Color(0.9, 0.78, 0.46))
	_screen(z, Vector2(444, 680), accent, Vector2(1.4, 1.0), _depth(700, 56))

	# The two emitter heads the lattice used to come out of, kept as dark props
	# either side of the counting floor, and a cart of reserves left where the
	# last audit abandoned it.
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
##
## "lights" is gone as of round 11. It was a pair of coordinates per region that
## _build_region_lights poured a 280px puddle onto, motivated by nothing at all —
## two of the four-to-five sources critique (f) counted. "focal" stays, and it now
## does double duty: it is where the region's ONE lamp hangs and where its token
## cluster is composed (see _token_spots).
static func _region_theme(region_id: String) -> Dictionary:
	match region_id:
		"dependency_district":
			# ACCENT acid #A8FF3E, WARM crate orange #E08A3C.
			var structs := _clu(190, 620, "struct_crate", 3, 0.95, Color(0.62, 0.52, 0.40), 55)
			structs += _clu(1120, 604, "struct_crate", 3, 0.95, Color(0.60, 0.50, 0.38), 55)
			structs += _clu(206, 424, "struct_crate", 3, 0.9, Color(0.61, 0.51, 0.39), 50)
			structs += [{"t": "struct_tower", "p": Vector2(1160, 430), "s": 0.9, "m": Color(0.50, 0.55, 0.46)}]
			return {
				"wall": Color(0.40, 0.44, 0.38),
				"glow": Color("#A8FF3E"), "accent": Color("#E08A3C"),
				"focal": Vector2(296, 286),  # the node_modules heap
				"structs": structs, "signs": [],
			}
		"stackoverflow_ruins":
			# ACCENT dusty gold #E8C46B, WARM copper #C97B4A.
			var structs: Array = [
				{"t": "struct_arch", "p": Vector2(272, 604), "s": 1.0, "m": Color(0.58, 0.55, 0.48)},
				{"t": "struct_arch", "p": Vector2(1012, 620), "s": 0.95, "m": Color(0.54, 0.51, 0.45)},
			]
			# Both southern slab piles spread through the bottom HUD band (732..852
			# and 720..840 respectively — critique #3). The western one goes fully
			# below the arrival frame beside the boss's clearing; the eastern one
			# comes up to the ruin's mid-floor, where the second arch already is.
			structs += _clu(196, 890, "struct_slab", 2, 0.75, Color(0.55, 0.52, 0.46), 40)
			structs += _clu(1156, 660, "struct_slab", 2, 0.7, Color(0.51, 0.48, 0.43), 50)
			return {
				"wall": Color(0.46, 0.43, 0.37),
				"glow": Color("#E8C46B"), "accent": Color("#C97B4A"),
				"focal": Vector2(640, 214),  # the Accepted Answer
				"structs": structs, "signs": [],
			}
		"api_bazaar":
			# ACCENT magenta #FF2D95, WARM gold #FFD34D.
			var structs := _clu(200, 470, "struct_console", 2, 0.85, Color(0.56, 0.50, 0.55), 60)
			structs += _clu(1104, 462, "struct_console", 2, 0.85, Color(0.55, 0.49, 0.54), 60)
			structs += _clu(206, 636, "struct_crate", 3, 0.85, Color(0.58, 0.53, 0.42), 55)
			return {
				"wall": Color(0.42, 0.37, 0.42),
				"glow": Color("#FF2D95"), "accent": Color("#FFD34D"),
				"focal": Vector2(640, 342),  # the market's main pitch
				"structs": structs, "signs": [],
			}
		"cloud_district":
			# ACCENT sky #6BC7FF, WARM near-white #E8F4FF.
			var structs := _clu(196, 604, "struct_orb", 2, 0.7, Color(0.50, 0.55, 0.62), 60)
			structs += _clu(1116, 612, "struct_orb", 2, 0.65, Color(0.53, 0.57, 0.63), 60)
			# Lifted from y 800 (critique #3): the pair spread into the bottom HUD
			# band, and a struct_tower is tall, so what the arrival frame showed of
			# them was two dark bars behind the objective line.
			structs += _clu(214, 640, "struct_tower", 2, 0.75, Color(0.47, 0.51, 0.58), 40)
			return {
				"wall": Color(0.42, 0.45, 0.52),
				"glow": Color("#6BC7FF"), "accent": Color("#E8F4FF"),
				"focal": Vector2(884, 648),  # the invoice altar
				"structs": structs, "signs": [],
			}
		"open_source_wildlands":
			# ACCENT leaf #58E07C, WARM lantern #C9A24A (v2 table: the old #3E9E5C
			# was a second green, i.e. one hue doing two jobs and neither of them
			# complementary).
			var structs := _clu(196, 604, "struct_crate", 3, 0.85, Color(0.46, 0.52, 0.44), 50)
			structs += _clu(1122, 610, "struct_slab", 2, 0.8, Color(0.44, 0.50, 0.44), 55)
			structs += _clu(1140, 300, "struct_crate", 2, 0.8, Color(0.45, 0.51, 0.43), 50)
			return {
				"wall": Color(0.38, 0.44, 0.39),
				"glow": Color("#58E07C"), "accent": Color("#C9A24A"),
				"focal": Vector2(1058, 662),  # the maintainer's campfire
				"structs": structs, "signs": [],
			}
		"corporate_enterprise":
			# ACCENT corp blue #4D7CFF, WARM glass grey #93A7C8.
			var structs: Array = []
			for gx in 2:
				structs.append({"t": "struct_slab", "p": Vector2(180.0 + float(gx) * 920.0, 470.0), "s": 0.75, "m": Color(0.48, 0.51, 0.57)})
				structs.append({"t": "struct_slab", "p": Vector2(180.0 + float(gx) * 920.0, 600.0), "s": 0.7, "m": Color(0.45, 0.48, 0.54)})
			return {
				"wall": Color(0.42, 0.44, 0.50),
				"glow": Color("#4D7CFF"), "accent": Color("#93A7C8"),
				"focal": Vector2(1000, 612),  # the all-hands stage screen
				"structs": structs, "signs": [],
			}
		"gpu_mines":
			# ACCENT ember #FF6B2D, WARM heat #FF3D2D.
			var structs := _clu(190, 604, "struct_tower", 2, 0.8, Color(0.54, 0.47, 0.44), 55)
			structs += _clu(1130, 596, "struct_tower", 2, 0.8, Color(0.52, 0.45, 0.42), 55)
			structs += _clu(196, 452, "struct_crate", 3, 0.8, Color(0.55, 0.48, 0.44), 50)
			return {
				"wall": Color(0.44, 0.38, 0.36),
				"glow": Color("#FF6B2D"), "accent": Color("#FF3D2D"),
				"focal": GPU_PIT,  # the heat pit
				"structs": structs, "signs": [],
			}
		"production":
			# ACCENT red #FF4757, WARM amber #FFB020.
			var structs: Array = [
				{"t": "struct_tower", "p": Vector2(186, 470), "s": 0.85, "m": Color(0.50, 0.44, 0.45)},
				{"t": "struct_tower", "p": Vector2(1104, 470), "s": 0.85, "m": Color(0.50, 0.44, 0.45)},
			]
			structs += _clu(206, 636, "struct_crate", 3, 0.85, Color(0.55, 0.49, 0.42), 55)
			return {
				"wall": Color(0.44, 0.38, 0.39),
				"glow": Color("#FF4757"), "accent": Color("#FFB020"),
				"focal": Vector2(856, 252),  # the war room
				"structs": structs, "signs": [],
			}
		"token_vault":
			# ACCENT gold #FFD34D, WARM violet #8B5CF6.
			var structs := _clu(192, 604, "struct_orb", 2, 0.6, Color(0.58, 0.53, 0.42), 55)
			structs += _clu(1124, 600, "struct_orb", 2, 0.6, Color(0.57, 0.52, 0.41), 55)
			structs += _clu(196, 442, "struct_orb", 1, 0.55, Color(0.58, 0.54, 0.44), 30)
			return {
				"wall": Color(0.46, 0.43, 0.37),
				"glow": Color("#FFD34D"), "accent": VIOLET,
				"focal": Vector2(640, 244),  # the reserve pedestal
				"structs": structs, "signs": [],
			}
		_:
			return {
				"wall": Color(0.44, 0.46, 0.49),
				"glow": Color("#24F0DC"), "accent": Color("#FFB74A"),
				"structs": [], "signs": [],
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
## THREE invariants, all load-bearing:
##   * every post is >= 420px from the arrival plaza at (640,480), because
##     tests/region_arrival_test.gd asserts nothing spawns inside the 340px
##     aggro radius. _staged() re-checks at runtime.
##   * the first combat region keeps exactly 4 (tests/region_winnable_test.gd).
##   * no post is above HUD_KEEP_Y (round-11 critiques #6 and #9: "a spider under
##     the tk counter", "an enemy at the top touching the HP bars"). An enemy is
##     drawn centred on its post with its body about 32 units above it, so a post
##     at y 166 puts a silhouette straight through the region title, and one at
##     (176,224) puts one under the token counter.
##   * and, since round 12, no post is in the bottom band either (730..840). An
##     enemy sprite is 64 units tall and a BOSS is 128 (node scale 2 x sprite
##     scale 2), so the five bosses that stood at y 856..880 were showing the
##     player their heads through the ability bar and nothing else — critique #3's
##     "Cloud ghost boss / SO Ruins beast / Vault eye turret / Corporate enemy /
##     Production crate + enemy".
##
## ROUND 13, critiques #1, #3 and #6 — the boss rule again, with the arithmetic
## done properly this time. y 890 was not enough: a boss is 128 units tall and
## drawn centred, so its head reaches 826 and it was still standing in the band,
## under the [H] hint, in production and corporate. The ideal answer is a FULL
## FRAME below the arrival view (y >= spawn.y + 780 = 1260) and the room is 960
## tall, so it does not exist here. What does exist is the far bottom band with
## two extra constraints, and every boss below satisfies all three:
##
##   * y >= 906 — spawn.y + 426, and 64 units of clearance under the band, so no
##     part of a 128-unit body is inside y 730..840. (_staged clamps to h - 52.)
##   * |x - 640| >= 260 — outside the bottom-centre HUD column, i.e. clear of the
##     six ability slots, the toast lane and the controls footer.
##   * 320 <= x <= 960 — outside the two bottom corner boxes, i.e. clear of the
##     objective line at bottom-left. That leaves exactly two windows, x 320..380
##     and x 900..960, and each boss takes a different pixel in one of them so the
##     five boss rooms do not all stage their fight in the same place.
##
## The distance from the plaza comes out at 500..525 for all five, which is over
## the 420 the arrival test asks for AND over the 480 the boss entrance now
## triggers at (enemy_base.gd), so no boss detonates its entrance off-screen.
##
## Those two rules fight each other in the top of the room — at y 250 the aggro
## radius allows only |x - 640| >= 345 — which is why the northern posts below are
## all tucked hard against the side walls. That is the correct answer anyway: it
## is where the landmarks they are guarding actually stand.
static func _region_enemy_posts(region_id: String) -> Array:
	match region_id:
		"dependency_district":
			# Two demons holding the node_modules heap, two null references
			# picketing the install bay. The artery between them stays clean.
			# BESIDE their landmarks, never inside them: _heap() spreads +/-70px
			# from (296,286) and the install bay console owns x 950..1070, so
			# posts tucked into those footprints were simply not visible.
			return [Vector2(188, 252), Vector2(286, 246), Vector2(1084, 252), Vector2(1064, 356)]
		"stackoverflow_ruins":
			# Bugs in the monolith fields; the merge conflict waits in the south
			# clearing, which is the only wide open floor in the ruins. The two
			# north posts stand clear of the toppled slabs at (238,300) and
			# (1096,318), and the south one clear of the shrine's sign plate.
			# The beast moves out of the bottom-centre HUD column to (938,906):
			# 520 from the plaza, and its head clears the band by 68.
			return [Vector2(172, 368), Vector2(1010, 250), Vector2(180, 696), Vector2(938, 906)]
		"api_bazaar":
			# Rate limiters posted at the market gates, bugs in the west aisle.
			return [Vector2(1120, 300), Vector2(900, 890), Vector2(250, 696), Vector2(250, 268), Vector2(180, 252)]
		"cloud_district":
			# The bill occupies the south-east floor; the leaks sit on the racks.
			return [Vector2(912, 906), Vector2(238, 296), Vector2(1082, 278)]
		"open_source_wildlands":
			# Legacy systems squatting on the issue graveyard — the thing worth
			# taking is the thing that is defended. Bugs patrol the perimeter.
			# The README bug stands west of the monument, not behind it.
			return [Vector2(246, 890), Vector2(404, 890), Vector2(186, 266), Vector2(1124, 268), Vector2(1148, 620)]
		"corporate_enterprise":
			# The architect owns the south-west floor; scope creep is everywhere
			# else, which is thematically the only correct arrangement. The
			# reception picket moved off the "raise a ticket" sign plate — a
			# world plate draws at z 1150 and hides anything standing under it.
			# The architect keeps the south-west floor but steps EAST to x 352:
			# at 286 he stood inside the bottom-left corner box, which is where the
			# objective line prints — critique #6's "red-eyed robot under the
			# objective". 352 is the first pixel clear of that box that is still
			# 288 from the centre column.
			return [Vector2(352, 906), Vector2(250, 248), Vector2(152, 596), Vector2(1108, 252)]
		"gpu_mines":
			# Leaks on both rig banks and one down at the spoil heap; two bugs on
			# the southern haul road, which is the long way round to the pit.
			# The northern pair stands at the ends of the rig banks rather than in
			# the gaps between them: the gaps are at x 366 and x 970, and both of
			# those sit under the HUD in the arrival frame.
			return [Vector2(228, 250), Vector2(236, 356), Vector2(1010, 252), Vector2(1114, 320),
				Vector2(250, 890), Vector2(750, 894), Vector2(1060, 894)]
		"production":
			# The monolith holds the south floor DIRECTLY below the war room, which
			# is where it belonged all along: at x 420 it stood in the bottom
			# HUD column with its 260-unit slam marker printed across the ability
			# bar (critique #6, "a red arc under the objective"), and the war room
			# it is guarding is at x 856.
			return [Vector2(924, 906), Vector2(170, 262), Vector2(1092, 268), Vector2(1148, 560)]
		"token_vault":
			# Two rate limiters on the shelving rows, the infinite context in the
			# open south-east where there is room to run away from it.
			return [Vector2(250, 258), Vector2(1092, 258), Vector2(946, 906)]
		_: return []

## Boss arena anchor (visual only — the post table above is what actually
## places the boss). A boss with nowhere to circle is a damage race, not a
## fight, so each of these gets a marked-out clearing with bollards on its
## corners and every other piece of scenery kept out of it.
static func _region_boss_arena(region_id: String) -> Vector2:
	match region_id:
		"stackoverflow_ruins": return Vector2(938, 906)
		"cloud_district": return Vector2(912, 906)
		"corporate_enterprise": return Vector2(352, 906)
		"production": return Vector2(924, 906)
		"token_vault": return Vector2(946, 906)
		_: return Vector2.ZERO

## Solid cover, per region. Small isolated blocks only — never a wall, never two
## within 150px of each other, never within 88px of a post or 150px of a portal
## or NPC — so they can shape a fight without ever boxing the player, an enemy
## or a quest-giver in. Positions are hand-checked against every portal, NPC and
## interactable in the region.
##
## ROUND 11: every block that stood above HUD_KEEP_Y is DELETED rather than
## relocated (critique #6, "keep the room's top corners clean"). Fourteen of them
## sat at y 180..240 — a 78x46 near-black rect with a lit cap chip, drawn under
## the token counter and the HP bars in the arrival frame of eight regions. The
## two that were load-bearing for a fight are replaced further down the same wall
## (cloud (1180,400), gpu (1180,520)); the rest are simply gone, which is what a
## quiet corner looks like.
##
## ROUND 12 does the same at the other end: seven blocks stood at y 740..830, in
## the bottom HUD band (critique #3), so they were barriers the player fought
## around while reading the objective line through them. Each moves to y 880 —
## below the arrival frame, beside the boss it is there to shape — except the
## wildlands' western pair, which the issue graveyard and the camp already own.
static func _region_cover(region_id: String) -> Array:
	match region_id:
		"dependency_district":
			# Deliberately NOT between the heap and the install bay: that corridor
			# is the engagement line tests/region_winnable_test.gd walks, and the
			# first combat region is the last place to introduce geometry that
			# could make a chasing enemy hesitate. (150,330) went with the demons'
			# new posts — 87 units apart is a barrier an enemy spawns against.
			return [Vector2(150, 660), Vector2(520, 700), Vector2(1160, 372)]
		"stackoverflow_ruins":
			# (980,880) went east with the beast: 52 units from its new post is a
			# barrier a boss spawns against.
			return [Vector2(1180, 380), Vector2(300, 880), Vector2(700, 880), Vector2(1112, 890)]
		"api_bazaar":
			return [Vector2(700, 880), Vector2(150, 600), Vector2(170, 340)]
		"cloud_district":
			return [Vector2(720, 880), Vector2(1080, 884), Vector2(1180, 400)]
		"open_source_wildlands":
			return [Vector2(150, 700), Vector2(640, 880), Vector2(1160, 880)]
		"corporate_enterprise":
			# (400,880) steps east to 508: at 400 it was 55 units from the
			# architect's new post, which is a barrier a boss spawns against. 157
			# now, and still west of the reserved arrival lane at x 524.
			return [Vector2(180, 880), Vector2(508, 888), Vector2(160, 340), Vector2(1170, 340)]
		"gpu_mines":
			# (150,860) drops 24: a barrier's lit cap sits 23 above its anchor, so
			# at 860 it printed inside the bottom band's left corner box.
			return [Vector2(1180, 520), Vector2(150, 884), Vector2(860, 880), Vector2(1160, 900)]
		"production":
			# (300,900) crosses the room to shape the monolith's new arena; it
			# clears the reserved lane's east edge (x 756) by eight units.
			return [Vector2(764, 900), Vector2(560, 880), Vector2(150, 600), Vector2(1180, 720)]
		"token_vault":
			return [Vector2(740, 890), Vector2(1116, 896), Vector2(1180, 420)]
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
		# h - 94 rather than h - 110 since round 13, following the bosses down to
		# y 906: a pad drawn 70 units north of the thing it is meant to be around
		# stops reading as that thing's floor.
		_arena(z, Vector2(clampf(arena.x, 260.0, float(w) - 260.0), clampf(arena.y, 250.0, float(h) - 94.0)))
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
##
## ROUND 13: the outer disc is gone as well. It was a 500-unit ACCENT stain at 7%
## — the region's own neon, painted on the floor — and with the boss staged at
## y 906 its top edge reached y 750, i.e. it was the region's accent hue smeared
## under the objective line and the ability bar in five of the ten rooms. What is
## left is one DARK swept pad, which cannot wash over anything: it makes the
## ground under the HUD text darker, not brighter.
static func _arena(parent: Node2D, pos: Vector2) -> void:
	_floor_patch(parent, pos, 330.0, Color(0.014, 0.016, 0.03), 0.30, -93)
	# ROUND 10: the poured RAIL is gone too — thirty rotated 4px bars laid end to
	# end around an ellipse, which is what critique #8 read as "smooth red
	# crescents" in the vault and the ruins. It was thirty anti-aliased quads
	# drawing a curve in a game with no curves (LAW 1). Two swept discs say
	# "fight here" perfectly well, and now the boss is the only thing in the ring.
	#
	# ROUND 11: and the 400px pool on top of them is gone too (critique (f)). An
	# arena is a DARKER patch of floor with room in it; lighting it was the one
	# thing guaranteed to stop it reading as a hole to fight in.

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
	# One lit cap and no puddle: five to seven barriers a region, each with two
	# glowing caps and its own pool, is set dressing lit to the same value as the
	# things the player is meant to look at (critique #7).
	_glow_rect(parent, pos + Vector2(-26, -20), Vector2(12, 4), Color(col.r, col.g, col.b, 0.5), zi + 2)
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
	# h - 52 rather than h - 66 since round 13: a boss has to stand at y 906 for
	# its 128-unit body to clear the bottom HUD band, and the old clamp silently
	# pulled every one of them back to 894 — where the head is in the band again.
	# 906 leaves 38 units between the body's own 14px radius and the wall collider
	# at 944, so nothing is depenetrating into the masonry.
	var p := Vector2(clampf(want.x, 130.0, w - 130.0), clampf(want.y, HUD_KEEP_Y, h - 52.0))
	var d := p - spawn
	if d.length() < 415.0:
		if d.length() < 1.0:
			d = Vector2(1.0, 0.0)
		p = spawn + d.normalized() * 415.0
		p = Vector2(clampf(p.x, 130.0, w - 130.0), clampf(p.y, HUD_KEEP_Y, h - 66.0))
	# The push above walks OUTWARD ALONG THE BEARING from the spawn, which for a
	# northern post means "further up" — i.e. straight back into the strip the
	# clamp just took it out of. So when the y clamp bites, pin y and buy the
	# distance sideways instead: at HUD_KEEP_Y the arrival radius needs 341 units
	# of x, and both x 299 and x 981 are comfortably inside the walkable interior.
	if p.y <= HUD_KEEP_Y and p.distance_to(spawn) < 415.0:
		var dy := spawn.y - HUD_KEEP_Y
		var need := sqrt(maxf(415.0 * 415.0 - dy * dy, 0.0))
		var side := 1.0 if p.x >= spawn.x else -1.0
		p = Vector2(clampf(spawn.x + side * (need + 4.0), 130.0, w - 130.0), HUD_KEEP_Y)
	# ...and the same treatment at the other end (critique #3). The push is
	# vertical because the low band is full-width, and it happens BEFORE the
	# radius check below so a post shoved out of the band can still fall back to
	# the safe scatter if the move brought it inside the arrival ring.
	if _below_hud(p):
		p = _clear_hud_bands(p)
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
	if p.distance_to(spawn) >= 420.0 and not _below_hud(p):
		return p
	# All four anchors are outside BOTH HUD bands: HUD_KEEP_Y + 16 clears the top
	# strip, and h - 100 (860) clears the bottom one by 20 (critique #3).
	var anchors: Array[Vector2] = [
		Vector2(200.0, HUD_KEEP_Y + 16.0), Vector2(w - 200.0, HUD_KEEP_Y + 16.0),
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
		# The anchors in _region_npcs are all outside the HUD bands by hand; this
		# is the guard-rail that keeps the next composition edit from putting a
		# quest-giver back under the ability bar (critique #3).
		n.position = _npc_spot(npc_data.pos)
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
	# The cluster at the set-piece, offset clear of the prop's own silhouette:
	# DOWNHILL of a landmark in the top half of the room, UPHILL of one in the
	# bottom half. The fixed +96 pushed the ring past the walkable edge for every
	# low focal (the campfire, the heat pit) and the clamp then stacked two of the
	# three coins on the same pixel — a reward the player cannot see twice.
	var lift := 96.0 if focal.y < h * 0.5 else -96.0
	for i in 3:
		var a := TAU * (float(i) + 0.5) / 3.0
		want.append(focal + Vector2(cos(a) * 96.0, sin(a) * 54.0 + lift))
	# One by the person.
	var npcs := _region_npcs(region_id)
	if npcs.is_empty():
		want.append(Vector2(w * 0.5, h - 220.0))
	else:
		var np: Vector2 = npcs[0].pos
		want.append(np + Vector2(-110.0, 62.0))
	var out: Array[Vector2] = []
	for p: Vector2 in want:
		# The y floor is the HUD keep-out: a gold coin is small and bright, and
		# one clamped to y 170 would bob under the region title all night. Since
		# round 12 the keep-out has a bottom half too, and the coin by the NPC is
		# the one this catches every time: np + (-110, 62) lands in the band for
		# six of the nine regions.
		var q := _clear_hud_bands(Vector2(clampf(p.x, 140.0, w - 140.0), clampf(p.y, HUD_KEEP_Y, h - 120.0)))
		# Nudge off cover and off the player's own landing spot, keeping the
		# composed position wherever it was already fine.
		#
		# The nudge walks OUTWARD from the spawn (with a widening fan, so a coin
		# pinned between two barriers still gets out) rather than around the old
		# fixed spiral, which turned through 1.9 radians a step and could — and in
		# the Bazaar always did — carry a coin straight back across the landing
		# spot it was trying to leave, all twelve times.
		for step in 12:
			if not _in_cover(q) and q.distance_to(spawn) > 96.0 and not _below_hud(q):
				break
			var d2 := q - spawn
			if d2.length() < 1.0:
				d2 = Vector2(1.0, 0.0)
			q += d2.normalized().rotated(float(step) * 0.5) * 34.0
			q = _clear_hud_bands(Vector2(clampf(q.x, 140.0, w - 140.0), clampf(q.y, 170.0, h - 120.0)))
		out.append(Vector2(round(q.x * 0.5) * 2.0, round(q.y * 0.5) * 2.0))
	return out

static func _random_pos(rng: RandomNumberGenerator, center: Vector2, min_dist: float = 80.0) -> Vector2:
	for attempt in 50:
		var pos := Vector2(
			rng.randf_range(TILE_SIZE * 2, (REGION_SIZE.x - 2) * TILE_SIZE),
			rng.randf_range(HUD_KEEP_Y, (REGION_SIZE.y - 2) * TILE_SIZE)
		)
		if pos.distance_to(center) > min_dist:
			# Solid cover exists now. A token scattered inside a barrier is a
			# collection objective the player cannot finish, so reject those.
			if _in_cover(pos):
				continue
			# ...and neither of the HUD bands (critique #3): a coin the player
			# cannot see is the same defect as a coin he cannot reach.
			if _below_hud(pos):
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
##
## ROUND 12, critique #3: six of these stood at y 748..852 — inside the bottom HUD
## band, or close enough below it that the NAME TAG landed there. npc.gd hangs the
## plate 106 units above the feet and stacks barks above that, so the maintainer
## at y 852 printed his own name at 736: under the objective line, every visit.
## A person is the one thing here that can only leave the band UPWARD (see
## _npc_spot), so each of them moved up, and each one's set-piece moved with them
## rather than leaving them standing in open floor next to an empty stall.
static func _region_npcs(region_id: String) -> Array:
	match region_id:
		"localhost":
			return [{"id": "roommate_ai", "pos": Vector2(1200, 900), "quests": ["hello_localhost", "tiny_change", "ship_dream_app"]}]
		"dependency_district":
			return [{"id": "maintainer", "pos": Vector2(1076, 700), "quests": ["install_node", "fix_without_touching", "pin_everything", "caret_gamble"]}]
		"stackoverflow_ruins":
			return [{"id": "stackoverflow_hermit", "pos": Vector2(1000, 704), "quests": ["stackoverflow_pilgrimage", "merge_conflict_hell"]}]
		"api_bazaar":
			return [{"id": "api_reseller", "pos": Vector2(1140, 690), "quests": ["one_more_api_call", "junior_agent"]}, {"id": "junior_agent", "pos": Vector2(800, 620), "quests": ["junior_agent"]}]
		"cloud_district":
			return [{"id": "cloud_salesperson", "pos": Vector2(1196, 700), "quests": ["cloud_migration", "context_window_full"]}]
		"open_source_wildlands":
			return [{"id": "oss_maintainer", "pos": Vector2(1058, 702), "quests": ["license_puzzle"]}]
		"corporate_enterprise":
			return [{"id": "svp_ai", "pos": Vector2(1000, 656), "quests": ["enterprise_ready", "mission_statement"]}]
		"gpu_mines":
			return [{"id": "gpu_foreman", "pos": Vector2(1136, 692), "quests": ["gpu_rush"]}]
		"production":
			# The one NPC with no furniture of his own, so he simply steps north out
			# of the band — and off the Token Vault door's reserved column, which is
			# why he is at x 860 rather than under the war room he is reporting on.
			return [{"id": "oncall_engineer", "pos": Vector2(860, 700), "quests": ["production_down"]}]
		_: return []

## Portal placement. Round 5 put every door at exactly (cx +/- 400, cy), so the
## critique's "the portal at the same left-third position in all nine frames"
## was literally true — the doors were the third thing (after the centred plaza
## and the horizontal artery) making every region read as the same room. The
## positions below are hand-checked per region against that region's own cover
## blocks, enemy posts, NPC and set-pieces; all of them sit in open, reachable
## floor well inside the walls. The pairs are deliberately NOT at matching
## heights any more: the two doors of a region sit at different latitudes, on
## different sides, so the room has a diagonal through it rather than the same
## left-to-right corridor nine times. (The paved spurs and chevron trails that
## used to be drawn from the plaza to each door are gone — round-8 critique #5
## reads a line drawn from the portal to the player as one more copy of the same
## room. The waypoint chevron is the wayfinding.)
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
## Each one sits inside a set-piece, so they read as objects in a place rather
## than markers on a plain. (They carry no pool of their own any more — round-11
## critique (f): a region has one light and it is the set-piece lamp.)
const REGION_FLAVOR := {
	"dependency_district": [
		["prop_node_modules", Vector2(300, 300), "node_modules"],
		["prop_leftpad", Vector2(1010, 300), "left-pad"],
		["prop_lockfile", Vector2(360, 860), "package-lock.json"],
	],
	"api_bazaar": [
		["prop_api_stall", Vector2(566, 342), "API reseller stall"],
		["prop_status_page", Vector2(266, 630), "Status page"],
		["prop_pricing", Vector2(392, 876), "Pricing board"],
	],
	"stackoverflow_ruins": [
		["prop_gravestone", Vector2(238, 300), "Question gravestone"],
		["prop_accepted", Vector2(640, 236), "Accepted answer"],
	],
	"cloud_district": [
		["prop_invoice", Vector2(884, 672), "Cloud invoice"],
		["prop_dashboard", Vector2(1196, 694), "Cloud dashboard"],
	],
	"gpu_mines": [
		["prop_rig", Vector2(318, 262), "Mining rig"],
		["prop_fan", Vector2(1096, 676), "Cooling fan"],
	],
	"open_source_wildlands": [
		["prop_sponsor", Vector2(1058, 630), "Sponsor button"],
		["prop_issue", Vector2(296, 846), "Open issue #4092"],
	],
	"corporate_enterprise": [
		["prop_mission", Vector2(258, 616), "Mission statement"],
		["prop_kanban", Vector2(770, 232), "Kanban board"],
	],
	"production": [
		["prop_pager", Vector2(856, 340), "On-call pager"],
		["prop_runbook", Vector2(268, 674), "Incident runbook"],
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
	# Region flavour props. NO MARKER (critique #4): the floating [E] prompt that
	# appears when the player is in range is the affordance, and a coloured chip
	# lying on the floor under a prop is a placeholder quad however small or
	# well-hued it is. _add_prop hides the scene's rect for every interactable in
	# the game, so this loop only has to place them.
	for entry in REGION_FLAVOR.get(region_id, []):
		var pr = _add_prop(props, interact_scene, entry[0], entry[1], entry[2])
		pr.one_shot = false

static func _add_prop(parent: Node2D, scene: PackedScene, id: String, pos: Vector2, text: String) -> Node:
	var node = scene.instantiate()
	node.interact_id = id
	node.interact_text = text
	node.position = pos
	# CRITIQUE #4, "flat untextured hard-edged saturated quads stamped in the
	# world: ~40px amber squares". generic_interactable.tscn ships a 32x32
	# ColorRect at Color(0.9, 0.7, 0.2, 0.8) and every interactable in the game
	# was drawing one on the floor. It is hidden here, once, for all of them:
	# the [E] prompt is the affordance and the prop is the art.
	var rect := node.get_node_or_null("ColorRect")
	if rect:
		rect.visible = false
	parent.add_child(node)
	return node
