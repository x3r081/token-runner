extends CanvasLayer
## Full-screen post-processing, created at runtime by world.gd.
##
## VISUAL_BIBLE_V2 LAW 5: post-processing is INVISIBLE. Round 6 deleted the
## whole per-region film-stock system that used to live in this file — a ten-
## entry GRADES table, fourteen crossfading uniforms per region change, the
## "stress" grade that smeared the frame as technical debt climbed, and the
## gpu_mines heat-haze pass with its BackBufferCopy. Between them they were
## responsible for the two loudest complaints about the QA frames: every region
## reading as one flat colour soup corner to corner, and every glyph in the game
## wearing a red/cyan fringe.
##
## Region mood now comes from where it should: the ambient CanvasModulate and
## the region's own lights (world.gd), not from a filter over the top.
##
## Layer 0 sits above the world's default canvas and below every UI CanvasLayer
## (HUD=1, dialogue=10, popups=15, opening=100), so the pass touches the game
## and never the menus. Draw order, bottom to top:
##   PostFX (neutral grade + vignette + grain) -> RegionFade (the entry curtain).
## Everything here is cosmetic: mouse_filter IGNORE, input is never blocked.
##
## Three entry points, all kept for their callers in world.gd:
##   set_region()  records the region. No longer regrades the frame.
##   set_stress()  records debt pressure. No longer touches a pixel.
##   pulse()       one short flash on a debt incident — an EVENT, not a filter.

const POSTFX_SHADER := "res://assets/shaders/postfx.gdshader"

## The one look. LAW 5's numbers, exactly: aberration and scanlines gone from
## the shader entirely, grain <= 0.012, vignette 0.14 on a wide plateau, and a
## neutral grade (no lift, gamma 1.0, saturation 1.0).
const VIGNETTE := 0.14
const GRAIN := 0.010

var _mat: ShaderMaterial
var _fade: ColorRect
var _fade_tween: Tween
var _wash_tween: Tween
## Last region asked for. Kept so callers can still ask, and so a future
## per-region nudge has somewhere to live; nothing reads it today.
var _region := ""
## Last stress value asked for, 0..1. Recorded, deliberately not rendered.
var _stress := 0.0

func _ready() -> void:
	# The fade curtain must never be frozen mid-transition by a pausing popup
	# (random events / dialogue pause the tree) — that strands a black screen.
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 0

	var rect := _screen_rect("PostFX")
	if ResourceLoader.exists(POSTFX_SHADER):
		_mat = ShaderMaterial.new()
		_mat.shader = load(POSTFX_SHADER)
		# Seed every uniform before anything animates one — an unset shader
		# parameter reads back as null, and tweening from null is a crash with
		# extra steps.
		_mat.set_shader_parameter("intensity", 1.0)
		_mat.set_shader_parameter("vignette_strength", VIGNETTE)
		_mat.set_shader_parameter("grain_amount", GRAIN)
		_mat.set_shader_parameter("grade_lift", Vector3.ZERO)
		_mat.set_shader_parameter("saturation", 1.0)
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

## Records the region. There is deliberately nothing to crossfade any more: one
## grade, every room. A region is told apart by its light and its palette, which
## is how the games this project is aiming at do it — a filter that changes at a
## doorway reads as a filter, and LAW 5 says the post must never be nameable.
func set_region(region_id: String) -> void:
	_region = region_id

## Records debt pressure for anything that wants to ask. The old implementation
## drained saturation, thickened the grain, heated the corners and slipped
## scanlines sideways as technical debt climbed — comedy paid for in legibility,
## on the frame the player is trying to fight in. The joke lives in dialogue and
## prop text now (LAW 10); the frame stays clean.
func set_stress(value: float, _duration: float = 1.2) -> void:
	_stress = clampf(value, 0.0, 1.0)

## One short coloured flash over the whole frame — an incident landing. Short
## enough to register as an event and not as a filter, and 0 the rest of the
## time, which is the only reason a full-frame wash is allowed to exist at all.
func pulse(color: Color, amount: float = 0.10, duration: float = 0.45) -> void:
	if not _mat:
		return
	if _wash_tween and _wash_tween.is_valid():
		_wash_tween.kill()
	_mat.set_shader_parameter("wash_color", color)
	_mat.set_shader_parameter("wash_amount", 0.0)
	_wash_tween = create_tween()
	_wash_tween.tween_property(_mat, "shader_parameter/wash_amount", clampf(amount, 0.0, 0.16), 0.06) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_wash_tween.tween_property(_mat, "shader_parameter/wash_amount", 0.0, duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
