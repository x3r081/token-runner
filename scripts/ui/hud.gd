extends CanvasLayer
## HUD — the permanent readout layer.
##
## LAYOUT LANES (the whole point of this file). Every element owns a band and
## nothing is allowed to draw into anyone else's:
##
##   y 14..86     TopBar        resources | region banner | vitals | pause button
##   y 90..122    StatusStrip   cycle countdown + active model, centred pill
##   y 100..176   ToastLane     one toast card at a time, right-aligned rail
##   bottom-left  QuestPanel    the "what now" panel
##   bottom-mid   AbilityBar (y -100..-42) then HintBar (y -34..-12)
##   bottom-right Minimap       196px radar disc
##
## Round 2 stacked the region banner, the cycle/model readout and the toast on
## the same pixels at top-centre; you could not read any of the three. The fix is
## structural: the readout moved into its own pill under the banner, and toasts
## moved to a right-hand rail with a real queue, so they can never collide with
## anything again no matter how many fire at once.

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
## reparented into the toast card, where it serves as the toast headline.
@onready var notification: Label = $Notification

## The on-screen chevron that points at whatever the tracker is talking about.
var _waypoint: Control
var _minimap: Control
var _action_tween: Tween
var _last_action := ""
var _last_action_shape := ""
var _quest_ui_accum := 0.0
## Rebuilding the tracker strings four times a second is smooth to read and
## avoids allocating three Strings every single frame for a label nobody is
## staring at that hard.
const QUEST_UI_INTERVAL := 0.22

var _theme: Theme
## Half-width of the cycle/model pill under the region banner.
const STRIP_HALF_W := 268.0
var _status_strip: PanelContainer
var _cycle_label: Label
var _model_label: Label
var _cycle_num := -1
var _cycle_shown := -1
## False until the countdown has been painted in its resting colour at least
## once, so the first frame always writes it (see _tick_status).
var _cycle_calm := false
var _model_sig := ""
var _player: Node
var _ability_bar: Control
var _ability_slots: Array = []
var _ability_panels: Array = []
var _ability_overlays: Array = []
var _ability_flashes: Array = []
var _ability_boxes: Array = []
var _ability_cost_labels: Array = []
## Bottom-edge recharge rails and the "cannot afford" wash, one per slot.
var _ability_rails: Array = []
var _ability_denies: Array = []
var _ability_prev_frac: PackedFloat32Array = PackedFloat32Array()
## Last discrete slot state (0 live / 1 recharging / 2 cannot afford) and the
## last price printed on it. The continuous parts (shutter height, recharge rail)
## are cheap anchor writes and run every frame; the discrete parts are theme
## overrides, and a theme override re-dirties the minimum size of the whole
## ability bar. Writing six of them per frame for values that change twice a
## minute is how a HUD quietly costs a millisecond.
var _ability_state: PackedInt32Array = PackedInt32Array()
var _ability_shown_cost: PackedInt32Array = PackedInt32Array()
var _hp_ghost: ColorRect
var _focus_ghost: ColorRect
var _hp_tween: Tween
var _hp_ghost_tween: Tween
var _focus_ghost_tween: Tween
var _hp_prev := -1.0
var _focus_tween: Tween
var _res_chips: Dictionary = {}
var _res_chip_tweens: Dictionary = {}
var _alert_vig: TextureRect
var _danger_vig: TextureRect
## Separate from _danger_vig: that one is a sustained state (you are low), this
## one is an event (you were just hit). Two different sentences, two nodes — the
## sustained one is written every frame from _tick_status and would stomp a
## tween sharing the same node.
var _hit_vig: TextureRect
var _hit_tween: Tween
var _quest_flash: ColorRect
var _quest_flash_tween: Tween
## Vitals panel stylebox, kept so the low-HP state can pulse its border.
var _bars_box: StyleBoxFlat
var _bars_group: Control
## Objective panel stylebox, kept so the region accent can tint it on arrival.
var _quest_box: StyleBoxFlat
var _hint_bar: Label
## Resource counters roll to their new value instead of snapping. Snapping reads
## as "the number was always that"; a 0.3s roll reads as "you just earned that".
var _count_shown: Dictionary = {}
var _count_target: Dictionary = {}
var _count_hot: Dictionary = {}
## Each counter's resting font colour, captured from the scene before anything
## overrides it. The roll's overbright rides the FONT colour, not `modulate`:
## the floating "+12" delta chip is a CHILD of the counter label, and modulate
## multiplies down the tree, so a 1.9x lift on the number blew the chip out to
## white for the first half of its life and lost the green/red that says whether
## the tick was a gain or a spend. Font colours may exceed 1.0, so bloom still
## picks the number up.
var _count_base_col: Dictionary = {}
const COUNT_KEYS := ["tokens", "compute", "context"]
## Low-HP threshold shared by the danger vignette, the bar pulse and the value
## colour, so all three agree on what "in trouble" means.
const LOW_HP_FRAC := 0.34
## Danger, reset and hit vignettes occupy the first N child slots of this layer.
const VIGNETTE_COUNT := 3

## key, display name, resource cost label, cost resource + amount for affordability.
##
## `amt` is the STATIC price. Prompt Blast's real price is model-dependent
## (`player.prompt_cost()` = ceil(5 * ModelManager.cost_mult())), so its entry is
## the fallback only — `_ability_cost()` resolves it live. Without that the slot
## printed "5 tk" and read as affordable on a premium model that actually wanted
## 12, i.e. the bar was lying about the one number the player budgets against.
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

# ------------------------------------------------------------------- toasts --
## One card, one lane, one at a time. Accent + glyph carry the category before
## the text is even read: GOLD quest, CYAN purchase, RED debt, VIOLET trophy.
## Glyphs are deliberately restricted to the Geometric Shapes / Dingbats subset
## the project's fallback font already renders elsewhere in this HUD — a toast
## opening with a tofu box is worse than no glyph at all.
const TOAST_KINDS := {
	"quest": {"accent": _GameTheme.GOLD, "glyph": "✓"},
	"purchase": {"accent": _GameTheme.CYAN, "glyph": "◆"},
	"debt": {"accent": _GameTheme.RED, "glyph": "▼"},
	"achievement": {"accent": _GameTheme.VIOLET, "glyph": "★"},
	"token": {"accent": _GameTheme.GOLD, "glyph": "◆"},
	"info": {"accent": _GameTheme.BLUE, "glyph": "●"},
	"alert": {"accent": _GameTheme.AMBER, "glyph": "⚠"},
	"objective": {"accent": _GameTheme.CYAN_HOT, "glyph": "▸"},
}
const TOAST_W := 372.0
const TOAST_H := 66.0
## The height budget a toast's COPY is expected to fit in — two wrapped headline
## lines plus two body lines land around 118px. It is documentation, not a
## clamp: the card grows to whatever the wrapped text needs (see _fit_toast),
## because clipping a guidance card is the defect this lane was rebuilt to fix.
## If a real toast exceeds this, shorten the string, not the card.
const TOAST_H_MAX := 132.0
## Width the text column actually gets inside the card: TOAST_W minus the glass
## box's content margins (8+8), the accent stripe (3), the glyph column (28) and
## the row's two separations (10+10). Used only to SEED a freshly-shown label's
## wrap width — the real width comes from the container a frame later.
const TOAST_TEXT_W := TOAST_W - 67.0
const TOAST_TOP := 100.0
const TOAST_PAD := 24.0
const TOAST_SLIDE := 56.0
const TOAST_IN := 0.20
const TOAST_HOLD := 1.90
const TOAST_OUT := 0.30
const TOAST_QUEUE_MAX := 5

var _toast_lane: Control
var _toast_card: PanelContainer
var _toast_box: StyleBoxFlat
var _toast_stripe: ColorRect
var _toast_glyph: Label
var _toast_body: Label
var _toast_count: Label
var _toast_queue: Array[Dictionary] = []
var _toast_phase := 0  # 0 idle, 1 slide-in, 2 hold, 3 slide-out
var _toast_t := 0.0
var _toast_key := ""
var _toast_amount := 0
var _toast_fmt := ""
var _toast_merges := 1

func _ready() -> void:
	# CanvasLayer order. The HUD used to sit on the default layer 1, which put it
	# UNDER the boss presentation layer (3): a boss entrance letterbox visibly
	# dimmed the resource bar and the ability bar, and the entrance card landed on
	# top of both. The permanent readout is not allowed to be dimmed by a
	# cinematic — it is the thing you play from. Layer 4 keeps the HUD above the
	# boss layer and the death red-out (2) while staying below guidance (8),
	# dialogue (10), event popups (15) and the opening sequence (100), all of
	# which are modal and DO outrank it.
	layer = HUD_LAYER
	_theme = _GameTheme.create()
	$TopBar.theme = _theme
	$QuestPanel.theme = _theme
	# Draw order, back to front: alert vignettes, waypoint chevron, then every
	# panel. The vignettes tint the WORLD, never the readouts sitting on it.
	_build_alert_vignettes()
	_mount_waypoint()
	_dress_top_bar()
	_dress_quest_panel()
	_dress_hint_bar()
	_build_status_strip()
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
	# Prime the banner so the region accent and rule are correct on frame one,
	# not only after the first portal.
	_on_region_changed(GameManager.current_region)

## Grouped glass panels: resources | region banner | vitals.
##
## HIERARCHY (round 5). Round 4 shipped every readout at one loudness: the
## resource counters were 22px gold, and the two bars that decide whether you
## live were 10px labels and a 13px strip in the far corner. That is backwards.
## The tiers are now explicit:
##
##   LOUD   vitals (HP/FOC) and the current objective — the next second of play
##   MID    resources — the next minute of play
##   QUIET  region subtitle, cycle/model strip, hint bar — flavour and reference
##
## Loudness is carried by size, weight, outline and opacity, never by inventing
## new colours: the palette stays the bible's.
func _dress_top_bar() -> void:
	$TopBar.add_theme_stylebox_override("panel", _GameTheme.empty_box())
	$TopBar/HBox/ResourcesPanel.add_theme_stylebox_override("panel", _GameTheme.glass_box(_GameTheme.GOLD))
	_bars_box = _GameTheme.glass_box(_GameTheme.RED, 10.0)
	$TopBar/HBox/BarsPanel.add_theme_stylebox_override("panel", _bars_box)
	# The region banner is TYPE, not a box. Round 2 gave it a glass panel that
	# expanded to fill the whole bar — a 1500px empty rectangle with two words in
	# it. Now the name floats, underlined by a rule that wipes in on arrival.
	$TopBar/HBox/RegionPanel.add_theme_stylebox_override("panel", _GameTheme.empty_box())
	region_label.add_theme_font_override("font", _GameTheme.spaced_font(4))
	region_label.add_theme_color_override("font_color", _GameTheme.TEXT)
	region_label.add_theme_color_override("font_outline_color", Color(0.02, 0.024, 0.055, 0.85))
	region_label.add_theme_constant_override("outline_size", 5)
	region_sub.add_theme_font_override("font", _GameTheme.spaced_font(1))
	# Outline only, no opacity tier: the scene already colours this at 0.9 alpha
	# and 12px, and stacking a QUIET tier on top of that crosses from "quiet" into
	# "cannot be read over a lit floor". Size and colour carry the tier here.
	_GameTheme.outline_text(region_sub, 3)
	region_rule.material = _GameTheme.additive_material()
	region_rule.resized.connect(func() -> void:
		region_rule.pivot_offset = region_rule.size * 0.5)
	# -- MID tier: resources. "DEBT TAX" was being clipped to "DEBT TAI" at the
	# panel's right margin in half the QA frames; the block needed the width its
	# own title asks for.
	var debt_block: Control = $TopBar/HBox/ResourcesPanel/Resources/DebtBlock
	debt_block.custom_minimum_size.x = 78.0
	for path: String in ["TokenBlock/TokenTitle", "ComputeBlock/ComputeTitle",
			"ContextBlock/ContextTitle", "DebtBlock/DebtTitle"]:
		var t: Label = get_node_or_null("TopBar/HBox/ResourcesPanel/Resources/" + path)
		if t:
			t.add_theme_font_override("font", _GameTheme.spaced_font(2))
			_GameTheme.outline_text(t, 3)
	for v: Label in [token_label, compute_label, context_label, debt_label]:
		_GameTheme.outline_text(v, 4)
	# Capture the resting colours BEFORE the roll ever repaints them, so the
	# overbright always returns to the palette the scene authored per resource.
	for k: String in COUNT_KEYS:
		var cl := _counter_label(k)
		if cl != null:
			_count_base_col[k] = cl.get_theme_color("font_color")
	# -- LOUD tier: vitals. Taller bars, a readable value, a lit tube fill.
	hp_bar.custom_minimum_size = Vector2(180, 20)
	focus_bar.custom_minimum_size = Vector2(180, 15)
	_GameTheme.style_bar(hp_bar, _GameTheme.RED, Color("#FF9A7A"))
	_GameTheme.style_bar(focus_bar, _GameTheme.CYAN, _GameTheme.CYAN_HOT)
	hp_value.add_theme_font_size_override("font_size", 16)
	hp_value.add_theme_color_override("font_color", _GameTheme.WHITE_HOT)
	_GameTheme.outline_text(hp_value, 4)
	focus_value.add_theme_font_size_override("font_size", 12)
	_GameTheme.outline_text(focus_value, 3)
	# Both readouts print "100/100", but at 16px and 12px — so their natural
	# minimum widths differ, and since the bars EXPAND_FILL into whatever is left,
	# the HP bar's right edge would stop short of the FOC bar's. One shared value
	# column keeps the two bars exactly the same length, which is the only reason
	# the pair reads as one instrument instead of two strips.
	hp_value.custom_minimum_size.x = 72.0
	focus_value.custom_minimum_size.x = 72.0
	# The captions used to be 11px, letter-spaced by 2 and painted in TEXT_DIM —
	# which at a demo's viewing distance is a smudge, on the two readouts the
	# LOUD tier is supposed to own. They are now 13px in full TEXT, and each one
	# is tinted toward its own bar so the caption identifies the instrument it
	# labels instead of being generic chrome.
	for lp: String in ["HPBlock/HPLabel", "FocusBlock/FocusLabel"]:
		var l: Label = get_node_or_null("TopBar/HBox/BarsPanel/Bars/" + lp)
		if l:
			l.add_theme_font_size_override("font_size", 13)
			l.add_theme_font_override("font", _GameTheme.spaced_font(1))
			l.custom_minimum_size.x = 38.0
			_GameTheme.outline_text(l, 4)
	var hp_cap: Label = get_node_or_null("TopBar/HBox/BarsPanel/Bars/HPBlock/HPLabel")
	if hp_cap:
		hp_cap.add_theme_color_override("font_color",
			_GameTheme.TEXT.lerp(_GameTheme.RED, 0.35))
	var foc_cap: Label = get_node_or_null("TopBar/HBox/BarsPanel/Bars/FocusBlock/FocusLabel")
	if foc_cap:
		foc_cap.add_theme_color_override("font_color",
			_GameTheme.TEXT.lerp(_GameTheme.CYAN, 0.35))
	_bars_group = get_node_or_null("TopBar/HBox/BarsPanel/Bars")
	_hp_ghost = _make_ghost(hp_bar, _GameTheme.RED)
	_focus_ghost = _make_ghost(focus_bar, _GameTheme.CYAN_HOT)
	# Track frames LAST, so they draw over the fill and over the loss ghost.
	_make_track(hp_bar, _GameTheme.RED)
	_make_track(focus_bar, _GameTheme.CYAN)
	# Floating "+12 / −5" chips next to each counter.
	_res_chips["tokens"] = _make_chip(token_label)
	_res_chips["compute"] = _make_chip(compute_label)
	_res_chips["context"] = _make_chip(context_label)
	_res_chips["technical_debt"] = _make_chip(debt_label)
	# Slow diagonal sheen on both glass groups, offset in period so they don't
	# pulse in lockstep — the top bar reads as two panes of lit glass rather than
	# two rectangles. Guarded inside add_sheen if the shader is missing.
	_GameTheme.add_sheen($TopBar/HBox/ResourcesPanel,
		_GameTheme.with_alpha(_GameTheme.GOLD, 0.045), 8.0)
	_GameTheme.add_sheen($TopBar/HBox/BarsPanel,
		_GameTheme.with_alpha(_GameTheme.WHITE_HOT, 0.04), 11.0)

## Every presentational tween on this layer, in one place, and every one of them
## survives `get_tree().paused` (HANDOVER §4.4 — the frozen-curtain class of bug).
##
## The HUD's own `_process` is deliberately NOT pause-proof: while a pause menu,
## a flavour popup or an incident ticket is up, the counters, the ability bar and
## the countdown have nothing new to say. Its one-shot FLASHES are a different
## matter — a bound tween stops mid-flight, and "mid-flight" for the hit vignette
## means a full-screen red rim frozen at 70% under the pause menu, and for the
## region rule means a 4px stub where the underline should be. They must be able
## to finish and clean up whatever the tree is doing.
func _tw() -> Tween:
	var t := create_tween()
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	return t

## Trailing segment that marks what a bar just lost, then burns away.
func _make_ghost(bar: ProgressBar, col: Color) -> ColorRect:
	var g := ColorRect.new()
	g.name = "Ghost"
	g.color = _GameTheme.with_alpha(col, 0.62)
	g.material = _GameTheme.additive_material()
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.visible = false
	g.anchor_top = 0.15
	g.anchor_bottom = 0.85
	g.anchor_left = 1.0
	g.anchor_right = 1.0
	bar.add_child(g)
	return g

## Tube frame + quarter ticks, drawn OVER the bar.
##
## Godot's ProgressBar paints the fill across the whole rect, border included,
## so a bar at 100% is a solid coloured block with no track left to compare it
## against — in the QA frames HP and FOC read as two decorative stripes rather
## than two gauges. Putting the frame in a CHILD of the bar means it is drawn
## after the fill (and after the loss ghost), so the outline and the 25/50/75
## ticks survive a full bar: the shape says "scale" before the numbers are read.
func _make_track(bar: ProgressBar, tint: Color) -> Control:
	var f := BarTrack.new()
	f.name = "Track"
	f.tint = tint
	bar.add_child(f)
	f.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return f

func _make_chip(host: Label) -> Label:
	var l := Label.new()
	l.name = "DeltaChip"
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.024, 0.055, 0.9))
	l.add_theme_constant_override("outline_size", 3)
	l.anchor_left = 1.0
	l.anchor_right = 1.0
	l.offset_left = 2.0
	l.offset_right = 76.0
	l.offset_top = -2.0
	l.offset_bottom = 20.0
	l.modulate.a = 0.0
	host.add_child(l)
	return l

func _dress_quest_panel() -> void:
	_quest_box = _GameTheme.glass_box(_GameTheme.CYAN, 4.0)
	$QuestPanel.add_theme_stylebox_override("panel", _quest_box)
	var header: Label = $QuestPanel/Margin/VBox/QuestHeader
	_GameTheme.style_heading(header, _GameTheme.CYAN, 12)
	# The caption is chrome, not information — QUIET, so the eye lands on the
	# instruction under it rather than on the word "OBJECTIVE".
	_GameTheme.outline_text(header, 3)
	_GameTheme.tier(header, _GameTheme.TIER_QUIET)
	# The headline: one concrete instruction, in the brightest thing on the panel.
	# LOUD tier — this is the sentence the whole guidance system exists to print.
	next_action.add_theme_font_size_override("font_size", 20)
	next_action.add_theme_color_override("font_color", _GameTheme.CYAN_HOT)
	next_action.add_theme_color_override("font_outline_color", Color(0.02, 0.024, 0.055, 0.95))
	next_action.add_theme_constant_override("outline_size", 5)
	# Supporting cast, one step down each: which quest, then its checklist.
	quest_name_label.add_theme_font_size_override("font_size", 13)
	quest_name_label.add_theme_color_override("font_color", _GameTheme.TEXT)
	_GameTheme.outline_text(quest_name_label, 3)
	_GameTheme.tier(quest_name_label, _GameTheme.TIER_MID)
	quest_tracker.add_theme_font_size_override("font_size", 12)
	quest_tracker.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	# The checklist is subordinate by SIZE (12 vs the headline's 20) and COLOUR
	# (TEXT_DIM vs CYAN_HOT); dimming it further would make progress counters —
	# the numbers that tell you how close you are — genuinely hard to read.
	_GameTheme.outline_text(quest_tracker, 3)
	_GameTheme.tier(quest_tracker, _GameTheme.TIER_MID)
	# A fat accent rail down the left edge — from the far side of the screen this
	# is the shape that says "your instructions live here". It rides the stylebox
	# rather than a child node on purpose: QuestPanel is a PanelContainer, and a
	# PanelContainer stretches every child to fill it (a rail added as a node
	# would render as a full-panel wash).
	_quest_box.set_border_width(SIDE_LEFT, 3)
	_quest_box.border_color = _GameTheme.with_alpha(_GameTheme.CYAN, 0.5)
	_quest_box.corner_radius_top_left = 2
	_quest_box.corner_radius_bottom_left = 2
	# Breathing room under the last checklist line. The scene's 10px bottom margin
	# plus the glass box's 4px content margin left the final bullet's descenders
	# ~14px off the border — which, with the panel's own accent glow bleeding
	# inward, reads as text sitting on its own frame. The last line of the
	# instruction set is not the place to look cramped.
	var mg: MarginContainer = $QuestPanel/Margin
	mg.add_theme_constant_override("margin_top", 12)
	mg.add_theme_constant_override("margin_bottom", 16)
	# The panel is a fixed 208px box in the scene, but its checklist grows with
	# the quest. A three-objective quest overflowed the glass and printed its last
	# line on bare world pixels. It now sizes to its own content, bottom-anchored,
	# which also means a quiet moment gets a quiet, small panel.
	var vb: Control = $QuestPanel/Margin/VBox
	# Deferred: the signal fires mid-layout, and moving the panel's own offset
	# from inside a layout pass is how you get a frame of visible jitter.
	vb.minimum_size_changed.connect(_fit_quest_panel, CONNECT_DEFERRED)
	call_deferred("_fit_quest_panel")
	# Clear the scene's placeholder copy so the first real update counts as a
	# change (and so a stale "Talk to Claude" never survives into another region).
	next_action.text = ""
	quest_name_label.text = ""
	quest_tracker.text = ""
	# Slow diagonal sheen: the panel reads as glass instead of a rectangle.
	_GameTheme.add_sheen($QuestPanel, _GameTheme.with_alpha(_GameTheme.CYAN, 0.05), 9.0)
	# Gold wash fired on quest completion — the toast says what happened, this
	# says it happened HERE, on the panel you were reading.
	_quest_flash = ColorRect.new()
	_quest_flash.name = "QuestFlash"
	_quest_flash.color = _GameTheme.with_alpha(_GameTheme.GOLD, 0.0)
	_quest_flash.material = _GameTheme.additive_material()
	_quest_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$QuestPanel.add_child(_quest_flash)

## Bottom-anchored, content-sized. QuestPanel keeps its scene anchors (both
## vertical anchors at 1.0), so moving offset_top is the whole job — the bottom
## edge stays pinned 24px off the floor and the panel grows upward.
const QUEST_PANEL_MIN_H := 96.0
## Generous ceiling: the longest authored quest is four objectives, and a panel
## that tall still clears the top half of the screen. The clamp exists to stop a
## pathological objective list from becoming a wall, not to trim a normal one.
const QUEST_PANEL_MAX_H := 400.0

## Deadband. The headline carries a live distance ("… (13m · W)") that is
## rewritten four times a second, so the panel's content height is nudged
## constantly by a couple of pixels of glyph metrics. Re-anchoring the panel for
## every one of those is a relayout the player sees as a shiver in the corner of
## the screen. Only a real change — a line gained or lost — moves it.
const QUEST_PANEL_DEADBAND := 8.0

func _fit_quest_panel() -> void:
	var p: PanelContainer = get_node_or_null("QuestPanel")
	if p == null:
		return
	var h := clampf(p.get_combined_minimum_size().y, QUEST_PANEL_MIN_H, QUEST_PANEL_MAX_H)
	var target := p.offset_bottom - h
	# GROWTH IS NEVER DEADBANDED. The deadband exists to stop the panel shivering
	# when the live distance readout re-measures by a pixel or two — but a
	# deadband that also swallows growth lets a line the content just gained
	# print into (or straight through) the bottom margin, which is the one
	# failure this whole fit routine exists to prevent. Only SHRINKING waits.
	if target >= p.offset_top and absf(target - p.offset_top) < QUEST_PANEL_DEADBAND:
		return
	p.offset_top = target

## The key legend. QUIET tier, but "quiet" in round 4 meant 72%-alpha 12px text
## laid straight onto the world at the bottom of the frame — in the QA captures
## it was competing with floor tiles and losing. It keeps its low loudness and
## gains a readable ground: outline plus a narrow glass strip behind it.
func _dress_hint_bar() -> void:
	_hint_bar = get_node_or_null("HintBar")
	if _hint_bar == null:
		return
	var box := _GameTheme.glass_box(_GameTheme.CYAN, 4.0)
	box.bg_color = _GameTheme.with_alpha(_GameTheme.BASE, 0.62)
	box.border_color = _GameTheme.with_alpha(_GameTheme.LINE, 0.5)
	box.shadow_size = 6
	box.set_corner_radius_all(11)
	box.content_margin_left = 18.0
	box.content_margin_right = 18.0
	box.content_margin_top = 2.0
	box.content_margin_bottom = 2.0
	_hint_bar.add_theme_stylebox_override("normal", box)
	_hint_bar.add_theme_color_override("font_color",
		_GameTheme.with_alpha(_GameTheme.TEXT_DIM, 0.95))
	_hint_bar.add_theme_font_override("font", _GameTheme.spaced_font(1))
	_GameTheme.outline_text(_hint_bar, 3)
	# A Label paints its stylebox across its WHOLE rect, and the scene pins that
	# rect at a flat 720px. Left alone the "pill" is a 720px slab with the legend
	# floating inside it — and the moment letter-spacing pushes the text past
	# 720 the label grows rightward from a fixed left offset and the legend
	# drifts off centre. Sizing the pill to its own content fixes both.
	_hint_bar.minimum_size_changed.connect(_fit_hint_bar, CONNECT_DEFERRED)
	call_deferred("_fit_hint_bar")

## Centre the hint pill on its own content width. No layout feedback: the width
## it reads (minimum size) depends on the text, font and stylebox margins only —
## never on the offsets this writes.
func _fit_hint_bar() -> void:
	if not is_instance_valid(_hint_bar):
		return
	var w := maxf(_hint_bar.get_combined_minimum_size().x, 120.0)
	_hint_bar.offset_left = -w * 0.5
	_hint_bar.offset_right = w * 0.5

## Full-screen vignettes that never eat input: amber when the reset clock is in
## its final seconds, red when you are about to die, and a sharp red slam the
## moment you take a hit. Alpha on the first two is driven from _process (one
## property write each per frame); the hit flash is tween-driven on its own node
## so the two never fight over the same value.
func _build_alert_vignettes() -> void:
	_danger_vig = _GameTheme.make_vignette(_GameTheme.with_alpha(_GameTheme.RED, 0.85))
	_danger_vig.name = "DangerVignette"
	_danger_vig.modulate.a = 0.0
	add_child(_danger_vig)
	move_child(_danger_vig, 0)
	# Palette RED pushed a step toward VOID — a deeper, bloodier rim than the
	# sustained danger vignette, without inventing a colour outside the bible.
	_hit_vig = _GameTheme.make_vignette(
		_GameTheme.with_alpha(_GameTheme.RED.lerp(_GameTheme.VOID, 0.18), 0.95))
	_hit_vig.name = "HitVignette"
	_hit_vig.modulate.a = 0.0
	add_child(_hit_vig)
	_alert_vig = _GameTheme.make_vignette(_GameTheme.with_alpha(_GameTheme.AMBER, 0.8))
	_alert_vig.name = "ResetVignette"
	_alert_vig.modulate.a = 0.0
	add_child(_alert_vig)
	# Explicit order so VIGNETTE_COUNT below stays honest: danger, reset, hit.
	move_child(_danger_vig, 0)
	move_child(_alert_vig, 1)
	move_child(_hit_vig, 2)

## The waypoint owns the world-space half of "where do I go"; it is mounted
## first so every panel and modal draws over it, and it never eats input.
func _mount_waypoint() -> void:
	if get_node_or_null("ObjectiveWaypoint"):
		return
	_waypoint = _ObjectiveWaypoint.new()
	_waypoint.name = "ObjectiveWaypoint"
	add_child(_waypoint)
	# Above every vignette, below every panel — the chevron must stay crisp at the
	# screen edge, which is exactly where the vignettes are at their darkest.
	move_child(_waypoint, mini(VIGNETTE_COUNT, maxi(get_child_count() - 1, 0)))

# -------------------------------------------------------------- status strip --
## Cycle countdown + active model, in one centred pill directly under the region
## banner. Previously two naked labels floating at y=92/110 with a toast landing
## on top of them.
func _build_status_strip() -> void:
	var strip := PanelContainer.new()
	strip.name = "StatusStrip"
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.anchor_left = 0.5
	strip.anchor_right = 0.5
	strip.offset_left = -STRIP_HALF_W
	strip.offset_right = STRIP_HALF_W
	strip.offset_top = 90.0
	strip.offset_bottom = 122.0
	var box := _GameTheme.glass_box(_GameTheme.CYAN, 4.0)
	# QUIET tier, but the countdown on it is the deadline the whole game hangs on:
	# it has to survive a bright floor. 0.70 alpha did not.
	box.bg_color = _GameTheme.with_alpha(_GameTheme.BASE, 0.84)
	box.border_color = _GameTheme.with_alpha(_GameTheme.LINE, 0.8)
	box.set_corner_radius_all(13)
	box.content_margin_left = 16.0
	box.content_margin_right = 16.0
	strip.add_theme_stylebox_override("panel", box)
	add_child(strip)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 14)
	strip.add_child(row)

	_cycle_label = _strip_label(row)
	var div := ColorRect.new()
	div.custom_minimum_size = Vector2(1, 14)
	div.color = _GameTheme.with_alpha(_GameTheme.LINE, 0.9)
	div.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(div)
	_model_label = _strip_label(row)
	_model_label.add_theme_font_size_override("font_size", 13)
	_status_strip = strip
	# The banner sits centred inside the RegionPanel, which is only centred on the
	# screen when the two side panels happen to be the same width. Rather than
	# hope, the strip tracks the banner's actual centre — one callback, fired on
	# layout changes, and the two lanes stay stacked to the pixel.
	var rp: Control = $TopBar/HBox/RegionPanel
	rp.item_rect_changed.connect(_align_status_strip)
	call_deferred("_align_status_strip")

func _align_status_strip() -> void:
	if not is_instance_valid(_status_strip):
		return
	var rp: Control = get_node_or_null("TopBar/HBox/RegionPanel")
	var vp := get_viewport()
	if rp == null or vp == null:
		return
	var view := vp.get_visible_rect().size
	if view.x <= 1.0:
		return
	var shift := (rp.global_position.x + rp.size.x * 0.5) - view.x * 0.5
	_status_strip.offset_left = -STRIP_HALF_W + shift
	_status_strip.offset_right = STRIP_HALF_W + shift

func _strip_label(row: HBoxContainer) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_font_override("font", _GameTheme.spaced_font(1))
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.024, 0.055, 0.9))
	l.add_theme_constant_override("outline_size", 3)
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(l)
	return l

func _setup_cycle_signals() -> void:
	CycleManager.cycle_warning.connect(_on_cycle_warning)
	CycleManager.reset_triggered.connect(_on_reset_triggered)
	ModelManager.model_changed.connect(_on_model_changed)
	AgentManager.agent_deployed.connect(_on_agent_deployed)
	AgentManager.agent_resolved.connect(_on_agent_resolved)
	ArchitectureManager.delayed_consequence.connect(_on_arch_consequence)
	EventManager.running_gag.connect(_on_running_gag)

# ---------------------------------------------------------------- toast lane --
func _build_toast_lane() -> void:
	_toast_lane = Control.new()
	_toast_lane.name = "ToastLane"
	_toast_lane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_lane.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_toast_lane)

	_toast_card = PanelContainer.new()
	_toast_card.name = "ToastCard"
	_toast_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box = _GameTheme.glass_box(_GameTheme.CYAN, 8.0)
	_toast_box.bg_color = _GameTheme.with_alpha(_GameTheme.BASE, 0.93)
	_toast_box.shadow_size = 14
	_toast_card.add_theme_stylebox_override("panel", _toast_box)
	_toast_card.visible = false
	_toast_lane.add_child(_toast_card)
	_toast_card.size = Vector2(TOAST_W, TOAST_H)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	_toast_card.add_child(row)

	_toast_stripe = ColorRect.new()
	_toast_stripe.custom_minimum_size = Vector2(3, 0)
	_toast_stripe.size_flags_vertical = Control.SIZE_FILL
	_toast_stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_stripe.material = _GameTheme.additive_material()
	row.add_child(_toast_stripe)

	_toast_glyph = Label.new()
	_toast_glyph.custom_minimum_size = Vector2(28, 0)
	_toast_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_glyph.add_theme_font_size_override("font_size", 22)
	_toast_glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_toast_glyph)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 1)
	row.add_child(col)

	# The scene's Notification label lives on as the toast headline — same node,
	# same path in the .tscn, new and considerably better job.
	notification.reparent(col, false)
	notification.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notification.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	# A toast that ellipsises mid-word threw away the half of the sentence that
	# said what to do: "NEXT: Head to Localhost — Coll…" is a guidance card that
	# guides nowhere. The headline wraps instead and the card grows to hold it
	# (see _fit_toast). OVERRUN_NO_TRIMMING is load-bearing, not cosmetic — an
	# autowrapping Label reports a minimum HEIGHT of 1px the moment any trimming
	# behaviour is set, so with ellipsis on, the card could never measure itself.
	notification.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notification.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	notification.add_theme_font_size_override("font_size", 17)
	notification.add_theme_font_override("font", _GameTheme.spaced_font(1))

	_toast_body = Label.new()
	_toast_body.name = "ToastBody"
	_toast_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_body.add_theme_font_size_override("font_size", 13)
	_toast_body.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	# Same contract as the headline: wrap, never trim, so the card can measure it.
	_toast_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_body.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	col.add_child(_toast_body)

	_toast_count = Label.new()
	_toast_count.name = "ToastCount"
	_toast_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_count.custom_minimum_size = Vector2(34, 0)
	_toast_count.add_theme_font_size_override("font_size", 13)
	_toast_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_toast_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast_count.visible = false
	row.add_child(_toast_count)

	# Glass sheen over the card (second child of the PanelContainer, so it fills
	# the same rect and rides over the text at 5% — guarded inside add_sheen).
	_GameTheme.add_sheen(_toast_card, _GameTheme.with_alpha(_GameTheme.WHITE_HOT, 0.05), 6.0)

## Queue a toast. `merge_key` collapses a burst of the same event into one card
## (ten token pickups in three seconds is one "+34 Tokens ×10", not ten cards
## fighting for the same rectangle). `fmt` rebuilds the headline after a merge.
func push_toast(kind: String, title: String, body := "", merge_key := "",
		amount := 0, fmt := "", accent := Color.TRANSPARENT, priority := false) -> void:
	if merge_key != "":
		if _toast_phase != 0 and _toast_key == merge_key:
			_toast_amount += amount
			_toast_merges += 1
			if _toast_fmt != "":
				notification.text = _toast_fmt % _toast_amount
			_toast_count.text = "×%d" % _toast_merges
			_toast_count.visible = _toast_merges > 1
			# Re-arm the hold so the merged card is readable again.
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

func _begin_toast(entry: Dictionary) -> void:
	var kind := str(entry.get("kind", "info"))
	var style: Dictionary = TOAST_KINDS.get(kind, TOAST_KINDS["info"])
	var accent: Color = entry.get("accent", Color.TRANSPARENT)
	if accent.a <= 0.0:
		accent = style["accent"]
	_toast_box.border_color = _GameTheme.with_alpha(accent, 0.85)
	_toast_box.shadow_color = _GameTheme.with_alpha(accent, 0.24)
	_toast_stripe.color = _GameTheme.with_alpha(accent, 0.95)
	_toast_glyph.text = str(style["glyph"])
	_toast_glyph.add_theme_color_override("font_color", _GameTheme.hot_of(accent))
	notification.text = str(entry.get("title", ""))
	notification.add_theme_color_override("font_color", _GameTheme.hot_of(accent))
	_toast_body.text = str(entry.get("body", ""))
	_toast_body.visible = _toast_body.text != ""
	_toast_merges = int(entry.get("merges", 1))
	_toast_count.text = "×%d" % _toast_merges
	_toast_count.visible = _toast_merges > 1
	_toast_count.add_theme_color_override("font_color", _GameTheme.with_alpha(accent, 0.9))
	_toast_key = str(entry.get("key", ""))
	_toast_amount = int(entry.get("amount", 0))
	_toast_fmt = str(entry.get("fmt", ""))
	# Seed both labels' wrap width BEFORE the card is measured. While the card is
	# hidden the box containers skip their children, so a label that has never
	# been shown still has width 0 — and an autowrapping Label at width 0 reports
	# one line per WORD. Since Control.set_size clamps UP to the minimum size,
	# measuring that would inflate the card to full height for a frame. The
	# container overwrites these on its next sort with the same number.
	notification.size.x = TOAST_TEXT_W
	_toast_body.size.x = TOAST_TEXT_W
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

## Slide in from the right, hold, slide back out. Total ≈ 2.4s, one card ever.
func _tick_toasts(delta: float) -> void:
	if _toast_phase == 0:
		if _toast_queue.is_empty():
			return
		_begin_toast(_toast_queue.pop_front())
	_toast_t += delta
	var slide := 0.0
	var alpha := 1.0
	match _toast_phase:
		1:
			var k := clampf(_toast_t / TOAST_IN, 0.0, 1.0)
			var e := 1.0 - pow(1.0 - k, 3.0)
			slide = (1.0 - e) * TOAST_SLIDE
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
			slide = k2 * k2 * TOAST_SLIDE
			alpha = 1.0 - k2
			if k2 >= 1.0:
				_end_toast()
				return
	_fit_toast()
	_toast_card.position = Vector2(
		_toast_lane.size.x - TOAST_PAD - TOAST_W + slide, TOAST_TOP)
	_toast_card.modulate.a = alpha

## The card is a fixed-width rail (right-aligned, so its width is the design)
## and a content-sized height (so wrapped text is never cut). Written every
## frame the card is up: it is one comparison plus, on the rare frame the text
## actually changed, one size assignment. The width never moves, so the labels'
## wrap width is constant and this cannot feed back into its own measurement.
func _fit_toast() -> void:
	# A hidden card's children are skipped by the box containers' resort, so on
	# the very first frame after a toast is shown the headline still has zero
	# width — and an autowrapping Label with no width reports an absurd height.
	# Measuring that would flash a full-height card for one frame. Wait for the
	# label to have been laid out; the card holds TOAST_H until then.
	if notification.size.x < 40.0:
		return
	# Grow to whatever the wrapped text actually needs, never below the design
	# height. TOAST_H_MAX is deliberately NOT a clamp here: `Control.set_size`
	# raises whatever it is handed to the combined minimum size, so clamping the
	# request at a ceiling the content has already passed does not shrink the
	# card — it just makes the "did it change" test compare against a number the
	# card can never hold, and the HUD re-lays-out the whole toast every single
	# frame for the life of the card. A ceiling that cannot be enforced is not a
	# ceiling; the honest number is the one below, and TOAST_H_MAX survives as
	# the budget the copy is expected to fit in (see its comment).
	var h := maxf(_toast_card.get_combined_minimum_size().y, TOAST_H)
	if absf(_toast_card.size.y - h) > 0.5 or absf(_toast_card.size.x - TOAST_W) > 0.5:
		_toast_card.size = Vector2(TOAST_W, h)

## Legacy entry point (text + color). Splits "title\nbody" and picks a kind from
## the colour it was handed, so old callers still land in the new lane.
func _show_notification(text: String, color: Color) -> void:
	var parts := text.split("\n", false)
	var title := parts[0] if parts.size() > 0 else text
	var body := parts[1] if parts.size() > 1 else ""
	push_toast("info", title, body, "", 0, "", color)

# ---------------------------------------------------------------- notifiers --
func _on_cycle_warning(seconds_left: int) -> void:
	push_toast("alert", "TOKEN RESET IN %ds" % seconds_left,
		"Ship something. Anything counts. Probably.", "", 0, "", Color.TRANSPARENT, true)

func _on_reset_triggered(cycle: int) -> void:
	push_toast("info", "RESET · Cycle %d" % cycle,
		"Quotas refilled. Prices moved. Guess which way.", "", 0, "",
		_GameTheme.BLUE, true)

func _on_model_changed(_id: String, display_name: String) -> void:
	push_toast("purchase", "Model → %s" % display_name,
		"Every blast now costs what it costs.", "model", 0, "", ModelManager.color())

func _on_agent_deployed(display_name: String) -> void:
	push_toast("info", "%s deployed" % display_name,
		"Resolves at the next reset. Confidence: 100%.")

func _on_agent_resolved(display_name: String, summary: String) -> void:
	push_toast("info", "%s reported back" % display_name, summary)

func _on_arch_consequence(text: String) -> void:
	push_toast("debt", "Architecture decision matured", text)

## The running gags EventManager keeps track of between cycles. They were being
## emitted into the void; without a surface the subscription bill, the ominous
## quiet and the "someone will bring this up later" beat were invisible.
## Amber alert lane, top-right rail — deliberately not the top-centre readout.
const GAG_TITLES := {
	"subscription": "Subscription renewed",
	"calm": "Nothing is happening",
	"scheduled": "Filed for later",
	"callback": "Somebody remembers",
}

func _on_running_gag(gag_id: String, note: String) -> void:
	var title: String = GAG_TITLES.get(gag_id, "Noted")
	push_toast("alert", title, note, "gag_%s" % gag_id)

func _on_tokens_gained(amount: int, _source: String) -> void:
	push_toast("token", "+%d Tokens" % amount, "", "tokens", amount, "+%d Tokens")

func _on_price_adjustment(lost: int) -> void:
	push_toast("debt", "−%d Tokens" % lost, "Provider pricing was 'updated'.")

func _on_quest_completed(quest_id: String, _rewards: Dictionary) -> void:
	var info := QuestManager.get_quest_info(quest_id)
	push_toast("quest", "Quest Complete",
		_quest_headline(quest_id, str(info.get("name", quest_id))))
	if is_instance_valid(_quest_flash):
		if _quest_flash_tween and _quest_flash_tween.is_valid():
			_quest_flash_tween.kill()
		_quest_flash.color = _GameTheme.with_alpha(_GameTheme.GOLD, 0.22)
		_quest_flash_tween = _tw().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_quest_flash_tween.tween_property(_quest_flash, "color:a", 0.0, 0.55)

func _on_achievement(_id: String, name_text: String, desc: String) -> void:
	push_toast("achievement", name_text, desc)

## The ability bar lives in the same bottom-center band as the dialogue panel
## and bleeds through its glass background. During a conversation the abilities
## are not usable (player.gd gates them on DialogueManager.is_active), so the
## bar goes away entirely and returns the moment the conversation ends.
## The hint strip lives in the same band and is equally useless mid-conversation
## (the dialogue panel prints its own key hints), so it leaves with the bar.
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
## Slot geometry. The bar keeps its documented band y -100..-42 to the pixel —
## the boss status frame reserves the space above it and the hint strip owns
## -34..-12, so widening the slots is a HORIZONTAL change only. 6 x 118 + 5 x 8
## separation = 748px inside a 780px lane.
const SLOT_SIZE := Vector2(118, 58)
const ABILITY_BAR_TOP := -100.0
const ABILITY_BAR_BOTTOM := -42.0

func _setup_ability_bar() -> void:
	var bar := HBoxContainer.new()
	bar.name = "AbilityBar"
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_constant_override("separation", 8)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = -390
	bar.offset_top = ABILITY_BAR_TOP
	bar.offset_right = 390
	bar.offset_bottom = ABILITY_BAR_BOTTOM
	add_child(bar)
	_ability_bar = bar
	_ability_prev_frac.resize(ABILITY_DEFS.size())
	_ability_state.resize(ABILITY_DEFS.size())
	_ability_shown_cost.resize(ABILITY_DEFS.size())
	for i in ABILITY_DEFS.size():
		# -1 is "nothing painted yet", so the first _update_ability_bar always
		# writes a full state instead of trusting a zero-initialised array.
		_ability_state[i] = -1
		_ability_shown_cost[i] = -1
	for def in ABILITY_DEFS:
		var accent: Color = ABILITY_ACCENTS.get(def.id, _GameTheme.CYAN)
		# Plain Control slot so the cooldown overlay, the recharge rail and the
		# affordability wash can each use their own anchors without a container
		# fighting them every layout pass.
		var slot := Control.new()
		slot.custom_minimum_size = SLOT_SIZE
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var sb := StyleBoxFlat.new()
		sb.bg_color = _GameTheme.with_alpha(_GameTheme.BASE, 0.90)
		sb.set_border_width_all(1)
		sb.border_color = _GameTheme.with_alpha(accent, 0.55)
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 8.0
		sb.content_margin_right = 8.0
		sb.content_margin_top = 4.0
		sb.content_margin_bottom = 6.0
		sb.shadow_color = _GameTheme.with_alpha(accent.lerp(_GameTheme.VOID, 0.6), 0.5)
		sb.shadow_size = 7
		panel.add_theme_stylebox_override("panel", sb)
		slot.add_child(panel)
		var v := VBoxContainer.new()
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_theme_constant_override("separation", 2)
		panel.add_child(v)
		# Top line: the KEY you press (loud, accent) and what it costs (quiet,
		# right-aligned). Round 4 ran both through one label at one weight, so the
		# thing you actually need — which key — had no more presence than a price.
		var top := HBoxContainer.new()
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_theme_constant_override("separation", 4)
		v.add_child(top)
		var key := Label.new()
		key.text = def.key
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		key.custom_minimum_size = Vector2(19, 0)
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key.add_theme_font_size_override("font_size", 13)
		key.add_theme_font_override("font", _GameTheme.spaced_font(1))
		key.add_theme_color_override("font_color", _GameTheme.WHITE_HOT)
		key.add_theme_stylebox_override("normal", _GameTheme.chip_box(accent))
		_GameTheme.outline_text(key, 3)
		top.add_child(key)
		var cost := Label.new()
		cost.text = def.cost
		cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cost.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cost.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cost.add_theme_font_size_override("font_size", 12)
		cost.add_theme_color_override("font_color", _GameTheme.hot_of(accent))
		_GameTheme.outline_text(cost, 3)
		top.add_child(cost)
		var nm := Label.new()
		nm.text = def.name
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		nm.add_theme_font_size_override("font_size", 14)
		nm.add_theme_color_override("font_color", _GameTheme.TEXT)
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_GameTheme.outline_text(nm, 3)
		v.add_child(nm)
		# Cooldown: dark shutter over the top, receding upward as it recharges,
		# with a bright sweep line riding its lower edge.
		var ov := ColorRect.new()
		ov.color = Color(0.02, 0.024, 0.055, 0.72)
		ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ov.anchor_left = 0.0
		ov.anchor_right = 1.0
		ov.anchor_top = 0.0
		ov.anchor_bottom = 1.0
		ov.visible = false
		slot.add_child(ov)
		var sweep := ColorRect.new()
		sweep.color = _GameTheme.hot_of(accent)
		sweep.material = _GameTheme.additive_material()
		sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sweep.anchor_left = 0.0
		sweep.anchor_right = 1.0
		sweep.anchor_top = 1.0
		sweep.anchor_bottom = 1.0
		sweep.offset_top = -2.0
		ov.add_child(sweep)
		# The recharge rail: a 3px accent bar along the bottom edge that is FULL
		# when the ability is ready and grows back from nothing while it recharges.
		# The shutter says "not yet"; the rail says "how much longer" without
		# making you estimate the height of a rectangle.
		var rail := ColorRect.new()
		rail.color = _GameTheme.hot_of(accent)
		rail.material = _GameTheme.additive_material()
		rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rail.anchor_left = 0.0
		rail.anchor_right = 1.0
		rail.anchor_top = 1.0
		rail.anchor_bottom = 1.0
		rail.offset_left = 3.0
		rail.offset_right = -3.0
		rail.offset_top = -4.0
		rail.offset_bottom = -1.0
		slot.add_child(rail)
		# Cannot afford: a red wash over the whole slot. Dimming alone reads as
		# "on cooldown"; the colour is what makes "you are broke" a different
		# sentence from "wait a second".
		var deny := ColorRect.new()
		deny.color = _GameTheme.with_alpha(_GameTheme.RED, 0.0)
		deny.mouse_filter = Control.MOUSE_FILTER_IGNORE
		deny.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		# Inset by the panel's corner radius so a square wash never pokes out of
		# the rounded slot as four red pixels.
		deny.offset_left = 2.0
		deny.offset_top = 2.0
		deny.offset_right = -2.0
		deny.offset_bottom = -2.0
		slot.add_child(deny)
		# Fires white when the ability is spent, accent when it comes back.
		var flash := ColorRect.new()
		flash.color = _GameTheme.with_alpha(accent, 0.0)
		flash.material = _GameTheme.additive_material()
		flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		slot.add_child(flash)
		bar.add_child(slot)
		_ability_slots.append(slot)
		_ability_panels.append(panel)
		_ability_overlays.append(ov)
		_ability_flashes.append(flash)
		_ability_boxes.append(sb)
		_ability_cost_labels.append(cost)
		_ability_rails.append(rail)
		_ability_denies.append(deny)

func _update_ability_bar() -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if not is_instance_valid(_player):
			return
	for i in _ability_slots.size():
		var def: Dictionary = ABILITY_DEFS[i]
		var accent: Color = ABILITY_ACCENTS.get(def.id, _GameTheme.CYAN)
		var ready_now: bool = _player.ability_ready(def.id)
		var cost_amt := _ability_cost(def)
		var affordable: bool = str(def.res) == "" \
			or ResourceManager.get_value(str(def.res)) >= float(cost_amt)
		var live: bool = ready_now and affordable
		# 0 live · 1 recharging · 2 cannot afford. Explicitly typed rather than
		# inferred: a nested conditional expression is exactly the shape where
		# leaning on `:=` costs more than it saves.
		var state: int = 0 if live else (1 if affordable else 2)
		var panel: PanelContainer = _ability_panels[i]
		var cost_label: Label = _ability_cost_labels[i]
		if state != _ability_state[i] or cost_amt != _ability_shown_cost[i]:
			_ability_state[i] = state
			_ability_shown_cost[i] = cost_amt
			# Three distinguishable states, not two: LIVE (full), RECHARGING (dim
			# but clearly the same slot), BROKE (dimmest, and washed red below).
			panel.modulate = Color(1, 1, 1, 1.0) if live else \
				(Color(1, 1, 1, 0.62) if affordable else Color(1, 1, 1, 0.44))
			var box: StyleBoxFlat = _ability_boxes[i]
			# Unaffordable reads RED on the cost line and drops the border to a
			# whisper; ready-and-affordable gets its accent edge back.
			if affordable:
				box.border_color = _GameTheme.with_alpha(accent, 0.85 if live else 0.4)
				cost_label.add_theme_color_override("font_color", _GameTheme.hot_of(accent))
			else:
				box.border_color = _GameTheme.with_alpha(_GameTheme.RED, 0.7)
				cost_label.add_theme_color_override("font_color", _GameTheme.RED)
			cost_label.text = _cost_text(def, cost_amt)
			var deny: ColorRect = _ability_denies[i]
			deny.color = _GameTheme.with_alpha(_GameTheme.RED, 0.0 if affordable else 0.12)
		var frac := _cooldown_frac(def.id)
		var prev: float = _ability_prev_frac[i]
		var ov: ColorRect = _ability_overlays[i]
		ov.anchor_top = 0.0
		ov.anchor_bottom = frac
		ov.visible = frac > 0.004
		# Recharge rail: full width when ready, growing back from zero on cooldown.
		var rail: ColorRect = _ability_rails[i]
		rail.anchor_right = 1.0 - frac
		rail.color = _GameTheme.with_alpha(
			_GameTheme.hot_of(accent) if affordable else _GameTheme.RED,
			0.95 if live else 0.55)
		if frac > prev + 0.2:
			_flash_slot(i, _GameTheme.WHITE_HOT, 0.45)
		elif prev > 0.02 and frac <= 0.004:
			_flash_slot(i, accent, 0.40)
		_ability_prev_frac[i] = frac

## The price the player will actually be charged this second. Only Prompt Blast
## moves — its cost scales with the active model, which is the whole point of the
## [T] model swap — so everything else falls straight through to its static `amt`.
func _ability_cost(def: Dictionary) -> int:
	if str(def.id) == "prompt_blast" and is_instance_valid(_player) \
			and _player.has_method("prompt_cost"):
		return int(_player.prompt_cost())
	return int(def.amt)

## The cost line for a slot. Static entries keep their authored string (including
## Dash's "free"); the one dynamic price is reprinted from the live number.
func _cost_text(def: Dictionary, amount: int) -> String:
	if str(def.id) == "prompt_blast":
		return "%d tk" % amount
	return str(def.cost)

func _flash_slot(i: int, col: Color, alpha: float) -> void:
	var flash: ColorRect = _ability_flashes[i]
	if not is_instance_valid(flash):
		return
	flash.color = _GameTheme.with_alpha(col, alpha)
	var old: Variant = flash.get_meta("tw") if flash.has_meta("tw") else null
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	var t := _tw().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(flash, "color:a", 0.0, 0.30)
	flash.set_meta("tw", t)

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

# ------------------------------------------------------------------ minimap --
func _build_minimap() -> void:
	_minimap = Minimap.new()
	_minimap.name = "Minimap"
	_minimap.anchor_left = 1.0
	_minimap.anchor_top = 1.0
	_minimap.anchor_right = 1.0
	_minimap.anchor_bottom = 1.0
	_minimap.offset_left = -220.0
	_minimap.offset_top = -220.0
	_minimap.offset_right = -24.0
	_minimap.offset_bottom = -24.0
	add_child(_minimap)
	if _minimap.has_method("bind_waypoint"):
		_minimap.call("bind_waypoint", _waypoint)

# ------------------------------------------------------------------ process --
func _process(delta: float) -> void:
	_quest_ui_accum += delta
	if _quest_ui_accum >= QUEST_UI_INTERVAL:
		_quest_ui_accum = 0.0
		_update_quest_tracker()
	_update_ability_bar()
	_tick_counters(delta)
	_tick_vitals(delta)
	_tick_toasts(delta)
	_tick_status(delta)

## Resource counters roll toward their target instead of snapping, and glow while
## they are moving. Costs nothing when nothing changed: the loop exits on the
## first comparison for every resource that is already settled.
func _tick_counters(delta: float) -> void:
	for k: String in COUNT_KEYS:
		var target: float = _count_target.get(k, 0.0)
		var shown: float = _count_shown.get(k, target)
		if absf(target - shown) < 0.01:
			var heat: float = _count_hot.get(k, 0.0)
			if heat > 0.0:
				heat = maxf(0.0, heat - delta * 2.6)
				_count_hot[k] = heat
				_paint_counter(k, shown, heat)
			continue
		# Proportional with a floor, so +3 still visibly ticks and +900 doesn't
		# take a week. Never overshoots: move_toward clamps at the target.
		var step := maxf(absf(target - shown) * 7.0, 24.0) * delta
		shown = move_toward(shown, target, step)
		_count_shown[k] = shown
		_count_hot[k] = 1.0
		_paint_counter(k, shown, 1.0)

func _counter_label(k: String) -> Label:
	match k:
		"tokens":
			return token_label
		"compute":
			return compute_label
		"context":
			return context_label
	return null

func _paint_counter(k: String, shown: float, heat: float) -> void:
	var l := _counter_label(k)
	if l == null:
		return
	l.text = "%d" % int(round(shown))
	# Overbright while rolling — HDR bloom turns a changing number into a small
	# light source, which is exactly how much attention a pickup deserves. Applied
	# to the font colour rather than `modulate` so the delta chip parented to this
	# label keeps its own gain-green / spend-red (see _count_base_col).
	var base: Color = _count_base_col.get(k, _GameTheme.WHITE_HOT)
	var lift := 1.0 + 0.9 * clampf(heat, 0.0, 1.0)
	l.add_theme_color_override("font_color",
		Color(base.r * lift, base.g * lift, base.b * lift, base.a))

## Low health is a STATE, not an event: the vitals panel breathes red, the value
## goes hot, and the danger vignette (driven in _tick_status) closes in. Above
## the threshold every one of these snaps back to neutral in a single write.
var _low_hp_active := false

func _tick_vitals(_delta: float) -> void:
	if _bars_box == null or hp_bar.max_value <= 0.0:
		return
	var frac := clampf(hp_bar.value / hp_bar.max_value, 0.0, 1.0)
	var low := frac < LOW_HP_FRAC and GameManager.state == GameManager.GameState.PLAYING
	if low:
		_low_hp_active = true
		var p := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.011)
		var urgency := 1.0 - frac / LOW_HP_FRAC
		_bars_box.border_color = _GameTheme.with_alpha(_GameTheme.RED, 0.45 + 0.5 * p * urgency)
		_bars_box.shadow_color = _GameTheme.with_alpha(_GameTheme.RED, 0.20 + 0.30 * p * urgency)
		hp_value.add_theme_color_override("font_color",
			_GameTheme.WHITE_HOT.lerp(_GameTheme.RED, 0.35 + 0.45 * p))
	elif _low_hp_active:
		_low_hp_active = false
		_bars_box.border_color = _GameTheme.with_alpha(_GameTheme.LINE, 0.95)
		_bars_box.shadow_color = _GameTheme.with_alpha(
			_GameTheme.RED.lerp(_GameTheme.VOID, 0.70), 0.55)
		hp_value.add_theme_color_override("font_color", _GameTheme.WHITE_HOT)

## Strings are only rebuilt when the value they show actually changed — the old
## version allocated three Strings every frame for a countdown that ticks once
## per second.
func _tick_status(_delta: float) -> void:
	var secs := CycleManager.seconds_left()
	var warn := secs <= int(CycleManager.WARN_AT)
	if _cycle_label:
		if secs != _cycle_shown or CycleManager.cycle != _cycle_num:
			_cycle_shown = secs
			_cycle_num = CycleManager.cycle
			_cycle_label.text = "◉ Cycle %d    ⏱ reset in %ds" % [CycleManager.cycle, secs]
		if warn:
			# Amber panic pulse — the deadline is a physical presence now.
			var p := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
			_cycle_label.add_theme_color_override("font_color",
				_GameTheme.AMBER.lerp(_GameTheme.WHITE_HOT, p * 0.6))
			_cycle_calm = false
		elif not _cycle_calm:
			# Written once on the way out of the warning, not sixty times a second
			# for a colour that is not moving. A theme override is not a cheap
			# assignment: it re-dirties the minimum size of every ancestor.
			_cycle_calm = true
			_cycle_label.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	if _model_label:
		var m := ModelManager.current()
		var pc: int = _player.prompt_cost() if is_instance_valid(_player) else int(m.cost * 5)
		var sig := "%s|%d" % [str(m.name), pc]
		if sig != _model_sig:
			_model_sig = sig
			_model_label.text = "⚙ %s  ·  [T] to swap  ·  %d tk/blast" % [m.name, pc]
			_model_label.add_theme_color_override("font_color", ModelManager.color())
	# Reset-clock vignette: amber creep in the last WARN_AT seconds.
	if _alert_vig:
		var urgency := 0.0
		if warn and GameManager.state == GameManager.GameState.PLAYING:
			urgency = clampf(1.0 - float(secs) / maxf(CycleManager.WARN_AT, 1.0), 0.0, 1.0)
			urgency *= 0.30 + 0.16 * sin(Time.get_ticks_msec() * 0.009)
		_alert_vig.modulate.a = urgency
	# Danger vignette: red creep below a third HP.
	if _danger_vig:
		var frac := 1.0
		if hp_bar.max_value > 0.0:
			frac = clampf(hp_bar.value / hp_bar.max_value, 0.0, 1.0)
		var d := 0.0
		if frac < LOW_HP_FRAC and GameManager.state == GameManager.GameState.PLAYING:
			d = (1.0 - frac / LOW_HP_FRAC) * (0.34 + 0.14 * sin(Time.get_ticks_msec() * 0.011))
		_danger_vig.modulate.a = d

func _update_all() -> void:
	for k: String in COUNT_KEYS:
		var v := float(int(ResourceManager.get_value(k)))
		_count_target[k] = v
		if not _count_shown.has(k):
			# First read of the run: no roll, just the truth.
			_count_shown[k] = v
			_count_hot[k] = 0.0
			_paint_counter(k, v, 0.0)
	var tax := int(round((DreamAppManager.debt_cost_multiplier() - 1.0) * 100.0))
	debt_label.text = "+%d%%" % tax
	debt_label.add_theme_color_override("font_color",
		_GameTheme.TEXT_DIM.lerp(_GameTheme.RED, clampf(float(tax) / 40.0, 0.0, 1.0)))
	var target := ResourceManager.get_value("focus")
	focus_value.text = "%d/%d" % [int(target), int(focus_bar.max_value)]
	if absf(focus_bar.value - target) > 0.5:
		if _focus_tween and _focus_tween.is_valid():
			_focus_tween.kill()
		_focus_tween = _tw().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_focus_tween.tween_property(focus_bar, "value", target, _GameTheme.T_STD)
	else:
		focus_bar.value = target
	_update_quest_tracker()

func _on_resource_changed(res_name: String, old_v: float, new_v: float) -> void:
	match res_name:
		"tokens", "compute", "context":
			_flash_resource(res_name, old_v, new_v)
			_update_all()
		"technical_debt":
			_flash_resource(res_name, old_v, new_v)
			_update_all()
		"focus":
			if new_v < old_v:
				_bar_ghost(focus_bar, _focus_ghost, old_v, new_v, false)
			_update_all()

## The tick: green chip and a green flash on a gain, red on a spend. The number
## itself pops so a pickup registers in the corner of your eye.
func _flash_resource(res_name: String, old_v: float, new_v: float) -> void:
	var delta := new_v - old_v
	if absf(delta) < 0.5:
		return
	var chip: Label = _res_chips.get(res_name, null)
	if not is_instance_valid(chip):
		return
	# Debt is the one resource where "more" is the bad news.
	var good := delta > 0.0
	if res_name == "technical_debt":
		good = delta < 0.0
	var col: Color = _GameTheme.ACID if good else _GameTheme.RED
	chip.text = ("+%d" % int(delta)) if delta > 0.0 else ("−%d" % int(absf(delta)))
	chip.add_theme_color_override("font_color", col)
	chip.modulate = Color(col.r * 1.6, col.g * 1.6, col.b * 1.6, 1.0)
	chip.position.y = -2.0
	# The counter itself reacts too: a pop on a gain, a shorter dip-free punch on
	# a spend, so the tick is visible even if the chip is off the edge of vision.
	var host := _counter_label(res_name)
	if host != null:
		_GameTheme.punch(host, 1.20 if good else 1.10, 0.24)
	var old = _res_chip_tweens.get(res_name, null)
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	var t := _tw().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(chip, "position:y", -20.0, 0.75)
	t.tween_property(chip, "modulate:a", 0.0, 0.75)
	_res_chip_tweens[res_name] = t

func _on_health_changed(current: int, max_hp: int) -> void:
	hp_bar.max_value = max_hp
	hp_value.text = "%d/%d" % [current, max_hp]
	var target := float(current)
	var prev := _hp_prev if _hp_prev >= 0.0 else target
	_hp_prev = target
	if _hp_tween and _hp_tween.is_valid():
		_hp_tween.kill()
	_hp_tween = _tw().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_hp_tween.tween_property(hp_bar, "value", target, _GameTheme.T_STD)
	if target < prev:
		_bar_ghost(hp_bar, _hp_ghost, prev, target, true)
		_feel_damage((prev - target) / maxf(1.0, float(max_hp)))
	elif target > prev:
		# Healing gets its own note, quieter and green — otherwise a coffee and a
		# Dependency Demon feel identical from the corner of your eye.
		_GameTheme.flash_over($TopBar/HBox/BarsPanel, _GameTheme.ACID, 0.22, 0.35)

## Damage is a fact you must feel before you read it: a red rim slam scaled to
## how much of your health just left, a punch on the vitals group, and a white
## wash across the bar itself. All three decay inside 0.4s so a hit never leaves
## the HUD tinted.
func _feel_damage(frac_lost: float) -> void:
	var bite := clampf(frac_lost * 3.4, 0.18, 1.0)
	if is_instance_valid(_hit_vig):
		if _hit_tween and _hit_tween.is_valid():
			_hit_tween.kill()
		_hit_vig.modulate.a = 0.22 + 0.55 * bite
		_hit_tween = _tw().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_hit_tween.tween_property(_hit_vig, "modulate:a", 0.0, 0.34 + 0.20 * bite)
	if is_instance_valid(_bars_group):
		_GameTheme.punch(_bars_group, 1.0 + 0.05 * bite, 0.26)
	_GameTheme.flash_over($TopBar/HBox/BarsPanel, _GameTheme.WHITE_HOT, 0.10 + 0.22 * bite, 0.26)

## Trailing segment marking what a bar just lost, which then burns away.
func _bar_ghost(bar: ProgressBar, ghost: ColorRect, from_v: float, to_v: float, is_hp: bool) -> void:
	if not is_instance_valid(ghost):
		return
	var denom := maxf(1.0, float(bar.max_value))
	var lo := clampf(to_v / denom, 0.0, 1.0)
	var hi := clampf(from_v / denom, 0.0, 1.0)
	if hi - lo < 0.004:
		return
	var tw: Tween = _hp_ghost_tween if is_hp else _focus_ghost_tween
	if tw and tw.is_valid():
		tw.kill()
	ghost.visible = true
	ghost.anchor_left = lo
	ghost.anchor_right = hi
	tw = _tw().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_interval(0.18)
	tw.tween_property(ghost, "anchor_right", lo, 0.32)
	tw.tween_callback(func() -> void: ghost.visible = false)
	if is_hp:
		_hp_ghost_tween = tw
	else:
		_focus_ghost_tween = tw

## Display names for every region id. The banner used to title-case the raw id,
## which printed "Gpu Mines", "Api Bazaar" and "Stackoverflow Ruins" as the
## largest text on screen — in a game about developer culture, on the one label
## a judge screenshots. Acronyms are not a styling decision, they are spelling,
## so they are authored. Mirrors quest_log.gd's REGION_NAMES deliberately: the
## two surfaces must never disagree about what a place is called.
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

## Region accents (VISUAL_BIBLE per-region table) — the banner rule and the
## objective panel pick up the local neon so each region feels like its own set.
const REGION_ACCENTS := {
	"localhost": _GameTheme.AMBER,
	"dependency_district": _GameTheme.ACID,
	"stackoverflow_ruins": Color("#E8C46B"),
	"api_bazaar": _GameTheme.MAGENTA,
	"cloud_district": Color("#6BC7FF"),
	"open_source_wildlands": Color("#58E07C"),
	"corporate_enterprise": Color("#4D7CFF"),
	"gpu_mines": Color("#FF6B2D"),
	"production": _GameTheme.RED,
	"token_vault": _GameTheme.GOLD,
}

func _on_region_changed(region_id: String) -> void:
	region_label.text = _format_region(region_id)
	region_sub.text = REGION_SUBTITLES.get(region_id, "Region under construction")
	var accent: Color = REGION_ACCENTS.get(region_id, _GameTheme.CYAN)
	region_rule.color = _GameTheme.with_alpha(accent, 0.75)
	region_label.add_theme_color_override("font_color", _GameTheme.TEXT)
	# The objective panel's rail picks up the local neon, so the HUD belongs to
	# the room you are standing in. Only the RAIL — the instruction inside it
	# stays CYAN_HOT everywhere, because "where do I go" must never change colour
	# on you just because the wallpaper did.
	if _quest_box != null:
		_quest_box.border_color = _GameTheme.with_alpha(accent, 0.55)
		_quest_box.shadow_color = _GameTheme.with_alpha(
			accent.lerp(_GameTheme.VOID, 0.70), 0.55)
	# Arrival sting: the name flashes overbright, the rule wipes out from centre.
	var t := _tw().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(region_label, "modulate", Color(1.7, 1.9, 1.9, 1.0), _GameTheme.T_MICRO)
	t.tween_property(region_label, "modulate", Color.WHITE, 0.5)
	region_rule.pivot_offset = region_rule.size * 0.5
	region_rule.scale = Vector2(0.02, 1.0)
	var t2 := _tw().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t2.tween_property(region_rule, "scale", Vector2.ONE, _GameTheme.T_DRAMA)

## Region id -> the name a human wrote. Falls back to the old title-casing only
## for an id nobody has authored yet, so a new region still prints something
## rather than nothing.
func _format_region(id: String) -> String:
	return str(REGION_TITLES.get(id, id.replace("_", " ").capitalize()))

## The pause button used to be anchored at (view.x-52, 46) — which put it right
## on top of the vitals panel, drawing its glyph through the HP bar in every
## single frame of the QA capture. It now lives IN the top bar's row, past the
## vitals, where it cannot collide with anything by construction.
func _setup_pause_button() -> void:
	var b := Button.new()
	b.name = "PauseButton"
	b.text = "‖"  # pause glyph
	b.custom_minimum_size = Vector2(38, 34)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.tooltip_text = "Pause (Esc)"
	b.focus_mode = Control.FOCUS_NONE
	_GameTheme.style_button(b, _GameTheme.CYAN, 14)
	b.add_theme_constant_override("outline_size", 0)
	b.pressed.connect(_on_pause_button)
	# A MOUSE_FILTER_IGNORE parent does not stop its children being hit-tested,
	# so the button still takes clicks inside the pass-through top bar.
	$TopBar/HBox.add_child(b)

func _on_pause_button() -> void:
	var w := get_parent()
	if w and w.has_method("_open_pause") and GameManager.state == GameManager.GameState.PLAYING:
		w._open_pause()
	# (No banner refresh here. A stray _on_region_changed() used to ride along,
	# which re-fired the region ARRIVAL sting — name flash plus rule wipe —
	# every time you clicked pause, in a region you had not just arrived in.)

## Dry consolation when the quest system has genuinely run dry. Picked once per
## session so the panel doesn't flicker through the whole bit every 0.2s.
const NO_QUEST_JOKES := [
	"Nothing tracked. Either you've won, or the backlog achieved self-awareness and quit.",
	"Nothing tracked. The quest system is 'between priorities', like everyone else here.",
	"Nothing tracked. Enjoy it; someone is definitely writing a ticket about this.",
	"Nothing tracked. This is the calmest thing that will happen to you today.",
]
var _no_quest_joke := ""

## Headline names for quests whose authored name is pure punchline.
##
## quests.json stays the source of truth for ids and prose — nothing here
## renames anything — but "TODO: Everything" as the NAME OF THE THING YOU ARE
## DOING, printed in the objective panel and in the completion toast, tells a
## first-time player exactly nothing. That is the one place COMEDY_BIBLE's hard
## rule bites: the joke rides alongside the information, never instead of it.
## The pattern is the bible's own "Real Name — quip": the informative half
## leads, the gag keeps its seat.
const QUEST_HEADLINE_NAMES := {
	"hello_localhost": "First Sprint — TODO: Everything",
}

## The name to print in a headline slot (objective panel, completion toast).
func _quest_headline(qid: String, authored: String) -> String:
	var over := str(QUEST_HEADLINE_NAMES.get(qid, ""))
	return over if over != "" else authored

## The one line that fixes "I don't know what to do": a concrete NEXT ACTION,
## plus how far and which way. Everything else on the panel is supporting cast.
func _update_quest_tracker(_qid: String = "") -> void:
	var obj := QuestManager.get_current_objective()
	if obj.is_empty():
		_set_next_action("→ Ship the Dream App. Somehow.")
		quest_name_label.text = "No active quest"
		if _no_quest_joke == "":
			_no_quest_joke = NO_QUEST_JOKES[randi() % NO_QUEST_JOKES.size()]
		quest_tracker.text = "%s\n  • [B] Dream App — spend tokens, meet the ship requirements\n  • Or take the portal and go disappoint someone new.\n  • Lost? Press [H]." % _no_quest_joke
		return
	var qid := str(obj.get("quest_id", ""))
	var info := QuestManager.get_quest_info(qid)
	var action := str(obj.get("action", obj.get("text", "")))
	# If the objective is in another region, the honest instruction is "get there
	# first" — the waypoint is already pointing at the door. ("region" objectives
	# already say "Travel to X"; prefixing those just stutters.)
	var region := str(obj.get("region", ""))
	if region != "" and region != GameManager.current_region \
			and str(obj.get("kind", "")) != "region":
		action = "Head to %s — %s" % [_format_region(region), action]
	var where := _where_suffix()
	_set_next_action("→ %s%s" % [action, where])
	quest_name_label.text = _quest_headline(qid, str(obj.get("quest_name", info.get("name", qid))))
	var text := ""
	for o in info.get("objectives", []):
		if not (o is Dictionary) or not o.has("id"):
			continue
		var prog: int = info.progress.get(o.id, 0)
		var target: int = o.get("count", 1)
		var done: bool = prog >= target
		var mark := "✓" if done else ("▸" if o.id == obj.get("objective_id", "") else "•")
		if text != "":
			text += "\n"
		text += "  %s [%d/%d] %s" % [mark, prog, target, o.get("text", o.id)]
	quest_tracker.text = text

## "  (28m · NE)" when the waypoint has a fix on something, "" otherwise.
func _where_suffix() -> String:
	if not is_instance_valid(_waypoint) or not _waypoint.has_method("readout"):
		return ""
	if not _waypoint.has_target() or _waypoint.is_fallback():
		return ""
	var r: String = _waypoint.readout()
	if r == "":
		return ""
	return "  (%s)" % r

## Swap the headline. Flashes whenever the instruction changes (including its
## counter), but only announces a genuinely NEW instruction — otherwise picking
## up ten tokens fires ten notifications on top of the ten pickup toasts.
func _set_next_action(text: String) -> void:
	if next_action.text == text:
		return
	next_action.text = text
	# Ignore pure distance drift: only the instruction itself is newsworthy.
	var core := text.split("  (")[0]
	if core == _last_action:
		return
	var first := _last_action == ""
	var shape := _action_shape(core)
	var new_shape := shape != _last_action_shape
	_last_action = core
	_last_action_shape = shape
	if _action_tween and _action_tween.is_valid():
		_action_tween.kill()
	_action_tween = _tw().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_action_tween.tween_property(next_action, "modulate", Color(2.0, 2.4, 2.3, 1.0), _GameTheme.T_MICRO)
	_action_tween.tween_property(next_action, "modulate", Color.WHITE, _GameTheme.T_STD)
	# Don't stomp a toast that's mid-flight (a pickup, a quest completion, a
	# reset warning); those outrank "here's your next chore".
	if not first and new_shape and _toast_phase == 0 and _toast_queue.is_empty():
		push_toast("objective", "NEXT: %s" % core.trim_prefix("→ "))

## The instruction minus its counters: "Collect 7 more tokens" and "Collect 6
## more tokens" are the same job, so they shouldn't re-announce themselves.
func _action_shape(s: String) -> String:
	var out := ""
	for i in s.length():
		var c := s[i]
		if c < "0" or c > "9":
			out += c
	return out

# ------------------------------------------------------------- intro hint ----
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
	_hint_label(vb, "NEVER WONDER WHERE TO GO", 18, _GameTheme.CYAN, true)
	_hint_label(vb, "The cyan arrow always points at your current objective — it pins to the screen edge with a distance when the target is off-screen.\nThe radar bottom-right shows portals, people and things that bite. The panel bottom-left says the same thing in words.", 15, _GameTheme.TEXT)
	_hint_label(vb, "CONTROLS", 18, _GameTheme.AMBER, true)
	# Dash is bound to BOTH Shift and Q (project.godot input map). The ability bar
	# prints the slot as [Q], so teaching only "Shift" here left a key on screen
	# that the onboarding never mentioned.
	_hint_label(vb, "WASD / Arrows  —  Move\nE  —  Interact / Talk (walk up to props & Claude)\n1  —  Prompt Blast (attack)      Shift or Q  —  Dash (escape)\n2-5  —  Abilities (Cache, Rubber Duck, Stack Trace, Ctrl+Z undo)\nB  —  Dream App      M  —  Map      J  —  Quests      Esc  —  Pause\nH  —  WHAT AM I DOING?  (open any time, tells you where to go)", 15, _GameTheme.TEXT)
	_hint_label(vb, "First up: follow the arrow to Claude, then grab some tokens.\nEstimated time: five minutes. Realistically: a weekend.\n\n[E] / click to begin", 14, _GameTheme.TEXT_DIM)
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

# -------------------------------------------------------------- bar track ----
## The frame that turns a filled rectangle back into a gauge. Added as a child
## of the ProgressBar it belongs to, so it draws on top of the fill.
class BarTrack extends Control:
	var tint: Color = GameTheme.LINE

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if size.x <= 6.0 or size.y <= 4.0:
			return
		# Dark seat on the outermost pixel, the tube's own hairline on the next one
		# in: two value steps, so the outline survives both an empty track (VOID
		# bg) and a full one (WHITE_HOT-topped fill).
		#
		# Both rects are inset by half a pixel and drawn 1px wide, which is not
		# fussiness: `draw_rect(..., filled=false, width)` centres its outline ON
		# the rect's edge, so a 2px outline on Rect2(ZERO, size) spent half its
		# width OUTSIDE the bar and put the rest on a half-pixel boundary — a
		# 1px feature smeared across two columns at half strength, in a pixel-art
		# game, on the readout this whole class exists to make legible.
		draw_rect(Rect2(Vector2(0.5, 0.5), size - Vector2(1.0, 1.0)),
			GameTheme.with_alpha(GameTheme.VOID, 0.9), false, 1.0)
		draw_rect(Rect2(Vector2(1.5, 1.5), size - Vector2(3.0, 3.0)),
			GameTheme.with_alpha(tint, 0.8), false, 1.0)
		# Quarter ticks. A full bar still reads as a scale, and a player can call
		# "about a third left" without doing arithmetic on the numbers beside it.
		#
		# LINE, not VOID: a VOID tick reads beautifully on a full bar and vanishes
		# completely on an empty one, because the empty track IS VOID — so the
		# graduations disappeared exactly when "how much is left" got urgent.
		# LINE is dark against the fill and light against the empty track, so the
		# scale is there at every level.
		for i: int in [1, 2, 3]:
			var x := roundf(size.x * float(i) * 0.25) + 0.5
			var a: float = 0.9 if i == 2 else 0.6
			draw_line(Vector2(x, 1.0), Vector2(x, size.y - 1.0),
				GameTheme.with_alpha(GameTheme.LINE, a), 1.0)

# ---------------------------------------------------------------- minimap ----
## Compact bottom-right radar. Everything is drawn with primitives in _draw()
## (no node pool, no per-frame allocation); the only allocating call is the group
## scan, throttled to ~2/sec — the same budget the waypoint already spends.
class Minimap extends Control:
	const RANGE_PX := 1000.0
	const SCAN_INTERVAL := 0.45
	const DRAW_INTERVAL := 0.033
	const MAX_BLIPS := 96

	const K_PORTAL := 0
	const K_NPC := 1
	const K_ENEMY := 2
	const K_TOKEN := 3

	var _nodes: Array[Node2D] = []
	var _kinds: PackedInt32Array = PackedInt32Array()
	var _scan_t := 999.0
	var _draw_t := 0.0
	var _t := 0.0
	var _player: Node2D = null
	var _wp: Node = null
	var _font: Font = null

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		_font = ThemeDB.fallback_font

	func bind_waypoint(wp: Node) -> void:
		_wp = wp

	func _process(delta: float) -> void:
		_t += delta
		_scan_t += delta
		var on: bool = GameManager.state == GameManager.GameState.PLAYING \
			and not UIManager.has_blocking_ui()
		if visible != on:
			visible = on
		if not on:
			return
		if _scan_t >= SCAN_INTERVAL:
			_scan()
		_draw_t += delta
		if _draw_t >= DRAW_INTERVAL:
			_draw_t = 0.0
			queue_redraw()

	func _scan() -> void:
		_scan_t = 0.0
		_nodes.clear()
		_kinds.clear()
		var tree := get_tree()
		if tree == null:
			return
		for n in tree.get_nodes_in_group("interactable"):
			if not (n is Node2D):
				continue
			if "target_region" in n:
				_nodes.append(n as Node2D)
				_kinds.append(K_PORTAL)
			elif "npc_id" in n and str(n.npc_id) != "":
				_nodes.append(n as Node2D)
				_kinds.append(K_NPC)
		for n in tree.get_nodes_in_group("enemy"):
			if n is Node2D:
				_nodes.append(n as Node2D)
				_kinds.append(K_ENEMY)
		for n in tree.get_nodes_in_group("token"):
			if _nodes.size() >= MAX_BLIPS:
				break
			if not (n is Node2D):
				continue
			if "collected" in n and n.collected:
				continue
			_nodes.append(n as Node2D)
			_kinds.append(K_TOKEN)

	func _player_node() -> Node2D:
		if is_instance_valid(_player):
			return _player
		var tree := get_tree()
		if tree == null:
			return null
		var p := tree.get_first_node_in_group("player")
		if p is Node2D:
			_player = p as Node2D
		else:
			_player = null
		return _player

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 4.0
		if r <= 8.0:
			return
		# Housing: void halo, dark glass disc, faint graticule.
		#
		# Round 5 drew this as a 1.5px ring at half alpha with 1.4–2.6px blips —
		# 196px of prime screen real estate that vanished at demo distance. Every
		# weight here went up a step: an opaque seat so the disc reads as an
		# instrument bezel rather than a hole in the frame, a 2.5px lit rim, and
		# blips large enough to count from across a room. The geometry (radius,
		# range, rim pinning) is untouched — this is contrast, not layout.
		draw_circle(c, r + 4.0, GameTheme.with_alpha(GameTheme.VOID, 0.85))
		draw_circle(c, r, GameTheme.with_alpha(GameTheme.BASE, 0.94))
		draw_arc(c, r - 1.0, 0.0, TAU, 72, GameTheme.with_alpha(GameTheme.LINE, 0.55), 1.0, true)
		var grid := GameTheme.with_alpha(GameTheme.LINE, 0.7)
		draw_line(c - Vector2(r, 0.0), c + Vector2(r, 0.0), grid, 1.0)
		draw_line(c - Vector2(0.0, r), c + Vector2(0.0, r), grid, 1.0)
		draw_arc(c, r * 0.5, 0.0, TAU, 40, GameTheme.with_alpha(GameTheme.LINE, 0.65), 1.0, true)
		# Slow radar sweep — the one thing that says "this is live".
		var a := fmod(_t * 0.85, TAU)
		draw_line(c, c + Vector2(cos(a), sin(a)) * r,
			GameTheme.with_alpha(GameTheme.CYAN, 0.38), 2.5)
		# Rim: a soft outer halo under a hard lit ring. Two passes, because one
		# 1.5px line at 50% is exactly the hairline the critique could not see.
		draw_arc(c, r + 1.5, 0.0, TAU, 72, GameTheme.with_alpha(GameTheme.CYAN, 0.18), 5.0, true)
		draw_arc(c, r, 0.0, TAU, 96, GameTheme.with_alpha(GameTheme.CYAN, 0.9), 2.5, true)

		var p := _player_node()
		if not is_instance_valid(p):
			return
		var origin := p.global_position
		var k := r / RANGE_PX
		var rim := r - 5.0
		for i in _nodes.size():
			var n: Node2D = _nodes[i]
			if not is_instance_valid(n):
				continue
			var kind := _kinds[i]
			var d := (n.global_position - origin) * k
			var out_of_range := d.length() > rim
			if out_of_range:
				# Portals are the one thing worth knowing about from anywhere:
				# they get pinned to the rim. Everything else simply isn't here.
				if kind != K_PORTAL:
					continue
				d = d.normalized() * rim
			var pos := c + d
			# Every blip gets a VOID seat first: a 3px dot at 95% alpha still
			# disappears into the graticule it happens to land on, and the disc
			# has a cross, a ring and a sweep line for it to land on.
			match kind:
				K_PORTAL:
					draw_circle(pos, 8.0, GameTheme.with_alpha(GameTheme.VIOLET, 0.30))
					draw_circle(pos, 5.4, GameTheme.with_alpha(GameTheme.VOID, 0.9))
					draw_circle(pos, 4.4, GameTheme.hot_of(GameTheme.VIOLET))
				K_NPC:
					draw_circle(pos, 4.4, GameTheme.with_alpha(GameTheme.VOID, 0.9))
					draw_circle(pos, 3.4, GameTheme.hot_of(GameTheme.CYAN))
				K_ENEMY:
					draw_circle(pos, 4.2, GameTheme.with_alpha(GameTheme.VOID, 0.9))
					draw_circle(pos, 3.2, GameTheme.with_alpha(GameTheme.RED, 1.0))
				K_TOKEN:
					draw_circle(pos, 2.8, GameTheme.with_alpha(GameTheme.VOID, 0.8))
					draw_circle(pos, 2.0, GameTheme.with_alpha(GameTheme.GOLD, 0.95))
		_draw_objective(c, r, origin, k)
		# The player, dead centre, hottest thing on the disc.
		draw_circle(c, 7.0, GameTheme.with_alpha(GameTheme.WHITE_HOT, 0.26))
		draw_circle(c, 4.6, GameTheme.with_alpha(GameTheme.VOID, 0.9))
		draw_circle(c, 3.4, GameTheme.WHITE_HOT)
		if _font != null:
			draw_string(_font, c + Vector2(-4.0, -r + 15.0), "N",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, GameTheme.with_alpha(GameTheme.TEXT, 0.95))

	## Objective blip: gold when the target is in this region, violet-hot when it
	## lives behind a portal somewhere else. Pinned to the rim when out of range.
	func _draw_objective(c: Vector2, r: float, origin: Vector2, k: float) -> void:
		if _wp == null or not is_instance_valid(_wp):
			return
		if not _wp.has_method("has_target") or not _wp.call("has_target"):
			return
		var far := _wp.has_method("is_cross_region") and bool(_wp.call("is_cross_region"))
		var col: Color = GameTheme.VIOLET if far else GameTheme.GOLD
		var tp: Vector2 = _wp.call("target_position")
		var d := (tp - origin) * k
		var rim := r - 5.0
		if d.length() > rim:
			d = d.normalized() * rim
		var pos := c + d
		var pulse := 0.55 + 0.45 * sin(_t * 4.0)
		draw_circle(pos, 10.0 + 2.5 * pulse, GameTheme.with_alpha(col, 0.20))
		draw_arc(pos, 7.5, 0.0, TAU, 24, GameTheme.with_alpha(col, 0.6 + 0.4 * pulse), 2.5, true)
		draw_circle(pos, 4.6, GameTheme.with_alpha(GameTheme.VOID, 0.9))
		draw_circle(pos, 3.6, GameTheme.hot_of(col))
