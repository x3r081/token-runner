extends Node
## Regression test: every region builds without error, returns a valid spawn/size,
## and produces the expected container nodes + themed set-dressing. Guards against
## the "flat noise field" regression and keeps all regions structurally valid.
##
## Run: godot --headless --path . --scene tests/region_test.tscn

const RegionBuilderClass = preload("res://scripts/world/region_builder.gd")

const REGIONS := [
	"localhost", "dependency_district", "stackoverflow_ruins", "api_bazaar",
	"cloud_district", "open_source_wildlands", "corporate_enterprise",
	"gpu_mines", "production", "token_vault",
]

var passed := 0
var failed := 0

func _ready() -> void:
	_run()
	print("REGION TESTS: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _run() -> void:
	for region in REGIONS:
		var root := Node2D.new()
		add_child(root)
		var data: Dictionary = RegionBuilderClass.build(root, region)
		_check("%s returns spawn+size" % region, data.has("spawn") and data.has("size"))
		_check("%s has floor" % region, root.get_node_or_null("Floor") != null)
		_check("%s has enemies container" % region, root.get_node_or_null("Enemies") != null)
		_check("%s has tokens container" % region, root.get_node_or_null("Tokens") != null)
		var floor := root.get_node_or_null("Floor")
		_check("%s floor is filled" % region, floor != null and floor.get_child_count() > 50)
		if region != "localhost":
			var structs := root.get_node_or_null("Structures")
			_check("%s has themed structures" % region, structs != null and structs.get_child_count() > 0)
		root.queue_free()

func _check(label: String, condition: bool) -> void:
	if condition:
		print("  PASS: %s" % label)
		passed += 1
	else:
		print("  FAIL: %s" % label)
		failed += 1
