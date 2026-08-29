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
##  y+39 PortalMotes     infalling debris, one step BEHIND the mouth
##  y+40 PortalDisc      the vortex itself, y-SORTED (see _body_z)
##  y+41 PortalSparks    ring sparks, one step IN FRONT of the mouth
## 1140 Label            destination plate, on top of its own artwork AND of the
##                       scenery: props y-sort themselves up to z ~1050, which
##                       is why world text at the old z 400 kept disappearing
##                       behind furniture. 1140 sits just under WorldLabel's
##                       plates (1150) so the shared label system still wins any
##                       tie it decides to arbitrate.
const Z_COPY := -4
const Z_LENS := -3
const Z_HALO := -2
## Lift added to the portal's own y when sorting the vortex body against the
## scenery. Round 5 fix: the disc used to sit at a flat z 0 while every prop in
## the region carries a y-sorted z of int(y + half_height) — i.e. ANY prop
## out-drew it, which is how an api_bazaar monitor standing level with the gate
## came to draw straight through the vortex.
##
## 40 is measured, not guessed, against region_api_bazaar.png: the struct_console
## cluster region_builder parks on the west gate sorts at roughly portal_y - 9
## (its sprite sits ABOVE the gate's centre line), so the disc at portal_y + 40
## now clears it by ~50 and the monitor falls behind the mouth where it belongs.
## It is deliberately NOT larger: the wildlands crates below the same gate sort
## at about portal_y + 96 and must keep drawing over the disc's lower lip, or a
## prop the player can walk behind would start floating in front of the portal.
##
## On actors, the honest version: the player and the NPCs sort at int(y) — their
## CENTRE — while every prop in this game sorts at int(y + half_height), its
## BASE. A prop therefore already out-draws an actor standing level with it, all
## over the game; at +40 the portal simply behaves like a prop of its own size,
## which is the existing rule rather than a new one. The one case worth knowing:
## an actor loitering beside the gate within 40px of its centre line gets its
## leading edge drawn under the vortex, exactly as it would under a crate at that
## latitude. Walking IN is NOT that case — the 48px trigger circle plus the 12px
## player capsule fires the region change at 60px, so nobody ever stands there.
const Z_BODY_LIFT := 40
const Z_LABEL := 1140

## Where the destination plate sits, in local px, measured from the portal
## centre. BELOW the vortex on purpose. The beacon that guidance pins over a
## portal (objective_waypoint.gd) occupies the whole column ABOVE the target —
## chevron at roughly -95..-10 screen px and its "through this portal" readout
## above that — so a plate above the centre was drawn through, which is exactly
## what the QA frames show ("→ Clou[chevron]District"). That file now steps
## around this label from its side too (_portal_clearance); moving the plate out
## of the column is the same fix from the other end, and the two agree.
## Below the disc the plate is in permanently clear air. It is also off the DISC
## itself for the first time: the vortex body reaches 58px from centre, so the
## old -60..-35 box lay across the top of its own artwork (region_token_vault.png
## shows "→ Production" printed over the swirl), while 64..90 starts 6px past the
## rim. And it is still inside the 200x200 box (localhost: 208x208) that both
## world builders reserve around a portal, so no auto-placed sign can land on it.
##
## COUPLED, do not move blind: objective_waypoint._portal_clearance() reads THIS
## Label's rect — absf(get_rect().position.y) * zoom + PORTAL_LABEL_CLEAR — to
## decide how far above the portal the guidance chevron floats. Any value here
## keeps the beacon clear because the beacon lifts by |LABEL_TOP| either way, but
## a LABEL_TOP smaller than 1.0 would trip that function's own guard and drop the
## chevron back onto the vortex at the flat BEACON_LIFT of 52.
const LABEL_TOP := 64.0
const LABEL_HEIGHT := 26.0

var _disc_mat: ShaderMaterial
var _light: PointLight2D
var _player: Node2D
var _base_speed := 0.8
var _seed := 0.0
var _phase := 0.0
var _heat := 0.74
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
## Round 5 EXPOSURE PASS. Round 3 fixed the portal and then overshot: in all ten
## QA frames the gate was the brightest object on screen, a ~280px near-white
## pool that beat the region's actual focal set-piece by a full value step.
## VISUAL_BIBLE round-4 rule 3 gives the brightest slot to the focal, never to
## navigation furniture. Every additive contributor here is now cut to roughly
## half to two-thirds of its old peak — the room light hardest, since it (not
## the disc) is what painted the wide white pool — while every STRUCTURAL
## element is untouched: same 58px body, same halo footprint and breathing,
## same refraction rim, same accretion ring and event horizon. The portal still
## announces itself from across a dark region; it no longer out-shouts the boss.
## The near-approach response was kept proportionally strong (the light roughly
## doubles and the horizon nearly doubles as you close), so "this is a thing you
## walk into" survives the exposure cut intact.
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
		# No shader: at least keep the destination hue readable, and sort it the
		# same way the disc would be so the fallback is not buried under props
		# either.
		rect.color = Color(vivid.r, vivid.g, vivid.b, 0.72)
		rect.z_index = _body_z()
	_build_motes(vivid)
	# Room lighting only, and the single biggest offender in the round-4 frames:
	# a 2D PointLight2D ADDS itself to every lit sprite in reach, so at the old
	# 0.58/2.4 it was painting a ~415px pool of destination hue over the floor
	# that read as the brightest thing in the region. Now roughly half the
	# energy in a slightly tighter cone: the gate's floor still glows and still
	# says "doorway", it just no longer bids for the focal slot.
	_light = FxLib.point_light(self, vivid, 0.30, 1.95)
	# The label reads in the destination's color, with an outline for the dark,
	# and sits above the portal's own artwork (the disc used to cover it) —
	# but BELOW the portal centre, out of the guidance beacon's column. See
	# LABEL_TOP.
	label.z_index = Z_LABEL
	label.offset_top = LABEL_TOP
	label.offset_bottom = LABEL_TOP + LABEL_HEIGHT
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
	# Round 5: the lip is a LINE that says "the room bends here", not a source.
	# The displacement (strength/swirl/inner) is untouched — that is the whole
	# identity of the rim — only its emissive glow comes down.
	mat.set_shader_parameter("glow", 0.26)
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
##
## The FOOTPRINT is deliberately unchanged in round 5 (findability is the whole
## job of this node) — only its value comes down, because footprint plus value
## is what let it read as a near-white pool instead of a coloured glow.
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
	halo.modulate = Color(vivid.r * 0.26, vivid.g * 0.26, vivid.b * 0.26, 0.12)
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
	disc.z_index = _body_z()
	_disc_mat = ShaderMaterial.new()
	_disc_mat.shader = load(SWIRL_SHADER)
	# Seed every uniform before anything animates one (hard rule: an unset
	# shader param reads back as null).
	_disc_mat.set_shader_parameter("hue_color", hue)
	_disc_mat.set_shader_parameter("speed", _base_speed)
	_disc_mat.set_shader_parameter("arms", 3.0)
	_disc_mat.set_shader_parameter("core_heat", _heat)
	_disc_mat.set_shader_parameter("depth_scale", 1.0)
	_disc_mat.set_shader_parameter("horizon", 0.26)
	# soft_clip's asymptote. Lower peak = the exponential ceiling bites sooner,
	# which compresses the hot terms toward the destination hue instead of
	# letting them stack toward white. Still above 1.0, so the HDR pass keeps
	# finding the accretion ring — the portal glows, it just stops being a lamp.
	_disc_mat.set_shader_parameter("peak_luma", 1.85)
	_disc_mat.set_shader_parameter("phase", 0.0)
	_disc_mat.set_shader_parameter("seed", _seed * 40.0)
	disc.material = _disc_mat
	add_child(disc)
	set_process(true)

## Sort key for the vortex body against the y-sorted scenery. See Z_BODY_LIFT.
## Read from global_position, which both world builders set BEFORE add_child(),
## so it is already correct by the time _ready() runs.
func _body_z() -> int:
	return int(global_position.y) + Z_BODY_LIFT

## Two emitters, inside the bible's per-region particle budget: motes falling in
## from the surrounding air, and faster sparks caught in the accretion ring.
func _build_motes(vivid: Color) -> void:
	var dot := FxLib.glow_dot()
	var add_mat := FxLib.additive_material()

	var body_z := _body_z()

	var motes := CPUParticles2D.new()
	motes.name = "PortalMotes"
	# One z below the disc: infalling debris passes BEHIND the mouth, and the
	# whole vortex still sorts against the scenery as one object rather than the
	# emitters being left down at z 0 for every prop to draw over.
	motes.z_index = body_z - 1
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
	motes.color = Color(vivid.r * 1.02, vivid.g * 1.02, vivid.b * 1.02, 0.44)
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
	sparks.z_index = body_z + 1
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
	# Still overbright (they are the sparkle that says "alive"), but no longer
	# far enough past 1.0 to drive the bloom pass on their own.
	sparks.color = Color(
		minf(vivid.r * 1.2 + 0.10, 1.45),
		minf(vivid.g * 1.2 + 0.10, 1.45),
		minf(vivid.b * 1.2 + 0.10, 1.45), 0.58)
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
	# Round 5 exposure: idle sits well down (0.60–0.72 where it used to idle at
	# 0.82–0.96), but the near-approach term is nearly untouched, so closing on
	# a portal still roughly DOUBLES the horizon burn. The gesture that says
	# "this is interactive" is the change, not the absolute level.
	var heat_target: float = 0.60 + 0.12 * breathe + near * 0.60
	_heat = lerpf(_heat, heat_target, clampf(delta * 4.0, 0.0, 1.0))
	_disc_mat.set_shader_parameter("phase", _phase)
	_disc_mat.set_shader_parameter("core_heat", _heat)
	if _light:
		_light.energy = 0.26 + 0.06 * breathe + near * 0.28

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
