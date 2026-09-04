class_name Interactable3D
extends Node3D
## The 3D twin of `scripts/world/interactable.gd` + `generic_interactable.gd`
## (3D_BIBLE.md §4, §7 "Props by interact id").
##
## THIS FILE CONTAINS NO GAME LOGIC ON PURPOSE. Deploy, the architecture
## console, the client email, the free-tier ad, the on-call pager, the coffee
## machine, every flavour popup and every story script live in
## generic_interactable.gd and are worth about six hundred lines. So a hidden 2D
## `GenericInteractable` is instantiated as a child, told its id, and asked to
## `interact()` — 100% logic reuse, one source of truth, and a story rewrite in
## the 2D file lands in the 3D game for free.
##
## The delegate is inert: invisible, not processing, not monitoring, on no
## collision layer, and REMOVED from the "interactable" group (the ActorProxy is
## this prop's one representative there — two would double it in every
## group-walking UI).
##
## What this file does own is the ART: which Kenney model an id wears, how far
## toward the region's dark it is muted (LAW 7: props are desaturated toward
## BASE, and only a screen's own face carries the accent), and the ten per cent
## of albedo that says "this one is a lever, not scenery" when you get close.
##
## EXCEPT in a room whose builder has already furnished the spot. LocalhostBuilder3D
## dresses every one of its sixteen hotspots by hand (the laptop at 430, the
## monitor bank at 650, the floor button at 760, the fridge, the bed...) and
## counts its own lights, so a prop that ALSO drew its §7 model there would put a
## second fridge through the first one and a second deploy button on top of the
## real one. In that room this node is INVISIBLE: the 2D brain and the proxy, and
## nothing in the frame at all.
##
## It used to draw a thin accent hoop on the floor there instead. LAW 3 ends
## "Floors do not glow", and the cold read of pass 3 found the hoops first: "a
## pale-blue torus ring lies on the floor beside a saucer with nothing attached".
## A ring is an editor gizmo — it marks a spot without being an object in the
## place — and the [E] prompt over the prop's head already says everything the
## ring was trying to say, without putting a lit circle on the ground.
##
## This node now casts NO LIGHT of any kind either. Every prop used to be allowed
## a small accent omni "because a monitor is a light" — but LAW 4 budgets a room
## at six PointLights and region_builder3d.gd counts and clamps exactly six, so
## every pool a prop added on top of that was a light nobody had budgeted,
## landing as an unexplained coloured wash on the floor around it (the pink
## puddle under the api_bazaar monitor in pass 3). The room lights the room.

const DELEGATE_SCENE := "res://scenes/world/generic_interactable.tscn"

## Regions whose 3D builder places the interactable's art itself. Every other
## builder (region_builder3d) places none and relies on PROP_MODEL below.
const DRESSED_REGIONS := ["localhost"]

## 3D_BIBLE.md §7's prop table, verbatim. Every key is in
## assets/external/kenney3d/manifest.json; the fallback is a prototype crate so
## an unmapped id is still a solid, findable object.
const PROP_MODEL := {
	"dream_app_terminal": "furniture/desk",
	"deploy_button": "prototype/button-floor-round",
	"client_email": "furniture/laptop",
	"free_tokens_ad": "space-station/display-wall",
	"agent_terminal": "space-station/computer-system",
	"broken_service": "space-station/container-tall",
	"prop_coffee": "furniture/kitchenCoffeeMachine",
	"abandoned_package": "prototype/crate",
	"backup_server": "space-station/computer-wide",
	"prop_node_modules": "factory/box-large",
	"prop_leftpad": "prototype/crate",
	"prop_lockfile": "mini-dungeon/chest",
	"prop_api_stall": "mini-market/cash-register",
	"prop_status_page": "space-station/display-wall",
	"prop_pricing": "mini-market/shelf-bags",
	"prop_gravestone": "graveyard/gravestone-round",
	"prop_accepted": "graveyard/gravestone-cross-large",
	"prop_invoice": "space-station/computer",
	"prop_dashboard": "space-station/display-wall-wide",
	"prop_rig": "factory/cog-a",
	"prop_fan": "factory/cone",
	"prop_sponsor": "mini-dungeon/chest",
	"prop_issue": "mini-forest/target",
	"prop_mission": "mini-arena/banner",
	"prop_kanban": "space-station/display-wall",
	"prop_pager": "space-station/computer",
	"prop_runbook": "mini-dungeon/table",
	"prop_vault": "castle/metal-gate",
	# --- localhost's ten flavour props ---------------------------------------
	# §7 gives localhost "furniture + food + space-station screens" but names
	# only the story props; these ten ids come from LocalhostBuilder's own
	# flavour table and are the FIRST room the player ever stands in, so they get
	# real furniture instead of ten identical fallback crates.
	"prop_fridge": "furniture/kitchenFridgeLarge",
	"prop_plant": "furniture/pottedPlant",
	"prop_bed": "furniture/bedSingle",
	"prop_server": "space-station/computer-wide",
	"prop_whiteboard": "space-station/display-wall-wide",
	"prop_terminal": "space-station/computer-screen",
	"prop_router": "furniture/televisionAntenna",
	"prop_monitors": "furniture/desk",
	"prop_sticker": "furniture/laptop",
}
const FALLBACK_MODEL := "prototype/crate"

## The assemblies §7 asks for, as [model key, local offset] RELATIVE TO THE
## PRIMARY MODEL'S AUTHORED ORIGIN (the whole assembly is then centred on the
## node together, see _build_prop). Heights are the manifest's (desk 0.384,
## box-large 0.55, cog-a 0.225 top), so a screen lands ON the desk instead of
## inside it; the x offsets centre a 0.39-wide screen on a desk that runs
## x -0.01..0.724 from its corner origin.
const PROP_EXTRA := {
	"dream_app_terminal": [
		["furniture/computerScreen", Vector3(0.17, 0.384, -0.1)],
		["furniture/computerKeyboard", Vector3(0.22, 0.384, 0.16)],
	],
	"prop_node_modules": [
		["factory/box-large", Vector3(0.05, 0.55, 0.0)],
		["factory/box-large", Vector3(-0.03, 1.1, 0.04)],
	],
	"prop_rig": [
		["tower-defense/detail-crystal", Vector3(0.0, 0.225, 0.0)],
	],
	"prop_vault": [
		["mini-dungeon/chest", Vector3(0.0, 0.0, 0.5)],
	],
	# The battlestation: two screens on the desk, which is the whole joke. Two
	# 0.39 screens on a 0.73 desk overhang its ends by 3cm each; that is a desk.
	"prop_monitors": [
		["furniture/computerScreen", Vector3(-0.03, 0.384, -0.08)],
		["furniture/computerScreen", Vector3(0.36, 0.384, -0.08)],
		["furniture/computerKeyboard", Vector3(0.22, 0.384, 0.17)],
	],
}

## VISUAL_BIBLE v2 LAW 2 — the region's BASE: the dark of its walls, its shadow
## and its out-of-bounds. Props are desaturated TOWARD it (LAW 7), which is why
## this table lives here and not just in the environment track.
const REGION_BASE := {
	"localhost": Color("#0E0C14"),
	"dependency_district": Color("#0A120C"),
	"stackoverflow_ruins": Color("#14110C"),
	"api_bazaar": Color("#140A12"),
	"cloud_district": Color("#0A0E16"),
	"open_source_wildlands": Color("#0A120E"),
	"corporate_enterprise": Color("#0B0E16"),
	"gpu_mines": Color("#140A08"),
	"production": Color("#14080A"),
	"token_vault": Color("#14100A"),
}
## Unknown region: localhost's BASE. A literal off the LAW 2 table is a fourth
## hue waiting to happen, so the fallback is a row of the table, not a new dark.
const DEFAULT_BASE := Color("#0E0C14")

## LAW 7's ONE exception for a prop: "only screens/lamps carry ACCENT or WARM,
## and only on their lit surface". So this is not a light table — it is how hard
## a SCREEN FACE is switched on, capped (below), and it reaches only the part of
## an assembly that `_is_screen_part` can prove is a screen SUB-mesh.
##
## CAP: 1.2, down from 1.6, and nothing in this game is allowed over it. At 1.6
## an emission of a full-value accent lands past 1.0 on top of the surface's own
## albedo, and past 1.0 there is exactly one colour: white. Pass 3 measured it —
## cloud_district's monitor face peaked at 252 and api_bazaar's at 224 with the
## magenta washed out of it. A screen is a lit surface, not a headlight.
##
## A row here is an INTENT, not a promise. Of the ids below only the three whose
## model is an assembly — `deploy_button` (a cap on a base plate) and
## `dream_app_terminal` / `prop_monitors` (a computerScreen standing on a desk) —
## currently pass SCREEN_PART_MAX_SHARE and light up. The rest name a Kenney
## appliance that is one mesh from cabinet to picture, and one mesh cannot be
## half switched on, so they stay dark until they are modelled with a face of
## their own. The rows stay because the id's intent has not changed.
const SCREEN_EMIT_MAX := 1.2
const SCREEN_EMIT := {
	"deploy_button": 1.2,
	"broken_service": 1.2,
	"free_tokens_ad": 1.2,
	"agent_terminal": 1.2,
	"dream_app_terminal": 1.2,
	"prop_status_page": 1.2,
	"prop_dashboard": 1.2,
	"prop_kanban": 1.05,
	"prop_accepted": 0.9,
	"backup_server": 1.05,
	"prop_pager": 1.05,
	"prop_monitors": 1.05,
	"prop_terminal": 1.05,
	"prop_server": 0.9,
	"prop_router": 0.75,
}

## And the colour it burns: the region ACCENT held to 0.85 value. The accents are
## authored at full value (#6BC7FF, #FF2D95 and #A8FF3E all peak at 1.0), so an
## emission in the raw accent starts a screen at the top of the range before the
## energy multiplier has touched it. Backing the colour off first is what keeps
## the HUE in the frame: a magenta screen at 0.85 x 1.2 still reads magenta,
## where the same screen at 1.0 x 1.6 reads white with pink edges.
const SCREEN_VALUE := 0.85

## Node names that mean "this part of the assembly is the lit surface". Kenney
## names its meshes after the thing they are (`computerScreen`, `display-wall`,
## `button-floor-round`), and Map3D.model() keeps that name on the instance, so
## a desk stays a desk while the screen standing on it is the part that is on.
const SCREEN_HINTS := ["screen", "display", "monitor", "computer", "button", "panel", "terminal"]
## ...and the names that match a hint by accident. `computerKeyboard` contains
## "computer", so for three rounds the battlestation's keyboard was as lit as the
## two monitors above it. A keyboard is not a screen.
const NOT_SCREEN := ["keyboard", "mouse", "chair", "drawer", "door", "leg", "stand", "mug"]

## A screen face may be at most this share of the assembly it belongs to, by
## bounding volume. This is the rule that stops "the screen glows" from meaning
## "the appliance glows": half the Kenney space-station kit (`display-wall`,
## `display-wall-wide`, `computer-wide`, `computer-screen`) is ONE mesh with ONE
## `colormap` material covering cabinet, bezel, buttons and picture alike, so
## switching "the screen" on there switches the whole box on — which is precisely
## the pink-white slab and the blue-white slab the pass-3 read picked out. There
## is no sub-mesh to isolate, so those props get NO emission: a dark appliance in
## a lit room is correct, a light box with a picture on it is not. Where the
## screen IS a separate piece (a computerScreen standing on a desk, the cap of a
## floor button) it comes in far under this share and burns as intended.
const SCREEN_PART_MAX_SHARE := 0.40
## Floor thickness for the volume test, so a screen authored as a flat quad has a
## volume at all instead of dividing by zero.
const PART_EPS := 0.02

## generic_interactable.gd's proximity highlight, converted at the coordinate
## edge (GLOW_RADIUS 110 map px / 64).
const NEAR_RADIUS := 1.72
const GATE_RATE := 4.0
## The near-player highlight, in ALBEDO. Ten per cent lighter — a prop you can
## use steps very slightly out of the room's dark as you close, the way an
## object catches the light when you lean over it. It is not an emissive pulse:
## LAW 3 says props do not glow, and a pulsing object in a quiet frame is the
## single loudest thing on screen. The [E] prompt over its head is the actual
## affordance; this is only the confirmation that the prompt means THIS one.
const HIGHLIGHT_LIFT := 0.10

## LAW 3: "Everything else is ≤ 60% value." A prop is never one of the five
## things allowed to be bright, so its albedo is capped here — AFTER the mute,
## because the mute cannot reach a white.
##
## It cannot reach a white because of how the Kenney kits are painted: a
## space-station model's material is a white `albedo_color` MULTIPLIER over a
## `colormap` texture that holds every hue the model has. Desaturating that
## multiplier toward grey does nothing (white is already grey) and the texture's
## white texels come through at full strength — which is where "a white tub prop"
## came from, and it was never emissive at all, just white paint under a light.
## Scaling the multiplier is the one operation that reaches the texture, so the
## cap goes on the multiplier and every texel comes down with it.
##
## 0.55 rather than 0.60: the near-player highlight lifts ten per cent toward
## white on top of it (0.55 -> 0.595), so the lit state is what has to fit under
## LAW 3's ceiling, not the resting one.
const PROP_VALUE_MAX := 0.55

@export var interact_id: String = ""
@export var interact_text: String = "Interact"
@export var one_shot: bool = true
## True when the room's builder placed this prop's model itself, so this node
## draws no art and adds no light of its own. Builders may set it; it is also
## inferred for DRESSED_REGIONS so a room never gets its furniture twice.
@export var dressed: bool = false

var _delegate: Node = null
var _accent := Color("#24F0DC")
var _mats: Array[StandardMaterial3D] = []
## The muted resting albedo of each material in `_mats`, in step. The highlight
## is computed FROM these rather than accumulated onto whatever is there, so
## walking past a prop a hundred times cannot creep its colour.
var _mat_base: Array[Color] = []
## Which of those materials belong to the lit surface of a screen.
var _mat_screen: Array[bool] = []
var _base := DEFAULT_BASE
## How hard this prop's screen face burns, already clamped to SCREEN_EMIT_MAX.
## Zero for the great majority of props, which have no screen at all.
var _screen_emit := 0.0
var _gate := 0.0
var _clock := 0.0
var _used := false
var _proxy: ActorProxy

func _ready() -> void:
	add_to_group("interactable")
	_build_delegate()
	_accent = _accent_for(interact_id)
	_base = REGION_BASE.get(GameManager.current_region, DEFAULT_BASE)
	_screen_emit = minf(float(SCREEN_EMIT.get(interact_id, 0.0)), SCREEN_EMIT_MAX)
	# region_portal.gd's guarantee holds here too: `GameManager.current_region`
	# is already the room being populated by the time a prop enters the tree.
	if GameManager.current_region in DRESSED_REGIONS:
		dressed = true
	# In a dressed room this node draws nothing: the builder's own furniture is
	# the art, and the [E] prompt is the affordance.
	if not dressed:
		_build_prop()
	_proxy = ActorProxy.attach(self, ["interactable"], {
		"interact_id": interact_id,
		"interact_text": interact_text,
	})

# ----------------------------------------------------------------- delegate --

## The hidden 2D brain. Everything after add_child() undoes what
## `interactable.gd::_ready` just set up for a 2D world it is no longer in.
func _build_delegate() -> void:
	if not ResourceLoader.exists(DELEGATE_SCENE):
		return
	var ps: PackedScene = load(DELEGATE_SCENE)
	if ps == null:
		return
	# Untyped on purpose, exactly as region_builder.gd instantiates the same
	# scene: the exported fields live on the script, not on Area2D.
	var d = ps.instantiate()
	d.interact_id = interact_id
	d.interact_text = interact_text
	d.one_shot = one_shot
	d.visible = false
	add_child(d)
	# _ready has run by now: disarm it.
	d.set_process(false)
	d.set_physics_process(false)
	if d is Area2D:
		var a := d as Area2D
		a.monitoring = false
		a.monitorable = false
		a.collision_layer = 0
		a.collision_mask = 0
	# The ActorProxy is this prop's one entry in the group-walking UI
	# (objective_waypoint, guide_overlay); the delegate must not be a second.
	d.remove_from_group("interactable")
	_delegate = d

## The prop's one accent: THE ROOM'S. It used to be the delegate's category
## accent — the hue its flavour popup opens in — and generic_interactable.gd has
## a dozen of those: magenta for commerce, violet for the weird ones, gold for
## money. A magenta screen face and a magenta floor ring in a room whose accent
## is corporate blue is a fourth and fifth hue in a frame the rubric allows
## three, and it is where the pink in the captured frames kept coming from. The
## POPUP can still open in its category colour; the object standing in the room
## belongs to the room (LAW 2, LAW 7).
func _accent_for(_id: String) -> Color:
	return GameTheme.region_accent(GameManager.current_region)

# ------------------------------------------------------------------- the art --

## The primary model and its assembly go under one holder that is then shifted
## so the PRIMARY's footprint is centred on the node and its lowest point sits
## on the floor. Kenney origins are floor-anchored but not centred (furniture/
## desk runs x -0.01..0.724 from a corner; bedSingle reaches 1.9u north of its
## origin) and a few are not even floor-anchored (kitchenFridgeLarge min.y
## -0.40, character-keeper -0.20, cog-a -0.15, chest -0.05) — placed raw, a
## fridge stands 40cm into the floor and a bed lands a tile away from the spot
## its popup was written about.
func _build_prop() -> void:
	var key: String = str(PROP_MODEL.get(interact_id, FALLBACK_MODEL))
	var root := Map3D.model(key)
	if root == null:
		key = FALLBACK_MODEL
		root = Map3D.model(FALLBACK_MODEL)
	var holder := Node3D.new()
	holder.name = "Prop"
	add_child(holder)
	if root == null:
		# Last resort: a solid box, so an interactable is never invisible.
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.5, 0.5, 0.5)
		mi.mesh = box
		mi.position.y = 0.25
		# LAW 7: a stand-in is still a prop, and props do not glow. A SURFACE
		# override, not material_override: _collect_materials reads the active
		# material back, mutes it and installs its own surface override, and a
		# material_override would sit on top of that and hide both the mute and
		# the near-player highlight. The accent goes in raw here; the mute below
		# is the one that desaturates and caps it.
		mi.set_surface_override_material(0, Map3D.matte(_accent, 0.0))
		holder.add_child(mi)
		_collect_materials(self)
		return
	root.name = key.get_file()
	holder.add_child(root)
	for part: Array in PROP_EXTRA.get(interact_id, []):
		var extra := Map3D.model(str(part[0]))
		if extra == null:
			continue
		extra.position = part[1] as Vector3
		holder.add_child(extra)
	holder.position = _anchor_offset(key)
	_collect_materials(self)

## The translation that centres a model's authored XZ footprint on the origin
## and lifts its lowest point onto the floor. Zero for an unknown key.
static func _anchor_offset(key: String) -> Vector3:
	var b := Map3D.bounds(key)
	if b.is_empty():
		return Vector3.ZERO
	var mn: Array = b.get("min", [0.0, 0.0, 0.0])
	var mx: Array = b.get("max", [0.0, 0.0, 0.0])
	return Vector3(
		-(float(mn[0]) + float(mx[0])) * 0.5,
		-minf(float(mn[1]), 0.0),
		-(float(mn[2]) + float(mx[2])) * 0.5)

## Duplicate every surface material into an override we own, mute it toward the
## region's BASE and under LAW 3's value ceiling (LAW 7), and switch on emission
## ONLY on a part the assembly proves is a screen SUB-mesh. `_mat_base` keeps the
## resting albedo so the proximity highlight is always computed from it, never
## accumulated onto it.
func _collect_materials(node: Node) -> void:
	var parts: Array[MeshInstance3D] = []
	_gather_meshes(node, parts)
	# The whole assembly's box, in this node's own space, so a part can be
	# measured against the object it belongs to rather than against a constant.
	var whole := AABB()
	var first := true
	for mi: MeshInstance3D in parts:
		var b := _part_box(mi)
		if first:
			whole = b
			first = false
		else:
			whole = whole.merge(b)
	# Never zero: _box_volume floors every axis at PART_EPS.
	var whole_vol := _box_volume(whole)
	for mi: MeshInstance3D in parts:
		var share := _box_volume(_part_box(mi)) / whole_vol
		var lit := _screen_emit > 0.0 and share <= SCREEN_PART_MAX_SHARE \
			and _is_screen_part(mi)
		for i in mi.mesh.get_surface_count():
			var src: Material = mi.get_active_material(i)
			var mat: StandardMaterial3D
			if src is StandardMaterial3D:
				mat = (src as StandardMaterial3D).duplicate()
			else:
				mat = StandardMaterial3D.new()
				mat.roughness = 0.9
				mat.metallic = 0.0
			var muted := _muted(mat.albedo_color)
			mat.albedo_color = muted
			if lit:
				# LAW 7's one exception, on the one surface it applies to.
				mat.emission_enabled = true
				mat.emission = _at_value(_accent, SCREEN_VALUE)
				mat.emission_energy_multiplier = _screen_emit
			else:
				mat.emission_enabled = false
				mat.emission_energy_multiplier = 0.0
			mi.set_surface_override_material(i, mat)
			_mats.append(mat)
			_mat_base.append(muted)
			_mat_screen.append(lit)

## Every drawable MeshInstance3D under `node`, in tree order. A MeshInstance3D
## with no mesh is skipped: it has no surfaces to override and no bounds to
## measure, and `get_aabb()` on one would fold an empty box into the assembly.
static func _gather_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node as MeshInstance3D)
	for c in node.get_children():
		_gather_meshes(c, out)

## A part's bounds expressed in THIS node's space. Built by walking the parent
## chain rather than through `global_transform`, so the measurement is the same
## whether a builder positioned this node before or after adding it to the tree,
## and is unaffected by where in the room the prop ended up standing.
func _rel_xform(mi: MeshInstance3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = mi
	while n != null and n != self:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf

func _part_box(mi: MeshInstance3D) -> AABB:
	return _rel_xform(mi) * mi.get_aabb()

## Volume with a floor under each axis, so a flat screen quad measures as a thin
## slab instead of as nothing and the assembly can never measure as zero.
static func _box_volume(b: AABB) -> float:
	return maxf(b.size.x, PART_EPS) * maxf(b.size.y, PART_EPS) * maxf(b.size.z, PART_EPS)

## `c` rescaled so its brightest channel is `v` — hue and saturation intact, the
## value pinned. Only ever darkens: an accent already below `v` is left alone
## rather than pumped up to meet it.
static func _at_value(c: Color, v: float) -> Color:
	var m: float = maxf(maxf(c.r, c.g), c.b)
	if m <= 0.0001:
		return c
	var k: float = minf(1.0, v / m)
	return Color(c.r * k, c.g * k, c.b * k, c.a)

## LAW 7: "props desaturated toward the region BASE". Half the chroma out of
## Kenney's colormap, then a quarter of the way into the room's own dark — the
## prop keeps its material identity (wood is still warmer than steel) and stops
## being a second saturated hue in a scene that is allowed three — and then LAW
## 3's value ceiling, which is the step that turns off the whites (PROP_VALUE_MAX).
func _muted(c: Color) -> Color:
	var grey: float = (c.r + c.g + c.b) / 3.0
	var flat := Color(grey, grey, grey, c.a)
	var toward := Color(_base.r, _base.g, _base.b, c.a)
	return _at_value(c.lerp(flat, 0.5).lerp(toward, 0.25), PROP_VALUE_MAX)

## Is this mesh part of the assembly's lit surface? Walks from the mesh up to
## this node, so a `computerScreen` standing on a `desk` is a screen and the
## desk under it is furniture. A name on NOT_SCREEN settles it immediately, at
## whatever level it appears: the keyboard beside the monitor is not the monitor
## merely because Kenney calls it a `computerKeyboard`.
##
## Saying yes here is necessary but not sufficient — `_collect_materials` then
## checks that the part is small enough to BE a face rather than the whole
## appliance (SCREEN_PART_MAX_SHARE).
func _is_screen_part(mi: MeshInstance3D) -> bool:
	var n: Node = mi
	var hit := false
	while n != null and n != self:
		var nm := n.name.to_lower()
		for veto: String in NOT_SCREEN:
			if nm.contains(veto):
				return false
		if not hit:
			for hint: String in SCREEN_HINTS:
				if nm.contains(hint):
					hit = true
					break
		n = n.get_parent()
	return hit

# --------------------------------------------------------------------- frame --

## generic_interactable.gd's step-up-and-hold highlight, in ALBEDO and in albedo
## ONLY: the prop lifts ten per cent as you come into range and holds while you
## are there, and the screen face (if it has one) keeps burning at exactly the
## level it was already burning at. LAW 9's 6% flicker rides on that face and
## nothing else. The [E] prompt (player-side) fades in on top of it.
func _process(delta: float) -> void:
	_clock += delta
	if _proxy:
		_proxy.sync()
	var near := false
	var player := get_tree().get_first_node_in_group("player")
	if player is Node3D:
		near = global_position.distance_to((player as Node3D).global_position) < NEAR_RADIUS
	var want := 1.0 if near else 0.0
	if is_equal_approx(_gate, want) and _gate <= 0.001:
		return
	_gate = move_toward(_gate, want, delta * GATE_RATE)
	var flicker: float = 0.94 + 0.06 * sin(_clock * 1.7)
	for i in _mats.size():
		var m: StandardMaterial3D = _mats[i]
		m.albedo_color = _mat_base[i].lightened(HIGHLIGHT_LIFT * _gate)
		if _mat_screen[i]:
			m.emission_energy_multiplier = _screen_emit * flicker

# ------------------------------------------------------------------ interact --

## Straight through to the 2D brain: `Interactable.interact()` runs the one_shot
## gate, `QuestManager.on_interact(interact_id)` and the whole
## `GenericInteractable._on_interact` match.
func interact(player: Node = null) -> void:
	if is_instance_valid(_delegate) and _delegate.has_method("interact"):
		_delegate.call("interact", player)
		return
	# No delegate scene (should never happen): still credit the quest system so
	# an objective can never be made unreachable by a missing 2D file.
	if one_shot and _used:
		return
	_used = true
	QuestManager.on_interact(interact_id)

func get_prompt() -> String:
	if is_instance_valid(_delegate) and _delegate.has_method("get_prompt"):
		return str(_delegate.call("get_prompt"))
	return interact_text
