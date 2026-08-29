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
var _sparkle: CPUParticles2D

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
	_setup_sparkle()

## Idle sparkle so tokens read as treasure from across the room. Only emits
## while the player is near (25 tokens x always-on emitters would blow the
## particle budget for nothing off-screen).
func _setup_sparkle() -> void:
	_sparkle = CPUParticles2D.new()
	_sparkle.emitting = false
	_sparkle.amount = 5
	_sparkle.lifetime = 0.9
	_sparkle.spread = 180.0
	_sparkle.gravity = Vector2(0, -30)
	_sparkle.initial_velocity_min = 4.0
	_sparkle.initial_velocity_max = 14.0
	_sparkle.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_sparkle.emission_sphere_radius = 9.0
	_sparkle.color = Color(glow.color.r * 1.9, glow.color.g * 1.8, glow.color.b * 1.5, 0.8)
	var spark := FxLib.spark()
	if spark:
		_sparkle.texture = spark
		_sparkle.material = FxLib.additive_material()
		_sparkle.scale_amount_min = 0.5
		_sparkle.scale_amount_max = 1.1
	else:
		_sparkle.scale_amount_min = 1.0
		_sparkle.scale_amount_max = 2.0
	add_child(_sparkle)

func _process(delta: float) -> void:
	if collected:
		return
	_bob_time += delta * 3.0
	_glow_hue += delta * 0.5
	position.y = _base_y + sin(_bob_time) * 6.0
	sprite.rotation = sin(_bob_time * 0.5) * 0.15
	# Coin-spin illusion: the sprite pinches on X as it "turns" to catch light.
	sprite.scale.x = 2.5 * (0.7 + 0.3 * absf(cos(_bob_time * 0.8)))
	sprite.modulate = Color(1, 1, 1, 0.85 + sin(_bob_time * 2.0) * 0.15)
	glow.energy = 0.5 + sin(_bob_time * 2.0) * 0.2
	var player := get_tree().get_first_node_in_group("player")
	if player:
		var dist := global_position.distance_to(player.global_position)
		if _sparkle:
			var want := dist < 460.0
			if _sparkle.emitting != want:
				_sparkle.emitting = want
		if dist < magnet_radius:
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
	AudioManager.play_sfx("token_collect" if token_type == "common" else "pickup_rare")
	particles.emitting = true
	if _sparkle:
		_sparkle.emitting = false
	# Pickup: scale-pop, ring flash + glow-dot burst, light flare, then a 0.15s
	# magnet flight into the (moving) player. Same total time as the old fade,
	# and the token is already counted above — visuals only from here down.
	var host := get_parent()
	if host:
		FxLib.flash(host, global_position, glow.color, 0.3, 2.1, 0.22)
		FxLib.burst(host, global_position, Color(glow.color.r * 2.0, glow.color.g * 1.9, glow.color.b * 1.6), 10, 150.0, FxLib.glow_dot(), Vector2(0, -60))
	var flare := create_tween()
	flare.tween_property(glow, "energy", 1.7, 0.07)
	flare.tween_property(glow, "energy", 0.0, 0.2)
	var tween := create_tween()
	tween.tween_property(sprite, "scale", Vector2(3.4, 3.4), 0.08).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_method(_fly_step.bind(body, global_position), 0.0, 1.0, 0.15)
	tween.tween_callback(queue_free)

## Magnet flight: chase the player, shrinking and fading on the way in.
func _fly_step(t: float, body: Node2D, from: Vector2) -> void:
	if is_instance_valid(body):
		global_position = from.lerp(body.global_position, t * t)
	sprite.scale = Vector2(3.4, 3.4).lerp(Vector2(0.9, 0.9), t)
	sprite.modulate.a = 1.0 - t * 0.7

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
