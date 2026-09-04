class_name ScreenLabels
extends Node
## Screen-space world text for the 3D world (VISUAL_BIBLE_V2 LAW 4/8 in 3D).
##
## Label3D was the wrong tool: its glyphs scale with distance, it cannot clamp
## to the screen edge, and a portal ended up wearing four texts. Every world
## caption is now a plain 2D Label in the game's aliased UI font, positioned
## each frame by unprojecting its owner's position, clamped inside the safe
## area, stacked when two would overlap, and kept OFF the player (see
## KEEP_CLEAR_RADIUS — a caption that lands on the one silhouette the frame is
## about costs more than it says). Owners free their labels by leaving the tree.
##
##   var lbl := ScreenLabels.attach(self, "Talk to Claude", ScreenLabels.BODY)
##   ScreenLabels.set_text(lbl, "...")   # or lbl.text = "..."
##
## Sizes: SMALL (14) for distance/prompt lines, BODY (18) for names. Nothing
## larger — the region heading owns 26.

const GROUP := "screen_labels"
const LAYER := 3			# under the HUD (4) and every modal
const SMALL := 14
const BODY := 18
const MAX_VISIBLE := 10	 # LAW 4 in spirit: the world does not shout
const SAFE_TOP := 96.0	  # HUD top strip
const SAFE_BOTTOM := 118.0  # ability bar + hint line
const SAFE_SIDE := 12.0
const STACK_GAP := 2.0

## KEEP-CLEAR (round 3). `combat_dependency_district.png` put five texts and the
## waypoint chevron inside a 260x160 box centred on the player — "-10", "+5",
## "Localhost · 4m · via this portal", "[E] node_modules" and a portal's
## "→ Localhost" — and the cold read of that frame was that the player is
## unfindable, which is the rubric's FIRST question ("can I tell in one second
## what is the player?"). No single caption is at fault; the pile is. Only the
## thing that places all of them can see the pile, so the rule lives here: a
## disc of KEEP_CLEAR_RADIUS around the player's screen position that ordinary
## captions do not enter at all, and that essential ones are lifted clear of.
##
## 100px at 1920x928 is a little under twice the player's on-screen height —
## enough to hold his silhouette plus the shoulders of the model, and small
## enough that a caption one prop away is untouched.
const KEEP_CLEAR_RADIUS := 100.0
## Priority at or above which a label may STAY inside the disc (pushed clear of
## it) instead of being dropped. Everything ambient — nameplates (0), portal
## captions (1), the interact prompt (-1) — is below it and simply does not draw
## while it would land on the player. Fx3D.glyph spawns AT this priority, so a
## damage number is still readable: it is the one text the player must not miss.
const KEEP_CLEAR_PRIORITY := 2
## Where the disc is centred on the player: chest height, so it covers the body
## rather than the floor he stands on.
const KEEP_CLEAR_LIFT := 0.6
## "There is no player on screen" — a centre every distance test fails against
## by kilometres, so a 2D run, a menu, or a camera looking away costs one
## comparison and changes nothing.
const NO_CLEAR := Vector2(-1.0e9, -1.0e9)

var _entries: Array[Dictionary] = []
var _canvas: CanvasLayer

## Find the live instance (or build one under the group-"world" node).
static func get_or_create(tree: SceneTree) -> ScreenLabels:
	if tree == null:
		return null
	var existing := tree.get_first_node_in_group(GROUP)
	if existing is ScreenLabels:
		return existing as ScreenLabels
	var world: Node = tree.get_first_node_in_group("world")
	if world == null:
		world = tree.current_scene
	if world == null:
		return null
	var layer := CanvasLayer.new()
	layer.name = "ScreenLabels"
	layer.layer = LAYER
	var sl := ScreenLabels.new()
	sl.name = "Labels"
	sl._canvas = layer
	layer.add_child(sl)
	world.add_child(layer)
	return sl

func _ready() -> void:
	add_to_group(GROUP)
	process_mode = Node.PROCESS_MODE_PAUSABLE

## Attach a label that follows `owner` (a Node3D) at `height` units above its
## origin. `priority` breaks ties when more than MAX_VISIBLE want the screen
## (higher wins). Returns the Label (never null while the tree is alive).
static func attach(owner: Node3D, text: String, size: int = BODY, color: Color = GameTheme.TEXT, height: float = 1.1, priority: int = 0) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_override("font", GameTheme.ui_font())
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.visible = false
	var tree := owner.get_tree()
	var sl := get_or_create(tree)
	if sl == null:
		owner.add_child(lbl)   # degenerate: keeps the caller's reference valid
		return lbl
	sl.add_child(lbl)
	sl._entries.append({"label": lbl, "owner": owner, "height": height, "priority": priority})
	owner.tree_exiting.connect(func() -> void:
		if is_instance_valid(lbl):
			lbl.queue_free())
	return lbl

## Untyped on purpose: a typed `Label` parameter rejects a freed instance at
## the call boundary, before the guard can run.
static func set_text(lbl, text: String) -> void:
	if is_instance_valid(lbl) and lbl is Label:
		(lbl as Label).text = text

static func detach(lbl) -> void:
	if is_instance_valid(lbl) and lbl is Node:
		(lbl as Node).queue_free()

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var view := get_viewport().get_visible_rect().size
	var safe := Rect2(SAFE_SIDE, SAFE_TOP, view.x - SAFE_SIDE * 2.0, view.y - SAFE_TOP - SAFE_BOTTOM)
	var clear_at := _keep_clear_centre(cam)
	var placed: Array[Rect2] = []
	var live: Array[Dictionary] = []
	# Drop dead entries, hide the ones behind the camera.
	for e in _entries:
		# Validity BEFORE the typed assignment: binding a freed object to a
		# `Label` var is itself the "previously freed instance" error.
		var lbl_raw = e.label
		var owner_raw = e.owner
		if not is_instance_valid(lbl_raw):
			continue
		if not is_instance_valid(owner_raw) or not (owner_raw as Node).is_inside_tree():
			(lbl_raw as Node).queue_free()
			continue
		live.append(e)
	_entries = live
	# Nearest-to-screen-centre first so the important caption keeps its spot;
	# priority overrides distance.
	var order: Array[Dictionary] = live.duplicate()
	var centre := view * 0.5
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.priority != b.priority:
			return a.priority > b.priority
		var pa: Vector3 = (a.owner as Node3D).global_position
		var pb: Vector3 = (b.owner as Node3D).global_position
		var sa := cam.unproject_position(pa).distance_squared_to(centre)
		var sb := cam.unproject_position(pb).distance_squared_to(centre)
		return sa < sb)
	var shown := 0
	for e in order:
		var lbl: Label = e.label
		var owner: Node3D = e.owner
		var anchor: Vector3 = owner.global_position + Vector3(0.0, float(e.height), 0.0)
		if cam.is_position_behind(anchor) or shown >= MAX_VISIBLE or lbl.text == "":
			lbl.visible = false
			continue
		var sp := cam.unproject_position(anchor)
		var size := lbl.get_combined_minimum_size()
		var pos := Vector2(sp.x - size.x * 0.5, sp.y - size.y)
		# Clamp into the safe area (never under the HUD, never off an edge).
		pos.x = clampf(pos.x, safe.position.x, safe.end.x - size.x)
		pos.y = clampf(pos.y, safe.position.y, safe.end.y - size.y)
		var rect := Rect2(pos, size)
		# KEEP-CLEAR, before stacking: a label that is not going to be drawn must
		# not reserve a row and push a caption that IS drawn out of the frame.
		if rect.get_center().distance_to(clear_at) < KEEP_CLEAR_RADIUS:
			if int(e.priority) < KEEP_CLEAR_PRIORITY:
				lbl.visible = false
				continue
			rect = _evade(rect, clear_at, safe)
		rect = _stack(rect, placed, safe)
		placed.append(rect)
		lbl.position = rect.position
		lbl.visible = true
		shown += 1

## The player's screen position, or NO_CLEAR when there is none to avoid.
##
## The "player" group is SCANNED for a Node3D rather than trusting the first
## member: 3D_BIBLE §5 keeps the ActorProxy in "player_proxy" and
## tests/world3d_test.gd asserts it is NOT in "player", but a 2D run's player is
## a CharacterBody2D in this same group and must cost nothing here. Untyped loop
## var on purpose: binding a group member to a typed `Node` before
## `is_instance_valid` is exactly the "previously freed instance" error
## documented above.
func _keep_clear_centre(cam: Camera3D) -> Vector2:
	for n in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(n) or not (n is Node3D):
			continue
		var at: Vector3 = (n as Node3D).global_position + Vector3(0.0, KEEP_CLEAR_LIFT, 0.0)
		if cam.is_position_behind(at):
			return NO_CLEAR
		return cam.unproject_position(at)
	return NO_CLEAR

## Lift an essential label off the player. Its BOTTOM edge goes one radius above
## the keep-clear centre — text belongs over its subject — and when that would
## climb out of the safe area it drops one radius BELOW instead, because a
## caption jammed against the HUD's top strip is the pile-up by another route.
func _evade(rect: Rect2, clear_at: Vector2, safe: Rect2) -> Rect2:
	var out := rect
	out.position.y = clear_at.y - KEEP_CLEAR_RADIUS - rect.size.y
	if out.position.y < safe.position.y:
		out.position.y = clear_at.y + KEEP_CLEAR_RADIUS
	out.position.y = _clamp_y(out.position.y, rect.size.y, safe)
	return out

## Push a rect off everything already placed: UPWARD first, and DOWNWARD from
## the original row when the upward run would leave the safe area. Round 2
## stacked upward only and clamped the overflow to SAFE_TOP, which is how four
## captions ended up interleaved inside one 20px band under the region name.
func _stack(rect: Rect2, placed: Array[Rect2], safe: Rect2) -> Rect2:
	var up := _slide(rect, placed, -1.0)
	if up.position.y >= safe.position.y:
		return up
	var down := _slide(rect, placed, 1.0)
	if down.end.y <= safe.end.y:
		return down
	up.position.y = _clamp_y(up.position.y, rect.size.y, safe)
	return up

## One directional run: step off each rect hit, `dir` -1 up and +1 down. The
## guard bounds a pathological pile; MAX_VISIBLE labels never reach it.
func _slide(rect: Rect2, placed: Array[Rect2], dir: float) -> Rect2:
	var out := rect
	var guard := 0
	while guard < 12:
		var hit := false
		for r: Rect2 in placed:
			if r.intersects(out):
				if dir < 0.0:
					out.position.y = r.position.y - out.size.y - STACK_GAP
				else:
					out.position.y = r.end.y + STACK_GAP
				hit = true
				break
		if not hit:
			break
		guard += 1
	return out

## Clamp a top edge into the safe band, tolerating a label taller than the band
## itself — a `clampf` whose min exceeds its max returns the max, i.e. the wrong
## end — in which case the TOP of the safe area wins.
func _clamp_y(y: float, height: float, safe: Rect2) -> float:
	var lo := safe.position.y
	return clampf(y, lo, maxf(lo, safe.end.y - height))
