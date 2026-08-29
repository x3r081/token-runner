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

## Nameplate furniture built in code: the leader that ties the plate to the head,
## and the deliberate lift that keeps the plate off the objective waypoint's
## distance readout when this NPC is the one the waypoint is pointing at.
var _name_tail: Node2D = null
var _tail_stem: Line2D = null
var _lift := 0.0
var _lift_want := 0.0
var _lift_poll := 0.0

const HIGHLIGHT_RADIUS := 100.0
## Nameplates gain a little presence as you approach — but the floor is a LEGIBLE
## alpha, not a decorative one. This constant used to be 0.3, and because
## `label.modulate` scales the whole Control it took the plate, the border, the
## text AND its outline down with it: every quest-giver more than NAME_RADIUS
## away was a ghost of accent-coloured text on a dark floor ("Shady API
## Reseller", "GPU Mine Foreman", "SVP of AI Transformation Excellence" — all of
## them unreadable in the QA frames, and all of them mistaken for props drawing
## over the plate, which is not what was happening). A nameplate is UI. It reads
## first and stylises second.
const NAME_RADIUS := 340.0
const NAME_MIN_ALPHA := 0.88
## Bottom edge of the nameplate in world space — clear of the sprite's head.
const NAME_BOTTOM_Y := -86.0
## Where the leader line has to stop so it never draws across a character.
##
## Measured off the QA frames, not derived from the texture box: the 64px sprite
## (scale 2.2, origin y -18) has transparent padding above the art, and the art
## itself varies. In region_localhost.png Claude's hair tops out around world
## -80; in region_api_bazaar.png the Junior Agent's antenna reaches about -82 and
## his hair only -68. -78 therefore TOUCHES every sprite in the cast — 2 to 4
## world px of overlap, which is what makes it read as a leader landing on a
## character rather than a line floating near one — without reaching the face on
## any of them. The nameplate, the notch and the stem all sit on absolute z
## (Z_NAME band) and so paint OVER the sprite: an overshoot here is not a leader,
## it is a scratch down somebody's portrait. The first pass used -72, which is
## 8-10px into Claude's hair.
const NAME_HEAD_Y := -78.0
## Leader geometry: a bubble notch under the plate plus a hairline stem down to
## the head, so the plate is owned by ONE npc no matter what the floor behind it
## is doing. Without it, "The Junior Agent" reads as a caption belonging to the
## bazaar plaza it happens to be sitting on.
const NAME_TAIL_HALF_W := 6.0
const NAME_TAIL_H := 7.0
## Any accent, on a near-black plate, has to land at least this bright.
##
## Honest accounting, because the numbers matter: hot_of() already carries every
## accent in NPC_ACCENT to 0.71-0.94 luma, so for today's cast this floor is a
## no-op on eight of eleven and a 15%-toward-white nudge on the three darkest
## (#FF2D95 reseller pink 0.707, #FF4757 on-call red 0.732, #8B5CF6 junior
## violet 0.735). It is a guard rail for the NEXT accent somebody adds, not the
## thing that fixed the unreadable plates — NAME_MIN_ALPHA and the plate
## background did that.
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
## The whole attention stack moves as one unit and the leader stem grows to cover
## the distance, so nothing about the plate's ownership of this NPC weakens.
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
## nameplates. The BODY joins the y-sort like everything else; the nameplate,
## marker and bark bubble are lifted onto absolute z values above every prop
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

## The nameplate used to sit at -50..-30 in a fixed 120px box, i.e. directly
## across the NPC's chest AND too narrow for "SVP of AI Transformation
## Excellence". It now sizes itself from the real font (so it cannot clip), sits
## clear above the sprite (content tops out near -80 world px), and wears a dark
## glass plate in the character's accent so it reads on a neon floor.
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
	label.add_theme_stylebox_override("normal", _nameplate_box())
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_font_override("font", _GameTheme.spaced_font(1))
	label.add_theme_color_override("font_color", _plate_text_color())
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.024, 0.055, 0.95))
	# The plate carries the contrast now, so the outline only has to crisp the
	# glyph edges. A 5px outline at 13px type reads as a smudge, not as weight.
	label.add_theme_constant_override("outline_size", 3)
	label.modulate.a = NAME_MIN_ALPHA
	_build_name_tail()
	# Measured, not guessed: reset_size() takes the font's real extents plus the
	# plate margins, which is the only way a nameplate can never clip.
	label.reset_size()
	label.resized.connect(_place_nameplate)
	_place_nameplate()

## Accent hue, forced up to a legible luminance. Linear in the lerp parameter, so
## the exact blend is solved rather than searched.
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

## Compact dark plate, 1px accent hairline. Deliberately quieter than the bark
## bubble: a name is a label, a bark is a statement.
##
## The plate is near-opaque and carries its own dark drop halo. That halo is what
## lets the plate survive being drawn against the brightest things in the game —
## the bazaar's lit plaza tiles, cloud_district's white satellite dishes,
## dependency_district's overbright node_modules crystals — instead of dissolving
## into them.
func _nameplate_box() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = _GameTheme.with_alpha(_GameTheme.BASE, 0.93)
	s.border_color = _GameTheme.with_alpha(_accent, 0.85)
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.content_margin_left = 9.0
	s.content_margin_right = 9.0
	s.content_margin_top = 3.0
	s.content_margin_bottom = 3.0
	s.shadow_color = _GameTheme.with_alpha(_GameTheme.VOID, 0.62)
	s.shadow_size = 6
	return s

## The leader: a bubble notch bolted to the plate's bottom edge and a hairline
## stem running down to the top of the head. Built once, resized only when the
## plate moves.
func _build_name_tail() -> void:
	if is_instance_valid(_name_tail):
		return
	_name_tail = Node2D.new()
	_name_tail.name = "NameTail"
	_name_tail.z_as_relative = false
	_name_tail.z_index = Z_NAME - 1
	_name_tail.modulate.a = NAME_MIN_ALPHA
	add_child(_name_tail)

	_tail_stem = Line2D.new()
	_tail_stem.name = "TailStem"
	_tail_stem.width = 2.0
	# 0.45 was fine for the 7px stub the stem is at rest. Lifted it spans ~39
	# world px and is the only thing saying which character the floating plate
	# belongs to, so it has to survive a neon floor behind it.
	_tail_stem.default_color = _GameTheme.with_alpha(_accent, 0.62)
	_tail_stem.points = PackedVector2Array([Vector2(0, NAME_TAIL_H), Vector2(0, NAME_TAIL_H)])
	_name_tail.add_child(_tail_stem)

	var notch := Polygon2D.new()
	notch.name = "TailNotch"
	notch.polygon = PackedVector2Array([
		Vector2(-NAME_TAIL_HALF_W, 0.0),
		Vector2(NAME_TAIL_HALF_W, 0.0),
		Vector2(0.0, NAME_TAIL_H)])
	notch.color = _GameTheme.with_alpha(_accent, 0.85)
	_name_tail.add_child(notch)

## Bottom edge of the plate right now — the default height, or lifted clear of
## the objective waypoint's readout while this NPC is the tracked objective.
func _name_bottom() -> float:
	return NAME_BOTTOM_Y - _lift

func _place_nameplate() -> void:
	if is_instance_valid(label):
		var sz: Vector2 = label.size
		label.position = Vector2(-sz.x * 0.5, _name_bottom() - sz.y)
	if is_instance_valid(_name_tail):
		_name_tail.position = Vector2(0.0, _name_bottom())
		# The stem stretches to absorb the lift, so the plate never floats free of
		# the character it names. Whole-array assignment rather than
		# set_point_position(): `points` is the form the rest of this codebase
		# uses (combat_fx.gd, enemy_base.gd, projectile.gd) and a member that
		# turns out not to exist here would silently kill every NPC.
		if is_instance_valid(_tail_stem):
			var tip := maxf(NAME_TAIL_H, NAME_HEAD_Y - _name_bottom())
			_tail_stem.points = PackedVector2Array([
				Vector2(0.0, NAME_TAIL_H), Vector2(0.0, tip)])

## One deliberate offset for the whole attention stack — plate, leader, quest
## marker and bark all move together, so their spacing is preserved exactly.
func _set_lift(v: float) -> void:
	if is_equal_approx(_lift, v):
		return
	_lift = v
	_place_nameplate()
	_place_bark()
	if is_instance_valid(indicator):
		_ind_base_y = INDICATOR_Y - _lift

## The quest indicator used to be a textureless (invisible) sprite. Give it an
## actual "!" over an overbright gold halo, so open quests advertise themselves.
func _build_indicator_glow() -> void:
	if not is_instance_valid(indicator):
		return
	# Clear of the nameplate, which owns roughly -110..-86 at rest.
	indicator.position = Vector2(0, INDICATOR_Y - _lift)
	indicator.z_as_relative = false
	indicator.z_index = Z_MARKER
	var dot := FxLib.glow_dot()
	if dot and indicator.texture == null:
		indicator.texture = dot
		indicator.material = FxLib.additive_material()
		indicator.modulate = Color(2.4, 2.0, 0.5, 0.9)  # overbright GOLD halo
		indicator.scale = Vector2(1.6, 1.6)
	_ind_base_scale = indicator.scale
	var mark := Label.new()
	mark.name = "Mark"
	mark.text = "!"
	mark.add_theme_font_size_override("font_size", 18)
	mark.add_theme_color_override("font_color", Color(1.0, 0.92, 0.4))
	mark.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.09, 0.95))
	mark.add_theme_constant_override("outline_size", 5)
	mark.position = Vector2(-5, -15)
	indicator.add_child(mark)
	_mark = mark

## The bark bubble: one PanelContainer + one Label, built once and reused for the
## whole run. No per-bark allocation beyond the line of text itself.
func _build_bark_bubble() -> void:
	_bark_panel = PanelContainer.new()
	_bark_panel.name = "Bark"
	_bark_panel.add_theme_stylebox_override("panel", _GameTheme.glass_box(_accent, 9.0))
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
	_bark_label.add_theme_font_size_override("font_size", 13)
	_bark_label.add_theme_color_override("font_color", _GameTheme.TEXT)
	_bark_label.add_theme_color_override("font_outline_color", Color(0.02, 0.024, 0.055, 0.95))
	_bark_label.add_theme_constant_override("outline_size", 5)
	_bark_panel.add_child(_bark_label)
	_bark_panel.resized.connect(_place_bark)

func _place_bark() -> void:
	if not is_instance_valid(_bark_panel):
		return
	var sz: Vector2 = _bark_panel.size
	_bark_panel.pivot_offset = Vector2(sz.x * 0.5, sz.y)
	_bark_panel.position = Vector2(-sz.x * 0.5, BARK_BOTTOM_Y - _lift - sz.y)

func _setup_sprite() -> void:
	var kind: String = NPC_KIND.get(npc_id, "maintainer")
	var path := "res://assets/textures/generated/npc_%s.png" % kind
	if ResourceLoader.exists(path):
		sprite.texture = load(path)
		sprite.modulate = Color.WHITE
		sprite.scale = Vector2(2.2, 2.2)
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
## the attention layer: they turn toward you, flinch slightly when you arrive,
## and their nameplate resolves out of the dark as you close.
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
	var b := sin(_anim_t * 1.9)
	sprite.position.y = _spr_base_y + b * 2.6
	# Notice-pop: a small startle the moment you enter their bubble, decaying.
	_notice_pop = maxf(_notice_pop - delta * 2.4, 0.0)
	var pop := _notice_pop * _notice_pop * 0.16
	sprite.scale = Vector2(
		2.2 * (1.0 - b * 0.02 - pop * 0.5),
		2.2 * (1.0 + b * 0.03 + pop))
	# Lean toward the player: a nearly symmetric sprite reads a tilt far better
	# than a flip, so we tilt (and nudge) instead of mirroring.
	var want_lean := 0.0
	if dist < NOTICE_RADIUS and absf(dx) > 6.0:
		want_lean = signf(dx)
	_lean = move_toward(_lean, want_lean, delta * 2.6)
	sprite.rotation = _lean * 0.075
	sprite.position.x = _lean * 3.0
	# Interaction highlight: a soft overbright rim pulse when the player is close
	# enough to talk — the world's way of saying "this one has lines".
	_hl_gate = move_toward(_hl_gate, 1.0 if dist < HIGHLIGHT_RADIUS else 0.0, delta * 5.0)
	if _hl_gate > 0.001:
		var pulse := 0.55 + 0.45 * sin(_anim_t * 3.6)
		sprite.self_modulate = Color.WHITE.lerp(Color(1.4, 1.55, 1.65), _hl_gate * pulse * 0.8)
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
	var a := lerpf(NAME_MIN_ALPHA, 1.0, _name_gate)
	label.modulate.a = a
	if is_instance_valid(_name_tail):
		_name_tail.modulate.a = a

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
	# The "!" floats, sways, and pulses — impossible to miss, hard to hate.
	indicator.position.y = _ind_base_y - 2.0 + sin(_anim_t * 3.2) * 5.0
	indicator.rotation = sin(_anim_t * 2.1) * 0.12
	var duck := 1.0 - _bark_gate * 0.75
	indicator.scale = _ind_base_scale * (1.0 + 0.1 * sin(_anim_t * 6.4)) * duck
	indicator.modulate.a = 0.9 * (1.0 - _bark_gate)

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
	if has_quest:
		_mark.text = "!"
		_mark.position = Vector2(-5, -15)
		_mark.add_theme_color_override("font_color", Color(1.0, 0.92, 0.4))
		indicator.modulate = Color(2.4, 2.0, 0.5, 0.9)
	else:
		_mark.text = "▸"
		_mark.position = Vector2(-7, -15)
		_mark.add_theme_color_override("font_color", Color(0.6, 1.0, 0.96))
		indicator.modulate = Color(0.5, 2.4, 2.2, 0.9)

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
	_bark_panel.scale = Vector2(0.92, 0.92)
	# A Control parented to a Node2D has no container driving its layout, so the
	# bubble has to size itself to the new line before we can center it.
	_bark_panel.reset_size()
	_place_bark()
	if _bark_tween and _bark_tween.is_valid():
		_bark_tween.kill()
	_bark_tween = _bark_panel.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_bark_tween.tween_property(_bark_panel, "modulate:a", 1.0, _GameTheme.T_STD)
	_bark_tween.parallel().tween_property(_bark_panel, "scale", Vector2.ONE, _GameTheme.T_STD)
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
