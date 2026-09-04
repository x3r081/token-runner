extends Area3D
class_name Projectile3D
## The player's bolt in 3D (3D_BIBLE.md §4). A port of scripts/combat/
## projectile.gd: same speeds, same lifetimes, same pierce/weak/crit rules, same
## hit handling — a fight that was winnable in 2D is winnable here.
##
## It flies on the XZ plane at chest height (y ≈ 0.6) so it reads against the
## room rather than skidding along the floor, and it is built in three layers the
## way the 2D bolt was: an accent BODY, a white-hot CORE that blooms on its own,
## and a trail. Plus the thing 2D could only fake — a real light travelling with
## it, so a shot passing a wall lights it for a frame.

## Direction is MAP SPACE (the language every manager, ability and table speaks);
## the flight converts to world units once, in `_physics_process`.
var direction := Vector2.RIGHT
var damage: int = 10
var speed: float = 400.0        ## map px/s — the 2D number
var lifetime: float = 2.0
var pierce := false
var proj_type := "prompt_blast"
## Set by the player before the bolt enters the tree.
## `weak`: the model hallucinated — the shot is a confident, useless sputter.
## `crit`: this one is going to hurt, and it is going to say so.
var weak := false
var crit := false

const FLY_Y := 0.6
## How many world-space samples the ribbon keeps. 12 at 6 u/s is about a third
## of a second of tail.
const TRAIL_POINTS := 12
## §9 budgets the region's lights; a Stack Trace volley can put five bolts in
## the air at once and every one of them wants to glow.
const MAX_LIGHTS := 6
static var _live_lights := 0

var _hit: Array = []
var _accent := Color(0.25, 0.95, 0.86)
var _size_mult := 1.0
var _pierce_count := 0
var _origin := Vector3.ZERO
var _trail_pts: PackedVector3Array = PackedVector3Array()
var _trail: MeshInstance3D
var _trail_mesh: ImmediateMesh
var _trail_mat: StandardMaterial3D
var _core: MeshInstance3D
var _core_base := Vector3.ONE
var _lamp: OmniLight3D
var _anim_t := 0.0

@onready var _body: MeshInstance3D = $Body
@onready var _shape: CollisionShape3D = $CollisionShape3D

## Stack Trace prints one frame per enemy it punches through. The last line is
## always "... 47 more", because the last line is always "... 47 more".
const STACK_FRAMES := [
	"at main()", "at handler()", "at retry()", "at Object.<anonymous>",
	"at process._tickCallback", "at doTheThing()", "at ???",
	"at node_modules/left-pad/index.js:1",
]

## What a hallucinated bolt says when it runs out of road. Decorative only — the
## information ("that shot did nothing") is carried by the bolt visibly losing
## cohesion; this is just the model's excuse.
const FIZZLE_LINES := [
	"[citation needed]",
	"confidently",
	"source: trust me",
	"as we all know",
	"temperature was high",
	"no such function",
]

func _ready() -> void:
	add_to_group("player_projectile")
	collision_layer = 16
	collision_mask = 2
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)
	_origin = global_position
	_build_visuals()

## Each ability is meant to be identifiable in flight without reading the HUD:
##   * Prompt Blast — a compact cyan bolt with a breathing core;
##   * Stack Trace  — a long magenta lance, fatter and faster, that pierces;
##   * hallucinated — a small violet thing that wobbles and flickers;
##   * a crit of any of the above — gold-hot and fatter.
func _build_visuals() -> void:
	_size_mult = 1.0
	if proj_type == "stack_trace":
		# A faster, longer, magenta piercing beam.
		speed = 560.0
		lifetime = 1.4
		_accent = Color(1.0, 0.28, 0.68)
		_size_mult = 1.15
	if weak:
		# Hallucinated: violet, slow, and visibly out of ideas.
		_accent = Color(0.55, 0.36, 0.96)
		speed *= 0.62
		lifetime = 0.75
		_size_mult = 0.6
	elif crit:
		# Crit: gold-hot and fatter, so you can see it coming before it lands.
		_accent = _accent.lerp(Color(1.0, 0.83, 0.30), 0.55)
		_size_mult *= 1.45
	var is_lance: bool = proj_type == "stack_trace"
	# 1. Body — the accent at full strength, stretched along the flight axis.
	if is_instance_valid(_body):
		_body.material_override = _hot_mat(_accent, 2.2, 0.85)
		var body_len: float = (0.34 if is_lance else 0.24) * _size_mult
		_body.scale = Vector3(0.13 * _size_mult, 0.13 * _size_mult, body_len)
		_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 2. Core — near-white, blooms on its own.
	_core = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 8
	sphere.rings = 4
	_core.mesh = sphere
	_core.material_override = _hot_mat(Color(1.0, 1.0, 1.0), 2.4)
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_core_base = Vector3(0.085, 0.085, 0.2) * _size_mult
	_core.scale = _core_base
	add_child(_core)
	if is_instance_valid(_shape):
		_shape.scale = Vector3.ONE * clampf(_size_mult, 0.6, 1.6)
	_build_trail()
	# A tiny light so a shot passing a wall lights it for a frame. The region's
	# own lamps sit at 2.5-5 energy (§7) and a bolt is in flight for a fifth of a
	# second — it should read as travelling THROUGH the room's lighting, not as a
	# brighter lamp than any lamp in it.
	if _live_lights < MAX_LIGHTS:
		_lamp = OmniLight3D.new()
		_lamp.light_color = _accent
		# v2 LAW 3: a bolt is combat and may be bright, but the light it drags
		# through the room is capped near the moon's own order of magnitude.
		# The hot core and the trail are what the player reads; this only tells
		# the wall it passes that something went by.
		_lamp.light_energy = 1.5 if crit else 1.1
		_lamp.omni_range = 3.0 if crit else 2.4
		_lamp.omni_attenuation = 1.6
		_lamp.shadow_enabled = false
		add_child(_lamp)
		Projectile3D._live_lights += 1
		tree_exiting.connect(func() -> void:
			Projectile3D._live_lights = maxi(0, Projectile3D._live_lights - 1))

## An overbright ADDITIVE material — the project's one way of making a thing
## bloom (VISUAL_BIBLE's HDR recipe, and how fx3d.gd builds every hot surface).
##
## Deliberately not "unshaded + emission": an UNSHADED material writes ALBEDO
## straight to the buffer and ignores `emission` entirely, so a hot core built
## that way is simply a flat mid-grey ball. Above 1.0 the albedo itself is what
## crosses the glow threshold.
static func _hot_mat(col: Color, boost: float, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.disable_receive_shadows = true
	m.albedo_color = Color(col.r * boost, col.g * boost, col.b * boost, alpha)
	return m

## One world-space ribbon behind the bolt: a triangle strip laid flat in the XZ
## plane, which is the plane the 3/4 camera looks down on. Rebuilt each frame
## from the last TRAIL_POINTS positions — an ImmediateMesh is exactly the tool
## for "a handful of verts that change every frame".
func _build_trail() -> void:
	_trail = MeshInstance3D.new()
	_trail_mesh = ImmediateMesh.new()
	_trail.mesh = _trail_mesh
	# Additive, and driven by VERTEX colour: the ribbon's own alpha ramp is what
	# fades the tail, and `albedo_color:a` is left as the one dial `_retire_trail`
	# turns down when the bolt dies.
	_trail_mat = _hot_mat(Color(1.0, 1.0, 1.0), 1.0)
	_trail_mat.vertex_color_use_as_albedo = true
	_trail.material_override = _trail_mat
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The ribbon's points are world-space, so the node must not inherit the
	# bolt's own transform.
	_trail.top_level = true
	add_child(_trail)
	_trail.global_transform = Transform3D.IDENTITY

## Called by the player before the bolt enters the tree. `dir` is map space.
func setup(dir: Vector2, dmg: int, type: String) -> void:
	direction = dir.normalized() if dir.length_squared() > 0.0001 else Vector2.RIGHT
	damage = dmg
	proj_type = type
	# Point the model's forward (-Z) down the flight line.
	rotation.y = atan2(-direction.x, -direction.y)

func _physics_process(delta: float) -> void:
	# Player3D parents the bolt FIRST and moves it to the muzzle after, so the
	# `_origin` read in `_ready` is the host's origin, not the muzzle. The first
	# tick is the first frame the bolt is where it was fired from: the trace's
	# scorch (`_pierce_frame`) is drawn from here, and a beam from (0,0,0) is a
	# line from the corner of the map.
	if _trail_pts.is_empty():
		_origin = global_position
	_anim_t += delta
	var step: Vector2 = direction * speed * delta
	if weak:
		# A hallucinated bolt cannot hold a straight line either.
		step += direction.orthogonal() * sin(lifetime * 26.0) * 42.0 * delta
	# The one place the flight leaves map space (§2's coordinate law).
	global_position += Vector3(step.x, 0.0, step.y) / Map3D.PX
	global_position.y = FLY_Y
	# The core never sits still. A healthy bolt breathes; a hallucinated one
	# flickers like something that is not sure it is there.
	if is_instance_valid(_core):
		if weak:
			var f: float = 0.55 + 0.45 * sin(_anim_t * 34.0)
			_core.scale = _core_base * f
		else:
			_core.scale = _core_base * (1.0 + 0.22 * sin(_anim_t * 26.0))
	_push_trail()
	lifetime -= delta
	if lifetime <= 0:
		_expire()

func _push_trail() -> void:
	_trail_pts.append(global_position)
	while _trail_pts.size() > TRAIL_POINTS:
		_trail_pts.remove_at(0)
	if not is_instance_valid(_trail) or _trail_mesh == null:
		return
	_trail_mesh.clear_surfaces()
	if _trail_pts.size() < 2:
		return
	var half: float = 0.045 * _size_mult
	var perp := Vector3(-direction.y, 0.0, direction.x)
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _trail_mat)
	for i in _trail_pts.size():
		# Tapered and faded toward the tail, so the ribbon reads as a wake rather
		# than as a stick glued to the back of the bolt.
		var u: float = float(i) / float(maxi(1, _trail_pts.size() - 1))
		var w: float = half * (0.12 + 0.88 * u)
		var p: Vector3 = _trail_pts[i]
		# Overbright accent (it is a wake of light, and the glow threshold is 1.0)
		# with the alpha ramp that makes it a wake rather than a stick.
		# Modest: the wake is a fading ribbon, not a second bolt. 1.35 keeps the
		# head of it just over the glow threshold and lets the tail fall under,
		# which is what makes it read as a taper rather than as a stripe.
		var col := Color(_accent.r * 1.35, _accent.g * 1.35, _accent.b * 1.35,
			u * u * (0.35 if weak else 0.6))
		_trail_mesh.surface_set_color(col)
		_trail_mesh.surface_add_vertex(p - perp * w)
		_trail_mesh.surface_set_color(col)
		_trail_mesh.surface_add_vertex(p + perp * w)
	_trail_mesh.surface_end()

## Out of range. This must NOT look like a shot that connected — the player
## learns the weapon's reach from the difference. So: no ring, no shake. The
## bolt loses cohesion and drops a few dying embers. A hallucinated bolt
## occasionally offers an excuse on the way down.
func _expire() -> void:
	var host := get_parent()
	if host:
		var pos := global_position
		Fx3D.burst(host, pos, Color(_accent.r * 1.4, _accent.g * 1.4, _accent.b * 1.4),
			6 if weak else 4, 1.6, 0.55)
		Fx3D.flash(host, pos, _accent, 0.9 * _size_mult, 0.22)
		if weak and randf() < 0.34:
			Fx3D.glyph(host, pos + Vector3(0.0, 0.3, 0.0),
				ComedyLines.pick("weak_fizzle", FIZZLE_LINES), Color("#8B5CF6"), 12, 0.85, 0.6)
	_retire_trail()
	queue_free()

## Hand the ribbon to our parent and fade it out, so the light doesn't vanish in
## a single frame when the bolt dies.
func _retire_trail() -> void:
	if not is_instance_valid(_trail):
		return
	var host := get_parent()
	var line := _trail
	_trail = null
	if host == null:
		return
	remove_child(line)
	host.add_child(line)
	line.global_transform = Transform3D.IDENTITY
	var tw := line.create_tween()
	tw.tween_property(_trail_mat, "albedo_color:a", 0.0, 0.18)
	tw.tween_callback(line.queue_free)

func _on_area_entered(area: Area3D) -> void:
	var parent := area.get_parent()
	if parent == null or not parent.is_in_group("enemy") or not parent.has_method("take_damage"):
		return
	if parent in _hit:
		return
	_hit.append(parent)
	parent.take_damage(damage, crit, direction)
	# Impact: shove the enemy along the shot so hits feel like they land.
	if parent.has_method("apply_knockback"):
		var kb := 430.0 if proj_type == "stack_trace" else 320.0
		if crit:
			kb *= 1.5
		if parent.get("is_boss"):
			kb *= 0.25  # bosses only flinch
		parent.apply_knockback(direction * kb)
	_impact_fx(parent)
	if pierce:
		_pierce_frame(parent)
	else:
		_retire_trail()
		queue_free()

## Every enemy a Stack Trace punches through adds a line to the trace, stacked
## upward. Comedy rides alongside: the information is "this hit landed too".
func _pierce_frame(enemy: Node) -> void:
	_pierce_count += 1
	var host := get_parent()
	if host == null or not (enemy is Node3D):
		return
	var pos: Vector3 = (enemy as Node3D).global_position
	var text: String = "... 47 more" if _pierce_count >= 4 else ComedyLines.pick("stack_frames", STACK_FRAMES)
	Fx3D.glyph(host, pos + Vector3(0.0, 1.0 + 0.12 * float(_pierce_count), 0.0), text,
		Color(1.0, 0.55, 0.82), 13, 0.95, 1.2)
	# The trace burns a mark between the enemies it passed through.
	Fx3D.beam(host, _origin, pos + Vector3(0.0, FLY_Y, 0.0), _accent, 0.05, 0.35)

## The layered impact: a core flash, a spark burst back along the shot, a ring,
## trauma scaled to the hit, and — on a crit — the short time-freeze that makes a
## big hit feel like one.
##
## `power` is the hit's severity normalised against a reference chunk of damage,
## so a 30-damage Stack Trace crit is visibly a bigger event than a 5-damage
## sputter, without either needing a hand-tuned effect.
func _impact_fx(victim: Node) -> void:
	if not is_inside_tree():
		return
	var host := get_parent()
	if host == null:
		return
	var pos := global_position
	var power: float = clampf(float(damage) / 18.0, 0.4, 2.2)
	Fx3D.burst(host, pos, Color(_accent.r * 2.0, _accent.g * 2.0, _accent.b * 2.0),
		int(6.0 + 8.0 * power), 3.0 + 2.0 * power, 0.35)
	Fx3D.flash(host, pos, _accent, 2.0 + 2.0 * power, 0.18)
	Fx3D.ring(host, Vector3(pos.x, 0.05, pos.z), _accent, 0.1, 0.5 + 0.5 * power, 0.24)
	Fx3D.add_trauma(get_tree(), clampf(0.06 * power, 0.03, 0.2) * (1.6 if crit else 1.0))
	if crit:
		Fx3D.hit_stop(get_tree())
	if proj_type == "stack_trace":
		# A lance: the force goes THROUGH, so the secondary read is a forward
		# ripple rather than another round pop.
		Fx3D.beam(host, pos, pos + Vector3(direction.x, 0.0, direction.y) * 0.6,
			_accent, 0.06, 0.18)
	# Kills earn their own beat. Checked on the victim's own HP so it fires once,
	# on the shot that actually finished it.
	if victim == null or not is_instance_valid(victim) or not (victim is Node3D):
		return
	var hp_left: Variant = victim.get("hp")
	if hp_left == null or int(hp_left) > 0:
		return
	Fx3D.shockwave(host, (victim as Node3D).global_position, _accent, 0.9 + 0.5 * power, 0.4)
	Fx3D.punch_zoom(get_tree(), 0.03)
