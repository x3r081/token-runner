class_name FxLib
extends RefCounted
## Shared gameplay-juice helpers: bloom-friendly materials, exists()-guarded FX
## textures, camera trauma, spark bursts, ring flashes, and hit-stop. One place,
## so every system blooms the same way instead of ten slightly different ways.

const GLOW_DOT_PATH := "res://assets/textures/generated/fx_glow_dot.png"
const SPARK_PATH := "res://assets/textures/generated/fx_spark.png"
const RADIAL_SOFT_PATH := "res://assets/textures/generated/fx_radial_soft.png"

static var _add_mat: CanvasItemMaterial
static var _light_tex: Texture2D
static var _white_tex: Texture2D
static var _glow_dot_tex: Texture2D
static var _glow_dot_checked := false
static var _spark_tex: Texture2D
static var _spark_checked := false
static var _hit_stopped := false

## One shared additive material — identical params everywhere, so every glow in
## the game reuses a single instance (see VISUAL_BIBLE, HDR trick #2).
static func additive_material() -> CanvasItemMaterial:
	if _add_mat == null:
		_add_mat = CanvasItemMaterial.new()
		_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _add_mat

## Soft 16x16 particle dot, or null when the pixel-art agent hasn't shipped it.
static func glow_dot() -> Texture2D:
	if not _glow_dot_checked:
		_glow_dot_checked = true
		if ResourceLoader.exists(GLOW_DOT_PATH):
			_glow_dot_tex = load(GLOW_DOT_PATH)
	return _glow_dot_tex

## Hard 8x8 spark, or null. Callers must tolerate null (CPUParticles2D renders
## plain scaled pixels without a texture, which is an acceptable fallback).
static func spark() -> Texture2D:
	if not _spark_checked:
		_spark_checked = true
		if ResourceLoader.exists(SPARK_PATH):
			_spark_tex = load(SPARK_PATH)
	return _spark_tex

## Radial falloff for PointLight2D cookies. Falls back to a generated gradient
## so lights never silently fail to render for want of a PNG.
static func light_texture() -> Texture2D:
	if _light_tex == null:
		if ResourceLoader.exists(RADIAL_SOFT_PATH):
			_light_tex = load(RADIAL_SOFT_PATH)
		else:
			var grad := Gradient.new()
			grad.set_color(0, Color(1, 1, 1, 1))
			grad.set_color(1, Color(1, 1, 1, 0))
			var tex := GradientTexture2D.new()
			tex.gradient = grad
			tex.fill = GradientTexture2D.FILL_RADIAL
			tex.fill_from = Vector2(0.5, 0.5)
			tex.fill_to = Vector2(0.5, 0.0)
			tex.width = 128
			tex.height = 128
			_light_tex = tex
	return _light_tex

## Plain white quad for fully-procedural shaders (portal_swirl ignores TEXTURE).
static func white_square(size: int = 64) -> Texture2D:
	if _white_tex == null:
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white_tex = ImageTexture.create_from_image(img)
	return _white_tex

## Attach a soft PointLight2D to `parent`. Returns it for further tuning.
static func point_light(parent: Node, color: Color, energy: float, tex_scale: float, offset := Vector2.ZERO) -> PointLight2D:
	var light := PointLight2D.new()
	light.texture = light_texture()
	light.color = color
	light.energy = energy
	light.texture_scale = tex_scale
	light.shadow_enabled = false
	light.position = offset
	parent.add_child(light)
	return light

## Kick the trauma-shake camera rig. Null-safe: the camera_fx node may not
## exist yet (tests, or the camera agent hasn't shipped) — then it's a no-op.
static func add_trauma(tree: SceneTree, amount: float) -> void:
	if tree == null:
		return
	var fx := tree.get_first_node_in_group("camera_fx")
	if fx and fx.has_method("add_trauma"):
		fx.add_trauma(amount)

## ~40ms of near-frozen time so kills land with weight. Never while paused or
## mid-dialogue, never stacked, and the restore timer ignores time_scale (and
## runs while paused), so the freeze physically cannot stick.
static func hit_stop(tree: SceneTree, time_scale := 0.05, duration := 0.04) -> void:
	if tree == null or tree.paused or _hit_stopped:
		return
	if Engine.time_scale < 0.999:
		return
	if DialogueManager and DialogueManager.is_active:
		return
	if GameManager.state != GameManager.GameState.PLAYING:
		return
	FxLib._hit_stopped = true
	Engine.time_scale = time_scale
	var timer := tree.create_timer(duration, true, false, true)
	timer.timeout.connect(func() -> void:
		Engine.time_scale = 1.0
		FxLib._hit_stopped = false
	)

## One-shot particle burst, parented to `parent` (not the dying thing) so it
## outlives its cause; self-frees via `finished`. Overbright colors welcome.
static func burst(parent: Node, pos: Vector2, color: Color, count: int = 12, speed_max: float = 220.0, tex: Texture2D = null, grav := Vector2.ZERO) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := CPUParticles2D.new()
	p.emitting = true
	p.one_shot = true
	p.amount = count
	p.lifetime = 0.42
	p.explosiveness = 1.0
	p.spread = 180.0
	p.initial_velocity_min = speed_max * 0.35
	p.initial_velocity_max = speed_max
	p.gravity = grav
	p.color = color
	p.z_index = 560
	if tex:
		p.texture = tex
		p.material = additive_material()
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.4
	else:
		p.scale_amount_min = 1.8
		p.scale_amount_max = 3.4
	parent.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)

## Expanding overbright ring flash (fx_glow_dot). Silently skips when the art
## is missing; fades and frees itself.
static func flash(parent: Node, pos: Vector2, color: Color, start_scale := 0.4, end_scale := 2.6, duration := 0.25) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var tex := glow_dot()
	if tex == null:
		return
	var s := Sprite2D.new()
	s.texture = tex
	s.material = additive_material()
	s.modulate = Color(color.r * 2.2, color.g * 2.2, color.b * 2.2, 0.9)
	s.scale = Vector2.ONE * start_scale
	s.z_index = 560
	parent.add_child(s)
	s.global_position = pos
	var tw := s.create_tween()
	tw.tween_property(s, "scale", Vector2.ONE * end_scale, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(s, "modulate:a", 0.0, duration)
	tw.tween_callback(s.queue_free)
