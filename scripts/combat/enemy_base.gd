extends CharacterBody2D
class_name EnemyBase

@export var enemy_type: String = "bug"
@export var max_hp: int = 30
@export var damage: int = 10
@export var speed: float = 80.0
@export var token_drop: int = 8
@export var is_boss: bool = false
@export var generation: int = 0  # for merge_conflict splitting

@onready var sprite: Sprite2D = $Sprite2D
@onready var hitbox: Area2D = $Hitbox
@onready var attack_timer: Timer = $AttackTimer

## Enemies orbit the player at ENGAGE_DISTANCE and repel each other within
## SEPARATION_RADIUS instead of physically colliding with the player. Combined
## with the player/enemy collision masks (walls only), this makes it impossible
## for a ring of enemies to permanently trap the player. See tests/soft_lock_test.
const ENGAGE_DISTANCE := 34.0
const SEPARATION_RADIUS := 46.0
const KNOCKBACK_DECAY := 900.0
## Enemies only chase once the player comes within AGGRO_RADIUS, and give up
## (return home) if the player gets beyond LEASH_RADIUS. This keeps distant
## enemies from swarming across a room (which turned the opening into a death
## loop) and makes combat something the player chooses to walk into.
@export var aggro_radius: float = 340.0
const LEASH_MULT := 1.8

## Every attack is readable a beat before it lands: the enemy plants, squashes,
## shifts colour and paints a wedge on the floor for WINDUP_TIME, and only then
## strikes. Fair difficulty is a visual feature, not a difficulty slider.
const WINDUP_TIME := 0.34
const STRIKE_RANGE := 56.0

var hp: int
var target: Node2D = null
var _flash_tween: Tween
var _knockback := Vector2.ZERO
var _stun_time := 0.0
var _base_speed := 0.0
var _base_scale := Vector2.ONE
var _grow := 0.0
var _special_cd := 0.0
var _telegraph := 0.0
var _boss_tele := 0.0
var _dying := false
var _home := Vector2.ZERO
var _aggroed := false
var _anim_t := 0.0
var _spr_base_y := 0.0
var _spr_base_x := 0.0
var _spr_base_scale := Vector2.ONE
var _hp_bar: Node2D
var _hp_fill: ColorRect
const HP_BAR_W := 30.0

## Melee wind-up state.
var _windup := 0.0
var _wind_dir := Vector2.RIGHT
var _wind_marker: Node2D
## Scripted sprite poses (strike lunge, hit stagger, startle hop). `_process`
## rewrites the sprite transform every frame for the idle/scuttle animation, so
## poses are driven by the same function instead of by tweens that would fight
## it. Allocation-free, and it always resolves back to the base pose.
const POSE_STRIKE := 1
const POSE_STAGGER := 2
const POSE_HOP := 3
var _pose_kind := 0
var _pose_t := 0.0
var _pose_dur := 0.0
var _pose_dir := Vector2.RIGHT
var _pose_mag := 0.0
## Same-frame damage numbers merge into one readable total (a bolt registers on
## both the projectile's area and the enemy's hitbox in the same physics flush).
var _num_label: Label
var _num_frame := -1
var _num_total := 0
var _num_crit := false
## Stun dressing (orbiting question marks) — one at a time.
var _dazed: Node2D
## Boss presentation.
var _boss_hud: BossHud
var _boss_phase := 1
var _intro_done := false
var _intro_lock := 0.0
var _boss_marker: Node2D

## Per-type death accents (VISUAL_BIBLE palette) for the dissolve burn edge.
const DEATH_ACCENTS := {
	"bug": Color("#A8FF3E"),
	"merge_conflict": Color("#FF2D95"),
	"scope_creep": Color("#8B5CF6"),
	"memory_leak": Color("#3D9BFF"),
	"rate_limiter": Color("#FFB020"),
	"hallucination": Color("#8B5CF6"),
	"cloud_bill": Color("#6BC7FF"),
	"dependency_demon": Color("#A8FF3E"),
	"enterprise_architect": Color("#4D7CFF"),
	"legacy_monolith": Color("#C97B4A"),
	"legacy_system": Color("#C97B4A"),
	"null_reference": Color("#7C8BB0"),
	"infinite_context": Color("#24F0DC"),
}

## Blood substitute. Nothing bleeds in this game; things leak error text.
## Decorative only (COMEDY_BIBLE: surfaces nothing depends on may be pure joke).
const DEATH_SHARDS := {
	"bug": ["works on my machine", "cannot reproduce", "wontfix", "// TODO"],
	"merge_conflict": ["<<<<<<< HEAD", "=======", ">>>>>>> feature/x", "both modified"],
	"scope_creep": ["one tiny thing", "while you're in there", "quick win", "v2"],
	"memory_leak": ["freed 0 bytes", "still reachable", "heap: yes", "leak: definitely"],
	"rate_limiter": ["429", "retry-after: ?", "quota exceeded", "back off"],
	"hallucination": ["[citation needed]", "source: trust me", "as we all know", "confidently"],
	"cloud_bill": ["$0.02/req", "egress", "line item 47", "auto-renewed"],
	"dependency_demon": ["node_modules", "peer dep", "deprecated", "14,203 packages"],
	"enterprise_architect": ["let's circle back", "sync on this", "Q3 initiative", "align"],
	"legacy_monolith": ["since 2009", "do not remove", "// don't ask", "temp"],
	"legacy_system": ["since 2009", "payroll", "do not touch", "COBOL"],
	"null_reference": ["undefined", "null", "of undefined", "?."],
	"infinite_context": ["context exceeded", "as previously stated", "summarising", "..."],
}

## The one-line obituary. Shown on boss kills, and on a minority of normal ones
## so it stays a joke instead of becoming a subtitle track.
const DEATH_QUIPS := {
	"bug": "closed as cannot reproduce",
	"merge_conflict": "resolved. into two more.",
	"scope_creep": "and one last tiny thing",
	"memory_leak": "freed. allegedly.",
	"rate_limiter": "retry-after: never",
	"hallucination": "source: itself",
	"cloud_bill": "this does not cancel the subscription",
	"dependency_demon": "removed 1 package. 14,202 remain.",
	"enterprise_architect": "the calendar invite survives",
	"legacy_monolith": "something else just broke",
	"legacy_system": "payroll is now everyone's problem",
	"null_reference": "undefined is not a function",
	"infinite_context": "context window closed",
}

func _accent() -> Color:
	return DEATH_ACCENTS.get(enemy_type, Color("#FF4757"))

func _ready() -> void:
	add_to_group("enemy")
	hp = max_hp
	if is_boss:
		max_hp *= 4
		hp = max_hp
		damage *= 2
		token_drop *= 5
		scale = Vector2(2, 2)
	_base_speed = speed
	_base_scale = scale
	_special_cd = randf_range(2.5, 4.5)
	_home = global_position
	_spr_base_y = sprite.position.y
	_spr_base_x = sprite.position.x
	_spr_base_scale = sprite.scale
	_anim_t = randf() * TAU  # desync the herd so they don't bob in lockstep
	# Bosses own their arena — they always engage once you're in the room.
	if is_boss:
		aggro_radius = 900.0
	var tex_path := "res://assets/textures/generated/enemy_%s.png" % enemy_type
	if ResourceLoader.exists(tex_path):
		sprite.texture = load(tex_path)
	attack_timer.timeout.connect(_attack)
	attack_timer.start(randf_range(1.0, 2.0))
	_build_hp_bar()
	if is_boss:
		_build_boss_presence()

## A small health bar above the enemy (hidden until damaged) so the player can
## read at a glance whether they're winning a fight.
func _build_hp_bar() -> void:
	_hp_bar = Node2D.new()
	_hp_bar.position = Vector2(0, -32)
	# Absolute: the enemy y-sorts, so a relative z would put the bar at a
	# different depth in every part of the room.
	_hp_bar.z_as_relative = false
	_hp_bar.z_index = CombatFx.Z_TEXT - 10
	_hp_bar.visible = false
	add_child(_hp_bar)
	var bg := ColorRect.new()
	bg.size = Vector2(HP_BAR_W + 2, 5)
	bg.position = Vector2(-(HP_BAR_W + 2) * 0.5, 0)
	bg.color = Color(0, 0, 0, 0.75)
	_hp_bar.add_child(bg)
	_hp_fill = ColorRect.new()
	_hp_fill.size = Vector2(HP_BAR_W, 3)
	_hp_fill.position = Vector2(-HP_BAR_W * 0.5, 1)
	_hp_fill.color = Color(0.45, 0.9, 0.45)
	_hp_bar.add_child(_hp_fill)

func _update_hp_bar() -> void:
	if not is_instance_valid(_hp_bar):
		return
	var frac := clampf(float(hp) / float(maxi(1, max_hp)), 0.0, 1.0)
	# Bosses get the full-width bar at the bottom of the screen instead.
	_hp_bar.visible = hp < max_hp and hp > 0 and not is_boss
	_hp_fill.size.x = HP_BAR_W * frac
	_hp_fill.color = Color(0.45, 0.9, 0.45).lerp(Color(0.95, 0.3, 0.3), 1.0 - frac)
	if _boss_hud and is_instance_valid(_boss_hud):
		_boss_hud.set_health(hp, max_hp)

func stun(duration: float) -> void:
	_stun_time = maxf(_stun_time, duration)
	_cancel_windup()
	# Visibly dazed: orbiting question marks, so a stunned enemy is obviously
	# stunned and not just standing there being blue.
	if (_dazed == null or not is_instance_valid(_dazed)) and not _dying:
		_dazed = CombatFx.dazed(self, 40.0, Color("#FFD34D"), duration, "?")

## Procedural liveliness: idle enemies breathe; moving enemies scuttle-hop and
## waddle; winding-up enemies plant, coil and lean away from the swing. Runs
## every frame (independent of the physics early-returns) so even dormant or
## telegraphing enemies never look like frozen stickers.
func _process(delta: float) -> void:
	if not is_instance_valid(sprite) or _dying:
		return  # while dying, the death-pop tween owns the sprite's scale/modulate
	_anim_t += delta
	if _windup > 0.0:
		# Coil: pull back away from the strike, squash wide, heat up.
		var t: float = 1.0 - clampf(_windup / WINDUP_TIME, 0.0, 1.0)
		sprite.position = Vector2(_spr_base_x - _wind_dir.x * 7.0 * t, _spr_base_y - 2.0 * t)
		sprite.rotation = -_wind_dir.x * 0.16 * t
		sprite.scale = Vector2(
			_spr_base_scale.x * (1.0 + 0.18 * t),
			_spr_base_scale.y * (1.0 - 0.14 * t))
		var hot := _accent()
		sprite.modulate = Color.WHITE.lerp(Color(hot.r * 2.0 + 0.6, hot.g * 1.2, hot.b * 1.2), t * 0.85)
		return
	if _pose_t > 0.0:
		_tick_pose(delta)
		return
	if _stun_time > 0.0:
		# Stunned: a dizzy wobble.
		sprite.position = Vector2(_spr_base_x, _spr_base_y)
		sprite.rotation = sin(_anim_t * 22.0) * 0.18
		sprite.scale = _spr_base_scale
		return
	if velocity.length() > 12.0:
		# Scuttle: a springy hop with squash-and-stretch and a waddle.
		var hop := absf(sin(_anim_t * 11.0))
		sprite.position = Vector2(_spr_base_x, _spr_base_y - hop * 7.0)
		sprite.rotation = sin(_anim_t * 11.0) * 0.14
		sprite.scale = Vector2(_spr_base_scale.x * (1.0 - hop * 0.12), _spr_base_scale.y * (1.0 + hop * 0.16))
	else:
		# Idle: breathe (bob + gentle squash).
		var b := sin(_anim_t * 2.8)
		sprite.position = Vector2(_spr_base_x, _spr_base_y + b * 2.4)
		sprite.rotation = lerp_angle(sprite.rotation, 0.0, delta * 8.0)
		sprite.scale = Vector2(_spr_base_scale.x * (1.0 + b * 0.05), _spr_base_scale.y * (1.0 - b * 0.05))

## Start a scripted pose. Overrides the idle/scuttle animation for `dur`.
func _set_pose(kind: int, dir: Vector2, magnitude: float, dur: float) -> void:
	if _dying:
		return
	_pose_kind = kind
	_pose_dir = dir if dir.length_squared() > 0.0001 else Vector2.RIGHT
	_pose_mag = magnitude
	_pose_dur = maxf(dur, 0.02)
	_pose_t = _pose_dur

func _tick_pose(delta: float) -> void:
	_pose_t = maxf(0.0, _pose_t - delta)
	var u: float = 1.0 - _pose_t / maxf(_pose_dur, 0.001)  # 0 -> 1
	var s: float = sin(u * PI)                             # out and back
	match _pose_kind:
		POSE_HOP:
			sprite.position = Vector2(_spr_base_x, _spr_base_y - s * _pose_mag)
			sprite.rotation = 0.0
			sprite.scale = Vector2(
				_spr_base_scale.x * (1.0 - s * 0.10),
				_spr_base_scale.y * (1.0 + s * 0.14))
		POSE_STAGGER:
			# Kicked away from the hit, springing back — decay, not a bounce.
			var back: float = (1.0 - u) * (1.0 - u)
			sprite.position = Vector2(
				_spr_base_x + _pose_dir.x * _pose_mag * back,
				_spr_base_y + _pose_dir.y * _pose_mag * 0.5 * back)
			sprite.rotation = _pose_dir.x * 0.16 * back
			sprite.scale = _spr_base_scale
		_:
			sprite.position = Vector2(
				_spr_base_x + _pose_dir.x * _pose_mag * s,
				_spr_base_y + _pose_dir.y * _pose_mag * 0.5 * s)
			sprite.rotation = _pose_dir.x * 0.12 * s
			sprite.scale = Vector2(
				_spr_base_scale.x * (1.0 + 0.14 * s),
				_spr_base_scale.y * (1.0 - 0.12 * s))

## Called on player respawn: forget the player and return to the home post, so a
## respawn is never immediately re-swarmed by enemies that were mid-chase.
func reset_to_home() -> void:
	_aggroed = false
	_knockback = Vector2.ZERO
	_cancel_windup()
	if _home != Vector2.ZERO:
		global_position = _home

func _physics_process(delta: float) -> void:
	# Knockback (e.g. from the player's Force Push dash) always resolves, even
	# while combat is paused, so the player can always shove enemies away.
	if _knockback.length() > 5.0:
		velocity = _knockback
		move_and_slide()
		_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
		return
	if _combat_paused():
		velocity = Vector2.ZERO
		_cancel_windup()
		return
	# Stunned (e.g. by Rubber Duck): frozen but still shoveable via knockback.
	if _stun_time > 0.0:
		_stun_time -= delta
		velocity = Vector2.ZERO
		_cancel_windup()
		sprite.modulate = Color(0.55, 0.65, 1.0)
		if _stun_time <= 0.0:
			sprite.modulate = Color.WHITE
		return
	if not target or not is_instance_valid(target):
		target = get_tree().get_first_node_in_group("player")
		return
	if _intro_lock > 0.0:
		_intro_lock -= delta
	if is_boss and not _intro_done and global_position.distance_to(target.global_position) < 620.0:
		_play_boss_intro()
	# A committed swing owns the frame: the enemy plants and cannot chase, which
	# is exactly what makes the telegraph dodgeable.
	if _windup > 0.0:
		_tick_windup(delta)
		return
	_update_special(delta)
	var to_player := target.global_position - global_position
	var dist := to_player.length()

	# Aggro gating: wake when the player comes near, sleep (return home) if they
	# leave. Special behaviours still tick, but a dormant enemy won't chase.
	if not _aggroed:
		if dist <= aggro_radius:
			_aggroed = true
			_on_aggro()
	elif dist > aggro_radius * LEASH_MULT:
		_aggroed = false

	var desired := Vector2.ZERO
	if _aggroed:
		if dist > ENGAGE_DISTANCE:
			desired = to_player.normalized() * speed
		else:
			# Hold at engage range and orbit slightly rather than piling on.
			desired = to_player.normalized() * speed * 0.12
	else:
		# Dormant: drift back toward home so enemies don't wander into the spawn.
		var to_home := _home - global_position
		if to_home.length() > 12.0:
			desired = to_home.normalized() * speed * 0.4
	desired += _separation() * speed
	velocity = desired
	move_and_slide()
	if absf(velocity.x) > 1.0:
		sprite.flip_h = velocity.x < 0

## "It has seen you." A classic exclamation tell plus a startle hop, so the
## moment a fight starts is never ambiguous.
func _on_aggro() -> void:
	if _dying or is_boss:
		return
	var host := get_parent()
	if host:
		CombatFx.glyph(host, global_position + Vector2(0, -46), "!", Color("#FF4757"), 22, 0.6, 18.0)
	_set_pose(POSE_HOP, Vector2.UP, 9.0, 0.24)

# ------------------------------------------------------- melee telegraph ----

## Commit to a swing: plant, coil, and paint the wedge that is about to hurt.
## Returns false when there is nothing to swing at, so the caller can put the
## attack clock back on the wall.
func _begin_windup() -> bool:
	if _dying or not target or not is_instance_valid(target):
		return false
	_windup = WINDUP_TIME
	var d: Vector2 = target.global_position - global_position
	_wind_dir = d.normalized() if d.length_squared() > 0.0001 else Vector2.RIGHT
	_pose_t = 0.0  # the coil owns the sprite now
	var host := get_parent()
	if host:
		_wind_marker = CombatFx.strike_arc(host, global_position, _wind_dir,
			Color("#FF4757"), STRIKE_RANGE + 14.0, WINDUP_TIME)
	return true

func _tick_windup(delta: float) -> void:
	velocity = Vector2.ZERO
	_windup -= delta
	if _windup <= 0.0:
		_strike()

## Clear the coil pose and the floor wedge. `resume` restarts the attack clock —
## a cancelled wind-up (stun, knockback, pause) must never silently retire an
## enemy from combat. The strike path restarts the clock itself.
## Early-returns when nothing was winding up, so it can be called every frame
## (and so it never stomps an unrelated damage flash).
func _cancel_windup(resume: bool = true) -> void:
	var was_winding: bool = _windup > 0.0 or _wind_marker != null
	if _wind_marker and is_instance_valid(_wind_marker):
		_wind_marker.queue_free()
	_wind_marker = null
	_windup = 0.0
	if not was_winding:
		return
	if is_instance_valid(sprite):
		sprite.modulate = Color.WHITE
		sprite.position = Vector2(_spr_base_x, _spr_base_y)
		sprite.rotation = 0.0
		sprite.scale = _spr_base_scale
	if resume and is_instance_valid(attack_timer) and attack_timer.is_stopped():
		attack_timer.start(randf_range(0.9, 1.6))

## The swing lands. Slightly more generous than the wind-up range, so stepping
## out of the wedge is a real dodge rather than a coin flip.
func _strike() -> void:
	_cancel_windup(false)
	if _dying:
		return
	var connected := false
	if target and is_instance_valid(target) and global_position.distance_to(target.global_position) <= STRIKE_RANGE:
		connected = true
		if target.has_method("take_damage"):
			target.take_damage(damage, enemy_type)
	_set_pose(POSE_STRIKE, _wind_dir, 13.0, 0.22)
	var host := get_parent()
	if host:
		var impact: Vector2 = global_position + _wind_dir * 26.0
		CombatFx.ripple(host, impact, _wind_dir, Color("#FF4757"), 46.0, 0.2)
		if connected:
			FxLib.burst(host, impact, Color(2.4, 0.8, 0.9), 7, 180.0, FxLib.spark(), Vector2.ZERO, CombatFx.Z_FX)
	if is_instance_valid(attack_timer):
		attack_timer.start(randf_range(1.2, 2.5))

## Per-type signature behaviours + telegraphs. Never traps the player.
func _update_special(delta: float) -> void:
	match enemy_type:
		"scope_creep":
			# Requirements never stop growing. It gets bigger and faster.
			_grow = minf(_grow + delta * 0.09, 1.0)
			scale = _base_scale * (1.0 + _grow * 0.7)
			speed = _base_speed * (1.0 + _grow * 0.9)
		"memory_leak":
			# Slowly bloats as it leaks.
			_grow = minf(_grow + delta * 0.05, 0.6)
			scale = _base_scale * (1.0 + _grow)
		"rate_limiter":
			_tick_rate_limiter(delta)
		"hallucination":
			_special_cd -= delta
			if _special_cd <= 0.0:
				_blink()
				_special_cd = randf_range(2.2, 3.6)
	if is_boss:
		_tick_boss(delta)

# ------------------------------------------------------------ boss rig ----

## Bosses carry their own presentation layer: the entrance card, the bottom
## health bar, phase banners and the death stamp all live in BossHud.
func _build_boss_presence() -> void:
	_boss_hud = BossHud.new()
	_boss_hud.name = "BossHud"
	add_child(_boss_hud)
	_boss_hud.setup(enemy_type, _accent())
	_boss_hud.set_health(hp, max_hp)
	# A boss is a light source. It should be visible before it is legible.
	var col := FxLib.vivid(_accent())
	FxLib.point_light(self, col, 1.15, 3.0, Vector2(0, -10))

## Name card, letterbox, camera push, ambience shift. Plays once, and never
## takes control away — the player can walk, shoot and leave during all of it.
func _play_boss_intro() -> void:
	if _intro_done:
		return
	_intro_done = true
	_intro_lock = 2.2
	if _boss_hud and is_instance_valid(_boss_hud):
		_boss_hud.play_entrance()
	var host := get_parent()
	var col := FxLib.vivid(_accent())
	if host:
		CombatFx.shockwave(host, global_position, col, 240.0, 0.6)
		CombatFx.ring(host, global_position, col, 10.0, 150.0, 0.9, 10.0, 2.0)
		FxLib.burst(host, global_position, Color(col.r * 2.0, col.g * 2.0, col.b * 2.0), 26, 300.0, FxLib.glow_dot(), Vector2(0, -120), CombatFx.Z_FX)
	# It rears up. (A pose, not a tween — `_process` owns the sprite transform.)
	_set_pose(POSE_HOP, Vector2.UP, 20.0, 0.6)
	FxLib.add_trauma(get_tree(), 0.5)
	var fx := get_tree().get_first_node_in_group("camera_fx")
	if fx and fx.has_method("punch_zoom"):
		fx.punch_zoom(0.07)
	AudioManager.play_sfx("upgrade")
	AudioManager.play_music("combat_music")

## Phase thresholds at 75/50/25%. Each one is louder, faster and better
## documented than the last.
func _check_boss_phase() -> void:
	if not is_boss or _dying:
		return
	var frac := float(hp) / float(maxi(1, max_hp))
	var want := 1
	if frac <= 0.25:
		want = 4
	elif frac <= 0.5:
		want = 3
	elif frac <= 0.75:
		want = 2
	if want <= _boss_phase:
		return
	_boss_phase = want
	if _boss_hud and is_instance_valid(_boss_hud):
		_boss_hud.announce_phase(_boss_phase)
	speed = _base_speed * (1.0 + 0.14 * float(_boss_phase - 1))
	_special_cd = minf(_special_cd, 1.2)
	var host := get_parent()
	var col := FxLib.vivid(_accent())
	if host:
		CombatFx.shockwave(host, global_position, col, 200.0, 0.45)
		CombatFx.text_shards(host, global_position, col,
			DEATH_SHARDS.get(enemy_type, ["escalated"]), 4)
	if is_instance_valid(sprite):
		var tw := create_tween()
		tw.tween_property(sprite, "modulate", Color(3.0, 3.0, 3.0), 0.06)
		tw.tween_property(sprite, "modulate", Color.WHITE, 0.5)
	FxLib.add_trauma(get_tree(), 0.4)
	AudioManager.play_sfx("ability")

## Bosses telegraph a big AoE shockwave, then slam. The Enterprise Architect
## also convenes a governance council (summons adds). Knockback is temporary,
## so a boss can never trap the player.
func _tick_boss(delta: float) -> void:
	if _intro_lock > 0.0:
		return
	if _boss_tele > 0.0:
		_boss_tele -= delta
		sprite.modulate = Color(1.5, 0.6, 0.6) if fmod(_boss_tele, 0.2) < 0.1 else Color.WHITE
		if _boss_tele <= 0.0:
			sprite.modulate = Color.WHITE
			_boss_slam()
		return
	_special_cd -= delta
	if _special_cd <= 0.0 and target and global_position.distance_to(target.global_position) < 320.0:
		_boss_tele = 0.7
		_special_cd = randf_range(4.0, 6.5)
		# Paint the kill zone on the floor for the whole wind-up. The slam
		# reaches 260px; so does the marker. No hidden information.
		var host := get_parent()
		if host:
			_boss_marker = CombatFx.marker(host, global_position, Color("#FF4757"), 260.0, 0.7)

func _boss_slam() -> void:
	if _boss_marker and is_instance_valid(_boss_marker):
		_boss_marker.queue_free()
		_boss_marker = null
	if target and is_instance_valid(target):
		var away: Vector2 = target.global_position - global_position
		if away.length() < 260.0:
			if target.has_method("apply_external_knockback"):
				target.apply_external_knockback(away.normalized() * 520.0)
			if target.has_method("take_damage"):
				target.take_damage(int(damage * 0.5), enemy_type)
	_slam_impact()
	if enemy_type == "enterprise_architect":
		_summon("scope_creep")
	AudioManager.play_sfx("ability")

## Give the slam physical weight: a camera kick, an expanding dust ring and a
## hard shockwave at the point of impact. All cosmetic and self-cleaning.
func _slam_impact() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam and cam.has_method("shake"):
		cam.shake(0.35, 7.0)
	var parent := get_parent()
	if not parent:
		return
	CombatFx.shockwave(parent, global_position, Color("#FF4757"), 260.0, 0.4)
	FxLib.add_trauma(get_tree(), 0.35)
	var dust := CPUParticles2D.new()
	dust.emitting = true
	dust.one_shot = true
	dust.amount = 20
	dust.lifetime = 0.5
	dust.explosiveness = 1.0
	dust.spread = 180.0
	dust.initial_velocity_min = 140.0
	dust.initial_velocity_max = 240.0
	dust.scale_amount_min = 3.0
	dust.scale_amount_max = 5.0
	dust.color = Color(0.8, 0.5, 0.55, 0.85)
	dust.z_index = CombatFx.Z_FX - 8
	parent.add_child(dust)
	dust.global_position = global_position
	dust.finished.connect(dust.queue_free)

func _summon(type: String) -> void:
	var scene := preload("res://scenes/combat/enemy.tscn")
	var e = scene.instantiate()
	e.enemy_type = type
	e.max_hp = 16
	get_parent().add_child(e)
	e.global_position = global_position + Vector2(randf_range(-44, 44), randf_range(-44, 44))
	# Adds arrive through a rift, not by appearing out of nothing.
	var host := get_parent()
	if host:
		CombatFx.ring(host, e.global_position, Color("#8B5CF6"), 2.0, 44.0, 0.3, 5.0, 1.0, 24)
		CombatFx.glyph(host, e.global_position + Vector2(0, -50), "added to the invite", Color("#8B5CF6"), 12, 0.9, 22.0)

func _tick_rate_limiter(delta: float) -> void:
	if _telegraph > 0.0:
		# Flash while winding up the 429 pulse.
		_telegraph -= delta
		sprite.modulate = Color(1.0, 0.85, 0.2) if fmod(_telegraph, 0.2) < 0.1 else Color.WHITE
		if _telegraph <= 0.0:
			sprite.modulate = Color.WHITE
			_rate_pulse()
		return
	_special_cd -= delta
	if _special_cd <= 0.0 and target and global_position.distance_to(target.global_position) < 280.0:
		_telegraph = 0.6
		_special_cd = randf_range(3.5, 5.5)
		# The pulse reaches 240px. So does the ring you are being shown.
		var host := get_parent()
		if host:
			CombatFx.marker(host, global_position, Color("#FFB020"), 240.0, 0.6)
			CombatFx.glyph(host, global_position + Vector2(0, -50), "429", Color("#FFB020"), 20, 0.7, 16.0)

## 429: shove the player back (temporary, decaying — never a trap).
func _rate_pulse() -> void:
	if target and is_instance_valid(target) and target.has_method("apply_external_knockback"):
		var away: Vector2 = target.global_position - global_position
		if away.length() < 240.0:
			target.apply_external_knockback(away.normalized() * 430.0)
	var host := get_parent()
	if host:
		CombatFx.shockwave(host, global_position, Color("#FFB020"), 240.0, 0.36)
	FxLib.add_trauma(get_tree(), 0.2)
	AudioManager.play_sfx("ability")

func _blink() -> void:
	var host := get_parent()
	var from: Vector2 = global_position
	var ang := randf() * TAU
	global_position += Vector2(cos(ang), sin(ang)) * 74.0
	sprite.modulate = Color(1, 1, 1, 0.4)
	var tw := create_tween()
	tw.tween_property(sprite, "modulate", Color.WHITE, 0.3)
	# It was never there. It is very confident it was never there.
	if host:
		CombatFx.afterimage(host, sprite, Color(1.3, 0.9, 2.2, 0.55), 0.35, from - global_position, -1)
		CombatFx.ring(host, from, Color("#8B5CF6"), 2.0, 34.0, 0.24, 4.0, 0.8, 20)
		CombatFx.ring(host, global_position, Color("#8B5CF6"), 30.0, 3.0, 0.2, 1.0, 4.0, 20)

## Repel from nearby enemies so they surround the player instead of stacking
## into a single blob (which previously helped wall the player in).
func _separation() -> Vector2:
	var push := Vector2.ZERO
	for other in get_tree().get_nodes_in_group("enemy"):
		if other == self or not is_instance_valid(other):
			continue
		var away: Vector2 = global_position - other.global_position
		var d := away.length()
		if d > 0.01 and d < SEPARATION_RADIUS:
			push += away.normalized() * (1.0 - d / SEPARATION_RADIUS)
	return push

func apply_knockback(impulse: Vector2) -> void:
	_knockback = impulse
	# Being shoved interrupts a committed swing. That is the whole point of the
	# dash, and it must read on screen the frame it happens.
	_cancel_windup()

func _combat_paused() -> bool:
	if GameManager.state != GameManager.GameState.PLAYING:
		return true
	if DialogueManager.is_active:
		return true
	var player := get_tree().get_first_node_in_group("player")
	if player and "can_move" in player and not player.can_move:
		return true
	return false

## Layered hit feedback: flash, stagger, damage number, sparks, screen shake
## scaled to the damage, and (on a crit) a short time-freeze.
func take_damage(amount: int, is_crit: bool = false, from_dir: Vector2 = Vector2.ZERO) -> void:
	if _dying:
		return
	# Sniping a boss from beyond the entrance trigger still counts as engaging it:
	# the card plays and the health bar appears, so the fight is never anonymous.
	if is_boss and not _intro_done:
		_play_boss_intro()
	hp -= amount
	_flash_damage()
	_spawn_damage_number(amount, is_crit)
	_hit_spark(from_dir, is_crit)
	_stagger(from_dir, is_crit)
	_update_hp_bar()
	FxLib.add_trauma(get_tree(), clampf(float(amount) / 90.0, 0.05, 0.3) * (1.6 if is_crit else 1.0))
	if hp > 0:
		_check_boss_phase()
	if hp <= 0:
		# take_damage often runs from a physics area callback; defer teardown so we
		# don't spawn pickups / disable shapes while the physics server is flushing.
		_dying = true
		_die.call_deferred()

## Knocked off its feet for a moment: the sprite kicks away from the hit and
## springs back. Never touches the body, so it can't affect collision.
func _stagger(from_dir: Vector2, is_crit: bool) -> void:
	if not is_instance_valid(sprite) or _windup > 0.0:
		return
	var d := from_dir
	if d.length_squared() < 0.0001:
		d = Vector2(randf_range(-1.0, 1.0), 0.0)
	_set_pose(POSE_STAGGER, d.normalized(), 11.0 if is_crit else 6.0, 0.2)

## Floating damage number — parented to the region so it survives the enemy's
## death, and driven by its own tween. Hits that land in the SAME physics frame
## merge into one number showing the real total, instead of two labels fighting
## for the same 30 pixels.
func _spawn_damage_number(amount: int, is_crit: bool = false) -> void:
	var frame := Engine.get_physics_frames()
	if frame == _num_frame and is_instance_valid(_num_label):
		_num_total += amount
		_num_crit = _num_crit or is_crit
		_num_label.text = str(_num_total)
		if _num_crit:
			_style_crit_number(_num_label)
		return
	var parent := get_parent()
	if not parent:
		return
	_num_frame = frame
	_num_total = amount
	_num_crit = is_crit
	var lbl := Label.new()
	lbl.text = str(amount)
	lbl.add_theme_font_size_override("font_size", 34 if is_crit else 26)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.35))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	lbl.add_theme_constant_override("outline_size", 6)
	lbl.z_index = CombatFx.Z_TEXT
	parent.add_child(lbl)
	lbl.global_position = global_position + Vector2(randf_range(-12, 8), -40)
	_num_label = lbl
	if is_crit:
		_style_crit_number(lbl)
		# The word, not just a bigger number — a crit should be legible mid-chaos.
		CombatFx.glyph(parent, global_position + Vector2(0, -66), "CRIT",
			Color("#F4F9FF"), 16, 0.7, 26.0)
	# Small "pop" then float up and fade — reads clearly even in busy fights.
	lbl.scale = Vector2(0.6, 0.6)
	var tw := lbl.create_tween()
	tw.tween_property(lbl, "scale", Vector2(1.35, 1.35) if is_crit else Vector2(1.15, 1.15), 0.12).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "scale", Vector2(1.0, 1.0), 0.08)
	tw.parallel().tween_property(lbl, "global_position", lbl.global_position + Vector2(0, -44), 0.7).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.7)
	tw.tween_callback(lbl.queue_free)

## Crit numbers go white-hot with a heavier outline, so they bloom.
func _style_crit_number(lbl: Label) -> void:
	if not is_instance_valid(lbl):
		return
	lbl.add_theme_font_size_override("font_size", 34)
	lbl.add_theme_color_override("font_color", Color(1.9, 1.85, 1.6))
	lbl.add_theme_constant_override("outline_size", 8)

func _hit_spark(from_dir: Vector2 = Vector2.ZERO, is_crit: bool = false) -> void:
	var p := CPUParticles2D.new()
	p.emitting = true
	p.one_shot = true
	p.amount = 14 if is_crit else 8
	p.lifetime = 0.35
	p.explosiveness = 1.0
	# Sparks fly back ALONG the shot when we know where it came from, and spray
	# everywhere when we don't.
	if from_dir.length_squared() > 0.0001:
		p.direction = from_dir
		p.spread = 62.0
	else:
		p.spread = 180.0
	p.initial_velocity_min = 60.0
	p.initial_velocity_max = 200.0 if is_crit else 140.0
	var spark := FxLib.spark()
	if spark:
		p.texture = spark
		p.material = FxLib.additive_material()
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.4 if is_crit else 1.2
	else:
		p.scale_amount_min = 2.0
		p.scale_amount_max = 3.5
	p.color = Color(2.4, 2.0, 1.0) if is_crit else Color(2.0, 1.7, 0.8)
	p.z_index = CombatFx.Z_FX
	# Parent to the region (not the enemy) so the burst completes after the enemy
	# dies, and self-free via `finished` to avoid a timer lambda capturing a node
	# that gets freed with the enemy.
	var parent := get_parent()
	if not parent:
		return
	parent.add_child(p)
	p.global_position = global_position
	p.finished.connect(p.queue_free)

func _flash_damage() -> void:
	if _flash_tween:
		_flash_tween.kill()
	sprite.modulate = Color(2, 2, 2)
	_flash_tween = create_tween()
	_flash_tween.tween_property(sprite, "modulate", Color.WHITE, 0.15)

func _attack() -> void:
	if _combat_paused() or _dying or _stun_time > 0.0 or _intro_lock > 0.0:
		attack_timer.start(1.0)
		return
	if not target or not is_instance_valid(target) or global_position.distance_to(target.global_position) > 40:
		attack_timer.start(1.0)
		return
	# Telegraph first, damage second. `_strike()` restarts the clock; if the
	# wind-up can't start, put the clock back ourselves so this enemy never
	# quietly stops fighting.
	if not _begin_windup():
		attack_timer.start(1.0)

func _die() -> void:
	if is_instance_valid(_hp_bar):
		_hp_bar.visible = false
	_cancel_windup(false)
	# A merge conflict resolves into two smaller, incompatible conflicts.
	if enemy_type == "merge_conflict" and generation < 1 and not is_boss:
		_split()
	QuestManager.on_enemy_defeated(enemy_type)
	GameManager.record_stat("enemies_defeated")
	AudioManager.play_sfx("enemy_death")
	_spawn_tokens()
	_death_burst()
	_death_comedy()
	_hit_stop_if_close()
	if is_boss:
		_boss_death_spectacle()
	# Dissolve into glowing embers (dissolve.gdshader, edge in the enemy's accent)
	# — falls back to the old white pop-fade if the shader library is missing.
	# Total death time stays under 0.5s (combat_test waits exactly that long),
	# including the per-type flourish that runs first.
	_death_dissolve()

## The dissolve, plus each type's last word. The whole sequence is budgeted at
## 0.45s no matter which branch runs — enemies must be gone before the 0.5s
## that combat_test waits for.
func _death_dissolve() -> void:
	# Scope Creep grows one last time before it pops; a Memory Leak bloats once
	# more before being (not) freed. Both eat into the same 0.45s budget.
	var grow_time := 0.0
	if enemy_type == "scope_creep":
		grow_time = 0.16
	elif enemy_type == "memory_leak":
		grow_time = 0.12
	var fade_time: float = 0.45 - grow_time
	# The damage flash owns `modulate` for another 0.15s; the dissolve needs it.
	if _flash_tween:
		_flash_tween.kill()
	var base_scale: Vector2 = sprite.scale
	var grown: Vector2 = base_scale * 1.55 if grow_time > 0.0 else base_scale
	var tween := create_tween()
	if grow_time > 0.0:
		tween.tween_property(sprite, "scale", grown, grow_time) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var shader_path := "res://assets/shaders/dissolve.gdshader"
	if ResourceLoader.exists(shader_path):
		var mat := ShaderMaterial.new()
		mat.shader = load(shader_path)
		mat.set_shader_parameter("edge_color", _accent())
		mat.set_shader_parameter("pixel_size", 2.0)
		mat.set_shader_parameter("progress", 0.0)  # explicit start for the tween
		sprite.material = mat
		sprite.modulate = Color(1.35, 1.35, 1.35)
		tween.tween_property(mat, "shader_parameter/progress", 1.0, fade_time)
		tween.parallel().tween_property(sprite, "scale", grown * 1.12, fade_time)
		tween.tween_callback(queue_free)
	else:
		sprite.modulate = Color(2.4, 2.4, 2.4)
		tween.tween_property(sprite, "scale", grown * 1.45, fade_time * 0.5).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(sprite, "modulate", Color(1, 1, 1, 0.0), fade_time)
		tween.tween_callback(queue_free)

## Thematically appropriate absurd deaths. Everything here is parented to the
## region, so it plays out after the corpse is gone.
func _death_comedy() -> void:
	var host := get_parent()
	if host == null:
		return
	var col := _accent()
	CombatFx.text_shards(host, global_position + Vector2(0, -12), col,
		DEATH_SHARDS.get(enemy_type, ["exit 1"]), 5 if is_boss else 4)
	# The obituary: always for bosses, sometimes for the rank and file, so it
	# stays a joke instead of turning into a subtitle track.
	if is_boss or randf() < 0.35:
		var quip: String = str(DEATH_QUIPS.get(enemy_type, ""))
		if not quip.is_empty():
			CombatFx.glyph(host, global_position + Vector2(0, -58), quip,
				Color("#C9D6F2"), 14, 1.4, 30.0)
	match enemy_type:
		"scope_creep":
			CombatFx.glyph(host, global_position + Vector2(0, -84), "just one more thing",
				Color("#8B5CF6"), 15, 0.9, 26.0)
			CombatFx.shockwave(host, global_position, Color("#8B5CF6"), 96.0, 0.4)
		"memory_leak":
			_leak_puddle(host)
		"rate_limiter":
			for i in 3:
				CombatFx.glyph(host, global_position + Vector2(randf_range(-30, 30), -20 - i * 14),
					"429", Color("#FFB020"), 17, 1.0, 34.0)
		"hallucination":
			# It splits into a second, equally confident copy that immediately
			# turns out to have never existed.
			CombatFx.afterimage(host, sprite, Color(1.4, 0.9, 2.4, 0.7), 0.5, Vector2(28, -6), -1)
		"null_reference":
			CombatFx.glyph(host, global_position + Vector2(0, -40), "undefined",
				Color("#7C8BB0"), 20, 1.1, 34.0)
		"cloud_bill":
			CombatFx.text_shards(host, global_position, Color("#6BC7FF"),
				["$", "$$", "+ tax", "+ egress"], 4)

## A memory leak does not stop leaking just because you killed it. The puddle
## spreads for eight seconds and is still "definitely reachable".
func _leak_puddle(host: Node) -> void:
	var puddle := Polygon2D.new()
	puddle.polygon = CombatFx.ring_points(20)
	puddle.color = Color(0.24, 0.61, 1.0, 0.30)
	puddle.z_index = -3
	puddle.scale = Vector2(6.0, 3.6)
	host.add_child(puddle)
	puddle.global_position = global_position + Vector2(0, 6)
	var tw := puddle.create_tween()
	tw.tween_property(puddle, "scale", Vector2(30.0, 17.0), 5.5).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(puddle, "color:a", 0.0, 8.0).set_ease(Tween.EASE_IN)
	tw.tween_callback(puddle.queue_free)

## A boss does not simply dissolve. Staggered detonations, a white-out, the bar
## draining, and the incident formally closed. The corpse still leaves on the
## same 0.45s clock as everything else — this all runs on the region.
func _boss_death_spectacle() -> void:
	if _boss_hud and is_instance_valid(_boss_hud):
		_boss_hud.detach()
		_boss_hud.play_death()
		_boss_hud = null
	var host := get_parent()
	if host == null:
		return
	var col := FxLib.vivid(_accent())
	var pos := global_position
	var tree := get_tree()
	for i in 5:
		var at: Vector2 = pos + Vector2(randf_range(-52, 52), randf_range(-44, 30))
		var radius: float = 120.0 + 26.0 * float(i)
		var t := host.create_tween()
		t.tween_interval(0.09 * float(i))
		t.tween_callback(func() -> void:
			CombatFx.shockwave(host, at, col, radius, 0.4)
			FxLib.add_trauma(tree, 0.22))
	CombatFx.shockwave(host, pos, Color(1, 1, 1), 300.0, 0.7)
	CombatFx.text_shards(host, pos, col, DEATH_SHARDS.get(enemy_type, ["exit 1"]), 6)
	FxLib.burst(host, pos, Color(col.r * 2.2, col.g * 2.2, col.b * 2.2), 40, 460.0, FxLib.spark(), Vector2(0, 200), CombatFx.Z_FX)
	FxLib.add_trauma(get_tree(), 0.8)
	var fx := get_tree().get_first_node_in_group("camera_fx")
	if fx and fx.has_method("punch_zoom"):
		fx.punch_zoom(0.09)
	# The room stops holding its breath. (No-op unless music is enabled.)
	AudioManager.play_music("explore_music")

## ~40ms time-freeze on close-range kills so melee-distance takedowns have
## physical weight. All the safety guards live in FxLib.hit_stop.
func _hit_stop_if_close() -> void:
	if not is_inside_tree():
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null or global_position.distance_to(player.global_position) > 150.0:
		return
	FxLib.hit_stop(get_tree())

## A burst of enemy-tinted debris on death, parented to the region so it outlives
## the enemy.
func _death_burst() -> void:
	var parent := get_parent()
	if not parent:
		return
	var col := _accent()
	var p := CPUParticles2D.new()
	p.emitting = true
	p.one_shot = true
	p.amount = 16
	p.lifetime = 0.45
	p.explosiveness = 1.0
	p.spread = 180.0
	p.initial_velocity_min = 90.0
	p.initial_velocity_max = 220.0
	p.gravity = Vector2(0, 240)
	p.color = Color(col.r * 1.8, col.g * 1.8, col.b * 1.8)  # overbright: embers bloom
	p.z_index = CombatFx.Z_FX - 4
	var spark := FxLib.spark()
	if spark:
		p.texture = spark
		p.material = FxLib.additive_material()
		p.scale_amount_min = 0.7
		p.scale_amount_max = 1.6
	else:
		p.scale_amount_min = 2.5
		p.scale_amount_max = 4.5
	parent.add_child(p)
	p.global_position = global_position
	p.finished.connect(p.queue_free)
	# Second layer: slow overbright glow motes drifting up out of the corpse.
	FxLib.burst(parent, global_position, Color(col.r * 2.0, col.g * 2.0, col.b * 2.0), 8, 90.0, FxLib.glow_dot(), Vector2(0, -140), CombatFx.Z_FX)
	FxLib.flash(parent, global_position, col, 0.4, 2.2, 0.3, CombatFx.Z_FX)
	CombatFx.ring(parent, global_position, col, 4.0, 78.0, 0.36, 7.0, 1.2)

func _split() -> void:
	var scene := preload("res://scenes/combat/enemy.tscn")
	var host := get_parent()
	var spawned: Array[Node2D] = []
	for i in 2:
		var e = scene.instantiate()
		e.enemy_type = "merge_conflict"
		e.max_hp = maxi(6, int(max_hp / 2))
		e.damage = maxi(4, int(damage * 0.7))
		e.token_drop = maxi(1, int(token_drop / 2))
		e.generation = generation + 1
		get_parent().add_child(e)
		e.global_position = global_position + Vector2(randf_range(-26, 26), randf_range(-26, 26))
		e.scale = _base_scale * 0.68
		spawned.append(e)
	# Show the resolution for what it is: two incompatible halves, labelled.
	if host and spawned.size() == 2:
		CombatFx.glyph(host, spawned[0].global_position + Vector2(0, -44), "<<<<<<< HEAD",
			Color("#FF2D95"), 13, 1.0, 24.0)
		CombatFx.glyph(host, spawned[1].global_position + Vector2(0, -44), ">>>>>>> feature/x",
			Color("#FF2D95"), 13, 1.0, 24.0)
		CombatFx.beam(host, spawned[0].global_position, spawned[1].global_position,
			Color("#FF2D95"), 8.0, 0.4)

func _spawn_tokens() -> void:
	var token_scene := preload("res://scenes/world/token_pickup.tscn")
	var count := 1 if not is_boss else 5
	for i in count:
		var t = token_scene.instantiate()
		t.amount = token_drop / count
		t.global_position = global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
		get_parent().add_child(t)

func _on_hitbox_area_entered(area: Area2D) -> void:
	if area.is_in_group("player_projectile"):
		var dmg: int = area.get("damage") if area.get("damage") else 10
		# Mirror the bolt's crit flag and heading so this path produces the same
		# feedback as the projectile's own (both fire in one physics flush; the
		# damage numbers merge into a single total).
		var is_crit: bool = area.get("crit") == true
		var raw_dir = area.get("direction")
		var dir: Vector2 = raw_dir if raw_dir is Vector2 else Vector2.ZERO
		take_damage(dmg, is_crit, dir)
		# Piercing shots (Stack Trace) survive contact — the projectile's own
		# handler tracks per-enemy hits; only consume non-piercing bolts.
		if not (area.get("pierce") == true):
			area.queue_free()
