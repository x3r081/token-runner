extends Area2D
class_name Projectile

var direction := Vector2.RIGHT
var damage: int = 10
var speed: float = 400.0
var lifetime: float = 2.0
var pierce := false
var proj_type := "prompt_blast"
var _hit: Array = []
var _accent := Color(0.25, 0.95, 0.86)
var _trail: Line2D

@onready var sprite: ColorRect = $ColorRect

const TRAIL_POINTS := 12

func _ready() -> void:
	add_to_group("player_projectile")
	collision_layer = 16
	collision_mask = 2
	area_entered.connect(_on_area_entered)
	_build_visuals()

## A real bolt of light: additive fx_glow_dot halo + white-hot core (overbright,
## so HDR bloom picks it up), a fading Line2D trail, and a small PointLight2D
## carving through the dark. Falls back to the legacy ColorRect when the
## generated art is missing.
func _build_visuals() -> void:
	if proj_type == "stack_trace":
		# A faster, longer, magenta piercing beam.
		speed = 560.0
		lifetime = 1.4
		_accent = Color(1.0, 0.28, 0.68)
	var dot := FxLib.glow_dot()
	if dot:
		sprite.visible = false
		var halo := Sprite2D.new()
		halo.texture = dot
		halo.material = FxLib.additive_material()
		halo.modulate = Color(_accent.r * 2.2, _accent.g * 2.2, _accent.b * 2.2, 0.8)
		halo.scale = Vector2(2.8, 1.7) if proj_type == "stack_trace" else Vector2(2.1, 1.5)
		add_child(halo)
		var core := Sprite2D.new()
		core.texture = dot
		core.material = FxLib.additive_material()
		core.modulate = Color(2.6, 2.6, 2.6)  # WHITE_HOT center
		core.scale = Vector2(1.4, 0.7)
		add_child(core)
	else:
		# Legacy rectangle, still bigger/brighter than the world around it.
		sprite.color = Color(_accent.r, _accent.g, _accent.b, 1.0)
		sprite.size = Vector2(30, 9) if proj_type == "stack_trace" else Vector2(22, 9)
		sprite.position = -sprite.size * 0.5
	# Fading world-space trail (top_level: points stay put as the bolt flies).
	_trail = Line2D.new()
	_trail.top_level = true
	_trail.width = 10.0
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
	_trail.z_index = -1
	add_child(_trail)
	# A tiny light so every shot is also a light source (bible lighting rules).
	FxLib.point_light(self, _accent, 0.8, 0.3)

func setup(dir: Vector2, dmg: int, type: String) -> void:
	direction = dir.normalized()
	damage = dmg
	proj_type = type
	rotation = direction.angle()

func _physics_process(delta: float) -> void:
	position += direction * speed * delta
	if _trail:
		_trail.add_point(global_position)
		if _trail.get_point_count() > TRAIL_POINTS:
			_trail.remove_point(0)
	lifetime -= delta
	if lifetime <= 0:
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
		parent.take_damage(damage)
		# Impact: shove the enemy along the shot so hits feel like they land.
		if parent.has_method("apply_knockback"):
			var kb := 430.0 if proj_type == "stack_trace" else 320.0
			if parent.get("is_boss"):
				kb *= 0.25  # bosses only flinch
			parent.apply_knockback(direction * kb)
		_impact_fx()
		if not pierce:
			_retire_trail()
			queue_free()

## Sparks + a ring flash + a small screen kick, so hits read as HITS. Null-safe:
## the camera_fx rig may not exist yet (tests, or the postfx agent's work).
func _impact_fx() -> void:
	if not is_inside_tree():
		return
	var host := get_parent()
	if host:
		FxLib.burst(host, global_position, Color(_accent.r * 2.0, _accent.g * 2.0, _accent.b * 2.0), 10, 240.0, FxLib.spark())
		FxLib.flash(host, global_position, _accent, 0.3, 1.6, 0.18)
	FxLib.add_trauma(get_tree(), 0.15)
