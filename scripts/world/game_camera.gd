extends Camera2D
class_name GameCamera

var _shake_amount := 0.0
var _shake_decay := 5.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

func _process(delta: float) -> void:
	if _shake_amount > 0:
		offset = Vector2(
			_rng.randf_range(-_shake_amount, _shake_amount),
			_rng.randf_range(-_shake_amount, _shake_amount)
		)
		_shake_amount = move_toward(_shake_amount, 0.0, _shake_decay * delta)
	else:
		offset = Vector2.ZERO

func shake(duration: float = 0.3, intensity: float = 8.0) -> void:
	_shake_amount = intensity
