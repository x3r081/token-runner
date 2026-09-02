class_name AbilityFx
extends Node2D
## The player's spectacle rig. Every ability gets a signature the player can
## recognise from across a dark room, and the player sprite gets the rim halo,
## motion lean and afterimages that let it hold its own against the environment
## art. Owned by Player, created in code (the .tscn stays untouched so every
## existing test that walks the player scene keeps working).
##
## Contract with Player:
##   setup(player, sprite)   once, in _ready
##   sample(delta)           once per physics frame (cheap: no allocations)
##   cast_*()                on ability use
##   open_cache/close_cache  around the Cache i-frame window
##   set_target(node)        aim-assist reticle (null = nothing targeted)
##   perfect_dodge/set_flow  the dash reward window
##   set_low_hp(on, hp)      the character-side "about to die" state
##   stride_wake(vel, s)     sprint settle texture
##   deny(text)              "that did not fire, and here is why"
##
## Everything degrades: missing FX art, missing shaders and a missing camera rig
## all just draw less. Nothing here can throw.

const CYAN := Color("#24F0DC")
const ACID := Color("#A8FF3E")
const GOLD := Color("#FFD34D")
const MAGENTA := Color("#FF2D95")
const VIOLET := Color("#8B5CF6")
const RED := Color("#FF4757")
const AMBER := Color("#FFB020")

## Rewind buffer: 48 samples at 16 Hz ~= 3 seconds of the player's own past,
## which is exactly the window Ctrl+Z can undo. Fixed size, written in place —
## zero allocations per frame.
const TRAIL_LEN := 48
const TRAIL_STEP := 0.0625

const SHIELD_RADIUS := 42.0

## Comedy: dealt through ComedyLines.pick() so nothing repeats in a session.
## (COMEDY_BIBLE says pools ideally live in comedy_lines.gd — these are combat
## callouts and are kept next to the code that fires them; see contracts.)
const HALLUCINATION_LINES := [
	"100% confident",
	"source: a blog from 2019",
	"per the documentation (there is no documentation)",
	"this compiles (it does not)",
	"i have verified this myself",
]
const DUCK_LINES := [
	"so anyway it worked yesterday",
	"wait. say that part again.",
	"okay so the array is zero-indexed —",
	"...oh. oh no. i see it.",
	"and THAT's why we don't do that",
]
const UNDO_LINES := [
	"that never happened",
	"no witnesses, no incident",
	"reverted. tests still red, but reverted.",
	"git reset --hard yourself",
	"the last two seconds are now unsourced",
]
const DEATH_SHARDS := [
	"SIGSEGV", "core dumped", "exit 137", "OOMKilled",
	"unhandled", "at main()", "null", "0x00000000",
]
## Low HP. Every line names a number or a key alongside the dread — the joke
## rides beside the information, it never replaces it (COMEDY_BIBLE).
const LOW_HP_LINES := [
	"this is the part before the postmortem",
	"[5] is Ctrl+Z. It undoes bodies too.",
	"[2] Cache eats one hit. Just one.",
	"not a great moment for one more room",
	"severity: yes",
	"[Shift] dashes. Backwards is a direction.",
]
## Cache eviction report. The bubble tells you what it actually did, because a
## defensive ability nobody can see working is one nobody presses again.
const CACHE_MISS_LINES := [
	"cache invalidated · 0 hits served",
	"cache miss · nothing asked for it",
	"evicted · you were never in danger",
]
var player: Node2D
var sprite: Node2D
var accent: Color = CYAN

var _trail: PackedVector2Array
var _trail_i := 0
var _trail_full := false
var _sample_t := 0.0
var _rim: AnimatedSprite2D
var _shield: Node2D
var _shield_open := false
var _lean := 0.0
var _turn := 0.0
var _last_dir := Vector2.ZERO
var _spr_base_x := 0.0
var _recoil_tween: Tween
## Earned states. Both retint the rim halo, so `hurt()` and `dash_end()` restore
## through _restore_rim() instead of hard-coding cyan back on.
var _flow_on := false
var _low_on := false
var _low_aura: Sprite2D
## Aim-assist reticle: one reused node, moved (never rebuilt) as the target
## changes. `top_level` so it lives in world space regardless of the player's
## transform.
var _reticle: Node2D
var _reticle_target: Node2D

func _ready() -> void:
	_trail = PackedVector2Array()
	_trail.resize(TRAIL_LEN)

## The reticle is parented to the WORLD (so it can sit on an enemy), which means
## it does not die with the player. Free it explicitly, or a region change or a
## freed player leaves a bracket hovering over nothing.
func _exit_tree() -> void:
	if is_instance_valid(_reticle):
		_reticle.queue_free()
	_reticle = null
	_reticle_target = null

## Wire up. `spr` may be an AnimatedSprite2D (normal) or anything Node2D-ish
## (defensive: a stripped test scene still has to work).
func setup(p: Node2D, spr: Node2D) -> void:
	player = p
	sprite = spr
	if is_instance_valid(sprite):
		_spr_base_x = sprite.position.x
	for i in TRAIL_LEN:
		_trail[i] = p.global_position if is_instance_valid(p) else Vector2.ZERO
	_build_rim()

## The world node effects should live on, so they survive the player being
## moved, killed or teleported. Falls back to ourselves.
func host() -> Node:
	if is_instance_valid(player):
		var pr := player.get_parent()
		if pr and pr.is_inside_tree():
			return pr
	return self

# -------------------------------------------------------- the rim halo ----

## A soft additive echo of the player sprite, one frame behind nothing and
## slightly larger, so the player reads as a LIT character instead of a sticker
## laid on top of a very expensive room. Frame-synced by signal, not per-frame
## polling, so it costs nothing while idle.
func _build_rim() -> void:
	if not (sprite is AnimatedSprite2D):
		return
	var src := sprite as AnimatedSprite2D
	if src.sprite_frames == null:
		return
	_rim = AnimatedSprite2D.new()
	_rim.sprite_frames = src.sprite_frames
	if src.sprite_frames.has_animation(src.animation):
		_rim.animation = src.animation
		_rim.frame = src.frame
	_rim.material = FxLib.additive_material()
	_rim.modulate = Color(accent.r * 1.5, accent.g * 1.5, accent.b * 1.5, 0.34)
	_rim.scale = src.scale * 1.07
	_rim.position = src.position
	_rim.z_index = -1
	if not is_instance_valid(player):
		_rim = null
		return
	player.add_child(_rim)
	if not src.frame_changed.is_connected(_sync_rim_frame):
		src.frame_changed.connect(_sync_rim_frame)
	if not src.animation_changed.is_connected(_sync_rim_anim):
		src.animation_changed.connect(_sync_rim_anim)
	var pulse := _rim.create_tween().set_loops()
	pulse.tween_property(_rim, "modulate:a", 0.44, 1.5).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(_rim, "modulate:a", 0.24, 1.5).set_trans(Tween.TRANS_SINE)

func _sync_rim_frame() -> void:
	if is_instance_valid(_rim) and sprite is AnimatedSprite2D:
		_rim.frame = (sprite as AnimatedSprite2D).frame

func _sync_rim_anim() -> void:
	if is_instance_valid(_rim) and sprite is AnimatedSprite2D:
		var a := sprite as AnimatedSprite2D
		if _rim.sprite_frames and _rim.sprite_frames.has_animation(a.animation):
			_rim.animation = a.animation

## Recolour the halo (dash = cyan hot, hurt = red, cached = shield colour).
func set_rim_color(c: Color, strength: float = 1.5) -> void:
	accent = c
	if is_instance_valid(_rim):
		var a: float = _rim.modulate.a
		_rim.modulate = Color(c.r * strength, c.g * strength, c.b * strength, a)

# ------------------------------------------------------------ per frame ----

## Cheap per-frame upkeep: rewind sampling, rim transform sync, motion lean.
## No allocations — the trail is a preallocated ring buffer written in place.
func sample(delta: float, moving_dir: Vector2 = Vector2.ZERO) -> void:
	if not is_instance_valid(player):
		return
	_sample_t += delta
	if _sample_t >= TRAIL_STEP:
		_sample_t = 0.0
		_trail[_trail_i] = player.global_position
		_trail_i = (_trail_i + 1) % TRAIL_LEN
		if _trail_i == 0:
			_trail_full = true
	if is_instance_valid(_reticle) and _reticle.visible:
		if is_instance_valid(_reticle_target):
			_reticle.global_position = _reticle_target.global_position + Vector2(0, -8)
			# Frame the target at ITS size. A boss is scaled 2x and a Scope Creep
			# grows as it eats, so a fixed 20px bracket ends up drawn INSIDE the
			# sprite — which reads as no bracket at all, on exactly the enemies
			# you most need to know you are locked onto.
			var ts: float = clampf(maxf(_reticle_target.scale.x, _reticle_target.scale.y),
				0.85, 3.2)
			_reticle.scale = Vector2(ts, ts)
		else:
			_reticle.visible = false
	if is_instance_valid(_rim) and is_instance_valid(sprite):
		_rim.position = sprite.position
		# The footstep squash lives on sprite.scale; the halo has to breathe with
		# it or it detaches from the body on every step.
		_rim.scale = sprite.scale * 1.07
		if sprite is AnimatedSprite2D:
			_rim.flip_h = (sprite as AnimatedSprite2D).flip_h
	# Motion lean: the sprite tips into the direction of travel and rights itself
	# when it stops. On top of that, a TURN lean — the cross product of last
	# frame's heading with this one is the signed turn rate, so cornering banks
	# the character into the corner and settles out of it. Two cheap terms, and
	# the character stops looking like it is being dragged on a rail.
	if is_instance_valid(sprite):
		var turn := 0.0
		if moving_dir.length_squared() > 0.04 and _last_dir.length_squared() > 0.04:
			turn = clampf(_last_dir.normalized().cross(moving_dir.normalized()) * 7.0, -1.0, 1.0)
		_last_dir = moving_dir
		_turn = lerpf(_turn, turn, clampf(delta * 7.0, 0.0, 1.0))
		var want: float = clampf(moving_dir.x, -1.0, 1.0) * 0.07 + _turn * 0.10
		_lean = lerpf(_lean, want, clampf(delta * 9.0, 0.0, 1.0))
		sprite.rotation = _lean
		if is_instance_valid(_rim):
			_rim.rotation = _lean

# ------------------------------------------------------------- reticle ----

## Name the target the aim assist has silently been choosing since round 1.
## Four corner brackets, dim, cyan — enough to say "this one", never enough to
## compete with the enemy's own telegraphs.
func set_target(t: Node2D) -> void:
	_reticle_target = t
	if t == null:
		if is_instance_valid(_reticle):
			_reticle.visible = false
		return
	if not is_instance_valid(_reticle):
		_build_reticle()
	if is_instance_valid(_reticle):
		_reticle.visible = true

func _build_reticle() -> void:
	var h := host()
	if h == null or not h.is_inside_tree():
		return
	var root := Node2D.new()
	root.name = "AimReticle"
	root.top_level = true
	root.z_index = CombatFx.Z_FX - 8
	root.modulate = Color(CYAN.r * 1.5, CYAN.g * 1.5, CYAN.b * 1.5, 0.5)
	h.add_child(root)
	for i in 4:
		var sx: float = 1.0 if i % 2 == 0 else -1.0
		var sy: float = 1.0 if i < 2 else -1.0
		var bracket := Line2D.new()
		bracket.points = PackedVector2Array([
			Vector2(sx * 20.0, sy * 9.0), Vector2(sx * 20.0, sy * 20.0), Vector2(sx * 9.0, sy * 20.0)])
		bracket.width = 2.0
		bracket.material = FxLib.additive_material()
		bracket.default_color = Color(CYAN.r * 1.8, CYAN.g * 1.8, CYAN.b * 1.8, 0.85)
		root.add_child(bracket)
	# The breathe is on ALPHA, not scale: sample() owns `scale` (it sizes the
	# brackets to the target), and a looping scale tween would fight it every
	# frame and win.
	var pulse := root.create_tween().set_loops()
	pulse.tween_property(root, "modulate:a", 0.72, 0.7).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(root, "modulate:a", 0.34, 0.7).set_trans(Tween.TRANS_SINE)
	_reticle = root

## Recent positions, oldest first, covering roughly `seconds` of the past.
func recent_positions(seconds: float, count: int = 6) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var span: int = mini(int(ceil(seconds / TRAIL_STEP)), TRAIL_LEN if _trail_full else _trail_i)
	if span <= 1:
		return out
	for i in count:
		var age: int = int(round(float(span - 1) * float(count - 1 - i) / float(maxi(1, count - 1))))
		var idx: int = (_trail_i - 1 - age + TRAIL_LEN * 2) % TRAIL_LEN
		out.append(_trail[idx])
	return out

# ------------------------------------------------------- Prompt Blast ----

## Muzzle flash, a gathering ring collapsing into the barrel, spark spray and a
## camera nudge. `weak` is the hallucination misfire: the model was extremely
## confident and extremely wrong, so the shot sputters and says so.
## `crit` (14% of shots) is gold-hot and hits the frame twice as hard as a
## normal shot; `heat` (0..1) is the cadence chain, so a sustained rhythm visibly
## runs the barrel hotter. Three shot flavours, three unmistakable looks:
## violet sputter, cyan bolt, gold hammer.
func cast_prompt_blast(dir: Vector2, color: Color, weak: bool, crit: bool = false,
		heat: float = 0.0) -> void:
	if not is_instance_valid(player):
		return
	var origin: Vector2 = player.global_position + dir * 18.0 + Vector2(0, -14)
	var h := host()
	if weak:
		CombatFx.muzzle(h, origin, dir, VIOLET, 0.55)
		CombatFx.glyph(h, player.global_position + Vector2(0, -74),
			ComedyLines.pick("hallucination_cast", HALLUCINATION_LINES), VIOLET, 15, 1.1, 26.0)
		FxLib.add_trauma(get_tree(), 0.05)
		_recoil(-dir, 1.5)
		return
	if crit:
		# The shot you want to keep rolling: a gold hammer with a ring behind it.
		CombatFx.muzzle(h, origin, dir, GOLD, 1.7)
		CombatFx.ripple(h, origin, dir, GOLD, 52.0, 0.26)
		CombatFx.ring(h, origin, GOLD, 4.0, 46.0, 0.26, 6.0, 1.0, 24, 1.1)
		FxLib.add_trauma(get_tree(), 0.16)
		_punch_zoom(0.028)
		_recoil(-dir, 7.0)
		return
	var power := 1.0 + clampf(heat, 0.0, 1.0) * 0.35
	CombatFx.muzzle(h, origin, dir, color, power)
	CombatFx.ripple(h, origin, dir, color, 34.0 * power, 0.22)
	FxLib.add_trauma(get_tree(), 0.09)
	_punch_zoom(0.018)
	_recoil(-dir, 4.0 + heat * 2.0)

# -------------------------------------------------------------- Cache ----

## The shield goes up: a hex bubble with a refraction rim. Idempotent.
func open_cache(color: Color) -> void:
	if _shield_open or not is_instance_valid(player):
		return
	_shield_open = true
	_shield = CombatFx.shield(player, color, SHIELD_RADIUS)
	if _shield:
		_shield.position = Vector2(0, -16)
	CombatFx.ring(host(), player.global_position + Vector2(0, -16), color, 4.0, 62.0, 0.34, 8.0, 1.5)
	CombatFx.glyph(host(), player.global_position + Vector2(0, -76), "CACHED · 1.5s", GameTheme.hot_of(color), 17, 0.9, 24.0)
	FxLib.add_trauma(get_tree(), 0.06)

## A hit hit the bubble instead of you. Say so, loudly — and count it, because
## the eviction report is what teaches the player that Cache is a REACTION.
func ping_cache(served: int = 0) -> void:
	if not _shield_open or _shield == null:
		return
	CombatFx.shield_ping(_shield, CYAN, SHIELD_RADIUS)
	if is_instance_valid(player):
		CombatFx.glyph(host(), player.global_position + Vector2(0, -58),
			"CACHE HIT" if served <= 1 else "CACHE HIT x%d" % served,
			Color("#7DFFF0"), 15, 0.7, 22.0)
	FxLib.add_trauma(get_tree(), 0.08)
	AudioManager.play_sfx("ui_click")

## Cache eviction. One of the two hard problems, solved here with violence — and
## with a hit-ratio report, so a well-timed bubble reads as a win and a panicked
## one reads as the miss it was.
func close_cache(served: int = 0, absorbed_dmg: int = 0, refund: int = 0) -> void:
	if not _shield_open:
		return
	_shield_open = false
	var pos: Vector2 = player.global_position + Vector2(0, -16) if is_instance_valid(player) else Vector2.ZERO
	CombatFx.shield_break(_shield, host(), pos, CYAN, SHIELD_RADIUS)
	_shield = null
	if served > 0:
		CombatFx.glyph(host(), pos + Vector2(0, -46),
			"evicted · %d hit%s, %d dmg served" % [served, "" if served == 1 else "s", absorbed_dmg],
			Color("#7DFFF0"), 14, 1.0, 24.0)
		if refund > 0:
			CombatFx.glyph(host(), pos + Vector2(40, -18), "+%d cp" % refund,
				Color("#24F0DC"), 17, 0.8, 30.0)
			CombatFx.ring(host(), pos, CYAN, 6.0, 54.0, 0.28, 5.0, 1.0, 24)
	else:
		CombatFx.glyph(host(), pos + Vector2(0, -46),
			ComedyLines.pick("cache_miss", CACHE_MISS_LINES), Color("#7C8BB0"), 13, 0.8, 20.0)

# -------------------------------------------------------- Rubber Duck ----

## A duck the size of a filing cabinet surfaces, explains your own bug back to
## you, and the shockwave stuns everything that was listening.
## `insight` / `bonus` describe the damage window the duck opens (Player owns the
## numbers; this only reports them). Naming the window is what turns the duck
## from "a stun" into "the setup half of a combo".
func cast_rubber_duck(radius: float, insight: float = 0.0, bonus: float = 0.0) -> void:
	if not is_instance_valid(player):
		return
	var h := host()
	var pos: Vector2 = player.global_position
	CombatFx.duck(h, pos + Vector2(0, -30), 1.9, 1.4)
	CombatFx.shockwave(h, pos, GOLD, radius, 0.42)
	CombatFx.ring(h, pos, AMBER, 8.0, radius * 0.66, 0.3, 6.0, 1.2, 28)
	CombatFx.ring(h, pos, GOLD, radius * 0.9, radius, 0.5, 3.0, 1.0, 36)
	FxLib.burst(h, pos, Color(GOLD.r * 2.0, GOLD.g * 2.0, GOLD.b * 2.0), 18, 260.0, FxLib.glow_dot(), Vector2.ZERO, CombatFx.Z_FX)
	CombatFx.glyph(h, pos + Vector2(0, -96),
		ComedyLines.pick("duck_cast", DUCK_LINES), GOLD, 16, 1.6, 30.0)
	if insight > 0.0:
		CombatFx.glyph(h, pos + Vector2(0, -68),
			"ROOT CAUSE FOUND · +%d%% dmg for %.1fs" % [int(round(bonus * 100.0)), insight],
			AMBER, 15, 1.3, 24.0)
	FxLib.add_trauma(get_tree(), 0.22)
	_punch_zoom(0.035)

# -------------------------------------------------------- Stack Trace ----

## A beam that punches straight through the line, leaves a scorch on the floor
## and a column of stack frames in the air behind it.
func cast_stack_trace(dir: Vector2, color: Color, reach: float = 720.0) -> void:
	if not is_instance_valid(player):
		return
	var h := host()
	var from: Vector2 = player.global_position + dir * 16.0 + Vector2(0, -14)
	var to: Vector2 = from + dir * reach
	CombatFx.beam(h, from, to, color, 16.0, 0.24)
	CombatFx.scorch(h, from + dir * 20.0, to, color, 2.0)
	CombatFx.muzzle(h, from, dir, color, 1.25)
	CombatFx.speed_lines(h, from + dir * 60.0, dir, color, 6)
	FxLib.add_trauma(get_tree(), 0.16)
	_punch_zoom(0.026)
	_recoil(-dir, 5.0)

# ------------------------------------------------------------- Ctrl+Z ----

## Rewind. The player's last few seconds light up as ghosts, then run backwards
## along the path while a clock unwinds over their head.
func cast_ctrl_z(healed: int) -> void:
	if not is_instance_valid(player):
		return
	var h := host()
	var pos: Vector2 = player.global_position
	var path := recent_positions(2.6, 6)

	if path.size() >= 2:
		var line := Line2D.new()
		line.top_level = true
		var pts := PackedVector2Array()
		for p in path:
			pts.append(p + Vector2(0, -16))
		pts.append(pos + Vector2(0, -16))
		line.points = pts
		line.width = 5.0
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		line.material = FxLib.additive_material()
		line.default_color = Color(ACID.r * 1.9, ACID.g * 1.9, ACID.b * 1.9, 0.8)
		line.z_index = 540
		h.add_child(line)
		var lt := line.create_tween()
		lt.tween_property(line, "width", 0.5, 0.5).set_ease(Tween.EASE_IN)
		lt.parallel().tween_property(line, "modulate:a", 0.0, 0.5)
		lt.tween_callback(line.queue_free)

	# Ghosts snap BACKWARD down the path, newest first — unmistakably a rewind.
	for i in range(path.size() - 1, 0, -1):
		var g := CombatFx.afterimage(h, sprite, Color(ACID.r * 1.6, ACID.g * 1.6, ACID.b * 1.6, 0.7), 0.42,
			path[i] - player.global_position, -2)
		if g == null:
			continue
		var target: Vector2 = path[i - 1] + (sprite.global_position - player.global_position)
		var gt := g.create_tween()
		gt.tween_interval(0.045 * float(path.size() - 1 - i))
		gt.tween_property(g, "global_position", target, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)

	CombatFx.undo_clock(h, pos + Vector2(0, -52), ACID, 44.0, 0.8)
	CombatFx.ring(h, pos, ACID, 3.0, 84.0, 0.4, 7.0, 1.2)
	FxLib.flash(h, pos + Vector2(0, -16), ACID, 0.4, 3.4, 0.35, CombatFx.Z_FX)
	if healed > 0:
		CombatFx.glyph(h, pos + Vector2(-26, -66), "+%d" % healed, Color(0.65, 2.0, 0.75), 26, 0.9, 40.0)
	CombatFx.glyph(h, pos + Vector2(0, -100),
		ComedyLines.pick("undo_cast", UNDO_LINES), ACID, 14, 1.4, 26.0)
	FxLib.add_trauma(get_tree(), 0.12)
	_punch_zoom(-0.022)

# --------------------------------------------------------------- Dash ----

## Force ripple, speed lines, and a cone of shoved dust. The dash is the panic
## button, so it has to look like one.
func dash_burst(dir: Vector2) -> void:
	if not is_instance_valid(player):
		return
	var h := host()
	var pos: Vector2 = player.global_position
	CombatFx.ripple(h, pos, dir, CYAN, 118.0, 0.32)
	CombatFx.ring(h, pos, CYAN, 6.0, 74.0, 0.26, 6.0, 1.0, 28)
	CombatFx.speed_lines(h, pos + Vector2(0, -14), dir, CYAN, 6)
	FxLib.burst(h, pos - dir * 12.0, Color(CYAN.r * 1.8, CYAN.g * 1.8, CYAN.b * 1.8), 10, 200.0, FxLib.spark(), -dir * 60.0, CombatFx.Z_FX)
	FxLib.add_trauma(get_tree(), 0.1)
	set_rim_color(Color("#7DFFF0"), 2.2)

## Chromatic smear: two offset ghosts in complementary neons, so the dash leaves
## an aberrated streak instead of a grey blur.
func dash_ghost(dir: Vector2) -> void:
	var h := host()
	# ONE ghost, not a chromatically-offset pair.
	#
	# This used to drop a cyan copy at 2.2x overbright and a magenta copy behind
	# it, i.e. it hand-drew the chromatic aberration that LAW 5 just deleted from
	# postfx.gdshader, in two hues no region owns, on the one sprite LAW 3 says
	# is already the brightest thing in the frame. player.gd now drops at most 2
	# ghosts per dash; each drop being a pair made that 4. It is one dim cool
	# trail copy, under 1.0 in every channel, so a dash reads as travel rather
	# than as a filter.
	CombatFx.afterimage(h, sprite, Color(0.34, 0.62, 0.72, 0.40), 0.30, -dir * 5.0, -2)

func dash_end() -> void:
	_restore_rim()

## The stride wake: once the sprint settles in, a few faint lines trail the
## player so long traversals read as travel instead of sliding. Deliberately
## dim — this is texture, not an effect.
func stride_wake(vel: Vector2, strength: float) -> void:
	if not is_instance_valid(player) or vel.length_squared() < 400.0:
		return
	var dir: Vector2 = vel.normalized()
	var c := Color(CYAN.r * 0.4 * strength, CYAN.g * 0.45 * strength, CYAN.b * 0.5 * strength)
	CombatFx.speed_lines(host(), player.global_position + Vector2(0, -10) - dir * 22.0, -dir, c, 3)

# ------------------------------------------------------- perfect dodge ----

## You dashed THROUGH a telegraphed attack. Gold shockwave, a callout that
## states the actual reward, and the rim goes gold for the duration — so the
## boost is visible on your own character the whole time it is running.
func perfect_dodge(duration: float, bonus: float, refresh: bool = false) -> void:
	if not is_instance_valid(player):
		return
	var h := host()
	var pos: Vector2 = player.global_position + Vector2(0, -16)
	CombatFx.ring(h, pos, GOLD, 10.0, 134.0, 0.44, 9.0, 1.2, 40, 1.3)
	CombatFx.ring(h, pos, Color(1, 1, 1), 6.0, 76.0, 0.3, 5.0, 1.0, 26)
	FxLib.burst(h, pos, Color(GOLD.r * 2.3, GOLD.g * 2.1, GOLD.b * 1.4), 16, 300.0,
		FxLib.spark(), Vector2.ZERO, CombatFx.Z_FX)
	var callout := "CLOSE CALL · +%d%% dmg / +speed, %.0fs" % [int(round(bonus * 100.0)), duration]
	if refresh:
		callout = "STILL IN FLOW · %.0fs" % duration
	CombatFx.glyph(h, pos + Vector2(0, -84), callout, GOLD, 18, 1.3, 34.0)
	FxLib.add_trauma(get_tree(), 0.14)
	_punch_zoom(0.03)  # snap IN on the frame you earned
	set_flow(true)

## Flow on/off. Only the rim is persistent — a permanent particle system on the
## player would fight every region's own atmosphere budget.
func set_flow(on: bool) -> void:
	if on == _flow_on:
		return
	_flow_on = on
	if not on and is_instance_valid(player):
		CombatFx.glyph(host(), player.global_position + Vector2(0, -66),
			"flow ended", Color("#7C8BB0"), 13, 0.7, 18.0)
	_restore_rim()

# ------------------------------------------------------------- low HP ----

## The state you must not be able to miss, read on the CHARACTER: a breathing
## red pool under your own feet, a red halo, and one warning that names the HP
## and a key. Armed once, on the crossing — never re-created per frame.
func set_low_hp(on: bool, hp_left: int = 0) -> void:
	if on == _low_on:
		return
	_low_on = on
	if not on:
		_clear_low_hp()
		_restore_rim()
		return
	_build_low_hp()
	_restore_rim()
	if is_instance_valid(player):
		CombatFx.glyph(host(), player.global_position + Vector2(0, -96),
			"%d HP · %s" % [hp_left, ComedyLines.pick("low_hp_warn", LOW_HP_LINES)],
			RED, 16, 1.9, 30.0)

func _build_low_hp() -> void:
	# NOTE: deliberately world-space only. hud.gd already owns the SCREEN half of
	# this state (its danger vignette + HP bar pulse, on the HUD's own layer at
	# its own LOW_HP_FRAC); a second full-screen red wash from here would stack
	# with it and crush the whole frame. What was missing was the state reading
	# on the CHARACTER — that is what this adds.
	if is_instance_valid(player) and (_low_aura == null or not is_instance_valid(_low_aura)):
		var tex := FxLib.light_texture()
		if tex:
			var aura := Sprite2D.new()
			aura.name = "LowHPAura"
			aura.texture = tex
			aura.material = FxLib.additive_material()
			aura.modulate = Color(RED.r * 1.7, RED.g * 0.5, RED.b * 0.55, 0.0)
			aura.scale = Vector2(1.15, 0.65)
			aura.position = Vector2(0, 6)
			aura.z_index = -2
			player.add_child(aura)
			var at := aura.create_tween().set_loops()
			at.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			# Peak capped under a full wash: nothing in the game heals except
			# Ctrl+Z, so this pool can sit under the player for the rest of a run
			# and must not bleach the floor material zone it stands on.
			at.tween_property(aura, "modulate:a", 0.40, 0.55).set_trans(Tween.TRANS_SINE)
			at.tween_property(aura, "modulate:a", 0.15, 0.85).set_trans(Tween.TRANS_SINE)
			_low_aura = aura

func _clear_low_hp() -> void:
	if _low_aura and is_instance_valid(_low_aura):
		_low_aura.queue_free()
	_low_aura = null

## One place decides what colour the halo goes back to, so the transient tints
## (dash, hurt) can never strand the player in the wrong persistent state.
func _restore_rim() -> void:
	if _flow_on:
		set_rim_color(GOLD, 2.4)
	elif _low_on:
		set_rim_color(RED, 1.9)
	else:
		set_rim_color(CYAN, 1.5)

# ------------------------------------------------------------- refusals ----

## "That did not fire, and here is why." Small, dim, and gone in under a second —
## information, not a scolding.
func deny(text: String) -> void:
	if not is_instance_valid(player) or text.is_empty():
		return
	var h := host()
	var pos: Vector2 = player.global_position + Vector2(0, -18)
	CombatFx.glyph(h, pos - Vector2(0, 58), text, Color("#FF8A8A"), 14, 0.8, 18.0)
	CombatFx.ring(h, pos, RED, 2.0, 24.0, 0.18, 3.0, 1.0, 16)

# --------------------------------------------------------------- pain ----

## Hit reaction: sparks off the player, a red halo beat, a recoil.
func hurt(amount: int, from_dir: Vector2) -> void:
	if not is_instance_valid(player):
		return
	var h := host()
	var pos: Vector2 = player.global_position + Vector2(0, -16)
	FxLib.burst(h, pos, Color(2.4, 0.7, 0.8), 9, 190.0, FxLib.spark(), Vector2.ZERO, CombatFx.Z_FX)
	CombatFx.ring(h, pos, RED, 4.0, 40.0, 0.24, 5.0, 1.0, 20)
	set_rim_color(RED, 2.4)
	var back := create_tween()
	back.tween_interval(0.3)
	back.tween_callback(_restore_rim)
	# Directional: the recoil throws you off the threat, the ripple is oriented
	# back along the line the hit came down, and the sparks spray off that side.
	# You should never have to guess what just hit you.
	if from_dir.length_squared() > 0.0001:
		_recoil(from_dir, 6.0)
		CombatFx.ripple(h, player.global_position + Vector2(0, -10), -from_dir, RED, 44.0, 0.24)
		FxLib.burst(h, pos - from_dir * 16.0, Color(2.6, 0.7, 0.7), 7, 210.0, FxLib.spark(),
			Vector2(0, 120), CombatFx.Z_FX)
	FxLib.add_trauma(get_tree(), clampf(float(amount) / 60.0, 0.12, 0.45))

## Death: the process exits. Ghosts spray out, the screen bleeds red for a beat,
## and the error text that killed you scatters across the floor. Purely
## cosmetic — the death/respawn flow above it is untouched and still synchronous.
func death_sequence() -> void:
	if not is_instance_valid(player):
		return
	var h := host()
	var pos: Vector2 = player.global_position
	# Nothing persistent survives the run ending: the shield, the Flow halo and
	# the low-HP dressing all go before the death screen opens — SILENTLY.
	# close_cache() would print an eviction report (a "cache miss" line, since
	# nothing hands it the counts on this path) and set_flow(false) would print
	# "flow ended", and neither is a caption worth stacking on the frame where
	# you died.
	if _shield_open:
		_shield_open = false
		CombatFx.shield_break(_shield, h, pos + Vector2(0, -16), CYAN, SHIELD_RADIUS)
		_shield = null
	_flow_on = false
	set_low_hp(false)
	_restore_rim()
	for i in 7:
		var a := TAU * float(i) / 7.0
		var off := Vector2(cos(a), sin(a) * 0.7) * randf_range(14.0, 34.0)
		var g := CombatFx.afterimage(h, sprite, Color(2.2, 0.6, 0.7, 0.6), 0.5, Vector2.ZERO, 1)
		if g:
			var gt := g.create_tween()
			gt.tween_property(g, "global_position", g.global_position + off * 3.0, 0.5) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			gt.parallel().tween_property(g, "rotation", randf_range(-1.4, 1.4), 0.5)
	CombatFx.shockwave(h, pos + Vector2(0, -16), RED, 150.0, 0.5)
	CombatFx.text_shards(h, pos + Vector2(0, -16), RED, DEATH_SHARDS, 6)
	FxLib.burst(h, pos + Vector2(0, -16), Color(2.6, 0.7, 0.8), 22, 320.0, FxLib.spark(), Vector2(0, 260), CombatFx.Z_FX)
	_red_out()
	_punch_zoom(0.05)  # slam IN on the last frame of your run

## A red vignette slam on its own layer, under the death screen (which world.gd
## puts on the HUD at layer 1... this sits at 2 and fades before the screen
## settles, so it never fights the UI for attention).
func _red_out() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 2
	# The death screen may pause the tree the moment it opens; this flash has to
	# finish and clean itself up regardless (hard rule: pause-proof nodes are
	# PROCESS_MODE_ALWAYS, and their tweens must say so too).
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var vig := GameTheme.make_vignette(Color(0.75, 0.06, 0.12))
	if vig == null:
		layer.queue_free()
		return
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vig.modulate.a = 0.0
	layer.add_child(vig)
	var tw := layer.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(vig, "modulate:a", 0.95, 0.08)
	tw.tween_property(vig, "modulate:a", 0.0, 0.75).set_ease(Tween.EASE_IN)
	tw.tween_callback(layer.queue_free)

## Reset every cosmetic the death sequence touched. Called from Player.respawn()
## so a respawned player is never left tilted, tinted or shielded.
func reset_cosmetics() -> void:
	if _shield_open:
		_shield_open = false
		if _shield and is_instance_valid(_shield):
			_shield.queue_free()
		_shield = null
	_lean = 0.0
	_turn = 0.0
	_last_dir = Vector2.ZERO
	_flow_on = false
	_low_on = false
	_clear_low_hp()
	set_target(null)
	if _recoil_tween and _recoil_tween.is_valid():
		_recoil_tween.kill()
	set_rim_color(CYAN, 1.5)
	if is_instance_valid(sprite):
		sprite.rotation = 0.0
		sprite.position.x = _spr_base_x
	if is_instance_valid(_rim):
		_rim.rotation = 0.0
		_rim.modulate.a = 0.34
	if is_instance_valid(player):
		for i in TRAIL_LEN:
			_trail[i] = player.global_position
		_trail_i = 0
		_trail_full = false

# ------------------------------------------------------------- helpers ----

## Kick the sprite a few pixels and let it spring back — recoil without ever
## touching the physics body (so it can't affect movement or collision).
func _recoil(dir: Vector2, strength: float = 4.0) -> void:
	if not is_instance_valid(sprite):
		return
	if _recoil_tween and _recoil_tween.is_valid():
		_recoil_tween.kill()
	_recoil_tween = create_tween()
	_recoil_tween.tween_property(sprite, "position:x", _spr_base_x + dir.x * strength, 0.05)
	_recoil_tween.tween_property(sprite, "position:x", _spr_base_x, 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _punch_zoom(amount: float) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var fx := tree.get_first_node_in_group("camera_fx")
	if fx and fx.has_method("punch_zoom"):
		fx.punch_zoom(amount)
