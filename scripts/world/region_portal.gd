extends Area2D

@export var target_region: String = "localhost"
@export var portal_label: String = "Portal"

@onready var label: Label = $Label

## Destination hues (VISUAL_BIBLE per-region primary accents) so every portal
## advertises where it goes before you read the label.
const REGION_HUES := {
	"localhost": Color("#FFB74A"),
	"dependency_district": Color("#A8FF3E"),
	"stackoverflow_ruins": Color("#E8C46B"),
	"api_bazaar": Color("#FF2D95"),
	"cloud_district": Color("#6BC7FF"),
	"open_source_wildlands": Color("#58E07C"),
	"corporate_enterprise": Color("#4D7CFF"),
	"gpu_mines": Color("#FF6B2D"),
	"production": Color("#FF4757"),
	"token_vault": Color("#FFD34D"),
}

func _ready() -> void:
	add_to_group("interactable")
	label.text = "→ %s" % portal_label
	body_entered.connect(_on_body_entered)
	_build_vortex()

## Swirling energy vortex (portal_swirl.gdshader) hued by destination, a soft
## PointLight2D, and motes spiralling into the mouth. Collision and interaction
## are untouched — this is purely the "that is obviously a portal" upgrade.
func _build_vortex() -> void:
	var hue: Color = REGION_HUES.get(target_region, Color("#8B5CF6"))
	var shader_path := "res://assets/shaders/portal_swirl.gdshader"
	var rect := get_node_or_null("ColorRect")
	if ResourceLoader.exists(shader_path):
		if rect:
			rect.visible = false
		var swirl := Sprite2D.new()
		swirl.texture = FxLib.white_square()
		swirl.scale = Vector2(1.9, 1.9)
		var mat := ShaderMaterial.new()
		mat.shader = load(shader_path)
		mat.set_shader_parameter("hue_color", hue)
		mat.set_shader_parameter("speed", 0.8)
		mat.set_shader_parameter("arms", 3.0)
		swirl.material = mat
		add_child(swirl)
	elif rect:
		rect.color = Color(hue.r, hue.g, hue.b, 0.5)
	FxLib.point_light(self, hue, 0.55, 1.0)
	# Ambient motes drifting inward, caught by the vortex.
	var motes := CPUParticles2D.new()
	motes.emitting = true
	motes.amount = 18
	motes.lifetime = 1.7
	motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE_SURFACE
	motes.emission_sphere_radius = 56.0
	motes.spread = 180.0
	motes.initial_velocity_min = 0.0
	motes.initial_velocity_max = 6.0
	motes.radial_accel_min = -46.0
	motes.radial_accel_max = -30.0
	motes.tangential_accel_min = 16.0
	motes.tangential_accel_max = 26.0
	motes.color = Color(hue.r * 1.25, hue.g * 1.25, hue.b * 1.25, 0.6)
	var dot := FxLib.glow_dot()
	if dot:
		motes.texture = dot
		motes.material = FxLib.additive_material()
		motes.scale_amount_min = 0.25
		motes.scale_amount_max = 0.55
	else:
		motes.scale_amount_min = 0.9
		motes.scale_amount_max = 2.0
	add_child(motes)
	# The label reads in the destination's color, with an outline for the dark.
	label.add_theme_color_override("font_color", hue.lightened(0.35))
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.06, 0.9))
	label.add_theme_constant_override("outline_size", 4)

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if not GameManager.is_region_unlocked(target_region):
		return
	GameManager.change_region(target_region)

func interact(_player: Node) -> void:
	if GameManager.is_region_unlocked(target_region):
		GameManager.change_region(target_region)

func get_prompt() -> String:
	return "Enter %s" % portal_label
