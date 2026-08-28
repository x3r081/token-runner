extends Area2D
class_name TokenPickup

@export var token_type: String = "common"
@export var amount: int = 5
@export var magnet_radius: float = 100.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var particles: CPUParticles2D = $Particles
@onready var glow: PointLight2D = $Glow

var collected := false
var _bob_time := 0.0
var _base_y: float
var _glow_hue := 0.0

func _ready() -> void:
	add_to_group("token")
	_base_y = position.y
	collision_layer = 4
	collision_mask = 1
	var tex_path := "res://assets/textures/generated/token_%s.png" % token_type
	if ResourceLoader.exists(tex_path):
		sprite.texture = load(tex_path)
	else:
		sprite.texture = load("res://assets/textures/generated/token_common.png")
	sprite.scale = Vector2(2.5, 2.5)
	body_entered.connect(_on_body_entered)
	match token_type:
		"premium", "golden", "frontier":
			amount = randi_range(amount, amount * 3)
			glow.color = Color(1.0, 0.85, 0.3)
		"compute":
			amount = randi_range(3, 8)
			glow.color = Color(0.4, 0.7, 1.0)
		"cached":
			glow.color = Color(0.5, 0.95, 0.85)
		_:
			glow.color = Color(0.35, 0.9, 0.8)
	glow.texture = _make_glow_texture()

func _process(delta: float) -> void:
	if collected:
		return
	_bob_time += delta * 3.0
	_glow_hue += delta * 0.5
	position.y = _base_y + sin(_bob_time) * 6.0
	sprite.rotation = sin(_bob_time * 0.5) * 0.15
	sprite.modulate = Color(1, 1, 1, 0.85 + sin(_bob_time * 2.0) * 0.15)
	glow.energy = 0.5 + sin(_bob_time * 2.0) * 0.2
	var player := get_tree().get_first_node_in_group("player")
	if player and global_position.distance_to(player.global_position) < magnet_radius:
		global_position = global_position.move_toward(player.global_position, 280 * delta)

func _on_body_entered(body: Node2D) -> void:
	if collected:
		return
	if not body.is_in_group("player"):
		return
	collected = true
	if token_type == "compute":
		ResourceManager.modify("compute", amount)
	else:
		ResourceManager.add_tokens(amount, "pickup_%s" % token_type)
	QuestManager.on_token_collected(amount)
	_spawn_float_text()
	AudioManager.play_sfx("token_collect")
	particles.emitting = true
	var tween := create_tween()
	tween.tween_property(sprite, "scale", Vector2(1.5, 1.5), 0.1)
	tween.tween_property(sprite, "modulate:a", 0.0, 0.2)
	tween.tween_callback(queue_free)

func _spawn_float_text() -> void:
	var label := Label.new()
	label.text = "+%d" % amount
	label.add_theme_font_size_override("font_size", 18)
	label.modulate = Color(0.3, 0.95, 0.85)
	label.z_index = 100
	get_tree().current_scene.add_child(label)
	label.global_position = global_position + Vector2(-10, -20)
	var tween := label.create_tween()
	tween.tween_property(label, "global_position:y", label.global_position.y - 40, 0.6)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(label.queue_free)

func _make_glow_texture() -> Texture2D:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for x in 32:
		for y in 32:
			var d := Vector2(x - 16, y - 16).length() / 16.0
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)
