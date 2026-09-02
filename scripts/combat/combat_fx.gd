class_name CombatFx
extends RefCounted
## Spectacle primitives for combat: expanding shock rings, beams, muzzle flashes,
## hex shields, ground telegraphs, afterimages, floating glyphs, error-text
## shards and one (1) rubber duck.
##
## Rules this file obeys, so nothing here can ever cost a frame or crash a fight:
##   * every helper is STATIC and EVENT-DRIVEN — nothing runs per-frame in
##     GDScript; motion is handed to Tweens, which live engine-side;
##   * everything parents to a caller-supplied HOST (the region, not the dying
##     thing) so effects outlive their cause, and frees itself when done;
##   * geometry and materials are cached — one unit circle, one hexagon, one
##     additive material, one haze material per strength;
##   * missing FX textures, a missing shader, or a host that already left the
##     tree all degrade to "draw less", never to an error.
##
## See docs/VISUAL_BIBLE.md — overbright modulate (>1.0) is how things bloom.

const HEAT_HAZE_PATH := "res://assets/shaders/heat_haze.gdshader"
const DISSOLVE_PATH := "res://assets/shaders/dissolve.gdshader"

## Depth bands. The world y-sorts its props to `int(pos.y + half)`, topping out
## near 1050, and WorldLabel plates sit at 1150 — that file's own docs say world
## text belongs "below combat readouts". So combat FX live ABOVE the plates, and
## floor decals live just above the floor and below the scenery standing on it.
## Getting this wrong is not subtle: an effect at z 560 is simply invisible
## behind any prop in the lower two thirds of a room.
const Z_GROUND := -2    # telegraph markers, scorch — painted ON the floor
const Z_FX := 1180      # rings, beams, sparks, shields, afterimage bias
const Z_TEXT := 1220    # damage numbers, callouts, error-text shards

## How many FULL layered impacts may be drawn in one physics frame before the
## rest fall back to the cheap core. See `impact()`.
const IMPACT_FULL_PER_FRAME := 4
static var _impact_frame := -1
static var _impact_count := 0

## Above this `power`, a NON-crit hit is heavy enough to earn hit-stop.
##
## Calibrated against the real weapon table, not against the idea of one.
## `impact()`'s callers normalise power as damage/18, and the ordinary Prompt
## Blast is 25 damage before any multiplier — power 1.39. A threshold of 1.3
## therefore froze the clock on EVERY basic shot that landed, roughly twice a
## second at BLAST_CADENCE's floor, which reads as the game stuttering rather
## than as weight. 1.9 means damage >= ~34: a heavily buffed lance, an elite
## slam, a boss's own blow. Crits are unaffected — they always freeze, and they
## are 14% of shots, which is the rhythm hit-stop is FOR.
const HEAVY_HIT_POWER := 1.9

## Meta key marking a corpse whose kill beat has already played. See
## `kill_pop_once()`.
const KILL_POP_META := "fx_kill_popped"

static var _ring_cache: Dictionary = {}
static var _hex_cache: Dictionary = {}
static var _haze_checked := false
static var _haze_shader: Shader
static var _haze_mats: Dictionary = {}

# ------------------------------------------------------------- geometry ----

## Unit circle (radius 1), closed by repeating the first point. Cached per
## segment count; callers scale the node instead of rebuilding points.
static func ring_points(segments: int = 36) -> PackedVector2Array:
	if _ring_cache.has(segments):
		return _ring_cache[segments]
	var pts := PackedVector2Array()
	for i in segments + 1:
		var a := TAU * float(i) / float(segments)
		pts.append(Vector2(cos(a), sin(a)))
	_ring_cache[segments] = pts
	return pts

## Unit hexagon (radius 1), flat-top, closed. `closed=false` leaves it open for
## fills (Polygon2D closes implicitly and dislikes the duplicate point).
static func hex_points(closed: bool = true) -> PackedVector2Array:
	var key := "c" if closed else "o"
	if _hex_cache.has(key):
		return _hex_cache[key]
	var pts := PackedVector2Array()
	var count := 7 if closed else 6
	for i in count:
		var a := TAU * float(i) / 6.0
		pts.append(Vector2(cos(a), sin(a)))
	_hex_cache[key] = pts
	return pts

## Wedge polygon (a "swing arc"): a fan from the origin, `spread` radians wide,
## centred on `angle`, out to radius 1. Callers scale it.
static func wedge_points(angle: float, spread: float, segments: int = 12) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(Vector2.ZERO)
	for i in segments + 1:
		var a: float = angle - spread * 0.5 + spread * float(i) / float(segments)
		pts.append(Vector2(cos(a), sin(a)))
	return pts

# ------------------------------------------------------------ materials ----

static func _haze_shader_or_null() -> Shader:
	if not _haze_checked:
		_haze_checked = true
		if ResourceLoader.exists(HEAT_HAZE_PATH):
			_haze_shader = load(HEAT_HAZE_PATH)
	return _haze_shader

## Screen-reading refraction material. One shared instance per strength bucket
## (the bible's "reuse ShaderMaterials" rule), or null when the shader is absent.
static func haze_material(strength: float, speed: float = 2.0) -> ShaderMaterial:
	var sh := _haze_shader_or_null()
	if sh == null:
		return null
	var key := "%.4f_%.2f" % [strength, speed]
	if _haze_mats.has(key):
		return _haze_mats[key]
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("strength", strength)
	mat.set_shader_parameter("speed", speed)
	_haze_mats[key] = mat
	return mat

## A square of visibly bent space. Returns null when the shader is missing, so
## every caller must tolerate null.
##
## IMPORTANT: this is a SCREEN-READING effect — it paints back whatever was
## already drawn, warped. It must therefore draw AFTER the world it is meant to
## bend, so callers set a high `z_index` on the returned rect. Left at the
## default it would sample an empty back buffer and read as a grey square.
static func distortion(parent: Node, size: float, strength: float = 0.0035, speed: float = 2.0) -> ColorRect:
	var mat := haze_material(strength, speed)
	if mat == null or parent == null:
		return null
	var rect := ColorRect.new()
	rect.material = mat
	rect.size = Vector2(size, size)
	rect.position = Vector2(-size * 0.5, -size * 0.5)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.z_index = Z_FX - 20
	parent.add_child(rect)
	return rect

static func _ok(host: Node) -> bool:
	return host != null and is_instance_valid(host) and host.is_inside_tree()

# ------------------------------------------------------------ shockwaves ----

## Expanding overbright ring. Points are a cached unit circle; the node scales
## and the stroke thins so the ring stays a ring instead of a growing donut.
##
## `glow` (optional, 0 = off) adds a wide, dim companion ring drawn behind the
## hot one. Without it a ring is a wireframe circle; with it the ring has a
## halo, which is the difference between "a circle appeared" and "something
## detonated". Existing callers are unaffected — the default is off.
static func ring(host: Node, pos: Vector2, color: Color, r_start: float, r_end: float,
		duration: float = 0.34, width_start: float = 7.0, width_end: float = 1.5,
		segments: int = 36, glow: float = 0.0) -> void:
	if not _ok(host):
		return
	if glow > 0.0:
		_ring_line(host, pos, color, r_start, r_end, duration * 1.15,
			width_start * 2.8 * glow, width_end * 3.4 * glow,
			maxi(segments / 2, 12), 0.26, Z_FX - 3)
	_ring_line(host, pos, color, r_start, r_end, duration, width_start, width_end, segments, 0.95, Z_FX)

## The single stroke behind `ring()`. Split out so a ring can be drawn twice —
## once wide and dim, once tight and hot — without duplicating the tween setup.
static func _ring_line(host: Node, pos: Vector2, color: Color, r_start: float, r_end: float,
		duration: float, width_start: float, width_end: float,
		segments: int, alpha: float, z: int) -> void:
	var line := Line2D.new()
	line.points = ring_points(segments)
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.material = FxLib.additive_material()
	line.default_color = Color(color.r * 2.1, color.g * 2.1, color.b * 2.1, alpha)
	line.z_index = z
	line.scale = Vector2.ONE * maxf(r_start, 0.01)
	line.width = width_start / maxf(r_start, 0.01)
	host.add_child(line)
	line.global_position = pos
	var tw := line.create_tween()
	tw.tween_property(line, "scale", Vector2.ONE * r_end, duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(line, "width", width_end / maxf(r_end, 0.01), duration)
	tw.parallel().tween_property(line, "modulate:a", 0.0, duration).set_ease(Tween.EASE_IN)
	tw.tween_callback(line.queue_free)

## Two nested rings + a white-hot core flash + a light that exists for a quarter
## of a second. The default "something important just happened here" punctuation
## mark.
static func shockwave(host: Node, pos: Vector2, color: Color, radius: float,
		duration: float = 0.38) -> void:
	if not _ok(host):
		return
	ring(host, pos, color, radius * 0.14, radius, duration, 9.0, 1.5, 36, 1.0)
	ring(host, pos, Color(1, 1, 1), radius * 0.10, radius * 0.62, duration * 0.7, 5.0, 1.0, 24)
	FxLib.flash(host, pos, color, 0.25, radius / 46.0, duration * 0.55, Z_FX)
	FxLib.flare(host, pos, FxLib.vivid(color), clampf(radius / 130.0, 0.5, 2.4),
		clampf(radius / 150.0, 0.35, 1.8), duration * 0.9)

## A squashed ring, oriented along `dir` — the "force ripple" a dash or a punch
## leaves behind. Reads as directional force instead of a generic pop.
static func ripple(host: Node, pos: Vector2, dir: Vector2, color: Color, radius: float,
		duration: float = 0.3) -> void:
	if not _ok(host) or dir.length_squared() < 0.0001:
		return
	var line := Line2D.new()
	line.points = ring_points(28)
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.material = FxLib.additive_material()
	line.default_color = Color(color.r * 2.0, color.g * 2.0, color.b * 2.0, 0.9)
	line.z_index = Z_FX - 2
	line.rotation = dir.angle()
	line.scale = Vector2(6.0, 10.0)
	line.width = 1.2
	host.add_child(line)
	line.global_position = pos
	var tw := line.create_tween()
	tw.tween_property(line, "scale", Vector2(radius * 0.55, radius), duration) \
		.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(line, "width", 0.06, duration)
	tw.parallel().tween_property(line, "modulate:a", 0.0, duration)
	tw.tween_callback(line.queue_free)

# --------------------------------------------------------------- impact ----

## Short tapered spikes stabbing outward from a point. Assembled under ONE root
## so the whole star costs a single tween no matter how many spikes it has.
##
## Why this exists: a particle spray reads as FUZZ at game zoom on a dark floor,
## and a ring reads as a boundary. Neither reads as force. Hard-edged spikes
## that punch out and vanish do, and they survive the bloom pass instead of
## being eaten by it.
static func spike_star(host: Node, pos: Vector2, color: Color, count: int = 6,
		length: float = 42.0, duration: float = 0.20, dir: Vector2 = Vector2.ZERO,
		spread: float = TAU) -> Node2D:
	if not _ok(host):
		return null
	var n: int = clampi(count, 1, 10)
	var root := Node2D.new()
	root.z_index = Z_FX + 2
	root.material = FxLib.additive_material()
	host.add_child(root)
	root.global_position = pos
	var base_a: float = dir.angle() if dir.length_squared() > 0.0001 else randf() * TAU
	var hot := Color(color.r * 2.4, color.g * 2.4, color.b * 2.4, 1.0)
	var w: float = maxf(1.8, length * 0.10)
	for i in n:
		var a: float = base_a - spread * 0.5 + spread * (float(i) + randf() * 0.7) / float(n)
		var len_i: float = length * randf_range(0.58, 1.0)
		var spike := Polygon2D.new()
		spike.polygon = PackedVector2Array([
			Vector2(length * 0.16, -w), Vector2(len_i, 0.0), Vector2(length * 0.16, w)])
		spike.color = hot
		spike.rotation = a
		spike.use_parent_material = true
		root.add_child(spike)
	root.scale = Vector2(0.26, 0.26)
	var tw := root.create_tween()
	tw.tween_property(root, "scale", Vector2.ONE, duration) \
		.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(root, "modulate:a", 0.0, duration).set_ease(Tween.EASE_IN)
	tw.tween_callback(root.queue_free)
	return root

## THE hit. Every landed blow in the game should be able to route through this
## one call, so hits read the same way whoever threw them. Layers, in the order
## the eye picks them up:
##   1. a WHITE-HOT core flash with a soft accent bloom behind it (FxLib.flash);
##   2. a spark cone thrown BACK along the blow — sparks come off the surface
##      that was struck, not out of the middle of the enemy;
##   3. a spike star biased into that same cone — force, not fuzz;
##   4. an expanding haloed ring;
##   5. a flare light, so the room reacts to the hit;
##   6. camera trauma, and on heavy hits only, hit-stop.
##
## `power` is severity normalised so 1.0 is "a solid hit"; callers can pass
## damage / a reference chunk. A crit is deliberately not "the same event
## slightly bigger" — it gets roughly double the geometry, a white inner ring,
## a directional force ripple, and the only guaranteed freeze.
static func impact(host: Node, pos: Vector2, dir: Vector2, color: Color,
		power: float = 1.0, crit: bool = false, allow_hit_stop: bool = true) -> void:
	if not _ok(host):
		return
	var p: float = clampf(power, 0.35, 2.2)
	var back := Vector2.ZERO
	if dir.length_squared() > 0.0001:
		back = -dir.normalized()
	var big: float = 1.65 if crit else 1.0
	var aimed: bool = back != Vector2.ZERO
	# Density governor. One AoE landing on six enemies calls this six times in a
	# single physics flush; past the fourth, the extra sparks, spikes and lights
	# are physically on top of each other and nobody can tell them apart, so the
	# tail of the burst drops to the cheap core (flash + ring) and keeps the
	# frame. Crits are never demoted — a crit you cannot see is a bug.
	var frame := Engine.get_physics_frames()
	if frame != _impact_frame:
		CombatFx._impact_frame = frame
		CombatFx._impact_count = 0
	CombatFx._impact_count += 1
	var full: bool = crit or _impact_count <= IMPACT_FULL_PER_FRAME
	FxLib.flash(host, pos, color, 0.26 * big, (1.9 + 1.2 * p) * big, 0.19 + 0.06 * p, Z_FX)
	ring(host, pos, color, 3.0, (24.0 + 15.0 * p) * big, 0.22 + 0.06 * p, 6.0, 1.0, 24, 1.0)
	if full:
		FxLib.burst(host, pos, Color(color.r * 2.1, color.g * 2.1, color.b * 2.1),
			int((8.0 + 8.0 * p) * (2.0 if crit else 1.0)),
			(190.0 + 110.0 * p) * (1.35 if crit else 1.0),
			FxLib.spark(), Vector2(0, 70.0), Z_FX,
			back, (54.0 if aimed else 180.0), 0.34, (1.25 if crit else 1.0))
		spike_star(host, pos, color, (7 if crit else 4), (26.0 + 16.0 * p) * big,
			(0.24 if crit else 0.17), back, (PI * 1.25 if aimed else TAU))
		FxLib.flare(host, pos, FxLib.vivid(color), (1.0 + 0.6 * p) * big, 0.5 * p * big, 0.22)
	if crit:
		ring(host, pos, Color(1, 1, 1), 2.0, 18.0 + 30.0 * p, 0.19, 4.0, 0.8, 20)
		if aimed:
			ripple(host, pos, -back, color, 58.0 + 30.0 * p, 0.28)
	var tree := host.get_tree()
	FxLib.add_trauma(tree, clampf(0.10 * p, 0.05, 0.30) * (1.9 if crit else 1.0))
	if allow_hit_stop and (crit or p >= HEAVY_HIT_POWER):
		FxLib.hit_stop(tree, (0.07 if crit else 0.15), (0.055 if crit else 0.030))

## The payoff for a KILL, as opposed to a hit. The world implodes toward the
## corpse for one beat, then detonates outward — cause and effect, ~90ms apart,
## which is long enough to read and short enough to still feel like one event.
## Nothing here touches the corpse, so the dying thing can leave on its own
## schedule while this plays out on the region.
static func kill_pop(host: Node, pos: Vector2, color: Color, power: float = 1.0) -> void:
	if not _ok(host):
		return
	var p: float = clampf(power, 0.5, 2.5)
	# In: a ring collapsing onto the corpse, plus motes dragged inward.
	ring(host, pos, Color(1, 1, 1), 62.0 * p, 5.0, 0.13, 1.0, 5.0, 20)
	var t := host.create_tween()
	t.tween_interval(0.09)
	# Every call inside the lambda is qualified with the class name. A lambda in a
	# static function has no `self` to hang an unqualified member call on, and a
	# resolution failure in THIS file takes the whole game down without failing a
	# single test (HANDOVER gotcha 6b). CombatFx.x costs nothing and cannot fail.
	t.tween_callback(func() -> void:
		if not CombatFx._ok(host):
			return
		CombatFx.shockwave(host, pos, color, 86.0 * p, 0.40)
		CombatFx.spike_star(host, pos, color, 8, 50.0 * p, 0.26)
		FxLib.burst(host, pos, Color(color.r * 2.3, color.g * 2.3, color.b * 2.3),
			int(14.0 * p), 280.0 * p, FxLib.spark(), Vector2(0, 240.0), Z_FX,
			Vector2.ZERO, 180.0, 0.5, 1.15))

## `kill_pop`, but at most ONCE for `victim`. A single enemy can be reported dead
## by more than one caller: the bolt's own area callback and the enemy's hitbox
## callback both fire in the same physics flush, a second bolt can reach a corpse
## before it finishes its 0.45s teardown (the hitbox stays live), and enemy_base
## may one day fire its own beat for kills no bolt caused. Two implosions and two
## detonations 16ms apart read as a rendering glitch, not as a bigger kill.
##
## The flag rides on the corpse itself rather than in a static table, so it costs
## nothing, needs no pruning, and is freed with the thing it describes — it
## cannot become state that survives a new game.
static func kill_pop_once(victim: Object, host: Node, pos: Vector2, color: Color,
		power: float = 1.0) -> void:
	if victim == null or not is_instance_valid(victim):
		return
	if victim.has_meta(KILL_POP_META):
		return
	victim.set_meta(KILL_POP_META, true)
	kill_pop(host, pos, color, power)

# ---------------------------------------------------------------- beams ----

## A hard beam of light: a wide accent glow with a white-hot core down the
## middle. Both fade together, so it reads as one bolt, not two lines.
static func beam(host: Node, from: Vector2, to: Vector2, color: Color,
		width: float = 14.0, duration: float = 0.22) -> void:
	if not _ok(host):
		return
	for pass_i: int in [0, 1]:
		var line := Line2D.new()
		line.top_level = true
		line.points = PackedVector2Array([from, to])
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		line.material = FxLib.additive_material()
		line.z_index = Z_FX - 4 + pass_i
		if pass_i == 0:
			line.width = width
			line.default_color = Color(color.r * 1.6, color.g * 1.6, color.b * 1.6, 0.55)
		else:
			line.width = width * 0.34
			line.default_color = Color(2.6, 2.6, 2.6, 0.95)
		host.add_child(line)
		var tw := line.create_tween()
		tw.tween_property(line, "width", line.width * 0.08, duration).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(line, "modulate:a", 0.0, duration)
		tw.tween_callback(line.queue_free)

## The mark a beam leaves on the floor. Lingers for `duration` (seconds) and
## fades out slowly — the room remembers what you did in it.
static func scorch(host: Node, from: Vector2, to: Vector2, color: Color,
		duration: float = 1.8) -> void:
	if not _ok(host):
		return
	var line := Line2D.new()
	line.top_level = true
	line.points = PackedVector2Array([from, to])
	line.width = 7.0
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.default_color = Color(color.r * 0.55, color.g * 0.55, color.b * 0.55, 0.42)
	line.z_index = Z_GROUND - 1  # on the floor, under everything that walks on it
	host.add_child(line)
	var tw := line.create_tween()
	tw.tween_interval(duration * 0.35)
	tw.tween_property(line, "modulate:a", 0.0, duration * 0.65)
	tw.tween_callback(line.queue_free)

## Muzzle flash: a bright bloom at the barrel, a streak along the shot, and a
## contracting "gather" ring that sells the charge-up in one frame.
static func muzzle(host: Node, pos: Vector2, dir: Vector2, color: Color, power: float = 1.0) -> void:
	if not _ok(host):
		return
	var dot := FxLib.glow_dot()
	if dot:
		var streak := Sprite2D.new()
		streak.texture = dot
		streak.material = FxLib.additive_material()
		streak.modulate = Color(color.r * 2.4, color.g * 2.4, color.b * 2.4, 0.95)
		streak.rotation = dir.angle()
		streak.z_index = Z_FX + 1
		streak.scale = Vector2(1.4 * power, 1.1 * power)
		host.add_child(streak)
		streak.global_position = pos
		var tw := streak.create_tween()
		tw.tween_property(streak, "scale", Vector2(5.2 * power, 0.5 * power), 0.13) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(streak, "modulate:a", 0.0, 0.13)
		tw.tween_callback(streak.queue_free)
	# Gather ring: collapses INTO the barrel, so the shot looks paid for.
	ring(host, pos, color, 2.4 * power, 0.35, 0.11, 3.0, 5.0, 20)
	FxLib.burst(host, pos + dir * 8.0, Color(color.r * 2.0, color.g * 2.0, color.b * 2.0),
		int(6 * power), 190.0 * power, FxLib.spark(), Vector2.ZERO, Z_FX)

# --------------------------------------------------------- hex shielding ----

## A shimmering hexagonal shield bubble. Returns the node — the caller owns it
## and should call `shield_break()` (or free it) when the effect ends.
## Structure: refraction disc (screen-reading) -> tinted fill -> honeycomb
## cells -> two counter-rotating rims. Motion is 100% Tween-driven.
static func shield(owner_node: Node2D, color: Color, radius: float = 40.0) -> Node2D:
	if owner_node == null or not is_instance_valid(owner_node) or not owner_node.is_inside_tree():
		return null
	var root := Node2D.new()
	# Absolute depth: the player's own z_index tracks their Y, so a relative
	# offset would make the bubble's depth wander with the room.
	root.z_as_relative = false
	root.z_index = Z_FX + 10
	owner_node.add_child(root)

	# Refraction disc, one step behind the rim so the bubble looks like glass
	# rather than a decal. Still high enough to sample a fully drawn world.
	var haze := distortion(root, radius * 2.2, 0.0026, 1.4)
	if haze:
		haze.z_index = -3

	var fill := Polygon2D.new()
	fill.polygon = hex_points(false)
	fill.scale = Vector2.ONE * radius
	fill.color = Color(color.r, color.g, color.b, 0.13)
	fill.material = FxLib.additive_material()
	root.add_child(fill)

	# Honeycomb: a centre cell plus a ring of six, so the bubble reads as CACHED
	# data rather than a soap bubble.
	var cell_r := radius * 0.30
	for i in 7:
		var cell := Line2D.new()
		cell.points = hex_points(true)
		cell.width = 0.055
		cell.default_color = Color(color.r * 1.3, color.g * 1.3, color.b * 1.3, 0.30)
		cell.material = FxLib.additive_material()
		cell.scale = Vector2.ONE * cell_r
		if i > 0:
			var a := TAU * float(i - 1) / 6.0
			cell.position = Vector2(cos(a), sin(a)) * cell_r * 1.72
		root.add_child(cell)

	var rims: Array[Line2D] = []
	for k: float in [1.0, 0.9]:
		var rim := Line2D.new()
		rim.points = hex_points(true)
		rim.joint_mode = Line2D.LINE_JOINT_ROUND
		rim.material = FxLib.additive_material()
		rim.scale = Vector2.ONE * radius * k
		rim.width = (3.4 if k > 0.95 else 1.6) / (radius * k)
		var boost := 2.3 if k > 0.95 else 1.5
		rim.default_color = Color(color.r * boost, color.g * boost, color.b * boost, 0.95)
		root.add_child(rim)
		rims.append(rim)

	# Pop in.
	root.scale = Vector2(0.25, 0.25)
	var pop := root.create_tween()
	pop.tween_property(root, "scale", Vector2(1.16, 1.16), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(root, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_CUBIC)
	# Counter-rotating rims + a slow shimmer, all engine-side loops.
	var spin_a := rims[0].create_tween().set_loops()
	spin_a.tween_property(rims[0], "rotation", TAU, 9.0).from(0.0)
	var spin_b := rims[1].create_tween().set_loops()
	spin_b.tween_property(rims[1], "rotation", -TAU, 6.0).from(0.0)
	var shimmer := fill.create_tween().set_loops()
	shimmer.tween_property(fill, "modulate:a", 1.0, 0.75).set_trans(Tween.TRANS_SINE)
	shimmer.tween_property(fill, "modulate:a", 0.5, 0.75).set_trans(Tween.TRANS_SINE)
	return root

## Ping the shield where a hit was absorbed: a bright hex ripple on the rim.
static func shield_ping(shield_node: Node2D, color: Color, radius: float) -> void:
	if shield_node == null or not is_instance_valid(shield_node) or not shield_node.is_inside_tree():
		return
	var ping := Line2D.new()
	ping.points = hex_points(true)
	ping.material = FxLib.additive_material()
	ping.scale = Vector2.ONE * radius * 0.55
	ping.width = 4.0 / (radius * 0.55)
	ping.default_color = Color(color.r * 2.6, color.g * 2.6, color.b * 2.6, 1.0)
	shield_node.add_child(ping)
	var tw := ping.create_tween()
	tw.tween_property(ping, "scale", Vector2.ONE * radius * 1.14, 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(ping, "modulate:a", 0.0, 0.26)
	tw.tween_callback(ping.queue_free)

## Shatter the bubble into hex shards. Frees `shield_node` immediately and plays
## the debris on the host, so the shards survive whatever owned the shield.
static func shield_break(shield_node: Node2D, host: Node, pos: Vector2, color: Color, radius: float) -> void:
	if shield_node and is_instance_valid(shield_node):
		shield_node.queue_free()
	if not _ok(host):
		return
	for i in 9:
		var a := TAU * float(i) / 9.0 + randf() * 0.4
		var shard := Line2D.new()
		shard.points = hex_points(true)
		shard.material = FxLib.additive_material()
		shard.scale = Vector2.ONE * radius * 0.22
		shard.width = 2.6 / (radius * 0.22)
		shard.default_color = Color(color.r * 2.2, color.g * 2.2, color.b * 2.2, 0.95)
		shard.z_index = Z_FX - 2
		host.add_child(shard)
		shard.global_position = pos + Vector2(cos(a), sin(a)) * radius * 0.6
		var away: Vector2 = shard.global_position + Vector2(cos(a), sin(a)) * randf_range(50.0, 110.0)
		var tw := shard.create_tween()
		tw.tween_property(shard, "global_position", away, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(shard, "rotation", randf_range(-3.0, 3.0), 0.42)
		tw.parallel().tween_property(shard, "modulate:a", 0.0, 0.42)
		tw.tween_callback(shard.queue_free)
	ring(host, pos, color, radius * 0.45, radius * 1.7, 0.3, 5.0, 1.0, 24)

# ----------------------------------------------------------- telegraphs ----

## Ground telegraph: an outline at the danger radius plus a disc that fills over
## `fill_time`. When the disc is full, the hit lands. Fair difficulty, drawn.
## Returns the node so the caller can cancel it (stun, death) by freeing it.
##
## VISUAL_BIBLE_V2: a telegraph is a SHAPE, not a light. Round 6 drew both layers
## additively with a 1.9x overbright edge, which at bloom threshold 1.0 turned
## every wind-up into a soft radial gradient bleeding across the floor — the
## exact smooth-glow read the QA critique named. Same information, flat: a 1px
## outline that thickens to 2px as the disc fills, both under 60% alpha.
static func marker(host: Node, pos: Vector2, color: Color, radius: float, fill_time: float) -> Node2D:
	if not _ok(host):
		return null
	var root := Node2D.new()
	root.z_index = Z_GROUND  # painted on the floor, under the fighters
	host.add_child(root)
	root.global_position = pos

	var disc := Polygon2D.new()
	disc.polygon = ring_points(28)
	disc.color = Color(color.r, color.g, color.b, 0.18)
	disc.scale = Vector2(0.01, 0.01)
	root.add_child(disc)

	var edge := Line2D.new()
	edge.points = ring_points(32)
	edge.scale = Vector2.ONE * radius
	edge.width = 2.0 / radius
	edge.default_color = Color(color.r, color.g, color.b, 0.6)
	root.add_child(edge)

	var tw := root.create_tween()
	tw.tween_property(disc, "scale", Vector2.ONE * radius, fill_time).set_trans(Tween.TRANS_LINEAR)
	tw.parallel().tween_property(edge, "width", 4.0 / radius, fill_time)
	tw.tween_property(root, "modulate:a", 0.0, 0.16)
	tw.tween_callback(root.queue_free)
	return root

## Melee wind-up arc: a wedge in front of the attacker that fills toward the
## strike. Same contract as `marker` — free it to cancel.
static func strike_arc(host: Node, pos: Vector2, dir: Vector2, color: Color,
		radius: float, fill_time: float) -> Node2D:
	if not _ok(host) or dir.length_squared() < 0.0001:
		return null
	var root := Node2D.new()
	root.z_index = Z_GROUND
	host.add_child(root)
	root.global_position = pos

	# Flat fill, not additive: the wedge says WHERE, and it says it by covering
	# floor, not by lighting it (LAW 3 — the floor is not one of the five things
	# allowed to be bright). Capped at 60% so the ground is still readable under
	# the thing that is about to hit you.
	var wedge := Polygon2D.new()
	wedge.polygon = wedge_points(dir.angle(), 1.5, 14)
	wedge.color = Color(color.r, color.g, color.b, 0.0)
	wedge.scale = Vector2.ONE * radius
	root.add_child(wedge)

	var tw := root.create_tween()
	tw.tween_property(wedge, "color:a", 0.28, fill_time * 0.8)
	tw.tween_property(wedge, "color:a", 0.6, fill_time * 0.2)
	tw.tween_property(root, "modulate:a", 0.0, 0.12)
	tw.tween_callback(root.queue_free)
	return root

# ---------------------------------------------------------- afterimages ----

## The texture a sprite is showing RIGHT NOW — Sprite2D or AnimatedSprite2D.
## Null for anything else, for a frameless animation, or for a freed node, so
## every caller must tolerate null. This is what lets a death animation be built
## out of copies parented to the ROOM: the corpse can leave on its own 0.45s
## budget while its remains keep moving.
static func frame_texture(src: Node2D) -> Texture2D:
	if src == null or not is_instance_valid(src):
		return null
	if src is AnimatedSprite2D:
		var a := src as AnimatedSprite2D
		if a.sprite_frames == null or not a.sprite_frames.has_animation(a.animation):
			return null
		return a.sprite_frames.get_frame_texture(a.animation, a.frame)
	if src is Sprite2D:
		return (src as Sprite2D).texture
	return null


## A frozen, overbright copy of a sprite — the smear a fast thing leaves behind.
## Handles both Sprite2D and AnimatedSprite2D sources; silently no-ops for
## anything else (or a frameless animation).
## `z_bias` is applied on top of the world's y-sort convention (`int(y)`), so a
## ghost sits at the same depth as the thing that cast it instead of behind the
## scenery.
static func afterimage(host: Node, src: Node2D, color: Color, duration: float = 0.34,
		offset: Vector2 = Vector2.ZERO, z_bias: int = -1) -> Sprite2D:
	if not _ok(host) or src == null or not is_instance_valid(src):
		return null
	var tex := frame_texture(src)
	if tex == null:
		return null
	var flip: bool = src.get("flip_h") == true
	var ghost := Sprite2D.new()
	ghost.texture = tex
	ghost.flip_h = flip
	ghost.material = FxLib.additive_material()
	ghost.modulate = Color(color.r, color.g, color.b, color.a)
	host.add_child(ghost)
	ghost.global_position = src.global_position + offset
	ghost.z_index = int(ghost.global_position.y) + z_bias
	ghost.scale = src.global_scale
	ghost.rotation = src.global_rotation
	var tw := ghost.create_tween()
	tw.tween_property(ghost, "modulate:a", 0.0, duration)
	tw.tween_callback(ghost.queue_free)
	return ghost

## Speed lines: short streaks flying past, opposite `dir`. Cheap, and instantly
## reads as "fast" even at 2x zoom on a dark floor.
static func speed_lines(host: Node, pos: Vector2, dir: Vector2, color: Color, count: int = 5) -> void:
	if not _ok(host) or dir.length_squared() < 0.0001:
		return
	var perp := dir.orthogonal()
	for i in count:
		var lat: float = randf_range(-26.0, 26.0)
		var start: Vector2 = pos + perp * lat - dir * randf_range(0.0, 18.0)
		var line := Line2D.new()
		line.top_level = true
		line.points = PackedVector2Array([start, start - dir * randf_range(26.0, 54.0)])
		line.width = randf_range(1.5, 3.2)
		line.material = FxLib.additive_material()
		line.default_color = Color(color.r * 1.8, color.g * 1.8, color.b * 1.8, 0.7)
		line.z_index = Z_FX - 6
		host.add_child(line)
		var tw := line.create_tween()
		tw.tween_property(line, "modulate:a", 0.0, randf_range(0.14, 0.26))
		tw.tween_callback(line.queue_free)

# --------------------------------------------------------------- deaths ----
## Per-type death treatments. The enemies in this game are bugs, rate limiters,
## merge conflicts and scope creep, and a generic dissolve throws away the whole
## joke — a merge conflict should come apart into two halves that disagree, and
## scope creep should let out all the air it spent the fight taking in.
##
## Every treatment builds host-parented COPIES of the sprite (see
## `frame_texture`), so it is completely independent of the corpse's own
## teardown: enemy_base can keep freeing itself inside its 0.45s budget and
## these keep playing on the region afterwards. Nothing here touches `src`.

## Which flourish each enemy type gets. Unknown types fall through to the
## dissolve, so a new enemy is never worse off than it is today.
const DEATH_STYLES := {
	"bug": "shatter",
	"merge_conflict": "split",
	"scope_creep": "deflate",
	"memory_leak": "deflate",
	"rate_limiter": "shatter",
	"hallucination": "glitch",
	"cloud_bill": "deflate",
	"dependency_demon": "shatter",
	"enterprise_architect": "shatter",
	"legacy_monolith": "shatter",
	"legacy_system": "shatter",
	"null_reference": "glitch",
	"infinite_context": "glitch",
}

## RGB-split tints for `glitch_out`. Const so the loop below can annotate the
## element type and keep inference alive (untyped literals make Variants).
const GLITCH_TINTS := [
	Color(2.4, 0.35, 0.55, 0.7),
	Color(0.35, 2.3, 0.95, 0.7),
	Color(0.45, 0.70, 2.5, 0.7),
]

## One host-parented copy of `src`'s current frame, at its current transform.
## Plain blending (not additive), because a corpse coming apart is matter, not
## light. Returns null when there is nothing to copy.
static func _corpse_ghost(host: Node, src: Node2D, z_bias: int = 0) -> Sprite2D:
	var tex := frame_texture(src)
	if not _ok(host) or tex == null:
		return null
	var g := Sprite2D.new()
	g.texture = tex
	g.flip_h = src.get("flip_h") == true
	host.add_child(g)
	g.global_position = src.global_position
	g.scale = src.global_scale
	g.rotation = src.global_rotation
	g.z_index = int(g.global_position.y) + z_bias
	return g

## Dispatch the treatment for `kind` (an enemy_type). Safe to call for anything;
## unknown types dissolve. This is the single entry point callers need.
static func death_treatment(host: Node, src: Node2D, kind: String, color: Color,
		duration: float = 0.5) -> void:
	if not _ok(host) or src == null or not is_instance_valid(src):
		return
	var style: String = str(DEATH_STYLES.get(kind, "dissolve"))
	match style:
		"shatter":
			shatter(host, src, color, 3, duration + 0.12)
		"deflate":
			deflate(host, src, color, duration + 0.06)
		"split":
			split_ghosts(host, src, color, duration)
		"glitch":
			glitch_out(host, src, color, duration * 0.8)
		_:
			dissolve_ghost(host, src, color, duration)

## Comes apart into a grid of cells that fly out and fall. The cells are real
## regions of the enemy's own texture, so what hits the floor is recognisably
## the thing you just killed. Used for anything that should read as BREAKING
## (bugs, rate limiters, monoliths).
static func shatter(host: Node, src: Node2D, color: Color, pieces: int = 3,
		duration: float = 0.6) -> void:
	var tex := frame_texture(src)
	if not _ok(host) or tex == null:
		return
	var size: Vector2 = tex.get_size()
	if size.x < 6.0 or size.y < 6.0:
		return
	var n: int = clampi(pieces, 2, 4)
	var cw: float = size.x / float(n)
	var ch: float = size.y / float(n)
	var origin: Vector2 = src.global_position
	var sc: Vector2 = src.global_scale
	# A flipped source is reproduced by mirroring BOTH the cell's draw scale and
	# its offset. `flip_h` per shard would mirror each cell inside itself, which
	# scrambles the sprite instead of flipping it.
	var mirror: float = -1.0 if src.get("flip_h") == true else 1.0
	for gy in n:
		for gx in n:
			var shard := Sprite2D.new()
			shard.texture = tex
			shard.region_enabled = true
			shard.region_rect = Rect2(cw * float(gx), ch * float(gy), cw, ch)
			shard.scale = Vector2(sc.x * mirror, sc.y)
			shard.z_index = Z_FX - 8
			host.add_child(shard)
			# Where this cell sat inside the sprite, converted to world space.
			var local := Vector2(
				((float(gx) + 0.5) * cw - size.x * 0.5) * mirror,
				(float(gy) + 0.5) * ch - size.y * 0.5)
			shard.global_position = origin + Vector2(local.x * sc.x, local.y * sc.y)
			var away := Vector2(randf_range(-1.0, 1.0), -1.0)
			if local.length_squared() > 0.01:
				away = local.normalized()
			var land: Vector2 = shard.global_position \
				+ away * randf_range(22.0, 58.0) + Vector2(0.0, randf_range(18.0, 50.0))
			var tw := shard.create_tween()
			tw.tween_property(shard, "global_position", land, duration) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.parallel().tween_property(shard, "rotation", randf_range(-2.6, 2.6), duration)
			tw.parallel().tween_property(shard, "modulate:a", 0.0, duration).set_ease(Tween.EASE_IN)
			tw.tween_callback(shard.queue_free)
	ring(host, origin, color, 4.0, 46.0, 0.26, 5.0, 1.0, 20, 0.8)

## Lets out all the air it spent the fight taking in: the body squashes flat and
## spreads sideways while a jet of debris fires out of it. Scope Creep, Memory
## Leak and the Cloud Bill all die of the same thing — being over-inflated.
static func deflate(host: Node, src: Node2D, color: Color, duration: float = 0.55) -> void:
	var g := _corpse_ghost(host, src, 2)
	if g == null:
		return
	var base: Vector2 = g.scale
	var pos: Vector2 = g.global_position
	var tw := g.create_tween()
	# One last indignant swell, then all the way down.
	tw.tween_property(g, "scale", Vector2(base.x * 1.22, base.y * 1.12), duration * 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(g, "scale", Vector2(base.x * 1.9, base.y * 0.10), duration * 0.82) \
		.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(g, "global_position", pos + Vector2(0.0, 12.0), duration * 0.82)
	tw.parallel().tween_property(g, "rotation", randf_range(-0.22, 0.22), duration * 0.82)
	tw.parallel().tween_property(g, "modulate:a", 0.0, duration * 0.82).set_ease(Tween.EASE_IN)
	tw.tween_callback(g.queue_free)
	# The air going out, both ways, along the floor.
	for k: float in [1.0, -1.0]:
		FxLib.burst(host, pos + Vector2(k * 6.0, 4.0),
			Color(color.r * 1.8, color.g * 1.8, color.b * 1.8), 7, 210.0,
			FxLib.glow_dot(), Vector2(0.0, 40.0), Z_FX - 4,
			Vector2(k, -0.15), 26.0, 0.5, 0.85)

## Resolves into two halves that immediately disagree about which one was right.
## The merge conflict's whole personality, played back at the moment of death.
static func split_ghosts(host: Node, src: Node2D, color: Color, duration: float = 0.55) -> void:
	var other := color.lerp(Color("#3D9BFF"), 0.65)
	for k: float in [-1.0, 1.0]:
		var g := _corpse_ghost(host, src, 1)
		if g == null:
			return
		var tint: Color = color if k < 0.0 else other
		g.modulate = Color(tint.r * 1.5 + 0.35, tint.g * 1.5 + 0.35, tint.b * 1.5 + 0.35, 0.92)
		var pos: Vector2 = g.global_position
		var tw := g.create_tween()
		tw.tween_property(g, "global_position", pos + Vector2(k * 44.0, -10.0), duration) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(g, "rotation", k * 0.55, duration)
		tw.parallel().tween_property(g, "scale", g.scale * 0.72, duration)
		tw.parallel().tween_property(g, "modulate:a", 0.0, duration).set_ease(Tween.EASE_IN)
		tw.tween_callback(g.queue_free)

## Stops having ever existed: three RGB-split copies jitter apart and blink out.
## For the things whose death is an epistemics problem — hallucinations, null
## references, infinite context.
static func glitch_out(host: Node, src: Node2D, color: Color, duration: float = 0.42) -> void:
	for k in 3:
		var g := _corpse_ghost(host, src, int(k) - 1)
		if g == null:
			return
		var tint: Color = GLITCH_TINTS[k]
		g.material = FxLib.additive_material()
		g.modulate = tint
		var pos: Vector2 = g.global_position
		var base: Vector2 = g.scale
		var tw := g.create_tween()
		# Three hard jumps, not a slide — a glitch has no in-between frames.
		for step in 3:
			tw.tween_property(g, "global_position",
				pos + Vector2(randf_range(-16.0, 16.0), randf_range(-9.0, 9.0)),
				duration / 3.0).set_trans(Tween.TRANS_LINEAR)
			tw.parallel().tween_property(g, "scale",
				base * Vector2(randf_range(0.86, 1.2), randf_range(0.8, 1.14)), duration / 3.0)
		tw.tween_callback(g.queue_free)
		# The fade is its own tween so it spans all three jumps instead of only
		# the last one (a `parallel()` after the loop attaches to that step).
		var fade := g.create_tween()
		fade.tween_property(g, "modulate:a", 0.0, duration).set_ease(Tween.EASE_IN)
	# A single accent ring so the glitch still reads as belonging to this enemy.
	# No caption here on purpose: enemy_base owns every word a death says
	# (`_death_comedy`), and stacking a second line on top of "undefined" would
	# make both unreadable. This file supplies the treatment, not the joke.
	ring(host, src.global_position, color, 3.0, 40.0, 0.22, 4.0, 1.0, 20, 0.7)

## The default: burns away through the dissolve shader, on a host-parented copy.
## The uniform is SEEDED before the tween — a shader uniform that was never set
## does not exist on the material and cannot be tweened (HANDOVER gotcha 2).
## Degrades to a bright pop-fade when the shader library is absent.
static func dissolve_ghost(host: Node, src: Node2D, color: Color, duration: float = 0.5) -> void:
	var g := _corpse_ghost(host, src, 1)
	if g == null:
		return
	var tw := g.create_tween()
	if ResourceLoader.exists(DISSOLVE_PATH):
		var mat := ShaderMaterial.new()
		mat.shader = load(DISSOLVE_PATH)
		mat.set_shader_parameter("progress", 0.0)
		mat.set_shader_parameter("edge_color", color)
		mat.set_shader_parameter("pixel_size", 2.0)
		mat.set_shader_parameter("edge_width", 0.16)
		g.material = mat
		g.modulate = Color(1.3, 1.3, 1.3, 1.0)
		tw.tween_property(mat, "shader_parameter/progress", 1.0, duration)
	else:
		g.modulate = Color(2.2, 2.2, 2.2, 1.0)
		tw.tween_property(g, "modulate:a", 0.0, duration)
	tw.parallel().tween_property(g, "global_position",
		g.global_position + Vector2(0.0, -12.0), duration)
	tw.tween_callback(g.queue_free)

# ---------------------------------------------------------------- text ----

## Floating text. Used for ability callouts, stack frames, "429", and the
## occasional line of commentary from a game that is worried about you.
static func glyph(host: Node, pos: Vector2, text: String, color: Color,
		size: int = 18, duration: float = 1.0, rise: float = 34.0) -> Label:
	if not _ok(host) or text.is_empty():
		return null
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	lbl.add_theme_constant_override("outline_size", 6)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.custom_minimum_size = Vector2(260, 0)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.z_index = Z_TEXT
	host.add_child(lbl)
	lbl.global_position = pos + Vector2(-130, -10)
	lbl.scale = Vector2(0.7, 0.7)
	lbl.pivot_offset = Vector2(130, 10)
	var tw := lbl.create_tween()
	tw.tween_property(lbl, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(lbl, "global_position",
		lbl.global_position + Vector2(0, -rise), duration).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, duration).set_ease(Tween.EASE_IN)
	tw.tween_callback(lbl.queue_free)
	return lbl

## Blood substitute. Fragments of error text spray out of whatever just took a
## fatal amount of damage and tumble to the floor. Nothing bleeds in this game;
## things leak stack frames.
static func text_shards(host: Node, pos: Vector2, color: Color, words: Array, count: int = 4) -> void:
	if not _ok(host) or words.is_empty():
		return
	for i in mini(count, 6):
		var word: String = str(words[randi() % words.size()])
		var lbl := Label.new()
		lbl.text = word
		lbl.add_theme_font_size_override("font_size", randi_range(11, 15))
		lbl.add_theme_color_override("font_color", Color(color.r * 1.4, color.g * 1.4, color.b * 1.4))
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		lbl.add_theme_constant_override("outline_size", 4)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.z_index = Z_TEXT - 4
		host.add_child(lbl)
		lbl.global_position = pos
		var ang := randf() * TAU
		var dist := randf_range(38.0, 96.0)
		var land: Vector2 = pos + Vector2(cos(ang), sin(ang) * 0.6) * dist + Vector2(0, 18)
		# Two stages, so the shards ARC instead of sliding along a straight line
		# to where they land: thrown up and out, then dropped. Rotation and fade
		# run on their own tweens across the whole flight.
		var apex: Vector2 = pos.lerp(land, 0.55) + Vector2(0, -randf_range(22.0, 44.0))
		var tw := lbl.create_tween()
		tw.tween_property(lbl, "global_position", apex, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(lbl, "global_position", land, 0.36).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(lbl.queue_free)
		var spin := lbl.create_tween()
		spin.tween_property(lbl, "rotation", randf_range(-1.1, 1.1), 0.58)
		spin.parallel().tween_property(lbl, "modulate:a", 0.0, 0.58).set_ease(Tween.EASE_IN)

# ----------------------------------------------------------- the duck ----

## A rubber duck, drawn from polygons because nobody shipped a duck sprite and
## the joke does not survive being cut. Returns the node; it animates and frees
## itself over `duration`.
static func duck(host: Node, pos: Vector2, size: float = 1.0, duration: float = 1.5) -> Node2D:
	if not _ok(host):
		return null
	var body_col := Color("#FFD34D")
	var light_col := Color("#FFF0A8")
	var beak_col := Color("#FF8A2D")
	var dark := Color(0.04, 0.05, 0.09, 0.85)

	var root := Node2D.new()
	root.z_index = Z_FX + 4
	host.add_child(root)
	root.global_position = pos
	root.scale = Vector2(0.01, 0.01)

	var body := Polygon2D.new()
	var bp := PackedVector2Array()
	for i in 20:
		var a := TAU * float(i) / 20.0
		bp.append(Vector2(cos(a) * 23.0, 4.0 + sin(a) * 15.0))
	body.polygon = bp
	body.color = body_col
	root.add_child(body)

	var tail := Polygon2D.new()
	tail.polygon = PackedVector2Array([Vector2(-19, -2), Vector2(-36, -14), Vector2(-20, -11)])
	tail.color = body_col
	root.add_child(tail)

	var head := Polygon2D.new()
	var hp := PackedVector2Array()
	for i in 16:
		var a := TAU * float(i) / 16.0
		hp.append(Vector2(15.0 + cos(a) * 12.0, -15.0 + sin(a) * 12.0))
	head.polygon = hp
	head.color = body_col
	root.add_child(head)

	# Light source is top-left everywhere in this game (VISUAL_BIBLE).
	var sheen := Polygon2D.new()
	var sp := PackedVector2Array()
	for i in 10:
		var a: float = PI * 0.55 + PI * 0.9 * float(i) / 9.0
		sp.append(Vector2(13.0 + cos(a) * 8.5, -17.0 + sin(a) * 8.5))
	sp.append(Vector2(13, -17))
	sheen.polygon = sp
	sheen.color = light_col
	root.add_child(sheen)

	var beak := Polygon2D.new()
	beak.polygon = PackedVector2Array([Vector2(24, -19), Vector2(40, -13), Vector2(24, -9)])
	beak.color = beak_col
	root.add_child(beak)

	var eye := Polygon2D.new()
	var ep := PackedVector2Array()
	for i in 8:
		var a := TAU * float(i) / 8.0
		ep.append(Vector2(18.0 + cos(a) * 2.6, -19.0 + sin(a) * 2.6))
	eye.polygon = ep
	eye.color = dark
	root.add_child(eye)

	# Rise, wobble with the smugness of something that already knows the bug,
	# then shrink away.
	var tw := root.create_tween()
	tw.tween_property(root, "scale", Vector2(size * 1.15, size * 1.15), 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(root, "scale", Vector2(size, size), 0.12)
	tw.parallel().tween_property(root, "global_position", pos + Vector2(0, -14.0 * size), 0.34) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(maxf(0.1, duration - 0.9))
	tw.tween_property(root, "scale", Vector2(size * 1.25, size * 0.55), 0.12)
	tw.tween_property(root, "scale", Vector2(0.01, 0.01), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(root, "modulate:a", 0.0, 0.16)
	tw.tween_callback(root.queue_free)

	var bob := body.create_tween().set_loops()
	bob.tween_property(root, "rotation", 0.10, 0.3).set_trans(Tween.TRANS_SINE)
	bob.tween_property(root, "rotation", -0.10, 0.3).set_trans(Tween.TRANS_SINE)
	return root

# -------------------------------------------------------------- clocks ----

## The Ctrl+Z glyph: a circular arrow sweeping ANTI-clockwise, with two clock
## hands winding backwards inside it. Undo, but for your entire body.
static func undo_clock(host: Node, pos: Vector2, color: Color, radius: float = 46.0,
		duration: float = 0.7) -> void:
	if not _ok(host):
		return
	var root := Node2D.new()
	root.z_index = Z_TEXT - 10
	host.add_child(root)
	root.global_position = pos

	# The arc: 300 degrees of circle, leaving a gap for the arrow head.
	var arc := Line2D.new()
	var ap := PackedVector2Array()
	for i in 25:
		var a: float = -PI * 0.35 - TAU * 0.83 * float(i) / 24.0
		ap.append(Vector2(cos(a), sin(a)) * radius)
	arc.points = ap
	arc.width = 5.0
	arc.begin_cap_mode = Line2D.LINE_CAP_ROUND
	arc.end_cap_mode = Line2D.LINE_CAP_ROUND
	arc.material = FxLib.additive_material()
	arc.default_color = Color(color.r * 2.2, color.g * 2.2, color.b * 2.2, 1.0)
	root.add_child(arc)

	var head_a := -PI * 0.35
	var head_p: Vector2 = Vector2(cos(head_a), sin(head_a)) * radius
	var head := Polygon2D.new()
	head.polygon = PackedVector2Array([
		head_p + Vector2(-9, -11), head_p + Vector2(13, 0), head_p + Vector2(-9, 11)])
	head.color = Color(color.r * 2.2, color.g * 2.2, color.b * 2.2, 1.0)
	head.material = FxLib.additive_material()
	head.rotation = 0.0
	root.add_child(head)

	for k: float in [0.52, 0.34]:
		var hand := Line2D.new()
		hand.points = PackedVector2Array([Vector2.ZERO, Vector2(0, -radius * k)])
		hand.width = 3.4 if k > 0.4 else 4.6
		hand.begin_cap_mode = Line2D.LINE_CAP_ROUND
		hand.end_cap_mode = Line2D.LINE_CAP_ROUND
		hand.material = FxLib.additive_material()
		hand.default_color = Color(2.2, 2.4, 2.2, 0.9)
		root.add_child(hand)
		var spin := hand.create_tween()
		spin.tween_property(hand, "rotation", -TAU * (3.0 if k > 0.4 else 1.0), duration) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	root.scale = Vector2(0.4, 0.4)
	var tw := root.create_tween()
	tw.tween_property(root, "scale", Vector2(1.12, 1.12), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(root, "scale", Vector2(1.34, 1.34), duration - 0.16)
	tw.parallel().tween_property(root, "modulate:a", 0.0, duration - 0.16).set_ease(Tween.EASE_IN)
	tw.tween_callback(root.queue_free)

## Small orbiting glyphs above a node's head — confusion, stun, "what".
## Parented to `owner_node`, so it travels with it and dies with it.
static func dazed(owner_node: Node2D, height: float, color: Color, duration: float, mark: String = "?") -> Node2D:
	if owner_node == null or not is_instance_valid(owner_node):
		return null
	var root := Node2D.new()
	root.position = Vector2(0, -height)
	root.z_index = Z_TEXT + 4
	owner_node.add_child(root)
	for i in 3:
		var lbl := Label.new()
		lbl.text = mark
		lbl.add_theme_font_size_override("font_size", 17)
		lbl.add_theme_color_override("font_color", color)
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		lbl.add_theme_constant_override("outline_size", 4)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pivot := Node2D.new()
		pivot.rotation = TAU * float(i) / 3.0
		root.add_child(pivot)
		pivot.add_child(lbl)
		lbl.position = Vector2(16, -6)
		var spin := pivot.create_tween().set_loops()
		spin.tween_property(pivot, "rotation", pivot.rotation + TAU, 1.3)
	var tw := root.create_tween()
	tw.tween_interval(maxf(0.1, duration - 0.25))
	tw.tween_property(root, "modulate:a", 0.0, 0.25)
	tw.tween_callback(root.queue_free)
	return root
