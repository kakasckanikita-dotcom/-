extends Node2D
## Частицы (кровь, искры, дым), трассеры и метки «Глаза ястреба».

var parts: Array = []
var tracers: Array = []


func _ready() -> void:
	z_index = 6


func add(pos: Vector2, v: Vector2, life: float, col: Color, size: float) -> void:
	if parts.size() < 600:
		parts.append({"p": pos, "v": v, "life": life, "max": life, "c": col, "s": size})


func burst(pos: Vector2, col: Color, n: int, smin: float, smax: float, life: float, size: float, dir := 0.0, spread := PI) -> void:
	for i in n:
		add(pos, Vector2.from_angle(dir + randf_range(-spread, spread)) * randf_range(smin, smax), life, col, size)


func blood(pos: Vector2) -> void:
	burst(pos, Color("8a1a10"), 8, 20.0, 90.0, 0.5, 3.0)


func muzzle(pos: Vector2, ang: float) -> void:
	burst(pos + Vector2.from_angle(ang) * 22.0, Color("ffd27a"), 4, 40.0, 120.0, 0.25, 3.0, ang, 0.5)


func tracer(a: Vector2, b: Vector2) -> void:
	tracers.append({"a": a, "b": b, "life": 0.15})


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.01)
	for i in range(parts.size() - 1, -1, -1):
		var p: Dictionary = parts[i]
		p["p"] += p["v"] * delta
		p["v"] *= 0.92
		p["life"] -= delta
		if p["life"] <= 0.0:
			parts.remove_at(i)
	for i in range(tracers.size() - 1, -1, -1):
		tracers[i]["life"] -= real
		if tracers[i]["life"] <= 0.0:
			tracers.remove_at(i)
	queue_redraw()


func _draw() -> void:
	for p in parts:
		var c: Color = p["c"]
		c.a *= clampf(p["life"] / p["max"], 0.0, 1.0)
		var s: float = p["s"]
		draw_rect(Rect2(p["p"] - Vector2(s, s) / 2.0, Vector2(s, s)), c)
	for t in tracers:
		draw_line(t["a"], t["b"], Color(1.0, 0.94, 0.7, t["life"] / 0.15), 2.0)
	var pl = Game.world.player if Game.world else null
	if pl:
		for m in pl.marks + pl.exec_q:
			if is_instance_valid(m) and not m.dead:
				Gfx.cross(self, m.global_position, 7.0, Color("e0261a"), 3.0)
