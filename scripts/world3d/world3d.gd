extends Node3D
## THE 3D WORLD (3D_BIBLE.md §3). The 2D twin of this file is
## scripts/world/world.gd, and this is a PORT of it: same lifecycle, same
## public surface, same method names, same signal wiring, same story triggers.
## Where behaviour differs it is because the renderer changed, and every one of
## those places says so.
##
## NO `class_name`. `World3D` is a REAL GODOT CLASS (the 3D scenario resource
## that backs every Viewport), so declaring one here would be a fatal
## collision. The scene attaches this script by path and everything else finds
## the world through the "world" group, exactly as in 2D.
##
## WHAT THE 2D WORLD DOES THAT THIS ONE DOES NOT, AND WHY
##
## world.gd is roughly half pixel-stage plumbing: the 640x360 SubViewport, the
## letterbox fit, `_adopt_layer` (a CanvasLayer born inside the stage renders
## against a 640x360 "screen"), `_purge_adopted`, the starfield, the 2D glow
## Environment, the CanvasModulate ambient, the atmosphere quads and the wall
## fixtures. None of it survives the port, and none of it is missing:
##
##   stage/letterbox  there is no stage. The 3D world renders straight into the
##                    main viewport, so a CanvasLayer's Controls already lay out
##                    in the same pixels a Camera3D unprojects into. Stage3D
##                    (stage3d.gd) answers the two questions the fit existed to
##                    answer, and answers them with `stage_k == 1`.
##   adopt/purge      a CanvasLayer parented to a boss is already in the only
##                    viewport there is, so boss_hud.gd needs no rescue and
##                    cannot be orphaned by a region change (it is freed with
##                    the boss that owns it).
##   starfield        the void outside a room is the Environment's background,
##                    painted in the region's BASE hex (environment3d.gd), not
##                    a quad.
##   ambient/glow     one WorldEnvironment, written by environment3d.gd only.
##   atmosphere/life  there is no atmosphere pass at all — VISUAL_BIBLE_V2 LAW 5
##                    took the volumetric fog out (it was tinting the whole
##                    frame with the region accent). Wall fixtures are real
##                    OmniLight3Ds placed by the region builders.
##
## THE SCENE (scenes/world3d/world3d.tscn — .tscn files carry no comments, so
## the two things a reader needs to know about its shape are here)
##
##   1. NODE ORDER IS LOAD-BEARING. `Proxies` comes before `RegionRoot`, and
##      the Player is inserted directly after `RegionRoot` — every 3D actor
##      calls `ActorProxy.attach()` from its own `_ready`, and that resolves
##      the "proxy_root" group.
##   2. THE PLAYER IS INSTANCED IN THE SCENE, directly after RegionRoot and
##      BEFORE the HUD — exactly where world.tscn puts its Player. That order
##      is not cosmetic: hud.gd resolves group "player" in ITS OWN `_ready`
##      (children ready before their parent) and connects `health_changed`
##      there, once. A player mounted later from this script's `_ready` is one
##      the HUD never hears from — the HP bar sits at full while you die.
##      `_spawn_player()` keeps an exists()-guarded runtime load only as the
##      fallback for a scene that has lost its Player node.

const _Environment3D := preload("res://scripts/world3d/environment3d.gd")
const _CameraRig3D := preload("res://scripts/world3d/camera_rig3d.gd")
const _Stage3D := preload("res://scripts/world3d/stage3d.gd")

## CROSS-TRACK SCENES. These are landing from sibling tracks while this file is
## being written, so every one of them is `load()`ed behind
## `ResourceLoader.exists()` and never `preload()`ed: a preload of a file that
## is not on disk yet is a parse error, and a parse error here takes the entire
## game down (HANDOVER.md §4 gotcha 6b). The paths themselves are FIXED by
## 3D_BIBLE.md §3/§4 and may not be renamed.
const PLAYER_SCENE := "res://scenes/world3d/player3d.tscn"
const ENEMY_SCENE := "res://scenes/world3d/enemy3d.tscn"

## The region builders, by global class name (3D_BIBLE §3) with a path fallback
## for the window before an `--import` has registered the class. Resolved
## through `_builder_script()`; a missing builder logs and leaves an empty room
## rather than crashing the world.
const REGION_BUILDER_CLASS := "RegionBuilder3D"
const REGION_BUILDER_PATHS := ["res://scripts/world3d/region_builder3d.gd"]
const LOCALHOST_BUILDER_CLASS := "LocalhostBuilder3D"
const LOCALHOST_BUILDER_PATHS := ["res://scripts/world3d/localhost_builder3d.gd"]

@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var moon: DirectionalLight3D = $Moon
## Hidden Node2D that every ActorProxy parents itself under (3D_BIBLE §5).
## FIRST in the tree among the gameplay nodes so it is in its group before any
## actor's `_ready` goes looking for it.
@onready var proxies: Node2D = $Proxies
@onready var region_root: Node3D = $RegionRoot
@onready var rig: _CameraRig3D = $CameraRig
@onready var stage: _Stage3D = $Stage3D
@onready var hud: CanvasLayer = $HUD

## The player body, instanced at `_ready` (see `_spawn_player`). Typed Node3D
## rather than CharacterBody3D so a player scene whose root is something else
## still mounts; every access is duck-typed the way world.gd's is.
var player: Node3D

var _current_region_node: Node3D
## The current room in MAP PIXELS, straight from the builder's `size`.
var _region_size := Vector2.ZERO
## Technical-debt pressure, 0..1. Recorded and rendered NOWHERE — see
## `_refresh_stress`.
var _stress := 0.0

func _ready() -> void:
	GameManager.state = GameManager.GameState.PLAYING
	_setup_viewport()
	_setup_environment()
	_spawn_player()
	# A world-space Node2D that lands on this node can only be misplaced here;
	# see `_reclaim_world_child`.
	get_tree().node_added.connect(_on_node_added)
	_reset_guide_fit()
	_load_region(GameManager.current_region)
	QuestManager.on_region_entered(GameManager.current_region)
	GameManager.region_changed.connect(_on_region_changed)
	GameManager.player_died.connect(_on_player_died)
	GameManager.debt_incident.connect(_on_debt_incident)
	# Debt pressure has to hear about every change — including the silent ones
	# an upgrade purchase makes.
	ResourceManager.resource_changed.connect(_on_resource_changed)
	# NOTE: do NOT also connect player.died here. player3d.gd emits `died` AND
	# calls GameManager.handle_player_death() (which emits player_died), so
	# wiring both spawns two stacked death screens — the top one's Respawn
	# button frees only itself, leaving an identical screen behind and making
	# respawn look broken. The 2D world learned this; the 3D one inherits it.
	if player and "can_move" in player:
		player.can_move = false
	if GameManager.show_opening_sequence:
		_start_opening_sequence()
	else:
		if player and "can_move" in player:
			player.can_move = true
			if player.has_method("grant_spawn_grace"):
				player.grant_spawn_grace()

## --- boot ------------------------------------------------------------------

## The main viewport, which the 2D game never had to configure because it
## rendered into its own SubViewport. Two settings, both cheap and both worth
## it on Kenney's flat colormap: MSAA, because a low-poly silhouette against a
## dark background is nothing BUT edges, and debanding, because a night grade is
## mostly slow ramps in the bottom tenth of the range — exactly what bands on an
## 8-bit output, and more so now that the frame HAS a bottom tenth.
##
## Left in place on exit: neither touches 2D rendering, so carrying them back
## to the (2D) main menu costs nothing and un-setting them would only add a
## code path that runs when the game is being torn down.
func _setup_viewport() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var q := _Environment3D.quality()
	vp.msaa_3d = Viewport.MSAA_2X if q >= 1 else Viewport.MSAA_DISABLED
	vp.use_debanding = q >= 1

## One Environment, built once. `apply_region` is called here as well as from
## `_load_region` on purpose: `build()` can only paint the DEFAULT region's void
## and fill, so without this the frames between `_ready` and the first region
## build (the opening sequence's first moments, and every `--headless` capture
## that photographs early) carry a background in the wrong region's BASE. It is
## idempotent, and `_load_region` calls it again a few lines later anyway.
func _setup_environment() -> void:
	if world_env != null:
		world_env.environment = _Environment3D.build()
	_Environment3D.setup_moon(moon)
	_Environment3D.apply_region(
		world_env.environment if world_env != null else null,
		moon, GameManager.current_region)

## Resolve the player. Normally the scene's own `Player` instance (see the
## header: it has to precede the HUD). If the scene has none, mount one at
## runtime so the world still boots — an empty room with a working camera and a
## working HUD is a diagnosable state, a failed scene load is not. The runtime
## copy is inserted directly after RegionRoot so the tree order still matches
## 3D_BIBLE §3 (Proxies, RegionRoot, Player) and every actor's `_ready` finds
## "proxy_root" already in its group; what it cannot do is reach a HUD that has
## already bound, which is why it is the fallback and not the rule.
func _spawn_player() -> void:
	var existing := get_node_or_null("Player")
	if existing is Node3D:
		player = existing as Node3D
		rig.set_target(player)
		return
	if not ResourceLoader.exists(PLAYER_SCENE):
		push_warning("World3D: %s missing; running without a player." % PLAYER_SCENE)
		return
	var ps: PackedScene = load(PLAYER_SCENE)
	if ps == null:
		push_warning("World3D: %s failed to load." % PLAYER_SCENE)
		return
	var inst := ps.instantiate()
	if not (inst is Node3D):
		push_warning("World3D: player3d.tscn root is not a Node3D.")
		inst.free()
		return
	inst.name = "Player"
	add_child(inst)
	move_child(inst, region_root.get_index() + 1)
	player = inst as Node3D
	rig.set_target(player)

## The guide overlay is an autoload's child and outlives every world scene, so
## it can arrive still carrying a 2D world's letterbox correction. There is no
## letterbox in 3D; give it its authored layout back. A no-op when it was never
## fitted (PixelStage.reset_layer checks its own metadata).
func _reset_guide_fit() -> void:
	var guide := UIManager.guide() if UIManager.has_method("guide") else null
	if guide is CanvasLayer:
		PixelStage.reset_layer(guide)

## --- regions ---------------------------------------------------------------

func _load_region(region_id: String) -> void:
	if _current_region_node:
		_current_region_node.queue_free()
	_current_region_node = Node3D.new()
	_current_region_node.name = region_id
	region_root.add_child(_current_region_node)
	var data := _build_region(_current_region_node, region_id)
	var spawn: Vector2 = data.get("spawn", Vector2.ZERO)
	_region_size = data.get("size", Vector2.ZERO)
	# MAP PIXELS, always: GameManager.region_spawn is read by saves, by the map
	# panel and by respawn, none of which know the 3D layer exists (§2).
	GameManager.region_spawn = spawn
	if player:
		# Straight assignment, not `respawn()`: player3d's respawn refills HP
		# (player.gd:1136), and a region change is not a heal.
		player.global_position = Map3D.to3d(spawn, 0.0)
	_apply_camera_bounds(_region_size)
	_Environment3D.apply_region(
		world_env.environment if world_env != null else null, moon, region_id)
	_refresh_stress(true)
	_region_flourish()
	# Production greets you with an incident (once).
	if region_id == "production" and not EventManager.is_script_completed("production_incident"):
		call_deferred("_trigger_production_incident")
	# Corporate Enterprise greets you with a surprise live demo (once).
	if region_id == "corporate_enterprise" and not EventManager.is_script_completed("all_hands_demo"):
		call_deferred("_trigger_all_hands_demo")

## Hand the room to its builder. `LocalhostBuilder3D.build(root)` for the
## apartment, `RegionBuilder3D.build(root, id)` for everything else — the same
## split, and the same return contract ({"spawn": Vector2 px, "size": Vector2
## px}), as the 2D builders.
##
## Everything here is defensive on purpose. A region builder is the largest,
## newest surface in the 3D layer; the world must survive one being absent,
## half-written or returning something unexpected, because the alternative is a
## black screen with no HUD and no way to tell which of ten regions broke.
func _build_region(root: Node3D, region_id: String) -> Dictionary:
	var is_localhost := region_id == "localhost"
	var cls := LOCALHOST_BUILDER_CLASS if is_localhost else REGION_BUILDER_CLASS
	var paths: Array = LOCALHOST_BUILDER_PATHS if is_localhost else REGION_BUILDER_PATHS
	# `builder`, not `script`: every Object already has a `script` property, and
	# a local of that name shadows it.
	var builder := _builder_script(cls, paths)
	if builder == null:
		push_warning("World3D: no 3D builder for '%s'; the room will be empty." % region_id)
		return _fallback_region(region_id)
	# NOT `builder.has_method("build")`: on a Script RESOURCE that answers for
	# the resource's own methods, and whether it also sees the script's static
	# functions has changed between Godot minors. A wrong answer here is nine
	# silently empty rooms, so the declaration list is read directly, the way
	# tests/world3d_test.gd does.
	if not _script_declares(builder, "build"):
		push_warning("World3D: builder %s has no build(); the room will be empty." % cls)
		return _fallback_region(region_id)
	var out: Variant
	if is_localhost:
		out = builder.call("build", root)
	else:
		out = builder.call("build", root, region_id)
	if not (out is Dictionary):
		push_warning("World3D: builder for '%s' did not return a Dictionary." % region_id)
		return _fallback_region(region_id)
	var d: Dictionary = out
	# A builder that answered but left the contract half-filled still gets a
	# usable spawn and a usable room rect, so the camera has bounds to clamp to.
	var fb := _fallback_region(region_id)
	var spawn: Variant = d.get("spawn")
	if not (spawn is Vector2):
		d["spawn"] = fb["spawn"]
	var size: Variant = d.get("size")
	if not (size is Vector2) or size == Vector2.ZERO:
		d["size"] = fb["size"]
	return d

## Does `s` DECLARE a function of this name (static or not)? The one lookup
## that is version-proof for a script that is only ever reached as a resource.
static func _script_declares(s: Script, method: String) -> bool:
	if s == null:
		return false
	for m: Dictionary in s.get_script_method_list():
		if String(m.get("name", "")) == method:
			return true
	return false

## The room a missing builder gets: the 2D geometry, read off RegionBuilder's
## own tables so the two can never disagree. Reading the 2D constants is
## explicitly allowed (3D_BIBLE §2/§4 — the authored layout is reused).
func _fallback_region(region_id: String) -> Dictionary:
	var size := Vector2(
		float(RegionBuilder.REGION_SIZE.x * RegionBuilder.TILE_SIZE),
		float(RegionBuilder.REGION_SIZE.y * RegionBuilder.TILE_SIZE))
	if region_id == "localhost":
		# The apartment is 25x16 tiles, not 20x15 (3D_BIBLE §2). Hardcoded
		# because LocalhostBuilder exposes its size only through build()'s
		# return value, and calling the 2D builder here would fill the room
		# with 2D nodes.
		size = Vector2(25.0 * float(RegionBuilder.TILE_SIZE), 16.0 * float(RegionBuilder.TILE_SIZE))
	return {"spawn": size * 0.5, "size": size}

## Resolve a builder by global class name, falling back to its authored path.
##
## `RegionBuilder3D` cannot be NAMED in this file: a bare reference to a
## `class_name` that is not on disk is a parse error, and a parse error here is
## a dead game (HANDOVER §4 gotcha 6b). So the class is looked up as a string —
## first in the project's global class table, then on disk — and its static
## `build()` is reached through `Script.call()`.
## `ProjectSettings.get_global_class_list()` is reached through `call()` and
## not written as a normal call, for the same reason: naming a method the
## running engine does not export is ALSO a parse error, and this file must
## survive every version of being wrong about the world around it.
static func _builder_script(cls: String, paths: Array) -> Script:
	if ProjectSettings.has_method("get_global_class_list"):
		var listing: Variant = ProjectSettings.call("get_global_class_list")
		if listing is Array:
			var rows: Array = listing
			for entry: Variant in rows:
				if not (entry is Dictionary):
					continue
				var e: Dictionary = entry
				if String(e.get("class", "")) != cls:
					continue
				var found := String(e.get("path", ""))
				if found != "" and ResourceLoader.exists(found):
					return load(found) as Script
	for p: String in paths:
		if ResourceLoader.exists(p):
			return load(p) as Script
	return null

## The camera may not look outside the room (§7). The 2D twin wrote Camera2D's
## four limits; the rig owns the equivalent here, and Stage3D needs the same
## rect to answer `world_rect` for the UI.
func _apply_camera_bounds(size: Vector2) -> void:
	if size == Vector2.ZERO:
		return
	rig.set_bounds(size)
	stage.set_world_rect(size)

## Region-entry flourish. Cosmetic only — input stays live and the opening
## sequence sits far above. Reached through the group rather than through `rig`
## so a replaced or absent rig is a missing flourish, not a crash: this is the
## same contract every combat call site uses.
func _region_flourish() -> void:
	var fx := get_tree().get_first_node_in_group("camera_fx")
	if fx and fx.has_method("region_settle"):
		fx.region_settle()

func _trigger_production_incident() -> void:
	if not EventManager.has_active_event():
		EventManager.start_scripted("production_incident", preload("res://scripts/world/story_events.gd").production_incident())

func _trigger_all_hands_demo() -> void:
	if not EventManager.has_active_event():
		EventManager.start_scripted("all_hands_demo", preload("res://scripts/world/story_events.gd").all_hands_demo())

## --- opening sequence ------------------------------------------------------

func _start_opening_sequence() -> void:
	var intro := preload("res://scenes/ui/opening_sequence.tscn").instantiate()
	add_child(intro)
	intro.sequence_finished.connect(_on_opening_finished)
	# Safety net: no matter what, restore control shortly after the intro window.
	get_tree().create_timer(18.0).timeout.connect(_ensure_player_control)

func _ensure_player_control() -> void:
	if player and "can_move" in player and not player.can_move \
			and GameManager.state == GameManager.GameState.PLAYING:
		_on_opening_finished()

func _on_opening_finished() -> void:
	GameManager.show_opening_sequence = false
	if player and "can_move" in player:
		player.can_move = true
		if player.has_method("grant_spawn_grace"):
			player.grant_spawn_grace()
	if hud and hud.has_method("show_intro_hint") and GameManager.current_region == "localhost":
		hud.show_intro_hint()
	# Let the player explore briefly; Claude dialogue starts on first interact.
	if SettingsManager.get_setting("music_enabled"):
		AudioManager.enable_music()
		AudioManager.play_music("explore_music")

## --- stray world-space 2D --------------------------------------------------

## A handful of nodes in the project spawn WORLD-SPACE Node2Ds into
## `get_tree().current_scene` (token_pickup.gd's "+5" float is the live one).
## In 2D that node lands in the camera's viewport and draws where the token is.
## Here `current_scene` is a Node3D, so a Node2D parented to it has no canvas
## transform at all: it draws at its raw map coordinates in WINDOW space — a
## "+5" for a token at (630, 460) appears 630px from the left edge of the
## window, nowhere near anything.
##
## There is no correct place for it, so it goes under the hidden Proxies node
## and is seen by nobody. The 3D actors use Fx3D.glyph() instead, which is a
## billboard in the world where the number belongs.
##
## Deferred, because `node_added` fires BEFORE the node's own `_ready`.
func _on_node_added(n: Node) -> void:
	if n is Node2D and n.get_parent() == self:
		call_deferred("_reclaim_world_child", n)

func _reclaim_world_child(n: Node) -> void:
	if not is_instance_valid(n) or not is_inside_tree() or not is_instance_valid(proxies):
		return
	if n.get_parent() != self:
		return
	remove_child(n)
	proxies.add_child(n)

## --- debt pressure ---------------------------------------------------------

func _on_resource_changed(res_name: String, _old: float, _new: float) -> void:
	if res_name == "technical_debt":
		_refresh_stress(false)

## Technical debt is RECORDED and RENDERED NOWHERE, which is a decision the 2D
## game made deliberately and this port inherits verbatim: draining the frame's
## saturation and heating its corners was "a good joke charged to the wrong
## account" (world.gd) — the player reads that frame while fighting in it. The
## joke lives in dialogue, barks and prop text. The call is kept so the debt
## signal still has exactly one owner.
func _refresh_stress(_snap: bool) -> void:
	var debt := ResourceManager.get_value("technical_debt")
	_stress = clampf((debt - 20.0) / 70.0, 0.0, 1.0)

## Technical debt "breaks a dependency": a fresh bug crawls out near the player.
func _on_debt_incident(_kind: String) -> void:
	if not _current_region_node or not player:
		return
	if not ResourceLoader.exists(ENEMY_SCENE):
		return
	var ps: PackedScene = load(ENEMY_SCENE)
	if ps == null:
		return
	# The 2D twin bails when the region has no "Enemies" node. This one falls
	# back to the region root instead: the 3D builders are new and their
	# container names are not yet load-bearing anywhere, and a debt incident
	# that silently never fires is worse than one parented a level up.
	var host: Node = _current_region_node.get_node_or_null("Enemies")
	if host == null:
		host = _current_region_node
	var e := ps.instantiate()
	if not (e is Node3D):
		e.free()
		return
	if "enemy_type" in e:
		e.enemy_type = "bug"
	if "max_hp" in e:
		e.max_hp = 16
	# POSITION BEFORE add_child, and again after. enemy3d.gd's `_ready` caches
	# `_home = Map3D.to_map(global_position)` — the point it leashes back to —
	# so a bug placed only after being parented adopts a home of (0,0) and
	# wanders toward the corner of the map whenever it loses aggro. The local
	# write lands before `_ready` runs (a builder's containers sit at the
	# origin, so local == global); the global write after it corrects for a
	# container that does not.
	var at := Map3D.to3d(_incident_spot(Map3D.to_map(player.global_position)), 0.0)
	(e as Node3D).position = at
	host.add_child(e)
	(e as Node3D).global_position = at
	# The 2D twin's red post-process pulse, "so the incident is felt before it
	# is seen". There is no full-frame post here (see `_refresh_stress`), so the
	# room itself flares instead: one short production-red light where the bug
	# crawls out. Same colour, same duration, same job.
	Fx3D.flash(self, at + Vector3(0.0, 0.6, 0.0), Color("#FF4757"), 5.0, 0.45)

## Where a debt incident's bug arrives: a ring around the player, but INSIDE
## the room — a bug 180-260 units into the masonry depenetrates against a
## static collider and can neither reach the player nor be walked up to. All in
## MAP PIXELS, because the room rect is.
func _incident_spot(from: Vector2) -> Vector2:
	const INSET := 130.0
	var dist := randf_range(180.0, 260.0)
	if _region_size == Vector2.ZERO:
		# No usable bounds (a rig with no region): keep the plain ring.
		var a := randf() * TAU
		return from + Vector2(cos(a), sin(a)) * dist
	var lo := Vector2(INSET, INSET)
	var hi := _region_size - Vector2(INSET, INSET)
	if hi.x <= lo.x or hi.y <= lo.y:
		var a2 := randf() * TAU
		return from + Vector2(cos(a2), sin(a2)) * dist
	# Eight bearings from a random start, so the choice is still a ring and not
	# a preferred side; the first one that lands in the room wins.
	var start := randf() * TAU
	for i: int in range(8):
		var ang: float = start + float(i) * TAU / 8.0
		var p: Vector2 = from + Vector2(cos(ang), sin(ang)) * dist
		if p.x >= lo.x and p.x <= hi.x and p.y >= lo.y and p.y <= hi.y:
			return p
	# Boxed in on every bearing (a room smaller than the ring): clamp inward.
	return Vector2(clampf(from.x, lo.x, hi.x), clampf(from.y, lo.y, hi.y))

## --- region changes and death ----------------------------------------------

func _on_region_changed(region_id: String) -> void:
	_load_region(region_id)
	QuestManager.on_region_entered(region_id)
	if player and player.has_method("grant_spawn_grace"):
		player.grant_spawn_grace(1.8)

func on_region_changed(region_id: String) -> void:
	_on_region_changed(region_id)

func _on_player_died(msg: String = "") -> void:
	get_tree().paused = false
	# Clear any transient overlay that could sit over the death screen and eat
	# the respawn click (e.g. a flavor popup that was open when you died).
	for n in hud.get_children():
		if n.name in ["FlavorPopup", "IntroHint"]:
			n.queue_free()
	# Idempotent: never stack death screens (see the player.died wiring note).
	if hud.get_node_or_null("DeathScreen"):
		return
	var death_scene := preload("res://scenes/ui/death_screen.tscn")
	var death = death_scene.instantiate()
	death.name = "DeathScreen"
	hud.add_child(death)  # screen-space overlay (see _open_pause)
	# Prefer the actual cause of death over the death screen's random pool line.
	# Must come after add_child so the screen's _ready has resolved its labels.
	death._set_message(msg)

## Shows a full-screen overlay (victory/etc.) in the HUD's screen space.
func show_overlay(node: Node) -> void:
	hud.add_child(node)

## --- input and modals ------------------------------------------------------

## Pause is handled in _input (not _unhandled_input) because Escape also maps
## to ui_cancel, which a focused Control can swallow before it reaches
## _unhandled_input — that's why the menu-toggle keys worked but Esc didn't.
func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause") or event.is_echo():
		return
	# Don't hijack Escape while a modal popup, dialogue, or panel is up.
	if EventManager.has_active_event() or DialogueManager.is_active or UIManager.has_blocking_ui():
		return
	if GameManager.state == GameManager.GameState.PLAYING:
		_open_pause()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quest_log"):
		_toggle_quest_log()
	if event.is_action_pressed("dream_app"):
		_toggle_dream_app()
	if event.is_action_pressed("map"):
		_toggle_map()

func _open_pause() -> void:
	GameManager.pause_game(true)
	var pause := preload("res://scenes/ui/pause_menu.tscn").instantiate()
	# Overlays MUST live under the HUD CanvasLayer (screen space). Adding a
	# Control under the world Node3D gives it no canvas transform at all.
	hud.add_child(pause)

func _close_pause() -> void:
	GameManager.pause_game(false)
	for c in hud.get_children():
		if c.name == "PauseMenu":
			c.queue_free()

## KEEP THESE THREE NAMES. tools/quality_capture.gd (and its 3D twin) call them
## by string to photograph the modals.
func _toggle_quest_log() -> void:
	_toggle_modal_panel("QuestLogPanel", preload("res://scenes/ui/quest_log.tscn"))

func _toggle_dream_app() -> void:
	_toggle_modal_panel("DreamAppPanel", preload("res://scenes/ui/dream_app_panel.tscn"))

func _toggle_map() -> void:
	_toggle_modal_panel("MapPanel", preload("res://scenes/ui/map_panel.tscn"))

func _toggle_modal_panel(panel_name: String, scene: PackedScene) -> void:
	var existing := hud.get_node_or_null(panel_name)
	if existing:
		existing.queue_free()
		return
	var panel := scene.instantiate()
	panel.name = panel_name
	if panel.has_method("register_modal"):
		panel.register_modal()
	elif panel is Control:
		panel.tree_exiting.connect(func(): UIManager.pop_modal())
		UIManager.push_modal()
	hud.add_child(panel)
