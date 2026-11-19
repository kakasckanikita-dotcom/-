extends Control
## Миникарта вокруг героя (обрезается по своему прямоугольнику).

const RANGE := 1400.0


func _draw() -> void:
	var w = Game.world
	if w == null:
		return
	var S := size.x
	var sc := S / RANGE
	var center: Vector2 = w.player.global_position
	var M := func(p: Vector2) -> Vector2: return (p - center) * sc + Vector2(S, S) / 2.0
	draw_rect(Rect2(Vector2.ZERO, size), Color("c9a46b"))
	for r in w.roads:
		var pts := PackedVector2Array()
		for p in r:
			pts.append(M.call(p))
		draw_polyline(pts, Color(0.55, 0.4, 0.25, 0.6), 60.0 * sc)
	var river := PackedVector2Array()
	var y := center.y - RANGE
	while y <= center.y + RANGE:
		river.append(M.call(Vector2(w.river_x(y), y)))
		y += 30.0
	draw_polyline(river, Color("3d7896"), w.RIVER_W * sc)
	for b in w.buildings:
		var p: Vector2 = M.call(b.rect.position)
		draw_rect(Rect2(p, b.rect.size * sc), Color("5a3a1a"))
	for c in w.camps:
		if c.known:
			draw_circle(M.call(c.position), 4.0, Color("777777") if c.cleared else Color("cc3333"))
	for n in get_tree().get_nodes_in_group("npcs"):
		if not n.dead and (n.aggro or n.kind == "lawman"):
			var col := Color("4a8adf") if n.kind in ["lawman", "sheriff"] else Color("ee3333")
			draw_rect(Rect2(M.call(n.global_position) - Vector2(1.5, 1.5), Vector2(3, 3)), col)
	if not w.player.mounted:
		draw_rect(Rect2(M.call(w.horse.global_position) - Vector2(2, 2), Vector2(4, 4)), Color("e8c35a"))
	if Game.bounty != null:
		var target: Vector2 = w.nearest_sheriff_door(center) if Game.bounty["done"] else Game.bounty["camp"].position
		var p: Vector2 = M.call(target)
		p = p.clamp(Vector2(6, 6), size - Vector2(6, 6))
		if Game.bounty["done"]:
			Gfx.text(self, p + Vector2(0, 5), "$", 14, Color("d4a017"))
		else:
			Gfx.cross(self, p, 5.0, Color("d4a017"), 2.5)
	var a: float = w.player.ang
	var c := Vector2(S, S) / 2.0
	draw_colored_polygon(PackedVector2Array([c + Vector2.from_angle(a) * 7.0, c + Vector2.from_angle(a + 2.5) * 6.0, c + Vector2.from_angle(a - 2.5) * 6.0]), Color.WHITE)
	draw_rect(Rect2(Vector2.ZERO, size), Color("3a2412"), false, 3.0)
