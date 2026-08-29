extends PanelContainer
## The quest log's job is CLARITY, not vibes: ACTIVE / AVAILABLE / DONE, live
## objective checkboxes with counts, WHO hands out an available quest and WHERE
## they're standing, and a "next step" line that names an actual key or place.
## Each quest gets one dry line of flavour — riding along, never in the way.

const _GameTheme = preload("res://scripts/ui/game_theme.gd")

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

## Quests whose JSON has no "giver" — the NPC who actually carries them in the
## world (see RegionBuilder._region_npcs). Keeps "who do I ask" always answered.
const FALLBACK_GIVERS := {
	"fix_without_touching": "maintainer",
	"junior_agent": "api_reseller",
	"merge_conflict_hell": "stackoverflow_hermit",
	"context_window_full": "cloud_salesperson",
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

const PROP_NAMES := {
	"dream_app_terminal": "the Dream App terminal",
	"deploy_button": "the Deploy button",
	"client_email": "the laptop (client email)",
	"abandoned_package": "the abandoned package",
	"backup_server": "the backup server",
}

## One line per quest. Brutally accurate beats random; the instruction lives in
## the objective rows right underneath.
const QUEST_FLAVOUR := {
	"hello_localhost": "Everyone's first sprint: wake up, talk to the AI, pick things up off the floor.",
	"tiny_change": "It is one word in one CSS file. It has never once been one word in one CSS file.",
	"install_node": "Estimate: thirty seconds. Actual: a folder with its own gravity.",
	"stackoverflow_pilgrimage": "The answer is there. It's from 2013. It works. Nobody living knows why.",
	"one_more_api_call": "Priced per request, per token, per glance, and per regret.",
	"cloud_migration": "Nobody in the room can define 'cloud'. The migration is approved.",
	"license_puzzle": "One unpaid volunteer is holding your Series A upright with both hands.",
	"enterprise_ready": "The strategy is 'AI'. The deadline is Friday. The implementation is you.",
	"gpu_rush": "94°C. The fans sound like a decision you can't take back.",
	"production_down": "Everyone agrees it's DNS. It is not DNS. It is, as ever, us.",
	"ship_dream_app": "The last 2% of the project, famously 80% of the project.",
	"fix_without_touching": "A change freeze during an outage: decisive, confident, physically impossible.",
	"junior_agent": "It was 100% confident. That's the part that should worry you.",
	"merge_conflict_hell": "Two branches, one file, three weeks, zero survivors.",
	"context_window_full": "You pasted the entire repo. The model has seen things.",
}

func _ready() -> void:
	theme = _GameTheme.create()
	add_theme_stylebox_override("panel", _GameTheme.panel_box(_GameTheme.CYAN, 4.0))
	_GameTheme.style_heading($Margin/VBox/Title, _GameTheme.CYAN, 22)
	$Margin/VBox/Subtitle.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	$Margin/VBox/Footer.add_theme_color_override("font_color", _GameTheme.AMBER)
	_GameTheme.style_button($Margin/VBox/CloseBtn, _GameTheme.CYAN, 15)
	_populate()
	_GameTheme.open_panel(self)
	$Margin/VBox/CloseBtn.pressed.connect(queue_free)

func _populate() -> void:
	var vbox: VBoxContainer = $Margin/VBox/Scroll/QuestList
	for c in vbox.get_children():
		vbox.remove_child(c)
		c.queue_free()
	vbox.add_theme_constant_override("separation", 8)

	var active: Array[Dictionary] = []
	var available: Array[Dictionary] = []
	var done: Array[Dictionary] = []
	for info: Dictionary in QuestManager.get_all_quest_infos():
		var state := int(info.get("state", QuestManager.QuestState.INACTIVE))
		if state == QuestManager.QuestState.ACTIVE:
			active.append(info)
		elif state == QuestManager.QuestState.COMPLETED:
			done.append(info)
		elif state == QuestManager.QuestState.INACTIVE and _prereqs_met(info):
			available.append(info)

	_group(vbox, "ACTIVE — %d" % active.size(), _GameTheme.CYAN)
	if active.is_empty():
		_empty(vbox, "Nothing active. Find someone with a floating gold [!] over their head and press [E].")
	for info: Dictionary in active:
		_active_card(vbox, info)

	_group(vbox, "AVAILABLE — %d" % available.size(), _GameTheme.AMBER)
	if available.is_empty():
		_empty(vbox, "Nothing on offer. Finish what's active — new work unlocks from the old work.")
	for info: Dictionary in available:
		_available_card(vbox, info)

	_group(vbox, "DONE — %d" % done.size(), _GameTheme.ACID)
	if done.is_empty():
		_empty(vbox, "Empty. Everyone's log starts here; most of them stay here.")
	for info: Dictionary in done:
		_done_card(vbox, info)

	_GameTheme.stagger_rows(vbox, 0.03, 0.06)

# ------------------------------------------------------------------- cards ----

func _active_card(parent: Node, info: Dictionary) -> void:
	var vb := _card(parent, _GameTheme.CYAN)
	_row(vb, "▸  %s" % str(info.get("name", "?")), 17, _GameTheme.WHITE_HOT, true)
	_row(vb, str(info.get("description", "")), 13, _GameTheme.TEXT_DIM)
	var flavour := str(QUEST_FLAVOUR.get(str(info.get("id", "")), ""))
	if flavour != "":
		_row(vb, flavour, 12, _GameTheme.with_alpha(_GameTheme.VIOLET, 0.85))
	var progress: Dictionary = info.get("progress", {})
	for obj in info.get("objectives", []):
		if not (obj is Dictionary):
			continue
		var od: Dictionary = obj
		var prog := int(progress.get(str(od.get("id", "")), 0))
		var need := int(od.get("count", 1))
		var checked := prog >= need
		var mark := "☑" if checked else "☐"
		var count_txt := "" if need <= 1 else ("   %d / %d" % [prog, need])
		var body := str(od.get("text", od.get("id", "?")))
		_row(vb, "   %s %s%s" % [mark, body, count_txt],
			14, _GameTheme.ACID if checked else _GameTheme.TEXT)
	_row(vb, "NEXT:  %s" % _next_step(info), 14, _GameTheme.AMBER)

func _available_card(parent: Node, info: Dictionary) -> void:
	var vb := _card(parent, _GameTheme.AMBER)
	_row(vb, "◆  %s" % str(info.get("name", "?")), 16, _GameTheme.TEXT, true)
	_row(vb, str(info.get("description", "")), 13, _GameTheme.TEXT_DIM)
	_row(vb, "FROM:  %s" % _giver_line(info), 14, _GameTheme.AMBER)

func _done_card(parent: Node, info: Dictionary) -> void:
	var vb := _card(parent, _GameTheme.ACID)
	_row(vb, "✔  %s" % str(info.get("name", "?")), 15, _GameTheme.with_alpha(_GameTheme.ACID, 0.75), true)
	var flavour := str(QUEST_FLAVOUR.get(str(info.get("id", "")), ""))
	if flavour != "":
		_row(vb, flavour, 12, _GameTheme.with_alpha(_GameTheme.TEXT_DIM, 0.7))

func _card(parent: Node, accent: Color) -> VBoxContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _GameTheme.glass_box(accent, 10.0))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	card.add_child(vb)
	return vb

func _group(parent: Node, text: String, accent: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", accent)
	l.add_theme_font_override("font", _GameTheme.spaced_font(3))
	parent.add_child(l)

func _empty(parent: Node, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(700, 0)
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", _GameTheme.with_alpha(_GameTheme.TEXT_DIM, 0.8))
	parent.add_child(l)

func _row(parent: Node, text: String, size: int, col: Color, heading := false) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(690, 0)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if heading:
		l.add_theme_font_override("font", _GameTheme.spaced_font(2))
	parent.add_child(l)

# ------------------------------------------------------------ teaching bits ----

## The single physical action that advances this quest, phrased as an order.
func _next_step(info: Dictionary) -> String:
	var progress: Dictionary = info.get("progress", {})
	var region := str(info.get("region", GameManager.current_region))
	for obj in info.get("objectives", []):
		if not (obj is Dictionary):
			continue
		var od: Dictionary = obj
		var prog := int(progress.get(str(od.get("id", "")), 0))
		var need := int(od.get("count", 1))
		if prog < need:
			return _step_text(od, prog, need, region)
	return "Everything's ticked. It should close itself; if not, that's a bug and you know whose."

func _step_text(od: Dictionary, prog: int, need: int, region: String) -> String:
	var kind := str(od.get("type", ""))
	var target := str(od.get("target", ""))
	var here := GameManager.current_region == region
	var place := _place(region)
	match kind:
		"talk":
			return "Find %s %s and press [E]." % [DialogueManager.get_npc_name(target), place]
		"interact":
			return "Walk onto %s %s and press [E]." % [
				str(PROP_NAMES.get(target, "the %s" % target.replace("_", " "))), place]
		"visit":
			if GameManager.current_region == target:
				return "You're standing in it. Take a few steps; it'll tick."
			if GameManager.is_region_unlocked(target):
				return "Travel to %s — press [M], or walk into the portal." % _region_name(target)
			return "%s is still locked. It unlocks as a quest reward; clear what's active." % _region_name(target)
		"collect_tokens":
			return "Collect %d more tokens — the gold pickups on the floor, plus whatever enemies drop." % (need - prog)
		"defeat":
			return "Defeat %d more %s %s. [1] Prompt Blast, [Shift] to dash out." % [
				need - prog, str(ENEMY_NAMES.get(target, target.replace("_", " ").capitalize())), place]
	# "story" beats and anything new: point at the room and the interact key.
	if here:
		return "It plays out right here — look for a prop showing an [E] prompt."
	return "It plays out in %s. Press [M] and travel there." % _region_name(region)

func _giver_line(info: Dictionary) -> String:
	var qid := str(info.get("id", ""))
	var giver := str(info.get("giver", FALLBACK_GIVERS.get(qid, "")))
	var region := str(info.get("region", "localhost"))
	var who := DialogueManager.get_npc_name(giver) if giver != "" else "whoever's standing there"
	if not GameManager.is_region_unlocked(region):
		return "%s, in %s — region still locked, so this one waits its turn." % [who, _region_name(region)]
	if GameManager.current_region == region:
		return "%s, in this region — look for the floating gold [!] and press [E]." % who
	return "%s, in %s — press [M] to travel, then press [E] on them." % [who, _region_name(region)]

func _place(region: String) -> String:
	if GameManager.current_region == region:
		return "here in %s" % _region_name(region)
	return "in %s ([M] to travel)" % _region_name(region)

func _region_name(region_id: String) -> String:
	return str(REGION_NAMES.get(region_id, region_id.replace("_", " ").capitalize()))

func _prereqs_met(info: Dictionary) -> bool:
	if QuestManager.is_completed(str(info.get("id", ""))):
		return false
	for p in info.get("prerequisites", []):
		if str(p) not in QuestManager.completed_quests:
			return false
	return true
