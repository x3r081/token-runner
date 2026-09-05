extends Node
## THE 3D WORLD, ASSERTED — the suite that says whether the conversion is a game
## or a diorama (3D_BIBLE.md §10).
##
## Run: godot --headless --path . --scene tests/world3d_test.tscn
##
## Everything here tests ONE claim: the gameplay brain is untouched and still
## speaks map pixels, while the thing you look at is 3D. That claim has exactly
## three failure modes, and each has assertions below:
##
##   1. THE COORDINATE LAW SLIPS (§2.3). `GameManager.region_spawn` is read by
##      saves, the map panel, the quest resolvers and every test in the repo. If
##      the 3D layer ever writes WORLD units into it, nothing crashes: the number
##      is just 64x too small, the player spawns in the corner of every room and
##      the map panel draws a dot in the top-left forever. So the spawn is
##      checked for MAGNITUDE, not merely for type, and the player's own 3D
##      position is round-tripped through Map3D against it.
##   2. THE SHADOW PROXIES ARE MISSING (§5). objective_waypoint.gd and
##      guide_overlay.gd read actors by GROUP and expect Node2D positions. With
##      no proxies the game renders perfectly and every piece of guidance
##      silently disappears — no chevron, no bearings, no idle nudge — which is
##      precisely the class of defect a screenshot cannot catch. So every actor
##      group is checked for a Node2D member, and the waypoint is asked out loud
##      whether it resolved a target.
##   3. A REGION FAILS TO BUILD. Ten rooms, ten chances for a missing model key
##      to return an empty dictionary.
##
## The suite is exists()-guarded end to end: sibling tracks land world3d.tscn and
## region_builder3d.gd concurrently, and a suite that hard-fails on a file that
## has not been written yet is noise, not signal. Absent files print a NOTE and
## the run passes with zero assertions.

const WORLD3D_PATH := "res://scenes/world3d/world3d.tscn"
const REGION_BUILDER3D_PATH := "res://scripts/world3d/region_builder3d.gd"
const LOCALHOST_BUILDER3D_PATH := "res://scripts/world3d/localhost_builder3d.gd"

## The room the actor assertions run in. Localhost is an apartment: it stocks
## NPCs, props and a portal but deliberately no enemies and no loose tokens, so
## asserting "there is an enemy proxy" there would be asserting a design bug.
const COMBAT_REGION := "dependency_district"

## How long a region rebuild gets before the frame is inspected. §9 budgets the
## rebuild itself at under 0.5s; the rest is the deferred build, the camera
## settle and one proxy sync.
const REGION_WAIT := 1.2

var passed := 0
var failed := 0

func _ready() -> void:
	await _run()
	print("WORLD3D TESTS: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _run() -> void:
	if not ResourceLoader.exists(WORLD3D_PATH):
		_note("%s is not on disk — the 3D suite is skipped, not failed" % WORLD3D_PATH)
		return
	var packed: PackedScene = load(WORLD3D_PATH)
	if packed == null:
		_check("world3d_scene_loads", false)
		return

	# A real run's worth of state: the starter quest has to be active or the
	# waypoint has nothing to resolve and the last assertion tests nothing.
	QuestManager.reset()
	GameManager.show_opening_sequence = false
	GameManager.current_region = "localhost"
	GameManager.regions_unlocked = ["localhost", COMBAT_REGION]
	GameManager.state = GameManager.GameState.PLAYING

	var world: Node = packed.instantiate()
	add_child(world)
	await _wait(REGION_WAIT)

	_check("world_root_in_group_world", world.is_in_group("world"))
	await _test_player(world)
	_test_stage3d()
	_test_spawn_is_map_pixels()
	await _test_actors_and_waypoint(world)
	await _test_prop_objective_resolves(world)

	# The live world goes FIRST, and the bare region builds run in the empty
	# tree behind it. A region built while world3d is mounted parents its
	# ActorProxy nodes under the LIVE "proxy_root" (§5) and its actors join the
	# live groups, so ten throwaway rooms would be walking through every group
	# scan above. Order is the whole fix.
	world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await _test_region_builds()

# ------------------------------------------------------------------- player --
##
## Two nodes, one player: the CharacterBody3D that group "player" holds (every
## manager, the HUD and the death flow read it) and the Node2D in group
## "player_proxy" that the UI reads. They must agree, through Map3D and nothing
## else — a proxy that drifts is worse than no proxy, because the chevron then
## points confidently at the wrong place.
func _test_player(_world: Node) -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	_check("player_in_group_player", player != null)
	_check("player_is_characterbody3d", player is CharacterBody3D)
	var proxy: Node = get_tree().get_first_node_in_group("player_proxy")
	_check("player_proxy_exists", proxy != null)
	_check("player_proxy_is_node2d", proxy is Node2D)
	# The proxy must NOT also be in group "player": UI code that wants the body
	# (guide_overlay's `can_move` check) resolves that group and would find a
	# Node2D with no such flag.
	_check("player_proxy_not_in_group_player", proxy == null or not proxy.is_in_group("player"))
	if player is Node3D and proxy is Node2D:
		await get_tree().process_frame
		var mapped := Map3D.to_map((player as Node3D).global_position)
		var drift := mapped.distance_to((proxy as Node2D).global_position)
		_check("player_proxy_tracks_body_in_map_px (drift %.1f px)" % drift, drift < 8.0)

# ------------------------------------------------------------------ stage3d --
##
## The one node that makes the 2D UI work over a 3D world. objective_waypoint.gd
## asks it to project a MAP-PIXEL position into window pixels and to say how many
## window pixels one map pixel spans; without it the chevron falls back to the
## main viewport's canvas transform, which has no camera, and pins itself to the
## raw world origin.
func _test_stage3d() -> void:
	var stage: Node = get_tree().get_first_node_in_group("stage3d")
	_check("stage3d_in_group", stage != null)
	if stage == null:
		return
	_check("stage3d_has_world_to_ui", stage.has_method("world_to_ui"))
	_check("stage3d_has_world_to_ui_scale", stage.has_method("world_to_ui_scale"))
	if stage.has_method("world_to_ui_scale"):
		var k: float = stage.call("world_to_ui_scale")
		_check("stage3d_scale_is_positive (%.3f)" % k, k > 0.0)
	if stage.has_method("world_to_ui"):
		var a: Vector2 = stage.call("world_to_ui", Vector2(200.0, 200.0))
		var b: Vector2 = stage.call("world_to_ui", Vector2(400.0, 200.0))
		# Moving EAST in map space must move RIGHT on screen. A sign flip here is
		# a chevron that points at the mirror image of the objective.
		_check("stage3d_projection_preserves_east", b.x > a.x)

# --------------------------------------------------------------- coordinates --
##
## §2.2: managers speak MAP PIXELS. A region is 1280x960 px (the apartment
## 1600x1024), so a legitimate spawn is hundreds of pixels from the origin; the
## same point expressed in WORLD units would be under 25. One order of magnitude
## between the right answer and the wrong one, which is what makes this testable
## at all.
func _test_spawn_is_map_pixels() -> void:
	var spawn: Variant = GameManager.region_spawn
	_check("region_spawn_is_vector2", typeof(spawn) == TYPE_VECTOR2)
	if typeof(spawn) != TYPE_VECTOR2:
		return
	var s: Vector2 = spawn
	_check("region_spawn_in_map_px_not_world_units (%s)" % str(s), s.length() > 64.0)
	_check("region_spawn_inside_room (%s)" % str(s),
		s.x > 0.0 and s.y > 0.0 and s.x < 2048.0 and s.y < 1280.0)
	var player: Node = get_tree().get_first_node_in_group("player")
	if player is Node3D:
		var at := Map3D.to_map((player as Node3D).global_position)
		var d := at.distance_to(s)
		_check("player_stands_on_region_spawn (%.1f px away)" % d, d < 96.0)

# ------------------------------------------------------------------ regions --
##
## All ten rooms, built into a bare Node3D. Same contract as the 2D suite:
## `build()` answers with a spawn and a size or the world has nothing to place
## the player against.
func _test_region_builds() -> void:
	var builder: GDScript = _load_script(REGION_BUILDER3D_PATH)
	if builder == null:
		_note("%s not on disk — per-region build assertions skipped" % REGION_BUILDER3D_PATH)
		return
	var localhost: GDScript = _load_script(LOCALHOST_BUILDER3D_PATH)
	var generic := _script_has(builder, "build")
	var specific := _script_has(localhost, "build")
	if not generic and not specific:
		_note("no build() on either 3D builder — per-region build assertions skipped")
		return
	for rid: String in GameManager.REGION_ORDER:
		var root := Node3D.new()
		add_child(root)
		var data: Dictionary = {}
		# Localhost is an authored apartment, not a generated room (§2.4), so it
		# has its own builder — but a RegionBuilder3D that also handles it is a
		# legitimate shape, hence "try the generic one, then the specific one".
		# `.call()`, not `builder.build(...)`: `builder` is statically typed
		# GDScript, and the analyser resolves method names against THAT class —
		# `build` is not one of its members, so the direct form is a parse error
		# rather than a dynamic dispatch. A preloaded const would type-resolve,
		# but preload is exactly what this suite may not do (see `_load_script`).
		# `.call()` answers a Variant; a builder that returns null (or nothing)
		# for a room it does not know must read as "no data", not abort the
		# suite with a typed-assignment error before the other nine rooms run.
		if generic:
			var r: Variant = builder.call("build", root, rid)
			if r is Dictionary:
				data = r
		if data.is_empty() and rid == "localhost" and specific:
			var r2: Variant = localhost.call("build", root)
			if r2 is Dictionary:
				data = r2
		var has_spawn: bool = data.has("spawn") and typeof(data["spawn"]) == TYPE_VECTOR2
		_check("%s builds with spawn+size" % rid, has_spawn and data.has("size"))
		_check("%s spawn is map px" % rid,
			has_spawn and (data["spawn"] as Vector2).length() > 64.0)
		_check("%s builds content" % rid, root.get_child_count() > 0)
		root.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame

# ------------------------------------------------- actors, proxies, waypoint --
##
## The failure this exists for: a beautiful room in which the guidance system is
## blind. Every actor the UI reads by group must have a Node2D standing in for it
## (§5), and the waypoint must be able to say out loud that it found something.
func _test_actors_and_waypoint(world: Node) -> void:
	GameManager.change_region(COMBAT_REGION)
	await _wait(REGION_WAIT)
	_check("change_region_switches_region", GameManager.current_region == COMBAT_REGION)
	_check("change_region_rebuilt_spawn", typeof(GameManager.region_spawn) == TYPE_VECTOR2)

	# Hosts first: no 3D actor at all is a different bug from a missing proxy,
	# and reading one line of output should tell you which you have.
	_check("%s has enemy hosts" % COMBAT_REGION, _count_in_group("enemy", false) > 0)
	_check("%s has enemy proxies" % COMBAT_REGION, _count_in_group("enemy", true) > 0)
	_check("%s has token proxies" % COMBAT_REGION, _count_in_group("token", true) > 0)
	_check("%s has interactable proxies" % COMBAT_REGION, _count_in_group("interactable", true) > 0)
	_check("proxy carries enemy_type", _group_has_field("enemy", "enemy_type"))
	_check("proxy carries token_type", _group_has_field("token", "token_type"))
	_check("a portal proxy carries target_region", _group_has_field("interactable", "target_region"))

	# NPCs live in Localhost; go home for them, which also exercises the return
	# trip through change_region.
	GameManager.change_region("localhost")
	await _wait(REGION_WAIT)
	_check("localhost has npc proxies", _count_in_group("npc", true) > 0)
	_check("proxy carries npc_id", _group_has_field("npc", "npc_id"))

	var hud: Node = world.get_node_or_null("HUD")
	_check("world3d mounts the HUD", hud != null)
	if hud == null:
		return
	var wp: Node = hud.get_node_or_null("ObjectiveWaypoint")
	_check("hud mounts the objective waypoint", wp != null)
	if wp == null:
		return
	wp.call("refresh_now")
	await get_tree().process_frame
	_check("waypoint resolves a target", bool(wp.call("has_target")))
	# `distance_metres()` is the number behind the objective line. With a target
	# but no Node2D player, `_measure()` writes ZERO — and `readout()` still
	# returns a non-empty "0m", so the text alone cannot tell "measured" from
	# "blind". Localhost's spawn (600,640) and Claude (820,560) are ~234 px
	# apart, so a working proxy reads several metres here, never zero.
	var metres: int = int(wp.call("distance_metres"))
	_check("waypoint measures a distance (\"%s\")" % str(wp.call("readout")), metres > 0)

# ------------------------------------------------------------------- helpers --

## Members of `group` that are (or are not) Node2D. In the 3D world both the
## host Node3D and its shadow proxy join the actor groups, so "how many Node2Ds"
## is exactly "how many proxies".
func _count_in_group(group: String, want_2d: bool) -> int:
	var n := 0
	for node: Node in get_tree().get_nodes_in_group(group):
		if not is_instance_valid(node):
			continue
		if (node is Node2D) == want_2d:
			n += 1
	return n

## A Node2D in `group` carrying a non-empty `field` — the same property probe
## objective_waypoint.gd identifies portals, tokens and NPCs by, so if this
## passes the waypoint's resolvers can do their job.
func _group_has_field(group: String, field: String) -> bool:
	for node: Node in get_tree().get_nodes_in_group(group):
		if not (node is Node2D) or not is_instance_valid(node):
			continue
		if field in node and str(node.get(field)) != "":
			return true
	return false

## Load a sibling track's script without preloading it: preload is resolved at
## parse time, so a file that has not landed yet would kill this whole suite.
func _load_script(path: String) -> GDScript:
	if not ResourceLoader.exists(path):
		return null
	var s: Resource = load(path)
	return s as GDScript

## Does the script DECLARE this function? `Object.has_method()` on a GDScript
## resource answers for Resource's own methods, not for the static functions the
## script declares, so the builders' `build()` has to be looked up in the script
## method list instead.
func _script_has(s: GDScript, method: String) -> bool:
	if s == null:
		return false
	for m: Dictionary in s.get_script_method_list():
		if str(m.get("name", "")) == method:
			return true
	return false

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().process_frame

func _check(label: String, condition: bool) -> void:
	if condition:
		print("  PASS: %s" % label)
		passed += 1
	else:
		print("  FAIL: %s" % label)
		failed += 1

## Neither a pass nor a fail: a thing that could not be tested yet, said out
## loud so a green run is never mistaken for a complete one.
func _note(text: String) -> void:
	print("  NOTE: %s" % text)


## REGRESSION — the first quest chain must never loop between portals.
## morning_ritual targets prop_coffee, an Interactable3D in the apartment. Its
## ActorProxy declares EVERY mirrored field, so a waypoint that classified NPCs
## by `"npc_id" in node` skipped every prop and fell back to "Way out" — the
## player was bounced Localhost <-> Dependency District with nothing to do.
func _test_prop_objective_resolves(world: Node) -> void:
	QuestManager.on_talk("roommate_ai")
	QuestManager.on_token_collected(10)
	await get_tree().process_frame
	var obj := QuestManager.get_current_objective()
	_check("after hello_localhost the current objective is prop_coffee (got %s)" % str(obj.get("node_id", "")), str(obj.get("node_id", "")) == "prop_coffee")
	var wp: Node = get_tree().get_first_node_in_group("objective_waypoint")
	if wp == null and is_instance_valid(world):
		wp = world.get_node_or_null("HUD/ObjectiveWaypoint")
	_check("objective waypoint is reachable (group or HUD child)", wp != null)
	if wp == null:
		return
	wp.refresh_now()
	await get_tree().create_timer(0.3).timeout
	var target = wp.target_node()
	_check("waypoint resolves prop_coffee (target=%s)" % str(target), target != null and "interact_id" in target and str(target.get("interact_id")) == "prop_coffee")
	_check("waypoint is NOT in 'Way out' fallback for an in-room prop objective", not bool(wp.get("_fallback")))
