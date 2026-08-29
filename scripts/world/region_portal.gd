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

const SWIRL_SHADER := "res://assets/shaders/portal_swirl.gdshader"
const RIM_SHADER := "res://assets/shaders/portal_rim.gdshader"

## Draw order inside the portal (z_index, all relative to the Portals node at 0):
##   -4 BackBufferCopy   captures floor + gate + light pools, nothing above
##   -3 PortalLens       screen-reading refraction ring (bends what it captured)
##   -2 PortalHalo       wide, dim additive skirt — visible from across the room
##    0 PortalDisc       the vortex itself
## 1140 Label            destination plate, on top of its own artwork AND of the
##                       scenery: props y-sort themselves up to z ~1050, which
##                       is why world text at the old z 400 kept disappearing
##                       behind furniture. 1140 sits just under WorldLabel's
##                       plates (1150) so the shared label system still wins any
##                       tie it decides to arbitrate.
const Z_COPY := -4
const Z_LENS := -3
const Z_HALO := -2
const Z_LABEL := 1140

var _disc_mat: ShaderMaterial
var _light: PointLight2D
var _player: Node2D
var _base_speed := 0.8
var _seed := 0.0
var _phase := 0.0
var _heat := 1.0
var _clock := 0.0

func _ready() -> void:
	add_to_group("interactable")
	label.text = "→ %s" % portal_label
	body_entered.connect(_on_body_entered)
	_build_vortex()

## Rebuilt for round 3. The old portal was a flat coloured blob for three
## compounding reasons, all fixed here:
##
##   1. It was LIT. Its own PointLight2D (plus the builder's gate spill) added
##      itself on top of the swirl sprite, flattening every filament before
##      bloom even ran. The vortex shader is `unshaded` now and the light is
##      dimmer and wider — it exists to light the ROOM, not the portal.
##   2. The bloom skirt was small, bright and opaque, so it sat ON the disc as a
##      pastel disc of its own. It is now roughly twice as wide at half the
##      alpha: a glow you see from the far wall, not a lid.
##   3. There was nothing to look at up close. There is now a real vortex —
##      three spiral shells parallaxing down a tunnel, an accretion ring, a dark
##      event horizon — plus a screen-reading rim that drags the floor around
##      the mouth, so the portal reads as a hole in the room.
##
## Hue is normalised to full chroma first (FxLib.vivid): the bible's muted
## accents — stackoverflow gold #E8C46B, cloud sky #6BC7FF — otherwise land as
## brown/grey sludge once the dark ambient CanvasModulate has had its way.
func _build_vortex() -> void:
	var hue: Color = REGION_HUES.get(target_region, Color("#8B5CF6"))
	var vivid := FxLib.vivid(hue)
	# Stable per-destination variation, so no two portals in one room breathe in
	# unison like a rendering artifact.
	_seed = float(absi(target_region.hash()) % 997) * 0.0063
	_base_speed = 0.68 + fmod(_seed, 0.34)
	var quality := int(SettingsManager.get_setting("graphics_quality"))
	var rect := get_node_or_null("ColorRect")

	_build_lens(vivid, quality)
	_build_halo(vivid)
	if ResourceLoader.exists(SWIRL_SHADER):
		if rect:
			rect.visible = false
		_build_disc(hue)
	elif rect:
		# No shader: at least keep the destination hue readable.
		rect.color = Color(vivid.r, vivid.g, vivid.b, 0.72)
	_build_motes(vivid)
	# Room lighting only. Wide and soft at just over half the old energy, so the
	# floor around the gate glows without the disc being washed out by it.
	_light = FxLib.point_light(self, vivid, 0.58, 2.4)
	# The label reads in the destination's color, with an outline for the dark,
	# and sits above the portal's own artwork (the disc used to cover it).
	label.z_index = Z_LABEL
	label.add_theme_color_override("font_color", vivid.lightened(0.30))
	label.add_theme_color_override("font_outline_color", Color(0.01, 0.012, 0.035, 0.96))
	label.add_theme_constant_override("outline_size", 6)

## Screen-reading refraction ring. The BackBufferCopy is a RECT copy sized to
## the ring — a viewport copy per portal would be wasteful, and copying at
## z -4 means the capture holds the floor, the gate arch and the light pools but
## NOT the world labels at z 400+, so nothing textual is ever smeared.
func _build_lens(vivid: Color, quality: int) -> void:
	if quality < 1 or not ResourceLoader.exists(RIM_SHADER):
		return
	var span := 300.0
	var copy := BackBufferCopy.new()
	copy.name = "PortalLensCopy"
	copy.copy_mode = BackBufferCopy.COPY_MODE_RECT
	copy.rect = Rect2(-span * 0.5, -span * 0.5, span, span)
	copy.z_index = Z_COPY
	add_child(copy)
	var lens := Sprite2D.new()
	lens.name = "PortalLens"
	lens.texture = FxLib.white_square()
	lens.scale = Vector2(4.3, 4.3)
	lens.z_index = Z_LENS
	var mat := ShaderMaterial.new()
	mat.shader = load(RIM_SHADER)
	mat.set_shader_parameter("hue_color", vivid)
	mat.set_shader_parameter("strength", 0.019)
	mat.set_shader_parameter("swirl", 0.58)
	mat.set_shader_parameter("speed", 1.0)
	mat.set_shader_parameter("inner", 0.54)
	mat.set_shader_parameter("glow", 0.40)
	mat.set_shader_parameter("aberration", 1.0)
	# Displacement is in SCREEN_UV, which is not square; without this the swirl
	# would be visibly stretched horizontally on a 16:9 window.
	var vp := get_viewport_rect().size
	var ratio: float = vp.x / maxf(vp.y, 1.0)
	mat.set_shader_parameter("screen_aspect", Vector2(1.0, ratio))
	lens.material = mat
	add_child(lens)

## Wide, dim additive skirt: what makes the portal legible from across a dark
## region. Breathes slowly so it never reads as a static decal.
func _build_halo(vivid: Color) -> void:
	var cookie := FxLib.light_texture()
	if cookie == null:
		return
	var halo := Sprite2D.new()
	halo.name = "PortalHalo"
	halo.texture = cookie
	halo.material = FxLib.additive_material()
	halo.scale = Vector2(1.9, 1.9)
	halo.z_index = Z_HALO
	halo.light_mask = 0
	halo.modulate = Color(vivid.r * 0.34, vivid.g * 0.34, vivid.b * 0.34, 0.20)
	add_child(halo)
	var pulse := halo.create_tween().set_loops()
	pulse.tween_property(halo, "scale", Vector2(2.16, 2.16), 1.9) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(halo, "scale", Vector2(1.9, 1.9), 1.9) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## The vortex. Radius ~58px, which is what region_builder reserves for a portal
## body when it places world labels — growing it would start pushing signs off
## their landmarks.
func _build_disc(hue: Color) -> void:
	var disc := Sprite2D.new()
	disc.name = "PortalDisc"
	disc.texture = FxLib.white_square()
	disc.scale = Vector2(1.82, 1.82)
	disc.light_mask = 0
	_disc_mat = ShaderMaterial.new()
	_disc_mat.shader = load(SWIRL_SHADER)
	# Seed every uniform before anything animates one (hard rule: an unset
	# shader param reads back as null).
	_disc_mat.set_shader_parameter("hue_color", hue)
	_disc_mat.set_shader_parameter("speed", _base_speed)
	_disc_mat.set_shader_parameter("arms", 3.0)
	_disc_mat.set_shader_parameter("core_heat", 1.0)
	_disc_mat.set_shader_parameter("depth_scale", 1.0)
	_disc_mat.set_shader_parameter("horizon", 0.26)
	_disc_mat.set_shader_parameter("peak_luma", 2.30)
	_disc_mat.set_shader_parameter("phase", 0.0)
	_disc_mat.set_shader_parameter("seed", _seed * 40.0)
	disc.material = _disc_mat
	add_child(disc)
	set_process(true)

## Two emitters, inside the bible's per-region particle budget: motes falling in
## from the surrounding air, and faster sparks caught in the accretion ring.
func _build_motes(vivid: Color) -> void:
	var dot := FxLib.glow_dot()
	var add_mat := FxLib.additive_material()

	var motes := CPUParticles2D.new()
	motes.name = "PortalMotes"
	motes.emitting = true
	motes.amount = 20
	motes.lifetime = 1.9
	motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE_SURFACE
	motes.emission_sphere_radius = 108.0
	motes.spread = 180.0
	motes.initial_velocity_min = 0.0
	motes.initial_velocity_max = 6.0
	motes.radial_accel_min = -58.0
	motes.radial_accel_max = -38.0
	motes.tangential_accel_min = 30.0
	motes.tangential_accel_max = 52.0
	motes.color = Color(vivid.r * 1.35, vivid.g * 1.35, vivid.b * 1.35, 0.62)
	if dot:
		motes.texture = dot
		motes.material = add_mat
		motes.scale_amount_min = 0.22
		motes.scale_amount_max = 0.50
	else:
		motes.scale_amount_min = 0.9
		motes.scale_amount_max = 2.0
	add_child(motes)

	if dot == null:
		return
	# Ring sparks: short-lived, orbiting, right on the accretion lip.
	var sparks := CPUParticles2D.new()
	sparks.name = "PortalSparks"
	sparks.emitting = true
	sparks.amount = 14
	sparks.lifetime = 0.7
	sparks.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE_SURFACE
	sparks.emission_sphere_radius = 46.0
	sparks.initial_velocity_min = 0.0
	sparks.initial_velocity_max = 0.0
	# orbit_velocity_* is the 2D-only half of the CPUParticles API. Set through
	# set() rather than as a typed property so this file cannot fail to PARSE on
	# an engine build that spells it differently — the sparks would just drift
	# inward without orbiting, and every other suite keeps running.
	sparks.set("orbit_velocity_min", 0.55)
	sparks.set("orbit_velocity_max", 0.95)
	sparks.radial_accel_min = -20.0
	sparks.radial_accel_max = -6.0
	sparks.texture = dot
	sparks.material = add_mat
	sparks.scale_amount_min = 0.18
	sparks.scale_amount_max = 0.34
	sparks.color = Color(
		minf(vivid.r * 1.9 + 0.25, 2.4),
		minf(vivid.g * 1.9 + 0.25, 2.4),
		minf(vivid.b * 1.9 + 0.25, 2.4), 0.8)
	add_child(sparks)

## The vortex notices you: within ~340px it spins up, the core heats, and the
## room light swells. Extra rotation is ACCUMULATED into `phase` rather than
## applied by scaling `speed`, because scaling the shader's TIME term mid-run
## snaps the animation by however long the game has been open.
##
## Two uniform writes and one energy write per portal per frame; nothing is
## allocated here.
func _process(delta: float) -> void:
	if _disc_mat == null:
		set_process(false)
		return
	_clock += delta
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
	var near := 0.0
	if _player:
		var d := global_position.distance_to(_player.global_position)
		near = clampf(1.0 - (d - 70.0) / 340.0, 0.0, 1.0)
	var breathe: float = 0.5 + 0.5 * sin(_clock * 1.6 + _seed * 9.0)
	_phase += delta * (0.10 * breathe + near * 1.15)
	var heat_target: float = 0.82 + 0.14 * breathe + near * 0.66
	_heat = lerpf(_heat, heat_target, clampf(delta * 4.0, 0.0, 1.0))
	_disc_mat.set_shader_parameter("phase", _phase)
	_disc_mat.set_shader_parameter("core_heat", _heat)
	if _light:
		_light.energy = 0.50 + 0.10 * breathe + near * 0.34

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if not GameManager.is_region_unlocked(target_region):
		return
	GameManager.change_region(target_region)

func interact(_player_node: Node) -> void:
	if GameManager.is_region_unlocked(target_region):
		GameManager.change_region(target_region)

func get_prompt() -> String:
	return "Enter %s" % portal_label
