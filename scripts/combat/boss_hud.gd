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
## ROUND 7 — ONE STACK, NO PLATES.
##
## The round-6 frames announced a boss with TWO plated panels: a gradient banner
## at the top carrying an incident number, the name and an epithet — which in
## region_cloud_district.png sat straight over the set-piece caption "THE CLOUD"
## — plus a second plate at the bottom of the screen carrying the name AGAIN, a
## live percentage, an 8px gradient bar, the epithet AGAIN and a phase chip. Two
## boxes, five text registers and the name printed twice, for one enemy.
##
## What it is now, per VISUAL_BIBLE_V2 LAW 8:
##   NAME CARD   ONE line — the boss's name, HEADING size, in HOSTILE, on its
##               own 1px shadow. No plate, no gradient, no incident number, no
##               sub-line, no rule under it. On screen for 2.5s, then gone.
##   HEALTH      ONE 4px bar directly under where the name was, in the same
##               HOSTILE. No border, no label, no percentage, no phase chip, no
##               plate. The bar getting shorter is the readout, and it stays up
##               until the boss dies.
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
##       y 262..266      the health bar (persistent)
##       y 278..300      phase call-outs, and the defeat stamp's note
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
const BAR_ROW := 40.0
const CALLOUT_ROW := 56.0
## How long the whole entrance lasts: 0.25 in + ENTRANCE_DWELL + 0.32 out.
## Round 6 held it inside EnemyBase's 2.2s `_intro_lock` because the card was an
## opaque plate covering a third of the screen. One line of text is not a
## curtain, so the card is now allowed to finish fading ~0.3s after the boss
## starts acting, which is what "shown 2.5s then gone" costs.
const ENTRANCE_DWELL := 1.93

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

## THE ONE COLOUR THIS LAYER SPENDS — and it is not the boss's own.
##
## VISUAL_BIBLE_V2 LAW 2 gives a scene three hues and reserves HOSTILE #FF4757
## for enemy tells; LAW 7 says enemies read as hostile by silhouette plus one
## red tell and do NOT each get a rainbow colour. `setup()` was handed
## `enemy_base.gd`'s DEATH_ACCENTS entry — magenta for the Merge Conflict, cyan
## for the Infinite Context, violet for Scope Creep — and painted the name card
## and the health bar with it. In region_stackoverflow_ruins.png that put a
## magenta title across a gold room, and in region_token_vault.png a cyan one
## across a gold vault: a fourth hue, on the single loudest element in the
## frame, chosen by which enemy happens to be attacking.
##
## A boss is an enemy. Every boss card is HOSTILE, in every room, which is both
## the law and the more useful signal — the colour now means "this is the thing
## hurting you" instead of "this is boss number six".
##
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

func _init() -> void:
	layer = 3
	# A boss card that freezes at full opacity because someone opened a dialogue
	# mid-entrance is a screen-covering bug, not a pause.
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
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
func _process(_delta: float) -> void:
	var tree := get_tree()
	if tree == null or not is_instance_valid(_root):
		return
	var want := not tree.paused
	if _root.visible != want:
		_root.visible = want

## Every tween on this layer survives `get_tree().paused` — see the header.
func _tw() -> Tween:
	var t := create_tween()
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	return t

## Called by EnemyBase before the entrance plays.
##
## `tint` is recorded and NOT painted with — see HOSTILE. The signature is
## unchanged so the call site does not have to know that the boss layer stopped
## having opinions about colour.
func setup(enemy_type: String, tint: Color) -> void:
	requested_tint = tint
	accent = HOSTILE
	var card: Array = BOSS_CARDS.get(enemy_type, [])
	if card.size() == 2:
		boss_name = str(card[0])
		boss_sub = str(card[1])
	else:
		boss_name = enemy_type.replace("_", " ").to_upper()
		boss_sub = "severity: yes · owner: unassigned"
	# The bar is built before setup() runs, so it is built in the DEFAULT red.
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

## Re-tint everything the boss colour drives. Safe to call before or after the
## nodes exist; `setup()` calls it once the real tint is known.
func _apply_accent() -> void:
	if is_instance_valid(_fill):
		_fill.color = accent

## Health, 0..1 of max. The fill moves in 0.22s and anything over 6% of the bar
## kicks it sideways. The lagging red ghost, the white leading-edge chip and the
## live percentage are gone — the bar getting shorter is the readout.
func set_health(current: int, maximum: int) -> void:
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

## The name fades in on the world, the bar fades in under it, the name fades out
## again. Nothing covers the player, nothing covers a world caption, and nothing
## touches a HUD lane.
##
## Length: 0.25 in + ENTRANCE_DWELL + 0.32 out = 2.50s.
func play_entrance() -> void:
	if _entered or not is_instance_valid(_root):
		return
	_entered = true
	_card = _band(NAME_ROW_H)

	# ONE line. HEADING size, the boss accent, the theme's 1px shadow — the same
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
	# Unconditional on purpose: these are where a COMPLETED entrance leaves
	# things, so running them when there was nothing to cancel is a no-op, and
	# running them when `play_entrance()` never fired is the difference between a
	# defeat draining a visible bar and draining an invisible one.
	if is_instance_valid(_bar_root):
		_bar_root.modulate.a = 1.0
	if is_instance_valid(_frame):
		_frame.position = Vector2.ZERO

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
	# One hit big enough to cross a gate inside EnemyBase's intro lock would
	# otherwise stack this line on the entrance card, in the same band.
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
func detach() -> void:
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
	if not is_instance_valid(_root):
		return
	# The stamp goes in the announcement band; a card still fading in it would
	# read as two incidents at once. Also settles the bar and its alpha.
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
	_cancel_entrance()
	if not is_instance_valid(_root):
		queue_free()
		return
	var tw := _tw()
	tw.tween_property(_root, "modulate:a", 0.0, 0.3)
	tw.tween_callback(queue_free)
