extends CanvasLayer

const _GameTheme = preload("res://scripts/ui/game_theme.gd")

@onready var token_label: Label = $TopBar/HBox/ResourcesPanel/Resources/TokenBlock/TokenLabel
@onready var compute_label: Label = $TopBar/HBox/ResourcesPanel/Resources/ComputeBlock/ComputeLabel
@onready var focus_bar: ProgressBar = $TopBar/HBox/BarsPanel/Bars/FocusBlock/FocusBar
@onready var hp_bar: ProgressBar = $TopBar/HBox/BarsPanel/Bars/HPBlock/HPBar
@onready var quest_tracker: Label = $QuestPanel/Margin/VBox/QuestTracker
@onready var region_label: Label = $TopBar/HBox/RegionPanel/RegionBlock/RegionLabel
@onready var region_sub: Label = $TopBar/HBox/RegionPanel/RegionBlock/RegionSub
@onready var notification: Label = $Notification

var _notif_tween: Tween
var _theme: Theme
var _cycle_label: Label
var _model_label: Label
var _player: Node
var _ability_slots: Array = []
var _ability_overlays: Array = []
var _ability_cost_labels: Array = []
var _hp_ghost: ColorRect
var _hp_tween: Tween
var _hp_ghost_tween: Tween
var _hp_prev := -1.0
var _focus_tween: Tween
var _pop_tween: Tween

## key, display name, resource cost label, cost resource + amount for affordability.
const ABILITY_DEFS := [
	{"key": "1", "name": "Prompt Blast", "cost": "5 tk", "res": "tokens", "amt": 5, "id": "prompt_blast"},
	{"key": "2", "name": "Cache", "cost": "3 cp", "res": "compute", "amt": 3, "id": "cache"},
	{"key": "3", "name": "Rubber Duck", "cost": "5 ctx", "res": "context", "amt": 5, "id": "rubber_duck"},
	{"key": "4", "name": "Stack Trace", "cost": "10 tk", "res": "tokens", "amt": 10, "id": "stack_trace"},
	{"key": "5", "name": "Ctrl+Z", "cost": "4 ctx", "res": "context", "amt": 4, "id": "ctrl_z"},
	{"key": "Q", "name": "Dash / Push", "cost": "free", "res": "", "amt": 0, "id": "dash"},
]

## Per-ability accent colors (bible palette) for the slot borders/keys.
const ABILITY_ACCENTS := {
	"prompt_blast": _GameTheme.CYAN,
	"cache": _GameTheme.BLUE,
	"rubber_duck": _GameTheme.AMBER,
	"stack_trace": _GameTheme.VIOLET,
	"ctrl_z": _GameTheme.MAGENTA,
	"dash": _GameTheme.ACID,
}

## Cooldown ceilings for the sweep overlay (mirrors player.gd's timings; the
## duck knows it should be a shared constant and has chosen violence).
const COOLDOWN_MAX := {
	"rubber_duck": 4.5, "stack_trace": 1.6, "ctrl_z": 10.0, "dash": 1.1,
}

func _ready() -> void:
	_theme = _GameTheme.create()
	$TopBar.theme = _theme
	$QuestPanel.theme = _theme
	_dress_top_bar()
	_dress_quest_panel()
	ResourceManager.resource_changed.connect(_on_resource_changed)
	ResourceManager.tokens_gained.connect(_on_tokens_gained)
	ResourceManager.funny_price_adjustment.connect(_on_price_adjustment)
	QuestManager.quest_updated.connect(_update_quest_tracker)
	QuestManager.quest_completed.connect(_on_quest_completed)
	GameManager.region_changed.connect(_on_region_changed)
	AchievementManager.achievement_unlocked.connect(_on_achievement)
	_player = get_tree().get_first_node_in_group("player")
	if _player:
		_player.health_changed.connect(_on_health_changed)
	_setup_cycle_readout()
	_setup_ability_bar()
	_setup_pause_button()
	_update_all()

## Grouped glass panels: resources | region title | vitals.
func _dress_top_bar() -> void:
	$TopBar.add_theme_stylebox_override("panel", _GameTheme.empty_box())
	$TopBar/HBox/ResourcesPanel.add_theme_stylebox_override("panel", _GameTheme.glass_box(_GameTheme.GOLD))
	$TopBar/HBox/RegionPanel.add_theme_stylebox_override("panel", _GameTheme.glass_box(_GameTheme.CYAN))
	$TopBar/HBox/BarsPanel.add_theme_stylebox_override("panel", _GameTheme.glass_box(_GameTheme.RED))
	region_label.add_theme_font_override("font", _GameTheme.spaced_font(2))
	region_label.add_theme_color_override("font_color", _GameTheme.TEXT)
	# Vitals: gradient fills with a white-hot top edge (baked into the texture).
	_GameTheme.style_bar(hp_bar, _GameTheme.RED, Color("#FF9A7A"))
	_GameTheme.style_bar(focus_bar, _GameTheme.CYAN, _GameTheme.CYAN_HOT)
	# Red trailing ghost segment shown while recent damage "burns down".
	_hp_ghost = ColorRect.new()
	_hp_ghost.color = _GameTheme.with_alpha(_GameTheme.RED, 0.6)
	_hp_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_ghost.visible = false
	_hp_ghost.anchor_top = 0.12
	_hp_ghost.anchor_bottom = 0.88
	_hp_ghost.anchor_left = 1.0
	_hp_ghost.anchor_right = 1.0
	hp_bar.add_child(_hp_ghost)

func _dress_quest_panel() -> void:
	$QuestPanel.add_theme_stylebox_override("panel", _GameTheme.glass_box(_GameTheme.CYAN, 4.0))
	var header: Label = $QuestPanel/Margin/VBox/QuestHeader
	_GameTheme.style_heading(header, _GameTheme.CYAN, 13)
	quest_tracker.add_theme_color_override("font_color", _GameTheme.TEXT)

## One-time onboarding card: teaches controls AND states the goal/loop, because
## the boot sequence is comedy, not a tutorial. Shown when control is first given.
var _intro_shown := false
func show_intro_hint() -> void:
	if _intro_shown or get_node_or_null("IntroHint"):
		return
	_intro_shown = true
	var root := Control.new()
	root.name = "IntroHint"
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	root.add_child(_GameTheme.make_vignette(_GameTheme.with_alpha(_GameTheme.VOID, 0.7)))
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.add_theme_stylebox_override("panel", _GameTheme.panel_box(_GameTheme.CYAN, 22.0))
	root.add_child(panel)
	_GameTheme.add_sheen(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.custom_minimum_size = Vector2(560, 0)
	panel.add_child(vb)
	_hint_label(vb, "WELCOME TO THE HACKATHON", 24, _GameTheme.CYAN, true)
	_hint_label(vb, "GOAL: ship your Dream App before the RESET.\nCollect tokens -> upgrade the Dream App [B] -> meet its ship requirements -> Deploy.", 16, _GameTheme.TEXT)
	_hint_label(vb, "CONTROLS", 18, _GameTheme.AMBER, true)
	_hint_label(vb, "WASD / Arrows  —  Move\nE  —  Interact / Talk (walk up to props & Claude)\n1  —  Prompt Blast (attack)      Shift  —  Dash (escape)\n2-5  —  Abilities (Cache, Rubber Duck, Stack Trace, Ctrl+Z undo)\nB  —  Dream App      M  —  Map      J  —  Quests      Esc  —  Pause", 15, _GameTheme.TEXT)
	_hint_label(vb, "First up: talk to Claude at the desk, then grab some tokens.\n\n[E] / click to begin", 14, _GameTheme.TEXT_DIM)
	_GameTheme.open_panel(panel)
	_GameTheme.stagger_rows(vb)
	get_tree().create_timer(0.25).timeout.connect(func():
		if is_instance_valid(root):
			root.set_meta("armed", true))
	root.gui_input.connect(func(e): _intro_dismiss(root, e))
	set_process_input(true)
	_intro_root = root

var _intro_root: Control = null
func _intro_dismiss(root: Control, e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and root.get_meta("armed", false):
		root.queue_free()

func _input(event: InputEvent) -> void:
	if is_instance_valid(_intro_root) and _intro_root.get_meta("armed", false):
		if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept") \
				or event.is_action_pressed("ui_cancel"):
			_intro_root.queue_free()
			_intro_root = null
			get_viewport().set_input_as_handled()

func _hint_label(parent: Node, text: String, size: int, col: Color, heading := false) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if heading:
		l.add_theme_font_override("font", _GameTheme.spaced_font(3))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(560, 0)
	parent.add_child(l)

func _setup_pause_button() -> void:
	var b := Button.new()
	b.text = "‖"  # pause glyph
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.position = Vector2(-52, 46)
	b.custom_minimum_size = Vector2(40, 30)
	b.tooltip_text = "Pause (Esc)"
	b.focus_mode = Control.FOCUS_NONE
	_GameTheme.style_button(b, _GameTheme.CYAN, 14)
	b.pressed.connect(_on_pause_button)
	add_child(b)

func _on_pause_button() -> void:
	var w := get_parent()
	if w and w.has_method("_open_pause") and GameManager.state == GameManager.GameState.PLAYING:
		w._open_pause()
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
	# Active model readout (press [T] to cycle).
	_model_label = Label.new()
	_model_label.anchor_left = 0.5
	_model_label.anchor_right = 0.5
	_model_label.position = Vector2(-120, 110)
	_model_label.custom_minimum_size = Vector2(240, 0)
	_model_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_model_label.add_theme_font_size_override("font_size", 13)
	_model_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_model_label.add_theme_constant_override("outline_size", 4)
	add_child(_model_label)
	ModelManager.model_changed.connect(_on_model_changed)
	AgentManager.agent_deployed.connect(_on_agent_deployed)
	AgentManager.agent_resolved.connect(_on_agent_resolved)
	ArchitectureManager.delayed_consequence.connect(_on_arch_consequence)

func _on_cycle_warning(seconds_left: int) -> void:
	_show_notification("⚠ TOKEN RESET IN %ds\nShip something before it's gone!" % seconds_left, Color(1.0, 0.55, 0.3))

func _on_reset_triggered(cycle: int) -> void:
	_show_notification("♻ RESET — Cycle %d\nQuotas refilled. Prices shifted." % cycle, Color(0.5, 0.85, 1.0))

func _on_model_changed(_id: String, display_name: String) -> void:
	_show_notification("Model → %s" % display_name, ModelManager.color())

func _on_agent_deployed(display_name: String) -> void:
	_show_notification("🤖 %s deployed\nResolves at next RESET." % display_name, Color(0.6, 0.85, 1.0))

func _on_agent_resolved(display_name: String, summary: String) -> void:
	_show_notification("🤖 %s: %s" % [display_name, summary], Color(0.8, 0.9, 1.0))

func _on_arch_consequence(text: String) -> void:
	_show_notification("🏷 %s" % text, Color(1.0, 0.6, 0.5))

func _setup_ability_bar() -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = -360
	bar.offset_top = -74
	bar.offset_right = 360
	bar.offset_bottom = -8
	add_child(bar)
	for def in ABILITY_DEFS:
		var accent: Color = ABILITY_ACCENTS.get(def.id, _GameTheme.CYAN)
		# Plain Control slot so the cooldown overlay can use its own anchors
		# without a container fighting it every layout pass.
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(104, 58)
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var sb := StyleBoxFlat.new()
		sb.bg_color = _GameTheme.with_alpha(_GameTheme.BASE, 0.85)
		sb.set_border_width_all(1)
		sb.border_color = _GameTheme.with_alpha(accent, 0.55)
		sb.set_corner_radius_all(6)
		sb.set_content_margin_all(6)
		sb.shadow_color = _GameTheme.with_alpha(accent, 0.10)
		sb.shadow_size = 5
		panel.add_theme_stylebox_override("panel", sb)
		slot.add_child(panel)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		panel.add_child(v)
		var key := Label.new()
		key.text = "[%s]  %s" % [def.key, def.cost]
		key.add_theme_font_size_override("font_size", 12)
		key.add_theme_color_override("font_color", _GameTheme.hot_of(accent))
		v.add_child(key)
		var nm := Label.new()
		nm.text = def.name
		nm.add_theme_font_size_override("font_size", 14)
		nm.add_theme_color_override("font_color", _GameTheme.TEXT)
		v.add_child(nm)
		# Cooldown: dark vertical sweep that drains as the ability recharges.
		var ov := ColorRect.new()
		ov.color = Color(0.02, 0.024, 0.055, 0.62)
		ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ov.anchor_left = 0.0
		ov.anchor_right = 1.0
		ov.anchor_top = 1.0
		ov.anchor_bottom = 1.0
		ov.visible = false
		slot.add_child(ov)
		_GameTheme.attach_hover_motion(slot)
		bar.add_child(slot)
		_ability_slots.append(slot)
		_ability_overlays.append(ov)
		_ability_cost_labels.append(key)

func _update_ability_bar() -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if not is_instance_valid(_player):
			return
	for i in _ability_slots.size():
		var def: Dictionary = ABILITY_DEFS[i]
		var ready_now: bool = _player.ability_ready(def.id)
		var affordable: bool = def.res == "" or ResourceManager.get_value(def.res) >= float(def.amt)
		_ability_slots[i].modulate = Color(1, 1, 1, 1.0) if (ready_now and affordable) else Color(1, 1, 1, 0.38)
		# Unaffordable cost readout goes red — the universal "no" color.
		var accent: Color = ABILITY_ACCENTS.get(def.id, _GameTheme.CYAN)
		_ability_cost_labels[i].add_theme_color_override("font_color",
			_GameTheme.hot_of(accent) if affordable else _GameTheme.RED)
		var frac := _cooldown_frac(def.id)
		var ov: ColorRect = _ability_overlays[i]
		ov.anchor_top = 1.0 - frac
		ov.visible = frac > 0.003

## 1.0 = just used, 0.0 = ready. Reads the player's cooldown state directly.
func _cooldown_frac(id: String) -> float:
	var left := 0.0
	var ceil_v := 1.0
	match id:
		"prompt_blast", "cache":
			left = _player.ability_cooldown.time_left
			ceil_v = maxf(_player.ability_cooldown.wait_time, 0.01)
		"rubber_duck":
			left = _player._duck_cd
			ceil_v = COOLDOWN_MAX.rubber_duck
		"stack_trace":
			left = _player._trace_cd
			ceil_v = COOLDOWN_MAX.stack_trace
		"ctrl_z":
			left = _player._ctrlz_cd
			ceil_v = COOLDOWN_MAX.ctrl_z
		"dash":
			left = _player._dash_cd
			ceil_v = COOLDOWN_MAX.dash
	return clampf(left / ceil_v, 0.0, 1.0)

func _process(_delta: float) -> void:
	_update_quest_tracker()
	_update_ability_bar()
	if _cycle_label:
		var secs := CycleManager.seconds_left()
		var warn := secs <= int(CycleManager.WARN_AT)
		_cycle_label.text = "◉ Cycle %d   ⏱ reset in %ds" % [CycleManager.cycle, secs]
		if warn:
			# Amber panic pulse — the deadline is a physical presence now.
			var p := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
			_cycle_label.add_theme_color_override("font_color",
				_GameTheme.AMBER.lerp(_GameTheme.WHITE_HOT, p * 0.6))
		else:
			_cycle_label.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	if _model_label:
		var m := ModelManager.current()
		var pc: int = _player.prompt_cost() if is_instance_valid(_player) else int(m.cost * 5)
		_model_label.text = "⚙ Model: %s  ([T], %d tk/blast)" % [m.name, pc]
		_model_label.add_theme_color_override("font_color", ModelManager.color())

func _update_all() -> void:
	token_label.text = "%d" % int(ResourceManager.get_value("tokens"))
	compute_label.text = "%d" % int(ResourceManager.get_value("compute"))
	var target := ResourceManager.get_value("focus")
	if absf(focus_bar.value - target) > 0.5:
		if _focus_tween and _focus_tween.is_valid():
			_focus_tween.kill()
		_focus_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_focus_tween.tween_property(focus_bar, "value", target, _GameTheme.T_STD)
	else:
		focus_bar.value = target
	_update_quest_tracker()

func _on_resource_changed(name: String, _o: float, _new_val: float) -> void:
	if name in ["tokens", "compute", "focus"]:
		_update_all()

func _on_health_changed(current: int, max_hp: int) -> void:
	hp_bar.max_value = max_hp
	var target := float(current)
	var prev := _hp_prev if _hp_prev >= 0.0 else target
	_hp_prev = target
	if _hp_tween and _hp_tween.is_valid():
		_hp_tween.kill()
	_hp_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_hp_tween.tween_property(hp_bar, "value", target, _GameTheme.T_STD)
	if target < prev and is_instance_valid(_hp_ghost):
		# Trailing red segment marking what was just lost, then it burns away.
		var denom := maxf(1.0, float(max_hp))
		var lo := clampf(target / denom, 0.0, 1.0)
		var hi := clampf(prev / denom, 0.0, 1.0)
		if _hp_ghost_tween and _hp_ghost_tween.is_valid():
			_hp_ghost_tween.kill()
		_hp_ghost.visible = true
		_hp_ghost.anchor_left = lo
		_hp_ghost.anchor_right = hi
		_hp_ghost_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		_hp_ghost_tween.tween_interval(0.2)
		_hp_ghost_tween.tween_property(_hp_ghost, "anchor_right", lo, 0.3)
		_hp_ghost_tween.tween_callback(func(): _hp_ghost.visible = false)

func _on_tokens_gained(amount: int, _source: String) -> void:
	_show_notification("+%d Tokens" % amount, Color(0.35, 0.95, 0.85))
	# Scale-pop the counter so pickups register in the corner of your eye.
	if _pop_tween and _pop_tween.is_valid():
		_pop_tween.kill()
	token_label.pivot_offset = token_label.size * 0.5
	_pop_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_pop_tween.tween_property(token_label, "scale", Vector2(1.25, 1.25), 0.08)
	_pop_tween.tween_property(token_label, "scale", Vector2.ONE, 0.17)

func _on_price_adjustment(lost: int) -> void:
	_show_notification("Provider pricing updated.\n−%d Tokens" % lost, Color(1.0, 0.45, 0.42))

func _on_quest_completed(quest_id: String, _rewards: Dictionary) -> void:
	var info := QuestManager.get_quest_info(quest_id)
	_show_notification("Quest Complete\n%s" % info.get("name", quest_id), Color(0.95, 0.88, 0.35))

func _on_achievement(_id: String, name: String, desc: String) -> void:
	_show_notification("🏆 %s\n%s" % [name, desc], Color(1.0, 0.82, 0.25))

const REGION_SUBTITLES := {
	"localhost": "3AM Coder Apartment",
	"dependency_district": "node_modules event horizon",
	"stackoverflow_ruins": "Ancient wisdom, mostly deprecated",
	"api_bazaar": "Everything's for sale (per request)",
	"cloud_district": "Someone else's computer",
	"open_source_wildlands": "Maintained by one exhausted volunteer",
	"corporate_enterprise": "Please raise a ticket",
	"gpu_mines": "94°C and climbing",
	"production": "DO NOT TOUCH",
	"token_vault": "The reserves (do not spend all at once)",
}

func _on_region_changed(region_id: String) -> void:
	region_label.text = _format_region(region_id)
	region_sub.text = REGION_SUBTITLES.get(region_id, "Region under construction")
	# Brief cyan flash on arrival — new zone, new neon.
	var t := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(region_label, "modulate", Color(1.6, 1.9, 1.85, 1.0), 0.1)
	t.tween_property(region_label, "modulate", Color.WHITE, 0.5)

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
	notification.pivot_offset = notification.size * 0.5
	notification.scale = Vector2(0.92, 0.92)
	if _notif_tween:
		_notif_tween.kill()
	_notif_tween = create_tween()
	_notif_tween.tween_property(notification, "scale", Vector2.ONE, _GameTheme.T_MICRO) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_notif_tween.tween_interval(2.4)
	_notif_tween.tween_property(notification, "modulate:a", 0.0, 0.5)
	_notif_tween.tween_callback(func(): notification.visible = false; notification.modulate.a = 1.0)
