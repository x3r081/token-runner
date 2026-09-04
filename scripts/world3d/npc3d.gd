class_name NPC3D
extends Node3D
## The 3D twin of `scripts/world/npc.gd` (3D_BIBLE.md §4).
##
## Same three layers of "this thing noticed you", rebuilt on the XZ plane:
##   1. Presence  — a rigged Kenney chibi looping `idle`, turning to face you
##                  when you come close. No light: LAW 3 keeps NPCs out of the
##                  five bright things.
##   2. Nameplate — a SCREEN-SPACE label (scripts/world3d/screen_labels.gd) that
##                  follows the head. Label3D is retired here: its glyphs scale
##                  with distance, so a name three metres from the camera
##                  rendered at ~30px — larger than the 26px region heading — and
##                  it could not be clamped, so eight of ten captured frames had
##                  a nameplate running off the right edge ("SVP of AI
##                  Transformation Excellenc"). ScreenLabels rasterises once at
##                  BODY (18), clamps inside the HUD safe area and stacks off the
##                  other captions in the room.
##   3. Barks     — the SAME corpus as 2D. `npc.gd::_bark_pool()` reads nothing
##                  but manager state and `npc_id`/`_passes`, so a throwaway
##                  NPC instance (created, asked, freed — never added to the
##                  tree, so `_ready` and its @onready nodes never run) hands us
##                  five hundred lines of state-aware comedy for free. Zero
##                  duplication, zero 2D nodes in a 3D scene.
##
## The throttles are npc.gd's, converted at the coordinate edge (map px / 64),
## and the global "nobody talks over anybody" gap is literally npc.gd's static
## `NPC._last_bark_at`, so a mixed 2D/3D scene would still take turns.

## Kenney character per NPC (3D_BIBLE.md §7 "Characters"). Every key is in
## assets/external/kenney3d/manifest.json.
const MODEL := {
	"roommate_ai": "mini-characters/character-male-c",
	"maintainer": "mini-characters/character-male-d",
	"stackoverflow_hermit": "graveyard/character-keeper",
	"api_reseller": "mini-market/character-employee",
	"junior_agent": "mini-characters/character-female-b",
	"cloud_salesperson": "mini-characters/character-female-c",
	"oss_maintainer": "mini-forest/character-archer",
	"svp_ai": "mini-characters/character-male-e",
	"gpu_foreman": "mini-characters/character-male-f",
	"oncall_engineer": "mini-characters/character-female-d",
	# Also an enemy type; as a person he gets the enemy row's suit (§7).
	"enterprise_architect": "mini-characters/character-male-a",
}
const DEFAULT_MODEL := "mini-characters/character-male-d"

## 3D_BIBLE.md §6: bind-pose characters are ~0.7u; the player and the NPCs are
## sized to 0.9u so a person is a little over half a tile tall.
const BODY_HEIGHT := 0.9
## THE SCALE CLAMP. `Map3D.fit_height` divides by the manifest's authored height,
## so a model whose bounds were never measured (or measured as a sliver) is
## multiplied by whatever that division happens to produce — which is how the
## production frame ended up with a Kenney head and torso at roughly four times
## player scale, cropped by the frame edge. A person in this game is between
## BODY_MIN and BODY_MAX tall and nothing in this file may make one bigger; a
## model whose authored height is degenerate is left at the kit's own scale
## instead of being fitted to a number derived from noise.
const BODY_MIN := 0.85
const BODY_MAX := 1.0
const DEGENERATE_H := 0.2

## VISUAL_BIBLE v2 LAW 7 — one sprite language. Kenney's colormap dresses its
## characters in primary reds, blues and yellows at full chroma, and ten of them
## standing in ten rooms is ten more hues than LAW 2 allows the game in total.
## This is a MULTIPLY (Map3D.tint's contract), a shade under one and a touch
## cooler on the red channel, so a person goes quiet toward the region's dark
## without going grey: he still reads as a person in a coloured shirt, he just
## stops competing with the objective for the eye.
const BODY_TINT := Color(0.74, 0.76, 0.82)

## The attention stack, in world units above the NPC's feet — the ANCHOR heights
## ScreenLabels unprojects, not glyph positions (a screen label is drawn upward
## from its anchor). Same ORDER as the 2D stack: name, marker, bark.
##
## The gaps are wide on purpose. The player's [E] prompt is attached to THIS node
## too when he walks up (player3d.gd, anchor 1.0), so the name at 1.05 is always
## going to be stacked one line clear of it; the marker and the bark are placed
## far enough above that to stay out of the shuffle, which is what keeps a
## nameplate from hopping over its own quest marker as the player approaches.
const NAME_Y := 1.05
const MARKER_Y := 2.0
const BARK_Y := 2.6
## LAW 4 caps a frame at four world labels. A name is a caption on a person you
## can walk up to and talk to, so it is drawn only for the people in that
## conversation range and every other NPC in the room stays quiet.
const NAME_RADIUS := 9.0
## LAW 9: the marker bobs TWO SCREEN PIXELS. One world unit is ~91 screen pixels
## on the live rig (camera_rig3d KEEP_WIDTH, 40° at distance 29, 21.1u across a
## 1920 frame), so 0.022u is those two pixels. It is applied to the marker's
## ANCHOR node: the label's own screen position belongs to ScreenLabels, which
## rewrites it every frame, and a second writer would fight it.
const MARKER_BOB := 0.022

## Kenney's characters are authored facing +Z (their bounds are deeper toward
## +Z than -Z — a nose and a chest, see manifest min/max), so pointing local +Z
## at the player is a plain `atan2(to.x, to.z)`. If a kit ever turns up backwards
## this is the ONE number to flip (PI), and player3d/enemy3d must flip with it.
const MODEL_YAW_OFFSET := 0.0
const TURN_RATE := 7.0
## Turn to face inside this radius (npc.gd's NOTICE_RADIUS 250px / 64).
const FACE_RADIUS := 3.9

# --- bark throttles, npc.gd's constants converted at the edge (px / 64) ------
const NOTICE_RADIUS := 3.9      # npc.gd NOTICE_RADIUS 250
const BARK_RADIUS := 3.2        # npc.gd BARK_RADIUS 205
const BARK_RESET_RADIUS := 5.16 # npc.gd BARK_RESET_RADIUS 330
const BARK_COOLDOWN := 17.0     # npc.gd BARK_COOLDOWN
const BARK_AFTER_TALK := 11.0   # npc.gd BARK_AFTER_TALK
const BARK_GLOBAL_GAP := 3.2    # npc.gd BARK_GLOBAL_GAP
const BARK_HOLD := 3.4          # npc.gd BARK_HOLD
const BARK_FADE_IN := 0.25      # GameTheme.T_STD
const BARK_FADE_OUT := 0.45

@export var npc_id: String = ""
@export var quest_ids: Array[String] = []

## Mirrored from npc.gd: an NPC IS an interactable whose id is its npc_id, and
## it is never one_shot (that retired every NPC after one chat, once).
var interact_id: String = ""
var interact_text: String = "Interact"

var _accent := Color("#24F0DC")
var _pivot: Node3D
var _anim: KenneyAnim
var _npc_name := ""
var _name_label: Label
var _marker: Label
## The marker's own node, so LAW 9's two-pixel bob moves the ANCHOR rather than
## the screen position ScreenLabels owns.
var _marker_anchor: Node3D
var _marker_on := false
var _bark_label: Label
var _proxy: ActorProxy

var _anim_t := 0.0
var _bark_cd := 0.0
var _bark_t := -1.0
var _bark_armed := true
var _noticed := false
var _passes := 0

func _ready() -> void:
	add_to_group("interactable")
	add_to_group("npc")
	interact_id = npc_id
	interact_text = "Talk to %s" % DialogueManager.get_npc_name(npc_id)
	_accent = Color(str(NPC.NPC_ACCENT.get(npc_id, "#24F0DC")))
	_anim_t = randf() * TAU
	_bark_cd = randf_range(1.5, 5.0)  # desync the first bark of a busy room
	_build_model()
	_build_labels()
	# Arity matters (HANDOVER §4.3): quest_started/quest_updated pass one arg,
	# quest_completed passes two. One tolerant handler covers all three, exactly
	# as npc.gd does after that bug cost a round of stale quest markers.
	QuestManager.quest_started.connect(_on_quest_changed)
	QuestManager.quest_completed.connect(_on_quest_changed)
	QuestManager.quest_updated.connect(_on_quest_changed)
	_update_indicator()
	_proxy = ActorProxy.attach(self, ["interactable", "npc"], {
		"npc_id": npc_id,
		"quest_ids": quest_ids,
		"interact_id": interact_id,
		"interact_text": interact_text,
	})

# ------------------------------------------------------------------ building --

## The body. A yaw pivot wraps the model so turning the character never turns
## the attention stack: the labels are anchored on THIS node (and on a marker
## anchor beside it), and a caption's anchor must not swing around a pivot.
func _build_model() -> void:
	_pivot = Node3D.new()
	_pivot.name = "Model"
	add_child(_pivot)
	var key: String = str(MODEL.get(npc_id, DEFAULT_MODEL))
	var m := Map3D.model(key)
	if m == null:
		key = DEFAULT_MODEL
		m = Map3D.model(key)
	if m == null:
		# An NPC is never allowed to be an invisible interact volume.
		var mi := MeshInstance3D.new()
		var caps := CapsuleMesh.new()
		caps.radius = 0.2
		caps.height = BODY_HEIGHT
		mi.mesh = caps
		mi.position.y = BODY_HEIGHT * 0.5
		# LAW 7: even the missing-model stand-in is a desaturated body, not a
		# glowing accent capsule.
		mi.material_override = Map3D.matte(_accent.lerp(GameTheme.TEXT_DIM, 0.7), 0.0)
		_pivot.add_child(mi)
		return
	# THE CLAMP (see BODY_MIN/BODY_MAX). Fit only when the manifest actually
	# measured this model; a degenerate authored height is not a scale factor,
	# it is a divide by nearly nothing.
	if Map3D.height_of(key) < DEGENERATE_H:
		m.scale = Vector3.ONE
	else:
		Map3D.fit_height(m, key, clampf(BODY_HEIGHT, BODY_MIN, BODY_MAX))
	# LAW 7: the body goes quiet before anything else is allowed to be loud.
	Map3D.tint(m, BODY_TINT)
	# Feet on the floor. Most characters are authored with min.y == 0, but
	# graveyard/character-keeper (the hermit) sits at -0.20 and would otherwise
	# stand shin-deep in the ruins once scaled.
	var b := Map3D.bounds(key)
	if not b.is_empty():
		var mn: Array = b.get("min", [0.0, 0.0, 0.0])
		m.position.y = -minf(float(mn[1]), 0.0) * m.scale.y
	_pivot.add_child(m)
	_anim = KenneyAnim.attach(m)
	# Unrigged stand-ins (graveyard/character-keeper) simply have no player;
	# KenneyAnim.play is a no-op there rather than an error.
	_anim.play("idle", 0.2, 1.0, ["static"])

## The attention stack, in screen space. Three labels, each empty until it has
## something to say — ScreenLabels hides a label whose text is "" and never
## gives it a slot, so "quiet" costs a room nothing.
func _build_labels() -> void:
	_npc_name = DialogueManager.get_npc_name(npc_id)
	# The name starts empty: `_update_name` switches it on inside NAME_RADIUS.
	_name_label = ScreenLabels.attach(self, "", ScreenLabels.BODY, _plate_color(), NAME_Y, 2)
	# One glyph, one meaning: "walk here and press [E]". npc.gd draws a chevron
	# in the REGION accent because VISUAL_BIBLE LAW 2 reserves gold for currency
	# and LAW 8 gives world-linked guidance exactly one colour; the 3D marker
	# keeps that rule and only changes the glyph to the universal "!". It is the
	# ONE accent-coloured thing over an NPC's head, and it is never magenta
	# unless magenta is the room's own accent.
	_marker_anchor = Node3D.new()
	_marker_anchor.name = "MarkerAnchor"
	add_child(_marker_anchor)
	_marker = ScreenLabels.attach(_marker_anchor, "", ScreenLabels.BODY, _marker_accent(), MARKER_Y, 3)
	_bark_label = ScreenLabels.attach(self, "", ScreenLabels.SMALL, GameTheme.TEXT, BARK_Y, 2)

## The nameplate's colour. NOT the per-NPC accent any more: ten NPCs carrying
## ten `NPC_ACCENT` hues is ten hues, and LAW 2 grants a scene three. A name is a
## caption — it says who, not where — so it is drawn in the neutral TEXT the rest
## of the game's copy uses, and the ONE accent-coloured thing over an NPC's head
## stays the quest marker, which is the part that means "go here".
func _plate_color() -> Color:
	return GameTheme.TEXT

## LAW 8: world-linked guidance is drawn in the REGION accent, not a colour per
## marker state. Identical to npc.gd::_marker_accent().
func _marker_accent() -> Color:
	return GameTheme.region_accent(GameManager.current_region)

# -------------------------------------------------------------------- frame --

func _process(delta: float) -> void:
	_anim_t += delta
	if _proxy:
		_proxy.sync()
	var dist := INF
	var to := Vector3.ZERO
	var player := get_tree().get_first_node_in_group("player")
	if player is Node3D:
		to = (player as Node3D).global_position - global_position
		to.y = 0.0
		dist = to.length()
	_face(delta, dist, to)
	_update_name(dist)
	_animate_marker()
	_tick_bark(delta, dist)

## LAW 4: a name is drawn for the person you could walk up to, and for nobody
## else in the room. An empty label is an unplaced label in ScreenLabels, so
## this is also what keeps a crowded room inside the four-caption budget.
func _update_name(dist: float) -> void:
	if _name_label == null:
		return
	ScreenLabels.set_text(_name_label, _npc_name if dist <= NAME_RADIUS else "")

## Turn toward the player when they are close enough to be talked to, and hold
## the last heading otherwise (npc.gd leans by one pixel; in 3D the equivalent
## reading is a body that has turned around to look at you).
func _face(delta: float, dist: float, to: Vector3) -> void:
	if _pivot == null or dist > FACE_RADIUS or dist < 0.01:
		return
	var want := atan2(to.x, to.z) + MODEL_YAW_OFFSET
	_pivot.rotation.y = lerp_angle(_pivot.rotation.y, want, clampf(delta * TURN_RATE, 0.0, 1.0))

func _animate_marker() -> void:
	if _marker == null:
		return
	if not _marker_on:
		ScreenLabels.set_text(_marker, "")
		return
	ScreenLabels.set_text(_marker, "!")
	# LAW 9: motion is small. Two screen pixels, on the anchor.
	if is_instance_valid(_marker_anchor):
		_marker_anchor.position.y = sin(_anim_t * 2.2) * MARKER_BOB
	# The marker steps aside while this NPC is speaking, on alpha alone. The
	# glyph's colour is the accent ScreenLabels rasterised it in; `modulate` is
	# the Control's own multiplier, so this fades without repainting it.
	var duck := 1.0 if _bark_t < 0.0 else 1.0 - _bark_alpha()
	_marker.modulate = Color(1.0, 1.0, 1.0, duck)

# ------------------------------------------------------------------- quests --

## Accepts quest_started(quest_id), quest_updated(quest_id) AND
## quest_completed(quest_id, rewards). See HANDOVER §4.3.
func _on_quest_changed(_a = null, _b = null) -> void:
	_update_indicator()

func _update_indicator() -> void:
	if _marker == null:
		return
	_marker_on = _has_available_quest() or _is_objective_target()
	if _marker_on:
		# The room's accent can change under a persistent NPC only by a region
		# rebuild, but repainting here costs nothing and keeps LAW 2 true even
		# then. `add_theme_color_override` is the font colour; `modulate` above
		# is the fade, and the two do not fight.
		_marker.add_theme_color_override("font_color", _marker_accent())

func _is_objective_target() -> bool:
	var cur: Dictionary = QuestManager.get_current_objective()
	if cur.is_empty():
		return false
	return str(cur.get("kind", "")) == "npc" and str(cur.get("node_id", "")) == npc_id

## npc.gd::_has_available_quest, verbatim in behaviour: an INACTIVE quest whose
## prerequisites are all completed.
func _has_available_quest() -> bool:
	for qid: String in quest_ids:
		var info: Dictionary = QuestManager.get_quest_info(qid)
		if info.is_empty():
			continue
		if int(info.get("state", -1)) == QuestManager.QuestState.INACTIVE:
			var prereqs: Array = QuestManager.quest_defs.get(qid, {}).get("prerequisites", [])
			var met := true
			for p in prereqs:
				if p not in QuestManager.completed_quests:
					met = false
			if met:
				return true
	return false

# ---------------------------------------------------------------- interact --

## 3D_BIBLE.md §4. The 2D path is Interactable.interact() → on_interact() →
## NPC._on_interact(); flattened here to the same two manager calls, in order.
func interact(_player_node: Node = null) -> void:
	# Don't bark the instant a conversation ends — that reads as a bug, not a bit.
	_bark_cd = maxf(_bark_cd, BARK_AFTER_TALK)
	_hide_bark()
	QuestManager.on_interact(npc_id)
	if _anim:
		_anim.play("interact-right", 0.15, 1.0, ["emote-yes", "idle"])
	DialogueManager.start_dialogue(npc_id)

func get_prompt() -> String:
	return "Talk to %s" % DialogueManager.get_npc_name(npc_id)

# ------------------------------------------------------------------- barks --

## npc.gd::_tick_bark, one for one: one bark per approach, a long per-NPC
## cooldown, and a global gap so a crowd never chatters.
func _tick_bark(delta: float, dist: float) -> void:
	_advance_bark(delta)
	if _bark_cd > 0.0:
		_bark_cd -= delta
	if _bark_t >= 0.0 and (DialogueManager.is_active or GameManager.state != GameManager.GameState.PLAYING):
		_hide_bark()
	if dist > BARK_RESET_RADIUS:
		_bark_armed = true
		_noticed = false
		return
	if dist < NOTICE_RADIUS and not _noticed:
		_noticed = true
	if not _bark_armed or dist > BARK_RADIUS or _bark_cd > 0.0:
		return
	if not _can_bark_now():
		return
	_bark_armed = false
	_bark_cd = BARK_COOLDOWN
	_passes += 1
	_say_bark()

func _can_bark_now() -> bool:
	if GameManager.state != GameManager.GameState.PLAYING:
		return false
	if DialogueManager.is_active:
		return false
	if UIManager.has_blocking_ui():
		return false
	if EventManager.has_active_event():
		return false
	return _now() - NPC._last_bark_at >= BARK_GLOBAL_GAP

func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0

## THE WHOLE 2D BARK CORPUS, WITHOUT A SECOND COPY OF IT.
##
## `npc.gd::_bark_pool()` touches no node and no tree — only ResourceManager,
## GameManager, AgentManager, ArchitectureManager, `npc_id` and `_passes`. So a
## bare `NPC.new()` that is NEVER added to the tree (no `_ready`, therefore no
## @onready sprite/label/indicator to be null) answers the question and is freed
## on the spot. If npc.gd ever grows a tree dependency in there, this returns an
## empty pool and the NPC simply goes quiet.
func _bark_pool() -> Array[String]:
	var probe := NPC.new()
	probe.npc_id = npc_id
	probe._passes = _passes
	var pool: Array[String] = probe._bark_pool()
	probe.free()
	return pool

func _say_bark() -> void:
	if _bark_label == null:
		return
	var pool := _bark_pool()
	if pool.is_empty():
		return
	# Shared with the 2D NPCs so a mixed scene would still take turns.
	NPC._last_bark_at = _now()
	# Bag key includes the pool size so a state-dependent pool never deals a
	# stale index into a shorter list (ComedyLines is the same shuffle bag the
	# 2D barks use, so a line does not repeat until the bag is empty).
	ScreenLabels.set_text(_bark_label, ComedyLines.pick("bark:%s:%d" % [npc_id, pool.size()], pool))
	_bark_label.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_bark_t = 0.0

## The bark's fade is driven by hand rather than by a Tween on purpose: a Tween
## started here freezes mid-fade the moment a popup sets `get_tree().paused`
## (HANDOVER §4.4) and would leave a bubble welded to the screen.
func _advance_bark(delta: float) -> void:
	if _bark_t < 0.0:
		return
	_bark_t += delta
	if _bark_t >= BARK_FADE_IN + BARK_HOLD + BARK_FADE_OUT:
		_hide_bark()
		return
	# LAW 4's world-text colour is the TEXT grey ScreenLabels drew the bark in;
	# only its opacity moves, and `modulate` is the multiplier that moves it.
	_bark_label.modulate = Color(1.0, 1.0, 1.0, _bark_alpha())

func _bark_alpha() -> float:
	if _bark_t < 0.0:
		return 0.0
	if _bark_t < BARK_FADE_IN:
		return clampf(_bark_t / BARK_FADE_IN, 0.0, 1.0)
	var out_t := _bark_t - BARK_FADE_IN - BARK_HOLD
	if out_t <= 0.0:
		return 1.0
	return clampf(1.0 - out_t / BARK_FADE_OUT, 0.0, 1.0)

## Emptying the text is what retires a screen label: ScreenLabels never places
## one whose text is "", so a silent NPC costs the frame no slot and no caption.
func _hide_bark() -> void:
	_bark_t = -1.0
	if _bark_label:
		ScreenLabels.set_text(_bark_label, "")
		_bark_label.modulate = Color(1.0, 1.0, 1.0, 0.0)
