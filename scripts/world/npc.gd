extends "res://scripts/world/interactable.gd"
class_name NPC
## A resident of the world who is, crucially, PAYING ATTENTION.
##
## Three layers of "this thing noticed you":
##   1. Presence  — breathing, a lean toward the player, a notice-pop when you
##                  first walk into their bubble, a rim highlight in talk range.
##   2. Nameplate — legible above the head (never over the sprite) at ANY
##                  distance, with a leader tying it to the character it names.
##                  It gains a little presence as you approach; it never fades
##                  to decoration, because a name you cannot read is not a name.
##   3. Barks     — short, dry, state-aware floating lines that fire when you
##                  walk past. Heavily throttled: one per approach, a long
##                  per-NPC cooldown, and a global gap so a crowd never chatters.
##
## Barks read the run: debt, deaths, tokens, stability, deployed agents,
## architecture ridiculousness, whether the app is already shippable, and how
## many times you have walked this exact lap. Claude gets the most of it — he is
## the roommate who has been watching you fail all night and taking notes.

const _Comedy = preload("res://scripts/ui/comedy_lines.gd")
const _GameTheme = preload("res://scripts/ui/game_theme.gd")

@export var npc_id: String = ""
@export var quest_ids: Array[String] = []

@onready var label: Label = $Label
@onready var sprite: Sprite2D = $Sprite2D
@onready var indicator: Sprite2D = $QuestIndicator

var _anim_t := 0.0
var _spr_base_y := 0.0
var _ind_base_y := 0.0
var _hl_gate := 0.0
var _ind_base_scale := Vector2.ONE
var _mark: Label = null

## Attention / reactivity state.
var _name_gate := 0.0
var _lean := 0.0
var _notice_pop := 0.0
var _bark_panel: PanelContainer = null
var _bark_label: Label = null
var _bark_tween: Tween = null
var _bark_cd := 0.0
var _bark_armed := true
var _noticed := false
var _bark_gate := 0.0
var _passes := 0
var _accent := Color("#24F0DC")

## The deliberate lift that keeps the name off the objective waypoint's distance
## readout when this NPC is the one the waypoint is pointing at.
var _lift := 0.0
var _lift_want := 0.0
var _lift_poll := 0.0

const HIGHLIGHT_RADIUS := 100.0
## Nameplates gain a little presence as you approach — but the floor is a
## LEGIBLE alpha, not a decorative one. A name you cannot read is not a name.
const NAME_RADIUS := 340.0
const NAME_MIN_ALPHA := 0.88
## Bottom edge of the name in world space — clear of the sprite's head. The
## sprite is 64px art at 2.0 with origin y -18, so its hair tops out around
## world -74; -86 clears it without floating.
const NAME_BOTTOM_Y := -86.0
## Any accent, drawn straight onto the world, has to land at least this bright.
##
## This matters MORE now than it did with a plate behind it: hot_of() carries
## every accent in NPC_ACCENT to 0.71-0.94 luma, and the floor lifts the three
## darkest (#FF2D95 reseller pink 0.707, #FF4757 on-call red 0.732, #8B5CF6
## junior violet 0.735) toward white until they read against a dark floor.
const NAME_MIN_LUMA := 0.74
## objective_waypoint.gd hangs its "<name> · <n>m" readout directly above
## whatever it is pointing at, which for an NPC objective is the same band this
## nameplate lives in — the two-plates-on-Claude collision in
## region_localhost.png. That plate is opaque and it is on a CanvasLayer, so it
## wins; the only move available from here is to get out from under it.
##
## Derived against the CURRENT waypoint code, screen px, camera zoom 1.35:
##
##   target       O
##   sp           O - 14*1.35            = O - 18.9   (its world nudge)
##   marker       sp - BEACON_LIFT 52 - 6 = O - 76.9  (top of its +/-6 bob)
##   plate top    marker - MARKER_CLEAR 44 - plate height (~31 at font 14
##                plus PLATE_PAD_Y 6 twice)           = O - 151.9
##
## The nameplate's own bottom edge sits at (NAME_BOTTOM_Y + lift) * 1.35 above O,
## so clearing O - 151.9 with ~15px to spare needs a lift of 38, not the 24 a
## first pass arrived at from the OLD waypoint layout (a bare Label offset a flat
## 40px from the marker centre — that node was rewritten this same round and its
## readout now sits ~40px higher than it did in the QA frames).
##
## The whole attention stack moves as one unit, so its spacing is preserved.
const NAME_TARGET_LIFT := 38.0
## How often an NPC re-asks whether it is the current objective. get_current_
## objective() builds a Dictionary, so this is deliberately not per-frame.
const LIFT_POLL := 0.45
## World px/sec the stack travels when the objective moves on. The step is a
## discrete event but a 51-screen-px teleport reads as a glitch, so it eases —
## with move_toward rather than a Tween, because tweens freeze under pause and
## this one would freeze mid-flight (HANDOVER gotcha 4).
const LIFT_RATE := 190.0
## Leaning/noticing starts a little outside bark range.
const NOTICE_RADIUS := 250.0
## Walk this close and they say something. Leave past BARK_RESET to re-arm.
const BARK_RADIUS := 205.0
const BARK_RESET_RADIUS := 330.0
## Per-NPC quiet time after a bark, and after a conversation.
const BARK_COOLDOWN := 17.0
const BARK_AFTER_TALK := 11.0
## Nobody talks over anybody: minimum seconds between ANY two NPC barks.
const BARK_GLOBAL_GAP := 3.2
const BARK_HOLD := 3.4
## World-space y of the bark bubble's bottom edge (sprite tops out near -80,
## nameplate occupies roughly -110..-86, so the bubble stacks cleanly above both).
const BARK_BOTTOM_Y := -118.0
## Resting y of the quest marker, above the nameplate. Lifted with the rest of
## the stack when this NPC is the tracked objective.
const INDICATOR_Y := -140.0

## Depth. The world y-sorts by z_index (props take int(y + half), the player
## takes int(y)), so anything left at the scene default z=0 is painted over by
## every piece of furniture in the room — which is exactly what happened to NPC
## nameplates. The BODY joins the y-sort like everything else; the name, the
## marker and the bark are lifted onto absolute z values above every prop
## (~1050 max) and just above world sign plates (WorldLabel.Z_PLATE = 1150), so
## an NPC's own name always wins against set dressing. They stay below the
## player's interact prompt (player z + 500) and enemy HP bars (enemy z + 600),
## which must never be covered.
const Z_NAME := 1160
const Z_MARKER := 1165
const Z_BARK := 1170

## Shared across every NPC in the scene so two neighbours never bark in unison.
static var _last_bark_at := -999.0

const NPC_KIND := {
	"roommate_ai": "claude",
	"cloud_salesperson": "cloud",
	"svp_ai": "svp",
	"api_reseller": "reseller",
	"enterprise_architect": "suit",
	"gpu_foreman": "foreman",
	"stackoverflow_hermit": "hermit",
	"oncall_engineer": "oncall",
	"junior_agent": "junior",
}

## Nameplate/bark accent per character — region palette, not decoration roulette.
const NPC_ACCENT := {
	"roommate_ai": "#7DFFF0",
	"maintainer": "#A8FF3E",
	"oss_maintainer": "#58E07C",
	"stackoverflow_hermit": "#E8C46B",
	"api_reseller": "#FF2D95",
	"cloud_salesperson": "#6BC7FF",
	"svp_ai": "#4D7CFF",
	"enterprise_architect": "#4D7CFF",
	"gpu_foreman": "#FF6B2D",
	"oncall_engineer": "#FF4757",
	"junior_agent": "#8B5CF6",
}

func _ready() -> void:
	super._ready()
	# NPCs are conversations, not levers. Interactable defaults to one_shot, which
	# silently retired every NPC after a single chat and made every "evolving
	# dialogue" branch below unreachable.
	one_shot = false
	interact_id = npc_id
	interact_text = "Talk to %s" % DialogueManager.get_npc_name(npc_id)
	_accent = Color(str(NPC_ACCENT.get(npc_id, "#24F0DC")))
	# Join the world's y-sort so NPCs stand in front of the furniture they are
	# standing in front of. NPCs never move, so once is enough.
	z_index = int(global_position.y)
	_setup_sprite()
	_setup_nameplate()
	_spr_base_y = sprite.position.y
	_anim_t = randf() * TAU
	_bark_cd = randf_range(1.5, 5.0)  # desync the first bark of a busy room
	QuestManager.quest_started.connect(_on_quest_changed)
	QuestManager.quest_completed.connect(_on_quest_changed)
	QuestManager.quest_updated.connect(_on_quest_changed)
	_build_indicator_glow()
	_build_bark_bubble()
	_ind_base_y = indicator.position.y if indicator else 0.0
	_update_indicator()
	# Resolve the waypoint offset once at spawn so an NPC that is ALREADY the
	# tracked objective (Claude, every single new run) never renders one frame
	# with its plate sitting on the waypoint's distance readout. Instant here:
	# there is nothing to ease FROM on the first frame.
	_refresh_lift(true)
	_lift_poll = randf_range(0.1, LIFT_POLL)  # desync a room's worth of polls

## The nameplate. VISUAL_BIBLE_V2 LAW 4 gives a world label exactly one style:
## "plain aliased text, 1px #000000@80% drop shadow offset (1,1). No plate, no
## accent bar, no leader line, no rounded rect."
##
## So round 6 removed, from this one label: the near-opaque dark plate, its 1px
## accent border, its 4px corner radius, its 6px drop halo, its 9px side
## margins, the 3px glyph outline, the letter-spaced font variation, and the
## whole leader assembly under it — a Polygon2D bubble notch plus a Line2D stem
## that stretched to the top of the character's head. Eleven NPCs wearing that
## is eleven rounded plates with tails in a frame that is trying to read as
## pixel art. The name itself is unchanged, still sized from the real font so it
## cannot clip, still in the character's accent, still legible at any distance.
func _setup_nameplate() -> void:
	if not is_instance_valid(label):
		return
	label.text = DialogueManager.get_npc_name(npc_id)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_as_relative = false
	label.z_index = Z_NAME
	# StyleBoxEmpty, not "no override": the theme's own Label style would
	# otherwise put a panel back under every name in the game.
	label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", _plate_text_color())
	label.add_theme_constant_override("outline_size", 0)
	# The one permitted piece of furniture: a 1px black drop shadow, which is
	# what makes plain text survive a lit floor without a box around it.
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_constant_override("shadow_outline_size", 0)
	label.modulate.a = NAME_MIN_ALPHA
	# Measured, not guessed: reset_size() takes the font's real extents, which
	# is the only way a name can never clip.
	label.reset_size()
	label.resized.connect(_place_nameplate)
	_place_nameplate()

## Accent hue, forced up to a legible luminance. Linear in the lerp parameter,
## so the exact blend is solved rather than searched. Load-bearing now that the
## plate is gone: this text is drawn straight onto the room.
func _plate_text_color() -> Color:
	var c := _GameTheme.hot_of(_accent)
	var w := _GameTheme.WHITE_HOT
	var lc := _luma(c)
	if lc >= NAME_MIN_LUMA:
		return c
	var lw := _luma(w)
	if lw <= lc:
		return c
	return c.lerp(w, clampf((NAME_MIN_LUMA - lc) / (lw - lc), 0.0, 1.0))

func _luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b

## Bottom edge of the name right now — the default height, or lifted clear of
## the objective waypoint's readout while this NPC is the tracked objective.
func _name_bottom() -> float:
	return NAME_BOTTOM_Y - _lift

func _place_nameplate() -> void:
	if not is_instance_valid(label):
		return
	var sz: Vector2 = label.size
	# Rounded: a Control parented to a Node2D lands wherever its half-width puts
	# it, and half of an odd pixel width is what makes text render off-grid.
	label.position = Vector2(roundf(-sz.x * 0.5), roundf(_name_bottom() - sz.y))

## One deliberate offset for the whole attention stack — name, quest marker and
## bark all move together, so their spacing is preserved exactly.
func _set_lift(v: float) -> void:
	if is_equal_approx(_lift, v):
		return
	_lift = v
	_place_nameplate()
	_place_bark()
	if is_instance_valid(indicator):
		_ind_base_y = INDICATOR_Y - _lift

## The quest marker: a "!" glyph over a soft halo, so open quests advertise
## themselves. This is GUIDANCE and it stays fully legible — the glyph keeps its
## GOLD and its full size. What comes down is the halo behind it, from an
## overbright (2.4, 2.0, 0.5) additive disc to something just under the bloom
## threshold, and the 5px glyph outline to a 1px drop shadow (LAW 4).
func _build_indicator_glow() -> void:
	if not is_instance_valid(indicator):
		return
	# Clear of the name, which owns roughly -108..-86 at rest.
	indicator.position = Vector2(0, INDICATOR_Y - _lift)
	indicator.z_as_relative = false
	indicator.z_index = Z_MARKER
	# The scene ships this node at modulate (1, 0.9, 0.2) — a gold tint that
	# would multiply straight through onto the child glyph and turn the cyan
	# "you are here" marker olive. `modulate` is reserved for the bark duck.
	indicator.modulate = Color.WHITE
	var dot := FxLib.glow_dot()
	if dot and indicator.texture == null:
		indicator.texture = dot
		indicator.material = FxLib.additive_material()
		# self_modulate, NOT modulate: `modulate` multiplies down through
		# children, and the "!" glyph is a child. Dimming the halo must never
		# dim the thing the halo exists to point at — guidance gets quieter,
		# never weaker. `modulate` is left to the bark duck alone.
		indicator.self_modulate = Color(0.98, 0.84, 0.30, 0.55)
		indicator.scale = Vector2(1.3, 1.3)
	_ind_base_scale = indicator.scale
	var mark := Label.new()
	mark.name = "Mark"
	mark.text = "!"
	mark.add_theme_font_size_override("font_size", 18)
	mark.add_theme_color_override("font_color", _GameTheme.GOLD)
	mark.add_theme_constant_override("outline_size", 0)
	mark.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	mark.add_theme_constant_override("shadow_offset_x", 1)
	mark.add_theme_constant_override("shadow_offset_y", 1)
	mark.position = Vector2(-5, -15)
	indicator.add_child(mark)
	_mark = mark

## The bark: one PanelContainer for layout + one Label, built once and reused
## for the whole run. No per-bark allocation beyond the line of text itself.
##
## The container keeps its job (it is what sizes and centres the line) and loses
## its appearance: LAW 4 allows a world label plain text and a 1px drop shadow,
## so the accent glass box with its 9px radius is a StyleBoxEmpty now. A bark is
## a character speaking, not a UI panel arriving.
func _build_bark_bubble() -> void:
	_bark_panel = PanelContainer.new()
	_bark_panel.name = "Bark"
	_bark_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_bark_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bark_panel.z_as_relative = false
	_bark_panel.z_index = Z_BARK
	_bark_panel.visible = false
	_bark_panel.modulate.a = 0.0
	add_child(_bark_panel)

	_bark_label = Label.new()
	_bark_label.name = "BarkLabel"
	_bark_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bark_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bark_label.add_theme_font_size_override("font_size", 14)
	_bark_label.add_theme_color_override("font_color", _GameTheme.TEXT)
	_bark_label.add_theme_constant_override("outline_size", 0)
	_bark_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	_bark_label.add_theme_constant_override("shadow_offset_x", 1)
	_bark_label.add_theme_constant_override("shadow_offset_y", 1)
	_bark_panel.add_child(_bark_label)
	_bark_panel.resized.connect(_place_bark)

func _place_bark() -> void:
	if not is_instance_valid(_bark_panel):
		return
	var sz: Vector2 = _bark_panel.size
	_bark_panel.pivot_offset = Vector2(sz.x * 0.5, sz.y)
	# Rounded for the same reason the name is: half of an odd width is half a
	# pixel, and half a pixel is where aliased text stops being crisp.
	_bark_panel.position = Vector2(roundf(-sz.x * 0.5), roundf(BARK_BOTTOM_Y - _lift - sz.y))

func _setup_sprite() -> void:
	# LAW 1: 64px art at exactly 2.0 — the same grid as the player, the tiles and
	# the tokens. 2.2 was a third pixel size in the same frame. Set ONCE, and
	# unconditionally: the scene ships this node at 2.5, so it has to be
	# overridden even on the path where the texture is missing, and nothing
	# animates it any more (see _animate_sprite) because a breathing scale is a
	# breathing grid.
	sprite.scale = Vector2(2.0, 2.0)
	var kind: String = NPC_KIND.get(npc_id, "maintainer")
	var path := "res://assets/textures/generated/npc_%s.png" % kind
	if ResourceLoader.exists(path):
		sprite.texture = load(path)
		sprite.modulate = Color.WHITE
		sprite.position = Vector2(0, -18)
	# A soft shadow so NPCs sit in the world like the player.
	var shadow_tex := "res://assets/textures/generated/player_shadow.png"
	if ResourceLoader.exists(shadow_tex):
		var sh := Sprite2D.new()
		sh.texture = load(shadow_tex)
		sh.position = Vector2(0, 8)
		sh.z_index = -1
		add_child(sh)

## Gentle breathing so NPCs feel alive rather than painted onto the floor, plus
## the attention layer: they lean toward you and their name resolves out of the
## dark as you close. LAW 9 sets the amplitude for all of it: characters breathe
## ONE pixel.
func _process(delta: float) -> void:
	_anim_t += delta
	var player := get_tree().get_first_node_in_group("player")
	var dist := INF
	var dx := 0.0
	if player is Node2D:
		var pp: Vector2 = (player as Node2D).global_position
		dist = global_position.distance_to(pp)
		dx = pp.x - global_position.x
	_animate_sprite(delta, dist, dx)
	_animate_nameplate(delta, dist)
	_animate_indicator(delta)
	_tick_bark(delta, dist)

func _animate_sprite(delta: float, dist: float, dx: float) -> void:
	if not is_instance_valid(sprite):
		return
	# LAW 9: one pixel of breath, and it is spent on POSITION, never on scale —
	# round 5 oscillated the scale between 2.156 and 2.266, i.e. the character
	# was on a different pixel grid from the floor on every single frame.
	# roundf() lands it on a whole world pixel: 0, then 1, then 0 — exactly one
	# pixel of travel, half a second each way.
	sprite.position.y = _spr_base_y + roundf(0.5 + 0.5 * sin(_anim_t * 1.4))
	# The notice-pop startle decays as before; it just no longer resizes anybody.
	_notice_pop = maxf(_notice_pop - delta * 2.4, 0.0)
	# Lean toward the player. A nearly symmetric sprite reads a small shift far
	# better than a flip — and a SHIFT, not the old 4-degree rotation, because
	# rotating a pixel sprite resamples every pixel in it (LAW 1).
	var want_lean := 0.0
	if dist < NOTICE_RADIUS and absf(dx) > 6.0:
		want_lean = signf(dx)
	_lean = move_toward(_lean, want_lean, delta * 2.6)
	sprite.position.x = roundf(_lean * 2.0)
	# Interaction highlight: a small STILL step-up when the player is close
	# enough to talk — the world's way of saying "this one has lines". Round 5
	# pulsed it to an overbright 1.65, which put every NPC in the room into the
	# same brightness band as the player (LAW 3) twice a second (LAW 9).
	_hl_gate = move_toward(_hl_gate, 1.0 if dist < HIGHLIGHT_RADIUS else 0.0, delta * 5.0)
	if _hl_gate > 0.001:
		sprite.self_modulate = Color.WHITE.lerp(Color(1.12, 1.14, 1.16), _hl_gate)
	elif sprite.self_modulate != Color.WHITE:
		sprite.self_modulate = Color.WHITE

func _animate_nameplate(delta: float, dist: float) -> void:
	# The waypoint can retarget without any quest signal firing (objective steps
	# advance inside a quest), so the offset is re-checked on a slow timer rather
	# than trusted to _on_quest_changed alone.
	_lift_poll -= delta
	if _lift_poll <= 0.0:
		_lift_poll = LIFT_POLL
		_refresh_lift()
	if not is_equal_approx(_lift, _lift_want):
		_set_lift(move_toward(_lift, _lift_want, delta * LIFT_RATE))
	if not is_instance_valid(label):
		return
	var want := 1.0 if dist < NAME_RADIUS else 0.0
	_name_gate = move_toward(_name_gate, want, delta * 3.0)
	label.modulate.a = lerpf(NAME_MIN_ALPHA, 1.0, _name_gate)

## The plate steps up only while the objective waypoint is parked on this NPC —
## which is the one and only case where a second plate shares its band.
func _refresh_lift(instant: bool = false) -> void:
	_lift_want = NAME_TARGET_LIFT if _is_objective_target() else 0.0
	if instant:
		_set_lift(_lift_want)

func _animate_indicator(delta: float) -> void:
	if not is_instance_valid(indicator):
		return
	# While a bark is up, the marker politely gets out of its way.
	_bark_gate = move_toward(_bark_gate, 1.0 if _bark_visible() else 0.0, delta * 6.0)
	if not indicator.visible:
		return
	# A 2px bob and nothing else. Round 5 also swayed it 7 degrees and pulsed
	# its scale at 6.4 rad/s — LAW 9 allows the bob; the rest was a marker
	# competing with the objective waypoint that is already pointing at it.
	indicator.position.y = _ind_base_y + roundf(sin(_anim_t * 2.2) * 2.0)
	var duck := 1.0 - _bark_gate * 0.75
	indicator.scale = _ind_base_scale * duck
	# The marker and its glyph both step aside while this NPC is speaking.
	indicator.modulate.a = 1.0 - _bark_gate

func _on_interact(_player: Node) -> void:
	# Don't bark the instant a conversation ends — that reads as a bug, not a bit.
	_bark_cd = maxf(_bark_cd, BARK_AFTER_TALK)
	_hide_bark()
	DialogueManager.start_dialogue(npc_id)

## Accepts both quest_started(quest_id) and quest_completed(quest_id, rewards).
## The old 1-arg handler failed arity on quest_completed and never fired, so
## indicators went stale after turn-ins.
func _on_quest_changed(_a = null, _b = null) -> void:
	_update_indicator()
	_refresh_lift()

## Gold "!" = this NPC is holding a quest you have not taken.
## Cyan "▸" = this NPC is literally the current objective. Either way the marker
## means "walk here and press [E]", which is the only thing it has ever meant.
func _update_indicator() -> void:
	if not is_instance_valid(indicator):
		return
	var has_quest := _has_available_quest()
	var is_target := _is_objective_target()
	indicator.visible = has_quest or is_target
	if not indicator.visible or _mark == null:
		return
	# Two states, two colours, both from the master palette and neither of them
	# overbright: GOLD for "this one is holding a quest", the region-neutral
	# CYAN for "this one IS the objective".
	if has_quest:
		_mark.text = "!"
		_mark.position = Vector2(-5, -15)
		_mark.add_theme_color_override("font_color", _GameTheme.GOLD)
		indicator.self_modulate = Color(0.98, 0.84, 0.30, 0.55)
	else:
		_mark.text = "▸"
		_mark.position = Vector2(-7, -15)
		_mark.add_theme_color_override("font_color", _GameTheme.CYAN)
		indicator.self_modulate = Color(0.14, 0.94, 0.86, 0.55)

func _is_objective_target() -> bool:
	var cur: Dictionary = QuestManager.get_current_objective()
	if cur.is_empty():
		return false
	return str(cur.get("kind", "")) == "npc" and str(cur.get("node_id", "")) == npc_id

func _has_available_quest() -> bool:
	for qid in quest_ids:
		var info := QuestManager.get_quest_info(qid)
		if info.is_empty():
			continue
		if info.state == QuestManager.QuestState.INACTIVE:
			var prereqs: Array = QuestManager.quest_defs.get(qid, {}).get("prerequisites", [])
			var met := true
			for p in prereqs:
				if p not in QuestManager.completed_quests:
					met = false
			if met:
				return true
	return false

# ---------------------------------------------------------------------- barks --

func _bark_visible() -> bool:
	return is_instance_valid(_bark_panel) and _bark_panel.visible

## One bark per approach, then silence until you leave and come back. The whole
## point is that it feels like being noticed, not like being nagged.
func _tick_bark(delta: float, dist: float) -> void:
	if _bark_cd > 0.0:
		_bark_cd -= delta
	if _bark_visible() and (DialogueManager.is_active or GameManager.state != GameManager.GameState.PLAYING):
		_hide_bark()
	if dist > BARK_RESET_RADIUS:
		_bark_armed = true
		_noticed = false
		return
	# The startle fires on approach whether or not they have anything to say.
	if dist < NOTICE_RADIUS and not _noticed:
		_noticed = true
		_notice_pop = 1.0
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

func _say_bark() -> void:
	var pool := _bark_pool()
	if pool.is_empty() or not is_instance_valid(_bark_panel):
		return
	NPC._last_bark_at = _now()
	# Bag key includes the pool size so a state-dependent pool never deals a
	# stale index into a shorter list.
	_bark_label.text = _Comedy.pick("bark:%s:%d" % [npc_id, pool.size()], pool)
	_bark_panel.visible = true
	_bark_panel.modulate.a = 0.0
	# A Control parented to a Node2D has no container driving its layout, so the
	# bubble has to size itself to the new line before we can center it.
	_bark_panel.reset_size()
	_place_bark()
	if _bark_tween and _bark_tween.is_valid():
		_bark_tween.kill()
	# A fade, not a pop: the scale-in that used to run alongside it resampled
	# the text for the length of the tween (LAW 1) to say something the fade
	# already says.
	_bark_tween = _bark_panel.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_bark_tween.tween_property(_bark_panel, "modulate:a", 1.0, _GameTheme.T_STD)
	_bark_tween.tween_interval(BARK_HOLD)
	_bark_tween.tween_property(_bark_panel, "modulate:a", 0.0, 0.45)
	_bark_tween.tween_callback(_on_bark_finished)

func _hide_bark() -> void:
	if _bark_tween and _bark_tween.is_valid():
		_bark_tween.kill()
	_on_bark_finished()

func _on_bark_finished() -> void:
	_bark_tween = null
	if is_instance_valid(_bark_panel):
		_bark_panel.visible = false
		_bark_panel.modulate.a = 0.0

# ------------------------------------------------------------------ bark text --
#
# Rules for every line in here (docs/COMEDY_BIBLE.md):
#   * two short lines maximum — this is a bubble over a head, not a monologue;
#   * it must be true of THIS run, or true of the industry, or both;
#   * never punch down at the player. Punch at the systems that produced the
#     situation, and at the NPC's own complicity in it.

func _bark_pool() -> Array[String]:
	var out: Array[String] = []
	var debt := int(ResourceManager.get_value("technical_debt"))
	var tokens := int(ResourceManager.get_value("tokens"))
	var stability := int(ResourceManager.get_value("stability"))
	var wtl := int(ResourceManager.get_value("will_to_live"))
	var deaths: int = GameManager.death_count
	var agents: int = AgentManager.active_count() if AgentManager else 0
	var arch: Dictionary = ArchitectureManager.flags if ArchitectureManager else {}
	var ridiculous: int = ArchitectureManager.ridiculousness if ArchitectureManager else 0

	match npc_id:
		"roommate_ai":
			_claude_barks(out, debt, tokens, stability, wtl, deaths, agents, arch)
		"maintainer", "oss_maintainer":
			out.append("Still using my package.\nStill not sponsoring. It's fine.")
			out.append("I maintain this in my evenings.\nThis is my evening.")
			out.append("New issue. Title: 'urgent'.\nBody: 'doesn't work'. No version.")
			out.append("Forty million downloads a month\nand one folding chair.")
			if debt >= 40:
				out.append("You smell faintly of a monorepo.")
			if deaths >= 3:
				out.append("You keep dying near my repo.\nThat is not a supported use case.")
			if _passes >= 3:
				out.append("You've walked past me three times.\nSo has everyone. For eleven years.")
		"stackoverflow_hermit":
			out.append("Ask. Someone will close it.\nProbably me. Sorry in advance.")
			out.append("That was answered in 2011.\nThe answer was wrong then, too.")
			out.append("Read the FAQ.\nNobody has read the FAQ since 2013.")
			out.append("Every accepted answer here\noutlived the language it was for.")
			if deaths >= 2:
				out.append("Your death has been marked\nas a duplicate.")
			if _passes >= 3:
				out.append("Still browsing. Still not asking.\nHonestly? Wise.")
		"api_reseller":
			out.append("Browsing is free.\nBrowsing thoughtfully is billable.")
			out.append("Free tier: three requests.\nPer lifetime. Yours, specifically.")
			out.append("This key definitely works.\nDefinitely. Mostly. Sometimes.")
			out.append("Prices went up while you read that.\nNothing personal. Market conditions.")
			if tokens < 25:
				out.append("Short on tokens? I do financing.\nThe interest is emotional.")
			if tokens >= 250:
				out.append("You're carrying %d tokens.\nLet's talk about a bundle." % tokens)
		"cloud_salesperson":
			out.append("Have you considered moving\nthat to the cloud? Any of it?")
			out.append("It's elastic.\nI've never been told which way.")
			out.append("We can migrate you today.\nMigrating back is a separate SKU.")
			if arch.get("hosting") == "cloud":
				out.append("Your invoice is growing beautifully.\nWe call that adoption.")
			else:
				out.append("Still hosting on the laptop?\nCharming. Unscalable, but charming.")
			if _passes >= 3:
				out.append("I've followed up three times.\nThat's not persistence, that's process.")
		"svp_ai", "enterprise_architect":
			out.append("Do we have an AI strategy?\nThe board asked. I said yes.")
			out.append("Let's take this offline.\nWe are offline. That's the issue.")
			out.append("Great velocity.\nRemind me what velocity is.")
			out.append("I've booked a workshop\nabout why the workshops aren't working.")
			if ridiculous >= 3:
				out.append("Your architecture is enterprise-grade.\nI mean that as a warning.")
			if arch.get("structure") == "microservices":
				out.append("Forty-seven services. Beautiful.\nWho owns them? ...Anyone?")
		"gpu_foreman":
			out.append("Mind the cables. And the heat.\nMostly the bills.")
			out.append("Rig four's been hot since February.\nWe zip-tied it. It's fine.")
			out.append("If it ever stops screaming,\ncome and find me immediately.")
			out.append("Training run: 71%.\nIt has been 71% since Tuesday.")
			if stability <= 40:
				out.append("Rigs hot, app wobbling.\nRelated? No. Ominous? Yes.")
		"oncall_engineer":
			out.append("Thirty-eight hours awake.\nThe bugs have names now.")
			out.append("It's not DNS.\n...I'm going to check DNS.")
			out.append("The runbook's four steps.\nStep three is 'blame DNS'.")
			if stability <= 40:
				out.append("Stability %d. The pager can smell that." % stability)
			if deaths >= 2:
				out.append("You've gone down %d times tonight.\nWelcome to the rotation." % deaths)
		"junior_agent":
			out.append("I refactored something!\nI'm 100% confident!")
			out.append("I opened 41 pull requests.\nThey're all the same file.")
			out.append("I read the docs!\nThey were from six months ago!")
			out.append("I fixed the test.\nI deleted the test. Same outcome.")
			if agents > 0:
				out.append("Your other agents and I\nformed a working group.")
			if debt >= 40:
				out.append("I noticed some debt, so I refactored\nauth. And the database. And your CV.")
		_:
			out.append("Busy night?\nIt's always a busy night.")
			out.append("Everyone here is shipping something.\nNobody here has shipped anything.")
	return out

## Claude is the one who has been in the room the whole time. His barks are the
## running tally of an evening he did not agree to but is now invested in.
func _claude_barks(out: Array[String], debt: int, tokens: int, stability: int,
		wtl: int, deaths: int, agents: int, arch: Dictionary) -> void:
	out.append("You walked past the desk again.\nI notice. It's most of what I do.")
	out.append("The README still says\n'TODO: everything'. Still ambitious.")
	out.append("You renamed the project again.\nThat's branding, not architecture.")
	out.append("No commits yet.\nGit has no feelings. I have some.")
	out.append("I'm not judging you.\nI'm logging you, which is worse.")
	out.append("You could sleep.\nHypothetically. Academically.")

	var tiers := int(DreamAppManager.get_totals().get("total_tiers", 0))
	var talks := int(DialogueManager.claude_state.get("talks", 0))
	if tiers == 0:
		out.append("Zero upgrades bought.\n[B] opens the console. One key.")
	if DreamAppManager.can_ship():
		out.append("You can ship. Right now.\nYou are, instead, standing here.")
	if tokens < 20:
		out.append("%d tokens. That's not a balance,\nthat's a rounding error." % tokens)
	if tokens >= 250:
		out.append("%d tokens, unspent.\nHoarding is not a roadmap." % tokens)
	if debt >= 40:
		out.append("The technical debt says hello.\nIt's staying the weekend.")
	if debt >= 70:
		out.append("The debt sent a calendar invite.\nIt recurs. Of course it recurs.")
	if wtl <= 40:
		out.append("You've blinked twice in a minute.\nDrink water. That's the whole note.")
	if stability <= 30:
		out.append("Stability %d.\nProduction is holding its breath." % stability)
	if deaths == 1:
		out.append("You died once tonight.\nI kept the tab open. No reason.")
	if deaths >= 4:
		out.append("Death number %d.\nI've started a chart. It's going up." % deaths)
	if agents > 0:
		out.append("Your agent is 'almost done'.\nIt has been almost done a while.")
	if arch.get("testing") == "later":
		out.append("'Tests later.'\nIt is later. This is later.")
	if arch.get("security") == "velocity":
		out.append("Security traded for velocity.\nSomewhere, a form is being filled in.")
	if CycleManager and CycleManager.cycle >= 3:
		out.append("Cycle %d.\nThe reset is not impressed either." % CycleManager.cycle)
	if _passes >= 4:
		out.append("Lap %d past my desk.\nWe could just talk. [E]." % _passes)
	if talks >= 4:
		out.append("We've spoken %d times tonight.\nYou keep asking. I keep answering." % talks)
