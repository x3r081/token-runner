extends Node3D
## THE CAMERA (3D_BIBLE.md §7). A Node3D that sits ON the focus point (y = 0,
## the floor plane) with a Camera3D child holding the whole orbit offset, so
## "where the frame looks" and "how the frame is framed" are two different
## numbers that never fight.
##
## Group "camera_fx", with camera_fx.gd's exact public surface — `add_trauma`,
## `punch_zoom`, `region_settle` — because every call site in the project
## (enemy_base x2, ability_fx x6, Fx3D.add_trauma/punch_zoom, world.gd's region
## flourish) reaches this through the group and duck-types the method.
##
## NO `class_name`: `World3D` is a real Godot class and this family of names sits
## uncomfortably close to the engine's. The scene attaches the script by path.
##
## WHAT CHANGES FROM THE 2D RIG, AND WHY
##
## camera_fx.gd deleted every zoom effect it had — the speed frame, the impact
## punch, the region settle — because the 2D game renders through a 640x360
## pixel stage where any magnification that is not exactly 0.5 resamples the
## art (VISUAL_BIBLE_V2 LAW 1; the whole argument is in that file's header).
## There is no pixel grid in 3D. The dolly is free again, so `punch_zoom()` and
## `region_settle()` do the thing their names promise instead of being kept as
## empty entry points. Everything else — trauma decay 2.2, squared response,
## look-ahead easing, the camera_shake setting gate, the "never show void"
## clamp — is ported behaviour, not new behaviour.

## FRAMING. `fov` is the HORIZONTAL field of view because `keep_aspect` is
## KEEP_WIDTH — Godot reads `fov` as whichever axis is not locked, and converts
## it with `get_fovy(fov, 1/aspect)` on the way into the projection.
##
## ROUND 2: §7's "distance 21u -> ~14u x 9u visible" was the defect, not the
## spec. Measured off docs/screenshots/qa3d, FOV 34 at 21u showed 13.0u across
## by 9.0u deep — about twelve units of a twenty-unit room — so every frame was
## a close-up of a floor with the walls, the exits and half the set dressing
## outside it, and a viewer could not answer "where are the exits" at all
## (VISUAL_BIBLE_V2's Definition of Done, question 1). The 2D game showed most
## of a 20x15 room; this rig now shows 21.5u across by 14.9u deep.
##
## Solved, not guessed. With pitch p, half-angles (ah, av) and distance D the
## camera sits at height D*sin(p) and the ground footprint is
##   across = 2*D*tan(ah)                      (at the focus)
##   depth  = h/tan(p-av) - h/tan(p+av)
## and at 16:9 with KEEP_WIDTH, tan(av) = tan(ah)/aspect. FOV 40 at D 29 gives
## 21.1u across at the focus (24.5u at the top edge, 18.6u at the bottom — it is
## a trapezoid) and 14.9u deep. The pitch and the yaw are unchanged: the 3/4
## angle is what makes walls and props show a face, and it is not the problem.
##
## WHAT THIS DOES TO THE CLAMP, measured rather than hoped. The footprint's
## axis-aligned BOUNDING BOX is 25.0u x 20.5u, which no authored room contains
## (20x15u, or 25x16u for the apartment), so `_clamped` below takes its "cannot
## be satisfied, centre instead" branch — both axes in a region, the depth axis
## in the apartment — and the frame comes to REST near the room's centre.
##
## At that rest position, in a 20x15 room: 86% of the floor is on screen, 82% of
## the frame is room floor and the remaining 18% is the strip beyond a wall,
## which is no longer a hole (environment3d.gd paints the background in the
## region's BASE hex — that is the other half of this round's fix). The
## apartment reads 74% / 94%.
##
## It is NOT a static camera, because the quad is not its bounding box: yawed 18
## degrees the trapezoid clips opposite corners of the room, so 71% of the floor
## sits inside the FRAME_KEEP quad and the outer ring does not. Walk into it and
## `_framed()` slides the frame a few units; walk back and it settles. That is
## the small, motivated motion LAW 9 asks for, in place of a frame that chased
## the player around a room whose edges he could never see.
const FOV := 40.0
const PITCH_DEG := -56.0
const YAW_DEG := -18.0
const DISTANCE := 29.0
const NEAR := 0.5
const FAR := 220.0

## Follow. Exponential damping, so the frame is frame-rate independent and can
## never overshoot; §7's "rate 6" plus a 1.2u lead in the direction of travel.
const FOLLOW_RATE := 6.0
const LOOK_DIST := 2.6
const LOOK_RATE := 5.5
const SPEED_SMOOTH := 4.5
## player.gd SPEED is 220 map px/s; one tile is 64 px (Map3D.PX), so full walk
## speed is 3.4375 world units/s. Only used to normalise "how fast is fast" — a
## wrong value here changes the strength of the lead, never its correctness.
const SPEED_REF := 220.0 / 64.0

## Trauma, ported from camera_fx.gd: same decay, same squared response, same
## saturation at 1.0, same suggested doses (hit 0.25, explosion 0.4, death 0.6).
## MAX_OFFSET is the one number that had to be re-derived, and re-derived AGAIN
## when the framing moved: the shake is a world-unit offset but the eye reads it
## as a fraction of the screen, and the screen is now 10.56u wide at the focus
## where it was 6.42u. 0.30u at the old framing was a ~4.7% displacement at full
## trauma; 0.50u is that same ~4.7% here. Shrinking the frame without moving
## this number would have quietly halved every hit in the game (LAW 9: motion is
## small — small, not absent).
const TRAUMA_DECAY := 2.2
const MAX_OFFSET := 0.50
const SHAKE_SPEED := 11.0

## How much of the visible floor quad the followed body must stay inside, as
## a scale about the focus. 0.84 keeps him roughly one body-height clear of
## every screen edge before the frame gives up "no void" to follow him.
const FRAME_KEEP := 0.84

## How much of the way the frame travels toward the player when the room is
## SMALLER than the frame — which, at this framing, is every authored room.
##
## The clamp below used to demand that the view's bounding box fit inside the
## room. That box is ~30u wide by ~33u deep once the yaw and pitch are taken
## into account, and a room is 20 x 15, so the demand was unsatisfiable on both
## axes, the clamp took its "centre instead" branch, and the camera parked: it
## did not follow at all. `_framed()` then had to drag the frame once the player
## had already reached 84% of the way to a screen edge, with no easing — exactly
## the "the edge does not reveal until very late" that was reported.
##
## A fixed overhang allowance cannot fix this in general: the depth box exceeds
## a room's depth by more than any sane constant. So when the frame does not
## fit, the focus travels this FRACTION of the way from the best-compromise
## position toward the player instead of stopping at it. The edge he walks
## toward reveals in proportion to his approach, and the overhang stays bounded
## by the fraction rather than being unbounded.
##
## Looking past a wall is cheap now and was not when that clamp was written:
## the Environment background is the region's own BASE, both builders paint a
## lit BASE ground plane 200u square beyond the border, and a backdrop band
## stands behind it. What shows past a wall is the region's dark, not a hole.
const TIGHT_FOLLOW := 0.55

## The hard cap on how far past a wall the frame may look, in world units.
## TIGHT_FOLLOW decides how much the camera leads; this decides how much of the
## outside that is ever allowed to cost. Together they replace the old
## all-or-nothing rule, which chose "no void" over "follow the player" and, in
## every room where the two conflicted, stopped following.
const VOID_ALLOW := 5.0

## Dolly transients, as a FRACTION of DISTANCE pulled in.
const PUNCH_DECAY := 4.5
const PUNCH_MAX := 0.10
const SETTLE_AMOUNT := 0.055
const SETTLE_DECAY := 1.6

var _cam: Camera3D
## The focus point on the floor plane, in WORLD units. Damped toward the
## target every frame and then clamped into the room.
var _focus := Vector3.ZERO
## Look-ahead, on the XZ plane, in world units.
var _look := Vector3.ZERO
var _speed_s := 0.0
var _trauma := 0.0
var _punch := 0.0
var _settle := 0.0
var _noise_t := 0.0
var _noise := FastNoiseLite.new()
var _target: Node3D
## The room, in WORLD units (map px / 64). Zero means "no bounds yet" and the
## clamp is skipped entirely — which is what a test rig gets.
var _room := Vector2.ZERO
## Ground footprint of the frustum RELATIVE TO THE FOCUS, recomputed every
## frame from the live camera. Asymmetric, because the rig is yawed. The seed
## values are the measured bounding box at the constants above, so the very
## first `_clamped()` — which can run before a viewport exists — reasons about
## roughly the right frame instead of about a 14u square.
var _view_min := Vector2(-10.8, -11.7)
var _view_max := Vector2(14.3, 8.9)
## The same footprint as the QUAD it actually is (XZ, relative to the focus,
## in screen order TL, TR, BR, BL). The rig is yawed, so this is a rotated
## trapezoid and its bounding box above is several units larger than it on each
## axis — see `_framed()` for why that matters. Empty until measured.
var _view_quad := PackedVector2Array()

func _ready() -> void:
	add_to_group("camera_fx")
	_noise.seed = 1337
	_noise.frequency = 0.9
	_cam = get_node_or_null("Camera3D") as Camera3D
	if _cam == null:
		for c: Node in get_children():
			if c is Camera3D:
				_cam = c as Camera3D
				break
	if _cam == null:
		push_warning("CameraRig3D: no Camera3D child; the rig will do nothing.")
		set_process(false)
		return
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.keep_aspect = Camera3D.KEEP_WIDTH
	_cam.fov = FOV
	_cam.near = NEAR
	_cam.far = FAR
	# The rig is unrotated, so the camera's local rotation IS its world
	# rotation, and the orbit offset below is expressible in rig space.
	_cam.rotation = Vector3(deg_to_rad(PITCH_DEG), deg_to_rad(YAW_DEG), 0.0)
	_cam.current = true
	_place_camera()

## The player, handed over by world3d.gd once it has instanced one. Falls back
## to the "player" group so a rig dropped into a test scene still follows.
func set_target(n: Node3D) -> void:
	_target = n
	if _target != null and _target.is_inside_tree():
		_focus = _floor(_target.global_position)
		_look = Vector3.ZERO
		_speed_s = 0.0
		_apply(0.0)

## The room the camera may not look outside of, in MAP PIXELS — the `size` the
## region builders return, unconverted, so callers never do the division.
func set_bounds(size_px: Vector2) -> void:
	_room = size_px / Map3D.PX
	_apply(0.0)

func camera() -> Camera3D:
	return _cam

func _floor(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)

func _process(delta: float) -> void:
	if _cam == null:
		return
	# A hitch must not teleport the frame (camera_fx.gd's guard, kept).
	var d := clampf(delta, 0.0, 0.1)
	_decay(d)
	_follow(d)
	_apply(d)

func _decay(delta: float) -> void:
	if _trauma > 0.0:
		_trauma = maxf(_trauma - TRAUMA_DECAY * delta, 0.0)
		_noise_t += delta * SHAKE_SPEED
	if _punch > 0.0:
		_punch = maxf(_punch - PUNCH_DECAY * _punch * delta - 0.02 * delta, 0.0)
	if _settle > 0.0:
		_settle = maxf(_settle - SETTLE_DECAY * _settle * delta - 0.004 * delta, 0.0)

## Damped follow plus look-ahead. Both are recomputed from state every frame and
## nothing accumulates, so a dropped frame can never park the camera off-centre.
func _follow(delta: float) -> void:
	var t := _resolve_target()
	if t == null:
		return
	var vel := Vector3.ZERO
	var v: Variant = t.get("velocity")
	if v is Vector3:
		vel = _floor(v)
	var speed := vel.length()
	var ratio := clampf(speed / SPEED_REF, 0.0, 1.4)
	_speed_s = lerpf(_speed_s, ratio, 1.0 - exp(-SPEED_SMOOTH * delta))

	var want := Vector3.ZERO
	if speed > 0.05:
		want = vel.normalized() * LOOK_DIST * minf(_speed_s, 1.0)
	_look = _look.lerp(want, 1.0 - exp(-LOOK_RATE * delta))

	var desired := _floor(t.global_position) + _look
	_focus = _focus.lerp(desired, 1.0 - exp(-FOLLOW_RATE * delta))

## The followed body. `is_inside_tree()` and not just `is_instance_valid()`:
## a player mid-region-change is valid and parentless for a frame, and reading
## `global_position` off it in that window is an error, not a stale number.
func _resolve_target() -> Node3D:
	if is_instance_valid(_target) and _target.is_inside_tree():
		return _target
	_target = null
	var tree := get_tree()
	if tree == null:
		return null
	var n := tree.get_first_node_in_group("player")
	if n is Node3D and (n as Node3D).is_inside_tree():
		_target = n as Node3D
	return _target

## Write the frame: camera offset (dolly + shake) first, so the frustum used by
## the clamp is this frame's frustum, then the clamped rig position.
func _apply(_delta: float) -> void:
	# `global_position` and `project_ray_normal` both need a live tree, and
	# set_target()/set_bounds() can arrive from world3d.gd's `_ready` ordering
	# before this rig has entered it.
	if _cam == null or not is_inside_tree():
		return
	_place_camera()
	_measure_view()
	global_position = _framed(_clamped(_focus))

## The orbit offset. `basis.z` is the camera's own backward axis, so the offset
## is derived from the rotation rather than from a hand-computed vector that
## could drift out of sync with PITCH/YAW.
func _place_camera() -> void:
	# `b`, not `basis`: Node3D already has a `basis` property and a local of
	# that name shadows it.
	var b := _cam.transform.basis
	var dist := DISTANCE * clampf(1.0 - _punch - _settle, 0.35, 1.0)
	var at := b.z * dist
	if _trauma > 0.0:
		# Squared trauma: small hits whisper, big hits rattle the desk. Applied
		# along the camera's own right/up so the shake reads as screen-space,
		# which is what every 2D call site was tuned against.
		var s := _trauma * _trauma * MAX_OFFSET
		at += b.x * (_noise.get_noise_2d(_noise_t, 0.0) * s)
		at += b.y * (_noise.get_noise_2d(0.0, _noise_t + 57.31) * s)
	_cam.position = at

## Where the frustum meets the floor, relative to the focus. Four corner rays,
## intersected with y = 0. Cheap enough to redo every frame, which is how the
## clamp stays correct while the dolly is moving.
##
## THE RIG IS NEVER ROTATED — nothing in this file or in world3d.gd writes its
## basis — so rig space and world space differ by a translation only. That is
## what lets a GLOBAL ray direction from `project_ray_normal` be intersected
## against the camera's LOCAL position and come out as an offset from the focus.
func _measure_view() -> void:
	var vp := _cam.get_viewport()
	if vp == null:
		return
	var size: Vector2 = vp.get_visible_rect().size
	if size.x < 1.0 or size.y < 1.0:
		return
	var h := _cam.position.y
	if h <= 0.01:
		return
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var quad := PackedVector2Array()
	# Screen order TL, TR, BR, BL — a convex ring, which is what `_framed()`
	# needs the quad to be.
	for corner: Vector2 in [Vector2.ZERO, Vector2(size.x, 0.0), size, Vector2(0.0, size.y)]:
		var n := _cam.project_ray_normal(corner)
		# A ray at or above the horizon has no floor hit; with a -56 degree
		# pitch and an 11.6 degree vertical half-angle (FOV 40 at 16:9 under
		# KEEP_WIDTH) the top edge still points 44 degrees down, so that cannot
		# happen — but a rig someone re-aimed should degrade rather than
		# produce INF.
		if n.y > -0.05:
			continue
		var p := _cam.position + n * (h / -n.y)
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
		quad.append(Vector2(p.x, p.z))
	if quad.is_empty():
		return
	_view_min = lo
	_view_max = hi
	# Only a complete ring is a usable polygon; a partial one keeps the last
	# good quad so the framing pass degrades to "stale" rather than "wrong".
	if quad.size() == 4:
		_view_quad = quad

## Hold the visible ground inside the room. §7: "clamp so the view never leaves
## the region rect" — the 2D game's equivalent (world.gd's `_apply_camera_bounds`)
## is what kept the starfield off screen at a region edge.
##
## An axis whose view is WIDER than the room cannot be satisfied; it is centred
## instead, which is the same choice camera_fx.gd's `_room_clamped` makes when
## the limits are narrower than the frame. At the round-2 framing that is BOTH
## axes in every authored region (see the FOV block), so this branch is the
## normal path now rather than the degenerate one — and it is survivable in a
## way it was not before, because what shows past a wall is no longer a hole:
## environment3d.gd paints the background in the region's own BASE hex, so the
## surround reads as deep wall. `_framed()` still has the last word.
func _clamped(f: Vector3) -> Vector3:
	if _room.x <= 0.0 or _room.y <= 0.0:
		return f
	var out := f
	out.x = _axis(f.x, 0.0 - _view_min.x, _room.x - _view_max.x)
	out.z = _axis(f.z, 0.0 - _view_min.y, _room.y - _view_max.y)
	out.y = 0.0
	return out

## One axis of the clamp.
##
## When the frame FITS between `lo` and `hi`, the focus is clamped into that
## band and the camera is a true follow cam that never shows anything past a
## wall. When it does not fit, the band's midpoint is still the best-compromise
## position — it is where the yawed frustum sits most evenly in the room, which
## is why this is not simply the room centre — and the focus travels
## TIGHT_FOLLOW of the way from there toward what the follow wants.
static func _axis(want: float, lo: float, hi: float) -> float:
	var base := (lo + hi) * 0.5
	var f := base + (want - base) * TIGHT_FOLLOW
	# The band is inverted when the frame does not fit the room, but widening
	# both ends by VOID_ALLOW leaves a sane interval either way, so this is one
	# formula rather than two branches.
	return clampf(f, minf(lo, hi) - VOID_ALLOW, maxf(lo, hi) + VOID_ALLOW)

## Keep the followed body ON SCREEN, which outranks "never show void".
##
## The clamp above holds the footprint's BOUNDING BOX inside the room, but the
## footprint is a yawed trapezoid, so its corners fall well short of the box's:
## a player standing in a room corner can be left several units outside the
## visible floor while the box sits flush to the walls. A hero who walks off his
## own screen is a worse frame than a strip of backdrop — and both builders
## paint a 190u void plane plus a backdrop beyond the border, over an
## Environment background in the region's BASE, so what the frame shows past a
## wall is the region's own dark, not a hole.
##
## At the round-2 framing this is also what keeps the camera ALIVE. `_clamped`
## parks the focus near the room centre (its bounding box no longer fits any
## room), and from there 71% of a 20x15 floor is inside the FRAME_KEEP quad and
## the outer ring is not — measured, not assumed. So the frame holds still while
## the player works the middle of the room and slides a few units when he goes
## to a corner. Note what that means mechanically: out there the rig tracks the
## BODY rather than the damped `_focus`, so the pan has no lag. It is smooth
## (the bisection result varies continuously with the body) and it is slow (the
## player walks at 3.4 u/s across a 21.5u frame), but it is not eased.
##
## The valid focus positions (those that put the body inside the FRAME_KEEP
## quad) form a convex set that contains the body itself, so along the segment
## from the clamped focus to the body the answer flips exactly once: bisect it.
## Ten steps is 0.1% of a ~10u segment, far below a pixel at this framing.
func _framed(f: Vector3) -> Vector3:
	if _view_quad.size() != 4:
		return f
	var t := _resolve_target()
	if t == null:
		return f
	var body := _floor(t.global_position)
	if _in_view(body - f):
		return f
	var lo := 0.0
	var hi := 1.0
	for _i: int in range(10):
		var mid := (lo + hi) * 0.5
		if _in_view(body - f.lerp(body, mid)):
			hi = mid
		else:
			lo = mid
	var out := f.lerp(body, hi)
	out.y = 0.0
	return out

## Is this focus-relative floor point inside the FRAME_KEEP-scaled view quad?
## Convex polygon test: the point is inside when it sits on the same side of
## every edge, and the quad is stored as a ring so the edges come in order.
func _in_view(rel: Vector3) -> bool:
	var p := Vector2(rel.x, rel.z)
	var sign_seen := 0.0
	for i: int in range(4):
		var a: Vector2 = _view_quad[i] * FRAME_KEEP
		var b: Vector2 = _view_quad[(i + 1) % 4] * FRAME_KEEP
		var cross := (b - a).cross(p - a)
		if absf(cross) < 0.0001:
			continue
		if sign_seen == 0.0:
			sign_seen = signf(cross)
		elif signf(cross) != sign_seen:
			return false
	return true

# ------------------------------------------------------------------ the API --

## Add shake. Clamped 0..1; repeated small hits stack into a proper tremor.
## Honours the Camera Shake setting — with it off the whole rig goes quiet, and
## every caller keeps working because they all come through here.
func add_trauma(amount: float) -> void:
	if not bool(SettingsManager.get_setting("camera_shake")):
		return
	_trauma = clampf(_trauma + amount, 0.0, 1.0)

## The impact punch: a short dolly-in on the hit frame. Gated on the same
## setting as the shake — a player who turned shake off turned off "the camera
## reacts to being hit", and half of that promise is not the deal.
func punch_zoom(amount: float = 0.04) -> void:
	if not bool(SettingsManager.get_setting("camera_shake")):
		return
	_punch = clampf(_punch + absf(amount), 0.0, PUNCH_MAX)

## Region entry. Two jobs, and the first is the load-bearing one: reset the
## look-ahead so a lead built up while running INTO a portal does not ride
## through it and frame the new room off-centre. Then snap onto the new spawn
## (the player teleported; damping toward it would fly the camera across the
## map) and arrive very slightly tight, easing out over about a second.
func region_settle() -> void:
	_look = Vector3.ZERO
	_speed_s = 0.0
	# Arriving in a new room still ringing from the last one reads as a bug.
	_trauma = 0.0
	_punch = 0.0
	_settle = SETTLE_AMOUNT if bool(SettingsManager.get_setting("camera_shake")) else 0.0
	snap()

## Put the frame on the target immediately, with no damping. Used on region
## entry and after a respawn.
func snap() -> void:
	var t := _resolve_target()
	if t != null:
		_focus = _floor(t.global_position)
	_apply(0.0)
