extends Node
## Camera juice, attached at runtime to the player's Camera2D by world.gd
## (the player scene itself stays untouched). Trauma shake, look-ahead and
## impact punches, per the VISUAL_BIBLE camera standards.
##
## Other systems reach it via the "camera_fx" group and must null-check:
##   var fx := get_tree().get_first_node_in_group("camera_fx")
##   if fx: fx.add_trauma(0.25)
## Suggested doses: hit 0.25, explosion 0.4, death 0.6. It saturates at 1.0,
## like most things in this codebase, and MAX_OFFSET caps the result at 3px.
##
## Round 6 — the pixel grid comes first. VISUAL_BIBLE_V2 LAW 1: every world
## pixel is exactly N screen pixels, always. Two things in the round-5 rig broke
## that continuously, and both are gone:
##
##   speed frame  a few percent of zoom-out while moving. A camera zoom of
##                1/(1 + speed*0.05) is a NON-INTEGER magnification for the
##                entire time the player is walking, i.e. the pixel grid was
##                dissolved for most of the game. Deleted outright — the frame
##                does not need to breathe to say "you are running".
##   sub-pixel    the composed offset was written at full float precision, so
##                look-ahead and shake both slid the world by fractions of a
##                pixel. The offset is rounded to whole world units now, which
##                with rendering/2d/snap/snap_2d_transforms_to_pixel is what
##                keeps the grid intact while scrolling.
##
## What is left, all additive on top of whatever GameCamera wrote this frame,
## and none of it accumulating — every frame recomputes from state, so a hitch
## can never leave the camera parked off-centre:
##
##   look-ahead   the frame leads the direction of travel, so you see what you
##                are running INTO. Written into camera.offset (the same
##                channel as the shake) and eased on its own curve, because
##                Camera2D's position smoothing does not touch offset.
##   punch        impacts push the frame IN and let it fall back out, at HALF
##                round 5's amplitude (LAW 9: motion is small). Attack is
##                near-instant, release is a quarter of a second, and the whole
##                thing is a pair of exponentials — no springs, no overshoot,
##                nothing that can oscillate on a low frame rate.
##   trauma       capped at 3px (LAW 9), down from 6.

const TRAUMA_DECAY := 2.2
## LAW 9 caps shake at 3 world px. Squared trauma still means small hits
## whisper; the ceiling is simply half what it was.
const MAX_OFFSET := 3.0
const SHAKE_SPEED := 11.0
## Player walk speed (player.gd SPEED). Used only to normalise "how fast is
## fast" — a wrong value here changes the strength of the effect, never its
## correctness.
const SPEED_REF := 220.0
## How far ahead of the player the frame leads, in world pixels, at full walk
## speed. Kept small on purpose (it is anticipation, not a second camera), and
## _room_clamped() additionally holds it inside the room limits — offset is
## applied AFTER Camera2D's own limit clamp, so without that it could show the
## off-map starfield at a region edge.
const LOOK_DIST := 26.0
const LOOK_RATE := 5.5            # look-ahead ease, per second
const SPEED_SMOOTH := 4.5         # how fast the "am I moving" signal reacts
const PUNCH_ATTACK := 30.0        # impact rise
const PUNCH_RELEASE := 8.5        # impact fall
## A chase toward a decaying target never reaches that target — with the rates
## above it peaks at ~61% of it, and 1.65 used to buy that back exactly so
## punch_zoom(0.07) meant "7% tighter at the peak". Round 6 halves it: every
## existing caller now lands at half the amplitude it asked for, which is the
## cheapest possible way to quiet every impact in the game at once without
## touching a single call site.
const PUNCH_GAIN := 0.82
const SETTLE_RATE := 3.6          # region-entry zoom settle

var _trauma := 0.0
var _noise_t := 0.0
var _noise := FastNoiseLite.new()
var _cam: Camera2D
var _body: Node2D
var _base_zoom := Vector2.ONE
var _look := Vector2.ZERO
var _speed_s := 0.0
var _punch := 0.0
var _punch_target := 0.0
var _settle := 0.0
var _applied_zoom := 0.0          # last zoom scalar written, to skip idle writes

func _ready() -> void:
	add_to_group("camera_fx")
	_noise.seed = 1337
	_noise.frequency = 0.9
	_cam = get_parent() as Camera2D
	if _cam:
		_cam.position_smoothing_enabled = true
		# Snappier than round 4's 6.0. With look-ahead doing the anticipation,
		# a slow follow just reads as lag.
		_cam.position_smoothing_speed = 9.0
		_base_zoom = _cam.zoom
		# The camera hangs off the player, which is where the velocity lives.
		# Anything else (a test rig, a cutscene camera) simply gets no
		# look-ahead and no speed framing.
		_body = _cam.get_parent() as Node2D
	else:
		# Attached to something that isn't a camera. Shake nothing, judge silently.
		set_process(false)

func _process(delta: float) -> void:
	if not _cam:
		return
	var d := clampf(delta, 0.0, 0.1)  # a hitch must not teleport the frame
	_update_framing(d)
	_update_shake(d)
	# LAW 1, the last step of every frame: the composed offset (GameCamera's
	# legacy shake + look-ahead + trauma) is snapped to whole world units, so
	# scrolling moves the world by whole pixels and the 2x grid never smears.
	# It has to happen here, after both writers, or the rounding is undone by
	# whichever one runs second.
	_cam.offset = _cam.offset.round()

## Look-ahead and the punch/settle zoom. The smoothed "how fast, which way"
## signal drives the look-ahead only now — the speed-framing zoom that used to
## share it is gone (LAW 1).
func _update_framing(delta: float) -> void:
	var vel := Vector2.ZERO
	if is_instance_valid(_body):
		var v: Variant = _body.get("velocity")
		if v is Vector2:
			vel = v
	var ratio := clampf(vel.length() / SPEED_REF, 0.0, 1.4)
	_speed_s = lerpf(_speed_s, ratio, 1.0 - exp(-SPEED_SMOOTH * delta))

	var target := Vector2.ZERO
	if vel.length_squared() > 1.0:
		target = vel.normalized() * LOOK_DIST * minf(_speed_s, 1.0)
	_look = _look.lerp(target, 1.0 - exp(-LOOK_RATE * delta))
	_cam.offset += _room_clamped(_look)

	# Impact punch: a fast chase toward a target that is itself decaying. Two
	# exponentials instead of a spring — it cannot overshoot, so it cannot
	# induce the pumping that makes zoom effects nauseating.
	_punch_target = lerpf(_punch_target, 0.0, 1.0 - exp(-PUNCH_RELEASE * delta))
	_punch = lerpf(_punch, _punch_target, 1.0 - exp(-PUNCH_ATTACK * delta))
	_settle = lerpf(_settle, 0.0, 1.0 - exp(-SETTLE_RATE * delta))

	# Zoom is a Camera2D magnification, so "wider frame" is a SMALLER number.
	# There is no speed term any more (see the header): at rest and at a walk
	# this is exactly 1.0, so the camera sits on the scene's authored zoom and
	# the pixel grid holds. Only a transient impact or a region entry moves it,
	# and both decay back to exactly 1.0 rather than near it.
	var zoom_scale := 1.0 + _punch + _settle
	if absf(zoom_scale - 1.0) < 0.0005:
		zoom_scale = 1.0
	if absf(zoom_scale - _applied_zoom) > 0.0005:
		_applied_zoom = zoom_scale
		_cam.zoom = _base_zoom * zoom_scale

## Camera2D's limits clamp POSITION; `offset` is applied on top of the clamped
## result, so a raw look-ahead can push the frame past the room edge and show
## the off-map starfield — world.gd sets those limits precisely so that never
## happens. Re-apply the engine's own clamp to the offset instead of trusting a
## small constant to stay small: the room is 1280x960 and the frame is wider
## than that at zoom 1.35, so the horizontal axis is already un-clampable and
## the vertical one is not. An axis whose limits are narrower than the view is
## left alone (clamping it would pin a constant offset, which is worse than the
## thing it prevents), and the default +/-10000000 limits make this a no-op
## before world.gd has applied any bounds.
func _room_clamped(look: Vector2) -> Vector2:
	var half := _cam.get_viewport_rect().size * 0.5 / _cam.zoom
	var lo := Vector2(float(_cam.limit_left), float(_cam.limit_top)) + half
	var hi := Vector2(float(_cam.limit_right), float(_cam.limit_bottom)) - half
	var c := _cam.global_position
	var framed := look
	if hi.x >= lo.x:
		var cx := clampf(c.x, lo.x, hi.x)
		framed.x = clampf(look.x, lo.x - cx, hi.x - cx)
	if hi.y >= lo.y:
		var cy := clampf(c.y, lo.y, hi.y)
		framed.y = clampf(look.y, lo.y - cy, hi.y - cy)
	return framed

func _update_shake(delta: float) -> void:
	if _trauma <= 0.0:
		return
	_trauma = maxf(_trauma - TRAUMA_DECAY * delta, 0.0)
	_noise_t += delta * SHAKE_SPEED
	# Squared trauma: small hits whisper, big hits actually rattle the desk.
	var shake := _trauma * _trauma
	# Our parent (GameCamera) writes camera.offset every frame it processes, and
	# parents process before children — so ADD on top of whatever it wrote this
	# frame. Legacy shake() calls, look-ahead and trauma shake compose instead
	# of fighting, and the offset never accumulates across frames.
	_cam.offset += Vector2(
		_noise.get_noise_2d(_noise_t, 0.0),
		_noise.get_noise_2d(0.0, _noise_t + 57.31)
	) * (MAX_OFFSET * shake)

## Add shake. Clamped 0..1; repeated small hits stack into a proper tremor.
## Honours the Camera Shake setting — with it off the whole rig goes quiet, and
## every caller keeps working because they all go through here.
func add_trauma(amount: float) -> void:
	if not bool(SettingsManager.get_setting("camera_shake")):
		return
	_trauma = clampf(_trauma + amount, 0.0, 1.0)

## Micro zoom pulse for impacts/pickups. 0.03 is subtle, 0.08 is rude. Negative
## values punch outward. Kicks are taken at their strongest, never summed, so a
## burst of ten hits is one punch and not a zoom to the moon.
##
## A kick in the OPPOSITE direction always wins, whatever its size: pulling the
## frame back is a different statement from slamming it in, not a weaker one.
## Without that exception ability_fx's Ctrl+Z pull-back (the only negative
## caller in the game) is silently eaten whenever any inward punch is still in
## flight — and a signature beat that plays only sometimes is worse than one
## that never plays at all.
func punch_zoom(amount: float = 0.04) -> void:
	if not _cam:
		return
	var a := clampf(amount, -0.2, 0.2) * PUNCH_GAIN
	if absf(a) > absf(_punch_target) or (a * _punch_target) < 0.0:
		_punch_target = a

## Region-entry settle: arrive framed slightly tight, ease out to normal.
func region_settle() -> void:
	if not _cam:
		return
	_settle = 0.05
	_look = Vector2.ZERO
	_speed_s = 0.0
	# A kill punch taken on the last frame of the old region has no business
	# riding the portal into the new one — the settle owns this transition.
	_punch = 0.0
	_punch_target = 0.0
