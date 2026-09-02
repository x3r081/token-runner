extends Node
## Regression capture for the dialogue-choice overflow bug: opens Claude's
## greeting, advances to the choice block, and screenshots the frame so a human
## (or agent) can verify every choice button is on-screen.
## Run WINDOWED: godot --path . res://tools/capture_dialogue_choices.tscn
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
	GameManager.start_new_game()
	await _settle(0.3)
	GameManager.show_opening_sequence = false
	get_tree().change_scene_to_file("res://scenes/world/world.tscn")
	await _settle(1.6)

	# First conversation of a fresh run: stacked greeting lines + the backups
	# choice block — the exact frame that used to push choices off-screen.
	DialogueManager.start_dialogue("roommate_ai")
	await _settle(0.4)
	var guard := 0
	while DialogueManager.is_active and DialogueManager.pending_choices.is_empty() and guard < 30:
		DialogueManager.advance()
		await _settle(0.25)
		guard += 1
	if DialogueManager.pending_choices.is_empty():
		push_error("never reached a choice block")
	await _settle(0.6)
	await _shot("ui_dialogue_choices.png")

	# Follow the guidance door one level deeper (plan topic) — a second choice
	# block, reached via goto, with its own text length.
	if not DialogueManager.pending_choices.is_empty():
		DialogueManager.select_choice(0)
		await _settle(0.4)
		guard = 0
		while DialogueManager.is_active and DialogueManager.pending_choices.is_empty() and guard < 30:
			DialogueManager.advance()
			await _settle(0.25)
			guard += 1
		await _settle(0.6)
		await _shot("ui_dialogue_choices_plan.png")

	print("dialogue-choice capture complete -> ", ProjectSettings.globalize_path(OUT))

func _quiet() -> void:
	if EventManager:
		EventManager.cooldown = 99999.0
		if EventManager.has_method("has_active_event") and EventManager.has_active_event():
			EventManager.active_event = {}
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
	_encode(img)
	img.save_png(ProjectSettings.globalize_path(OUT) + "/" + fname)
	print("shot: ", fname)

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
