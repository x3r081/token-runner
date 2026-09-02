extends Area2D
class_name Projectile

var direction := Vector2.RIGHT
var damage: int = 10
var speed: float = 400.0
var lifetime: float = 2.0
var pierce := false
var proj_type := "prompt_blast"
## Set by Player before the bolt enters the tree.
## `weak`: the model hallucinated — the shot is a confident, useless sputter.
## `crit`: this one is going to hurt, and it is going to say so.
var weak := false
var crit := false
var _hit: Array = []
var _accent := Color(0.25, 0.95, 0.86)
var _trail: Line2D
## A second, thinner, white-hot trail drawn on top of the accent one. Two trails
## of different widths and colours are what make a bolt read as a bolt at speed
## instead of as a coloured smear — the eye tracks the hot line and reads the
## wide one as its glow.
var _core_trail: Line2D
var _pierce_count := 0
var _origin := Vector2.ZERO
var _size_mult := 1.0

@onready var sprite: ColorRect = $ColorRect

const TRAIL_POINTS := 12

## Travelling heat haze is a SCREEN-READING effect: every bolt carrying one
## forces a back-buffer copy. One bolt looks great; five in the air during a
## Stack Trace volley is a measurable GPU cost for an effect nobody can see at
## that speed. So it is reserved for the shots that earn it (crits and traces)
## and hard-capped globally. Everything else buys its presence with sprites,
## which are free.
const MAX_HAZE := 2
static var _live_haze := 0

## Stack Trace prints one frame per enemy it punches through. The last line is
## always "... 47 more", because the last line is always "... 47 more".
const STACK_FRAMES := [
	"at main()", "at handler()", "at retry()", "at Object.<anonymous>",
	"at process._tickCallback", "at doTheThing()", "at ???",
	"at node_modules/left-pad/index.js:1",
]

## What a hallucinated bolt says when it runs out of road. Decorative only —
## the information ("that shot did nothing, and here is why") is carried by the
## bolt visibly losing cohesion; this is just the model's excuse.
const FIZZLE_LINES := [
	"[citation needed]",
	"confidently",
	"source: trust me",
	"as we all know",
	"temperature was high",
	"no such function",
]

func _ready() -> void:
	add_to_group("player_projectile")
	collision_layer = 16
	collision_mask = 2
	area_entered.connect(_on_area_entered)
	_origin = global_position
	# Depth: above every world prop (which y-sort up to ~1050) and above the
	# WorldLabel plates at 1150, so your own shot is never swallowed by scenery.
	# Below NPC name tags is fine — a bolt is in flight for a fifth of a second.
	z_index = CombatFx.Z_FX
	_build_visuals()

## A real bolt of light, built in THREE layers so it has a shape rather than a
## colour: an accent body, a WHITE-HOT core (overbright, so HDR bloom picks it
## up), and a per-type decoration. Behind it, two trails and a small PointLight2D.
## Falls back to the legacy ColorRect when the generated art is missing.
##
## The fourth layer — a wide soft outer glow at 3.5x — is gone. Three stacked
## radial gradients is how a bolt becomes a smooth blob with rays instead of a
## shape, which is the read the QA critique named on the boss; the body and the
## core already say "hot thing travelling fast", and the trail says which way.
##
## Each ability is meant to be identifiable in flight without reading the HUD:
##   * Prompt Blast — a compact cyan bolt with a breathing core;
##   * Stack Trace  — a long magenta lance inside a spinning trace ring;
##   * hallucinated — a small violet thing that tumbles and flickers;
##   * a crit of any of the above — gold-hot, fatter, wearing two chevrons.
func _build_visuals() -> void:
	_size_mult = 1.0
	if proj_type == "stack_trace":
		# A faster, longer, magenta piercing beam.
		speed = 560.0
		lifetime = 1.4
		_accent = Color(1.0, 0.28, 0.68)
		_size_mult = 1.15
	if weak:
		# Hallucinated: violet, slow, and visibly out of ideas.
		_accent = Color(0.55, 0.36, 0.96)
		speed *= 0.62
		lifetime = 0.75
		_size_mult = 0.6
	elif crit:
		# Crit: gold-hot and fatter, so you can see it coming before it lands.
		_accent = _accent.lerp(Color(1.0, 0.83, 0.30), 0.55)
		_size_mult *= 1.45
	var dot := FxLib.glow_dot()
	if dot:
		sprite.visible = false
		var is_lance: bool = proj_type == "stack_trace"
		# 1. Body — the accent at full strength.
		var halo := Sprite2D.new()
		halo.texture = dot
		halo.material = FxLib.additive_material()
		halo.modulate = Color(_accent.r * 2.2, _accent.g * 2.2, _accent.b * 2.2, 0.85)
		var base_scale: Vector2 = (Vector2(2.8, 1.7) if is_lance else Vector2(2.1, 1.5)) * _size_mult
		halo.scale = base_scale
		add_child(halo)
		# 2. Core — near-white, blooms on its own.
		var core := Sprite2D.new()
		core.texture = dot
		core.material = FxLib.additive_material()
		core.modulate = Color(2.4, 2.4, 2.4)  # WHITE_HOT center
		var core_scale: Vector2 = Vector2(1.4, 0.7) * _size_mult
		core.scale = core_scale
		add_child(core)
		# Spawn pop: the bolt snaps out to size in two frames.
		halo.scale = base_scale * 0.4
		var pop := halo.create_tween()
		pop.tween_property(halo, "scale", base_scale, 0.07) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_animate_core(core, core_scale)
		_build_decoration()
	else:
		# Legacy rectangle, still bigger/brighter than the world around it.
		sprite.color = Color(_accent.r, _accent.g, _accent.b, 1.0)
		sprite.size = (Vector2(30, 9) if proj_type == "stack_trace" else Vector2(22, 9)) * _size_mult
		sprite.position = -sprite.size * 0.5
	_build_trails()
	# Self-heal the haze budget before spending it. `_live_haze` is static and
	# decremented by `tree_exited`; a counter that can only drift UPWARD fails
	# silently and permanently (no bolt ever bends space again for the rest of the
	# session). A haze only ever lives inside a live bolt, so the size of the
	# projectile group is a hard upper bound we can clamp to, once per shot.
	var live_bolts: int = get_tree().get_nodes_in_group("player_projectile").size()
	if _live_haze > live_bolts:
		Projectile._live_haze = live_bolts
	# Travelling distortion: a pocket of bent space riding along with the shots
	# that deserve one. Null when the shader library is absent — that's fine.
	if (crit or proj_type == "stack_trace") and not weak and _live_haze < MAX_HAZE:
		var haze_size: float = 52.0 if proj_type == "stack_trace" else 42.0
		var haze := CombatFx.distortion(self, haze_size, 0.0034 if crit else 0.0026, 2.4)
		if haze:
			# Screen-reading: must draw after the world it bends, before the bolt.
			haze.z_index = -6
			Projectile._live_haze += 1
			haze.tree_exited.connect(func() -> void:
				Projectile._live_haze = maxi(0, Projectile._live_haze - 1))
	# A tiny light so a shot passing a wall lights it for a frame. LAW 4 puts the
	# region's own lights at 0.4-0.9 energy, and a bolt is in flight for a fifth
	# of a second — it should read as travelling THROUGH the room's lighting, not
	# as a brighter lamp than any lamp in it.
	FxLib.point_light(self, FxLib.vivid(_accent), 0.75 if crit else 0.55,
		0.40 if crit else 0.30)

## The core never sits still. A healthy bolt breathes; a hallucinated one
## flickers like something that is not sure it is there. Both loops are
## engine-side tweens, so this costs nothing per frame in GDScript.
func _animate_core(core: Sprite2D, base: Vector2) -> void:
	var loop := core.create_tween().set_loops()
	if weak:
		loop.tween_property(core, "modulate:a", 0.25, 0.09).set_trans(Tween.TRANS_LINEAR)
		loop.tween_property(core, "modulate:a", 1.0, 0.13).set_trans(Tween.TRANS_LINEAR)
	else:
		loop.tween_property(core, "scale", base * 1.28, 0.12).set_trans(Tween.TRANS_SINE)
		loop.tween_property(core, "scale", base * 0.92, 0.12).set_trans(Tween.TRANS_SINE)

## The bit that tells you WHICH ability is in the air. Everything here lives
## under one spinning Node2D, so the whole decoration is a single looping tween.
func _build_decoration() -> void:
	var spin := Node2D.new()
	spin.material = FxLib.additive_material()
	add_child(spin)
	var hot := Color(_accent.r * 2.4, _accent.g * 2.4, _accent.b * 2.4, 0.9)
	if weak:
		# A single lopsided ring that tumbles: the shape of a shot that has lost
		# the thread. It also spins the WRONG way, slowly, which is the joke.
		var ring := Line2D.new()
		ring.points = CombatFx.ring_points(9)
		ring.scale = Vector2.ONE * 8.0
		ring.width = 1.6 / 8.0
		ring.default_color = Color(hot.r, hot.g, hot.b, 0.55)
		ring.use_parent_material = true
		spin.add_child(ring)
		var slow := spin.create_tween().set_loops()
		slow.tween_property(spin, "rotation", -TAU, 1.1).from(0.0)
		return
	if proj_type == "stack_trace":
		# The trace ring: a fast-spinning open circle around the lance head, so
		# a piercing shot looks like it is drilling rather than just travelling.
		var ring := Line2D.new()
		ring.points = CombatFx.ring_points(12)
		ring.scale = Vector2.ONE * 11.0 * _size_mult
		ring.width = 2.2 / (11.0 * _size_mult)
		ring.default_color = hot
		ring.use_parent_material = true
		spin.add_child(ring)
		var fast := spin.create_tween().set_loops()
		fast.tween_property(spin, "rotation", TAU, 0.34).from(0.0)
	if crit:
		# Two chevrons riding the shoulders of a crit — the "this one is going
		# to hurt" tell, readable before it lands.
		for k: float in [1.0, -1.0]:
			var chev := Polygon2D.new()
			chev.polygon = PackedVector2Array([
				Vector2(-5.0, k * 11.0), Vector2(7.0, k * 6.0), Vector2(-5.0, k * 3.0)])
			chev.color = Color(2.6, 2.2, 1.1, 0.95)
			chev.use_parent_material = true
			spin.add_child(chev)
		if proj_type != "stack_trace":
			var beat := spin.create_tween().set_loops()
			beat.tween_property(spin, "scale", Vector2(1.18, 1.18), 0.1).set_trans(Tween.TRANS_SINE)
			beat.tween_property(spin, "scale", Vector2(0.92, 0.92), 0.1).set_trans(Tween.TRANS_SINE)

## Two world-space trails: a wide accent ribbon and a thin white-hot line inside
## it. `top_level` keeps their POINTS in world space while the bolt moves, so
## their depth has to be stated absolutely, just behind the bolt head.
func _build_trails() -> void:
	_trail = _make_trail(10.0 * _size_mult, Color(_accent.r * 1.8, _accent.g * 1.8, _accent.b * 1.8, 0.62), CombatFx.Z_FX - 3)
	_core_trail = _make_trail(3.4 * _size_mult, Color(2.4, 2.4, 2.4, (0.4 if weak else 0.85)), CombatFx.Z_FX - 2)

func _make_trail(width: float, tail_color: Color, z: int) -> Line2D:
	var line := Line2D.new()
	line.top_level = true
	line.width = width
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.material = FxLib.additive_material()
	var grad := Gradient.new()
	grad.set_color(0, Color(tail_color.r, tail_color.g, tail_color.b, 0.0))
	grad.set_color(1, tail_color)
	line.gradient = grad
	var wc := Curve.new()
	wc.add_point(Vector2(0.0, 0.06))
	wc.add_point(Vector2(0.62, 0.48))
	wc.add_point(Vector2(1.0, 1.0))
	line.width_curve = wc
	line.z_as_relative = false
	line.z_index = z
	add_child(line)
	return line

func setup(dir: Vector2, dmg: int, type: String) -> void:
	direction = dir.normalized()
	damage = dmg
	proj_type = type
	rotation = direction.angle()

func _physics_process(delta: float) -> void:
	position += direction * speed * delta
	if weak:
		# A hallucinated bolt cannot hold a straight line either.
		position += direction.orthogonal() * sin(lifetime * 26.0) * 42.0 * delta
	_push_trail(_trail)
	_push_trail(_core_trail)
	lifetime -= delta
	if lifetime <= 0:
		_expire()

func _push_trail(line: Line2D) -> void:
	if line == null or not is_instance_valid(line):
		return
	line.add_point(global_position)
	if line.get_point_count() > TRAIL_POINTS:
		line.remove_point(0)

## Out of range. This must NOT look like a shot that connected — the player
## learns the weapon's reach from the difference. So: no ring, no spikes, no
## screen shake. The bolt loses cohesion, sags, and drops a few dying embers.
## A hallucinated bolt occasionally offers an excuse on the way down.
func _expire() -> void:
	var host := get_parent()
	if host:
		var pos := global_position
		var col := _accent
		FxLib.burst(host, pos, Color(col.r * 1.4, col.g * 1.4, col.b * 1.4),
			6 if weak else 4, 66.0, FxLib.glow_dot(), Vector2(0, 150.0),
			CombatFx.Z_FX - 2, Vector2.ZERO, 180.0, 0.55, 0.9)
		FxLib.flash(host, pos, col, 0.55 * _size_mult, 0.95 * _size_mult, 0.22, CombatFx.Z_FX - 2)
		if weak and randf() < 0.34:
			CombatFx.glyph(host, pos + Vector2(0, -18),
				ComedyLines.pick("weak_fizzle", FIZZLE_LINES), Color("#8B5CF6"), 12, 0.85, 20.0)
	_retire_trail()
	queue_free()

## Hand the trails to our parent and fade them out, so the light doesn't vanish
## in a single frame when the bolt dies.
func _retire_trail() -> void:
	_retire_one(_trail)
	_retire_one(_core_trail)
	_trail = null
	_core_trail = null

func _retire_one(line: Line2D) -> void:
	if line == null or not is_instance_valid(line):
		return
	var host := get_parent()
	if host == null:
		return
	remove_child(line)
	host.add_child(line)
	var tw := line.create_tween()
	tw.tween_property(line, "modulate:a", 0.0, 0.18)
	tw.tween_callback(line.queue_free)

func _on_area_entered(area: Area2D) -> void:
	var parent := area.get_parent()
	if parent and parent.is_in_group("enemy") and parent.has_method("take_damage"):
		if parent in _hit:
			return
		_hit.append(parent)
		parent.take_damage(damage, crit, direction)
		# Impact: shove the enemy along the shot so hits feel like they land.
		if parent.has_method("apply_knockback"):
			var kb := 430.0 if proj_type == "stack_trace" else 320.0
			if crit:
				kb *= 1.5
			if parent.get("is_boss"):
				kb *= 0.25  # bosses only flinch
			parent.apply_knockback(direction * kb)
		_impact_fx(parent)
		if pierce:
			_pierce_frame(parent)
		else:
			_retire_trail()
			queue_free()

## Every enemy a Stack Trace punches through adds a line to the trace, stacked
## upward. Comedy rides alongside: the information is "this hit landed too".
func _pierce_frame(enemy: Node) -> void:
	_pierce_count += 1
	var host := get_parent()
	if host == null or not (enemy is Node2D):
		return
	var pos: Vector2 = (enemy as Node2D).global_position
	var text: String = "... 47 more" if _pierce_count >= 4 else ComedyLines.pick("stack_frames", STACK_FRAMES)
	CombatFx.glyph(host, pos + Vector2(0, -46 - _pierce_count * 5), text, Color(1.0, 0.55, 0.82), 13, 0.95, 34.0)
	# The trace burns a mark on the floor between the enemies it passed through.
	CombatFx.scorch(host, _origin, pos, _accent, 1.6)

## The whole layered impact — core flash, directional spark cone, spike star,
## haloed ring, flare light, trauma and (crits only) hit-stop — lives in
## `CombatFx.impact`, so a bolt landing looks the same as anything else landing.
## What this adds on top is the SHOT's own signature: a lance punching through
## versus a blast going off.
##
## `power` is the hit's severity normalised against a reference chunk of damage,
## so a 30-damage Stack Trace crit is visibly a bigger event than a 5-damage
## sputter, without either needing a hand-tuned effect.
func _impact_fx(victim: Node = null) -> void:
	if not is_inside_tree():
		return
	# A bolt that reached a CORPSE dealt nothing — `take_damage` refuses once
	# `_dying` is set, and the hitbox stays live for the 0.45s the body spends
	# leaving. Drawing the full impact there teaches the player that a wasted
	# shot connected. The kill-pop marker is what says "already finished before
	# this bolt": in the killing flush it has not been set yet, so the shot that
	# actually did it keeps every layer.
	if victim != null and is_instance_valid(victim) and victim.get("_dying") == true \
			and victim.has_meta(CombatFx.KILL_POP_META):
		return
	var host := get_parent()
	var pos := global_position
	var power: float = clampf(float(damage) / 18.0, 0.4, 2.2)
	if host:
		CombatFx.impact(host, pos, direction, _accent, power, crit)
		if proj_type == "stack_trace":
			# A lance: the force goes THROUGH, so the secondary read is a
			# forward ripple rather than another round pop.
			CombatFx.ripple(host, pos, direction, _accent, 54.0 + 26.0 * power, 0.24)
			CombatFx.speed_lines(host, pos + direction * 22.0, direction, _accent, 3)
		elif not weak:
			CombatFx.spike_star(host, pos, Color(1, 1, 1), 3, 22.0 * power, 0.14, direction, PI * 0.7)
	# Kills earn their own beat. Checked on the victim's own HP so it fires once,
	# on the shot that actually finished it.
	if victim == null or not is_instance_valid(victim) or host == null:
		return
	var hp_left: Variant = victim.get("hp")
	if hp_left == null or int(hp_left) > 0:
		return
	var at := pos
	if victim is Node2D:
		at = (victim as Node2D).global_position
	# `_once`: the enemy's own hitbox reports this same contact in the same
	# physics flush, and its hitbox stays live for the 0.45s it spends dying, so
	# a second bolt can reach a corpse. Both would otherwise pop the same kill.
	CombatFx.kill_pop_once(victim, host, at, _accent, 0.9 + 0.5 * power)
