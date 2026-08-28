extends Node
## Deployable autonomous coding agents. You delegate work; the agent goes off and
## does... something. Each has traits (reliability, initiative, token burn). At
## the end of a development cycle (RESET) every deployed agent resolves: it may
## gather tokens, overengineer (technical debt), hallucinate (waste), or even
## spawn ANOTHER agent. Cheap agents are a gamble; expensive ones are steadier.

signal agent_deployed(display_name: String)
signal agent_resolved(display_name: String, summary: String)

const ARCHETYPES := {
	"junior": {"name": "Junior Agent", "cost": 15, "power": 10, "reliability": 0.5, "initiative": 0.85},
	"senior": {"name": "Senior Agent", "cost": 40, "power": 26, "reliability": 0.85, "initiative": 0.35},
	"frontier": {"name": "Frontier Agent", "cost": 90, "power": 58, "reliability": 0.95, "initiative": 0.55},
}

var agents: Array = []
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	# Agents finish their "sprint" when the development cycle resets.
	if CycleManager and CycleManager.has_signal("reset_triggered"):
		CycleManager.reset_triggered.connect(_on_cycle_reset)

func reset() -> void:
	agents.clear()

func can_deploy(type: String) -> bool:
	if type not in ARCHETYPES:
		return false
	return ResourceManager.get_value("tokens") >= float(ARCHETYPES[type].cost)

## Deploy an agent, paying its cost up front. Returns false if unaffordable.
func deploy(type: String) -> bool:
	if type not in ARCHETYPES:
		return false
	var a: Dictionary = ARCHETYPES[type]
	if not ResourceManager.spend({"tokens": a.cost}):
		return false
	agents.append({
		"type": type,
		"name": a.name,
		"power": a.power,
		"reliability": a.reliability,
		"initiative": a.initiative,
	})
	GameManager.record_stat("api_calls")
	agent_deployed.emit(a.name)
	AudioManager.play_sfx("ability")
	return true

func active_count() -> int:
	return agents.size()

func _on_cycle_reset(_cycle: int) -> void:
	resolve_all()

## Resolve every deployed agent, applying outcomes. Returns the outcome list.
func resolve_all() -> Array:
	var outcomes: Array = []
	var snapshot := agents.duplicate()
	agents.clear()
	for a in snapshot:
		outcomes.append(_resolve(a))
	return outcomes

func _resolve(a: Dictionary) -> Dictionary:
	var gain := int(round(float(a.power) * _rng.randf_range(1.6, 3.0)))
	var debt := 0
	var hallucinated := false
	var overengineered := false
	var spawned := false
	var notes: Array = []

	# Reliability roll: a low-reliability agent hallucinates a "solution".
	if _rng.randf() > a.reliability:
		hallucinated = true
		gain = int(gain * 0.2)
		debt += 6
		notes.append("hallucinated a fix")

	# Initiative roll: high-initiative agents overengineer everything.
	if _rng.randf() < float(a.initiative) * 0.8:
		overengineered = true
		debt += int(6 + a.initiative * 10.0)
		notes.append("added 6 abstractions")

	# Frontier agents occasionally spawn ANOTHER agent (which also overreaches).
	if a.type == "frontier" and _rng.randf() < 0.35:
		spawned = true
		debt += 10
		notes.append("spawned another agent")

	if gain > 0:
		ResourceManager.modify("tokens", gain, "agent")
	if debt > 0:
		ResourceManager.accept_debt(debt)

	var summary := "+%d tokens" % gain
	if not notes.is_empty():
		summary += ", " + ", ".join(notes)
	if debt > 0:
		summary += " (+%d debt)" % debt
	agent_resolved.emit(a.name, summary)
	return {
		"name": a.name, "gain": gain, "debt": debt,
		"hallucinated": hallucinated, "overengineered": overengineered, "spawned": spawned,
	}
