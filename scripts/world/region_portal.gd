extends Area2D

@export var target_region: String = "localhost"
@export var portal_label: String = "Portal"

@onready var label: Label = $Label

## Destination hues — VISUAL_BIBLE_V2 LAW 2's ACCENT column, verbatim — so every
## portal advertises where it goes before you read the label. (localhost is
## #24F0DC here now, matching world.gd: amber is that region's WARM, not its
## accent.)
const REGION_HUES := {
	"localhost": Color("#24F0DC"),
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

## VISUAL_BIBLE_V2 LAW 4: a portal is 48px of art drawn at 2x — 96 world units
## across, a doorway a person could walk through — with a soft swirl, one light
## at energy 0.5, and no halo. It should be FINDABLE, not dominant.
##
## Round 5's gate was, in all ten QA frames, the brightest and the largest
## object on screen: a 116-unit disc with a white-hot horizon, a 122-unit
## breathing additive halo over it, a 275-unit screen-reading refraction lens
## around that, 20 infalling motes and 14 orbiting ring sparks. Removed this
## round, all of it except the disc and a thinned mote stream:
##
##   PortalLens + its BackBufferCopy   a per-portal screen capture whose only
##       job was to bend the floor. "No refraction" is a LAW 4 instruction and
##       this was also the single most expensive node in the region.
##       portal_rim.gdshader is gone from the repo — nothing else loaded it.
##   PortalHalo   a wide additive skirt that breathed on a 3.8s loop. A glow
##       with no source, moving at rest (LAW 9), and the thing that painted the
##       near-white pool the QA frames actually show.
##   PortalSparks   sparkle. LAW 9 again.
##
## Draw order inside the portal (z_index, all relative to the Portals node at 0):
##  y+29 PortalMotes     infalling debris, one step BEHIND the mouth
##  y+30 PortalDisc      the swirl itself, y-SORTED (see _body_z)
## 1140 Label            destination text, on top of its own artwork AND of the
##                       scenery: props y-sort themselves up to z ~1050, which
##                       is why world text at the old z 400 kept disappearing
##                       behind furniture. 1140 sits just under WorldLabel's
##                       plates (1150) so the shared label system still wins any
##                       tie it decides to arbitrate.
##
## Lift added to the portal's own y when sorting the body against the scenery.
## Every prop in the region carries a y-sorted z of int(y + half_height), i.e. a
## portal left at a flat z 0 is out-drawn by ALL of them — which is how an
## api_bazaar monitor standing level with the gate came to draw straight through
## the vortex. The lift makes the portal behave like a prop of its own size,
## which is the existing rule rather than a new one, and it tracks the body:
## round 5 used 40 against a 58px radius, so a 48px radius takes 30. Props below
## the gate (the wildlands crates sort at about portal_y + 96) still draw over
## its lower lip, which is what lets the player walk behind them.
const Z_BODY_LIFT := 30
const Z_LABEL := 1140

## Where the destination text sits, in local px, measured from the portal
## centre. BELOW the swirl on purpose. The beacon that guidance pins over a
## portal (objective_waypoint.gd) occupies the whole column ABOVE the target —
## chevron at roughly -95..-10 screen px and its "through this portal" readout
## above that — so a plate above the centre was drawn through, which is exactly
## what the QA frames show ("→ Clou[chevron]District"). That file now steps
## around this label from its side too (_portal_clearance); moving the plate out
## of the column is the same fix from the other end, and the two agree.
## Below the disc the text is in permanently clear air. It is also off the DISC
## itself: the body now reaches 48px from centre, so 64..90 starts 16px past the
## rim (the old -60..-35 box lay across the top of its own artwork —
## region_token_vault.png shows "→ Production" printed over the swirl). And it is still inside the 200x200 box (localhost: 208x208) that both
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
var _base_speed := 0.4
var _seed := 0.0
var _phase := 0.0
var _heat := 0.62
var _clock := 0.0

func _ready() -> void:
	add_to_group("interactable")
	label.text = "→ %s" % portal_label
	body_entered.connect(_on_body_entered)
	_build_vortex()

## The portal, whole. Hue is normalised to full chroma first (FxLib.vivid):
## the bible's muted accents — stackoverflow gold #E8C46B, cloud sky #6BC7FF —
## otherwise land as brown/grey sludge once the dark ambient CanvasModulate has
## had its way.
##
## What a portal is, after round 6: a 96-unit swirl in the destination accent, a
## thin inward mote stream, one PointLight2D at energy 0.5, and a line of text
## under it. Four nodes. See the LAW 4 note above for the six that are gone.
func _build_vortex() -> void:
	var hue: Color = REGION_HUES.get(target_region, Color("#8B5CF6"))
	var vivid := FxLib.vivid(hue)
	# Stable per-destination variation, so no two portals in one room breathe in
	# unison like a rendering artifact.
	_seed = float(absi(target_region.hash()) % 997) * 0.0063
	# LAW 9: motion is small. The swirl turns at roughly half round 5's rate —
	# slow enough that a still frame and a moving one look the same.
	_base_speed = 0.34 + fmod(_seed, 0.16)
	var rect := get_node_or_null("ColorRect")

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
	# Room lighting only, and LAW 4 names the number: energy 0.5. A 2D
	# PointLight2D ADDS itself to every lit sprite in reach, so this is what
	# actually says "doorway" from across a dark room — the gate's floor glows,
	# the artwork does not have to shout. texture_scale 1.6 keeps the pool
	# roughly two body-widths across instead of the old ~415px wash.
	_light = FxLib.point_light(self, vivid, 0.5, 1.6)
	# The label reads in the destination's colour and sits above the portal's own
	# artwork — but BELOW the portal centre, out of the guidance beacon's column
	# (see LABEL_TOP). LAW 4's label style: plain text, one 1px drop shadow, no
	# plate and no 6px outline halo, which at 14px type was a smudge.
	label.z_index = Z_LABEL
	label.offset_top = LABEL_TOP
	label.offset_bottom = LABEL_TOP + LABEL_HEIGHT
	label.add_theme_color_override("font_color", vivid)
	label.add_theme_constant_override("outline_size", 0)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)

## The swirl. LAW 4's 48px of art at 2x: a 64px white square at scale 1.5 is
## 96 world units across, i.e. a 48-unit radius. region_builder reserves 58 for
## a portal body when it places world labels, so this fits inside what the
## builders already expect and no sign has to move.
func _build_disc(hue: Color) -> void:
	var disc := Sprite2D.new()
	disc.name = "PortalDisc"
	disc.texture = FxLib.white_square()
	disc.scale = Vector2(1.5, 1.5)
	disc.light_mask = 0
	disc.z_index = _body_z()
	_disc_mat = ShaderMaterial.new()
	_disc_mat.shader = load(SWIRL_SHADER)
	# Seed every uniform before anything animates one (hard rule: an unset
	# shader param reads back as null).
	_disc_mat.set_shader_parameter("hue_color", hue)
	_disc_mat.set_shader_parameter("speed", _base_speed)
	# Two arms, not three: fewer, wider, slower bands read as a swirl at a
	# glance instead of as a texture you have to stop and resolve.
	_disc_mat.set_shader_parameter("arms", 2.0)
	_disc_mat.set_shader_parameter("core_heat", _heat)
	_disc_mat.set_shader_parameter("depth_scale", 1.0)
	_disc_mat.set_shader_parameter("horizon", 0.26)
	# The hue-preserving ceiling. 1.05 is a hair over the engine's HDR glow
	# threshold of 1.0, so the brightest filament picks up a whisper of bloom
	# and nothing else in the portal reaches the threshold at all. Round 5 ran
	# this at 1.85 and let a white-hot horizon lip stack on top of it.
	_disc_mat.set_shader_parameter("peak_luma", 1.05)
	_disc_mat.set_shader_parameter("phase", 0.0)
	_disc_mat.set_shader_parameter("seed", _seed * 40.0)
	disc.material = _disc_mat
	add_child(disc)
	set_process(true)

## Sort key for the swirl body against the y-sorted scenery. See Z_BODY_LIFT.
## Read from global_position, which both world builders set BEFORE add_child(),
## so it is already correct by the time _ready() runs.
func _body_z() -> int:
	return int(global_position.y) + Z_BODY_LIFT

## ONE emitter: the inward mote stream. LAW 4 gives a region two emitters total
## and this is the portal's share; the ring sparks that used to orbit the
## accretion lip are gone, because sparkle at rest is exactly what LAW 9 rules
## out. Twelve particles at 40% alpha and NOT overbright — the stream says
## "something is being pulled in here", it does not contribute to the bloom.
func _build_motes(vivid: Color) -> void:
	var dot := FxLib.glow_dot()
	var motes := CPUParticles2D.new()
	motes.name = "PortalMotes"
	# One z below the disc: infalling debris passes BEHIND the mouth, and the
	# whole portal still sorts against the scenery as one object rather than the
	# emitter being left down at z 0 for every prop to draw over.
	motes.z_index = _body_z() - 1
	motes.emitting = true
	motes.amount = 12
	motes.lifetime = 2.2
	motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE_SURFACE
	# Tracks the smaller body: the stream starts just under a body-width out
	# rather than at the old 108, so it never reads as a second, wider halo.
	motes.emission_sphere_radius = 74.0
	motes.spread = 180.0
	motes.initial_velocity_min = 0.0
	motes.initial_velocity_max = 4.0
	motes.radial_accel_min = -42.0
	motes.radial_accel_max = -28.0
	motes.tangential_accel_min = 18.0
	motes.tangential_accel_max = 32.0
	motes.color = Color(vivid.r, vivid.g, vivid.b, 0.40)
	if dot:
		motes.texture = dot
		motes.material = FxLib.additive_material()
		motes.scale_amount_min = 0.18
		motes.scale_amount_max = 0.36
	else:
		motes.scale_amount_min = 0.8
		motes.scale_amount_max = 1.6
	add_child(motes)

## The portal notices you: within ~340px it turns a little faster, lifts a
## little, and its floor pool swells by 40%. Extra rotation is ACCUMULATED into `phase` rather than
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
	# LAW 9: the idle portal is nearly still. The old breathe term drove phase,
	# heat and the light on a 3.9s cycle whether or not anyone was near it; it
	# survives only as a +/- 6% wobble on the light, which is the flicker
	# allowance and nothing more.
	var breathe: float = 0.5 + 0.5 * sin(_clock * 1.2 + _seed * 9.0)
	_phase += delta * (0.06 + near * 0.55)
	# The near-approach response is what says "this is a thing you walk into",
	# and it is deliberately the only thing here that changes: the swirl lifts
	# by about a fifth as you close. There is no hot core to burn any more, so
	# `core_heat` now scales the whole body rather than a horizon lip.
	var heat_target: float = 0.62 + near * 0.50
	_heat = lerpf(_heat, heat_target, clampf(delta * 4.0, 0.0, 1.0))
	_disc_mat.set_shader_parameter("phase", _phase)
	_disc_mat.set_shader_parameter("core_heat", _heat)
	if _light:
		_light.energy = 0.5 * (0.94 + 0.06 * breathe) + near * 0.20

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
