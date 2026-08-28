extends "res://scripts/world/interactable.gd"
class_name NPC

@export var npc_id: String = ""
@export var quest_ids: Array[String] = []

@onready var label: Label = $Label
@onready var sprite: Sprite2D = $Sprite2D
@onready var indicator: Sprite2D = $QuestIndicator

const NPC_KIND := {
	"roommate_ai": "claude",
	"cloud_salesperson": "suit",
	"svp_ai": "suit",
	"api_reseller": "suit",
	"enterprise_architect": "suit",
	"gpu_foreman": "foreman",
}

func _ready() -> void:
	super._ready()
	interact_id = npc_id
	interact_text = "Talk to %s" % DialogueManager.get_npc_name(npc_id)
	label.text = DialogueManager.get_npc_name(npc_id)
	_setup_sprite()
	QuestManager.quest_started.connect(_on_quest_changed)
	QuestManager.quest_completed.connect(_on_quest_changed)
	_update_indicator()

func _setup_sprite() -> void:
	var kind: String = NPC_KIND.get(npc_id, "maintainer")
	var path := "res://assets/textures/generated/npc_%s.png" % kind
	if ResourceLoader.exists(path):
		sprite.texture = load(path)
		sprite.modulate = Color.WHITE
		sprite.scale = Vector2(2.2, 2.2)
		sprite.position = Vector2(0, -18)
	# A soft shadow so NPCs sit in the world like the player.
	var shadow_tex := "res://assets/textures/generated/player_shadow.png"
	if ResourceLoader.exists(shadow_tex):
		var sh := Sprite2D.new()
		sh.texture = load(shadow_tex)
		sh.position = Vector2(0, 8)
		sh.z_index = -1
		add_child(sh)

func _on_interact(_player: Node) -> void:
	DialogueManager.start_dialogue(npc_id)

func _on_quest_changed(_qid: String = "") -> void:
	_update_indicator()

func _update_indicator() -> void:
	if indicator:
		indicator.visible = _has_available_quest()

func _has_available_quest() -> bool:
	for qid in quest_ids:
		var info := QuestManager.get_quest_info(qid)
		if info.is_empty():
			continue
		if info.state == QuestManager.QuestState.INACTIVE:
			var prereqs: Array = QuestManager.quest_defs.get(qid, {}).get("prerequisites", [])
			var met := true
			for p in prereqs:
				if p not in QuestManager.completed_quests:
					met = false
			if met:
				return true
	return false
