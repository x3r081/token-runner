extends Node
## Model selection: the player picks which AI model powers their Prompt Blast.
## Each model is a real strategic trade-off between token cost, damage, and
## reliability (a low-reliability model may "hallucinate" and misfire).

signal model_changed(id: String, display_name: String)

const MODELS := [
	{"id": "local", "name": "Local 7B", "cost": 0.6, "dmg": 0.7, "reliability": 0.75, "color": Color(0.55, 0.85, 0.6)},
	{"id": "fast", "name": "Fast", "cost": 1.0, "dmg": 1.0, "reliability": 0.95, "color": Color(0.4, 0.85, 0.95)},
	{"id": "frontier", "name": "Frontier", "cost": 2.2, "dmg": 1.8, "reliability": 0.99, "color": Color(0.85, 0.5, 1.0)},
	{"id": "experimental", "name": "Experimental", "cost": 1.2, "dmg": 1.6, "reliability": 0.6, "color": Color(1.0, 0.72, 0.2)},
]

var index: int = 1  # Fast by default

func reset() -> void:
	index = 1

func current() -> Dictionary:
	return MODELS[index]

func cycle() -> void:
	index = (index + 1) % MODELS.size()
	var m := current()
	model_changed.emit(m.id, m.name)
	AudioManager.play_sfx("ability")

func set_model(id: String) -> void:
	for i in MODELS.size():
		if MODELS[i].id == id:
			index = i
			model_changed.emit(MODELS[i].id, MODELS[i].name)
			return

func cost_mult() -> float:
	return float(current().cost)

func dmg_mult() -> float:
	return float(current().dmg)

func reliability() -> float:
	return float(current().reliability)

func color() -> Color:
	return current().color
