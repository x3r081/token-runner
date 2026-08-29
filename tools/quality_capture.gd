extends Node
## Full-coverage visual QA capture: menu, every region, and key UI surfaces.
## Run WINDOWED (rendering required): godot --path . res://tools/quality_capture.tscn
## Writes to docs/screenshots/qa/.

const OUT := "res://docs/screenshots/qa"

func _ready() -> void:
	await get_tree().process_frame
	# This node IS current_scene, so change_scene_to_file() would free it
	# mid-coroutine. Vacating the slot lets the capture run survive.
	get_tree().current_scene = null
	await _run()
	get_tree().quit(0)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))

	# Main menu.
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")
	await _settle(1.2)
	await _shot("menu.png")

	# Enter world without the opening cutscene.
	GameManager.show_opening_sequence = false
	get_tree().change_scene_to_file("res://scenes/world/world.tscn")
	await _settle(1.6)
	var world: Node = get_tree().get_first_node_in_group("world")
	if world == null:
		push_error("world failed to load")
		return
	var player: Node = world.get_node_or_null("Player")
	if player and "can_move" in player:
		player.can_move = true
	await _shot("region_localhost.png")

	# Dialogue surface.
	DialogueManager.start_dialogue("roommate_ai")
	await _settle(0.6)
	await _shot("ui_dialogue.png")
	if DialogueManager.has_method("end_dialogue"):
		DialogueManager.end_dialogue()
	await _settle(0.3)

	# UI panels.
	for m in [["_toggle_dream_app", "ui_dream_app.png"], ["_toggle_quest_log", "ui_quest_log.png"], ["_toggle_map", "ui_map.png"]]:
		if world.has_method(m[0]):
			world.call(m[0])
			await _settle(0.5)
			await _shot(m[1])
			world.call(m[0])  # close again
			await _settle(0.3)

	# Every region.
	for rid in GameManager.REGION_ORDER:
		if rid == "localhost":
			continue
		GameManager.unlock_region(rid)
		GameManager.change_region(rid)
		await _settle(1.4)
		await _shot("region_%s.png" % rid)

	print("QA capture complete -> ", ProjectSettings.globalize_path(OUT))

## Random events fire on a timer, pause the tree and cover the frame — none of
## which belongs in a visual QA capture.
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

func _settle(t: float) -> void:
	_quiet()
	await get_tree().create_timer(t).timeout
	_quiet()

func _shot(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT) + "/" + fname)
	print("shot: ", fname)
