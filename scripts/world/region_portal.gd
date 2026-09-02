extends Area2D

@export var target_region: String = "localhost"
@export var portal_label: String = "Portal"

@onready var label: Label = $Label

## VISUAL_BIBLE_V2 LAW 2's ACCENT column, verbatim, keyed by REGION ID.
##
## ROUND 7 — THE PORTAL TAKES THE ROOM'S COLOUR, NOT THE DESTINATION'S.
##
## Round 6 hued every portal by where it GOES: a cyan swirl, cyan halo and cyan
## label standing in acid-green Dependency District; a red one in gold Token
## Vault; a magenta one in blue Cloud District. LAW 2 allows a scene exactly
## three hues (BASE / ACCENT / WARM) and this spent a fourth in every single
## room — the one saturated object the eye lands on first, painted in a colour
## that belongs to somewhere else.
##
## So the hue is looked up from `GameManager.current_region` at build time. The
## destination is still advertised, in the only place it costs nothing: the
## line of text under the mouth.
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
## Everything that made the round-5 gate the brightest object in ten QA frames
## is gone (the refraction lens, the breathing additive halo, the ring sparks,
## the white-hot horizon). Round 7 removes the last of it:
##
##   PortalMotes   twelve additive dots orbiting the mouth on a 74px emission
##       sphere. LAW 4 gives a REGION two particle emitters — one ambient dust
##       layer and one at the set-piece — and the portal was quietly spending a
##       third. LAW 9 rules out sparkle at rest on its own.
##
## What is left is four things: a swirl, a light, a label, and a trigger.
##
## Draw order inside the portal (z_index, all relative to the Portals node at 0):
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

## The swirl's radius in world units — a 64px texture at scale 1.5, halved.
## READ FROM THE LIVE NODE by objective_waypoint._portal_radius(), which floats
## its beacon clear of the mouth; this constant is only that file's fallback and
## the number `_build_disc` is built to.
const BODY_RADIUS := 48.0

## Where the destination text sits, in local px, measured from the portal
## centre. BELOW the swirl on purpose, and never over it: the body reaches
## BODY_RADIUS from centre, so 64..90 starts 16px past the rim. (The old
## -60..-35 box lay across the top of its own artwork — region_token_vault.png
## shows "→ Production" printed over the swirl.) It is also outside the column
## ABOVE the portal, which belongs to the guidance beacon
## (objective_waypoint.gd), and still inside the 200x200 box (localhost:
## 208x208) that both world builders reserve around a portal, so no auto-placed
## sign can land on it either.
const LABEL_TOP := 64.0
const LABEL_HEIGHT := 26.0

## Half the widest the destination line is allowed to be, in world units.
##
## ROUND 9 — THE LABEL NO LONGER RUNS OFF THE WORLD (critique #9, "→ Depen").
## The scene's Label is a 160-unit box with `horizontal_alignment = CENTER` and
## no wrapping, and an unwrapped Label does not clip: "→ Open Source Wildlands"
## at SMALL simply draws past both edges of its own box, reaching roughly ±105
## units. A portal within ~110 units of a wall then printed its own name into
## the wall — or, with the camera clamped at that wall, off the frame entirely.
## AUTOWRAP_WORD_SMART inside this half-width turns the long destinations into
## two short lines instead, and `_clamp_label()` then shifts the whole box so it
## cannot cross the room bounds either. LABEL_TOP and LABEL_HEIGHT are NOT
## touched by any of this: objective_waypoint._portal_clearance() measures its
## beacon off this Label's top edge.
const LABEL_HALF_W := 80.0
## Two wrapped lines plus the shadow row. A one-line destination still occupies
## only its own line — Label draws top-aligned inside the box.
const LABEL_MAX_H := 52.0

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

## The hue this portal is drawn in: the ACCENT of the room it STANDS IN (LAW 2),
## read once at build time. `GameManager.current_region` is already the region
## being populated by the time a portal enters the tree — region_builder sets
## `position` and calls `add_child` well after `change_region`.
func _room_accent() -> Color:
	var c: Color = REGION_HUES.get(GameManager.current_region, Color("#24F0DC"))
	return c

## The portal, whole. Hue is normalised to full chroma for the LIGHT only
## (FxLib.vivid): the bible's muted accents — stackoverflow gold #E8C46B, cloud
## sky #6BC7FF — otherwise land as brown/grey sludge once the dark ambient
## CanvasModulate has had its way. The swirl does its own normalisation inside
## the shader.
##
## What a portal is, after round 7: a 96-unit swirl in the ROOM's accent, one
## PointLight2D at energy 0.5 pooling on the floor, and a line of dim text under
## it. Three nodes.
func _build_vortex() -> void:
	var accent := _room_accent()
	var vivid := FxLib.vivid(accent)
	# Stable per-DESTINATION variation, so the two portals in one room no longer
	# differ by hue but still do not breathe in unison like a rendering artifact.
	_seed = float(absi(target_region.hash()) % 997) * 0.0063
	# LAW 9: motion is small. The swirl turns at roughly half round 5's rate —
	# slow enough that a still frame and a moving one look the same.
	_base_speed = 0.34 + fmod(_seed, 0.16)
	var rect := get_node_or_null("ColorRect")

	if ResourceLoader.exists(SWIRL_SHADER):
		if rect:
			rect.visible = false
		_build_disc(accent)
	elif rect:
		# No shader: at least keep the room's hue readable, and sort it the same
		# way the disc would be so the fallback is not buried under props either.
		rect.color = Color(vivid.r, vivid.g, vivid.b, 0.72)
		rect.z_index = _body_z()
	# Room lighting only, and LAW 4 names the number: energy 0.5. A 2D
	# PointLight2D ADDS itself to every lit sprite in reach, so this is what
	# actually says "doorway" from across a dark room — the gate's floor POOLS
	# (LAW 4), the artwork does not have to shout. texture_scale 1.6 keeps that
	# pool roughly two body-widths across instead of the old ~415px wash.
	_light = FxLib.point_light(self, vivid, 0.5, 1.6)
	_dress_label()

## The destination, named once, quietly. LAW 4's label style exactly: plain
## aliased text (LAW 1 — the scene's default font is smooth and 14px), SMALL,
## TEXT_DIM, one 1px drop shadow, no plate, no outline halo, and BELOW the art.
##
## TEXT_DIM and not the accent on purpose: the SWIRL is the wayfinding signal
## and it is already the room's one neon. A second accent-coloured object 16px
## under it would just be the same shout twice.
func _dress_label() -> void:
	label.z_index = Z_LABEL
	label.offset_top = LABEL_TOP
	label.offset_bottom = LABEL_TOP + LABEL_MAX_H
	label.offset_left = -LABEL_HALF_W
	label.offset_right = LABEL_HALF_W
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", GameTheme.ui_font())
	label.add_theme_font_size_override("font_size", GameTheme.SMALL)
	label.add_theme_color_override("font_color", GameTheme.TEXT_DIM)
	label.add_theme_constant_override("outline_size", 0)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_constant_override("shadow_outline_size", 0)
	_clamp_label()

## Slide the destination box sideways until it is entirely inside the room.
##
## The box is centred on the portal, so a doorway cut close to a side wall would
## otherwise print half its name into the masonry. WorldLabel.bounds() is the
## room rect the builder declared for THIS region (WorldLabel.begin() runs at
## the top of every build, well before any portal is added), and EDGE_KEEP is
## the same 24-unit margin every auto-placed caption already respects — so the
## portal's own text now obeys the rule the rest of the world's text does.
func _clamp_label() -> void:
	var room := WorldLabel.bounds()
	if room.size.x <= LABEL_HALF_W * 2.0:
		return
	var keep := WorldLabel.EDGE_KEEP
	var centre := global_position.x
	var lo := room.position.x + keep + LABEL_HALF_W
	var hi := room.position.x + room.size.x - keep - LABEL_HALF_W
	var want := clampf(centre, lo, maxf(lo, hi))
	var dx := want - centre
	label.offset_left = -LABEL_HALF_W + dx
	label.offset_right = LABEL_HALF_W + dx

## The swirl. LAW 4's 48px of art at 2x: a 64px white square at scale 1.5 is
## 96 world units across, i.e. a BODY_RADIUS of 48. region_builder reserves 58
## for a portal body when it places world labels, so this fits inside what the
## builders already expect and no sign has to move.
##
## The texture is SQUARE and the scale is UNIFORM, which is not decoration: the
## shader builds its disc out of `length(UV - 0.5)`, so a non-square quad would
## print an ellipse and a non-uniform scale would shear the cell grid off LAW
## 1's pixel lattice.
func _build_disc(accent: Color) -> void:
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
	_disc_mat.set_shader_parameter("hue_color", accent)
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

## The portal notices you: within ~340px it turns a little faster, lifts a
## little, and its floor pool swells. Extra rotation is ACCUMULATED into `phase`
## rather than applied by scaling `speed`, because scaling the shader's TIME
## term mid-run snaps the animation by however long the game has been open.
##
## Two uniform writes and one energy write per portal per frame; nothing is
## allocated here.
func _process(delta: float) -> void:
	if _disc_mat == null:
		set_process(false)
		return
	_clock += delta
	_update_label_visibility()
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
	# by a couple of percent as you close. There is no hot core to burn any
	# more, so `core_heat` scales the whole body rather than a horizon lip, and
	# the shader caps what it can do at a 1.02 multiplier.
	var heat_target: float = 0.62 + near * 0.50
	_heat = lerpf(_heat, heat_target, clampf(delta * 4.0, 0.0, 1.0))
	_disc_mat.set_shader_parameter("phase", _phase)
	_disc_mat.set_shader_parameter("core_heat", _heat)
	if _light:
		_light.energy = 0.5 * (0.94 + 0.06 * breathe) + near * 0.20

## A CAPTION FOR A BODY THE PLAYER CANNOT SEE.
##
## ROUND 12, critique #6 — "three stacked navigation cues in the top-right of
## token_vault". Two of them were the waypoint's, and the waypoint agent fixed
## those. The third is THIS label: the vault's return portal stands above the
## arrival camera's top edge, so the swirl is a sliver behind the region title
## and the only legible thing left is "← Return to Localhost", hanging in open
## floor beside the pinned chevron and its "Localhost · 14m" readout. Three
## cues, one destination, and the one drawn largest points at nothing visible.
##
## The rule: a portal names its destination only while the portal is on screen.
## The test is the CENTRE, not the bounds — a disc whose middle is past the
## frame edge is not a doorway the player can read, it is a smear against the
## HUD, and a label anchored 64 units under it lands in the room proper with no
## visible object to belong to. Off-screen wayfinding is the beacon's job and
## the beacon is already doing it.
func _update_label_visibility() -> void:
	if label == null:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var cam := vp.get_camera_2d()
	if cam == null:
		return
	var vis := Vector2(vp.get_visible_rect().size) / cam.zoom
	var view := Rect2(cam.get_screen_center_position() - vis * 0.5, vis)
	var on := view.has_point(global_position)
	if label.visible != on:
		label.visible = on

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
