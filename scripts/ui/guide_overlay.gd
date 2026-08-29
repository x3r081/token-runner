extends CanvasLayer
## "WHAT AM I DOING?" — the always-available answer to the only question a tired
## player actually has. Press [H] (or F1) anywhere in the world and get, in this
## order: the current objective AND where it physically is, the core loop, live
## ship requirements, a nudge aimed at your specific mess, and the controls.
##
## Also owns the idle nudge toast: 40 seconds of no quest progress and it taps
## you on the shoulder, getting funnier and slightly more concerned each time.
##
## Mounted by UIManager so it exists wherever the world does. Layer 8 — above
## the HUD (1), below event popups (15) and dialogue (20). PROCESS_MODE_ALWAYS
## so the help screen still works while the game is paused (it pauses the game
## itself, because reading directions while a bug eats you helps nobody).

const _GameTheme = preload("res://scripts/ui/game_theme.gd")

const OVERLAY_LAYER := 8
## Seconds of zero quest progress before the game gently asks if you're okay.
const IDLE_SECONDS := 40.0
const TICK := 0.5
## One floor tile is 64px (RegionBuilder.TILE_SIZE) — call that one "step".
const STEP_PX := 64.0
## An enemy this close means you are busy; the toast waits its turn.
const COMBAT_RADIUS := 380.0
const TOAST_HOLD := 9.0

## Eight compass sectors, starting at east and rotating counter-clockwise.
const COMPASS: Array[String] = [
	"east", "north-east", "north", "north-west",
	"west", "south-west", "south", "south-east",
]

const REGION_NAMES := {
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

## Readable names for the things quests point at, so the guide never says
## "interact with dream_app_terminal" like a database with a grudge.
const PROP_NAMES := {
	"dream_app_terminal": "the Dream App terminal",
	"deploy_button": "the Deploy button",
	"client_email": "the laptop (the client's email)",
	"abandoned_package": "the abandoned package",
	"backup_server": "the backup server",
	"free_tokens_ad": "the suspicious pop-up ad",
	"agent_terminal": "the autonomous agent terminal",
	"broken_service": "the broken /checkout service",
	"prop_lockfile": "the package-lock.json",
	"prop_node_modules": "the node_modules drift",
	"prop_leftpad": "the left-pad marker",
	"prop_kanban": "the Kanban board",
	"prop_rig": "the mining rig",
	"prop_fan": "the cooling fan",
}

const ENEMY_NAMES := {
	"bug": "Bugs",
	"dependency_demon": "Dependency Demons",
	"null_reference": "Null References",
	"rate_limiter": "Rate Limiters",
	"merge_conflict": "the Merge Conflict",
	"cloud_bill": "the $700 Cloud Bill",
	"memory_leak": "Memory Leaks",
	"legacy_system": "Legacy Systems",
	"enterprise_architect": "the Enterprise Architect",
	"legacy_monolith": "the Legacy Monolith",
	"hallucination": "Hallucinations",
	"infinite_context": "THE INFINITE CONTEXT",
}

const REQ_ORDER: Array[String] = [
	"features", "stability", "total_upgrades", "ai_tier", "infra_tier",
]
const REQ_LABELS := {
	"features": "Features",
	"stability": "Stability",
	"total_upgrades": "Upgrades",
	"ai_tier": "AI tier",
	"infra_tier": "Infra tier",
}
## One dry line per requirement — the joke explains the number, never replaces it.
const REQ_NOTES := {
	"features": "things it does",
	"stability": "things it does twice in a row",
	"total_upgrades": "total tiers bought across all nine branches",
	"ai_tier": "it must have AI in it. This is not negotiable in this economy",
	"infra_tier": "it has to run somewhere that isn't your laptop",
}

const RES_SHORT := {
	"tokens": "tk", "compute": "cp", "context": "ctx",
	"api_credits": "cr", "reputation": "rep",
}

## The core loop, one line each. This is the entire game; everything else is set
## dressing and jokes about YAML.
const LOOP_LINES: Array[String] = [
	"1.  COLLECT TOKENS — the glowing gold things on the floor. Enemies drop them too, which is the only honest reason to fight anything.",
	"2.  PRESS [B] — spend tokens on Dream App upgrades. Nine branches, each a different mistake with a nicer name.",
	"3.  MEET THE REQUIREMENTS below. They are not vibes. The Deploy button actually checks.",
	"4.  DEPLOY — go back to Localhost, walk to the Deploy button, press [E]. That's shipping. It really is that small, which is the joke.",
]

const CONTROLS_LINE := "WASD / Arrows move  ·  [E] interact & talk  ·  [1] Prompt Blast  ·  [Shift] dash  ·  [2]-[5] abilities  ·  [T] swap model  ·  [B] Dream App  ·  [J] quests  ·  [M] map & fast travel  ·  [Esc] pause  ·  [H] this screen"

## Escalating idle nudges: concerned, never condescending. Punch up, or at us.
## The ladder only ever climbs — that escalation IS the joke — and every rung
## still names the key, because a nudge that doesn't tell you what to press is
## just a notification.
const NUDGES: Array[String] = [
	"Stuck? Press [H].",
	"Still circling. [H] says what to do and, more usefully, where.",
	"[H] answers 'what am I doing', which is more than most standups manage.",
	"Third lap of the same room. [H] has directions and no opinions.",
	"Press [H]. I'm not worried. I'm logging it, but I'm not worried.",
	"You have explored significantly more than you have accomplished. [H].",
	"[H] for a plan. Wandering is a valid strategy in other, kinder games.",
	"This is now the longest anyone has spent in this room, including the person who built it. [H].",
	"[H]. I have re-read the objective on your behalf. It has not changed.",
	"Hour four on the same three floor tiles. [H], for both our sakes.",
	"I've started narrating your movement to myself. Please press [H] so I can stop.",
]

var _open := false
var _modal_pushed := false
var _paused_by_us := false
var _has_action := false

var _root: Control
var _panel: PanelContainer
var _content: VBoxContainer
var _objective_line := ""

var _toast: PanelContainer
var _toast_label: Label
var _toast_tween: Tween
var _toast_visible := false

var _tick_accum := 0.0
var _idle := 0.0
var _fingerprint := -1
var _nudge_level := 0

# ------------------------------------------------------------------ setup ----

func _ready() -> void:
	name = "GuideOverlay"
	layer = OVERLAY_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_has_action = InputMap.has_action("guide")
	_build_shell()
	_build_toast()

func _build_shell() -> void:
	_root = Control.new()
	_root.name = "GuideRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = false
	add_child(_root)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.02, 0.024, 0.055, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	_root.add_child(_GameTheme.make_vignette(_GameTheme.with_alpha(_GameTheme.VOID, 0.75)))

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	_panel = PanelContainer.new()
	_panel.name = "GuidePanel"
	_panel.theme = _GameTheme.create()
	_panel.add_theme_stylebox_override("panel", _GameTheme.panel_box(_GameTheme.CYAN, 20.0))
	center.add_child(_panel)
	_GameTheme.add_sheen(_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.custom_minimum_size = Vector2(780, 0)
	_panel.add_child(vb)

	var title := Label.new()
	title.name = "GuideTitle"
	title.text = "WHAT AM I DOING?"
	title.add_theme_font_size_override("font_size", 26)
	_GameTheme.style_heading(title, _GameTheme.CYAN, 26)
	vb.add_child(title)

	var sub := Label.new()
	sub.text = "A field guide for the sleep-deprived. This screen is always one [H] away."
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	vb.add_child(sub)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(760, 520)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)

	_content = VBoxContainer.new()
	_content.name = "GuideContent"
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 5)
	scroll.add_child(_content)

	var controls := Label.new()
	controls.name = "ControlsFooter"
	controls.text = CONTROLS_LINE
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.custom_minimum_size = Vector2(760, 0)
	controls.add_theme_font_size_override("font_size", 12)
	controls.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	vb.add_child(controls)

	var close := Button.new()
	close.name = "CloseBtn"
	close.text = "Fine.  [H] / [Esc]"
	_GameTheme.style_button(close, _GameTheme.CYAN, 15)
	close.pressed.connect(close_guide)
	vb.add_child(close)

func _build_toast() -> void:
	_toast = PanelContainer.new()
	_toast.name = "GuideToast"
	_toast.theme = _GameTheme.create(_GameTheme.AMBER)
	_toast.add_theme_stylebox_override("panel", _GameTheme.glass_box(_GameTheme.AMBER, 12.0))
	_toast.anchor_left = 1.0
	_toast.anchor_right = 1.0
	_toast.anchor_top = 1.0
	_toast.anchor_bottom = 1.0
	_toast.offset_left = -430.0
	_toast.offset_top = -164.0
	_toast.offset_right = -24.0
	_toast.offset_bottom = -96.0
	_toast.visible = false
	add_child(_toast)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	_toast.add_child(vb)

	_toast_label = Label.new()
	_toast_label.name = "ToastLabel"
	_toast_label.text = NUDGES[0]
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_label.custom_minimum_size = Vector2(380, 0)
	_toast_label.add_theme_font_size_override("font_size", 14)
	_toast_label.add_theme_color_override("font_color", _GameTheme.TEXT)
	vb.add_child(_toast_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)
	var show_btn := Button.new()
	show_btn.text = "Show me  [H]"
	_GameTheme.style_button(show_btn, _GameTheme.AMBER, 13)
	show_btn.pressed.connect(open_guide)
	row.add_child(show_btn)
	var dismiss := Button.new()
	dismiss.text = "I'm fine"
	_GameTheme.style_button(dismiss, _GameTheme.TEXT_DIM, 13)
	dismiss.pressed.connect(_hide_toast)
	row.add_child(dismiss)

# ------------------------------------------------------------------ input ----

func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if _has_action and event.is_action_pressed("guide"):
		toggle_guide()
		get_viewport().set_input_as_handled()
		return
	if _open and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")):
		close_guide()
		get_viewport().set_input_as_handled()

# ------------------------------------------------------------- open / close ----

func is_open() -> bool:
	return _open

func toggle_guide() -> void:
	if _open:
		close_guide()
	else:
		open_guide()

func open_guide() -> void:
	if _open or not _world_ready():
		return
	_open = true
	_hide_toast()
	_rebuild()
	_root.visible = true
	if not _modal_pushed:
		_modal_pushed = true
		UIManager.push_modal()
	# Pause only if WE are the ones pausing — never yank the pause menu's rug.
	if GameManager.state == GameManager.GameState.PLAYING:
		_paused_by_us = true
		GameManager.pause_game(true)
	_GameTheme.open_panel(_panel)
	_GameTheme.stagger_rows(_content, 0.03, 0.04)

func close_guide() -> void:
	if not _open:
		return
	_open = false
	if is_instance_valid(_root):
		_root.visible = false
	if _modal_pushed:
		_modal_pushed = false
		UIManager.pop_modal()
	if _paused_by_us:
		_paused_by_us = false
		if GameManager.state == GameManager.GameState.PAUSED:
			GameManager.pause_game(false)
	_idle = 0.0

# ------------------------------------------------------------------ content ----

## Plain-text mirror of everything the panel says. Handy for debugging and for
## anything that wants to assert the guide is actually answering the question.
func summary_text() -> String:
	if _content == null:
		return ""
	_rebuild()
	return _collect_text(_content)

## The one-line "do this next", without opening the panel. Anything that wants
## to echo the objective (HUD, tooltips) can read it from here.
func current_objective_text() -> String:
	var cur := _current_objective()
	if cur.is_empty():
		return "No active objective."
	var obj: Dictionary = cur.obj
	return str(obj.get("text", obj.get("id", "Do the thing")))

func _collect_text(n: Node, acc: String = "") -> String:
	if n is Label:
		acc += " " + (n as Label).text
	for c: Node in n.get_children():
		acc = _collect_text(c, acc)
	return acc

func _rebuild() -> void:
	if _content == null:
		return
	for c: Node in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	_section_objective()
	_section_loop()
	_section_requirements()
	_section_diagnosis()
	_section_nudges()

func _section_objective() -> void:
	_head("RIGHT NOW", _GameTheme.AMBER)
	var cur := _current_objective()
	if cur.is_empty():
		_objective_line = "No active objective — which is either freedom or a bug, and both are on you."
		_line(_objective_line, 18, _GameTheme.WHITE_HOT)
		_line("WHERE: find anyone with a floating gold [!] over their head and press [E]. Claude lives in Localhost, at the desk.", 15, _GameTheme.CYAN_HOT)
		return
	var quest: Dictionary = cur.quest
	var obj: Dictionary = cur.obj
	var need: int = cur.need
	var text := str(obj.get("text", obj.get("id", "Do the thing")))
	if need > 1:
		text += "  (%d / %d)" % [int(cur.prog), need]
	_objective_line = text
	_line("→  %s" % text, 18, _GameTheme.WHITE_HOT)
	_line("Quest: %s — %s" % [str(quest.get("name", "?")), str(quest.get("description", ""))], 13, _GameTheme.TEXT_DIM)
	_line("WHERE: %s" % _where_for(obj, quest), 15, _GameTheme.CYAN_HOT)

## The numbers that are quietly steering this run, each with a one-line verdict.
## The value column always carries the fact; the verdict column carries the joke.
## Nothing here is decoration — every row is a number the player can move.
func _section_diagnosis() -> void:
	_gap()
	_head("THE STATE OF YOU — numbers that are already steering this run", _GameTheme.MAGENTA)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 3)
	_content.add_child(grid)
	for row: Array in _diagnosis_rows():
		var col: Color = row[3]
		_cell(grid, String(row[0]), 14, _GameTheme.TEXT_DIM)
		_cell(grid, String(row[1]), 15, col)
		# The verdict column wraps: the scroll view has horizontal scrolling
		# disabled, so an unwrapped sentence here would simply be cut off.
		_cell_wrap(grid, String(row[2]), 13, _GameTheme.TEXT_DIM, 452.0)

## [label, value, verdict, value_color]. Rows that are only interesting when
## they're going wrong (agents, focus, will to live) are omitted when they aren't.
func _diagnosis_rows() -> Array:
	var out: Array = []
	var tokens := int(ResourceManager.get_value("tokens"))
	var debt := int(ResourceManager.get_value("technical_debt"))
	var stability := int(ResourceManager.get_value("stability"))
	var focus := int(ResourceManager.get_value("focus"))
	var wtl := int(ResourceManager.get_value("will_to_live"))
	var deaths: int = GameManager.death_count
	var tiers := int(DreamAppManager.get_totals().get("total_tiers", 0))
	var agents: int = AgentManager.active_count() if AgentManager else 0
	var surcharge := int(round((DreamAppManager.debt_cost_multiplier() - 1.0) * 100.0))

	var tok_note := "enough to keep moving"
	if tokens < 20:
		tok_note = "broke. Gold pickups are on the floor; enemies drop more"
	elif tokens >= 250:
		tok_note = "hoarding. Tokens do nothing in a pocket. [B] converts them into an app"
	out.append(["Tokens", str(tokens), tok_note,
		_GameTheme.RED if tokens < 20 else _GameTheme.GOLD])

	var up_note := "each one moves a requirement below"
	if tiers == 0:
		up_note = "you own none. This is the one thing blocking the ending. [B]"
	elif tiers >= 12:
		up_note = "genuinely well equipped. Suspicious. Keep going"
	out.append(["Upgrades bought", str(tiers), up_note,
		_GameTheme.RED if tiers == 0 else _GameTheme.ACID])

	var debt_note := "harmless, for now"
	if debt >= 60:
		debt_note = "every price is +%d%%. It compounds. It does not forgive" % surcharge
	elif debt >= 25:
		debt_note = "quietly adding +%d%% to every price you will ever see" % surcharge
	out.append(["Technical debt", str(debt), debt_note,
		_GameTheme.RED if debt >= 60 else (_GameTheme.AMBER if debt >= 25 else _GameTheme.TEXT)])

	var stab_note := "shippable range"
	if stability <= 30:
		stab_note = "one incident from a bad night. Buy Stability in [B]"
	elif stability <= 60:
		stab_note = "wobbly — and it is a ship requirement, so not optional"
	out.append(["Stability", str(stability), stab_note,
		_GameTheme.RED if stability <= 30 else _GameTheme.TEXT])

	var death_note := "clean run so far"
	if deaths >= 5:
		death_note = "you lose only time. [Shift] dashes; enemies give up if you outrun them"
	elif deaths >= 1:
		death_note = "respawn is free. Ctrl+Z, but for your entire body"
	out.append(["Deaths tonight", str(deaths), death_note,
		_GameTheme.RED if deaths >= 5 else _GameTheme.TEXT])

	out.append(["Cycle", "%d · %ds left" % [CycleManager.cycle, CycleManager.seconds_left()],
		"the reset refills quotas and shuffles prices. Purchases survive",
		_GameTheme.AMBER if CycleManager.seconds_left() <= int(CycleManager.WARN_AT) else _GameTheme.TEXT])

	if agents > 0:
		out.append(["Agents deployed", str(agents),
			"working autonomously and confidently, in that order",
			_GameTheme.VIOLET])
	if focus <= 35:
		out.append(["Focus", str(focus),
			"abilities cost focus. Coffee restores it: find the machine, [E]",
			_GameTheme.AMBER])
	if wtl <= 40:
		out.append(["Will to live", str(wtl),
			"cosmetic. Mostly. It is also the game gently asking after you",
			_GameTheme.AMBER])
	return out

func _section_loop() -> void:
	_gap()
	_head("THE LOOP (this is the whole game)", _GameTheme.CYAN)
	for l: String in LOOP_LINES:
		_line(l, 14, _GameTheme.TEXT)

func _section_requirements() -> void:
	_gap()
	_head("SHIP REQUIREMENTS — what Deploy checks", _GameTheme.GOLD)
	var reqs: Dictionary = DreamAppManager.get_ship_requirements()
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 3)
	_content.add_child(grid)
	for key: String in REQ_ORDER:
		var r: Dictionary = reqs.get(key, {"current": 0, "required": 0})
		var cur_v := int(r.get("current", 0))
		var req_v := int(r.get("required", 0))
		var done := cur_v >= req_v
		var col: Color = _GameTheme.ACID if done else _GameTheme.TEXT
		var mark := "☑" if done else "☐"
		var val_col: Color = col if done else _GameTheme.GOLD
		_cell(grid, mark, 15, col)
		_cell(grid, str(REQ_LABELS.get(key, key)), 15, col)
		_cell(grid, "%d / %d" % [cur_v, req_v], 15, val_col)
		_cell(grid, str(REQ_NOTES.get(key, "")), 12, _GameTheme.TEXT_DIM)
	if DreamAppManager.can_ship():
		_line("STATUS: shippable. Go to Localhost, walk to the Deploy button, press [E]. Do it before you start thinking.", 15, _GameTheme.ACID)
	else:
		var cheap := _cheapest_next()
		if cheap.is_empty():
			_line("STATUS: not yet. Press [B] and buy upgrades — that is the only thing that moves these numbers.", 14, _GameTheme.TEXT)
		elif bool(cheap.afford):
			_line("STATUS: not yet. You can afford %s — %s (%s). Press [B] and buy it." % [
				_branch_name(str(cheap.branch)), str(cheap.name), str(cheap.cost_text)], 14, _GameTheme.TEXT)
		else:
			_line("STATUS: not yet. Cheapest next upgrade is %s — %s (%s). You are short. Go collect tokens." % [
				_branch_name(str(cheap.branch)), str(cheap.name), str(cheap.cost_text)], 14, _GameTheme.TEXT)

func _section_nudges() -> void:
	_gap()
	_head("WHILE YOU'RE HERE", _GameTheme.VIOLET)
	for n: String in _nudges():
		_line("•  %s" % n, 14, _GameTheme.TEXT)

# ------------------------------------------------------- content primitives ----

func _head(text: String, accent: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", accent)
	l.add_theme_font_override("font", _GameTheme.spaced_font(3))
	_content.add_child(l)

func _line(text: String, size: int, col: Color) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(736, 0)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	_content.add_child(l)

func _cell(grid: GridContainer, text: String, size: int, col: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	grid.add_child(l)

## Grid cell that wraps inside a fixed column width instead of widening the grid.
func _cell_wrap(grid: GridContainer, text: String, size: int, col: Color, width: float) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(width, 0)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	grid.add_child(l)

func _gap() -> void:
	var s := HSeparator.new()
	s.add_theme_constant_override("separation", 12)
	_content.add_child(s)

# ------------------------------------------------------- objective + "where" ----

## First unfinished objective of the first active quest — the thing the player
## should physically be doing in the next ten seconds.
func _current_objective() -> Dictionary:
	for qid: String in QuestManager.get_active_quests():
		var info := QuestManager.get_quest_info(qid)
		var progress: Dictionary = info.get("progress", {})
		for obj in info.get("objectives", []):
			if not (obj is Dictionary):
				continue
			var od: Dictionary = obj
			var prog := int(progress.get(str(od.get("id", "")), 0))
			var need := int(od.get("count", 1))
			if prog < need:
				return {"quest": info, "obj": od, "prog": prog, "need": need}
	return {}

## The load-bearing sentence: WHERE, in this room, relative to your body.
func _where_for(obj: Dictionary, quest: Dictionary) -> String:
	var kind := str(obj.get("type", ""))
	var target := str(obj.get("target", ""))
	# The quest's own "region" is where the GIVER stands, which is not always
	# where the work is: context_window_full is handed out in Cloud District and
	# its boss only spawns in the Token Vault. QuestManager.objective_region()
	# resolves that from the world's real spawn table — use it, or the guide
	# sends the player to a room the objective cannot be completed in.
	var home := QuestManager.objective_region(str(quest.get("id", "")), obj)
	if home == "":
		home = str(quest.get("region", GameManager.current_region))
	if kind == "talk":
		var who := DialogueManager.get_npc_name(target)
		var npc := _find_npc(target)
		if npc:
			return "%s is %s. Walk over and press [E]." % [who, _bearing(npc.global_position)]
		return "%s is in %s, and you are not. Press [M] and travel there." % [who, _region_name(home)]
	if kind == "interact":
		var what := str(PROP_NAMES.get(target, "the %s" % target.replace("_", " ")))
		var prop := _find_interactable(target)
		if prop:
			return "Head for %s — it's %s. Stand on it and press [E]." % [what, _bearing(prop.global_position)]
		return "Head for %s, over in %s. Press [M] and travel there." % [what, _region_name(home)]
	if kind == "visit":
		if GameManager.current_region == target:
			return "You're already here. Walking a few steps should tick it over."
		var portal := _find_portal(target)
		if portal:
			return "The portal to %s is %s. Walk into it." % [_region_name(target), _bearing(portal.global_position)]
		if GameManager.is_region_unlocked(target):
			return "%s is unlocked — press [M] and fast travel. No portal in this room." % _region_name(target)
		return "%s is still locked. Finish the quests you have; regions unlock as rewards." % _region_name(target)
	if kind == "collect_tokens":
		var tok := _nearest_in_group("token")
		if tok:
			return "Nearest token is %s. They're the glowing gold pickups; enemies drop more." % _bearing(tok.global_position)
		return "This room is picked clean. Try another region ([M]) or hit something that drops tokens."
	if kind == "defeat":
		var foe := _nearest_enemy(target)
		if foe:
			return "%s: nearest one is %s. [1] Prompt Blast, [Shift] to dash out again." % [
				str(ENEMY_NAMES.get(target, target.replace("_", " ").capitalize())), _bearing(foe.global_position)]
		return "%s live in %s. Press [M] and go where the problem is." % [
			str(ENEMY_NAMES.get(target, target.replace("_", " ").capitalize())), _region_name(home)]
	# "story" and anything new: point at the region and the interact key.
	if GameManager.current_region == home:
		return "It happens right here in %s — look for a prop with an [E] prompt over it." % _region_name(home)
	return "It happens in %s. Press [M] and travel there." % _region_name(home)

## "north-east of you, about 7 steps" — a direction a human can actually walk.
func _bearing(target: Vector2) -> String:
	var p := _player()
	if p == null:
		return "somewhere in this region"
	var d: Vector2 = target - p.global_position
	var steps := int(round(d.length() / STEP_PX))
	if steps <= 2:
		return "practically under your feet (yes, that one)"
	var ang := rad_to_deg(atan2(-d.y, d.x))
	if ang < 0.0:
		ang += 360.0
	var idx := int(round(ang / 45.0)) % 8
	return "%s of you, about %d steps" % [COMPASS[idx], steps]

# --------------------------------------------------------------- contextual ----

## Up to three nudges chosen from your actual state, most urgent first. Each one
## names a key or a place; a joke without an instruction is just noise.
func _nudges() -> Array[String]:
	var out: Array[String] = []
	var tokens := int(ResourceManager.get_value("tokens"))
	var debt := int(ResourceManager.get_value("technical_debt"))
	var focus := int(ResourceManager.get_value("focus"))
	var coffee := int(ResourceManager.get_value("coffee"))
	var totals: Dictionary = DreamAppManager.get_totals()
	var tiers := int(totals.get("total_tiers", 0))

	var deaths: int = GameManager.death_count

	if _combat_nearby():
		out.append("Something is chewing on you. [1] Prompt Blast, [Shift] to dash out, or just leave — enemies give up if you outrun them.")
	if DreamAppManager.can_ship():
		out.append("You already meet the ship requirements. Localhost → Deploy button → [E]. Shipping is a decision, not a state of readiness.")
	if not _has_talked_to_anyone():
		out.append("You haven't talked to anybody yet. NPCs with a floating gold [!] are holding your quests hostage. [E] frees them.")
	if tiers == 0:
		out.append("You own zero upgrades. Your Dream App is currently a README with feelings. Press [B]; Infrastructure tier 1 costs about 10 tokens.")
	if deaths >= 4:
		out.append("You have died %d times. Dying costs you nothing but momentum, so this is a pacing note, not a scolding: [Shift] dashes through things, and you can simply walk away from a fight." % deaths)
	if tokens < 30:
		out.append("You have %d tokens, which buys roughly one opinion. Gold pickups are on the floor; enemies drop them when they stop existing." % tokens)
	if debt >= 60:
		out.append("Technical debt is %d, so every upgrade costs about %d%% more. Compound interest, but for decisions. Nothing removes it. Spend earlier next time." % [debt, int(round((DreamAppManager.debt_cost_multiplier() - 1.0) * 100.0))])
	if tokens >= 250 and tiers < 6:
		out.append("You are holding %d tokens and %d upgrades. Tokens do nothing in your pocket except lose value at the reset. [B] converts them into an ending." % [tokens, tiers])
	if focus <= 35 and coffee > 0:
		out.append("Focus is at %d. You are holding %d coffee. These two facts are related; find the coffee machine and press [E]." % [focus, coffee])
	if CycleManager.seconds_left() <= int(CycleManager.WARN_AT):
		out.append("Reset lands in %ds. Nothing you bought disappears — quotas refill and prices shuffle. Keep moving." % CycleManager.seconds_left())
	if out.size() < 2 and GameManager.current_region == "localhost":
		out.append("Localhost is safe-ish: the two bugs live over by the exit on the right. Everything else here is furniture with jokes on it.")
	if out.size() < 2:
		out.append("Press [J] for the quest log — it lists who gives what, and where they stand.")
	if out.size() < 3:
		out.append("Walk past an NPC and they will say something unprompted. It is usually about you. It is usually accurate.")
	if out.is_empty():
		out.append("Nothing is on fire. Follow the objective at the top; if it names someone, that someone is standing in a room you can walk to.")
	return out.slice(0, 3)

## The idle toast alternates between the escalating ladder (the running gag) and
## a line aimed at whatever is actually wrong right now (the useful part). Both
## always name a key.
func _toast_line() -> String:
	var ladder: String = NUDGES[mini(_nudge_level, NUDGES.size() - 1)]
	var state := _state_nudge()
	_nudge_level += 1
	if state != "" and _nudge_level % 2 == 0:
		return state
	return ladder

## One short, specific "here is your actual problem" line, or "" when the run is
## not visibly in trouble. Short enough for a 380px toast.
func _state_nudge() -> String:
	var tokens := int(ResourceManager.get_value("tokens"))
	var debt := int(ResourceManager.get_value("technical_debt"))
	var tiers := int(DreamAppManager.get_totals().get("total_tiers", 0))
	var deaths: int = GameManager.death_count
	if DreamAppManager.can_ship():
		return "It is shippable. Localhost → Deploy button → [E]. [H] if you want the checklist again."
	if not _has_talked_to_anyone():
		return "Nobody has been talked to yet. Find a floating gold [!] and press [E]. [H] says where."
	if tiers == 0:
		return "Still zero upgrades. [B] opens the Dream App console — that is the whole game. [H] for the rest."
	if tokens < 20:
		return "%d tokens. Gold pickups are on the floor and enemies drop more. [H] points at the nearest one." % tokens
	if deaths >= 4:
		return "%d deaths. You can walk away from any fight; nothing chases forever. [H] has the plan." % deaths
	if debt >= 60:
		return "Technical debt %d is inflating every price. Buy sooner rather than better. [H] for details." % debt
	return ""

func _has_talked_to_anyone() -> bool:
	for qid in QuestManager.quest_progress:
		var per: Dictionary = QuestManager.quest_progress[qid]
		for oid in per:
			if int(per[oid]) > 0:
				return true
	return not QuestManager.completed_quests.is_empty()

func _branch_name(branch: String) -> String:
	return branch.replace("_", " ").capitalize()

func _fmt_cost(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for k in cost:
		parts.append("%d %s" % [int(cost[k]), str(RES_SHORT.get(k, k))])
	if parts.is_empty():
		return "free, suspiciously"
	return ", ".join(parts)

## Cheapest purchasable next tier across all branches — the concrete "buy this".
func _cheapest_next() -> Dictionary:
	var best := {}
	var best_cost := 1 << 30
	for b in DreamAppManager.BRANCHES:
		var nxt: Dictionary = DreamAppManager.get_next_upgrade(b)
		if nxt.is_empty():
			continue
		var cost: Dictionary = DreamAppManager.get_effective_cost(b)
		var total := 0
		for k in cost:
			total += int(cost[k])
		if total < best_cost:
			best_cost = total
			best = {
				"branch": b,
				"name": str(nxt.get("name", "?")),
				"cost_text": _fmt_cost(cost),
				"afford": ResourceManager.can_afford(cost),
			}
	return best

# ------------------------------------------------------------ scene lookups ----

func _player() -> Node2D:
	if not is_inside_tree():
		return null
	var p: Node = get_tree().get_first_node_in_group("player")
	if p is Node2D:
		return p as Node2D
	return null

func _find_npc(npc_id: String) -> Node2D:
	if not is_inside_tree():
		return null
	for n: Node in get_tree().get_nodes_in_group("interactable"):
		if n is Node2D and "npc_id" in n and str(n.get("npc_id")) == npc_id:
			return n as Node2D
	return null

func _find_interactable(id: String) -> Node2D:
	if not is_inside_tree():
		return null
	for n: Node in get_tree().get_nodes_in_group("interactable"):
		if n is Node2D and "interact_id" in n and str(n.get("interact_id")) == id:
			return n as Node2D
	return null

func _find_portal(region_id: String) -> Node2D:
	if not is_inside_tree():
		return null
	for n: Node in get_tree().get_nodes_in_group("interactable"):
		if n is Node2D and "target_region" in n and str(n.get("target_region")) == region_id:
			return n as Node2D
	return null

func _nearest_in_group(group: String) -> Node2D:
	var p := _player()
	if p == null:
		return null
	var best: Node2D = null
	var best_d := INF
	for n: Node in get_tree().get_nodes_in_group(group):
		if not (n is Node2D):
			continue
		var d: float = (n as Node2D).global_position.distance_squared_to(p.global_position)
		if d < best_d:
			best_d = d
			best = n as Node2D
	return best

func _nearest_enemy(enemy_type: String) -> Node2D:
	var p := _player()
	if p == null:
		return null
	var best: Node2D = null
	var best_d := INF
	for n: Node in get_tree().get_nodes_in_group("enemy"):
		if not (n is Node2D):
			continue
		if enemy_type != "" and "enemy_type" in n and str(n.get("enemy_type")) != enemy_type:
			continue
		var d: float = (n as Node2D).global_position.distance_squared_to(p.global_position)
		if d < best_d:
			best_d = d
			best = n as Node2D
	return best

func _region_name(region_id: String) -> String:
	return str(REGION_NAMES.get(region_id, region_id.replace("_", " ").capitalize()))

# -------------------------------------------------------------- idle nudge ----

func _process(delta: float) -> void:
	if _open and not _world_ready():
		close_guide()
	_tick_accum += delta
	if _tick_accum < TICK:
		return
	var dt := _tick_accum
	_tick_accum = 0.0
	_idle_tick(dt)

func _idle_tick(dt: float) -> void:
	if not _world_ready():
		_idle = 0.0
		if _toast_visible:
			_hide_toast()
		return
	# Any real progress (objective ticked, quest done, upgrade bought, region
	# unlocked) resets the clock AND the escalation. You earned that.
	var fp := _fingerprint_now()
	if fp != _fingerprint:
		_fingerprint = fp
		_idle = 0.0
		_nudge_level = 0
		if _toast_visible:
			_hide_toast()
		return
	# Dialogue, pause, modals and events aren't "stuck" — they're content.
	if _busy():
		_idle = 0.0
		return
	if _toast_visible or _open:
		return
	if _idle < IDLE_SECONDS:
		_idle += dt
		return
	# At the threshold: hold (don't reset) until you're out of a fight.
	if _combat_nearby():
		return
	_idle = 0.0
	_show_toast()

func _busy() -> bool:
	if GameManager.state != GameManager.GameState.PLAYING:
		return true
	if DialogueManager.is_active:
		return true
	if UIManager.has_blocking_ui():
		return true
	if EventManager.has_active_event():
		return true
	# Cutscenes and the one-time intro card own the screen; standing still during
	# those is obedience, not confusion.
	var p := _player()
	if p != null and "can_move" in p and not bool(p.get("can_move")):
		return true
	if _intro_card_up():
		return true
	return false

## The HUD's one-time onboarding card (hud.gd show_intro_hint) is already
## answering the question; don't talk over it.
func _intro_card_up() -> bool:
	var world := get_tree().get_first_node_in_group("world")
	if world == null:
		return false
	var hud := world.get_node_or_null("HUD")
	return hud != null and hud.get_node_or_null("IntroHint") != null

func _combat_nearby() -> bool:
	var p := _player()
	if p == null:
		return false
	var r2 := COMBAT_RADIUS * COMBAT_RADIUS
	for n: Node in get_tree().get_nodes_in_group("enemy"):
		if n is Node2D and (n as Node2D).global_position.distance_squared_to(p.global_position) < r2:
			return true
	return false

## Cheap integer signature of "have you accomplished anything". Dictionary walks
## only — no arrays allocated — and it runs twice a second at most.
func _fingerprint_now() -> int:
	var h := QuestManager.completed_quests.size() * 1000003
	h += GameManager.regions_unlocked.size() * 7919
	for qid in QuestManager.quest_progress:
		var per: Dictionary = QuestManager.quest_progress[qid]
		for oid in per:
			h = h * 31 + int(per[oid])
	for b in DreamAppManager.purchased:
		h = h * 17 + int(DreamAppManager.purchased[b])
	return h

func _world_ready() -> bool:
	if not is_inside_tree():
		return false
	var tree := get_tree()
	if tree == null:
		return false
	return tree.get_first_node_in_group("world") != null

func _show_toast() -> void:
	if not is_instance_valid(_toast):
		return
	_toast_visible = true
	_toast_label.text = _toast_line()
	_toast.visible = true
	_toast.modulate.a = 0.0
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = _toast.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_toast_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, _GameTheme.T_STD)
	_toast_tween.tween_interval(TOAST_HOLD)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)
	_toast_tween.tween_callback(_on_toast_finished)

func _hide_toast() -> void:
	# Never kill the tween from inside its own callback — that path calls
	# _on_toast_finished directly instead.
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_on_toast_finished()

func _on_toast_finished() -> void:
	_toast_visible = false
	_toast_tween = null
	if is_instance_valid(_toast):
		_toast.visible = false
		_toast.modulate.a = 1.0
