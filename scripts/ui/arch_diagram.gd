extends Control
## The Dream App's live architecture diagram. It grows visibly more ridiculous as
## the player buys upgrades and makes architecture decisions: more boxes, more
## tangled "spaghetti" arrows, and increasingly unhinged annotations. Purely
## procedural (draw calls) so it reflects the exact current state every redraw.

const NODES := {
	"frontend": {"pos": Vector2(70, 46), "label": "FE", "col": Color(0.4, 0.8, 0.95)},
	"backend": {"pos": Vector2(215, 34), "label": "BE", "col": Color(0.55, 0.85, 0.6)},
	"database": {"pos": Vector2(360, 52), "label": "DB", "col": Color(0.85, 0.7, 0.4)},
	"ai": {"pos": Vector2(120, 128), "label": "AI", "col": Color(0.8, 0.5, 1.0)},
	"infrastructure": {"pos": Vector2(300, 140), "label": "INFRA", "col": Color(0.5, 0.7, 1.0)},
	"security": {"pos": Vector2(415, 118), "label": "SEC", "col": Color(0.95, 0.5, 0.5)},
}
const BASE_EDGES := [["frontend", "backend"], ["backend", "database"], ["ai", "backend"], ["infrastructure", "database"], ["security", "backend"]]
const CHAOS := ["???", "TODO", "load-bearing", "here be dragons", "why", "do not touch", "legacy", "temp (2019)"]

func _ready() -> void:
	custom_minimum_size = Vector2(470, 178)

func refresh() -> void:
	queue_redraw()

func _draw() -> void:
	var font := get_theme_default_font()
	var fs := 11
	var total := 0
	var active: Array = []
	for b in NODES:
		var tier: int = DreamAppManager.get_branch_tier(b)
		if tier > 0:
			active.append(b)
			total += tier
	var ridic: int = ArchitectureManager.ridiculousness if ArchitectureManager else 0
	var arch: Dictionary = ArchitectureManager.flags if ArchitectureManager else {}

	# Backdrop.
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.06, 0.09, 0.6))
	draw_string(font, Vector2(8, 16), "MVP ARCHITECTURE  (ridiculousness: %d)" % (ridic + total),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.9, 0.85))

	if active.is_empty():
		draw_string(font, Vector2(120, 100), "(a README that says 'TODO: everything')",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.6, 0.7))
		return

	# Base edges between built branches.
	for e in BASE_EDGES:
		if e[0] in active and e[1] in active:
			_arrow(NODES[e[0]].pos, NODES[e[1]].pos, Color(0.5, 0.6, 0.75, 0.8), 2.0)

	# Spaghetti: the more you've built (and the more "ridiculous" your decisions),
	# the more tangled cross-arrows appear. Deterministic per state.
	var rng := RandomNumberGenerator.new()
	rng.seed = total * 131 + ridic * 17
	var spaghetti: int = clampi(total - 3 + ridic / 2, 0, 22)
	for i in spaghetti:
		var a: String = active[rng.randi() % active.size()]
		var b: String = active[rng.randi() % active.size()]
		var col := Color(0.9, 0.45, 0.4, 0.5) if rng.randf() < 0.4 else Color(0.5, 0.7, 0.9, 0.4)
		if a == b:
			_self_loop(NODES[a].pos, col)  # a service that calls itself. classic.
		else:
			_arrow(NODES[a].pos, NODES[b].pos, col, 1.0)

	# Microservices flag: explode backend into a swarm of little boxes.
	if arch.get("structure") == "microservices" and "backend" in active:
		var bp: Vector2 = NODES["backend"].pos
		for i in 8:
			var mp := bp + Vector2(cos(i) * (26 + i * 3), sin(i * 1.7) * 18)
			draw_rect(Rect2(mp - Vector2(4, 4), Vector2(8, 8)), Color(0.55, 0.85, 0.6, 0.7))
			_arrow(bp, mp, Color(0.55, 0.85, 0.6, 0.35), 1.0)

	# Nodes on top.
	for b in active:
		var p: Vector2 = NODES[b].pos
		var tier: int = DreamAppManager.get_branch_tier(b)
		var w: float = 30.0 + tier * 5.0
		var h: float = 22.0
		var col: Color = NODES[b].col
		draw_rect(Rect2(p - Vector2(w, h) * 0.5, Vector2(w, h)), Color(col.r, col.g, col.b, 0.85))
		draw_rect(Rect2(p - Vector2(w, h) * 0.5, Vector2(w, h)), Color(1, 1, 1, 0.25), false, 1.0)
		var lbl: String = "%s%d" % [NODES[b].label, tier]
		draw_string(font, p - Vector2(w * 0.5 - 4, -4), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.05, 0.06, 0.09))

	# Unhinged annotations scale with ridiculousness.
	var notes: int = clampi((ridic + total) / 4, 0, CHAOS.size())
	for i in notes:
		var np := Vector2(rng.randf_range(30, size.x - 60), rng.randf_range(30, size.y - 14))
		draw_string(font, np, CHAOS[i % CHAOS.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.9, 0.55, 0.5, 0.8))

func _arrow(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	draw_line(a, b, col, w)
	var dir := (b - a).normalized()
	var head := b - dir * 8.0
	var perp := Vector2(-dir.y, dir.x) * 4.0
	draw_line(b, head + perp, col, w)
	draw_line(b, head - perp, col, w)

func _self_loop(p: Vector2, col: Color) -> void:
	draw_arc(p + Vector2(0, -16), 10.0, 0, TAU, 16, col, 1.0)
