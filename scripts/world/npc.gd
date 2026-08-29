extends "res://scripts/world/interactable.gd"
class_name NPC

@export var npc_id: String = ""
@export var quest_ids: Array[String] = []

@onready var label: Label = $Label
@onready var sprite: Sprite2D = $Sprite2D
@onready var indicator: Sprite2D = $QuestIndicator

var _anim_t := 0.0
var _spr_base_y := 0.0
var _ind_base_y := 0.0
var _hl_gate := 0.0
var _ind_base_scale := Vector2.ONE

const HIGHLIGHT_RADIUS := 100.0

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
	_spr_base_y = sprite.position.y
	_ind_base_y = indicator.position.y if indicator else 0.0
	_anim_t = randf() * TAU
	QuestManager.quest_started.connect(_on_quest_changed)
	QuestManager.quest_completed.connect(_on_quest_changed)
	_build_indicator_glow()
	_update_indicator()

## The quest indicator used to be a textureless (invisible) sprite. Give it an
## actual "!" over an overbright gold halo, so open quests advertise themselves.
func _build_indicator_glow() -> void:
	if not is_instance_valid(indicator):
		return
	var dot := FxLib.glow_dot()
	if dot and indicator.texture == null:
		indicator.texture = dot
		indicator.material = FxLib.additive_material()
		indicator.modulate = Color(2.4, 2.0, 0.5, 0.9)  # overbright GOLD halo
		indicator.scale = Vector2(1.6, 1.6)
	_ind_base_scale = indicator.scale
	var mark := Label.new()
	mark.name = "Mark"
	mark.text = "!"
	mark.add_theme_font_size_override("font_size", 18)
	mark.add_theme_color_override("font_color", Color(1.0, 0.92, 0.4))
	mark.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.09, 0.95))
	mark.add_theme_constant_override("outline_size", 5)
	mark.position = Vector2(-5, -15)
	indicator.add_child(mark)

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

## Gentle breathing so NPCs feel alive rather than painted onto the floor. The
## quest indicator floats a little higher/faster to draw the eye.
func _process(delta: float) -> void:
	_anim_t += delta
	if is_instance_valid(sprite):
		var b := sin(_anim_t * 1.9)
		sprite.position.y = _spr_base_y + b * 2.6
		# Gentle breathing scale (baseline set in _setup_sprite is 2.2).
		sprite.scale = Vector2(2.2 * (1.0 - b * 0.02), 2.2 * (1.0 + b * 0.03))
		# Interaction highlight: a soft overbright rim pulse when the player is
		# close enough to talk — the world's way of saying "this one has lines".
		var near := false
		var player := get_tree().get_first_node_in_group("player")
		if player and global_position.distance_to(player.global_position) < HIGHLIGHT_RADIUS:
			near = true
		_hl_gate = move_toward(_hl_gate, 1.0 if near else 0.0, delta * 5.0)
		if _hl_gate > 0.001:
			var pulse := 0.55 + 0.45 * sin(_anim_t * 3.6)
			sprite.self_modulate = Color.WHITE.lerp(Color(1.4, 1.55, 1.65), _hl_gate * pulse * 0.8)
		elif sprite.self_modulate != Color.WHITE:
			sprite.self_modulate = Color.WHITE
	if is_instance_valid(indicator) and indicator.visible:
		# The "!" floats, sways, and pulses — impossible to miss, hard to hate.
		indicator.position.y = _ind_base_y - 2.0 + sin(_anim_t * 3.2) * 5.0
		indicator.rotation = sin(_anim_t * 2.1) * 0.12
		indicator.scale = _ind_base_scale * (1.0 + 0.1 * sin(_anim_t * 6.4))

func _on_interact(_player: Node) -> void:
	DialogueManager.start_dialogue(npc_id)

## Accepts both quest_started(quest_id) and quest_completed(quest_id, rewards).
## The old 1-arg handler failed arity on quest_completed and never fired, so
## indicators went stale after turn-ins.
func _on_quest_changed(_a = null, _b = null) -> void:
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
