extends PanelContainer

func _ready() -> void:
	_populate()
	$Margin/VBox/CloseBtn.pressed.connect(queue_free)

func _populate() -> void:
	var vbox: VBoxContainer = $Margin/VBox/Scroll/QuestList
	for c in vbox.get_children():
		c.queue_free()
	for info in QuestManager.get_all_quest_infos():
		if info.state != QuestManager.QuestState.ACTIVE and info.state != QuestManager.QuestState.COMPLETED:
			continue
		var label := Label.new()
		var status := "✓" if info.state == QuestManager.QuestState.COMPLETED else "→"
		label.text = "%s %s\n   %s" % [status, info.get("name", ""), info.get("description", "")]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 16)
		vbox.add_child(label)
