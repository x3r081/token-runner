extends PanelContainer

const _GameTheme = preload("res://scripts/ui/game_theme.gd")

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

func _ready() -> void:
	theme = _GameTheme.create()
	add_theme_stylebox_override("panel", _GameTheme.panel_box(_GameTheme.CYAN, 4.0))
	_GameTheme.style_heading($Margin/VBox/Title, _GameTheme.CYAN, 22)
	_GameTheme.style_button($Margin/VBox/CloseBtn, _GameTheme.CYAN, 15)
	_populate()
	_GameTheme.open_panel(self)
	$Margin/VBox/CloseBtn.pressed.connect(queue_free)

func _populate() -> void:
	var vbox: VBoxContainer = $Margin/VBox/RegionList
	for c in vbox.get_children():
		c.queue_free()
	for rid in GameManager.REGION_ORDER:
		var unlocked := GameManager.is_region_unlocked(rid)
		var current := GameManager.current_region == rid
		var display: String = REGION_NAMES.get(rid, rid)
		var accent: Color = REGION_ACCENTS.get(rid, _GameTheme.CYAN)
		if unlocked and not current:
			# Fast-travel to any unlocked region. Buttons stay direct children of
			# RegionList (the travel test counts them there).
			var btn := Button.new()
			btn.text = "▸ Travel to %s" % display
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			_GameTheme.style_button(btn, accent, 15)
			var r: String = rid
			btn.pressed.connect(func(): _travel(r))
			vbox.add_child(btn)
		else:
			var label := Label.new()
			var prefix := "📍 " if current else "🔒 "
			label.text = "%s%s%s" % [prefix, display, "  (you are here)" if current else "  (locked)"]
			if current:
				label.add_theme_color_override("font_color", _GameTheme.hot_of(accent))
				label.add_theme_stylebox_override("normal", _GameTheme.chip_box(accent))
				label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			else:
				label.add_theme_color_override("font_color", _GameTheme.with_alpha(_GameTheme.TEXT_DIM, 0.55))
			vbox.add_child(label)
			if current:
				# The "you are here" beacon breathes. (Tween AFTER add_child —
				# tweens refuse to exist outside the tree, like the rest of us.)
				var t := label.create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
				t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
				t.tween_property(label, "modulate:a", 0.65, 0.9)
				t.tween_property(label, "modulate:a", 1.0, 0.9)
	_GameTheme.stagger_rows(vbox, 0.04, 0.1)

func _travel(rid: String) -> void:
	if GameManager.is_region_unlocked(rid) and rid != GameManager.current_region:
		GameManager.change_region(rid)
	queue_free()
