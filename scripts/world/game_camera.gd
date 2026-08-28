extends Camera2D
class_name GameCamera

var _shake_amount := 0.0
var _shake_decay := 12.0
var _shake_time := 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

func _process(delta: float) -> void:
	if _shake_amount > 0.01:
		_shake_time += delta * 24.0
		offset = Vector2(
			sin(_shake_time * 1.7) * _shake_amount,
			cos(_shake_time * 2.3) * _shake_amount
		)
		_shake_amount = move_toward(_shake_amount, 0.0, _shake_decay * delta)
	else:
		_shake_amount = 0.0
		_shake_time = 0.0
		offset = Vector2.ZERO

func shake(_duration: float = 0.3, intensity: float = 3.0) -> void:
	_shake_amount = maxf(_shake_amount, intensity)
