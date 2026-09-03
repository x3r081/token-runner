extends Node
## Full-coverage visual QA capture: menu, every region, and key UI surfaces.
## Run WINDOWED (rendering required): godot --path . res://tools/quality_capture.tscn
## Writes to docs/screenshots/qa/.

const OUT := "res://docs/screenshots/qa"

## How long after the last `_quiet()` the shot is taken. See `_settle`.
const QUIET_BEAT := 0.35

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

	# Start a REAL run: start_new_game() activates the starter quest, which is
	# what the waypoint and guide overlay key off. Then skip the cutscene.
	GameManager.start_new_game()
	await _settle(0.3)
	GameManager.show_opening_sequence = false
	get_tree().change_scene_to_file("res://scenes/world/world.tscn")
	await _settle(1.6)
	var world: Node = get_tree().get_first_node_in_group("world")
	if world == null:
		push_error("world failed to load")
		return
	var player: Node = _player_of(world)
	if player and "can_move" in player:
		player.can_move = true
	await _shot("region_localhost.png")
	_prove_grid(world, player, "region_localhost.png")
	await _wide_shot(world, player)

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

	# The two full-screen modals nothing else in this project ever photographs.
	# They are the surfaces most likely to break silently: both are mounted on the
	# HUD layer AFTER world._ready() has run, so they inherit the pixel stage's
	# letterbox fit from their parent rather than being fitted themselves — and if
	# that parenting ever changes they will anchor to the WINDOW, 320px outside
	# the world, with no test able to say so. Photograph them.
	if world.has_method("_open_pause"):
		world.call("_open_pause")
		await _settle(0.6)
		await _shot("ui_pause.png")
		_report_modal(world, "PauseMenu", world.get_node_or_null("PixelStage"))
		var pause: Node = world.get("hud").get_node_or_null("PauseMenu")
		if pause:
			pause.queue_free()
		get_tree().paused = false
		GameManager.state = GameManager.GameState.PLAYING
		await _settle(0.4)

	if world.has_method("_on_player_died"):
		world.call("_on_player_died", "the agent deleted the database")
		await _settle(0.7)
		await _shot("ui_death.png")
		var death: Node = world.get("hud").get_node_or_null("DeathScreen")
		if death:
			death.queue_free()
		get_tree().paused = false
		GameManager.state = GameManager.GameState.PLAYING
		await _settle(0.4)

	# The [H] guide overlay — the answer to "what do I do now". UIManager owns
	# the only instance and the methods are open_guide/close_guide, NOT
	# open/close: the old name-sniffing loop matched nothing and silently
	# skipped the shot, so [H] went uncaptured for every QA round.
	var guide: Node = UIManager.guide() if UIManager.has_method("guide") else null
	if is_instance_valid(guide) and guide.has_method("open_guide"):
		guide.call("open_guide")
		await _settle(0.6)
		await _shot("ui_guide.png")
		if guide.has_method("close_guide"):
			guide.call("close_guide")
		await _settle(0.3)
	else:
		push_warning("guide overlay not mounted — ui_guide.png skipped")

	# Every region.
	for rid in GameManager.REGION_ORDER:
		if rid == "localhost":
			continue
		GameManager.unlock_region(rid)
		GameManager.change_region(rid)
		await _settle(1.4)
		await _shot("region_%s.png" % rid)

	print("QA capture complete -> ", ProjectSettings.globalize_path(OUT))

## The player moved into the pixel stage's SubViewport this round, so
## `world.get_node("Player")` no longer resolves. The group is the stable handle
## and always was.
func _player_of(world: Node) -> Node:
	var p := world.get_node_or_null("PixelStage/Viewport/Player")
	if p != null:
		return p
	return get_tree().get_first_node_in_group("player")

# ---------------------------------------------------------- the grid proof --
##
## VISUAL_BIBLE_V2 LAW 1 asks for exactly K screen pixels per art pixel, K a
## whole number, and until this round the game did not deliver it: a 1649x928
## window under `canvas_items` stretch against a 1920x1080 base magnified every
## sprite by 0.859, so a 2.0-scaled 32px character at camera zoom 1.6 landed on
## 2.75 screen pixels and the frames showed runs of 2 and 3 alternating down its
## edges. A screenshot cannot be eyeballed for that; it has to be measured.
##
## The test: take the row through the player's centre and the column through it,
## walk them, and record the length of every run of identical pixels. If the grid
## is real, every run INSIDE the sprite is a multiple of K — the art has no
## feature narrower than one art pixel, and one art pixel is K screen pixels. The
## two runs at either end of the scan are allowed to be partial: they begin and
## end in the middle of whatever the sprite is standing on.
func _prove_grid(world: Node, player: Node, fname: String) -> void:
	var stage: Node = world.get_node_or_null("PixelStage")
	if stage == null or player == null:
		push_error("grid proof: no stage or no player")
		return
	var k: int = int(stage.get("stage_k"))
	var rect: Rect2 = stage.get("world_rect")
	var img := Image.load_from_file(ProjectSettings.globalize_path(OUT) + "/" + fname)
	if img == null:
		push_error("grid proof: could not reload " + fname)
		return
	# The player's feet are their origin; the body is up and to the left of it.
	# Convert through the stage, which is the only thing that knows the framing.
	var at: Vector2 = stage.call("world_to_stage", (player as Node2D).global_position + Vector2(0, -20))
	var px := Vector2i(rect.position + at * float(k))
	px.x = clampi(px.x, 0, img.get_width() - 1)
	px.y = clampi(px.y, 0, img.get_height() - 1)
	print("GRID PROOF  K=%d  world_rect=%s  window=%dx%d  sample=%s"
		% [k, str(rect), img.get_width(), img.get_height(), str(px)])
	# THE ASSERTION runs over the sprite and the ground it stands on: SPRITE_SPAN
	# each way is 220 screen pixels, comfortably more than a 32px character drawn
	# at scale 2 through a K=2 stage (128px) plus its shadow and floor.
	#
	# It is deliberately NOT the whole letterbox. The HUD is a screen-space layer
	# fitted onto the world rect (pixel_stage.fit_layer) — aliased text at a
	# fractional layer scale, which is what UI has always been in this project and
	# is not what LAW 1 is about. Scanning the full width would measure hud.gd's
	# glyph edges and call the renderer broken. The full-rect histogram is printed
	# underneath as information, with the same caveat.
	const SPRITE_SPAN := 220
	_report_runs("row  y=%d  (sprite)" % px.y,
		_runs(img, px.y, true, px.x - SPRITE_SPAN, px.x + SPRITE_SPAN), k, true)
	_report_runs("col  x=%d  (sprite)" % px.x,
		_runs(img, px.x, false, px.y - SPRITE_SPAN, px.y + SPRITE_SPAN), k, true)
	_report_runs("row  y=%d  (full letterbox, incl. HUD)" % px.y,
		_runs(img, px.y, true, int(rect.position.x), int(rect.end.x)), k, false)
	_report_runs("col  x=%d  (full letterbox, incl. HUD)" % px.x,
		_runs(img, px.x, false, int(rect.position.y), int(rect.end.y)), k, false)

## Run lengths of identical colours along one scanline, clipped to the world's
## letterbox rect (the bars either side of it are one enormous run of clear
## colour and say nothing about the grid).
func _runs(img: Image, line: int, horizontal: bool, from: int, to: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var lo := maxi(from, 0)
	var hi := mini(to, (img.get_width() if horizontal else img.get_height()))
	if hi - lo < 2:
		return out
	var prev := img.get_pixel(lo, line) if horizontal else img.get_pixel(line, lo)
	var run := 1
	for i in range(lo + 1, hi):
		var c := img.get_pixel(i, line) if horizontal else img.get_pixel(line, i)
		if c.is_equal_approx(prev):
			run += 1
		else:
			out.append(run)
			run = 1
			prev = c
	out.append(run)
	return out

func _report_runs(label: String, runs: PackedInt32Array, k: int, assertive: bool) -> void:
	if runs.is_empty():
		print("GRID PROOF  %s  (no samples)" % label)
		return
	var hist := {}
	var bad := 0
	# The first and last runs start/end at the clip, not at an art edge.
	for i in runs.size():
		var r := runs[i]
		hist[r] = int(hist.get(r, 0)) + 1
		if i == 0 or i == runs.size() - 1:
			continue
		if r % k != 0:
			bad += 1
	var keys := hist.keys()
	keys.sort()
	var parts := PackedStringArray()
	for key in keys:
		parts.append("%d:%d" % [key, hist[key]])
	print("GRID PROOF  %s  runs=%d  histogram(len:count) %s" % [label, runs.size(), " ".join(parts)])
	if not assertive:
		print("GRID PROOF  %s  %d interior runs off the grid (HUD glyphs live here)" % [label, bad])
		return
	if bad == 0:
		print("GRID PROOF  %s  PASS — every interior run is a multiple of %d" % [label, k])
	else:
		push_error("GRID PROOF %s FAIL — %d interior runs are not multiples of %d" % [label, bad, k])
		print("GRID PROOF  %s  FAIL — %d interior runs are not multiples of %d" % [label, bad, k])

## THE ULTRAWIDE PASS, on this machine's own screen shape.
##
## The world is letterboxed into the middle of a 3840-wide window and the UI is
## re-anchored onto it (pixel_stage.gd), so the two things worth photographing
## here are the HUD — which must be laid out identically to the 1920 frame, at
## full size, not at the half size the old layer-scale fit produced — and a
## modal, which must still be centred on the world and not on the desktop. The
## grid proof runs at this size too: K is the same 2, and if the blit ever went
## fractional on a window this shape the runs would say so.
##
## The size is restored afterwards so every later shot matches the rest of the set.
func _wide_shot(world: Node, player: Node) -> void:
	var was := DisplayServer.window_get_size()
	DisplayServer.window_set_size(Vector2i(3840, 1040))
	await _settle(0.8)
	await _shot("region_localhost_wide.png")
	_prove_grid(world, player, "region_localhost_wide.png")
	var stage: Node = world.get_node_or_null("PixelStage")
	if stage:
		print("WIDE  K=%d  world_rect=%s  window=%s"
			% [int(stage.get("stage_k")), str(stage.get("world_rect")), str(DisplayServer.window_get_size())])
	if world.has_method("_open_pause"):
		world.call("_open_pause")
		await _settle(0.6)
		await _shot("ui_pause_wide.png")
		_report_modal(world, "PauseMenu", stage)
		var pause: Node = world.get("hud").get_node_or_null("PauseMenu")
		if pause:
			pause.queue_free()
		get_tree().paused = false
		GameManager.state = GameManager.GameState.PLAYING
		await _settle(0.4)
	DisplayServer.window_set_size(was)
	await _settle(0.8)

## Where a modal actually landed, against where the world actually is. Two rects
## printed side by side is the whole evidence that "centred in the world rect"
## is true rather than believed.
func _report_modal(world: Node, panel_name: String, stage: Node) -> void:
	var hud: Node = world.get("hud")
	if hud == null or stage == null:
		return
	var panel := hud.get_node_or_null(panel_name) as Control
	if panel == null:
		return
	var wr: Rect2 = stage.get("world_rect")
	print("MODAL %s  root=%s  world_rect=%s  window=%s"
		% [panel_name, str(panel.get_global_rect()), str(wr), str(DisplayServer.window_get_size())])
	# The root is the full-rect host; the BOX the player sees is the panel inside
	# it, and "centred" is a claim about that box.
	var body := panel.get_node_or_null("Panel") as Control
	if body == null:
		return
	var b: Rect2 = body.get_global_rect()
	print("MODAL %s  box=%s  left/right gap=%d/%d  top/bottom gap=%d/%d"
		% [panel_name, str(b),
			int(b.position.x - wr.position.x), int(wr.end.x - b.end.x),
			int(b.position.y - wr.position.y), int(wr.end.y - b.end.y)])

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

## THE LAST _quiet() USED TO LAND ON THE SAME FRAME AS THE SHOT.
##
## `_quiet()` clears EventManager's active event and unpauses. Other nodes read
## that state in THEIR `_process`, one frame later: objective_waypoint.gd hides
## itself while an event is up (`_should_hide`) and only un-hides on its next
## tick. Clearing the event and shooting immediately therefore captured
## production and corporate_enterprise — the two regions that fire a scripted
## event on arrival — with no waypoint chevron and no readout at all, which
## reads in the frame as "the guidance system is missing in two rooms".
##
## So the quiet happens EARLY and the frame is taken LATE, with a beat in
## between for everything that was hiding behind the popup to come back.
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

## THE SINGLE MOST IMPORTANT LINE IN THIS FILE.
##
## project.godot runs `rendering/viewport/hdr_2d=true`, so the 2D framebuffer is
## LINEAR. The compositor applies the linear->sRGB encode on its way to the
## monitor, but `Viewport.get_texture().get_image()` hands back the raw buffer,
## BEFORE that encode. Saving it straight to PNG bakes a ~2.2 gamma crush into
## every QA frame: TEXT #D8DEEA (216) lands at 175, and a floor tile authored at
## 80 lands at 30. Every visual-QA round so far has been reviewing frames roughly
## two stops darker than what a player actually sees, and has then "fixed" the
## art to compensate.
##
## Godot's Image.linear_to_srgb() wants an 8-bit RGB(A) image, which is what the
## capture is, but guard the format anyway: a viewport in a half-float format
## would otherwise silently skip the encode.
func _encode(img: Image) -> void:
	if not get_viewport().use_hdr_2d:
		return
	if img.get_format() != Image.FORMAT_RGBA8 and img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGBA8)
	img.linear_to_srgb()
