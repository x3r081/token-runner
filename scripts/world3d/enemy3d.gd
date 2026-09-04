extends CharacterBody3D
class_name Enemy3D
## The 2D game's enemy brain (scripts/combat/enemy_base.gd), moved onto the XZ
## plane (3D_BIBLE.md §4). Nothing about the FIGHT changes: every distance,
## every timer, every damage number below is the 2D number, in MAP PIXELS, and
## the steering is computed in map pixels and converted to world units exactly
## once per frame (§2's coordinate law). A player who learned the 2D fight has
## learned this one.
##
## What changes is the presentation: a Kenney model instead of a sprite, a
## billboard health bar instead of a ColorRect, telegraphs painted on the FLOOR
## as flat unlit decals instead of Line2D, and Fx3D for the juice on top.
##
## The telegraph decals are built and owned HERE rather than delegated to Fx3D.
## Fx3D is a stub another track fills in, and a wind-up the player cannot see is
## not a hard fight, it is an unfair one — so the shapes that carry INFORMATION
## (the alert ring, the strike wedge, the charge lane, the slam marker, the guard
## plate) are in this file, and Fx3D is called alongside them for the sparks.

# ------------------------------------------------------------- identity ----

@export var enemy_type: String = "bug"
@export var max_hp: int = 30
@export var damage: int = 10
@export var speed: float = 80.0          ## map px/s — the 2D number
@export var token_drop: int = 8
@export var is_boss: bool = false
@export var generation: int = 0          ## for merge_conflict splitting
## Enemies only chase once the player comes within AGGRO_RADIUS, and give up
## (return home) if the player gets beyond aggro_radius * LEASH_MULT.
@export var aggro_radius: float = 340.0

@onready var model_root: Node3D = $Model
@onready var hitbox: Area3D = $Hitbox
@onready var attack_timer: Timer = $AttackTimer
@onready var _body_col: CollisionShape3D = $Collision
@onready var _hitbox_col: CollisionShape3D = $Hitbox/CollisionShape3D
@onready var _shadow: MeshInstance3D = $Shadow

# ------------------------------------------------ tuning (MAP PIXELS) ----
## Every one of these is copied verbatim from enemy_base.gd. Read that file for
## why each number is what it is; this file must never drift from it.

const ENGAGE_DISTANCE := 34.0
const SEPARATION_RADIUS := 46.0
const KNOCKBACK_DECAY := 900.0
const LEASH_MULT := 1.8

const WINDUP_TIME := 0.42
const STRIKE_RANGE := 56.0
## The swing only connects inside the wedge painted on the floor: cos(1.5/2).
## The decal is drawn from STRIKE_ARC (1.5 rad) and the hit test from this dot,
## so the picture and the hitbox are the same shape. Keep them in lockstep.
const STRIKE_ARC := 1.5
const STRIKE_ARC_DOT := 0.7317
const STRIKE_START_RANGE := 48.0

const ROLE_BRAWLER := 0
const ROLE_SKIRMISHER := 1
const ROLE_ARTILLERY := 2
const ROLE_GUARDIAN := 3
const ROLE_SUMMONER := 4
const ROLE_CHARGER := 5

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

## At most this many NON-BOSS enemies may be committed at once, so a pack takes
## turns instead of landing four hits in one frame.
const MAX_COMMITTED := 2

const CHARGE_TELE := 0.62
const CHARGE_SPEED := 560.0
const CHARGE_TIME := 0.36
const CHARGE_RECOVER := 1.05

const GUARD_ARC := 1.9
const GUARD_SLEW := 1.7
const GUARD_MITIGATION := 0.28

const BOSS_SLAM := 0
const BOSS_BARRAGE := 1
const BOSS_CHARGE := 2
const BOSS_SIGNATURE := 3

const ELITE_FREE_REGIONS := ["localhost", "dependency_district"]
const ELITE_CHANCE := 0.16
const BOSS_INTRO_RANGE := 480.0

## VISUAL_BIBLE LAW 2: every tell in this file is this ONE red, so "that is about
## to hurt" reads identically in every room.
const HOSTILE := Color("#FF4757")
## The wind-up tint, as a MULTIPLY and never above 1.0 — the model goes red, it
## does not light up.
const TELL_TINT := Color(1.0, 0.42, 0.47)

## VISUAL_BIBLE v2 LAW 7 — enemies are hostile by SILHOUETTE. The Kenney kits
## dress a zombie in teal, an orc in green, a keeper in brown and a UFO in
## chrome, all at full chroma; a room with four of them had four hues in it
## before the region spent one. A multiply of ~0.57 grey-blue drops every body
## to a dark, faintly cool shape that the moon still models — a silhouette, not
## a mud pit — and leaves exactly one saturated thing on the whole enemy: the
## red tell below.
const BODY_TINT := Color(0.55, 0.58, 0.62)

## THE TELL. One red core per enemy, and nothing else on the body is allowed to
## be bright (LAW 3 lists "enemy tells (eyes/core only)" among the five). It is
## a tiny billboarded quad at eye height, additive and over the §7 glow
## threshold so it blooms as a point rather than as a halo — the read is "two
## eyes in the dark", not "an enemy wearing a coloured light".
const TELL_QUAD := 0.075
const TELL_GAIN := 1.5
## Elites and bosses speak the SAME language, louder: the same red core, bigger,
## plus a pool small enough to stay under the body. v1 gave them a 2.4-energy
## OmniLight in the enemy's own DEATH_ACCENT — a per-type rainbow halo, range 5,
## which is precisely the "accent halo" LAW 7 forbids and a large part of why
## the combat frame is a pastel wash.
const TELL_LIGHT_ELITE := 0.6
const TELL_LIGHT_BOSS := 0.8
const TELL_RANGE_ELITE := 1.5
const TELL_RANGE_BOSS := 2.2

## The readout over a damaged body: SMALL, TEXT_DIM, and silent until it has
## something to say (LAW 4: quiet by default). It is a screen-space label like
## every other piece of world text now (scripts/world3d/screen_labels.gd) — the
## two quads it replaces were a black plate with a coloured fill, which is a HUD
## widget parked in the world, and eight of them across a room read as UI litter.
## The range is the fight you are actually in: a body being shot at across the
## floor does not need a number, it needs to be visibly dying.
const HP_LABEL_RANGE := 12.0
const HP_LABEL_LIFT := 0.28

## THE PER-TYPE DEATH ACCENTS ARE GONE. There were thirteen of them — acid,
## magenta, violet, blue, amber, sky, copper, cyan — and every one was a hue the
## bible had already spent somewhere else: LAW 2 gives a region three, and a room
## with four enemy types in it was drawing eight before the region drew one. A
## death is the loudest moment an enemy gets, so it was also the moment the
## palette broke worst, in violet and magenta, in rooms whose accent is red.
##
## An enemy is HOSTILE, and everything it emits — the wind-up, the shard text,
## the dissolve, the boss bar, the summon ring — is that same one red. LAW 7's
## "hostile by silhouette, exactly one red tell" all the way down; the comedy
## lives in the WORDS, which is where LAW 10 says the jokes belong.

## Blood substitute. Nothing bleeds in this game; things leak error text.
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

## What it says a beat before a BIG move lands.
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

const ELITE_TAGS := ["load-bearing", "since 2009", "do not remove", "unowned",
	"marked @deprecated", "still in prod"]

# ------------------------------------------------------------- 3D models ----

## 3D_BIBLE §7's enemy mapping. `h` is the world height the model is fitted to
## (Map3D.fit_height); `boss_h` overrides it for the types that are ALWAYS the
## room's boss and whose mapped scale already accounts for that. `y` lifts the
## model off the floor for the things that fly. Every key here is in
## assets/external/kenney3d/manifest.json — Map3D.model() is exists()-guarded
## anyway, and a missing model falls back to a primitive so an enemy is never
## invisible.
const MODELS := {
	"bug": {"key": "cube-pets/animal-bee", "h": 0.65, "y": 0.42, "spin": 0.0},
	"rate_limiter": {"key": "tower-defense/enemy-ufo-a", "h": 0.55, "y": 0.86, "spin": 1.1},
	"memory_leak": {"key": "graveyard/character-zombie", "h": 0.95, "y": 0.0, "spin": 0.0},
	"merge_conflict": {"key": "mini-dungeon/character-orc", "h": 1.0, "boss_h": 1.55, "y": 0.0, "spin": 0.0},
	"scope_creep": {"key": "graveyard/character-vampire", "h": 0.95, "y": 0.0, "spin": 0.0},
	"dependency_demon": {"key": "graveyard/character-skeleton", "h": 0.95, "y": 0.0, "spin": 0.0},
	"hallucination": {"key": "graveyard/character-ghost", "h": 0.9, "y": 0.22, "spin": 0.0},
	"null_reference": {"key": "tower-defense/enemy-ufo-b", "h": 0.5, "y": 0.82, "spin": 1.4},
	"legacy_system": {"key": "graveyard/character-keeper", "h": 1.0, "y": 0.0, "spin": 0.0},
	"legacy_monolith": {"key": "mini-arena/statue", "h": 1.6, "boss_h": 2.94, "y": 0.0, "spin": 0.0},
	"infinite_context": {"key": "tower-defense/enemy-ufo-d-weapon", "h": 1.32, "boss_h": 1.32, "y": 1.05, "spin": 0.7},
	"cloud_bill": {"key": "tower-defense/enemy-ufo-c-weapon", "h": 1.3, "boss_h": 1.3, "y": 1.05, "spin": 0.9},
	"enterprise_architect": {"key": "mini-characters/character-male-a", "h": 1.21, "boss_h": 1.35, "y": 0.0, "spin": 0.0},
}
const FALLBACK_HEIGHT := 0.9

## THE SCALE CLAMP — the production defect, verbatim: "a Kenney character head
## and torso at roughly four times player scale is cropped by the frame edge".
## Three limits, applied to the height BEFORE `_visual_scale()` multiplies it,
## because what a viewer measures is the product of the two (a 2.94 statue at a
## boss's 1.55 is a four-and-a-half-metre enemy in a room whose ceiling is the
## camera):
##   * a person is a person — 0.85-1.0u, the band npc3d.gd holds its NPCs to
##   * a boss may be a monument, but never over 2.2u tall
##   * a saucer is measured ACROSS: `fit_height` scales uniformly, and the ufos
##     are half again wider than they are tall, so 1.6u of width is the limit
##     that actually governs them
## And a model whose manifest bounds are degenerate is not fitted at all: that
## division is noise, not a scale factor.
const HUMANOID_MIN := 0.85
const HUMANOID_MAX := 1.0
const BOSS_MAX := 2.2
const UFO_MAX_W := 1.6
const DEGENERATE_H := 0.2
## Kenney's characters are authored facing +Z (player3d.gd / npc3d.gd verified
## it from the rig). Every decal in this file — the strike wedge, the charge
## lane, the guard plate — is built around Godot's -Z forward and turned with
## `_yaw_of`, so the MODEL alone wears this half-turn on top of the same yaw.
## Without it every rigged enemy walks, winds up and swings with its back to
## the player. If a kit ever turns up backwards, this is the one number to flip
## (npc3d.gd's MODEL_YAW_OFFSET is the same switch on its side).
const MODEL_YAW_OFFSET := PI

## Scene paths are FIXED by the bible. load(), never preload(): enemy3d.tscn
## carries THIS script, so a compile-time preload here is a load cycle — the
## same one that once made every 2D enemy instantiate as a bare body with no AI.
const ENEMY3D_SCENE := "res://scenes/world3d/enemy3d.tscn"
const TOKEN3D_SCENE := "res://scenes/world3d/token_pickup3d.tscn"

# ------------------------------------------------------------- runtime ----

var hp: int
var target: Node3D = null
var _knockback := Vector2.ZERO            ## map px/s
var _stun_time := 0.0
var _base_speed := 0.0
var _grow := 0.0
var _special_cd := 0.0
var _telegraph := 0.0
var _boss_tele := 0.0
var _dying := false
var _home := Vector2.ZERO                 ## map px
var _home_lock := 0.12                    ## see _physics_process: late placement
var _aggroed := false
var _anim_t := 0.0
var _elite := false
var _grow_announced := false

## `_body_scale` is the 2D node scale this enemy would have had (1.0, 2.0 for a
## boss, up to 1.7 for a grown Scope Creep). It drives _reach() and the model's
## size, so the 3D fight has the 2D fight's numbers. The MODEL is scaled by a
## gentler curve — a boss at literal 2x is a 6-unit statue next to a 0.9-unit
## player, which reads as a bug rather than as a boss.
var _body_scale := 1.0
var _base_model_h := FALLBACK_HEIGHT
var _model_y := 0.0
var _model_key := ""
var _model_spin := 0.0
var _anim: KenneyAnim
var _anim_lock := 0.0
var _procedural := false                  ## no AnimationPlayer: bob + spin

## Melee wind-up state.
var _windup := 0.0
var _wind_dir := Vector2.RIGHT

## Committed dash: 0 idle, 1 telegraph, 2 dashing, 3 recovering.
var _charge_state := 0
var _charge_t := 0.0
var _charge_dir := Vector2.RIGHT
var _charge_hit := false
var _charge_cd := 0.0

## Vulnerability window: anything that over-commits is EXPOSED for a moment and
## takes extra damage. This is where the player is meant to punish.
var _vuln_t := 0.0
var _vuln_mult := 1.0

## Directional guard plate (guardians).
var _guard: Node3D
var _guard_dir := Vector2.RIGHT
var _guard_hits := 0
var _guard_max := 3
var _guard_down := 0.0
var _guard_frame := -1

## Ranged cadence, and how many friends this one may still call in.
var _lob_cd := 0.0
var _summons_left := 0
## Shots currently in the air, ticked BY HAND so a caster that dies mid-flight
## cancels its own incoming shot — no callback can fire from a freed enemy.
var _shots: Array = []

## Behaviour identity.
var _role := ROLE_BRAWLER
var _standoff := ENGAGE_DISTANCE
var _flank := 0.0
var _orbit := 1.0
var _wake_delay := 0.0
var _wake_t := 0.0

## Boss presentation.
var _boss_hud: BossHud
var _boss_anchor: Node2D
var _boss_phase := 1
var _intro_done := false
var _intro_lock := 0.0
var _boss_move := BOSS_SLAM
var _boss_recover := 0.0

## Presentation nodes (all built in _ready, all owned here).
## The HP readout and the node it hangs off — the anchor rides the body's own
## height, so a boss, a grown Scope Creep and a halved Merge Conflict each carry
## their number at their own head level without ScreenLabels needing to know.
var _hp_anchor: Node3D
var _hp_label: Label
var _alert_ring: MeshInstance3D
var _wedge: MeshInstance3D
var _lane: MeshInstance3D
var _marker: MeshInstance3D
var _marker_t := 0.0
var _marker_dur := 0.0
var _marker_r := 0.0
var _tell: MeshInstance3D
var _tell_light: OmniLight3D
var _proxy: ActorProxy

## Material state: the model's own materials, duplicated once, then written only
## when the desired tint actually changes (a per-frame material write on every
## enemy in the room is a real cost, and materials are shared resources).
var _mats: Array[StandardMaterial3D] = []
var _mat_albedo: Array[Color] = []
var _mat_emis: Array[Color] = []
var _mat_emis_e: Array[float] = []
var _mat_emis_on: Array[bool] = []
var _flash_t := 0.0
var _applied_mix := -99.0
var _applied_flash := -99.0

## Same-frame damage numbers merge into one readable total (a bolt registers on
## both the projectile's area and this enemy's hitbox in the same physics flush).
var _num_frame := -1
var _num_total := 0
var _num_crit := false

## Shared telegraph geometry — one unit-sized mesh per shape for the whole class,
## scaled per use. Building an ArrayMesh per swing would be garbage per second.
static var _mesh_wedge: ArrayMesh
static var _mesh_disc: ArrayMesh
static var _mat_tell: StandardMaterial3D
static var _mat_lane: StandardMaterial3D

## The one colour an enemy is allowed to emit (see the block where the per-type
## table used to be). Kept as a function, not inlined, so a future exception has
## exactly one place to argue for itself.
func _accent() -> Color:
	return HOSTILE

# ------------------------------------------------------------------ setup ----

func _ready() -> void:
	add_to_group("enemy")
	hp = max_hp
	if is_boss:
		max_hp *= 4
		hp = max_hp
		damage *= 2
		token_drop *= 5
		_body_scale = 2.0
	_roll_elite()
	_base_speed = speed
	_special_cd = randf_range(2.5, 4.5)
	_home = Map3D.to_map(global_position)
	_anim_t = randf() * TAU  # desync the herd so they don't bob in lockstep
	# Behaviour identity. Everything downstream reads off these four lines.
	_role = int(ROLES.get(enemy_type, ROLE_BRAWLER))
	_standoff = _standoff_for(_role)
	_flank = randf_range(-0.85, 0.85)
	_orbit = 1.0 if randf() < 0.5 else -1.0
	_lob_cd = randf_range(1.4, 3.0)
	_charge_cd = randf_range(1.6, 3.4)
	# Ragged aggro + a slightly different sight radius each, so a room does not
	# wake up as one organism. Capped at 1.10x — the builder stages enemies
	# 420px from the region spawn and 340 * 1.10 must stay under that.
	_wake_delay = randf_range(0.05, 0.75)
	_wake_t = _wake_delay
	aggro_radius *= randf_range(0.86, 1.10)
	# A boss owns its arena and wakes the instant you step into it.
	if is_boss:
		aggro_radius = 440.0
		_wake_delay = 0.0
		_wake_t = 0.0
		_summons_left = 6
		_guard_max = 6
	elif _role == ROLE_SUMMONER:
		# Exactly one friend, and a small one. The joke is the package count.
		_summons_left = 1
	if generation > 0:
		# A resolved merge conflict is two SMALLER incompatible halves.
		_body_scale *= 0.68
	_build_model()
	_build_hp_readout()
	_build_presence()
	if _role == ROLE_GUARDIAN:
		_build_guard()
	if is_boss:
		_build_boss_presence()
	attack_timer.timeout.connect(_attack)
	attack_timer.start(randf_range(1.0, 2.0))
	# The shadow proxy (§5): the UI reads actors by group and Vector2 position.
	_proxy = ActorProxy.attach(self, ["enemy"], {
		"enemy_type": enemy_type, "hp": hp, "max_hp": max_hp, "is_boss": is_boss,
	})

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

## Elites: an occasional buffed variant, visibly marked and worth more. A longer
## fight, never a bigger number. Skipped entirely in the teaching regions.
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

## The Kenney body. Floor-anchored (some packs author a negative min.y, so the
## model is lifted by its own bounds rather than trusted to sit at zero), fitted
## to the bible's height, tinted with the accent only when it is a boss or an
## elite (LAW 2: an ordinary enemy is its own flat colormap).
func _build_model() -> void:
	var spec: Dictionary = MODELS.get(enemy_type, {})
	_model_key = str(spec.get("key", ""))
	_base_model_h = float(spec.get("boss_h", spec.get("h", FALLBACK_HEIGHT))) if is_boss \
		else float(spec.get("h", FALLBACK_HEIGHT))
	_model_y = float(spec.get("y", 0.0))
	_model_spin = float(spec.get("spin", 0.0))
	_base_model_h = _clamped_height()
	var inst: Node3D = Map3D.model(_model_key) if _model_key != "" else null
	if inst == null:
		# Never invisible: a capsule in the enemy's accent still reads as a body.
		var mi := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.26
		cap.height = _base_model_h
		mi.mesh = cap
		mi.position.y = _base_model_h * 0.5
		# LAW 7: even the missing-model stand-in is a dark body, not an accent.
		mi.material_override = Map3D.matte(GameTheme.TEXT_DIM * BODY_TINT)
		model_root.add_child(mi)
	else:
		model_root.add_child(inst)
		if Map3D.height_of(_model_key) < DEGENERATE_H:
			# Unmeasurable bounds: keep the kit's own scale rather than dividing
			# a target height by nearly nothing.
			inst.scale = Vector3.ONE
			_base_model_h = FALLBACK_HEIGHT
		else:
			Map3D.fit_height(inst, _model_key, _base_model_h)
		# Floor-anchor: manifest min.y is authored, so lift by it * the fit scale.
		var b: Dictionary = Map3D.bounds(_model_key)
		var mn: Array = b.get("min", [0.0, 0.0, 0.0])
		inst.position.y = -float(mn[1]) * inst.scale.y
		# LAW 7, every body without exception — including the boss, whose v1
		# accent wash plus 0.18 emission made the one enemy the player is
		# meant to read as a shape into the brightest object in its arena.
		# A boss is bigger and its tell is brighter; that is the whole diff.
		Map3D.tint(inst, BODY_TINT)
		_anim = KenneyAnim.attach(inst)
	if _anim == null:
		_anim = KenneyAnim.new()
	_procedural = _anim.player == null
	_bind_materials(model_root)
	_apply_body_scale()
	model_root.position.y = _model_y

## Cache the model's materials so a damage flash or a wind-up tint is two float
## writes instead of a recursive duplicate-everything pass.
func _bind_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			for i in mi.mesh.get_surface_count():
				var src: Material = mi.get_surface_override_material(i)
				if src == null:
					src = mi.get_active_material(i)
				if src is StandardMaterial3D:
					var mat := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
					mi.set_surface_override_material(i, mat)
					_mats.append(mat)
					_mat_albedo.append(mat.albedo_color)
					_mat_emis.append(mat.emission)
					_mat_emis_e.append(mat.emission_energy_multiplier)
					_mat_emis_on.append(mat.emission_enabled)
	for c in node.get_children():
		_bind_materials(c)

## Model, body collider and hitbox all follow `_body_scale`, so a boss is meaty
## and a grown Scope Creep genuinely occupies more floor. The root node's own
## scale stays 1 — the health bar and the floor decals are authored in world
## units and must not inherit it.
##
## Called every frame by the two types that grow, so it early-returns unless the
## size actually moved: five transform writes per enemy per frame for a value
## that changes by 0.09/s is a cost with no picture attached.
var _applied_scale := -1.0

func _apply_body_scale() -> void:
	var k := _visual_scale()
	if absf(k - _applied_scale) < 0.005:
		return
	_applied_scale = k
	model_root.scale = Vector3.ONE * k
	# Both shapes are authored centred on their own half-height, so the offset
	# scales with them — otherwise a boss's capsule grows THROUGH the floor and
	# spends the fight being pushed out of it by the wall colliders.
	if is_instance_valid(_body_col):
		_body_col.scale = Vector3.ONE * k
		_body_col.position.y = 0.45 * k
	if is_instance_valid(_hitbox_col):
		_hitbox_col.scale = Vector3.ONE * k
		_hitbox_col.position.y = 0.5 * k
	if is_instance_valid(_hp_anchor):
		_hp_anchor.position.y = _base_model_h * k + _model_y + HP_LABEL_LIFT
	if is_instance_valid(_alert_ring):
		_alert_ring.scale = Vector3(k, 1.0, k)
	if is_instance_valid(_tell):
		_tell.position.y = _tell_y()
	if is_instance_valid(_tell_light):
		_tell_light.position.y = _tell_y()
	if is_instance_valid(_shadow):
		_shadow.scale = Vector3(k, 1.0, k)

## The model's scale curve. 2D doubled a boss outright; in 3D that is a tower.
func _visual_scale() -> float:
	return 1.0 + (_body_scale - 1.0) * 0.55

## The fitted height this body is allowed, after the three limits in the SCALE
## CLAMP block. Reads `_model_key`, `_base_model_h` and `is_boss`, all of which
## `_build_model` has set by the time it is called; returns the number to hand
## `Map3D.fit_height`, which `_visual_scale()` then multiplies.
func _clamped_height() -> float:
	var h := _base_model_h
	var k := maxf(_visual_scale(), 0.01)
	# Kenney names every rigged person `character-*` and every saucer `enemy-ufo-*`,
	# and Map3D keeps that name, so the kit itself says which limit applies.
	if _model_key.contains("character") and not is_boss:
		h = clampf(h, HUMANOID_MIN, HUMANOID_MAX)
	if _model_key.contains("ufo"):
		var b := Map3D.bounds(_model_key)
		var sz: Array = b.get("size", [])
		if sz.size() >= 3 and float(sz[0]) > 0.001 and float(sz[1]) > 0.001:
			# width == h * (size.x / size.y) * k, solved for h.
			h = minf(h, UFO_MAX_W * float(sz[1]) / (float(sz[0]) * k))
	# Whatever it is and whoever it is, it does not tower over the room.
	return minf(h, BOSS_MAX / k)

# ------------------------------------------------------------- presence ----

## The readout over a damaged enemy, so the player can read at a glance whether
## they are winning a fight. An anchor node at head height plus one screen-space
## label; the anchor is what `_apply_body_scale` moves.
func _build_hp_readout() -> void:
	_hp_anchor = Node3D.new()
	_hp_anchor.name = "HpAnchor"
	_hp_anchor.position = Vector3(0.0, _base_model_h * _visual_scale() + _model_y + HP_LABEL_LIFT, 0.0)
	add_child(_hp_anchor)
	# LAW 8's palette: a readout is TEXT_DIM. Priority 1 — a name or a prompt
	# outranks a number if the screen ever has to choose.
	_hp_label = ScreenLabels.attach(_hp_anchor, "", ScreenLabels.SMALL, GameTheme.TEXT_DIM, 0.0, 1)

## An unlit, two-sided, alpha-blended material for the floor telegraphs (the
## alert ring, the strike wedge, the slam marker). Deliberately NOT a billboard
## material: BILLBOARD_ENABLED throws a node's scale away unless
## `billboard_keep_scale` is on, and a telegraph's size IS a scale.
static func _flat_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	return m

## An overbright ADDITIVE material for the things that are meant to be LIGHT
## (a lobbed shot in flight). Unshaded on purpose — and therefore driven by an
## albedo above 1.0, because an unshaded material ignores `emission` entirely.
## Everything a telegraph draws stays under 1.0 and uses `_flat_mat`: a tell is
## a shape, not a light source (LAW 3).
static func _hot_mat(col: Color, boost: float, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.disable_receive_shadows = true
	m.albedo_color = Color(col.r * boost, col.g * boost, col.b * boost, alpha)
	return m

## The number over a damaged body: shown only while this enemy is hurt, alive,
## not a boss (bosses own the bottom-of-screen bar) and inside the fight the
## player is in. Everything else in the room stays a silhouette.
##
## Called once per frame from `_process`, because the range test is about where
## the PLAYER is, which changes without this enemy being touched.
func _sync_hp_label() -> void:
	if not is_instance_valid(_hp_label):
		return
	if hp >= max_hp or hp <= 0 or is_boss or not _player_near(HP_LABEL_RANGE):
		ScreenLabels.set_text(_hp_label, "")
		return
	ScreenLabels.set_text(_hp_label, "%d/%d" % [hp, max_hp])

## The full refresh, on damage: the readout, the boss bar and the shadow proxy
## the UI reads this enemy's health off.
func _update_hp_readout() -> void:
	_sync_hp_label()
	if _boss_hud and is_instance_valid(_boss_hud):
		_boss_hud.set_health(hp, max_hp)
	if _proxy and is_instance_valid(_proxy):
		_proxy.set_field("hp", hp)
		_proxy.set_field("max_hp", max_hp)

## Is the player inside `radius` world units of this body? (The one distance
## test the readout needs; combat measures in map pixels, but a caption's range
## is a thing you judge on screen, in metres.)
func _player_near(radius: float) -> bool:
	var player := get_tree().get_first_node_in_group("player")
	if not (player is Node3D):
		return false
	return global_position.distance_to((player as Node3D).global_position) <= radius

## LAW 3 and LAW 7: an enemy at rest is its model, and nothing else. What it
## wears is a floor ring drawn ONLY while it is COMMITTED — a flat HOSTILE
## outline in the same red as every wind-up wedge and charge lane. A telegraph
## is a shape, not a light source, so the ring is unlit and under 1.0.
##
## `_sync_alert_ring` in `_physics_process` is the single owner of its visibility.
func _build_presence() -> void:
	# A contact shadow under the feet. The moon casts a real one, but the rooms
	# are dark on purpose and a body with no grounding cue floats — which is
	# doubly true of the four enemies that actually do float.
	if is_instance_valid(_shadow):
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.cull_mode = BaseMaterial3D.CULL_DISABLED
		sm.albedo_color = Color(0.0, 0.0, 0.02, 0.42)
		var blob := "res://assets/textures/generated/player_shadow.png"
		if ResourceLoader.exists(blob):
			sm.albedo_texture = load(blob)
		_shadow.material_override = sm
	_alert_ring = MeshInstance3D.new()
	_alert_ring.name = "AlertRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.34
	torus.outer_radius = 0.40
	torus.rings = 20
	torus.ring_segments = 5
	_alert_ring.mesh = torus
	_alert_ring.material_override = _tell_mat()
	# The tube's own radius is 0.03, so the ring rides at 0.035 to keep all of it
	# above the floor (whose top is y = 0, with the builder's own decals at
	# 0.012-0.02) instead of half-buried in it.
	_alert_ring.position.y = 0.035
	_alert_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_alert_ring.visible = false
	_alert_ring.scale = Vector3(_visual_scale(), 1.0, _visual_scale())
	add_child(_alert_ring)
	# The strike wedge and the charge lane: built once at unit size, scaled per
	# use, hidden the rest of the time. Same shapes the hit tests use.
	_wedge = MeshInstance3D.new()
	_wedge.name = "StrikeWedge"
	_wedge.mesh = _wedge_mesh()
	_wedge.material_override = _tell_mat()
	_wedge.position.y = 0.03
	_wedge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wedge.visible = false
	add_child(_wedge)
	_lane = MeshInstance3D.new()
	_lane.name = "ChargeLane"
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 0.02, 1.0)
	_lane.mesh = box
	_lane.material_override = _lane_mat()
	_lane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lane.visible = false
	add_child(_lane)
	_marker = MeshInstance3D.new()
	_marker.name = "SlamMarker"
	_marker.mesh = _disc_mesh()
	_marker.material_override = _lane_mat()
	_marker.position.y = 0.025
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.visible = false
	add_child(_marker)
	_build_tell()

## THE TELL (LAW 7). Every enemy in the game wears exactly one saturated thing
## and it is this: a tiny HOSTILE core at eye height, billboarded so it reads
## from any angle, additive and just over the glow threshold so it blooms as a
## POINT. A dark silhouette with a red eye is legible at a glance in a night
## room and costs the frame nothing; the v1 answer — a range-5 OmniLight in the
## enemy's own per-type accent — cost it a hue, a wash, and the hierarchy.
##
## Elites and bosses get the same tell, larger, plus a small pool of the same
## red. They are still the only enemies carrying a light, and it is now under a
## third of what it was and reaches a body's width instead of five metres.
func _tell_y() -> float:
	return _base_model_h * _visual_scale() * 0.78 + _model_y

func _build_tell() -> void:
	var k := _visual_scale()
	_tell = MeshInstance3D.new()
	_tell.name = "Tell"
	var quad := QuadMesh.new()
	var span: float = TELL_QUAD * (1.7 if is_boss else (1.3 if _elite else 1.0))
	quad.size = Vector2(span, span)
	_tell.mesh = quad
	var tm := _hot_mat(HOSTILE, TELL_GAIN)
	tm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_tell.material_override = tm
	_tell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tell.position = Vector3(0.0, _tell_y(), 0.0)
	add_child(_tell)
	if not (_elite or is_boss):
		return
	_tell_light = OmniLight3D.new()
	_tell_light.name = "TellLight"
	_tell_light.light_color = HOSTILE
	_tell_light.light_energy = TELL_LIGHT_BOSS if is_boss else TELL_LIGHT_ELITE
	_tell_light.omni_range = TELL_RANGE_BOSS if is_boss else TELL_RANGE_ELITE
	_tell_light.omni_attenuation = 1.6
	_tell_light.shadow_enabled = false
	_tell_light.position = Vector3(0.0, _tell_y(), 0.0)
	add_child(_tell_light)
	if _elite and not is_boss:
		# The elite chevron: one small STILL marker over its head, in the same
		# red as every other tell. It does not spin and it does not pulse.
		var mark := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(0.26, 0.2, 0.05)
		mark.mesh = prism
		mark.material_override = _tell_mat()
		mark.rotation_degrees = Vector3(0.0, 0.0, 180.0)
		mark.position = Vector3(0.0, _base_model_h * k + _model_y + 0.5, 0.0)
		mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mark)

static func _tell_mat() -> StandardMaterial3D:
	if _mat_tell == null:
		_mat_tell = StandardMaterial3D.new()
		_mat_tell.albedo_color = Color(HOSTILE.r, HOSTILE.g, HOSTILE.b, 0.5)
		_mat_tell.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_tell.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat_tell.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat_tell.disable_receive_shadows = true
	return _mat_tell

static func _lane_mat() -> StandardMaterial3D:
	if _mat_lane == null:
		_mat_lane = StandardMaterial3D.new()
		_mat_lane.albedo_color = Color(HOSTILE.r, HOSTILE.g, HOSTILE.b, 0.3)
		_mat_lane.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_lane.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat_lane.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat_lane.disable_receive_shadows = true
	return _mat_lane

## A flat triangle fan on the XZ plane spanning `arc` radians, centred on the
## node's forward (-Z) axis, radius 1. Scaled at use time.
static func _wedge_mesh() -> ArrayMesh:
	if _mesh_wedge == null:
		_mesh_wedge = _fan_mesh(STRIKE_ARC, 14)
	return _mesh_wedge

static func _disc_mesh() -> ArrayMesh:
	if _mesh_disc == null:
		_mesh_disc = _fan_mesh(TAU, 28)
	return _mesh_disc

static func _fan_mesh(arc: float, segments: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	verts.append(Vector3.ZERO)
	normals.append(Vector3.UP)
	for i in segments + 1:
		var a: float = -arc * 0.5 + arc * float(i) / float(segments)
		verts.append(Vector3(sin(a), 0.0, -cos(a)))
		normals.append(Vector3.UP)
	for i in segments:
		# Wound so the face normal is +Y (up). The materials these meshes wear
		# are unshaded and two-sided, so it costs nothing either way — but a fan
		# whose geometry disagrees with its own normals is a trap for whoever
		# next puts a lit material on it.
		indices.append(0)
		indices.append(i + 2)
		indices.append(i + 1)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## The guard plate: an arc bolted to the front of a guardian. It slews toward the
## player, but slowly — walking around it is always an option, and so is breaking
## it. Purely a drawing; the mitigation lives in take_damage().
func _build_guard() -> void:
	_guard = Node3D.new()
	_guard.name = "GuardPlate"
	add_child(_guard)
	var k := _visual_scale()
	var plate := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.9 * k, 0.6 * k, 0.06)
	plate.mesh = box
	plate.material_override = _tell_mat()
	plate.position = Vector3(0.0, 0.42 * k, -0.48 * k)
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_guard.add_child(plate)
	var arc := MeshInstance3D.new()
	arc.mesh = _fan_mesh(GUARD_ARC, 12)
	arc.material_override = _lane_mat()
	arc.scale = Vector3(0.62 * k, 1.0, 0.62 * k)
	arc.position.y = 0.02
	arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_guard.add_child(arc)
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
		var want: Vector2 = _target_map() - map_pos()
		if want.length_squared() > 1.0:
			var w := want.normalized()
			var step: float = clampf(_guard_dir.angle_to(w), -GUARD_SLEW * delta, GUARD_SLEW * delta)
			_guard_dir = _guard_dir.rotated(step)
	if is_instance_valid(_guard):
		_guard.rotation.y = _yaw_of(_guard_dir)

## Enough shots into the plate and it comes off. The window that follows is the
## reward for choosing to break it instead of walking around it.
func _break_guard() -> void:
	var host := get_parent()
	var col := _accent()
	if _guard and is_instance_valid(_guard):
		Fx3D.burst(host, global_position + Map3D.dir3d(_guard_dir) * 0.5 + Vector3(0.0, 0.5, 0.0),
			col, 16, 5.0, 0.45)
		Fx3D.ring(host, global_position, col, 0.3, 1.0, 0.3)
		_guard.queue_free()
	_guard = null
	_guard_hits = 0
	_guard_down = 6.0
	_open_vuln(2.2, 1.6)
	Fx3D.glyph(host, _head_pos(0.5), "plate deprecated", GameTheme.TEXT, 15, 1.0, 0.5)
	Fx3D.add_trauma(get_tree(), 0.25)
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

func stun(duration: float) -> void:
	_stun_time = maxf(_stun_time, duration)
	_cancel_windup()
	_cancel_charge()
	# Visibly dazed, so a stunned enemy is obviously stunned and not just
	# standing there being blue.
	Fx3D.glyph(get_parent(), _head_pos(0.35), "?", GameTheme.TEXT, 22, minf(duration, 1.2), 0.3)

# --------------------------------------------------------- coordinate law ----

## This enemy's position in MAP PIXELS — the language every number in this file
## and every manager speaks (§2).
func map_pos() -> Vector2:
	return Map3D.to_map(global_position)

func _set_map_pos(px: Vector2) -> void:
	global_position = Map3D.to3d(px, global_position.y)

func _target_map() -> Vector2:
	if target == null or not is_instance_valid(target):
		return map_pos()
	return Map3D.to_map(target.global_position)

## Map-space direction -> a yaw that points a model's forward (-Z) down it.
static func _yaw_of(d: Vector2) -> float:
	if d.length_squared() < 0.000001:
		return 0.0
	return atan2(-d.x, -d.y)

## A point above this enemy's head, for floating text.
func _head_pos(extra: float = 0.0) -> Vector3:
	return global_position + Vector3(0.0, _base_model_h * _visual_scale() + _model_y + 0.35 + extra, 0.0)

# ----------------------------------------------------------- presentation ----

## Procedural liveliness, model tint and the death fade. Runs every frame,
## independent of the physics early-returns, so even a dormant or telegraphing
## enemy is never a frozen statue.
func _process(delta: float) -> void:
	_anim_t += delta
	if _flash_t > 0.0:
		_flash_t = maxf(0.0, _flash_t - delta)
	_flush_damage_number()
	if _dying:
		# Fx3D.dissolve owns the model's materials from here (it swaps in shader
		# materials), so the tint/flash pass stops writing to the ones it
		# replaced.
		_tick_death(delta)
		return
	_apply_material_state()
	_sync_hp_label()
	_tick_marker(delta)
	_drive_anim(delta)
	if _procedural and is_instance_valid(model_root):
		# UFOs and anything else the pack shipped unrigged: bob and spin, so a
		# hovering thing is never a prop stuck in the air.
		model_root.position.y = _model_y + sin(_anim_t * 1.8) * 0.07
		if _model_spin != 0.0:
			model_root.rotation.y += _model_spin * delta
	if _proxy and is_instance_valid(_proxy):
		_proxy.sync()

## One clip driver for every rigged Kenney body (§6). Locomotion is only allowed
## to speak when nothing scripted owns the rig (`_anim_lock`).
func _drive_anim(delta: float) -> void:
	if _anim == null or _anim.player == null:
		return
	if _anim_lock > 0.0:
		_anim_lock -= delta
		return
	if _charge_state == 2:
		_anim.play("sprint", 0.1, 1.5, ["run", "walk", "idle"])
	elif _stun_time > 0.0:
		_anim.play("fall", 0.15, 0.5, ["crouch", "idle", "static"])
	elif _windup > 0.0 or _boss_tele > 0.0 or _boss_recover > 0.0:
		_anim.play("crouch", 0.12, 1.0, ["idle", "static"])
	elif velocity.length() > 0.25:
		var sp: float = clampf(velocity.length() / 1.4, 0.7, 1.9)
		_anim.play("walk", 0.15, sp, ["run", "idle", "static"])
	else:
		_anim.play("idle", 0.2, 1.0, ["static", "walk"])

## Face where it is going (or, while committed, where it is about to swing).
## A spinning body (the UFOs) has no face: `_process` owns its yaw, and a lerp
## toward the player here would turn the spin into a wobble.
func _face(dir: Vector2, delta: float, rate: float = 9.0) -> void:
	if dir.length_squared() < 0.0001 or not is_instance_valid(model_root) or _model_spin != 0.0:
		return
	var want := _model_yaw_of(dir)
	model_root.rotation.y = lerp_angle(model_root.rotation.y, want, clampf(rate * delta, 0.0, 1.0))

## The yaw the MODEL wears to look down `d`: the decal yaw plus the kit's own
## forward-axis offset (see MODEL_YAW_OFFSET).
static func _model_yaw_of(d: Vector2) -> float:
	return _yaw_of(d) + MODEL_YAW_OFFSET

## The model's materials, written only when the desired look actually changes.
## Two effects share them: the white damage flash and the red wind-up tell.
func _apply_material_state() -> void:
	if _mats.is_empty():
		return
	var mix := 0.0
	if _windup > 0.0:
		mix = 1.0 - clampf(_windup / WINDUP_TIME, 0.0, 1.0)
	elif _charge_state == 1:
		mix = 1.0 - clampf(_charge_t / CHARGE_TELE, 0.0, 1.0)
	elif _boss_tele > 0.0 or _telegraph > 0.0:
		# The big-move flash: on/off at 10Hz, the same cadence the 2D sprite used.
		var t: float = _boss_tele if _boss_tele > 0.0 else _telegraph
		mix = 1.0 if fmod(t, 0.2) < 0.1 else 0.0
	elif _stun_time > 0.0:
		mix = -1.0  # dazed: desaturated, not a hue
	var flash: float = _flash_t / 0.15
	if absf(mix - _applied_mix) < 0.02 and absf(flash - _applied_flash) < 0.02:
		return
	_applied_mix = mix
	_applied_flash = flash
	for i in _mats.size():
		var mat: StandardMaterial3D = _mats[i]
		var base: Color = _mat_albedo[i]
		if mix > 0.0:
			mat.albedo_color = base.lerp(base * TELL_TINT, mix)
		elif mix < 0.0:
			var grey: float = (base.r + base.g + base.b) / 3.0
			mat.albedo_color = base.lerp(Color(grey, grey, grey, base.a), 0.55)
		else:
			mat.albedo_color = base
		if flash > 0.0:
			# The white hit flash rides ON TOP of whatever emission the model
			# already had (a boss keeps its accent glow), and is restored to that
			# exact state rather than to zero.
			mat.emission_enabled = true
			mat.emission = _mat_emis[i].lerp(Color.WHITE, 0.85)
			mat.emission_energy_multiplier = _mat_emis_e[i] + 1.6 * flash
		else:
			mat.emission_enabled = _mat_emis_on[i]
			mat.emission = _mat_emis[i]
			mat.emission_energy_multiplier = _mat_emis_e[i]

func _flash_damage() -> void:
	_flash_t = 0.15

## Same-frame hits merge into ONE damage number, emitted on the following frame
## so the total is real (a bolt registers on both the projectile's area and this
## enemy's hitbox in the same physics flush).
func _flush_damage_number() -> void:
	if _num_total <= 0 or Engine.get_physics_frames() == _num_frame:
		return
	# LAW 2: the damage number is TEXT, not gold. Gold means money in this game
	# and a gold "12" floating over a body is the same glyph the coins wear — a
	# crit gets SIZE and an overbright neutral white, not a second hue.
	Fx3D.glyph(get_parent(), _head_pos(0.1), str(_num_total),
		Color(1.9, 1.9, 1.95) if _num_crit else GameTheme.TEXT,
		34 if _num_crit else 26, 0.7, 1.1)
	if _num_crit:
		Fx3D.glyph(get_parent(), _head_pos(0.5), "CRIT", GameTheme.WHITE_HOT, 16, 0.7, 0.9)
	_num_total = 0
	_num_crit = false

func _spawn_damage_number(amount: int, is_crit: bool) -> void:
	var frame := Engine.get_physics_frames()
	if frame != _num_frame:
		_num_total = 0
		_num_crit = false
	_num_frame = frame
	_num_total += amount
	_num_crit = _num_crit or is_crit

## The alert ring's ONE owner. A tell is on while the thing it tells you about is
## happening, and off otherwise — no aggro toggle, no leash toggle, no idle
## radius. Called from the top of `_physics_process`, so it also covers the
## frames a knockback, a pause or a stun returns early from.
func _sync_alert_ring() -> void:
	if not is_instance_valid(_alert_ring):
		return
	_alert_ring.visible = not _dying and is_committed()

## The expanding floor marker a boss slam / 429 pulse is painted with: it fills
## to the exact radius of the thing that is about to happen, and the hit lands
## inside it.
func _show_marker(radius_px: float, duration: float) -> void:
	if not is_instance_valid(_marker):
		return
	_marker_r = radius_px / Map3D.PX
	_marker_dur = maxf(duration, 0.05)
	_marker_t = _marker_dur
	_marker.scale = Vector3(0.01, 1.0, 0.01)
	_marker.visible = true

func _tick_marker(delta: float) -> void:
	if not is_instance_valid(_marker) or not _marker.visible:
		return
	_marker_t = maxf(0.0, _marker_t - delta)
	var u: float = 1.0 - _marker_t / maxf(_marker_dur, 0.001)
	var r: float = maxf(_marker_r * u, 0.01)
	_marker.scale = Vector3(r, 1.0, r)
	if _marker_t <= 0.0:
		_marker.visible = false

func _hide_marker() -> void:
	if is_instance_valid(_marker):
		_marker.visible = false
		_marker_t = 0.0

# ----------------------------------------------------------------- brain ----

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
	_hide_marker()
	if is_instance_valid(_alert_ring):
		_alert_ring.visible = false
	if _home != Vector2.ZERO:
		_set_map_pos(_home)

func _physics_process(delta: float) -> void:
	# The builder may place this body either before or after add_child, so the
	# home post is re-read for the first tenth of a second. After that it is
	# fixed: `reset_to_home` teleports to it.
	if _home_lock > 0.0 and not _aggroed:
		_home_lock -= delta
		_home = map_pos()
	_sync_alert_ring()
	# A corpse stops fighting. (`_die` runs deferred, so the body would otherwise
	# keep chasing — and keep rescaling itself, if it is a Scope Creep — for the
	# 0.45s it spends leaving.)
	if _dying:
		velocity = Vector3.ZERO
		return
	# Lobbed shots live on this enemy's own clock (deliberately not on a tween),
	# so they keep travelling through knockback and stun, and stop dead when the
	# room does.
	if not _combat_paused():
		_tick_shots(delta)
		_tick_vuln(delta)
	# Knockback always resolves, even while combat is paused, so the player can
	# always shove enemies away.
	if _knockback.length() > 5.0:
		velocity = _to_world(_knockback)
		move_and_slide()
		_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
		return
	if _combat_paused():
		velocity = Vector3.ZERO
		_cancel_windup()
		_cancel_charge()
		return
	# Stunned (e.g. by Rubber Duck): frozen but still shoveable via knockback.
	if _stun_time > 0.0:
		_stun_time -= delta
		velocity = Vector3.ZERO
		_cancel_windup()
		return
	if target == null or not is_instance_valid(target):
		target = get_tree().get_first_node_in_group("player") as Node3D
		return
	if _intro_lock > 0.0:
		_intro_lock -= delta
	var here := map_pos()
	var to_player := _target_map() - here
	var dist := to_player.length()
	if is_boss and not _intro_done and dist < BOSS_INTRO_RANGE and _on_camera():
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
	# A telegraphing or recovering boss PLANTS: the slam marker is painted where
	# the wind-up started, so a boss that kept walking during its own telegraph
	# would be drawing the player a kill zone in the wrong place.
	if is_boss and (_boss_tele > 0.0 or _boss_recover > 0.0):
		velocity = Vector3.ZERO
		_face(to_player, delta, 4.0)
		return

	# Aggro gating: wake when the player comes near, sleep (return home) if they
	# leave. The wake timer staggers the pack so a room notices you raggedly.
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
		var to_home := _home - here
		if to_home.length() > 12.0:
			desired = to_home.normalized() * speed * 0.4
	desired += _separation() * speed
	velocity = _to_world(desired)
	move_and_slide()
	_face(desired if desired.length() > 6.0 else to_player, delta)

## Map px/s -> world units/s. The ONE place the steering leaves map space.
static func _to_world(px_per_s: Vector2) -> Vector3:
	return Vector3(px_per_s.x, 0.0, px_per_s.y) / Map3D.PX

## Where this enemy wants to be, by role. Nobody walks the straight line to the
## player: brawlers fan out along their own approach arc, skirmishers pulse in
## and out, artillery holds its range, and anyone sitting in the pocket strafes
## rather than standing. A pack breathes instead of queueing.
func _role_steering(to_player: Vector2, dist: float) -> Vector2:
	var dir: Vector2 = to_player.normalized() if dist > 0.001 else Vector2.RIGHT
	var want := _standoff
	if _role == ROLE_SKIRMISHER:
		# Dart cycle: press, then think better of it.
		want = _standoff + (58.0 if sin(_anim_t * 1.3) > 0.35 else 0.0)
	elif _role == ROLE_CHARGER and not is_boss and _charge_state == 0 and _charge_cd <= 0.0:
		# A charger with a run off cooldown backs up to a distance it can
		# actually run FROM, or the lane telegraph is never drawn outside a boss
		# fight. Bosses are excluded: their move choice comes from _boss_moves().
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
	Fx3D.glyph(host, _head_pos(), "!", HOSTILE, 22, 0.6, 0.7)
	if _elite:
		# Say why this one is different BEFORE the player wastes a clip on it.
		Fx3D.glyph(host, _head_pos(0.45),
			"ELITE · %s" % ComedyLines.pick("enemy_elite", ELITE_TAGS),
			GameTheme.TEXT, 14, 1.1, 0.9)
	if _anim and _anim.has("jump"):
		_anim.play("jump", 0.05, 1.4)
		_anim_lock = 0.3

## Back to the explore track, but only when NOTHING in the room is still
## chasing — one enemy dropping its leash must not calm the music mid-brawl.
func _music_calm_check() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		# The group also holds every enemy's SHADOW PROXY (§5), which is a Node2D
		# with none of this state. Ask only the bodies.
		if e != self and e is Enemy3D and is_instance_valid(e) and (e as Enemy3D)._aggroed:
			return
	AudioManager.play_music("explore_music")

# ------------------------------------------------------- melee telegraph ----

## Commit to a swing: plant, coil, and paint the wedge that is about to hurt.
## Returns false when there is nothing to swing at, so the caller can put the
## attack clock back on the wall.
func _begin_windup() -> bool:
	if _dying or target == null or not is_instance_valid(target):
		return false
	_windup = WINDUP_TIME
	var d: Vector2 = _target_map() - map_pos()
	_wind_dir = d.normalized() if d.length_squared() > 0.0001 else Vector2.RIGHT
	if is_instance_valid(model_root) and _model_spin == 0.0:
		model_root.rotation.y = _model_yaw_of(_wind_dir)
	# The wedge on the floor IS the hitbox: same reach, same 1.5 rad arc.
	if is_instance_valid(_wedge):
		var r: float = (_reach() + 14.0) / Map3D.PX
		_wedge.rotation.y = _yaw_of(_wind_dir)
		_wedge.scale = Vector3(r, 1.0, r)
		_wedge.visible = true
	# The swing itself, timed so the clip's contact frame lands on the strike.
	if _anim and _anim.has("attack-melee-right"):
		var clip := _anim.player.get_animation("attack-melee-right")
		var sp: float = 1.0
		if clip and clip.length > 0.05:
			sp = clip.length / (WINDUP_TIME + 0.18)
		_anim.play("attack-melee-right", 0.06, sp)
		_anim_lock = WINDUP_TIME + 0.18
	return true

func _tick_windup(delta: float) -> void:
	velocity = Vector3.ZERO
	_windup -= delta
	if _windup <= 0.0:
		_strike()

## Clear the coil and the floor wedge. `resume` restarts the attack clock — a
## cancelled wind-up (stun, knockback, pause) must never silently retire an
## enemy from combat. Early-returns when nothing was winding up, so it can be
## called every frame.
func _cancel_windup(resume: bool = true) -> void:
	var was_winding: bool = _windup > 0.0
	if is_instance_valid(_wedge):
		_wedge.visible = false
	_windup = 0.0
	if not was_winding:
		return
	_anim_lock = 0.0
	if resume and is_instance_valid(attack_timer) and attack_timer.is_stopped():
		attack_timer.start(randf_range(0.9, 1.6))

## The swing lands — but ONLY inside the wedge that was painted on the floor.
## Distance alone used to be enough, which meant a telegraph you read correctly
## and sidestepped still hit you. Stepping out of the arc is a real dodge, and a
## swing that finds nothing leaves the swinger briefly open.
func _strike() -> void:
	_cancel_windup(false)
	if _dying:
		return
	# Let the swing follow through: `_cancel_windup` handed the rig back, and the
	# attack clip still has its recovery frames to play.
	if _anim and _anim.current == "attack-melee-right":
		_anim_lock = 0.18
	var connected := false
	var impact := global_position + Map3D.dir3d(_wind_dir) * 0.4 + Vector3(0.0, 0.5, 0.0)
	if target and is_instance_valid(target):
		var to_t: Vector2 = _target_map() - map_pos()
		var d := to_t.length()
		# Point blank always connects — the arc test is about sidestepping, and
		# standing directly on top of something is not a sidestep.
		if d <= _reach() and (d < 14.0 or to_t.normalized().dot(_wind_dir) >= STRIKE_ARC_DOT):
			connected = true
			if target.has_method("take_damage"):
				target.take_damage(damage, enemy_type)
	var host := get_parent()
	Fx3D.ring(host, impact, HOSTILE, 0.1, 0.7, 0.2)
	if connected:
		Fx3D.burst(host, impact, Color(2.4, 0.8, 0.9), 7, 3.0, 0.35)
		Fx3D.add_trauma(get_tree(), 0.12)
	else:
		# A miss is information: the recovery frames are yours.
		Fx3D.glyph(host, _head_pos(), "no-op", GameTheme.TEXT_DIM, 12, 0.5, 0.5)
		_open_vuln(0.55, 1.35)
	if connected and _role == ROLE_SKIRMISHER:
		# Hit and run: a skirmisher never stands in the place it just struck.
		_knockback = -_wind_dir * 240.0
	if is_instance_valid(attack_timer):
		attack_timer.start(randf_range(1.2, 2.5))

## How far this one's swing actually reaches. Bigger things reach further — a
## fully-grown Scope Creep can hit you from where it could not five seconds ago
## — and the wedge painted on the floor is drawn from the same number, so the
## picture never lies about the hitbox.
func _reach() -> float:
	return STRIKE_RANGE * (1.0 + (maxf(_body_scale, 0.5) - 1.0) * 0.5)

## An enemy commits from slightly inside its own reach, so the wedge it paints
## is a threat rather than an announcement it has already missed.
func _start_reach() -> float:
	return _reach() - (STRIKE_RANGE - STRIKE_START_RANGE)

## Is this enemy currently locked into something the player must react to?
## Used by the pack to take turns; public so siblings (and BossHud) can ask.
func is_committed() -> bool:
	return _windup > 0.0 or _charge_state == 1 or _charge_state == 2 \
		or _boss_tele > 0.0 or _telegraph > 0.0

## Fewer than MAX_COMMITTED others mid-attack? Bosses never wait their turn.
func _attack_slot_free() -> bool:
	if is_boss or not is_inside_tree():
		return true
	var busy := 0
	for other in get_tree().get_nodes_in_group("enemy"):
		if other == self or not (other is Enemy3D) or not is_instance_valid(other):
			continue
		if (other as Enemy3D).is_committed():
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
			_body_scale = (2.0 if is_boss else 1.0) * (1.0 + _grow * 0.7)
			speed = _base_speed * (1.0 + _grow * 0.9)
			_apply_body_scale()
			if _grow >= 1.0 and not _grow_announced:
				_grow_announced = true
				Fx3D.glyph(get_parent(), _head_pos(0.4), "v2 · out of scope for v1",
					GameTheme.TEXT_DIM, 14, 1.2, 0.9)
		"memory_leak":
			# Slowly bloats as it leaks.
			_grow = minf(_grow + delta * 0.05, 0.6)
			_body_scale = (2.0 if is_boss else 1.0) * (1.0 + _grow)
			_apply_body_scale()
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
	var dist := map_pos().distance_to(_target_map())
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
	var d: Vector2 = _target_map() - map_pos()
	if d.length_squared() < 1.0:
		return
	_cancel_windup(false)
	_charge_dir = d.normalized()
	_charge_state = 1
	_charge_t = CHARGE_TELE
	_charge_hit = false
	var run_px: float = CHARGE_SPEED * CHARGE_TIME + 40.0
	if is_instance_valid(_lane):
		# The lane is drawn from the body to the far end of the run: everything
		# inside it is about to be somewhere a 560px/s body is.
		var len_u: float = run_px / Map3D.PX
		_lane.rotation.y = _yaw_of(_charge_dir)
		_lane.scale = Vector3(0.7 * _visual_scale(), 1.0, len_u)
		_lane.position = Vector3(0.0, 0.03, 0.0) + Map3D.dir3d(_charge_dir) * (len_u * 0.5)
		_lane.visible = true
	if is_instance_valid(model_root) and _model_spin == 0.0:
		model_root.rotation.y = _model_yaw_of(_charge_dir)
	var host := get_parent()
	Fx3D.beam(host, global_position + Vector3(0.0, 0.2, 0.0),
		global_position + Map3D.dir3d(_charge_dir) * (run_px / Map3D.PX) + Vector3(0.0, 0.2, 0.0),
		HOSTILE, 0.1, CHARGE_TELE)
	Fx3D.glyph(host, _head_pos(), str(TELLS.get(enemy_type, "committing")),
		HOSTILE, 15, CHARGE_TELE + 0.2, 0.5)
	AudioManager.play_sfx("ability")

func _tick_charge(delta: float) -> void:
	_charge_t -= delta
	match _charge_state:
		1:
			velocity = Vector3.ZERO
			if _charge_t <= 0.0:
				_charge_state = 2
				_charge_t = CHARGE_TIME
				# The lane comes off the instant the run starts: it is a child of
				# this body, so leaving it up would drag the painted kill zone
				# along in front of the dash — a marker that lies about where the
				# hit is, which is the one thing a telegraph may never do. The
				# body IS the tell for the 0.36s the run lasts.
				if is_instance_valid(_lane):
					_lane.visible = false
				Fx3D.burst(get_parent(), global_position + Vector3(0.0, 0.3, 0.0),
					_accent(), 8, 4.0, 0.25)
		2:
			velocity = _to_world(_charge_dir * CHARGE_SPEED)
			move_and_slide()
			if Engine.get_physics_frames() % 3 == 0:
				Fx3D.afterimage(get_parent(), model_root, Color(1.6, 1.1, 1.1, 0.5), 0.22)
			_charge_contact()
			if get_slide_collision_count() > 0:
				_end_charge(true)
			elif _charge_t <= 0.0:
				_end_charge(false)
		_:
			velocity = Vector3.ZERO
			if _charge_t <= 0.0:
				_charge_state = 0
				_charge_cd = randf_range(3.4, 5.2)

## One hit per dash, at contact range. It shoves rather than pins.
func _charge_contact() -> void:
	if _charge_hit or target == null or not is_instance_valid(target):
		return
	if map_pos().distance_to(_target_map()) > 42.0:
		return
	_charge_hit = true
	if target.has_method("take_damage"):
		target.take_damage(damage, enemy_type)
	if target.has_method("apply_external_knockback"):
		target.apply_external_knockback(_charge_dir * 360.0)
	Fx3D.ring(get_parent(), target.global_position + Vector3(0.0, 0.3, 0.0), HOSTILE, 0.2, 1.0, 0.22)
	Fx3D.add_trauma(get_tree(), 0.2)

## Over-run. Running into a wall costs it more, because that is funnier and
## because a room's geometry should be a weapon the player can aim things into.
func _end_charge(hit_wall: bool) -> void:
	_charge_state = 3
	_charge_t = CHARGE_RECOVER * (1.35 if hit_wall else 1.0)
	_open_vuln(_charge_t, 1.7)
	velocity = Vector3.ZERO
	if is_instance_valid(_lane):
		_lane.visible = false
	var host := get_parent()
	if hit_wall:
		Fx3D.shockwave(host, global_position, HOSTILE, 2.0, 0.35)
		Fx3D.add_trauma(get_tree(), 0.22)
	Fx3D.glyph(host, _head_pos(), "reverted" if hit_wall else "over-committed",
		GameTheme.TEXT, 14, 0.9, 0.8)
	Fx3D.glyph(host, _head_pos(0.35), "?", GameTheme.TEXT, 18, minf(_charge_t, 1.0), 0.3)

## Tear down a dash at any stage and put it back on cooldown. Safe to call every
## frame and safe to call on an enemy that was never a charger.
func _cancel_charge() -> void:
	if _charge_state == 0:
		return
	_charge_state = 0
	_charge_t = 0.0
	_charge_hit = false
	_charge_cd = maxf(_charge_cd, 1.2)
	if is_instance_valid(_lane):
		_lane.visible = false

# ------------------------------------------------------------ lobbed shots ----

## A telegraphed lobbed shot. The ground marker fills for the WHOLE flight and
## the hit lands exactly inside it, so "why did that hit me" always has the same
## answer: you were still standing in the circle when it finished filling.
## `real = false` draws a decoy — the hallucination's other, equally confident
## answer — in dead grey, so it is always distinguishable at a glance.
##
## In 3D the arc is a real arc: the shot climbs, and the shadow it is heading
## for is the circle on the floor.
func _lob(at_px: Vector2, radius: float, dmg: int, flight: float, tag: String = "", real: bool = true) -> void:
	var host := get_parent()
	if host == null or not host.is_inside_tree() or _dying:
		return
	# LAW 7: an incoming shot is HOSTILE red, like every other tell in this
	# file. It used to be the caster's DEATH_ACCENT, so "that is about to
	# hurt" was acid green in one room and cyan in the next; the grey the
	# hallucination's fakes already use is what carries "this one is not
	# real", and against one red that reads harder than it ever did.
	var col: Color = HOSTILE if real else GameTheme.TEXT_DIM
	var at := Map3D.to3d(at_px, 0.03)
	# The marker: a disc that fills to the blast radius over the flight.
	var mk := MeshInstance3D.new()
	mk.mesh = _disc_mesh()
	mk.material_override = _lane_mat() if real else _flat_mat(Color(0.49, 0.55, 0.69, 0.22))
	mk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mk.scale = Vector3(0.01, 1.0, 0.01)
	host.add_child(mk)
	mk.global_position = at
	if not tag.is_empty():
		Fx3D.glyph(host, at + Vector3(0.0, 0.4, 0.0), tag, col, 12, flight, 0.3)
	# The shot itself: a hot little core with its own light, so it lights the
	# floor it is about to land on.
	var shot := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.13
	sphere.height = 0.26
	sphere.radial_segments = 10
	sphere.rings = 6
	shot.mesh = sphere
	# Overbright ADDITIVE, not "unshaded + emission": an unshaded material writes
	# ALBEDO straight out and ignores emission, so that combination would put a
	# flat grey ball in the air instead of a hot one. Above 1.0 the albedo itself
	# is what the Environment's glow picks up.
	shot.material_override = _hot_mat(col, 2.2 if real else 0.7, 0.95 if real else 0.45)
	shot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(shot)
	var from := global_position + Vector3(0.0, _base_model_h * _visual_scale() * 0.6 + _model_y, 0.0)
	shot.global_position = from
	# Only the first few shots of a barrage carry a light: §9 budgets 40 omnis a
	# region, and a phase-4 boss can have six of these in the air at once.
	if real and _shots.size() < 3:
		var lamp := OmniLight3D.new()
		lamp.light_color = col
		# A shot in flight is combat, and v2 lets combat be loud — but a lobbed
		# arc is not a lamp. It lights the tile it is about to land on.
		lamp.light_energy = 1.2
		lamp.omni_range = 2.4
		lamp.omni_attenuation = 1.6
		lamp.shadow_enabled = false
		shot.add_child(lamp)
	var apex: Vector3 = from.lerp(at, 0.5) + Vector3(0.0, maxf(1.1, from.distance_to(at) * 0.42), 0.0)
	_shots.append({
		"node": shot, "marker": mk, "from": from, "apex": apex, "at": at,
		"t": 0.0, "dur": maxf(flight, 0.1), "radius": radius, "at_px": at_px,
		"dmg": dmg, "col": col, "real": real,
	})

## Quadratic arc, stepped by hand. No tweens: a caster that dies mid-flight
## cancels its own incoming shot, and nothing can fire from a freed enemy.
func _tick_shots(delta: float) -> void:
	if _shots.is_empty():
		return
	var i := _shots.size() - 1
	while i >= 0:
		var s: Dictionary = _shots[i]
		s["t"] = float(s["t"]) + delta
		var u: float = clampf(float(s["t"]) / float(s["dur"]), 0.0, 1.0)
		var node: Node3D = s["node"]
		if is_instance_valid(node):
			# Typed locals, not `as Vector3` on the dictionary values: `as` is an
			# object cast, and the arc must not depend on how it treats built-ins.
			var p_from: Vector3 = s["from"]
			var p_apex: Vector3 = s["apex"]
			var p_at: Vector3 = s["at"]
			var a: Vector3 = p_from.lerp(p_apex, u)
			var b: Vector3 = p_apex.lerp(p_at, u)
			node.global_position = a.lerp(b, u)
			node.rotation.y += delta * 6.0
		var mk: Node3D = s["marker"]
		if is_instance_valid(mk):
			var r: float = maxf(float(s["radius"]) / Map3D.PX * u, 0.01)
			mk.scale = Vector3(r, 1.0, r)
		if u >= 1.0:
			_land_shot(s)
			_shots.remove_at(i)
		i -= 1

func _land_shot(s: Dictionary) -> void:
	var node: Node3D = s["node"]
	if is_instance_valid(node):
		node.queue_free()
	var mk: Node3D = s["marker"]
	if is_instance_valid(mk):
		mk.queue_free()
	var host := get_parent()
	if host == null or not host.is_inside_tree():
		return
	var at: Vector3 = s["at"]
	var col: Color = s["col"]
	var radius: float = float(s["radius"])
	if not bool(s["real"]):
		# It was never sourced. It was, however, extremely confident.
		Fx3D.glyph(host, at + Vector3(0.0, 0.3, 0.0), "[citation needed]",
			GameTheme.TEXT_DIM, 12, 0.8, 0.7)
		return
	Fx3D.shockwave(host, at, col, radius / Map3D.PX, 0.34)
	Fx3D.burst(host, at, Color(col.r * 2.0, col.g * 2.0, col.b * 2.0), 10, 4.0, 0.5)
	Fx3D.flash(host, at + Vector3(0.0, 0.3, 0.0), col, 4.0, 0.22)
	if _combat_paused() or target == null or not is_instance_valid(target):
		return
	var at_px: Vector2 = s["at_px"]
	var miss: float = _target_map().distance_to(at_px)
	# Only shake the camera for impacts the player could actually feel.
	if miss < 220.0:
		Fx3D.add_trauma(get_tree(), 0.12)
	if miss <= radius and target.has_method("take_damage"):
		target.take_damage(int(s["dmg"]), enemy_type)

## Killing the caster cancels its incoming shot. Also the only teardown path, so
## nothing in flight can outlive the room.
func _cancel_shots() -> void:
	for entry in _shots:
		var s: Dictionary = entry
		var node: Node3D = s["node"]
		if is_instance_valid(node):
			node.queue_free()
		var mk: Node3D = s["marker"]
		if mk != null and is_instance_valid(mk):
			mk.queue_free()
	_shots.clear()

## What each artillery type actually throws. All of them aim at where you ARE:
## a lob is a question about whether you intend to keep standing there.
func _fire_ranged() -> void:
	if target == null or not is_instance_valid(target):
		return
	var at: Vector2 = _target_map()
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
	Fx3D.glyph(host, _head_pos(), "peer dep missing", GameTheme.TEXT_DIM, 14, 1.0, 0.8)
	Fx3D.ring(host, e.global_position, GameTheme.TEXT_DIM, 0.05, 0.7, 0.3)
	AudioManager.play_sfx("ability")

## Blink one step sideways, leaving the shape of where it was. Not an escape —
## it stays inside the fight, it just stops being where you aimed.
func _dereference() -> void:
	var host := get_parent()
	var from := global_position
	var toward := Vector2.RIGHT
	if target and is_instance_valid(target):
		var d: Vector2 = _target_map() - map_pos()
		if d.length_squared() > 0.0001:
			toward = d.normalized()
	# Sidestep around the player rather than a random jump, so it never blinks
	# itself into scenery on the far side of the room.
	_set_map_pos(map_pos() + toward.orthogonal() * (54.0 * _orbit) + toward * 18.0)
	Fx3D.afterimage(host, model_root, Color(1.0, 1.0, 1.4, 0.6), 0.35)
	Fx3D.glyph(host, from + Vector3(0.0, 0.6, 0.0), "undefined", GameTheme.TEXT_DIM, 12, 0.5, 0.5)

# ------------------------------------------------------------ boss rig ----

## Bosses carry their own presentation layer: the entrance card, the bottom
## health bar, phase banners and the death stamp all live in BossHud.
##
## BossHud captures `get_parent() as Node2D` as its host and asks it
## `is_committed()`, so it is mounted on a hidden 2D ANCHOR that tracks this body
## in map pixels rather than on the body itself — a CanvasLayer parented to a
## CharacterBody3D would give the layer a null host and silently disarm its
## engagement gate. The anchor lives under the proxy root with the shadow
## proxies, for the same reason they do.
func _build_boss_presence() -> void:
	_boss_anchor = BossAnchor.new()
	_boss_anchor.name = "BossAnchor_" + name
	(_boss_anchor as BossAnchor).enemy = self
	_boss_anchor.visible = false
	var root: Node = get_tree().get_first_node_in_group(ActorProxy.ROOT_GROUP)
	if root == null:
		root = get_parent()
	if root == null:
		return
	root.add_child(_boss_anchor)
	_boss_anchor.global_position = map_pos()
	# The anchor lives OUTSIDE this body's subtree, so it must be told when the
	# body goes. On death `_boss_death_spectacle` has already handed the layer
	# to the scene and freed the anchor (leaving this null); the only way to get
	# here with it still alive is a region rebuild freeing the boss under it —
	# and then the anchor's exit is what tells BossHud its host is gone, which is
	# exactly the "stale card in a room that no longer exists" case it vanishes on.
	var anchor := _boss_anchor
	tree_exiting.connect(func() -> void:
		if is_instance_valid(anchor):
			anchor.queue_free())
	_boss_hud = BossHud.new()
	_boss_hud.name = "BossHud"
	_boss_anchor.add_child(_boss_hud)
	_boss_hud.setup(enemy_type, _accent())
	_boss_hud.set_health(hp, max_hp)

## The 2D shim BossHud mounts on: a Node2D that stands where the boss stands (in
## map pixels) and forwards the one question the HUD asks a host.
class BossAnchor extends Node2D:
	var enemy: Node = null

	func _process(_delta: float) -> void:
		if is_instance_valid(enemy) and enemy.has_method("map_pos"):
			global_position = enemy.call("map_pos")

	func is_committed() -> bool:
		return is_instance_valid(enemy) and enemy.has_method("is_committed") \
			and bool(enemy.call("is_committed"))

## Is this body inside the frame the player is actually looking at? An entrance
## is a thing you are supposed to WATCH — the 2D version detonated its shockwave
## under the HUD around a body that was off the bottom of the arrival frame for
## several rounds. `take_damage()` still triggers the intro unconditionally, so
## sniping a boss from beyond the trigger is unchanged.
func _on_camera() -> bool:
	var vp := get_viewport()
	if vp == null:
		return true
	var cam := vp.get_camera_3d()
	if cam == null:
		return true
	return cam.is_position_in_frustum(global_position + Vector3(0.0, 0.5, 0.0))

func _play_boss_intro() -> void:
	if _intro_done:
		return
	_intro_done = true
	_intro_lock = 2.2
	if _boss_hud and is_instance_valid(_boss_hud):
		_boss_hud.play_entrance()
	# LAW 2 and LAW 7: an entrance is a HOSTILE tell, not the boss's own hue.
	Fx3D.shockwave(get_parent(), global_position, HOSTILE, 3.2, 0.55)
	if _anim and _anim.has("emote-no"):
		_anim.play("emote-no", 0.1, 0.8)
		_anim_lock = 0.7
	Fx3D.add_trauma(get_tree(), 0.5)
	Fx3D.punch_zoom(get_tree(), 0.07)
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
	_hide_marker()
	if _role == ROLE_GUARDIAN and not _guard_up():
		_guard_down = 0.0
		_build_guard()
	var host := get_parent()
	var col := _accent()
	Fx3D.shockwave(host, global_position, col, 3.2, 0.45)
	var shards: Array = DEATH_SHARDS.get(enemy_type, ["escalated"])
	Fx3D.glyph(host, _head_pos(0.5), str(shards[randi() % shards.size()]), col, 14, 1.1, 1.0)
	_flash_damage()
	Fx3D.add_trauma(get_tree(), 0.4)
	AudioManager.play_sfx("ability")

## Which patterns a boss may use, by phase. Each phase ADDS a move rather than
## only speeding up the last one, so phase 4 does not play like a faster phase 1.
## Artillery bosses lead with the barrage from the first phase — a $700 cloud
## bill has never walked up to anybody.
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
## THERE. The recovery is not a gap in the design, it is the design — every boss
## commitment ends in a window the player is meant to punish.
func _tick_boss(delta: float) -> void:
	if _intro_lock > 0.0:
		return
	if _charge_state != 0:
		return  # the dash state machine owns this boss right now
	if _boss_recover > 0.0:
		_boss_recover -= delta
		return
	if _boss_tele > 0.0:
		_boss_tele -= delta
		if _boss_tele <= 0.0:
			_boss_execute()
		return
	_special_cd -= delta
	if _special_cd > 0.0 or target == null or not is_instance_valid(target):
		return
	var dist := map_pos().distance_to(_target_map())
	# ...and never before its own entrance.
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

## Paint the move before it happens. No hidden information, ever — and in
## HOSTILE, like every other telegraph the game draws, so a player who has learnt
## that red means "move" does not have to re-learn it per boss.
func _telegraph_boss_move() -> void:
	var host := get_parent()
	match _boss_move:
		BOSS_BARRAGE:
			Fx3D.glyph(host, _head_pos(0.5), str(TELLS.get(enemy_type, "incoming")),
				HOSTILE, 16, _boss_tele + 0.2, 0.5)
			Fx3D.ring(host, global_position, HOSTILE, 0.3, 2.4, _boss_tele)
			_show_marker(150.0, _boss_tele)
		BOSS_SIGNATURE:
			Fx3D.glyph(host, _head_pos(0.5), _signature_tell(), HOSTILE, 16, _boss_tele + 0.3, 0.5)
			Fx3D.ring(host, global_position, HOSTILE, 3.4, 0.5, _boss_tele)
			_show_marker(220.0, _boss_tele)
		_:
			# The slam reaches 260px; so does the marker.
			_show_marker(260.0, _boss_tele)

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
	var here: Vector2 = _target_map()
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
				# Generation 1: these ones do not get to split again. Written
				# AFTER the add is built, exactly as the 2D boss does it, so they
				# arrive full-size — only a resolved conflict's halves are the
				# small ones (`generation` is read by `_ready`, so passing it in
				# would shrink these too).
				var e := _spawn_add("merge_conflict", 18, maxi(4, int(damage * 0.4)), 3)
				if e:
					e.set("generation", 1)
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
	Fx3D.glyph(get_parent(), _head_pos(0.6), "EXPOSED", GameTheme.TEXT, 17, minf(seconds, 1.0), 0.7)

func _boss_slam() -> void:
	_hide_marker()
	if target and is_instance_valid(target):
		var away: Vector2 = _target_map() - map_pos()
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
	var host := get_parent()
	if host == null:
		return
	Fx3D.shockwave(host, global_position, HOSTILE, 260.0 / Map3D.PX, 0.4)
	Fx3D.burst(host, global_position + Vector3(0.0, 0.15, 0.0), Color(0.8, 0.5, 0.55), 20, 5.0, 0.5)
	Fx3D.add_trauma(get_tree(), 0.35)
	Fx3D.punch_zoom(get_tree(), 0.03)

func _summon(type: String) -> void:
	var e := _spawn_add(type, 16)
	if e == null:
		return
	# Adds arrive through a rift, not by appearing out of nothing.
	var host := get_parent()
	Fx3D.ring(host, e.global_position, GameTheme.TEXT_DIM, 0.05, 0.8, 0.3)
	Fx3D.glyph(host, e.global_position + Vector3(0.0, 1.0, 0.0), "added to the invite",
		GameTheme.TEXT_DIM, 12, 0.9, 0.8)

## Shared add-spawning. `dmg` / `drop` below zero leave the scene defaults alone.
## Returns null when this enemy has no tree to spawn into (or the sibling track
## has not landed enemy3d.tscn yet — every cross-track scene load is guarded).
func _spawn_add(type: String, hp_val: int, dmg: int = -1, drop: int = -1, gen: int = 0) -> Node3D:
	var host := get_parent()
	if host == null or not host.is_inside_tree():
		return null
	if not ResourceLoader.exists(ENEMY3D_SCENE):
		return null
	var scene: PackedScene = load(ENEMY3D_SCENE)
	if scene == null:
		return null
	var e := scene.instantiate() as Node3D
	if e == null:
		return null
	# Everything the add's own `_ready` reads is written BEFORE add_child: adding
	# a node runs its _ready immediately, and `generation` in particular decides
	# how big the body it builds is.
	e.set("enemy_type", type)
	e.set("max_hp", hp_val)
	if dmg >= 0:
		e.set("damage", dmg)
	if drop >= 0:
		e.set("token_drop", drop)
	if gen > 0:
		e.set("generation", gen)
	# Adds arrive on the far side of the summoner, never on top of the player. A
	# body that materialises inside your hitbox is a free hit, not a threat.
	var offset := Vector2(randf_range(-30, 30), randf_range(-30, 30))
	if target and is_instance_valid(target):
		var back: Vector2 = map_pos() - _target_map()
		if back.length_squared() > 1.0:
			offset += back.normalized() * randf_range(40.0, 62.0)
	var at := Map3D.to3d(map_pos() + offset, 0.0)
	# Placed BEFORE add_child (the add's _ready records its home post from where
	# it stands) and confirmed in world space after, in case the host that
	# received it is not itself at the origin.
	e.position = at
	host.add_child(e)
	e.global_position = at
	return e

func _tick_rate_limiter(delta: float) -> void:
	if _telegraph > 0.0:
		# Flash while winding up the 429 pulse.
		_telegraph -= delta
		if _telegraph <= 0.0:
			_rate_pulse()
		return
	_special_cd -= delta
	if _special_cd <= 0.0 and target and is_instance_valid(target) \
			and map_pos().distance_to(_target_map()) < 280.0:
		_telegraph = 0.6
		_special_cd = randf_range(3.5, 5.5)
		# The pulse reaches 240px. So does the ring you are being shown.
		_show_marker(240.0, 0.6)
		Fx3D.glyph(get_parent(), _head_pos(), "429", HOSTILE, 20, 0.7, 0.5)

## 429: shove the player back (temporary, decaying — never a trap).
func _rate_pulse() -> void:
	_hide_marker()
	if target and is_instance_valid(target) and target.has_method("apply_external_knockback"):
		var away: Vector2 = _target_map() - map_pos()
		if away.length() < 240.0 and away.length_squared() > 0.0001:
			target.apply_external_knockback(away.normalized() * 430.0)
	Fx3D.shockwave(get_parent(), global_position, HOSTILE, 240.0 / Map3D.PX, 0.36)
	Fx3D.add_trauma(get_tree(), 0.2)
	AudioManager.play_sfx("ability")

func _blink() -> void:
	var host := get_parent()
	var from := global_position
	var ang := randf() * TAU
	_set_map_pos(map_pos() + Vector2(cos(ang), sin(ang)) * 74.0)
	# It was never there. It is very confident it was never there.
	Fx3D.afterimage(host, model_root, Color(1.1, 1.15, 1.3, 0.55), 0.35)
	Fx3D.ring(host, from, GameTheme.TEXT_DIM, 0.05, 0.55, 0.24)
	Fx3D.ring(host, global_position, GameTheme.TEXT_DIM, 0.5, 0.05, 0.2)

## Repel from nearby enemies so they surround the player instead of stacking into
## a single blob (which previously helped wall the player in).
func _separation() -> Vector2:
	var push := Vector2.ZERO
	var here := map_pos()
	for other in get_tree().get_nodes_in_group("enemy"):
		# Shadow proxies share this group; only bodies push.
		if other == self or not (other is Enemy3D) or not is_instance_valid(other):
			continue
		var away: Vector2 = here - (other as Enemy3D).map_pos()
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
	var hard: bool = impulse.length() >= 360.0 and _player_is_dashing()
	var broke_commit: bool = hard and (_charge_state == 1 or _boss_tele > 0.0)
	if broke_commit:
		_cancel_charge()
		if _boss_tele > 0.0:
			_boss_tele = 0.0
			_hide_marker()
	if _dying or not (broke_commit or (hard and was_winding)):
		return
	# Reading a telegraph and dashing into it is supposed to PAY.
	_open_vuln(1.1, 1.6)
	Fx3D.glyph(get_parent(), _head_pos(), "interrupted", GameTheme.TEXT, 15, 0.8, 0.8)

## Is the player mid-dash right now? Used to tell a Force Push apart from a bolt,
## which carry overlapping impulses. Property-probed rather than hard-referenced
## so a missing field degrades to `false` — never to an error.
func _player_is_dashing() -> bool:
	if not is_inside_tree():
		return false
	var p := get_tree().get_first_node_in_group("player")
	if p == null or not is_instance_valid(p):
		return false
	if "_dash_timer" in p:
		return float(p.get("_dash_timer")) > 0.0
	if "_dash_time" in p:
		return float(p.get("_dash_time")) > 0.0
	if "is_dashing" in p:
		return bool(p.get("is_dashing"))
	return false

func _combat_paused() -> bool:
	if GameManager.state != GameManager.GameState.PLAYING:
		return true
	if DialogueManager.is_active:
		return true
	var player := get_tree().get_first_node_in_group("player")
	if player and "can_move" in player and not player.can_move:
		return true
	return false

# ------------------------------------------------------------- damage ----

## Layered hit feedback: flash, damage number, sparks, screen shake scaled to the
## damage, and (on a crit) a short time-freeze.
func take_damage(amount: int, is_crit: bool = false, from_dir: Vector2 = Vector2.ZERO) -> void:
	if _dying:
		return
	# Sniping a boss from beyond the entrance trigger still counts as engaging
	# it: the card plays and the health bar appears, so the fight is never
	# anonymous.
	if is_boss and not _intro_done:
		_play_boss_intro()
	amount = _resolve_damage(amount, from_dir)
	hp -= amount
	_flash_damage()
	_spawn_damage_number(amount, is_crit)
	_hit_spark(from_dir, is_crit)
	_update_hp_readout()
	Fx3D.add_trauma(get_tree(), clampf(float(amount) / 90.0, 0.05, 0.3) * (1.6 if is_crit else 1.0))
	if hp > 0:
		_check_boss_phase()
	if hp <= 0:
		# take_damage often runs from a physics area callback; defer teardown so
		# we don't spawn pickups / disable shapes while the physics server is
		# flushing.
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
	# the same physics flush. Everything that must happen once per SHOT — chipping
	# the plate, printing a callout — is gated on the frame rather than on the
	# callback.
	var frame := Engine.get_physics_frames()
	var first_this_frame: bool = frame != _guard_frame
	if _guard_up() and from_dir.length_squared() > 0.0001:
		_guard_frame = frame
		if from_dir.dot(_guard_dir) < -cos(GUARD_ARC * 0.5):
			amount = maxi(1, int(round(float(amount) * GUARD_MITIGATION)))
			if first_this_frame:
				_guard_hits += 1
				Fx3D.ring(host, global_position + Map3D.dir3d(_guard_dir) * 0.47
					+ Vector3(0.0, 0.4, 0.0), _accent(), 0.06, 0.4, 0.22)
				Fx3D.glyph(host, global_position + Map3D.dir3d(_guard_dir) * 0.55
					+ Vector3(0.0, 0.7, 0.0), "blocked", GameTheme.TEXT, 12, 0.45, 0.3)
				if _guard_hits >= _guard_max:
					_break_guard()
			return amount
		if first_this_frame and randf() < 0.4:
			Fx3D.glyph(host, _head_pos(), "flanked", GameTheme.TEXT, 13, 0.55, 0.5)
	if _vuln_t > 0.0 and _vuln_mult > 1.0:
		amount = int(round(float(amount) * _vuln_mult))
	return amount

func _hit_spark(from_dir: Vector2, is_crit: bool) -> void:
	var at := global_position + Vector3(0.0, _base_model_h * _visual_scale() * 0.55 + _model_y, 0.0)
	# Sparks fly back ALONG the shot when we know where it came from.
	if from_dir.length_squared() > 0.0001:
		at -= Map3D.dir3d(from_dir.normalized()) * 0.2
	# Overbright NEUTRAL sparks: an impact is a flash of white, and the only
	# saturated thing on an enemy stays the red tell (LAW 7).
	Fx3D.burst(get_parent(), at, Color(1.9, 1.9, 1.95), 14 if is_crit else 8,
		5.0 if is_crit else 3.4, 0.35)
	if is_crit:
		Fx3D.flash(get_parent(), at, Color(2.2, 2.2, 2.3), 3.0, 0.14)

func _attack() -> void:
	if _combat_paused() or _dying or _stun_time > 0.0 or _intro_lock > 0.0:
		attack_timer.start(1.0)
		return
	# A boss must not swing during its own punish window; the whole point of the
	# recovery is that it is defenceless for a beat. Nor during ANY big-move
	# telegraph — a melee wind-up returns out of `_physics_process` BEFORE
	# `_update_special` runs, which would freeze the telegraph in place while the
	# marker painted under it ran out.
	if _charge_state != 0 or _telegraph > 0.0 \
			or (is_boss and (_boss_recover > 0.0 or _boss_tele > 0.0)):
		attack_timer.start(0.8)
		return
	if target == null or not is_instance_valid(target) \
			or map_pos().distance_to(_target_map()) > _start_reach():
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

# --------------------------------------------------------------- death ----

func _die() -> void:
	if is_instance_valid(_hp_label):
		ScreenLabels.set_text(_hp_label, "")
	_cancel_windup(false)
	_cancel_charge()
	# Anything this one still had in the air is cancelled with it, and every tell
	# comes off so the dissolve is the only thing left to look at.
	_cancel_shots()
	_hide_marker()
	if is_instance_valid(_alert_ring):
		_alert_ring.visible = false
	# The red core goes out with the body it belonged to.
	if is_instance_valid(_tell):
		_tell.visible = false
	if is_instance_valid(_tell_light):
		_tell_light.visible = false
	if is_instance_valid(_guard):
		_guard.visible = false
	if is_instance_valid(hitbox):
		hitbox.monitoring = false
		hitbox.monitorable = false
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
	# Dissolve into glowing embers. Total death time stays under 0.5s — the same
	# budget the 2D fight (and combat_test) uses.
	Fx3D.dissolve(model_root, _accent(), 0.45)
	if _anim and _anim.has("die"):
		_anim.play("die", 0.08, 1.6)
		_anim_lock = 1.0
	# The corpse leaves on a SceneTree timer, not a tween: a tween on a node that
	# is about to be freed is one more thing to keep alive, and a timer whose
	# only listener has been freed simply never fires.
	var tree := get_tree()
	if tree == null:
		queue_free()
		return
	tree.create_timer(0.45).timeout.connect(queue_free)

## The corpse's own 0.45s: it collapses and lifts off as embers. Fx3D.dissolve
## does the pretty version; this is what guarantees a death READS even while
## that track is a stub.
func _tick_death(delta: float) -> void:
	if not is_instance_valid(model_root):
		return
	var full := maxf(_visual_scale(), 0.001)
	var k: float = maxf(model_root.scale.x - delta * full * 2.2, 0.02)
	model_root.scale = Vector3(k, k, k)
	model_root.position.y = _model_y + (1.0 - k / full) * 0.18
	if is_instance_valid(_shadow):
		_shadow.scale = Vector3(k, 1.0, k)

## Thematically appropriate absurd deaths. Everything here is parented to the
## region, so it plays out after the corpse is gone.
func _death_comedy() -> void:
	var host := get_parent()
	if host == null:
		return
	var col := _accent()
	var shards: Array = DEATH_SHARDS.get(enemy_type, ["exit 1"])
	var count: int = 5 if is_boss else 4
	for i in count:
		var txt: String = str(shards[i % shards.size()])
		Fx3D.glyph(host, global_position + Vector3(randf_range(-0.5, 0.5), 0.5 + 0.18 * float(i),
			randf_range(-0.4, 0.4)), txt, col, 13, 1.1, 1.0)
	if _elite:
		# Elites are worth saying goodbye to; the payout is the point.
		Fx3D.glyph(host, _head_pos(0.5), "deprecated at last", GameTheme.TEXT, 15, 1.2, 1.2)
		Fx3D.ring(host, global_position, GameTheme.TEXT, 0.1, 1.8, 0.45)
	# The obituary: always for bosses, sometimes for the rank and file, so it
	# stays a joke instead of turning into a subtitle track.
	if is_boss or randf() < 0.35:
		var quip: String = str(DEATH_QUIPS.get(enemy_type, ""))
		if not quip.is_empty():
			Fx3D.glyph(host, _head_pos(0.2), quip, GameTheme.TEXT, 14, 1.4, 1.2)
	match enemy_type:
		"scope_creep":
			Fx3D.glyph(host, _head_pos(0.8), "just one more thing", GameTheme.TEXT_DIM, 15, 0.9, 1.0)
			Fx3D.shockwave(host, global_position, GameTheme.TEXT_DIM, 1.5, 0.4)
		"memory_leak":
			# A memory leak does not stop leaking just because you killed it.
			_leak_puddle(host)
		"rate_limiter":
			for i in 3:
				Fx3D.glyph(host, global_position + Vector3(randf_range(-0.5, 0.5), 0.4 + 0.22 * float(i), 0.0),
					"429", HOSTILE, 17, 1.0, 1.3)
		"hallucination":
			# A ghost leaves a ghost. Neutral and cool, not the violet it used to
			# be: LAW 2 does not hand an enemy a hue of its own.
			Fx3D.afterimage(host, model_root, Color(1.1, 1.15, 1.3, 0.7), 0.5)
		"null_reference":
			Fx3D.glyph(host, _head_pos(), "undefined", GameTheme.TEXT_DIM, 20, 1.1, 1.3)
		"cloud_bill":
			for s: String in ["$", "$$", "+ tax", "+ egress"]:
				Fx3D.glyph(host, global_position + Vector3(randf_range(-0.6, 0.6), 0.6, randf_range(-0.5, 0.5)),
					s, GameTheme.TEXT_DIM, 14, 1.0, 1.1)

## The puddle spreads for eight seconds and is still "definitely reachable".
## Parented to the region so it outlives the corpse; it frees itself.
func _leak_puddle(host: Node) -> void:
	var puddle := MeshInstance3D.new()
	puddle.mesh = _disc_mesh()
	var mat := StandardMaterial3D.new()
	# TEXT_DIM, not the saturated blue it used to be: a puddle on the floor is
	# not one of LAW 3's five bright things and not one of LAW 2's three hues.
	mat.albedo_color = GameTheme.with_alpha(GameTheme.TEXT_DIM, 0.30)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	puddle.material_override = mat
	puddle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	puddle.scale = Vector3(0.12, 1.0, 0.12)
	host.add_child(puddle)
	puddle.global_position = Vector3(global_position.x, 0.015, global_position.z)
	var tw := puddle.create_tween()
	tw.tween_property(puddle, "scale", Vector3(0.55, 1.0, 0.55), 5.5).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 8.0).set_ease(Tween.EASE_IN)
	tw.tween_callback(puddle.queue_free)

## A boss does not simply dissolve. Staggered detonations, a white-out, the bar
## draining, and the incident formally closed.
func _boss_death_spectacle() -> void:
	if _boss_hud and is_instance_valid(_boss_hud):
		_boss_hud.detach()
		_boss_hud.play_death()
		_boss_hud = null
	# The anchor's job is over the moment the layer has been handed to the scene.
	if _boss_anchor and is_instance_valid(_boss_anchor):
		_boss_anchor.queue_free()
		_boss_anchor = null
	var host := get_parent()
	if host == null:
		return
	var col := _accent()
	var pos := global_position
	var tree := get_tree()
	for i in 5:
		var at: Vector3 = pos + Vector3(randf_range(-0.8, 0.8), randf_range(0.0, 0.9), randf_range(-0.7, 0.7))
		var radius: float = 1.9 + 0.4 * float(i)
		var t := host.create_tween()
		t.tween_interval(0.09 * float(i))
		t.tween_callback(func() -> void:
			Fx3D.shockwave(host, at, col, radius, 0.4)
			Fx3D.add_trauma(tree, 0.22))
	Fx3D.shockwave(host, pos, Color(1, 1, 1), 4.7, 0.7)
	Fx3D.burst(host, pos + Vector3(0.0, 0.5, 0.0),
		Color(col.r * 2.2, col.g * 2.2, col.b * 2.2), 40, 7.0, 0.8)
	Fx3D.add_trauma(get_tree(), 0.8)
	Fx3D.punch_zoom(get_tree(), 0.09)
	# The room stops holding its breath. (No-op unless music is enabled.)
	AudioManager.play_music("explore_music")

## ~40ms time-freeze on close-range kills so melee-distance takedowns have
## physical weight. All the safety guards live in FxLib.hit_stop.
func _hit_stop_if_close() -> void:
	if not is_inside_tree():
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or map_pos().distance_to(Map3D.to_map(player.global_position)) > 150.0:
		return
	Fx3D.hit_stop(get_tree())

## A burst of enemy-tinted debris on death, parented to the region so it outlives
## the enemy.
func _death_burst() -> void:
	var host := get_parent()
	if host == null:
		return
	var col := _accent()
	var at := global_position + Vector3(0.0, _base_model_h * _visual_scale() * 0.5 + _model_y, 0.0)
	Fx3D.burst(host, at, Color(col.r * 1.8, col.g * 1.8, col.b * 1.8), 16, 4.0, 0.45)
	Fx3D.flash(host, at, col, 2.2, 0.3)
	Fx3D.ring(host, global_position, col, 0.06, 1.2, 0.36)

func _split() -> void:
	var host := get_parent()
	var spawned: Array[Node3D] = []
	for i in 2:
		var e := _spawn_add("merge_conflict", maxi(6, int(max_hp / 2)),
			maxi(4, int(damage * 0.7)), maxi(1, int(token_drop / 2)), generation + 1)
		if e == null:
			continue
		spawned.append(e)
	# Show the resolution for what it is: two incompatible halves, labelled.
	if host and spawned.size() == 2:
		Fx3D.glyph(host, spawned[0].global_position + Vector3(0.0, 1.0, 0.0), "<<<<<<< HEAD",
			GameTheme.TEXT_DIM, 13, 1.0, 0.8)
		Fx3D.glyph(host, spawned[1].global_position + Vector3(0.0, 1.0, 0.0), ">>>>>>> feature/x",
			GameTheme.TEXT_DIM, 13, 1.0, 0.8)
		Fx3D.beam(host, spawned[0].global_position + Vector3(0.0, 0.5, 0.0),
			spawned[1].global_position + Vector3(0.0, 0.5, 0.0), GameTheme.TEXT_DIM, 0.1, 0.4)

func _spawn_tokens() -> void:
	var host := get_parent()
	if host == null or not ResourceLoader.exists(TOKEN3D_SCENE):
		return
	var scene: PackedScene = load(TOKEN3D_SCENE)
	if scene == null:
		return
	var count := 5 if is_boss else 1
	for i in count:
		var t := scene.instantiate() as Node3D
		if t == null:
			continue
		# TokenPickup3D reads `token_type` and its own height in `_ready`, so
		# everything it looks at is set before it enters the tree.
		t.set("amount", maxi(1, token_drop / count))
		t.position = Map3D.to3d(map_pos()
			+ Vector2(randf_range(-20, 20), randf_range(-20, 20)), 0.0)
		host.add_child(t)

## The player's bolt, reported by THIS enemy's hitbox. The projectile reports the
## same contact on its own side in the same physics flush — that is how the 2D
## game has always resolved a hit, and both halves are kept so the damage per
## shot is the number the 2D game balanced around (the two hits merge into one
## damage number; see `_spawn_damage_number`).
func _on_hitbox_area_entered(area: Area3D) -> void:
	if area.is_in_group("player_projectile"):
		var raw_dmg: Variant = area.get("damage")
		var dmg: int = int(raw_dmg) if raw_dmg != null else 10
		var is_crit: bool = area.get("crit") == true
		var raw_dir: Variant = area.get("direction")
		var dir: Vector2 = raw_dir if raw_dir is Vector2 else Vector2.ZERO
		take_damage(dmg, is_crit, dir)
		# Piercing shots (Stack Trace) survive contact — the projectile's own
		# handler tracks per-enemy hits; only consume non-piercing bolts.
		if not (area.get("pierce") == true):
			area.queue_free()
