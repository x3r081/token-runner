extends RefCounted
class_name LocalhostBuilder3D
## The Localhost apartment in three dimensions (3D_BIBLE.md §2.4, §7) — the
## first three minutes of the game, and therefore the frame every judge sees.
##
## This is a PORT of scripts/world/localhost_builder.gd, not a new room. Every
## gameplay anchor (spawn, Claude, the six story interactables, the ten flavour
## props, the eight tokens, the two bugs, PORTAL_POS) keeps its authored MAP
## PIXEL position, and every piece of furniture stands where the 2D twin drew
## its DROP SHADOW — which is the one place a top-down sprite tells you where
## its feet are. `_drop_shadow(z, Vector2(120, 272), ...)` under the fridge
## means the fridge touches the floor at map (120, 272); that is its 3D
## position, full stop. Sprite CENTRES (the fridge's own 210) are half a body
## too far north and using them would have every prop in the flat hovering.
##
## LOOK LAW: docs/VISUAL_BIBLE_V2.md, which supersedes 3D_BIBLE §7 wherever they
## disagree. The QA frame of this room was a cream floor in a cream box with
## pastel furniture on it and no dark anywhere — every surface was at Kenney's
## daylit albedo and fourteen omnis were lighting all of them. Four helpers now
## hold the line instead of four conventions: `_prop` dims every model toward
## BASE, `_batch` multiplies the floor and walls down onto their LAW 6 / LAW 2
## tones while keeping the kit's own seams, `_light` clamps and budgets the rig
## at eight, and `_glow` caps a lit face at energy 3. It is night; the lamp, the
## monitors and the city are the only bright things, which is the point.
##
## Kits: Kenney Furniture (the flat), Food (dinner), Space Station (the hardware
## this flat is actually about), City Commercial (the skyline through the
## window), Prototype (the deploy button). 1 model unit == 1 tile == 64 map px.
## The furniture kit is authored at human scale against a 0.9u character, so
## nothing here is scaled up: the apartment reads as a converted loft with a
## server corner in it, which is the only kind of flat a 25x16-tile rect can be
## at human scale — and it is a better fiction than a doll's house anyway.

## Room geometry. Mirrors LocalhostBuilder.ROOM_W / ROOM_H / TILE; kept as local
## constants rather than const-expressions reaching into the 2D class, because a
## parse failure in a world-builder is silent and total (HANDOVER §4.6b).
const ROOM_W := 25          # tiles -> 1600 px -> 25 world units on X
const ROOM_H := 16          # tiles -> 1024 px -> 16 world units on Z
const TILE := 64.0

## Where the player lands. Same value the 2D builder returns from its build():
## on the rug, Claude north-east, the way out over the right shoulder. It is a
## local `var` over there, so this is the one number that has to be duplicated.
const SPAWN := Vector2(600.0, 640.0)

## VISUAL_BIBLE localhost row: three hues and no more. Cyan is every screen in
## the flat, amber is the one lamp this person owns and the light it throws, red
## is reserved for the two things that are actually on fire — the deploy button
## and the broken service. NIGHT is the city, and it is the only light in the
## room that is not inside the room.
const ACCENT := Color("#24F0DC")
const WARM := Color("#FFB74A")
const ALARM := Color("#FF4757")
## TEXT_DIM (#7C8BB0), the palette's own cool neutral — not a saturated blue.
## The window light was (0.42, 0.55, 0.95), which is a fourth hue on every wall
## and floor face it reached (LAW 2: cyan, amber, BASE, and nothing else).
const NIGHT := Color("#7C8BB0")

## LAW 2's third value, and the one the QA frame was missing entirely: BASE is
## the DARK — the walls, the shadow, everything outside the flat. It is not a
## hue you look at, it is what the three hues are read against.
const BASE := Color("#0E0C14")

## LAW 6 — the floor is a separate, MID-VALUE material with structure, and
## Localhost's planks are the bible's own reference for it: #5A3F2A. The Kenney
## plank reads near-white out of the box (see the QA frame, where the whole flat
## is one cream field), so it is multiplied down to land on that hex; the kit's
## own plank seams and grain survive the multiply, which is the entire point of
## tinting rather than replacing the material.
const FLOOR_TONE := Color("#5A3F2A")

## What each model reads at untouched — the area-weighted mean of its base
## colour over its faces, in LINEAR light reported as sRGB, MEASURED from the
## GLBs. The furniture kit is not a mid grey: its wood is a flat (0.95, 0.80,
## 0.66), its sofa is (0.97, 0.64, 0.62) and its walls are near-white, so
## dividing by a guessed 0.55 landed the planks 1.6x over #5A3F2A.
##
## It is EVERY model this file places now, not just the five it batches: `_prop`
## needs a model's own reading to desaturate it (see `_prop_target`). A
## multiplier cannot take the colour out of a sofa; only a division by what the
## sofa actually reads at can.
const SWATCH := {
	"city-commercial/building-skyscraper-b": Color(0.585, 0.628, 0.738),
	"city-commercial/building-skyscraper-d": Color(0.627, 0.671, 0.759),
	"city-commercial/low-detail-building-a": Color(0.775, 0.778, 0.831),
	"city-commercial/low-detail-building-d": Color(0.851, 0.851, 0.899),
	"city-commercial/low-detail-building-g": Color(0.819, 0.821, 0.871),
	"food/cup": Color(0.871, 0.871, 0.918),
	"food/cup-coffee": Color(0.833, 0.831, 0.872),
	"food/mug": Color(0.597, 0.426, 0.424),
	"food/pizza": Color(0.853, 0.573, 0.323),
	"food/pizza-box": Color(0.809, 0.809, 0.879),
	"food/soda-can": Color(0.790, 0.470, 0.498),
	"food/soda-can-crushed": Color(0.704, 0.509, 0.577),
	"furniture/bedSingle": Color(0.969, 0.832, 0.786),
	"furniture/bookcaseClosedWide": Color(0.953, 0.799, 0.660),
	"furniture/bookcaseOpen": Color(0.953, 0.799, 0.660),
	"furniture/bookcaseOpenLow": Color(0.953, 0.799, 0.660),
	"furniture/books": Color(0.805, 0.718, 0.700),
	"furniture/cabinetBedDrawer": Color(0.953, 0.803, 0.669),
	"furniture/cardboardBoxClosed": Color(0.951, 0.797, 0.659),
	"furniture/cardboardBoxOpen": Color(0.951, 0.797, 0.659),
	"furniture/chairDesk": Color(0.871, 0.668, 0.656),
	"furniture/coatRackStanding": Color(0.953, 0.799, 0.660),
	"furniture/computerKeyboard": Color(0.599, 0.667, 0.667),
	"furniture/computerMouse": Color(0.589, 0.656, 0.656),
	"furniture/computerScreen": Color(0.696, 0.752, 0.755),
	"furniture/desk": Color(0.953, 0.799, 0.660),
	"furniture/floorFull": Color(0.953, 0.799, 0.660),
	"furniture/hoodModern": Color(0.676, 0.739, 0.739),
	"furniture/kitchenCabinet": Color(0.943, 0.814, 0.700),
	"furniture/kitchenCabinetDrawer": Color(0.944, 0.811, 0.694),
	"furniture/kitchenCabinetUpper": Color(0.951, 0.797, 0.659),
	"furniture/kitchenCoffeeMachine": Color(0.740, 0.795, 0.797),
	"furniture/kitchenFridge": Color(0.951, 0.974, 0.963),
	"furniture/kitchenMicrowave": Color(0.849, 0.882, 0.881),
	"furniture/kitchenSink": Color(0.936, 0.828, 0.733),
	"furniture/kitchenStove": Color(0.816, 0.778, 0.727),
	"furniture/lampRoundFloor": Color(0.958, 0.946, 0.842),
	"furniture/lampSquareTable": Color(0.970, 0.950, 0.828),
	"furniture/laptop": Color(0.648, 0.709, 0.711),
	"furniture/loungeSofaLong": Color(0.974, 0.644, 0.621),
	"furniture/loungeSofaOttoman": Color(0.974, 0.650, 0.622),
	"furniture/pillow": Color(0.975, 0.640, 0.620),
	"furniture/pillowLong": Color(0.975, 0.640, 0.620),
	"furniture/plantSmall2": Color(0.874, 0.827, 0.690),
	"furniture/pottedPlant": Color(0.730, 0.864, 0.729),
	"furniture/radio": Color(0.879, 0.793, 0.708),
	"furniture/rugDoormat": Color(0.953, 0.799, 0.660),
	"furniture/rugRectangle": Color(0.965, 0.636, 0.617),
	"furniture/rugRound": Color(0.963, 0.636, 0.616),
	"furniture/rugSquare": Color(0.963, 0.636, 0.617),
	"furniture/speaker": Color(0.889, 0.779, 0.674),
	"furniture/tableCoffee": Color(0.953, 0.799, 0.660),
	"furniture/toaster": Color(0.815, 0.863, 0.869),
	"furniture/trashcan": Color(0.826, 0.871, 0.878),
	"furniture/wall": Color(0.842, 0.857, 0.853),
	"furniture/wallDoorway": Color(0.870, 0.849, 0.821),
	"furniture/wallWindow": Color(0.875, 0.851, 0.815),
	"prototype/button-floor-round": Color(0.604, 0.563, 0.666),
	"prototype/crate": Color(0.655, 0.594, 0.629),
	"space-station/computer": Color(0.577, 0.566, 0.647),
	"space-station/computer-system": Color(0.548, 0.555, 0.652),
	"space-station/computer-wide": Color(0.606, 0.552, 0.588),
	"space-station/container": Color(0.870, 0.688, 0.569),
	"space-station/container-flat": Color(0.861, 0.689, 0.574),
	"space-station/container-tall": Color(0.855, 0.688, 0.593),
	"space-station/display-wall": Color(0.573, 0.527, 0.568),
	"space-station/display-wall-wide": Color(0.594, 0.546, 0.588),
	"space-station/floor-panel": Color(0.505, 0.531, 0.640),
	"space-station/pipe": Color(0.622, 0.651, 0.781),
}
const SWATCH_DEFAULT := Color(0.55, 0.55, 0.55)
const TINT_MAX := 1.6

## The joint between planks: LAW 6 seams 36-48 against a 64-84 floor. 0.72 of
## the floor albedo displays at about 0.57 of its value under the moon's ACES
## toe, which is a ~40 seam under a ~70 plank.
const FLOOR_SEAM_TONE := 0.72

## How far the out-of-bounds ground is lifted off BASE before it is painted —
## the same pre-compensation environment3d applies to the background, and for
## the same reason (see `_build_floor`).
const GROUND_LIFT := 0.06

## The value band a prop's albedo is COMPRESSED into by `_prop` (LAW 7: props
## desaturate toward BASE; only screens and lamps carry ACCENT or WARM, and only
## on their lit surface). The planks are authored at #5A3F2A — luminance 0.26 —
## so a band of 0.24-0.40 puts every piece of furniture in the flat within a
## step of the floor it stands on, with the lamp, the monitors and the city the
## only things above it.
##
## THIS REPLACED A MULTIPLIER, and the difference is the whole of LAW 2 here. A
## grey multiplier scales all three channels equally, so `furniture/loungeSofa-
## Long` at (0.97, 0.64, 0.62) times (0.46, 0.44, 0.52) is still a red sofa, the
## rugs are still pink and the soda cans are still a rainbow — five saturated
## hues in a room the bible allows three. `_prop_target` re-hues instead.
const PROP_L_MIN := 0.24
const PROP_L_MAX := 0.40
const PROP_SW_LO := 0.20
const PROP_SW_HI := 0.95
## How far a desaturated prop leans off neutral toward BASE. The flat's BASE is
## a cool near-black, so this is what keeps the furniture agreeing with the
## night outside the window instead of reading as studio grey.
const PROP_BASE_TILT := 0.35

## VISUAL_BIBLE_V2 LAW 4 caps a region's rig at six lights. The apartment is
## allowed eight — it is an interior full of machines that are genuinely
## switched on — and it spends exactly eight, each one motivated by something
## the player can point at. Fourteen was already restrained by 3D_BIBLE §9's
## count and still lit the flat from every direction at once, which is the
## defect: a room lit from everywhere is lit from nowhere.
const LIGHT_BUDGET := 8
const SHADOW_BUDGET := 1
## LAW 3/4 windows, clamped in `_light` and `_glow` rather than trusted.
const LIGHT_E_MIN := 0.5
const LIGHT_E_MAX := 1.2
const LIGHT_R_MIN := 6.0
const LIGHT_R_MAX := 10.0
const LIGHT_ATTEN := 1.5
## LAW 3/7, re-sized with region_builder3d's `panel()` after pass 3: over about
## 1.6 an emissive face clips the ACES shoulder and comes back WHITE whatever
## hue it was authored in. The glow threshold is 1.0, so everything here still
## blooms; it blooms in cyan and amber now instead of in white.
const GLOW_E_MAX := 1.6
static var _lights := 0
static var _shadows := 0

## Physics layer 6 ("walls") == bit value 32 (3D_BIBLE §8), mirroring the 2D
## scene's WALL_LAYER.
const WALL_LAYER := 32

## The two lanes the opening sequence walks: spawn -> Claude, and spawn/Claude
## -> the battlestation. A collider whose footprint lands in one of them is
## dropped (its MESH still draws), so no amount of later dressing can wall the
## player in during the scripted three minutes. Authored placement never trips
## these; they are a net, not a layout tool. World units, XZ.
const LANE_SPAWN_CLAUDE := Rect2(8.3, 7.9, 5.4, 2.6)
const LANE_CLAUDE_DESK := Rect2(8.3, 6.1, 3.8, 2.2)

## Cross-track actor scenes. The bible FIXES these paths and the tracks that own
## them are landing concurrently, so every one is load()ed behind exists().
const SCENES3D := "res://scenes/world3d/"

## furniture/desk is 0.384 tall, so anything that lives on a desk sits here.
const DESK_TOP := 0.384

## One-time mesh extraction cache keyed by "pack/name": a 400-tile floor must
## instantiate its GLB once, not four hundred times. `_aabb_cache` holds the
## real measured bounds of the same models (see _aabb).
static var _parts_cache: Dictionary = {}
static var _aabb_cache: Dictionary = {}

## food/pizza-box ships OPEN (its lid node stands at -120 deg, 0.88u tall).
## Folded flat it is a 0.18u closed box: base 0..0.09, lid 0.09..0.18.
const PIZZA_BOX_H := 0.18

## ...and it is 0.94 UNITS ACROSS at scale 1.0, which at this project's 1u = 2 m
## is a pizza box nearly two metres wide — as wide as the sofa it is stacked
## next to and five times a laptop. That stack is what the pass-3 critic was
## looking at when they wrote "laptops larger than the sofa": the dark slabs in
## the bottom-right of the Localhost frame are five of these. 0.45 makes it a
## 42 cm box, which is a pizza box. `food/pizza` is the same model family and
## takes the same scale, or the slice ends up bigger than the box.
const PIZZA_SCALE := 0.45


static func build(root: Node3D) -> Dictionary:
	_lights = 0
	_shadows = 0
	var size := Vector2(ROOM_W * TILE, ROOM_H * TILE)
	_build_floor(root)
	_build_walls(root)
	_build_skyline(root)
	_build_kitchen(root)
	_build_battlestation(root)
	_build_gpu_rig(root)
	_build_server_corner(root)
	_build_lounge(root)
	_build_bedroom(root)
	_build_clutter(root)
	_build_cables(root)
	_build_lighting(root)
	_build_atmosphere(root)
	_populate_gameplay(root)
	return {"spawn": SPAWN, "size": size}


# ------------------------------------------------------------- helpers ------

## A model's REAL bounds, measured off its imported meshes with every node
## transform applied, cached per key. NOT Map3D.bounds(): the manifest stores
## the raw glTF accessor bounds and ignores node scale and child transforms, so
## it is wrong for every model whose GLB is not a single unscaled node —
## furniture/laptop is really 0.44x its manifest size, furniture/trashcan is
## 0.43u tall not 0.91, bedSingle's manifest box is its cover's unrotated local
## box (1.6u wide for a 0.57u bed), space-station/container-tall is a symmetric
## 0.6u square not the lopsided 0.8u the manifest claims. A prop centred off
## those numbers lands off its own anchor by up to half a metre, and a collider
## sized off them fences off floor nothing stands on. Falls back to the
## manifest only when the model is missing altogether.
static func _aabb(key: String) -> AABB:
	if _aabb_cache.has(key):
		var cached: AABB = _aabb_cache[key]
		return cached
	var box := AABB()
	var first := true
	for part: Dictionary in _mesh_parts(key):
		var mesh: Mesh = part["mesh"]
		var xf: Transform3D = part["xform"]
		var b: AABB = xf * mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		var m := Map3D.bounds(key)
		var mn: Array = m.get("min", [0.0, 0.0, 0.0])
		var mx: Array = m.get("max", [1.0, 1.0, 1.0])
		var p := Vector3(float(mn[0]), float(mn[1]), float(mn[2]))
		box = AABB(p, Vector3(float(mx[0]), float(mx[1]), float(mx[2])) - p)
	_aabb_cache[key] = box
	return box


## XZ centre of a model's real bounds. Kenney origins are floor-anchored but
## NOT centred — furniture/desk runs x -0.01..0.724, furniture/floorFull runs
## z -1..0 — so a builder that ignores this scatters every prop by half its own
## width. Everything below places by FOOTPRINT CENTRE and lets this correct it.
static func _centre(key: String) -> Vector3:
	var b := _aabb(key)
	return Vector3(b.position.x + b.size.x * 0.5, 0.0, b.position.z + b.size.z * 0.5)


## Top of a model's real bounds — its height above the floor.
static func _top(key: String) -> float:
	return _aabb(key).end.y


## Place one Kenney model with its footprint centred on `px` (MAP PIXELS — the
## lingua franca of this project) at height `y`, yawed `yaw_deg` about +Y.
##
## Yaw convention throughout this file: 0 faces +Z (map south, toward the
## camera), 180 faces the north wall, -90 faces west, +90 faces east. The kits
## are authored front-to-+Z, so a piece standing against the north wall and
## looking into the room wants yaw 0.
static func _prop(parent: Node3D, key: String, px: Vector2, y: float = 0.0,
		yaw_deg: float = 0.0, model_scale: float = 1.0,
		tint_col: Color = Color.WHITE) -> Node3D:
	var n := Map3D.model(key)
	if n == null:
		return null
	# The model goes UNDER a holder rather than being transformed itself: a GLB
	# root may carry its own transform from the importer, and overwriting that
	# would silently deform the prop. The holder is what gets posed, and it is
	# what callers get back.
	var holder := Node3D.new()
	holder.name = n.name
	var rot := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	var c := _centre(key)
	# The centring offset travels through the same rotation and scale the model
	# does, or a yawed prop lands half a body off its own anchor.
	var off := rot * Vector3(-c.x, 0.0, -c.z) * model_scale
	holder.transform = Transform3D(
		rot.scaled(Vector3(model_scale, model_scale, model_scale)),
		Map3D.to3d(px, y) + off)
	holder.add_child(n)
	# LAW 7, by DIVISION rather than by multiplication (see `_prop_target`): the
	# model's mean is landed on a desaturated target computed from its own
	# swatch, and its internal tones survive as ratios around it.
	Map3D.tint(n, _tint_to(_prop_target(key, tint_col), key))
	parent.add_child(holder)
	return holder


## A pizza box, open or closed. The Food kit only ships the box OPEN — its
## "lid" node stands at -120 degrees about Z, 0.88u tall — so a stack of them
## placed as-is is a stack of lids stabbing through each other. `closed` folds
## the lid flat onto the base: the lid mesh is centred on its own origin, so a
## half-turn about Z plus a lift of two lid heights is the whole fold.
static func _pizza_box(parent: Node3D, px: Vector2, y: float, yaw_deg: float,
		closed: bool, tint_col: Color = Color.WHITE) -> Node3D:
	var holder := _prop(parent, "food/pizza-box", px, y, yaw_deg, PIZZA_SCALE, tint_col)
	if holder == null or not closed:
		return holder
	var lid := holder.find_child("lid", true, false)
	if lid is Node3D:
		(lid as Node3D).transform = Transform3D(
			Basis(Vector3.BACK, PI), Vector3(0.0, PIZZA_BOX_H, 0.0))
	return holder


## A box collider on the walls layer. `px` is the footprint centre in MAP
## PIXELS; `size_xz` and `height` are WORLD UNITS (they come from model bounds).
## Silently skipped when it would block one of the two opening walk lanes.
static func _solid(parent: Node3D, px: Vector2, size_xz: Vector2, height: float) -> void:
	var c := Vector2(px.x / Map3D.PX, px.y / Map3D.PX)
	var foot := Rect2(c - size_xz * 0.5, size_xz)
	if foot.intersects(LANE_SPAWN_CLAUDE) or foot.intersects(LANE_CLAUDE_DESK):
		return
	var body := StaticBody3D.new()
	body.collision_layer = WALL_LAYER
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size_xz.x, height, size_xz.y)
	shape.shape = box
	shape.position = Vector3(0.0, height * 0.5, 0.0)
	body.add_child(shape)
	body.position = Map3D.to3d(px, 0.0)
	parent.add_child(body)


## An unshaded emissive quad: every screen face, status strip, sticky note and
## warning panel in the flat. These are what actually BLOOM; the Kenney colormap
## underneath stays flat and matte, exactly as the look recipe asks.
## `pitch_deg` of -90 lays one flat on the floor (the deploy button's disc, the
## power strip's LED).
##
## Energy is capped at 3 (VISUAL_BIBLE_V2 LAW 3/7 — a lit face is 2-3, not
## 3D_BIBLE §7's old 4-7). At 6.5 a 30 cm monitor was clipping the ACES curve
## and blooming across a third of the frame, which is how the flat ended up with
## no blacks: the bright things were not brighter than everything else, they
## were simply washing everything else out.
static func _glow(parent: Node3D, px: Vector2, y: float, size: Vector2,
		color: Color, energy: float, yaw_deg: float = 0.0,
		pitch_deg: float = 0.0) -> MeshInstance3D:
	energy = clampf(energy, 0.0, GLOW_E_MAX)
	var q := QuadMesh.new()
	q.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var basis := Basis(Vector3.UP, deg_to_rad(yaw_deg)) * Basis(Vector3.RIGHT, deg_to_rad(pitch_deg))
	mi.transform = Transform3D(basis, Map3D.to3d(px, y))
	parent.add_child(mi)
	return mi


## A motivated light. Budgeted on the way IN (the 2D file learned this at
## sixteen lights), CLAMPED into LAW 4's window on the way in too, and
## shadow-capped at one, which the desk lamp spends.
static func _light(parent: Node3D, px: Vector2, y: float, color: Color,
		energy: float, range_u: float, shadows: bool = false) -> OmniLight3D:
	if _lights >= LIGHT_BUDGET:
		return null
	_lights += 1
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = clampf(energy, LIGHT_E_MIN, LIGHT_E_MAX)
	l.omni_range = clampf(range_u, LIGHT_R_MIN, LIGHT_R_MAX)
	l.omni_attenuation = LIGHT_ATTEN
	l.light_specular = 0.12
	if shadows and _shadows < SHADOW_BUDGET:
		_shadows += 1
		l.shadow_enabled = true
	l.position = Map3D.to3d(px, y)
	parent.add_child(l)
	return l


## Every MeshInstance3D inside a model, flattened with its accumulated
## transform, so the whole model can be drawn through a MultiMesh (3D_BIBLE §7:
## floors are MultiMesh, never three hundred MeshInstance3Ds).
static func _mesh_parts(key: String) -> Array:
	if _parts_cache.has(key):
		return _parts_cache[key]
	var parts: Array = []
	var root := Map3D.model(key)
	if root:
		_collect_parts(root, Transform3D.IDENTITY, parts)
		# Not in the tree, so free() (never queue_free) — the Meshes themselves
		# stay alive on Map3D's cached PackedScene.
		root.free()
	_parts_cache[key] = parts
	return parts


static func _collect_parts(n: Node, xf: Transform3D, out: Array) -> void:
	var here := xf
	if n is Node3D:
		here = xf * (n as Node3D).transform
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh:
			out.append({"mesh": mi.mesh, "xform": here, "mat": mi.material_override})
	for c in n.get_children():
		_collect_parts(c, here, out)


## What model `key` reads at untouched (SWATCH), or the mid grey if unmeasured.
static func _swatch(key: String) -> Color:
	var c: Color = SWATCH.get(key, SWATCH_DEFAULT)
	return c


## sRGB relative luminance.
static func _lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b

## `c` normalised so its brightest channel is 1.0 — its hue, without its value.
static func _hue_of(c: Color) -> Color:
	var m := maxf(maxf(c.r, c.g), maxf(c.b, 0.0001))
	return Color(c.r / m, c.g / m, c.b / m, 1.0)

## The albedo `_prop` draws model `key` at, given what the caller asked for: the
## model's own MEASURED reading reduced to a luminance, remapped into the band
## furniture is allowed to occupy, and re-hued — toward BASE-leaned neutral when
## the caller asked for nothing, toward the caller's own colour when it did (the
## dead plant, the hazard mat, the greasy pizza boxes keep their story and lose
## their saturation). See PROP_L_MIN for why a multiplier could not do this.
static func _prop_target(key: String, want: Color) -> Color:
	var sw := _swatch(key)
	var t := clampf((_lum(sw) - PROP_SW_LO) / (PROP_SW_HI - PROP_SW_LO), 0.0, 1.0)
	var l := lerpf(PROP_L_MIN, PROP_L_MAX, t)
	if want == Color.WHITE:
		var base_hue := _hue_of(BASE)
		var grey := Color(l, l, l, 1.0)
		return grey.lerp(Color(base_hue.r * l, base_hue.g * l, base_hue.b * l, 1.0),
			PROP_BASE_TILT)
	var hue := _hue_of(want)
	var hl := maxf(_lum(hue), 0.05)
	var k := clampf(l / hl, 0.0, 1.0)
	return Color(hue.r * k, hue.g * k, hue.b * k, 1.0)

## The albedo multiplier that lands model `key` ON `target` (sRGB) once the GPU
## has multiplied it into the model's own material. Divided in LINEAR space —
## the space the multiply happens in, since albedo_color is converted on upload
## — so lin(tint) * lin(swatch) == lin(target) exactly on average, and the
## model's own tones survive as ratios around it.
static func _tint_to(target: Color, key: String) -> Color:
	var sw := _swatch(key).srgb_to_linear()
	var want := target.srgb_to_linear()
	var t := Color(want.r / maxf(sw.r, 0.002), want.g / maxf(sw.g, 0.002),
		want.b / maxf(sw.b, 0.002), 1.0).linear_to_srgb()
	return Color(minf(t.r, TINT_MAX), minf(t.g, TINT_MAX), minf(t.b, TINT_MAX), 1.0)


## `mesh` with every surface's material duplicated and multiplied by `tint`.
## A MultiMeshInstance3D has only a whole-instance `material_override`, so the
## only way to tint a multi-surface mesh and KEEP its surfaces is to duplicate
## the ArrayMesh and set each surface's material on the copy. This is what lets
## furniture/wall keep its trim and furniture/wallWindow keep its GLASS — the
## previous whole-instance matte turned the window wall's glass into an opaque
## slab of wall tone, and the city behind the hero window with it. Surfaces
## that are not StandardMaterial3D get a matte at `fallback`. Returns null for
## a mesh that cannot be duplicated this way.
static func _tinted_mesh(mesh: Mesh, tint: Color, fallback: Color) -> Mesh:
	if not (mesh is ArrayMesh):
		return null
	var dup: ArrayMesh = (mesh as ArrayMesh).duplicate()
	for i in dup.get_surface_count():
		var src: Material = dup.surface_get_material(i)
		var m: StandardMaterial3D
		if src is StandardMaterial3D:
			m = (src as StandardMaterial3D).duplicate()
			m.albedo_color = m.albedo_color * tint
		else:
			m = Map3D.matte(fallback)
		dup.surface_set_material(i, m)
	return dup


## Draw `xforms` copies of a model through one MultiMesh per sub-mesh.
##
## `tint` multiplies the model's OWN materials (duplicates of them, per surface,
## on a duplicated mesh — see _tinted_mesh — so the shared import is never
## mutated), which is how the floor keeps its plank seams and the window wall
## its glass while losing two stops of value. A flat `override` throws the
## structure away with the brightness, and LAW 6 wants the structure kept; it
## is only used where a caller asks for one (the lino, the city).
static func _batch(parent: Node3D, key: String, xforms: Array[Transform3D],
		node_name: String, override: Material = null,
		tint: Color = Color.WHITE) -> void:
	if xforms.is_empty():
		return
	var parts := _mesh_parts(key)
	var idx := 0
	for part: Dictionary in parts:
		var mesh: Mesh = part["mesh"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = xforms.size()
		var local: Transform3D = part["xform"]
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i] * local)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s%d" % [node_name, idx]
		mmi.multimesh = mm
		var mat: Material = override
		if mat == null and tint != Color.WHITE:
			var sw := _swatch(key)
			var flat := Color(tint.r * sw.r, tint.g * sw.g, tint.b * sw.b, 1.0)
			var tinted := _tinted_mesh(mesh, tint, flat)
			if tinted != null:
				mm.mesh = tinted
			else:
				mat = Map3D.matte(flat)
		if mat == null and tint == Color.WHITE:
			mat = part["mat"]
		if mat:
			mmi.material_override = mat
		parent.add_child(mmi)
		idx += 1


## Batched emissive quads — the lit windows of the city, ~150 of them for the
## cost of one draw call.
static func _glow_batch(parent: Node3D, xforms: Array[Transform3D], size: Vector2,
		color: Color, energy: float, node_name: String) -> void:
	if xforms.is_empty():
		return
	# Same ceiling as `_glow`: these were the one emissive path in the flat that
	# skipped the clamp, at 2.2-2.4, which is over the ACES shoulder and white.
	energy = clampf(energy, 0.0, GLOW_E_MAX)
	var q := QuadMesh.new()
	q.size = size
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = q
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)


## Kenney floor tiles butt edge to edge and the joint disappears. Each one is
## inset by this about its own footprint centre, so the seam plane under the
## flat shows through as a joint — LAW 6's "visible joints", drawn as geometry
## rather than painted on as a floor overlay. The flat shows ~14u across 1920px
## (~137px a unit), so 1.5% is a 2px line; the old 2.5% was a 3-4px grid.
const FLOOR_SEAM := 0.985

## One floor tile of `key` covering map cell (gx, gz), top surface at y = 0.
static func _tile_xform(key: String, gx: int, gz: int) -> Transform3D:
	var c := _centre(key)
	var mid := Vector3(float(gx) + 0.5, 0.0, float(gz) + 0.5)
	# Scale about the CELL centre, not the model origin: these origins are
	# corner-anchored (floorFull runs z -1..0), so scaling in place would walk
	# every tile half a seam north-west and open a gap along two walls.
	var off := (Vector3(-c.x, 0.0, -c.z)) * FLOOR_SEAM
	return Transform3D(Basis.IDENTITY.scaled(Vector3(FLOOR_SEAM, 1.0, FLOOR_SEAM)),
		mid + off + Vector3(0.0, -_top(key), 0.0))


static func _group(root: Node3D, node_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	root.add_child(n)
	return n


# -------------------------------------------------------------- floor -------

## Three floor MATERIALS, not one noise field (VISUAL_BIBLE round 4, rule 1:
## structure before noise — a player must see where to walk in a one-second
## glance at a static frame). Planks everywhere, kitchen lino in the north-west,
## space-station panel decking under the server corner — laid flush at y 0, so
## nothing standing on it sinks. The room's zones read as zones before a single
## prop is placed, and it costs three draw calls.
static func _build_floor(root: Node3D) -> void:
	var z := _group(root, "Floor")
	# The dark the flat stands in. 90x90 units centred on a 25x16 room, so it
	# runs 32+ units past every wall — the camera cannot find its edge at any
	# yaw, and no gap between a parapet and a rug can ever show the background
	# through the floor.
	#
	# LIT, and LIFTED off BASE by GROUND_LIFT. Painted at the raw hex this plane
	# rendered at about 4/255 through the ACES toe — the black wedge past the
	# room's south-east corner in the pass-3 frame, and the same defect
	# region_builder3d's void plane had. Lifted it lands at ~17, which is what
	# environment3d paints the BACKGROUND at, so ground and sky beyond the flat
	# are one continuous dark with no seam in it.
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var gm := PlaneMesh.new()
	gm.size = Vector2(90.0, 90.0)
	ground.mesh = gm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = BASE.lightened(GROUND_LIFT)
	gmat.roughness = 1.0
	gmat.metallic = 0.0
	ground.material_override = gmat
	ground.position = Vector3(ROOM_W * 0.5, -0.012, ROOM_H * 0.5)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	z.add_child(ground)
	# The joint the planks show between them: room-sized, a step darker than
	# the floor (FLOOR_SEAM_TONE), a hair above the BASE ground. BASE itself
	# displays at ~4/255 under this grade, which as a seam is a black grid.
	var seams := MeshInstance3D.new()
	seams.name = "Seams"
	var sm := PlaneMesh.new()
	sm.size = Vector2(float(ROOM_W), float(ROOM_H))
	seams.mesh = sm
	seams.material_override = Map3D.matte(Color(FLOOR_TONE.r * FLOOR_SEAM_TONE,
		FLOOR_TONE.g * FLOOR_SEAM_TONE, FLOOR_TONE.b * FLOOR_SEAM_TONE, 1.0))
	seams.position = Vector3(ROOM_W * 0.5, -0.006, ROOM_H * 0.5)
	seams.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	z.add_child(seams)

	var plank := "furniture/floorFull"
	var panel := "space-station/floor-panel"
	var has_panel := Map3D.has_model(panel)
	var planks: Array[Transform3D] = []
	var lino: Array[Transform3D] = []
	var panels: Array[Transform3D] = []
	for gx in ROOM_W:
		for gz in ROOM_H:
			if has_panel and gx >= 19 and gz <= 5:
				panels.append(_tile_xform(panel, gx, gz))
			elif gx <= 5 and gz <= 4:
				lino.append(_tile_xform(plank, gx, gz))
			else:
				planks.append(_tile_xform(plank, gx, gz))
	# Two floor MATERIALS at two tones (LAW 6): the planks the flat lives on, and
	# the harder surfaces — kitchen lino, server decking — a legal step apart
	# from them and a little cooler. The plank tint is the reference hex divided
	# by what the kit's wood actually reads at (SWATCH — a flat orange, not a mid
	# grey), so the multiply LANDS on #5A3F2A instead of 1.6x over it.
	_batch(z, plank, planks, "Planks", null, _tint_to(FLOOR_TONE, plank))
	# Lino is the same mesh under a flat cool override: a kitchen floor is a
	# different SURFACE, and one material buys that for nothing. Mid-value, not
	# void — the old 0.20 grey was BASE being used as a floor again.
	_batch(z, plank, lino, "Lino", Map3D.matte(Color(0.26, 0.27, 0.30)))
	# The decking lands a legal 6% over the planks' value and cooler: #5A3F2A is
	# luminance 0.264, this is 0.28.
	_batch(z, panel, panels, "ServerPanels", null, _tint_to(Color(0.27, 0.28, 0.31), panel))
	# The battlestation rug. The 2D twin's int_rug is 320x224 px, so the kit rug
	# is scaled to that exact footprint instead of dropped in at doll size. Rugs
	# are the largest single surfaces in the flat after the floor itself, so they
	# take the floor's discipline: desaturated, a step off the planks, no colour.
	_prop(z, "furniture/rugRectangle", Vector2(560.0, 600.0), 0.002, 0.0, 3.2,
		Color(0.72, 0.68, 0.66))
	_prop(z, "furniture/rugRound", Vector2(760.0, 780.0), 0.002, 0.0, 2.4,
		Color(0.72, 0.68, 0.66))
	_prop(z, "furniture/rugSquare", Vector2(1320.0, 860.0), 0.002, 0.0, 2.2,
		Color(0.72, 0.68, 0.66))
	# Hazard mat under the deploy button, in the room's WARM (amber is what a
	# hazard mat is anyway). It was a saturated red — HOSTILE is for the button's
	# own tell and the outage, not for a metre and a half of floor (LAW 2).
	_prop(z, "furniture/rugDoormat", Vector2(760.0, 380.0), 0.003, 0.0, 1.6, WARM)


# -------------------------------------------------------------- walls -------

## Four walls, two heights. North and east run full height (1.29u) because the
## camera — FOV 34, pitch -56, yaw -18 — sits south-west of the player and looks
## north-east, so those are the walls it SEES; south and west are cut to a 0.55u
## parapet so the near edge of the room never draws a bar across the player's
## own head. Colliders are full height on all four regardless: the parapet is a
## drawing decision, not a gameplay one.
##
## The north wall carries the hero piece — nine bays of furniture/wallWindow
## between x 4 and x 13, with the city behind them. That window is the single
## reason this flat looks like a place instead of a box.
static func _build_walls(root: Node3D) -> void:
	var z := _group(root, "Walls")
	var full: Array[Transform3D] = []
	var window: Array[Transform3D] = []
	var doorway: Array[Transform3D] = []
	var low: Array[Transform3D] = []
	var parapet := Basis.IDENTITY.scaled(Vector3(1.0, 0.43, 1.0))
	var yaw180 := Basis(Vector3.UP, PI)
	var yaw_w := Basis(Vector3.UP, PI * 0.5)
	var yaw_e := Basis(Vector3.UP, -PI * 0.5)
	# North (z = 0): furniture/wall is x 0..1, z -0.05..0, so an untranslated
	# piece already sits just outside the room with its face at z = 0.
	for gx in ROOM_W:
		var t := Transform3D(Basis.IDENTITY, Vector3(gx, 0.0, 0.0))
		if gx >= 4 and gx <= 12:
			window.append(t)
		else:
			full.append(t)
	# East (x = 25), yawed -90 so its face points west into the room. Two bays
	# at z 7..9 are a doorway: the fiction the exit portal stands in front of.
	for gz in ROOM_H:
		var te := Transform3D(yaw_e, Vector3(ROOM_W, 0.0, gz))
		if gz == 7 or gz == 8:
			doorway.append(te)
		else:
			full.append(te)
	for gx2 in ROOM_W:
		low.append(Transform3D(yaw180 * parapet, Vector3(gx2 + 1, 0.0, ROOM_H)))
	for gz2 in ROOM_H:
		low.append(Transform3D(yaw_w * parapet, Vector3(0.0, 0.0, gz2 + 1)))
	# LAW 2: the walls ARE the BASE. They were untinted, which is why the QA
	# frame has a cream box around a cream floor and no dark anywhere for the
	# lamp, the monitors or the city to be bright against. A little of the floor
	# tone is lerped in so masonry and planks read as one room, and the parapet
	# takes a step down again because it is the near edge, below the eye.
	var wall_tone := BASE.lerp(FLOOR_TONE, 0.35)
	_batch(z, "furniture/wall", full, "WallFull", null, _tint_to(wall_tone, "furniture/wall"))
	_batch(z, "furniture/wallWindow", window, "WallWindow", null,
		_tint_to(wall_tone, "furniture/wallWindow"))
	_batch(z, "furniture/wallDoorway", doorway, "WallDoorway", null,
		_tint_to(wall_tone, "furniture/wallDoorway"))
	_batch(z, "furniture/wall", low, "WallParapet", null,
		_tint_to(Color(wall_tone.r * 0.7, wall_tone.g * 0.7, wall_tone.b * 0.7, 1.0),
			"furniture/wall"))
	_wall_collider(z, Vector2(ROOM_W * TILE * 0.5, -8.0), Vector2(ROOM_W + 1.0, 0.25))
	_wall_collider(z, Vector2(ROOM_W * TILE * 0.5, ROOM_H * TILE + 8.0), Vector2(ROOM_W + 1.0, 0.25))
	_wall_collider(z, Vector2(-8.0, ROOM_H * TILE * 0.5), Vector2(0.25, ROOM_H + 1.0))
	_wall_collider(z, Vector2(ROOM_W * TILE + 8.0, ROOM_H * TILE * 0.5), Vector2(0.25, ROOM_H + 1.0))
	# Ceiling rib stubs: the 3D twin of _build_framing's beam row, which in 2D
	# lives ONLY in the top band of the frame. They hang off the north wall and
	# stop 1.4u in, because a rib spanning the room at y 1.42 draws a dark bar
	# across whoever walks under it (VISUAL_BIBLE: comedy never beats clarity).
	var beam := BoxMesh.new()
	beam.size = Vector3(0.22, 0.18, 1.4)
	var beam_mat := Map3D.matte(Color(0.05, 0.05, 0.08))
	for i in 5:
		var mi := MeshInstance3D.new()
		mi.name = "Beam%d" % i
		mi.mesh = beam
		mi.material_override = beam_mat
		mi.position = Vector3(2.8 + float(i) * (ROOM_W - 5.6) / 4.0, 1.42, 0.7)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		z.add_child(mi)
	# The two west-wall posters and SHIP OR DIE up the east wall, at the 2D
	# twin's own x 30 / y 420, 620 and (ROOM_W*TILE - 62, 300). Printed matter:
	# barely emissive, because LAW 3 says signs do not glow.
	for py: float in [420.0, 620.0]:
		_glow(z, Vector2(6.0, py), 0.78, Vector2(0.5, 0.7), Color(0.18, 0.20, 0.30), 0.35, 90.0)
	_glow(z, Vector2(ROOM_W * TILE - 6.0, 300.0), 0.82, Vector2(0.5, 0.7),
		Color(0.16, 0.24, 0.22), 0.35, -90.0)
	# The whiteboard of doom, wall-mounted at the 2D twin's (950, 60). Its
	# interactable (prop_whiteboard) stands at (950, 138), which is where the
	# player can actually get to — the same offset the 2D room had. The display
	# is 0.38u deep with its back at -0.19 from centre, so a centre at z 0.19
	# (12 px) puts that back ON the wall face rather than a third of a tile off
	# it. Its screen is the +Z face at 0.05 from the model origin, y 0.18..0.28
	# — the glow sits 1 px south of the footprint centre, on that face.
	_prop(z, "space-station/display-wall-wide", Vector2(950.0, 12.5), 0.62, 0.0)
	_glow(z, Vector2(950.0, 13.5), 0.85, Vector2(0.50, 0.24), ACCENT * 0.9, 3.2)


static func _wall_collider(parent: Node3D, px: Vector2, size_xz: Vector2) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = WALL_LAYER
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size_xz.x, 3.0, size_xz.y)
	shape.shape = box
	shape.position = Vector3(0.0, 1.5, 0.0)
	body.add_child(shape)
	body.position = Map3D.to3d(px, 0.0)
	parent.add_child(body)


# ------------------------------------------------------------- skyline ------

## The city, through the window wall. Three depth ranks of low-detail commercial
## blocks and skyscrapers, flattened to a near-black silhouette by one material
## override, with their lit windows drawn as two batched emissive quad fields
## (warm and cyan). Everything here is deterministic — one seeded RNG, no Time,
## no randomize() — so two builds of the flat are the same flat.
static func _build_skyline(root: Node3D) -> void:
	var z := _group(root, "Skyline")
	# The ground the city stands on. It is now BELOW the flat's own lifted ground
	# plane rather than a hair above it — that plane already runs 32 units past
	# every wall and is the thing the window actually shows under the skyline, so
	# a second, near-black slab at the same height was a z-fight waiting to
	# happen and a black stripe if it won. This is the plinth under the towers,
	# nothing more.
	var ground := MeshInstance3D.new()
	ground.name = "CityGround"
	var gm := BoxMesh.new()
	gm.size = Vector3(90.0, 0.4, 46.0)
	ground.mesh = gm
	ground.material_override = Map3D.matte(BASE.lightened(GROUND_LIFT * 0.5))
	ground.position = Vector3(ROOM_W * 0.5, -0.30, -18.0)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	z.add_child(ground)

	var rng := RandomNumberGenerator.new()
	rng.seed = 0x10CA1105
	var keys := ["city-commercial/low-detail-building-a",
		"city-commercial/low-detail-building-d",
		"city-commercial/low-detail-building-g",
		"city-commercial/building-skyscraper-b",
		"city-commercial/building-skyscraper-d"]
	var buckets: Dictionary = {}
	for k: String in keys:
		# A fresh typed array per key — one shared empty would put every
		# building in every bucket.
		var fresh: Array[Transform3D] = []
		buckets[k] = fresh
	var warm_windows: Array[Transform3D] = []
	var cool_windows: Array[Transform3D] = []
	# rank: [z centre, z jitter, scale min, scale max, count, first key index]
	var ranks := [
		[-9.0, 1.6, 1.6, 2.6, 16, 0],
		[-16.0, 2.4, 2.4, 3.6, 14, 0],
		[-26.0, 3.0, 2.0, 3.2, 10, 3],
	]
	var rank_i := 0
	for rank: Array in ranks:
		var zc := float(rank[0])
		var zj := float(rank[1])
		var smin := float(rank[2])
		var smax := float(rank[3])
		var count := int(rank[4])
		var kfirst := int(rank[5])
		var span := 2 if kfirst == 0 else 1
		for i in count:
			var key: String = keys[kfirst + rng.randi_range(0, span)]
			if not Map3D.has_model(key):
				continue
			var s := rng.randf_range(smin, smax)
			var bx := -8.0 + float(i) * (44.0 / float(maxi(count - 1, 1))) + rng.randf_range(-1.1, 1.1)
			var bz := zc + rng.randf_range(-zj, zj)
			var yaw := float(rng.randi_range(0, 3)) * PI * 0.5
			var c := _centre(key)
			var rot := Basis(Vector3.UP, yaw)
			var xf := Transform3D(
				rot.scaled(Vector3(s, s, s)),
				Vector3(bx, 0.0, bz) + rot * Vector3(-c.x, 0.0, -c.z) * s)
			var bucket: Array[Transform3D] = buckets[key]
			bucket.append(xf)
			# Lit windows on the face that points at the flat (+Z). LAW 8 puts the
			# ceiling at sixty lit windows in WARM and ACCENT — "not confetti" —
			# and the old rule (up to seven rows on every one of forty buildings)
			# was three hundred. One or two per building on the two NEAR ranks;
			# the far rank stays a pure silhouette, which is also what gives the
			# skyline its depth.
			if rank_i >= 2:
				continue
			var sz := _aabb(key).size
			var w := sz.x * s
			var h := sz.y * s
			var face := bz + sz.z * s * 0.5 + 0.03
			var rows := clampi(int(h / 1.7), 1, 2)
			for r in rows:
				var wx := bx + rng.randf_range(-w * 0.32, w * 0.32)
				var wy := h * (0.12 + 0.78 * (float(r) + rng.randf_range(0.1, 0.9)) / float(rows))
				var wxf := Transform3D(Basis.IDENTITY, Vector3(wx, wy, face))
				if rng.randf() < 0.62:
					warm_windows.append(wxf)
				else:
					cool_windows.append(wxf)
		rank_i += 1
	# One flat dark material for the whole city: a distant skyline is a
	# silhouette with lights in it, and the colormap would only muddy it. Sized
	# against the moon, not the void: at ~0.21 albedo a face the moon catches
	# displays in the mid-20s and a face it misses at 2-4, against a background
	# of ~11 — a skyline with a moonlit edge. BASE x 1.9 (0.10-0.15) displayed
	# at 2-15 on every face: a city the window could not show.
	var city := Map3D.matte(BASE.lerp(Color(0.34, 0.33, 0.36, 1.0), 0.5))
	for k2: String in keys:
		_batch(z, k2, buckets[k2], "City_" + k2.get_file(), city)
	# LAW 8: lit windows in WARM and ACCENT only — the room's own two hues, not a
	# third amber and a fourth sky-blue — at the same energy as any other lit
	# face in the flat (GLOW_E_MAX; `_glow_batch` clamps too).
	_glow_batch(z, warm_windows, Vector2(0.10, 0.15), WARM, GLOW_E_MAX, "CityWindowsWarm")
	_glow_batch(z, cool_windows, Vector2(0.10, 0.15), ACCENT, GLOW_E_MAX, "CityWindowsCool")


# ------------------------------------------------------------- kitchen ------

## Two counter runs. One against the north wall (sink, stove, uppers, hood,
## microwave), one as a peninsula at z 4.3 — which is where the 2D twin's fridge
## and coffee-machine drop shadows land (y 272 and 268, the same line), so that
## peninsula was always in the drawing, it just had no depth to stand in.
static func _build_kitchen(root: Node3D) -> void:
	var z := _group(root, "Kitchen")
	var run := ["furniture/kitchenCabinet", "furniture/kitchenSink",
		"furniture/kitchenCabinetDrawer", "furniture/kitchenStove",
		"furniture/kitchenCabinet", "furniture/kitchenCabinetDrawer"]
	for i in run.size():
		# Base cabinets are 0.48 deep with their back at z 0.03, so a footprint
		# centre at z 0.24 puts them flush against the north wall.
		var cx := (0.62 + float(i) * 0.44) * TILE
		_prop(z, run[i], Vector2(cx, 0.24 * TILE), 0.0, 0.0)
		if i != 3:
			_prop(z, "furniture/kitchenCabinetUpper", Vector2(cx, 0.13 * TILE), 0.95, 0.0)
	_prop(z, "furniture/hoodModern", Vector2((0.62 + 3.0 * 0.44) * TILE, 0.15 * TILE), 0.95, 0.0)
	_prop(z, "furniture/kitchenMicrowave", Vector2((0.62 + 4.0 * 0.44) * TILE, 0.20 * TILE), 0.45, 0.0)
	_solid(z, Vector2(1.95 * TILE, 0.24 * TILE), Vector2(2.9, 0.5), 0.9)

	# The fridge, at its 2D drop shadow (120, 272). prop_fridge stands at
	# (150, 275), half a unit east of it — well inside the player's reach.
	_prop(z, "furniture/kitchenFridge", Vector2(120.0, 272.0), 0.0, 0.0)
	_solid(z, Vector2(120.0, 272.0), Vector2(0.46, 0.34), 0.92)
	# The peninsula, doors facing the working side, and the load-bearing
	# appliance in this person's life on top of it at the 2D twin's (230, 268).
	for j in 4:
		_prop(z, "furniture/kitchenCabinet", Vector2((2.6 + float(j) * 0.44) * TILE, 4.34 * TILE), 0.0, 180.0)
	_solid(z, Vector2(3.48 * TILE, 4.34 * TILE), Vector2(1.8, 0.5), 0.5)
	_prop(z, "furniture/kitchenCoffeeMachine", Vector2(230.0, 268.0), 0.45, 0.0)
	_prop(z, "food/mug", Vector2(268.0, 272.0), 0.45, 0.0)
	_prop(z, "food/cup-coffee", Vector2(292.0, 276.0), 0.45, 0.0)
	_prop(z, "furniture/toaster", Vector2(196.0, 268.0), 0.45, 0.0)
	# Empty energy drinks on the boards, at the 2D twin's own five positions.
	# Every other one is crushed and lying down, which is the difference between
	# litter and a tidy row of cans.
	for i2 in 5:
		var cpos := Vector2(185.0 + float(i2) * 22.0, 366.0 + float(i2 % 2) * 14.0)
		var key := "food/soda-can-crushed" if i2 % 2 == 0 else "food/soda-can"
		var can := _prop(z, key, cpos, 0.0, float(i2) * 47.0)
		if can and i2 % 2 == 0:
			can.rotation = Vector3(deg_to_rad(88.0), can.rotation.y, 0.0)
			can.position.y = 0.11
	# A pizza box balanced on the bin, because the bin is full. The bin is 0.43u
	# tall (its GLB node is scaled 0.47; the manifest's 0.91 is the raw mesh).
	_prop(z, "furniture/trashcan", Vector2(400.0, 300.0), 0.0, 0.0)
	_pizza_box(z, Vector2(400.0, 292.0), 0.43, 14.0, false)


# --------------------------------------------------------- battlestation ----

## The hero. Six desks in TWO sections with a 0.85u slot between them at x ~8.9,
## so the player can walk THROUGH to the window nook — which is where the 2D
## twin's `prop_monitors` interactable (600, 300) actually stands. A continuous
## desk run would have made that prop unreachable, and a static frame would
## never have shown it.
##
## The 2D twin's desk drop shadow is (520, 382), so the run is built on z 5.75
## and the monitor faces sit on its back edge rather than at the sprite-centre
## y 296, which in 3D would have floated them a metre behind the desk.
static func _build_battlestation(root: Node3D) -> void:
	var z := _group(root, "Battlestation")
	var desk_z := 5.75 * TILE
	# Section A: world x 6.35..8.55. Section B: 9.40..10.87. Slot: 8.55..9.40.
	for i in 3:
		_prop(z, "furniture/desk", Vector2((6.72 + float(i) * 0.734) * TILE, desk_z), 0.0, 0.0)
	for j in 2:
		_prop(z, "furniture/desk", Vector2((9.77 + float(j) * 0.734) * TILE, desk_z), 0.0, 0.0)
	_solid(z, Vector2(7.45 * TILE, desk_z), Vector2(2.2, 0.58), 0.42)
	_solid(z, Vector2(10.14 * TILE, desk_z), Vector2(1.48, 0.58), 0.42)

	# Screens. TWO cyan faces are lit and one is dark glass, exactly as the 2D
	# twin's bank: a workstation is a shape first and a glow second. The face at
	# x 650 is the Dream App terminal itself, so it is the brightest.
	_monitor(z, Vector2(430.0, 356.0), true, ACCENT, 5.5)
	_monitor(z, Vector2(524.0, 356.0), false, ACCENT, 0.0)
	_monitor(z, Vector2(650.0, 356.0), true, ACCENT, 6.5)
	_monitor(z, Vector2(676.0, 360.0), true, ACCENT * 0.8, 4.0)
	# No keyboard under the laptop: it has its own, and a second one in front of
	# it overlapped the laptop's base.
	for kx: float in [524.0, 650.0]:
		_prop(z, "furniture/computerKeyboard", Vector2(kx, 378.0), DESK_TOP, 0.0)
	_prop(z, "furniture/computerMouse", Vector2(566.0, 378.0), DESK_TOP, 0.0)
	# client_email lives on a laptop (3D_BIBLE §7 props table). It sits at the
	# interactable's own authored x, so the [E] prompt hangs over the thing it
	# names rather than over the desk in general. The laptop is really 0.26u
	# wide and 0.16u tall (its GLB node is scaled 0.44 — the manifest reports
	# the unscaled mesh), hinged at the back with the screen leaning 24 degrees
	# off vertical, so its glow is a small tilted quad on that screen: 5 px
	# north of the footprint centre, a hand above the desk, pitched to match.
	_prop(z, "furniture/laptop", Vector2(430.0, 368.0), DESK_TOP, 0.0)
	_glow(z, Vector2(430.0, 364.0), DESK_TOP + 0.095, Vector2(0.20, 0.12), ACCENT * 0.85, 3.5,
		0.0, -24.0)
	_prop(z, "furniture/speaker", Vector2(412.0, 362.0), DESK_TOP, 0.0)
	_prop(z, "furniture/speaker", Vector2(694.0, 362.0), DESK_TOP, 0.0)
	_prop(z, "furniture/lampSquareTable", Vector2(474.0, 360.0), DESK_TOP, 0.0)
	_prop(z, "food/mug", Vector2(616.0, 364.0), DESK_TOP, 0.0)
	_prop(z, "food/soda-can", Vector2(640.0, 366.0), DESK_TOP, 0.0)
	# The chair, pulled up to the desk in front of the dark monitor and turned
	# to face it. The 2D twin's drop shadow (560, 505) is two tiles south of
	# the desk — right in the spawn->Claude lane, and in a room with depth a
	# chair that far from its desk reads as abandoned in the middle of the
	# floor. x 524 keeps it west of both walk lanes.
	_prop(z, "furniture/chairDesk", Vector2(524.0, 432.0), 0.0, 180.0)
	# The one lamp this person owns. It gets the region's single shadow-casting
	# light in _build_lighting; everything else in the flat is a machine that is
	# merely switched on.
	_prop(z, "furniture/lampRoundFloor", Vector2(376.0, 400.0), 0.0, 0.0)
	# Sticky notes along both desk fronts. Estimates. All of them say TODO.
	# The run is px 406..547 (section A) and 602..696 (section B), so a note
	# outside that would hang in mid-air east of the desk. The desk's real front
	# edge is 0.196u south of its footprint centre (z -0.38..0.012); the notes
	# sit a finger in front of it.
	var front := desk_z + 0.21 * TILE
	for n in 8:
		var sx := 412.0 + float(n) * 42.0
		if sx > 700.0 or (sx > 545.0 and sx < 602.0):
			continue    # nothing hangs across the walk-through slot
		# Paper, not pixels: a sticky note is not a light source (LAW 3), so
		# these are unshaded squares at a paper value with NO emission. At
		# energy 1.1 eight of them were eight more bright things in the frame.
		# Unshaded means the albedo IS the screen value: 0.52 sRGB came out of
		# the grade at ~158, over LAW 3's 60% ceiling; 0.40 lands at ~115.
		_glow(z, Vector2(sx, front), 0.19 + float(n % 3) * 0.045,
			Vector2(0.07, 0.07), Color(0.40, 0.34, 0.20), 0.0)
	# Under-desk cave: cardboard, and the boxes that came with the GPUs.
	_prop(z, "furniture/cardboardBoxClosed", Vector2(716.0, 372.0), 0.0, 24.0)
	_prop(z, "furniture/cardboardBoxOpen", Vector2(732.0, 400.0), 0.0, -14.0)
	# prop_sticker (470, 430): a sticker-covered laptop on a box stack. West of
	# both walk lanes, so it can never be in the opening's way.
	_prop(z, "furniture/cardboardBoxClosed", Vector2(460.0, 448.0), 0.0, 12.0)
	_prop(z, "furniture/laptop", Vector2(462.0, 444.0), 0.281, 168.0, 0.9)
	# deploy_button (760, 380): a red floor button you physically stand on to
	# ship to production. 3D_BIBLE §7 names the model; the comedy names itself.
	_prop(z, "prototype/button-floor-round", Vector2(760.0, 380.0), 0.0, 0.0, 1.0, ALARM)
	_glow(z, Vector2(760.0, 380.0), 0.155, Vector2(0.42, 0.42), ALARM, 4.5, 0.0, -90.0)


## One monitor: the prop, and — when it is switched on — the emissive face that
## makes it a light source. The face is a quad rather than a material override
## so it blooms at a known energy whatever the GLB's own material does. The
## quad sits 4 px (0.0625u) south of the footprint centre, which clears the
## model's own front plane at +0.052u.
static func _monitor(parent: Node3D, px: Vector2, lit: bool, color: Color, energy: float) -> void:
	_prop(parent, "furniture/computerScreen", px, DESK_TOP, 0.0)
	if not lit:
		# DARK GLASS. A monitor that is off is still a monitor; it is the shape,
		# not the glow, that says workstation.
		_glow(parent, px + Vector2(0.0, 4.0), DESK_TOP + 0.155,
			Vector2(0.30, 0.20), Color(0.05, 0.055, 0.075), 0.0)
		return
	_glow(parent, px + Vector2(0.0, 4.0), DESK_TOP + 0.155, Vector2(0.30, 0.20), color, energy)


# ------------------------------------------------------------ gpu rig -------

## The second workstation: a jury-rigged inference box made of crates, on the 2D
## twin's own drop shadows (1120, 460) for the desk and (1200, 572) for the
## stack. Both its faces are DARK — five lit screens in a two-hue room is four
## motivated sources too many — and the thermal glow underneath is what says the
## machine is running.
static func _build_gpu_rig(root: Node3D) -> void:
	var z := _group(root, "GpuRig")
	for i in 3:
		_prop(z, "furniture/desk", Vector2((16.77 + float(i) * 0.734) * TILE, 460.0), 0.0, 0.0)
	_solid(z, Vector2(17.5 * TILE, 460.0), Vector2(2.2, 0.58), 0.42)
	_monitor(z, Vector2(1060.0, 450.0), false, WARM, 0.0)
	_monitor(z, Vector2(1170.0, 452.0), false, WARM, 0.0)
	_prop(z, "furniture/computerKeyboard", Vector2(1112.0, 470.0), DESK_TOP, 0.0)
	# computer-wide is a floor console whose screen is its SLANTED TOP (normal
	# (0, 0.8, 0.6) — facing +Z and up, straight at the camera); its -Z side is
	# the back panel. The glow lies ON that slope: 1 px north of the footprint
	# centre at y 0.336, pitched -53 to match the surface.
	_prop(z, "space-station/computer-wide", Vector2(1224.0, 452.0), 0.0, -20.0)
	_glow(z, Vector2(1224.0, 451.0), 0.336, Vector2(0.44, 0.16), WARM * 0.7, 2.4, -20.0, -53.0)
	# Stacked GPU crates: three high, each turned a few degrees, because nobody
	# who built this stacked it straight.
	for j in 3:
		_prop(z, "space-station/container",
			Vector2(1200.0 + float(j) * 6.0, 572.0 - float(j) * 4.0),
			float(j) * 0.60, -12.0 + float(j) * 9.0)
	_solid(z, Vector2(1204.0, 568.0), Vector2(0.66, 0.66), 1.8)
	# The chair, pulled up to the rig desk (front edge z 7.39) rather than a
	# tile and a half behind it.
	_prop(z, "furniture/chairDesk", Vector2(1112.0, 500.0), 0.0, 168.0)
	_prop(z, "furniture/cardboardBoxOpen", Vector2(1268.0, 606.0), 0.0, 34.0)
	# broken_service (1120, 650): a service container that is, in every sense,
	# down. 3D_BIBLE §7 asks for container-tall plus a red light. Every body in
	# this room stands NORTH of its own anchor and faces south, so the player
	# always approaches an open front and the camera — which looks north-east —
	# always sees the lit face rather than the back panel. container-tall is a
	# symmetric 0.6u square (the manifest's lopsided 0.8u box is wrong); its
	# warning panel is the +Z face at 0.30, so the glow sits 22 px south.
	_prop(z, "space-station/container-tall", Vector2(1120.0, 610.0), 0.0, 0.0)
	_solid(z, Vector2(1120.0, 610.0), Vector2(0.64, 0.64), 0.9)
	_glow(z, Vector2(1120.0, 632.0), 0.55, Vector2(0.34, 0.20), ALARM, 5.0)
	# free_tokens_ad (1160, 620): a display screaming an offer, on a crate so it
	# stands at eye height and can be read from across the room. Its crate is
	# clear of both the outage container (z 9.21..9.85) and the GPU stack
	# (x 18.42..19.08), so nothing in this corner intersects anything else. The
	# crate is solid — a display you can walk through is not a display — and
	# display-wall's screen is its +Z face at 0.05 from the origin, y 0.18..0.28.
	_prop(z, "space-station/container", Vector2(1160.0, 660.0), 0.0, 0.0)
	_solid(z, Vector2(1160.0, 660.0), Vector2(0.60, 0.60), 0.6)
	_prop(z, "space-station/display-wall", Vector2(1160.0, 660.0), 0.60, 0.0)
	_glow(z, Vector2(1160.0, 661.0), 0.83, Vector2(0.30, 0.22), WARM, 6.0)


# --------------------------------------------------------- server corner ----

## The corner this flat is really about: five space-station computer systems on
## panel decking, at the 2D twin's rack drop shadows (1470, 276) and
## (1380, 296) plus three more that fill the corner the 2D room could only imply.
## Cyan status strips, one cyan light, no green — hardware reads in cyan and the
## room owns three hues.
static func _build_server_corner(root: Node3D) -> void:
	var z := _group(root, "ServerCorner")
	var racks := [Vector2(1470.0, 276.0), Vector2(1380.0, 296.0), Vector2(1462.0, 190.0),
		Vector2(1372.0, 200.0), Vector2(1552.0, 268.0)]
	for i in racks.size():
		# Facing south into the room. computer-system's screen is the top band
		# of its +Z face, which SLOPES: z 0.02 from the origin at y 0.42, 0.10
		# at y 0.34, 0.18 at the base. The strip sits at y 0.45, 7 px south of
		# the footprint centre — a finger in front of the band, not a third of
		# a tile out in the room where the manifest's 0.32 extent (the base
		# plinth) would have put it.
		var yaw := 0.0 if i < 2 else -12.0
		_prop(z, "space-station/computer-system", racks[i], 0.0, yaw)
		_glow(z, racks[i] + Vector2(0.0, 7.0), 0.45, Vector2(0.46, 0.05), ACCENT, 4.0, yaw)
	_solid(z, Vector2(1470.0, 250.0), Vector2(4.0, 2.7), 0.6)
	# prop_router (1352, 300): space-station/computer, 0.4 x 0.44 in plan. At
	# x 1352 it shared a corner with the second rack (x 21.11..22.01, z
	# 4.28..4.98); 24 px west it clears it, still inside the anchor's reach.
	# Its screen is the orange top of the +Z face, z ~0.05 from the origin.
	_prop(z, "space-station/computer", Vector2(1328.0, 264.0), 0.0, 0.0)
	_glow(z, Vector2(1328.0, 266.0), 0.52, Vector2(0.26, 0.12), ACCENT * 0.8, 3.0)
	# The drum the cable spaghetti was cut from, at the 2D twin's (1462, 336),
	# nudged 18 px north so its 1.1u-long footprint stays under the corner's
	# collider instead of standing 0.8u proud of it as a walk-through.
	_prop(z, "space-station/container-flat", Vector2(1462.0, 318.0), 0.0, -14.0)
	_prop(z, "space-station/pipe", Vector2(1560.0, 120.0), 0.0, 0.0)
	_prop(z, "space-station/pipe", Vector2(1560.0, 180.0), 0.0, 0.0)
	# agent_terminal (300, 560): the autonomous agent, alone against the west
	# wall with nobody watching it. Body half a unit north of its anchor so the
	# player approaches the front; the glow on the sloped screen band as above.
	_prop(z, "space-station/computer-system", Vector2(300.0, 528.0), 0.0, 0.0)
	_solid(z, Vector2(300.0, 528.0), Vector2(0.92, 0.72), 0.6)
	_glow(z, Vector2(300.0, 535.0), 0.45, Vector2(0.50, 0.14), ACCENT, 5.0)


# -------------------------------------------------------------- lounge ------

## The couch nobody sleeps on, the coffee table, and the pizza-box archaeology.
## Contacts from the 2D twin: couch (760, 804), pizza stack (905, 839), the one
## open single (700, 884), the noodle cup (626, 856).
static func _build_lounge(root: Node3D) -> void:
	var z := _group(root, "Lounge")
	_prop(z, "furniture/loungeSofaLong", Vector2(760.0, 804.0), 0.0, 180.0)
	_solid(z, Vector2(760.0, 804.0), Vector2(1.0, 0.84), 0.46)
	_prop(z, "furniture/pillowLong", Vector2(716.0, 796.0), 0.30, 168.0)
	_prop(z, "furniture/pillow", Vector2(806.0, 798.0), 0.30, 190.0)
	_prop(z, "furniture/loungeSofaOttoman", Vector2(880.0, 812.0), 0.0, 180.0)
	_prop(z, "furniture/tableCoffee", Vector2(760.0, 736.0), 0.0, 0.0)
	_solid(z, Vector2(760.0, 736.0), Vector2(0.64, 0.4), 0.23)
	# Tonight's box, open on the table, dinner beside it.
	_pizza_box(z, Vector2(748.0, 730.0), 0.23, 18.0, false)
	_prop(z, "food/pizza", Vector2(778.0, 742.0), 0.23, -22.0, PIZZA_SCALE)
	_prop(z, "food/soda-can", Vector2(808.0, 718.0), 0.23, 0.0)
	_prop(z, "food/cup-coffee", Vector2(730.0, 748.0), 0.23, 0.0)
	# Pizza archaeology: five CLOSED boxes (lids folded — see _pizza_box), each
	# greasier and more rotated than the one below it, one box height apart.
	for i in 5:
		_pizza_box(z, Vector2(905.0 + float(i) * 3.0, 839.0 - float(i) * 2.0),
			float(i) * PIZZA_BOX_H * PIZZA_SCALE, -18.0 + float(i) * 15.0, true,
			Color.WHITE.lerp(WARM, float(i) * 0.08))
	# One open single, the last slice preserved in situ.
	_pizza_box(z, Vector2(700.0, 884.0), 0.0, 26.0, false)
	_prop(z, "food/pizza", Vector2(700.0, 884.0), 0.09 * PIZZA_SCALE, 26.0,
		PIZZA_SCALE * 0.72)
	_prop(z, "food/cup", Vector2(626.0, 856.0), 0.0, 0.0)
	_prop(z, "furniture/lampRoundFloor", Vector2(880.0, 748.0), 0.0, 0.0)
	_prop(z, "furniture/bookcaseOpenLow", Vector2(560.0, 968.0), 0.0, 180.0)


# ------------------------------------------------------------- bedroom ------

## An unslept-in bed at the 2D twin's (1320, 888), a nightstand, the shelves at
## (1500, 694), and the deprecated plant at (110, 842).
static func _build_bedroom(root: Node3D) -> void:
	var z := _group(root, "Bedroom")
	# bedSingle is really 0.57u x 1.13u (its manifest box is the cover's
	# unrotated local box), head at the -Z end; yawed 180 the head is south,
	# where the pillow goes. Collider and laptop are sized and placed to the
	# real bed, not the phantom one.
	_prop(z, "furniture/bedSingle", Vector2(1320.0, 888.0), 0.0, 180.0)
	_solid(z, Vector2(1320.0, 888.0), Vector2(0.64, 1.2), 0.5)
	_prop(z, "furniture/pillowLong", Vector2(1320.0, 916.0), 0.376, 180.0)
	_prop(z, "furniture/laptop", Vector2(1312.0, 866.0), 0.375, 150.0, 0.85)
	# Nightstand at the bed's east side (the bed ends at x 20.91u), not a tile
	# and a half away from it.
	_prop(z, "furniture/cabinetBedDrawer", Vector2(1372.0, 920.0), 0.0, 0.0)
	_prop(z, "furniture/lampSquareTable", Vector2(1372.0, 916.0), 0.263, 0.0)
	# Shelves along the east wall — AGAINST it: the 2D twin's x 1500 is a
	# sprite centre 1.5 tiles off the wall, which in 3D is a bookcase standing
	# in the middle of the floor. 0.25u deep, so a centre 8 px off x 1600 puts
	# the back on the wall face.
	_prop(z, "furniture/bookcaseOpen", Vector2(1592.0, 694.0), 0.0, -90.0)
	_prop(z, "furniture/bookcaseClosedWide", Vector2(1592.0, 618.0), 0.0, -90.0)
	_solid(z, Vector2(1592.0, 656.0), Vector2(0.3, 2.2), 0.88)
	# bookcaseOpen's shelves are at y 0.13 / 0.37 / 0.61 / 0.85 and it spans
	# z 10.64..11.04 (px 681..707): books ON shelves, inside the case.
	for i in 3:
		_prop(z, "furniture/books", Vector2(1592.0, 686.0 + float(i) * 8.0),
			0.13 + float(i % 2) * 0.24, -90.0)
	_prop(z, "furniture/radio", Vector2(1592.0, 610.0), 0.79, -90.0)
	# The deprecated plant. Tinted toward dead, because its whole joke is colour.
	_prop(z, "furniture/pottedPlant", Vector2(110.0, 842.0), 0.0, 0.0, 1.0, WARM)
	# Two that are still alive, in the window nook where the light is.
	_prop(z, "furniture/plantSmall2", Vector2(224.0, 168.0), 0.0, 0.0)
	_prop(z, "furniture/pottedPlant", Vector2(852.0, 168.0), 0.0, 0.0)


# ------------------------------------------------------------- clutter ------

## node_modules, in physical form. Contacts (210, 894) and (330, 878) from the
## 2D twin, grown into a heap because a directory that size is not two boxes.
static func _build_clutter(root: Node3D) -> void:
	var z := _group(root, "Clutter")
	var heap := [
		[Vector2(210.0, 894.0), 0.0, 0.0],
		[Vector2(248.0, 872.0), 0.0, 26.0],
		[Vector2(206.0, 856.0), 0.281, -14.0],
		[Vector2(330.0, 878.0), 0.0, 12.0],
		[Vector2(364.0, 902.0), 0.0, -32.0],
		[Vector2(336.0, 852.0), 0.281, 40.0],
		[Vector2(286.0, 918.0), 0.0, -8.0],
	]
	for i in heap.size():
		var e: Array = heap[i]
		var key := "furniture/cardboardBoxClosed" if i % 3 != 1 else "furniture/cardboardBoxOpen"
		_prop(z, key, e[0], float(e[1]), float(e[2]))
	_solid(z, Vector2(228.0, 880.0), Vector2(0.62, 0.62), 0.56)
	_solid(z, Vector2(346.0, 880.0), Vector2(0.62, 0.62), 0.56)
	_prop(z, "furniture/trashcan", Vector2(430.0, 900.0), 0.0, 0.0)
	_prop(z, "prototype/crate", Vector2(1560.0, 900.0), 0.0, -18.0)
	_prop(z, "prototype/crate", Vector2(1560.0, 900.0), 0.5, 14.0)
	_prop(z, "furniture/coatRackStanding", Vector2(1560.0, 460.0), 0.0, -90.0)


# -------------------------------------------------------------- cables ------

## The infrastructure the room was built on: thin dark-grey cylinders, drawn as
## ONE MultiMesh, running along the SKIRTING rather than across the floor.
##
## The pass-3 frame is why. The old runs were five polylines struck diagonally
## across the middle of the flat at (0.055, 0.055, 0.075) — near-black, and
## because the region's lights are pools rather than fill, they rendered as two
## flat unlit black lines from one corner of the room to the other. The critic
## read them exactly as they looked: "navigation-debug lines". Cable does not
## lie across the middle of a floor anyway; it is stapled to the wall and it
## drops down to the machines.
##
## So: a spine along the north skirting at y 40, a second down the east skirting
## at x 1568, and one short drop from each spine to the machine it feeds. Same
## fiction (this is still the run the player steps over on the way to the
## power strip), no line across the room, and the colour is now a lit
## dark grey — the brief's (0.18, 0.19, 0.22) — so it reads as rubber in the
## moonlight instead of as a hole. No colliders: cable is something you trip
## over in fiction, not in physics.
const CABLE_R := 0.03
const CABLE_TONE := Color(0.18, 0.19, 0.22)

static func _build_cables(root: Node3D) -> void:
	var z := _group(root, "Cables")
	var runs := [
		# The north spine, and its drops to the battlestation and the servers.
		[Vector2(300, 40), Vector2(1470, 40)],
		[Vector2(430, 40), Vector2(430, 300), Vector2(560, 340)],
		[Vector2(1470, 40), Vector2(1470, 240)],
		# The east spine, and its drop to the GPU rig.
		[Vector2(1568, 260), Vector2(1568, 700)],
		[Vector2(1568, 470), Vector2(1300, 470), Vector2(1180, 470)],
		# The last metre: rig to power strip, along the desks rather than across
		# the walk lane the opening sequence uses.
		[Vector2(1180, 470), Vector2(900, 452), Vector2(716, 438)],
	]
	var xforms: Array[Transform3D] = []
	for run: Array in runs:
		for i in run.size() - 1:
			var a := Map3D.to3d(run[i], 0.035)
			var b := Map3D.to3d(run[i + 1], 0.035)
			var d := b - a
			var len_u := d.length()
			if len_u < 0.001:
				continue
			# CylinderMesh runs along +Y, so the basis maps Y onto the segment.
			# Both endpoints sit on the floor plane, so UP is always a valid
			# perpendicular and the cross product can never degenerate.
			var y_axis := d / len_u
			var z_axis := Vector3.UP
			var x_axis := y_axis.cross(z_axis).normalized()
			xforms.append(Transform3D(
				Basis(x_axis, y_axis * len_u, z_axis), (a + b) * 0.5))
	var cyl := CylinderMesh.new()
	cyl.top_radius = CABLE_R
	cyl.bottom_radius = CABLE_R
	cyl.height = 1.0
	cyl.radial_segments = 6
	cyl.rings = 0
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cyl
	mm.instance_count = xforms.size()
	for i2 in xforms.size():
		mm.set_instance_transform(i2, xforms[i2])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "CableRuns"
	mmi.multimesh = mm
	mmi.material_override = Map3D.matte(CABLE_TONE)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	z.add_child(mmi)
	# The power strip every one of those runs was always heading for, at the 2D
	# twin's (706, 436): more wall-warts than sockets, one confidently red LED.
	var strip := MeshInstance3D.new()
	strip.name = "PowerStrip"
	var sm := BoxMesh.new()
	sm.size = Vector3(0.36, 0.055, 0.13)
	strip.mesh = sm
	strip.material_override = Map3D.matte(Color(0.20, 0.20, 0.23))
	strip.position = Map3D.to3d(Vector2(706.0, 436.0), 0.028)
	z.add_child(strip)
	_glow(z, Vector2(722.0, 436.0), 0.062, Vector2(0.035, 0.02), ALARM, 4.0, 0.0, -90.0)


# ------------------------------------------------------------ lighting ------

## EIGHT motivated sources, in the order the eye should find them, and nothing
## else. Fourteen was already under 3D_BIBLE §9's ceiling and it still lit every
## face of every object in the flat from some direction — twenty-two omnis
## totalling energy 48 once the region rig was counted with it, which is a
## reading light in every corner of a one-room apartment at three in the morning.
##
## What went: the coffee machine's own glow (a machine with an LED does not need
## an omni), the agent terminal's (the server corner's light reaches it), the
## rig thermals AND the ad (one warm source covers that corner), the deploy
## button (its own red disc is the tell), and the bedside lamp (nobody is in
## bed; that is the joke). Each survivor is something a player can point at and
## name, and there is a great deal of dark left over for them to matter in.
static func _build_lighting(root: Node3D) -> void:
	var z := _group(root, "Lighting")
	# 1. The warm amber key — the one lamp this person owns, beside the desk.
	#    Focal, so it spends the single shadow the budget allows.
	_light(z, Vector2(376.0, 400.0), 0.92, WARM, 1.2, 8.0, true)
	# 2. The battlestation, lit as ONE source: the monitor bank and the Dream App
	#    terminal are 2 units apart and were never two lights, they were one
	#    light drawn twice.
	_light(z, Vector2(588.0, 340.0), 0.80, ACCENT, 1.0, 7.0)
	# 3. City light through the window wall — the only light in the flat that is
	#    not inside the flat, and the reason the north wall reads as a window.
	_light(z, Vector2(544.0, 96.0), 1.05, NIGHT, 0.7, 10.0)
	# 4. Kitchen: the ceiling over the peninsula.
	_light(z, Vector2(224.0, 224.0), 1.20, WARM, 0.75, 7.5)
	# 5. The server corner — the thing this flat is actually about.
	_light(z, Vector2(1450.0, 268.0), 0.90, ACCENT, 0.8, 7.0)
	# 6. The GPU rig's corner: thermals, and the ad that will not close.
	_light(z, Vector2(1150.0, 560.0), 0.82, WARM, 0.7, 7.0)
	# 7. The outage. The one red thing in the room, and it is a warning, not a
	#    light source — low energy, short reach, on the container it belongs to.
	_light(z, Vector2(1120.0, 630.0), 0.70, ALARM, 0.6, 6.0)
	# 8. The lounge — low, warm, and last in the reading order.
	_light(z, Vector2(880.0, 748.0), 1.00, WARM, 0.6, 6.5)


# ---------------------------------------------------------- atmosphere ------

## Two emitters, well inside the twelve the budget allows: the dust the room
## breathes, and the steam off the load-bearing appliance in this person's life.
static func _build_atmosphere(root: Node3D) -> void:
	var z := _group(root, "Atmosphere")
	var dust := GPUParticles3D.new()
	dust.name = "DustMotes"
	# LAW 4: the ambient layer is <= 16 particles, slow, TEXT_DIM at a quarter
	# alpha, and it does NOT emit — dust is something a light catches.
	dust.amount = 16
	dust.lifetime = 11.0
	dust.preprocess = 6.0
	dust.position = Vector3(ROOM_W * 0.5, 0.9, ROOM_H * 0.5)
	dust.visibility_aabb = AABB(Vector3(-13.0, -1.2, -8.5), Vector3(26.0, 3.0, 17.0))
	dust.draw_pass_1 = _mote_mesh(Vector2(0.035, 0.035), Color(0.49, 0.55, 0.69), 0.0)
	var dm := ParticleProcessMaterial.new()
	dm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	dm.emission_box_extents = Vector3(ROOM_W * 0.5 - 1.0, 0.9, ROOM_H * 0.5 - 1.0)
	dm.direction = Vector3(0.0, 1.0, 0.0)
	dm.spread = 70.0
	dm.gravity = Vector3(0.0, 0.015, 0.0)
	dm.initial_velocity_min = 0.02
	dm.initial_velocity_max = 0.10
	dm.scale_min = 0.5
	dm.scale_max = 1.5
	dm.color = Color(0.62, 0.68, 0.84, 0.28)
	dust.process_material = dm
	z.add_child(dust)

	# FOUR motes, small and dim. At fourteen 0.07u quads scaled up to 2.2 this
	# read as what the critic called it: "a column of small white cubes" over the
	# coffee machine. Steam is something you notice after the room, not before
	# it — LAW 9, and LAW 4's particle budget in spirit.
	var steam := GPUParticles3D.new()
	steam.name = "CoffeeSteam"
	steam.amount = 4
	steam.lifetime = 2.4
	steam.preprocess = 2.0
	steam.position = Map3D.to3d(Vector2(230.0, 268.0), 0.78)
	steam.visibility_aabb = AABB(Vector3(-0.8, -0.4, -0.8), Vector3(1.6, 2.2, 1.6))
	steam.draw_pass_1 = _mote_mesh(Vector2(0.035, 0.035), Color(0.55, 0.57, 0.62), 0.0)
	var sm := ParticleProcessMaterial.new()
	sm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	sm.emission_sphere_radius = 0.05
	sm.direction = Vector3(0.0, 1.0, 0.0)
	sm.spread = 10.0
	sm.gravity = Vector3(0.0, 0.16, 0.0)
	sm.initial_velocity_min = 0.16
	sm.initial_velocity_max = 0.32
	sm.scale_min = 0.5
	sm.scale_max = 1.2
	sm.color = Color(0.62, 0.64, 0.70, 0.16)
	steam.process_material = sm
	z.add_child(steam)


static func _mote_mesh(size: Vector2, color: Color, energy: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = energy
	q.material = m
	return q


# ------------------------------------------------------------ gameplay ------

## Instantiate one cross-track 3D actor scene at an authored MAP PIXEL position.
## Every path is exists()-guarded because the tracks that own those scenes are
## landing at the same time as this file; a missing one costs the flat that
## actor, never the whole region.
static func _actor(parent: Node3D, path: String, px: Vector2, fields: Dictionary) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var ps: PackedScene = load(path)
	if ps == null:
		return null
	var inst := ps.instantiate()
	if not (inst is Node3D):
		inst.free()
		return null
	var n := inst as Node3D
	for k in fields:
		n.set(str(k), fields[k])
	n.position = Map3D.to3d(px, 0.0)
	parent.add_child(n)
	return n


## Every gameplay actor at its authored px. This is the table quests, saves, the
## objective waypoint and the tests all speak, so not one number here is new —
## it is copied from the 2D builder's _populate_gameplay, positions included.
static func _populate_gameplay(root: Node3D) -> void:
	var tokens := _group(root, "Tokens")
	var enemies := _group(root, "Enemies")
	var npcs := _group(root, "NPCs")
	var portals := _group(root, "Portals")
	var props := _group(root, "Interactables")

	var token_types := ["common", "common", "cached", "common", "cached"]
	var token_positions := [
		Vector2(560, 700), Vector2(660, 660), Vector2(700, 760),
		Vector2(900, 620), Vector2(1030, 580),
		Vector2(1160, 540), Vector2(1300, 520),
		Vector2(500, 560),
	]
	for i in token_positions.size():
		_actor(tokens, SCENES3D + "token_pickup3d.tscn", token_positions[i],
			{"token_type": token_types[i % token_types.size()]})

	# The two bugs live far right, toward the exit and away from the spawn, the
	# token path and Claude, so a new player can explore, collect and talk before
	# combat is encountered by heading for the door (the 2D twin's reasoning).
	for pos: Vector2 in [Vector2(1330, 706), Vector2(1490, 820)]:
		_actor(enemies, SCENES3D + "enemy3d.tscn", pos,
			{"enemy_type": "bug", "max_hp": 20})

	var claude_quests: Array[String] = ["hello_localhost", "tiny_change", "ship_dream_app"]
	_actor(npcs, SCENES3D + "npc3d.tscn", Vector2(820, 560),
		{"npc_id": "roommate_ai", "quest_ids": claude_quests})

	var ipath := SCENES3D + "interactable3d.tscn"
	# The six story interactables. one_shot mirrors the 2D twin exactly: the
	# inbox, the ad, the agent terminal and the outage are running gags and stay
	# re-triggerable; the Dream App terminal and the deploy button keep the
	# scene's own default. `dressed` tells Interactable3D this builder already
	# placed the prop's art (the laptop, the monitor bank, the floor button...)
	# so it draws a hotspot, not a second fridge through the first. It infers
	# the same from GameManager.current_region; saying it outright costs
	# nothing and survives a region id arriving late.
	_actor(props, ipath, Vector2(430, 360), {"interact_id": "client_email",
		"interact_text": "Check client email", "one_shot": false, "dressed": true})
	_actor(props, ipath, Vector2(650, 360), {"interact_id": "dream_app_terminal",
		"interact_text": "Dream App Terminal", "dressed": true})
	_actor(props, ipath, Vector2(760, 380), {"interact_id": "deploy_button",
		"interact_text": "Deploy To Production", "dressed": true})
	_actor(props, ipath, Vector2(1160, 620), {"interact_id": "free_tokens_ad",
		"interact_text": "Suspicious pop-up ad", "one_shot": false, "dressed": true})
	_actor(props, ipath, Vector2(300, 560), {"interact_id": "agent_terminal",
		"interact_text": "Autonomous Agent terminal", "one_shot": false, "dressed": true})
	_actor(props, ipath, Vector2(1120, 650), {"interact_id": "broken_service",
		"interact_text": "Investigate the outage", "one_shot": false, "dressed": true})

	# Environmental comedy props: readable flavour on the furniture, rewarding
	# exploration. Same ten ids, texts and positions the 2D twin authored, so
	# every popup body still lands on the object it was written about.
	var flavor := {
		"prop_fridge": [Vector2(150, 275), "Fridge"],
		"prop_coffee": [Vector2(245, 288), "Coffee machine"],
		"prop_plant": [Vector2(135, 852), "Deprecated plant"],
		"prop_bed": [Vector2(1300, 772), "Bed"],
		"prop_server": [Vector2(1452, 272), "Server rack"],
		"prop_whiteboard": [Vector2(950, 138), "Whiteboard"],
		"prop_terminal": [Vector2(1120, 476), "Terminal"],
		"prop_router": [Vector2(1352, 300), "Router"],
		"prop_monitors": [Vector2(600, 300), "Battlestation monitors"],
		"prop_sticker": [Vector2(470, 430), "Sticker-covered laptop"],
	}
	for id in flavor:
		var e: Array = flavor[id]
		_actor(props, ipath, e[0], {"interact_id": str(id),
			"interact_text": str(e[1]), "one_shot": false, "dressed": true})

	if GameManager.is_region_unlocked("dependency_district"):
		_actor(portals, SCENES3D + "portal3d.tscn", LocalhostBuilder.PORTAL_POS,
			{"target_region": "dependency_district", "portal_label": "Dependency District"})
