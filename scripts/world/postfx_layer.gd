extends CanvasLayer
## Full-screen post-processing stack, created at runtime by world.gd.
## Layer 0 sits above the world's default canvas and below every UI CanvasLayer
## (HUD=1, dialogue=10, popups=15, opening=100), so the grade touches the game,
## not the menus. Draw order inside this layer, bottom to top:
##   HeatHaze (screen distortion, gpu_mines only) -> PostFX (grade/vignette/
##   grain/aberration) -> RegionFade (the 0.4s curtain-up on region entry).
## Everything here is cosmetic: mouse_filter IGNORE, input is never blocked.

const POSTFX_SHADER := "res://assets/shaders/postfx.gdshader"
const HAZE_SHADER := "res://assets/shaders/heat_haze.gdshader"

var _mat: ShaderMaterial
var _haze: ColorRect
var _haze_copy: BackBufferCopy
var _fade: ColorRect
var _grade_tween: Tween
var _fade_tween: Tween

func _ready() -> void:
	# The fade curtain must never be frozen mid-transition by a pausing popup
	# (random events / dialogue pause the tree) — that strands a black screen.
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 0
	_haze = _screen_rect("HeatHaze")
	if ResourceLoader.exists(HAZE_SHADER):
		var hm := ShaderMaterial.new()
		hm.shader = load(HAZE_SHADER)
		hm.set_shader_parameter("strength", 0.0018)
		hm.set_shader_parameter("speed", 1.6)
		_haze.material = hm
	_haze.visible = false
	add_child(_haze)
	# Two screen-reading shaders in a row share one screen capture, so without
	# this the grade below would sample the PRE-haze screen and quietly undo the
	# distortion. Only pays its copy cost while the haze is actually visible.
	_haze_copy = BackBufferCopy.new()
	_haze_copy.name = "HazeBackBuffer"
	_haze_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	_haze_copy.visible = false
	add_child(_haze_copy)

	var rect := _screen_rect("PostFX")
	if ResourceLoader.exists(POSTFX_SHADER):
		_mat = ShaderMaterial.new()
		_mat.shader = load(POSTFX_SHADER)
		# Seed the tweened uniforms explicitly — unset shader params read back
		# as null, and tweening from null is a crash with extra steps.
		_mat.set_shader_parameter("grade_lift", Vector3(0.012, 0.008, 0.03))
		_mat.set_shader_parameter("aberration", 1.1)
		_mat.set_shader_parameter("vignette_strength", 0.20)
		rect.material = _mat
	else:
		rect.visible = false  # no shader, no opinions
	add_child(rect)

	_fade = _screen_rect("RegionFade")
	_fade.color = Color(0.02, 0.024, 0.055, 0.0)  # VOID, invisible until asked
	add_child(_fade)

## Anchors full-rect under a CanvasLayer track the viewport size for free.
func _screen_rect(rect_name: String) -> ColorRect:
	var r := ColorRect.new()
	r.name = rect_name
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

## Quick curtain-up on region entry. Purely visual; the player can already move.
func fade_from_black(duration: float = 0.4) -> void:
	if not _fade:
		return
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade.color.a = 1.0
	_fade_tween = create_tween()
	_fade_tween.tween_property(_fade, "color:a", 0.0, duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## Per-region screen chemistry: nudge lift/vignette/aberration toward the
## region's mood (VISUAL_BIBLE ambience table). Subtle by design — the grade
## seasons the frame, it doesn't cook it.
func set_region(region_id: String) -> void:
	if _haze:
		_haze.visible = region_id == "gpu_mines" and _haze.material != null
	if _haze_copy:
		_haze_copy.visible = _haze != null and _haze.visible
	if not _mat:
		return
	var lift := Vector3(0.012, 0.008, 0.03)  # default: shadows toward indigo
	var aberr := 1.1
	var vig := 0.34
	match region_id:
		"gpu_mines":
			lift = Vector3(0.03, 0.012, 0.006)
			aberr = 1.5
			vig = 0.4
		"production":
			lift = Vector3(0.034, 0.008, 0.012)
			aberr = 1.9
			vig = 0.42
		"cloud_district":
			lift = Vector3(0.014, 0.02, 0.038)
			aberr = 0.8
			vig = 0.26
		"token_vault":
			lift = Vector3(0.028, 0.022, 0.008)
			vig = 0.38
		"api_bazaar":
			lift = Vector3(0.026, 0.006, 0.026)
			aberr = 1.4
		"open_source_wildlands", "dependency_district":
			lift = Vector3(0.008, 0.022, 0.012)
		"stackoverflow_ruins":
			lift = Vector3(0.022, 0.016, 0.008)
		"corporate_enterprise":
			lift = Vector3(0.01, 0.014, 0.032)
			vig = 0.28
	if _grade_tween and _grade_tween.is_valid():
		_grade_tween.kill()
	_grade_tween = create_tween().set_parallel(true)
	_grade_tween.tween_property(_mat, "shader_parameter/grade_lift", lift, 0.6) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_grade_tween.tween_property(_mat, "shader_parameter/aberration", aberr, 0.6) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_grade_tween.tween_property(_mat, "shader_parameter/vignette_strength", vig, 0.6) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
