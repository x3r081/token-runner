extends Area2D
class_name Projectile

var direction := Vector2.RIGHT
var damage: int = 10
var speed: float = 400.0
var lifetime: float = 2.0
var pierce := false
var proj_type := "prompt_blast"
var _hit: Array = []

@onready var sprite: ColorRect = $ColorRect

func _ready() -> void:
	add_to_group("player_projectile")
	collision_layer = 16
	collision_mask = 2
	area_entered.connect(_on_area_entered)
	# Bigger, brighter core so it reads clearly against the busy world.
	sprite.color = Color(0.4, 1.0, 0.9, 1.0)
	sprite.size = Vector2(22, 9)
	sprite.position = Vector2(-11, -4.5)
	if proj_type == "stack_trace":
		# A faster, longer, magenta piercing beam.
		speed = 560.0
		lifetime = 1.4
		sprite.color = Color(1.0, 0.45, 0.98, 1)
		sprite.size = Vector2(30, 9)
		sprite.position = Vector2(-15, -4.5)
	_add_glow_and_trail()

func _add_glow_and_trail() -> void:
	# Soft glow halo.
	var glow := ColorRect.new()
	glow.size = sprite.size * 2.0
	glow.position = -glow.size * 0.5
	glow.color = Color(sprite.color.r, sprite.color.g, sprite.color.b, 0.28)
	glow.z_index = -1
	add_child(glow)
	# Fading particle trail.
	var trail := CPUParticles2D.new()
	trail.local_coords = false
	trail.emitting = true
	trail.amount = 16
	trail.lifetime = 0.35
	trail.explosiveness = 0.0
	trail.direction = Vector2.ZERO
	trail.spread = 0.0
	trail.initial_velocity_min = 0.0
	trail.initial_velocity_max = 0.0
	trail.scale_amount_min = 2.0
	trail.scale_amount_max = 4.0
	trail.color = Color(sprite.color.r, sprite.color.g, sprite.color.b, 0.5)
	trail.z_index = -1
	add_child(trail)

func setup(dir: Vector2, dmg: int, type: String) -> void:
	direction = dir.normalized()
	damage = dmg
	proj_type = type
	rotation = direction.angle()

func _physics_process(delta: float) -> void:
	position += direction * speed * delta
	lifetime -= delta
	if lifetime <= 0:
		queue_free()

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
		if not pierce:
			queue_free()
