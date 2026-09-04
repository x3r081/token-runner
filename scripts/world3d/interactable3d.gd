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
## real one. In that room this node is a hotspot: the 2D brain, the proxy, and a
## floor ring that lights up as you close — no model, no light.

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
const DEFAULT_BASE := Color("#0B0E1C")

## LAW 7's ONE exception for a prop: "only screens/lamps carry ACCENT or WARM,
## and only on their lit surface". So this is no longer a light table — it is
## how hard a SCREEN FACE is switched on, capped (below), and it is applied only
## to the parts of an assembly whose node name says they are a screen (see
## `_is_screen_part`). Round 1 put `emission = accent` on EVERY surface of every
## prop at a floor of 0.55 and lifted the whole object to 1.45 as the player
## approached: that is a crate that glows, a gravestone that glows, a shelf of
## bags that glows, and it is most of why the dependency_district frame is a
## field of luminous yellow boxes.
## CAP: 1.6, and nothing in this game is allowed over it. A screen face is the
## ONE emissive surface a prop may have (LAW 7), and at 1.8-2.0 it stopped being
## a lit surface and became a lamp with a picture on it — the ad board in
## api_bazaar was blowing out its own frame.
const SCREEN_EMIT_MAX := 1.6
const SCREEN_EMIT := {
	"deploy_button": 1.6,
	"broken_service": 1.6,
	"free_tokens_ad": 1.6,
	"agent_terminal": 1.6,
	"dream_app_terminal": 1.6,
	"prop_status_page": 1.6,
	"prop_dashboard": 1.6,
	"prop_kanban": 1.4,
	"prop_accepted": 1.2,
	"backup_server": 1.4,
	"prop_pager": 1.4,
	"prop_monitors": 1.4,
	"prop_terminal": 1.4,
	"prop_server": 1.2,
	"prop_router": 1.0,
}

## The handful of props that are a MOTIVATED LIGHT in the fiction — a monitor
## bank, an ad board, a failing service's alarm. LAW 3 allows a frame two of
## these and LAW 4 puts every world light in the 0.4-0.9 band with a soft
## radius, so a room with three interactables now spends about as much light in
## total as ONE of the old 3.4-energy, range-6 prop lamps did. A prop not in
## this table is lit by the room, like every other object in it.
const PROP_POOL := {
	"deploy_button": 0.55,
	"broken_service": 0.70,
	"free_tokens_ad": 0.80,
	"agent_terminal": 0.70,
	"dream_app_terminal": 0.70,
	"prop_status_page": 0.70,
	"prop_dashboard": 0.70,
	"prop_kanban": 0.60,
	"prop_accepted": 0.60,
	"backup_server": 0.60,
	"prop_pager": 0.50,
}
const POOL_RANGE := 3.5

## Node names that mean "this part of the assembly is the lit surface". Kenney
## names its meshes after the thing they are (`computerScreen`, `display-wall`,
## `button-floor-round`), and Map3D.model() keeps that name on the instance, so
## a desk stays a desk while the screen standing on it is the part that is on.
const SCREEN_HINTS := ["screen", "display", "monitor", "computer", "button", "panel", "terminal"]

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
## The hotspot ring (dressed rooms only): a thin flat hoop on the floor around
## the thing the builder already placed, in the prop's accent, that fades in
## with the same gate the emissive highlight uses everywhere else.
const RING_INNER := 0.34
const RING_OUTER := 0.42
const RING_Y := 0.02
## Under 1.0, so the hoop is a mark on the floor rather than a lit one: at 1.6
## it crossed the §7 glow threshold and bloomed a ring of accent around every
## hotspot in the apartment. LAW 5 spends bloom on LAW 3's five things only.
const RING_GAIN := 0.9
const RING_ALPHA := 0.55

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
var _light: OmniLight3D
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _light_base := 0.0
var _emit_floor := 0.0
var _gate := 0.0
var _clock := 0.0
var _used := false
var _proxy: ActorProxy

func _ready() -> void:
	add_to_group("interactable")
	_build_delegate()
	_accent = _accent_for(interact_id)
	_base = REGION_BASE.get(GameManager.current_region, DEFAULT_BASE)
	_emit_floor = minf(float(SCREEN_EMIT.get(interact_id, 0.0)), SCREEN_EMIT_MAX)
	# region_portal.gd's guarantee holds here too: `GameManager.current_region`
	# is already the room being populated by the time a prop enters the tree.
	if GameManager.current_region in DRESSED_REGIONS:
		dressed = true
	if dressed:
		_build_ring()
	else:
		_build_prop()
		_build_light()
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
		# LAW 7: a stand-in is still a prop, and props do not glow.
		mi.material_override = Map3D.matte(_muted(_accent), 0.0)
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

## The dressed-room cue: a flat hoop on the floor, additive and unshaded in the
## prop's accent, invisible at rest and lifted over the glow threshold by the
## gate as you close. It says "lever" without adding a second object to a room
## the builder already finished.
func _build_ring() -> void:
	_ring = MeshInstance3D.new()
	_ring.name = "HotspotRing"
	var t := TorusMesh.new()
	t.inner_radius = RING_INNER
	t.outer_radius = RING_OUTER
	t.rings = 40
	t.ring_segments = 6
	_ring.mesh = t
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring_mat.disable_receive_shadows = true
	_ring_mat.albedo_color = Color(_accent.r * RING_GAIN, _accent.g * RING_GAIN,
		_accent.b * RING_GAIN, 0.0)
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# TorusMesh lies in the XZ plane already (its axis is +Y); no rotation.
	_ring.position = Vector3(0.0, RING_Y, 0.0)
	_ring.visible = false
	add_child(_ring)

## Duplicate every surface material into an override we own, mute it toward the
## region's BASE (LAW 7), and switch on emission ONLY where the assembly says
## there is a screen. `_mat_base` keeps the resting albedo so the proximity
## highlight is always computed from it, never accumulated onto it.
func _collect_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var lit := _emit_floor > 0.0 and _is_screen_part(mi)
		if mi.mesh:
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
					mat.emission = _accent
					mat.emission_energy_multiplier = _emit_floor
				else:
					mat.emission_enabled = false
					mat.emission_energy_multiplier = 0.0
				mi.set_surface_override_material(i, mat)
				_mats.append(mat)
				_mat_base.append(muted)
				_mat_screen.append(lit)
	for c in node.get_children():
		_collect_materials(c)

## LAW 7: "props desaturated toward the region BASE". Half the chroma out of
## Kenney's colormap, then a quarter of the way into the room's own dark — the
## prop keeps its material identity (wood is still warmer than steel) and stops
## being a second saturated hue in a scene that is allowed three.
func _muted(c: Color) -> Color:
	var grey: float = (c.r + c.g + c.b) / 3.0
	var flat := Color(grey, grey, grey, c.a)
	var toward := Color(_base.r, _base.g, _base.b, c.a)
	return c.lerp(flat, 0.5).lerp(toward, 0.25)

## Is this mesh part of the assembly's lit surface? Walks from the mesh up to
## this node, so a `computerScreen` standing on a `desk` is a screen and the
## desk under it is furniture.
func _is_screen_part(mi: MeshInstance3D) -> bool:
	var n: Node = mi
	while n != null and n != self:
		var nm := n.name.to_lower()
		for hint: String in SCREEN_HINTS:
			if nm.contains(hint):
				return true
		n = n.get_parent()
	return false

## The pool a motivated prop casts. LAW 4's band (0.4-0.9) at a radius that
## reaches the floor around it and stops — not the 3.4-at-range-6 spot-halo that
## put a coloured wash across four tiles of every room it stood in.
##
## MOTIVATED means the player can see what is casting it: the pool is only
## built when `_collect_materials` actually switched a screen face on. A prop
## in PROP_POOL whose assembly has no screen part (broken_service is a bare
## container-tall; prop_accepted is a gravestone) would be a coloured pool on
## the floor with nothing above it emitting — the unexplained light LAW 3 says
## is too bright by definition.
func _build_light() -> void:
	if not PROP_POOL.has(interact_id):
		return
	if not _mat_screen.has(true):
		return
	_light_base = float(PROP_POOL[interact_id])
	_light = OmniLight3D.new()
	_light.name = "PropLight"
	_light.light_color = _accent
	_light.light_energy = _light_base
	_light.omni_range = POOL_RANGE
	_light.omni_attenuation = 1.6
	_light.shadow_enabled = false
	_light.position = Vector3(0.0, 0.75, 0.25)
	add_child(_light)

# --------------------------------------------------------------------- frame --

## generic_interactable.gd's step-up-and-hold highlight, in ALBEDO: the prop
## lifts ten per cent as you come into range and holds while you are there, and
## the screen face (if it has one) keeps burning at exactly the level it was
## already burning at. LAW 9's 6% flicker rides on the lamp and nothing else.
## The [E] prompt (player-side) fades in on top of it.
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
			m.emission_energy_multiplier = _emit_floor * flicker
	if _light:
		_light.light_energy = _light_base * (flicker + _gate * 0.15)
	if _ring_mat:
		_ring_mat.albedo_color.a = _gate * flicker * RING_ALPHA
		_ring.visible = _gate > 0.001

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
