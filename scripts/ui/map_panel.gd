extends PanelContainer

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

func _ready() -> void:
	_populate()
	$Margin/VBox/CloseBtn.pressed.connect(queue_free)

func _populate() -> void:
	var vbox: VBoxContainer = $Margin/VBox/RegionList
	for c in vbox.get_children():
		c.queue_free()
	for rid in GameManager.REGION_ORDER:
		var unlocked := GameManager.is_region_unlocked(rid)
		var current := GameManager.current_region == rid
		var display: String = REGION_NAMES.get(rid, rid)
		if unlocked and not current:
			# Fast-travel to any unlocked region.
			var btn := Button.new()
			btn.text = "Travel to %s" % display
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var r: String = rid
			btn.pressed.connect(func(): _travel(r))
			vbox.add_child(btn)
		else:
			var label := Label.new()
			var prefix := "\ud83d\udccd " if current else "\ud83d\udd12 "
			label.text = "%s%s%s" % [prefix, display, "  (here)" if current else "  (locked)"]
			label.modulate = Color(0.4, 0.95, 0.85) if current else Color(0.5, 0.5, 0.5)
			vbox.add_child(label)

func _travel(rid: String) -> void:
	if GameManager.is_region_unlocked(rid) and rid != GameManager.current_region:
		GameManager.change_region(rid)
	queue_free()
