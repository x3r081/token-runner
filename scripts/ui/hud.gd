extends CanvasLayer
## HUD — one quiet strip (VISUAL_BIBLE_V2 LAW 8).
##
## WHAT IS ON SCREEN, and nothing else:
##
##   top-left      `65 tk · 20 cp`            one aliased line, 1px shadow, no plate
##   top-centre    region name (HEADING)      with `Cycle 1 · 149s` (SMALL, TEXT_DIM)
##   top-right     HP and Focus               two 4px bars, no border, no captions
##   bottom-left   `→ Talk to Claude · 4m NE` one line, region ACCENT, no panel
##   bottom-centre six 28px ability slots     monochrome, key glyph only
##   bottom edge   `[E] interact · [T] model · [H] help`   one SMALL line
##   above the bar one toast at a time        one line, no box, slides up
##
## WHAT ROUND 6 DELETED, because the round-5 frames were nine plated boxes and a
## radar: the resource plate and its four titled columns, the vitals plate with
## its tube frames and quarter ticks, the cycle/model pill, the objective panel
## with its header, quest name and checklist, the 196px minimap, the toast card
## with its accent stripe and category glyph, both glass sheens, the loss ghosts,
## the delta chips, the counter overbright, the amber reset vignette and the
## per-ability rainbow.
##
## Nothing that was INFORMATION was deleted. The checklist lives in [J], the
## model price and the full key legend live in [H], the region flavour line lives
## in the props you can walk up to. The HUD keeps the six facts you play from.
##
## Node paths are unchanged from the old scene on purpose: `tests/ui_overlay_
## test.gd` and half a dozen scripts resolve them. Several of those nodes are now
## hidden rather than removed — they exist, they are empty, and that is fine.

const _GameTheme = preload("res://scripts/ui/game_theme.gd")
const _ObjectiveWaypoint = preload("res://scripts/ui/objective_waypoint.gd")

## Above the boss layer (3) and the death red-out (2); below guidance (8),
## dialogue (10), event popups (15) and the opening sequence (100).
const HUD_LAYER := 4

@onready var token_label: Label = $TopBar/HBox/ResourcesPanel/Resources/TokenBlock/TokenLabel
@onready var compute_label: Label = $TopBar/HBox/ResourcesPanel/Resources/ComputeBlock/ComputeLabel
@onready var context_label: Label = $TopBar/HBox/ResourcesPanel/Resources/ContextBlock/ContextLabel
@onready var debt_label: Label = $TopBar/HBox/ResourcesPanel/Resources/DebtBlock/DebtLabel
@onready var focus_bar: ProgressBar = $TopBar/HBox/BarsPanel/Bars/FocusBlock/FocusBar
@onready var hp_bar: ProgressBar = $TopBar/HBox/BarsPanel/Bars/HPBlock/HPBar
@onready var hp_value: Label = $TopBar/HBox/BarsPanel/Bars/HPBlock/HPValue
@onready var focus_value: Label = $TopBar/HBox/BarsPanel/Bars/FocusBlock/FocusValue
@onready var quest_tracker: Label = $QuestPanel/Margin/VBox/QuestTracker
@onready var next_action: Label = $QuestPanel/Margin/VBox/NextAction
@onready var quest_name_label: Label = $QuestPanel/Margin/VBox/QuestName
@onready var region_label: Label = $TopBar/HBox/RegionPanel/RegionBlock/RegionLabel
@onready var region_sub: Label = $TopBar/HBox/RegionPanel/RegionBlock/RegionSub
@onready var region_rule: ColorRect = $TopBar/HBox/RegionPanel/RegionBlock/RuleRow/RegionRule
## Kept at its scene path so nothing that looks it up breaks; at _ready it is
## reparented into the toast lane, where it IS the toast.
@onready var notification: Label = $Notification

## The on-screen chevron that points at whatever the objective line names.
var _waypoint: Control
## The radar is gone (LAW 8: "Minimap: removed. The waypoint chevron is the
## navigation."). The field stays so nothing that probes for it explodes.
var _minimap: Control = null
var _action_tween: Tween
var _last_action := ""
var _quest_ui_accum := 0.0
## Rebuilding the objective string four times a second is smooth to read and
## avoids allocating Strings every frame for a line nobody stares at that hard.
const QUEST_UI_INTERVAL := 0.22

var _theme: Theme
## The one colour the HUD is allowed to spend, and it belongs to the region you
## are standing in: the objective line, the ready ability slot, the waypoint.
## Everything else on this layer is TEXT or TEXT_DIM (LAW 2).
var _accent := _GameTheme.CYAN
var _cycle_shown := -1
var _cycle_num := -1
## Tri-state so the warning colour is written once on each transition rather
## than sixty times a second (a theme override re-dirties ancestor minimum
## sizes; it is not a cheap assignment).
var _cycle_warn := -1
var _player: Node
var _ability_bar: Control
var _ability_slots: Array = []
var _ability_panels: Array = []
var _ability_overlays: Array = []
var _ability_boxes: Array = []
var _ability_keys: Array = []
## Last discrete slot state: 0 ready / 1 recharging / 2 cannot afford.
var _ability_state: PackedInt32Array = PackedInt32Array()
var _hp_tween: Tween
var _focus_tween: Tween
var _hp_prev := -1.0
## Sustained "you are low" (driven every frame from _tick_status) and the event
## "you were just hit" (tween-driven). Two sentences, two nodes — sharing one
## would have the per-frame write stomp the tween.
var _danger_vig: TextureRect
var _hit_vig: TextureRect
var _hit_tween: Tween
var _hint_bar: Label

## Resource counters roll to their new value instead of snapping. Snapping reads
## as "the number was always that"; a short roll reads as "you just earned that".
## That roll is the whole of the resource feedback now — the floating delta chip
## and the overbright number went with the rest of the glow.
var _count_shown: Dictionary = {}
var _count_target: Dictionary = {}
const COUNT_KEYS := ["tokens", "compute", "context"]
## Low-HP threshold shared by the danger vignette and the value colour.
const LOW_HP_FRAC := 0.34
## Bars print no number until they are worth worrying about (LAW 8).
const VALUE_REVEAL_FRAC := 0.30
## Danger and hit vignettes occupy the first N child slots of this layer.
const VIGNETTE_COUNT := 2

## key, display name, cost resource + amount for affordability.
##
## The bar prints only the KEY now — names and prices are in [H] — but the price
## is still read here, because a slot you cannot afford has to look different
## from one you can. `amt` is the STATIC price; Prompt Blast's real price is
## model-dependent and `_ability_cost()` resolves it live.
const ABILITY_DEFS := [
	{"key": "1", "name": "Prompt Blast", "cost": "5 tk", "res": "tokens", "amt": 5, "id": "prompt_blast"},
	{"key": "2", "name": "Cache", "cost": "3 cp", "res": "compute", "amt": 3, "id": "cache"},
	{"key": "3", "name": "Rubber Duck", "cost": "5 ctx", "res": "context", "amt": 5, "id": "rubber_duck"},
	{"key": "4", "name": "Stack Trace", "cost": "10 tk", "res": "tokens", "amt": 10, "id": "stack_trace"},
	{"key": "5", "name": "Ctrl+Z", "cost": "4 ctx", "res": "context", "amt": 4, "id": "ctrl_z"},
	{"key": "Q", "name": "Dash / Push", "cost": "free", "res": "", "amt": 0, "id": "dash"},
]

## Cooldown ceilings for the sweep (mirrors player.gd's timings).
const COOLDOWN_MAX := {
	"rubber_duck": 4.5, "stack_trace": 1.6, "ctrl_z": 10.0, "dash": 1.1,
}

# ------------------------------------------------------------------- toasts --
## One line, bottom-centre, one at a time, no box. The card, the accent stripe,
## the category glyph and the body row are gone: a toast is a sentence, and a
## sentence does not need a rectangle to be read.
const TOAST_W := 720.0
const TOAST_H := 26.0
const TOAST_BOTTOM := -104.0
const TOAST_RISE := 14.0
const TOAST_IN := 0.18
const TOAST_HOLD := 2.00
const TOAST_OUT := 0.28
const TOAST_QUEUE_MAX := 5

var _toast_lane: Control
var _toast_card: Control
var _toast_queue: Array[Dictionary] = []
var _toast_phase := 0  # 0 idle, 1 rise-in, 2 hold, 3 fade-out
var _toast_t := 0.0
var _toast_key := ""
var _toast_amount := 0
var _toast_fmt := ""
var _toast_merges := 1

func _ready() -> void:
	# Layer 4 keeps the permanent readout above the boss layer (3) and the death
	# red-out (2) — a cinematic may not dim the thing you play from — while
	# staying below every modal that legitimately outranks it.
	layer = HUD_LAYER
	_theme = _GameTheme.create()
	_build_alert_vignettes()
	_mount_waypoint()
	_dress_top_bar()
	_dress_objective()
	_dress_hint_bar()
	_build_toast_lane()
	_build_minimap()
	ResourceManager.resource_changed.connect(_on_resource_changed)
	ResourceManager.tokens_gained.connect(_on_tokens_gained)
	ResourceManager.funny_price_adjustment.connect(_on_price_adjustment)
	QuestManager.quest_updated.connect(_update_quest_tracker)
	QuestManager.quest_completed.connect(_on_quest_completed)
	GameManager.region_changed.connect(_on_region_changed)
	AchievementManager.achievement_unlocked.connect(_on_achievement)
	DialogueManager.dialogue_started.connect(_on_dialogue_started)
	DialogueManager.dialogue_ended.connect(_on_dialogue_ended)
	_player = get_tree().get_first_node_in_group("player")
	if _player:
		_player.health_changed.connect(_on_health_changed)
		if "hp" in _player:
			_on_health_changed(int(_player.hp), int(hp_bar.max_value))
	_setup_cycle_signals()
	_setup_ability_bar()
	_setup_pause_button()
	_update_all()
	# Prime the accent so frame one already belongs to the room you are in.
	_on_region_changed(GameManager.current_region)

## Every Control this layer owns inherits the aliased font and the one panel
## style. CanvasLayer has no `theme`, so it is applied per root Control.
func _apply_theme(c: Control) -> void:
	if c != null:
		c.theme = _theme

## The strip: resources left, region centre, vitals right — all of it type and
## two hairline bars, laid straight on the world.
func _dress_top_bar() -> void:
	_apply_theme($TopBar)
	$TopBar.add_theme_stylebox_override("panel", _GameTheme.empty_box())
	$TopBar/HBox/ResourcesPanel.add_theme_stylebox_override("panel", _GameTheme.empty_box())
	$TopBar/HBox/RegionPanel.add_theme_stylebox_override("panel", _GameTheme.empty_box())
	$TopBar/HBox/BarsPanel.add_theme_stylebox_override("panel", _GameTheme.empty_box())

	# One line, one colour. The four titled columns (TOKENS / COMPUTE / CONTEXT /
	# DEBT TAX, each with a 22px number in its own hue) are hidden in the scene;
	# TokenLabel carries the whole strip.
	token_label.add_theme_font_size_override("font_size", _GameTheme.BODY)
	token_label.add_theme_color_override("font_color", _GameTheme.TEXT)
	_GameTheme.outline_text(token_label)

	region_label.add_theme_font_override("font", _GameTheme.spaced_font(2))
	region_label.add_theme_font_size_override("font_size", _GameTheme.HEADING)
	region_label.add_theme_color_override("font_color", _GameTheme.TEXT)
	_GameTheme.outline_text(region_label)
	# The cycle countdown moved in here, under the name, as small dim type. It
	# used to be a bordered pill at y 90..122 with a divider and a model readout.
	region_sub.add_theme_font_size_override("font_size", _GameTheme.SMALL)
	region_sub.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	_GameTheme.outline_text(region_sub)
	region_rule.visible = false

	# Two 4px bars. No frame, no ticks, no gradient, no ghost — a bar reports one
	# number, and at four pixels tall the only thing that reads is its length.
	hp_bar.custom_minimum_size = Vector2(168, 4)
	focus_bar.custom_minimum_size = Vector2(168, 4)
	_GameTheme.style_bar(hp_bar, _GameTheme.RED)
	_GameTheme.style_bar(focus_bar, _GameTheme.CYAN)
	for v: Label in [hp_value, focus_value]:
		v.add_theme_font_size_override("font_size", _GameTheme.SMALL)
		v.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
		_GameTheme.outline_text(v)
		# Present but invisible: the number only appears below 30%, and reserving
		# its column keeps both bars' right edges from jumping when it does.
		v.modulate.a = 0.0

## The objective. ONE line, bottom-left, in the region's accent — the sentence
## the whole guidance system exists to print. The panel it used to sit in (a
## bordered glass box with a header, the quest name and a three-line checklist)
## is gone; the checklist is in [J], where the player asks for it.
func _dress_objective() -> void:
	_apply_theme($QuestPanel)
	$QuestPanel.add_theme_stylebox_override("panel", _GameTheme.empty_box())
	var mg: MarginContainer = $QuestPanel/Margin
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		mg.add_theme_constant_override(side, 0)
	next_action.add_theme_font_size_override("font_size", _GameTheme.BODY)
	next_action.add_theme_color_override("font_color", _accent)
	_GameTheme.outline_text(next_action)
	next_action.text = ""
	# Alive at their scene paths, silent. Anything that writes to them is free to
	# keep doing so; nothing reads them back onto the screen.
	quest_name_label.visible = false
	quest_tracker.visible = false
	quest_name_label.text = ""
	quest_tracker.text = ""
	var header: Label = $QuestPanel/Margin/VBox/QuestHeader
	if header:
		header.visible = false

## The key legend: one small dim line at the bottom edge. It used to be a
## rounded 720px glass pill with a shadow.
func _dress_hint_bar() -> void:
	_hint_bar = get_node_or_null("HintBar")
	if _hint_bar == null:
		return
	_apply_theme(_hint_bar)
	_hint_bar.add_theme_stylebox_override("normal", _GameTheme.empty_box())
	_hint_bar.add_theme_font_size_override("font_size", _GameTheme.SMALL)
	_hint_bar.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	_GameTheme.outline_text(_hint_bar)

## Two full-screen tints that never eat input: red creep when you are about to
## die, and a red slam the moment you are hit. The amber reset-clock vignette is
## gone — the countdown under the region name says the same thing without
## repainting the whole frame every cycle.
func _build_alert_vignettes() -> void:
	_danger_vig = _GameTheme.make_vignette(_GameTheme.with_alpha(_GameTheme.RED, 0.7))
	_danger_vig.name = "DangerVignette"
	_danger_vig.modulate.a = 0.0
	add_child(_danger_vig)
	_hit_vig = _GameTheme.make_vignette(_GameTheme.with_alpha(_GameTheme.RED, 0.8))
	_hit_vig.name = "HitVignette"
	_hit_vig.modulate.a = 0.0
	add_child(_hit_vig)
	# Explicit order so VIGNETTE_COUNT stays honest: danger, hit.
	move_child(_danger_vig, 0)
	move_child(_hit_vig, 1)

## The waypoint owns the world-space half of "where do I go"; mounted first so
## every readout draws over it, and it never eats input.
func _mount_waypoint() -> void:
	if get_node_or_null("ObjectiveWaypoint"):
		return
	_waypoint = _ObjectiveWaypoint.new()
	_waypoint.name = "ObjectiveWaypoint"
	add_child(_waypoint)
	# Above the vignettes, below everything else — the chevron must stay crisp at
	# the screen edge, which is where the vignettes are darkest.
	move_child(_waypoint, mini(VIGNETTE_COUNT, maxi(get_child_count() - 1, 0)))

## The radar is removed, not hidden-with-a-cost: nothing is built, nothing scans
## groups twice a second, nothing redraws 96 blips at 30Hz. Kept as a function
## because `_ready` names it and because the decision deserves a place to live.
func _build_minimap() -> void:
	_minimap = null

func _setup_cycle_signals() -> void:
	CycleManager.cycle_warning.connect(_on_cycle_warning)
	CycleManager.reset_triggered.connect(_on_reset_triggered)
	ModelManager.model_changed.connect(_on_model_changed)
	AgentManager.agent_deployed.connect(_on_agent_deployed)
	AgentManager.agent_resolved.connect(_on_agent_resolved)
	ArchitectureManager.delayed_consequence.connect(_on_arch_consequence)
	EventManager.running_gag.connect(_on_running_gag)

## Every presentational tween on this layer survives `get_tree().paused`
## (HANDOVER §4.4 — the frozen-curtain class of bug). The HUD's own `_process`
## is deliberately NOT pause-proof: behind a modal the counters and the countdown
## have nothing new to say. Its one-shot flashes are a different matter — a bound
## tween stopped mid-flight leaves a red rim frozen at 70% under the pause menu.
func _tw() -> Tween:
	var t := create_tween()
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	return t

# ---------------------------------------------------------------- toast lane --
func _build_toast_lane() -> void:
	_toast_lane = Control.new()
	_toast_lane.name = "ToastLane"
	_toast_lane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_lane.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_toast_lane)
	_apply_theme(_toast_lane)

	_toast_card = Control.new()
	_toast_card.name = "ToastCard"
	_toast_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_card.size = Vector2(TOAST_W, TOAST_H)
	_toast_card.visible = false
	_toast_lane.add_child(_toast_card)

	# The scene's Notification label lives on as the toast itself — same node,
	# same path in the .tscn, one job instead of three.
	notification.reparent(_toast_card, false)
	notification.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notification.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	notification.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notification.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	notification.autowrap_mode = TextServer.AUTOWRAP_OFF
	notification.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	notification.add_theme_font_size_override("font_size", _GameTheme.BODY)
	notification.add_theme_color_override("font_color", _GameTheme.TEXT)
	_GameTheme.outline_text(notification)

## Queue a toast. `merge_key` collapses a burst of the same event into one line
## (ten token pickups in three seconds is one "+34 Tokens ×10"). `fmt` rebuilds
## the line after a merge.
##
## `kind`, `body` and `accent` are still accepted — every caller in the project
## passes them — and are deliberately not drawn any more: a toast is one line of
## TEXT. The category colour, the glyph and the second row were three ways of
## saying something the sentence already says.
func push_toast(kind: String, title: String, body := "", merge_key := "",
		amount := 0, fmt := "", accent := Color.TRANSPARENT, priority := false) -> void:
	if merge_key != "":
		if _toast_phase != 0 and _toast_key == merge_key:
			_toast_amount += amount
			_toast_merges += 1
			if _toast_fmt != "":
				notification.text = _toast_line(_toast_fmt % _toast_amount, _toast_merges)
			# Re-arm the hold so the merged line is readable again.
			if _toast_phase == 2:
				_toast_t = minf(_toast_t, TOAST_HOLD * 0.35)
			return
		for i in _toast_queue.size():
			var q: Dictionary = _toast_queue[i]
			if str(q.get("key", "")) == merge_key:
				q["amount"] = int(q.get("amount", 0)) + amount
				q["merges"] = int(q.get("merges", 1)) + 1
				if str(q.get("fmt", "")) != "":
					q["title"] = str(q["fmt"]) % int(q["amount"])
				return
	var entry := {
		"kind": kind, "title": title, "body": body, "key": merge_key,
		"amount": amount, "fmt": fmt, "merges": 1, "accent": accent,
	}
	if priority:
		_toast_queue.push_front(entry)
	else:
		_toast_queue.append(entry)
	while _toast_queue.size() > TOAST_QUEUE_MAX:
		_toast_queue.remove_at(_toast_queue.size() - 1)

func _toast_line(title: String, merges: int) -> String:
	return title if merges <= 1 else "%s  ×%d" % [title, merges]

func _begin_toast(entry: Dictionary) -> void:
	_toast_merges = int(entry.get("merges", 1))
	notification.text = _toast_line(str(entry.get("title", "")), _toast_merges)
	_toast_key = str(entry.get("key", ""))
	_toast_amount = int(entry.get("amount", 0))
	_toast_fmt = str(entry.get("fmt", ""))
	_toast_card.size = Vector2(TOAST_W, TOAST_H)
	_toast_card.visible = true
	_toast_phase = 1
	_toast_t = 0.0

func _end_toast() -> void:
	_toast_phase = 0
	_toast_t = 0.0
	_toast_key = ""
	_toast_fmt = ""
	_toast_card.visible = false

## Rise, hold, fade. Total ≈ 2.5s, one line ever.
func _tick_toasts(delta: float) -> void:
	if _toast_phase == 0:
		if _toast_queue.is_empty():
			return
		_begin_toast(_toast_queue.pop_front())
	_toast_t += delta
	var rise := 0.0
	var alpha := 1.0
	match _toast_phase:
		1:
			var k := clampf(_toast_t / TOAST_IN, 0.0, 1.0)
			var e := 1.0 - pow(1.0 - k, 3.0)
			rise = (1.0 - e) * TOAST_RISE
			alpha = e
			if k >= 1.0:
				_toast_phase = 2
				_toast_t = 0.0
		2:
			if _toast_t >= TOAST_HOLD:
				_toast_phase = 3
				_toast_t = 0.0
		3:
			var k2 := clampf(_toast_t / TOAST_OUT, 0.0, 1.0)
			rise = -k2 * TOAST_RISE * 0.4
			alpha = 1.0 - k2
			if k2 >= 1.0:
				_end_toast()
				return
	_toast_card.position = Vector2(
		roundf((_toast_lane.size.x - TOAST_W) * 0.5),
		roundf(_toast_lane.size.y + TOAST_BOTTOM + rise))
	_toast_card.modulate.a = alpha

## Legacy entry point (text + colour). Splits "title\nbody" and drops the body:
## the toast is one line now.
func _show_notification(text: String, color: Color) -> void:
	var parts := text.split("\n", false)
	var title := parts[0] if parts.size() > 0 else text
	var body := parts[1] if parts.size() > 1 else ""
	push_toast("info", title, body, "", 0, "", color)

# ---------------------------------------------------------------- notifiers --
func _on_cycle_warning(seconds_left: int) -> void:
	push_toast("alert", "Token reset in %ds" % seconds_left, "", "", 0, "",
		Color.TRANSPARENT, true)

func _on_reset_triggered(cycle: int) -> void:
	push_toast("info", "Reset · Cycle %d — quotas refilled, prices moved" % cycle,
		"", "", 0, "", Color.TRANSPARENT, true)

func _on_model_changed(_id: String, display_name: String) -> void:
	var pc: int = _player.prompt_cost() if is_instance_valid(_player) else 0
	push_toast("purchase", "Model → %s · %d tk per blast" % [display_name, pc],
		"", "model")

func _on_agent_deployed(display_name: String) -> void:
	push_toast("info", "%s deployed — resolves at the next reset" % display_name)

func _on_agent_resolved(display_name: String, summary: String) -> void:
	push_toast("info", "%s: %s" % [display_name, summary])

func _on_arch_consequence(text: String) -> void:
	push_toast("debt", text)

## The running gags EventManager keeps between cycles.
const GAG_TITLES := {
	"subscription": "Subscription renewed",
	"calm": "Nothing is happening",
	"scheduled": "Filed for later",
	"callback": "Somebody remembers",
}

func _on_running_gag(gag_id: String, note: String) -> void:
	var title: String = GAG_TITLES.get(gag_id, "Noted")
	push_toast("alert", "%s — %s" % [title, note], "", "gag_%s" % gag_id)

func _on_tokens_gained(amount: int, _source: String) -> void:
	push_toast("token", "+%d tokens" % amount, "", "tokens", amount, "+%d tokens")

func _on_price_adjustment(lost: int) -> void:
	push_toast("debt", "−%d tokens · provider pricing was 'updated'" % lost)

func _on_quest_completed(quest_id: String, _rewards: Dictionary) -> void:
	var info := QuestManager.get_quest_info(quest_id)
	push_toast("quest", "Quest complete — %s"
		% _quest_headline(quest_id, str(info.get("name", quest_id))))

func _on_achievement(_id: String, name_text: String, _desc: String) -> void:
	push_toast("achievement", name_text)

## The ability bar shares the bottom band with the dialogue panel, and abilities
## are gated during a conversation anyway (player.gd checks
## DialogueManager.is_active), so the bar and the key legend step out together.
func _on_dialogue_started(_npc_id: String) -> void:
	if is_instance_valid(_ability_bar):
		_ability_bar.visible = false
	if is_instance_valid(_hint_bar):
		_hint_bar.visible = false

func _on_dialogue_ended(_npc_id: String) -> void:
	if is_instance_valid(_ability_bar):
		_ability_bar.visible = true
	if is_instance_valid(_hint_bar):
		_hint_bar.visible = true

# -------------------------------------------------------------- ability bar --
## Six 28px squares in a row, 198px wide in total. They were 118x58 cards with a
## name, a price, a coloured chip around the key, a recharge rail, a red "broke"
## wash and a per-ability accent — six different hues on one strip, which is a
## sixth of LAW 2's entire budget spent on a legend.
##
## What survives is what you act on: which key, is it ready, can I afford it.
const SLOT_SIZE := Vector2(28, 28)
const SLOT_GAP := 6
const ABILITY_BAR_TOP := -64.0
const ABILITY_BAR_BOTTOM := -36.0
const ABILITY_BAR_HALF_W := 99.0

func _setup_ability_bar() -> void:
	var bar := HBoxContainer.new()
	bar.name = "AbilityBar"
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_constant_override("separation", SLOT_GAP)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = -ABILITY_BAR_HALF_W
	bar.offset_top = ABILITY_BAR_TOP
	bar.offset_right = ABILITY_BAR_HALF_W
	bar.offset_bottom = ABILITY_BAR_BOTTOM
	add_child(bar)
	_apply_theme(bar)
	_ability_bar = bar
	_ability_state.resize(ABILITY_DEFS.size())
	for i in ABILITY_DEFS.size():
		# -1 is "nothing painted yet", so the first update always writes a full
		# state instead of trusting a zero-initialised array.
		_ability_state[i] = -1
	for def in ABILITY_DEFS:
		var slot := Control.new()
		slot.custom_minimum_size = SLOT_SIZE
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var sb := StyleBoxFlat.new()
		sb.bg_color = _GameTheme.with_alpha(_GameTheme.BASE, 0.55)
		sb.set_border_width_all(1)
		sb.border_color = _GameTheme.with_alpha(_GameTheme.TEXT_DIM, 0.55)
		sb.set_corner_radius_all(0)
		sb.set_content_margin_all(0)
		sb.shadow_size = 0
		panel.add_theme_stylebox_override("panel", sb)
		slot.add_child(panel)

		var key := Label.new()
		key.text = str(def.key)
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		key.add_theme_font_size_override("font_size", _GameTheme.SMALL)
		key.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
		_GameTheme.outline_text(key)
		panel.add_child(key)

		# Cooldown: a dark shutter covering the slot from the top, sweeping
		# downward out of frame as the ability recharges.
		var ov := ColorRect.new()
		ov.color = _GameTheme.with_alpha(_GameTheme.VOID, 0.72)
		ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ov.anchor_left = 0.0
		ov.anchor_right = 1.0
		ov.anchor_top = 0.0
		ov.anchor_bottom = 1.0
		ov.visible = false
		slot.add_child(ov)

		bar.add_child(slot)
		_ability_slots.append(slot)
		_ability_panels.append(panel)
		_ability_overlays.append(ov)
		_ability_boxes.append(sb)
		_ability_keys.append(key)

func _update_ability_bar() -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if not is_instance_valid(_player):
			return
	for i in _ability_slots.size():
		var def: Dictionary = ABILITY_DEFS[i]
		var ready_now: bool = _player.ability_ready(def.id)
		var affordable: bool = str(def.res) == "" \
			or ResourceManager.get_value(str(def.res)) >= float(_ability_cost(def))
		# 0 ready · 1 recharging · 2 cannot afford.
		var state: int = 0 if (ready_now and affordable) else (1 if affordable else 2)
		if state != _ability_state[i]:
			_ability_state[i] = state
			var panel: Control = _ability_panels[i]
			var box: StyleBoxFlat = _ability_boxes[i]
			var key: Label = _ability_keys[i]
			# Monochrome, three readings: lit in the region accent when it is
			# yours to spend, plain when it is coming back, 40% when you are
			# short (LAW 8).
			panel.modulate.a = 1.0 if state != 2 else 0.4
			if state == 0:
				box.border_color = _GameTheme.with_alpha(_accent, 0.9)
				key.add_theme_color_override("font_color", _accent)
			else:
				box.border_color = _GameTheme.with_alpha(_GameTheme.TEXT_DIM, 0.55)
				key.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
		var frac := _cooldown_frac(def.id)
		var ov: ColorRect = _ability_overlays[i]
		ov.anchor_bottom = frac
		ov.visible = frac > 0.004

## The price the player will actually be charged this second. Only Prompt Blast
## moves — its cost scales with the active model — so everything else falls
## straight through to its static `amt`.
func _ability_cost(def: Dictionary) -> int:
	if str(def.id) == "prompt_blast" and is_instance_valid(_player) \
			and _player.has_method("prompt_cost"):
		return int(_player.prompt_cost())
	return int(def.amt)

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

# ------------------------------------------------------------------ process --
func _process(delta: float) -> void:
	_quest_ui_accum += delta
	if _quest_ui_accum >= QUEST_UI_INTERVAL:
		_quest_ui_accum = 0.0
		_update_quest_tracker()
	_update_ability_bar()
	_tick_counters(delta)
	_tick_toasts(delta)
	_tick_status(delta)

## Counters roll toward their target instead of snapping. Costs nothing when
## nothing changed: the loop exits on the first comparison for every resource
## that is already settled.
func _tick_counters(delta: float) -> void:
	var moved := false
	for k: String in COUNT_KEYS:
		var target: float = _count_target.get(k, 0.0)
		var shown: float = _count_shown.get(k, target)
		if absf(target - shown) < 0.01:
			continue
		# Proportional with a floor, so +3 still visibly ticks and +900 doesn't
		# take a week. move_toward clamps at the target, so it never overshoots.
		var step := maxf(absf(target - shown) * 7.0, 24.0) * delta
		_count_shown[k] = move_toward(shown, target, step)
		moved = true
	if moved:
		_paint_strip()

## The whole resource readout, in one string.
func _paint_strip() -> void:
	if token_label == null:
		return
	token_label.text = "%d tk  ·  %d cp" % [
		int(round(float(_count_shown.get("tokens", 0.0)))),
		int(round(float(_count_shown.get("compute", 0.0)))),
	]

## Strings are only rebuilt when the value they show actually changed.
func _tick_status(_delta: float) -> void:
	var secs := CycleManager.seconds_left()
	if region_sub:
		if secs != _cycle_shown or CycleManager.cycle != _cycle_num:
			_cycle_shown = secs
			_cycle_num = CycleManager.cycle
			region_sub.text = "Cycle %d  ·  %ds" % [CycleManager.cycle, secs]
		# The deadline gets ONE tell: the line turns amber. No pulse, no pill, no
		# full-screen wash. Written once per transition — a theme override
		# re-dirties every ancestor's minimum size, so it is not free.
		var warn := 1 if secs <= int(CycleManager.WARN_AT) else 0
		if warn != _cycle_warn:
			_cycle_warn = warn
			region_sub.add_theme_color_override("font_color",
				_GameTheme.AMBER if warn == 1 else _GameTheme.TEXT_DIM)
	# Danger vignette: red creep below a third HP, and nothing above it.
	if _danger_vig:
		var frac := 1.0
		if hp_bar.max_value > 0.0:
			frac = clampf(hp_bar.value / hp_bar.max_value, 0.0, 1.0)
		var d := 0.0
		if frac < LOW_HP_FRAC and GameManager.state == GameManager.GameState.PLAYING:
			d = (1.0 - frac / LOW_HP_FRAC) * 0.30
		_danger_vig.modulate.a = d
	_reveal_value(hp_value, hp_bar)
	_reveal_value(focus_value, focus_bar)

## A bar prints its number only when it is worth worrying about (LAW 8). The
## label keeps its column either way, so neither bar's right edge ever jumps.
func _reveal_value(l: Label, bar: ProgressBar) -> void:
	if l == null or bar == null or bar.max_value <= 0.0:
		return
	var frac := clampf(bar.value / bar.max_value, 0.0, 1.0)
	var a := 1.0 if frac < VALUE_REVEAL_FRAC else 0.0
	if absf(l.modulate.a - a) > 0.01:
		l.modulate.a = a

func _update_all() -> void:
	for k: String in COUNT_KEYS:
		var v := float(int(ResourceManager.get_value(k)))
		_count_target[k] = v
		if not _count_shown.has(k):
			# First read of the run: no roll, just the truth.
			_count_shown[k] = v
	_paint_strip()
	var tax := int(round((DreamAppManager.debt_cost_multiplier() - 1.0) * 100.0))
	debt_label.text = "+%d%%" % tax
	var target := ResourceManager.get_value("focus")
	focus_value.text = "%d" % int(target)
	if absf(focus_bar.value - target) > 0.5:
		if _focus_tween and _focus_tween.is_valid():
			_focus_tween.kill()
		_focus_tween = _tw().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_focus_tween.tween_property(focus_bar, "value", target, _GameTheme.T_STD)
	else:
		focus_bar.value = target
	_update_quest_tracker()

func _on_resource_changed(res_name: String, _old_v: float, _new_v: float) -> void:
	match res_name:
		"tokens", "compute", "context", "technical_debt", "focus":
			_update_all()

func _on_health_changed(current: int, max_hp: int) -> void:
	hp_bar.max_value = max_hp
	hp_value.text = "%d" % current
	var target := float(current)
	var prev := _hp_prev if _hp_prev >= 0.0 else target
	_hp_prev = target
	if _hp_tween and _hp_tween.is_valid():
		_hp_tween.kill()
	_hp_tween = _tw().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_hp_tween.tween_property(hp_bar, "value", target, _GameTheme.T_STD)
	if target < prev:
		_feel_damage((prev - target) / maxf(1.0, float(max_hp)))

## Damage is a fact you feel before you read it: one red rim slam, scaled to how
## much of your health just left, decaying inside half a second. The vitals
## punch, the white wash over the bar and the trailing loss ghost are gone — the
## bar getting shorter is the readout, and it does not need three chaperones.
func _feel_damage(frac_lost: float) -> void:
	if not is_instance_valid(_hit_vig):
		return
	var bite := clampf(frac_lost * 3.4, 0.15, 1.0)
	if _hit_tween and _hit_tween.is_valid():
		_hit_tween.kill()
	_hit_vig.modulate.a = 0.14 + 0.34 * bite
	_hit_tween = _tw().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_hit_tween.tween_property(_hit_vig, "modulate:a", 0.0, 0.30 + 0.18 * bite)

## Display names for every region id. The banner used to title-case the raw id,
## which printed "Gpu Mines" and "Api Bazaar" as the largest text on screen.
## Acronyms are spelling, not styling, so they are authored. Mirrors
## quest_log.gd's REGION_NAMES deliberately: the two surfaces must never
## disagree about what a place is called.
const REGION_TITLES := {
	"localhost": "Localhost",
	"dependency_district": "Dependency District",
	"stackoverflow_ruins": "Stack Overflow Ruins",
	"api_bazaar": "API Bazaar",
	"cloud_district": "Cloud District",
	"open_source_wildlands": "Open Source Wildlands",
	"corporate_enterprise": "Corporate Enterprise",
	"gpu_mines": "GPU Mines",
	"production": "Production",
	"token_vault": "Token Vault",
}

## Arrival: the name changes and fades up. That is the whole sting. The
## overbright name flash and the accent rule wiping out from the centre are
## gone — LAW 9, nothing moves at rest.
func _on_region_changed(region_id: String) -> void:
	region_label.text = _format_region(region_id)
	_accent = _GameTheme.region_accent(region_id)
	next_action.add_theme_color_override("font_color", _accent)
	if is_instance_valid(_waypoint) and _waypoint.has_method("set_accent"):
		_waypoint.call("set_accent", _accent)
	# Force the ability slots to repaint in the new accent on the next update.
	for i in _ability_state.size():
		_ability_state[i] = -1
	var t := _tw().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(region_label, "modulate:a", 1.0, _GameTheme.T_STD).from(0.0)

## Region id -> the name a human wrote. Falls back to title-casing only for an id
## nobody has authored yet.
func _format_region(id: String) -> String:
	return str(REGION_TITLES.get(id, id.replace("_", " ").capitalize()))

## The pause affordance: a glyph in the top bar's own row, past the vitals, where
## it cannot collide with anything by construction. No box.
func _setup_pause_button() -> void:
	var b := Button.new()
	b.name = "PauseButton"
	b.text = "‖"
	b.custom_minimum_size = Vector2(38, 28)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.tooltip_text = "Pause (Esc)"
	b.focus_mode = Control.FOCUS_NONE
	_GameTheme.style_button(b, _accent, _GameTheme.SMALL)
	b.add_theme_stylebox_override("normal", _GameTheme.empty_box())
	b.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	b.pressed.connect(_on_pause_button)
	# A MOUSE_FILTER_IGNORE parent does not stop its children being hit-tested,
	# so the button still takes clicks inside the pass-through top bar.
	$TopBar/HBox.add_child(b)

func _on_pause_button() -> void:
	var w := get_parent()
	if w and w.has_method("_open_pause") and GameManager.state == GameManager.GameState.PLAYING:
		w._open_pause()

## Headline names for quests whose authored name is pure punchline.
##
## quests.json stays the source of truth for ids and prose, but "TODO:
## Everything" as the NAME OF THE THING YOU ARE DOING tells a first-time player
## nothing. The pattern is COMEDY_BIBLE's own "Real Name — quip": the informative
## half leads, the gag keeps its seat. MUST stay identical to quest_log.gd's
## copy of this table.
const QUEST_HEADLINE_NAMES := {
	"hello_localhost": "First Sprint — TODO: Everything",
}

## The name to print in a headline slot (completion toast, quest log).
func _quest_headline(qid: String, authored: String) -> String:
	var over := str(QUEST_HEADLINE_NAMES.get(qid, ""))
	return over if over != "" else authored

## The one line that fixes "I don't know what to do": a concrete NEXT ACTION,
## how far and which way. Everything that used to sit under it — the quest name,
## the checklist, the progress counters — is in [J].
func _update_quest_tracker(_qid: String = "") -> void:
	var obj := QuestManager.get_current_objective()
	if obj.is_empty():
		_set_next_action("→ Ship the Dream App  ·  [B]")
		return
	var action := str(obj.get("action", obj.get("text", "")))
	# If the objective is in another region the honest instruction is "get there
	# first" — the chevron is already pointing at the door. ("region" objectives
	# already say "Travel to X"; prefixing those just stutters.)
	var region := str(obj.get("region", ""))
	if region != "" and region != GameManager.current_region \
			and str(obj.get("kind", "")) != "region":
		action = "Head to %s — %s" % [_format_region(region), action]
	_set_next_action("→ %s%s" % [action, _where_suffix()])

## "  ·  28m NE" when the waypoint has a fix on something, "" otherwise.
func _where_suffix() -> String:
	if not is_instance_valid(_waypoint) or not _waypoint.has_method("readout"):
		return ""
	if not _waypoint.has_target() or _waypoint.is_fallback():
		return ""
	var r: String = _waypoint.readout()
	if r == "":
		return ""
	return "  ·  %s" % r

## Swap the line. A genuinely new instruction fades in; a drifting distance
## readout does not. Nothing flashes, and nothing announces itself in a toast any
## more — the line is permanently on screen, so telling you about it twice was
## the definition of noise.
func _set_next_action(text: String) -> void:
	if next_action.text == text:
		return
	next_action.text = text
	# Ignore pure distance drift: only the instruction itself is newsworthy.
	var core := text.split("  ·  ")[0]
	if core == _last_action:
		return
	var first := _last_action == ""
	_last_action = core
	if first:
		return
	if _action_tween and _action_tween.is_valid():
		_action_tween.kill()
	_action_tween = _tw().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_action_tween.tween_property(next_action, "modulate:a", 1.0, _GameTheme.T_STD).from(0.35)

# ------------------------------------------------------------- intro hint ----
## One-time onboarding card: the goal, the arrow, the keys. Six lines, because
## the boot sequence is comedy, not a tutorial, and a wall of text at minute zero
## is not onboarding either.
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
	_apply_theme(root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.024, 0.055, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.add_theme_stylebox_override("panel", _GameTheme.panel_box(_accent, 28.0))
	root.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	vb.custom_minimum_size = Vector2(560, 0)
	panel.add_child(vb)
	_hint_label(vb, "WELCOME TO THE HACKATHON", _GameTheme.HEADING, _accent, true)
	_hint_label(vb, "GOAL: ship your Dream App before the reset.",
		_GameTheme.BODY, _GameTheme.TEXT)
	_hint_label(vb, "Follow the arrow. It always points at your current objective.",
		_GameTheme.BODY, _GameTheme.TEXT)
	_hint_label(vb, "WASD move  ·  E interact  ·  1 attack  ·  Shift dash\nB Dream App  ·  J quests  ·  M map  ·  H help",
		_GameTheme.SMALL, _GameTheme.TEXT_DIM)
	_hint_label(vb, "[E] to begin", _GameTheme.SMALL, _GameTheme.TEXT_DIM)
	_GameTheme.open_panel(panel)
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
		l.add_theme_font_override("font", _GameTheme.spaced_font(2))
	_GameTheme.outline_text(l)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(560, 0)
	parent.add_child(l)
