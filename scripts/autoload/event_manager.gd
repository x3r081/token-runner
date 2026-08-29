extends Node
## Random incidents, world events, and the authored branching sagas.
##
## This is the comedy engine: a joke only counts if it costs or pays something.
## Three systems live here.
##
## 1. RANDOM EVENTS (data/events/random_events.json). Act-gated as before, now
##    also weighted and state-gated, so the world reacts to the run you are
##    actually having: broke players get shaken down, rich players get "pricing
##    simplified", players with four agents get a working group.
##
## 2. SAGAS (scripts/world/story_events.gd). Multi-stage branching scenarios with
##    real failure states. They start themselves on act/cycle gates, so no world
##    builder has to place a prop for them to exist in a run.
##
## 3. RUNNING GAGS with mechanical payoff:
##      - the ninth subscription: a bill that grows at every RESET until cancelled
##      - "it only ever breaks when you feel safe": stability + tokens both high
##        arms an outage, and doing it three times is an achievement
##      - the pager escalation policy, which lists you more times every incident
##      - CALLBACKS: choices are remembered and come back for you cycles later
##
## Nothing here fires while the game is not PLAYING or while a blocking UI is up,
## so headless tests and cutscenes are never interrupted.

signal event_triggered(event_id: String, description: String)
signal event_resolved(event_id: String, choice: int)
## A running gag advanced (subscription renewed, outage armed, callback queued).
## Purely informational — the HUD may surface it, nothing depends on it.
signal running_gag(gag_id: String, note: String)

var event_defs: Array = []
var active_event: Dictionary = {}
var cooldown: float = 0.0
var _rng := RandomNumberGenerator.new()

## Scripted multi-stage storylines (comedy-as-mechanics). Reuses the same popup
## UI as random events by having active_event hold the current stage.
var completed_scripts: Array[String] = []
var _script_id: String = ""
var _script_stages: Array = []
var _script_repeatable: bool = false

## ---------------------------------------------------------------------------
## Run memory. `memory` is what the world knows about you: which way you jumped
## on the Friday deploy, whether the demo rendered a horse, what you did to the
## licence audit. Sagas read it back through recall() to write text that could
## only apply to this run.
## ---------------------------------------------------------------------------
var memory: Dictionary = {}
var _seen_events: Dictionary = {}          # event id -> times fired this run
var _last_event_id: String = ""
var _force_event_id: String = ""
var _pending_callbacks: Array = []         # [{story, cycles, ready}]
var _played_callbacks: Array[String] = []
var _bill: float = 0.0                     # the ninth subscription, in tokens
var _bill_active: bool = false
var _bill_reckoned: bool = false
var _calm_streak: int = 0
var _calm_punished: int = 0
var _escalation: int = 1

## Authored sagas that can start themselves. Gated by act and cycle so the
## absurdity escalates on the schedule COMEDY_BIBLE.md asks for: relatable in
## act 1, existential by act 5.
const SAGAS := [
	{"id": "five_minute_fix", "min_act": 1, "min_cycle": 1, "weight": 1.3},
	{"id": "oncall_pager", "min_act": 2, "min_cycle": 2, "weight": 1.1},
	{"id": "runaway_refactor", "min_act": 2, "min_cycle": 2, "weight": 1.0},
	{"id": "license_audit", "min_act": 3, "min_cycle": 2, "weight": 0.9},
	{"id": "friday_deploy", "min_act": 3, "min_cycle": 3, "weight": 1.2},
	{"id": "stakeholder_demo", "min_act": 4, "min_cycle": 3, "weight": 1.0},
]
const SAGA_CHANCE := 0.38

## Finishing one of these arms a callback: somebody remembers, later, out loud.
const AUTO_CALLBACKS := {
	"tiny_change": {"story": "client_remembers", "cycles": 2},
	"all_hands_demo": {"story": "svp_remembers", "cycles": 2},
	"production_incident": {"story": "svp_remembers", "cycles": 3},
}

## Quest -> gag achievement. Wired here (additively) so quests.json reward keys
## never have to change to give a joke its payoff.
const QUEST_ACHIEVEMENTS := {
	"install_node": "dependency_archaeologist",
	"stackoverflow_pilgrimage": "marked_as_duplicate",
	"one_more_api_call": "one_more_api_call",
	"junior_agent": "escorted_the_agent",
	"license_puzzle": "nine_days_of_noodles",
	"production_down": "we_have_observability_now",
	"ship_dream_app": "deployed_on_friday",
}

## The outage that only ever happens when everything is finally fine.
const CALM_PUNISHERS: Array[String] = [
	"provider_outage", "status_page_still_green", "dns_again", "zero_day",
]

func _ready() -> void:
	_rng.randomize()
	_load_events()
	# CycleManager and AgentManager load AFTER this autoload, so wire up on the
	# next idle frame rather than reaching for singletons that do not exist yet.
	call_deferred("_connect_late")

func _connect_late() -> void:
	var cm := get_node_or_null("/root/CycleManager")
	if cm and cm.has_signal("reset_triggered") and not cm.reset_triggered.is_connected(_on_cycle_reset):
		cm.reset_triggered.connect(_on_cycle_reset)
	var qm := get_node_or_null("/root/QuestManager")
	if qm and qm.has_signal("quest_completed") and not qm.quest_completed.is_connected(_on_quest_completed):
		qm.quest_completed.connect(_on_quest_completed)

func reset() -> void:
	active_event.clear()
	cooldown = 60.0
	completed_scripts.clear()
	_script_id = ""
	_script_stages = []
	_script_repeatable = false
	memory.clear()
	_seen_events.clear()
	_last_event_id = ""
	_force_event_id = ""
	_pending_callbacks.clear()
	_played_callbacks.clear()
	_bill = 0.0
	_bill_active = false
	_bill_reckoned = false
	_calm_streak = 0
	_calm_punished = 0
	_escalation = 1

## Everything a run accumulates that is not a resource: which storylines are
## finished, what the world remembers you doing, the subscription that renews
## itself, and the payoff scenes waiting to land. Without this in the save,
## Continue replayed completed sagas and quietly forgave the bill.
func save_state() -> Dictionary:
	return {
		"completed_scripts": completed_scripts.duplicate(),
		"memory": memory.duplicate(true),
		"seen_events": _seen_events.duplicate(),
		"pending_callbacks": _pending_callbacks.duplicate(true),
		"played_callbacks": _played_callbacks.duplicate(),
		"bill": _bill,
		"bill_active": _bill_active,
		"bill_reckoned": _bill_reckoned,
		"calm_streak": _calm_streak,
		"calm_punished": _calm_punished,
		"escalation": _escalation,
	}

func load_state(d: Dictionary) -> void:
	if d.is_empty():
		return
	completed_scripts.assign(d.get("completed_scripts", []))
	memory = d.get("memory", {}).duplicate(true)
	_seen_events = d.get("seen_events", {}).duplicate()
	_pending_callbacks = (d.get("pending_callbacks", []) as Array).duplicate(true)
	_played_callbacks.assign(d.get("played_callbacks", []))
	_bill = float(d.get("bill", 0.0))
	_bill_active = bool(d.get("bill_active", false))
	_bill_reckoned = bool(d.get("bill_reckoned", false))
	_calm_streak = int(d.get("calm_streak", 0))
	_calm_punished = int(d.get("calm_punished", 0))
	_escalation = int(d.get("escalation", 1))

func _load_events() -> void:
	var file := FileAccess.open("res://data/events/random_events.json", FileAccess.READ)
	if file:
		var data = JSON.parse_string(file.get_as_text())
		if data is Array:
			event_defs = data
		elif data is Dictionary:
			event_defs = data.get("events", [])
		file.close()

func _process(delta: float) -> void:
	if not GameManager or GameManager.state != GameManager.GameState.PLAYING:
		return
	if not active_event.is_empty():
		return
	cooldown -= delta
	if cooldown <= 0:
		cooldown = _rng.randf_range(90.0, 180.0)
		_try_trigger()

func _try_trigger() -> void:
	if UIManager.has_blocking_ui():
		return
	_check_gag_achievements()
	# Authored sagas and callbacks outrank the random pool: they are rarer,
	# longer, and they are the reason anything in this run has consequences.
	if _start_pending_callback():
		return
	if _start_bill_reckoning():
		return
	if _maybe_start_saga():
		return
	var forced := _force_event_id
	_force_event_id = ""
	if forced != "":
		var punisher := _find_event(forced)
		if not punisher.is_empty():
			_calm_punished += 1
			_fire(punisher)
			return
	var eligible := _eligible_events()
	if eligible.is_empty():
		return
	if _rng.randf() > 0.35:
		return
	var ev := _weighted_pick(eligible)
	if ev.is_empty():
		return
	_fire(ev)

func _fire(ev: Dictionary) -> void:
	var id := str(ev.get("id", ""))
	_seen_events[id] = int(_seen_events.get(id, 0)) + 1
	_last_event_id = id
	active_event = ev.duplicate(true)
	event_triggered.emit(id, ev.get("description", ""))

func _find_event(id: String) -> Dictionary:
	for ev in event_defs:
		if str(ev.get("id", "")) == id:
			return ev
	return {}

## Events the current run is allowed to see: act window, one-shot history, the
## optional `require` state gate, and never the same incident twice in a row.
func _eligible_events() -> Array:
	var out: Array = []
	for ev in event_defs:
		var id := str(ev.get("id", ""))
		if int(GameManager.current_act) < int(ev.get("min_act", 1)):
			continue
		if ev.has("max_act") and int(GameManager.current_act) > int(ev.get("max_act", 5)):
			continue
		if ev.get("once", false) and int(_seen_events.get(id, 0)) > 0:
			continue
		if id == _last_event_id and event_defs.size() > 1:
			continue
		if not _meets(ev.get("require", {})):
			continue
		out.append(ev)
	if out.is_empty() and _last_event_id != "":
		# Everything was filtered out by the no-repeat rule; allow a repeat rather
		# than going silently quiet for the rest of the run. The state gate still
		# applies — a broke-player incident must never fire at a rich player.
		for ev in event_defs:
			if int(GameManager.current_act) >= int(ev.get("min_act", 1)) and _meets(ev.get("require", {})):
				out.append(ev)
	return out

## State gate for an event. Every key is optional; an absent key never blocks.
func _meets(req: Dictionary) -> bool:
	if req.is_empty():
		return true
	for key in req:
		var v = req[key]
		match str(key):
			"tokens_min":
				if ResourceManager.get_value("tokens") < float(v): return false
			"tokens_max":
				if ResourceManager.get_value("tokens") > float(v): return false
			"debt_min":
				if ResourceManager.get_value("technical_debt") < float(v): return false
			"debt_max":
				if ResourceManager.get_value("technical_debt") > float(v): return false
			"stability_min":
				if ResourceManager.get_value("stability") < float(v): return false
			"stability_max":
				if ResourceManager.get_value("stability") > float(v): return false
			"will_max":
				if ResourceManager.get_value("will_to_live") > float(v): return false
			"agents_min":
				if _agent_count() < int(v): return false
			"cycle_min":
				if _cycle() < int(v): return false
			"deaths_min":
				if int(GameManager.death_count) < int(v): return false
			"ridiculous_min":
				if _ridiculousness() < int(v): return false
			"flag":
				if not GameManager.get_flag(str(v)): return false
			"not_flag":
				if GameManager.get_flag(str(v)): return false
			"arch":
				if v is Dictionary:
					var flags: Dictionary = ArchitectureManager.flags if ArchitectureManager else {}
					for dk in v:
						if str(flags.get(dk, "")) != str(v[dk]): return false
			"memory":
				if v is Dictionary:
					for mk in v:
						if str(memory.get(mk, "")) != str(v[mk]): return false
			"bill_min":
				if _bill < float(v): return false
	return true

func _weighted_pick(pool: Array) -> Dictionary:
	var total := 0.0
	for ev in pool:
		total += maxf(0.01, float(ev.get("weight", 1.0)))
	if total <= 0.0:
		return {}
	var roll := _rng.randf() * total
	for ev in pool:
		roll -= maxf(0.01, float(ev.get("weight", 1.0)))
		if roll <= 0.0:
			return ev
	return pool[pool.size() - 1]

# ---------------------------------------------------------------------------
# Sagas and callbacks
# ---------------------------------------------------------------------------

func _saga_stages(id: String) -> Array:
	var defs = load("res://scripts/world/story_events.gd")
	if defs == null:
		return []
	return defs.by_id(id)

func _maybe_start_saga() -> bool:
	if _rng.randf() > SAGA_CHANCE:
		return false
	var pool: Array = []
	for s in SAGAS:
		var id := str(s.get("id", ""))
		if id in completed_scripts:
			continue
		if int(GameManager.current_act) < int(s.get("min_act", 1)):
			continue
		if _cycle() < int(s.get("min_cycle", 1)):
			continue
		if not _meets(s.get("require", {})):
			continue
		pool.append(s)
	if pool.is_empty():
		return false
	var pick := _weighted_pick(pool)
	if pick.is_empty():
		return false
	var sid := str(pick.get("id", ""))
	var stages := _saga_stages(sid)
	if stages.is_empty():
		return false
	if sid == "oncall_pager":
		_escalation += 1
	start_scripted(sid, stages)
	return not active_event.is_empty()

func _start_pending_callback() -> bool:
	for i in _pending_callbacks.size():
		var cb: Dictionary = _pending_callbacks[i]
		if not bool(cb.get("ready", false)):
			continue
		var story := str(cb.get("story", ""))
		_pending_callbacks.remove_at(i)
		if story == "" or story in _played_callbacks:
			return false
		var stages := _saga_stages(story)
		if stages.is_empty():
			return false
		_played_callbacks.append(story)
		# Callbacks are one-per-run payoffs, never repeatable, and they must be
		# allowed to fire even if a same-named saga id was completed earlier.
		start_scripted("cb_%s" % story, stages)
		running_gag.emit("callback", story)
		return not active_event.is_empty()
	return false

## The ninth subscription grows until you look at it. Once it hurts, it demands
## a conversation.
func _start_bill_reckoning() -> bool:
	if _bill_reckoned or not _bill_active or _bill < 45.0:
		return false
	var stages := _saga_stages("subscription_reckoning")
	if stages.is_empty():
		return false
	_bill_reckoned = true
	start_scripted("subscription_reckoning", stages)
	return not active_event.is_empty()

## Begin a scripted storyline. Stages are provided by StoryEvents.*.
## Repeatable scripts (e.g. menus) can be reopened and never mark as completed.
func start_scripted(script_id: String, stages: Array, repeatable: bool = false) -> void:
	if not repeatable and script_id in completed_scripts:
		return
	if stages.is_empty() or not active_event.is_empty():
		return
	_script_id = script_id
	_script_stages = stages
	_script_repeatable = repeatable
	active_event = _stage_to_event(0)
	event_triggered.emit(_script_id, active_event.get("description", ""))

func is_script_completed(script_id: String) -> bool:
	return script_id in completed_scripts

func _stage_to_event(i: int) -> Dictionary:
	var s: Dictionary = _script_stages[i]
	return {
		"id": "%s_%d" % [_script_id, i],
		"scripted": true,
		"stage": i,
		"title": s.get("title", "INCIDENT"),
		"description": s.get("description", ""),
		"choices": s.get("choices", [{"text": "Continue", "next": -1}]),
	}

func resolve(choice_index: int) -> void:
	if active_event.is_empty():
		return
	var choices: Array = active_event.get("choices", [])
	if choice_index < 0 or choice_index >= choices.size():
		return
	var choice: Dictionary = choices[choice_index]
	_apply_choice(choice)

	if active_event.get("scripted", false):
		_resolve_scripted(choice)
		return

	event_resolved.emit(active_event.id, choice_index)
	active_event.clear()

## Everything a choice can DO. Resources first, so a choice that pays you can
## also afford the agent it deploys.
func _apply_choice(choice: Dictionary) -> void:
	for res in choice.get("effects", {}):
		if res == "technical_debt":
			ResourceManager.accept_debt(int(choice.effects[res]))
		else:
			ResourceManager.modify(res, float(choice.effects[res]))
	if choice.has("achievement"):
		AchievementManager.unlock(choice.achievement)
	for extra in choice.get("achievements", []):
		AchievementManager.unlock(str(extra))
	if choice.has("deploy_agent"):
		AgentManager.deploy(choice.deploy_agent)
		if _agent_count() >= 4:
			AchievementManager.unlock("middle_management")
	if choice.has("architecture"):
		ArchitectureManager.choose(choice.architecture.decision, choice.architecture.option)
	if choice.has("flag"):
		GameManager.set_flag(str(choice.flag), true)
	if choice.has("remember"):
		for key in choice.remember:
			memory[str(key)] = choice.remember[key]
	if choice.has("bill"):
		_adjust_bill(float(choice.bill))
	if choice.has("time"):
		_adjust_cycle_time(float(choice.time))
	if choice.has("price"):
		_adjust_price(float(choice.price))
	if choice.has("model"):
		ModelManager.set_model(str(choice.model))
	if choice.has("callback"):
		var cb: Dictionary = choice.callback
		schedule_callback(str(cb.get("story", "")), int(cb.get("cycles", 2)))
	if choice.has("start_quest"):
		QuestManager.start_quest(str(choice.start_quest))

func _resolve_scripted(choice: Dictionary) -> void:
	var next_stage: int = _branch(choice)
	if next_stage >= 0 and next_stage < _script_stages.size():
		active_event = _stage_to_event(next_stage)
		event_triggered.emit(_script_id, active_event.get("description", ""))
		return
	# End of storyline: finalize completion + quest chaining.
	if choice.has("complete_quest"):
		var qid: String = choice["complete_quest"]
		if not QuestManager.is_completed(qid):
			if QuestManager.quest_states.get(qid) != QuestManager.QuestState.ACTIVE:
				QuestManager.start_quest(qid)
			QuestManager.complete_quest(qid)
	var finished_id := _script_id
	if not _script_repeatable and finished_id != "" and finished_id not in completed_scripts:
		completed_scripts.append(finished_id)
	_script_id = ""
	_script_stages = []
	_script_repeatable = false
	active_event.clear()
	if AUTO_CALLBACKS.has(finished_id):
		var cb: Dictionary = AUTO_CALLBACKS[finished_id]
		schedule_callback(str(cb.get("story", "")), int(cb.get("cycles", 2)))
	event_resolved.emit(finished_id, 0)

## Which stage a choice leads to. Plain `next` unless the choice carries one of
## the branch verbs, in which case the run's own state picks the ending.
func _branch(choice: Dictionary) -> int:
	var next_stage: int = int(choice.get("next", -1))
	var win := -1
	# "Blame DNS": almost always a joke... except, once in a while, it IS DNS.
	if choice.get("dns_gamble", false):
		win = 1 if _rng.randf() < 0.12 else 0
		if win == 1:
			AchievementManager.unlock("it_was_dns")
			ResourceManager.modify("stability", 20.0)
	# AI diagnosis: reliability depends on the currently selected model. A cheap
	# model is likely to hallucinate a confident, wrong answer.
	elif choice.get("ai_gamble", false):
		win = 1 if _rng.randf() < ModelManager.reliability() else 0
	# Shipping into a wobbly system is a bet against your own stability.
	elif choice.get("stability_gamble", false):
		var p_stab := clampf(ResourceManager.get_value("stability") / 100.0, 0.08, 0.94)
		win = 1 if _rng.randf() < p_stab else 0
	# Debt is interest on being clever at 02:14.
	elif choice.get("debt_gamble", false):
		var p_debt := clampf(1.0 - ResourceManager.get_value("technical_debt") / 120.0, 0.08, 0.94)
		win = 1 if _rng.randf() < p_debt else 0
	# Every autonomous agent you have running is one more thing changing under you.
	elif choice.get("agent_gamble", false):
		var p_agent := clampf(0.9 - float(_agent_count()) * 0.22, 0.08, 0.94)
		win = 1 if _rng.randf() < p_agent else 0
	# Deterministic: did you do the boring responsible thing hours ago?
	elif choice.get("backup_branch", false):
		win = 1 if GameManager.get_flag("backups") else 0
	# Deterministic: are you actually rich, or do you just feel rich?
	elif choice.get("wealth_branch", false):
		win = 1 if ResourceManager.get_value("tokens") >= float(choice.get("rich_at", 500)) else 0
	# Deterministic: your ACTUAL Dream App, in public, with no dice involved.
	elif choice.get("app_gamble", false):
		var totals: Dictionary = DreamAppManager.get_totals()
		var ok := int(totals.get("features", 0)) >= int(choice.get("app_needs", 6))
		ok = ok and ResourceManager.get_value("stability") >= float(choice.get("stability_needs", 50))
		win = 1 if ok else 0
	elif choice.has("chance"):
		win = 1 if _rng.randf() < float(choice.chance) else 0
	if win >= 0:
		next_stage = int(choice.get("next_success", -1)) if win == 1 else int(choice.get("next_fail", -1))
	return next_stage

# ---------------------------------------------------------------------------
# Running gags with a bill attached
# ---------------------------------------------------------------------------

## Remember a decision so a later scene can bring it up unprompted.
func remember(key: String, value: Variant) -> void:
	memory[key] = value

func recall(key: String, fallback: Variant = "") -> Variant:
	return memory.get(key, fallback)

## Queue a payoff scene for `cycles` RESETs from now.
func schedule_callback(story: String, cycles: int = 2) -> void:
	if story == "" or story in _played_callbacks:
		return
	for cb in _pending_callbacks:
		if str(cb.get("story", "")) == story:
			return
	_pending_callbacks.append({"story": story, "cycles": maxi(1, cycles), "ready": false})
	running_gag.emit("scheduled", story)

func bill_amount() -> float:
	return _bill

## How many times the pager has found you. The escalation policy grows with it.
func escalation_level() -> int:
	return _escalation

func _adjust_bill(delta: float) -> void:
	if delta <= -1000.0:
		_bill = 0.0
		_bill_active = false
		return
	_bill = clampf(_bill + delta, 0.0, 900.0)
	_bill_active = _bill > 0.0
	_bill_reckoned = false

## A choice that eats (or buys back) real time before the next RESET. This is the
## sharpest mechanical joke available: "quick five-minute fix" literally costs
## you deadline.
func _adjust_cycle_time(delta: float) -> void:
	var cm := get_node_or_null("/root/CycleManager")
	if cm == null:
		return
	cm.time_left = clampf(float(cm.time_left) + delta, 8.0, 600.0)

func _adjust_price(mult: float) -> void:
	var cm := get_node_or_null("/root/CycleManager")
	if cm == null or mult <= 0.0:
		return
	cm.price_index = clampf(float(cm.price_index) * mult, 0.6, 3.0)

func _on_cycle_reset(_cycle_number: int) -> void:
	# The ninth subscription. You do not remember signing up. It remembers you.
	if _bill_active and _bill > 0.0:
		ResourceManager.modify("tokens", -_bill)
		_bill = minf(_bill * 1.5 + 4.0, 900.0)
		running_gag.emit("subscription", "Renewed on the 3rd. Next: %d tokens." % int(_bill))
	# It only ever goes down when everything is finally, genuinely fine.
	if ResourceManager.get_value("stability") >= 78.0 and ResourceManager.get_value("tokens") >= 300.0:
		_calm_streak += 1
		if _force_event_id == "":
			_force_event_id = CALM_PUNISHERS[(_calm_streak - 1) % CALM_PUNISHERS.size()]
			cooldown = minf(cooldown, 15.0)
			running_gag.emit("calm", "Everything is fine. That is the problem.")
	else:
		_calm_streak = 0
	# Callbacks mature between cycles; they are delivered by _try_trigger so they
	# never land on top of dialogue or a pause menu.
	for cb in _pending_callbacks:
		cb["cycles"] = int(cb.get("cycles", 1)) - 1
		if int(cb["cycles"]) <= 0:
			cb["ready"] = true
	_check_gag_achievements()

func _on_quest_completed(quest_id: String, _rewards: Dictionary) -> void:
	if QUEST_ACHIEVEMENTS.has(quest_id):
		AchievementManager.unlock(str(QUEST_ACHIEVEMENTS[quest_id]))

func _check_gag_achievements() -> void:
	if int(GameManager.death_count) >= 10:
		AchievementManager.unlock("actually_i_cannot_explain")
	if _bill >= 200.0:
		AchievementManager.unlock("the_ninth_subscription")
	if _calm_punished >= 3:
		AchievementManager.unlock("it_waits_for_calm")
	if _agent_count() >= 4:
		AchievementManager.unlock("middle_management")
	if _ridiculousness() >= 12:
		AchievementManager.unlock("architecture_astronaut")

func _agent_count() -> int:
	var am := get_node_or_null("/root/AgentManager")
	return am.active_count() if am else 0

func _cycle() -> int:
	var cm := get_node_or_null("/root/CycleManager")
	return int(cm.cycle) if cm else 1

func _ridiculousness() -> int:
	var am := get_node_or_null("/root/ArchitectureManager")
	return int(am.ridiculousness) if am else 0

func has_active_event() -> bool:
	return not active_event.is_empty()

func get_active() -> Dictionary:
	return active_event
