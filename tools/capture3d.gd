extends Node
## VISUAL QA FOR THE 3D CONVERSION — the twin of tools/quality_capture.gd, aimed
## at scenes/world3d/world3d.tscn (3D_BIBLE.md §10).
##
## Run WINDOWED (rendering required):
##     godot --path . res://tools/capture3d.tscn
## Writes to docs/screenshots/qa3d/.
##
## It photographs the same surfaces the 2D tool does — the menu, Localhost, the
## dialogue screen, the three modal panels, every region — because those are the
## frames a reviewer compares side by side to answer "is this the same game with
## better graphics, or a different game?". Two things are new:
##
##   * THE DIALOGUE SHOT IS TAKEN ON A CHOICE. Claude's opening lines end in a
##     branch, and a screenshot of a plain line proves only that a text box
##     renders. Advancing to `pending_choices` proves the whole dialogue UI —
##     buttons, focus, layout — survived the port.
##   * EVERY REGION PRINTS ITS BUDGET (§9): MeshInstance3D / MultiMeshInstance3D
##     / OmniLight3D / shadow-casting lights / GPUParticles3D. A frame can look
##     right and still be 3,000 draw calls; a number cannot. These lines are the
##     evidence for the budget claims, and they cost one node walk per room.
##
## HANDOVER gotcha 7: this node IS `current_scene`, so the slot is vacated before
## the first `change_scene_to_file()` or the engine frees this script's coroutine
## halfway through the run. HANDOVER gotcha 11: `get_image()` hands back the raw
## LINEAR buffer under `hdr_2d`, so every frame is encoded to sRGB before it is
## written or it lands ~2 stops dark — see `_encode`.

const OUT := "res://docs/screenshots/qa3d"

## How long after the last `_quiet()` the shot is taken. See `_settle`.
const QUIET_BEAT := 0.35
## Region loads rebuild a whole room of Kenney meshes; give them longer to settle
## than the 2D tool needs (§9 budgets a rebuild at under 0.5s, plus the camera
## settle and the fog/ambient retint).
const REGION_SETTLE := 1.8
## How many `advance()` calls the dialogue shot will spend looking for a branch
## before it settles for whatever line is on screen.
const CHOICE_TRIES := 8
## How close to an enemy the player is parked for the combat frame, in MAP
## PIXELS — inside a typical aggro radius, outside contact range.
const AGGRO_STANDOFF := 96.0

var _combat_done := false

func _ready() -> void:
	await get_tree().process_frame
	# This node IS current_scene, so change_scene_to_file() would free it
	# mid-coroutine. Vacating the slot lets the capture run survive.
	get_tree().current_scene = null
	await _run()
	get_tree().quit(0)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))

	# Main menu — unchanged by the conversion, and that is the point: it is the
	# control frame for every judgement about the rooms behind it.
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")
	await _settle(1.2)
	await _shot("menu.png")

	# GameManager.world_scene() falls back to the 2D world when the 3D one is
	# missing, which for THIS tool would silently produce a full set of frames of
	# the wrong game. Refuse BEFORE start_new_game() so the check gates the load
	# that actually happens rather than a second one after it.
	var scene: String = GameManager.WORLD_SCENE_3D
	if not ResourceLoader.exists(scene):
		push_error("capture3d: %s is not on disk — refusing to photograph the 2D world" % scene)
		return

	# A REAL run: start_new_game() activates the starter quest, which is what the
	# waypoint chevron and the guide overlay key off. An empty quest log
	# photographs a game with no guidance in it. It also changes scene to
	# world_scene() == WORLD_SCENE_3D (checked above), so no second load here:
	# a 3D room is a few hundred Kenney meshes and a full retint, and the 2D
	# tool's load-twice idiom would build Localhost twice and let the opening
	# sequence start on the first copy.
	GameManager.start_new_game()
	# change_scene_to_file() is deferred to the end of this frame, so the flag
	# lands before world3d._ready() reads it. The opening sequence is a separate
	# surface with its own capture; here it would just be twelve seconds of
	# black between the menu and the world.
	GameManager.show_opening_sequence = false
	await _settle(2.0)

	var world: Node = get_tree().get_first_node_in_group("world")
	if world == null:
		push_error("capture3d: world3d failed to load")
		return
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null and "can_move" in player:
		player.set("can_move", true)
	await _shot("region_localhost.png")
	_budget(world, "localhost")
	_proxy_report()

	# The dialogue surface, ON A CHOICE. See the header.
	await _dialogue_shot()

	# The three modal panels. world3d.gd keeps world.gd's method names precisely
	# so this loop does not need a second version of itself (3D_BIBLE §3).
	for m: Array in [["_toggle_dream_app", "ui_dream_app.png"],
			["_toggle_quest_log", "ui_quest_log.png"],
			["_toggle_map", "ui_map.png"]]:
		var method := str(m[0])
		if not world.has_method(method):
			push_warning("capture3d: world3d has no %s — %s skipped" % [method, str(m[1])])
			continue
		world.call(method)
		await _settle(0.6)
		await _shot(str(m[1]))
		world.call(method)  # close again
		await _settle(0.35)

	# Every region, in play order, with its budget line.
	for rid: String in GameManager.REGION_ORDER:
		if rid == "localhost":
			continue
		GameManager.unlock_region(rid)
		GameManager.change_region(rid)
		await _settle(REGION_SETTLE)
		await _shot("region_%s.png" % rid)
		_budget(world, rid)
		# The first room that actually stocks enemies also gets the combat frame.
		if not _combat_done:
			await _combat_shot(rid)

	print("QA3D capture complete -> ", ProjectSettings.globalize_path(OUT))

# ------------------------------------------------------------------ dialogue --
##
## Claude's greeting is assembled at runtime (`build_claude_lines`) and the
## branch is not at a fixed index, so advance until `pending_choices` fills or
## the lines run out. Photographing whatever is on screen at that point is still
## a useful frame — it just gets a name that does not claim to be a choice.
func _dialogue_shot() -> void:
	DialogueManager.start_dialogue("roommate_ai")
	await _settle(0.7)
	var tries := 0
	while DialogueManager.is_active and DialogueManager.pending_choices.is_empty() \
			and tries < CHOICE_TRIES:
		DialogueManager.advance()
		tries += 1
		await _settle(0.45)
	if not DialogueManager.is_active:
		push_warning("capture3d: dialogue ended before a choice appeared")
	elif DialogueManager.pending_choices.is_empty():
		await _shot("ui_dialogue.png")
	else:
		await _shot("ui_dialogue_choice.png")
	if DialogueManager.is_active:
		DialogueManager.end_dialogue()
	await _settle(0.4)

# -------------------------------------------------------------------- combat --
##
## Aggro, bought as cheaply as the actor contracts allow: park the player next to
## an enemy and let the enemy's own leash logic do the rest. `respawn(pos)` takes
## MAP PIXELS (3D_BIBLE §4) and is the only sanctioned way to move the player
## from outside, so the enemy's position has to be read in map pixels too — which
## is exactly what its shadow proxy carries (§5). The Node3D and its Node2D proxy
## are BOTH in group "enemy", so the scan filters for the Node2D.
func _combat_shot(region_id: String) -> void:
	var target: Node2D = null
	for n: Node in get_tree().get_nodes_in_group("enemy"):
		if n is Node2D and is_instance_valid(n):
			target = n as Node2D
			break
	if target == null:
		return
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("respawn"):
		return
	player.call("respawn", target.global_position + Vector2(AGGRO_STANDOFF, 0.0))
	await _settle(1.4)
	await _shot("combat_%s.png" % region_id)
	_combat_done = true

# ------------------------------------------------------------------- budgets --
##
## 3D_BIBLE §9: <= 700 MeshInstance3D per region (floors go through MultiMesh),
## <= 40 OmniLight3D with <= 3 casting shadows, <= 12 GPUParticles3D. Printed
## rather than asserted — a capture tool that aborts halfway leaves the reviewer
## with fewer frames than a capture tool that prints a red number and carries on.
##
## `owned = false`: every node in a region is built at runtime, so none of them
## has an owner and the default (owned) walk would count nothing at all.
func _budget(world: Node, region_id: String) -> void:
	var meshes := world.find_children("*", "MeshInstance3D", true, false).size()
	var multi := world.find_children("*", "MultiMeshInstance3D", true, false).size()
	var particles := world.find_children("*", "GPUParticles3D", true, false).size()
	var lights := world.find_children("*", "OmniLight3D", true, false)
	var shadowed := 0
	for l: Node in lights:
		if l is Light3D and (l as Light3D).shadow_enabled:
			shadowed += 1
	var verdict := "OK"
	if meshes > 700 or lights.size() > 40 or shadowed > 3 or particles > 12:
		verdict = "OVER BUDGET"
	print("BUDGET %-24s mesh=%d multimesh=%d omni=%d (shadow %d) particles=%d  %s"
		% [region_id, meshes, multi, lights.size(), shadowed, particles, verdict])

## What the UI can actually see. objective_waypoint.gd and guide_overlay.gd read
## actors by GROUP and expect Node2D positions in map pixels; if the proxies (§5)
## are missing, every frame below still renders beautifully and the guidance is
## silently gone. One line says whether that happened.
func _proxy_report() -> void:
	var parts := PackedStringArray()
	for g: String in ["player_proxy", "enemy", "npc", "token", "interactable"]:
		var total := 0
		var two_d := 0
		for n: Node in get_tree().get_nodes_in_group(g):
			total += 1
			if n is Node2D:
				two_d += 1
		parts.append("%s %d/%d" % [g, two_d, total])
	print("PROXIES (Node2D of total in group)  ", " · ".join(parts))
	var stage: Node = get_tree().get_first_node_in_group("stage3d")
	print("STAGE3D  present=%s  world_to_ui=%s  scale=%s" % [
		str(stage != null),
		str(stage != null and stage.has_method("world_to_ui")),
		str(stage.call("world_to_ui_scale")) if stage != null and stage.has_method("world_to_ui_scale") else "n/a",
	])

# ---------------------------------------------------------------- plumbing ----
##
## Everything below is quality_capture.gd's, unchanged in behaviour: random
## events fire on a timer, pause the tree and cover the frame, and none of that
## belongs in a visual QA capture.
func _quiet() -> void:
	if EventManager:
		EventManager.cooldown = 99999.0
		if EventManager.has_method("has_active_event") and EventManager.has_active_event():
			EventManager.active_event = {}
	var popup := get_tree().get_first_node_in_group("event_popup")
	if popup and popup.has_method("hide"):
		popup.hide()
	for n in get_tree().root.find_children("*EventPopup*", "", true, false):
		n.visible = false
	get_tree().paused = false

## The quiet happens EARLY and the frame is taken LATE. Nodes that hide
## themselves while an event is up (objective_waypoint.gd `_should_hide`) only
## come back on their NEXT tick, so clearing the event and shooting on the same
## frame photographs a game with no guidance in it — which is how the 2D round
## lost the chevron in production and corporate_enterprise.
func _settle(t: float) -> void:
	_quiet()
	await get_tree().create_timer(maxf(t - QUIET_BEAT, t * 0.5)).timeout
	_quiet()
	await get_tree().create_timer(QUIET_BEAT).timeout

func _shot(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_encode(img)
	img.save_png(ProjectSettings.globalize_path(OUT) + "/" + fname)
	print("shot: ", fname)

## HANDOVER gotcha 11. project.godot runs `rendering/viewport/hdr_2d=true`, so
## the framebuffer is LINEAR: the compositor applies the linear->sRGB encode on
## its way to the monitor, but `get_texture().get_image()` hands back the raw
## buffer BEFORE that encode. Saving it straight to PNG bakes a ~2.2 gamma crush
## into every QA frame and every visual judgement made from it.
func _encode(img: Image) -> void:
	if not get_viewport().use_hdr_2d:
		return
	if img.get_format() != Image.FORMAT_RGBA8 and img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGBA8)
	img.linear_to_srgb()
