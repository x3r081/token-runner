extends Node
## NPC dialogue presentation.
##
## Two things live here that are easy to break, so read this before editing:
##
## 1. REACHABILITY. `build_claude_lines()` REPLACES roommate_ai's authored JSON
##    greeting, and that greeting is the only door into the plan -> orders ->
##    advice / tokens -> pricing -> app -> reset guidance tree. Every code path
##    out of this file must therefore still offer a `goto: "plan"` choice, or
##    the player loses the in-fiction answer to "what now, and WHERE?".
##    A choice carrying `action` but no `goto` ENDS the dialogue, so the
##    guidance entry has to live in the same choices block, not a later one.
##
## 2. THE 3-CHOICE CAP. dialogue_ui.tscn renders one button per choice inside a
##    fixed-height panel. Never emit a block with more than three.
##
## Everything else here exists to make NPCs feel like they have been watching
## this run happen: `_reactive_intro()` gives every archetype a state-aware
## opening line, and Claude gets a full memory (talks, what he has already
## nagged about, and what changed since you last spoke).

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
## already nagged you about, and a snapshot of the run taken at the end of every
## conversation so the next one can open with what changed while he waited.
var claude_state: Dictionary = {"talks": 0, "warned_backups": false}
## Per-NPC talk counts, so the archetype NPCs also react/evolve across a run.
var npc_talks: Dictionary = {}

const NPC_SPEAKER := {
	"maintainer": "Maintainer", "stackoverflow_hermit": "Hermit",
	"api_reseller": "Reseller", "cloud_salesperson": "Salesperson",
	"oss_maintainer": "Maintainer", "svp_ai": "SVP", "gpu_foreman": "Foreman",
	"oncall_engineer": "Engineer", "junior_agent": "Agent",
}

# Priority tiers for the weighted line picker. Gaps are wider than the jitter in
# `_weighted()`, so the single most relevant line in a given state always wins.
const W_CRITICAL := 100   # the run is actively on fire
const W_STRONG := 80      # a specific, damning fact about this run
const W_STATE := 62       # a mild state observation
const W_EVOLVE := 44      # "we have done this before" escalation
const W_FLAVOR := 26      # in-character filler, always true of the industry

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
	# REASSIGN, never clear(). `current_lines` and `pending_choices` are handed
	# out as references INTO dialogue_data (see start_dialogue / _show_line), so
	# clear() would empty that NPC's topic — or that line's choice list — inside
	# the loaded JSON, permanently, for the rest of the run.
	current_lines = []
	pending_choices = []
	line_index = 0
	claude_state = {"talks": 0, "warned_backups": false}
	npc_talks.clear()

# ------------------------------------------------------------ line selection --

## Deal `count` lines from a weighted pool of `{"w": int, "t": String}` entries.
## Ordering is by priority with a small random jitter: variety between runs,
## without ever burying the one line that describes the disaster in progress.
func _weighted(pool: Array, count: int) -> Array[String]:
	for e: Dictionary in pool:
		e["_r"] = float(e.get("w", W_FLAVOR)) + randf() * 6.0
	pool.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("_r", 0.0)) > float(b.get("_r", 0.0)))
	var out: Array[String] = []
	for i in mini(count, pool.size()):
		out.append(String(pool[i].get("t", "")))
	return out

func _w(pool: Array, weight: int, text: String) -> void:
	pool.append({"w": weight, "t": text})

## One in-character, state-aware line prepended to an archetype NPC's greeting so
## they feel alive and evolve across the run (like Claude, but lighter-weight).
## ALWAYS returns exactly one line for a known archetype, and nothing at all for
## anyone else — callers splice the result straight onto the JSON greeting.
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
	var ridiculous: int = ArchitectureManager.ridiculousness if ArchitectureManager else 0
	var agents: int = AgentManager.active_count() if AgentManager else 0
	var quests_done: int = QuestManager.completed_quests.size()
	var shippable: bool = DreamAppManager.can_ship()
	var pool: Array = []

	match npc_id:
		"maintainer", "oss_maintainer":
			if debt >= 40: _w(pool, W_STRONG, "You reek of technical debt. It's a bold cologne. I respect the commitment.")
			if deaths >= 3: _w(pool, W_STATE, "Back again? People only find my repo when something's already on fire.")
			if quests_done >= 3: _w(pool, W_STATE, "You've actually finished things tonight. %d of them. That's %d more than my roadmap." % [quests_done, quests_done])
			_w(pool, W_FLAVOR, "Still using my package, I see. That makes one of us who remembers it exists.")
			_w(pool, W_FLAVOR, "Eleven years, forty million downloads a month, and one (1) folding chair. Ask me anything.")
			if n >= 2: _w(pool, W_EVOLVE, "You keep coming back. I haven't merged a PR since, and yet: here we are.")
			if n >= 4: _w(pool, W_EVOLVE, "At this point you've visited me more than the three companies that ship this in production.")
		"cloud_salesperson":
			if arch.get("hosting") == "cloud": _w(pool, 95, "Loving the cloud journey? The invoice certainly is. It's grown so much.")
			else: _w(pool, W_STRONG, "Still self-hosting on that Raspberry Pi? Adorable. Unscalable, but adorable.")
			if tokens < 20: _w(pool, W_STATE, "Low on tokens? Perfect time to commit to a 3-year reserved instance!")
			if cyc >= 3: _w(pool, W_STATE, "Cycle %d and still no cloud migration? Your competitors are 'leveraging synergies'." % cyc)
			_w(pool, W_FLAVOR, "It's elastic. In which direction? Elastic doesn't specify. That's the elegance.")
			if n >= 2: _w(pool, W_EVOLVE, "I've followed up twice now. That's not persistence, that's a documented process.")
		"svp_ai":
			if arch.get("structure") == "microservices": _w(pool, W_STRONG, "47 microservices! Finally, someone who gets 'enterprise readiness'.")
			if ridiculous >= 3: _w(pool, W_STRONG, "Your architecture is enterprise-grade. I want to be clear that I mean that as a warning.")
			if arch.is_empty(): _w(pool, W_STATE, "Do we have an AI strategy yet? The board asked. I said 'yes'. Make me not a liar.")
			if stability <= 30: _w(pool, W_STATE, "Stability's low, but have we considered a reorg? Reorgs fix everything. Allegedly.")
			if shippable: _w(pool, W_STRONG, "I hear it's shippable. Wonderful. I've already told the board it shipped.")
			_w(pool, W_FLAVOR, "Let's circle back, take this offline, and align on the ask. The ask being: ship it.")
			if n >= 3: _w(pool, W_EVOLVE, "I've now had three meetings with you and could not describe what you do.")
		"gpu_foreman":
			if stability <= 40: _w(pool, W_STRONG, "Rigs are running hot and the app's wobbling. Coincidence? ...Yes, actually. But still.")
			if cyc >= 3: _w(pool, W_STATE, "Cycle %d. Rig four has been at 94 degrees for all of them." % cyc)
			_w(pool, W_FLAVOR, "Mind the memory leaks. And the heat. And the bills. Mostly the bills.")
			_w(pool, W_FLAVOR, "Every problem down here is thermal, structural, or emotional. Same fix: zip tie.")
			if n >= 2: _w(pool, W_EVOLVE, "You again. The GPUs remember you. They do not forgive.")
		"oncall_engineer":
			if stability <= 30: _w(pool, W_CRITICAL, "Stability's at %d. I can hear the pager warming up from here." % int(stability))
			if deaths >= 2: _w(pool, W_STATE, "You've gone down %d times. Rookie numbers. I did that before lunch." % deaths)
			if agents > 0: _w(pool, W_STATE, "Something autonomous is making changes in prod. I've decided not to look.")
			_w(pool, W_FLAVOR, "38 hours awake. I've started naming the bugs. That one's Gerald. Gerald is winning.")
			if n >= 2: _w(pool, W_EVOLVE, "You keep visiting. Nobody visits on-call. This is the nicest thing that's happened this quarter.")
		"api_reseller":
			if tokens < 15: _w(pool, W_STRONG, "Tight on tokens? Say no more. Say slightly less, and pay slightly more.")
			if tokens >= 250: _w(pool, W_STRONG, "%d tokens on you. Let's discuss a bundle. A generous, non-refundable bundle." % int(tokens))
			if cyc >= 2: _w(pool, W_STATE, "Prices updated at the reset. Upward. Market conditions. The market is me.")
			_w(pool, W_FLAVOR, "New shipment of 'definitely legitimate' API keys. Fell off a truck. A very reputable truck.")
			if n >= 2: _w(pool, W_EVOLVE, "Back for more? I knew you'd be an enterprise customer at heart.")
		"junior_agent":
			if agents > 0: _w(pool, W_STRONG, "Your other agents and I formed a working group. We have a Slack. We have opinions.")
			if debt >= 40: _w(pool, W_STRONG, "I noticed some tech debt so I refactored auth. And the database. And your resume.")
			if stability <= 40: _w(pool, W_STATE, "Stability dipped right after my last change. Correlation isn't causation! I looked it up!")
			_w(pool, W_FLAVOR, "I'm 100% confident! (Confidence not correlated with correctness. I read that. Ignored it.)")
			if n >= 2: _w(pool, W_EVOLVE, "You came back! Most people just revoke my credentials.")
		"stackoverflow_hermit":
			if deaths >= 3: _w(pool, W_STRONG, "Your repeated deaths have been marked as duplicate of an earlier death.")
			if cyc >= 3: _w(pool, W_STATE, "Time is a flat circle, like the reset. Also: your question is off-topic.")
			_w(pool, W_FLAVOR, "Ah, a seeker. The answer you need was posted in 2011 and downvoted into the abyss.")
			_w(pool, W_FLAVOR, "The accepted answer still works. It is older than the framework it is answering about.")
			if n >= 2: _w(pool, W_EVOLVE, "You have returned. Your previous visit was closed as 'needs more focus'.")

	if pool.is_empty():
		return []
	var picked := _weighted(pool, 1)
	if picked.is_empty():
		return []
	return [{"speaker": NPC_SPEAKER[npc_id], "text": picked[0]}]

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
	# Shallow copy so nothing downstream can mutate the loaded JSON in place.
	current_lines = lines.duplicate()
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
			pending_choices = (line.choices as Array).duplicate()
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
	# Reassign: this array is the `choices` array inside dialogue_data.
	pending_choices = []
	choice_made.emit(index)
	if choice.has("action"):
		_handle_action(choice.action)
		if not choice.has("goto"):
			end_dialogue()
			return
	if choice.has("effects") and not _apply_effects(choice):
		# Refused: nothing bought, nothing charged, and the NPC says so rather
		# than the conversation silently swallowing the transaction.
		var who: String = dialogue_data.get(current_npc, {}).get("display_name", current_npc)
		current_lines = [{"speaker": who,
			"text": "That is not what you have. The price is the price; the balance is the balance."}]
		line_index = 0
		_show_line()
		return
	if choice.has("achievement"):
		AchievementManager.unlock(choice.achievement)
	for extra in choice.get("achievements", []):
		AchievementManager.unlock(str(extra))
	if choice.has("quest"):
		QuestManager.start_quest(choice.quest)
	if choice.has("goto"):
		var topic: String = choice.goto
		var npc: Dictionary = dialogue_data[current_npc]
		current_lines = (npc.get(topic, []) as Array).duplicate()
		line_index = 0
		_show_line()
	else:
		end_dialogue()

## Currencies you can actually run out of. A NEGATIVE delta on one of these,
## inside a choice that also GRANTS something, is a purchase — and a purchase
## you cannot afford must not go through. ResourceManager.modify() clamps at
## zero, so without this the reseller's 200-token context expansion could be
## bought with 3 tokens, for 3 tokens. Straight penalties (will_to_live,
## reputation, a compute cost with no goods attached) are left exactly as they
## were: they are supposed to land whether you can spare it or not.
const SPENDABLE := ["tokens", "compute", "context", "api_credits", "coffee"]

func _apply_effects(choice: Dictionary) -> bool:
	var eff: Dictionary = choice.get("effects", {})
	if eff.is_empty():
		return true
	var costs := {}
	var grants := false
	for res in eff:
		var v := float(eff[res])
		if v > 0.0:
			grants = true
		elif v < 0.0 and res in SPENDABLE:
			costs[str(res)] = -v
	if grants and not costs.is_empty():
		if not ResourceManager.spend(costs):
			return false
		for res in eff:
			if not costs.has(str(res)):
				ResourceManager.modify(res, float(eff[res]))
		return true
	for res in eff:
		ResourceManager.modify(res, float(eff[res]))
	return true

func _handle_action(action: String) -> void:
	match action:
		"setup_backups":
			# Sets the flag that later turns disasters into non-events.
			if ResourceManager.spend({"tokens": 30}):
				GameManager.set_flag("backups", true)
		"decline_backups":
			pass

func end_dialogue() -> void:
	# `who` is captured BEFORE the reset: dialogue_ended used to fire with
	# current_npc already blanked, so every listener got "".
	var who := current_npc
	is_active = false
	current_npc = ""
	# Reassign, do NOT clear: both arrays alias data inside dialogue_data, and
	# clearing them wiped that NPC's topic (and its choice list) out of the
	# loaded JSON for the rest of the run. Invisible while NPCs were one_shot;
	# fatal now that they are repeatable.
	current_lines = []
	pending_choices = []
	line_index = 0
	if GameManager.state == GameManager.GameState.DIALOGUE:
		GameManager.state = GameManager.GameState.PLAYING
	dialogue_ended.emit(who)

func _c(text: String) -> Dictionary:
	return {"speaker": "Claude", "text": text}

## Build Claude's contextual dialogue from the current game state + memory.
##
## Structure is fixed and load-bearing:
##   [intro or reactive observations]  ->  [optional "since we last spoke"]
##   ->  [backups gag]  ->  [choices block containing the goto into "plan"]
func build_claude_lines() -> Array:
	claude_state.talks = int(claude_state.get("talks", 0)) + 1
	var lines: Array = []
	var debt := ResourceManager.get_value("technical_debt")
	var wtl := ResourceManager.get_value("will_to_live")
	var stability := ResourceManager.get_value("stability")
	var tokens := ResourceManager.get_value("tokens")
	var deaths := GameManager.death_count
	var cyc: int = CycleManager.cycle if CycleManager else 1
	var agents: int = AgentManager.active_count() if AgentManager else 0
	var arch: Dictionary = ArchitectureManager.flags if ArchitectureManager else {}
	var ridiculous: int = ArchitectureManager.ridiculousness if ArchitectureManager else 0
	var tiers := int(DreamAppManager.get_totals().get("total_tiers", 0))

	if claude_state.talks == 1:
		lines.append(_c("Oh good, you're awake. I'm Claude. I live in your terminal and, increasingly, your regrets."))
		lines.append(_c("Your Dream App is currently a README that says 'TODO: everything'. Ambitious. Deluded. I respect it."))
	else:
		var pool: Array = []
		if debt >= 60:
			_w(pool, W_CRITICAL, "Your technical debt is now sentient. It asked about equity.")
		elif debt >= 30:
			_w(pool, W_STRONG, "That technical debt isn't going to apologize for itself, you know.")
		if wtl <= 40:
			_w(pool, W_STRONG, "You have the will to live of an unmaintained Jira board. Please drink water.")
		if stability <= 30:
			_w(pool, W_CRITICAL, "Stability is at %d. Production is one deep breath away from an incident." % int(stability))
		if deaths >= 3:
			_w(pool, W_STRONG, "You've died %d times. 'Works on my machine' is doing heavy lifting as a worldview." % deaths)
		if agents > 0:
			_w(pool, W_STRONG, "You have %d agent(s) deployed. They're 'refactoring'. Historically, be afraid." % agents)
		if arch.get("structure") == "microservices":
			_w(pool, 70, "47 microservices for a to-do list. Bold. Distributed. Doomed. I love it.")
		if arch.get("testing") == "later":
			_w(pool, W_STATE, "'We'll add tests later.' Narrator voice: they did not.")
		if arch.get("security") == "velocity":
			_w(pool, W_STATE, "You traded security for velocity. The Security Engineer knows. He always knows.")
		if arch.get("hosting") == "cloud":
			_w(pool, W_STATE, "Your cloud bill just described itself, unprompted, as 'successful adoption'.")
		if ridiculous >= 4:
			_w(pool, 72, "I diagrammed your architecture. The diagram needs its own architecture.")
		if tiers == 0 and claude_state.talks >= 3:
			_w(pool, 75, "Still zero upgrades bought. [B] opens the Dream App console. It is one key. I've counted.")
		if DreamAppManager.can_ship():
			_w(pool, 78, "It meets the requirements. You could ship it right now and go outside, which I hear still exists.")
		if tokens >= 250:
			_w(pool, W_STATE, "%d tokens, unspent. Hoarding is a strategy the way standing still is a direction." % int(tokens))
		if cyc >= 3:
			_w(pool, W_STATE, "Cycle %d already. Ship something before the reset eats it." % cyc)
		if claude_state.talks >= 6:
			_w(pool, W_EVOLVE, "This is conversation %d. At some point one of us has to write code, and I have no hands." % int(claude_state.talks))
		if pool.is_empty():
			_w(pool, W_FLAVOR, "No new disasters since last time. Suspicious. Keep going, I guess.")
		for l: String in _weighted(pool, 2):
			lines.append(_c(l))
		# The roommate bit: he has been sitting here the whole time, and the first
		# thing he says is what changed while you were gone.
		var since := _since_last_talk(deaths, debt, tokens, tiers)
		if since != "":
			lines.append(_c(since))
	_snapshot(deaths, debt, tokens, tiers)

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

## "Since we last spoke..." — the single most roommate-shaped line in the game.
## Only ever fires when a snapshot from a PREVIOUS conversation exists, so a
## fresh run (or a test poking `talks` directly) never claims a false delta.
func _since_last_talk(deaths: int, debt: float, tokens: float, tiers: int) -> String:
	if not claude_state.has("seen_deaths"):
		return ""
	var d_deaths := deaths - int(claude_state.get("seen_deaths", 0))
	var d_debt := int(debt) - int(claude_state.get("seen_debt", 0))
	var d_tokens := int(tokens) - int(claude_state.get("seen_tokens", 0))
	var d_tiers := tiers - int(claude_state.get("seen_tiers", 0))
	if d_deaths >= 2:
		return "Since we last spoke you have died %d times. I didn't move. Neither did the README." % d_deaths
	if d_deaths == 1:
		return "You died once while you were out there. I heard it. I made no notes, out of respect."
	if d_tiers >= 2:
		return "You bought %d upgrades while you were gone. Look at you, spending money on the actual product." % d_tiers
	if d_debt >= 15:
		return "Technical debt is up %d since we last spoke. Whatever you did out there, it worked, and it will cost us." % d_debt
	if d_tiers == 0 and d_tokens >= 60:
		return "You came back %d tokens richer and zero upgrades wiser. The console is [B]. It has been [B] all night." % d_tokens
	if d_tokens <= -40:
		return "You're down %d tokens and I can't see a single new feature. I'm not accusing. I'm reconciling." % absi(d_tokens)
	return ""

func _snapshot(deaths: int, debt: float, tokens: float, tiers: int) -> void:
	claude_state["seen_deaths"] = deaths
	claude_state["seen_debt"] = int(debt)
	claude_state["seen_tokens"] = int(tokens)
	claude_state["seen_tiers"] = tiers

func get_npc_name(npc_id: String) -> String:
	if npc_id in dialogue_data:
		return dialogue_data[npc_id].get("display_name", npc_id)
	return npc_id
