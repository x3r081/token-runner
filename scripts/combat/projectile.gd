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
	if proj_type == "stack_trace":
		# A faster, longer, magenta piercing beam.
		speed = 560.0
		lifetime = 1.4
		sprite.color = Color(1.0, 0.4, 0.95, 1)
		sprite.size = Vector2(26, 6)
		sprite.position = Vector2(-13, -3)

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
		if not pierce:
			queue_free()
