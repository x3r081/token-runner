extends Node
## Camera juice, attached at runtime to the player's Camera2D by world.gd
## (the player scene itself stays untouched). Provides trauma-based shake and
## micro zoom punches per the VISUAL_BIBLE camera standards.
##
## Other systems reach it via the "camera_fx" group and must null-check:
##   var fx := get_tree().get_first_node_in_group("camera_fx")
##   if fx: fx.add_trauma(0.25)
## Suggested doses: hit 0.25, explosion 0.4, death 0.6. It saturates at 1.0,
## like most things in this codebase.

const TRAUMA_DECAY := 2.2
const MAX_OFFSET := 6.0
const SHAKE_SPEED := 11.0

var _trauma := 0.0
var _noise_t := 0.0
var _noise := FastNoiseLite.new()
var _cam: Camera2D
var _base_zoom := Vector2.ONE
var _zoom_tween: Tween

func _ready() -> void:
	add_to_group("camera_fx")
	_noise.seed = 1337
	_noise.frequency = 0.9
	_cam = get_parent() as Camera2D
	if _cam:
		_cam.position_smoothing_enabled = true
		_cam.position_smoothing_speed = 6.0
		_base_zoom = _cam.zoom
	else:
		# Attached to something that isn't a camera. Shake nothing, judge silently.
		set_process(false)

func _process(delta: float) -> void:
	if _trauma <= 0.0:
		return
	_trauma = maxf(_trauma - TRAUMA_DECAY * delta, 0.0)
	_noise_t += delta * SHAKE_SPEED
	# Squared trauma: small hits whisper, big hits actually rattle the desk.
	var shake := _trauma * _trauma
	# Our parent (GameCamera) writes camera.offset every frame it processes, and
	# parents process before children — so ADD on top of whatever it wrote this
	# frame. Legacy shake() calls and trauma shake compose instead of fighting,
	# and the offset never accumulates across frames.
	_cam.offset += Vector2(
		_noise.get_noise_2d(_noise_t, 0.0),
		_noise.get_noise_2d(0.0, _noise_t + 57.31)
	) * (MAX_OFFSET * shake)

## Add shake. Clamped 0..1; repeated small hits stack into a proper tremor.
func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)

## Micro zoom pulse for impacts/pickups. 0.03 is subtle, 0.08 is rude.
func punch_zoom(amount: float = 0.04) -> void:
	if not _cam:
		return
	_start_zoom_tween(_base_zoom * (1.0 + clampf(amount, -0.2, 0.2)), 0.05, 0.22)

## Region-entry settle: arrive framed slightly tight, ease out to normal.
func region_settle() -> void:
	if not _cam:
		return
	_start_zoom_tween(_base_zoom * 1.05, 0.0, 0.55)

func _start_zoom_tween(target: Vector2, in_time: float, out_time: float) -> void:
	if _zoom_tween and _zoom_tween.is_valid():
		_zoom_tween.kill()
	_zoom_tween = create_tween()
	if in_time > 0.0:
		_zoom_tween.tween_property(_cam, "zoom", target, in_time) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		_cam.zoom = target
	_zoom_tween.tween_property(_cam, "zoom", _base_zoom, out_time) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
