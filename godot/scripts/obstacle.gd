extends StaticBody2D
## Кактус или скала: препятствие для людей, коней и пуль.

var kind := "cactus"
var r := 12.0
var arms := 0
var rot := 0.0
var sh := 0.0


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = r
	cs.shape = c
	add_child(cs)


func _draw() -> void:
	if kind == "rock":
		Gfx.ell(self, Transform2D.IDENTITY, Vector2(6, 7), r, r * 0.8, Gfx.SHADOW)
		var pts := PackedVector2Array()
		for i in 8:
			var rr := r * (0.85 + 0.15 * sin(i * 2.3 + sh * 9.0))
			pts.append(Vector2.from_angle(i / 8.0 * TAU) * rr)
		draw_colored_polygon(pts, Color("8b7b6a") if sh > 0.5 else Color("7a6a5a"))
		Gfx.ell(self, Transform2D(-0.5, Vector2(-r * 0.25, -r * 0.3)), Vector2.ZERO, r * 0.45, r * 0.3, Color(1, 1, 1, 0.15))
	else:
		Gfx.ell(self, Transform2D.IDENTITY, Vector2(5, 6), r, r * 0.7, Gfx.SHADOW)
		var xf := Transform2D(rot, Vector2.ZERO)
		var green := Color("3f6b33")
		if arms > 0:
			Gfx.ell(self, xf, Vector2(r + 3, 0), 6, 5, green)
		if arms > 1:
			Gfx.ell(self, xf, Vector2(-r - 3, 0), 6, 5, green)
		Gfx.ell(self, xf, Vector2.ZERO, r, r, green)
		for i in 6:
			draw_line(Vector2.ZERO, Vector2.from_angle(i + rot) * r * 0.85, Color("5e8f4a"), 1.5)
		draw_circle(Vector2.ZERO, 2.0, Color("e8d070"))
