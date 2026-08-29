extends CanvasLayer
## Full-screen post-processing stack, created at runtime by world.gd.
## Layer 0 sits above the world's default canvas and below every UI CanvasLayer
## (HUD=1, dialogue=10, popups=15, opening=100), so the grade touches the game,
## not the menus. Draw order inside this layer, bottom to top:
##   HeatHaze (screen distortion, gpu_mines only) -> PostFX (grade/vignette/
##   grain/aberration/stress) -> RegionFade (the 0.4s curtain-up on region entry).
## Everything here is cosmetic: mouse_filter IGNORE, input is never blocked.
##
## Three knobs, three owners:
##   set_region()  world.gd, on every region load — the per-region grade.
##   set_stress()  world.gd, whenever technical debt moves — comedy through
##                 cinematography: the frame loses its composure as the codebase
##                 does. Free at stress 0.
##   pulse()       world.gd, on a debt incident — one short coloured flash.

const POSTFX_SHADER := "res://assets/shaders/postfx.gdshader"
const HAZE_SHADER := "res://assets/shaders/heat_haze.gdshader"

var _mat: ShaderMaterial
var _haze: ColorRect
var _haze_mat: ShaderMaterial
var _haze_copy: BackBufferCopy
var _fade: ColorRect
var _grade_tween: Tween
var _fade_tween: Tween
var _stress_tween: Tween
var _wash_tween: Tween

func _ready() -> void:
	# The fade curtain must never be frozen mid-transition by a pausing popup
	# (random events / dialogue pause the tree) — that strands a black screen.
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 0
	_haze = _screen_rect("HeatHaze")
	if ResourceLoader.exists(HAZE_SHADER):
		_haze_mat = ShaderMaterial.new()
		_haze_mat.shader = load(HAZE_SHADER)
		_haze_mat.set_shader_parameter("strength", 0.0014)
		_haze_mat.set_shader_parameter("speed", 1.15)
		_haze_mat.set_shader_parameter("tint", Color(1.0, 0.55, 0.28))
		_haze_mat.set_shader_parameter("tint_amount", 0.0)
		_haze_mat.set_shader_parameter("rise", 1.0)
		_haze.material = _haze_mat
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
		_mat.set_shader_parameter("saturation", 1.16)
		_mat.set_shader_parameter("contrast", 0.12)
		_mat.set_shader_parameter("filmic", 0.30)
		_mat.set_shader_parameter("stress", 0.0)
		_mat.set_shader_parameter("stress_tint", Vector3(1.0, 0.55, 0.50))
		_mat.set_shader_parameter("wash_color", Color("#FF4757"))
		_mat.set_shader_parameter("wash_amount", 0.0)
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

## Per-region screen chemistry: nudge lift/vignette/aberration/saturation/
## contrast toward the region's mood (VISUAL_BIBLE ambience table). Subtle by
## design — the grade seasons the frame, it doesn't cook it.
##
## Round 3 retune, from the QA frames: the two furnace regions were running at
## saturation 1.20–1.24 on top of lighting that is already almost monochrome
## red, which is why they read as a screaming wall of orange rather than as
## HEAT. Production is now the most desaturated grade in the game and the most
## contrasty — hot, bleached, and out of patience — while Cloud District gets
## the clean cool end and Token Vault keeps the only genuinely rich one.
## Vignettes stay light across the board (the old 0.34–0.42 ate the corners of
## an already dark frame) and every region carries a small S-curve so the indigo
## shadow lift reads as depth instead of haze.
##
## Round 4: the vignette CURVE moved into the shader — a wide clean plateau to
## ~0.42 of the frame radius plus a corner-commit term — so these per-region
## strengths now price only the edges, not the mid-ground. A `filmic` tone
## response (seeded in _ready, constant across regions) separates near-white
## mid-values from the true HDR bloom sources above 1.0.
func set_region(region_id: String) -> void:
	var hot := region_id == "gpu_mines"
	if _haze:
		_haze.visible = hot and _haze.material != null
	if _haze_copy:
		_haze_copy.visible = _haze != null and _haze.visible
	if _haze_mat and hot:
		# Round 4: slower and subtler. The old 0.0024/1.9 made the whole mine
		# swim and smeared prop edges in the QA frame — heat now reads in the
		# peripheral vision, not as a lens over the room.
		_haze_mat.set_shader_parameter("strength", 0.0019)
		_haze_mat.set_shader_parameter("speed", 1.3)
		_haze_mat.set_shader_parameter("tint_amount", 0.024)
		_haze_mat.set_shader_parameter("rise", 1.15)
	if not _mat:
		return
	var lift := Vector3(0.012, 0.008, 0.03)  # default: shadows toward indigo
	var aberr := 1.1
	var vig := 0.28
	var sat := 1.16
	var con := 0.12
	match region_id:
		"localhost":
			lift = Vector3(0.018, 0.012, 0.026)
			aberr = 1.0
			vig = 0.26
			sat = 1.14
			con = 0.12
		"gpu_mines":
			lift = Vector3(0.030, 0.011, 0.005)
			aberr = 1.4
			vig = 0.30
			sat = 1.06
			con = 0.17
		"production":
			lift = Vector3(0.034, 0.010, 0.012)
			aberr = 1.8
			vig = 0.33
			sat = 0.94
			con = 0.20
		"cloud_district":
			lift = Vector3(0.012, 0.019, 0.036)
			aberr = 0.7
			vig = 0.18
			sat = 1.08
			con = 0.09
		"token_vault":
			lift = Vector3(0.028, 0.021, 0.008)
			aberr = 1.0
			vig = 0.30
			sat = 1.24
			con = 0.15
		"api_bazaar":
			lift = Vector3(0.024, 0.006, 0.026)
			aberr = 1.4
			vig = 0.26
			sat = 1.24
			con = 0.14
		"open_source_wildlands", "dependency_district":
			lift = Vector3(0.008, 0.022, 0.012)
			sat = 1.14
			con = 0.11
		"stackoverflow_ruins":
			lift = Vector3(0.020, 0.015, 0.008)
			vig = 0.30
			sat = 1.02
			con = 0.11
		"corporate_enterprise":
			lift = Vector3(0.010, 0.014, 0.030)
			vig = 0.22
			sat = 0.98
			con = 0.06
	if _grade_tween and _grade_tween.is_valid():
		_grade_tween.kill()
	_grade_tween = create_tween().set_parallel(true)
	_grade_tween.tween_property(_mat, "shader_parameter/grade_lift", lift, 0.6) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_grade_tween.tween_property(_mat, "shader_parameter/aberration", aberr, 0.6) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_grade_tween.tween_property(_mat, "shader_parameter/vignette_strength", vig, 0.6) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_grade_tween.tween_property(_mat, "shader_parameter/saturation", sat, 0.6) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_grade_tween.tween_property(_mat, "shader_parameter/contrast", con, 0.6) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## The stress grade: 0 is a clean run, 1 is a codebase nobody will admit to.
## Every stress term in the shader multiplies out at 0, so a tidy player pays
## nothing for this and never sees it. Pass duration 0.0 to snap (region load).
func set_stress(value: float, duration: float = 1.2) -> void:
	if not _mat:
		return
	var target := clampf(value, 0.0, 1.0)
	if _stress_tween and _stress_tween.is_valid():
		_stress_tween.kill()
	if duration <= 0.0:
		_mat.set_shader_parameter("stress", target)
		return
	_stress_tween = create_tween()
	_stress_tween.tween_property(_mat, "shader_parameter/stress", target, duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## One short coloured flash over the whole frame — an incident landing. Short
## enough to register as an event and not as a filter.
func pulse(color: Color, amount: float = 0.22, duration: float = 0.55) -> void:
	if not _mat:
		return
	if _wash_tween and _wash_tween.is_valid():
		_wash_tween.kill()
	_mat.set_shader_parameter("wash_color", color)
	_mat.set_shader_parameter("wash_amount", 0.0)
	_wash_tween = create_tween()
	_wash_tween.tween_property(_mat, "shader_parameter/wash_amount", clampf(amount, 0.0, 1.0), 0.06) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_wash_tween.tween_property(_mat, "shader_parameter/wash_amount", 0.0, duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
