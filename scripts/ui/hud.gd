extends CanvasLayer

const _GameTheme = preload("res://scripts/ui/game_theme.gd")

@onready var token_label: Label = $TopBar/HBox/Resources/TokenBlock/TokenLabel
@onready var compute_label: Label = $TopBar/HBox/Resources/ComputeBlock/ComputeLabel
@onready var focus_bar: ProgressBar = $TopBar/HBox/Bars/FocusBlock/FocusBar
@onready var hp_bar: ProgressBar = $TopBar/HBox/Bars/HPBlock/HPBar
@onready var quest_tracker: Label = $QuestPanel/Margin/VBox/QuestTracker
@onready var region_label: Label = $TopBar/HBox/RegionBlock/RegionLabel
@onready var region_sub: Label = $TopBar/HBox/RegionBlock/RegionSub
@onready var notification: Label = $Notification

var _notif_tween: Tween
var _theme: Theme
var _cycle_label: Label

func _ready() -> void:
	_theme = _GameTheme.create()
	$TopBar.theme = _theme
	$QuestPanel.theme = _theme
	hp_bar.add_theme_stylebox_override("fill", _GameTheme.hp_bar_fill())
	focus_bar.add_theme_stylebox_override("fill", _GameTheme.focus_bar_fill())
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
	_setup_cycle_readout()
	_update_all()
	_on_region_changed(GameManager.current_region)

func _setup_cycle_readout() -> void:
	_cycle_label = Label.new()
	_cycle_label.anchor_left = 0.5
	_cycle_label.anchor_right = 0.5
	_cycle_label.position = Vector2(-120, 92)
	_cycle_label.custom_minimum_size = Vector2(240, 0)
	_cycle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cycle_label.add_theme_font_size_override("font_size", 15)
	_cycle_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_cycle_label.add_theme_constant_override("outline_size", 4)
	add_child(_cycle_label)
	CycleManager.cycle_warning.connect(_on_cycle_warning)
	CycleManager.reset_triggered.connect(_on_reset_triggered)

func _on_cycle_warning(seconds_left: int) -> void:
	_show_notification("\u26a0 TOKEN RESET IN %ds\nShip something before it's gone!" % seconds_left, Color(1.0, 0.55, 0.3))

func _on_reset_triggered(cycle: int) -> void:
	_show_notification("\u267b RESET \u2014 Cycle %d\nQuotas refilled. Prices shifted." % cycle, Color(0.5, 0.85, 1.0))

func _process(_delta: float) -> void:
	_update_quest_tracker()
	if _cycle_label:
		var secs := CycleManager.seconds_left()
		var warn := secs <= int(CycleManager.WARN_AT)
		_cycle_label.text = "\u25c9 Cycle %d   \u23f1 reset in %ds" % [CycleManager.cycle, secs]
		_cycle_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.3) if warn else Color(0.7, 0.78, 0.85))

func _update_all() -> void:
	token_label.text = "%d" % int(ResourceManager.get_value("tokens"))
	compute_label.text = "%d" % int(ResourceManager.get_value("compute"))
	focus_bar.value = ResourceManager.get_value("focus")
	_update_quest_tracker()

func _on_resource_changed(name: String, _o: float, _new_val: float) -> void:
	if name in ["tokens", "compute", "focus"]:
		_update_all()

func _on_health_changed(current: int, max_hp: int) -> void:
	hp_bar.max_value = max_hp
	hp_bar.value = current

func _on_tokens_gained(amount: int, _source: String) -> void:
	_show_notification("+%d Tokens" % amount, Color(0.35, 0.95, 0.85))

func _on_price_adjustment(lost: int) -> void:
	_show_notification("Provider pricing updated.\n−%d Tokens" % lost, Color(1.0, 0.45, 0.42))

func _on_quest_completed(quest_id: String, _rewards: Dictionary) -> void:
	var info := QuestManager.get_quest_info(quest_id)
	_show_notification("Quest Complete\n%s" % info.get("name", quest_id), Color(0.95, 0.88, 0.35))

func _on_achievement(_id: String, name: String, desc: String) -> void:
	_show_notification("🏆 %s\n%s" % [name, desc], Color(1.0, 0.82, 0.25))

func _on_region_changed(region_id: String) -> void:
	region_label.text = _format_region(region_id)
	match region_id:
		"localhost":
			region_sub.text = "3AM Coder Apartment"
		_:
			region_sub.text = "Region under construction"

func _format_region(id: String) -> String:
	return id.replace("_", " ").capitalize()

func _update_quest_tracker(_qid: String = "") -> void:
	var active := QuestManager.get_active_quests()
	if active.is_empty():
		quest_tracker.text = "No active quests.\nTalk to Claude at the desk."
		return
	var qid: String = active[0]
	var info := QuestManager.get_quest_info(qid)
	var text := "%s\n%s" % [info.get("name", ""), info.get("description", "")]
	for obj in info.get("objectives", []):
		if obj is Dictionary and obj.has("id"):
			var prog: int = info.progress.get(obj.id, 0)
			var target: int = obj.get("count", 1)
			text += "\n  • [%d/%d] %s" % [prog, target, obj.get("text", obj.id)]
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
