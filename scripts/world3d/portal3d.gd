class_name Portal3D
extends Node3D
## The 3D twin of `scripts/world/region_portal.gd` (3D_BIBLE.md §4, §7).
##
## Four things, exactly as the 2D gate: a doorway, a swirl, a light and a line
## of text. In 3D the doorway is real geometry (mini-dungeon/gate) and the
## swirl is an additive disc hung in its mouth, so the portal reads as something
## you WALK THROUGH rather than a decal on the floor.
##
## Behaviour is region_portal.gd's, unchanged: touching it travels, [E] travels,
## and a locked destination refuses (in 3D it also says so, once, instead of
## silently doing nothing).
##
## HUE: the swirl, the light and the motes are the ROOM's accent, and the caption
## is TEXT_DIM — exactly region_portal.gd's palette (the contract §4 says this
## file mirrors). VISUAL_BIBLE_V2 LAW 2 grants a scene three hues and the rubric
## counts them; a gate in its destination's accent is a fourth, and the second
## gate a fifth, in every room of the game. The destination is still advertised
## in the one place it costs nothing: the line of text over the arch. What WAS
## shouting in the frames was the gate itself — an untextured near-white arch,
## the brightest object in all ten — so the masonry is graded like a prop in the
## ROOM's own BASE hue (GATE_TINT_VALUE), the swirl stays small, and nothing
## here wears a halo, a ring or a ground disc.

## The fx3d track's shader, if it has landed. Never preload(): sibling tracks
## land concurrently, and a missing preload is a parse error, not a fallback.
const VORTEX_SHADER := "res://assets/shaders3d/portal_vortex.gdshader"

## Kenney gate, scaled to a doorway a 0.9u person walks through.
const GATE_MODEL := "mini-dungeon/gate"
const GATE_HEIGHT := 2.1
## The mouth: a quad hung inside the frame. The gate is 0.8 wide x 0.75 tall at
## authored scale and only 0.2 deep, so its opening faces +/-Z and a quad in the
## XY plane (QuadMesh's default orientation) sits flush in it.
## Sized to stay INSIDE the frame's opening (the gate is 0.8 x 0.75 authored,
## so at GATE_HEIGHT its clear span is roughly 1.9 x 1.6): a swirl that pokes
## through the masonry reads as a decal, not a doorway.
const DISC_SIZE := Vector2(1.25, 1.5)
const DISC_Y := 1.0
## The destination caption's anchor: just clear of the gate's top edge, which is
## also the height objective_waypoint.gd measures its chevron clearance from.
const LABEL_Y := GATE_HEIGHT + 0.2

## The masonry's multiply (Map3D.tint's contract). Kenney's mini-dungeon gate is
## an untextured near-white lavender, and at the region ambient every frame we
## captured had it as the BRIGHTEST OBJECT ON SCREEN — a ~230-luminance arch in
## rooms whose floors sit at 64-84. Round 2 answered that with a FIXED cool grey
## (0.32, 0.34, 0.42), which fixed the glare and introduced a hue: in
## `region_api_bazaar.png` and `combat_dependency_district.png` the same NAVY
## arch stands in a magenta room and in a green one, a fourth saturated hue in
## both and the second most eye-catching object in the frame.
##
## So the tint carries the ROOM's own BASE — LAW 2's dark, the colour of its
## walls and its out-of-bounds — as a HUE, graded like every other prop in the
## room (LAW 7: "desaturated toward the region BASE"). The single copy of that
## table is environment3d.gd's REGION_BASE (`base_color()`, which also owns the
## fallback for a region that is not in it), so nothing here restates the bible.
##
## GRADED, not lifted. Round 3's first cut multiplied BASE by 2.4, which put the
## multiplier at 0.09-0.17 per channel — a quarter of region_builder3d.gd's
## TINT_MIN (0.45, its pass-4 HIGH rule: below that, every texel darker than the
## model's mean falls off the bottom of the grade and the prop goes to black).
## An arch at that multiplier is not dark stone, it is a hole with a swirl in it.
## So: BASE normalised to its hue (brightest channel 1.0), scaled to
## GATE_TINT_VALUE, and floored per channel at GATE_TINT_MIN — the same floor the
## builder gives a crate. On Kenney's ~0.87 gate that displays around 100-110,
## the top of the builder's prop band and under the floor's own highlight
## (96-116): a grey arch with a breath of the room's hue, brighter than the tile
## it stands on and dimmer than the swirl in its mouth. LAW 3: 0.5 x 0.87 is well
## under the 60% ceiling. LAW 3 spends the brightness budget on the swirl; the
## masonry only has to hold its silhouette.
const GATE_TINT_VALUE := 0.5
## region_builder3d.gd's TINT_MIN, quoted rather than imported: that file is a
## builder, not a shared helper, and the number is the contract.
const GATE_TINT_MIN := 0.45

## LAW 4: a portal is FINDABLE, not dominant. 2.8 at range 7 lit half a region
## in the destination's hue and put a coloured wash across every floor tile
## between the player and the door — the accent stopped meaning "this is the way
## out" because it was also the colour of the ground. 0.5 at range 6 is a doorway
## with a light behind it.
const LIGHT_ENERGY := 0.5
const LIGHT_RANGE := 6.0
## The swirl's own brightness. It sits just over the §7 glow threshold of 1.0, so
## the mouth of the gate is the one surface here that blooms — LAW 3's "at most
## two motivated lights", spent on the one object whose whole job is to be seen
## from across a room.
const DISC_ENERGY := 1.5
## LAW 4's particle budget, spent once: twelve slow motes, not sixteen quick ones.
const MOTE_COUNT := 12

## The one copy of LAW 2's BASE column (see GATE_TINT_VALUE). world3d.gd preloads
## this same script; environment3d.gd has landed and declares no `class_name`
## (its header says why), so a const preload is how it is reached.
const _Environment3D := preload("res://scripts/world3d/environment3d.gd")

## How often the caption asks whether the HUD is already naming this door. Four
## times a second: the answer only changes when the objective does.
const CAPTION_POLL := 0.25
## The group objective_waypoint.gd joins so a gate can ask it what it is aiming
## at without the two files knowing each other's types.
const WAYPOINT_GROUP := "objective_waypoint"

@export var target_region: String = "localhost"
@export var portal_label: String = "Portal"

var _disc_a: MeshInstance3D
var _shader_mat: ShaderMaterial
var _has_phase := false
var _has_heat := false
var _heat := 0.62
var _light: OmniLight3D
var _label: Label
var _proxy: ActorProxy
var _seed := 0.0
var _phase := 0.0
var _clock := 0.0
## Caption state: the poll accumulator and whether the line is currently printed.
var _caption_t := 0.0
var _caption_on := true

## One 128px swirl texture for every portal in the game.
static var _vortex_tex: Texture2D = null

func _ready() -> void:
	add_to_group("interactable")
	# Stable per-DESTINATION variation so two doors in one room never breathe in
	# unison like a rendering artifact (region_portal.gd's trick, same numbers).
	_seed = float(absi(target_region.hash()) % 997) * 0.0063
	var area := get_node_or_null("Area3D") as Area3D
	if area:
		area.body_entered.connect(_on_body_entered)
	_build_gate()
	_build_vortex()
	_build_light()
	_build_motes()
	_build_label()
	_proxy = ActorProxy.attach(self, ["interactable"], {
		"target_region": target_region,
		"portal_label": portal_label,
		"interact_id": "portal_%s" % target_region,
		"interact_text": get_prompt(),
	})

## The accent of the room this gate STANDS IN (see the header) — the room's one
## neon, read once at build time exactly as region_portal.gd::_room_accent()
## reads it: `GameManager.current_region` is already the region being populated
## by the time a portal enters the tree. GameTheme.REGION_ACCENT is the single
## copy of LAW 2's table, and an unknown room falls back to CYAN rather than
## inventing a hue.
func _accent() -> Color:
	return GameTheme.region_accent(GameManager.current_region)

# ------------------------------------------------------------------ building --

## The doorway. Real geometry, graded grey: see GATE_TINT_VALUE. Nothing else is
## added — no halo ring, no ground disc, no second frame. The swirl in its mouth
## is the whole of the portal's brightness budget.
func _build_gate() -> void:
	var gate := Map3D.model(GATE_MODEL)
	if gate == null:
		return
	Map3D.fit_height(gate, GATE_MODEL, GATE_HEIGHT)
	Map3D.tint(gate, _gate_tint())
	add_child(gate)

## The room's BASE as a hue at prop value (see GATE_TINT_VALUE). Built
## component-wise with an explicit alpha rather than with `Color * float`, which
## would scale the ALPHA too — and Map3D.tint multiplies the model's albedo,
## alpha included, so a scaled alpha is a transparency bug in the one channel
## nobody looks at. Read at build time from the region being populated, exactly
## as `_accent()` reads the other half of LAW 2's table. A BASE that is somehow
## black normalises to plain grey rather than dividing by zero.
func _gate_tint() -> Color:
	var b: Color = _Environment3D.base_color(GameManager.current_region)
	var peak: float = maxf(maxf(b.r, b.g), b.b)
	if peak < 0.001:
		return Color(GATE_TINT_VALUE, GATE_TINT_VALUE, GATE_TINT_VALUE, 1.0)
	var k: float = GATE_TINT_VALUE / peak
	return Color(
		clampf(b.r * k, GATE_TINT_MIN, GATE_TINT_VALUE),
		clampf(b.g * k, GATE_TINT_MIN, GATE_TINT_VALUE),
		clampf(b.b * k, GATE_TINT_MIN, GATE_TINT_VALUE),
		1.0)

## The swirl. ONE disc, either way — with the fx track's shader it draws the
## whole vortex (bands, eye and rim); without it, one additive quad carries the
## procedural spiral below. Round 1 stacked a SECOND counter-rotating disc at
## gain 2.10 inside the first, and two overbright quads on top of each other is
## how a doorway became the brightest object in ten frames. Two arms, one disc,
## at DISC_ENERGY.
func _build_vortex() -> void:
	var vivid := FxLib.vivid(_accent(), 1.0)
	var shared := _shader_material()
	if shared != null:
		_disc_a = _make_disc("Vortex", DISC_SIZE, shared)
		return
	_disc_a = _make_disc("Vortex", DISC_SIZE, _additive_disc(vivid, DISC_ENERGY))

## Draw order is the MATERIAL's job in 3D — GeometryInstance3D has no
## render_priority — and additive blending is order-independent anyway.
func _make_disc(node_name: String, size: Vector2, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var quad := QuadMesh.new()
	quad.size = size
	mi.mesh = quad
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0.0, DISC_Y, 0.0)
	add_child(mi)
	return mi

## The fx3d track's shader, if that file has landed — otherwise null and the
## additive disc below takes over (the fallback 3D_BIBLE.md §7 allows).
##
## Uniforms are SEEDED before anything animates one (HANDOVER §4.2), and only
## the names the shader actually DECLARES are touched, so this cannot fight
## whatever signature that file ends up with — including the case where it has
## no `phase` at all, in which case `_process` leaves it alone. The hue handed
## over is the RAW accent: portal_vortex.gdshader normalises it to full chroma
## itself (its own `vivid()`), exactly as the 2D swirl shader does.
func _shader_material() -> ShaderMaterial:
	if _shader_mat != null:
		return _shader_mat
	if not ResourceLoader.exists(VORTEX_SHADER):
		return null
	var sh: Shader = load(VORTEX_SHADER)
	if sh == null:
		return null
	var sm := ShaderMaterial.new()
	sm.shader = sh
	# region_portal.gd's own numbers where the names match; anything this shader
	# does not declare is simply not written, and anything it declares that is
	# not named here keeps its authored default (energy, rim_alpha, levels).
	var want := {
		"hue_color": _accent(), "color": _accent(), "accent": _accent(), "tint": _accent(),
		"speed": 0.34 + fmod(_seed, 0.16), "arms": 2.0,
		"core_heat": _heat, "peak_luma": DISC_ENERGY, "horizon": 0.26,
		"phase": 0.0, "seed": _seed * 40.0,
	}
	for u: Dictionary in sh.get_shader_uniform_list():
		var n := str(u.get("name", ""))
		if want.has(n):
			sm.set_shader_parameter(n, want[n])
			if n == "phase":
				_has_phase = true
			elif n == "core_heat":
				_has_heat = true
	_shader_mat = sm
	return sm

## The no-shader swirl: an unshaded additive quad carrying the procedural
## spiral below. `gain` pushes the brightest filament over the §7 glow
## threshold of 1.0 so the mouth of the gate is the one thing here that blooms.
func _additive_disc(vivid: Color, gain: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = _vortex_texture()
	# Over 1.0 on purpose: the glow threshold in the §7 recipe is 1.0, so the
	# swirl is the one thing in the doorway that blooms.
	m.albedo_color = Color(vivid.r * gain, vivid.g * gain, vivid.b * gain, 1.0)
	m.disable_receive_shadows = true
	return m

## A two-armed spiral with a soft rim, built once in code so the portal needs no
## imported texture (and no shader) to look like a vortex.
static func _vortex_texture() -> Texture2D:
	if _vortex_tex != null:
		return _vortex_tex
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for x in n:
		for y in n:
			var uv := Vector2(float(x) / float(n) - 0.5, float(y) / float(n) - 0.5)
			var r: float = uv.length() * 2.0
			if r >= 1.0:
				img.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
				continue
			var ang: float = atan2(uv.y, uv.x)
			var arms: float = 0.5 + 0.5 * sin(ang * 2.0 + r * 9.0)
			var core: float = clampf(1.0 - r, 0.0, 1.0)
			var edge: float = clampf(1.0 - pow(r, 6.0), 0.0, 1.0)
			var a: float = clampf(pow(core, 0.55) * (0.28 + 0.72 * arms) * edge, 0.0, 1.0)
			var v: float = clampf(0.45 + 0.55 * arms + core * 0.55, 0.0, 1.0)
			img.set_pixel(x, y, Color(v, v, v, a))
	_vortex_tex = ImageTexture.create_from_image(img)
	return _vortex_tex

## One OmniLight per gate at LAW 4's portal energy (0.5 — v2 supersedes §7's
## 2.5-5 neon rule), attenuation 1.6, shadows OFF (a portal is never the region
## focal, so it never takes one of the room's shadow-caster slots).
func _build_light() -> void:
	_light = OmniLight3D.new()
	_light.name = "PortalLight"
	# Value-normalised, chroma UNTOUCHED (1.0): FxLib.vivid's default 1.45 is the
	# chroma boost fx3d.gd refuses for lights — it turns a muted region accent
	# into a saturated wash on the floor, a fourth hue by another route.
	_light.light_color = FxLib.vivid(_accent(), 1.0)
	_light.light_energy = LIGHT_ENERGY
	_light.omni_range = LIGHT_RANGE
	_light.omni_attenuation = 1.6
	_light.shadow_enabled = false
	_light.position = Vector3(0.0, DISC_Y, 0.0)
	add_child(_light)

## Motes drifting up out of the mouth. One emitter per portal, two portals per
## region — well inside §9's budget of twelve alive.
func _build_motes() -> void:
	var p := GPUParticles3D.new()
	p.name = "Motes"
	p.amount = MOTE_COUNT
	p.lifetime = 3.2
	p.randomness = 0.6
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.vertex_color_use_as_albedo = true
	qm.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	quad.material = qm
	p.draw_pass_1 = quad
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.55
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 22.0
	# LAW 9: slow. Half the old rise, so the motes drift instead of streaming.
	pm.initial_velocity_min = 0.06
	pm.initial_velocity_max = 0.22
	pm.gravity = Vector3(0.0, 0.09, 0.0)
	pm.scale_min = 0.35
	pm.scale_max = 0.9
	pm.color = FxLib.vivid(_accent(), 1.0)
	p.process_material = pm
	p.position = Vector3(0.0, DISC_Y * 0.7, 0.0)
	add_child(p)

## The destination, named ONCE, above the frame — a screen-space label
## (scripts/world3d/screen_labels.gd) in TEXT_DIM, region_portal.gd's choice for
## the same reason: the SWIRL is the wayfinding signal and it is already the
## room's one neon, so a second accent-coloured object a few pixels above it is
## the same shout twice (LAW 4: "TEXT_DIM for captions"). The HUD's waypoint
## paints the accent on the door that is actually the objective.
##
## The round-2 frames had four texts stacked on one door: a BODY-sized Label3D
## that grew to ~30px as the player approached and clipped off the top-right
## corner of localhost ("→ Dependen"), the HUD's chevron drawn straight through
## its glyphs, and the waypoint's own "Localhost · 12m" over the top. A screen
## label is rasterised once at SMALL (14), clamped inside the safe area, and
## stacked off every other caption in the room, so the door says its name in one
## line that cannot leave the frame and cannot land on the guidance.
func _build_label() -> void:
	_label = ScreenLabels.attach(self, _caption(), ScreenLabels.SMALL,
		GameTheme.TEXT_DIM, LABEL_Y, 1)

func _caption() -> String:
	return "→ %s" % portal_label

## SAY IT ONCE. Round 3's frames still carried the destination twice within
## forty pixels: the HUD's waypoint reads "Localhost · 4m · via this portal" and
## the door under it reads "→ Localhost". The waypoint line is strictly the
## better of the two — it names the destination, the distance AND this gate's
## part in the route — so while it is aiming at THIS door the door says nothing,
## and the moment the objective moves elsewhere the caption comes back for the
## players who need to know where the other exit goes.
##
## ONLY when the two lines would say the same thing. objective_waypoint.gd's own
## ROUND 12 note is the reason the 3D line reads "via this portal": the door it
## aims at is often a HOP whose name is a different region's, and then the two
## texts are a route and a destination, not a duplicate — `region_api_bazaar.png`
## has "Localhost · 12m · via this portal" over a gate that reads "→ Stack
## Overflow Ruins", and dropping the second would leave the player not knowing
## where the door they are told to take actually goes. Likewise the idle "Way
## out" fallback aims at a door without naming it. So the gate yields when the
## waypoint is aiming at it AND names this gate's destination (see
## `_waypoint_names_me`), and keeps its name in every other case.
##
## The two files never learn each other's types: objective_waypoint.gd joins
## WAYPOINT_GROUP and answers `target_node()`, which in 3D is this portal's
## ActorProxy (§5), and `destination_region()`, the region id the line is
## naming. Hiding is done by EMPTYING the text, not by touching `visible` —
## ScreenLabels rewrites visibility every frame and skips empty labels, so
## anything else here would fight it.
func _sync_caption() -> void:
	var want := not _waypoint_names_me()
	if want == _caption_on:
		return
	_caption_on = want
	ScreenLabels.set_text(_label, _caption() if want else "")

## Is any waypoint currently aiming at this gate AND printing this gate's
## destination? Both halves matter: aimed-at alone is the hop case above, where
## the caption is the only thing naming where the door goes. A waypoint that
## cannot say what it is naming (no `destination_region`) is treated as not
## naming it — the caption stays, which is the quiet-safe failure: one line too
## many beats a door with no name.
##
## Untyped locals throughout: a group member or a returned target can be a freed
## instance, and binding one to a typed variable is the error before the guard,
## not after it.
func _waypoint_names_me() -> bool:
	if not is_instance_valid(_proxy):
		return false
	for wp in get_tree().get_nodes_in_group(WAYPOINT_GROUP):
		if not is_instance_valid(wp):
			continue
		# The cast happens AFTER the validity check, never at the loop variable.
		var node := wp as Node
		if node == null or not node.has_method("target_node") \
				or not node.has_method("destination_region"):
			continue
		var t = node.call("target_node")
		if t == null or not is_instance_valid(t) or t != _proxy:
			continue
		if str(node.call("destination_region")) == target_region:
			return true
	return false

# -------------------------------------------------------------------- frame --

## region_portal.gd's approach response, in 3D: the swirl turns a little faster
## and the pool swells as you close, and nothing else moves (LAW 9). Extra
## rotation is ACCUMULATED into `_phase` rather than applied by scaling a shader
## `speed`, because scaling the TIME term mid-run snaps the animation by however
## long the game has been open.
func _process(delta: float) -> void:
	_clock += delta
	if _proxy:
		_proxy.sync()
	_caption_t += delta
	if _caption_t >= CAPTION_POLL:
		_caption_t = 0.0
		_sync_caption()
	var near := 0.0
	var player := get_tree().get_first_node_in_group("player")
	if player is Node3D:
		var d: float = global_position.distance_to((player as Node3D).global_position)
		near = clampf(1.0 - (d - 1.1) / 5.3, 0.0, 1.0)
	# The shader spins itself off TIME * speed, so `phase` there carries ONLY the
	# near-approach bonus. The fallback discs have no clock of their own, so they
	# get the base rate too.
	var base := 0.0 if _shader_mat != null else 0.35
	_phase += delta * (base + near * 1.15)
	if _shader_mat != null:
		if _has_phase:
			_shader_mat.set_shader_parameter("phase", _phase)
		if _has_heat:
			# region_portal.gd's smoothing, one for one: the swirl lifts a couple
			# of percent as you close and nothing else about it changes.
			_heat = lerpf(_heat, 0.62 + near * 0.50, clampf(delta * 4.0, 0.0, 1.0))
			_shader_mat.set_shader_parameter("core_heat", _heat)
	else:
		if _disc_a:
			_disc_a.rotation.z = _phase
	if _light:
		var breathe: float = 0.5 + 0.5 * sin(_clock * 1.2 + _seed * 9.0)
		# LAW 9's flicker allowance is 6%, and that is all this spends at rest.
		# The approach bonus is a third of the base now instead of two and a
		# half times it: standing in a doorway must not relight the room.
		_light.light_energy = LIGHT_ENERGY * (0.94 + 0.06 * breathe) + near * 0.18

# ----------------------------------------------------------------- travel --

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	if not GameManager.is_region_unlocked(target_region):
		return
	GameManager.change_region(target_region)

## region_portal.gd::interact, plus the refusal it never had a way to voice.
func interact(_player_node: Node = null) -> void:
	if GameManager.is_region_unlocked(target_region):
		GameManager.change_region(target_region)
		return
	AudioManager.play_sfx("denied")
	# LAW 2: HOSTILE red is reserved for enemy tells. A locked door is not an
	# enemy — it is a refusal, and a refusal is TEXT with a sound behind it.
	Fx3D.glyph(get_parent(), global_position + Vector3(0.0, DISC_Y + 0.5, 0.0),
		"LOCKED", GameTheme.TEXT, 22, 0.9, 0.8)

func get_prompt() -> String:
	return "Enter %s" % portal_label
