extends Control

@onready var token_label: Label = $Margin/VBox/Resources/TokenLabel
@onready var compute_label: Label = $Margin/VBox/Resources/ComputeLabel
@onready var focus_bar: ProgressBar = $Margin/VBox/FocusBar
@onready var hp_bar: ProgressBar = $Margin/VBox/HPBar
@onready var quest_tracker: Label = $Margin/VBox/QuestTracker
@onready var region_label: Label = $Margin/VBox/RegionLabel
@onready var notification: Label = $Notification

var _notif_tween: Tween

func _ready() -> void:
	ResourceManager.resource_changed.connect(_on_resource_changed)
	ResourceManager.tokens_gained.connect(_on_tokens_gained)
	ResourceManager.funny_price_adjustment.connect(_on_price_adjustment)
	QuestManager.quest_updated.connect(_update_quest_tracker)
	QuestManager.quest_completed.connect(_on_quest_completed)
	GameManager.region_changed.connect(_on_region_changed)
	AchievementManager.achievement_unlocked.connect(_on_achievement)
	var player := get_tree().get_first_node_in_group("player")
	if player:
		player.health_changed.connect(_on_health_changed)
	_update_all()
	_on_region_changed(GameManager.current_region)

func _process(_delta: float) -> void:
	_update_quest_tracker()

func _update_all() -> void:
	token_label.text = "⚡ %d Tokens" % int(ResourceManager.get_value("tokens"))
	compute_label.text = "🖥 %d Compute" % int(ResourceManager.get_value("compute"))
	focus_bar.value = ResourceManager.get_value("focus")
	_update_quest_tracker()

func _on_resource_changed(name: String, _o: float, new_val: float) -> void:
	if name in ["tokens", "compute", "focus"]:
		_update_all()

func _on_health_changed(current: int, max_hp: int) -> void:
	hp_bar.max_value = max_hp
	hp_bar.value = current

func _on_tokens_gained(amount: int, _source: String) -> void:
	_show_notification("+%d Tokens" % amount, Color(0.3, 0.95, 0.85))

func _on_price_adjustment(lost: int) -> void:
	_show_notification("Provider pricing updated.\n-%d Tokens" % lost, Color(1.0, 0.4, 0.4))

func _on_quest_completed(quest_id: String, _rewards: Dictionary) -> void:
	var info := QuestManager.get_quest_info(quest_id)
	_show_notification("Quest Complete: %s" % info.get("name", quest_id), Color(0.9, 0.85, 0.3))

func _on_achievement(_id: String, name: String, desc: String) -> void:
	_show_notification("🏆 %s\n%s" % [name, desc], Color(1.0, 0.8, 0.2))

func _on_region_changed(region_id: String) -> void:
	region_label.text = _format_region(region_id)

func _format_region(id: String) -> String:
	return id.replace("_", " ").capitalize()

func _update_quest_tracker(_qid: String = "") -> void:
	var active := QuestManager.get_active_quests()
	if active.is_empty():
		quest_tracker.text = "No active quests. Talk to NPCs."
		return
	var qid: String = active[0]
	var info := QuestManager.get_quest_info(qid)
	var text := "📋 %s\n%s" % [info.get("name", ""), info.get("description", "")]
	for obj in info.get("objectives", []):
		if obj is Dictionary and obj.has("id"):
			var prog: int = info.progress.get(obj.id, 0)
			var target: int = obj.get("count", 1)
			text += "\n  [%d/%d] %s" % [prog, target, obj.get("text", obj.id)]
	quest_tracker.text = text

func _show_notification(text: String, color: Color) -> void:
	notification.text = text
	notification.modulate = color
	notification.visible = true
	if _notif_tween:
		_notif_tween.kill()
	_notif_tween = create_tween()
	_notif_tween.tween_interval(2.5)
	_notif_tween.tween_property(notification, "modulate:a", 0.0, 0.5)
	_notif_tween.tween_callback(func(): notification.visible = false; notification.modulate.a = 1.0)
