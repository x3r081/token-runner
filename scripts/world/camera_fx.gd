extends Node
## Camera juice, attached at runtime to the player's Camera2D by world.gd
## (the player scene itself stays untouched). Trauma shake and look-ahead, per
## the VISUAL_BIBLE camera standards. Both write camera.offset and nothing else
## — the zoom belongs to the scene now (see "Round 11" below).
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
##   trauma       capped at 3px (LAW 9), down from 6.
##
## Round 11 — the punch and settle ZOOMS are gone too, for the same reason the
## speed frame was. Round 6 deleted the continuous one and kept the two
## transients, on the grounds that they "decay back to exactly 1.0". They do,
## but the whole way there they are a non-integer magnification.
##
## The stage is 640x360 and the camera sits at zoom 0.5 (pixel_stage.gd), so a
## 32px sprite drawn at scale 2.0 covers exactly 32 stage pixels: one art pixel,
## one stage pixel. That holds at zoom 0.5 and at NO zoom within 90% of it — the
## next magnification where an art pixel is a whole number of stage pixels is
## 1.0, a doubling. A 3-5% punch is therefore not a small violation of LAW 1, it
## is the same resampling the whole round-11 stage was built to remove: one art
## pixel column in ~30 comes out double width, and it moves while the envelope
## decays.
##
## Measured, because "3% is surely invisible" is exactly the reasoning that put
## 2.75 screen pixels per art pixel in the shipping build: region_settle() takes
## the camera to zoom 0.5222, and in that frame the player's two pupils are
## different widths. region_settle() runs on EVERY region entry, for about a
## second — the first second the player looks at fresh art.
##
## No frame in docs/screenshots/qa can show this. The capture never fires a
## punch, and even if it did, the composed SCREEN runs stay multiples of K
## whatever the zoom does (the blit doubles whatever the stage holds), so the
## grid proof passes either way. It has to be reasoned about, not screenshotted.
##
## The impact itself is not lost: every punch_zoom() call site in the project
## (enemy_base x2, ability_fx x6) calls FxLib.add_trauma() on the same frame,
## and trauma IS grid-safe — it moves the camera by whole stage pixels via
## _snap_offset(). The zoom was garnish on top of a shake that stays.

const TRAUMA_DECAY := 2.2
## LAW 9 caps shake at TWO STAGE PIXELS, and this is the number in world units:
## the camera runs at zoom 0.5 inside a 640x360 stage (pixel_stage.gd), so one
## stage pixel is 2 world units and the ceiling is 4. Quoted in world units
## because that is what `offset` is measured in; quantised to whole stage pixels
## by `_snap_offset()`, because a shake of 1.5 stage pixels is a shake that
## dissolves the grid it is shaking.
const MAX_OFFSET := 4.0
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

var _trauma := 0.0
var _noise_t := 0.0
var _noise := FastNoiseLite.new()
var _cam: Camera2D
var _body: Node2D
var _look := Vector2.ZERO
var _speed_s := 0.0

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
	# legacy shake + look-ahead + trauma) is snapped to whole STAGE pixels, so
	# scrolling moves the world by whole pixels and the grid never smears. It has
	# to happen here, after both writers, or the rounding is undone by whichever
	# one runs second.
	#
	# Whole WORLD units is not enough any more: at zoom 0.5 a world unit is half
	# a stage pixel, so an odd offset shifts the whole frame by half a pixel and
	# every edge in it lands between two screen pixels.
	_cam.offset = _snap_offset(_cam.offset)

## Quantise to the stage's own pixel: one stage pixel is 1/zoom world units (2.0
## at the authored zoom of 0.5). Falls back to whole world units for a camera
## with no zoom, which is what a test rig has.
func _snap_offset(v: Vector2) -> Vector2:
	var q := Vector2(
		1.0 / maxf(absf(_cam.zoom.x), 0.0001),
		1.0 / maxf(absf(_cam.zoom.y), 0.0001))
	return Vector2(roundf(v.x / q.x) * q.x, roundf(v.y / q.y) * q.y)

## Look-ahead. The smoothed "how fast, which way" signal drives it and nothing
## else: every zoom term this function used to carry — the speed frame, the
## impact punch, the region settle — is gone, because none of them can be
## expressed at this stage's magnification without resampling the art (LAW 1;
## see the header). `_cam.zoom` is now written exactly once, by the scene.
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

## Camera2D's limits clamp POSITION; `offset` is applied on top of the clamped
## result, so a raw look-ahead can push the frame past the room edge and show
## the off-map starfield — world.gd sets those limits precisely so that never
## happens. Re-apply the engine's own clamp to the offset instead of trusting a
## small constant to stay small: the room is 1280x960 and the frame is exactly
## 1280x720 at the stage zoom of 0.5, so the horizontal axis is already
## un-clampable (view == room width) and the vertical one is not. An axis whose limits are narrower than the view is
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

## The impact-punch entry point, kept so the eight call sites (enemy_base x2,
## ability_fx x6) need no edit — and so a future pixel-safe punch has a home.
##
## It no longer touches the zoom. It cannot: see the header. A few percent of
## magnification on a stage where one art pixel is one stage pixel resamples
## every sprite in the frame, which is the exact artifact round 11 exists to
## remove. Every one of those call sites already calls FxLib.add_trauma() on the
## same frame, so the impact still lands — through the shake, which is snapped
## to whole stage pixels and stays on the grid.
##
## Deliberately NOT re-expressed as extra trauma: that would raise the shake
## amplitude at eight tuned call sites as a side effect of a rendering fix.
func punch_zoom(_amount: float = 0.04) -> void:
	pass

## Region entry. The "arrive framed slightly tight, ease out" zoom is gone with
## the rest of them — it was the worst of the three, because it ran for a second
## on every single region entry, over the first frames of art the player sees.
##
## What remains is the state reset, which is the part that was load-bearing: a
## look-ahead built up while running INTO the portal must not ride through it
## and frame the new region off-centre on arrival.
func region_settle() -> void:
	if not _cam:
		return
	_look = Vector2.ZERO
	_speed_s = 0.0
