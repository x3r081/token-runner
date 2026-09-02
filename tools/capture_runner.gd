extends Node

func _ready() -> void:
	await get_tree().create_timer(0.3).timeout
	await _capture_sequence()
	get_tree().quit(0)

func _capture_sequence() -> void:
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")
	await get_tree().create_timer(0.8).timeout
	await _shot("00_main_menu.png")

	GameManager.show_opening_sequence = false
	get_tree().change_scene_to_file("res://scenes/world/world.tscn")
	await get_tree().create_timer(1.2).timeout

	var world := get_tree().current_scene
	var player: Node = world.get_node_or_null("Player") if world else null
	if player:
		player.can_move = true
	await _shot("01_localhost_establishing.png")

	DialogueManager.start_dialogue("roommate_ai", "greeting")
	await get_tree().create_timer(0.4).timeout
	await _shot("02_npc_interaction.png")
	DialogueManager.end_dialogue()

	if player:
		player.global_position = Vector2(750, 480)
	await get_tree().create_timer(0.4).timeout
	await _shot("03_token_collection.png")

	if world and world.has_method("_toggle_dream_app"):
		world._toggle_dream_app()
		await get_tree().create_timer(0.4).timeout
		await _shot("04_dream_app_ui.png")

	print("Screenshot capture complete.")

func _shot(name: String) -> void:
	var dir := ProjectSettings.globalize_path("res://docs/screenshots")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir + "/" + name
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	_encode(img)
	if img.get_width() != 1920 or img.get_height() != 1080:
		img.resize(1920, 1080, Image.INTERPOLATE_LANCZOS)
	var err: Error = img.save_png(path)
	if err == OK:
		print("  Saved ", name, " (", img.get_width(), "x", img.get_height(), ")")
	else:
		push_error("Failed: " + name)

## project.godot runs hdr_2d=true, so the 2D framebuffer is LINEAR and
## Viewport.get_texture().get_image() hands it back BEFORE the compositor's
## linear->sRGB encode. Saving it raw bakes a ~2.2 gamma crush into the PNG
## (TEXT #D8DEEA lands at 175, not 216). See tools/quality_capture.gd.
func _encode(img: Image) -> void:
	if not get_viewport().use_hdr_2d:
		return
	if img.get_format() != Image.FORMAT_RGBA8 and img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGBA8)
	img.linear_to_srgb()
