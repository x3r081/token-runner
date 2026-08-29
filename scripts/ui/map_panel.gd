extends PanelContainer
## World map / fast travel. Every region gets a one-line description of what it
## actually is, every locked region says exactly which quest opens it (the taunt
## rides along, it does not replace the hint), and the region holding your
## current objective is called out.

const _GameTheme = preload("res://scripts/ui/game_theme.gd")
const _Comedy = preload("res://scripts/ui/comedy_lines.gd")

const REGION_NAMES := {
	"localhost": "Localhost",
	"dependency_district": "Dependency District",
	"stackoverflow_ruins": "Stack Overflow Ruins",
	"api_bazaar": "API Bazaar",
	"cloud_district": "Cloud District",
	"open_source_wildlands": "Open Source Wildlands",
	"corporate_enterprise": "Corporate Enterprise",
	"gpu_mines": "GPU Mines",
	"production": "Production",
	"token_vault": "Token Vault",
}

## Region accents from the bible, so each row glows like its destination.
const REGION_ACCENTS := {
	"localhost": Color("#FFB74A"),
	"dependency_district": Color("#A8FF3E"),
	"stackoverflow_ruins": Color("#E8C46B"),
	"api_bazaar": Color("#FF2D95"),
	"cloud_district": Color("#6BC7FF"),
	"open_source_wildlands": Color("#58E07C"),
	"corporate_enterprise": Color("#4D7CFF"),
	"gpu_mines": Color("#FF6B2D"),
	"production": Color("#FF4757"),
	"token_vault": Color("#FFD34D"),
}

## The literal unlock condition for every region. This is load-bearing guidance:
## the joke lives in the taunt next to it, never in here.
const UNLOCK_HINTS := {
	"localhost": "Where you live. It was never locked.",
	"dependency_district": "Open from the start — walk out of Localhost.",
	"stackoverflow_ruins": "Complete 'Install Node' in Dependency District.",
	"api_bazaar": "Complete 'Accepted Answer (2013)' in Stack Overflow Ruins.",
	"cloud_district": "Complete 'One More API Call' in API Bazaar.",
	"open_source_wildlands": "Complete 'We Should Move To The Cloud' in Cloud District.",
	"corporate_enterprise": "Complete 'The Dependency That Nobody Maintains' in Open Source Wildlands.",
	"gpu_mines": "Complete 'Just Add AI' in Corporate Enterprise.",
	"production": "Complete 'Mine Your Own Business' in GPU Mines.",
	"token_vault": "Complete 'Production Is Down' in Production.",
}

func _ready() -> void:
	theme = _GameTheme.create()
	add_theme_stylebox_override("panel", _GameTheme.panel_box(_GameTheme.CYAN, 4.0))
	# Two lines per region needs more room than the original 500x560 rect.
	offset_left = -320.0
	offset_right = 320.0
	offset_top = -320.0
	offset_bottom = 320.0
	_GameTheme.style_heading($Margin/VBox/Title, _GameTheme.CYAN, 22)
	$Margin/VBox/CloseBtn.text = "Close Map"
	$Margin/VBox/CloseBtn.tooltip_text = "Closes the map. [M] does it too."
	_GameTheme.style_button($Margin/VBox/CloseBtn, _GameTheme.CYAN, 15)
	_build_subtitle()
	_populate()
	_GameTheme.open_panel(self)
	$Margin/VBox/CloseBtn.pressed.connect(queue_free)

func _build_subtitle() -> void:
	var sub := Label.new()
	sub.name = "MapSubtitle"
	sub.text = "Fast travel is instant and free. Everything at the other end is neither."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	var vbox: VBoxContainer = $Margin/VBox
	vbox.add_child(sub)
	vbox.move_child(sub, 1)

func _populate() -> void:
	var vbox: VBoxContainer = $Margin/VBox/RegionList
	for c in vbox.get_children():
		c.queue_free()
	# Where the game currently wants you — surfaced right on the map.
	var objective: Dictionary = QuestManager.get_current_objective() if QuestManager else {}
	var target_region := String(objective.get("region", ""))
	for rid in GameManager.REGION_ORDER:
		var unlocked := GameManager.is_region_unlocked(rid)
		var current := GameManager.current_region == rid
		var display: String = REGION_NAMES.get(rid, rid)
		var accent: Color = REGION_ACCENTS.get(rid, _GameTheme.CYAN)
		var flag: String = ""
		if rid == target_region:
			flag = "   ◀ your objective is here"
		if unlocked and not current:
			# Fast-travel to any unlocked region. Buttons stay direct children of
			# RegionList (the travel test counts them there).
			var btn := Button.new()
			btn.text = "▸ Travel to %s%s" % [display, flag]
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.tooltip_text = _Comedy.region_subtitle(rid)
			_GameTheme.style_button(btn, accent, 15)
			var r: String = rid
			btn.pressed.connect(func(): _travel(r))
			vbox.add_child(btn)
			_add_note(vbox, _Comedy.region_subtitle(rid), _GameTheme.TEXT_DIM)
		else:
			var label := Label.new()
			var prefix := "📍 " if current else "🔒 "
			label.text = "%s%s%s%s" % [prefix, display, "  (you are here)" if current else "  (locked)", flag]
			if current:
				label.add_theme_color_override("font_color", _GameTheme.hot_of(accent))
				label.add_theme_stylebox_override("normal", _GameTheme.chip_box(accent))
				label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			else:
				label.add_theme_color_override("font_color", _GameTheme.with_alpha(_GameTheme.TEXT_DIM, 0.55))
			vbox.add_child(label)
			if current:
				_add_note(vbox, _Comedy.region_subtitle(rid), _GameTheme.TEXT_DIM)
				# The "you are here" beacon breathes. (Tween AFTER add_child —
				# tweens refuse to exist outside the tree, like the rest of us.)
				var t := label.create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
				t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
				t.tween_property(label, "modulate:a", 0.65, 0.9)
				t.tween_property(label, "modulate:a", 1.0, 0.9)
			else:
				# Taunt first (short), then the literal unlock condition.
				var taunt: String = _Comedy.pick("locked_taunt", _Comedy.LOCKED_TAUNTS)
				var how: String = UNLOCK_HINTS.get(rid, "Keep going; it opens eventually.")
				_add_note(vbox, "%s  %s" % [taunt, how], _GameTheme.with_alpha(_GameTheme.TEXT_DIM, 0.6))
	_GameTheme.stagger_rows(vbox, 0.04, 0.1)

## Small dim second line under a region row. Stays a direct child of RegionList
## so the travel-button count the map test asserts on is unaffected.
func _add_note(vbox: VBoxContainer, text: String, col: Color) -> void:
	var note := Label.new()
	note.text = "      %s" % text
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", col)
	vbox.add_child(note)

func _travel(rid: String) -> void:
	if GameManager.is_region_unlocked(rid) and rid != GameManager.current_region:
		GameManager.change_region(rid)
	queue_free()
