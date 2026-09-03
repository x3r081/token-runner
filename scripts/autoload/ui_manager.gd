extends Node
## Tracks blocking UI so events/dialogue don't overlap modals, and hosts the
## always-available guide overlay ([H] — "WHAT AM I DOING?") plus its idle nudge.
## The overlay lives here rather than in world.tscn so it survives region loads
## and exists the moment the world does, without touching the world scene.

## Loaded at runtime, not preloaded: guide_overlay.gd talks back to UIManager,
## and a preload here would make that a compile-time cycle.
const GUIDE_OVERLAY_PATH := "res://scripts/ui/guide_overlay.gd"

var _modal_count: int = 0
var _guide: CanvasLayer = null

func _ready() -> void:
	# The overlay must keep answering questions while the game is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Deferred: autoloads registered after this one (CycleManager, ModelManager,
	# ...) aren't in the tree during _ready, and the overlay reads them.
	call_deferred("_mount_guide")

func _mount_guide() -> void:
	if is_instance_valid(_guide):
		return
	if not ResourceLoader.exists(GUIDE_OVERLAY_PATH):
		return
	var script: GDScript = load(GUIDE_OVERLAY_PATH)
	if script == null:
		return
	var node = script.new()
	if node is CanvasLayer:
		_guide = node
		_guide.name = "GuideOverlay"
		add_child(_guide)
	elif node is Node:
		(node as Node).free()

## The [H] guide overlay. Null only before the deferred mount has run.
func guide() -> CanvasLayer:
	return _guide

## Convenience entry points for anything that wants to point the player at help.
func open_guide() -> void:
	if is_instance_valid(_guide) and _guide.has_method("open_guide"):
		_guide.call("open_guide")

func toggle_guide() -> void:
	if is_instance_valid(_guide) and _guide.has_method("toggle_guide"):
		_guide.call("toggle_guide")

func push_modal() -> void:
	_modal_count += 1

func pop_modal() -> void:
	_modal_count = maxi(0, _modal_count - 1)

## Drop every hold. The count is the twin of modal_panel.gd's `_dim_depth`, and
## it has the same failure mode with none of its safety net: this is an autoload,
## so the number outlives every scene, and a panel that never got to run its
## `tree_exiting` release leaves `has_blocking_ui()` permanently true — random
## events stop firing, the idle nudge goes quiet and the world reads as if a
## modal it cannot see is open, for the rest of the session. Called where the
## world dim is cleared (hud.gd, once per world) and on New Game, so a fresh room
## always opens with nothing held.
## The guide overlay is the ONE holder that can outlive a world — it is this
## autoload's own child — so it re-asserts its hold instead of losing it.
func clear_modals() -> void:
	_modal_count = 0
	if is_instance_valid(_guide) and _guide.get("_modal_pushed"):
		_modal_count = 1

func has_blocking_ui() -> bool:
	if _modal_count > 0:
		return true
	if DialogueManager.is_active:
		return true
	if GameManager.state == GameManager.GameState.PAUSED:
		return true
	if GameManager.state == GameManager.GameState.DIALOGUE:
		return true
	if GameManager.state == GameManager.GameState.LOADING:
		return true
	return false
