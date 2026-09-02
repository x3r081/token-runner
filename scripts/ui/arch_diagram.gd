extends Control
## The Dream App's live architecture diagram. It grows visibly more ridiculous as
## the player buys upgrades and makes architecture decisions: more boxes, more
## tangled arrows, more annotations nobody wants to read. Purely procedural (draw
## calls) so it reflects the exact current state every redraw.
##
## Round 6 took its colours away. It used to draw six differently-hued boxes, red
## and blue spaghetti, and up to eight red annotations scattered by RNG — six
## hues in a 470x156 rectangle, inside a panel that is otherwise two. Now it is a
## blueprint: LINE outlines, TEXT labels, TEXT_DIM wiring. The gag was never the
## colour, it was the number of arrows.

const _GameTheme = preload("res://scripts/ui/game_theme.gd")

const NODES := {
	"frontend": {"pos": Vector2(70, 46), "label": "FE"},
	"backend": {"pos": Vector2(215, 34), "label": "BE"},
	"database": {"pos": Vector2(360, 52), "label": "DB"},
	"ai": {"pos": Vector2(120, 128), "label": "AI"},
	"infrastructure": {"pos": Vector2(300, 140), "label": "INFRA"},
	"security": {"pos": Vector2(415, 118), "label": "SEC"},
}
const BASE_EDGES := [["frontend", "backend"], ["backend", "database"], ["ai", "backend"], ["infrastructure", "database"], ["security", "backend"]]
const CHAOS := ["???", "TODO", "load-bearing", "here be dragons", "why", "do not touch", "legacy", "temp (2019)"]

## Spaghetti used to run to 22 crossing arrows. Eight already reads as "this is
## out of control" and leaves the boxes legible, which is the joke's setup.
const MAX_SPAGHETTI := 8
const MAX_NOTES := 2

func _ready() -> void:
	custom_minimum_size = Vector2(470, 178)

func refresh() -> void:
	queue_redraw()

func _draw() -> void:
	var font := get_theme_default_font()
	var total := 0
	var active: Array = []
	for b in NODES:
		var tier: int = DreamAppManager.get_branch_tier(b)
		if tier > 0:
			active.append(b)
			total += tier
	var ridic: int = ArchitectureManager.ridiculousness if ArchitectureManager else 0
	var arch: Dictionary = ArchitectureManager.flags if ArchitectureManager else {}

	# No backdrop plate: the diagram sits on the panel body, which is already the
	# darkest surface on screen. A box inside a box was the round-5 signature.
	draw_string(font, Vector2(8, 14), "MVP ARCHITECTURE · ridiculousness %d" % (ridic + total),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, _GameTheme.TEXT_DIM)

	if active.is_empty():
		draw_string(font, Vector2(8, 46), "a README that says 'TODO: everything'",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, _GameTheme.TEXT_DIM)
		return

	var wire := _GameTheme.with_alpha(_GameTheme.TEXT_DIM, 0.75)
	var tangle := _GameTheme.with_alpha(_GameTheme.TEXT_DIM, 0.35)

	for e in BASE_EDGES:
		if e[0] in active and e[1] in active:
			_arrow(NODES[e[0]].pos, NODES[e[1]].pos, wire, 1.0)

	# The more you have built (and the more "ridiculous" your decisions), the more
	# tangled cross-arrows appear. Deterministic per state, capped.
	var rng := RandomNumberGenerator.new()
	rng.seed = total * 131 + ridic * 17
	var spaghetti: int = clampi(total - 3 + ridic / 2, 0, MAX_SPAGHETTI)
	for i in spaghetti:
		var a: String = active[rng.randi() % active.size()]
		var b: String = active[rng.randi() % active.size()]
		if a == b:
			_self_loop(NODES[a].pos, tangle)  # a service that calls itself. classic.
		else:
			_arrow(NODES[a].pos, NODES[b].pos, tangle, 1.0)

	# Microservices flag: explode backend into a swarm of little boxes.
	if arch.get("structure") == "microservices" and "backend" in active:
		var bp: Vector2 = NODES["backend"].pos
		for i in 8:
			var mp := bp + Vector2(cos(i) * (26 + i * 3), sin(i * 1.7) * 18)
			draw_rect(Rect2(mp - Vector2(3, 3), Vector2(6, 6)), _GameTheme.LINE)
			_arrow(bp, mp, tangle, 1.0)

	# Boxes on top: flat BASE fill, 1px LINE outline, TEXT label. One drawing
	# language for all six, the way the sprites obey one (LAW 7).
	for b in active:
		var p: Vector2 = NODES[b].pos
		var tier: int = DreamAppManager.get_branch_tier(b)
		var w: float = 30.0 + tier * 5.0
		var h: float = 22.0
		var box := Rect2(p - Vector2(w, h) * 0.5, Vector2(w, h))
		draw_rect(box, _GameTheme.BASE)
		draw_rect(box, _GameTheme.LINE, false, 1.0)
		draw_string(font, p - Vector2(w * 0.5 - 5.0, -4.0), "%s%d" % [NODES[b].label, tier],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, _GameTheme.TEXT)

	# Annotations: two, in the margin, not scattered across the boxes by RNG.
	var notes: int = clampi((ridic + total) / 6, 0, MAX_NOTES)
	for i in notes:
		draw_string(font, Vector2(8.0, size.y - 20.0 + float(i) * 14.0 - float(notes) * 7.0),
			CHAOS[i % CHAOS.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, tangle)

func _arrow(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	draw_line(a, b, col, w)
	var dir := (b - a).normalized()
	var head := b - dir * 8.0
	var perp := Vector2(-dir.y, dir.x) * 4.0
	draw_line(b, head + perp, col, w)
	draw_line(b, head - perp, col, w)

func _self_loop(p: Vector2, col: Color) -> void:
	draw_arc(p + Vector2(0, -16), 10.0, 0, TAU, 16, col, 1.0)
