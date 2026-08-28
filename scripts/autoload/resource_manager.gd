extends Node
## Manages all player resources and economy.

signal resource_changed(name: String, old_value: float, new_value: float)
signal resource_depleted(name: String)
signal tokens_gained(amount: int, source: String)
signal funny_price_adjustment(lost: int)

const RESOURCE_DEFAULTS := {
	"tokens": 50,
	"compute": 20,
	"context": 30,
	"api_credits": 10,
	"reputation": 0,
	"coffee": 3,
	"focus": 100,
	"stability": 80,
	"technical_debt": 5,
	"will_to_live": 100,
}

const RESOURCE_CAPS := {
	"tokens": 99999,
	"compute": 500,
	"context": 200,
	"api_credits": 500,
	"reputation": 1000,
	"coffee": 10,
	"focus": 100,
	"stability": 100,
	"technical_debt": 999,
	"will_to_live": 100,
}

var resources: Dictionary = {}

func _ready() -> void:
	reset()

func reset() -> void:
	resources = RESOURCE_DEFAULTS.duplicate()

func get_value(name: String) -> float:
	return float(resources.get(name, 0))

func get_all() -> Dictionary:
	return resources.duplicate()

func modify(name: String, delta: float, source: String = "") -> bool:
	if not resources.has(name):
		return false
	var old := float(resources[name])
	var cap := float(RESOURCE_CAPS.get(name, 99999))
	var new_val := clampf(old + delta, 0.0, cap)
	resources[name] = new_val
	resource_changed.emit(name, old, new_val)
	if name == "tokens" and delta > 0:
		tokens_gained.emit(int(delta), source)
		GameManager.record_stat("tokens_collected", int(delta))
		_maybe_funny_price_hike()
	if new_val <= 0 and old > 0:
		resource_depleted.emit(name)
	return true

func can_afford(costs: Dictionary) -> bool:
	for key in costs:
		if get_value(key) < float(costs[key]):
			return false
	return true

func spend(costs: Dictionary) -> bool:
	if not can_afford(costs):
		return false
	for key in costs:
		modify(key, -float(costs[key]))
	return true

func add_tokens(amount: int, source: String = "pickup") -> void:
	modify("tokens", amount, source)
	AudioManager.play_sfx("token_collect")

func drink_coffee() -> bool:
	if get_value("coffee") < 1:
		return false
	modify("coffee", -1)
	modify("focus", 40)
	modify("will_to_live", 5)
	AudioManager.play_sfx("coffee")
	return true

func regenerate_focus(delta: float) -> void:
	if get_value("focus") < 100:
		modify("focus", delta * 2.0)

func accept_debt(amount: int) -> void:
	modify("technical_debt", amount)
	GameManager.record_stat("debt_accepted", amount)

func _maybe_funny_price_hike() -> void:
	if randf() < 0.03 and get_value("tokens") > 100:
		var lost := mini(int(get_value("tokens") * 0.15), 200)
		if lost > 10:
			modify("tokens", -lost)
			funny_price_adjustment.emit(lost)

func get_display_name(name: String) -> String:
	match name:
		"tokens": return "Tokens"
		"compute": return "Compute"
		"context": return "Context"
		"api_credits": return "API Credits"
		"reputation": return "Reputation"
		"coffee": return "Coffee"
		"focus": return "Focus"
		"stability": return "Stability"
		"technical_debt": return "Technical Debt"
		"will_to_live": return "Will To Live"
		_: return name.capitalize()

func get_tooltip(name: String) -> String:
	match name:
		"tokens": return "The fuel of modern development. Also the bill."
		"compute": return "GPUs go brr. Wallet goes cry."
		"context": return "How much of your mess the model can see."
		"api_credits": return "Definitely not expiring. Probably."
		"reputation": return "LinkedIn points, basically."
		"coffee": return "Liquid scope creep insurance."
		"focus": return "Depletes faster than your free tier."
		"stability": return "How likely production stays up."
		"technical_debt": return "Features you borrowed from the future."
		"will_to_live": return "Regenerates slower than npm audit fixes."
		_: return ""
