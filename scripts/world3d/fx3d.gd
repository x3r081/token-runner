class_name Fx3D
extends RefCounted
## 3D combat/juice helpers (3D_BIBLE.md §6). This is the API CONTRACT every 3D
## actor calls; every signature below is fixed and callers already exist. Each
## call must stay safe (no-ops acceptable) so a missing effect never breaks a
## fight. Positions are WORLD units; `host` is any node in the 3D world.
##
## The rules this file obeys are the ones scripts/combat/combat_fx.gd obeys, in
## three dimensions:
##
##   * every helper is STATIC and EVENT-DRIVEN — nothing runs per-frame in
##     GDScript; motion is handed to Tweens, which live engine-side;
##   * nothing parents to the thing that caused it. Effects go under a lazily
##     created `Fx3DRoot` on the world node, so a corpse can leave on its own
##     schedule while its death keeps playing;
##   * everything frees itself; a missing shader, a missing FX texture or a
##     host that already left the tree all degrade to "draw less", never to an
##     error;
##   * meshes, materials, gradients and shaders are CACHED — one unit torus,
##     one unit box, two quads, one fade ramp for the whole game.
##
## BUDGET (3D_BIBLE §9: <= 12 GPUParticles3D alive, <= 40 OmniLights per region
## with <= 3 casting shadows). Rather than count in static ints — which drift
## across a scene change and then silently switch every effect off for the rest
## of the session, the exact failure mode FxLib had to add `release_hit_stop()`
## for — each effect family lives in its own bin node under `Fx3DRoot` and the
## cap is a `get_child_count()` on that bin. The count is therefore EXACT, it
## costs nothing, and it resets itself when the world is torn down, because the
## thing doing the counting is torn down with it.
##
## Over budget, effects THIN OUT and then stop. Glyphs get their own bin because
## a damage number is INFORMATION, not decoration: sparks may be dropped in a
## six-enemy brawl, a number may not. Its size is now set by what ScreenLabels
## can actually SHOW rather than by generosity — see MAX_GLYPHS.
##
## VISUAL_BIBLE_V2 (LAW 5, LAW 9) — WHAT CHANGED AND WHY
##
## The v1 version of this file was built on one assumption that turned out to be
## wrong: that an unshaded additive surface should be OVERBRIGHT, because the
## environment's bloom threshold is 1.0 and crossing it is how a thing glows.
## Every helper multiplied its colour by 1.5x-2.8x on that theory, and the
## caller was invited to pass overbright colours on top ("overbright colours
## welcome"). Look at docs/screenshots/qa3d/combat_dependency_district.png: a
## single hit is a flash sprite, a ring, a ground decal, a spark spray and an
## omni light, EACH of them over the threshold, stacked on the same twenty
## pixels. The frame has no blacks left.
##
## So under v2 every additive surface in this file is on a BRIGHTNESS BUDGET
## (`_capped`), and the budgets sit below 1.0 on purpose: bloom is reserved for
## LAW 3's five bright things, and transient combat FX are not among them. The
## effects did not get fewer or shorter-lived in kind — a hit is still four
## beats, a kill still implodes and then detonates — they got QUIET ENOUGH TO
## STACK. Three overlapping hits now read as three hits.
##
## Three rules hold the line, and every helper below obeys all three:
##   1. colour is NORMALISED to a per-family ceiling, never trusted and never
##      multiplied — hue survives, brightness does not;
##   2. nothing is white. "White-hot" cores are the blow's own hue lifted toward
##      its ceiling (`_hot`), so a hit never introduces a fourth hue (LAW 2);
##   3. every effect is capped in TIME as well — a flash decays in 0.15s, a ring
##      is gone in 0.4s, a glyph in 0.8s. Combat may be loud; it may not linger.
##
## ROUND 7 ADDS TWO MORE:
##
##   4. THE HUE ITSELF IS NOT TRUSTED EITHER (`_law`, see "palette law" below).
##      Budgeting brightness while passing every caller's hue straight through
##      lets a violet or magenta call site put a fourth hue in a three-hue
##      room. A colour now has to BE hostile red or BE the room's accent to
##      stay saturated; anything else desaturates toward TEXT. And nothing this
##      file spawns sits above `FX_MAX_Y` — combat happens on the floor.
##   5. WORLD TEXT IS SCREEN TEXT. `glyph()` no longer builds a Label3D; it
##      drops an anchor in the world and hands a plain 2D Label in the UI font
##      to `ScreenLabels`. One typographic system, two sizes, one pixel grid
##      (LAW 1), and a damage number that can no longer hide under the HUD.
##
## WHAT THIS ROUND DOES NOT CLOSE, so nobody reads it as closed: the two rings
## the critic named — "a magenta torus floating in the sky" at ~(1398, 18) in
## region_stackoverflow_ruins.png and "a pink ring under the saucer" at
## ~(455, 258) in region_token_vault.png — are NOT drawn by this file. Both are
## enemy3d.gd's `_alert_ring` (its own 0.34/0.40 TorusMesh under `_tell_mat`,
## visible for as long as `is_committed()`): they appear in static ARRIVAL
## frames with no combat in them, sample at the same clipped (255, 232, 255)
## in both, and have the tube proportions of that mesh, not of `_torus_mesh()`.
## A hoop from this file lives 0.4s and is only ever drawn by a combat event.
## The gate and the ceilings below govern what THIS file draws; that ring is
## enemy3d's to bring under LAW 2/3.

# --------------------------------------------------------------- layout ----

const FX_ROOT_NAME := "Fx3DRoot"

const BIN_POOL := "Pool"        # pooled one-shot GPUParticles3D
const BIN_FLARES := "Flares"    # short-lived OmniLight3D pulses
const BIN_GHOSTS := "Ghosts"    # afterimage copies
const BIN_GLYPHS := "Glyphs"    # anchors for screen-space damage numbers/text
const BIN_SHAPES := "Shapes"    # rings, ripples, beams, flash sprites

## Emitters are POOLED (never freed) because allocating a GPUParticles3D means
## allocating GPU buffers; twelve is the bible's ceiling on live emitters, and
## also comfortably more than a screen can show apart. Every bin below is at or
## under its previous value — VISUAL_BIBLE_V2 lets a budget tighten, never grow.
const MAX_EMITTERS := 10
const MAX_FLARES := 6
const MAX_GHOSTS := 4
## Was 28, on the reasoning that a damage number is INFORMATION and may not be
## dropped. That reasoning still holds; the NUMBER was wrong once glyphs became
## screen-space, because ScreenLabels shows at most `ScreenLabels.MAX_VISIBLE`
## (10) captions at a time and keeping eighteen more alive behind them buys
## nothing but per-frame unprojections. Twelve is that ceiling plus a little
## slack for the ones already fading out.
const MAX_GLYPHS := 12
const MAX_SHAPES := 48

## Fixed particle allocation per pooled emitter. Per-call counts scale it via
## `amount_ratio` instead of writing `amount`, which would reallocate the GPU
## buffer on every single spark spray.
const BURST_AMOUNT := 24

## Hard ceiling on particles in ONE spray. A spark spray reads as sparks up to
## about a dozen and a half; past that it is a cloud, and a cloud of additive
## quads over a mid-value floor (LAW 6) is a bloom blob, not a hit.
const BURST_MAX_COUNT := 16

# ------------------------------------------------------- LAW 5 / LAW 9 caps ----
#
# Every number below is a CEILING the callers cannot raise. The frames that
# triggered VISUAL_BIBLE_V2 were washed to pastel by exactly this layer:
# overbright additive sprites (albedo x2.2 - x2.8) stacking on top of a bloom
# threshold of 1.0, so a hit, its ring, its ground mark and its light all
# crossed the threshold at once and the room went white. The FX are allowed to
# be loud (combat may be); they are not allowed to WHITE OUT the frame, and
# they are not allowed to outlive the beat they punctuate.

## The brightest a flash light may be, and the longest it may take to decay.
## Callers derive `energy` from damage and crit multipliers and pass values up
## to 5; the pulse is a fifth of a second of *motivated* light, not a second
## sun. Clamped, not trusted.
##
## WHY 1.2 AND NOT 2.5: Godot 4's omni falloff is
##   energy * (1 - (d / range)^4)^2 * d^(-omni_attenuation)
## i.e. an inverse POWER of distance, so a light hung 0.35u over the floor at
## energy 2.5 / attenuation 2.2 put 2.5 * 0.35^-2.2 = 25x irradiance on the
## tiles under it — about eighty times what a region light (energy <= 1.2 at
## 2-3u) lands on the same floor — and a white disc a unit wide for 0.15s is
## the defect in combat_dependency_district.png by another route. At 1.2,
## hung 0.6u up with attenuation 1.8, the peak is 1.2 * 0.6^-1.8 = 3.0: a
## visible warm pool about 1.5u across, and no pixel of floor goes white.
const FLARE_MAX_ENERGY := 1.2
const FLARE_MAX_TIME := 0.15
const FLARE_HEIGHT := 0.6
const FLARE_ATTENUATION := 1.8

## The brightest CHANNEL an additive FX surface may output, per family. Below
## 1.0 the surface cannot cross the environment's bloom threshold on its own —
## which is the point: bloom belongs to LAW 3's five bright things, and a spark
## is not one of them. The flash core is the single exception at 1.0, because a
## landed hit has to read on a lit floor.
const SPARK_CEILING := 0.80
const RING_CEILING := 0.72
const FLASH_CEILING := 1.00
const BEAM_CEILING := 0.85
const GHOST_CEILING := 0.55
const BURN_CEILING := 0.85

## The portal disc is one of LAW 3's two motivated lights, so it gets its own,
## higher pair of numbers — and hard ceilings all the same. The swirl body must
## stay under the environment's 1.0 bloom threshold (only the thin rim at the
## mouth of the gate is allowed near it), so the hue is normalised to 0.95 and
## the emission may not pass 1.5, which is also where portal_vortex.gdshader
## clamps it in code. A doorway is FINDABLE; it is not a second sun.
const PORTAL_HUE_CEILING := 0.95
const PORTAL_MAX_ENERGY := 1.5

## Rings and ground marks: thin, translucent at birth, gone inside 0.4s.
##
## 0.50 and not 0.60. At 0.6 an additive hoop over a mid-value LAW 6 floor is
## READ AS SOLID — a drawn line, not a pressure wave — and it holds that weight
## for its whole life because it is also the widest thing on screen. Half is
## the point at which the floor's own tone still comes through the band, which
## is what makes a ring look like force passing over ground.
const RING_MAX_ALPHA := 0.50
const RING_MAX_TIME := 0.40

## Nothing this file draws belongs in the SKY.
##
## Combat FX are events on the GROUND plane: a hoop, a ground mark, a spark
## spray and a flash pool all describe something that happened to a character
## standing on a floor. A CEILING, not a position — an effect at ankle height
## stays at ankle height. 2.4 and not "head height": the tallest things that
## get hit are the scale-2 UFO bosses, which HOVER (enemy3d's `_model_y`) and
## take a hit spark at 0.55 of their model height, so their impact point sits
## around 2.1u; a lower clamp would draw the flash a hand's width under the
## body, which reads as detached rather than grounded. (The ring at the top edge
## of region_stackoverflow_ruins.png is not this — it is at the FAR wall of the
## room, on the floor, and it is enemy3d's `_alert_ring`; see the header.)
const FX_MAX_Y := 2.4

## Glyph typography (LAW 1: one pixel grid, aliased text). Sizes come from
## ScreenLabels (SMALL 14 / BODY 18) — this file does not get a third scale.
const GLYPH_MAX_TIME := 0.80
## The rise, in world units, that the glyph's anchor travels before it goes.
## LAW 9 wants small motion: at the rig's ~0.011 units per screen pixel this is
## about forty pixels of drift over the life of the text, which reads as "this
## number came off that enemy" and stops well short of a banner.
const GLYPH_MAX_RISE := 0.45
## The sideways half of that drift, alternating per call (see `_glyph_flip`).
## Two hits in the same second used to rise along the SAME column and overwrite
## each other pixel for pixel; a fan of up-left / up-right separates them
## without adding motion — the rise is unchanged, it is merely tilted.
const GLYPH_DRIFT := 0.30

const DISSOLVE_PATH := "res://assets/shaders3d/dissolve3d.gdshader"
const PORTAL_PATH := "res://assets/shaders3d/portal_vortex.gdshader"
const HOLOGRAM_PATH := "res://assets/shaders3d/hologram3d.gdshader"
const RIPPLE_PATH := "res://assets/shaders3d/ground_ripple3d.gdshader"

const META_FREE_AT := "fx3d_free_at"

## Dissolve bookkeeping (see `dissolve()` / `undissolve()`). On the model root:
const META_DISSOLVED := "fx3d_dissolved"          # wears burn materials
const META_DISSOLVE_DONE := "fx3d_dissolve_done"  # the burn has finished
## On each MeshInstance3D: what it wore before the burn.
const META_PREV_SURFACES := "fx3d_prev_surfaces"
const META_PREV_OVERRIDE := "fx3d_prev_override"
## On the model's AnimationPlayer: the self-heal Callable, so it can be removed.
const META_HEAL_HOOK := "fx3d_heal_hook"

# Cached resources. Resources, not nodes — safe to hold statically across a
# scene change, unlike anything that lives in a tree.
static var _torus: TorusMesh
static var _quad_sprite: QuadMesh
static var _quad_particle: QuadMesh
static var _box: BoxMesh
static var _ramp: GradientTexture1D
static var _white: Texture2D
static var _shaders: Dictionary = {}
## Which way the NEXT glyph leans. Purely cosmetic, so it is deliberately not
## reset on a scene change: the only thing a stale value can do is start the
## next fan on its other side.
static var _glyph_flip := false

# --------------------------------------------------------------- plumbing ----

static func _ok(n: Node) -> bool:
	return n != null and is_instance_valid(n) and n.is_inside_tree()

## The node every effect hangs off. Preference order: the World3D node (group
## "world", 3D_BIBLE §3), then the current scene, then the nearest Node3D above
## `host`. The last fallback means an effect can die with its cause in a bare
## test scene — acceptable, and the alternative is no effect at all.
static func _fx_root(host: Node) -> Node3D:
	if not _ok(host):
		return null
	var tree := host.get_tree()
	if tree == null:
		return null
	var base: Node3D = null
	# The 2D world.gd is ALSO in group "world" (it is a Node2D), so this is a
	# type test and not just a group lookup: in a 2D scene it finds nothing here
	# and falls through to the scene root / ancestor search below.
	var world := tree.get_first_node_in_group("world")
	if world is Node3D:
		base = world as Node3D
	if base == null and tree.current_scene is Node3D:
		base = tree.current_scene as Node3D
	if base == null:
		base = _nearest_node3d(host)
	if base == null:
		return null
	var root := base.get_node_or_null(NodePath(FX_ROOT_NAME)) as Node3D
	if root == null:
		root = Node3D.new()
		root.name = FX_ROOT_NAME
		base.add_child(root)
	return root

static func _nearest_node3d(n: Node) -> Node3D:
	var cur := n
	while cur != null:
		if cur is Node3D:
			return cur as Node3D
		cur = cur.get_parent()
	return null

## The bin for one effect family, created on demand. Returns null when the bin
## is already at `cap` — which is the whole budget system: a live count that
## cannot drift because it is `get_child_count()` on a node that self-frees.
## `cap < 0` means "no cap" (the pool manages its own).
static func _bin(root: Node3D, bin_name: String, cap: int) -> Node3D:
	if root == null:
		return null
	var n := root.get_node_or_null(NodePath(bin_name)) as Node3D
	if n == null:
		n = Node3D.new()
		n.name = bin_name
		root.add_child(n)
	if cap >= 0 and n.get_child_count() >= cap:
		return null
	return n

## Cached shader load, exists()-guarded, negative result cached too. A missing
## shader must cost one filesystem check per session, not one per effect.
static func _shader(path: String) -> Shader:
	if _shaders.has(path):
		var hit: Shader = _shaders[path]
		return hit
	var sh: Shader = null
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is Shader:
			sh = res as Shader
	_shaders[path] = sh
	return sh

# ------------------------------------------------------------ palette law ----
#
# VISUAL_BIBLE_V2 LAW 2, enforced at the layer that actually draws.
#
# Neither of the regions the critic named a ring in has a magenta in its
# palette — stackoverflow_ruins is #E8C46B gold over #14110C, token_vault is
# #FFD34D gold over #14100A — and this file HAD been letting such hues in from
# outside the room: enemy3d and player3d between them hand it #8B5CF6 violet,
# #FF2D95 magenta, #7DFFF0 cyan-hot, #A8FF3E acid, #FFB020 amber and nine more,
# and they hand over the same hue whatever region the fight is in. (The two
# rings actually in those frames are enemy3d's own `_alert_ring`, not a call
# into this file — see the header — but the leak below is real all the same.)
#
# v2 budgeted the BRIGHTNESS of those hues (`_capped`) and never questioned the
# hue itself, so a violet ring came out as a perfectly well-behaved, perfectly
# out-of-palette lilac. LAW 2 allows a scene THREE hues; a fight is not
# entitled to a fourth just because a call site is fond of one.
#
# So every colour entering this file now passes `_law` before anything is drawn
# with it:
#
#   * HOSTILE #FF4757 survives — an enemy tell is entitled to it, globally;
#   * the CURRENT REGION's ACCENT survives — that is the one neon the room has;
#   * everything else is DESATURATED TOWARD TEXT #D8DEEA, not replaced by it. A
#     heal ring stays a hair green and a push ring a hair cyan, which is as much
#     hue as a 0.3s effect needs; what it loses is the chroma that made it read
#     as a fourth colour in a three-colour room.
#
# And there is no magenta or lilac FALLBACK left anywhere: a caller that passes
# black now gets TEXT, not the violet that portal_vortex.gdshader happens to
# declare as its uniform default.

## How far a hue that is neither HOSTILE nor the region ACCENT is pulled toward
## TEXT. At 0.82, #8B5CF6 violet lands on (0.79, 0.78, 0.93) and #FF2D95 magenta
## on (0.88, 0.80, 0.90) — cool greys with a memory of where they came from.
## Neither reads as a saturated hue at any size this file draws.
const LAW_DESATURATE := 0.82

## Per-channel tolerance for "this IS hostile / IS the accent", measured on hues
## normalised to peak 1.0. Wide enough that a caller's #FF4757 with a rounding
## error still matches; tight enough that violet never passes for gold (#FFD34D
## and #8B5CF6 differ by 0.63 on the blue channel alone).
const LAW_TOLERANCE := 0.12

## The room's one neon (LAW 2's ACCENT column). GameTheme owns that table, so
## this reads it rather than keeping a third copy; `GameManager` is guarded the
## way FxLib.hit_stop guards DialogueManager, so a bare test scene degrades to
## "no accent survives the gate" instead of erroring.
static func _region_accent() -> Color:
	if GameManager:
		return GameTheme.region_accent(GameManager.current_region)
	return GameTheme.TEXT

## Hue equality, brightness ignored: a caller that passes an overbright or a
## dimmed version of the accent still means the accent.
static func _hue_matches(color: Color, other: Color) -> bool:
	var a: float = maxf(color.r, maxf(color.g, color.b))
	var b: float = maxf(other.r, maxf(other.g, other.b))
	if a <= 0.001 or b <= 0.001:
		return false
	return absf(color.r / a - other.r / b) <= LAW_TOLERANCE \
		and absf(color.g / a - other.g / b) <= LAW_TOLERANCE \
		and absf(color.b / a - other.b / b) <= LAW_TOLERANCE

## THE palette gate. Every helper below runs its caller's colour through this
## before `_capped` puts it on a brightness budget — hue first, then brightness.
## Alpha is passed through untouched; it is what the tweens drive.
static func _law(color: Color) -> Color:
	var mx: float = maxf(color.r, maxf(color.g, color.b))
	if mx <= 0.001:
		return Color(GameTheme.TEXT.r, GameTheme.TEXT.g, GameTheme.TEXT.b, color.a)
	if _hue_matches(color, GameTheme.RED):
		return Color(GameTheme.RED.r, GameTheme.RED.g, GameTheme.RED.b, color.a)
	var accent := _region_accent()
	if _hue_matches(color, accent):
		return Color(accent.r, accent.g, accent.b, color.a)
	var quiet := color.lerp(GameTheme.TEXT, LAW_DESATURATE)
	return Color(quiet.r, quiet.g, quiet.b, color.a)

## Pull a spawn position down onto the world the player is standing in. See
## FX_MAX_Y: a caller's anchor height is not this file's business, and a hoop
## or a flash pool hanging in the roofline is the one thing a viewer names.
static func _grounded(pos: Vector3) -> Vector3:
	return Vector3(pos.x, minf(pos.y, FX_MAX_Y), pos.z)

# -------------------------------------------------------------- resources ----

## Put a colour ON a brightness budget, hue intact.
##
## THE single most important function in this file. Callers hand this layer
## whatever they like — `Color(2.4, 0.8, 0.9)`, `Color(1, 1, 1)`, a muted region
## accent straight out of the palette table — and before v2 those values went
## into an additive material multiplied by a further 1.5x-2.8x. Three of those
## overlapping was a white hole in the frame.
##
## So every additive surface now NORMALISES: the brightest channel is set to
## exactly `ceiling`, and the other two follow, which fixes both failure modes at
## once. An overbright input comes DOWN to budget; a muted accent (#E8C46B,
## #4D7CFF) comes UP to the same budget instead of collapsing into sludge, so
## every region's sparks read with equal weight and none of them bloom.
##
## Alpha is passed through untouched — it is what the tweens drive.
static func _capped(color: Color, ceiling: float) -> Color:
	var mx: float = maxf(color.r, maxf(color.g, color.b))
	if mx <= 0.0001:
		return Color(0.0, 0.0, 0.0, color.a)
	var k: float = maxf(ceiling, 0.0) / mx
	return Color(color.r * k, color.g * k, color.b * k, color.a)

## `_capped`, then lifted toward white by `k`. The "white-hot core" of a hit,
## without the actual white: a hot spark is a PALER version of the blow's hue,
## which reads as heat and still tells you whose blow it was. Pure white cores
## were most of the blown-out area in the QA frames.
static func _hot(color: Color, ceiling: float, k: float, alpha: float) -> Color:
	var c := _capped(color, ceiling)
	var t: float = clampf(k, 0.0, 1.0)
	return Color(
		lerpf(c.r, ceiling, t),
		lerpf(c.g, ceiling, t),
		lerpf(c.b, ceiling, t),
		alpha)

## The FX workhorse material: unshaded, additive, depth-tested but not
## depth-writing, two-sided.
##
## UNSHADED means the renderer outputs ALBEDO and IGNORES EMISSION, so brightness
## lives entirely in the albedo. Under v2 that albedo is BUDGETED (`_capped`)
## rather than overbright: LAW 5 keeps the bloom threshold at 1.0 for LAW 3's
## five bright things, and transient combat FX are not among them. A material
## per effect, because the alpha is what gets tweened.
static func additive_material(color: Color, tex: Texture2D = null, billboard: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.disable_receive_shadows = true
	m.albedo_color = color
	if tex != null:
		m.albedo_texture = tex
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
	return m

## A thin flat hoop of radius 1 lying in the XZ plane (TorusMesh's natural
## orientation), so a ring scaled on X/Z is a ground-parallel shockwave without
## any rotation maths at the call site.
static func _torus_mesh() -> TorusMesh:
	if _torus == null:
		var t := TorusMesh.new()
		# THIN. A hoop is a line of force, not a tube of neon: at 0.08 of the
		# radius the old ring drew a solid band of additive colour that ate the
		# floor under it. 0.025 reads as an edge at every radius a caller uses.
		t.inner_radius = 0.975
		t.outer_radius = 1.025
		t.rings = 40          # around the ring: enough to read as a circle
		t.ring_segments = 6   # around the tube: it is 5cm thick, nobody counts
		_torus = t
	return _torus

## Unit quad (1x1, facing +Z). No material of its own — every user sets a
## `material_override`, so one mesh serves billboard flashes and floor decals.
static func _sprite_quad() -> QuadMesh:
	if _quad_sprite == null:
		var q := QuadMesh.new()
		q.size = Vector2(1.0, 1.0)
		_quad_sprite = q
	return _quad_sprite

## The particle draw pass. This one DOES own its material: the per-call colour
## rides on the particle vertex colour (`vertex_color_use_as_albedo`), so every
## pooled emitter can share a single draw material.
static func _particle_quad() -> QuadMesh:
	if _quad_particle == null:
		var q := QuadMesh.new()
		# 8.5cm. At 0.14 a spark was a 12-screen-pixel additive lozenge at the
		# bible's camera distance — the white capsules littering the QA frames —
		# and a dozen of them overlapping was a bloom blob. At this size a spray
		# reads as grit coming off the surface that was struck.
		q.size = Vector2(0.085, 0.085)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		m.disable_receive_shadows = true
		m.vertex_color_use_as_albedo = true
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.particles_anim_h_frames = 1
		m.particles_anim_v_frames = 1
		m.particles_anim_loop = false
		var tex := FxLib.glow_dot()
		if tex != null:
			m.albedo_texture = tex
		q.material = m
		_quad_particle = q
	return _quad_particle

static func _box_mesh() -> BoxMesh:
	if _box == null:
		var b := BoxMesh.new()
		b.size = Vector3.ONE
		_box = b
	return _box

## "Particles fade out instead of blinking out" — the 3D twin of
## FxLib.fade_ramp(). ParticleProcessMaterial wants a texture, not a Gradient.
##
## The ramp is also the spray's SECOND brightness budget, on top of `_capped`:
## it never reaches full alpha and it starts falling immediately, so the moment
## where a dozen additive quads are all at peak — the moment that blows out —
## simply does not exist any more.
static func _fade_ramp() -> GradientTexture1D:
	if _ramp == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		g.colors = PackedColorArray([
			Color(1.0, 1.0, 1.0, 0.80),
			Color(1.0, 1.0, 1.0, 0.52),
			Color(1.0, 1.0, 1.0, 0.0)])
		var t := GradientTexture1D.new()
		t.gradient = g
		t.width = 64
		_ramp = t
	return _ramp

## 1x1 white. The dissolve shader samples `albedo_tex` unconditionally, and a
## Kenney surface without an albedo texture must still come out its own colour.
static func white_texture() -> Texture2D:
	if _white == null:
		var img := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white = ImageTexture.create_from_image(img)
	return _white

# ---------------------------------------------------------------- bursts ----

static func _make_emitter(pool: Node3D) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "burst_%d" % pool.get_child_count()
	p.one_shot = true
	p.explosiveness = 1.0
	p.randomness = 0.25
	p.amount = BURST_AMOUNT
	p.lifetime = 0.4
	p.local_coords = false      # sparks stay where they were thrown
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.draw_pass_1 = _particle_quad()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.12
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 180.0
	pm.flatness = 0.0
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -220.0
	pm.angular_velocity_max = 220.0
	pm.scale_min = 0.45
	pm.scale_max = 1.0
	pm.color_ramp = _fade_ramp()
	p.process_material = pm
	pool.add_child(p)
	return p

## An emitter that is done firing AND done living. `emitting` goes false when a
## one-shot finishes EMITTING, not when its particles die, so restarting on that
## alone would cut a spray off mid-air — hence the wall-clock release stamp.
static func _take_emitter(root: Node3D) -> GPUParticles3D:
	var pool := _bin(root, BIN_POOL, -1)
	if pool == null:
		return null
	var now := Time.get_ticks_msec()
	for c: Node in pool.get_children():
		var p := c as GPUParticles3D
		if p == null:
			continue
		if not p.emitting and now >= int(p.get_meta(META_FREE_AT, 0)):
			return p
	if pool.get_child_count() < MAX_EMITTERS:
		return _make_emitter(pool)
	return null

## Pooled one-shot spark spray.
##
## Colours are BUDGETED, not trusted (`_capped` + `SPARK_CEILING`), and the count
## is capped at `BURST_MAX_COUNT`: a spray of a dozen small dim additive quads
## over a mid-value floor is grit, and that is all this call is for. The old
## contract ("overbright colours welcome", albedo x2.2, 24 particles at 0.14u)
## is exactly what turned every hit in the QA frames into a bloom blob, so
## overbright inputs are now normalised down rather than passed through.
static func burst(host: Node, pos: Vector3, color: Color, count: int = 12, speed: float = 4.0, life: float = 0.4) -> void:
	if count <= 0:
		return
	var root := _fx_root(host)
	if root == null:
		return
	var p := _take_emitter(root)
	if p == null:
		return
	var pm := p.process_material as ParticleProcessMaterial
	if pm == null:
		return
	var sp: float = maxf(speed, 0.05)
	# Sparks are punctuation: half a second is already the outside of what reads
	# as one event, and anything longer is litter drifting through a quiet frame.
	var lf: float = clampf(life, 0.08, 0.5)
	pm.initial_velocity_min = sp * 0.35
	pm.initial_velocity_max = sp
	# Damping is what turns a spray into debris: particles throw hard and then
	# settle, instead of sliding away at constant speed forever.
	pm.damping_min = sp * 0.35
	pm.damping_max = sp * 1.10
	pm.gravity = Vector3(0.0, -clampf(sp * 1.4, 2.0, 12.0), 0.0)
	# `_law` owns the hue, the cap owns brightness, the ramp owns alpha — hence
	# the explicit 1.0.
	var spark := _capped(_law(color), SPARK_CEILING)
	pm.color = Color(spark.r, spark.g, spark.b, 1.0)
	p.lifetime = lf
	var n: int = mini(count, BURST_MAX_COUNT)
	p.amount_ratio = clampf(float(n) / float(BURST_AMOUNT), 0.08, 1.0)
	p.global_position = _grounded(pos)
	p.set_meta(META_FREE_AT, Time.get_ticks_msec() + int(lf * 1000.0) + 250)
	p.restart()
	p.emitting = true

# ----------------------------------------------------------------- rings ----

## One expanding hoop. Split out so `shockwave` can draw several without
## repeating the tween setup, exactly as CombatFx._ring_line does in 2D.
##
## `hot` (0 = the plain hue, 1 = as pale as the family ceiling allows) is how a
## caller asks for the paler, faster INNER hoop of a shockwave or a crit. It is
## a parameter rather than something the caller pre-computes with `_hot`,
## because the palette gate has to run FIRST: lifting #8B5CF6 toward its ceiling
## and then desaturating gives a different — and paler — grey than desaturating
## and then lifting, and only the second order can promise that the inner hoop
## is the same hue as the outer one.
static func _hoop(host: Node, pos: Vector3, color: Color, r_start: float, r_end: float,
		duration: float, alpha: float, priority: int, hot: float = 0.0) -> void:
	var bin := _bin(_fx_root(host), BIN_SHAPES, MAX_SHAPES)
	if bin == null:
		return
	var r0: float = maxf(r_start, 0.01)
	var r1: float = maxf(r_end, 0.01)
	# A hoop may CONVERGE as well as expand — `kill_pop` collapses one onto the
	# corpse before it detonates. Clamping r1 above r0 would silently turn that
	# implosion into a tiny expansion, so the two ends are clamped independently
	# and only the tube profile knows which direction it is going.
	var expanding: bool = r1 >= r0
	var y0: float = 0.60 if expanding else 0.30
	var y1: float = 0.32 if expanding else 0.66
	var dur: float = clampf(duration, 0.06, RING_MAX_TIME)
	var mi := MeshInstance3D.new()
	mi.mesh = _torus_mesh()
	# Budgeted, translucent, thin (LAW 5). The hoop was albedo x2.1 at alpha
	# 0.95 — an opaque overbright band that crossed the bloom threshold on its
	# own and stayed on screen for the whole hit.
	var a0: float = clampf(alpha, 0.0, RING_MAX_ALPHA)
	var lawful := _law(color)
	var tint := _capped(lawful, RING_CEILING)
	if hot > 0.0:
		tint = _hot(lawful, RING_CEILING, hot, 1.0)
	var mat := additive_material(Color(tint.r, tint.g, tint.b, a0))
	mat.render_priority = priority
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bin.add_child(mi)
	# Most callers hand over a FEET position (y = 0). A tube centred exactly on
	# the floor plane loses its lower half to the depth test; 3cm up keeps the
	# whole hoop visible, and is invisible on a ring drawn at chest height.
	mi.global_position = _grounded(pos) + Vector3(0.0, 0.03, 0.0)
	# Y is squashed further as the ring grows, so the tube thins as it widens —
	# the 3D equivalent of tweening a Line2D's width down.
	mi.scale = Vector3(r0, y0, r0)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(r1, y1, r1), dur) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# EASE_OUT, not EASE_IN: the alpha has to be visibly falling from the first
	# frame, so the ring never sits at full strength while it is also at its
	# widest. That overlap is what read as a solid disc of light in the frames.
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, dur).set_ease(Tween.EASE_OUT)
	tw.tween_callback(mi.queue_free)

## The default punctuation hoop. `color` is a REQUEST: `_hoop` sends it through
## the palette gate, so a ring is the region ACCENT, HOSTILE, or a quiet grey
## with a memory of the hue the caller asked for — never a fourth colour.
static func ring(host: Node, pos: Vector3, color: Color, r_start: float, r_end: float, duration: float = 0.35) -> void:
	_hoop(host, pos, color, r_start, r_end, duration, RING_MAX_ALPHA, 4)

## A ring painted ON THE FLOOR (assets/shaders3d/ground_ripple3d.gdshader).
## In a 3/4 top-down view a hoop in the air is a thin ellipse the eye reads as a
## line; a ring on the ground reads instantly as force leaving a point. Every
## uniform is seeded before anything is tweened (HANDOVER gotcha 2).
static func ground_ripple(host: Node, pos: Vector3, color: Color, radius: float,
		duration: float = 0.5, spokes: float = 0.0) -> void:
	var sh := _shader(RIPPLE_PATH)
	if sh == null:
		return
	var bin := _bin(_fx_root(host), BIN_SHAPES, MAX_SHAPES)
	if bin == null:
		return
	var r: float = maxf(radius, 0.05)
	var dur: float = clampf(duration, 0.08, RING_MAX_TIME)
	var mi := MeshInstance3D.new()
	mi.mesh = _sprite_quad()
	var mat := ShaderMaterial.new()
	mat.shader = sh
	# NOT FxLib.vivid() any more. `vivid` pushes chroma to 1.45 and value to
	# full — correct for a 2D layer sitting under a dark CanvasModulate, wrong
	# for an additive decal lying on a lit LAW 6 floor, where it painted a
	# saturated disc that owned the frame. Budgeted hue, dim energy, thin band.
	mat.set_shader_parameter("ring_color", _capped(_law(color), RING_CEILING))
	mat.set_shader_parameter("progress", 0.0)
	# 0.08, not 0.10: the band is the only part of this decal that carries
	# brightness (the shader puts 0.78 of the albedo in it), so its width IS how
	# much floor the mark covers. A thinner wavefront over a readable LAW 6 floor
	# is a mark travelling across ground; a wider one is a disc switching on.
	mat.set_shader_parameter("thickness", 0.08)
	mat.set_shader_parameter("energy", 0.85)
	# NOT 1.0, and not RING_MAX_ALPHA either. The shader clamps its own ALPHA to
	# 0.60 and then multiplies by `fade`, so seeding the 0.50 cap here would have
	# compounded to 0.30 and the mark would have vanished — while seeding 1.0
	# left the peak at the shader's 0.60, over this file's ceiling. 0.83 is the
	# number that makes the two agree: 0.60 * 0.83 = 0.50 exactly.
	mat.set_shader_parameter("fade", 0.83)
	mat.set_shader_parameter("spokes", spokes)
	mat.set_shader_parameter("inner_wash", 0.05)
	mat.render_priority = 3
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bin.add_child(mi)
	# QuadMesh faces +Z; -90 deg about X lays it flat with its normal up. Lifted
	# 4cm so it never z-fights the floor tiles it is painted on.
	mi.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	mi.global_position = _grounded(pos) + Vector3(0.0, 0.04, 0.0)
	mi.scale = Vector3(r * 2.0, r * 2.0, 1.0)
	var tw := mi.create_tween()
	tw.tween_property(mat, "shader_parameter/progress", 1.0, dur) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mat, "shader_parameter/fade", 0.0, dur).set_ease(Tween.EASE_OUT)
	tw.tween_callback(mi.queue_free)

## "Something important happened HERE": an accent hoop, a faster paler inner
## hoop, the ground mark, and a light so the room reacts. The 2D twin's default
## punctuation mark, in three dimensions.
##
## The inner hoop used to be PURE WHITE at alpha 0.85, on top of an accent hoop
## at 0.95, on top of a ground decal at energy 3.0, on top of a 5-energy light.
## Four blown-out layers on one spot is the single loudest thing this file did.
## It is now one budgeted accent hoop, one paler and faster hoop in the SAME
## hue, a dim ground mark and a 1.2-energy pulse — still four beats of one
## event, none of which can white out the frame on its own or together.
##
## The inner hoop now asks `_hoop` for its pale variant (`hot`) instead of
## pre-lifting the colour itself, so the palette gate runs on the caller's own
## hue exactly once and both hoops come out of the same gate decision. Under the
## old order a violet shockwave produced an outer grey and an inner near-white,
## which read as two effects rather than one.
static func shockwave(host: Node, pos: Vector3, color: Color, radius: float, duration: float = 0.45) -> void:
	var r: float = maxf(radius, 0.05)
	var dur: float = clampf(duration, 0.10, RING_MAX_TIME)
	_hoop(host, pos, color, r * 0.14, r, dur, RING_MAX_ALPHA, 4)
	_hoop(host, pos, color, r * 0.10, r * 0.62, dur * 0.66, 0.28, 5, 0.55)
	ground_ripple(host, pos, color, r * 1.15, dur, 0.0)
	flash(host, pos, color, minf(maxf(r * 0.9, 0.8), FLARE_MAX_ENERGY), dur * 0.5)

# ---------------------------------------------------------------- flashes ----

## A short pulse of LIGHT, and a small hot core to say where it came from.
##
## This call did more damage to the QA frames than the rest of the file put
## together, and the reason is worth writing down: it drew a BILLBOARD at albedo
## x2.6, alpha 0.95, scaling to `0.70 + 0.30 * energy` — at the energy 5 that
## world3d.gd passes for a debt incident, a 2.2-unit overbright disc, roughly a
## fifth of the screen, pinned in front of the player. That is the white hole in
## `combat_dependency_district.png`. It also lit the room with a 6-energy omni
## for nearly half a second, which is longer than the event it punctuates.
##
## What it does now: the LIGHT is the effect (a room reacting to a blow is the
## cheapest way to make a hit physical, and light respects the floor's own
## material instead of painting over it), capped at `FLARE_MAX_ENERGY` = 1.2 and
## fully decayed inside `FLARE_MAX_TIME` = 0.15s. The sprite survives only as a
## SMALL core — never larger than a character's head, never above alpha 0.45 —
## so a hit still has a legible origin point on a lit floor. It cannot fill the
## screen at any `energy` a caller passes, because its size no longer scales
## with energy past a hard ceiling.
static func flash(host: Node, pos: Vector3, color: Color, energy: float = 4.0, duration: float = 0.2) -> void:
	var root := _fx_root(host)
	if root == null:
		return
	# One number drives both layers, and both are clamped to a beat, not a mood.
	var e: float = clampf(energy, 0.2, FLARE_MAX_ENERGY)
	var dur: float = clampf(duration, 0.05, FLARE_MAX_TIME)
	# Hue first (LAW 2), then brightness, then the ground plane. A flash is the
	# only FX family that puts REAL light on the floor, so an out-of-palette hue
	# here washes a whole tile in it — the loudest way to break a three-hue room.
	var lawful := _law(color)
	var at := _grounded(pos)
	var shapes := _bin(root, BIN_SHAPES, MAX_SHAPES)
	# Without the soft dot the quad is a hard SQUARE — worse than no sprite.
	# FxLib.flash makes the same call; the light below still fires.
	var dot := FxLib.glow_dot()
	if shapes != null and dot != null:
		var mi := MeshInstance3D.new()
		mi.mesh = _sprite_quad()
		var core := _hot(lawful, FLASH_CEILING, 0.35, 0.45)
		var mat := additive_material(core, dot, true)
		mat.render_priority = 6
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shapes.add_child(mi)
		mi.global_position = at
		# Absolute ceilings, in world units, on a 0.9u-tall character: 0.14u of
		# core growing to at most 0.46u. `energy` may vary it inside that window
		# and may not leave it.
		var s0: float = 0.14 + 0.03 * e
		var s1: float = clampf(0.22 + 0.10 * e, 0.24, 0.46)
		mi.scale = Vector3.ONE * s0
		var tw := mi.create_tween()
		tw.tween_property(mi, "scale", Vector3.ONE * s1, dur) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		# Falling from frame one (EASE_OUT): the core is brightest when it is
		# smallest, which is what makes it read as a spark rather than a bloom.
		tw.parallel().tween_property(mat, "albedo_color:a", 0.0, dur).set_ease(Tween.EASE_OUT)
		tw.tween_callback(mi.queue_free)
	# Lights are the expensive layer (each is a real light in the clustered
	# pass), so they get the tightest bin of all.
	var flares := _bin(root, BIN_FLARES, MAX_FLARES)
	if flares == null:
		return
	var light := OmniLight3D.new()
	# The blow's own hue, gated and then budgeted. FxLib.vivid() would push a
	# muted region accent to full chroma and drop a saturated wash across the
	# floor — LAW 2 allows three hues per scene and a flash is not entitled to
	# a fourth, whichever direction the fourth arrives from.
	light.light_color = _capped(lawful, 1.0)
	light.light_energy = 0.0
	light.omni_range = clampf(1.6 + e * 0.9, 1.8, 3.2)
	# NOT a higher exponent than the §7 recipe's 1.6: `omni_attenuation` is the
	# inverse-power decay, so raising it makes the spot UNDER the light hotter
	# while the pool shrinks — the opposite of "pools where the hit happened".
	# The pool is shaped by hanging the light higher (FLARE_HEIGHT) instead.
	light.omni_attenuation = FLARE_ATTENUATION
	light.shadow_enabled = false
	flares.add_child(light)
	light.global_position = at + Vector3(0.0, FLARE_HEIGHT, 0.0)
	var lt := light.create_tween()
	lt.tween_property(light, "light_energy", e, dur * 0.18).set_ease(Tween.EASE_OUT)
	lt.tween_property(light, "light_energy", 0.0, dur * 0.82).set_ease(Tween.EASE_IN)
	lt.tween_callback(light.queue_free)

# ------------------------------------------------------------------ text ----

## Snap any requested glyph colour onto LAW 2's three global constants.
##
## Callers across enemy3d/player3d/projectile3d pass fourteen different hues —
## #A8FF3E, #8B5CF6, #FFB020, #7DFFF0, #C9D6F2, #F4F9FF, #7C8BB0 and more — and
## LAW 2 allows a scene THREE. Floating text is the worst offender because it is
## the one FX family that is always on screen during a fight, so a rainbow here
## is a rainbow in every combat frame. The signature is frozen and the call
## sites are not mine, so the snap happens here.
##
## The rule is the bible's own semantics, not nearest-neighbour colour maths:
## GOLD is currency and reward, HOSTILE is damage the player took, everything
## else — enemy tells, comedy, dialogue barks, status — is TEXT. A caller's hue
## is only evidence of which of the three it MEANT.
static func _glyph_color(color: Color) -> Color:
	var mx: float = maxf(color.r, maxf(color.g, color.b))
	if mx <= 0.001:
		return GameTheme.TEXT
	# Normalise first: several callers pass overbright values (Color(2.4, ...)),
	# where raw channel comparisons say nothing about the hue they intended.
	var r: float = color.r / mx
	var g: float = color.g / mx
	var b: float = color.b / mx
	# Red-dominant with BOTH other channels suppressed: damage, hostility, the
	# boss's tell. The blue bound is tight (0.50) on purpose — it is what keeps
	# the player's own magenta trace beam (#FF2D95, blue at 0.58) out of the
	# hostile bucket, where it would have told the player they were being hurt
	# by their own ability.
	if r > 0.90 and g < 0.62 and b < 0.50:
		return GameTheme.RED
	# GOLD is #FFD34D and nothing else (LAW 2: "tokens/currency only"). Every
	# caller that MEANS currency passes that exact hex (Token2D.GOLD,
	# GameTheme.GOLD, player3d.COL_GOLD, enemy3d's reward barks), so the window
	# is a tight box around its normalised value (1.0, 0.83, 0.30). The warm
	# yellows that are NOT money — the enemy damage number (1.0, 0.92, 0.35),
	# the rate limiter's #FFB020, the stackoverflow accent #E8C46B — all fall
	# outside it and read as TEXT, which is what a number that is not a payout
	# should be.
	if r > 0.96 and g > 0.76 and g < 0.90 and b > 0.20 and b < 0.42:
		return GameTheme.GOLD
	return GameTheme.TEXT

## Floating combat text (damage numbers, comedy glyphs) — SCREEN-SPACE.
##
## LABEL3D IS RETIRED, and it is worth saying why, because the previous round
## worked hard to make one look right and still could not. A Label3D is a
## textured quad in the world, so its glyphs are only aliased while the world-to-
## screen mapping happens to sit at 1:1 — a mapping that depends on the rig's
## FOV, its distance, its aspect mode and the capture resolution, all four of
## which moved this round. The `pixel_size` maths that chased that ratio is gone
## with it. Look at `combat_dependency_district.png`: the "-10" at (480, 172) is
## a thin, resampled, half-transparent red smear sitting at a completely
## different apparent size from the "!" at (1770, 350) — two type sizes and two
## rasterisations in one frame, which is LAW 1's headline defect. A Label3D also
## cannot clamp to the screen edge, cannot avoid its neighbours, and happily
## draws a number underneath the HUD.
##
## So a glyph is now exactly what the HUD is: a plain 2D `Label` in
## `GameTheme.ui_font()` at 14 or 18, with LAW 4's 1px black drop shadow, living
## on the ScreenLabels canvas — ONE typographic system for every word in the
## game. The only thing this call still puts in the 3D world is an empty ANCHOR
## at `pos`; ScreenLabels unprojects it every frame, clamps the label into the
## HUD safe area and stacks it off the other captions, which is what a damage
## number needed all along.
##
## Everything else is a budget: `size` collapses onto the two allowed sizes,
## `color` is snapped to LAW 2's three global constants (TEXT, GOLD for a
## payout, HOSTILE for damage taken), and `duration` and `rise` are capped so a
## glyph is a beat (<= 0.8s) rather than a banner.
##
## PAUSE-SAFE (HANDOVER gotcha 4): the anchor and its tween process while the
## tree is paused, so a modal opening mid-flight cannot leave a number pinned to
## the screen — the anchor still reaches its own `queue_free`, and the label
## goes with it (ScreenLabels frees a caption when its owner leaves the tree).
static func glyph(host: Node, pos: Vector3, text: String, color: Color, size: int = 24, duration: float = 0.9, rise: float = 1.2) -> void:
	if text.is_empty():
		return
	var bin := _bin(_fx_root(host), BIN_GLYPHS, MAX_GLYPHS)
	if bin == null:
		return
	bin.process_mode = Node.PROCESS_MODE_ALWAYS
	var anchor := Node3D.new()
	anchor.process_mode = Node.PROCESS_MODE_ALWAYS
	bin.add_child(anchor)
	# A hand's width of XZ jitter so two numbers in the same frame do not start
	# on the same pixel; ScreenLabels' own stacking takes it from there.
	anchor.global_position = pos + Vector3(randf_range(-0.12, 0.12), 0.0, randf_range(-0.08, 0.08))
	# LAW 1: two sizes in the world, 14 and 18, and no others — the 26 of a
	# heading belongs to the region name and nothing else. Which of the two is
	# decided by the CONTENT first — a NUMBER is 14 and a WORD is 18 — with the
	# `size` a caller passed demoted to the tie-breaker it always was. In
	# `combat_dependency_district.png` that ordering is exactly backwards: "-10"
	# is set larger than the sentence beside it, which is why a transient number
	# reads as the loudest thing on the player.
	var fs: int = _glyph_size(text, size)
	# Height 0 — the anchor is already where the text should point.
	# KEEP_CLEAR_PRIORITY is the point of this number: a glyph is the one world
	# text that may stay inside the disc ScreenLabels keeps clear around the
	# player, and it is lifted out of that disc rather than dropped, so a hit
	# you took is always readable while the ambient captions around it are not.
	var lbl := ScreenLabels.attach(anchor, text, fs, _glyph_color(color), 0.0,
		ScreenLabels.KEEP_CLEAR_PRIORITY)
	if lbl == null:
		anchor.queue_free()
		return
	var dur: float = clampf(duration, 0.12, GLYPH_MAX_TIME)
	var lift: float = clampf(rise, 0.0, GLYPH_MAX_RISE)
	# Held opaque for the first half, then gone: a number has to be READ, and a
	# glyph fading from frame one is the thing that makes damage numbers mush.
	# Driven through a GUARDED method rather than a property tween because the
	# label lives under the ScreenLabels canvas, and a region change takes that
	# canvas with it while this tween's own node is still alive. (A lambda in a
	# static function has no `self`; this one touches nothing but its capture.)
	var fade := func(a: float) -> void:
		if is_instance_valid(lbl):
			lbl.modulate = Color(1.0, 1.0, 1.0, a)
	# LAW 9 asks for small motion: it rises a little and it leaves. No scale pop
	# — an aliased face resampled off its own pixel grid every frame of a
	# TRANS_BACK overshoot is the smeared text LAW 1 is about.
	var tw := anchor.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(anchor, "global_position",
		anchor.global_position + Vector3.UP * lift + _glyph_drift(bin), dur) \
		.set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(fade, 1.0, 0.0, dur * 0.5) \
		.set_delay(dur * 0.5).set_ease(Tween.EASE_IN)
	tw.tween_callback(anchor.queue_free)

## 14 for a NUMBER, 18 for a WORD (LAW 1 allows exactly those two sizes in the
## world, and the frames had them the wrong way round — "-10" set larger than
## the sentence beside it).
##
## A word is any string containing a LETTER: "CRIT", "cache miss", "session
## expired". A number is a string with a digit and no letters: "-10", "+5",
## "429". A string that is neither — the bare "!" and "?" of a telegraph — has
## no content to judge, so the caller's `hint` decides, split at the midpoint of
## the 12..30 range the thirty-odd call sites pass.
##
## Letters are detected with `to_lower() != to_upper()`, which is true of cased
## characters in every alphabet Godot's String handles and false for digits,
## signs, punctuation and the middle dot.
static func _glyph_size(text: String, hint: int) -> int:
	var digits := false
	for i in text.length():
		var c := text[i]
		if c.to_lower() != c.to_upper():
			return ScreenLabels.BODY
		if c >= "0" and c <= "9":
			digits = true
	if digits:
		return ScreenLabels.SMALL
	return ScreenLabels.BODY if hint >= 17 else ScreenLabels.SMALL

## The sideways component of the rise: up-LEFT then up-RIGHT, alternating per
## call. "Left" and "right" are the CAMERA's, taken from the live rig's basis, so
## the fan is a fan on screen and not a diagonal that changes meaning with the
## isometric yaw. With no camera (a headless test, a scene mid-swap) the drift is
## simply zero — the glyph still rises, which is all the callers promise.
##
## `host` is untyped: the iron rule is never to type a parameter that could
## receive a freed instance, because the binding itself is the error and it
## happens before any guard inside can run.
static func _glyph_drift(host) -> Vector3:
	_glyph_flip = not _glyph_flip
	if not is_instance_valid(host):
		return Vector3.ZERO
	# The cast happens AFTER the validity check, never at the parameter.
	var node := host as Node
	if node == null or not node.is_inside_tree():
		return Vector3.ZERO
	var vp := node.get_viewport()
	if vp == null:
		return Vector3.ZERO
	var cam := vp.get_camera_3d()
	if cam == null:
		return Vector3.ZERO
	var side := cam.global_transform.basis.x
	if side.length_squared() < 0.000001:
		return Vector3.ZERO
	return side.normalized() * (GLYPH_DRIFT if _glyph_flip else -GLYPH_DRIFT)

# ----------------------------------------------------------- afterimages ----

static func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for c: Node in node.get_children():
		var found := _find_skeleton(c)
		if found != null:
			return found
	return null

static func _collect_meshes(node: Node, out: Array[MeshInstance3D], limit: int) -> void:
	if out.size() >= limit:
		return
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for c: Node in node.get_children():
		_collect_meshes(c, out, limit)

## Paint every mesh in a duplicated subtree with the ghost material and delete
## everything that is not geometry. A duplicated AnimationPlayer would keep
## animating the smear, and a duplicated light would double the room's lighting
## for a third of a second — both are bugs, and both are one `is` check away.
static func _paint_walk(node: Node, mat: Material, doomed: Array[Node]) -> void:
	for c: Node in node.get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_paint_walk(c, mat, doomed)
		elif c is Light3D or c is GPUParticles3D or c is CPUParticles3D \
				or c is Camera3D or c is AnimationPlayer or c is AnimationTree \
				or c is CollisionObject3D:
			doomed.append(c)
		else:
			_paint_walk(c, mat, doomed)

## The smear a fast thing leaves behind: a frozen, overbright copy of `src`'s
## geometry that fades on the world instead of on the mover.
##
## Kenney characters are RIGGED, and a bare mesh copy of a skinned mesh renders
## its BIND POSE — a T-posed ghost trailing a running character. So when there
## is a Skeleton3D, the skeleton subtree is duplicated instead: `duplicate()`
## copies the bone poses as they are right now, and the child meshes' `skeleton`
## NodePaths resolve inside the copy, which yields a correctly POSED, frozen
## ghost. Flags are 0 — no signals, no groups, no scripts, shared subresources,
## so the copy costs a node and not a mesh.
static func afterimage(host: Node, src: Node3D, color: Color, duration: float = 0.3) -> void:
	if not _ok(src):
		return
	var bin := _bin(_fx_root(host), BIN_GHOSTS, MAX_GHOSTS)
	if bin == null:
		return
	# A smear is the DIMMEST thing this file draws: it is a hint that something
	# moved fast, and at albedo x1.5 / alpha 0.5 it was instead a second, glowing
	# copy of the character standing next to the first one.
	var ghost_tint := _capped(_law(color), GHOST_CEILING)
	var mat := additive_material(Color(ghost_tint.r, ghost_tint.g, ghost_tint.b, 0.30))
	mat.render_priority = 2
	var ghost := Node3D.new()
	bin.add_child(ghost)
	var skel := _find_skeleton(src)
	if skel != null:
		ghost.global_transform = skel.global_transform
		var dup := skel.duplicate(0)
		if dup is Node3D:
			var d3 := dup as Node3D
			d3.transform = Transform3D.IDENTITY
			ghost.add_child(d3)
			var doomed: Array[Node] = []
			_paint_walk(d3, mat, doomed)
			for n: Node in doomed:
				var parent := n.get_parent()
				if parent != null:
					parent.remove_child(n)
				n.queue_free()
		elif dup != null:
			dup.free()
	else:
		ghost.global_transform = src.global_transform
		var meshes: Array[MeshInstance3D] = []
		_collect_meshes(src, meshes, 24)
		for mi: MeshInstance3D in meshes:
			if mi.mesh == null:
				continue
			var copy := MeshInstance3D.new()
			copy.mesh = mi.mesh
			copy.material_override = mat
			copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ghost.add_child(copy)
			copy.global_transform = mi.global_transform
	if ghost.get_child_count() == 0:
		ghost.queue_free()
		return
	var dur: float = clampf(duration, 0.05, 0.35)
	var tw := ghost.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, dur).set_ease(Tween.EASE_OUT)
	# Relative to the ghost's OWN scale: it inherited the model's fit scale
	# (fit_height puts a Kenney character at ~1.3x), and an absolute 1.06 would
	# shrink the smear instead of swelling it.
	tw.parallel().tween_property(ghost, "scale", ghost.scale * 1.06, dur)
	tw.tween_callback(ghost.queue_free)

# ----------------------------------------------------------------- beams ----

## A hard bolt of light: an accent shaft with a paler core down the middle, both
## collapsing to nothing together so it reads as one beam.
##
## The core used to be `Color(2.8, 2.8, 2.8, 0.95)` — a near-opaque overbright
## WHITE box drawn the full length of the shot. Same geometry, same collapse,
## budgeted colour: the core is now the shaft's own hue lifted most of the way
## toward its ceiling, which still reads as the hot centre of a bolt without
## introducing a fourth hue or a bloom trail across the room.
static func beam(host: Node, from: Vector3, to: Vector3, color: Color, width: float = 0.08, duration: float = 0.15) -> void:
	var delta := to - from
	var length := delta.length()
	if length < 0.01:
		return
	var bin := _bin(_fx_root(host), BIN_SHAPES, MAX_SHAPES)
	if bin == null:
		return
	var mid := from + delta * 0.5
	# `look_at` errors out when the direction and the up vector are parallel —
	# rare for a beam on the XZ plane, fatal for a vertical one.
	var up := Vector3.UP
	if absf(delta.normalized().dot(Vector3.UP)) > 0.995:
		up = Vector3.FORWARD
	var dur: float = clampf(duration, 0.04, 0.20)
	var w0: float = maxf(width, 0.005)
	# Gated once, outside the loop: both passes have to agree about the hue or
	# the "hot core" reads as a second beam in a second colour.
	var lawful := _law(color)
	for pass_i: int in [0, 1]:
		var w: float = w0 if pass_i == 0 else w0 * 0.4
		var shaft := _capped(lawful, BEAM_CEILING)
		var col := Color(shaft.r, shaft.g, shaft.b, 0.32)
		if pass_i == 1:
			col = _hot(lawful, BEAM_CEILING, 0.70, 0.55)
		var mi := MeshInstance3D.new()
		mi.mesh = _box_mesh()
		var mat := additive_material(col)
		mat.render_priority = 5 + pass_i
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bin.add_child(mi)
		mi.global_position = mid
		mi.look_at(to, up)   # -Z points down the beam; the box is symmetric
		mi.scale = Vector3(w, w, length)
		var tw := mi.create_tween()
		tw.tween_property(mi, "scale", Vector3(w * 0.08, w * 0.08, length), dur).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(mat, "albedo_color:a", 0.0, dur)
		tw.tween_callback(mi.queue_free)

# -------------------------------------------------------------- dissolve ----

## Death dissolve for a model root; must free nothing itself.
##
## Every MeshInstance3D under `node` gets a ShaderMaterial built from what its
## own surface was already showing — albedo texture, tint and vertex-colour
## flag copied across — so a dissolving Kenney character keeps its colormap
## right up to the moment it stops existing. Every uniform is SEEDED before the
## tween (HANDOVER gotcha 2), and the sweep runs through a single
## `tween_method` rather than one tween per surface, so a twelve-surface model
## still costs one tween.
##
## The tween is created on `node`, so if the caller frees the corpse early the
## tween dies with it — which is correct: the corpse's own teardown wins.
##
## REVERSIBLE. Not every dissolved model is a corpse: the PLAYER dissolves on
## death and is then `respawn()`ed as the SAME node, and a model whose every
## fragment is still being discarded is an invisible protagonist for the rest
## of the run. So the materials each surface wore before the burn are kept on
## the mesh (meta), `undissolve()` puts them back, and a burned model heals
## ITSELF the next time its AnimationPlayer starts a clip after the burn has
## finished — which is exactly what a respawn does ("idle") and exactly what a
## corpse never does (its "die" clip starts before the burn ends, and the hook
## ignores anything that starts before then). Callers that rebuild or free the
## model need to do nothing; callers that reuse it should still call
## `undissolve()` at the point they consider the body alive again.
static func dissolve(node: Node3D, color: Color, duration: float = 0.6) -> void:
	if not _ok(node):
		return
	# A second burn on a body that never healed (died twice without a respawn
	# path in between) starts from the original surfaces, not from nothing.
	if node.has_meta(META_DISSOLVED):
		undissolve(node)
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(node, meshes, 32)
	if meshes.is_empty():
		return
	var dur: float = maxf(duration, 0.05)
	var sh := _shader(DISSOLVE_PATH)
	if sh == null:
		# Degrade to a pop-fade rather than to nothing at all — at budget, so a
		# missing shader cannot turn a death into a white silhouette either.
		var burn := _capped(_law(color), BURN_CEILING)
		var fade_mat := additive_material(Color(burn.r, burn.g, burn.b, 0.55))
		for mi: MeshInstance3D in meshes:
			_stash_materials(mi)
			mi.material_override = fade_mat
		_mark_dissolved(node)
		var ft := node.create_tween()
		ft.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		ft.tween_property(fade_mat, "albedo_color:a", 0.0, dur)
		ft.tween_callback(func() -> void:
			if is_instance_valid(node):
				node.set_meta(Fx3D.META_DISSOLVE_DONE, true))
		return
	var mats: Array[ShaderMaterial] = []
	# Gated ONCE. A twelve-surface Kenney character would otherwise ask the
	# palette gate the same question twelve times for one death, and every
	# surface of one body has to burn in one colour in any case.
	var burn_edge := _capped(_law(color), BURN_CEILING)
	for mi: MeshInstance3D in meshes:
		var mesh := mi.mesh
		if mesh == null:
			continue
		var aabb := mi.get_aabb()
		_stash_materials(mi)
		for i in mesh.get_surface_count():
			var src: Material = mi.get_active_material(i)
			var tex: Texture2D = null
			var tint := Color.WHITE
			var vcol: float = 0.0
			# BaseMaterial3D, not StandardMaterial3D: glTF normally imports to
			# StandardMaterial3D but an ORM-textured surface arrives as
			# ORMMaterial3D, and a type test that misses it would burn the model
			# away as a featureless white silhouette.
			if src is BaseMaterial3D:
				var sm := src as BaseMaterial3D
				tex = sm.albedo_texture
				tint = sm.albedo_color
				# glTF sets this whenever the mesh carries COLOR_0; a kit that
				# paints with vertex colours must burn in those colours.
				vcol = 1.0 if sm.vertex_color_use_as_albedo else 0.0
			var m := ShaderMaterial.new()
			m.shader = sh
			m.set_shader_parameter("albedo_tex", tex if tex != null else white_texture())
			m.set_shader_parameter("albedo_color", tint)
			m.set_shader_parameter("use_vertex_color", vcol)
			m.set_shader_parameter("progress", 0.0)
			# Budgeted, not vivid, and a narrower, dimmer burn line. The burn edge
			# is a rim on a dying silhouette (LAW 7: one tell, no glow pass), not
			# a light source: at edge_width 0.16 and emission 5.0 a corpse was
			# briefly the brightest object in the region.
			m.set_shader_parameter("edge_color", burn_edge)
			m.set_shader_parameter("edge_width", 0.10)
			m.set_shader_parameter("noise_scale", 9.0)
			# 1.15 x BURN_CEILING 0.85 = 0.98 at the cut: the burn line stays
			# under the bloom threshold from the first frame to the last.
			m.set_shader_parameter("emission_energy", 1.15)
			m.set_shader_parameter("bottom_up", 0.45)
			m.set_shader_parameter("base_y", aabb.position.y)
			m.set_shader_parameter("height", maxf(aabb.size.y, 0.001))
			m.set_shader_parameter("surface_roughness", 0.9)
			mi.set_surface_override_material(i, m)
			mats.append(m)
		# A whole-mesh override (the capsule fallbacks, a tint pass) WINS over
		# surface overrides, so left in place it would hide the burn entirely.
		# It was stashed above and comes back with `undissolve()`.
		mi.material_override = null
	if mats.is_empty():
		return
	_mark_dissolved(node)
	# One tween drives every surface. The lambda touches nothing but its own
	# captures and locals on purpose: a lambda inside a static function has no
	# `self`, and an unqualified member call there fails to resolve and takes the
	# whole class down with it (see CombatFx.kill_pop's note on the same hazard).
	var apply := func(v: float) -> void:
		for m: ShaderMaterial in mats:
			if is_instance_valid(m):
				m.set_shader_parameter("progress", v)
	# Pause-safe: a death modal must not leave a half-burned body frozen on
	# screen, and a corpse finishing its burn behind a menu is the right look.
	var tw := node.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_method(apply, 0.0, 1.0, dur)
	tw.tween_callback(func() -> void:
		if is_instance_valid(node):
			node.set_meta(Fx3D.META_DISSOLVE_DONE, true))

## Put back every material `dissolve()` replaced on the meshes under `node`,
## and disarm the self-heal hook. Safe to call on a node that was never
## dissolved, or twice.
static func undissolve(node: Node3D) -> void:
	if node == null or not is_instance_valid(node):
		return
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(node, meshes, 32)
	for mi: MeshInstance3D in meshes:
		_restore_materials(mi)
	var ap := _find_anim_player(node)
	if ap != null and ap.has_meta(META_HEAL_HOOK):
		var cb: Callable = ap.get_meta(META_HEAL_HOOK)
		if ap.animation_started.is_connected(cb):
			ap.animation_started.disconnect(cb)
		ap.remove_meta(META_HEAL_HOOK)
	if node.has_meta(META_DISSOLVED):
		node.remove_meta(META_DISSOLVED)
	if node.has_meta(META_DISSOLVE_DONE):
		node.remove_meta(META_DISSOLVE_DONE)

## True while `node` wears dissolve materials (burning or burned out).
static func is_dissolved(node: Node3D) -> bool:
	return node != null and is_instance_valid(node) and node.has_meta(META_DISSOLVED)

## Remember what a mesh wore before the burn: its whole-mesh override and its
## per-surface overrides (nulls included — null means "the mesh's own").
static func _stash_materials(mi: MeshInstance3D) -> void:
	if mi.has_meta(META_PREV_SURFACES):
		return   # already stashed by an earlier burn that never healed
	var prev: Array = []
	if mi.mesh != null:
		for i in mi.mesh.get_surface_count():
			prev.append(mi.get_surface_override_material(i))
	mi.set_meta(META_PREV_SURFACES, prev)
	mi.set_meta(META_PREV_OVERRIDE, mi.material_override)

static func _restore_materials(mi: MeshInstance3D) -> void:
	if not mi.has_meta(META_PREV_SURFACES):
		return
	var prev: Array = mi.get_meta(META_PREV_SURFACES, [])
	if mi.mesh != null:
		var n: int = mini(prev.size(), mi.mesh.get_surface_count())
		for i in n:
			mi.set_surface_override_material(i, prev[i] as Material)
	mi.material_override = mi.get_meta(META_PREV_OVERRIDE, null) as Material
	mi.remove_meta(META_PREV_SURFACES)
	if mi.has_meta(META_PREV_OVERRIDE):
		mi.remove_meta(META_PREV_OVERRIDE)

static func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for c: Node in node.get_children():
		var found := _find_anim_player(c)
		if found != null:
			return found
	return null

## Flag the node and arm the self-heal: the next clip that STARTS after the
## burn has finished restores the original materials. Persistent (not one-shot)
## on purpose — a corpse's "die" clip starts during the burn and must be
## ignored, and a one-shot would be spent on it. The hook is stored on the
## AnimationPlayer so `undissolve()` can find and remove it. Handler arity
## matches `animation_started(anim_name: StringName)` exactly (gotcha 3).
static func _mark_dissolved(node: Node3D) -> void:
	node.set_meta(META_DISSOLVED, true)
	if node.has_meta(META_DISSOLVE_DONE):
		node.remove_meta(META_DISSOLVE_DONE)
	var ap := _find_anim_player(node)
	if ap == null or ap.has_meta(META_HEAL_HOOK):
		return
	var heal := func(_anim_name: StringName) -> void:
		if not is_instance_valid(node) or not node.has_meta(Fx3D.META_DISSOLVE_DONE):
			return
		Fx3D.undissolve(node)
	ap.animation_started.connect(heal)
	ap.set_meta(META_HEAL_HOOK, heal)

# ------------------------------------------------------- shader factories ----

## A ready-to-use portal disc material (assets/shaders3d/portal_vortex.gdshader).
## Returns null when the shader is missing, so every caller must tolerate null.
## Put it on a QuadMesh or CylinderMesh face inside the `mini-dungeon/gate`
## frame; drive `phase` and `core_heat` from the portal script if it wants the
## near-approach response, or leave them and the swirl turns on its own.
##
## FINDABLE, NOT DOMINANT (LAW 4). A portal is one of LAW 3's two motivated
## lights, so it is allowed to be bright — and it was taking the licence far
## past the budget: energy 2.6 with a rim at alpha 0.88 made a doorway that
## owned whichever third of the frame it stood in. The defaults below hold the
## swirl under the bloom threshold and let the RIM — a thin hot lip at the mouth
## of the gate — do the finding. Note that portal3d.gd seeds only the uniforms
## it names and leaves `energy`, `rim_alpha` and `levels` at the SHADER's own
## defaults, which is why those are restrained in both places.
##
## `color` IS the destination's accent (3D_BIBLE §7: a gate is coloured by where
## it goes, which is the one piece of wayfinding a doorway can carry on its own).
## So this is the ONE helper in the file that does not run its colour through
## `_law` — gating it would paint every exit the room's own hue and throw that
## information away. What it does instead is put the hue on the same brightness
## budget as everything else, and refuse the shader's own lilac uniform default:
## `hue_color` is seeded unconditionally, so a caller that passes black gets
## TEXT and never the (0.55, 0.36, 0.96) that portal_vortex.gdshader declares.
static func portal_material(color: Color, arms: float = 2.0, speed: float = 0.65) -> ShaderMaterial:
	var sh := _shader(PORTAL_PATH)
	if sh == null:
		return null
	var m := ShaderMaterial.new()
	m.shader = sh
	var hue := _capped(color, PORTAL_HUE_CEILING)
	if maxf(color.r, maxf(color.g, color.b)) <= 0.001:
		hue = GameTheme.TEXT
	m.set_shader_parameter("hue_color", Color(hue.r, hue.g, hue.b, 1.0))
	# Slower than the old 0.65: LAW 9 wants small motion at rest, and a doorway
	# spinning fast enough to notice is a doorway the eye cannot leave.
	m.set_shader_parameter("speed", clampf(speed, 0.05, 0.45))
	m.set_shader_parameter("arms", arms)
	m.set_shader_parameter("phase", 0.0)
	m.set_shader_parameter("seed", randf() * 6.283)
	m.set_shader_parameter("core_heat", 0.65)
	# A wider dark eye: the deep tone at the centre is what makes the disc read
	# as an OPENING rather than as a lit sign lying in a doorway.
	m.set_shader_parameter("horizon", 0.28)
	# Explicitly under the ceiling rather than incidentally under it: a later
	# hand raising this number has to raise PORTAL_MAX_ENERGY with it, and that
	# constant carries the reason it exists.
	m.set_shader_parameter("energy", minf(1.1, PORTAL_MAX_ENERGY))
	m.set_shader_parameter("rim_alpha", 0.55)
	# More bands, each a smaller step: the quantiser still reads as "drawn",
	# without the six hard rings that made the swirl the loudest edge on screen.
	m.set_shader_parameter("levels", 8.0)
	m.render_priority = 1
	return m

## Holographic signage material (assets/shaders3d/hologram3d.gdshader): a quiet
## fresnel emissive with a barely-there scan, additive, for projected signs and
## display walls. Pass a texture to project artwork through it. Null when the
## shader is missing.
##
## LAW 3 is blunt about this one: signs do not glow. A hologram is only ever
## allowed on screens and lamps — one of the two motivated lights — and then
## only on its LIT SURFACE. So the loudness is gone: the scan is a 14% ripple
## instead of a 28% one at a third of the density (42 bands over a wall was a
## moire pattern, not a projection), the dropout glitch fires a fifth as often,
## and the sheet is dimmer and more transparent so the wall behind it survives.
static func hologram_material(color: Color, energy: float = 2.2, tex: Texture2D = null) -> ShaderMaterial:
	var sh := _shader(HOLOGRAM_PATH)
	if sh == null:
		return null
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("tint", _capped(_law(color), 0.95))
	m.set_shader_parameter("scan_speed", 0.6)
	m.set_shader_parameter("scan_density", 14.0)
	m.set_shader_parameter("alpha_base", 0.30)
	m.set_shader_parameter("fresnel_power", 2.6)
	# The caller's `energy` is a request, not an instruction. The shader's
	# fragment weights sum to 1.22 and its ALPHA_MAX is 0.70, so under additive
	# blending the most an edge-on fragment can ADD to the frame is
	# 0.95 * 1.22 * energy * 0.70 — which stays under 1.0 only for energy <=
	# 1.15. That is the shader's own ENERGY_MAX; the default 2.2 sailed past it.
	m.set_shader_parameter("energy", clampf(energy, 0.3, 1.15))
	m.set_shader_parameter("flicker", 0.10)
	m.set_shader_parameter("holo_tex", tex if tex != null else white_texture())
	m.set_shader_parameter("use_texture", 1.0 if tex != null else 0.0)
	m.render_priority = 1
	return m

# ------------------------------------------------------------ composites ----

## THE hit, in one call — the 3D twin of CombatFx.impact(). Every landed blow
## can route through here so hits read the same way whoever threw them: a small
## hot core, sparks thrown BACK along the blow (they come off the surface that
## was struck, not out of the middle of the enemy), a ring, and trauma.
## `power` is severity normalised so 1.0 is "a solid hit"; `dir` is the blow's
## travel direction in world space.
##
## The shape of the hit is unchanged — four beats, same timing, same geometry.
## What changed is that a crit no longer adds a SECOND full-strength white ring
## on top of the first; it gets a paler, faster one in the same hue, which is
## what "crit" needed to say and not one hue more.
static func impact(host: Node, pos: Vector3, dir: Vector3, color: Color,
		power: float = 1.0, crit: bool = false) -> void:
	if not _ok(host):
		return
	var p: float = clampf(power, 0.35, 2.2)
	var big: float = 1.65 if crit else 1.0
	# Sparks and the hot core come off the surface that was STRUCK — a hand's
	# width back along the blow — not out of the middle of the enemy.
	var back := Vector3.ZERO
	if dir.length_squared() > 0.000001:
		back = -dir.normalized()
	flash(host, pos + back * 0.12, color, (1.0 + 0.7 * p) * big, 0.13)
	ring(host, pos, color, 0.12, (0.42 + 0.30 * p) * big, 0.22 + 0.06 * p)
	burst(host, pos + back * 0.20, color, int((6.0 + 5.0 * p) * (1.5 if crit else 1.0)),
		(3.2 + 2.2 * p) * (1.35 if crit else 1.0), 0.30)
	if crit:
		_hoop(host, pos, color, 0.08, 0.34 + 0.55 * p, 0.19, 0.30, 5, 0.60)
	var tree := host.get_tree()
	add_trauma(tree, clampf(0.10 * p, 0.05, 0.30) * (1.9 if crit else 1.0))
	if crit or p >= 1.9:
		hit_stop(tree, (0.07 if crit else 0.15), (0.055 if crit else 0.030))

## The payoff for a KILL, as opposed to a hit: the world implodes toward the
## corpse for one beat, then detonates ~90ms later. Long enough to read as cause
## and effect, short enough to still feel like one event. Nothing here touches
## the corpse, so the dying thing can leave on its own schedule.
static func kill_pop(host: Node, pos: Vector3, color: Color, power: float = 1.0) -> void:
	if not _ok(host):
		return
	var p: float = clampf(power, 0.5, 2.5)
	# The implosion is the blow's own GATED hue lifted toward hot, not white: a
	# pure white converging hoop over a mid-value floor was the brightest single
	# element in the combat frames, and it arrives right before the detonation.
	# `_hoop` does the lifting so the palette gate runs before it, not after.
	_hoop(host, pos, color, 1.10 * p, 0.10, 0.13, 0.42, 5, 0.50)
	var t := host.create_tween()
	t.tween_interval(0.09)
	# Lambdas in a static function have no `self`; every call inside is either a
	# capture or an explicitly qualified static (HANDOVER gotcha 6b).
	t.tween_callback(func() -> void:
		Fx3D.shockwave(host, pos, color, 1.5 * p, 0.40)
		Fx3D.burst(host, pos, color, int(11.0 * p), 5.0 * p, 0.45))

# ------------------------------------------------------------- forwarding ----

## Forwarded to the camera rig (group "camera_fx") when present.
static func add_trauma(tree: SceneTree, amount: float) -> void:
	if tree == null:
		return
	var cam := tree.get_first_node_in_group("camera_fx")
	if cam and cam.has_method("add_trauma"):
		cam.add_trauma(amount)

static func punch_zoom(tree: SceneTree, amount: float = 0.04) -> void:
	if tree == null:
		return
	var cam := tree.get_first_node_in_group("camera_fx")
	if cam and cam.has_method("punch_zoom"):
		cam.punch_zoom(amount)

## Engine-wide time dip; the 2D helper is renderer-agnostic, so reuse it.
static func hit_stop(tree: SceneTree, time_scale: float = 0.05, duration: float = 0.04) -> void:
	FxLib.hit_stop(tree, time_scale, duration)
