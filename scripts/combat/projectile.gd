extends Area2D
class_name Projectile

var direction := Vector2.RIGHT
var damage: int = 10
var speed: float = 400.0
var lifetime: float = 2.0
var pierce := false
var proj_type := "prompt_blast"
## Set by Player before the bolt enters the tree.
## `weak`: the model hallucinated — the shot is a confident, useless sputter.
## `crit`: this one is going to hurt, and it is going to say so.
var weak := false
var crit := false
var _hit: Array = []
var _accent := Color(0.25, 0.95, 0.86)
var _trail: Line2D
var _pierce_count := 0
var _origin := Vector2.ZERO

@onready var sprite: ColorRect = $ColorRect

const TRAIL_POINTS := 12

## Stack Trace prints one frame per enemy it punches through. The last line is
## always "... 47 more", because the last line is always "... 47 more".
const STACK_FRAMES := [
	"at main()", "at handler()", "at retry()", "at Object.<anonymous>",
	"at process._tickCallback", "at doTheThing()", "at ???",
	"at node_modules/left-pad/index.js:1",
]

func _ready() -> void:
	add_to_group("player_projectile")
	collision_layer = 16
	collision_mask = 2
	area_entered.connect(_on_area_entered)
	_origin = global_position
	# Depth: above every world prop (which y-sort up to ~1050) and above the
	# WorldLabel plates at 1150, so your own shot is never swallowed by scenery.
	# Below NPC name tags is fine — a bolt is in flight for a fifth of a second.
	z_index = CombatFx.Z_FX
	_build_visuals()

## A real bolt of light: additive fx_glow_dot halo + white-hot core (overbright,
## so HDR bloom picks it up), a fading Line2D trail, a small PointLight2D
## carving through the dark, and — for a full-power Prompt Blast — a pocket of
## visibly bent space travelling with it. Falls back to the legacy ColorRect
## when the generated art is missing.
func _build_visuals() -> void:
	var size_mult := 1.0
	if proj_type == "stack_trace":
		# A faster, longer, magenta piercing beam.
		speed = 560.0
		lifetime = 1.4
		_accent = Color(1.0, 0.28, 0.68)
		size_mult = 1.15
	if weak:
		# Hallucinated: violet, slow, and visibly out of ideas.
		_accent = Color(0.55, 0.36, 0.96)
		speed *= 0.62
		lifetime = 0.75
		size_mult = 0.6
	elif crit:
		# Crit: gold-hot and fatter, so you can see it coming before it lands.
		_accent = _accent.lerp(Color(1.0, 0.83, 0.30), 0.55)
		size_mult *= 1.45
	var dot := FxLib.glow_dot()
	if dot:
		sprite.visible = false
		var halo := Sprite2D.new()
		halo.texture = dot
		halo.material = FxLib.additive_material()
		halo.modulate = Color(_accent.r * 2.2, _accent.g * 2.2, _accent.b * 2.2, 0.8)
		var base_scale := Vector2(2.8, 1.7) if proj_type == "stack_trace" else Vector2(2.1, 1.5)
		halo.scale = base_scale * size_mult
		add_child(halo)
		var core := Sprite2D.new()
		core.texture = dot
		core.material = FxLib.additive_material()
		core.modulate = Color(2.6, 2.6, 2.6)  # WHITE_HOT center
		core.scale = Vector2(1.4, 0.7) * size_mult
		add_child(core)
		# Spawn pop: the bolt snaps out to size in two frames.
		halo.scale *= 0.4
		var pop := halo.create_tween()
		pop.tween_property(halo, "scale", base_scale * size_mult, 0.07) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		# Legacy rectangle, still bigger/brighter than the world around it.
		sprite.color = Color(_accent.r, _accent.g, _accent.b, 1.0)
		sprite.size = (Vector2(30, 9) if proj_type == "stack_trace" else Vector2(22, 9)) * size_mult
		sprite.position = -sprite.size * 0.5
	# Fading world-space trail (top_level: points stay put as the bolt flies).
	_trail = Line2D.new()
	_trail.top_level = true
	_trail.width = 10.0 * size_mult
	_trail.joint_mode = Line2D.LINE_JOINT_ROUND
	_trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_trail.end_cap_mode = Line2D.LINE_CAP_ROUND
	_trail.material = FxLib.additive_material()
	var grad := Gradient.new()
	grad.set_color(0, Color(_accent.r, _accent.g, _accent.b, 0.0))
	grad.set_color(1, Color(_accent.r * 1.8, _accent.g * 1.8, _accent.b * 1.8, 0.65))
	_trail.gradient = grad
	var wc := Curve.new()
	wc.add_point(Vector2(0.0, 0.12))
	wc.add_point(Vector2(1.0, 1.0))
	_trail.width_curve = wc
	# top_level keeps the trail's POINTS in world space; its depth still has to be
	# stated absolutely, just behind the bolt head.
	_trail.z_as_relative = false
	_trail.z_index = CombatFx.Z_FX - 3
	add_child(_trail)
	# Travelling distortion: a pocket of bent space riding along with a
	# full-power bolt. Null when the shader library is absent — that's fine.
	if not weak:
		var haze_size := 52.0 if proj_type == "stack_trace" else 42.0
		var haze := CombatFx.distortion(self, haze_size, 0.0034 if crit else 0.0026, 2.4)
		if haze:
			# Screen-reading: must draw after the world it bends, before the bolt.
			haze.z_index = -6
	# A tiny light so every shot is also a light source (bible lighting rules).
	FxLib.point_light(self, _accent, 1.05 if crit else 0.8, 0.42 if crit else 0.3)

func setup(dir: Vector2, dmg: int, type: String) -> void:
	direction = dir.normalized()
	damage = dmg
	proj_type = type
	rotation = direction.angle()

func _physics_process(delta: float) -> void:
	position += direction * speed * delta
	if weak:
		# A hallucinated bolt cannot hold a straight line either.
		position += direction.orthogonal() * sin(lifetime * 26.0) * 42.0 * delta
	if _trail:
		_trail.add_point(global_position)
		if _trail.get_point_count() > TRAIL_POINTS:
			_trail.remove_point(0)
	lifetime -= delta
	if lifetime <= 0:
		_expire()

## Out of range. A weak bolt fizzles visibly, so the player learns that the
## cheap model is the reason nothing happened.
func _expire() -> void:
	if weak:
		var host := get_parent()
		if host:
			FxLib.burst(host, global_position, Color(1.1, 0.72, 1.9), 6, 70.0,
				FxLib.glow_dot(), Vector2(0, 90), CombatFx.Z_FX)
	_retire_trail()
	queue_free()

## Hand the trail to our parent and fade it out, so the light doesn't vanish in
## a single frame when the bolt dies.
func _retire_trail() -> void:
	if _trail == null or not is_instance_valid(_trail):
		return
	var host := get_parent()
	if host:
		remove_child(_trail)
		host.add_child(_trail)
		var tw := _trail.create_tween()
		tw.tween_property(_trail, "modulate:a", 0.0, 0.18)
		tw.tween_callback(_trail.queue_free)
	_trail = null

func _on_area_entered(area: Area2D) -> void:
	var parent := area.get_parent()
	if parent and parent.is_in_group("enemy") and parent.has_method("take_damage"):
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
		_impact_fx()
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
	if host == null or not (enemy is Node2D):
		return
	var pos: Vector2 = (enemy as Node2D).global_position
	var text: String = "... 47 more" if _pierce_count >= 4 else ComedyLines.pick("stack_frames", STACK_FRAMES)
	CombatFx.glyph(host, pos + Vector2(0, -46 - _pierce_count * 5), text, Color(1.0, 0.55, 0.82), 13, 0.95, 34.0)
	# The trace burns a mark on the floor between the enemies it passed through.
	CombatFx.scorch(host, _origin, pos, _accent, 1.6)

## Sparks + a ring flash + a screen kick, layered by how hard the hit was. A
## crit adds a white-hot bloom, a bigger ring, a "CRIT" callout and hit-stop.
## Null-safe: the camera_fx rig may not exist yet (tests, or the postfx agent).
func _impact_fx() -> void:
	if not is_inside_tree():
		return
	var host := get_parent()
	if host:
		var hot := Color(_accent.r * 2.0, _accent.g * 2.0, _accent.b * 2.0)
		FxLib.burst(host, global_position, hot, 16 if crit else 10, 330.0 if crit else 240.0,
			FxLib.spark(), Vector2.ZERO, CombatFx.Z_FX)
		FxLib.flash(host, global_position, _accent, 0.3, 2.6 if crit else 1.6, 0.2, CombatFx.Z_FX)
		CombatFx.ring(host, global_position, _accent, 3.0, 62.0 if crit else 34.0, 0.26, 6.0, 1.0, 24)
		if crit:
			CombatFx.ring(host, global_position, Color(1, 1, 1), 2.0, 40.0, 0.2, 4.0, 0.8, 20)
			CombatFx.ripple(host, global_position, direction, _accent, 74.0, 0.26)
	FxLib.add_trauma(get_tree(), 0.3 if crit else 0.15)
	if crit:
		FxLib.hit_stop(get_tree(), 0.08, 0.045)
