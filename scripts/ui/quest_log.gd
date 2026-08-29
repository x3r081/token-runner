extends PanelContainer

const _GameTheme = preload("res://scripts/ui/game_theme.gd")

func _ready() -> void:
	theme = _GameTheme.create()
	add_theme_stylebox_override("panel", _GameTheme.panel_box(_GameTheme.CYAN, 4.0))
	_GameTheme.style_heading($Margin/VBox/Title, _GameTheme.CYAN, 22)
	_GameTheme.style_button($Margin/VBox/CloseBtn, _GameTheme.CYAN, 15)
	_populate()
	_GameTheme.open_panel(self)
	$Margin/VBox/CloseBtn.pressed.connect(queue_free)

func _populate() -> void:
	var vbox: VBoxContainer = $Margin/VBox/Scroll/QuestList
	for c in vbox.get_children():
		c.queue_free()
	for info in QuestManager.get_all_quest_infos():
		if info.state != QuestManager.QuestState.ACTIVE and info.state != QuestManager.QuestState.COMPLETED:
			continue
		var done: bool = info.state == QuestManager.QuestState.COMPLETED
		var label := Label.new()
		var status := "✓" if done else "→"
		label.text = "%s %s\n   %s" % [status, info.get("name", ""), info.get("description", "")]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 16)
		# Done quests fade to dependency-green; live ones stay readable.
		label.add_theme_color_override("font_color",
			_GameTheme.with_alpha(_GameTheme.ACID, 0.6) if done else _GameTheme.TEXT)
		vbox.add_child(label)
	_GameTheme.stagger_rows(vbox, 0.04, 0.1)
