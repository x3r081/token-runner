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

## Per-region film stock. Round 5: the round-4 grade differed between regions by
## little more than a hue push, so every region came out as ONE colour from
## corner to corner — red soup, green soup, magenta soup in the QA frames. A
## region is a look now, not a tint: it has its own black level, its own curve,
## its own split-tone (shadows one hue, highlights the complementary one), its
## own bleach point, its own bloom threshold and its own grain. The regions still
## share one art direction because they share the same TOOLS — a Kodak and a
## Fuji stock of the same camera, not two different cameras.
##
## Fields, all consumed by postfx.gdshader:
##   lift      shadow tint (added before the curve)
##   gain      highlight tint (luma-weighted, the other half of the split-tone)
##   black     black re-anchor — how much haze gets cut out of the shadows
##   con/sat   S-curve amount / saturation
##   bleach    how hard the top end goes toward white instead of toward hue
##   clarity   mid-frequency local contrast (the "crisp" knob)
##   bloom/thr/btint  selective bloom amount, threshold, colour. These are
##                    deliberately small: world.gd::_setup_glow() already puts a
##                    WorldEnvironment with glow_enabled + glow_hdr_threshold
##                    1.0 over the whole viewport, so every overbright pixel the
##                    artists authored blooms in the ENGINE too. The shader pass
##                    exists for the near-white band the engine threshold misses
##                    and for the per-region tint; run it hot and the two passes
##                    stack on the same emissive and blow it to white.
##   vig/aberr/grain/scan  lens and film-stock character
const GRADE_DEFAULT := {
	"lift": Vector3(0.012, 0.008, 0.030),
	"gain": Vector3(1.0, 1.0, 1.0),
	"black": 0.024,
	"con": 0.14,
	"sat": 1.14,
	"bleach": 0.26,
	"clarity": 0.18,
	"bloom": 0.26,
	"thr": 0.90,
	"btint": Vector3(1.0, 0.96, 0.90),
	"vig": 0.28,
	"aberr": 1.1,
	"grain": 0.028,
	"scan": 0.040,
}

const GRADES := {
	# Warm lamp-light in a cold flat: amber highlights over indigo shadows.
	"localhost": {
		"lift": Vector3(0.014, 0.010, 0.030), "gain": Vector3(1.06, 1.00, 0.92),
		"black": 0.022, "con": 0.15, "sat": 1.12, "bleach": 0.20, "clarity": 0.16,
		"bloom": 0.28, "thr": 0.86, "btint": Vector3(1.00, 0.92, 0.80),
		"vig": 0.26, "aberr": 1.0, "grain": 0.030, "scan": 0.045,
	},
	# Furnace. The old grade let the ambient red own every pixel; the shadows are
	# now COLD and the top end bleaches out, which is what makes heat read as
	# heat rather than as a red filter. Bloom threshold sits AT 1.0 so only the
	# genuine HDR ember cores pick up a halo on top of the engine glow.
	"gpu_mines": {
		"lift": Vector3(0.004, 0.012, 0.030), "gain": Vector3(1.10, 0.96, 0.86),
		"black": 0.032, "con": 0.22, "sat": 1.00, "bleach": 0.42, "clarity": 0.22,
		"bloom": 0.26, "thr": 1.00, "btint": Vector3(1.00, 0.80, 0.62),
		"vig": 0.30, "aberr": 1.4, "grain": 0.038, "scan": 0.050,
	},
	# Still the most desaturated and most contrasty grade in the game: hot,
	# bleached and out of patience. Grain is the heaviest anywhere — an incident
	# looks like footage, not like a screenshot.
	"production": {
		"lift": Vector3(0.006, 0.010, 0.026), "gain": Vector3(1.10, 0.94, 0.92),
		"black": 0.032, "con": 0.24, "sat": 0.92, "bleach": 0.46, "clarity": 0.20,
		"bloom": 0.22, "thr": 1.02, "btint": Vector3(1.00, 0.78, 0.76),
		"vig": 0.33, "aberr": 1.9, "grain": 0.044, "scan": 0.055,
	},
	# Clinical: the cleanest glass in the game. Almost no grain, almost no
	# fringing, the widest clean centre, and the most clarity — a datacentre is
	# lit for cameras, not for atmosphere.
	"cloud_district": {
		"lift": Vector3(0.010, 0.017, 0.034), "gain": Vector3(0.96, 1.00, 1.08),
		"black": 0.016, "con": 0.11, "sat": 1.06, "bleach": 0.30, "clarity": 0.24,
		"bloom": 0.30, "thr": 0.90, "btint": Vector3(0.86, 0.95, 1.00),
		"vig": 0.18, "aberr": 0.6, "grain": 0.014, "scan": 0.022,
	},
	# Sterile. Neutral to the point of rudeness: nothing is warm, nothing is
	# saturated, and the frame is very slightly blue because the ceiling is.
	"corporate_enterprise": {
		"lift": Vector3(0.008, 0.012, 0.028), "gain": Vector3(0.97, 1.00, 1.06),
		"black": 0.018, "con": 0.09, "sat": 0.96, "bleach": 0.24, "clarity": 0.22,
		"bloom": 0.22, "thr": 0.94, "btint": Vector3(0.88, 0.94, 1.00),
		"vig": 0.22, "aberr": 0.55, "grain": 0.012, "scan": 0.020,
	},
	# The one genuinely rich grade: gold highlights, violet shadows, the most
	# bloom in the game. Money is allowed to look like money.
	"token_vault": {
		"lift": Vector3(0.020, 0.010, 0.036), "gain": Vector3(1.10, 1.02, 0.86),
		"black": 0.028, "con": 0.18, "sat": 1.20, "bleach": 0.26, "clarity": 0.18,
		"bloom": 0.36, "thr": 0.88, "btint": Vector3(1.00, 0.90, 0.66),
		"vig": 0.30, "aberr": 1.0, "grain": 0.026, "scan": 0.038,
	},
	# Night market: magenta everywhere is the failure mode, so the highlights go
	# GOLD and the shadows stay cool. Same palette, three value levels instead
	# of one.
	"api_bazaar": {
		"lift": Vector3(0.014, 0.008, 0.032), "gain": Vector3(1.08, 0.98, 0.94),
		"black": 0.028, "con": 0.18, "sat": 1.18, "bleach": 0.34, "clarity": 0.20,
		"bloom": 0.34, "thr": 0.88, "btint": Vector3(1.00, 0.86, 0.78),
		"vig": 0.26, "aberr": 1.35, "grain": 0.030, "scan": 0.042,
	},
	# Sickly green — but the shadows lean violet, which is the only reason the
	# frame reads as foliage-at-night and not as a green gel over the lens.
	"open_source_wildlands": {
		"lift": Vector3(0.020, 0.010, 0.026), "gain": Vector3(1.02, 1.06, 0.90),
		"black": 0.030, "con": 0.20, "sat": 1.10, "bleach": 0.34, "clarity": 0.24,
		"bloom": 0.26, "thr": 0.92, "btint": Vector3(0.84, 1.00, 0.78),
		"vig": 0.28, "aberr": 0.9, "grain": 0.032, "scan": 0.040,
	},
	# Same family, one notch grubbier and one notch dimmer.
	"dependency_district": {
		"lift": Vector3(0.022, 0.012, 0.024), "gain": Vector3(1.00, 1.05, 0.88),
		"black": 0.030, "con": 0.19, "sat": 1.08, "bleach": 0.30, "clarity": 0.22,
		"bloom": 0.26, "thr": 0.92, "btint": Vector3(0.86, 1.00, 0.74),
		"vig": 0.29, "aberr": 1.0, "grain": 0.034, "scan": 0.042,
	},
	# Dust and old paper. Desaturated, sepia-gained, a low soft bloom.
	"stackoverflow_ruins": {
		"lift": Vector3(0.020, 0.014, 0.014), "gain": Vector3(1.06, 1.00, 0.90),
		"black": 0.028, "con": 0.16, "sat": 0.98, "bleach": 0.28, "clarity": 0.20,
		"bloom": 0.24, "thr": 0.92, "btint": Vector3(1.00, 0.92, 0.76),
		"vig": 0.30, "aberr": 0.9, "grain": 0.036, "scan": 0.044,
	},
}

var _mat: ShaderMaterial
var _haze: ColorRect
var _haze_mat: ShaderMaterial
var _haze_copy: BackBufferCopy
var _fade: ColorRect
var _grade_tween: Tween
var _fade_tween: Tween
var _stress_tween: Tween
var _wash_tween: Tween
## Last region asked for, so a graphics-quality change can re-apply the grade
## without world.gd having to know that the setting exists.
var _region := ""
var _full_quality := true

func _ready() -> void:
	# The fade curtain must never be frozen mid-transition by a pausing popup
	# (random events / dialogue pause the tree) — that strands a black screen.
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 0
	_full_quality = int(SettingsManager.get_setting("graphics_quality")) >= 1
	if not SettingsManager.settings_changed.is_connected(_on_settings_changed):
		SettingsManager.settings_changed.connect(_on_settings_changed)
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
		# as null, and tweening from null is a crash with extra steps. Every
		# field of GRADE_DEFAULT has to be in here for the same reason.
		_mat.set_shader_parameter("grade_lift", GRADE_DEFAULT["lift"])
		_mat.set_shader_parameter("grade_gain", GRADE_DEFAULT["gain"])
		_mat.set_shader_parameter("black_point", GRADE_DEFAULT["black"])
		_mat.set_shader_parameter("aberration", GRADE_DEFAULT["aberr"])
		_mat.set_shader_parameter("vignette_strength", GRADE_DEFAULT["vig"])
		_mat.set_shader_parameter("saturation", GRADE_DEFAULT["sat"])
		_mat.set_shader_parameter("contrast", GRADE_DEFAULT["con"])
		_mat.set_shader_parameter("highlight_desat", GRADE_DEFAULT["bleach"])
		_mat.set_shader_parameter("clarity", (GRADE_DEFAULT["clarity"] if _full_quality else 0.0))
		_mat.set_shader_parameter("bloom_intensity", (GRADE_DEFAULT["bloom"] if _full_quality else 0.0))
		_mat.set_shader_parameter("bloom_threshold", GRADE_DEFAULT["thr"])
		_mat.set_shader_parameter("bloom_knee", 0.35)
		_mat.set_shader_parameter("bloom_tint", GRADE_DEFAULT["btint"])
		_mat.set_shader_parameter("grain_amount", GRADE_DEFAULT["grain"])
		_mat.set_shader_parameter("scanline_amount", GRADE_DEFAULT["scan"])
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

## Per-region screen chemistry — see the GRADES table for what each region is
## trying to be. Everything crossfades over 0.6s so walking through a portal
## reads as a change of light rather than as a cut.
##
## Round 4 kept the vignette CURVE in the shader (a wide clean plateau to ~0.42
## of the frame radius plus a corner-commit term), so these per-region strengths
## price only the edges, not the mid-ground.
##
## Round 5 added the other four dimensions a real grade has — black level,
## highlight tint, bleach point and bloom threshold — plus per-region grain and
## scanline weight, so "different region" is no longer spelled entirely in hue.
func set_region(region_id: String) -> void:
	_region = region_id
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
	var g := _grade_for(region_id)
	if _grade_tween and _grade_tween.is_valid():
		_grade_tween.kill()
	_grade_tween = create_tween().set_parallel(true)
	_ramp("grade_lift", g["lift"])
	_ramp("grade_gain", g["gain"])
	_ramp("black_point", g["black"])
	_ramp("aberration", g["aberr"])
	_ramp("vignette_strength", g["vig"])
	_ramp("saturation", g["sat"])
	_ramp("contrast", g["con"])
	_ramp("highlight_desat", g["bleach"])
	_ramp("clarity", (g["clarity"] if _full_quality else 0.0))
	_ramp("bloom_intensity", (g["bloom"] if _full_quality else 0.0))
	_ramp("bloom_threshold", g["thr"])
	_ramp("bloom_tint", g["btint"])
	_ramp("grain_amount", g["grain"])
	_ramp("scanline_amount", g["scan"])

## The region's grade, with every missing field falling back to the house look —
## so an unlisted region is still graded, just not characterised.
func _grade_for(region_id: String) -> Dictionary:
	var g := GRADE_DEFAULT.duplicate()
	var over: Dictionary = GRADES.get(region_id, {})
	for key: String in over:
		g[key] = over[key]
	return g

## One crossfading uniform. All of them ride the same tween so the whole grade
## arrives together instead of in fourteen separate little slides.
func _ramp(param: String, value: Variant) -> void:
	_grade_tween.tween_property(_mat, "shader_parameter/" + param, value, 0.6) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## Reduced quality drops the two costly terms (the mip-chain bloom taps and the
## clarity tap) and keeps the whole rest of the grade — "Reduced" should cost
## the player frame time, not the art direction.
func _on_settings_changed() -> void:
	var full := int(SettingsManager.get_setting("graphics_quality")) >= 1
	if full == _full_quality:
		return
	_full_quality = full
	if _region != "":
		set_region(_region)
	elif _mat:
		_mat.set_shader_parameter("bloom_intensity", (GRADE_DEFAULT["bloom"] if full else 0.0))
		_mat.set_shader_parameter("clarity", (GRADE_DEFAULT["clarity"] if full else 0.0))

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
