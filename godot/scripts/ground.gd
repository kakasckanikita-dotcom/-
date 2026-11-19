extends Node2D
## Земля: песок из шума, дороги, улицы городов, река и мосты.

const ROAD := Color("ab8758")

var world: Node2D
var tex: NoiseTexture2D


func _ready() -> void:
	z_index = -10
	var n := FastNoiseLite.new()
	n.seed = 7
	n.frequency = 0.012
	n.fractal_octaves = 4
	var g := Gradient.new()
	g.set_color(0, Color("ad8a55"))
	g.set_color(1, Color("d8b882"))
	g.add_point(0.45, Color("c9a46b"))
	g.add_point(0.62, Color("b9a066"))
	g.add_point(0.8, Color("caa874"))
	tex = NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.noise = n
	tex.color_ramp = g
	tex.changed.connect(queue_redraw)


func _draw() -> void:
	var W: float = world.WORLD
	draw_texture_rect(tex, Rect2(0, 0, W, W), false)
	for r in world.roads:
		var pts := PackedVector2Array(r)
		for p in pts:
			draw_circle(p, 30.0, ROAD)
		draw_polyline(pts, ROAD, 60.0)
		draw_polyline(pts, Color("9a7650"), 6.0)
	for t in world.towns:
		draw_rect(Rect2(t["pos"] + Vector2(-420, -80), Vector2(840, 160)), ROAD)
	# река: берег и вода полосами
	var step := 24.0
	var y := 0.0
	while y < W:
		var x0: float = world.river_x(y)
		var x1: float = world.river_x(y + step)
		var hw: float = world.RIVER_W / 2.0
		draw_colored_polygon(PackedVector2Array([Vector2(x0 - hw - 22, y), Vector2(x0 + hw + 22, y), Vector2(x1 + hw + 22, y + step + 1), Vector2(x1 - hw - 22, y + step + 1)]), Color(0.43, 0.47, 0.24, 0.5))
		draw_colored_polygon(PackedVector2Array([Vector2(x0 - hw, y), Vector2(x0 + hw, y), Vector2(x1 + hw, y + step + 1), Vector2(x1 - hw, y + step + 1)]), Color("3d7896"))
		draw_line(Vector2(x0 + sin(y * 0.03) * hw * 0.4, y), Vector2(x1 + sin((y + step) * 0.03) * hw * 0.4, y + step), Color(0.7, 0.86, 0.92, 0.25), 3.0)
		y += step
	for by in world.BRIDGES:
		var x: float = world.river_x(by)
		var half: float = world.RIVER_W / 2.0 + 30.0
		draw_rect(Rect2(x - half + 6, by - 34, half * 2, 80), Color(0, 0, 0, 0.3))
		var i := -half
		while i < half:
			draw_rect(Rect2(x + i, by - 40, 9, 80), Color("7a5232") if int(i / 10) % 2 == 0 else Color("6b4423"))
			i += 10.0
		draw_rect(Rect2(x - half, by - 44, half * 2, 5), Color("4a2e18"))
		draw_rect(Rect2(x - half, by + 39, half * 2, 5), Color("4a2e18"))
