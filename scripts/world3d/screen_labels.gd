class_name ScreenLabels
extends Node
## Screen-space world text for the 3D world (VISUAL_BIBLE_V2 LAW 4/8 in 3D).
##
## Label3D was the wrong tool: its glyphs scale with distance, it cannot clamp
## to the screen edge, and a portal ended up wearing four texts. Every world
## caption is now a plain 2D Label in the game's aliased UI font, positioned
## each frame by unprojecting its owner's position, clamped inside the safe
## area, and stacked when two would overlap. Owners free their labels by
## leaving the tree.
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
		# Stack upward off anything already placed.
		var rect := Rect2(pos, size)
		var guard := 0
		while guard < 12:
			var hit := false
			for r in placed:
				if r.intersects(rect):
					rect.position.y = r.position.y - size.y - STACK_GAP
					hit = true
					break
			if not hit:
				break
			guard += 1
		if rect.position.y < safe.position.y:
			rect.position.y = safe.position.y
		placed.append(rect)
		lbl.position = rect.position
		lbl.visible = true
		shown += 1
