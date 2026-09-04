class_name Map3D
extends RefCounted
## Coordinate law + Kenney model access for the 3D layer (3D_BIBLE.md §2, §6).
##
## Managers, saves, UI and every authored table speak MAP PIXELS (64 px per
## tile). The 3D world converts at its edge and nowhere else:
##   world3d = Vector3(px.x / 64, height, px.y / 64)   (map +y == world +z)

const PX := 64.0
const ROOT := "res://assets/external/kenney3d/"
const MANIFEST := ROOT + "manifest.json"

static var _manifest: Dictionary = {}
static var _scene_cache: Dictionary = {}

static func to3d(px: Vector2, y: float = 0.0) -> Vector3:
	return Vector3(px.x / PX, y, px.y / PX)

static func to_map(v: Vector3) -> Vector2:
	return Vector2(v.x * PX, v.z * PX)

## Map-space direction (Vector2) -> world XZ direction, y = 0.
static func dir3d(d: Vector2) -> Vector3:
	return Vector3(d.x, 0.0, d.y)

static func dir_map(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)

static func _load_manifest() -> void:
	if not _manifest.is_empty():
		return
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	if f == null:
		push_warning("Map3D: manifest missing at " + MANIFEST)
		_manifest = {"models": {}}
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	_manifest = data if data is Dictionary else {"models": {}}

## Bounds/animation info for "pack/name" from the manifest (empty if unknown).
static func bounds(key: String) -> Dictionary:
	_load_manifest()
	var models: Dictionary = _manifest.get("models", {})
	return models.get(key, {})

static func path_of(key: String) -> String:
	return ROOT + key + ".glb"

static func has_model(key: String) -> bool:
	return ResourceLoader.exists(path_of(key))

## Instantiate "pack/name". exists()-guarded: returns null when the model is
## missing so a builder can fall back instead of crashing a whole region.
static func model(key: String) -> Node3D:
	var path := path_of(key)
	var ps: PackedScene = _scene_cache.get(path)
	if ps == null:
		if not ResourceLoader.exists(path):
			push_warning("Map3D: no model " + key)
			return null
		ps = load(path)
		if ps == null:
			return null
		_scene_cache[path] = ps
	var inst := ps.instantiate()
	if inst is Node3D:
		(inst as Node3D).name = key.get_file()
		return inst as Node3D
	inst.free()
	return null

## Height of the model's authored bounds (manifest), 1.0 if unknown.
static func height_of(key: String) -> float:
	var b := bounds(key)
	if b.is_empty():
		return 1.0
	var s: Array = b.get("size", [1, 1, 1])
	return maxf(float(s[1]), 0.01)

## Uniformly scale `node` (a model from `key`) so its authored height == h.
static func fit_height(node: Node3D, key: String, h: float) -> void:
	if node == null:
		return
	var k := h / height_of(key)
	node.scale = Vector3.ONE * k

## Recursively override materials: albedo multiplied by `color`, optional
## emission in the same color. Duplicates materials so shared imports are not
## mutated. Skips nodes without surfaces.
static func tint(node: Node, color: Color, emission_energy: float = 0.0) -> void:
	if node == null:
		return
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mesh := mi.mesh
		if mesh:
			for i in mesh.get_surface_count():
				var src: Material = mi.get_active_material(i)
				var mat: StandardMaterial3D
				if src is StandardMaterial3D:
					mat = (src as StandardMaterial3D).duplicate()
				else:
					mat = StandardMaterial3D.new()
				mat.albedo_color = mat.albedo_color * color
				if emission_energy > 0.0:
					mat.emission_enabled = true
					mat.emission = color
					mat.emission_energy_multiplier = emission_energy
				mi.set_surface_override_material(i, mat)
	for c in node.get_children():
		tint(c, color, emission_energy)

## A flat-shaded Kenney material tuned for the bible's look (no PBR sparkle).
static func matte(color: Color, emission_energy: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	m.metallic = 0.0
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission_energy
	return m
