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
		var label := Label.new()
		var unlocked := GameManager.is_region_unlocked(rid)
		var current := GameManager.current_region == rid
		var prefix := "📍 " if current else ("✓ " if unlocked else "🔒 ")
		label.text = "%s%s" % [prefix, REGION_NAMES.get(rid, rid)]
		label.modulate = Color.WHITE if unlocked else Color(0.5, 0.5, 0.5)
		vbox.add_child(label)
