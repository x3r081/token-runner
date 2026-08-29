extends Node
## Quest tracking, progression, and completion.

signal quest_started(quest_id: String)
signal quest_updated(quest_id: String)
signal quest_completed(quest_id: String, rewards: Dictionary)
signal quest_failed(quest_id: String)

enum QuestState { INACTIVE, ACTIVE, COMPLETED, FAILED }

var quest_defs: Dictionary = {}
var quest_states: Dictionary = {}
var quest_progress: Dictionary = {}
var completed_quests: Array[String] = []

func _ready() -> void:
	_load_quest_definitions()

func reset() -> void:
	quest_states.clear()
	quest_progress.clear()
	completed_quests.clear()
	_activate_starter_quests()

func _load_quest_definitions() -> void:
	var file := FileAccess.open("res://data/quests/quests.json", FileAccess.READ)
	if file:
		var data = JSON.parse_string(file.get_as_text())
		if data is Dictionary:
			quest_defs = data.get("quests", {})
		file.close()

func _activate_starter_quests() -> void:
	for qid in quest_defs:
		var q: Dictionary = quest_defs[qid]
		if q.get("auto_start", false):
			start_quest(qid)

func start_quest(quest_id: String) -> bool:
	if quest_id not in quest_defs:
		return false
	if quest_states.get(quest_id, QuestState.INACTIVE) == QuestState.ACTIVE:
		return false
	if quest_id in completed_quests:
		return false
	var prereqs: Array = quest_defs[quest_id].get("prerequisites", [])
	for p in prereqs:
		if p not in completed_quests:
			return false
	quest_states[quest_id] = QuestState.ACTIVE
	quest_progress[quest_id] = {}
	for obj in quest_defs[quest_id].get("objectives", []):
		quest_progress[quest_id][obj.id] = 0
	quest_started.emit(quest_id)
	return true

func update_objective(quest_id: String, objective_id: String, amount: int = 1) -> void:
	if quest_states.get(quest_id) != QuestState.ACTIVE:
		return
	if not quest_progress.has(quest_id):
		return
	if not quest_progress[quest_id].has(objective_id):
		return
	var obj_def := _get_objective_def(quest_id, objective_id)
	var target: int = obj_def.get("count", 1)
	quest_progress[quest_id][objective_id] = mini(
		quest_progress[quest_id][objective_id] + amount, target
	)
	quest_updated.emit(quest_id)
	if _is_quest_complete(quest_id):
		complete_quest(quest_id)

func set_objective(quest_id: String, objective_id: String, value: int) -> void:
	if quest_states.get(quest_id) != QuestState.ACTIVE:
		return
	if quest_progress.has(quest_id) and quest_progress[quest_id].has(objective_id):
		quest_progress[quest_id][objective_id] = value
		quest_updated.emit(quest_id)
		if _is_quest_complete(quest_id):
			complete_quest(quest_id)

func complete_quest(quest_id: String) -> void:
	if quest_states.get(quest_id) != QuestState.ACTIVE:
		return
	quest_states[quest_id] = QuestState.COMPLETED
	completed_quests.append(quest_id)
	var q: Dictionary = quest_defs[quest_id]
	var rewards: Dictionary = q.get("rewards", {})
	for res in rewards:
		if res == "technical_debt":
			ResourceManager.accept_debt(int(rewards[res]))
		else:
			ResourceManager.modify(res, float(rewards[res]))
	if rewards.has("unlock_region"):
		GameManager.unlock_region(rewards.unlock_region)
	if rewards.has("achievement"):
		AchievementManager.unlock(rewards.achievement)
	GameManager.record_stat("quests_completed")
	quest_completed.emit(quest_id, rewards)
	AudioManager.play_sfx("quest_complete")
	# Chain next quests
	for next_id in quest_defs:
		var nq: Dictionary = quest_defs[next_id]
		var prereqs: Array = nq.get("prerequisites", [])
		if quest_id in prereqs and _prereqs_met(prereqs):
			start_quest(next_id)

func fail_quest(quest_id: String) -> void:
	quest_states[quest_id] = QuestState.FAILED
	quest_failed.emit(quest_id)

func get_active_quests() -> Array[String]:
	var result: Array[String] = []
	for qid in quest_states:
		if quest_states[qid] == QuestState.ACTIVE:
			result.append(qid)
	return result

func get_quest_info(quest_id: String) -> Dictionary:
	if quest_id not in quest_defs:
		return {}
	var q: Dictionary = quest_defs[quest_id].duplicate(true)
	q["id"] = quest_id
	q["state"] = quest_states.get(quest_id, QuestState.INACTIVE)
	q["progress"] = quest_progress.get(quest_id, {})
	return q

func get_all_quest_infos() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for qid in quest_defs:
		result.append(get_quest_info(qid))
	return result

func is_completed(quest_id: String) -> bool:
	return quest_id in completed_quests

func _get_objective_def(quest_id: String, objective_id: String) -> Dictionary:
	for obj in quest_defs[quest_id].get("objectives", []):
		if obj.id == objective_id:
			return obj
	return {}

func _is_quest_complete(quest_id: String) -> bool:
	for obj in quest_defs[quest_id].get("objectives", []):
		var prog: int = quest_progress[quest_id].get(obj.id, 0)
		if prog < obj.get("count", 1):
			return false
	return true

func _prereqs_met(prereqs: Array) -> bool:
	for p in prereqs:
		if p not in completed_quests:
			return false
	return true

func on_enemy_defeated(enemy_type: String) -> void:
	for qid in get_active_quests():
		for obj in quest_defs[qid].get("objectives", []):
			if obj.get("type") == "defeat" and obj.get("target") == enemy_type:
				update_objective(qid, obj.id)

func on_token_collected(count: int = 1) -> void:
	for qid in get_active_quests():
		for obj in quest_defs[qid].get("objectives", []):
			if obj.get("type") == "collect_tokens":
				update_objective(qid, obj.id, count)

func on_region_entered(region_id: String) -> void:
	for qid in get_active_quests():
		for obj in quest_defs[qid].get("objectives", []):
			if obj.get("type") == "visit" and obj.get("target") == region_id:
				set_objective(qid, obj.id, 1)

func on_interact(target_id: String) -> void:
	for qid in get_active_quests():
		for obj in quest_defs[qid].get("objectives", []):
			if obj.get("type") == "interact" and obj.get("target") == target_id:
				set_objective(qid, obj.id, 1)

func on_talk(npc_id: String) -> void:
	for qid in get_active_quests():
		for obj in quest_defs[qid].get("objectives", []):
			if obj.get("type") == "talk" and obj.get("target") == npc_id:
				set_objective(qid, obj.id, 1)

# ----------------------------------------------------------------------------
# Objective routing — "what now, and WHERE?"
#
# Everything below is purely additive read-only sugar over the state the rest of
# this file already maintains. It exists because a quest line that says "Talk to
# your AI roommate" is useless if the player has no idea which of the eleven
# glowing rectangles in the room IS the roommate. scripts/ui/objective_waypoint.gd
# turns these dictionaries into an on-screen arrow; the HUD turns them into a
# sentence. Nothing here mutates quest state.
# ----------------------------------------------------------------------------

## Objectives of type "story" are advanced by an EventManager script, but the
## player still has to find the prop that STARTS that script. This maps the
## story id to the interactable that fires it, so the waypoint has something
## physical to point at instead of shrugging.
const STORY_TRIGGERS := {
	"tiny_change": "client_email",
	"free_tier": "free_tokens_ad",
	"autonomous_agent": "agent_terminal",
	"debugging_investigation": "broken_service",
}

## Short, conversational NPC names for objective lines. The full display names
## ("SVP of AI Transformation Excellence") are correct and also do not fit on a
## HUD arrow, which is arguably the most accurate thing about that job title.
const NPC_SHORT_NAMES := {
	"roommate_ai": "Claude",
	"maintainer": "the Maintainer",
	"stackoverflow_hermit": "the Hermit",
	"api_reseller": "the Reseller",
	"cloud_salesperson": "the Salesperson",
	"oss_maintainer": "the Maintainer",
	"svp_ai": "the SVP",
	"gpu_foreman": "the Foreman",
	"oncall_engineer": "the On-Call Engineer",
	"junior_agent": "the Junior Agent",
}

## Objective type -> the kind of world node that satisfies it. Consumers switch
## on "kind" instead of re-deriving this from the raw JSON types.
const OBJECTIVE_KINDS := {
	"talk": "npc",
	"collect_tokens": "token",
	"defeat": "enemy",
	"interact": "prop",
	"story": "prop",
	"visit": "region",
	"reach": "region",
}

func npc_short_name(npc_id: String) -> String:
	if NPC_SHORT_NAMES.has(npc_id):
		return str(NPC_SHORT_NAMES[npc_id])
	return DialogueManager.get_npc_name(npc_id)

## "dependency_demon" -> "Dependency Demon". Used for enemies and regions alike.
func pretty_name(id: String) -> String:
	return id.replace("_", " ").capitalize()

## The one quest the HUD and the waypoint agree to track. Prefers something the
## player can actually do standing where they are, then the critical path, then
## whatever is left — so the pointer never sends you three regions away for a
## side quest you picked up by accident.
func get_tracked_quest_id() -> String:
	var active := get_active_quests()
	if active.is_empty():
		return ""
	var here: String = GameManager.current_region
	var best := ""
	var best_score := -9999
	for qid in active:
		var obj := get_next_objective(qid)
		if obj.is_empty():
			continue
		var score := 0
		if objective_region(qid, obj) == here:
			score += 100
		var q: Dictionary = quest_defs.get(qid, {})
		if q.get("rewards", {}).has("unlock_region"):
			score += 10
		# Earlier regions first, so the critical path stays in story order.
		# (find() returns -1 for a region-less side quest, nudging it one point
		# up — harmless, and stable across runs.)
		score -= GameManager.REGION_ORDER.find(str(q.get("region", "")))
		if score > best_score:
			best_score = score
			best = qid
	return best if best != "" else active[0]

## First objective of `quest_id` that is not yet satisfied ({} when all are).
func get_next_objective(quest_id: String) -> Dictionary:
	var prog: Dictionary = quest_progress.get(quest_id, {})
	for obj in quest_defs.get(quest_id, {}).get("objectives", []):
		if not (obj is Dictionary):
			continue
		var oid := str(obj.get("id", ""))
		if int(prog.get(oid, 0)) < int(obj.get("count", 1)):
			return obj
	return {}

## Which region an objective is performed in. "visit" objectives name their own;
## everything else happens wherever the quest is set.
##
## A quest's "region" field means "where the GIVER stands" (quest_log.gd renders
## it that way in its FROM: line), which is usually also where the work happens.
## It is not always: context_window_full is handed out by the Cloud Salesperson in
## cloud_district, but its target boss, THE INFINITE CONTEXT, only ever spawns in
## token_vault. Trusting the quest region there would aim the waypoint at a region
## the objective cannot be completed in, and contradict the objective's own text.
## So for "defeat" we resolve the region from where the enemy actually spawns and
## only fall back to the quest region when the type isn't placed anywhere.
func objective_region(quest_id: String, obj: Dictionary) -> String:
	var otype := str(obj.get("type", ""))
	if otype == "visit" or otype == "reach":
		return str(obj.get("target", ""))
	var q: Dictionary = quest_defs.get(quest_id, {})
	var r := str(q.get("region", ""))
	if otype == "defeat":
		var spawned := enemy_home_region(str(obj.get("target", "")), r)
		if spawned != "":
			return spawned
	if r == "":
		r = GameManager.current_region
	return r

## enemy type -> the region it actually spawns in, built once from the world's own
## spawn table so this can never drift from what the builder places.
var _enemy_regions: Dictionary = {}

## Where an enemy type is actually spawned. When a type appears in several regions
## (bug, memory_leak, rate_limiter) we prefer `prefer` if it is one of them, so a
## quest set in a region that does spawn its target keeps pointing there.
func enemy_home_region(enemy_type: String, prefer: String = "") -> String:
	if enemy_type == "":
		return ""
	if _enemy_regions.is_empty():
		var builder = load("res://scripts/world/region_builder.gd")
		if builder == null:
			return ""
		for region: String in GameManager.REGION_ORDER:
			for e: Dictionary in builder._region_enemies(region):
				var t := str(e.get("type", ""))
				if t == "":
					continue
				if not _enemy_regions.has(t):
					_enemy_regions[t] = []
				_enemy_regions[t].append(region)
	var homes: Array = _enemy_regions.get(enemy_type, [])
	if homes.is_empty():
		return ""
	if prefer != "" and prefer in homes:
		return prefer
	return str(homes[0])

## The current objective, resolved to something a waypoint can find:
##   quest_id, quest_name, objective_id, text, type, target, kind, node_id,
##   region, progress, count, remaining, action
## Returns {} when there is genuinely nothing to do.
func get_current_objective() -> Dictionary:
	var qid := get_tracked_quest_id()
	if qid == "":
		return {}
	var obj := get_next_objective(qid)
	if obj.is_empty():
		return {}
	var oid := str(obj.get("id", ""))
	var otype := str(obj.get("type", ""))
	var target := str(obj.get("target", ""))
	var kind := str(OBJECTIVE_KINDS.get(otype, ""))
	var node_id := target
	# A story beat is invisible; the prop that triggers it is not.
	if otype == "story" and STORY_TRIGGERS.has(target):
		node_id = str(STORY_TRIGGERS[target])
	var count: int = int(obj.get("count", 1))
	var progress: int = int(quest_progress.get(qid, {}).get(oid, 0))
	var remaining: int = maxi(count - progress, 0)
	return {
		"quest_id": qid,
		"quest_name": str(quest_defs.get(qid, {}).get("name", qid)),
		"objective_id": oid,
		"text": str(obj.get("text", oid)),
		"type": otype,
		"target": target,
		"kind": kind,
		"node_id": node_id,
		"region": objective_region(qid, obj),
		"progress": progress,
		"count": count,
		"remaining": remaining,
		"action": _objective_action(kind, target, remaining, str(obj.get("text", oid))),
	}

## One concrete imperative sentence: what the player should physically do next.
func get_objective_hint() -> String:
	var obj := get_current_objective()
	if obj.is_empty():
		return ""
	return str(obj.get("action", ""))

func _objective_action(kind: String, target: String, remaining: int, text: String) -> String:
	match kind:
		"npc":
			return "Talk to %s" % npc_short_name(target)
		"token":
			var noun := "token" if remaining == 1 else "tokens"
			if target == "compute":
				noun = "compute" if remaining == 1 else "compute pickups"
			return "Collect %d more %s" % [remaining, noun]
		"enemy":
			var who := pretty_name(target)
			if remaining != 1:
				who += "s"
			return "Defeat %d more %s" % [remaining, who]
		"region":
			return "Travel to %s" % pretty_name(target)
		_:
			return text
