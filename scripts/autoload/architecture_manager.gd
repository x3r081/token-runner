extends Node
## Dream App architecture decisions. Each is a binary trade-off with an immediate
## effect AND a delayed consequence that emerges at later cycle RESETs (some bills
## come due hours later). Ridiculous choices raise the app's "ridiculousness",
## which colours the final ship results.

signal decision_made(decision_id: String, option_id: String)
signal delayed_consequence(text: String)

const DECISIONS := [
	{
		"id": "structure", "q": "Structure",
		"desc": "How should the Dream App be structured?",
		"a": {"id": "monolith", "label": "Monolith", "hint": "(boring, stable)", "eff": {"stability": 6}, "rid": 0},
		"b": {"id": "microservices", "label": "Microservices", "hint": "(47 of them)", "eff": {"technical_debt": 8, "reputation": 5}, "rid": 3},
	},
	{
		"id": "database", "q": "Database",
		"desc": "Pick a data store. This is permanent. (It never is.)",
		"a": {"id": "sql", "label": "SQL", "hint": "(it just works)", "eff": {"stability": 5}, "rid": 0},
		"b": {"id": "nosql", "label": "NoSQL", "hint": "(web scale)", "eff": {"reputation": 6}, "rid": 2},
	},
	{
		"id": "testing", "q": "Testing",
		"desc": "Write tests now, or... later?",
		"a": {"id": "tests", "label": "Write tests", "hint": "(slow, safe)", "eff": {"tokens": -20, "stability": 8}, "rid": 0},
		"b": {"id": "later", "label": "We'll add them later", "hint": "(narrator: they didn't)", "eff": {"tokens": 25, "technical_debt": 10, "stability": -4}, "rid": 3},
	},
	{
		"id": "security", "q": "Security",
		"desc": "The Security Engineer is watching.",
		"a": {"id": "secure", "label": "Do it right", "hint": "(slow)", "eff": {"stability": 6, "reputation": 4}, "rid": 0},
		"b": {"id": "velocity", "label": "Ship it, patch later", "hint": "(velocity!)", "eff": {"tokens": 20}, "rid": 3},
	},
	{
		"id": "hosting", "q": "Hosting",
		"desc": "Where does this thing live?",
		"a": {"id": "cloud", "label": "The Cloud", "hint": "(someone's invoice)", "eff": {"compute": 15}, "rid": 1},
		"b": {"id": "local", "label": "Self-host", "hint": "(a Raspberry Pi)", "eff": {"stability": 3}, "rid": 0},
	},
]

var flags: Dictionary = {}       # decision_id -> option_id
var ridiculousness: int = 0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	if CycleManager and CycleManager.has_signal("reset_triggered"):
		CycleManager.reset_triggered.connect(_on_cycle_reset)

func reset() -> void:
	flags.clear()
	ridiculousness = 0

func choose(decision_id: String, option_id: String) -> void:
	var d := _decision(decision_id)
	if d.is_empty():
		return
	var opt: Dictionary = d.a if d.a.id == option_id else d.b
	for res in opt.get("eff", {}):
		if res == "technical_debt":
			ResourceManager.accept_debt(int(opt.eff[res]))
		else:
			ResourceManager.modify(res, float(opt.eff[res]))
	flags[decision_id] = option_id
	ridiculousness += int(opt.get("rid", 0))
	decision_made.emit(decision_id, option_id)

## Delayed consequences fire each cycle reset based on prior choices.
func _on_cycle_reset(_cycle: int) -> void:
	apply_delayed()

func apply_delayed() -> void:
	if flags.get("structure") == "microservices":
		ResourceManager.modify("stability", -2.0)
		delayed_consequence.emit("A microservice you forgot about fell over.")
	if flags.get("hosting") == "cloud":
		ResourceManager.modify("tokens", -12.0)
		delayed_consequence.emit("Cloud invoice: 'successful adoption.' -12 tokens.")
	if flags.get("database") == "nosql" and _rng.randf() < 0.2:
		if GameManager.get_flag("backups"):
			ResourceManager.modify("stability", -2.0)
			AchievementManager.unlock("boring_responsible_adult")
			delayed_consequence.emit("NoSQL ate a document. You restored from backup. Nerd.")
		else:
			ResourceManager.modify("stability", -10.0)
			delayed_consequence.emit("NoSQL ate a document. It was load-bearing.")
	if flags.get("security") == "velocity" and _rng.randf() < 0.15:
		if GameManager.get_flag("backups"):
			ResourceManager.modify("stability", -3.0)
			AchievementManager.unlock("boring_responsible_adult")
			delayed_consequence.emit("Breach! But your backups saved you. The Security Engineer nodded. Once.")
		else:
			ResourceManager.modify("stability", -15.0)
			delayed_consequence.emit("Breach. The Security Engineer said nothing. Just stared.")

func menu_stages() -> Array:
	var pending: Array = []
	for d in DECISIONS:
		if not flags.has(d.id):
			pending.append(d)
	if pending.is_empty():
		return [{
			"title": "ARCHITECTURE",
			"description": "All decisions locked in. The diagram now requires two monitors and a lie.\n\nRidiculousness: %d" % ridiculousness,
			"choices": [{"text": "Admire the diagram", "next": -1}],
		}]
	var stages: Array = []
	for i in pending.size():
		var d: Dictionary = pending[i]
		var nxt: int = -1 if i == pending.size() - 1 else i + 1
		stages.append({
			"title": "ARCHITECTURE: %s" % d.q,
			"description": d.desc,
			"choices": [
				{"text": "%s %s" % [d.a.label, d.a.hint], "architecture": {"decision": d.id, "option": d.a.id}, "next": nxt},
				{"text": "%s %s" % [d.b.label, d.b.hint], "architecture": {"decision": d.id, "option": d.b.id}, "next": nxt},
			],
		})
	return stages

func _decision(id: String) -> Dictionary:
	for d in DECISIONS:
		if d.id == id:
			return d
	return {}
