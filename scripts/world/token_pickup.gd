extends Area2D
class_name TokenPickup

@export var token_type: String = "common"
@export var amount: int = 5
@export var magnet_radius: float = 100.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var particles: CPUParticles2D = $Particles
@onready var glow: PointLight2D = $Glow

## VISUAL_BIBLE_V2 LAW 2: GOLD is reserved for tokens and currency, and nothing
## else in the game is allowed to use it. Round 5 gave four token types four
## different hues — cyan, teal, blue, amber — which is four of the eight hues
## the QA frames were carrying. One colour means "this is money", full stop.
const GOLD := Color("#FFD34D")
## Compute is the one pickup that is NOT money, so it keeps a second, cool
## colour — deliberately a desaturated glass grey-blue (LAW 2's corporate
## #93A7C8 family), not another neon.
const COMPUTE := Color("#9FB4D0")
## LAW 1: art is 32px, drawn at 2x. Exactly 2.0, and it never animates — the
## coin-spin X pinch that used to run here put the token on a different pixel
## grid from the floor it was sitting on, every frame.
const ART_SCALE := Vector2(2.0, 2.0)
## LAW 9: tokens bob 2px. Rounded, so the token lands on whole pixels.
const BOB_PX := 2.0

var collected := false
var _bob_time := 0.0
var _base_y: float

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
	sprite.scale = ART_SCALE
	body_entered.connect(_on_body_entered)
	match token_type:
		"premium", "golden", "frontier":
			amount = randi_range(amount, amount * 3)
		"compute":
			amount = randi_range(3, 8)
	glow.color = COMPUTE if token_type == "compute" else GOLD
	# LAW 9: nothing moves at rest except the 2px bob. A steady pool, sized to
	# the coin — a token is one of the five things LAW 3 lets be bright, and
	# being bright is enough; it does not also have to pulse.
	#
	# 0.30, not 0.40: LAW 4 budgets a region SIX lights and a region carries 6-10
	# tokens, so the token pool has to sit under the lamps rather than alongside
	# them. The gold is legible from the sprite; the light is only there so the
	# coin sits on a floor instead of floating over one.
	glow.energy = 0.30
	glow.texture = _make_glow_texture()

## The whole idle animation: a 2px bob, on whole pixels. Round 5 also spun the
## sprite (rotation breaks the pixel grid — LAW 1), pinched its X scale to fake
## a coin spin (same), breathed its alpha, breathed the light, and ran a
## five-particle sparkle emitter on every token within 460px. With 25 tokens per
## region that was 25 emitters and 25 pulsing lights in one room; LAW 4 cuts the
## map to 6-10 tokens and this file stops paying for the ones that remain.
func _process(delta: float) -> void:
	if collected:
		return
	_bob_time += delta * 2.4
	position.y = _base_y + roundf(sin(_bob_time) * BOB_PX)
	var player := get_tree().get_first_node_in_group("player")
	if player:
		if global_position.distance_to(player.global_position) < magnet_radius:
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
	# Pickup: scale-pop, one ring flash, light flare, then a 0.15s magnet flight
	# into the (moving) player. The token is already counted above — visuals
	# only from here down, and a transient VFX tween is allowed to scale freely
	# (LAW 1 binds STATIC art to the grid, not a 0.2s pop). The glow-dot burst
	# is gone: a flash and a flare already say "collected" twice.
	var host := get_parent()
	if host:
		FxLib.flash(host, global_position, glow.color, 0.3, 1.7, 0.20)
	var flare := create_tween()
	flare.tween_property(glow, "energy", 1.1, 0.07)
	flare.tween_property(glow, "energy", 0.0, 0.2)
	var tween := create_tween()
	tween.tween_property(sprite, "scale", Vector2(2.6, 2.6), 0.08).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_method(_fly_step.bind(body, global_position), 0.0, 1.0, 0.15)
	tween.tween_callback(queue_free)

## Magnet flight: chase the player, shrinking and fading on the way in.
func _fly_step(t: float, body: Node2D, from: Vector2) -> void:
	if is_instance_valid(body):
		global_position = from.lerp(body.global_position, t * t)
	sprite.scale = Vector2(2.6, 2.6).lerp(Vector2(0.9, 0.9), t)
	sprite.modulate.a = 1.0 - t * 0.7

func _spawn_float_text() -> void:
	var label := Label.new()
	label.text = "+%d" % amount
	label.add_theme_font_size_override("font_size", 18)
	label.modulate = glow.color
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
