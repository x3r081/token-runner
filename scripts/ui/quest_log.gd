extends PanelContainer
## The quest log's job is CLARITY: ACTIVE / AVAILABLE / DONE, live objective
## checkboxes with counts, WHO hands out an available quest and WHERE they are
## standing, and a "next step" line that names an actual key or place.
##
## Round 6 removed the cards. Every quest used to sit in its own glass panel with
## its own accent glow — cyan for active, amber for available, acid for done —
## inside a panel, inside a scrim: boxes around boxes around boxes, in four hues.
## Now the log is a typeset list. Hierarchy comes from indentation, one accent on
## the quest you are actually doing, and whitespace.

const _GameTheme = preload("res://scripts/ui/game_theme.gd")
const _Modal = preload("res://scripts/ui/modal_panel.gd")

## Measure for the wrapping body copy inside an 880-wide panel.
const MEASURE := 740.0

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
	"prop_lockfile": "the package-lock.json",
	"prop_node_modules": "the node_modules drift",
	"prop_leftpad": "the left-pad marker",
	"prop_kanban": "the Kanban board",
	"prop_rig": "the mining rig",
	"prop_fan": "the cooling fan",
}

## One line per quest, shown only on the quest you are currently doing. It used
## to ride along on every card in every section, three times over.
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
	"supply_chain": "Eleven lines of code, one unpaid weekend, and every build on Earth.",
	"scope_control": "Nobody added the work. It arrived, gradually, while everyone agreed.",
	"thermal_shift": "94 degrees, held together with zip ties and a cone in the asset register.",
}

## Quest names that are jokes instead of names.
##
## "TODO: Everything" is funny in body copy and useless as the HEADLINE of the
## thing you are currently doing. The informative half leads and the gag keeps
## its seat. These MUST stay identical to hud.gd's QUEST_HEADLINE_NAMES.
const TITLE_OVERRIDES := {
	"hello_localhost": "First Sprint — TODO: Everything",
}

func _ready() -> void:
	theme = _GameTheme.create()
	add_theme_stylebox_override("panel", _Modal.modal_box(_GameTheme.CYAN, 6.0))
	_Modal.attach_scrim(self)
	offset_left = -440.0
	offset_right = 440.0
	_Modal.place_centred(self, 720.0)
	($Margin/VBox/Scroll as ScrollContainer).custom_minimum_size = Vector2(0, 420)
	var title: Label = $Margin/VBox/Title
	title.add_theme_font_size_override("font_size", _Modal.HEADING)
	title.add_theme_color_override("font_color", _GameTheme.CYAN)
	var sub: Label = $Margin/VBox/Subtitle
	sub.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	sub.add_theme_font_size_override("font_size", _Modal.SMALL)
	var footer: Label = $Margin/VBox/Footer
	footer.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	footer.add_theme_font_size_override("font_size", _Modal.SMALL)
	_GameTheme.style_button($Margin/VBox/CloseBtn, _GameTheme.TEXT_DIM, _Modal.SMALL)
	_populate()
	_GameTheme.open_panel(self)
	$Margin/VBox/CloseBtn.pressed.connect(queue_free)

func _populate() -> void:
	var vbox: VBoxContainer = $Margin/VBox/Scroll/QuestList
	for c in vbox.get_children():
		vbox.remove_child(c)
		c.queue_free()
	vbox.add_theme_constant_override("separation", 10)

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

	_group(vbox, "ACTIVE — %d" % active.size(), _GameTheme.TEXT_DIM)
	if active.is_empty():
		_empty(vbox, "Nothing active. Find a floating gold [!] and press [E].")
	for info: Dictionary in active:
		_active_card(vbox, info)

	_group(vbox, "AVAILABLE — %d" % available.size(), _GameTheme.TEXT_DIM)
	if available.is_empty():
		_empty(vbox, "Nothing on offer. New work unlocks from finished work.")
	for info: Dictionary in available:
		_available_card(vbox, info)

	_group(vbox, "DONE — %d" % done.size(), _GameTheme.TEXT_DIM)
	if done.is_empty():
		_empty(vbox, "Empty. Most logs stay here.")
	for info: Dictionary in done:
		_done_card(vbox, info)

	_Modal.reveal_rows(vbox)

# ------------------------------------------------------------------- cards ----

func _active_card(parent: Node, info: Dictionary) -> void:
	var vb := _card(parent, _GameTheme.CYAN)
	# The one accent in the log: the quest you are actually on.
	_row(vb, _headline(info), _Modal.BODY, _GameTheme.CYAN)
	var ticket := _ticket_name(info)
	if ticket != "":
		_row(vb, '   ticket: "%s"' % ticket, _Modal.SMALL, _GameTheme.TEXT_DIM)
	_row(vb, str(info.get("description", "")), _Modal.SMALL, _GameTheme.TEXT)
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
			_Modal.SMALL, _GameTheme.TEXT_DIM if checked else _GameTheme.TEXT)
	_row(vb, "Next:  %s" % _next_step(info), _Modal.SMALL, _GameTheme.TEXT)
	# One dry line, on the quest you are doing and nowhere else.
	var flavour := str(QUEST_FLAVOUR.get(str(info.get("id", "")), ""))
	if flavour != "":
		_row(vb, flavour, _Modal.SMALL, _GameTheme.TEXT_DIM)

func _available_card(parent: Node, info: Dictionary) -> void:
	var vb := _card(parent, _GameTheme.TEXT)
	_row(vb, _headline(info), _Modal.BODY, _GameTheme.TEXT)
	_row(vb, "From:  %s" % _giver_line(info), _Modal.SMALL, _GameTheme.TEXT_DIM)

func _done_card(parent: Node, info: Dictionary) -> void:
	var vb := _card(parent, _GameTheme.TEXT_DIM)
	_row(vb, "✔  %s" % _headline(info), _Modal.SMALL, _GameTheme.TEXT_DIM)

## A quest block. No panel, no border, no glow: a VBox and the whitespace around
## it. `_accent` is kept so callers read as before; the block has no colour of
## its own — the rows inside decide what is loud.
func _card(parent: Node, _accent: Color) -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(vb)
	return vb

func _group(parent: Node, text: String, accent: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", _Modal.SMALL)
	l.add_theme_color_override("font_color", accent)
	parent.add_child(l)

func _empty(parent: Node, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(MEASURE, 0)
	l.add_theme_font_size_override("font_size", _Modal.SMALL)
	l.add_theme_color_override("font_color", _GameTheme.TEXT_DIM)
	parent.add_child(l)

func _row(parent: Node, text: String, size: int, col: Color) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(MEASURE, 0)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	parent.add_child(l)

# ------------------------------------------------------------ quest naming ----

## The name shown as the block's headline: the override where one exists,
## otherwise whatever the quest JSON calls itself.
func _headline(info: Dictionary) -> String:
	var qid := str(info.get("id", ""))
	var over := str(TITLE_OVERRIDES.get(qid, ""))
	if over != "":
		return over
	return str(info.get("name", "?"))

## The authored JSON name, printed as a ticket line under the headline so the gag
## survives being demoted — but only when the override actually dropped it.
func _ticket_name(info: Dictionary) -> String:
	var qid := str(info.get("id", ""))
	if not TITLE_OVERRIDES.has(qid):
		return ""
	var authored := str(info.get("name", ""))
	if authored == "" or _headline(info).findn(authored) != -1:
		return ""
	return authored

# ------------------------------------------------------------ teaching bits ----

## The single physical action that advances this quest, phrased as an order.
func _next_step(info: Dictionary) -> String:
	var progress: Dictionary = info.get("progress", {})
	var qid := str(info.get("id", ""))
	var fallback := str(info.get("region", GameManager.current_region))
	for obj in info.get("objectives", []):
		if not (obj is Dictionary):
			continue
		var od: Dictionary = obj
		var prog := int(progress.get(str(od.get("id", "")), 0))
		var need := int(od.get("count", 1))
		if prog < need:
			# Per OBJECTIVE, not per quest: the quest's region is where the giver
			# stands. THE INFINITE CONTEXT's quest is given in Cloud District and
			# the boss is only ever in the Token Vault, so a quest-level region
			# here would print "travel to Cloud District" and strand the player.
			var region := QuestManager.objective_region(qid, od)
			if region == "":
				region = fallback
			return _step_text(od, prog, need, region)
	return "All ticked. It should close itself."

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
				return "You're standing in it. Take a few steps."
			if GameManager.is_region_unlocked(target):
				return "Travel to %s — press [M], or walk into the portal." % _region_name(target)
			return "%s is still locked; it unlocks as a quest reward." % _region_name(target)
		"collect_tokens":
			return "Collect %d more tokens — gold pickups, plus enemy drops." % (need - prog)
		"defeat":
			return "Defeat %d more %s %s. [1] blasts, [Shift] dashes out." % [
				need - prog, str(ENEMY_NAMES.get(target, target.replace("_", " ").capitalize())), place]
	# "story" beats and anything new: point at the room and the interact key.
	if here:
		return "It plays out right here — look for a prop with an [E] prompt."
	return "It plays out in %s. Press [M] and travel there." % _region_name(region)

func _giver_line(info: Dictionary) -> String:
	var qid := str(info.get("id", ""))
	var giver := str(info.get("giver", FALLBACK_GIVERS.get(qid, "")))
	var region := str(info.get("region", "localhost"))
	var who := DialogueManager.get_npc_name(giver) if giver != "" else "whoever's standing there"
	if not GameManager.is_region_unlocked(region):
		return "%s, in %s — region still locked." % [who, _region_name(region)]
	if GameManager.current_region == region:
		return "%s, in this region — look for the gold [!]." % who
	return "%s, in %s — press [M] to travel." % [who, _region_name(region)]

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
