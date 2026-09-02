extends Control
## Death is the game's most-repeated screen, so it carries the densest comedy: a
## no-repeat cause-of-death line plus a roast assembled from THIS run. Underneath
## the jokes it still answers the only question that matters at 3AM: what happens
## if I press Respawn, and do I lose anything?
##
## Round 6: black background, one RED title, the roast, one button. Gone are the
## red vignette closing in, the title's duplicated glow layer and its pulse, the
## red-tinted panel with its red border and red glow, and the staggered rows.

const _GameTheme = preload("res://scripts/ui/game_theme.gd")
const _Comedy = preload("res://scripts/ui/comedy_lines.gd")
const _Modal = preload("res://scripts/ui/modal_panel.gd")

var _roast_label: Label
var _hint_label: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# A cause-of-death line, never repeated until the whole pool is spent.
	$Panel/VBox/Message.text = _Comedy.pick("death", _Comedy.DEATH)
	$Panel/VBox/Title.text = "You Died"
	$Panel/VBox/Respawn.text = "Respawn  [Ctrl+Z]"
	$Panel/VBox/Respawn.tooltip_text = "Undo, but for your entire body."
	$Panel/VBox/Menu.text = "Main Menu"
	$Panel/VBox/Menu.tooltip_text = "Sometimes called 'work-life balance'. Progress is saved."
	_build_extra_rows()
	GameManager.player_died.connect(_set_message)
	$Panel/VBox/Respawn.pressed.connect(_on_respawn)
	$Panel/VBox/Menu.pressed.connect(_on_menu)
	_dress()
	# Focus the button so Enter/Space works, and support the labelled Ctrl+Z key,
	# so respawn is never "click-only" (a lingering overlay could eat a click).
	$Panel/VBox/Respawn.grab_focus()

## Two runtime rows the scene doesn't own: the personalised roast, and the plain
## statement of what Respawn actually does (so nobody hesitates over the button).
func _build_extra_rows() -> void:
	var vbox: VBoxContainer = $Panel/VBox
	_roast_label = Label.new()
	_roast_label.name = "Roast"
	_roast_label.text = _build_roast()
	_roast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_roast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_roast_label.add_theme_font_size_override("font_size", _Modal.SMALL)
	vbox.add_child(_roast_label)
	vbox.move_child(_roast_label, 2)

	_hint_label = Label.new()
	_hint_label.name = "RespawnHint"
	_hint_label.text = _build_hint()
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", _Modal.SMALL)
	vbox.add_child(_hint_label)
	vbox.move_child(_hint_label, 3)

## The roast is built from the run's real numbers — the sting is the accuracy.
## Deaths always lead; then the single most damning fact currently true.
func _build_roast() -> String:
	var lines: Array[String] = [_Comedy.death_count_roast(GameManager.death_count)]
	var extras: Array[String] = []
	var totals: Dictionary = DreamAppManager.get_totals()
	var tiers := int(totals.get("total_tiers", 0))
	var debt := ResourceManager.get_value("technical_debt")
	var tokens := int(ResourceManager.get_value("tokens"))
	var will := int(ResourceManager.get_value("will_to_live"))
	var ridiculous: int = 0
	if ArchitectureManager:
		ridiculous = int(ArchitectureManager.ridiculousness)

	if tiers == 0:
		extras.append("Upgrades bought: zero. You died with the roadmap fully intact.")
	elif tiers >= 10:
		extras.append("%d upgrades deep and it still ended like this. Features are not armour." % tiers)
	if debt >= 40.0:
		extras.append(_Comedy.debt_roast(debt))
	if tokens >= 400:
		extras.append("Also hoarding %d tokens. They will look excellent in the postmortem." % tokens)
	elif tokens <= 25:
		extras.append("Token balance: %d. You died broke AND wrong." % tokens)
	if will <= 30:
		extras.append("Will to live: %d. Treat that as a production metric." % will)
	if ridiculous >= 6:
		extras.append("Architecture Ridiculousness %d. The diagram will outlive you." % ridiculous)
	extras.append(_Comedy.model_roast(String(ModelManager.current().get("id", "fast"))))

	# One extra, not two: the death screen is read at 3AM, mid-defeat, and it is
	# read every time. Two roasts and it stops being a punchline.
	if not extras.is_empty():
		lines.append(extras[0])
	return "\n".join(lines)

## Plain facts, no joke in the load-bearing half: respawning costs you nothing.
func _build_hint() -> String:
	var region: String = GameManager.current_region.replace("_", " ").capitalize()
	return "You respawn at the safe spawn in %s with 3 seconds of invincibility. Tokens, upgrades and quests are untouched." % region

## Black, one accent, no effects. A production incident is not a light show.
func _dress() -> void:
	var dim: ColorRect = $Dim
	dim.modulate.a = 1.0
	var panel: PanelContainer = $Panel
	# The scene's panel rect predates the roast/hint rows; widen it so nothing
	# has to fight the container for space.
	panel.offset_left = -340.0
	panel.offset_right = 340.0
	panel.offset_top = -200.0
	panel.offset_bottom = 200.0
	panel.theme = _GameTheme.create()
	panel.add_theme_stylebox_override("panel", _Modal.modal_box(_GameTheme.RED, 26.0))
	var title: Label = $Panel/VBox/Title
	title.add_theme_color_override("font_color", _GameTheme.RED)
	$Panel/VBox/Message.add_theme_color_override("font_color", _GameTheme.TEXT)
	if is_instance_valid(_roast_label):
		_roast_label.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	if is_instance_valid(_hint_label):
		_hint_label.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	# The one button that matters gets the accent; leaving is a quiet option.
	_GameTheme.style_button($Panel/VBox/Respawn, _GameTheme.RED, _Modal.BODY)
	_GameTheme.style_button($Panel/VBox/Menu, _GameTheme.TEXT_DIM, _Modal.SMALL)
	_GameTheme.open_panel(panel)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_on_respawn()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_Z and event.ctrl_pressed:
		get_viewport().set_input_as_handled()
		_on_respawn()

## Public: a cause-specific death (e.g. "the agent deleted the database") wins
## over the random pool line. Also refreshes the roast — the numbers moved.
func _set_message(msg: String) -> void:
	if msg.strip_edges().is_empty():
		return
	$Panel/VBox/Message.text = msg
	if is_instance_valid(_roast_label):
		_roast_label.text = _build_roast()

func _on_respawn() -> void:
	GameManager.respawn_player()
	var player := get_tree().get_first_node_in_group("player")
	if player:
		# Respawn at the region's safe spawn point (never back in the enemy pile
		# that killed us) with i-frames so the player can regroup.
		var safe: Vector2 = GameManager.region_spawn if GameManager.region_spawn != Vector2.ZERO else player.global_position
		player.respawn(safe)
		if player.has_method("grant_spawn_grace"):
			player.grant_spawn_grace(3.0)
	# Send any chasing enemies back to their posts so the respawn isn't a re-swarm.
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and e.has_method("reset_to_home"):
			e.reset_to_home()
	queue_free()

func _on_menu() -> void:
	GameManager.return_to_menu()
