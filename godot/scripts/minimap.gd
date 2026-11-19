extends Control
## Миникарта вокруг героя, повёрнута по взгляду камеры (вверх — куда вы смотрите).

const RANGE := 260.0


func _draw() -> void:
	var w = Game.world
	if w == null:
		return
	var S := size.x
	var sc := S / RANGE
	var center: Vector2 = w.v2(w.player.global_position)
	var rot: float = w.player.yaw
	var mid := Vector2(S, S) / 2.0
	# мировой (x, z) → экран миникарты; поворот, чтобы взгляд камеры был вверх
	var M := func(p: Vector2) -> Vector2: return (p - center).rotated(rot) * sc + mid
	draw_rect(Rect2(Vector2.ZERO, size), Color("c9a46b"))
	for r in w.roads:
		var pts := PackedVector2Array()
		for p in r:
			pts.append(M.call(p))
		draw_polyline(pts, Color(0.55, 0.4, 0.25, 0.7), maxf(2.0, 7.0 * sc))
	var river := PackedVector2Array()
	var z := center.y - RANGE
	while z <= center.y + RANGE:
		river.append(M.call(Vector2(w.river_x(z), z)))
		z += 6.0
	draw_polyline(river, Color("3d7896"), w.RIVER_W * sc)
	for b in w.buildings:
		var r: Rect2 = b["rect"]
		var pts := PackedVector2Array([M.call(r.position), M.call(Vector2(r.end.x, r.position.y)), M.call(r.end), M.call(Vector2(r.position.x, r.end.y))])
		draw_colored_polygon(pts, Color("5a3a1a"))
	for c in w.camps:
		if c.known:
			draw_circle(M.call(w.v2(c.position)), 4.0, Color("777777") if c.cleared else Color("cc3333"))
	for n in get_tree().get_nodes_in_group("npcs"):
		if not n.dead and (n.aggro or n.kind == "lawman"):
			var col := Color("4a8adf") if n.kind in ["lawman", "sheriff"] else Color("ee3333")
			draw_rect(Rect2(M.call(w.v2(n.global_position)) - Vector2(2, 2), Vector2(4, 4)), col)
	if not w.player.mounted:
		draw_rect(Rect2(M.call(w.v2(w.horse.global_position)) - Vector2(2.5, 2.5), Vector2(5, 5)), Color("e8c35a"))
	if Game.bounty != null:
		var target: Vector2 = w.v2(w.nearest_sheriff_door(w.player.global_position)) if Game.bounty["done"] else w.v2(Game.bounty["camp"].position)
		var p: Vector2 = M.call(target)
		p = p.clamp(Vector2(7, 7), size - Vector2(7, 7))
		if Game.bounty["done"]:
			draw_circle(p, 6.0, Color("d4a017"))
		else:
			draw_line(p + Vector2(-5, -5), p + Vector2(5, 5), Color("d4a017"), 2.5)
			draw_line(p + Vector2(5, -5), p + Vector2(-5, 5), Color("d4a017"), 2.5)
	# герой — стрелка (камера всегда смотрит вверх)
	var fy: float = w.player.face_yaw - rot
	var dir := Vector2(-sin(fy), -cos(fy))
	draw_colored_polygon(PackedVector2Array([mid + dir * 8.0, mid + dir.rotated(2.5) * 6.0, mid + dir.rotated(-2.5) * 6.0]), Color.WHITE)
	draw_rect(Rect2(Vector2.ZERO, size), Color("3a2412"), false, 3.0)
