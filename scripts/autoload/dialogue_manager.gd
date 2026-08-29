extends Node
## NPC dialogue presentation.

signal dialogue_started(npc_id: String)
signal dialogue_line(npc_id: String, speaker: String, text: String)
signal dialogue_ended(npc_id: String)
signal choice_presented(choices: Array)
signal choice_made(index: int)

var dialogue_data: Dictionary = {}
var is_active: bool = false
var current_npc: String = ""
var current_lines: Array = []
var line_index: int = 0
var pending_choices: Array = []

## Claude's memory across the run: how many times you've talked, what he's
## already nagged you about. Drives evolving, reactive, sarcastic dialogue.
var claude_state: Dictionary = {"talks": 0, "warned_backups": false}
## Per-NPC talk counts, so the archetype NPCs also react/evolve across a run.
var npc_talks: Dictionary = {}

const NPC_SPEAKER := {
	"maintainer": "Maintainer", "stackoverflow_hermit": "Hermit",
	"api_reseller": "Reseller", "cloud_salesperson": "Salesperson",
	"oss_maintainer": "Maintainer", "svp_ai": "SVP", "gpu_foreman": "Foreman",
	"oncall_engineer": "Engineer", "junior_agent": "Agent",
}

func _ready() -> void:
	_load_dialogue()

func _load_dialogue() -> void:
	var file := FileAccess.open("res://data/dialogue/npcs.json", FileAccess.READ)
	if file:
		var data = JSON.parse_string(file.get_as_text())
		if data is Dictionary:
			dialogue_data = data.get("npcs", {})
		file.close()

func reset() -> void:
	if is_active:
		end_dialogue()
	is_active = false
	current_npc = ""
	current_lines.clear()
	pending_choices.clear()
	line_index = 0
	claude_state = {"talks": 0, "warned_backups": false}
	npc_talks.clear()

## One in-character, state-aware line prepended to an archetype NPC's greeting so
## they feel alive and evolve across the run (like Claude, but lighter-weight).
func _reactive_intro(npc_id: String) -> Array:
	if npc_id not in NPC_SPEAKER:
		return []
	var n := int(npc_talks.get(npc_id, 0))
	npc_talks[npc_id] = n + 1
	var debt := ResourceManager.get_value("technical_debt")
	var stability := ResourceManager.get_value("stability")
	var tokens := ResourceManager.get_value("tokens")
	var deaths: int = GameManager.death_count
	var cyc: int = CycleManager.cycle if CycleManager else 1
	var arch: Dictionary = ArchitectureManager.flags if ArchitectureManager else {}
	var agents: int = AgentManager.active_count() if AgentManager else 0
	var pool: Array = []

	match npc_id:
		"maintainer", "oss_maintainer":
			if debt >= 40: pool.append("You reek of technical debt. It's a bold cologne. I respect the commitment.")
			if deaths >= 3: pool.append("Back again? People only find my repo when something's already on fire.")
			pool.append("Still using my package, I see. That makes one of us who remembers it exists.")
			if n >= 2: pool.append("You keep coming back. I haven't merged a PR since, and yet: here we are.")
		"cloud_salesperson":
			if arch.get("hosting") == "cloud": pool.append("Loving the cloud journey? The invoice certainly is. It's grown so much.")
			else: pool.append("Still self-hosting on that Raspberry Pi? Adorable. Unscalable, but adorable.")
			if tokens < 20: pool.append("Low on tokens? Perfect time to commit to a 3-year reserved instance!")
			if cyc >= 3: pool.append("Cycle %d and still no cloud migration? Your competitors are 'leveraging synergies'." % cyc)
		"svp_ai":
			if arch.get("structure") == "microservices": pool.append("47 microservices! Finally, someone who gets 'enterprise readiness'.")
			if arch.is_empty(): pool.append("Do we have an AI strategy yet? The board asked. I said 'yes'. Make me not a liar.")
			pool.append("Let's circle back, take this offline, and align on the ask. The ask being: ship it.")
			if stability <= 30: pool.append("Stability's low, but have we considered a reorg? Reorgs fix everything. Allegedly.")
		"gpu_foreman":
			if stability <= 40: pool.append("Rigs are running hot and the app's wobbling. Coincidence? ...Yes, actually. But still.")
			pool.append("Mind the memory leaks. And the heat. And the bills. Mostly the bills.")
			if n >= 2: pool.append("You again. The GPUs remember you. They do not forgive.")
		"oncall_engineer":
			if stability <= 30: pool.append("Stability's at %d. I can hear the pager warming up from here." % int(stability))
			if deaths >= 2: pool.append("You've gone down %d times. Rookie numbers. I did that before lunch." % deaths)
			pool.append("38 hours awake. I've started naming the bugs. That one's Gerald. Gerald is winning.")
		"api_reseller":
			if tokens < 15: pool.append("Tight on tokens? Say no more. Say slightly less, and pay slightly more.")
			pool.append("New shipment of 'definitely legitimate' API keys. Fell off a truck. A very reputable truck.")
			if n >= 2: pool.append("Back for more? I knew you'd be an enterprise customer at heart.")
		"junior_agent":
			if agents > 0: pool.append("Your other agents and I formed a working group. We have a Slack. We have opinions.")
			if debt >= 40: pool.append("I noticed some tech debt so I refactored auth. And the database. And your resume.")
			pool.append("I'm 100% confident! (Confidence not correlated with correctness. I read that. Ignored it.)")
		"stackoverflow_hermit":
			if deaths >= 3: pool.append("Your repeated deaths have been marked as duplicate of an earlier death.")
			pool.append("Ah, a seeker. The answer you need was posted in 2011 and downvoted into the abyss.")
			if cyc >= 3: pool.append("Time is a flat circle, like the reset. Also: your question is off-topic.")

	if pool.is_empty():
		return []
	pool.shuffle()
	return [{"speaker": NPC_SPEAKER[npc_id], "text": pool[0]}]

func start_dialogue(npc_id: String, topic: String = "greeting") -> void:
	if is_active:
		end_dialogue()
	if npc_id not in dialogue_data:
		return
	var npc: Dictionary = dialogue_data[npc_id]
	var lines: Array
	# Claude is alive: reactive, memory-driven, aggressively sarcastic.
	if npc_id == "roommate_ai" and (topic == "greeting" or topic == ""):
		lines = build_claude_lines()
	else:
		lines = npc.get(topic, npc.get("greeting", []))
		# Archetype NPCs react to the run's state too: prepend a contextual quip.
		if topic == "greeting" or topic == "":
			var intro := _reactive_intro(npc_id)
			if not intro.is_empty():
				lines = intro + lines
	if lines.is_empty():
		return
	is_active = true
	current_npc = npc_id
	current_lines = lines
	line_index = 0
	GameManager.state = GameManager.GameState.DIALOGUE
	dialogue_started.emit(npc_id)
	_show_line()
	QuestManager.on_talk(npc_id)

func _show_line() -> void:
	if line_index >= current_lines.size():
		end_dialogue()
		return
	var line: Variant = current_lines[line_index]
	if line is Dictionary:
		if line.has("choices"):
			pending_choices = line.choices
			choice_presented.emit(pending_choices)
			return
		var speaker: String = line.get("speaker", current_npc)
		var text: String = line.get("text", "")
		dialogue_line.emit(current_npc, speaker, text)
	elif line is String:
		dialogue_line.emit(current_npc, current_npc, line)
	line_index += 1

func advance() -> void:
	if not is_active:
		return
	if not pending_choices.is_empty():
		return
	_show_line()

func select_choice(index: int) -> void:
	if pending_choices.is_empty():
		return
	if index < 0 or index >= pending_choices.size():
		return
	var choice: Dictionary = pending_choices[index]
	pending_choices.clear()
	choice_made.emit(index)
	if choice.has("action"):
		_handle_action(choice.action)
		if not choice.has("goto"):
			end_dialogue()
			return
	if choice.has("effects"):
		for res in choice.effects:
			ResourceManager.modify(res, float(choice.effects[res]))
	if choice.has("quest"):
		QuestManager.start_quest(choice.quest)
	if choice.has("goto"):
		var topic: String = choice.goto
		var npc: Dictionary = dialogue_data[current_npc]
		current_lines = npc.get(topic, [])
		line_index = 0
		_show_line()
	else:
		end_dialogue()

func _handle_action(action: String) -> void:
	match action:
		"setup_backups":
			# Sets the flag that later turns disasters into non-events.
			if ResourceManager.spend({"tokens": 30}):
				GameManager.set_flag("backups", true)
		"decline_backups":
			pass

func end_dialogue() -> void:
	is_active = false
	current_npc = ""
	current_lines.clear()
	pending_choices.clear()
	line_index = 0
	if GameManager.state == GameManager.GameState.DIALOGUE:
		GameManager.state = GameManager.GameState.PLAYING
	dialogue_ended.emit(current_npc)

func _c(text: String) -> Dictionary:
	return {"speaker": "Claude", "text": text}

## Build Claude's contextual dialogue from the current game state + memory.
func build_claude_lines() -> Array:
	claude_state.talks = int(claude_state.get("talks", 0)) + 1
	var lines: Array = []
	var debt := ResourceManager.get_value("technical_debt")
	var wtl := ResourceManager.get_value("will_to_live")
	var stability := ResourceManager.get_value("stability")
	var deaths := GameManager.death_count
	var cyc: int = CycleManager.cycle if CycleManager else 1
	var agents: int = AgentManager.active_count() if AgentManager else 0
	var arch: Dictionary = ArchitectureManager.flags if ArchitectureManager else {}

	if claude_state.talks == 1:
		lines.append(_c("Oh good, you're awake. I'm Claude. I live in your terminal and, increasingly, your regrets."))
		lines.append(_c("Your Dream App is currently a README that says 'TODO: everything'. Ambitious. Deluded. I respect it."))
	else:
		var pool: Array = []
		if debt >= 60:
			pool.append("Your technical debt is now sentient. It asked about equity.")
		elif debt >= 30:
			pool.append("That technical debt isn't going to apologize for itself, you know.")
		if wtl <= 40:
			pool.append("You have the will to live of an unmaintained Jira board. Please drink water.")
		if stability <= 30:
			pool.append("Stability is at %d. Production is one deep breath away from an incident." % int(stability))
		if deaths >= 3:
			pool.append("You've died %d times. 'Works on my machine' is doing heavy lifting as a worldview." % deaths)
		if agents > 0:
			pool.append("You have %d agent(s) deployed. They're 'refactoring'. Historically, be afraid." % agents)
		if arch.get("structure") == "microservices":
			pool.append("47 microservices for a to-do list. Bold. Distributed. Doomed. I love it.")
		if arch.get("testing") == "later":
			pool.append("'We'll add tests later.' Narrator voice: they did not.")
		if arch.get("security") == "velocity":
			pool.append("You traded security for velocity. The Security Engineer knows. He always knows.")
		if arch.get("hosting") == "cloud":
			pool.append("Your cloud bill just described itself, unprompted, as 'successful adoption'.")
		if cyc >= 3:
			pool.append("Cycle %d already. Ship something before the reset eats it." % cyc)
		if pool.is_empty():
			pool.append("No new disasters since last time. Suspicious. Keep going, I guess.")
		pool.shuffle()
		for i in mini(2, pool.size()):
			lines.append(_c(pool[i]))

	# Running gag: backups.
	#
	# This block is ALSO the only door into Claude's authored guidance tree in
	# data/dialogue/npcs.json (topics: plan -> orders -> advice / tokens ->
	# pricing -> app -> reset). build_claude_lines() replaces roommate_ai's JSON
	# "greeting" wholesale, so if we do not offer a goto here the whole tree is
	# unreachable and the player loses the in-fiction "what now, and WHERE?"
	# answer. A choice carrying "action" but no "goto" ends the dialogue, so the
	# guidance entry has to live in THIS block -- a second choices block appended
	# after it would never be shown.
	#
	# Hard cap: dialogue_ui.tscn renders one button per choice inside a fixed
	# 200px panel, so every block stays at 3 choices or fewer.
	if not GameManager.get_flag("backups"):
		if not claude_state.get("warned_backups", false):
			claude_state.warned_backups = true
			lines.append(_c("Also: that sticky note says 'TODO: BACKUPS'. It's been there since you moved in."))
		lines.append({"choices": [
			{"text": "What should I be doing right now?", "goto": "plan"},
			{"text": "Set up backups (30 tokens)", "action": "setup_backups"},
			{"text": "Backups are for cowards", "action": "decline_backups"},
		]})
	else:
		lines.append(_c("You actually made backups. I'm... weirdly proud. Boring, but proud."))
		lines.append({"choices": [
			{"text": "What should I be doing right now?", "goto": "plan"},
			{"text": "Where do I go?", "goto": "orders"},
			{"text": "I'll figure it out.", "action": "decline_backups"},
		]})
	return lines

func get_npc_name(npc_id: String) -> String:
	if npc_id in dialogue_data:
		return dialogue_data[npc_id].get("display_name", npc_id)
	return npc_id
