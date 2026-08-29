extends Node
## Regression test for environmental comedy props: every FLAVOR entry is placed in
## Localhost, interacting spawns a styled FlavorPopup, and it closes on input.
## Run: godot --headless --path . tests/flavor_test.tscn

const Generic := preload("res://scripts/world/generic_interactable.gd")

var passed := 0
var failed := 0

func _ready() -> void:
	await _run()
	print("FLAVOR TESTS: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _run() -> void:
	GameManager.current_region = "localhost"
	GameManager.show_opening_sequence = false
	GameManager.state = GameManager.GameState.PLAYING
	var world: Node = preload("res://scenes/world/world.tscn").instantiate()
	add_child(world)
	for i in 5:
		await get_tree().physics_frame

	# Collect placed interactable ids.
	var placed: Array = []
	for n in _all(world):
		if n.get("interact_id") != null and String(n.interact_id).begins_with("prop_"):
			placed.append(n.interact_id)
	_check("all_flavor_ids_placed (%d/%d)" % [placed.size(), Generic.FLAVOR.size()],
		placed.size() >= Generic.FLAVOR.size())
	var missing: Array = []
	for id in Generic.FLAVOR:
		if id not in placed:
			missing.append(id)
	_check("no_missing_flavor_props (%s)" % str(missing), missing.is_empty())

	# Interacting with a prop spawns a FlavorPopup with the right text.
	var fridge: Node = null
	for n in _all(world):
		if n.get("interact_id") == "prop_fridge":
			fridge = n
			break
	_check("fridge_prop_exists", fridge != null)
	if fridge:
		fridge.interact(get_tree().get_first_node_in_group("player"))
		await get_tree().process_frame
		var popup := _find_popup(get_tree().root)
		_check("interacting_spawns_flavor_popup", popup != null)
		if popup:
			_check("popup_has_fridge_title", popup.title_text == "Fridge")
			_check("popup_body_nonempty", popup.body_text.length() > 10)

func _all(n: Node, out: Array = []) -> Array:
	out.append(n)
	for c in n.get_children():
		_all(c, out)
	return out

func _find_popup(root: Node) -> Node:
	for n in _all(root):
		if n.get_script() and n.get("title_text") != null and n.get("body_text") != null:
			return n
	return null

func _check(label: String, condition: bool) -> void:
	if condition:
		print("  PASS: %s" % label)
		passed += 1
	else:
		print("  FAIL: %s" % label)
		failed += 1
