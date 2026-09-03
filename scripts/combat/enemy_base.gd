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
const WINDUP_TIME := 0.42
const STRIKE_RANGE := 56.0
## The swing only connects inside the wedge that was painted on the floor. This
## is the difference between "I got hit" and "I got hit because I stood there":
## sidestepping a telegraph is now a real dodge, not a coin flip on distance.
## THE NUMBER IS NOT FREE: CombatFx.strike_arc paints a wedge 1.5 rad wide, so
## the hitbox test has to be cos(1.5 / 2) = 0.7317. At the old 0.42 the hitbox
## was 2.27 rad — half a radian WIDER than the picture — so a player who read
## the telegraph and stepped out of the lit wedge still got hit, which is the
## exact defect the wedge was drawn to remove. Keep these two in lockstep.
const STRIKE_ARC_DOT := 0.7317
## An enemy may only START a wind-up from inside this range.
const STRIKE_START_RANGE := 48.0

# ------------------------------------------------------------ combat roles ----
## "Walk up and touch the player" is now only one of six things an enemy can be
## doing. The role drives spacing, approach arc and which specials the type may
## use; the fiction of each type picks the role.
const ROLE_BRAWLER := 0     # closes, plants, swings
const ROLE_SKIRMISHER := 1  # darts in, hits, hops back out
const ROLE_ARTILLERY := 2   # holds range, lobs telegraphed shots at your feet
const ROLE_GUARDIAN := 3    # carries a front plate; flank it or break it
const ROLE_SUMMONER := 4    # brawls, and calls in exactly one friend too many
const ROLE_CHARGER := 5     # telegraphed committed dash, punishable on a miss

const ROLES := {
	"bug": ROLE_SKIRMISHER,
	"null_reference": ROLE_SKIRMISHER,
	"merge_conflict": ROLE_CHARGER,
	"scope_creep": ROLE_BRAWLER,
	"memory_leak": ROLE_ARTILLERY,
	"rate_limiter": ROLE_ARTILLERY,
	"hallucination": ROLE_ARTILLERY,
	"dependency_demon": ROLE_SUMMONER,
	"legacy_system": ROLE_GUARDIAN,
	"legacy_monolith": ROLE_GUARDIAN,
	"enterprise_architect": ROLE_SUMMONER,
	"cloud_bill": ROLE_ARTILLERY,
	"infinite_context": ROLE_ARTILLERY,
}

## Preferred fighting distance per role. Every melee role sits inside
## STRIKE_START_RANGE — an enemy that holds a distance it can never attack from
## is not a design, it's a bug.
static func _standoff_for(role: int) -> float:
	match role:
		ROLE_SKIRMISHER:
			return 38.0
		ROLE_ARTILLERY:
			return 200.0
		ROLE_GUARDIAN:
			return 36.0
		ROLE_SUMMONER:
			return 40.0
		ROLE_CHARGER:
			return 44.0
	return ENGAGE_DISTANCE

## At most this many NON-BOSS enemies anywhere may be committed to an attack at
## the same time. A pack therefore takes turns instead of landing four hits in
## one frame — the single biggest reason the old fights read as unfair rather
## than hard. Bosses ignore it; a boss owns its room.
const MAX_COMMITTED := 2

## Committed dash: telegraph (a lane you can step out of) -> commit -> recover.
## The recovery is the point. Every big attack in this file opens a window.
const CHARGE_TELE := 0.62
const CHARGE_SPEED := 560.0
const CHARGE_TIME := 0.36
const CHARGE_RECOVER := 1.05

## Directional guard plate. GUARD_SLEW is deliberately slower than a player can
## circle at melee range, so flanking is always available as an answer.
const GUARD_ARC := 1.9
const GUARD_SLEW := 1.7
const GUARD_MITIGATION := 0.28

## Boss move ids. Phases ADD patterns; they do not merely speed the old one up.
const BOSS_SLAM := 0
const BOSS_BARRAGE := 1
const BOSS_CHARGE := 2
const BOSS_SIGNATURE := 3

## Elites never appear in the two teaching regions. The first rooms teach; they
## do not test. (This also keeps every regression suite off the elite path,
## since they all run in localhost / dependency_district.)
const ELITE_FREE_REGIONS := ["localhost", "dependency_district"]
const ELITE_CHANCE := 0.16

## VISUAL_BIBLE_V2 LAW 2: enemies do not each get their own colour. Every tell in
## this file — the alert ring, the wind-up tint, the charge lane, the boss
## telegraph, the elite mark — is this ONE red, so "that is about to hurt" reads
## identically in every room instead of being a different hue per archetype.
const HOSTILE := Color("#FF4757")
## The tell tint, as a MULTIPLY and never above 1.0. The sprite goes red; it does
## not light up. LAW 3 allows exactly five bright things and an enemy body is not
## one of them (its eyes/core, drawn into the sprite, are).
const TELL_TINT := Color(1.0, 0.42, 0.47)
## One art pixel, in the enemy's own units: the sprite draws its 32px art at 2.0,
## so a two-unit step is exactly one texel. Every idle/scuttle offset below is a
## multiple of this, which is the whole of LAW 1 in one number.
const PX := 2.0

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

# --------------------------------------------------------- behaviour state ----
var _role := ROLE_BRAWLER
var _standoff := ENGAGE_DISTANCE
## Every enemy approaches on its OWN arc and strafes its OWN way, so a pack
## fans out around the player instead of converging into one queue.
var _flank := 0.0
var _orbit := 1.0
## Staggered aggro: the pack notices you raggedly, over about three quarters of
## a second, so a fight opens as a trickle rather than a wall.
var _wake_delay := 0.0
var _wake_t := 0.0
var _elite := false
var _grow_announced := false
## Committed dash state: 0 idle, 1 telegraph, 2 dashing, 3 recovering.
var _charge_state := 0
var _charge_t := 0.0
var _charge_dir := Vector2.RIGHT
var _charge_hit := false
var _charge_cd := 0.0
## Vulnerability window. Anything that over-commits (a whiffed dash, a landed
## special, a broken plate, an interrupted telegraph) is EXPOSED for a moment
## and takes extra damage. This is where the player is meant to punish.
var _vuln_t := 0.0
var _vuln_mult := 1.0
## Directional guard plate (guardians).
var _guard: Node2D
var _guard_dir := Vector2.RIGHT
var _guard_hits := 0
var _guard_max := 3
var _guard_down := 0.0
var _guard_frame := -1
## Ranged cadence, and how many friends this one may still call in.
var _lob_cd := 0.0
var _summons_left := 0
## Shots currently in the air. Ticked BY HAND (not by tweens) so a caster that
## dies mid-flight simply cancels its own incoming shot — no callback can ever
## fire from a freed enemy, which is the classic way this kind of thing crashes.
var _shots: Array = []
## The only thing an enemy wears at rest besides its own sprite: a floor ring
## that appears while it is hunting you (see _build_presence).
var _alert_ring: Line2D
## Boss move set.
var _boss_move := BOSS_SLAM
var _boss_recover := 0.0

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

## What it says a beat before a BIG move lands. The ground marker carries the
## information (where it hurts, and when); the line is the joke riding alongside
## it (COMEDY_BIBLE). Deliberately short — a telegraph you have to read is not a
## telegraph. Only the big commitments speak; ordinary swings stay quiet.
const TELLS := {
	"bug": "cannot reproduce",
	"null_reference": "undefined",
	"merge_conflict": "both modified",
	"scope_creep": "one tiny thing",
	"memory_leak": "still reachable",
	"rate_limiter": "retry-after: ?",
	"hallucination": "as we all know",
	"dependency_demon": "peer dep missing",
	"legacy_system": "do not touch",
	"legacy_monolith": "load-bearing",
	"enterprise_architect": "circling back",
	"cloud_bill": "line item",
	"infinite_context": "as previously stated",
}

## The elite tag. Same enemy; it has simply been in the codebase longer than
## anyone still working here.
const ELITE_TAGS := ["load-bearing", "since 2009", "do not remove", "unowned",
	"marked @deprecated", "still in prod"]

func _accent() -> Color:
	return DEATH_ACCENTS.get(enemy_type, HOSTILE)

func _ready() -> void:
	add_to_group("enemy")
	hp = max_hp
	if is_boss:
		max_hp *= 4
		hp = max_hp
		damage *= 2
		token_drop *= 5
		scale = Vector2(2, 2)
	_roll_elite()
	_base_speed = speed
	_base_scale = scale
	_special_cd = randf_range(2.5, 4.5)
	_home = global_position
	_spr_base_y = sprite.position.y
	_spr_base_x = sprite.position.x
	_spr_base_scale = sprite.scale
	_anim_t = randf() * TAU  # desync the herd so they don't bob in lockstep
	# Behaviour identity. Everything downstream (spacing, specials, telegraphs)
	# reads off these four lines.
	_role = int(ROLES.get(enemy_type, ROLE_BRAWLER))
	_standoff = _standoff_for(_role)
	_flank = randf_range(-0.85, 0.85)
	_orbit = 1.0 if randf() < 0.5 else -1.0
	_lob_cd = randf_range(1.4, 3.0)
	_charge_cd = randf_range(1.6, 3.4)
	# Ragged aggro + a slightly different sight radius each, so a room does not
	# wake up as one organism. Capped at 1.10x: region_builder spawns enemies
	# 420px from the region spawn, and 340 * 1.10 must stay under that or a
	# respawning player would be re-engaged the instant they land.
	_wake_delay = randf_range(0.05, 0.75)
	_wake_t = _wake_delay
	aggro_radius *= randf_range(0.86, 1.10)
	# Bosses own their arena — they always engage once you're in the room.
	if is_boss:
		aggro_radius = 900.0
		_wake_delay = 0.0
		_wake_t = 0.0
		_summons_left = 6
		_guard_max = 6
	elif _role == ROLE_SUMMONER:
		# Exactly one friend, and a small one. The joke is the package count,
		# not the difficulty.
		_summons_left = 1
	var tex_path := "res://assets/textures/generated/enemy_%s.png" % enemy_type
	# Bosses prefer their own richer variant when one was baked for this type.
	if is_boss:
		var boss_tex := "res://assets/textures/generated/enemy_%s_boss.png" % enemy_type
		if ResourceLoader.exists(boss_tex):
			tex_path = boss_tex
	if ResourceLoader.exists(tex_path):
		sprite.texture = load(tex_path)
		# LAW 1: one pixel grid. Enemy art is authored at 32px and drawn at 2.0.
		# A boss doubles its NODE scale (tests/boss_test asserts that), so the
		# day the art agent ships a boss at 64px this halves the sprite scale to
		# keep the composed scale at exactly 2.0 — bigger silhouette, same pixel.
		var tex_w: int = sprite.texture.get_width()
		if tex_w >= 64:
			sprite.scale = Vector2(2.0, 2.0) * (32.0 / float(tex_w))
		else:
			sprite.scale = Vector2(2.0, 2.0)
		_spr_base_scale = sprite.scale
	attack_timer.timeout.connect(_attack)
	attack_timer.start(randf_range(1.0, 2.0))
	_build_hp_bar()
	_build_presence()
	if _role == ROLE_GUARDIAN:
		_build_guard()
	if is_boss:
		_build_boss_presence()

## Elites: an occasional buffed variant, visibly marked and worth more. A longer
## fight, never a bigger number — an elite must not spike the damage a player is
## budgeting for. Skipped entirely in the teaching regions.
func _roll_elite() -> void:
	if is_boss or GameManager.current_region in ELITE_FREE_REGIONS:
		return
	if randf() >= ELITE_CHANCE:
		return
	_elite = true
	max_hp = int(round(float(max_hp) * 1.8))
	hp = max_hp
	speed *= 1.12
	token_drop = int(round(float(token_drop) * 2.5))
	_guard_max += 1

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
	_hp_fill.color = Color("#D8DEEA")
	_hp_bar.add_child(_hp_fill)

func _update_hp_bar() -> void:
	if not is_instance_valid(_hp_bar):
		return
	var frac := clampf(float(hp) / float(maxi(1, max_hp)), 0.0, 1.0)
	# Bosses get the full-width bar at the bottom of the screen instead.
	_hp_bar.visible = hp < max_hp and hp > 0 and not is_boss
	_hp_fill.size.x = HP_BAR_W * frac
	# LAW 2: TEXT draining to HOSTILE. The old lime-to-salmon ramp put two more
	# hues on screen for every enemy that had ever been hit.
	_hp_fill.color = Color("#D8DEEA").lerp(HOSTILE, 1.0 - frac)
	if _boss_hud and is_instance_valid(_boss_hud):
		_boss_hud.set_health(hp, max_hp)

# ------------------------------------------------------------- presence ----

## LAW 3 and LAW 7: an enemy at rest is its pixel sprite, and nothing else.
##
## Round 6 wrapped every body in four layers of light — an additive overbright
## copy of its own silhouette at 1.18x, a dark backing plate at 1.30x, a
## PointLight2D, and (for elites) a spinning bracket. That rig is what the QA
## frames caught: the Token Vault boss rendered as a smooth cyan gradient blob
## with a pink core and bloom rays, none of which is the sprite. All four are
## gone, and with them two off-grid scales (1.18, 1.30) and a looping tween that
## ran while the enemy was standing still.
##
## What is left is the two things the laws actually ask for:
##   * a contact shadow, so the body stands ON the floor rather than over it;
##   * a floor ring, drawn ONLY while this one is COMMITTED — a flat HOSTILE
##     outline at 45% alpha in the same red as every wind-up wedge and charge
##     lane. A telegraph is a shape, not a light source.
##
## ROUND 13, critique #1: the ring used to come on at `_on_aggro` and stay on for
## as long as the enemy had a leash on you, i.e. it was an IDLE RADIUS painted on
## the floor under every awake body in the room. Six enemies noticing you at once
## is six red ellipses that mean nothing in particular; the same ring drawn only
## while `is_committed()` is true (wind-up, dash, boss telegraph) means exactly
## one thing — "this one is mid-swing, move" — which is what a tell is for.
## `_sync_alert_ring` in `_physics_process` is the single owner of its visibility.
func _build_presence() -> void:
	var shadow := Polygon2D.new()
	shadow.polygon = CombatFx.ring_points(16)
	shadow.scale = Vector2(15.0, 7.0)
	shadow.position = Vector2(0, 13)
	shadow.color = Color(0.02, 0.02, 0.05, 0.42)
	shadow.z_index = -2
	add_child(shadow)
	_alert_ring = Line2D.new()
	# Baked as a flattened ellipse instead of a scaled circle: a non-uniform
	# scale on a Line2D stretches the STROKE with it, so the old ring drew twice
	# as thick at the sides as at the top.
	var ring_pts := PackedVector2Array()
	for i in 23:
		var a: float = TAU * float(i) / 22.0
		ring_pts.append(Vector2(cos(a) * 23.0, sin(a) * 11.0))
	_alert_ring.points = ring_pts
	# No additive blend and nothing over 1.0: at bloom threshold 1.0 (LAW 5) the
	# old (2.4, 0.62, 0.74) stroke was a light source drawn on the floor.
	_alert_ring.default_color = Color(HOSTILE.r, HOSTILE.g, HOSTILE.b, 0.45)
	_alert_ring.width = PX  # exactly one art pixel of stroke
	_alert_ring.position = Vector2(0, 13)
	_alert_ring.z_index = -2
	_alert_ring.visible = false
	add_child(_alert_ring)
	if _elite:
		_build_elite_marker()

## An elite wears its promotion: one small STILL chevron over its head, in the
## same red as every other tell. It used to be an overbright additive diamond on
## a looping 3.4s spin — a rotation on a marker (LAW 1) that pulsed light at rest
## (LAW 9) on an enemy that was doing nothing.
func _build_elite_marker() -> void:
	var root := Node2D.new()
	root.position = Vector2(0, -30)
	# Absolute: the marker must not change depth as the enemy walks up the room.
	root.z_as_relative = false
	root.z_index = CombatFx.Z_TEXT - 12
	add_child(root)
	var mark := Line2D.new()
	mark.points = PackedVector2Array([Vector2(-6, 3), Vector2(0, -4), Vector2(6, 3)])
	mark.width = PX
	mark.default_color = Color(HOSTILE.r, HOSTILE.g, HOSTILE.b, 0.6)
	root.add_child(mark)

## The guard plate: an arc bolted to the front of a guardian. It slews toward the
## player, but slowly — walking around it is always an option, and so is breaking
## it. Purely a drawing; the mitigation lives in take_damage().
##
## A guardian standing in a doorway wears this permanently, which makes it REST
## dressing, not combat dressing: it used to be an additive overbright edge over
## an additive fill, i.e. a light source on an idle enemy (LAW 3). Now it is one
## flat 2px HOSTILE stroke at 55% and a fill so faint it only separates the arc
## from the floor.
func _build_guard() -> void:
	_guard = Node2D.new()
	_guard.z_index = 1
	add_child(_guard)
	var fill := Polygon2D.new()
	fill.polygon = CombatFx.wedge_points(0.0, GUARD_ARC, 14)
	fill.scale = Vector2(30.0, 30.0)
	fill.color = Color(HOSTILE.r, HOSTILE.g, HOSTILE.b, 0.10)
	_guard.add_child(fill)
	var edge := Line2D.new()
	var pts := PackedVector2Array()
	for i in 13:
		var a: float = -GUARD_ARC * 0.5 + GUARD_ARC * float(i) / 12.0
		pts.append(Vector2(cos(a), sin(a)) * 30.0)
	edge.points = pts
	edge.width = PX * 2.0
	edge.default_color = Color(HOSTILE.r, HOSTILE.g, HOSTILE.b, 0.55)
	_guard.add_child(edge)
	_guard_hits = 0
	_guard_down = 0.0

func _guard_up() -> bool:
	return _guard != null and is_instance_valid(_guard) and _guard_down <= 0.0

## Turn the plate toward the player at GUARD_SLEW. A player circling at melee
## range moves faster than this, which is exactly the point.
func _tick_guard(delta: float) -> void:
	if _guard_down > 0.0:
		_guard_down -= delta
		if _guard_down <= 0.0 and is_boss and not _dying:
			_build_guard()
		return
	if not _guard_up():
		return
	if target and is_instance_valid(target):
		var want: Vector2 = target.global_position - global_position
		if want.length_squared() > 1.0:
			var w := want.normalized()
			var step: float = clampf(_guard_dir.angle_to(w), -GUARD_SLEW * delta, GUARD_SLEW * delta)
			_guard_dir = _guard_dir.rotated(step)
	if is_instance_valid(_guard):
		_guard.rotation = _guard_dir.angle()

## Enough shots into the plate and it comes off. The window that follows is the
## reward for choosing to break it instead of walking around it.
func _break_guard() -> void:
	var host := get_parent()
	var col := FxLib.vivid(_accent())
	if _guard and is_instance_valid(_guard):
		CombatFx.shield_break(_guard, host, global_position + _guard_dir * 26.0, col, 34.0)
	_guard = null
	_guard_hits = 0
	_guard_down = 6.0
	_open_vuln(2.2, 1.6)
	if host:
		CombatFx.glyph(host, global_position + Vector2(0, -54), "plate deprecated",
			Color("#FFD34D"), 15, 1.0, 26.0)
	FxLib.add_trauma(get_tree(), 0.25)
	AudioManager.play_sfx("ability")

## Open (or extend) the punish window. Never shortens an existing one.
func _open_vuln(seconds: float, mult: float) -> void:
	_vuln_t = maxf(_vuln_t, seconds)
	_vuln_mult = maxf(_vuln_mult, mult)

func _tick_vuln(delta: float) -> void:
	if _vuln_t <= 0.0:
		return
	_vuln_t -= delta
	if _vuln_t <= 0.0:
		_vuln_t = 0.0
		_vuln_mult = 1.0

## Orbiting question marks, guarded so only one set exists at a time.
func _dazed_mark(duration: float) -> void:
	if _dying or duration <= 0.0:
		return
	if _dazed != null and is_instance_valid(_dazed):
		return
	_dazed = CombatFx.dazed(self, 40.0, Color("#FFD34D"), duration, "?")

func stun(duration: float) -> void:
	_stun_time = maxf(_stun_time, duration)
	_cancel_windup()
	_cancel_charge()
	# Visibly dazed: orbiting question marks, so a stunned enemy is obviously
	# stunned and not just standing there being blue.
	_dazed_mark(duration)

## Procedural liveliness: idle enemies breathe one pixel, moving enemies hop two,
## winding-up enemies plant and coil. Runs every frame (independent of the
## physics early-returns) so even dormant or telegraphing enemies never look like
## frozen stickers.
##
## Everything here moves in whole art pixels and NOTHING here rotates. The old
## version rode a rotation on every state (a 0.14 rad waddle, a 0.18 rad dizzy
## wobble, a 0.16 rad coil), and rotating a pixel sprite resamples every pixel in
## it — the single most reliable way to make pixel art look like it was rendered
## by something that had never seen pixel art (LAW 1).
func _process(delta: float) -> void:
	if not is_instance_valid(sprite) or _dying:
		return  # while dying, the death-pop tween owns the sprite's scale/modulate
	_anim_t += delta
	if _charge_state != 0:
		_pose_charge()
		return
	if is_boss and _boss_recover > 0.0:
		# The punish window has to LOOK like one: slumped and wide open. The
		# wobble is gone — rotating a pixel sprite resamples every pixel in it.
		sprite.position = Vector2(_spr_base_x, _spr_base_y + PX * 2.0)
		sprite.rotation = 0.0
		sprite.scale = Vector2(_spr_base_scale.x * 1.10, _spr_base_scale.y * 0.88)
		return
	if _windup > 0.0:
		# Coil: pull back away from the strike and squash wide. The squash is a
		# transient telegraph, which LAW 1 allows; the 4-degree lean it used to
		# ride on was not, and the tint is now the one red tell rather than an
		# overbright wash of the enemy's own accent (LAW 2 / LAW 3).
		var t: float = 1.0 - clampf(_windup / WINDUP_TIME, 0.0, 1.0)
		sprite.position = Vector2(
			_spr_base_x - roundf(_wind_dir.x * 3.0 * t) * PX, _spr_base_y - roundf(t) * PX)
		sprite.rotation = 0.0
		sprite.scale = Vector2(
			_spr_base_scale.x * (1.0 + 0.18 * t),
			_spr_base_scale.y * (1.0 - 0.14 * t))
		sprite.modulate = Color.WHITE.lerp(TELL_TINT, t)
		return
	if _pose_t > 0.0:
		_tick_pose(delta)
		return
	if _stun_time > 0.0:
		# Stunned: it just stops. The orbiting question marks say "dazed"; a
		# 22 rad/s sprite wobble said "the renderer is broken".
		sprite.position = Vector2(_spr_base_x, _spr_base_y)
		sprite.rotation = 0.0
		sprite.scale = _spr_base_scale
		return
	if velocity.length() > 12.0:
		# Scuttle: a two-pixel hop, landed on whole art pixels. No rotation and
		# no squash — a sprite whose scale changes every frame is on a different
		# pixel grid from the floor it is walking on, every frame (LAW 1).
		sprite.position = Vector2(
			_spr_base_x, _spr_base_y - roundf(absf(sin(_anim_t * 11.0)) * 2.0) * PX)
		sprite.rotation = 0.0
		sprite.scale = _spr_base_scale
	else:
		# Idle: ONE pixel of breath (LAW 9), quantised to the grid — 0, then 1
		# art pixel, then 0. Nothing else moves on a resting enemy.
		sprite.position = Vector2(
			_spr_base_x, _spr_base_y + roundf(0.5 + 0.5 * sin(_anim_t * 2.8)) * PX)
		sprite.rotation = 0.0
		sprite.scale = _spr_base_scale

## The three frames of a committed dash, drawn instead of animated: coil back
## along the lane, stretch flat through the run, slump open on the recovery.
## The slump is deliberately unmistakable — it is the "hit me now" pose.
func _pose_charge() -> void:
	match _charge_state:
		1:
			var t: float = 1.0 - clampf(_charge_t / CHARGE_TELE, 0.0, 1.0)
			sprite.position = Vector2(
				_spr_base_x - roundf(_charge_dir.x * 4.0 * t) * PX,
				_spr_base_y - roundf(1.5 * t) * PX)
			sprite.rotation = 0.0
			sprite.scale = Vector2(
				_spr_base_scale.x * (1.0 + 0.22 * t),
				_spr_base_scale.y * (1.0 - 0.16 * t))
			sprite.modulate = Color.WHITE.lerp(TELL_TINT, t)
		2:
			sprite.position = Vector2(
				_spr_base_x + roundf(_charge_dir.x * 2.0) * PX, _spr_base_y - PX * 2.0)
			sprite.rotation = 0.0
			sprite.scale = Vector2(_spr_base_scale.x * 1.24, _spr_base_scale.y * 0.84)
		_:
			sprite.position = Vector2(_spr_base_x, _spr_base_y + PX)
			sprite.rotation = 0.0
			sprite.scale = Vector2(_spr_base_scale.x * 1.08, _spr_base_scale.y * 0.90)

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
	# Every pose lands on whole art pixels and none of them rotates: the poses are
	# short, but a pixel sprite that resamples itself is off the grid for as long
	# as it lasts, and a hit reaction is exactly when the player is looking.
	match _pose_kind:
		POSE_HOP:
			sprite.position = Vector2(_spr_base_x, _spr_base_y - roundf(s * _pose_mag / PX) * PX)
			sprite.rotation = 0.0
			sprite.scale = Vector2(
				_spr_base_scale.x * (1.0 - s * 0.10),
				_spr_base_scale.y * (1.0 + s * 0.14))
		POSE_STAGGER:
			# Kicked away from the hit, springing back — decay, not a bounce.
			var back: float = (1.0 - u) * (1.0 - u)
			sprite.position = Vector2(
				_spr_base_x + roundf(_pose_dir.x * _pose_mag * back / PX) * PX,
				_spr_base_y + roundf(_pose_dir.y * _pose_mag * 0.5 * back / PX) * PX)
			sprite.rotation = 0.0
			sprite.scale = _spr_base_scale
		_:
			sprite.position = Vector2(
				_spr_base_x + roundf(_pose_dir.x * _pose_mag * s / PX) * PX,
				_spr_base_y + roundf(_pose_dir.y * _pose_mag * 0.5 * s / PX) * PX)
			sprite.rotation = 0.0
			sprite.scale = Vector2(
				_spr_base_scale.x * (1.0 + 0.14 * s),
				_spr_base_scale.y * (1.0 - 0.12 * s))

## Called on player respawn: forget the player and return to the home post, so a
## respawn is never immediately re-swarmed by enemies that were mid-chase.
func reset_to_home() -> void:
	_aggroed = false
	_knockback = Vector2.ZERO
	_cancel_windup()
	# Everything mid-commitment is torn down too, or a respawning player would
	# land in front of a dash that started before they died.
	_cancel_charge()
	_cancel_shots()
	_boss_tele = 0.0
	_boss_recover = 0.0
	_vuln_t = 0.0
	_vuln_mult = 1.0
	_wake_t = _wake_delay
	if is_instance_valid(_alert_ring):
		_alert_ring.visible = false
	if _home != Vector2.ZERO:
		global_position = _home

func _physics_process(delta: float) -> void:
	# Depth-sort against the world the same way player.gd does. Without this an
	# enemy sits at z 0 while every builder prop sets z_index = _depth(y), so
	# cover and landmarks draw in front of enemies at any Y.
	z_index = int(global_position.y)
	_sync_alert_ring()
	# Lobbed shots live on this enemy's own clock (deliberately not on a tween),
	# so they keep travelling through knockback and stun, and stop dead when the
	# room does.
	if not _combat_paused():
		_tick_shots(delta)
		_tick_vuln(delta)
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
		_cancel_charge()
		return
	# Stunned (e.g. by Rubber Duck): frozen but still shoveable via knockback.
	if _stun_time > 0.0:
		_stun_time -= delta
		velocity = Vector2.ZERO
		_cancel_windup()
		sprite.modulate = Color(0.62, 0.66, 0.74)  # dazed: desaturated, not a hue
		if _stun_time <= 0.0:
			sprite.modulate = Color.WHITE
		return
	if not target or not is_instance_valid(target):
		target = get_tree().get_first_node_in_group("player")
		return
	if _intro_lock > 0.0:
		_intro_lock -= delta
	if is_boss and not _intro_done and global_position.distance_to(target.global_position) < BOSS_INTRO_RANGE \
			and _on_camera():
		_play_boss_intro()
	# A committed swing owns the frame: the enemy plants and cannot chase, which
	# is exactly what makes the telegraph dodgeable.
	if _windup > 0.0:
		_tick_windup(delta)
		return
	_update_special(delta)
	# A committed dash owns the body outright — it steers nothing, it just goes.
	if _charge_state != 0:
		_tick_charge(delta)
		return
	# A telegraphing or recovering boss PLANTS. This is not decoration: the slam
	# marker is painted at the position the wind-up started from, so a boss that
	# kept walking during its own telegraph was drawing the player a kill zone in
	# the wrong place.
	if is_boss and (_boss_tele > 0.0 or _boss_recover > 0.0):
		velocity = Vector2.ZERO
		return
	var to_player := target.global_position - global_position
	var dist := to_player.length()

	# Aggro gating: wake when the player comes near, sleep (return home) if they
	# leave. Special behaviours still tick, but a dormant enemy won't chase.
	# The wake timer staggers the pack so a room notices you raggedly.
	if not _aggroed:
		if dist <= aggro_radius:
			_wake_t -= delta
			if _wake_t <= 0.0:
				_aggroed = true
				_on_aggro()
		else:
			_wake_t = _wake_delay
	elif dist > aggro_radius * LEASH_MULT:
		_aggroed = false
		_wake_t = _wake_delay
		_music_calm_check()

	var desired := Vector2.ZERO
	if _aggroed:
		desired = _role_steering(to_player, dist)
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

## Where this enemy wants to be, by role. Nobody walks the straight line to the
## player any more: brawlers fan out along their own approach arc, skirmishers
## pulse in and out, artillery holds its range, and anyone sitting in the pocket
## strafes rather than standing. A pack breathes instead of queueing.
func _role_steering(to_player: Vector2, dist: float) -> Vector2:
	var dir: Vector2 = to_player.normalized() if dist > 0.001 else Vector2.RIGHT
	var want := _standoff
	if _role == ROLE_SKIRMISHER:
		# Dart cycle: press, then think better of it. Reads as nerves, plays as
		# spacing the player can work with.
		want = _standoff + (58.0 if sin(_anim_t * 1.3) > 0.35 else 0.0)
	elif _role == ROLE_CHARGER and not is_boss and _charge_state == 0 and _charge_cd <= 0.0:
		# A charger with a run off cooldown backs up to a distance it can
		# actually run FROM. Without this it parks at its 44px melee standoff,
		# permanently inside `_tick_role`'s 76px charge floor, and the lane
		# telegraph — the entire point of the archetype — is never drawn outside
		# a boss fight. Bosses are excluded: their move choice comes from
		# `_boss_moves()`, not `_charge_cd`, so this would just walk them away.
		want = 150.0
	if dist > want * 1.12:
		# Approach on this one's own arc — the offset straightens out as it
		# closes, so the pack converges late instead of walking in a fan.
		return dir.rotated(_flank * clampf(dist / 260.0, 0.0, 1.0)) * speed
	if dist < want * 0.78:
		return -dir * speed * 0.55
	return dir.orthogonal() * _orbit * speed * 0.42

## "It has seen you." A classic exclamation tell plus a startle hop, so the
## moment a fight starts is never ambiguous.
func _on_aggro() -> void:
	if _dying or is_boss:
		return
	AudioManager.play_music("combat_music")
	var host := get_parent()
	if host:
		CombatFx.glyph(host, global_position + Vector2(0, -46), "!", HOSTILE, 22, 0.6, 18.0)
		if _elite:
			# Say why this one is different BEFORE the player wastes a clip on it.
			CombatFx.glyph(host, global_position + Vector2(0, -68),
				"ELITE · %s" % ComedyLines.pick("enemy_elite", ELITE_TAGS),
				Color("#FFD34D"), 14, 1.1, 24.0)
	_set_pose(POSE_HOP, Vector2.UP, 9.0, 0.24)

## Back to the explore track, but only when NOTHING in the room is still
## chasing — one enemy dropping its leash must not calm the music mid-brawl.
func _music_calm_check() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if e != self and is_instance_valid(e) and "_aggroed" in e and e._aggroed:
			return
	AudioManager.play_music("explore_music")

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
			HOSTILE, _reach() + 14.0, WINDUP_TIME)
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

## The swing lands — but ONLY inside the wedge that was painted on the floor.
## Distance alone used to be enough, which meant a telegraph you read correctly
## and sidestepped still hit you. Now stepping out of the arc is a real dodge,
## and a swing that finds nothing leaves the swinger briefly open.
func _strike() -> void:
	_cancel_windup(false)
	if _dying:
		return
	var connected := false
	if target and is_instance_valid(target):
		var to_t: Vector2 = target.global_position - global_position
		var d := to_t.length()
		# Point blank always connects — the arc test is about sidestepping, and
		# standing directly on top of something is not a sidestep.
		if d <= _reach() and (d < 14.0 or to_t.normalized().dot(_wind_dir) >= STRIKE_ARC_DOT):
			connected = true
			if target.has_method("take_damage"):
				target.take_damage(damage, enemy_type)
	_set_pose(POSE_STRIKE, _wind_dir, 13.0, 0.22)
	var host := get_parent()
	if host:
		var impact: Vector2 = global_position + _wind_dir * 26.0
		CombatFx.ripple(host, impact, _wind_dir, HOSTILE, 46.0, 0.2)
		if connected:
			FxLib.burst(host, impact, Color(2.4, 0.8, 0.9), 7, 180.0, FxLib.spark(), Vector2.ZERO, CombatFx.Z_FX)
		else:
			# A miss is information: the recovery frames are yours. In dev
			# register, not fighting-game register — "whiffed" was the only
			# player-facing line in this file that isn't something a tired
			# engineer would say (COMEDY_BIBLE: dry, technically literate).
			CombatFx.glyph(host, global_position + Vector2(0, -50), "no-op",
				Color("#7C8BB0"), 12, 0.5, 16.0)
	if not connected:
		_open_vuln(0.55, 1.35)
	elif _role == ROLE_SKIRMISHER:
		# Hit and run: a skirmisher never stands in the place it just struck.
		_knockback = -_wind_dir * 240.0
	if is_instance_valid(attack_timer):
		attack_timer.start(randf_range(1.2, 2.5))

## How far this one's swing actually reaches. Bigger things reach further — a
## fully-grown Scope Creep can hit you from where it could not five seconds ago,
## which is the entire joke — and the wedge painted on the floor is drawn from
## the same number, so the picture never lies about the hitbox.
func _reach() -> float:
	return STRIKE_RANGE * (1.0 + (maxf(scale.x, 0.5) - 1.0) * 0.5)

## An enemy commits to a swing from slightly inside its own reach, so the wedge
## it paints is a threat rather than an announcement it has already missed.
func _start_reach() -> float:
	return _reach() - (STRIKE_RANGE - STRIKE_START_RANGE)

## The alert ring's ONE owner. A tell is on while the thing it tells you about is
## happening, and off otherwise — no aggro toggle, no leash toggle, no idle
## radius (critique #1). Called from the top of `_physics_process`, so it also
## covers the frames a knockback, a pause or a stun returns early from.
func _sync_alert_ring() -> void:
	if not is_instance_valid(_alert_ring):
		return
	_alert_ring.visible = not _dying and is_committed()

## Is this enemy currently locked into something the player must react to?
## Used by the pack to take turns; public so siblings can ask cheaply.
func is_committed() -> bool:
	return _windup > 0.0 or _charge_state == 1 or _charge_state == 2 \
		or _boss_tele > 0.0 or _telegraph > 0.0

## Fewer than MAX_COMMITTED others mid-attack? Bosses never wait their turn.
func _attack_slot_free() -> bool:
	if is_boss or not is_inside_tree():
		return true
	var busy := 0
	for other in get_tree().get_nodes_in_group("enemy"):
		if other == self or not is_instance_valid(other):
			continue
		if other.has_method("is_committed") and other.is_committed():
			busy += 1
			if busy >= MAX_COMMITTED:
				return false
	return true

## Per-type signature behaviours + telegraphs. Never traps the player.
func _update_special(delta: float) -> void:
	_charge_cd = maxf(0.0, _charge_cd - delta)
	_lob_cd = maxf(0.0, _lob_cd - delta)
	_tick_guard(delta)
	match enemy_type:
		"scope_creep":
			# Requirements never stop growing. It gets bigger, faster, and — via
			# _reach() — able to hit you from where it could not a moment ago.
			_grow = minf(_grow + delta * 0.09, 1.0)
			scale = _base_scale * (1.0 + _grow * 0.7)
			speed = _base_speed * (1.0 + _grow * 0.9)
			if _grow >= 1.0 and not _grow_announced:
				_grow_announced = true
				var host := get_parent()
				if host:
					CombatFx.glyph(host, global_position + Vector2(0, -62),
						"v2 · out of scope for v1", Color("#8B5CF6"), 14, 1.2, 26.0)
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
		"null_reference":
			# It is here. It is not here. It cannot read properties of itself.
			_special_cd -= delta
			if _special_cd <= 0.0 and _aggroed:
				_dereference()
				_special_cd = randf_range(3.4, 5.2)
	if is_boss:
		_tick_boss(delta)
		return
	_tick_role(delta)

## The non-boss role clock: when does this archetype get to do its thing.
func _tick_role(delta: float) -> void:
	if _dying or not _aggroed or target == null or not is_instance_valid(target):
		return
	var dist := global_position.distance_to(target.global_position)
	match _role:
		ROLE_CHARGER:
			if _charge_state == 0 and _charge_cd <= 0.0 and dist > 76.0 and dist < 330.0 \
					and _attack_slot_free():
				_start_charge()
		ROLE_ARTILLERY:
			if _lob_cd <= 0.0 and dist > 84.0 and dist < 430.0 and _attack_slot_free():
				_fire_ranged()
		ROLE_SUMMONER:
			if _summons_left > 0 and _special_cd <= 0.0 and dist < 340.0:
				_special_cd = randf_range(6.0, 9.0)
				_summons_left -= 1
				_call_in_help()
			else:
				_special_cd -= delta

# --------------------------------------------------------- committed dash ----

## Telegraph the lane, then commit to it. The dash is a straight line that was
## drawn on the floor before it started: sidestep it and the dasher over-runs,
## lands in its recovery pose and takes 70% more damage until it recovers.
func _start_charge() -> void:
	if _dying or target == null or not is_instance_valid(target):
		return
	var d: Vector2 = target.global_position - global_position
	if d.length_squared() < 1.0:
		return
	_cancel_windup(false)
	_charge_dir = d.normalized()
	_charge_state = 1
	_charge_t = CHARGE_TELE
	_charge_hit = false
	var host := get_parent()
	if host:
		var to: Vector2 = global_position + _charge_dir * (CHARGE_SPEED * CHARGE_TIME + 40.0)
		CombatFx.beam(host, global_position, to, HOSTILE, 7.0, CHARGE_TELE)
		CombatFx.scorch(host, global_position, to, HOSTILE, CHARGE_TELE)
		CombatFx.glyph(host, global_position + Vector2(0, -54),
			str(TELLS.get(enemy_type, "committing")), HOSTILE, 15, CHARGE_TELE + 0.2, 16.0)
	AudioManager.play_sfx("ability")

func _tick_charge(delta: float) -> void:
	_charge_t -= delta
	match _charge_state:
		1:
			velocity = Vector2.ZERO
			if _charge_t <= 0.0:
				_charge_state = 2
				_charge_t = CHARGE_TIME
				if is_instance_valid(sprite):
					sprite.modulate = Color.WHITE
				var host := get_parent()
				if host:
					CombatFx.speed_lines(host, global_position, _charge_dir, FxLib.vivid(_accent()), 6)
		2:
			velocity = _charge_dir * CHARGE_SPEED
			move_and_slide()
			if absf(velocity.x) > 1.0 and is_instance_valid(sprite):
				sprite.flip_h = velocity.x < 0
			if Engine.get_physics_frames() % 3 == 0:
				var host := get_parent()
				if host:
					CombatFx.afterimage(host, sprite, Color(1.6, 1.1, 1.1, 0.5), 0.22)
			_charge_contact()
			if get_slide_collision_count() > 0:
				_end_charge(true)
			elif _charge_t <= 0.0:
				_end_charge(false)
		_:
			velocity = Vector2.ZERO
			if _charge_t <= 0.0:
				_charge_state = 0
				_charge_cd = randf_range(3.4, 5.2)

## One hit per dash, at contact range. It shoves rather than pins.
func _charge_contact() -> void:
	if _charge_hit or target == null or not is_instance_valid(target):
		return
	if global_position.distance_to(target.global_position) > 42.0:
		return
	_charge_hit = true
	if target.has_method("take_damage"):
		target.take_damage(damage, enemy_type)
	if target.has_method("apply_external_knockback"):
		target.apply_external_knockback(_charge_dir * 360.0)
	var host := get_parent()
	if host:
		CombatFx.ripple(host, target.global_position, _charge_dir, HOSTILE, 60.0, 0.22)
	FxLib.add_trauma(get_tree(), 0.2)

## Over-run. Running into a wall costs it more, because that is funnier and
## because a room's geometry should be a weapon the player can aim things into.
func _end_charge(hit_wall: bool) -> void:
	_charge_state = 3
	_charge_t = CHARGE_RECOVER * (1.35 if hit_wall else 1.0)
	_open_vuln(_charge_t, 1.7)
	velocity = Vector2.ZERO
	if is_instance_valid(sprite):
		sprite.modulate = Color.WHITE
	var host := get_parent()
	if host:
		if hit_wall:
			CombatFx.shockwave(host, global_position, HOSTILE, 120.0, 0.35)
			FxLib.add_trauma(get_tree(), 0.22)
		CombatFx.glyph(host, global_position + Vector2(0, -50),
			"reverted" if hit_wall else "over-committed", Color("#FFD34D"), 14, 0.9, 24.0)
	_dazed_mark(_charge_t)

## Tear down a dash at any stage and put it back on cooldown. Safe to call every
## frame and safe to call on an enemy that was never a charger.
func _cancel_charge() -> void:
	if _charge_state == 0:
		return
	_charge_state = 0
	_charge_t = 0.0
	_charge_hit = false
	_charge_cd = maxf(_charge_cd, 1.2)
	if is_instance_valid(sprite):
		sprite.modulate = Color.WHITE
		sprite.position = Vector2(_spr_base_x, _spr_base_y)
		sprite.rotation = 0.0
		sprite.scale = _spr_base_scale

# ------------------------------------------------------------ lobbed shots ----

## A telegraphed lobbed shot. The ground marker fills for the WHOLE flight and
## the hit lands exactly inside it, so "why did that hit me" always has the same
## answer: you were still standing in the circle when it finished filling.
## `real = false` draws a decoy — the hallucination's other, equally confident
## answer — in dead grey, so it is always distinguishable at a glance.
func _lob(at: Vector2, radius: float, dmg: int, flight: float, tag: String = "", real: bool = true) -> void:
	var host := get_parent()
	if host == null or not host.is_inside_tree() or _dying:
		return
	var col: Color = FxLib.vivid(_accent()) if real else Color("#7C8BB0")
	var mk := CombatFx.marker(host, at, col, radius, flight)
	if not tag.is_empty():
		CombatFx.glyph(host, at + Vector2(0, -16), tag, col, 12, flight, 8.0)
	var from: Vector2 = global_position + Vector2(0, -16)
	var shot := Sprite2D.new()
	var dot := FxLib.glow_dot()
	var scl := 1.7
	if dot:
		shot.texture = dot
	else:
		shot.texture = FxLib.white_square(8)
		scl = 0.7
	shot.material = FxLib.additive_material()
	shot.modulate = Color(col.r * 2.2, col.g * 2.2, col.b * 2.2, 0.95 if real else 0.45)
	shot.z_index = CombatFx.Z_FX
	shot.scale = Vector2.ONE * scl
	host.add_child(shot)
	shot.global_position = from
	var apex: Vector2 = from.lerp(at, 0.5) + Vector2(0, -maxf(56.0, from.distance_to(at) * 0.38))
	_shots.append({
		"node": shot, "marker": mk, "from": from, "apex": apex, "at": at,
		"t": 0.0, "dur": maxf(flight, 0.1), "radius": radius, "dmg": dmg,
		"col": col, "real": real, "scl": scl,
	})

## Quadratic arc, stepped by hand. No allocations beyond the Vector2 values.
func _tick_shots(delta: float) -> void:
	if _shots.is_empty():
		return
	var i := _shots.size() - 1
	while i >= 0:
		var s: Dictionary = _shots[i]
		s["t"] = float(s["t"]) + delta
		var u: float = clampf(float(s["t"]) / float(s["dur"]), 0.0, 1.0)
		var node: Node2D = s["node"]
		if is_instance_valid(node):
			var p_from: Vector2 = s["from"]
			var p_apex: Vector2 = s["apex"]
			var p_at: Vector2 = s["at"]
			var a: Vector2 = p_from.lerp(p_apex, u)
			var b: Vector2 = p_apex.lerp(p_at, u)
			node.global_position = a.lerp(b, u)
			node.scale = Vector2.ONE * float(s["scl"]) * (1.0 + 0.45 * sin(u * PI))
		if u >= 1.0:
			_land_shot(s)
			_shots.remove_at(i)
		i -= 1

func _land_shot(s: Dictionary) -> void:
	var node: Node2D = s["node"]
	if is_instance_valid(node):
		node.queue_free()
	var host := get_parent()
	if host == null or not host.is_inside_tree():
		return
	var at: Vector2 = s["at"]
	var col: Color = s["col"]
	var radius: float = float(s["radius"])
	if not bool(s["real"]):
		# It was never sourced. It was, however, extremely confident.
		CombatFx.glyph(host, at + Vector2(0, -10), "[citation needed]",
			Color("#7C8BB0"), 12, 0.8, 22.0)
		return
	CombatFx.shockwave(host, at, col, radius, 0.34)
	FxLib.burst(host, at, Color(col.r * 2.0, col.g * 2.0, col.b * 2.0), 10, 200.0,
		FxLib.spark(), Vector2(0, 120), CombatFx.Z_FX)
	if _combat_paused() or target == null or not is_instance_valid(target):
		return
	var miss: float = target.global_position.distance_to(at)
	# Only shake the camera for impacts the player could actually feel — five
	# memory leaks lobbing across a room must not turn into a permanent rumble.
	if miss < 220.0:
		FxLib.add_trauma(get_tree(), 0.12)
	if miss <= radius and target.has_method("take_damage"):
		target.take_damage(int(s["dmg"]), enemy_type)

## Killing the caster cancels its incoming shot. Also the only teardown path,
## so nothing in flight can outlive the room.
func _cancel_shots() -> void:
	for entry in _shots:
		var s: Dictionary = entry
		var node: Node2D = s["node"]
		if is_instance_valid(node):
			node.queue_free()
		var mk: Node2D = s["marker"]
		if mk != null and is_instance_valid(mk):
			mk.queue_free()
	_shots.clear()

## What each artillery type actually throws. All of them aim at where you ARE:
## a lob is a question about whether you intend to keep standing there.
func _fire_ranged() -> void:
	if target == null or not is_instance_valid(target):
		return
	var at: Vector2 = target.global_position
	match enemy_type:
		"memory_leak":
			_lob_cd = randf_range(5.5, 8.0)
			_lob(at, 52.0, maxi(3, int(damage * 0.6)), 1.0, "still reachable")
		"rate_limiter":
			_lob_cd = randf_range(4.2, 6.4)
			_lob(at, 46.0, maxi(3, int(damage * 0.7)), 0.9, "retry-after: ?")
		"hallucination":
			# Two answers. One of them is sourced. The grey one is the confident
			# one, and it has never hurt anybody.
			_lob_cd = randf_range(4.0, 6.0)
			_lob(at, 48.0, maxi(3, int(damage * 0.7)), 1.0, "as we all know")
			var off := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
			if off.length_squared() > 0.001:
				_lob(at + off.normalized() * randf_range(90.0, 150.0), 48.0, 0, 1.0, "", false)
		_:
			_lob_cd = randf_range(3.4, 5.0)
			_lob(at, 54.0, maxi(4, int(damage * 0.55)), 1.0, str(TELLS.get(enemy_type, "")))
	AudioManager.play_sfx("projectile_shoot")

## The transitive dependency. Small, weak, and it brought nothing with it.
func _call_in_help() -> void:
	var host := get_parent()
	if host == null:
		return
	var e := _spawn_add("null_reference", 10, maxi(3, int(damage * 0.5)), 3)
	if e == null:
		return
	CombatFx.glyph(host, global_position + Vector2(0, -52), "peer dep missing",
		Color("#A8FF3E"), 14, 1.0, 24.0)
	CombatFx.ring(host, e.global_position, Color("#A8FF3E"), 2.0, 40.0, 0.3, 5.0, 1.0, 22)
	AudioManager.play_sfx("ability")

## Blink one step sideways, leaving the shape of where it was. Not an escape —
## it stays inside the fight, it just stops being where you aimed.
func _dereference() -> void:
	var host := get_parent()
	var from: Vector2 = global_position
	var toward: Vector2 = Vector2.RIGHT
	if target and is_instance_valid(target):
		toward = (target.global_position - global_position).normalized()
	# Sidestep around the player rather than a random jump, so it never blinks
	# itself into scenery on the far side of the room.
	global_position += toward.orthogonal() * (54.0 * _orbit) + toward * 18.0
	if host:
		CombatFx.afterimage(host, sprite, Color(1.0, 1.0, 1.4, 0.6), 0.35, from - global_position, -1)
		CombatFx.glyph(host, from + Vector2(0, -34), "undefined", Color("#7C8BB0"), 12, 0.5, 18.0)

# ------------------------------------------------------------ boss rig ----

## Bosses carry their own presentation layer: the entrance card, the bottom
## health bar, phase banners and the death stamp all live in BossHud.
func _build_boss_presence() -> void:
	_boss_hud = BossHud.new()
	_boss_hud.name = "BossHud"
	add_child(_boss_hud)
	_boss_hud.setup(enemy_type, _accent())
	_boss_hud.set_health(hp, max_hp)
	# There is no boss aura. A 3.0-scale PointLight2D parked on the body is what
	# the QA frame read as "a smooth-gradient cyan blob"; a boss is legible
	# because it is BIG and because the room's own lights fall on it (LAW 4:
	# lights pool on the floor, they do not spot-halo the thing standing there).

## Name card, letterbox, camera push, ambience shift. Plays once, and never
## takes control away — the player can walk, shoot and leave during all of it.
## IS THIS BODY INSIDE THE FRAME THE PLAYER IS ACTUALLY LOOKING AT?
##
## ROUND 12's critique #3 staged every boss at y 890, and the arrival camera
## shows y 120..840 of a 1280x960 room — so a boss is DELIBERATELY off the bottom
## of the frame when the room finishes building. The entrance trigger below is a
## distance test (620 units) and a boss at (866,890) stands 469 units from the
## spawn, so it fired on the first frame of every boss region: a 240-unit
## shockwave, a 150-unit ring, a 26-dot glow burst, a camera punch, a trauma
## kick and the boss music, all detonating around an object that is not on
## screen. What the player got was a bright saturated wave welling up from under
## the ability bar with no visible cause — measured at 34,000 pixels over
## luminance 180 in the bottom third of region_production.png and
## region_corporate_enterprise.png, against ~2,000 in every other room.
##
## An entrance is a thing you are supposed to WATCH. It now waits until the boss
## is in the frame to be seen making it; chasing brings it in within a second or
## two. `take_damage()` still triggers the intro unconditionally, so sniping a
## boss from beyond the trigger is unchanged and the fight is never anonymous.
##
## ROUND 13 tightens the distance half of the same test from 620 to 480. The
## rooms are 1280x960 and there is nowhere in one of them a boss can stand that
## is a full frame below the arrival view, so region_builder stages every boss at
## y 906 — 500-odd units from the spawn plaza. At 620 that is INSIDE the trigger
## on the first frame of the visit and the gate is carrying the whole load on its
## own; at 480 the distance test agrees with the camera test instead of fighting
## it, and neither one has to be right by itself.
const BOSS_INTRO_RANGE := 480.0

func _on_camera() -> bool:
	var vp := get_viewport()
	if vp == null:
		return true
	var cam := vp.get_camera_2d()
	if cam == null:
		return true
	var vis := Vector2(vp.get_visible_rect().size) / cam.zoom
	var view := Rect2(cam.get_screen_center_position() - vis * 0.5, vis)
	return view.has_point(global_position)

func _play_boss_intro() -> void:
	if _intro_done:
		return
	_intro_done = true
	_intro_lock = 2.2
	if _boss_hud and is_instance_valid(_boss_hud):
		_boss_hud.play_entrance()
	var host := get_parent()
	# LAW 2 and LAW 7: an entrance is a HOSTILE tell, not the boss's own hue. The
	# accent ramp (#FF2D95 for the merge conflict, #24F0DC for the infinite
	# context, #6BC7FF for the bill) put a second saturated hue on screen per boss
	# and drew it as three stacked layers — a 240-unit shockwave, a 150-unit ring
	# and twenty-six overbright glow dots. That is what the QA frames read as "a
	# triple magenta ring filling the bottom third" and "a cyan ring in the gold
	# vault". One shockwave, in the same red as every other telegraph in the game.
	if host:
		CombatFx.shockwave(host, global_position, HOSTILE, 200.0, 0.55)
	# It rears up. (A pose, not a tween — `_process` owns the sprite transform.)
	_set_pose(POSE_HOP, Vector2.UP, 20.0, 0.6)
	FxLib.add_trauma(get_tree(), 0.5)
	var fx := get_tree().get_first_node_in_group("camera_fx")
	if fx and fx.has_method("punch_zoom"):
		fx.punch_zoom(0.07)
	AudioManager.play_sfx("boss_spawn")
	AudioManager.play_music("boss_music")

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
	# A phase change resets the board: whatever it was mid-way through is
	# abandoned, and a guardian's plate is re-approved for the new quarter.
	_boss_tele = 0.0
	_boss_recover = 0.0
	_charge_cd = 0.0
	_cancel_charge()
	if _boss_marker and is_instance_valid(_boss_marker):
		_boss_marker.queue_free()
		_boss_marker = null
	if _role == ROLE_GUARDIAN and not _guard_up():
		_guard_down = 0.0
		_build_guard()
	var host := get_parent()
	var col := FxLib.vivid(_accent())
	if host:
		CombatFx.shockwave(host, global_position, col, 200.0, 0.45)
		CombatFx.text_shards(host, global_position, col,
			DEATH_SHARDS.get(enemy_type, ["escalated"]), 4)
	if is_instance_valid(sprite):
		var tw := create_tween()
		tw.tween_property(sprite, "modulate", Color(1.6, 1.6, 1.6), 0.06)
		tw.tween_property(sprite, "modulate", Color.WHITE, 0.5)
	FxLib.add_trauma(get_tree(), 0.4)
	AudioManager.play_sfx("ability")

## Which patterns a boss may use, by phase. Each phase ADDS a move rather than
## only speeding up the last one, so phase 4 of a fight does not play like a
## faster phase 1. Artillery bosses lead with the barrage from the first phase —
## a $700 cloud bill has never walked up to anybody.
func _boss_moves() -> Array:
	var moves: Array = [BOSS_SLAM] if _role != ROLE_ARTILLERY else [BOSS_BARRAGE, BOSS_SLAM]
	if _boss_phase >= 2:
		moves.append(BOSS_BARRAGE)
	if _boss_phase >= 3:
		moves.append(BOSS_CHARGE)
	if _boss_phase >= 4:
		moves.append(BOSS_SIGNATURE)
		moves.append(BOSS_CHARGE)
	return moves

## Bosses cycle: pick a move for the phase, telegraph it, commit, then STAND
## THERE. The recovery is not a gap in the design, it is the design — every
## boss commitment ends in a window the player is meant to punish.
func _tick_boss(delta: float) -> void:
	if _intro_lock > 0.0:
		return
	if _charge_state != 0:
		return  # the dash state machine owns this boss right now
	if _boss_recover > 0.0:
		_boss_recover -= delta
		if _boss_recover <= 0.0 and is_instance_valid(sprite):
			sprite.modulate = Color.WHITE
		return
	if _boss_tele > 0.0:
		_boss_tele -= delta
		sprite.modulate = TELL_TINT if fmod(_boss_tele, 0.2) < 0.1 else Color.WHITE
		if _boss_tele <= 0.0:
			sprite.modulate = Color.WHITE
			_boss_execute()
		return
	_special_cd -= delta
	if _special_cd > 0.0 or target == null or not is_instance_valid(target):
		return
	var dist := global_position.distance_to(target.global_position)
	# ...and never before its own entrance. A boss's aggro radius is 900, so it
	# starts walking at the player from across the room the instant it is built,
	# and at 460 it began telegraphing while it was still off the bottom of the
	# arrival frame — a 150- or 220-unit ring painted under the ability bar around
	# a body the player cannot see (critiques #1 and #3). `_play_boss_intro` fires
	# on proximity + camera, or on the first damage taken, so a boss that is
	# genuinely in the fight has always had its entrance by the time this matters.
	if dist > 460.0 or not _intro_done:
		return
	var moves := _boss_moves()
	_boss_move = int(moves[randi() % moves.size()])
	# A dash needs room to be dodgeable; up close it becomes a slam instead.
	if _boss_move == BOSS_CHARGE:
		if dist > 96.0:
			_special_cd = randf_range(3.6, 5.4)
			_start_charge()
			return
		_boss_move = BOSS_SLAM
	_boss_tele = 0.7 if _boss_move == BOSS_SLAM else 0.9
	_special_cd = maxf(2.6, randf_range(3.6, 5.8) - 0.3 * float(_boss_phase - 1))
	_telegraph_boss_move()

## Paint the move before it happens. No hidden information, ever.
##
## In HOSTILE, like every other telegraph the game draws (LAW 2's "enemy tells
## only", LAW 7's "exactly one red tell"). These two rings were the largest
## coloured shapes in four of the QA frames and each was in its own boss's private
## hue — the per-enemy rainbow LAW 7 exists to forbid — and it cost the reading
## besides, because a player who has learnt that red means "move" should not have
## to re-learn it per boss.
func _telegraph_boss_move() -> void:
	var host := get_parent()
	if host == null:
		return
	match _boss_move:
		BOSS_BARRAGE:
			CombatFx.glyph(host, global_position + Vector2(0, -72),
				str(TELLS.get(enemy_type, "incoming")), HOSTILE, 16, _boss_tele + 0.2, 18.0)
			CombatFx.ring(host, global_position, HOSTILE, 20.0, 150.0, _boss_tele, 3.0, 5.0, 28)
		BOSS_SIGNATURE:
			CombatFx.glyph(host, global_position + Vector2(0, -72), _signature_tell(),
				HOSTILE, 16, _boss_tele + 0.3, 18.0)
			CombatFx.ring(host, global_position, HOSTILE, 220.0, 30.0, _boss_tele, 3.0, 5.0, 28)
		_:
			# The slam reaches 260px; so does the marker.
			_boss_marker = CombatFx.marker(host, global_position, HOSTILE, 260.0, _boss_tele)

func _boss_execute() -> void:
	match _boss_move:
		BOSS_BARRAGE:
			_boss_barrage()
		BOSS_SIGNATURE:
			_boss_signature()
		_:
			_boss_slam()

## Telegraphed impacts fanned around where the player is standing, one under
## their feet and the rest ringing it. Standing still is the only wrong answer;
## walking out of the ring is always possible.
func _boss_barrage() -> void:
	if target == null or not is_instance_valid(target):
		_open_window(0.7)
		return
	var here: Vector2 = target.global_position
	var count: int = 3 + mini(2, _boss_phase - 1)
	var base: float = randf() * TAU
	var dmg: int = maxi(4, int(damage * 0.45))
	_lob(here, 60.0, dmg, 1.05, str(TELLS.get(enemy_type, "")))
	for i in count:
		var a: float = base + TAU * float(i) / float(count)
		var at: Vector2 = here + Vector2(cos(a), sin(a)) * randf_range(90.0, 150.0)
		_lob(at, 56.0, dmg, 1.05 + 0.12 * float(i))
	AudioManager.play_sfx("ability")
	_open_window(0.9)

## The phase-4 move, one per boss. It is the thing that boss is ABOUT.
func _boss_signature() -> void:
	match enemy_type:
		"enterprise_architect":
			# The governance council convenes. Capped, because the joke is the
			# meeting, not the wipe.
			for i in mini(2, _summons_left):
				_summons_left -= 1
				_summon("scope_creep")
		"merge_conflict":
			for i in mini(2, _summons_left):
				_summons_left -= 1
				var e := _spawn_add("merge_conflict", 18, maxi(4, int(damage * 0.4)), 3)
				if e:
					e.set("generation", 1)  # these ones do not get to split again
		"legacy_monolith":
			_guard_down = 0.0
			if not _guard_up():
				_build_guard()
		"cloud_bill", "infinite_context":
			_boss_barrage()
			return
		_:
			_boss_slam()
			return
	_open_window(1.0)

func _signature_tell() -> String:
	match enemy_type:
		"enterprise_architect":
			return "convening a working group"
		"merge_conflict":
			return "conflicted copy (2)"
		"legacy_monolith":
			return "re-approving the plate"
		"cloud_bill":
			return "annual true-up"
		"infinite_context":
			return "summarising the summary"
	return "escalating"

## Every boss commitment ends in an opening. This is where the fight is won: it
## stands still, wears the question marks, and takes 75% more damage.
func _open_window(seconds: float) -> void:
	_boss_recover = seconds
	_open_vuln(seconds, 1.75)
	if _dying:
		return
	var host := get_parent()
	if host:
		CombatFx.glyph(host, global_position + Vector2(0, -76), "EXPOSED",
			Color("#FFD34D"), 17, minf(seconds, 1.0), 20.0)
	_dazed_mark(seconds)

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
	_open_window(0.85)

## Give the slam physical weight: a camera kick, an expanding dust ring and a
## hard shockwave at the point of impact. All cosmetic and self-cleaning.
func _slam_impact() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam and cam.has_method("shake"):
		cam.shake(0.35, 7.0)
	var parent := get_parent()
	if not parent:
		return
	CombatFx.shockwave(parent, global_position, HOSTILE, 260.0, 0.4)
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
	var e := _spawn_add(type, 16)
	if e == null:
		return
	# Adds arrive through a rift, not by appearing out of nothing.
	var host := get_parent()
	if host:
		CombatFx.ring(host, e.global_position, Color("#8B5CF6"), 2.0, 44.0, 0.3, 5.0, 1.0, 24)
		CombatFx.glyph(host, e.global_position + Vector2(0, -50), "added to the invite", Color("#8B5CF6"), 12, 0.9, 22.0)

## Shared add-spawning. `dmg` / `drop` below zero leave the scene defaults alone,
## which is what `_summon()` has always relied on. Returns null when this enemy
## has no tree to spawn into. Exported fields are written through `set()` so the
## statically-typed handle never has to pretend it knows the enemy script.
func _spawn_add(type: String, hp_val: int, dmg: int = -1, drop: int = -1) -> Node2D:
	var host := get_parent()
	if host == null or not host.is_inside_tree():
		return null
	# NOT preload(): enemy.tscn carries this very script as its ext_resource, so a
	# compile-time preload here is a load cycle. Whenever enemy_base.gd is compiled
	# before enemy.tscn is cached, the .tscn resolves its script to null and every
	# enemy instantiates as a bare CharacterBody2D with no AI, HP or hitbox.
	var scene: PackedScene = load("res://scenes/combat/enemy.tscn")
	var e: Node2D = scene.instantiate()
	e.set("enemy_type", type)
	e.set("max_hp", hp_val)
	if dmg >= 0:
		e.set("damage", dmg)
	if drop >= 0:
		e.set("token_drop", drop)
	host.add_child(e)
	# Adds arrive on the far side of the summoner, never on top of the player. A
	# body that materialises inside your hitbox is a free hit, not a threat, and
	# it is the one way a summon could feel unfair.
	var offset := Vector2(randf_range(-30, 30), randf_range(-30, 30))
	if target and is_instance_valid(target):
		var back: Vector2 = global_position - target.global_position
		if back.length_squared() > 1.0:
			offset += back.normalized() * randf_range(40.0, 62.0)
	e.global_position = global_position + offset
	return e

func _tick_rate_limiter(delta: float) -> void:
	if _telegraph > 0.0:
		# Flash while winding up the 429 pulse.
		_telegraph -= delta
		sprite.modulate = TELL_TINT if fmod(_telegraph, 0.2) < 0.1 else Color.WHITE
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
	var was_winding: bool = _windup > 0.0
	# Being shoved interrupts a committed swing. That is the whole point of the
	# dash, and it must read on screen the frame it happens.
	_cancel_windup()
	# The DASH — and only the dash — also breaks a charge telegraph or a boss
	# wind-up. Ordinary bolts deliberately cannot: if a bolt cancelled a
	# telegraph, no enemy that stands still to wind up would ever get an attack
	# off, and the whole read-the-tell loop would collapse into "shoot faster".
	# Force Push and a bolt overlap in raw impulse, so the tell is the player's
	# own dash state; if that ever stops being readable this degrades to "no
	# interrupt", never to an error.
	var hard: bool = impulse.length() >= 360.0 and _player_is_dashing()
	var broke_commit: bool = hard and (_charge_state == 1 or _boss_tele > 0.0)
	if broke_commit:
		_cancel_charge()
		if _boss_tele > 0.0:
			_boss_tele = 0.0
			if _boss_marker and is_instance_valid(_boss_marker):
				_boss_marker.queue_free()
				_boss_marker = null
			if is_instance_valid(sprite):
				sprite.modulate = Color.WHITE
	if _dying or not (broke_commit or (hard and was_winding)):
		return
	# Reading a telegraph and dashing into it is supposed to PAY.
	_open_vuln(1.1, 1.6)
	var host := get_parent()
	if host:
		CombatFx.glyph(host, global_position + Vector2(0, -56), "interrupted",
			Color("#7DFFF0"), 15, 0.8, 24.0)

## Is the player mid-dash right now? Used to tell a Force Push apart from a
## bolt, which carry overlapping impulses. Property-probed rather than
## hard-referenced so a missing field degrades to `false`.
func _player_is_dashing() -> bool:
	if not is_inside_tree():
		return false
	var p := get_tree().get_first_node_in_group("player")
	if p == null or not is_instance_valid(p):
		return false
	return "_dash_timer" in p and p._dash_timer > 0.0

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
	amount = _resolve_damage(amount, from_dir)
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

## Two modifiers sit between a shot and an enemy's HP, and both are things the
## player controls:
##   * the guard plate — shots into a guardian's front are mostly absorbed and
##     chip the plate; from anywhere else they land in full;
##   * the vulnerability window — anything that over-committed takes more.
## Both announce themselves on screen, so the number is never a mystery.
func _resolve_damage(amount: int, from_dir: Vector2) -> int:
	var host := get_parent()
	# One bolt registers on BOTH the projectile's area and this enemy's hitbox in
	# the same physics flush (see _spawn_damage_number). Everything that must
	# happen once per SHOT — chipping the plate, printing a callout — is gated on
	# the frame rather than on the callback.
	var frame := Engine.get_physics_frames()
	var first_this_frame: bool = frame != _guard_frame
	if _guard_up() and from_dir.length_squared() > 0.0001:
		_guard_frame = frame
		if from_dir.dot(_guard_dir) < -cos(GUARD_ARC * 0.5):
			amount = maxi(1, int(round(float(amount) * GUARD_MITIGATION)))
			if first_this_frame:
				_guard_hits += 1
				if host:
					CombatFx.ring(host, global_position + _guard_dir * 30.0,
						FxLib.vivid(_accent()), 4.0, 26.0, 0.22, 5.0, 1.0, 18)
					CombatFx.glyph(host, global_position + _guard_dir * 36.0 + Vector2(0, -10),
						"blocked", Color("#C9D6F2"), 12, 0.45, 12.0)
				if _guard_hits >= _guard_max:
					_break_guard()
			return amount
		if first_this_frame and host and randf() < 0.4:
			CombatFx.glyph(host, global_position + Vector2(0, -46), "flanked",
				Color("#7DFFF0"), 13, 0.55, 18.0)
	if _vuln_t > 0.0 and _vuln_mult > 1.0:
		amount = int(round(float(amount) * _vuln_mult))
	return amount

## Knocked off its feet for a moment: the sprite kicks away from the hit and
## springs back. Never touches the body, so it can't affect collision.
func _stagger(from_dir: Vector2, is_crit: bool) -> void:
	if not is_instance_valid(sprite) or _windup > 0.0 or _charge_state != 0:
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
	sprite.modulate = Color(1.6, 1.6, 1.6)
	_flash_tween = create_tween()
	_flash_tween.tween_property(sprite, "modulate", Color.WHITE, 0.15)

func _attack() -> void:
	if _combat_paused() or _dying or _stun_time > 0.0 or _intro_lock > 0.0:
		attack_timer.start(1.0)
		return
	# A boss must not swing during its own punish window; the whole point of the
	# recovery is that it is defenceless for a beat.
	#
	# Nor during ANY big-move telegraph (a boss slam/barrage, or a rate limiter's
	# 429): a melee wind-up returns out of `_physics_process` BEFORE
	# `_update_special` runs, which freezes `_boss_tele` / `_telegraph` in place
	# while the ground marker — a tween, which does not freeze — runs out and
	# frees itself. The big move then landed with nothing painted under it, which
	# is the same "the marker lies about the kill zone" defect the planting was
	# added to fix, arriving through the other door.
	if _charge_state != 0 or _telegraph > 0.0 \
			or (is_boss and (_boss_recover > 0.0 or _boss_tele > 0.0)):
		attack_timer.start(0.8)
		return
	if not target or not is_instance_valid(target) or global_position.distance_to(target.global_position) > _start_reach():
		attack_timer.start(1.0)
		return
	# Take turns. Four enemies landing a swing in the same frame is the thing
	# that made packs read as unfair rather than hard.
	if not _attack_slot_free():
		attack_timer.start(randf_range(0.45, 0.9))
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
	_cancel_charge()
	# Anything this one still had in the air is cancelled with it, and the alert
	# ring comes off so the dissolve is the only thing left to look at.
	_cancel_shots()
	if is_instance_valid(_alert_ring):
		_alert_ring.visible = false
	if is_instance_valid(_guard):
		_guard.visible = false
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
	if _elite:
		# Elites are worth saying goodbye to; the payout is the point.
		CombatFx.glyph(host, global_position + Vector2(0, -72), "deprecated at last",
			Color("#FFD34D"), 15, 1.2, 30.0)
		CombatFx.ring(host, global_position, Color("#FFD34D"), 6.0, 110.0, 0.45, 8.0, 1.4)
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
	# NOT preload(): enemy.tscn carries this very script as its ext_resource, so a
	# compile-time preload here is a load cycle. Whenever enemy_base.gd is compiled
	# before enemy.tscn is cached, the .tscn resolves its script to null and every
	# enemy instantiates as a bare CharacterBody2D with no AI, HP or hitbox.
	var scene: PackedScene = load("res://scenes/combat/enemy.tscn")
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
