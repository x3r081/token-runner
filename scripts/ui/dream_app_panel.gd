extends PanelContainer

func _ready() -> void:
	_populate()
	$Margin/VBox/CloseBtn.pressed.connect(queue_free)
	$Margin/VBox/ShipBtn.pressed.connect(_on_ship)
	_update_ship_status()

func _populate() -> void:
	var vbox: VBoxContainer = $Margin/VBox/Scroll/BranchList
	for c in vbox.get_children():
		c.queue_free()
	for branch in DreamAppManager.BRANCHES:
		var tier := DreamAppManager.get_branch_tier(branch)
		var next := DreamAppManager.get_next_upgrade(branch)
		var h := HBoxContainer.new()
		var info := Label.new()
		var branch_name: String = DreamAppManager.upgrade_defs.get(branch, {}).get("display", branch)
		if next.is_empty():
			info.text = "%s: MAX — %s" % [branch_name, DreamAppManager.get_upgrade_name(branch)]
		else:
			info.text = "%s [%d]: %s → %s" % [branch_name, tier, DreamAppManager.get_upgrade_name(branch), next.get("name", "?")]
			info.tooltip_text = next.get("description", "")
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		h.add_child(info)
		if not next.is_empty():
			var btn := Button.new()
			var cost: Dictionary = next.get("cost", {})
			var cost_str := ""
			for k in cost:
				cost_str += "%s:%d " % [k, cost[k]]
			btn.text = "Buy (%s)" % cost_str.strip_edges()
			btn.disabled = not DreamAppManager.can_purchase(branch)
			var b: String = branch
			btn.pressed.connect(func(): _purchase(b))
			h.add_child(btn)
		vbox.add_child(h)
	var totals := DreamAppManager.get_totals()
	$Margin/VBox/Totals.text = "Features: %d | Stability: %d | Security: %d | Debt incoming: check HUD" % [totals.features, totals.stability, totals.security]

func _purchase(branch: String) -> void:
	if DreamAppManager.purchase(branch):
		AudioManager.play_sfx("upgrade")
		_populate()
		_update_ship_status()

func _update_ship_status() -> void:
	var req := DreamAppManager.get_ship_requirements()
	var ready := GameManager.can_ship()
	$Margin/VBox/ShipStatus.text = "Ship Ready: %s\nFeatures %d/%d | Stability %d/%d | Upgrades %d/%d" % [
		"YES — hit Deploy in Localhost!" if ready else "Not yet",
		req.features.current, req.features.required,
		req.stability.current, req.stability.required,
		req.total_upgrades.current, req.total_upgrades.required,
	]

func _on_ship() -> void:
	if GameManager.can_ship():
		GameManager.trigger_victory()
		var v := preload("res://scenes/ui/victory_screen.tscn").instantiate()
		get_tree().current_scene.add_child(v)
		queue_free()
