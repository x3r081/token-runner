extends Node
## Dream App upgrade tree and ship readiness.

signal upgrade_purchased(branch: String, tier: int)
signal app_evolved(totals: Dictionary)

const BRANCHES := [
	"frontend", "backend", "database", "ai", "infrastructure",
	"security", "marketing", "observability", "architecture",
]

var upgrade_defs: Dictionary = {}
var purchased: Dictionary = {}  # branch -> tier (0 = none)

func _ready() -> void:
	_load_definitions()
	reset()

func reset() -> void:
	purchased.clear()
	for b in BRANCHES:
		purchased[b] = 0

func _load_definitions() -> void:
	var file := FileAccess.open("res://data/upgrades/dream_app.json", FileAccess.READ)
	if file:
		var data = JSON.parse_string(file.get_as_text())
		if data is Dictionary:
			upgrade_defs = data.get("branches", {})
		file.close()

func get_branch_tier(branch: String) -> int:
	return purchased.get(branch, 0)

func get_upgrade_name(branch: String, tier: int = -1) -> String:
	if tier < 0:
		tier = get_branch_tier(branch)
	var tiers: Array = upgrade_defs.get(branch, {}).get("tiers", [])
	if tier <= 0 or tier > tiers.size():
		return "Nothing"
	return tiers[tier - 1].get("name", "?")

func get_upgrade_desc(branch: String, tier: int) -> String:
	var tiers: Array = upgrade_defs.get(branch, {}).get("tiers", [])
	if tier <= 0 or tier > tiers.size():
		return ""
	return tiers[tier - 1].get("description", "")

func get_next_upgrade(branch: String) -> Dictionary:
	var current := get_branch_tier(branch)
	var tiers: Array = upgrade_defs.get(branch, {}).get("tiers", [])
	if current >= tiers.size():
		return {}
	return tiers[current]

## Technical debt makes everything cost more — borrowing against the future
## isn't free. +0.4% per debt point (e.g. 100 debt => +40% upgrade costs).
const DEBT_COST_PER_POINT := 0.004

func debt_cost_multiplier() -> float:
	return 1.0 + ResourceManager.get_value("technical_debt") * DEBT_COST_PER_POINT

func get_effective_cost(branch: String) -> Dictionary:
	var next := get_next_upgrade(branch)
	var base: Dictionary = next.get("cost", {})
	var mult := debt_cost_multiplier()
	var out := {}
	for k in base:
		out[k] = int(ceil(float(base[k]) * mult))
	return out

func can_purchase(branch: String) -> bool:
	var next := get_next_upgrade(branch)
	if next.is_empty():
		return false
	return ResourceManager.can_afford(get_effective_cost(branch))

func purchase(branch: String) -> bool:
	var next := get_next_upgrade(branch)
	if next.is_empty():
		return false
	if not ResourceManager.spend(get_effective_cost(branch)):
		return false
	purchased[branch] = get_branch_tier(branch) + 1
	if next.has("debt"):
		ResourceManager.accept_debt(int(next.debt))
	upgrade_purchased.emit(branch, purchased[branch])
	app_evolved.emit(get_totals())
	AudioManager.play_sfx("upgrade")
	return true

func get_totals() -> Dictionary:
	var features := 0
	var stability := 0
	var security := 0
	var ai_dep := 0
	var cost := 0
	for branch in BRANCHES:
		var tier := get_branch_tier(branch)
		var tiers: Array = upgrade_defs.get(branch, {}).get("tiers", [])
		for i in tier:
			var t: Dictionary = tiers[i]
			features += int(t.get("features", 0))
			stability += int(t.get("stability", 0))
			security += int(t.get("security", 0))
			ai_dep += int(t.get("ai_dependency", 0))
			cost += int(t.get("money_spent", 0))
	return {
		"features": features,
		"stability": stability,
		"security": security,
		"ai_dependency": ai_dep,
		"money_spent": cost,
		"total_tiers": _total_tiers(),
	}

func _total_tiers() -> int:
	var t := 0
	for b in BRANCHES:
		t += get_branch_tier(b)
	return t

func can_ship() -> bool:
	var totals := get_totals()
	return (
		totals.features >= 15
		and totals.stability >= 8
		and _total_tiers() >= 12
		and get_branch_tier("ai") >= 2
		and get_branch_tier("infrastructure") >= 2
	)

func get_ship_requirements() -> Dictionary:
	return {
		"features": {"current": get_totals().features, "required": 15},
		"stability": {"current": get_totals().stability, "required": 8},
		"total_upgrades": {"current": _total_tiers(), "required": 12},
		"ai_tier": {"current": get_branch_tier("ai"), "required": 2},
		"infra_tier": {"current": get_branch_tier("infrastructure"), "required": 2},
	}

func get_visual_stage() -> int:
	return clampi(_total_tiers() / 3, 0, 5)
