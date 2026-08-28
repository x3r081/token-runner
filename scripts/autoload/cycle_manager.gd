extends Node
## "Ship Before Reset" — the game's title mechanic. Development proceeds in
## cycles. At the end of each cycle the token/compute economy RESETS: volatile
## quotas refill, vendor prices shift, and accumulated technical debt triggers a
## reckoning. This creates strategic "finish it BEFORE RESET" pressure without a
## single stressful real-time timer for the whole game.

signal cycle_warning(seconds_left: int)
signal reset_triggered(cycle: int)
signal cycle_changed(cycle: int)

const CYCLE_LENGTH := 150.0
const WARN_AT := 20.0

var cycle: int = 1
var time_left: float = CYCLE_LENGTH
var price_index: float = 1.0
var _warned := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE

func reset() -> void:
	cycle = 1
	time_left = CYCLE_LENGTH
	price_index = 1.0
	_warned = false

func _process(delta: float) -> void:
	if GameManager.state != GameManager.GameState.PLAYING:
		return
	if get_tree().paused:
		return
	time_left -= delta
	if time_left <= WARN_AT and not _warned:
		_warned = true
		cycle_warning.emit(int(ceil(maxf(time_left, 0.0))))
	if time_left <= 0.0:
		end_cycle()

func end_cycle() -> void:
	# Volatile quotas refill — a fresh cycle, a fresh (over)confidence.
	_topup_to_default("compute")
	_topup_to_default("context")
	ResourceManager.modify("focus", 100.0)
	ResourceManager.modify("will_to_live", 4.0)
	# Debt reckoning: the bill for borrowing against the future comes due.
	var debt := ResourceManager.get_value("technical_debt")
	if debt > 0.0:
		ResourceManager.modify("stability", -clampf(debt * 0.1, 0.0, 20.0))
	# Vendors change prices ("successful adoption").
	price_index = clampf(price_index * randf_range(0.85, 1.3), 0.6, 3.0)
	cycle += 1
	time_left = CYCLE_LENGTH
	_warned = false
	reset_triggered.emit(cycle)
	cycle_changed.emit(cycle)

func seconds_left() -> int:
	return int(ceil(maxf(time_left, 0.0)))

func _topup_to_default(name: String) -> void:
	var def := float(ResourceManager.RESOURCE_DEFAULTS.get(name, 0))
	var cur := ResourceManager.get_value(name)
	if cur < def:
		ResourceManager.modify(name, def - cur)
