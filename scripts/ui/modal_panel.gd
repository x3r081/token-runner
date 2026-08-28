extends Control
## Mixin-style helpers for modal panels that block random events.

func register_modal() -> void:
	UIManager.push_modal()
	tree_exiting.connect(_unregister_modal, CONNECT_ONE_SHOT)

func _unregister_modal() -> void:
	UIManager.pop_modal()
