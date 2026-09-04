class_name BossHud
extends CanvasLayer
## Boss presentation: the name card, the health bar, the phase call-outs and the
## defeat stamp. Created and owned by EnemyBase when `is_boss` is set, so a boss
## carries its own UI and nothing else in the project has to know it exists.
##
## Layer 3: below the HUD (`hud.gd` HUD_LAYER = 4), the guide overlay (8), event
## popups (15) and dialogue (20) — a conversation, an incident ticket and the
## player's own readout all outrank a boss.
##
## ROUND 11 — NOTHING AT REST, AND NOTHING LEFT BEHIND.
##
## Round 7 deleted the two plated panels. What round 10's frames still showed was
## worse than a plate, because it was a lie. Three separate faults produced it,
## and all three are fixed here:
##
##   1. IT PLAYED AT REGION ENTRY. enemy_base.gd calls `play_entrance()` the
##      moment the boss is within 620 units, and region_builder spawns enemies
##      >= 415 units from the region's own spawn point — so every boss room
##      announced itself on arrival, before the player had taken a step. The
##      card is GATED (see `_poll_engagement`): the layer arms on that call and
##      shows nothing until the boss is actually ENGAGED.
##   2. THE GATE'S OWN RADIUS WAS THE SPAWN RADIUS. Round 10 gated on distance
##      alone at 420, which is the number region_builder.gd guarantees BETWEEN
##      the arrival plaza and every enemy it places (`_random_pos(rng, spawn,
##      420.0)`, `_safe_scatter`'s >= 415 fallback). A boss standing exactly where
##      the builder put it already satisfied that test, and one step of its own
##      approach carried it over — so region_cloud_district.png,
##      region_stackoverflow_ruins.png and region_token_vault.png STILL captured
##      a card, a sub-caption's worth of clear air and a 600px bar over a quiet
##      room. Distance is now only the outer bound; see ENGAGEMENT.
##   3. IT SURVIVED THE ROOM IT BELONGED TO. region_api_bazaar.png prints Stack
##      Overflow Ruins' "THE MERGE CONFLICT" in Ruins gold over the Bazaar's
##      market stall; region_open_source_wildlands.png prints Cloud District's
##      "THE $700 CLOUD BILL" in Cloud sky. This layer is not a child of the boss
##      by the time that matters — world.gd `_adopt_layer` reparents every
##      CanvasLayer born inside the pixel stage onto World, and its
##      `_purge_adopted` sweep runs from the deferred message queue, i.e. BEFORE
##      the scene tree flushes the delete queue that actually frees the old
##      region. The host is still valid when the sweep asks, so the sweep keeps
##      the layer, and a frame later the boss is gone and the card is not. A
##      layer that outlives its boss is this file's problem to notice: see
##      `_on_host_gone` and `_on_region_changed`.
##
## What it is, per VISUAL_BIBLE_V2 LAW 8:
##   NAME CARD   ONE line — the boss's name, HEADING size, in the region ACCENT,
##               on its own 1px shadow. No plate, no gradient, no incident
##               number, no sub-line, no rule under it. It appears when the fight
##               starts, holds 2.5s, and is gone. Never at region entry.
##   HEALTH      ONE 4px bar, in the band's second row, same accent. No border,
##               no label, no percentage, no phase chip, no plate. It arrives
##               with the card and stays until the boss dies; before the fight
##               starts there is nothing on this layer at all.
##   NOTHING     else. No scrim, no edge flare, no glow, no letterboxing. The
##               HUD is never dimmed by a cinematic and the world is never
##               darkened to make our text legible.
##
## The whole boss layer is therefore one column at the top of the frame, which
## is also the only place it can be: the bottom band is where the objective
## line, the toast lane, the ability slots and the key legend live.
##
## LANES (hud.gd's header owns the map; this is the one slot reserved here):
##   ANNOUNCEMENT BAND   y 222 down, centred, BAND_W wide. Below the waypoint's
##                       guidance band, which ends at 190 (objective_waypoint.gd
##                       GUIDE_BAND_BOTTOM). world_label.gd dodges captions out
##                       of the top 372 units while a boss is alive, which
##                       covers every row below.
##       y 222..256      the name line, and later the defeat stamp (transient)
##       y 310..314      the health bar (persistent, once engaged)
##       y 334..360      phase call-outs, and the defeat stamp's note
## Every row goes through `_band()`, which is what guarantees no call-out can
## land on the player, on a HUD lane, or across the bar.
##
## Nothing here blocks input or pauses the tree — the player fights through all
## of it. The layer is PROCESS_MODE_ALWAYS and every tween is
## TWEEN_PAUSE_PROCESS, so opening a dialogue mid-entrance cannot freeze a card
## at full opacity on screen (HANDOVER §4.4, the black-curtain bug).

const BAR_W := 600.0
## LAW 8's bar: four pixels, no border, no label chip. The same hairline the
## HUD's own HP and Focus bars are drawn at, so the two read as one system.
const BAR_H := 4.0
## Announcement band, in pixels from the top of the screen. 222 and not 112:
## `objective_waypoint.gd` pins its chevron at MARGIN_TOP = 112 and hangs its
## readout inside GUIDE_BAND_TOP..GUIDE_BAND_BOTTOM (112..190), so everything
## down to 190 belongs to guidance.
const BAND_TOP := 222.0
const BAND_W := 720.0
## The three rows of the band, as offsets from BAND_TOP.
const NAME_ROW_H := 34.0
## 88, and not 58, and certainly not the 40 it started at. A 600px hairline set
## close under a centred 26px title is read as an UNDERLINE, not as a gauge —
## every QA round has said so, round 10's included at 58, where the frames still
## show a rule under a sentence. The two rows are now three line-heights apart:
## far enough that the eye stops binding them into one object and starts reading
## a name and, separately, a health bar.
const BAR_ROW := 88.0
## Below the bar, not through it. Tracks BAR_ROW so the two never collide.
const CALLOUT_ROW := 112.0
## How long the whole entrance lasts: 0.25 in + ENTRANCE_DWELL + 0.32 out.
## Round 6 held it inside EnemyBase's 2.2s `_intro_lock` because the card was an
## opaque plate covering a third of the screen. One line of text is not a
## curtain, so the card is now allowed to finish fading ~0.3s after the boss
## starts acting, which is what "shown 2.5s then gone" costs.
const ENTRANCE_DWELL := 1.93

## ENGAGEMENT — the gate that keeps this layer off the screen at rest.
##
## enemy_base.gd emits no "engaged" signal. It decides in `_physics_process`
## that a boss has noticed you at 620 units and calls `play_entrance()` there,
## and region_builder.gd puts every enemy at least 415 units from the region
## spawn — so that call arrives on the frame the player walks into the room,
## which is exactly the frame the card must NOT play on.
##
## `play_entrance()` therefore only ARMS this layer. The card then waits for one
## of three things, every one of which means "you are in a fight" and none of
## which is true of a boss standing where the builder left it:
##
##   FIRST BLOOD    `set_health()` sees current < maximum. The honest signal that
##                  YOU started it; sniping a boss across the room still
##                  announces the fight.
##   IT SWUNG       `EnemyBase.is_committed()` — a wind-up, a charge, or a slam
##                  telegraph. It is the enemy's own public "the player has to
##                  react to this now", and nothing but a real fight sets it.
##   IT CLOSED      the boss is inside ENGAGE_RADIUS *and* has covered
##                  ENGAGE_CLOSE units since the layer armed.
##
## THE SECOND HALF OF THAT LAST TEST IS THE WHOLE FIX. ENGAGE_RADIUS is 420, and
## 420 is also the radius region_builder.gd guarantees between the arrival plaza
## and every enemy in the room — so "inside 420" is satisfied on the frame the
## player arrives, and round 10's frames prove it: three quiet rooms, three boss
## cards. Requiring the boss to have CLOSED on you separates "it is coming for
## me" from "it is over there", which is the distinction the gate was always
## trying to make and the one a bare radius cannot make in a room whose spawn
## rule uses the same number.
##
## Polled every ENGAGE_POLL rather than every frame: a card that lands within a
## quarter second of the boss closing is indistinguishable from one that lands
## on the exact frame, and this is a comparison per boss per quarter second
## instead of sixty per second.
const ENGAGE_RADIUS := 420.0
const ENGAGE_POLL := 0.25
## How much ground the boss must cover, from wherever it stood when this layer
## armed, before distance alone counts as engagement. Two thirds of a screen
## height: far enough that no spawn placement can satisfy it standing still, and
## short enough that a boss walking at you crosses it in about a second.
const ENGAGE_CLOSE := 120.0

## Comedy bible: the joke rides ALONGSIDE the information. The name is the
## information (which boss is this) and it is what the card prints; the epithet
## is the joke and it now lives where the player CHOOSES to read it (LAW 10) —
## `boss_sub` is still published for dialogue, the quest log and the results
## screen, it is simply not stamped over the world any more.
const BOSS_CARDS := {
	"merge_conflict": ["THE MERGE CONFLICT", "1,204 files changed · nobody remembers why"],
	"enterprise_architect": ["THE ENTERPRISE ARCHITECT", "has never merged a pull request"],
	"legacy_monolith": ["THE LEGACY MONOLITH", "written in 2009 · load-bearing · undocumented"],
	"legacy_system": ["THE LEGACY SYSTEM", "runs the payroll. do not touch the payroll."],
	"infinite_context": ["THE INFINITE CONTEXT", "remembers everything except the point"],
	"cloud_bill": ["THE $700 CLOUD BILL", "mostly egress. nobody can explain egress."],
	"dependency_demon": ["THE DEPENDENCY DEMON", "14,203 packages · three of them on purpose"],
	"scope_creep": ["SCOPE CREEP", "and one tiny last thing"],
	"hallucination": ["THE HALLUCINATION", "100% confident · 0% sourced"],
	"rate_limiter": ["THE RATE LIMITER", "429. try again in a period we won't specify."],
	"memory_leak": ["THE MEMORY LEAK", "it has been growing since Tuesday"],
	"null_reference": ["THE NULL REFERENCE", "cannot read properties of undefined"],
	"bug": ["THE BUG", "reproducible only when observed"],
}

## Indexed by PHASE - 1: entry 0 is phase 1, which announces nothing. EnemyBase
## passes the live phase number (2, 3, 4), so read these with `phase - 1`.
const PHASE_BANNERS := [
	"",
	"PHASE 2 — escalated to the wider team",
	"PHASE 3 — a war room has been opened",
	"PHASE 4 — the postmortem has been pre-written",
]

## THE ONE COLOUR THIS LAYER SPENDS — and it is the ROOM's, not the enemy's.
##
## Round 7 read `enemy_base.gd`'s DEATH_ACCENTS entry — magenta for the Merge
## Conflict, cyan for the Infinite Context, violet for Scope Creep — and painted
## the card and the bar with it: a fourth hue, on the loudest element in the
## frame, chosen by which enemy happened to be attacking. Round 9 replaced that
## with HOSTILE #FF4757 for every boss in every room, which fixed the rainbow and
## introduced a subtler version of the same fault: a red title and a red rule
## across a gold vault is still one more saturated hue than LAW 2 allows the
## scene, and the frames show exactly that.
##
## LAW 2 is explicit about which colour a UI element gets: "The UI uses one
## accent: the region ACCENT for the world-linked elements". A boss is as
## world-linked as an element gets — it is the room's set-piece — so the card and
## the bar are painted in the accent the objective line, the waypoint and the
## ready ability slots are already wearing. One accent on screen, and it belongs
## to where you are standing.
##
## Hostility is carried where LAW 7 puts it: on the enemy's own silhouette and
## its one red tell. It does not need the title too.
##
## HOSTILE stays as the fallback for a region nobody has authored an accent for.
## The same value as `GameTheme.RED`, spelled out because this is a class-level
## const; if one moves, move both.
const HOSTILE := Color("#FF4757")

var accent: Color = HOSTILE
var boss_name: String = "BOSS"
var boss_sub: String = "severity: yes · owner: unassigned"
## What the caller asked for, kept because it is honest about the parameter
## being read, and because the corpse VFX in `enemy_base.gd` still uses that
## per-enemy colour where a one-shot burst can afford one. Nothing on THIS
## layer paints with it.
var requested_tint: Color = HOSTILE

var _root: Control
var _card: Control
var _bar_root: Control
## The bar hangs off this, so damage can shake it without fighting the anchors
## that keep the row where it is.
var _frame: Control
var _track: ColorRect
var _fill: ColorRect
var _fill_tween: Tween
var _shake_tween: Tween
## The entrance's own tween, tracked so anything that needs the announcement
## band back (a phase call, the defeat stamp, `dismiss()`) can cut the card
## instead of stamping on top of one that is still mid-fade.
var _entrance_tween: Tween
var _entered := false
var _frac := 1.0
## The engagement gate. `_armed` is "the boss has noticed you and wants its
## card"; `_engaged` is "the fight is on and the card has been spent". Nothing
## on this layer is visible while the first is true and the second is not.
var _armed := false
var _engaged := false
var _poll_t := 0.0
## How far the boss stood from the player when the layer armed. The card needs it
## to have closed ENGAGE_CLOSE on that, so "it is coming for you" cannot be
## satisfied by a boss that has not moved. INF until the first poll reads it.
var _arm_dist := INF
## The enemy this layer belongs to, and the thing it measures distance to. Both
## are cached and both are re-checked with `is_instance_valid` — `detach()`
## hands this layer to the scene when the boss dies, and the player can be
## replaced by a respawn.
var _host: Node2D
var _player: Node2D
## Whether there was ever a boss to lose. A rig that mounts this layer under
## something that is not a Node2D (a test harness) has no host to outlive, and
## must not be mistaken for a layer whose boss has just been freed.
var _had_host := false
## Set the moment the death outro takes ownership: from here the boss node is
## LEGITIMATELY about to disappear and this layer must NOT follow it out. Every
## other way of losing the host — above all a region rebuild — is a stale card.
var _closing := false

func _init() -> void:
	layer = 3
	# A boss card that freezes at full opacity because someone opened a dialogue
	# mid-entrance is a screen-covering bug, not a pause.
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	# The enemy that owns this layer — `_build_boss_presence()` adds it as a
	# child, so the parent at _ready IS the boss. Captured before anything can
	# reparent it.
	_host = get_parent() as Node2D
	_had_host = _host != null
	# TWO WAYS TO OUTLIVE THE ROOM, so both are watched. The boss can be freed
	# under us (a region rebuild frees the whole region node, and by then
	# world.gd has already reparented this layer onto World — see the header),
	# and the region can change without the boss being freed on the same frame.
	if _had_host and not _host.tree_exited.is_connected(_on_host_gone):
		_host.tree_exited.connect(_on_host_gone)
	if not GameManager.region_changed.is_connected(_on_region_changed):
		GameManager.region_changed.connect(_on_region_changed)
	accent = _region_accent()
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# One theme for the layer: the aliased font, the one panel style, the 1px
	# label shadow. Every label below then only says its size and its colour.
	_root.theme = GameTheme.create(accent)
	add_child(_root)
	_build_bar()
	_bar_root.modulate.a = 0.0

## Whenever the tree is paused a full-screen modal is up and there is nothing to
## read here, so the bar steps out of the way rather than showing through. It
## keeps animating while paused — nothing freezes half-faded (HANDOVER §4.4) —
## it is only hidden.
func _process(delta: float) -> void:
	var tree := get_tree()
	if tree == null or not is_instance_valid(_root):
		return
	# The boss is gone and it was not the death outro that took it: the room this
	# card belongs to has been rebuilt under us. `tree_exited` normally gets here
	# first; this is the backstop for a host freed without ever leaving the tree
	# in a frame we saw.
	if _had_host and not _closing and not is_instance_valid(_host):
		_vanish()
		return
	var want := not tree.paused
	if _root.visible != want:
		_root.visible = want
	# Nothing moves behind a modal, so nothing can become engaged behind one
	# either — and a card that fired while the tree was paused would be waiting
	# at full opacity when the panel closed.
	if want and _armed and not _engaged:
		_poll_engagement(delta)

## Is the fight actually on? See the ENGAGEMENT block for the three tests and
## for why the distance one is not allowed to stand on its own.
func _poll_engagement(delta: float) -> void:
	_poll_t -= delta
	if _poll_t > 0.0:
		return
	_poll_t = ENGAGE_POLL
	if not is_instance_valid(_host):
		return
	# The enemy's own answer to "is the player being asked to react to me right
	# now" (EnemyBase.is_committed: a wind-up, a charge, a boss telegraph). It
	# cannot be true of a boss that has not reached you.
	#
	# Called dynamically: `_host` is typed Node2D — deliberately, because this
	# layer is mounted by EnemyBase and must not import it back — so the method is
	# not on the static type and `has_method` is the whole contract.
	if _host.has_method("is_committed") and bool(_host.call("is_committed")):
		_engage()
		return
	if not is_instance_valid(_player):
		_player = (get_tree().get_first_node_in_group("player_proxy") if get_tree().get_first_node_in_group("player_proxy") else get_tree().get_first_node_in_group("player")) as Node2D
		if _player == null:
			return
	var d := _host.global_position.distance_to(_player.global_position)
	if _arm_dist == INF:
		_arm_dist = d
	if d <= ENGAGE_RADIUS and d <= _arm_dist - ENGAGE_CLOSE:
		_engage()

## The fight has started: spend the card, and never arm again.
func _engage() -> void:
	if _engaged:
		return
	_mark_engaged()
	_run_entrance()

## "The fight is on" without playing the card — for the beats that can only
## happen mid-fight and are taking the band for themselves (a phase call-out, the
## defeat stamp). Without this, `_cancel_entrance()` could not tell a boss that
## was never engaged from one whose card has already been and gone, and would
## fade a health bar in under a stamp that is closing the incident.
func _mark_engaged() -> void:
	_engaged = true
	_armed = false

# ------------------------------------------------------------- lifetime ----

## The boss left the tree.
##
## If the death outro took it, `detach()` said so and the stamp is allowed to
## finish over the corpse. Any other route — and in practice that means a region
## rebuild freeing the room out from under a layer world.gd has already
## reparented onto World — leaves a card announcing a fight in a room that no
## longer exists. Go with the boss.
func _on_host_gone() -> void:
	if _closing:
		return
	_vanish()

## The room changed. Whatever this layer was saying belonged to the last one —
## an armed gate, a card mid-fade, a health bar, even a defeat stamp still
## closing the incident. None of it is true here. No fade: the world under it
## has already been replaced.
func _on_region_changed(_region_id: String) -> void:
	_vanish()

## Off the screen NOW, and gone. Hidden before `queue_free()`, which is deferred
## to the end of the frame — a layer the game has finished with must not be able
## to paint one more frame at whatever alpha it happens to hold.
func _vanish() -> void:
	# Three callers race to get here (the host's `tree_exited`, the region signal,
	# `_process`'s backstop) and `queue_free` only takes effect at the end of the
	# frame, so the losers must fall straight through.
	if is_queued_for_deletion():
		return
	_armed = false
	if _entrance_tween and _entrance_tween.is_valid():
		_entrance_tween.kill()
	_entrance_tween = null
	if _fill_tween and _fill_tween.is_valid():
		_fill_tween.kill()
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
	if is_instance_valid(_root):
		_root.visible = false
	queue_free()

## Every tween on this layer survives `get_tree().paused` — see the header.
func _tw() -> Tween:
	var t := create_tween()
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	return t

## Called by EnemyBase before the entrance plays.
##
## `tint` is recorded and NOT painted with — see the ACCENT block. The signature
## is unchanged so the call site does not have to know that the boss layer
## stopped having opinions about colour.
func setup(enemy_type: String, tint: Color) -> void:
	requested_tint = tint
	accent = _region_accent()
	var card: Array = BOSS_CARDS.get(enemy_type, [])
	if card.size() == 2:
		boss_name = str(card[0])
		boss_sub = str(card[1])
	else:
		boss_name = enemy_type.replace("_", " ").to_upper()
		boss_sub = "severity: yes · owner: unassigned"
	# The bar is built in `_ready`, which already resolved the room's accent; this
	# only matters if the region changed between the two calls, which it cannot.
	_apply_accent()

# ------------------------------------------------------------- the bar ----

## One 4px bar, centred, in the band's second row. Two ColorRects: the track it
## drains along and the accent that is left. No plate, no border, no name, no
## percentage, no epithet, no phase chip — every one of those was a second way
## of saying what the bar's own length already says.
func _build_bar() -> void:
	_bar_root = Control.new()
	_bar_root.name = "StatusFrame"
	_bar_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_root.anchor_left = 0.5
	_bar_root.anchor_right = 0.5
	_bar_root.offset_left = -BAR_W * 0.5
	_bar_root.offset_right = BAR_W * 0.5
	_bar_root.offset_top = BAND_TOP + BAR_ROW
	_bar_root.offset_bottom = BAND_TOP + BAR_ROW + BAR_H
	_root.add_child(_bar_root)

	_frame = Control.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.position = Vector2.ZERO
	_frame.size = Vector2(BAR_W, BAR_H)
	_bar_root.add_child(_frame)

	_track = ColorRect.new()
	_track.color = GameTheme.with_alpha(GameTheme.VOID, 0.72)
	_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track.position = Vector2.ZERO
	_track.size = Vector2(BAR_W, BAR_H)
	_frame.add_child(_track)

	# Flat accent, not a gradient with a hot top edge: LAW 8's bars report one
	# number and at four pixels tall the only thing that reads is their length.
	_fill = ColorRect.new()
	_fill.color = accent
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill.position = Vector2.ZERO
	_fill.size = Vector2(BAR_W, BAR_H)
	_track.add_child(_fill)

	_apply_accent()

## The room's accent, straight out of LAW 2's table. `GameTheme.region_accent`
## is the one place that table lives, so the HUD, the waypoint, the map and this
## layer cannot hold four opinions about what colour a region is.
func _region_accent() -> Color:
	return GameTheme.region_accent(GameManager.current_region)

## Re-tint everything the accent drives. Safe to call before or after the nodes
## exist; `setup()` calls it once the boss's identity is known.
func _apply_accent() -> void:
	if is_instance_valid(_fill):
		_fill.color = accent

## Health, 0..1 of max. The fill moves in 0.22s and anything over 6% of the bar
## kicks it sideways. The lagging red ghost, the white leading-edge chip and the
## live percentage are gone — the bar getting shorter is the readout.
func set_health(current: int, maximum: int) -> void:
	# First blood is engagement, whatever the distance: a boss you have shot is a
	# boss you are fighting, and the fight must never be anonymous. EnemyBase
	# calls this once at full health while building the rig, which is not damage
	# and must not trip the gate.
	if current < maximum:
		_engage()
	if not is_instance_valid(_fill):
		return
	var f := clampf(float(current) / float(maxi(1, maximum)), 0.0, 1.0)
	var lost := maxf(0.0, _frac - f)
	_frac = f
	if _fill_tween and _fill_tween.is_valid():
		_fill_tween.kill()
	_fill_tween = _tw()
	_fill_tween.tween_property(_fill, "size:x", BAR_W * f, 0.22) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if lost >= 0.06:
		_shake(minf(4.0, 2.0 + lost * 16.0))

## Kick the bar sideways. Only the inner frame moves — the anchors that keep the
## row where it is are untouched. Four pixels of travel at most: a hairline that
## wobbles further than its own height reads as a rendering fault.
func _shake(px: float) -> void:
	if not is_instance_valid(_frame):
		return
	# The entrance owns `_frame.position` while it rises. Two tweens on the same
	# property is how you get a bar that never settles.
	if is_instance_valid(_card):
		return
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
	_frame.position = Vector2.ZERO
	_shake_tween = _tw()
	for i in 3:
		var d: float = px * (1.0 - float(i) / 3.0)
		if i % 2 == 1:
			d = -d
		_shake_tween.tween_property(_frame, "position:x", d, 0.045)
	_shake_tween.tween_property(_frame, "position", Vector2.ZERO, 0.07)

# ---------------------------------------------------- announcement band ----

## A fresh, empty box in the reserved band. EVERY boss call-out goes through
## here, which is what guarantees none of them can land on the player, on a HUD
## lane, or on the health bar's own row.
func _band(height: float, top: float = BAND_TOP) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.anchor_left = 0.5
	c.anchor_right = 0.5
	c.offset_left = -BAND_W * 0.5
	c.offset_right = BAND_W * 0.5
	c.offset_top = top
	c.offset_bottom = top + height
	_root.add_child(c)
	return c

## Centred band label. No outline: the theme's one-pixel shadow does the job, and
## a 4–7px outline on a 26px title is a black slab with letters cut out of it.
func _band_label(host: Control, text: String, size: int, col: Color,
		top: float, height: float, spacing: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	if spacing > 0:
		l.add_theme_font_override("font", GameTheme.spaced_font(spacing))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.position = Vector2(0, top)
	l.size = Vector2(BAND_W, height)
	host.add_child(l)
	return l

# ------------------------------------------------------------ entrance ----

## ARM the layer. Called by EnemyBase the moment the boss notices the player,
## which is 620 units out and, in every boss room in the game, on the frame the
## player arrives — so this deliberately shows NOTHING. The card plays when the
## boss is genuinely engaged; see the ENGAGEMENT block and `_poll_engagement`.
##
## The name and the signature are unchanged: the call site asks for an entrance
## and gets one, a second or two later, when it means something.
func play_entrance() -> void:
	if _entered or _engaged or not is_instance_valid(_root):
		return
	_armed = true
	# Poll on the next tick rather than after a full quarter second, so a player
	# who walks straight into the arena is not kept waiting for a timer. The first
	# poll is also what records `_arm_dist` — where the boss stood when it noticed
	# you, which is the baseline "it has closed on you" is measured against.
	_poll_t = 0.0
	_arm_dist = INF

## The name fades in on the world, the bar fades in under it, the name fades out
## again. Nothing covers the player, nothing covers a world caption, and nothing
## touches a HUD lane.
##
## Length: 0.25 in + ENTRANCE_DWELL + 0.32 out = 2.50s.
func _run_entrance() -> void:
	if _entered or not is_instance_valid(_root):
		return
	_entered = true
	_card = _band(NAME_ROW_H)

	# ONE line. HEADING size, the room's accent, the theme's 1px shadow — the same
	# treatment the region name in the HUD strip gets, because it is the same
	# kind of statement: this is where you are, this is what you are fighting.
	_band_label(_card, boss_name, GameTheme.HEADING, accent, 0.0, NAME_ROW_H, 2)

	# The bar rises into place rather than appearing: 6px of travel reads as an
	# arrival and is short enough not to be a distraction.
	if is_instance_valid(_frame):
		_frame.position = Vector2(0, 6.0)
	_card.modulate.a = 0.0

	if _entrance_tween and _entrance_tween.is_valid():
		_entrance_tween.kill()
	var tw := _tw()
	_entrance_tween = tw
	tw.tween_property(_card, "modulate:a", 1.0, 0.25)
	tw.parallel().tween_property(_bar_root, "modulate:a", 1.0, 0.30)
	if is_instance_valid(_frame):
		tw.parallel().tween_property(_frame, "position", Vector2.ZERO, 0.30) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(ENTRANCE_DWELL)
	tw.tween_property(_card, "modulate:a", 0.0, 0.32)
	tw.tween_callback(_clear_card)

## The last beat of the entrance. `queue_free()` is deferred to the end of the
## frame, so hide it in the same call — a card the tween has finished with must
## not be able to paint one more frame at whatever alpha it happens to hold.
func _clear_card() -> void:
	if is_instance_valid(_card):
		_card.visible = false
		_card.queue_free()
	_card = null

## Take the announcement band back NOW.
##
## The entrance owns the band for 2.5s and `_frame.position` for the first 0.30s
## of that. Anything that needs either before it is done has to cut it rather
## than draw over a card that is still mid-fade. Leaves the bar settled and
## fully faded in, which is exactly where the entrance would have left it.
func _cancel_entrance() -> void:
	if _entrance_tween and _entrance_tween.is_valid():
		_entrance_tween.kill()
	_entrance_tween = null
	_clear_card()
	_armed = false
	if is_instance_valid(_frame):
		_frame.position = Vector2.ZERO
	# Where a COMPLETED entrance leaves the bar — so running this when there was
	# nothing to cancel is a no-op, and running it when the entrance was cut
	# short is the difference between a defeat draining a visible bar and
	# draining an invisible one. A boss that was NEVER ENGAGED never showed a
	# bar, and being dismissed is not a reason to reveal one for 0.3s on its way
	# out; `_mark_engaged()` is how the mid-fight callers say otherwise.
	if is_instance_valid(_bar_root):
		_bar_root.modulate.a = 1.0 if _engaged else 0.0

# -------------------------------------------------------------- phases ----

## One line under the bar, and gone again. The persistent phase chip is removed
## with the rest of the plate: the phase is a moment, and the bar's own length
## is the state you can still read ten seconds later.
func announce_phase(phase_index: int) -> void:
	if not is_instance_valid(_root):
		return
	# `phase_index` is the LIVE phase (2, 3, 4), and the table is written
	# phase-first — entry 0 is phase 1. Indexing it by the phase itself is off by
	# one, which is how the 75% gate printed phase 3's banner and phase 2's was
	# authored but unreachable. Read it with `phase - 1`.
	var phase := clampi(phase_index, 1, PHASE_BANNERS.size())
	var text: String = PHASE_BANNERS[phase - 1]
	if text.is_empty():
		return
	# A phase gate can only be crossed by damage, so the fight is on by
	# definition — and one hit big enough to cross a gate inside EnemyBase's
	# intro lock would otherwise stack this line on the entrance card, in the
	# same band.
	_mark_engaged()
	_cancel_entrance()

	var host := _band(26.0, BAND_TOP + CALLOUT_ROW)
	var lbl := _band_label(host, text, GameTheme.BODY, GameTheme.TEXT, 0.0, 26.0, 3)
	lbl.modulate.a = 0.0

	var tw := _tw()
	tw.tween_property(lbl, "modulate:a", 1.0, 0.18)
	tw.tween_interval(1.05)
	tw.tween_property(host, "modulate:a", 0.0, 0.35)
	tw.tween_callback(host.queue_free)

	_shake(3.0)
	AudioManager.play_sfx("denied")

# --------------------------------------------------------------- death ----

## Hand this layer to the current scene so the outro survives the corpse.
##
## `_closing` is set FIRST and unconditionally, before any of the early returns:
## it is what tells `_on_host_gone` that the boss is about to be freed on
## purpose. (The reparent itself is usually already done — world.gd's
## `_adopt_layer` moves every layer born inside the pixel stage onto World, which
## IS `current_scene`, so this then finds nothing to do.)
func detach() -> void:
	_closing = true
	var tree := get_tree()
	if tree == null:
		return
	var host: Node = tree.current_scene
	var p := get_parent()
	if host == null or host == self or p == null or p == host:
		return
	p.remove_child(self)
	host.add_child(self)

## Bar drains and the incident is formally closed, in the band the name used.
## One line and one dim line under it — the hairline rule between them went with
## every other divider on this layer.
func play_death() -> void:
	# The corpse is on a 0.45s clock and this outro runs for two seconds after it,
	# so the boss WILL be freed while the stamp is still on screen. Say so, even
	# if `detach()` was skipped.
	_closing = true
	if not is_instance_valid(_root):
		return
	# The stamp goes in the announcement band; a card still fading in it would
	# read as two incidents at once. Also settles the bar and its alpha — and a
	# boss that died was fought, whatever the gate saw.
	_mark_engaged()
	_cancel_entrance()
	if _fill_tween and _fill_tween.is_valid():
		_fill_tween.kill()
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
	if is_instance_valid(_frame):
		_frame.position = Vector2.ZERO
	_frac = 0.0

	# The stamp takes the name's row and the note takes the call-out row, so the
	# drained bar sits BETWEEN them rather than through the middle of a sentence.
	var host := _band(CALLOUT_ROW + 22.0)
	var stamp := _band_label(host, "INCIDENT CLOSED", GameTheme.HEADING,
		GameTheme.TEXT, 0.0, NAME_ROW_H, 6)
	var line := _band_label(host,
		"root cause: you · action items: 3 · completed: 0 · reopened next quarter: 3",
		GameTheme.SMALL, GameTheme.TEXT_DIM, CALLOUT_ROW, 22.0)
	stamp.modulate.a = 0.0
	line.modulate.a = 0.0

	var tw := _tw()
	if is_instance_valid(_fill):
		tw.tween_property(_fill, "size:x", 0.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	else:
		tw.tween_interval(0.5)
	tw.tween_callback(_death_beat)
	tw.parallel().tween_property(stamp, "modulate:a", 1.0, 0.22)
	tw.parallel().tween_property(line, "modulate:a", 1.0, 0.34)
	tw.tween_interval(1.4)
	tw.tween_property(_root, "modulate:a", 0.0, 0.6)
	tw.tween_callback(queue_free)

## The impact frame of the defeat: the sound of a ticket being closed by someone
## who is not relieved. The white pop through the frame and the edge flare went
## with the rest of the effects.
func _death_beat() -> void:
	# NOT "achievement": AudioManager plays that stream on `achievement_unlocked`
	# (audio_manager._on_achievement_unlocked), and two achievements unlock on
	# boss kills specifically — `i_can_explain` (Merge Conflict) and
	# `context_is_social_construct` (Infinite Context) — so it would double-fire
	# on those and false-signal an unlock on every other boss. "upgrade" is the
	# only positive stinger with no signal binding: its other callers live inside
	# the Dream App panel, which cannot be open mid-fight.
	AudioManager.play_sfx("upgrade")

## Fade out and free without the stamp — used if the boss leaves any other way.
func dismiss() -> void:
	# Deliberate removal, so losing the host afterwards is not a stale card.
	_closing = true
	_cancel_entrance()
	if not is_instance_valid(_root):
		queue_free()
		return
	var tw := _tw()
	tw.tween_property(_root, "modulate:a", 0.0, 0.3)
	tw.tween_callback(queue_free)
