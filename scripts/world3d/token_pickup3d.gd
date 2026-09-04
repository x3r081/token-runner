class_name TokenPickup3D
extends Area3D
## The 3D twin of `scripts/world/token_pickup.gd` (3D_BIBLE.md §4, §7).
##
## Every reward call, SFX name, amount roll and magnet number is token_pickup.gd's;
## only the presentation changed. In 3D the coin gets what a sprite could never
## have: depth. It bobs LAW 9's two pixels and turns on its axis slowly enough to
## read as a coin rather than a turbine. It is a small emissive gold point (LAW 3)
## and carries no light of its own (LAW 4's light budget is the room's, not the
## loot's); the only light it ever casts is the pickup flare.
##
## VISUAL_BIBLE LAW 2, the OTHER half of it: gold means money, and money is ONE
## colour. Round 2 put pale-cyan `cached` pills and grey-blue `compute` crystals
## on the same floor as the gold coins, and the critic read the frame exactly as
## it was drawn — "tokens are two different colours in one frame". A player
## cannot be asked to learn that the cyan pill is also currency while cyan is
## also localhost's accent. Every pickup in the game is now GOLD: `cached` is the
## same gold at 85% value (a coin that has been sitting in the cache), `compute`
## keeps its crystal SHAPE and gives up its hue.

const COIN_MODEL := "mini-dungeon/coin"
const COMPUTE_MODEL := "tower-defense/detail-crystal"

## Reused from the 2D twin so the palette has exactly one definition. Read at
## RUNTIME (`Token2D.GOLD`) rather than copied into a const of our own, which
## keeps this file out of const-expression territory entirely.
const Token2D := preload("res://scripts/world/token_pickup.gd")

const COIN_HEIGHT := 0.34
const CRYSTAL_HEIGHT := 0.42
## Resting height of the coin's centre above the floor, and LAW 9's bob — the
## 2D twin's 2px, at 64px to the unit. 2px IS 0.031u; the old 0.05 was three.
const HOVER_Y := 0.45
const BOB := 0.031
## The coin LIES FLAT. Kenney's coin is authored standing in its own XY plane,
## and a standing disc under this camera is a two-pixel-wide vertical sliver —
## which is why the round-2 frames read as "pills" rather than as money. A
## quarter turn about X puts its face toward the camera, where a 0.34u disc is a
## 30px coin you can name at a glance.
const COIN_TILT := -PI * 0.5
## A builder that has ALREADY lifted the node off the floor has said where it
## wants the coin, so the internal hover collapses to zero and the art centres
## on the node origin instead of stacking two lifts. (localhost_builder3d places
## tokens at y 0; region_builder3d places them at y 0.55 — both land right.)
const PRELIFTED_Y := 0.2
## LAW 9 says tokens BOB; the 2D coin is forbidden to spin because rotation
## breaks the pixel grid, and 3D inherited the freedom and overspent it at 2.2
## rad/s — a coin whirling like a turbine reads as a powerup, not as money. What
## survives is a slow yaw about the VERTICAL axis of a coin that is already
## lying flat: one turn every eighteen seconds, which catches the moon on the
## rim and is otherwise invisible in a still frame.
const SPIN_RATE := 0.35

## token_pickup.gd's magnet, converted at the coordinate edge: 100 map px of
## reach, 280 map px/s of pull.
const MAGNET_SPEED := 4.375

## LAW 3 lets a token be bright; LAW 4 does not let eight of them light the
## room. The coin's own emission is what the player reads (see `_build_model`)
## and it carries NO resting light: LAW 4 budgets a region six lights in the
## 0.4-0.9 band, and eight-to-ten coins each dragging a 0.25 omni around is
## eight-to-ten lights under the band's floor — a budget spent on things the
## bible does not even count as lights. The pickup flare is the one moment a
## coin is allowed to touch the floor with light (Fx3D.flash, below), and it is
## over in a quarter of a second. 0.25 is well under LAW 4's 0.4-0.9 band on
## purpose: this is a wink, not one of the room's six lights.
const FLARE_ENERGY := 0.25
const FLARE_TIME := 0.15
## The coin's emissive energy. 1.2 clears the §7 glow threshold of 1.0 — so a
## token still blooms, as one of LAW 3's five — without the 2.2 that turned a
## cluster of them into a single lamp.
const EMIT_ENERGY := 1.2

@export var token_type: String = "common"
@export var amount: int = 5
## MAP PIXELS, like the 2D export the builders already set.
@export var magnet_radius: float = 100.0

var collected := false

var _model: Node3D
var _proxy: ActorProxy
var _color: Color = Token2D.GOLD
var _bob_time := 0.0
var _pop_scale := Vector3.ONE
var _lift := HOVER_Y

func _ready() -> void:
	add_to_group("token")
	collision_layer = 4
	collision_mask = 1
	_bob_time = randf() * TAU
	_lift = 0.0 if position.y > PRELIFTED_Y else HOVER_Y
	# The trigger volume rides with the art, so "walked into the coin" means the
	# same thing whichever builder placed it.
	var shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape:
		shape.position.y = _lift
	# token_pickup.gd's rolls, verbatim — the economy tests read these numbers.
	match token_type:
		"premium", "golden", "frontier":
			amount = randi_range(amount, amount * 3)
		"compute":
			amount = randi_range(3, 8)
	_color = _tint_for(token_type)
	_build_model()
	body_entered.connect(_on_body_entered)
	_proxy = ActorProxy.attach(self, ["token"], {
		"token_type": token_type,
		"amount": amount,
		"collected": false,
	})

## LAW 2: ONE colour for money, in every region, without exception. §7's "cached
## tinted cyan" is superseded here — v2 supersedes §7 where they conflict, and
## two currencies in two hues on one floor is the conflict. `cached` is the same
## gold at 85% value, which reads as a duller coin next to a fresh one rather
## than as a different substance.
func _tint_for(kind: String) -> Color:
	var gold: Color = Token2D.GOLD
	if kind == "cached":
		return Color(gold.r * 0.85, gold.g * 0.85, gold.b * 0.85, gold.a)
	return gold

## The art hangs under a HOLDER: the holder is what bobs and yaws, so the coin
## inside it can keep its quarter-turn onto the floor plane without the two
## rotations having to share one node's Euler order.
func _build_model() -> void:
	var is_coin := token_type != "compute"
	var key := COIN_MODEL if is_coin else COMPUTE_MODEL
	var h := COIN_HEIGHT if is_coin else CRYSTAL_HEIGHT
	var holder := Node3D.new()
	holder.name = "Art"
	var m := Map3D.model(key)
	if m == null:
		# A pickup is never allowed to be an invisible trigger volume. A
		# CylinderMesh's axis is +Y, so a short wide one is a coin already lying
		# flat — the same read as the tilted Kenney model.
		var mi := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = h * 0.5 if is_coin else 0.16
		cyl.bottom_radius = cyl.top_radius
		cyl.height = h * 0.28 if is_coin else h
		mi.mesh = cyl
		# A CylinderMesh is centred on its own origin, and so is the holder.
		mi.material_override = Map3D.matte(_color, EMIT_ENERGY)
		holder.add_child(mi)
	else:
		Map3D.fit_height(m, key, h)
		# Emissive so a coin reads as a coin under the §7 moon, and so it picks
		# up the glow pass at threshold 1.0. Map3D.tint MULTIPLIES albedo, so
		# the hue the player actually reads is the emission — which is exactly
		# `_color` at full strength.
		Map3D.tint(m, _color, EMIT_ENERGY)
		if is_coin:
			m.rotation.x = COIN_TILT  # face up
		# Centre the art on the holder, whatever its own origin and rotation are.
		# Kenney authors these floor-anchored (the coin's origin is its bottom
		# EDGE, and after the quarter-turn that edge is 17cm off to one side), so
		# the offset has to go through the model's own basis rather than being a
		# hand-written half-height that is only right for an upright mesh.
		var b := Map3D.bounds(key)
		if not b.is_empty():
			var mn: Array = b.get("min", [0.0, 0.0, 0.0])
			var mx: Array = b.get("max", [0.0, 0.0, 0.0])
			var mid := Vector3(
				(float(mn[0]) + float(mx[0])) * 0.5,
				(float(mn[1]) + float(mx[1])) * 0.5,
				(float(mn[2]) + float(mx[2])) * 0.5)
			m.position = -(m.transform.basis * mid)
		holder.add_child(m)
	holder.position = Vector3(0.0, _lift, 0.0)
	add_child(holder)
	_model = holder

## Bob, spin, magnet. Nothing else moves (LAW 9) — the 2D twin's pulsing light
## and per-token sparkle emitter are still gone.
func _process(delta: float) -> void:
	if collected:
		if _proxy:
			_proxy.sync()
		return
	_bob_time += delta * 2.4
	if _model:
		# The holder IS the coin's centre (see `_build_model`), so the bob is the
		# resting lift plus LAW 9's two pixels and nothing else.
		_model.position.y = _lift + sin(_bob_time) * BOB
		_model.rotation.y += delta * SPIN_RATE
	var player := get_tree().get_first_node_in_group("player")
	if player is Node3D:
		# The pull is on the floor plane only: the coin keeps whatever height its
		# builder gave it, so a pre-lifted region coin does not sink into the
		# tiles on its way over (the 2D twin has no third axis to lose).
		var target: Vector3 = (player as Node3D).global_position
		target.y = global_position.y
		if global_position.distance_to(target) < magnet_radius / Map3D.PX:
			global_position = global_position.move_toward(target, MAGNET_SPEED * delta)
	if _proxy:
		_proxy.sync()

# ------------------------------------------------------------- collection --

## token_pickup.gd::_on_body_entered, call for call and SFX for SFX.
func _on_body_entered(body: Node3D) -> void:
	if collected:
		return
	if not body.is_in_group("player"):
		return
	collected = true
	if _proxy:
		_proxy.set_field("collected", true)
	# One trigger only: the flight below keeps moving through the player.
	set_deferred("monitoring", false)
	if token_type == "compute":
		ResourceManager.modify("compute", amount)
	else:
		ResourceManager.add_tokens(amount, "pickup_%s" % token_type)
	QuestManager.on_token_collected(amount)
	AudioManager.play_sfx("token_collect" if token_type == "common" else "pickup_rare")
	# The float text and the ring the 2D twin spawns by hand; in 3D both belong
	# to the fx track's API (a no-op today, a burst tomorrow — either is safe).
	var host := get_parent()
	Fx3D.glyph(host, global_position + Vector3(0.0, _lift + 0.25, 0.0),
		"+%d" % amount, _color, 24, 0.9, 1.2)
	Fx3D.burst(host, global_position + Vector3(0.0, _lift, 0.0), _color, 10, 3.0, 0.35)
	Fx3D.ring(host, global_position + Vector3(0.0, 0.05, 0.0), _color, 0.1, 0.7, 0.3)
	# The one touch of gold light a coin ever puts on the floor: Fx3D's flare is
	# a transient omni (capped at 1.2 for 0.15s in fx3d.gd, freed when it fades)
	# and it lives in the fx bins, so a stack of pickups cannot leave a lamp
	# behind on a node that is about to be freed.
	Fx3D.flash(host, global_position + Vector3(0.0, _lift, 0.0), _color, FLARE_ENERGY, FLARE_TIME)
	# Scale-pop, then a 0.15s magnet flight into the (still moving) player.
	# The token is already counted above: everything from here is visual.
	var tween := create_tween()
	if _model:
		_pop_scale = _model.scale * 1.35
		tween.tween_property(_model, "scale", _pop_scale, 0.08) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_method(_fly_step.bind(body, global_position), 0.0, 1.0, 0.15)
	tween.tween_callback(queue_free)

## Chase the player, shrinking on the way in.
func _fly_step(t: float, body: Node3D, from: Vector3) -> void:
	if is_instance_valid(body):
		# Aim at chest height, not the floor, so the coin does not dive.
		global_position = from.lerp(body.global_position + Vector3(0.0, 0.5, 0.0), t * t)
	if _model:
		_model.scale = _pop_scale.lerp(_pop_scale * 0.25, clampf(t, 0.0, 1.0))
