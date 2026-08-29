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
var _spr_base_x := 0.0
var _recoil_tween: Tween

func _ready() -> void:
	_trail = PackedVector2Array()
	_trail.resize(TRAIL_LEN)

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
	if is_instance_valid(_rim) and is_instance_valid(sprite):
		_rim.position = sprite.position
		if sprite is AnimatedSprite2D:
			_rim.flip_h = (sprite as AnimatedSprite2D).flip_h
	# Motion lean: the sprite tips into the direction of travel and rights itself
	# when it stops. Two lines of maths, and the character stops looking rigid.
	if is_instance_valid(sprite):
		var want: float = clampf(moving_dir.x, -1.0, 1.0) * 0.07
		_lean = lerpf(_lean, want, clampf(delta * 9.0, 0.0, 1.0))
		sprite.rotation = _lean
		if is_instance_valid(_rim):
			_rim.rotation = _lean

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
func cast_prompt_blast(dir: Vector2, color: Color, weak: bool) -> void:
	if not is_instance_valid(player):
		return
	var origin: Vector2 = player.global_position + dir * 18.0 + Vector2(0, -14)
	var h := host()
	if weak:
		CombatFx.muzzle(h, origin, dir, VIOLET, 0.55)
		CombatFx.glyph(h, player.global_position + Vector2(0, -74),
			ComedyLines.pick("hallucination_cast", HALLUCINATION_LINES), VIOLET, 15, 1.1, 26.0)
		FxLib.add_trauma(get_tree(), 0.05)
		return
	CombatFx.muzzle(h, origin, dir, color, 1.0)
	CombatFx.ripple(h, origin, dir, color, 34.0, 0.22)
	FxLib.add_trauma(get_tree(), 0.09)
	_punch_zoom(0.018)
	_recoil(-dir)

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
	CombatFx.glyph(host(), player.global_position + Vector2(0, -76), "CACHED", GameTheme.hot_of(color), 17, 0.9, 24.0)
	FxLib.add_trauma(get_tree(), 0.06)

## A hit hit the bubble instead of you. Say so, loudly.
func ping_cache() -> void:
	if not _shield_open or _shield == null:
		return
	CombatFx.shield_ping(_shield, CYAN, SHIELD_RADIUS)
	FxLib.add_trauma(get_tree(), 0.08)
	AudioManager.play_sfx("ui_click")

## Cache eviction. One of the two hard problems, solved here with violence.
func close_cache() -> void:
	if not _shield_open:
		return
	_shield_open = false
	var pos: Vector2 = player.global_position + Vector2(0, -16) if is_instance_valid(player) else Vector2.ZERO
	CombatFx.shield_break(_shield, host(), pos, CYAN, SHIELD_RADIUS)
	_shield = null
	CombatFx.glyph(host(), pos + Vector2(0, -46), "cache invalidated", Color("#7C8BB0"), 13, 0.8, 20.0)

# -------------------------------------------------------- Rubber Duck ----

## A duck the size of a filing cabinet surfaces, explains your own bug back to
## you, and the shockwave stuns everything that was listening.
func cast_rubber_duck(radius: float) -> void:
	if not is_instance_valid(player):
		return
	var h := host()
	var pos: Vector2 = player.global_position
	CombatFx.duck(h, pos + Vector2(0, -30), 1.9, 1.4)
	CombatFx.shockwave(h, pos, GOLD, radius, 0.42)
	CombatFx.ring(h, pos, AMBER, 8.0, radius * 0.66, 0.3, 6.0, 1.2, 28)
	FxLib.burst(h, pos, Color(GOLD.r * 2.0, GOLD.g * 2.0, GOLD.b * 2.0), 18, 260.0, FxLib.glow_dot(), Vector2.ZERO, CombatFx.Z_FX)
	CombatFx.glyph(h, pos + Vector2(0, -96),
		ComedyLines.pick("duck_cast", DUCK_LINES), GOLD, 16, 1.6, 30.0)
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
	CombatFx.afterimage(h, sprite, Color(0.4, 2.2, 2.0, 0.55), 0.32, -dir * 3.0, -2)
	CombatFx.afterimage(h, sprite, Color(2.2, 0.5, 1.4, 0.28), 0.28, -dir * 9.0, -3)

func dash_end() -> void:
	set_rim_color(CYAN, 1.5)

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
	back.tween_callback(set_rim_color.bind(CYAN, 1.5))
	if from_dir.length_squared() > 0.0001:
		_recoil(from_dir, 6.0)
	FxLib.add_trauma(get_tree(), clampf(float(amount) / 60.0, 0.12, 0.45))

## Death: the process exits. Ghosts spray out, the screen bleeds red for a beat,
## and the error text that killed you scatters across the floor. Purely
## cosmetic — the death/respawn flow above it is untouched and still synchronous.
func death_sequence() -> void:
	if not is_instance_valid(player):
		return
	var h := host()
	var pos: Vector2 = player.global_position
	if _shield_open:
		close_cache()
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
