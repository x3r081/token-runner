extends Node
## Tracks blocking UI so events/dialogue don't overlap modals.

var _modal_count: int = 0

func push_modal() -> void:
	_modal_count += 1

func pop_modal() -> void:
	_modal_count = maxi(0, _modal_count - 1)

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
