extends Area2D
class_name Projectile

var direction := Vector2.RIGHT
var damage: int = 10
var speed: float = 400.0
var lifetime: float = 2.0

@onready var sprite: ColorRect = $ColorRect

func _ready() -> void:
	add_to_group("player_projectile")
	collision_layer = 16
	collision_mask = 2
	area_entered.connect(_on_area_entered)

func setup(dir: Vector2, dmg: int, _type: String) -> void:
	direction = dir.normalized()
	damage = dmg
	rotation = direction.angle()

func _physics_process(delta: float) -> void:
	position += direction * speed * delta
	lifetime -= delta
	if lifetime <= 0:
		queue_free()

func _on_area_entered(area: Area2D) -> void:
	var parent := area.get_parent()
	if parent and parent.is_in_group("enemy") and parent.has_method("take_damage"):
		parent.take_damage(damage)
		queue_free()
