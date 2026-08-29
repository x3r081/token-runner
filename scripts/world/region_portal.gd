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

## Swirling energy vortex (portal_swirl.gdshader) hued by destination, an outer
## bloom halo, a soft PointLight2D, and motes spiralling into the mouth.
## Collision and interaction are untouched — this is purely the "that is
## obviously a portal, and obviously THAT colour" upgrade.
##
## Every hue is pushed to full chroma first (FxLib.vivid): the bible's muted
## accents — stackoverflow gold #E8C46B, cloud sky #6BC7FF — otherwise land as
## brown/grey sludge once the dark ambient CanvasModulate has had its way.
func _build_vortex() -> void:
	var hue: Color = REGION_HUES.get(target_region, Color("#8B5CF6"))
	var vivid := FxLib.vivid(hue)
	var shader_path := "res://assets/shaders/portal_swirl.gdshader"
	var rect := get_node_or_null("ColorRect")
	# Outer bloom skirt: an additive hue wash behind the disc, breathing slowly.
	# It is what makes the portal visible from the far side of a dark region.
	var cookie := FxLib.light_texture()
	if cookie:
		var halo := Sprite2D.new()
		halo.name = "PortalHalo"
		halo.texture = cookie
		halo.material = FxLib.additive_material()
		halo.scale = Vector2(1.25, 1.25)
		halo.z_index = -1
		halo.modulate = Color(vivid.r * 0.75, vivid.g * 0.75, vivid.b * 0.75, 0.55)
		add_child(halo)
		var pulse := halo.create_tween().set_loops()
		pulse.tween_property(halo, "scale", Vector2(1.42, 1.42), 1.6) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		pulse.tween_property(halo, "scale", Vector2(1.25, 1.25), 1.6) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
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
		mat.set_shader_parameter("core_heat", 1.0)
		swirl.material = mat
		add_child(swirl)
	elif rect:
		rect.color = Color(vivid.r, vivid.g, vivid.b, 0.72)
	FxLib.point_light(self, vivid, 1.0, 1.7)
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
	motes.color = Color(vivid.r * 1.45, vivid.g * 1.45, vivid.b * 1.45, 0.7)
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
	label.add_theme_color_override("font_color", vivid.lightened(0.30))
	label.add_theme_color_override("font_outline_color", Color(0.01, 0.012, 0.035, 0.96))
	label.add_theme_constant_override("outline_size", 6)

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
