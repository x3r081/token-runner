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
static var _hit_stop_scale := 1.0
static var _hit_stop_serial := 0
static var _fade_grad: Gradient

# ------------------------------------------------------------- FX budget ----
## Combat does not fire evenly — it fires in clumps. A piercing Stack Trace
## through six enemies is six impacts, six damage numbers and six spark sprays
## inside ONE physics flush, and a boss death detonates five shockwaves in half
## a second. Rather than let that stack without limit, every emitter this file
## creates books its cost against a per-frame particle allowance and a
## concurrent-emitter cap.
##
## The numbers, reasoned rather than guessed:
##   * a heavy impact asks for ~24 particles; six in one frame is ~144, and the
##     visible difference between 144 and 96 sparks arriving in the same 16ms is
##     nothing at all — so 96 is the frame ceiling;
##   * emitters live 0.34-0.5s, so 26 concurrent is roughly four frames of an
##     unbroken six-enemy brawl before new sprays start being skipped;
##   * flare lights are the expensive one (each is a real PointLight2D touching
##     the 2D lighting pass), so they get a much tighter cap of 8.
## Over budget, effects THIN OUT and then stop. The tween-driven layers (rings,
## flashes, spike stars) are never budgeted, so a starved frame loses density,
## never legibility — and nothing here can ever raise an error.
const FX_FRAME_PARTICLES := 96
const FX_MAX_EMITTERS := 26
const FX_MAX_FLARES := 8

static var _fx_frame := -1
static var _fx_spent := 0
static var _fx_live := 0
static var _flares := 0

## Book `want` particles against this physics frame's allowance. Returns how
## many may actually be emitted — 0 means "skip the emitter entirely".
static func budget(want: int) -> int:
	if want <= 0:
		return 0
	var frame := Engine.get_physics_frames()
	if frame != _fx_frame:
		FxLib._fx_frame = frame
		FxLib._fx_spent = 0
	if _fx_live >= FX_MAX_EMITTERS:
		return 0
	var left: int = FX_FRAME_PARTICLES - _fx_spent
	if left <= 2:
		return 0
	var give: int = mini(want, left)
	FxLib._fx_spent += give
	return give

## Shared "particles fade out instead of blinking out" ramp. One instance for
## every burst in the game; CPUParticles2D multiplies it by `color`, so the
## overbright colours callers pass survive.
static func fade_ramp() -> Gradient:
	if _fade_grad == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		g.colors = PackedColorArray([
			Color(1.0, 1.0, 1.0, 1.0),
			Color(1.0, 1.0, 1.0, 0.82),
			Color(1.0, 1.0, 1.0, 0.0)])
		_fade_grad = g
	return _fade_grad

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

## Push a colour to full value and boosted chroma WITHOUT changing its hue.
## The bible's per-region accents include several muted ones (stackoverflow gold
## #E8C46B, cloud sky #6BC7FF, corporate #4D7CFF); multiplied by a dark ambient
## CanvasModulate they collapse into brown/grey sludge. Anything that has to
## read as "energy" — portals, threat halos, danger rims — runs through here
## first. Near-white inputs degrade gracefully (they stay near-white).
static func vivid(c: Color, chroma: float = 1.45) -> Color:
	var mx: float = maxf(c.r, maxf(c.g, c.b))
	if mx <= 0.001:
		return c
	var n := Color(c.r / mx, c.g / mx, c.b / mx, c.a)
	var lum: float = n.r * 0.299 + n.g * 0.587 + n.b * 0.114
	return Color(
		clampf(lum + (n.r - lum) * chroma, 0.0, 1.0),
		clampf(lum + (n.g - lum) * chroma, 0.0, 1.0),
		clampf(lum + (n.b - lum) * chroma, 0.0, 1.0),
		c.a)

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
## mid-dialogue, and the restore timer ignores time_scale (and runs while
## paused), so the freeze physically cannot stick.
##
## Freezes no longer simply swallow each other: a HARDER freeze may take over
## from a softer one mid-flight. That matters because the ordinary case is a
## crit that also kills — the crit's 45ms nudge used to claim the clock and the
## kill's real freeze was dropped on the floor, which is exactly backwards. The
## takeover is serial-guarded, so only the newest freeze restores the clock and
## an older timer firing late can never un-freeze the current one.
static func hit_stop(tree: SceneTree, time_scale := 0.05, duration := 0.04) -> void:
	if tree == null or tree.paused:
		return
	if DialogueManager and DialogueManager.is_active:
		return
	if GameManager.state != GameManager.GameState.PLAYING:
		return
	if _hit_stopped:
		if time_scale >= _hit_stop_scale:
			return  # an equal-or-harder freeze already owns the clock
	elif Engine.time_scale < 0.999:
		return  # somebody else is driving time; do not fight them
	FxLib._hit_stopped = true
	FxLib._hit_stop_scale = time_scale
	FxLib._hit_stop_serial += 1
	var serial: int = _hit_stop_serial
	Engine.time_scale = time_scale
	var timer := tree.create_timer(duration, true, false, true)
	timer.timeout.connect(func() -> void:
		if FxLib._hit_stop_serial != serial:
			return  # a harder freeze took over; it owns the restore
		Engine.time_scale = 1.0
		FxLib._hit_stop_scale = 1.0
		FxLib._hit_stopped = false
	)

## Force time back to normal AND hand the FX budget back. Static state outliving
## a scene change is exactly the bug class this project keeps finding, so
## anything that tears the world down (new game, death, scene swap) can call this
## and be certain.
##
## The budget counters are decremented by `tree_exited`, which fires reliably, so
## clearing them here is belt-and-braces rather than a fix — but a counter that
## drifts upward only ever fails ONE way (bursts and flares silently stop for the
## rest of the session), and that is precisely the kind of invisible failure this
## project has been bitten by. Zeroing is safe at any time: every decrement is
## `maxi(0, n - 1)`, so emitters still in flight cannot push the counters
## negative on their way out.
static func release_hit_stop() -> void:
	FxLib._hit_stop_serial += 1
	FxLib._hit_stopped = false
	FxLib._hit_stop_scale = 1.0
	FxLib._fx_frame = -1
	FxLib._fx_spent = 0
	FxLib._fx_live = 0
	FxLib._flares = 0
	if Engine.time_scale < 0.999:
		Engine.time_scale = 1.0

## One-shot particle burst, parented to `parent` (not the dying thing) so it
## outlives its cause; self-frees via `finished`. Overbright colors welcome.
##
## Everything past `z` is additive and optional, so the ~30 existing call sites
## are untouched: pass `dir`/`spread` for a cone thrown along a direction rather
## than a uniform ball, `life` for how long the debris hangs around, and
## `scale_mult` to size the grains. Particles now DAMP (they throw and settle
## instead of sliding away at constant speed), TUMBLE, and FADE via the shared
## ramp instead of blinking out of existence — that last one is most of why the
## old bursts read as "confetti" rather than "sparks".
static func burst(parent: Node, pos: Vector2, color: Color, count: int = 12, speed_max: float = 220.0, tex: Texture2D = null, grav := Vector2.ZERO, z: int = 560, dir := Vector2.ZERO, spread := 180.0, life := 0.42, scale_mult := 1.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var give := budget(count)
	if give <= 0:
		return
	var p := CPUParticles2D.new()
	p.emitting = true
	p.one_shot = true
	p.amount = give
	p.lifetime = maxf(0.08, life)
	p.explosiveness = 1.0
	if dir.length_squared() > 0.0001:
		p.direction = dir.normalized()
		p.spread = clampf(spread, 1.0, 180.0)
	else:
		p.spread = 180.0
	p.initial_velocity_min = speed_max * 0.35
	p.initial_velocity_max = speed_max
	p.damping_min = speed_max * 0.30
	p.damping_max = speed_max * 0.85
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -260.0
	p.angular_velocity_max = 260.0
	p.gravity = grav
	p.color = color
	p.color_ramp = fade_ramp()
	p.z_index = z
	if tex:
		p.texture = tex
		p.material = additive_material()
		p.scale_amount_min = 0.6 * scale_mult
		p.scale_amount_max = 1.4 * scale_mult
	else:
		p.scale_amount_min = 1.8 * scale_mult
		p.scale_amount_max = 3.4 * scale_mult
	FxLib._fx_live += 1
	p.tree_exited.connect(func() -> void:
		FxLib._fx_live = maxi(0, FxLib._fx_live - 1))
	parent.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)

## Expanding overbright ring flash (fx_glow_dot). Silently skips when the art
## is missing; fades and frees itself.
##
## Two layers, because one was never enough: a soft accent bloom that expands
## across the whole duration, and a WHITE-HOT core that expands less and dies in
## a third of the time. That timing difference is what makes a flash read as an
## impact rather than as a coloured circle — the eye sees a white pop first and
## the colour second, which is the order real light arrives in.
static func flash(parent: Node, pos: Vector2, color: Color, start_scale := 0.4, end_scale := 2.6, duration := 0.25, z: int = 560) -> void:
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
	s.z_index = z
	parent.add_child(s)
	s.global_position = pos
	var tw := s.create_tween()
	tw.tween_property(s, "scale", Vector2.ONE * end_scale, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(s, "modulate:a", 0.0, duration)
	tw.tween_callback(s.queue_free)
	var core := Sprite2D.new()
	core.texture = tex
	core.material = additive_material()
	core.modulate = Color(3.0, 3.0, 3.0, 1.0)
	core.scale = Vector2.ONE * start_scale * 0.62
	core.z_index = z + 1
	parent.add_child(core)
	core.global_position = pos
	var ct := core.create_tween()
	ct.tween_property(core, "scale", Vector2.ONE * end_scale * 0.44, duration * 0.36) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	ct.parallel().tween_property(core, "modulate:a", 0.0, duration * 0.36).set_ease(Tween.EASE_IN)
	ct.tween_callback(core.queue_free)

# The brightest an impact flare may ever be. The bible puts PROP lights at
# 0.5-1.4 and forbids strobing; a flare is allowed above that because it lives
# for a fifth of a second — but callers compute energy from damage and crit
# multipliers, and an un-clamped product (a buffed crit reaches ~3.8) would white
# out an intentionally dark room several times a second. Clamped, not trusted.
const FLARE_MAX_ENERGY := 2.4

## A light that exists for a quarter of a second. Impacts, kills and detonations
## should light the ROOM, not just draw a sprite on top of it — in a game this
## dark that is the single cheapest way to make a hit feel physical.
## Hard-capped at FX_MAX_FLARES concurrent, because each one is a real light
## touching the 2D lighting pass; over the cap this is a silent no-op.
## `energy` is clamped to FLARE_MAX_ENERGY.
static func flare(parent: Node, pos: Vector2, color: Color, energy := 1.6, tex_scale := 0.9, duration := 0.24) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	if _flares >= FX_MAX_FLARES:
		return
	FxLib._flares += 1
	var light := PointLight2D.new()
	light.texture = light_texture()
	light.color = color
	light.energy = 0.0
	light.texture_scale = maxf(0.05, tex_scale)
	light.shadow_enabled = false
	light.tree_exited.connect(func() -> void:
		FxLib._flares = maxi(0, FxLib._flares - 1))
	parent.add_child(light)
	light.global_position = pos
	var peak: float = clampf(energy, 0.0, FLARE_MAX_ENERGY)
	var tw := light.create_tween()
	tw.tween_property(light, "energy", peak, duration * 0.18).set_ease(Tween.EASE_OUT)
	tw.tween_property(light, "energy", 0.0, duration * 0.82).set_ease(Tween.EASE_IN)
	tw.tween_callback(light.queue_free)
